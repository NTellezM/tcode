#!/usr/bin/env python3
"""
Suite del lenguaje Tcode. Cada seccion es un modulo de `tests/lenguaje/`.

RECHAZO   -> el programa NO debe compilar, y el error debe explicar por que.
ACEPTA    -> compila, corre bajo ASan+UBSan y da exactamente esta salida.
GENERADOR -> el comprobador lo acepta y el generador se niega a escribirlo:
             es la valvula, y sin ella el programa se colaria hasta el C.

Los cuatro primeros casos de RECHAZO son las cuatro clases de fallo que
encontramos auditando la libreria safestr en C. Que aqui sean errores de compilacion
es la unica razon por la que este lenguaje existe.

Sin argumentos corre todas las secciones, cada una en su proceso. Con nombres,
solo esas:

    python3 tests/test_lenguaje.py ACEPTA ABORTA
    python3 tests/test_lenguaje.py --lista
    TCODE_EN_SERIE=1 python3 tests/test_lenguaje.py     # una tras otra
"""

import concurrent.futures
import importlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)
sys.path.insert(0, os.path.join(RAIZ, "tests"))

from cifras import guardar
from lenguaje.comun import Resultado, construir_tcodec

# Las secciones, en el orden en que corren en serie. Cada una se puede pedir
# sola, y es el modulo de `tests/lenguaje/` que se llama como ella.
SECCIONES = [
    "RECHAZO", "AVISA", "ACEPTA", "GENERADOR", "SALIDA", "ARCHIVOS", "FORMATO",
    "LINEAS", "ABORTA", "MODULOS", "EJEMPLOS", "PROGRAMAS", "REGLAS",
    "ESPECIFICACION", "CONGELADO",
]
# Las que mas tardan, en el orden en que conviene empezarlas: con una seccion
# por proceso, la pasada entera dura lo que la mas larga.
PRIMERO = ["ACEPTA", "EJEMPLOS"]


def en_serie(secciones, todas):
    """Las secciones una tras otra, en este proceso. Si son todas, las cifras
    van a `.cifras.json`; si la pidio `en_procesos`, lo suyo va al archivo de
    `TCODE_RESULTADO` para que lo sume."""
    suite = Resultado()
    for nombre in secciones:
        modulo = importlib.import_module(f"lenguaje.{nombre.lower()}")
        print(f"=== {nombre}: {modulo.TITULO} ===", flush=True)
        modulo.correr(suite)
    print(f"\n{suite.total} casos, {suite.fallos} fallas")
    if todas:
        suite.cifra("casos", suite.total)
        guardar("lenguaje", suite.cifras)
    elif os.environ.get("TCODE_RESULTADO"):
        with open(os.environ["TCODE_RESULTADO"], "w", encoding="utf-8") as f:
            json.dump({"total": suite.total, "fallos": suite.fallos,
                       "cifras": suite.cifras}, f)
    return 1 if suite.fallos else 0


def en_procesos(secciones, todas):
    """Cada seccion en su propio proceso, tantos a la vez como nucleos. Cada
    una va por su cuenta —su directorio temporal, sus herramientas—, asi que
    no se estorban. Lo que imprime cada una sale entero cuando acaba, y al
    final se suman los casos, las fallas y, si corrieron todas, las cifras
    del README."""
    orden = ([s for s in PRIMERO if s in secciones]
             + [s for s in SECCIONES if s in secciones and s not in PRIMERO])
    tmp = tempfile.mkdtemp(prefix="tcode-secciones-")

    # `tcodec` se construye una vez, desde su semilla, y cada seccion recibe
    # el mismo: todas lo usan, tambien las que comparan sus capas con las de
    # Python, que construyen con el sus herramientas.
    constructor = concurrent.futures.ThreadPoolExecutor(1)
    construido = constructor.submit(construir_tcodec, tmp)

    def una(seccion):
        ruta = os.path.join(tmp, seccion + ".json")
        entorno = dict(os.environ, TCODE_RESULTADO=ruta)
        try:
            entorno["TCODE_TCODEC"] = construido.result()
        except RuntimeError:
            pass    # cada seccion lo intenta y dice por que no
        antes = time.monotonic()
        r = subprocess.run([sys.executable, os.path.abspath(__file__), seccion],
                           capture_output=True, text=True, env=entorno)
        return seccion, r, ruta, time.monotonic() - antes

    casos = fallas = 0
    cifras = {}
    try:
        # Uno mas que nucleos: mientras esperan a `tcodec` no gastan nada.
        with concurrent.futures.ThreadPoolExecutor((os.cpu_count() or 2) + 1) as hilos:
            for hecho in concurrent.futures.as_completed(
                    [hilos.submit(una, s) for s in orden]):
                seccion, r, ruta, tardo = hecho.result()
                # Su ultima linea son sus casos y sus fallas: aqui se suman.
                lineas = r.stdout.rstrip("\n").split("\n")
                while lineas and (not lineas[-1].strip()
                                  or lineas[-1].endswith(" fallas")):
                    lineas.pop()
                print("\n".join(lineas))
                if r.stderr.strip():
                    print(r.stderr.rstrip("\n"))
                print(f"    ({seccion}: {tardo:.0f} s)", flush=True)
                try:
                    with open(ruta, encoding="utf-8") as f:
                        dicho = json.load(f)
                except (OSError, ValueError):
                    dicho = None
                if dicho is None or (r.returncode != 0 and not dicho["fallos"]):
                    fallas += 1
                    print(f"  FALLA: la seccion {seccion} no termino bien "
                          f"(codigo {r.returncode})")
                if dicho is not None:
                    casos += dicho["total"]
                    fallas += dicho["fallos"]
                    cifras.update(dicho["cifras"])
    finally:
        constructor.shutdown()
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{casos} casos, {fallas} fallas")
    if todas:
        cifras["casos"] = casos
        guardar("lenguaje", cifras)
    return 1 if fallas else 0


def main(argumentos):
    if "--lista" in argumentos:
        print("\n".join(SECCIONES))
        return 0
    pedidas = [a.upper() for a in argumentos]
    desconocidas = [a for a in pedidas if a not in SECCIONES]
    if desconocidas:
        print(f"no hay seccion {', '.join(desconocidas)}; hay: {' '.join(SECCIONES)}",
              file=sys.stderr)
        return 2
    # Solo si corren todas las cifras de la suite son las de la suite.
    todas = not pedidas
    secciones = pedidas or SECCIONES
    if (len(secciones) > 1 and not os.environ.get("TCODE_EN_SERIE")
            and not os.environ.get("TCODE_RESULTADO")):
        return en_procesos(secciones, todas)
    return en_serie(secciones, todas)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
