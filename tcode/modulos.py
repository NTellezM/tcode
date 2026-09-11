"""
Carga de modulos.

Un archivo es un modulo. `usar "ruta.t";` trae sus declaraciones, con las
rutas relativas al archivo que las escribe. Cada modulo se carga una sola vez
aunque lo pidan varios, y las dependencias circulares se detectan y se
explican en vez de colgar el compilador.

En v0 no hay espacios de nombres: lo que trae un `usar` entra al mismo saco.
Dos funciones con el mismo nombre en dos modulos es un error, y el mensaje
dice en que archivos estan.
"""

import os

from tcode.lexer import tokenizar
from tcode.parser import parsear
from tcode.nodos import Usar, Struct


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
        salida.append(Usar(toks[i + 1].valor, linea=toks[i].linea,
                           archivo=archivo))
        i += 3
    return salida


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


def cargar(ruta_principal):
    """Devuelve las declaraciones de todos los modulos, dependencias primero."""
    cargados = {}
    decls = []
    pila = []
    # Nombres de struct ya vistos. Un modulo puede usar un tipo que declara
    # otro, asi que el parser tiene que conocerlos antes de leerlo.
    structs = set()

    def cargar_uno(ruta, quien=None, linea=0):
        real = os.path.realpath(ruta)

        if real in pila:
            ciclo = pila[pila.index(real):] + [real]
            nombres = " -> ".join(os.path.basename(p) for p in ciclo)
            raise ErrorDeModulo(
                f"dependencia circular entre modulos: {nombres}")

        if real in cargados:
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
        # Primero las dependencias: sus structs tienen que estar declarados
        # antes de analizar este archivo.
        pila.append(real)
        for d in _solo_usar(fuente, mostrada):
            destino = resolver(d.ruta, os.path.dirname(real))
            cargar_uno(destino, mostrada, d.linea)
        pila.pop()

        propias = parsear(fuente, mostrada, structs)
        structs.update(d.nombre for d in propias if isinstance(d, Struct))

        cargados[real] = True
        decls.extend(d for d in propias if not isinstance(d, Usar))

    cargar_uno(ruta_principal)
    return decls
