#!/usr/bin/env python3
"""
Mide Tcode contra C escrito a mano, y al compilador contra si mismo.

Para cada caso compila tres binarios:

  C            el equivalente en C, sin comprobaciones
  Tcode        lo que escribe `tcodec`
  Tcode*       el mismo C generado, con las comprobaciones anuladas a mano

La tercera columna no es un modo del lenguaje: es solo para aislar cuanto
cuestan las comprobaciones sobre codigo por lo demas identico.

Los segundos dependen de la maquina; las razones no tanto. Por eso los
limites de `bench/limites.json` son razones: Tcode / C en cada caso, y lo
que tarda `tcodec` en escribir su propio C contra el compilador de
referencia (`REFERENCIA_C`, `bench/referencia/tcodec.c`, construido en la
misma maquina y en la misma pasada). `medir()` devuelve esa razon en
`"compilador"` y `T_REF` guarda el tiempo de la referencia.

    python3 bench/medir.py              las tablas
    python3 bench/medir.py --comprobar  falla si algo pasa de su limite
    python3 bench/medir.py --fijar      pone los limites: lo medido, con margen
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNTIME = os.path.join(RAIZ, "runtime")
BENCH = os.path.join(RAIZ, "bench")
LIMITES = os.path.join(BENCH, "limites.json")
# El compilador de referencia: la semilla fijada aqui, construida en la misma
# maquina, para medir el compilador de hoy contra algo comparable.
REFERENCIA_C = os.path.join(BENCH, "referencia", "tcodec.c")
TCODEC = os.path.join(RAIZ, "tcodec")
ENTORNO = dict(os.environ, TCODE_RAIZ=RAIZ)

# Lo que tardo el compilador de referencia en esta pasada; `None` si no se pudo.
T_REF = None

REPS = 5
# Cuanto por encima de lo medido se deja el limite con `--fijar`.
MARGEN = 1.25
NIVELES = ("2", "3")


def sin_comprobaciones(codigo):
    """El mismo C con las comprobaciones quitadas, para medir lo que cuestan.

    Las funciones de aritmetica las genera un macro por cada ancho que el
    programa usa, asi que no estan escritas en el C: lo que se cambia es
    quien decide si hubo desborde, que pasa a decir siempre que no. Todo lo
    demas —los tipos, las llamadas, el codigo del programa— queda igual, que
    es lo que hace que la comparacion signifique algo.
    """
    anular = "\n".join(
        f"#undef SS_LANG_DESB_{op}_U\n"
        f"#define SS_LANG_DESB_{op}_U(a, b, r, tmax) (*(r) = (a) {simbolo} (b), 0)\n"
        f"#undef SS_LANG_DESB_{op}_I\n"
        f"#define SS_LANG_DESB_{op}_I(a, b, r, tmax, tmin) "
        f"(*(r) = (a) {simbolo} (b), 0)"
        for op, simbolo in (("SUMA", "+"), ("RESTA", "-"), ("MUL", "*")))

    ancla = "#define SS_LANG_ARIT_U("
    assert ancla in codigo, "no encuentro donde anular la aritmetica comprobada"
    codigo = codigo.replace(ancla, anular + "\n\n" + ancla, 1)

    codigo, n = re.subn(
        r"    if \(SS_LANG_RARO\(i >= n\)\)\n    \{(?:.*\n)*?    \}\n", "", codigo)
    assert n == 1, "no pude anular la comprobacion de indice"
    return codigo


def c_de(fuente_t):
    r = subprocess.run([TCODEC, fuente_t, "--mostrar-c"], capture_output=True,
                       text=True, env=ENTORNO)
    if r.returncode != 0:
        raise SystemExit(f"{fuente_t}:\n{r.stderr}")
    return r.stdout


def compilar_c(fuente_c, destino, tmp, nivel="2"):
    ruta = os.path.join(tmp, os.path.basename(destino) + ".c")
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(fuente_c)
    r = subprocess.run(
        ["cc", "-std=c17", f"-O{nivel}", f"-I{RUNTIME}", ruta,
         os.path.join(RUNTIME, "safestr.c"), "-o", destino, "-lm"],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"no compila {destino}:\n{r.stderr}")


def cronometrar(orden, **kw):
    """El mejor de `REPS`: lo demas es ruido de la maquina."""
    mejor = float("inf")
    salida = None
    for _ in range(REPS):
        t0 = time.perf_counter()
        r = subprocess.run(orden, capture_output=True, text=True, **kw)
        mejor = min(mejor, time.perf_counter() - t0)
        salida = r.stdout
    return mejor, salida


def medir(tmp):
    """{"O2": {caso: razon}, "O3": {...}, "compilador": veces el de
    referencia}, y las filas para las tablas."""
    casos = sorted(f[:-2] for f in os.listdir(BENCH) if f.endswith(".t"))
    razones = {}
    filas = {}
    for nivel in NIVELES:
        razones[f"O{nivel}"] = {}
        filas[nivel] = []
        for caso in casos:
            fuente_t = os.path.join(BENCH, caso + ".t")
            fuente_c = os.path.join(BENCH, caso + ".c")
            codigo = c_de(fuente_t)
            compilar_c(codigo, os.path.join(tmp, caso + "_tc"), tmp, nivel)
            compilar_c(sin_comprobaciones(codigo),
                       os.path.join(tmp, caso + "_sc"), tmp, nivel)
            t_tc, s_tc = cronometrar([os.path.join(tmp, caso + "_tc")])
            t_sc, _ = cronometrar([os.path.join(tmp, caso + "_sc")])
            t_c = None
            if os.path.exists(fuente_c):
                with open(fuente_c, encoding="utf-8") as f:
                    compilar_c(f.read(), os.path.join(tmp, caso + "_c"), tmp, nivel)
                t_c, s_c = cronometrar([os.path.join(tmp, caso + "_c")])
                if s_c.strip() != s_tc.strip():
                    raise SystemExit(f"{caso}: C y Tcode dan resultados distintos "
                                     f"({s_c.strip()!r} contra {s_tc.strip()!r})")
                razones[f"O{nivel}"][caso] = round(t_tc / t_c, 3)
            filas[nivel].append((caso, t_c, t_tc, t_sc))

    # El compilador: `tcodec` escribiendo su propio C, contra el compilador de
    # referencia construido aqui mismo. Antes se dividia por el C de
    # `aritmetica`, que dura ~0,15 s: eso es ruido, y el numero que salia no era
    # el mismo en dos maquinas, asi que el limite no significaba lo mismo en el
    # CI que en local. La razon contra un compilador de la misma maquina si es
    # comparable.
    global T_REF
    T_REF = None
    fuente = os.path.join("ejemplos", "compilador", "tcodec.t")
    t_comp, _ = cronometrar([TCODEC, fuente, "--mostrar-c"], cwd=RAIZ, env=ENTORNO)
    razones["compilador"] = None
    if os.path.exists(REFERENCIA_C):
        ref = os.path.join(tmp, "tcodec_ref")
        # Las mismas piezas con las que el Makefile construye su semilla: el C
        # de la referencia no se basta solo, necesita el runtime, el sistema y
        # los dos acompanantes de `std/`.
        r = subprocess.run([os.environ.get("CC", "cc"), "-std=c17", "-O1",
                            "-Iruntime", REFERENCIA_C,
                            "runtime/safestr.c",
                            "ejemplos/compilador/lib/sistema_tcodec.c",
                            "std/proceso.c", "std/terminal.c",
                            "-o", ref, "-lm"],
                           capture_output=True, text=True, cwd=RAIZ)
        if r.returncode == 0:
            t_ref, _ = cronometrar([ref, fuente, "--mostrar-c"], cwd=RAIZ,
                                   env=ENTORNO)
            T_REF = t_ref
            razones["compilador"] = round(t_comp / t_ref, 3)
        else:
            print("  AVISO: no se pudo construir el compilador de referencia:\n"
                  + r.stderr.strip()[:400])
    return razones, filas, t_comp


def imprimir(filas, razones, t_comp):
    for nivel, lista in filas.items():
        print(f"\n--- compilado con -O{nivel} ---")
        print(f"{'caso':<24} {'C a mano':>10} {'Tcode':>10} "
              f"{'Tcode*':>10} {'Tcode / C':>11}")
        print("-" * 69)
        for caso, t_c, t_tc, t_sc in lista:
            c = f"{t_c:.3f}s" if t_c else "-"
            r = f"{t_tc / t_c:.2f}x" if t_c else "-"
            print(f"{caso:<24} {c:>10} {t_tc:>9.3f}s {t_sc:>9.3f}s {r:>11}")
    if T_REF:
        print(f"\ntcodec escribe su propio C en {t_comp:.2f}s "
              f"({razones['compilador']}x el compilador de referencia, "
              f"que tarda {T_REF:.2f}s)")
    else:
        print(f"\ntcodec escribe su propio C en {t_comp:.2f}s "
              f"(sin compilador de referencia: no se mide la razon)")


def comprobar(razones):
    with open(LIMITES, encoding="utf-8") as f:
        limites = json.load(f)
    fallas = []
    for nivel, por_caso in limites.items():
        if nivel == "compilador":
            if razones["compilador"] is None:
                print("  AVISO: sin compilador de referencia, no se comprueba "
                      "la razon del compilador")
            elif razones["compilador"] > por_caso:
                fallas.append(f"tcodec: {razones['compilador']}x el de "
                              f"referencia, limite {por_caso}x")
            continue
        for caso, limite in por_caso.items():
            medido = razones.get(nivel, {}).get(caso)
            if medido is None:
                fallas.append(f"{caso} -{nivel}: no se midio")
            elif medido > limite:
                fallas.append(f"{caso} -{nivel}: {medido}x, limite {limite}x")
    for f in fallas:
        print(f"  FALLA: {f}")
    print(f"{'ninguna medida' if not fallas else len(fallas)} por encima de su limite")
    return 1 if fallas else 0


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--comprobar", action="store_true")
    p.add_argument("--fijar", action="store_true")
    a = p.parse_args()
    if not os.path.exists(TCODEC):
        raise SystemExit("falta ./tcodec: `make` primero")
    tmp = tempfile.mkdtemp(prefix="tcode-bench-")
    try:
        razones, filas, t_comp = medir(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    imprimir(filas, razones, t_comp)
    if a.fijar:
        limites = {k: ({c: round(r * MARGEN, 2) for c, r in v.items()}
                       if isinstance(v, dict)
                       else (round(v * MARGEN, 2) if v else None))
                   for k, v in razones.items()}
        with open(LIMITES, "w", encoding="utf-8") as f:
            json.dump(limites, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"\nlimites escritos en {os.path.relpath(LIMITES, RAIZ)}")
        return 0
    if a.comprobar:
        return comprobar(razones)
    return 0


if __name__ == "__main__":
    sys.exit(main())
