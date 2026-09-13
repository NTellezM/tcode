"""
Carga de modulos.

Un archivo es un modulo. `usar "ruta.t";` trae sus declaraciones, con las
rutas relativas al archivo que las escribe. Cada modulo se carga una sola vez
aunque lo pidan varios, y las dependencias circulares se detectan y se
explican en vez de colgar el compilador.

Los nombres se resuelven POR ARCHIVO, como en Python: cada archivo ve lo que
el mismo importa, y nada mas. Dos modulos pueden declarar `contar` sin
estorbarse; solo choca si un mismo archivo los trae a los dos de forma llana,
y entonces el mensaje dice en que archivos estan y como arreglarlo:

    usar "std/cuenta" como c;   ->  c.contar(xs)

El renombrado interno solo ocurre cuando un nombre lo declara mas de un
modulo. Mientras no choque, `palabras` se sigue llamando `palabras` en el C
generado, que es lo que se quiere al leerlo.
"""

import os
import re

from tcode.lexer import tokenizar
from tcode.parser import parsear
from tcode.nodos import (Usar, Struct, Funcion, Llamada, LiteralStruct,
                         Enum, EnumLit, Match)


def _solo_usar(fuente, archivo):
    """Los `usar` de un archivo, sin analizarlo entero.

    Hace falta porque las dependencias tienen que cargarse ANTES de analizar
    el archivo que las usa, y para analizarlo hacen falta sus structs.
    """
    toks = tokenizar(fuente, archivo)
    salida = []
    i = 0
    while (i + 2 < len(toks) and toks[i].tipo == "palabra"
           and toks[i].valor == "usar" and toks[i + 1].tipo == "cadena"):
        ruta, linea = toks[i + 1].valor, toks[i].linea
        i += 2
        alias = None
        if (toks[i].tipo == "ident" and toks[i].valor == "como"
                and toks[i + 1].tipo == "ident"):
            alias = toks[i + 1].valor
            i += 2
        salida.append(Usar(ruta, linea=linea, archivo=archivo, alias=alias))
        i += 1          # el `;`
    return salida


IDENTIFICADOR = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*")


def renombrar_tipo(t, mapa):
    """Cambia los nombres de struct dentro de un tipo, a cualquier hondura:
    `lista<par.Par<usize, str>>` con `par.Par -> par__Par`."""
    if not isinstance(t, str) or not mapa:
        return t
    return IDENTIFICADOR.sub(lambda m: mapa.get(m.group(0), m.group(0)), t)


def renombrar_en_arbol(nodo, mapa):
    """Aplica el mapa de nombres visibles de un archivo a todo lo suyo."""
    from dataclasses import fields, is_dataclass
    if isinstance(nodo, (list, tuple)):
        for x in nodo:
            renombrar_en_arbol(x, mapa)
        return
    if not is_dataclass(nodo):
        return
    if isinstance(nodo, (Llamada, LiteralStruct, EnumLit, Match)):
        clave = nodo.nombre if isinstance(nodo, Llamada) else nodo.tipo
        if clave in mapa:
            if isinstance(nodo, Llamada):
                nodo.nombre = mapa[clave]
            else:
                nodo.tipo = mapa[clave]
    for campo in fields(nodo):
        valor = getattr(nodo, campo.name)
        if campo.name in ("tipo", "retorno") and isinstance(valor, str):
            setattr(nodo, campo.name, renombrar_tipo(valor, mapa))
        elif campo.name != "nombre":
            renombrar_en_arbol(valor, mapa)


# Palabras que en C significan algo. En Tcode no, asi que `union` o `enum`
# son nombres legales — pero el C generado no compilaria. Se renombran todas
# de una vez: como el cambio es el mismo en todas partes, el programa
# significa exactamente lo mismo, y el mensaje de error sigue diciendo el
# nombre que se escribio.
PALABRAS_C = {
    "auto", "break", "case", "char", "const", "continue", "default", "do",
    "double", "else", "enum", "extern", "float", "for", "goto", "if",
    "inline", "int", "long", "register", "restrict", "return", "short",
    "signed", "sizeof", "static", "struct", "switch", "typedef", "union",
    "unsigned", "void", "volatile", "while",
    # `bool`, `true` y `false` NO: son de Tcode tambien, y significan lo
    # mismo en los dos lados.
    "complex", "imaginary", "noreturn", "alignas", "alignof", "thread_local",
    "static_assert", "generic",
    # de la biblioteca de C, que tambien esta incluida
    "malloc", "free", "calloc", "realloc", "memcpy", "memset", "strlen",
    "printf", "fprintf", "sprintf", "snprintf", "abort", "exit", "stdin",
    "stdout", "stderr", "main", "NULL", "size_t", "errno",
}


