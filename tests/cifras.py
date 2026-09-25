#!/usr/bin/env python3
"""
Las cifras del README, medidas en vez de escritas a mano.

El README cuenta cosas que cambian con el codigo: cuantos tokens compara la
suite, cuantas lineas tiene el compilador escrito en Tcode, que imprime el
lexer sobre su propio fuente. Escritas a mano se quedaban viejas: decia
15.690 lineas de Tcode cuando ya habia 17.421. Aqui cada una lleva una marca
en el README, que no se ve al leerlo, y este programa pone lo que mide:

    **<!--c:tokens-->169.017<!--/c--> tokens identicos**

Un bloque de codigo entero se marca en la linea de encima:

    <!--c:bloque:check-->
    ```
    ...
    ```

Las de la suite salen de `.cifras.json`, que escriben `test_lenguaje.py` y
`test_propiedades.py` cuando corren enteros. Las demas se miden aqui: lineas
de codigo, modulos de la biblioteca, y la salida de dos ejemplos.

    python3 tests/cifras.py               pone las cifras en el README
    python3 tests/cifras.py --comprobar   dice cuales estan viejas, y falla
"""

import json
import os
import re
import subprocess
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README = os.path.join(RAIZ, "README.md")
GUARDADAS = os.path.join(RAIZ, ".cifras.json")
RUNTIME = os.path.join(RAIZ, "runtime")

MARCA = re.compile(r"<!--c:([a-z_]+)-->(.*?)<!--/c-->", re.S)
BLOQUE = re.compile(r"<!--c:bloque:([a-z_]+)-->\n```\n(.*?)```", re.S)


def guardar(parte, cifras):
    """Lo que midio una de las suites, junto a lo que midio la otra."""
    todo = {}
    try:
        with open(GUARDADAS, encoding="utf-8") as f:
            todo = json.load(f)
    except (OSError, ValueError):
        pass
    todo[parte] = cifras
    with open(GUARDADAS, "w", encoding="utf-8") as f:
        json.dump(todo, f, indent=1, sort_keys=True)
        f.write("\n")


# ---------- lo que se mide aqui ----------

def lineas(*rutas):
    return sum(sum(1 for _ in open(os.path.join(RAIZ, r), encoding="utf-8"))
               for r in rutas)


def compilador_en_tcode():
    lib = os.path.join("ejemplos", "compilador", "lib")
    return ([os.path.join("ejemplos", "lexer", "lib", "lexico.t"),
             os.path.join("ejemplos", "lexer", "lib", "sintaxis.t"),
             os.path.join("ejemplos", "compilador", "tcodec.t")]
            + sorted(os.path.join(lib, x) for x in os.listdir(os.path.join(RAIZ, lib))
                     if x.endswith(".t")))


def biblioteca():
    return sorted(x[:-2] for x in os.listdir(os.path.join(RAIZ, "std"))
                  if x.endswith(".t"))


def salida_de(programa, *args):
    """Lo que imprime un ejemplo, compilado sin sanitizers y corrido desde la
    raiz, como en el README."""
    sys.path.insert(0, RAIZ)
    from tcode.cli import compilar_archivo
    antes = os.getcwd()
    os.chdir(RAIZ)
    try:
        codigo, errores = compilar_archivo(programa)
    finally:
        os.chdir(antes)
    if errores:
        raise SystemExit(f"cifras: {programa} no compila: {errores[0]}")
    with tempfile.TemporaryDirectory() as tmp:
        ruta_c = os.path.join(tmp, "p.c")
        binario = os.path.join(tmp, "p")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(["cc", "-std=c17", "-O1", f"-I{RUNTIME}", ruta_c,
                            os.path.join(RUNTIME, "safestr.c"), "-o", binario,
                            "-lm"], capture_output=True, text=True)
        if r.returncode != 0:
            raise SystemExit(f"cifras: el C de {programa} no compila:\n{r.stderr}")
        e = subprocess.run([binario, *args], capture_output=True, text=True,
                           cwd=RAIZ)
        return e.stdout


