SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -e -o pipefail -c

CXX ?= g++
NVCC ?= nvcc
CXXFLAGS ?= -O3 -std=c++17
NVCCFLAGS ?= -O3 -std=c++17
CUDA_ARCH ?= sm_86

T ?= 1000
REPETICIONES ?= 3
SEMILLA ?= 42
HILOS_BASE ?= 256
N_VALORES ?= 100000 1000000 10000000
HILOS_VALORES ?= 64 128 256 512 1024

SEC_SRC := secuencial/secuencial_monte_carlo.cpp
SEC_BIN := secuencial/secuencial_monte_carlo
CUDA_SRC := paralela_cuda/paralelismo_monte_carlo.cu
CUDA_BIN := paralela_cuda/paralelismo_monte_carlo

RESULT_DIR := analisis_resultados/resultados_3_3_1
TABLA_TIEMPOS := $(RESULT_DIR)/tabla_tiempos.csv
TABLA_BLOQUES := $(RESULT_DIR)/tabla_hilos_por_bloque.csv
RESUMEN_MD := $(RESULT_DIR)/resumen_3_3_1.md
GRAFICAS_SCRIPT := analisis_resultados/graficar_resultados_3_3_1.py

.PHONY: all secuencial cuda benchmark graficas clean help

all: secuencial cuda

secuencial: $(SEC_BIN)

$(SEC_BIN): $(SEC_SRC)
	$(CXX) $(CXXFLAGS) $< -o $@

cuda: $(CUDA_BIN)

$(CUDA_BIN): $(CUDA_SRC)
	if command -v $(NVCC) >/dev/null 2>&1; then
	    $(NVCC) $(NVCCFLAGS) -arch=$(CUDA_ARCH) $< -o $@
	else
	    echo "Advertencia: nvcc no esta disponible. No se compilo la version CUDA."
	fi

