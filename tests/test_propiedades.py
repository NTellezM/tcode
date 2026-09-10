#!/usr/bin/env python3
"""
Tests por propiedad de Tcode.

Los de test_lenguaje.py son por ejemplo: este programa da esta salida. Solo
encuentran lo que a uno se le ocurrio escribir. Estos comprueban invariantes
sobre programas generados al azar, que es lo que encuentra lo que no se le
ocurrio a nadie.

La idea sale de los tests de ~/Proyectos/ntvidia, que en vez de casos
concretos afirman propiedades del modelo: `no_starvation`, `sigma_bounds`,
`ordering_property`, `decay_eventually_drops`.

Las cinco propiedades:

  P1  Todo programa aceptado genera C que el compilador de C acepta con
      -Wall -Wextra -Werror. Si no, el fallo es del compilador de Tcode.
  P2  Todo programa aceptado corre limpio bajo AddressSanitizer y
      UndefinedBehaviorSanitizer: ni fugas, ni doble free, ni uso tras
      liberar. Esta es la promesa central del lenguaje.
  P3  Compilar dos veces da C byte a byte identico.
  P4  Todo error nombra un archivo y una linea que existen de verdad.
  P5  El compilador nunca revienta: ni una excepcion de Python se escapa,
      con entrada valida o invalida.
  P6  `--explicar` funciona sobre todo programa aceptado, y nombra todas sus
      funciones y variables. Es el modelo del compilador hecho visible: si
      deja de cuadrar, el fallo esta en el analisis.
"""

import os
import random
import shutil
import subprocess
import sys
import tempfile
import traceback

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)
sys.path.insert(0, os.path.join(RAIZ, "tests"))

from tcode.cli import compilar_a_c
from tcode.explicar import explicar
from tcode.lexer import ErrorLexico
from tcode.parser import ErrorSintactico
from generador_programas import generar

RUNTIME = os.path.join(RAIZ, "runtime")
CUANTOS = int(os.environ.get("TCODE_PROGRAMAS", "60"))

fallos = 0
total = 0


def falla(propiedad, semilla, detalle, fuente=None):
    global fallos
    fallos += 1
    print(f"  FALLA [{propiedad}] semilla={semilla}")
    for linea in detalle.strip().split("\n")[:12]:
        print(f"         {linea}")
    if fuente is not None:
        ruta = os.path.join(tempfile.gettempdir(), f"tcode_falla_{semilla}.t")
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(fuente)
        print(f"         programa guardado en {ruta}")


def probar_programa(semilla, tmp):
    """P1, P2, P3 y P5 sobre un programa generado."""
    global total
    fuente = generar(semilla)
    nombre = f"p{semilla}"

    # P5: compilar no puede lanzar una excepcion
    total += 1
    try:
        codigo, errores, comp = compilar_a_c(fuente, nombre + ".t",
                                             devolver_comp=True)
    except (ErrorLexico, ErrorSintactico) as exc:
        falla("P5 no revienta", semilla,
              f"el generador produjo algo que no parsea: {exc}", fuente)
        return
    except Exception:
        falla("P5 no revienta", semilla, traceback.format_exc(), fuente)
        return

    if errores:
        falla("P5 no revienta", semilla,
              "el generador produjo un programa que no compila:\n"
              + "\n".join(errores), fuente)
        return

    # P6: se puede explicar, y nombra lo que hay
    total += 1
    try:
        texto = explicar(comp, nombre + ".t")
    except Exception:
        falla("P6 explicable", semilla, traceback.format_exc(), fuente)
        return
    faltan = [f.nombre for f in comp.informe and
              [e["funcion"] for e in comp.informe] or []
              if f"fn {f.nombre}(" not in texto]
    if faltan:
        falla("P6 explicable", semilla,
              f"--explicar no nombra: {', '.join(faltan)}", fuente)
    sin_nombrar = [s_.nombre for e in comp.informe for s_ in e["simbolos"]
                   if f" {s_.nombre} " not in texto and f" {s_.nombre}  " not in texto]
    if sin_nombrar:
        falla("P6 explicable", semilla,
              f"--explicar no nombra las variables: "
              f"{', '.join(sorted(set(sin_nombrar))[:6])}", fuente)

    # P3: el compilador es determinista
    total += 1
    otra, _ = compilar_a_c(fuente, nombre + ".t")[:2]
    if otra != codigo:
        falla("P3 determinista", semilla,
              "dos compilaciones del mismo fuente dan C distinto", fuente)

    ruta_c = os.path.join(tmp, nombre + ".c")
    binario = os.path.join(tmp, nombre)
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(codigo)

    # P1: el C generado compila sin un solo aviso
    total += 1
    r = subprocess.run(
        ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
         "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
         f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
         "-o", binario],
        capture_output=True, text=True)
    if r.returncode != 0:
        falla("P1 C limpio", semilla, r.stderr, fuente)
        return

    # P2: corre limpio bajo los sanitizers
    total += 1
    try:
        e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        falla("P2 memoria limpia", semilla, "el programa no termino", fuente)
        return
    if e.returncode != 0 or "Sanitizer" in e.stderr or "runtime error" in e.stderr:
        falla("P2 memoria limpia", semilla,
              f"codigo {e.returncode}\n{e.stderr}", fuente)


