#!/usr/bin/env python3
"""
La cobertura de `tcodec`, medida a mano.

`make check` no la corre: la CI no tiene tiempo. Esto es un instrumento que se
coge cuando se quiere mirar que caminos del compilador no pisa nadie.

Construye el compilador desde su C semilla (`bootstrap/tcodec.c`) con
`--coverage`, lo pasa por un subconjunto acotado de la suite —las secciones de
`make rapido`— y por los casos del banco (`bench/*.t`), y le pide a `gcov` las
lineas, las ramas y, en particular, **las funciones que no se ejecutan nunca**:
lo que nadie pisa no envejece con avisos, envejece a escondidas.

    make cobertura
    python3 tests/cobertura.py                    # `rapido` y el banco
    python3 tests/cobertura.py RECHAZO ACEPTA     # solo esas secciones

Se instrumenta a `-O0`, que es donde gcov dice las lineas y las ramas exactas;
por eso la lista de funciones sin ejecutar incluye tambien las que el
optimizador quitaria (media `std/`, por ejemplo), que el compilador escribe
igual porque emite todas las funciones de todos los modulos que carga.

Necesita `gcov`, el de gcc: si no esta o no funciona, lo dice y sale. Todo lo
que escribe vive en `.cache/cobertura/`; no toca `tcodec` ni el arbol.
"""

import argparse
import glob
import gzip
import json
import os
import shutil
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNTIME = os.path.join(RAIZ, "runtime")
SEMILLA = os.path.join(RAIZ, "bootstrap", "tcodec.c")
SISTEMA = os.path.join(RAIZ, "ejemplos", "compilador", "lib", "sistema_tcodec.c")
ACOMPANANTES = [os.path.join(RAIZ, "runtime", "safestr.c"), SISTEMA,
                os.path.join(RAIZ, "std", "proceso.c"),
                os.path.join(RAIZ, "std", "terminal.c")]
DIR = os.path.join(RAIZ, ".cache", "cobertura")
OBJETO = os.path.join(DIR, "tcodec.o")
BINARIO = os.path.join(DIR, "tcodec")

# Las secciones rapidas: las mismas de `make rapido` (Makefile: RAPIDAS). Es el
# subconjunto acotado que se usa cuando no se le piden otras por nombre.
RAPIDAS = ["RECHAZO", "AVISA", "ACEPTA", "EQUIVALE", "GENERADOR", "SALIDA",
           "ARCHIVOS", "ABORTA", "MODULOS", "FORMATO", "LINEAS", "EJEMPLOS",
           "ESPECIFICACION", "CONGELADO"]


def correr(orden, **kw):
    return subprocess.run(orden, cwd=RAIZ, capture_output=True, text=True, **kw)


def construir():
    """El compilador de `bootstrap/tcodec.c`, con los contadores de gcov.

    Solo se instrumenta el C semilla: los acompanantes son runtime, no
    compilador, y se compilan sin cobertura."""
    # `.cache/cobertura` fue un archivo de la cobertura vieja, la de Python:
    # ahora es un directorio. Cualquiera de los dos se tira y se rehace.
    if os.path.isdir(DIR):
        shutil.rmtree(DIR, ignore_errors=True)
    elif os.path.exists(DIR):
        os.remove(DIR)
    os.makedirs(DIR)
    cc = os.environ.get("CC", "cc")
    base = ["-std=c17", "-O0", "-g", f"-I{RUNTIME}"]

    r = correr([cc, "--coverage", *base, "-c", SEMILLA, "-o", OBJETO])
    if r.returncode != 0:
        return f"no compila {os.path.relpath(SEMILLA, RAIZ)}:\n{r.stderr[:800]}"

    objetos = []
    for fuente in ACOMPANANTES:
        objeto = os.path.join(DIR, os.path.basename(fuente) + ".o")
        r = correr([cc, *base, "-c", fuente, "-o", objeto])
        if r.returncode != 0:
            return f"no compila {os.path.relpath(fuente, RAIZ)}:\n{r.stderr[:800]}"
        objetos.append(objeto)

    r = correr([cc, "--coverage", OBJETO, *objetos, "-o", BINARIO, "-lm"])
    if r.returncode != 0:
        return f"no enlaza el compilador con cobertura:\n{r.stderr[:800]}"
    return None


