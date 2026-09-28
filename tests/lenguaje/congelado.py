"""CONGELADO: el compilador de Python no aprende nada nuevo."""

import json

from python_congelado import GUARDADA, diferencias, superficie

from .comun import Resultado

TITULO = "el compilador de Python no aprende nada nuevo"


def correr(suite: Resultado) -> None:
    # Desde 0.9.0 Python es un oraculo congelado: solo arreglos de
    # correccion. Lo nuevo va a `tcodec`, validado con oraculos que no son
    # Python. Ver `tests/python_congelado.py`.
    suite.total += 1
    with open(GUARDADA, encoding="utf-8") as f:
        antes = json.load(f)
    cambios = diferencias(antes, json.loads(json.dumps(superficie())))
    if cambios:
        suite.falla("el compilador de Python esta congelado",
                    "cambio lo que sabe; lo nuevo va solo a tcodec:\n         "
                    + "\n         ".join(cambios))
    else:
        print("    palabras, simbolos, tipos, internas, nodos y opciones: "
              "los de 0.9.0")
