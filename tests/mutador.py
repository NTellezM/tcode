"""
Rompe programas validos a proposito.

El generador de `generador_programas.py` solo produce programas correctos, y
con eso se prueba la mitad del compilador: la que acepta. La otra mitad —la
que rechaza— crece con cada construccion que anadimos y hasta ahora solo se
probaba con ocho programas escritos a mano.

Un mutante no tiene por que ser invalido: borrar un `var` puede dejar algo
que sigue compilando. Lo que se exige no es que falle, sino que el compilador
se comporte: o lo acepta, o lo rechaza diciendo archivo y linea. Nunca una
excepcion, nunca un cuelgue.
"""

import random
import re

PUNTUACION = list("(){}[]<>,;:.=+-*/%!&|\"")
PALABRAS_SUELTAS = [
    "fn", "let", "var", "if", "else", "while", "return", "str", "view",
    "usize", "i64", "bool", "struct", "lista", "mapa", "mut", "try", "sino",
    "falla", "usar", "true", "false", "x", "0", "1",
]


def _piezas(fuente):
    """Divide en piezas conservando los espacios, para poder recomponer."""
    return re.findall(r"\s+|\w+|.", fuente)


def mutar(fuente, semilla):
    """Devuelve (fuente_mutada, descripcion_de_la_mutacion)."""
    r = random.Random(semilla)
    piezas = _piezas(fuente)
    indices = [i for i, p in enumerate(piezas) if not p.isspace()]
    if not indices:
        return fuente, "sin cambios"

    cual = r.choice([
        "borrar", "borrar", "duplicar", "intercambiar", "sustituir",
        "sustituir", "insertar_signo", "cortar_final", "borrar_linea",
    ])

    if cual == "borrar":
        i = r.choice(indices)
        quitada = piezas[i]
        piezas[i] = ""
        return "".join(piezas), f"borrada la pieza {quitada!r}"

    if cual == "duplicar":
        i = r.choice(indices)
        piezas[i] = piezas[i] + piezas[i]
        return "".join(piezas), f"duplicada la pieza {piezas[i]!r}"

    if cual == "intercambiar":
        if len(indices) < 2:
            return fuente, "sin cambios"
        k = r.randrange(len(indices) - 1)
        a, b = indices[k], indices[k + 1]
        piezas[a], piezas[b] = piezas[b], piezas[a]
        return "".join(piezas), f"intercambiadas {piezas[b]!r} y {piezas[a]!r}"

    if cual == "sustituir":
        i = r.choice(indices)
        nueva = r.choice(PALABRAS_SUELTAS)
        viejo = piezas[i]
        piezas[i] = nueva
        return "".join(piezas), f"{viejo!r} sustituida por {nueva!r}"

    if cual == "insertar_signo":
        i = r.choice(indices)
        signo = r.choice(PUNTUACION)
        piezas[i] = piezas[i] + signo
        return "".join(piezas), f"insertado {signo!r}"

    if cual == "cortar_final":
        # Un archivo truncado a la mitad: bloques y cadenas sin cerrar.
        corte = r.randrange(len(fuente) // 2, len(fuente)) if len(fuente) > 2 else 1
        return fuente[:corte], f"cortado en el byte {corte}"

    lineas = fuente.split("\n")
    if len(lineas) < 2:
        return fuente, "sin cambios"
    i = r.randrange(len(lineas))
    quitada = lineas[i].strip()
    del lineas[i]
    return "\n".join(lineas), f"borrada la linea {i + 1}: {quitada[:40]!r}"
