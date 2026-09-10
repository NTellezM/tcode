"""Compilador de Tcode: fuente .t -> C -> binario nativo."""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

from tcode.lexer import ErrorLexico
from tcode.parser import parsear, ErrorSintactico
from tcode.modulos import cargar, ErrorDeModulo
from tcode.comprobador import comprobar
from tcode.generador import generar
from tcode.explicar import explicar

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNTIME = os.path.join(RAIZ, "runtime")

MARCA = "/* Generado por el compilador de Tcode. No editar a mano. */"


def _lo_generamos_nosotros(ruta):
    """True si ese .c lo escribio tcode: entonces se puede pisar."""
    try:
        with open(ruta, encoding="utf-8") as f:
            return MARCA in f.read(200)
    except OSError:
        return False


def compilar_a_c(fuente, archivo, devolver_comp=False):
    """Compila una fuente suelta, sin resolver `usar`. Lo usan los tests."""
    return _compilar(parsear(fuente, archivo), archivo, devolver_comp)


def compilar_archivo(ruta, devolver_comp=False):
    """Compila un archivo resolviendo sus modulos."""
    mostrada = os.path.relpath(ruta)
    if mostrada.startswith(".."):
        mostrada = os.path.abspath(ruta)
    return _compilar(cargar(ruta), mostrada, devolver_comp)


def _compilar(arbol, archivo, devolver_comp=False):
    errores, comp = comprobar(arbol, archivo)
    if errores:
        return (None, errores, comp) if devolver_comp else (None, errores)
    codigo = generar(arbol, comp, archivo)
    return (codigo, [], comp) if devolver_comp else (codigo, [])


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="tcode", description="Compilador del lenguaje Tcode")
    ap.add_argument("fuente", help="archivo .t")
    ap.add_argument("-o", "--salida", help="binario de salida")
    ap.add_argument("--emitir-c", action="store_true",
                    help="escribe el C generado y no invoca al compilador")
    ap.add_argument("--cc", default=os.environ.get("CC", "cc"))
    ap.add_argument("-O", "--optimizacion", default="2", choices=["0", "1", "2", "3", "s"],
                    help="nivel que se le pasa al compilador de C (por defecto 2). "
                         "Con aritmetica comprobada en bucles cerrados, 3 suele "
                         "recuperar lo que cuesta comprobar: los cuerpos crecen y "
                         "en -O2 dejan de integrarse")
    ap.add_argument("--solo-comprobar", action="store_true",
                    help="analiza y reporta errores, sin generar nada")
    ap.add_argument("--avisos-como-errores", action="store_true",
                    help="no compila si hay avisos")
    ap.add_argument("--sin-avisos", action="store_true",
                    help="no muestra los avisos")
    ap.add_argument("--explicar", action="store_true",
                    help="muestra lo que el compilador infirio: quien es "
                         "duenio de que, quien presta a quien, donde se libera "
                         "cada cosa y de donde sale cada vista")
    args = ap.parse_args(argv)

    if not os.path.isfile(args.fuente):
        print(f"tcode: no encuentro {args.fuente}", file=sys.stderr)
        return 2

    try:
        codigo, errores, comp = compilar_archivo(args.fuente, devolver_comp=True)
    except (ErrorLexico, ErrorSintactico, ErrorDeModulo) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"tcode: no se pudo leer: {exc}", file=sys.stderr)
        return 2

    avisos = comp.avisos if comp is not None else []

    if errores:
        for e in errores:
            print(f"error: {e}", file=sys.stderr)
        n = len(errores)
        print(f"\n{n} error{'es' if n != 1 else ''}. No se genero nada.",
              file=sys.stderr)
        return 1

    if avisos and not args.sin_avisos:
        for a in avisos:
            print(f"aviso: {a}", file=sys.stderr)
        if args.avisos_como_errores:
            n = len(avisos)
            print(f"\n{n} aviso{'s' if n != 1 else ''} tratado"
                  f"{'s' if n != 1 else ''} como error. No se genero nada.",
                  file=sys.stderr)
            return 1

    if args.explicar:
        print(explicar(comp, args.fuente))
        return 0

    if args.solo_comprobar:
        n = len(avisos)
        resumen = "sin errores" if not n else \
            f"sin errores, {n} aviso{'s' if n != 1 else ''}"
        print(f"{args.fuente}: {resumen}")
        return 0

    base = args.salida or os.path.splitext(args.fuente)[0]

    # Con --emitir-c el C es el producto y va junto al fuente. Sin la opcion
    # es un intermedio y va a un temporal: escribirlo junto al fuente pisaria
    # un `<base>.c` del usuario, y borrarlo despues lo destruiria.
    if args.emitir_c:
        ruta_c = base + ".c"
        if os.path.exists(ruta_c) and not _lo_generamos_nosotros(ruta_c):
            print(f"tcode: {ruta_c} ya existe y no lo genero tcode, asi que "
                  f"no lo piso. Usa -o para elegir otro nombre.",
                  file=sys.stderr)
            return 2
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        print(ruta_c)
        return 0

    tmp = tempfile.mkdtemp(prefix="tcode-")
    try:
        ruta_c = os.path.join(tmp, os.path.basename(base) + ".c")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)

        orden = [args.cc, "-std=c17", f"-O{args.optimizacion}", "-Wall", "-Wextra",
                 f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
                 "-o", base]
        r = subprocess.run(orden, capture_output=True, text=True)
        if r.returncode != 0:
            print("tcode: el C generado no compilo. Es un fallo del "
                  "compilador, no de tu programa.", file=sys.stderr)
            print(r.stderr, file=sys.stderr)
            return 1
        if r.stderr.strip():
            print(r.stderr, file=sys.stderr)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(base)
    return 0


if __name__ == "__main__":
    sys.exit(main())
