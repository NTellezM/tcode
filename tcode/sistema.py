"""Las internas que hablan con el sistema, y el C de cada una.

Aqui esta lo que no puede pasar por un bloque `externo`, porque tiene que
respetar la propiedad: lo que devuelven es un `str` de Tcode, con su
liberacion automatica, no un `char*` prestado.

Cada entrada es el cuerpo en C de una interna, y solo entra en el programa
que la usa: quien no lee la entrada no carga con el codigo de leerla.

El C vive en `runtime/sistema/*.inc`, no aqui: lo leen igual este generador
y el compilador escrito en Tcode, y asi no hay dos copias que puedan
separarse. `@RES_STR@` lo rellena el generador con el nombre del tipo
resultado; es un marcador y no un `{}` de Python para que el C se escriba
con sus llaves tal cual.

En las cinco hay una decision que no es la de C:

  - `leer_linea` crece lo que haga falta. `fgets` corta y deja el resto para
    la vuelta siguiente, que es peor que fallar porque parece que funciona;
    el `bufio.Scanner` de Go deja de leer a los 64 KB y no lo dice.
  - El fin de la entrada es un fallo, no una cadena vacia: una linea en
    blanco no es lo mismo que no haber nada.
  - `variable_entorno` distingue "no esta" de "esta vacia". `getenv` no
    puede: las dos dan algo falso.
  - Hay dos relojes y el nombre dice cual es cual. Medir una duracion con el
    de pared es el error clasico, y el `clock()` de C mide tiempo de CPU
    aunque medio mundo lo use para lo otro.
  - `azar` no tiene el sesgo de `rand() % n`, y el generador es decente
    (xoshiro256++, con un recorte sin sesgo que comparten `azar` y
    `sembrar`).
"""

import os

_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "runtime", "sistema")


def _leer(nombre):
    with open(os.path.join(_DIR, nombre + ".inc"), encoding="utf-8") as f:
        return f.read()


# nombre de la interna -> su C. `_semilla` no es una interna: es lo que
# comparten `azar` y `sembrar`, y entra si aparece cualquiera de las dos.
SISTEMA = {
    "leer_linea": _leer("leer_linea"),
    "entrada_completa": _leer("entrada_completa"),
    "variable_entorno": _leer("variable_entorno"),
    "ahora_ms": _leer("ahora_ms"),
    "monotono_ms": _leer("monotono_ms"),
    "_semilla": _leer("semilla"),
}

# Que ayudante trae cada interna. `azar` y `sembrar` comparten el mismo, y
# ninguna de las dos aparece como clave de SISTEMA porque el codigo es uno.
TRAE = {
    "leer_linea": ["leer_linea"],
    "entrada_completa": ["entrada_completa"],
    "variable_entorno": ["variable_entorno"],
    "ahora_ms": ["ahora_ms"],
    # El monotono cae en el de pared donde no haya monotono de verdad, pero
    # su C ya lleva ese respaldo dentro: no arrastra al otro.
    "monotono_ms": ["monotono_ms"],
    "azar": ["_semilla"],
    "sembrar": ["_semilla"],
}

# El orden importa: `monotono_ms` cae en el de pared si no hay monotono, y
# el sembrado sin semilla usa el reloj.
ORDEN = ["ahora_ms", "monotono_ms", "_semilla", "leer_linea",
         "entrada_completa", "variable_entorno"]
