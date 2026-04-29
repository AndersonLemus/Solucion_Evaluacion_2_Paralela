#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <chrono>
#include <cuda_runtime.h>
#include <curand_kernel.h>
#include <stdint.h>

#define CUDA_CHECK(call)                                                        \
    do {                                                                        \
        cudaError_t err = (call);                                               \
        if (err != cudaSuccess) {                                               \
            fprintf(stderr, "Error CUDA en %s:%d — %s\n",                      \
                    __FILE__, __LINE__, cudaGetErrorString(err));               \
            exit(EXIT_FAILURE);                                                 \
        }                                                                       \
    } while (0)

__global__ void kernel_random_walk(long long* d_r2,
                                   long long  N,
                                   int        T,
                                   uint64_t   semilla){

    long long idx = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if(idx >= N) return;
    
    curandState estado;
    curand_init(semilla + (uint64_t)idx, 0, 0, &estado);

    int x = 0, y = 0;

    for(int t = 0; t < T; ++t){
        unsigned int r = curand(&estado);
        int direccion = (int)(r % 4); 
        
        switch(direccion){
            case 0: ++y; break;
            case 1: --y; break;
            case 2: --x; break;
            case 3: ++x; break;
        }
    }
    // Escribimos una sola vez al final (Optimización de memoria global)
    d_r2[idx] = (long long)x * x + (long long)y * y;
}

__global__ void kernel_reduccion(long long* d_datos,
                                 long long* d_parciales,
                                 long long  N)
{
    extern __shared__ long long s_datos[];

    long long idx = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    int tid = threadIdx.x;

    s_datos[tid] = (idx < N) ? d_datos[idx] : 0LL; 
    __syncthreads();

    // Reducción en árbol
    for(int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if(tid < stride){
            s_datos[tid] += s_datos[tid + stride];
        }
        __syncthreads();
    }

    if(tid == 0) {
        d_parciales[blockIdx.x] = s_datos[0];   
    }
}

int main(int argc, char* argv[]){ // Corregido argv[]

    if (argc < 3) {
        fprintf(stderr, "Uso: %s <N> <T> [hilos_por_bloque] [semilla]\n", argv[0]);
        return 1;
    }

    long long N               = atoll(argv[1]);
    int       T               = atoi(argv[2]); // Corregido atoi
    int       hilos_por_bloque = (argc >= 4) ? atoi(argv[3]) : 256;
    uint64_t  semilla         = (argc >= 5) ? (uint64_t)atoll(argv[4]) : 42ULL;

    long long num_bloques = (N + hilos_por_bloque - 1) / hilos_por_bloque; 
    
    long long* d_r2;
    long long* d_parciales;
    CUDA_CHECK(cudaMalloc(&d_r2, N * sizeof(long long)));
    CUDA_CHECK(cudaMalloc(&d_parciales, num_bloques * sizeof(long long)));

    // Declaración de eventos (Debe estar aquí)
    cudaEvent_t ev_inicio, ev_fin;
    CUDA_CHECK(cudaEventCreate(&ev_inicio));
    CUDA_CHECK(cudaEventCreate(&ev_fin));

    auto t_total_inicio = std::chrono::steady_clock::now(); 

    // Fase 1: Random Walk
    CUDA_CHECK(cudaEventRecord(ev_inicio));
    kernel_random_walk<<<num_bloques, hilos_por_bloque>>>(d_r2, N, T, semilla);
    CUDA_CHECK(cudaEventRecord(ev_fin));
    CUDA_CHECK(cudaEventSynchronize(ev_fin));

    float ms_kernel = 0.0f;
    CUDA_CHECK(cudaEventElapsedTime(&ms_kernel, ev_inicio, ev_fin)); 

    // Fase 2: Reducción
    size_t mem_compartida = hilos_por_bloque * sizeof(long long);
    CUDA_CHECK(cudaEventRecord(ev_inicio));
    kernel_reduccion<<<num_bloques, hilos_por_bloque, mem_compartida>>>(d_r2, d_parciales, N);
    CUDA_CHECK(cudaEventRecord(ev_fin));
    CUDA_CHECK(cudaEventSynchronize(ev_fin));

    float ms_reduccion = 0.0f;
    CUDA_CHECK(cudaEventElapsedTime(&ms_reduccion, ev_inicio, ev_fin));

    // Copiar resultados a CPU
    long long* h_parciales = (long long*)malloc(num_bloques * sizeof(long long));
    CUDA_CHECK(cudaMemcpy(h_parciales, d_parciales, num_bloques * sizeof(long long), cudaMemcpyDeviceToHost));

    long long suma_total = 0;
    for (long long b = 0; b < num_bloques; ++b) suma_total += h_parciales[b];

    auto t_total_fin = std::chrono::steady_clock::now(); // Consistencia con steady_clock
    double tiempo_total = std::chrono::duration<double>(t_total_fin - t_total_inicio).count();

    printf("=== Resultados ===\n");
    printf("  MSD calculado     : %.6f\n", (double)suma_total / N);
    printf("  Kernel walk       : %.3f ms\n", ms_kernel);
    printf("  Tiempo total      : %.6f s\n", tiempo_total);

    // Limpieza
    CUDA_CHECK(cudaFree(d_r2));
    CUDA_CHECK(cudaFree(d_parciales));
    free(h_parciales);
    CUDA_CHECK(cudaEventDestroy(ev_inicio));
    CUDA_CHECK(cudaEventDestroy(ev_fin));

    return 0;
}