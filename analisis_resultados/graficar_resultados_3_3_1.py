#!/usr/bin/env python3
import argparse
import csv
import os
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-codex")

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def leer_csv(ruta):
    with ruta.open(newline="", encoding="utf-8") as archivo:
        return list(csv.DictReader(archivo))


def numero(valor):
    if valor is None or valor == "" or valor.upper() == "ERROR":
        return None
    return float(valor)


def entero(valor):
    dato = numero(valor)
    return None if dato is None else int(dato)


def guardar(figura, ruta):
    ruta.parent.mkdir(parents=True, exist_ok=True)
    figura.tight_layout()
    figura.savefig(ruta, dpi=180)
    plt.close(figura)
    print(f"Grafica guardada: {ruta}")


def filtrar_validos(filas, version):
    datos = []
    for fila in filas:
        if fila["version"] != version:
            continue
        n = entero(fila["N"])
        tiempo = numero(fila["tiempo_prom_s"])
        msd = numero(fila["MSD_prom"])
        error = numero(fila["error_rel_prom"])
        speedup = numero(fila.get("speedup"))
        if n is not None and tiempo is not None:
            datos.append({
                "N": n,
                "tiempo": tiempo,
                "speedup": speedup,
                "MSD": msd,
                "error": error,
            })
    return sorted(datos, key=lambda item: item["N"])


def grafica_tiempo_vs_n(filas, salida):
    sec = filtrar_validos(filas, "Secuencial")
    cuda = filtrar_validos(filas, "CUDA")

    fig, ax = plt.subplots(figsize=(8, 5))
    if sec:
        ax.plot([d["N"] for d in sec], [d["tiempo"] for d in sec],
                marker="o", linewidth=2, label="Secuencial")
    if cuda:
        ax.plot([d["N"] for d in cuda], [d["tiempo"] for d in cuda],
                marker="s", linewidth=2, label="CUDA")

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("Numero de particulas (N)")
    ax.set_ylabel("Tiempo promedio (s)")
    ax.set_title("Tiempo de ejecucion vs N")
    ax.grid(True, which="both", linestyle=":", linewidth=0.8)
    ax.legend()
    guardar(fig, salida / "tiempo_vs_n.png")


def grafica_speedup_vs_n(filas, salida, amdahl_f):
    cuda = [d for d in filtrar_validos(filas, "CUDA") if d["speedup"] is not None]
    if not cuda:
        print("No hay datos CUDA validos para graficar speedup.")
        return

    ns = [d["N"] for d in cuda]
    speedups = [d["speedup"] for d in cuda]

    if amdahl_f is None:
        amdahl_f = 1.0 / max(speedups)

    amdahl_max = 1.0 / amdahl_f if amdahl_f > 0 else max(speedups)
    amdahl_pred = [amdahl_max for _ in ns]

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot(ns, speedups, marker="o", linewidth=2, label="Speedup observado")
    ax.plot(ns, amdahl_pred, linestyle="--", linewidth=2,
            label=f"Amdahl estimado: f={amdahl_f:.5f}, Smax={amdahl_max:.1f}")

    ax.set_xscale("log")
    ax.set_xlabel("Numero de particulas (N)")
    ax.set_ylabel("Speedup")
    ax.set_title("Speedup vs N")
    ax.grid(True, which="both", linestyle=":", linewidth=0.8)
    ax.legend()
    guardar(fig, salida / "speedup_vs_n_amdahl.png")


def grafica_tiempo_vs_hilos(filas, salida):
    datos = []
    for fila in filas:
        hilos = entero(fila["hilos_por_bloque"])
        tiempo = numero(fila["tiempo_prom_s"])
        if hilos is not None and tiempo is not None:
            datos.append((hilos, tiempo))

    if not datos:
        print("No hay datos validos para graficar tiempo vs hilos por bloque.")
        return

    datos.sort()
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot([d[0] for d in datos], [d[1] for d in datos], marker="o", linewidth=2)
    ax.set_xlabel("Hilos por bloque")
    ax.set_ylabel("Tiempo promedio CUDA (s)")
    ax.set_title("Tiempo de ejecucion vs hilos por bloque")
    ax.grid(True, linestyle=":", linewidth=0.8)
    ax.set_xticks([d[0] for d in datos])
    guardar(fig, salida / "tiempo_vs_hilos_bloque.png")