benchmark: all
	mkdir -p "$(RESULT_DIR)"
	echo "version,N,T,hilos_por_bloque,repeticiones,tiempo_prom_s,speedup,MSD_prom,error_rel_prom" > "$(TABLA_TIEMPOS)"
	echo "hilos_por_bloque,N,T,repeticiones,tiempo_prom_s,MSD_prom,error_rel_prom" > "$(TABLA_BLOQUES)"

	promedio() {
	    awk '{ suma += $$1; n += 1 } END { if (n > 0) printf "%.6f", suma / n; else printf "nan" }'
	}

	dividir() {
	    awk -v a="$$1" -v b="$$2" 'BEGIN { if (b > 0) printf "%.6f", a / b; else printf "nan" }'
	}

	extraer_valor() {
	    local etiqueta="$$1"
	    awk -F':' -v etiqueta="$$etiqueta" '
	        index($$1, etiqueta) > 0 {
	            gsub(/^[ \t]+|[ \t]+$$/, "", $$2)
	            split($$2, partes, " ")
	            print partes[1]
	            exit
	        }
	    '
	}

	ejecutar_programa() {
	    local version="$$1"
	    local n="$$2"
	    local hilos="$${3:-}"
	    local tiempos=()
	    local msds=()
	    local errores=()
	    local salida
	    local tiempo
	    local msd
	    local error

	    for ((rep = 1; rep <= $(REPETICIONES); rep++)); do
	        echo "  [$$version] N=$$n T=$(T) rep=$$rep/$(REPETICIONES)" >&2
	        if [[ "$$version" == "Secuencial" ]]; then
	            salida="$$("$(SEC_BIN)" "$$n" "$(T)" "$(SEMILLA)" 2>&1)"
	        else
	            salida="$$("$(CUDA_BIN)" "$$n" "$(T)" "$$hilos" "$(SEMILLA)" 2>&1)"
	        fi

	        if [[ $$? -ne 0 ]]; then
	            echo "  Error ejecutando $$version con N=$$n" >&2
	            echo "$$salida" >&2
	            return 1
	        fi

	        tiempo="$$(printf "%s\n" "$$salida" | extraer_valor "Tiempo total")"
	        msd="$$(printf "%s\n" "$$salida" | extraer_valor "MSD calculado")"
	        error="$$(printf "%s\n" "$$salida" | extraer_valor "Error relativo")"

	        tiempos+=("$$tiempo")
	        msds+=("$$msd")
	        errores+=("$$error")
	    done

	    local tiempo_prom
	    local msd_prom
	    local error_prom
	    tiempo_prom="$$(printf "%s\n" "$${tiempos[@]}" | promedio)"
	    msd_prom="$$(printf "%s\n" "$${msds[@]}" | promedio)"
	    error_prom="$$(printf "%s\n" "$${errores[@]}" | promedio)"
	    printf "%s,%s,%s,%s\n" "$$tiempo_prom" "$$msd_prom" "$$error_prom" "$$hilos"
	}

	declare -A tiempos_secuenciales

	echo
	echo "=== Tabla principal: Secuencial vs CUDA ==="
	for n in $(N_VALORES); do
	    if resultado="$$(ejecutar_programa "Secuencial" "$$n")"; then
	        IFS=',' read -r tiempo msd error _ <<< "$$resultado"
	        tiempos_secuenciales["$$n"]="$$tiempo"
	        echo "Secuencial,$$n,$(T),,$(REPETICIONES),$$tiempo,,$$msd,$$error" >> "$(TABLA_TIEMPOS)"
	    else
	        echo "Secuencial,$$n,$(T),,$(REPETICIONES),ERROR,,ERROR,ERROR" >> "$(TABLA_TIEMPOS)"
	    fi
	done

	if [[ -x "$(CUDA_BIN)" ]]; then
	    for n in $(N_VALORES); do
	        if resultado="$$(ejecutar_programa "CUDA" "$$n" "$(HILOS_BASE)")"; then
	            IFS=',' read -r tiempo msd error hilos <<< "$$resultado"
	            speedup="$$(dividir "$${tiempos_secuenciales[$$n]:-0}" "$$tiempo")"
	            echo "CUDA,$$n,$(T),$$hilos,$(REPETICIONES),$$tiempo,$$speedup,$$msd,$$error" >> "$(TABLA_TIEMPOS)"
	        else
	            echo "CUDA,$$n,$(T),$(HILOS_BASE),$(REPETICIONES),ERROR,ERROR,ERROR,ERROR" >> "$(TABLA_TIEMPOS)"
	        fi
	    done

	    echo
	    echo "=== Exploracion de hilos por bloque con N=1000000 ==="
	    for hilos in $(HILOS_VALORES); do
	        if resultado="$$(ejecutar_programa "CUDA" "1000000" "$$hilos")"; then
	            IFS=',' read -r tiempo msd error _ <<< "$$resultado"
	            echo "$$hilos,1000000,$(T),$(REPETICIONES),$$tiempo,$$msd,$$error" >> "$(TABLA_BLOQUES)"
	        else
	            echo "$$hilos,1000000,$(T),$(REPETICIONES),ERROR,ERROR,ERROR" >> "$(TABLA_BLOQUES)"
	        fi
	    done
	fi

	{
	    echo "# Resultados 3.3.1"
	    echo
	    echo "- T: $(T)"
	    echo "- Repeticiones por caso: $(REPETICIONES)"
	    echo "- Semilla: $(SEMILLA)"
	    echo "- Hilos base CUDA: $(HILOS_BASE)"
	    echo
	    echo "## Tabla de tiempos"
	    echo
	    echo '| Version | N | T | Hilos/bloque | Tiempo prom. (s) | Speedup | MSD prom. | Error rel. prom. |'
	    echo '|---|---:|---:|---:|---:|---:|---:|---:|'
	    awk -F',' 'NR > 1 {
	        hilos = ($$4 == "" ? "-" : $$4)
	        speedup = ($$7 == "" ? "-" : $$7)
	        printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n", $$1, $$2, $$3, hilos, $$6, speedup, $$8, $$9
	    }' "$(TABLA_TIEMPOS)"
	    echo
	    echo "## Hilos por bloque"
	    echo
	    echo '| Hilos/bloque | N | T | Tiempo prom. (s) | MSD prom. | Error rel. prom. |'
	    echo '|---:|---:|---:|---:|---:|---:|'
	    awk -F',' 'NR > 1 {
	        printf "| %s | %s | %s | %s | %s | %s |\n", $$1, $$2, $$3, $$5, $$6, $$7
	    }' "$(TABLA_BLOQUES)"
	} > "$(RESUMEN_MD)"

	echo
	echo "Resultados guardados en:"
	echo "  $(TABLA_TIEMPOS)"
	echo "  $(TABLA_BLOQUES)"
	echo "  $(RESUMEN_MD)"

graficas:
	python3 "$(GRAFICAS_SCRIPT)"

clean:
	rm -f "$(SEC_BIN)" "$(CUDA_BIN)"

help:
	@echo "Targets disponibles:"
	@echo "  make all        Compila secuencial y CUDA"
	@echo "  make secuencial Compila solo la version secuencial"
	@echo "  make cuda       Compila solo la version CUDA"
	@echo "  make benchmark  Genera tablas de la seccion 3.3.1"
	@echo "  make graficas   Genera graficas desde las tablas CSV"
	@echo "  make clean      Elimina ejecutables generados"
	@echo
	@echo "Variables utiles:"
	@echo "  CUDA_ARCH=sm_86 T=1000 REPETICIONES=3 SEMILLA=42 HILOS_BASE=256"
