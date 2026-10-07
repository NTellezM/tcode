#!/usr/bin/env python3
"""
Rompe una regla en `tcodec`, y mira si la suite lo nota.

Solo lo pueden ver los oráculos independientes —REGLAS (pares mínimos),
RECHAZO (programas que no deben compilar) y ACEPTA (programas que tienen que
correr limpios bajo ASan)—; el replay de `tests/fuzz.py` también guarda
codegen —el hallazgo del `const const T**` es uno—, pero queda fuera por
tiempo, que son minutos más por mutación. Aquí se rompe una regla a la vez en
`comprobar.t` o en `generar.t`, y la suite tiene que fallar. Si no falla, ese
camino no lo prueba nadie.

La muestra cubre una mutación por familia de regla: propiedad y movimientos,
préstamos, mutabilidad, ámbitos, `match`/enums/structs, genéricas, cierres,
números y conversiones. No es una por regla —eso multiplicaría por tres el
tiempo—, pero ninguna familia se queda sin tocar.

    python3 tests/mutar.py                todas las mutaciones de la lista
    python3 tests/mutar.py --lista        y qué debería cazar cada una
    python3 tests/mutar.py --solo lista   solo las que lleven eso en el nombre
    python3 tests/mutar.py --trabajos 1   sin paralelismo, para mirar una

Cada mutación se aplica a una copia del árbol (sin `.git`, `.cache`, `dist`,
`contrib`), así que el repositorio no se toca, y las copias van en paralelo:
cada una construye su `tcodec` desde la semilla y corre las tres secciones.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# `contrib` son 47 MB de nodos y gramáticas: el compilador no los mira.
NO_SE_COPIA = {".git", ".cache", "dist", ".mypy_cache", ".ruff_cache",
               ".github", "contrib"}
# Las tres con oráculo propio.
SECCIONES = ["REGLAS", "RECHAZO", "ACEPTA"]

MUTACIONES = [
    {
        "nombre": "una lista vuelve a aceptar prestamos",
        "caza": "REGLAS (el par del prestamo guardado) y RECHAZO (sus cinco casos)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    if T.es_lista(t) {\n"
             "        // Guardar un prestamo pediria expresar cuanto vive lo que apunta.\n"
             "        let e = T.elemento(t);\n"
             "        return e != \"view\" && !T.es_referencia(e) && !T.es_arreglo(e)\n"
             "        && !es_prestado_st(m, e) && almacenable(m, e);\n"
             "    }",
             "    if T.es_lista(t) {\n"
             "        // Guardar un prestamo pediria expresar cuanto vive lo que apunta.\n"
             "        let e = T.elemento(t);\n"
             "        return e != \"view\" && !T.es_arreglo(e)\n"
             "        && !es_prestado_st(m, e) && almacenable(m, e);\n"
             "    }"),
        ],
    },
    {
        "nombre": "un campo de struct vuelve a guardar un `&T`",
        "caza": "REGLAS (el par del campo) y RECHAZO (el campo y la carga de enum)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "                if T.es_referencia(ct) {",
             "                if false {"),
        ],
    },
    {
        "nombre": "una vista de una vista vuelve a dar `const const T**`",
        "caza": "ACEPTA (el programa del `& &T`, que compila con -Werror)",
        "cambios": [
            ("ejemplos/compilador/lib/generar.t",
             "    if T.es_referencia(t) { return $\"{base} const*\"; }",
             "    if false { return $\"{base} const*\"; }"),
        ],
    },
    {
        "nombre": "usar lo movido deja de ser un error",
        "caza": "REGLAS (`usar lo movido`, `usar lo que se llevo una clausura`) y RECHAZO",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    c.simbolos[i].leida = true;\n"
             "    if c.simbolos[i].movida {",
             "    c.simbolos[i].leida = true;\n"
             "    if false {"),
        ],
    },
    {
        "nombre": "modificar lo prestado deja de ser un error",
        "caza": "REGLAS (`modificar lo prestado`, `redimensionar lo prestado`)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    let vivos = prestamos_vivos(c, i);\n"
             "    if vivos.largo() > 0 {\n"
             "        let por = ocupada(vivos);\n"
             "        error(c, m, linea, $\"no se puede modificar `{n}`: {por}\");",
             "    let vivos = prestamos_vivos(c, i);\n"
             "    if false {\n"
             "        let por = ocupada(vivos);\n"
             "        error(c, m, linea, $\"no se puede modificar `{n}`: {por}\");"),
        ],
    },
    {
        "nombre": "un `let` se puede volver a modificar",
        "caza": "REGLAS (el par de `modificar un let`)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    if !c.simbolos[i].mutable {\n"
             "        error_no_mutable(c, m, linea, i);\n"
             "        return;\n"
             "    }",
             "    if false {\n"
             "        error_no_mutable(c, m, linea, i);\n"
             "        return;\n"
             "    }"),
        ],
    },
    {
        "nombre": "`try` fuera de una funcion que falla deja de ser un error",
        "caza": "REGLAS (el par de `try` fuera de una funcion que falla)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "        Clase.Try -> {\n"
             "            if !c.falible {",
             "        Clase.Try -> {\n"
             "            if false {"),
        ],
    },
    {
        "nombre": "un `match` al que le faltan formas deja de ser un error",
        "caza": "REGLAS (el par de `match sin todas las formas`) y RECHAZO",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "        var a_medias: list<str> = [];\n"
             "        for v en I.lista_de(m.en_variantes, vista(base)) sino [] {\n"
             "            if !esta_entre(con_brazo, v) {\n"
             "                faltan.anadir($\"{base}.{v}\");\n"
             "            } else if !esta_entre(vistas, v) {\n"
             "                a_medias.anadir($\"{base}.{v}\");\n"
             "            }\n"
             "        }\n"
             "        if faltan.largo() > 0 {",
             "        var a_medias: list<str> = [];\n"
             "        for v en I.lista_de(m.en_variantes, vista(base)) sino [] {\n"
             "            if !esta_entre(con_brazo, v) {\n"
             "                faltan.anadir($\"{base}.{v}\");\n"
             "            } else if !esta_entre(vistas, v) {\n"
             "                a_medias.anadir($\"{base}.{v}\");\n"
             "            }\n"
             "        }\n"
             "        if false {"),
        ],
    },
    {
        "nombre": "un indice que no es `usize` deja de ser un error",
        "caza": "REGLAS (el par de `un indice que no es usize`)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    if T.conocido(ti) && !encaja(\"usize\", T.escribir_tipo(ti)) {",
             "    if false {"),
        ],
    },
    {
        "nombre": "llamar con menos argumentos deja de ser un error",
        "caza": "REGLAS (el par de `argumentos que faltan`) y RECHAZO",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    if n.hijos.largo() != f.params.largo() {",
             "    if false {"),
        ],
    },
    {
        "nombre": "mover algo de fuera dentro de un bucle deja de ser un error",
        "caza": "REGLAS (el par de `mover dentro de un bucle`)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    if c.en_bucle > c.simbolos[i].bucle_al_declarar && c.en_retorno == 0 {",
             "    if false {"),
        ],
    },
    {
        "nombre": "una condicion que no es `bool` deja de ser un error",
        "caza": "REGLAS (el par de `una condicion que no es bool`) y RECHAZO",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    let t = comprobar_expresion(c, m, tipos, s.hijos[0], \"\", false);\n"
             "    if T.conocido(t) && t.nombre != \"bool\" {\n"
             "        error(c, m, s.linea, $\"la condicion de `if` debe ser "
             "`bool`, es `{T.escribir_tipo(t)}`\");\n"
             "    }",
             "    let t = comprobar_expresion(c, m, tipos, s.hijos[0], \"\", false);\n"
             "    if false {\n"
             "        error(c, m, s.linea, $\"la condicion de `if` debe ser "
             "`bool`, es `{T.escribir_tipo(t)}`\");\n"
             "    }"),
        ],
    },
    {
        "nombre": "negar un entero sin signo deja de ser un error",
        "caza": "REGLAS (el par de `negar un entero sin signo`)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    if es_sin_signo(T.escribir_tipo(t)) {",
             "    if false {"),
        ],
    },
    {
        "nombre": "un struct puede quedarse sin campos",
        "caza": "REGLAS (el par de `un struct sin todos sus campos`)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    var faltan: list<str> = [];\n"
             "    for x en campos_nombres(m, tipo) {\n"
             "        if !esta_entre(dados, x) { faltan.anadir(copiar(x)); }\n"
             "    }\n"
             "    if faltan.largo() > 0 {",
             "    var faltan: list<str> = [];\n"
             "    for x en campos_nombres(m, tipo) {\n"
             "        if !esta_entre(dados, x) { faltan.anadir(copiar(x)); }\n"
             "    }\n"
             "    if false {"),
        ],
    },
    {
        "nombre": "un campo que no existe deja de ser un error",
        "caza": "REGLAS (el par de `un campo que no existe`)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    error(c, m, n.linea, $\"`{base}` no tiene un campo `{nombre}`\");\n"
             "    return T.ninguno();",
             "    return T.ninguno();"),
        ],
    },
    {
        "nombre": "un patron que atrapa de mas deja de ser un error",
        "caza": "REGLAS (el par de `un patron que atrapa de mas`)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    if posiciones.largo() != lleva.largo() {",
             "    if false {"),
        ],
    },
    {
        "nombre": "una forma de enum con otros valores deja de ser un error",
        "caza": "REGLAS (el par de `una forma con otros valores`)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "    if n.hijos.largo() != lleva.largo() {",
             "    if false {"),
        ],
    },
]


def _copiar(destino):
    """El árbol, sin lo que no hace falta, en `destino`."""
    shutil.copytree(RAIZ, destino, dirs_exist_ok=True, symlinks=True,
                    ignore=shutil.ignore_patterns(*NO_SE_COPIA))


def _mutar(destino, cambios):
    """Aplica la mutación entera; None si va bien, si no qué falló."""
    for ruta, viejo, nuevo in cambios:
        completa = os.path.join(destino, ruta)
        with open(completa, encoding="utf-8") as f:
            texto = f.read()
        if texto.count(viejo) != 1:
            return (f"el anclaje de `{ruta}` no está una sola vez "
                    f"({texto.count(viejo)}); la mutación se ha quedado vieja")
        with open(completa, "w", encoding="utf-8") as f:
            f.write(texto.replace(viejo, nuevo))
    return None


def _construir(destino):
    """`tcodec` desde la semilla, para saber que la mutación compila."""
    r = subprocess.run(["make", "tcodec"], cwd=destino, capture_output=True,
                       text=True, timeout=1800)
    return r.returncode == 0, (r.stderr or r.stdout)[-600:]


def _secciones(destino):
    """Las tres secciones, y cuáles se quejaron.

    Cada sección corre en su proceso y su salida sale entera cuando acaba, así
    que se cuentan todas las que traen una falla: cuál sale antes depende de
    cuál termine antes.
    """
    r = subprocess.run([sys.executable, "tests/test_lenguaje.py", *SECCIONES],
                       cwd=destino, capture_output=True, text=True, timeout=7200)
    salida = r.stdout + r.stderr
    cual, quejadas = None, []
    for linea in salida.splitlines():
        if linea.startswith("=== ") and ": " in linea:
            cual = linea[4:].split(":")[0].strip()
        elif (linea.lstrip().startswith("FALLA") and cual
                and cual not in quejadas):
            quejadas.append(cual)
    return r.returncode, quejadas, salida[-800:]


def correr(mutacion):
    """(estado, detalle): cazada, sin cazar, o la mutación no vale."""
    tmp = tempfile.mkdtemp(prefix="tcode-mutar-")
    try:
        _copiar(os.path.join(tmp, "arbol"))
        arbol = os.path.join(tmp, "arbol")
        malo = _mutar(arbol, mutacion["cambios"])
        if malo:
            return "anclaje", malo
        compila, error = _construir(arbol)
        if not compila:
            return "invalida", f"la mutación no compila:\n{error}"
        codigo, quejadas, salida = _secciones(arbol)
        if codigo == 0:
            return "sin_cazar", salida
        return "cazada", ", ".join(quejadas) or "(una seccion)"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--lista", action="store_true",
                   help="solo decir qué mutaciones hay y qué debería cazarlas")
    p.add_argument("--solo", default="",
                   help="solo las mutaciones cuyo nombre contenga esto")
    p.add_argument("--trabajos", type=int, default=min(4, os.cpu_count() or 1),
                   help="cuántas copias a la vez (por defecto, 4)")
    a = p.parse_args()

    elegidas = [m for m in MUTACIONES if a.solo in m["nombre"]]
    if a.lista:
        for m in elegidas:
            print(f"  {m['nombre']}\n      debería cazarlo: {m['caza']}")
        print(f"\n  {len(elegidas)} mutaciones")
        return 0
    if not elegidas:
        print(f"ninguna mutación lleva `{a.solo}` en el nombre", file=sys.stderr)
        return 2

    print("=== MUTAR: una regla rota en tcodec, a ver quién se queja ===")
    print(f"    secciones: {', '.join(SECCIONES)}; {a.trabajos} a la vez")
    with ThreadPoolExecutor(max_workers=a.trabajos) as ex:
        resultados = list(ex.map(correr, elegidas))

    sin_cazar = []
    for m, (estado, detalle) in zip(elegidas, resultados):
        print(f"\n  {m['nombre']}")
        if estado == "cazada":
            print(f"      cazada por {detalle}")
        elif estado == "sin_cazar":
            sin_cazar.append(m["nombre"])
            print("      NO CAZADA: ese camino no lo prueba nadie")
        elif estado == "anclaje":
            print(f"      la mutación se ha quedado vieja: {detalle}")
        else:
            print(f"      la mutación no vale: {detalle}")
    print()
    if sin_cazar:
        print("SIN CAZAR: " + "; ".join(sin_cazar), file=sys.stderr)
        return 1
    print(f"{len(elegidas)} mutaciones, todas cazadas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
