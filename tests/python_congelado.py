"""
La superficie del compilador de Python, congelada.

Desde 0.9.0 el compilador de Python (`tcode/`) es un oraculo congelado: no
aprende nada nuevo, solo recibe arreglos de correccion. Lo nuevo del
lenguaje va a `tcodec` y se valida con oraculos que no son Python. Esto
guarda lo que Python sabe —palabras, simbolos, tipos, funciones internas y
sus firmas, nodos del arbol y sus campos, opciones de la linea de ordenes—
en `tests/python_congelado.json`, y la seccion CONGELADO falla si cambia.

Un arreglo de correccion no cambia nada de eso. Una construccion nueva que
reutiliza nodos que ya existian tampoco: para eso esta la regla escrita, y
cada commit en `tcode/` trae el caso que demuestra que arregla algo.

    python3 tests/python_congelado.py           dice si cambio
    python3 tests/python_congelado.py --fijar   la vuelve a guardar; solo
                                                con una razon en el commit
"""

import dataclasses
import inspect
import json
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)
GUARDADA = os.path.join(RAIZ, "tests", "python_congelado.json")


def superficie() -> dict:
    from tcode import comprobador, lexer, nodos, parser

    internas = {}
    for nombre, firma in comprobador.INTERNAS.items():
        internas[nombre] = {k: (sorted(v) if isinstance(v, (set, frozenset))
                                else v)
                            for k, v in sorted(firma.items())}
    clases = {}
    for nombre, clase in inspect.getmembers(nodos, inspect.isclass):
        if clase.__module__ == nodos.__name__ and dataclasses.is_dataclass(clase):
            clases[nombre] = [f.name for f in dataclasses.fields(clase)]
    with open(os.path.join(RAIZ, "tcode", "cli.py"), encoding="utf-8") as f:
        opciones = sorted(set(re.findall(r'"(--?[a-zA-Z][\w-]*)"', f.read())))
    return {
        "palabras": sorted(lexer.PALABRAS),
        "simbolos": list(lexer.SIMBOLOS),
        "enteros": sorted([*comprobador.SIN_SIGNO, *comprobador.CON_SIGNO]),
        "decimales": sorted(comprobador.DECIMALES),
        "restricciones": sorted(parser.RESTRICCIONES),
        "internas": internas,
        "nodos": clases,
        "opciones": opciones,
    }


def diferencias(antes: dict, ahora: dict) -> list:
    """Lo que cambio, dicho por partes: que se anadio y que se quito."""
    salida = []
    for parte in sorted(set(antes) | set(ahora)):
        a, b = antes.get(parte), ahora.get(parte)
        if a == b:
            continue
        if isinstance(a, dict) and isinstance(b, dict):
            for k in sorted(set(a) | set(b)):
                if k not in a:
                    salida.append(f"{parte}: nuevo `{k}`")
                elif k not in b:
                    salida.append(f"{parte}: ya no esta `{k}`")
                elif a[k] != b[k]:
                    salida.append(f"{parte}: `{k}` cambio: {a[k]} -> {b[k]}")
        elif isinstance(a, list) and isinstance(b, list):
            for k in b:
                if k not in a:
                    salida.append(f"{parte}: nuevo `{k}`")
            for k in a:
                if k not in b:
                    salida.append(f"{parte}: ya no esta `{k}`")
            if not salida and a != b:
                salida.append(f"{parte}: cambio de orden")
        else:
            salida.append(f"{parte}: {a} -> {b}")
    return salida


def main() -> int:
    ahora = superficie()
    if "--fijar" in sys.argv:
        with open(GUARDADA, "w", encoding="utf-8") as f:
            json.dump(ahora, f, indent=1, sort_keys=True, ensure_ascii=False)
            f.write("\n")
        print(f"guardada en {os.path.relpath(GUARDADA, RAIZ)}")
        return 0
    with open(GUARDADA, encoding="utf-8") as f:
        antes = json.load(f)
    cambios = diferencias(antes, json.loads(json.dumps(ahora)))
    for c in cambios:
        print(f"  {c}")
    print("sin cambios" if not cambios else f"{len(cambios)} cambios")
    return 1 if cambios else 0


if __name__ == "__main__":
    sys.exit(main())
