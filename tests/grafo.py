#!/usr/bin/env python3
"""Genera `docs/grafo-llamadas.md`: la red de llamadas entre los archivos del
compilador.

Cada nodo es un archivo `.t`; una flecha `A --> B` dice que `A` usa algo de
`B`:

  * una llamada calificada `I.tipo_de(...)` (o una referencia `I.Contexto`)
    se resuelve por el alias del `use "tipar.t" como I;` del archivo, y
  * lo que se trae sin calificar de la biblioteca (`use "std/texto";`) se
    dibuja como una flecha al modulo de `std`.

Se lee con el lexer, no a mano: las cadenas interpoladas son un solo token,
asi que un `I.algo` dentro de un mensaje no se cuenta como llamada.

No se edita a mano: se regenera con `make grafo`.
"""

import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Las palabras reservadas, igual que en el lexer del compilador: un
# identificador que sea una de estas es `palabra`, no `ident`.
PALABRAS = {
    "fn", "let", "var", "mut", "if", "else", "while", "return",
    "true", "false", "str", "view", "bool", "list", "struct",
    "use", "try", "sino", "fail", "map", "enum", "match", "externo",
    "for", "en", "break", "continue",
    "u8", "u16", "u32", "u64", "usize", "i8", "i16", "i32", "i64", "f32", "f64",
    "drop", "extends", "protocol", "implements", "anchor",
}


class _Token:
    __slots__ = ("tipo", "valor")

    def __init__(self, tipo, valor):
        self.tipo = tipo
        self.valor = valor


def leer(ruta):
    with open(ruta, encoding="utf-8") as f:
        return f.read()