def simular_msd_temporal(n, t, semilla):
    rng = np.random.default_rng(semilla)
    x = np.zeros(n, dtype=np.int32)
    y = np.zeros(n, dtype=np.int32)
    msd = np.empty(t + 1, dtype=np.float64)
    msd[0] = 0.0

    for paso in range(1, t + 1):
        direccion = rng.integers(0, 4, size=n, dtype=np.int8)
        y += direccion == 0
        y -= direccion == 1
        x -= direccion == 2
        x += direccion == 3
        msd[paso] = np.mean(x.astype(np.int64) * x + y.astype(np.int64) * y)

    return np.arange(t + 1), msd


def grafica_msd_temporal(t, n, semilla, salida):
    pasos, msd = simular_msd_temporal(n, t, semilla)
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot(pasos, msd, linewidth=2, label=f"MSD simulado (N={n})")
    ax.plot(pasos, pasos, linestyle="--", linewidth=2, label="Teorico: MSD = t")
    ax.set_xlabel("Paso de tiempo (t)")
    ax.set_ylabel("MSD")
    ax.set_title("MSD vs paso de tiempo")
    ax.grid(True, linestyle=":", linewidth=0.8)
    ax.legend()
    guardar(fig, salida / "msd_vs_paso_tiempo.png")


def escribir_indice(salida, archivos, msd_n, msd_t, amdahl_f):
    ruta = salida / "indice_graficas.md"
    with ruta.open("w", encoding="utf-8") as archivo:
        archivo.write("# Graficas generadas\n\n")
        archivo.write(f"- MSD temporal simulado con N = {msd_n}, T = {msd_t}.\n")
        if amdahl_f is None:
            archivo.write("- Fraccion serie de Amdahl estimada como 1 / max(speedup observado).\n\n")
        else:
            archivo.write(f"- Fraccion serie de Amdahl indicada por usuario: f = {amdahl_f}.\n\n")
        for nombre in archivos:
            archivo.write(f"- `{nombre}`\n")
    print(f"Indice guardado: {ruta}")


def main():
    base = Path(__file__).resolve().parent
    resultados = base / "resultados_3_3_1"

    parser = argparse.ArgumentParser(
        description="Genera las graficas solicitadas para la seccion 3.3.1 del taller."
    )
    parser.add_argument("--resultados", type=Path, default=resultados,
                        help="Carpeta con tabla_tiempos.csv y tabla_hilos_por_bloque.csv.")
    parser.add_argument("--salida", type=Path, default=None,
                        help="Carpeta donde se guardan las graficas.")
    parser.add_argument("--msd-n", type=int, default=20000,
                        help="Particulas usadas para simular la curva MSD temporal.")
    parser.add_argument("--msd-t", type=int, default=None,
                        help="Pasos para la curva MSD temporal. Por defecto usa T del CSV.")
    parser.add_argument("--semilla", type=int, default=42,
                        help="Semilla para la curva MSD temporal.")
    parser.add_argument("--amdahl-f", type=float, default=None,
                        help="Fraccion serie f para la prediccion de Amdahl.")
    args = parser.parse_args()

    tabla_tiempos = args.resultados / "tabla_tiempos.csv"
    tabla_hilos = args.resultados / "tabla_hilos_por_bloque.csv"
    salida = args.salida or (args.resultados / "graficas")

    if not tabla_tiempos.exists():
        raise FileNotFoundError(f"No existe {tabla_tiempos}")
    if not tabla_hilos.exists():
        raise FileNotFoundError(f"No existe {tabla_hilos}")

    tiempos = leer_csv(tabla_tiempos)
    hilos = leer_csv(tabla_hilos)

    valores_t = [entero(fila["T"]) for fila in tiempos if entero(fila["T"]) is not None]
    msd_t = args.msd_t or (valores_t[0] if valores_t else 1000)

    grafica_tiempo_vs_n(tiempos, salida)
    grafica_speedup_vs_n(tiempos, salida, args.amdahl_f)
    grafica_tiempo_vs_hilos(hilos, salida)
    grafica_msd_temporal(msd_t, args.msd_n, args.semilla, salida)

    escribir_indice(
        salida,
        [
            "tiempo_vs_n.png",
            "speedup_vs_n_amdahl.png",
            "tiempo_vs_hilos_bloque.png",
            "msd_vs_paso_tiempo.png",
        ],
        args.msd_n,
        msd_t,
        args.amdahl_f,
    )


if __name__ == "__main__":
    main()