def correr_corpus(secciones):
    """La suite rapida contra el compilador instrumentado, y el banco."""
    for viejo in glob.glob(os.path.join(DIR, "*.gcda")):
        os.remove(viejo)
    entorno = dict(os.environ, TCODE_TCODEC=BINARIO, TCODE_EN_SERIE="1",
                   TCODE_RAIZ=RAIZ)
    r = correr([sys.executable, os.path.join("tests", "test_lenguaje.py"),
                *secciones], env=entorno)
    resumen = [x for x in r.stdout.splitlines() if x.strip()]
    if resumen:
        print(f"  suite: {resumen[-1]}")
    if r.returncode != 0:
        print("  AVISO: la suite no termino bien; la cobertura es parcial")
        print("    " + "\n    ".join(r.stdout.rstrip().splitlines()[-8:]))
        print("    " + r.stderr.rstrip()[-400:])

    casos = sorted(glob.glob(os.path.join(RAIZ, "bench", "*.t")))
    for fuente in casos:
        correr([BINARIO, os.path.relpath(fuente, RAIZ), "--mostrar-c"], env=entorno)
    print(f"  banco: {len(casos)} casos")
    return r.returncode == 0


def gcov_json():
    """El JSON de gcov, o `(None, motivo)` si no se puede."""
    gcov = shutil.which("gcov")
    if not gcov:
        return None, ("no esta gcov. Es parte de gcc: instala gcc o el paquete "
                      "que lo traiga, y vuelve a probar.")
    for viejo in glob.glob(os.path.join(DIR, "*.gcov.json.gz")):
        os.remove(viejo)
    r = subprocess.run([gcov, "-j", "-b", "-c", "-o", DIR, OBJETO], cwd=DIR,
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, f"gcov fallo:\n{r.stderr[:800]}"
    salidas = sorted(glob.glob(os.path.join(DIR, "*.gcov.json.gz")))
    if not salidas:
        return None, "gcov no escribio ningun .gcov.json.gz"
    datos = {"files": []}
    for salida in salidas:
        with gzip.open(salida, "rt", encoding="utf-8") as f:
            datos["files"].extend(json.load(f)["files"])
    return datos, None


def _vacio():
    return {"lineas": 0, "cubiertas": 0, "funciones": 0, "cubiertas_fn": 0,
            "ramas": 0, "tomadas": 0, "alcanzadas": 0, "dos_vias": 0,
            "ambos": 0, "sin_ejecutar": 0}


def _sumar(destino, fuente):
    for clave, valor in fuente.items():
        destino[clave] += valor


def _grupo(nombre):
    """Los tres bloques del binario: el compilador, la biblioteca y el resto."""
    if os.path.basename(nombre) == "xid.t":
        return "tablas generadas"
    if nombre.startswith(("ejemplos/compilador/", "ejemplos/lexer/")):
        return "tcodec (compilador y lexer)"
    if nombre.startswith("std/"):
        return "std/ (biblioteca)"
    return "arranque y runtime"


def medir(datos):
    """Las cuentas que se resumen, y la lista de funciones sin ejecutar."""
    total = _vacio()
    por_fichero: dict[str, dict[str, int]] = {}
    nunca: list[tuple[str, int, str]] = []
    for f in datos["files"]:
        nombre = f["file"]
        if os.path.isabs(nombre):
            nombre = os.path.relpath(nombre, RAIZ)
        cuenta = _vacio()
        for fn in f.get("functions", []):
            cuenta["funciones"] += 1
            if fn["execution_count"] > 0:
                cuenta["cubiertas_fn"] += 1
            else:
                cuenta["sin_ejecutar"] += 1
                nunca.append((nombre, fn["start_line"], fn["name"]))
        for ln in f.get("lines", []):
            c = ln.get("count")
            if c is None:
                continue
            cuenta["lineas"] += 1
            if c > 0:
                cuenta["cubiertas"] += 1
            ramas = ln.get("branches") or []
            cuenta["ramas"] += len(ramas)
            cuenta["tomadas"] += sum(1 for b in ramas if b["count"] > 0)
            if c > 0:
                cuenta["alcanzadas"] += len(ramas)
            if len(ramas) == 2:
                cuenta["dos_vias"] += 1
                if all(b["count"] > 0 for b in ramas):
                    cuenta["ambos"] += 1
        por_fichero[nombre] = cuenta
        _sumar(total, cuenta)
    nunca.sort(key=lambda x: (x[0], x[1]))
    return total, por_fichero, nunca


def centinela(parte, entero):
    if not entero:
        return "-"
    return f"{100.0 * parte / entero:.1f}%"


def _resumen(c):
    return (f"lineas {centinela(c['cubiertas'], c['lineas']):>6s} "
            f"({c['cubiertas']}/{c['lineas']})"
            f"   funciones {centinela(c['cubiertas_fn'], c['funciones']):>6s} "
            f"({c['cubiertas_fn']}/{c['funciones']})"
            f"   ramas {centinela(c['tomadas'], c['ramas']):>6s} "
            f"({c['tomadas']}/{c['ramas']})"
            f"   ambos sentidos {centinela(c['ambos'], c['dos_vias']):>6s}")


def imprimir(total, por_fichero, nunca):
    print("\n=== cobertura de tcodec (gcov, -O0) ===")
    print(f"  total: {_resumen(total)}")
    print(f"    sin ejecutar nunca: {total['sin_ejecutar']} funciones")

    grupos: dict[str, dict[str, int]] = {}
    for nombre, cuenta in por_fichero.items():
        _sumar(grupos.setdefault(_grupo(nombre), _vacio()), cuenta)
    print("\n  por grupo:")
    for nombre in sorted(grupos):
        print(f"    {nombre:28s} {_resumen(grupos[nombre])}")

    print("\n  por fichero:")
    for nombre in sorted(por_fichero, key=lambda n: -por_fichero[n]["lineas"]):
        c = por_fichero[nombre]
        if not c["lineas"]:
            continue
        print(f"    {nombre:45s} lineas {c['cubiertas']:5d}/{c['lineas']:<5d} "
              f"{centinela(c['cubiertas'], c['lineas']):>6s}   "
              f"sin ejecutar: {c['sin_ejecutar']}")

    print(f"\n  funciones que no se ejecutan nunca: {len(nunca)}")
    fichero = None
    for nombre, linea, fn in nunca:
        if nombre != fichero:
            fichero = nombre
            print(f"    {nombre}:")
        print(f"      {linea:6d}  {fn}")


def main(argumentos):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("secciones", nargs="*",
                   help=f"secciones de la suite (por defecto: {' '.join(RAPIDAS)})")
    a = p.parse_args(argumentos)
    secciones = [s.upper() for s in a.secciones] or RAPIDAS

    print("construyendo tcodec con --coverage...")
    fallo = construir()
    if fallo:
        print(f"cobertura: {fallo}", file=sys.stderr)
        return 1

    print(f"corriendo {' '.join(secciones)} y el banco...")
    completa = correr_corpus(secciones)

    print("midiendo con gcov...")
    datos, fallo = gcov_json()
    if datos is None:
        print(f"cobertura: {fallo}", file=sys.stderr)
        return 1

    total, por_fichero, nunca = medir(datos)
    imprimir(total, por_fichero, nunca)
    return 0 if completa else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