def probar_errores(tmp):
    """P4: todo error nombra un archivo y una linea que existen."""
    global total
    r = random.Random(99)
    malos = [
        'fn f() { var s: str = nuevo("a"); let v: view = vista(s);\n'
        ' empujar(s, "b"); }',
        'fn f() { let a: usize = 1; let b: i64 = 2;\n let c: usize = a + b; }',
        'struct P { v: view }',
        'fn f() -> view { var s: str = nuevo("h");\n return vista(s); }',
        'fn f() -> usize ! { falla "x"; }\nfn g() -> usize { return f(); }',
        'fn f() { let a: [usize; 2] = [1,2];\n let b: bool = true;\n'
        ' imprimir(a[b]); }',
        'struct P { n: str } fn g(p: P) {}\nfn f(p: &P) { g(p); }',
        'fn f() { let n: usize = 1;\n n = 2; }',
    ]
    for i, fuente in enumerate(malos):
        total += 1
        nombre = f"malo{i}.t"
        try:
            codigo, errores = compilar_a_c(fuente, nombre)
        except (ErrorLexico, ErrorSintactico) as exc:
            errores = [str(exc)]
        except Exception:
            falla("P5 no revienta", f"malo{i}", traceback.format_exc(), fuente)
            continue

        if not errores:
            falla("P4 error ubicado", f"malo{i}", "compilo, y no deberia", fuente)
            continue

        n_lineas = len(fuente.split("\n"))
        for e in errores:
            if not e.startswith(nombre + ":"):
                falla("P4 error ubicado", f"malo{i}",
                      f"el error no nombra el archivo: {e!r}", fuente)
                continue
            resto = e[len(nombre) + 1:]
            numero = resto.split(":", 1)[0]
            if not numero.isdigit():
                falla("P4 error ubicado", f"malo{i}",
                      f"el error no trae numero de linea: {e!r}", fuente)
            elif not 1 <= int(numero) <= n_lineas:
                falla("P4 error ubicado", f"malo{i}",
                      f"linea {numero} fuera del archivo (tiene {n_lineas}): "
                      f"{e!r}", fuente)


def main():
    print(f"=== PROPIEDADES sobre {CUANTOS} programas generados ===")
    tmp = tempfile.mkdtemp(prefix="tcode-prop-")
    try:
        for semilla in range(1, CUANTOS + 1):
            probar_programa(semilla, tmp)
        probar_errores(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"\n{total} comprobaciones sobre {CUANTOS} programas, {fallos} fallas")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
