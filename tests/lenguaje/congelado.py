"""CONGELADO: el trato con el compilador de Python, que ya no esta.

`tests/python_congelado.json` es lo que el compilador de Python congelo antes
de borrarse (`13a2fb7`, `docs/sin-oraculo.md`): las palabras reservadas, las
funciones internas con su firma, las restricciones de las genericas, los tipos
numericos y las opciones de la linea de comandos. No es un segundo compilador
—eso ya no existe—, pero si es un **segundo camino** para la superficie del
lenguaje: esas listas no las escribio `tcodec`, y compararlas con lo que
`tcodec` dice hoy convierte cualquier deriva en una falla.

La deriva que hubo **a proposito** esta escrita en `DERIVA`, una por una. Lo
que aparezca fuera de esa tabla falla: un nombre de interna que cambia de
firma, una palabra reservada que se pierde, una opcion que desaparece sin
decirlo.

Lo que **no** se compara: `nodos`, porque la representacion del arbol se
rediseño a proposito (`TIPOS.md`: los nombres y los campos son otros), y
`simbolos`, porque el lexer los reconoce por byte y no por tabla:
reconstruirlos aqui seria probar la copia, no el original.
"""

import json
import os
import re

from .comun import RAIZ, Resultado

TITULO = "el trato congelado con el compilador de Python sigue en pie"

CONGELADO = os.path.join(RAIZ, "tests", "python_congelado.json")
COMPROBAR = os.path.join(RAIZ, "ejemplos", "compilador", "lib", "comprobar.t")
LEXICO = os.path.join(RAIZ, "ejemplos", "lexer", "lib", "lexico.t")
TCODEC = os.path.join(RAIZ, "ejemplos", "compilador", "tcodec.t")

# La deriva que hubo a proposito, y solo esa.
DERIVA: dict[str, dict[str, set[str]]] = {
    "palabras": {
        # La fase C devolvio `lista`/`mapa`/`usar`/`falla` al idioma y reservo
        # los nombres en ingles; `anchor`, `drop`, `extends`, `protocol` e
        # `implements` son de las formas que se anadieron despues.
        "perdidas": {"falla", "lista", "mapa", "usar"},
        "nuevas": {"list", "map", "use", "fail", "anchor", "drop",
                   "extends", "protocol", "implements"},
    },
    "internas": {"perdidas": set(), "nuevas": {"truncar"}},
    "restricciones": {"perdidas": set(), "nuevas": set()},
    "enteros": {"perdidas": set(), "nuevas": set()},
    "decimales": {"perdidas": set(), "nuevas": set()},
    "opciones": {
        # `--optimizacion` y `--salida` son ahora `-O` y `-o`. `--sin-lineas`
        # esta en ESPECIFICACION.md y no se implemento en Tcode: queda aqui
        # como perdida conocida, no como olvido.
        "perdidas": {"--optimizacion", "--salida", "--sin-lineas"},
        "nuevas": {"--mostrar-c"},
    },
}


def _leer(ruta):
    with open(ruta, encoding="utf-8") as f:
        return f.read()


def _cuerpo(texto, firma):
    """El texto de una funcion, desde su firma hasta su llave de cierre."""
    inicio = texto.index(firma)
    return texto[inicio:texto.index("\n}\n", inicio)]


def _palabras(lexico):
    return set(re.findall(r't == "([a-z0-9_]+)"',
                          _cuerpo(lexico, "fn es_reservada(")))


def _internas(comprobar):
    """`nombre -> (params, retorno)`, leido de `firma_interna`."""
    cuerpo = _cuerpo(comprobar, "fn firma_interna(")
    salida = {}
    for bloque in re.split(r"\n    (?:else )?if nombre == ", cuerpo)[1:]:
        cabecera, resto = bloque.split("{", 1)
        nombres = re.findall(r'"(\w+)"', "if nombre == " + cabecera)
        fin = resto.find("\n    }")
        dentro = resto[:fin] if fin >= 0 else resto
        params = re.findall(r'ps\.anadir\(nuevo\("([^"]+)"\)\)', dentro)
        r = re.search(r'\br = nuevo\("([^"]+)"\)', dentro)
        for nombre in nombres:
            salida[nombre] = (params, r.group(1) if r else None)
    return salida


def _restricciones(comprobar):
    return set(re.findall(r'r == "(\w+)"',
                          _cuerpo(comprobar, "fn restriccion_admite(")))


def _numericos(comprobar):
    return set(re.findall(r'nuevo\("(\w+)"\)',
                          _cuerpo(comprobar, "fn numericos(")))


def _opciones(tcodec):
    ops = set(re.findall(r'a == "(--[\w-]+|-o)"', tcodec))
    if 'empieza_con(a, "-O")' in tcodec:
        ops.add("-O")
    return ops


def correr(suite: Resultado) -> None:
    with open(CONGELADO, encoding="utf-8") as f:
        congelado = json.load(f)
    comprobar = _leer(COMPROBAR)
    lexico = _leer(LEXICO)
    tcodec = _leer(TCODEC)

    numericos = _numericos(comprobar)
    frozen_ops = {o for o in congelado["opciones"] if o.startswith("--")}
    frozen_ops |= {"-o", "-O"} & set(congelado["opciones"])

    pares = {
        "palabras": (set(congelado["palabras"]), _palabras(lexico)),
        "restricciones": (set(congelado["restricciones"]),
                          _restricciones(comprobar)),
        "enteros": (set(congelado["enteros"]), numericos - {"f32", "f64"}),
        "decimales": (set(congelado["decimales"]), numericos & {"f32", "f64"}),
        "opciones": (frozen_ops, _opciones(tcodec)),
    }

    for clave, (frozen, actual) in pares.items():
        suite.total += 1
        deriva = DERIVA[clave]
        perdidas = frozen - actual
        nuevas = actual - frozen
        if perdidas != deriva["perdidas"] or nuevas != deriva["nuevas"]:
            suite.falla(
                f"la deriva de `{clave}` es la que se decidio",
                f"se esperaba perder {sorted(deriva['perdidas'])} y ganar "
                f"{sorted(deriva['nuevas'])}; se pierde {sorted(perdidas)} y "
                f"se gana {sorted(nuevas)}")

    # Las internas, ademas de los nombres, con su firma entera: un parametro
    # que cambia de sitio o un retorno que se pierde no lo ve nadie mas.
    suite.total += 1
    frozen_int = {k: (v["params"], v["retorno"])
                  for k, v in congelado["internas"].items()}
    actual_int = _internas(comprobar)
    cambiadas = sorted(k for k, v in frozen_int.items()
                       if actual_int.get(k) != v)
    if cambiadas:
        suite.falla(
            "las firmas congeladas de las internas son las mismas",
            "cambiaron: " + ", ".join(
                f"`{k}` ({frozen_int[k]} -> {actual_int.get(k)})"
                for k in cambiadas))

    suite.cifra("congelado_internas", len(frozen_int))
    suite.cifra("congelado_palabras", len(congelado["palabras"]))
    print(f"    {len(pares) + 1} comprobaciones: "
          f"{len(frozen_int)} firmas de internas, "
          f"{len(pares['palabras'][0])} palabras, "
          f"{len(pares['enteros'][0])} enteros y "
          f"{len(pares['decimales'][0])} decimales congelados")
