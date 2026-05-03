#include <iostream>
#include <random>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iomanip>

inline long long simular_particula(int T, std::mt19937& rng, std::uniform_int_distribution<int>& dist){
    int x = 0, y = 0;

    for (int t = 0; t < T; ++t){
        switch (dist(rng)){
            case 0: ++y; break;   
            case 1: --y; break;   
            case 2: --x; break;   
            case 3: ++x; break;   
        }
    }

    return static_cast<long long>(x) * x + static_cast<long long>(y) * y;
}

int main(int argc, char* argv[]){

    if(argc < 3) {
        std::cerr << "Uso: " << argv[0] << " <N> <T> [semilla]\n";
        return 1;
    }

    const long long N = std::atoll(argv[1]);
    const int T = std::atoi(argv[2]);
    uint32_t seed = 42u;

    if (argc >= 4) {
        seed = static_cast<uint32_t>(std::strtoul(argv[3], nullptr, 10));
    }


    if (N <= 0 || T <= 0) {
        std::cerr << "Error N y T deben ser enteros positivos.\n";
        return 1;
    }

    std::cout << std::fixed << std::setprecision(6);
    
    // Para generar números pseudoaleatorios.
    std::mt19937 rng(seed);
    std::uniform_int_distribution<int> dist(0, 3);


    //Inicio de la simulacion.
    auto t_inicio = std::chrono::steady_clock::now();


    //Suma de partículas. (Sumatoria)
    long long suma_r2 = 0;
    for(long long i = 0; i < N; ++i){
        suma_r2 += simular_particula(T, rng, dist); 
    }

    auto t_fin = std::chrono::steady_clock::now();


    // Cálculo de métricas.
    double msd = static_cast<double>(suma_r2) / static_cast<double>(N);
    double error_relativo = std::abs(msd - static_cast<double>(T)) / static_cast<double>(T);
    double tiempo_seg = std::chrono::duration<double>(t_fin - t_inicio).count();

    // Impresión de resultados.

    std::cout << "=== Resultados secuencial ===\n";
    std::cout << "N: " << N << "\n";
    std::cout << "T: " << T << "\n";
    std::cout << "Semilla: " << seed << "\n";
    std::cout << "MSD calculado: " << msd << "\n"; 
    std::cout << "MSD teorico: " << T << "\n"; 
    std::cout << "Error relativo: " << error_relativo << "\n";
    std::cout << "Tiempo total: " << tiempo_seg << " s\n";

    return 0;
}



