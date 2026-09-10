"""Compilador de safestr: fuente .sfs -> C -> binario nativo."""

import argparse
import os
import subprocess
import sys

from safestrc.lexer import ErrorLexico
from safestrc.parser import parsear, ErrorSintactico
from safestrc.modulos import cargar, ErrorDeModulo
from safestrc.comprobador import comprobar
from safestrc.generador import generar

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNTIME = os.path.join(RAIZ, "runtime")


def compilar_a_c(fuente, archivo):
    """Compila una fuente suelta, sin resolver `usar`. Lo usan los tests."""
    return _compilar(parsear(fuente, archivo), archivo)


def compilar_archivo(ruta):
    """Compila un archivo resolviendo sus modulos."""
    mostrada = os.path.relpath(ruta)
    if mostrada.startswith(".."):
        mostrada = os.path.abspath(ruta)
    return _compilar(cargar(ruta), mostrada)


def _compilar(arbol, archivo):
    errores, comp = comprobar(arbol, archivo)
    if errores:
        return None, errores
    return generar(arbol, comp, archivo), []


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="safestrc", description="Compilador del lenguaje safestr")
    ap.add_argument("fuente", help="archivo .sfs")
    ap.add_argument("-o", "--salida", help="binario de salida")
    ap.add_argument("--emitir-c", action="store_true",
                    help="escribe el C generado y no invoca al compilador")
    ap.add_argument("--cc", default=os.environ.get("CC", "cc"))
    ap.add_argument("--solo-comprobar", action="store_true",
                    help="analiza y reporta errores, sin generar nada")
    args = ap.parse_args(argv)

    if not os.path.isfile(args.fuente):
        print(f"safestrc: no encuentro {args.fuente}", file=sys.stderr)
        return 2

    try:
        codigo, errores = compilar_archivo(args.fuente)
    except (ErrorLexico, ErrorSintactico, ErrorDeModulo) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"safestrc: no se pudo leer: {exc}", file=sys.stderr)
        return 2

    if errores:
        for e in errores:
            print(f"error: {e}", file=sys.stderr)
        n = len(errores)
        print(f"\n{n} error{'es' if n != 1 else ''}. No se genero nada.",
              file=sys.stderr)
        return 1

    if args.solo_comprobar:
        print(f"{args.fuente}: sin errores")
        return 0

    base = args.salida or os.path.splitext(args.fuente)[0]
    ruta_c = base + ".c"
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(codigo)

    if args.emitir_c:
        print(ruta_c)
        return 0

    orden = [args.cc, "-std=c17", "-O2", "-Wall", "-Wextra",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", base]
    r = subprocess.run(orden, capture_output=True, text=True)
    if r.returncode != 0:
        print("safestrc: el C generado no compilo. Es un fallo del compilador,"
              " no de tu programa.", file=sys.stderr)
        print(r.stderr, file=sys.stderr)
        return 1
    if r.stderr.strip():
        print(r.stderr, file=sys.stderr)

    os.remove(ruta_c)
    print(base)
    return 0


if __name__ == "__main__":
    sys.exit(main())
