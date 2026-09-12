#!/usr/bin/env python3
"""
Mide Tcode contra C escrito a mano.

Para cada caso compila tres binarios:

  C            el equivalente en C, sin comprobaciones
  Tcode        lo que produce el compilador
  Tcode*       el mismo C generado, con las comprobaciones anuladas a mano

La tercera columna no es un modo del lenguaje: es solo para aislar cuanto
cuestan las comprobaciones sobre codigo por lo demas identico.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)
RUNTIME = os.path.join(RAIZ, "runtime")
BENCH = os.path.join(RAIZ, "bench")

from tcode.cli import compilar_archivo

REPS = 5


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


NIVELES = ("2", "3")


def compilar_c(fuente_c, destino, tmp, nivel="2"):
    ruta = os.path.join(tmp, os.path.basename(destino) + ".c")
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(fuente_c)
    r = subprocess.run(
        ["cc", "-std=c17", f"-O{nivel}", f"-I{RUNTIME}", ruta,
         os.path.join(RUNTIME, "safestr.c"), "-o", destino],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"no compila {destino}:\n{r.stderr}")


def cronometrar(binario):
    mejor = float("inf")
    salida = None
    for _ in range(REPS):
        t0 = time.perf_counter()
        r = subprocess.run([binario], capture_output=True, text=True)
        mejor = min(mejor, time.perf_counter() - t0)
        salida = r.stdout
    return mejor, salida


def main():
    casos = sorted(f[:-2] for f in os.listdir(BENCH) if f.endswith(".t"))
    tmp = tempfile.mkdtemp(prefix="tcode-bench-")
    try:
        for nivel in NIVELES:
            print(f"\n--- compilado con -O{nivel} ---")
            print(f"{'caso':<24} {'C a mano':>10} {'Tcode':>10} "
                  f"{'Tcode*':>10} {'Tcode / C':>11}")
            print("-" * 69)
            for caso in casos:
                fuente_t = os.path.join(BENCH, caso + ".t")
                fuente_c = os.path.join(BENCH, caso + ".c")

                codigo, errores = compilar_archivo(fuente_t)
                if errores:
                    raise SystemExit(f"{caso}: {errores}")

                compilar_c(codigo, os.path.join(tmp, caso + "_tc"), tmp, nivel)
                compilar_c(sin_comprobaciones(codigo),
                           os.path.join(tmp, caso + "_sc"), tmp, nivel)

                t_tc, s_tc = cronometrar(os.path.join(tmp, caso + "_tc"))
                t_sc, _ = cronometrar(os.path.join(tmp, caso + "_sc"))

                if os.path.exists(fuente_c):
                    with open(fuente_c, encoding="utf-8") as f:
                        compilar_c(f.read(), os.path.join(tmp, caso + "_c"),
                                   tmp, nivel)
                    t_c, s_c = cronometrar(os.path.join(tmp, caso + "_c"))
                    if s_c.strip() != s_tc.strip():
                        print(f"  AVISO: {caso} da resultados distintos "
                              f"({s_c.strip()!r} contra {s_tc.strip()!r})")
                    razon, c = f"{t_tc / t_c:.2f}x", f"{t_c:.3f}s"
                else:
                    razon, c = "-", "-"

                print(f"{caso:<24} {c:>10} {t_tc:>9.3f}s {t_sc:>9.3f}s "
                      f"{razon:>11}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
