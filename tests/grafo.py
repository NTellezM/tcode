#!/usr/bin/env python3
"""Genera `docs/grafo-llamadas.md`: la red de llamadas entre los archivos del
compilador.

Cada nodo es un archivo `.t`; una flecha `A --> B` dice que `A` usa algo de
`B`:

  * una llamada calificada `I.tipo_de(...)` (o una referencia `I.Contexto`)
    se resuelve por el alias del `usar "tipar.t" como I;` del archivo, y
  * lo que se trae sin calificar de la biblioteca (`usar "std/texto";`) se
    dibuja como una flecha al modulo de `std`.

Se lee con el lexer, no a mano: las cadenas interpoladas son un solo token,
asi que un `I.algo` dentro de un mensaje no se cuenta como llamada.

No se edita a mano: se regenera con `make grafo`.
"""

import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)

from tcode.lexer import leer_fuente, tokenizar

# Los directorios del compilador. De `std` no se listan todos: solo se dibujan
# los modulos que el compilador importa, como hojas.
DIRS = [
    "ejemplos/compilador",
    "ejemplos/compilador/lib",
    "ejemplos/lexer",
    "ejemplos/lexer/lib",
]

SALIDA = os.path.join(RAIZ, "docs", "grafo-llamadas.md")


def archivos():
    """Los archivos `.t` del compilador, como rutas relativas al repo."""
    out = []
    for d in DIRS:
        raiz_d = os.path.join(RAIZ, d)
        for nombre in sorted(os.listdir(raiz_d)):
            if nombre.endswith(".t") and not nombre.startswith(".mut_fuzz"):
                out.append(os.path.join(d, nombre))
    return out


def resolver(desde, ruta):
    """De una ruta de `usar`, a la ruta (relativa al repo) que trae.

    `std/...` es desde la raiz; lo demas, desde el directorio del archivo."""
    if ruta.startswith("std/"):
        j = ruta
    else:
        j = os.path.normpath(os.path.join(os.path.dirname(desde), ruta))
    if not j.endswith(".t"):
        j += ".t"
    return j


def nodo_id(rel):
    """Identificador unico para Mermaid."""
    s = rel
    if s.startswith("ejemplos/"):
        s = s[len("ejemplos/"):]
    if s.endswith(".t"):
        s = s[:-2]
    return s.replace("/", "_").replace(".", "_")


def etiqueta(rel):
    """La cara del nodo: ruta corta, con `std/` tal cual."""
    if rel.startswith("std/"):
        return rel[:-2]  # "std/texto"
    s = rel
    if s.startswith("ejemplos/"):
        s = s[len("ejemplos/"):]
    return s  # "compilador/lib/comprobar.t"


def grafo():
    """`{archivo: {archivos a los que usa}}`."""
    nodos = set(archivos())
    salidas = {a: set() for a in nodos}

    for a in sorted(nodos):
        toks = tokenizar(leer_fuente(os.path.join(RAIZ, a)), a)

        # Primero los `usar`: alias -> archivo, y las hojas de std.
        alias = {}
        i = 0
        while i < len(toks):
            t = toks[i]
            if t.tipo == "palabra" and t.valor == "usar":
                ruta = toks[i + 1].valor
                j = i + 2
                al = None
                if j < len(toks) and toks[j].tipo == "ident" \
                        and toks[j].valor == "como":
                    al = toks[j + 1].valor
                    j += 2
                res = resolver(a, ruta)
                if al:
                    alias[al] = res
                else:
                    nodos.add(res)
                    salidas.setdefault(res, set())
                    salidas[a].add(res)
                i = j
            else:
                i += 1

        # Luego las referencias calificadas `alias.algo` (llamada, tipo o
        # funcion como valor): el alias dice de que archivo viene.
        for k in range(len(toks) - 2):
            if toks[k].tipo == "ident" and toks[k].valor in alias \
                    and toks[k + 1].tipo == "simbolo" \
                    and toks[k + 1].valor == "." \
                    and toks[k + 2].tipo == "ident":
                destino = alias[toks[k].valor]
                if destino in nodos:
                    salidas[a].add(destino)

    return {a: salidas.get(a, set()) for a in sorted(nodos)}


def mermaid(red):
    lineas = ["graph TD"]
    for a in red:
        lineas.append(f"    {nodo_id(a)}[\"{etiqueta(a)}\"]")
    lineas.append("")
    for a in red:
        for b in sorted(red[a]):
            lineas.append(f"    {nodo_id(a)} --> {nodo_id(b)}")
    return "\n".join(lineas) + "\n"


def contenido(red):
    return (
        "# Grafo de llamadas del compilador\n\n"
        "Generado por `make grafo` (`tests/grafo.py`); no se edita a mano.\n"
        "Cada nodo es un archivo `.t` del compilador, y una flecha `A --> B`\n"
        "dice que `A` usa algo de `B` (una llamada o una referencia calificada\n"
        "`alias.algo`). Las hojas de `std` son los modulos que el compilador\n"
        "importa sin calificar.\n\n"
        "```mermaid\n" + mermaid(red) + "```\n"
    )


def principal():
    red = grafo()
    texto = contenido(red)

    if "--comprobar" in sys.argv:
        try:
            with open(SALIDA, encoding="utf-8") as f:
                actual = f.read()
        except OSError:
            actual = ""
        if actual != texto:
            print("FALLA: docs/grafo-llamadas.md no esta al dia; "
                  "regeneralo con `make grafo`", file=sys.stderr)
            sys.exit(1)
        print("grafo de llamadas: al dia")
        return

    with open(SALIDA, "w", encoding="utf-8") as f:
        f.write(texto)
    print(f"escrito {os.path.relpath(SALIDA, RAIZ)} "
          f"({len(red)} archivos, {sum(len(v) for v in red.values())} flechas)")


if __name__ == "__main__":
    principal()
