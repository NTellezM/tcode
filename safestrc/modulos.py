"""
Carga de modulos.

Un archivo es un modulo. `usar "ruta.sfs";` trae sus declaraciones, con las
rutas relativas al archivo que las escribe. Cada modulo se carga una sola vez
aunque lo pidan varios, y las dependencias circulares se detectan y se
explican en vez de colgar el compilador.

En v0 no hay espacios de nombres: lo que trae un `usar` entra al mismo saco.
Dos funciones con el mismo nombre en dos modulos es un error, y el mensaje
dice en que archivos estan.
"""

import os

from safestrc.parser import parsear
from safestrc.nodos import Usar


class ErrorDeModulo(Exception):
    pass


def cargar(ruta_principal):
    """Devuelve las declaraciones de todos los modulos, dependencias primero."""
    cargados = {}
    decls = []
    pila = []

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
            raise ErrorDeModulo(f"{de}no encuentro el modulo {ruta!r}")

        with open(real, encoding="utf-8") as f:
            fuente = f.read()

        # Ruta relativa al directorio de trabajo: los errores quedan cortos
        # y se pueden pinchar en el terminal.
        mostrada = os.path.relpath(real)
        if mostrada.startswith(".."):
            mostrada = real
        propias = parsear(fuente, mostrada)

        pila.append(real)
        for d in propias:
            if isinstance(d, Usar):
                base = os.path.dirname(real)
                cargar_uno(os.path.join(base, d.ruta), mostrada, d.linea)
        pila.pop()

        cargados[real] = True
        decls.extend(d for d in propias if not isinstance(d, Usar))

    cargar_uno(ruta_principal)
    return decls
