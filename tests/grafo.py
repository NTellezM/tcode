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
SALIDA_FUNCIONES = os.path.join(RAIZ, "docs", "grafo-funciones.md")

# Los modulos de std que el compilador importa sin calificar: sus funciones
# son las que una llamada sin calificar puede traer.
STD_MODULOS = ["std/texto.t", "std/lista.t", "std/mapa.t", "std/caracter.t"]


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


def funciones_de(archivo):
    """Los nombres de las funciones que define `archivo`."""
    toks = tokenizar(leer_fuente(os.path.join(RAIZ, archivo)), archivo)
    defs = set()
    for i in range(len(toks)):
        t = toks[i]
        if t.tipo == "palabra" and t.valor == "fn":
            j = i + 1
            if j < len(toks) and toks[j].tipo == "simbolo" \
                    and toks[j].valor == "!":
                j += 1
            if j < len(toks) and toks[j].tipo == "ident":
                defs.add(toks[j].valor)
    return defs


def grafo_funciones():
    """Aristas entre funciones de distintos archivos.

    Devuelve un conjunto de `(archivo, funcion, archivo, funcion)`. Las
    llamadas dentro del mismo archivo no salen: son la madeja interna."""
    comps = archivos()
    locales = {a: funciones_de(a) for a in comps}
    std_de = {}
    for s in STD_MODULOS:
        for fn in funciones_de(s):
            std_de.setdefault(fn, []).append(s)

    aristas = set()
    for a in comps:
        toks = tokenizar(leer_fuente(os.path.join(RAIZ, a)), a)

        # los alias de los `usar`, igual que en grafo()
        alias = {}
        i = 0
        while i < len(toks):
            if toks[i].tipo == "palabra" and toks[i].valor == "usar":
                ruta = toks[i + 1].valor
                j = i + 2
                if j < len(toks) and toks[j].tipo == "ident" \
                        and toks[j].valor == "como":
                    alias[toks[j + 1].valor] = resolver(a, ruta)
                    j += 2
                i = j
            else:
                i += 1

        # las llamadas, con la funcion que las hace
        actual = None
        prof = 0
        i = 0
        while i < len(toks):
            t = toks[i]
            if t.tipo == "palabra" and t.valor == "fn":
                j = i + 1
                if j < len(toks) and toks[j].tipo == "simbolo" \
                        and toks[j].valor == "!":
                    j += 1
                if j < len(toks) and toks[j].tipo == "ident":
                    actual = toks[j].valor
                    prof = 0
                    i = j + 1
                    continue
            if t.tipo == "simbolo":
                if t.valor == "{":
                    prof += 1
                elif t.valor == "}":
                    prof -= 1
                    if prof <= 0:
                        actual = None
                        prof = 0
                elif t.valor == "(" and actual is not None and prof >= 1:
                    if i >= 3 and toks[i - 1].tipo == "ident" \
                            and toks[i - 2].tipo == "simbolo" \
                            and toks[i - 2].valor == "." \
                            and toks[i - 3].tipo == "ident":
                        # calificada: `alias.func(...)`
                        cabeza = toks[i - 3].valor
                        if cabeza in alias:
                            aristas.add((a, actual, alias[cabeza],
                                         toks[i - 1].valor))
                    elif i >= 1 and toks[i - 1].tipo == "ident":
                        # sin calificar: local, de std, o del lenguaje
                        nombre = toks[i - 1].valor
                        if nombre in std_de:
                            for s in std_de[nombre]:
                                aristas.add((a, actual, s, nombre))
            i += 1

    return aristas


def nodo_fn(archivo, fn):
    return f"{nodo_id(archivo)}__{fn}"


def mermaid_funciones(aristas):
    usados = {}
    for a, fa, b, fb in aristas:
        usados.setdefault(a, set()).add(fa)
        usados.setdefault(b, set()).add(fb)

    lineas = ["graph TD"]
    for a in sorted(usados):
        lineas.append(f"    subgraph {nodo_id(a)}[\"{etiqueta(a)}\"]")
        for fn in sorted(usados[a]):
            lineas.append(f"        {nodo_fn(a, fn)}[\"{fn}\"]")
        lineas.append("    end")
    lineas.append("")
    for a, fa, b, fb in sorted(aristas):
        lineas.append(f"    {nodo_fn(a, fa)} --> {nodo_fn(b, fb)}")
    return "\n".join(lineas) + "\n"


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


def contenido_funciones(aristas):
    return (
        "# Grafo de funciones del compilador\n\n"
        "Generado por `make grafo` (`tests/grafo.py`); no se edita a mano.\n"
        "Cada nodo es una funcion, agrupada por archivo; una flecha `A --> B`\n"
        "dice que la funcion `A` llama a la `B` de otro archivo. Las llamadas\n"
        "dentro del mismo archivo y las funciones del lenguaje (`copiar`,\n"
        "`igual`, `largo`...) no se dibujan.\n\n"
        "```mermaid\n" + mermaid_funciones(aristas) + "```\n"
    )


def principal():
    red = grafo()
    aristas = grafo_funciones()
    textos = {
        SALIDA: contenido(red),
        SALIDA_FUNCIONES: contenido_funciones(aristas),
    }

    if "--comprobar" in sys.argv:
        todo_bien = True
        for ruta, texto in textos.items():
            try:
                with open(ruta, encoding="utf-8") as f:
                    actual = f.read()
            except OSError:
                actual = ""
            if actual != texto:
                print(f"FALLA: {os.path.relpath(ruta, RAIZ)} no esta al dia; "
                      "regeneralo con `make grafo`", file=sys.stderr)
                todo_bien = False
        if not todo_bien:
            sys.exit(1)
        print("grafo de llamadas: al dia")
        return

    for ruta, texto in textos.items():
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(texto)
    n_flechas = sum(len(v) for v in red.values())
    print(f"escrito {os.path.relpath(SALIDA, RAIZ)} "
          f"({len(red)} archivos, {n_flechas} flechas) y "
          f"{os.path.relpath(SALIDA_FUNCIONES, RAIZ)} ({len(aristas)} aristas)")


if __name__ == "__main__":
    principal()