def renombrar_identificadores(nodo, mapa):
    """Cambia un identificador en todas partes: declaraciones, usos, campos y
    tipos. Al ser el mismo cambio en todos lados, nada mas se entera."""
    from dataclasses import fields, is_dataclass
    if isinstance(nodo, (list, tuple)):
        for x in nodo:
            renombrar_identificadores(x, mapa)
        return
    if not is_dataclass(nodo):
        return
    for campo in fields(nodo):
        valor = getattr(nodo, campo.name)
        if isinstance(valor, str):
            if campo.name in ("nombre", "variable", "clave"):
                setattr(nodo, campo.name, mapa.get(valor, valor))
            elif campo.name in ("tipo", "retorno"):
                setattr(nodo, campo.name, renombrar_tipo(valor, mapa))
        elif campo.name == "campos" and isinstance(valor, list):
            nuevos = []
            for c in valor:
                if isinstance(c, tuple) and len(c) == 2:
                    nuevos.append((mapa.get(c[0], c[0]), c[1]))
                    renombrar_identificadores(c[1], mapa)
                else:
                    renombrar_identificadores(c, mapa)
                    nuevos.append(c)
            setattr(nodo, campo.name, nuevos)
        elif campo.name == "capturas" and isinstance(valor, list):
            setattr(nodo, campo.name, [mapa.get(x, x) for x in valor])
        else:
            renombrar_identificadores(valor, mapa)


def prefijo_de(ruta):
    """Un nombre corto y legible para el modulo: `std/texto.t` -> `texto`."""
    base = os.path.splitext(os.path.basename(ruta))[0]
    return re.sub(r"[^A-Za-z0-9_]", "_", base)


class ErrorDeModulo(Exception):
    pass


# Donde vive la biblioteca estandar: junto al compilador, no junto al programa.
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ESTANDAR = os.path.join(RAIZ, "std")


def resolver(ruta, desde_dir):
    """Donde buscar un `usar`.

    `usar "std/texto"` viene de la instalacion; cualquier otra ruta es
    relativa al archivo que la escribe. La extension `.t` es opcional: se
    escribe el nombre del modulo, no el del archivo.
    """
    candidatos = [ruta, ruta + ".t"] if not ruta.endswith(".t") else [ruta]
    base = ESTANDAR if ruta.startswith("std/") else desde_dir
    recorte = 4 if ruta.startswith("std/") else 0
    for c in candidatos:
        entero = os.path.join(base, c[recorte:])
        if os.path.isfile(entero):
            return entero
    # Se devuelve el primero para que el error diga algo reconocible.
    return os.path.join(base, candidatos[0][recorte:])


