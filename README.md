# Simulacion Monte Carlo de difusion 2D

Este proyecto implementa una caminata aleatoria en una grilla 2D para estudiar la difusion de
particulas. Todas las particulas empiezan en `(0, 0)` y, en cada paso de tiempo, se mueven una
celda hacia arriba, abajo, izquierda o derecha con igual probabilidad.

La metrica principal es el desplazamiento cuadratico medio:

```text
MSD = promedio(x_i^2 + y_i^2)
```

Para una caminata aleatoria 2D de `T` pasos, el valor esperado teorico es:

```text
MSD ~= T
```

Por eso el programa tambien reporta el error relativo:

```text
error_relativo = |MSD - T| / T
```

## Organizacion

```text
introduccion_computacion_paralela/
├── README.md
├── Makefile
├── secuencial/
│   ├── secuencial_monte_carlo.cpp
│   └── secuencial_monte_carlo        # generado al compilar
├── paralela_cuda/
│   ├── paralelismo_monte_carlo.cu
│   └── paralelismo_monte_carlo       # generado al compilar
└── analisis_resultados/
    ├── graficar_resultados_3_3_1.py
    └── resultados_3_3_1/
```

- `secuencial/`: version secuencial en C++17.
- `paralela_cuda/`: version paralela en CUDA.
- `analisis_resultados/`: scripts, tablas y graficas para el informe.

## Requisitos

Para la version secuencial:

- Compilador C++ con soporte para C++17, por ejemplo `g++`.

Para la version CUDA:

- NVIDIA CUDA Toolkit, incluyendo `nvcc`.
- Una GPU NVIDIA compatible con CUDA.

## Compilacion con Makefile

Desde esta carpeta:

```bash
cd introduccion_computacion_paralela
```

Compilar ambas versiones:

```bash
make all
```

Compilar solo la version secuencial:

```bash
make secuencial
```

Compilar solo la version CUDA:

```bash
make cuda
```

En una RTX 3050 se usa `sm_86`. Si aparece el error `the provided PTX was compiled with an
unsupported toolchain`, normalmente hay una diferencia entre la version de `nvcc` y la version
soportada por el driver. Compilar con `-arch=sm_86` genera codigo nativo para la GPU y evita que
el driver tenga que compilar PTX en tiempo de ejecucion.

Para usar otra arquitectura CUDA:

```bash
make cuda CUDA_ARCH=sm_75
```

## Ejecucion

### Version secuencial

Formato:

```bash
./secuencial/secuencial_monte_carlo <N> <T> [semilla]
```

Ejemplo:

```bash
./secuencial/secuencial_monte_carlo 1000000 1000 42
```

Parametros:

- `N`: numero de particulas.
- `T`: numero de pasos de tiempo.
- `semilla`: valor opcional para reproducibilidad. Si no se indica, se usa `42`.

### Version CUDA

Formato:

```bash
./paralela_cuda/paralelismo_monte_carlo <N> <T> [hilos_por_bloque] [semilla]
```

Ejemplo:

```bash
./paralela_cuda/paralelismo_monte_carlo 1000000 1000 256 42
```

Parametros:

- `N`: numero de particulas.
- `T`: numero de pasos de tiempo.
- `hilos_por_bloque`: tamano del bloque CUDA. Si no se indica, se usa `256`.
- `semilla`: valor opcional para reproducibilidad. Si no se indica, se usa `42`.

Valores recomendados para `hilos_por_bloque`:

```text
64, 128, 256, 512, 1024
```

El programa valida que `hilos_por_bloque` sea potencia de 2 porque la reduccion en GPU usa una
suma en arbol que depende de esa condicion.

## Logica de la solucion

### Version secuencial

La version secuencial usa `std::mt19937` como generador pseudoaleatorio. Para cada particula:

1. Inicializa su posicion en `(0, 0)`.
2. Ejecuta `T` movimientos aleatorios.
3. Calcula `r2 = x^2 + y^2`.
4. Acumula ese valor en una suma total.

Al final se calcula:

```text
MSD = suma_total / N
```

Esta version sirve como referencia de correctitud y rendimiento base.

### Version CUDA

La version CUDA asigna un hilo a cada particula. Cada hilo:

1. Calcula su indice global.
2. Inicializa su propio estado de cuRAND usando una semilla derivada de su indice.
3. Simula localmente los `T` pasos de su particula.
4. Guarda en memoria global su valor final `r2 = x^2 + y^2`.

Despues se ejecuta un kernel de reduccion. Este kernel suma los valores `r2` por bloques usando
memoria compartida. Cada bloque produce una suma parcial, y esas sumas parciales se copian a CPU
para hacer la suma final.

