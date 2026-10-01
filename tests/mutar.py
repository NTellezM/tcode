#!/usr/bin/env python3
"""
Rompe una regla en los DOS compiladores, y mira si la suite lo nota.

La comparación diferencial no puede ver un fallo que los dos compiladores
comparten: escriben el mismo C malo, y comparar dos copias de lo mismo no dice
nada. Solo lo pueden ver los oráculos independientes —REGLAS (pares mínimos),
RECHAZO (programas que no deben compilar) y ACEPTA (programas que tienen que
correr limpios bajo ASan)—; el replay de `tests/fuzz.py` también guarda
codegen —el hallazgo del `const const T**` es uno—, pero queda fuera por
tiempo, que son minutos más por mutación. Aquí se rompe una regla a la vez en `comprobar.t`
y en `comprobador.py` (o en `generar.t` y `generador.py`), y la suite tiene
que fallar. Si no falla, ese camino no lo prueba nadie.

    python3 tests/mutar.py            todas las mutaciones de la lista
    python3 tests/mutar.py --lista    y qué debería cazar cada una

Cada mutación se aplica a una copia del árbol (sin `.git`, `.cache`, `dist`),
así que el repositorio no se toca. Tarda minutos: cada copia construye su
`tcodec` desde la semilla.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NO_SE_COPIA = {".git", ".cache", "dist", ".mypy_cache", ".ruff_cache", ".github"}
# Las tres que traen oráculo propio, sin comparar con el otro compilador.
SECCIONES = ["REGLAS", "RECHAZO", "ACEPTA"]

MUTACIONES = [
    {
        "nombre": "una lista vuelve a aceptar préstamos",
        "caza": "REGLAS (el par del préstamo guardado) y RECHAZO (sus cinco casos)",
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
            ("tcode/comprobador.py",
             "        if es_lista(t):\n"
             "            elem = elem_lista(t)\n"
             "            # Guardar una vista o un prestamo en una coleccion exigiria\n"
             "            # expresar cuanto vive lo que apuntan.\n"
             "            return (elem != \"view\" and not es_referencia(elem)\n"
             "                    and not es_arreglo(elem)\n"
             "                    and not self.es_prestado_st(elem) "
             "and self.tipo_existe(elem))",
             "        if es_lista(t):\n"
             "            elem = elem_lista(t)\n"
             "            # Guardar una vista o un prestamo en una coleccion exigiria\n"
             "            # expresar cuanto vive lo que apuntan.\n"
             "            return (elem != \"view\"\n"
             "                    and not es_arreglo(elem)\n"
             "                    and not self.es_prestado_st(elem) "
             "and self.tipo_existe(elem))"),
        ],
    },
    {
        "nombre": "un campo de struct vuelve a guardar un `&T`",
        "caza": "REGLAS (el par del campo) y RECHAZO (el campo y la carga de enum)",
        "cambios": [
            ("ejemplos/compilador/lib/comprobar.t",
             "                if T.es_referencia(ct) {",
             "                if false {"),
            ("tcode/comprobador.py",
             "                if es_referencia(c.tipo):",
             "                if False:"),
        ],
    },
    {
        "nombre": "una vista de una vista vuelve a dar `const const T**`",
        "caza": "ACEPTA (el programa del `& &T`, que compila con -Werror)",
        "cambios": [
            ("ejemplos/compilador/lib/generar.t",
             "    if T.es_referencia(t) { return $\"{base} const*\"; }",
             "    if false { return $\"{base} const*\"; }"),
            ("tcode/generador.py",
             "        if es_referencia(t):\n            return f\"{base} const*\"",
             "        if False:\n            return f\"{base} const*\""),
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
    a = p.parse_args()

    if a.lista:
        for m in MUTACIONES:
            print(f"  {m['nombre']}\n      debería cazarlo: {m['caza']}")
        return 0

    print("=== MUTAR: una regla rota en los DOS compiladores, a ver quién se "
          "queja ===")
    print(f"    secciones: {', '.join(SECCIONES)} (sin comparar con el otro "
          f"compilador)")
    sin_cazar = []
    for m in MUTACIONES:
        print(f"\n  {m['nombre']}")
        estado, detalle = correr(m)
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
    print(f"{len(MUTACIONES)} mutaciones, todas cazadas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
