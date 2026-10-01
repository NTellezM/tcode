#!/usr/bin/env python3
"""
La cobertura del compilador de Python: qué caminos del oráculo no se pisan.

El oráculo congelado (`tcode/`) es la segunda opinión de la suite: si una
regla suya no se ejecuta nunca, esa regla no está probada por nadie. Aquí se
compila el corpus de la suite —y los rechazos escritos a mano— en un solo
proceso, con `coverage`, y se dice qué queda sin pisar.

Las secciones que comparan capa por capa (CUERPOS, EXPRESIONES, TIPAR,
PROPIEDAD, FIRMAS) compilan en hijos de `fork`, y `coverage` no ve lo que pasa
ahí: lo que sale aquí es un suelo, no el total. Las que sí entran son las que
compilan archivos enteros: PROGRAMA, RECHAZO, FORMAS y el corpus.

    python3 tests/cobertura.py               el resumen por archivo
    python3 tests/cobertura.py --faltan 40   y las líneas sin ejecutar de los
                                             `N` archivos con menos cobertura
    python3 tests/cobertura.py --minimo 80   falla si el total baja de ahí

Necesita `coverage` (`pip install coverage`), como `make lint` necesita
`ruff` y `mypy`.
"""

import argparse
import os
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def ejercitar():
    """Compila con el oráculo el corpus de la suite y los rechazos."""
    from tcode.cli import compilar_archivo
    from lenguaje.comun import corpus_python
    from lenguaje.rechazo import RECHAZO

    archivos = corpus_python()
    ok = malos = revientan = 0
    for ruta in archivos:
        try:
            _codigo, errores = compilar_archivo(ruta)
        except Exception:
            revientan += 1
            continue
        if errores:
            malos += 1
        else:
            ok += 1
    print(f"    corpus: {len(archivos)} archivos, {ok} compilan, {malos} "
          f"rechazados, {revientan} revientan")
    tmp = tempfile.mkdtemp(prefix="tcode-cobertura-")
    ruta = os.path.join(tmp, "p.t")
    for _nombre, fuente, _dice in RECHAZO:
        try:
            if isinstance(fuente, bytes):
                with open(ruta, "wb") as f:
                    f.write(fuente)
            else:
                with open(ruta, "w", encoding="utf-8") as f:
                    f.write(fuente)
            compilar_archivo(ruta)
        except Exception:
            pass
    print(f"    rechazos: {len(RECHAZO)} casos")
    # El formateador tambien es oraculo: la seccion FORMATO compara el de
    # `tcodec` con el suyo. Aqui se pisa para que la medida lo incluya.
    from tcode.formato import formatear
    formateados = 0
    for ruta in archivos:
        try:
            with open(ruta, encoding="utf-8") as f:
                formatear(f.read(), ruta)
            formateados += 1
        except Exception:
            pass
    print(f"    formateados: {formateados} archivos")
    return len(archivos) + len(RECHAZO) + formateados


def faltan(datos, cuantos):
    """Las líneas sin ejecutar de los archivos con menos cobertura."""
    peores = sorted(datos["files"].items(), key=lambda x: x[1]["summary"]["percent_covered"])
    for ruta, d in peores[:cuantos]:
        s = d["summary"]
        print(f"\n    {ruta}: {s['percent_covered']:.0f}% "
              f"({s['missing_lines']} de {s['num_statements']} sin ejecutar)")
        lineas = open(os.path.join(RAIZ, ruta), encoding="utf-8").read().splitlines()
        for n in d["missing_lines"][:12]:
            print(f"      {n:5d}  {lineas[n - 1].strip()[:76]}")


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--faltan", type=int, default=0, metavar="N",
                   help="y las lineas sin ejecutar de los N peores archivos")
    p.add_argument("--minimo", type=float, default=None,
                   help="falla si el total baja de este porcentaje")
    a = p.parse_args()

    try:
        import coverage
    except ImportError:
        print("falta `coverage`: pip install coverage", file=sys.stderr)
        return 2

    datos_cov = os.path.join(RAIZ, ".cache", "cobertura")
    os.makedirs(os.path.dirname(datos_cov), exist_ok=True)
    for resto in (datos_cov, datos_cov + ".json"):
        if os.path.exists(resto):
            os.remove(resto)
    cov = coverage.Coverage(source=["tcode"], data_file=datos_cov)
    print("=== COBERTURA: los caminos del oraculo de Python que la suite pisa ===")
    cov.start()
    try:
        cuantos = ejercitar()
    finally:
        cov.stop()
        cov.save()

    print(f"    {cuantos} compilaciones")
    if a.faltan:
        import json
        cov.json_report(outfile=datos_cov + ".json")
        with open(datos_cov + ".json", encoding="utf-8") as f:
            faltan(json.load(f), a.faltan)
    total = cov.report(show_missing=False)
    if a.minimo is not None and total < a.minimo:
        print(f"\nla cobertura ({total:.1f}%) baja del minimo ({a.minimo}%)",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