Esta estrategia evita copiar todos los `N` valores a CPU. En lugar de eso, solo se copian las
sumas parciales, reduciendo el costo de transferencia entre GPU y CPU.

## Salida esperada

Ambos programas reportan:

- `N`
- `T`
- semilla usada
- `MSD calculado`
- `MSD teorico`
- `Error relativo`
- tiempo de ejecucion

La version CUDA tambien reporta:

- hilos por bloque
- numero de bloques
- tiempo del kernel de caminata aleatoria
- tiempo del kernel de reduccion

Para `N = 1000000` y `T = 1000`, el `MSD calculado` deberia estar cerca de `1000`. Un error
relativo menor al `1%` es esperable.

## Pruebas sugeridas

Para comparar rendimiento con `T = 1000`:

```bash
./secuencial/secuencial_monte_carlo 100000 1000 42
./secuencial/secuencial_monte_carlo 1000000 1000 42
./secuencial/secuencial_monte_carlo 10000000 1000 42
```

```bash
./paralela_cuda/paralelismo_monte_carlo 100000 1000 256 42
./paralela_cuda/paralelismo_monte_carlo 1000000 1000 256 42
./paralela_cuda/paralelismo_monte_carlo 10000000 1000 256 42
```

Para explorar el efecto del tamano de bloque con `N = 1000000`:

```bash
./paralela_cuda/paralelismo_monte_carlo 1000000 1000 64 42
./paralela_cuda/paralelismo_monte_carlo 1000000 1000 128 42
./paralela_cuda/paralelismo_monte_carlo 1000000 1000 256 42
./paralela_cuda/paralelismo_monte_carlo 1000000 1000 512 42
./paralela_cuda/paralelismo_monte_carlo 1000000 1000 1024 42
```

## Analisis para la seccion 3.3.1

El `Makefile` automatiza las mediciones pedidas en la tabla de tiempos del taller. Compila los
programas, ejecuta varias repeticiones, calcula promedios y genera archivos con los resultados.

Uso recomendado para el taller:

```bash
make benchmark T=1000 REPETICIONES=3 SEMILLA=42 HILOS_BASE=256
```

Variables:

- `1000`: numero de pasos `T`.
- `3`: numero de repeticiones por caso.
- `42`: semilla.
- `256`: hilos por bloque para la comparacion principal CUDA vs secuencial.

El target `benchmark` evalua:

- `N = 100000`, `1000000`, `10000000` para secuencial y CUDA.
- `hilos_por_bloque = 64`, `128`, `256`, `512`, `1024` con `N = 1000000`.

Los resultados quedan en:

```text
analisis_resultados/resultados_3_3_1/tabla_tiempos.csv
analisis_resultados/resultados_3_3_1/tabla_hilos_por_bloque.csv
analisis_resultados/resultados_3_3_1/resumen_3_3_1.md
```

Para hacer una prueba rapida sin ejecutar los tamanos grandes:

```bash
make benchmark T=100 REPETICIONES=1 N_VALORES="1000 10000" HILOS_VALORES="128 256"
```

Por defecto el Makefile compila CUDA con `CUDA_ARCH=sm_86`, adecuado para RTX 3050. Para otra GPU,
se puede cambiar asi:

```bash
make benchmark CUDA_ARCH=sm_75 T=1000 REPETICIONES=3 SEMILLA=42 HILOS_BASE=256
```

## Graficas del informe

Despues de ejecutar `make benchmark`, se pueden generar las graficas solicitadas en el enunciado
con:

```bash
make graficas
```

El script lee:

```text
analisis_resultados/resultados_3_3_1/tabla_tiempos.csv
analisis_resultados/resultados_3_3_1/tabla_hilos_por_bloque.csv
```

Y genera:

```text
analisis_resultados/resultados_3_3_1/graficas/tiempo_vs_n.png
analisis_resultados/resultados_3_3_1/graficas/speedup_vs_n_amdahl.png
analisis_resultados/resultados_3_3_1/graficas/tiempo_vs_hilos_bloque.png
analisis_resultados/resultados_3_3_1/graficas/msd_vs_paso_tiempo.png
analisis_resultados/resultados_3_3_1/graficas/indice_graficas.md
```

La grafica `msd_vs_paso_tiempo.png` se genera con una simulacion representativa en Python,
porque los ejecutables C++/CUDA actuales reportan el MSD final, no el MSD de cada paso.

Opciones utiles:

```bash
./analisis_resultados/graficar_resultados_3_3_1.py --msd-n 50000 --semilla 42
./analisis_resultados/graficar_resultados_3_3_1.py --amdahl-f 0.0017
```