def medidas():
    """Las cifras que no hace falta correr la suite para saber."""
    std = biblioteca()
    nombres = [f"`std/{x}`" for x in std]
    lexer = os.path.join("ejemplos", "lexer", "lexer.t")
    parser = os.path.join("ejemplos", "lexer", "parser.t")
    orden_lexer = "./ejemplos/lexer/lexer ejemplos/lexer/lib/lexico.t --contar"
    orden_parser = "./ejemplos/lexer/parser ejemplos/lexer/parser.t --callado"
    return {
        "lineas_tcodec": lineas(*compilador_en_tcode()),
        "lineas_sintaxis": lineas(os.path.join("ejemplos", "lexer", "lib", "sintaxis.t")),
        "lineas_comprobar": lineas(os.path.join("ejemplos", "compilador", "lib",
                                                "comprobar.t")),
        "lineas_sistema": lineas(os.path.join("ejemplos", "compilador", "lib",
                                              "sistema_tcodec.c")),
        "std_modulos": len(std),
        "std_lineas": lineas(*(os.path.join("std", x + ".t") for x in std)),
        "std_lista": ", ".join(nombres[:-1]) + " y " + nombres[-1],
        "bloque:lexer": f"$ {orden_lexer}\n"
                        + salida_de(lexer, os.path.join("ejemplos", "lexer", "lib",
                                                        "lexico.t"), "--contar"),
        "bloque:parser": f"$ {orden_parser}\n"
                         + salida_de(parser, os.path.join("ejemplos", "lexer",
                                                          "parser.t"), "--callado"),
    }


# ---------- como se escriben ----------

def miles(n):
    """`169017` -> `169.017`, como se escriben los numeros en el README."""
    return f"{n:,}".replace(",", ".")


def texto(clave, valor):
    if clave == "punto_fijo_bytes":
        return f"{valor / 1e6:.2f}".replace(".", ",")
    if isinstance(valor, int):
        return miles(valor)
    return str(valor)


def todas():
    try:
        with open(GUARDADAS, encoding="utf-8") as f:
            guardadas = json.load(f)
    except (OSError, ValueError):
        raise SystemExit("cifras: no hay `.cifras.json`; corre antes `make check`, "
                         "que la escribe")
    valores = {}
    for parte in ("lenguaje", "propiedades"):
        if parte not in guardadas:
            raise SystemExit(f"cifras: `.cifras.json` no tiene lo de {parte}; "
                             f"corre antes `make check` entero")
        valores.update(guardadas[parte])
    valores.update(medidas())
    p = guardadas["propiedades"]
    l = guardadas["lenguaje"]
    valores["bloque:check"] = (
        "$ make check\n"
        f"{l['casos']} casos, 0 fallas\n"
        f"{p['comprobaciones']} comprobaciones sobre {p['programas']} programas, 0 fallas\n")
    return valores


def poner(readme, valores):
    """El README con las cifras puestas, y lo que cambio: (clave, antes,
    ahora)."""
    cambios = []

    def marca(m):
        clave = m.group(1)
        if clave not in valores:
            raise SystemExit(f"cifras: el README pide `{clave}` y no se mide")
        nuevo = texto(clave, valores[clave])
        if nuevo != m.group(2):
            cambios.append((clave, m.group(2), nuevo))
        return f"<!--c:{clave}-->{nuevo}<!--/c-->"

    def bloque(m):
        clave = "bloque:" + m.group(1)
        if clave not in valores:
            raise SystemExit(f"cifras: el README pide `{clave}` y no se mide")
        nuevo = valores[clave]
        if nuevo != m.group(2):
            # De un bloque basta con la primera linea que cambia.
            viejas, nuevas = m.group(2).split("\n"), nuevo.split("\n")
            k = next((i for i, (a, b) in enumerate(zip(viejas, nuevas)) if a != b),
                     min(len(viejas), len(nuevas)) - 1)
            cambios.append((clave, viejas[k], nuevas[k]))
        return f"<!--c:{clave}-->\n```\n{nuevo}```"

    return BLOQUE.sub(bloque, MARCA.sub(marca, readme)), cambios


def main():
    comprobar = "--comprobar" in sys.argv[1:]
    with open(README, encoding="utf-8") as f:
        readme = f.read()
    nuevo, cambios = poner(readme, todas())
    cuantas = len(MARCA.findall(readme)) + len(BLOQUE.findall(readme))
    if comprobar:
        print("=== CIFRAS: el README dice lo que mide la suite ===")
        for clave, antes, ahora in cambios:
            print(f"  FALLA: el README dice {antes!r} y se mide {ahora!r} ({clave})")
        if cambios:
            print("         arreglalo con `make cifras`")
            return 1
        print(f"    {cuantas} cifras, todas al dia")
        return 0
    if nuevo != readme:
        with open(README, "w", encoding="utf-8") as f:
            f.write(nuevo)
    print(f"{len(cambios)} de {cuantas} cifras cambiadas en el README")
    return 0


if __name__ == "__main__":
    sys.exit(main())