def cargar(ruta_principal, nombres_bonitos=None):
    """Devuelve las declaraciones de todos los modulos, dependencias primero.

    `nombres_bonitos` se rellena con {nombre interno: como se escribio}, para
    que un error hable del nombre que la persona puso y no del renombrado.
    """
    modulos = {}        # real -> {"decls", "usars", "mostrada"}
    orden = []
    pila = []
    structs = set()
    enums = set()

    def cargar_uno(ruta, quien=None, linea=0):
        real = os.path.realpath(ruta)

        if real in pila:
            ciclo = pila[pila.index(real):] + [real]
            nombres = " -> ".join(os.path.basename(p) for p in ciclo)
            raise ErrorDeModulo(
                f"dependencia circular entre modulos: {nombres}")

        if real in modulos:
            return

        if not os.path.isfile(real):
            de = f"{quien}:{linea}: " if quien else ""
            pista = ("; los modulos de `std/` viven junto al compilador"
                     if os.sep + "std" + os.sep in ruta else "")
            raise ErrorDeModulo(
                f"{de}no encuentro el modulo {os.path.basename(ruta)!r}{pista}")

        with open(real, encoding="utf-8") as f:
            fuente = f.read()

        # Ruta relativa al directorio de trabajo: los errores quedan cortos
        # y se pueden pinchar en el terminal.
        mostrada = os.path.relpath(real)
        if mostrada.startswith(".."):
            mostrada = real

        usars = _solo_usar(fuente, mostrada)
        # Primero las dependencias: sus structs tienen que estar declarados
        # antes de analizar este archivo.
        pila.append(real)
        destinos = {}
        for d in usars:
            destino = resolver(d.ruta, os.path.dirname(real))
            cargar_uno(destino, mostrada, d.linea)
            destinos[id(d)] = os.path.realpath(destino)
        pila.pop()

        propias = parsear(fuente, mostrada, structs, enums)
        # Los nombres de tipo van juntos —un enum tambien es un tipo— pero
        # los enum ademas por separado: el archivo que los usa tiene que
        # saber que `Color.Rojo` es una forma y no el campo de una variable.
        structs.update(d.nombre for d in propias
                       if isinstance(d, (Struct, Enum)))
        enums.update(d.nombre for d in propias if isinstance(d, Enum))

        modulos[real] = {
            "decls": [d for d in propias if not isinstance(d, Usar)],
            "usars": [(d, destinos[id(d)]) for d in usars],
            "mostrada": mostrada,
        }
        orden.append(real)

    cargar_uno(os.path.realpath(ruta_principal))

    # Que declara cada modulo, y quien declara cada nombre.
    declara = {}        # real -> {nombre: declaracion}
    duenios = {}        # nombre -> [real]
    for real, m in modulos.items():
        propios = {d.nombre: d for d in m["decls"]
                   if isinstance(d, (Funcion, Struct, Enum))}
        declara[real] = propios
        for n in propios:
            duenios.setdefault(n, []).append(real)

    # Renombrar solo lo que choca: mientras `palabras` sea de un solo modulo,
    # se sigue llamando `palabras` en el C generado.
    interno = {}        # (real, nombre) -> nombre interno
    for nombre, reales in duenios.items():
        for real in reales:
            if len(reales) == 1:
                interno[(real, nombre)] = nombre
            else:
                interno[(real, nombre)] = f"{prefijo_de(real)}__{nombre}"

    # El mapa de cada archivo: lo suyo, mas lo que trae cada `usar`.
    for real, m in modulos.items():
        visible = {}
        de_donde = {}

        def anotar(clave, destino_real, nombre, nodo):
            valor = interno[(destino_real, nombre)]
            previo = visible.get(clave)
            if previo is not None and previo != valor:
                otro = modulos[de_donde[clave]]["mostrada"]
                este = modulos[destino_real]["mostrada"]
                raise ErrorDeModulo(
                    f"{m['mostrada']}:{getattr(nodo, 'linea', 0)}: `{clave}` "
                    f"llega de dos sitios, {otro} y {este}. Dale un nombre a "
                    f"uno de los dos: `usar \"...\" como algo;` y luego "
                    f"`algo.{clave}`")
            visible[clave] = valor
            de_donde[clave] = destino_real

        for nombre in declara[real]:
            anotar(nombre, real, nombre, m["decls"][0] if m["decls"] else None)
        for d, destino_real in m["usars"]:
            for nombre in declara[destino_real]:
                clave = f"{d.alias}.{nombre}" if d.alias else nombre
                anotar(clave, destino_real, nombre, d)

        # Las declaraciones propias cambian de nombre; las referencias, todas.
        renombrar_en_arbol(m["decls"], visible)
        for d in m["decls"]:
            if isinstance(d, (Funcion, Struct, Enum)):
                nuevo = interno[(real, d.nombre)]
                if nuevo != d.nombre and nombres_bonitos is not None:
                    nombres_bonitos[nuevo] = d.nombre
                d.nombre = nuevo

    decls = []
    for real in orden:
        decls.extend(modulos[real]["decls"])

    # `main` se deja en paz: es el nombre que espera el generador.
    mapa_c = {p: f"ss_id_{p}" for p in PALABRAS_C if p != "main"}
    renombrar_identificadores(decls, mapa_c)
    if nombres_bonitos is not None:
        for original, nuevo in mapa_c.items():
            nombres_bonitos[nuevo] = original
    return decls