def tokenizar(fuente):
    """Un lexer minimo para el grafo: `palabra`, `ident`, `cadena`,
    `interpolada`, `entero` y `simbolo`. Salta comentarios y trata las
    cadenas (normales e interpoladas) como un solo token, asi que un
    `I.algo` dentro de un mensaje no se cuenta como llamada."""
    toks = []
    i = 0
    n = len(fuente)
    while i < n:
        c = fuente[i]
        if c in " \t\r\n":
            i += 1
            continue
        if fuente.startswith("//", i):
            while i < n and fuente[i] != "\n":
                i += 1
            continue
        if fuente.startswith("/*", i):
            fin = fuente.find("*/", i + 2)
            i = n if fin < 0 else fin + 2
            continue
        if c == '"':
            inicio = i
            i += 1
            while i < n:
                if fuente[i] == "\\":
                    i += 2
                    continue
                if fuente[i] == '"':
                    i += 1
                    break
                i += 1
            toks.append(_Token("cadena", fuente[inicio + 1:i - 1]))
            continue
        if c == "$" and i + 1 < n and fuente[i + 1] == '"':
            i += 2
            prof = 0
            while i < n:
                if fuente[i] == "\\":
                    i += 2
                    continue
                if fuente[i] == '"':
                    if prof == 0:
                        i += 1
                        break
                    i += 1
                    while i < n:  # cadena dentro de la interpolacion
                        if fuente[i] == "\\":
                            i += 2
                            continue
                        if fuente[i] == '"':
                            i += 1
                            break
                        i += 1
                    continue
                if fuente[i] == "{":
                    if i + 1 < n and fuente[i + 1] == "{":
                        i += 2  # {{ es una llave literal
                        continue
                    prof += 1
                elif fuente[i] == "}":
                    if i + 1 < n and fuente[i + 1] == "}":
                        i += 2  # }} es una llave literal
                        continue
                    prof -= 1
                i += 1
            toks.append(_Token("interpolada", ""))
            continue
        if c.isalpha() or c == "_":
            j = i
            while j < n and (fuente[j].isalnum() or fuente[j] == "_"):
                j += 1
            palabra = fuente[i:j]
            toks.append(_Token("palabra" if palabra in PALABRAS else "ident",
                               palabra))
            i = j
            continue
        if c.isdigit():
            j = i
            while j < n and (fuente[j].isalnum() or fuente[j] in "._"):
                j += 1
            toks.append(_Token("entero", fuente[i:j]))
            i = j
            continue
        toks.append(_Token("simbolo", c))
        i += 1
    return toks

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
SALIDA_INDICE = os.path.join(RAIZ, "docs", "llamadas.md")

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
    """De una ruta de `use`, a la ruta (relativa al repo) que trae.

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
        toks = tokenizar(leer(os.path.join(RAIZ, a)))

        # Primero los `use`: alias -> archivo, y las hojas de std.
        alias = {}
        i = 0
        while i < len(toks):
            t = toks[i]
            if t.tipo == "palabra" and t.valor in ("use", "use"):
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
    toks = tokenizar(leer(os.path.join(RAIZ, archivo)))
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


def llamadas():
    """Todas las llamadas: `(archivo, funcion, archivo_del_callee, callee)`.

    `archivo_del_callee` es `None` si es del lenguaje (builtin), el mismo
    archivo si es local, o el modulo de std/calificado."""
    comps = archivos()
    locales = {a: funciones_de(a) for a in comps}
    std_de = {}
    for s in STD_MODULOS:
        for fn in funciones_de(s):
            std_de.setdefault(fn, []).append(s)

    todas = []
    for a in comps:
        toks = tokenizar(leer(os.path.join(RAIZ, a)))

        # los alias de los `use`, igual que en grafo()
        alias = {}
        i = 0
        while i < len(toks):
            if toks[i].tipo == "palabra" and toks[i].valor in ("use", "use"):
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
                            todas.append((a, actual, alias[cabeza],
                                          toks[i - 1].valor))
                    elif i >= 1 and toks[i - 1].tipo == "ident":
                        # sin calificar: local, de std, o del lenguaje
                        nombre = toks[i - 1].valor
                        if nombre in locales[a]:
                            todas.append((a, actual, a, nombre))
                        elif nombre in std_de:
                            for s in std_de[nombre]:
                                todas.append((a, actual, s, nombre))
                        else:
                            todas.append((a, actual, None, nombre))
            i += 1

    return todas


def grafo_funciones():
    """Aristas entre funciones de distintos archivos (de `llamadas()`)."""
    return {(a, fa, b, fb) for (a, fa, b, fb) in llamadas()
            if b is not None and b != a}


def etiqueta_corta(rel):
    if rel.startswith("std/"):
        return rel[:-2]
    return os.path.basename(rel)


def indice(todas):
    """`{(archivo, funcion): {(archivo_llamante, funcion_llamante)}}`.

    Sin las del lenguaje: no se cambian desde aqui."""
    de = {}
    for ca, cf, b, fb in todas:
        if b is None:
            continue
        de.setdefault((b, fb), set()).add((ca, cf))
    return de


def contenido_indice(de):
    por_archivo = {}
    for b, fb in de:
        por_archivo.setdefault(b, []).append(fb)

    lineas = [
        "# Índice de llamadas del compilador\n",
        "\n",
        "Regenerado por `make grafo` (`tests/grafo.py`); no se edita a mano.\n",
        "Para cada función, quién la llama: `nombre (archivo)`, con el archivo\n",
        "de la que llama. Las funciones del lenguaje (`copiar`, `igual`,\n",
        "`largo`...) no aparecen porque no se cambian desde aquí.\n",
        "\n",
    ]
    for b in sorted(por_archivo):
        lineas.append(f"## {etiqueta(b)}\n")
        for fb in sorted(por_archivo[b]):
            llamantes = sorted(de[(b, fb)])
            lista = ", ".join(f"`{cf}` ({etiqueta_corta(ca)})"
                              for ca, cf in llamantes)
            lineas.append(f"- `{fb}` ← {lista}\n")
        lineas.append("\n")
    return "".join(lineas)


def nodo_fn(archivo, fn):
    return f"{nodo_id(archivo)}__{fn}"


def mermaid_funciones_de(archivo, aristas_de):
    """El grafo de UN archivo: sus funciones y las de fuera que llama."""
    locales = sorted({fa for fa, _b, _fb in aristas_de})
    externas = sorted({(b, fb) for _fa, b, fb in aristas_de})
    lineas = ["graph TD"]
    lineas.append(f"    subgraph {nodo_id(archivo)}[\"{etiqueta(archivo)}\"]")
    for fn in locales:
        lineas.append(f"        {nodo_fn(archivo, fn)}[\"{fn}\"]")
    lineas.append("    end")
    if externas:
        lineas.append("    subgraph fuera[\"de otros archivos\"]")
        for b, fb in externas:
            lineas.append(f"        {nodo_fn(b, fb)}[\"{fb} · {etiqueta_corta(b)}\"]")
        lineas.append("    end")
    lineas.append("")
    for fa, b, fb in sorted(aristas_de):
        lineas.append(f"    {nodo_fn(archivo, fa)} --> {nodo_fn(b, fb)}")
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
    por_archivo = {}
    for a, fa, b, fb in aristas:
        por_archivo.setdefault(a, []).append((fa, b, fb))
    lineas = [
        "# Grafo de funciones del compilador\n",
        "\n",
        "Generado por `make grafo` (`tests/grafo.py`); no se edita a mano.\n",
        "Un diagrama por archivo: sus funciones y las que llama de otros\n",
        "archivos (las de fuera llevan el nombre del archivo). Las llamadas\n",
        "dentro del mismo archivo y las funciones del lenguaje no se dibujan.\n",
        "Para saber quien llama a una funcion, mira `docs/llamadas.md`.\n",
        "\n",
    ]
    for a in sorted(por_archivo):
        lineas.append(f"## {etiqueta(a)}\n")
        lineas.append("\n```mermaid\n")
        lineas.append(mermaid_funciones_de(a, por_archivo[a]))
        lineas.append("```\n")
        lineas.append("\n")
    return "".join(lineas)


def principal():
    red = grafo()
    todas = llamadas()
    aristas = {(a, fa, b, fb) for (a, fa, b, fb) in todas
               if b is not None and b != a}
    textos = {
        SALIDA: contenido(red),
        SALIDA_FUNCIONES: contenido_funciones(aristas),
        SALIDA_INDICE: contenido_indice(indice(todas)),
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
          f"({len(red)} archivos, {n_flechas} flechas), "
          f"{os.path.relpath(SALIDA_FUNCIONES, RAIZ)} ({len(aristas)} aristas "
          f"en {len({a for a, _f, _b, _fb in aristas})} diagramas) "
          f"y {os.path.relpath(SALIDA_INDICE, RAIZ)} "
          f"({len(indice(todas))} funciones)")


if __name__ == "__main__":
    principal()
