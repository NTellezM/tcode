#!/usr/bin/env python3
"""Genera `docs/grafo-llamadas.md`, `docs/grafo-funciones.md` y
`docs/llamadas.md`: la red de llamadas de los `.t` del repositorio.

Cubre los ficheros `.t` de `ejemplos/`, `programas/` y `bench/` —el compilador,
los programas de ejemplo y los del banco— y los modulos de `std/` que unos u
otros importan, directa o transitivamente. **No** cubre los `.t` de `tests/`,
que son entradas de prueba. La cabecera de cada documento lo dice, y no
promete mas de lo que mira.

Cada nodo es un fichero `.t`, con su ruta completa desde la raiz: asi
`ejemplos/compilador/tipar.t` no se confunde con
`ejemplos/compilador/lib/tipar.t`. Una flecha `A --> B` dice que `A` usa algo
de `B`: un `use`, una llamada calificada `I.tipo_de(...)` o una referencia
`I.Contexto`.

Las llamadas salen del lexer, no de buscar texto: las cadenas son un token,
pero el codigo dentro de `$"{...}"` se tokeniza como codigo, porque lo es. Asi
`imprimir($"{f(x)}")` cuenta como llamada a `f`, y un `I.algo` dentro de un
mensaje de texto no cuenta. Una llamada sin calificar se resuelve por el
`use` sin alias del fichero (`use "lib/sintaxis.t";` trae sus nombres, y
`#importar "x.t"` es `use "std/x.t"`), no solo por el fichero que la define.

Cada fichero se marca segun entre o no en el binario `tcodec`: los que no
entran pueden llamar a algo que, visto solo desde dentro, parece muerto.

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

# De donde salen los ficheros que se analizan. De `std/` solo se anaden los
# que estos importan (la clausura de `use`): el documento dice exactamente
# eso, y no finge cubrir toda la biblioteca.
BASES = ["ejemplos", "programas", "bench"]

# El programa que se compila para tener `tcodec`: su clausura de `use` es lo
# que entra en el binario.
RAIZ_BINARIO = "ejemplos/compilador/tcodec.t"

SALIDA = os.path.join(RAIZ, "docs", "grafo-llamadas.md")
SALIDA_FUNCIONES = os.path.join(RAIZ, "docs", "grafo-funciones.md")
SALIDA_INDICE = os.path.join(RAIZ, "docs", "llamadas.md")


class _Token:
    __slots__ = ("tipo", "valor")

    def __init__(self, tipo, valor):
        self.tipo = tipo
        self.valor = valor


def leer(ruta):
    with open(ruta, encoding="utf-8") as f:
        return f.read()


def _interpolada(fuente, i):
    """Las expresiones `{...}` de una interpolada que empieza en `i` (justo
    despues de la comilla de apertura de `$"`), y donde acaba la cadena.

    Devuelve `(expresiones, fin)`, con `fin` el indice tras la comilla de
    cierre. Las llaves dobles (`{{`, `}}`) son texto literal; dentro de una
    expresion, las cadenas anidadas se saltan enteras."""
    expresiones = []
    n = len(fuente)
    while i < n:
        c = fuente[i]
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return expresiones, i + 1
        if c == "{":
            if i + 1 < n and fuente[i + 1] == "{":
                i += 2
                continue
            inicio = i + 1
            prof = 1
            j = inicio
            while j < n and prof > 0:
                d = fuente[j]
                if d == "\\":
                    j += 2
                    continue
                if d == '"':
                    j += 1
                    while j < n:
                        if fuente[j] == "\\":
                            j += 2
                            continue
                        if fuente[j] == '"':
                            j += 1
                            break
                        j += 1
                    continue
                if d == "{":
                    prof += 1
                elif d == "}":
                    prof -= 1
                j += 1
            expresiones.append(fuente[inicio:j - 1])
            i = j
            continue
        i += 1
    return expresiones, i


def tokenizar(fuente, en_interpolacion=False):
    """Un lexer minimo para el grafo: `palabra`, `ident`, `cadena`,
    `interpolada`, `entero` y `simbolo`.

    Salta comentarios y no deja ver el texto de las cadenas, pero el codigo
    dentro de `$"{...}"` si se lexa: es codigo. Las llaves de una
    interpolacion no llegan a los tokens, para que quien cuenta llaves de un
    cuerpo de funcion no se confunda."""
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
        if c == "$" and i + 1 < n and fuente[i + 1] == '"':
            expresiones, i = _interpolada(fuente, i + 2)
            for e in expresiones:
                toks.extend(tokenizar(e, True))
            continue
        if fuente.startswith("#importar", i) \
                and (i + 9 >= n or not (fuente[i + 9].isalnum()
                                        or fuente[i + 9] == "_")):
            # La directiva de la biblioteca del compilador: `#importar "x.t"`
            # es `use "std/x.t"`. El lexer de verdad la da por una palabra.
            toks.append(_Token("palabra", "#importar"))
            i += 9
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
        if en_interpolacion and c in "{}":
            i += 1
            continue
        toks.append(_Token("simbolo", c))
        i += 1
    return toks


_TOKENS: dict[str, list] = {}


def tokens(rel):
    """Los tokens de `rel`, cacheados: el mismo fichero se mira varias veces."""
    if rel not in _TOKENS:
        _TOKENS[rel] = tokenizar(leer(os.path.join(RAIZ, rel)))
    return _TOKENS[rel]


def fuentes():
    """Los `.t` de las bases, como rutas relativas al repo."""
    out = []
    for base in BASES:
        raiz_base = os.path.join(RAIZ, base)
        for dirpath, dirnames, nombres in os.walk(raiz_base):
            dirnames[:] = [d for d in dirnames if d != ".cache"]
            for nombre in sorted(nombres):
                if nombre.endswith(".t") and not nombre.startswith(".mut_fuzz"):
                    out.append(os.path.relpath(os.path.join(dirpath, nombre),
                                               RAIZ))
    return sorted(out)


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


def usos(rel):
    """`(alias, sin_alias)` de los `use` y `#importar` de `rel`.

    `#importar "x.t"` es `use "std/x.t"`. `alias` es `{alias: fichero}`;
    `sin_alias` son los ficheros importados sin `como`, cuyos nombres entran
    sin calificar."""
    alias = {}
    sin_alias = []
    toks = tokens(rel)
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.tipo == "palabra" and t.valor in ("use", "#importar") \
                and i + 1 < len(toks) and toks[i + 1].tipo == "cadena":
            pedido = toks[i + 1].valor
            if t.valor == "#importar" and not pedido.startswith("std/"):
                pedido = "std/" + pedido
            destino = resolver(rel, pedido)
            j = i + 2
            if j + 1 < len(toks) and toks[j].tipo == "ident" \
                    and toks[j].valor == "como":
                alias[toks[j + 1].valor] = destino
                j += 2
            else:
                sin_alias.append(destino)
            i = j
        else:
            i += 1
    return alias, sin_alias


def _cierra(semillas):
    """La clausura de `use` de `semillas`, entre los ficheros que existen."""
    vistos = set()
    pend = list(semillas)
    while pend:
        a = pend.pop()
        if a in vistos or not os.path.exists(os.path.join(RAIZ, a)):
            continue
        vistos.add(a)
        for destino in usos(a)[1] + list(usos(a)[0].values()):
            if destino not in vistos:
                pend.append(destino)
    return vistos


def archivos():
    """Todo lo que cubre el documento: las bases y lo que importan."""
    return sorted(_cierra(fuentes()) | _cierra([RAIZ_BINARIO]))


def en_binario():
    """Los ficheros que entran en el binario `tcodec`."""
    return _cierra([RAIZ_BINARIO])


def funciones_de(rel):
    """Los nombres de las funciones que define `rel`."""
    defs = set()
    toks = tokens(rel)
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


def _importados_sin_alias(rel, locales):
    """`{funcion: [ficheros]}` de lo que trae sin calificar el `use` de `rel`."""
    de = {}
    for s in usos(rel)[1]:
        for fn in locales.get(s, ()):
            de.setdefault(fn, []).append(s)
    return de


def llamadas():
    """Todas las llamadas: `(archivo, funcion, archivo_del_callee, callee)`.

    `archivo_del_callee` es `None` si es del lenguaje (builtin), el mismo
    archivo si es local, o el modulo importado (de `std/` o no)."""
    comps = archivos()
    locales = {a: funciones_de(a) for a in comps}
    sin_alias_de = {a: _importados_sin_alias(a, locales) for a in comps}

    todas = []
    for a in comps:
        toks = tokens(a)
        alias = usos(a)[0]

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
                        # sin calificar: local, de un `use` sin alias, o del lenguaje
                        nombre = toks[i - 1].valor
                        if nombre in locales[a]:
                            todas.append((a, actual, a, nombre))
                        elif nombre in sin_alias_de[a]:
                            for s in sin_alias_de[a][nombre]:
                                todas.append((a, actual, s, nombre))
                        else:
                            todas.append((a, actual, None, nombre))
            i += 1

    return todas


def grafo():
    """`{archivo: {archivos a los que usa}}`."""
    nodos = set(archivos())
    salidas = {a: set() for a in nodos}

    for a in sorted(nodos):
        alias, sin_alias = usos(a)
        for destino in sin_alias + list(alias.values()):
            if destino in nodos:
                salidas[a].add(destino)

        # Las referencias calificadas `alias.algo` (llamada, tipo o funcion
        # como valor): el alias dice de que archivo viene.
        toks = tokens(a)
        for k in range(len(toks) - 2):
            if toks[k].tipo == "ident" and toks[k].valor in alias \
                    and toks[k + 1].tipo == "simbolo" \
                    and toks[k + 1].valor == "." \
                    and toks[k + 2].tipo == "ident":
                destino = alias[toks[k].valor]
                if destino in nodos:
                    salidas[a].add(destino)

    return {a: salidas.get(a, set()) for a in sorted(nodos)}


def nodo_id(rel):
    """Identificador unico para Mermaid (con la ruta entera)."""
    s = rel[:-2] if rel.endswith(".t") else rel
    return s.replace("/", "_").replace(".", "_")


def etiqueta(rel):
    """La cara del nodo: la ruta entera, para no confundir dos `tipar.t`."""
    return rel


def _marca(rel, binario):
    return "en tcodec" if rel in binario else "fuera de tcodec"


def contenido(red, binario):
    fuera = sorted(a for a in red if a not in binario)
    dentro = sorted(a for a in red if a in binario)
    lineas = [
        "# Grafo de llamadas de los `.t` del repositorio\n",
        "\n",
        "Generado por `make grafo` (`tests/grafo.py`); no se edita a mano.\n",
        "\n",
        "**Que cubre:** todos los `.t` de `ejemplos/`, `programas/` y `bench/`,\n",
        "mas los modulos de `std/` que estos importan (directa o\n",
        "transitivamente). **No cubre** los `.t` de\n",
        "`tests/` (entradas de prueba).\n",
        "\n",
        "Cada nodo es un fichero con su ruta entera, y una flecha `A --> B` dice\n",
        "que `A` usa algo de `B` (un `use` o un `#importar`, una llamada o una\n",
        "referencia calificada `alias.algo`).\n",
        "\n",
        f"**En el binario `tcodec`** ({len(dentro)} ficheros): los que se\n",
        "compilan dentro del compilador. **Fuera** ("
        f"{len(fuera)} ficheros, con el nodo punteado): programas que se\n",
        "compilan y se corren aparte; lo que llamen no se ejecuta al compilar.\n",
        "\n",
        "```mermaid\n",
        "graph TD\n",
    ]
    for rel in sorted(red):
        lineas.append(f"    {nodo_id(rel)}[\"{etiqueta(rel)}\"]\n")
    lineas.append("\n")
    for rel in sorted(red):
        for destino in sorted(red[rel]):
            lineas.append(f"    {nodo_id(rel)} --> {nodo_id(destino)}\n")
    if fuera:
        lineas.append("\n    classDef fuera fill:#eeeeee,stroke:#999999,"
                      "stroke-dasharray:4 3;\n")
        lineas.append("    class " + ",".join(nodo_id(a) for a in fuera)
                      + " fuera;\n")
    lineas.append("```\n")
    return "".join(lineas)


def etiqueta_fn(rel, fn):
    return f"{fn} ({rel})"


def indice(todas):
    """`{(archivo, funcion): {(archivo_llamante, funcion_llamante)}}`.

    Sin las del lenguaje: no se cambian desde aqui."""
    de = {}
    for ca, cf, b, fb in todas:
        if b is None:
            continue
        de.setdefault((b, fb), set()).add((ca, cf))
    return de


def contenido_indice(de, definidas, binario):
    lineas = [
        "# Índice de llamadas de los `.t` del repositorio\n",
        "\n",
        "Regenerado por `make grafo` (`tests/grafo.py`); no se edita a mano.\n",
        "\n",
        "**Que cubre:** todos los `.t` de `ejemplos/`, `programas/` y `bench/`,\n",
        "mas los modulos de `std/` que estos importan (directa o\n",
        "transitivamente). **No cubre** los `.t` de\n",
        "`tests/` (entradas de prueba): una llamada desde ahi no se ve.\n",
        "\n",
        "Para cada funcion, quien la llama. Cada nombre va con su ruta entera,\n",
        "para que `ejemplos/compilador/tipar.t` no se confunda con\n",
        "`ejemplos/compilador/lib/tipar.t`, y con `(en tcodec)` o\n",
        "`(fuera de tcodec)` segun entre o no en el binario del compilador.\n",
        "Un llamante `(fuera de tcodec)` **no se ejecuta al compilar**: una\n",
        "funcion que solo tenga llamantes de esos no esta muerta, solo no la\n",
        "toca el instrumento de cobertura. Las funciones del lenguaje\n",
        "(`copiar`, `igual`, `largo`...) no aparecen como callee.\n",
        "\n",
        "Una funcion sin llamantes dice `(nadie en lo cubierto)`, que tambien\n",
        "es lo que se sabe: nadie **de los ficheros cubiertos** la llama.\n",
        "\n",
    ]
    for b in sorted(definidas):
        lineas.append(f"## {etiqueta(b)} ({_marca(b, binario)})\n")
        for fb in sorted(definidas[b]):
            llamantes = sorted(de.get((b, fb), set()))
            if not llamantes:
                lineas.append(f"- `{fb}` ← (nadie en lo cubierto)\n")
                continue
            lista = ", ".join(
                f"`{cf}` ({ca}, {_marca(ca, binario)})" for ca, cf in llamantes)
            lineas.append(f"- `{fb}` ← {lista}\n")
        lineas.append("\n")
    return "".join(lineas)


def nodo_fn(archivo, fn):
    return f"{nodo_id(archivo)}__{fn}"


def mermaid_funciones_de(archivo, aristas_de, binario):
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
            lineas.append(f"        {nodo_fn(b, fb)}[\"{fb} · {b} · "
                          f"{_marca(b, binario)}\"]")
        lineas.append("    end")
    lineas.append("")
    for fa, b, fb in sorted(aristas_de):
        lineas.append(f"    {nodo_fn(archivo, fa)} --> {nodo_fn(b, fb)}")
    return "\n".join(lineas) + "\n"


def contenido_funciones(aristas, binario):
    por_archivo = {}
    for a, fa, b, fb in aristas:
        por_archivo.setdefault(a, []).append((fa, b, fb))
    lineas = [
        "# Grafo de funciones de los `.t` del repositorio\n",
        "\n",
        "Generado por `make grafo` (`tests/grafo.py`); no se edita a mano.\n",
        "\n",
        "**Que cubre:** todos los `.t` de `ejemplos/`, `programas/` y `bench/`,\n",
        "mas los modulos de `std/` que estos importan (directa o\n",
        "transitivamente). **No cubre** los `.t` de\n",
        "`tests/`.\n",
        "\n",
        "Un diagrama por archivo: sus funciones y las que llama de otros\n",
        "archivos (cada una con su ruta entera y si esta o no en `tcodec`). Las\n",
        "llamadas dentro del mismo archivo y las funciones del lenguaje no se\n",
        "dibujan. Para saber quien llama a una funcion, mira `docs/llamadas.md`.\n",
        "\n",
    ]
    for a in sorted(por_archivo):
        lineas.append(f"## {etiqueta(a)} ({_marca(a, binario)})\n")
        lineas.append("\n```mermaid\n")
        lineas.append(mermaid_funciones_de(a, por_archivo[a], binario))
        lineas.append("```\n")
        lineas.append("\n")
    return "".join(lineas)


def principal():
    binario = en_binario()
    red = grafo()
    todas = llamadas()
    aristas = {(a, fa, b, fb) for (a, fa, b, fb) in todas
               if b is not None and b != a}
    definidas = {a: funciones_de(a) for a in archivos()}
    de = indice(todas)
    textos = {
        SALIDA: contenido(red, binario),
        SALIDA_FUNCIONES: contenido_funciones(aristas, binario),
        SALIDA_INDICE: contenido_indice(de, definidas, binario),
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
    n_definidas = sum(len(v) for v in definidas.values())
    print(f"escrito {os.path.relpath(SALIDA, RAIZ)} "
          f"({len(red)} archivos, {n_flechas} flechas), "
          f"{os.path.relpath(SALIDA_FUNCIONES, RAIZ)} ({len(aristas)} aristas "
          f"en {len({a for a, _f, _b, _fb in aristas})} diagramas) "
          f"y {os.path.relpath(SALIDA_INDICE, RAIZ)} "
          f"({n_definidas} funciones, {len(de)} con llamantes)")


if __name__ == "__main__":
    principal()
