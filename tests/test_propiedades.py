#!/usr/bin/env python3
"""
Tests por propiedad de Tcode.

Los de test_lenguaje.py son por ejemplo: este programa da esta salida. Solo
encuentran lo que a uno se le ocurrio escribir. Estos comprueban invariantes
sobre programas generados al azar, que es lo que encuentra lo que no se le
ocurrio a nadie.

En vez de casos concretos, afirman propiedades del modelo, como hacen los
tests por propiedad de cualquier otro proyecto: `no_starvation`,
`sigma_bounds`, `ordering_property`.

Las propiedades:

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
  P7  Todo aviso nombra un archivo y una linea que existen, y ningun aviso
      impide compilar.
  P9  Un programa repartido en varios archivos se comporta igual: los
      structs y las funciones cruzan de modulo a modulo, la carga en rombo no
      duplica nada, y corre limpio bajo los sanitizers.
  P8  Ante un programa ROTO, el compilador se comporta: o lo acepta, o lo
      rechaza diciendo archivo y linea. Nunca una excepcion, nunca un
      cuelgue. Es la mitad del compilador que el generador de programas
      validos no toca, y la que crece con cada construccion nueva.
  P10 Una vista no sobrevive a que su duenio se reasigne, crezca, se mueva
      o se libere, venga de donde venga: `vista`, `rebanar`, un `if` o un
      `match` que la dan, una funcion, un puntero a funcion, una clausura,
      una generica, un struct que presta, un mapa. El programa que la usa
      despues no compila; el que la deja morir antes compila y corre limpio
      bajo ASan. Los programas validos por construccion no prueban esto
      nunca, y fue donde estaban los agujeros.
  P11 Un programa de aritmetica imprime lo que tiene que imprimir, y para
      donde tiene que parar. Las demas propiedades miran que el programa
      corra limpio, no que el numero sea el bueno: `1 + x`, con
      `x: f64 = 2.5`, imprimio `3` con todas en verde. Aqui cada programa
      lleva su salida calculada aparte, en Python, con las reglas de la
      especificacion (`tests/oraculo.py`), con todos los enteros y los dos
      decimales, numeros escritos a los dos lados, conversiones, `if` como
      valor, llamadas, genericas, campos y arreglos. Y el C que escribe
      `tcodec` para ese programa es el mismo, byte a byte. Una cuenta hecha
      solo de numeros escritos se hace al compilar: la que pararia el
      programa no compila, con el error que dice el oraculo, en los dos
      compiladores; la que no, compila.
  P12 El compilador escrito en Tcode escribe, byte a byte, el mismo C que
      el de Python para todo programa generado y para cada programa valido
      de P10. Lo que uno sabe escribir y el otro no aparece aqui antes que
      en ningun ejemplo escrito a mano: asi aparecio que `tcodec` soltaba
      dos veces lo que entrega la alternativa de un `sino`.
  P13 Un prestamo dura hasta el ultimo uso de la vista. En programas que
      toman vistas, modifican a sus duenios y las usan entre `if` y bucles,
      lo que el compilador acepta corre limpio bajo ASan —si diera por
      muerta una vista que se usa, leeria memoria liberada—, y los dos
      compiladores dicen lo mismo de cada uno.
"""

import concurrent.futures
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

from tcode.cli import compilar_a_c, compilar_archivo
from tcode.explicar import explicar
from tcode.lexer import ErrorLexico
from tcode.parser import ErrorSintactico
from generador_programas import generar, generar_modulos
from mutador import mutar
from violaciones import casos as casos_de_violacion
from oraculo import generar as generar_oraculo, cuentas_escritas
from prestamos import generar as generar_prestamos

RUNTIME = os.path.join(RAIZ, "runtime")
CUANTOS = int(os.environ.get("TCODE_PROGRAMAS", "60"))
# Sin construir `tcodec`: P11 mira la salida pero no compara el C de los dos
# compiladores, y P12 no corre. Es lo que hace `make rapido`.
SIN_TCODEC = os.environ.get("TCODE_SIN_TCODEC") == "1"

fallos = 0
total = 0


def falla(propiedad, semilla, detalle, fuente=None):
    global fallos
    fallos += 1
    print(f"  FALLA [{propiedad}] semilla={semilla}")
    for linea in detalle.strip().split("\n")[:12]:
        print(f"         {linea}")
    if fuente is not None:
        seguro = str(semilla).replace("/", "_")
        ruta = os.path.join(tempfile.gettempdir(), f"tcode_falla_{seguro}.t")
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

    # P7: los avisos estan bien puestos y no impiden compilar
    total += 1
    n_lineas = len(fuente.split("\n"))
    for a in comp.avisos:
        if not a.startswith(nombre + ".t:"):
            falla("P7 avisos ubicados", semilla,
                  f"el aviso no nombra el archivo: {a!r}", fuente)
            break
        numero = a[len(nombre) + 3:].split(":", 1)[0]
        if not numero.isdigit() or not 1 <= int(numero) <= n_lineas:
            falla("P7 avisos ubicados", semilla,
                  f"linea fuera del archivo (tiene {n_lineas}): {a!r}", fuente)
            break
    if codigo is None:
        falla("P7 avisos ubicados", semilla,
              "un aviso impidio generar codigo", fuente)

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
         "-o", binario, "-lm"],
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


def probar_violaciones(tmp):
    """P10: una vista no sobrevive a que su duenio se invalide."""
    global total
    buenos = []
    for nombre, malo, bueno in casos_de_violacion():
        total += 1
        try:
            _, errores = compilar_a_c(malo, "malo.t")
        except Exception:
            falla("P10 lo colgante no compila", nombre,
                  traceback.format_exc(), malo)
            continue
        if not errores:
            falla("P10 lo colgante no compila", nombre,
                  "el compilador acepto un programa que usa una vista "
                  "despues de invalidar a su duenio", malo)
        total += 1
        try:
            codigo, errores = compilar_a_c(bueno, "bueno.t")
        except Exception:
            falla("P10 lo valido compila", nombre, traceback.format_exc(), bueno)
            continue
        if errores:
            falla("P10 lo valido compila", nombre, "\n".join(errores), bueno)
            continue
        buenos.append((nombre, codigo, bueno))

    def correr(i, nombre, codigo):
        ruta_c = os.path.join(tmp, f"v{i}.c")
        binario = os.path.join(tmp, f"v{i}")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            return r.stderr
        e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
        if e.returncode != 0 or "Sanitizer" in e.stderr or "runtime error" in e.stderr:
            return f"codigo {e.returncode}\n{e.stderr}"
        return None

    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        resultados = hilos.map(lambda x: correr(*x),
                               [(i, n, c) for i, (n, c, _) in enumerate(buenos)])
        for (nombre, _, bueno), problema in zip(buenos, resultados):
            total += 1
            if problema:
                falla("P10 lo valido corre limpio", nombre, problema, bueno)


def construir_tcodec(tmp):
    """`tcodec`, sin sanitizers: solo se le pide el C de cada programa."""
    global total
    total += 1
    antes = os.getcwd()
    try:
        os.chdir(RAIZ)
        codigo, errores = compilar_archivo(
            os.path.join("ejemplos", "compilador", "tcodec.t"))
    finally:
        os.chdir(antes)
    if errores:
        falla("P11 tcodec se construye", "tcodec", "\n".join(errores))
        return None
    ruta_c = os.path.join(tmp, "tcodec.c")
    binario = os.path.join(tmp, "tcodec")
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(codigo)
    r = subprocess.run(
        ["cc", "-std=c17", "-O1", f"-I{RUNTIME}", ruta_c,
         os.path.join(RUNTIME, "safestr.c"),
         os.path.join(RAIZ, "ejemplos", "compilador", "lib", "sistema_tcodec.c"),
         "-o", binario, "-lm"],
        capture_output=True, text=True)
    if r.returncode != 0:
        falla("P11 tcodec se construye", "tcodec", r.stderr)
        return None
    return binario


def probar_oraculo(tmp, tcodec):
    """P11: la salida es la que dice el oraculo, y `tcodec` escribe el mismo
    C que Python."""
    global total
    programas = []
    for semilla in range(1, CUANTOS + 1):
        fuente, salida, parada = generar_oraculo(semilla)
        ruta = os.path.join(tmp, f"o{semilla}.t")
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(fuente)
        total += 1
        try:
            codigo, errores = compilar_a_c(fuente, ruta)
        except Exception:
            falla("P11 el oraculo compila", semilla, traceback.format_exc(), fuente)
            continue
        if errores:
            falla("P11 el oraculo compila", semilla, "\n".join(errores), fuente)
            continue
        programas.append((semilla, fuente, ruta, codigo, salida, parada))

    def correr(semilla, fuente, ruta, codigo, salida, parada):
        problemas = []
        if tcodec:
            r = subprocess.run([tcodec, ruta, "--mostrar-c"], capture_output=True,
                               text=True, cwd=RAIZ, timeout=300,
                               env=dict(os.environ, TCODE_RAIZ="."))
            if r.stdout != codigo:
                problemas.append(("P11 mismo C en Tcode",
                                  f"tcodec escribe otro C (codigo {r.returncode})\n"
                                  + r.stderr[:400]))
        ruta_c = ruta[:-2] + ".c"
        binario = ruta[:-2]
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            return problemas + [("P11 C limpio", r.stderr)]
        e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
        if "Sanitizer" in e.stderr or "runtime error" in e.stderr:
            problemas.append(("P11 memoria limpia", e.stderr))
        if e.stdout != salida:
            dados, esperados = e.stdout.splitlines(), salida.splitlines()
            for i, (x, y) in enumerate(zip(dados, esperados)):
                if x != y:
                    problemas.append(("P11 salida correcta",
                                      f"linea {i + 1} de la salida: da {x!r}, "
                                      f"tenia que dar {y!r}"))
                    break
            else:
                problemas.append(("P11 salida correcta",
                                  f"da {len(dados)} lineas, tenia que dar "
                                  f"{len(esperados)}\n{e.stderr[:300]}"))
        if parada:
            linea, mensaje = parada
            if e.returncode == 0 or f"{ruta}:{linea}: {mensaje}" not in e.stderr:
                problemas.append(("P11 para donde tiene que parar",
                                  f"tenia que parar en la linea {linea}: "
                                  f"{mensaje}\ncodigo {e.returncode}: "
                                  f"{e.stderr[:300]}"))
        elif e.returncode != 0:
            problemas.append(("P11 no para sin motivo",
                              f"codigo {e.returncode}: {e.stderr[:300]}"))
        return problemas

    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        resultados = hilos.map(lambda x: correr(*x), programas)
        for (semilla, fuente, *_), problemas in zip(programas, resultados):
            total += 1
            for propiedad, detalle in problemas:
                falla(propiedad, semilla, detalle, fuente)


def probar_cuentas_escritas(tmp, tcodec):
    """P11, al compilar: una cuenta de numeros escritos que pararia el
    programa es un error, y el mismo en los dos compiladores."""
    global total
    trabajos = []
    for semilla in range(1, 5 * CUANTOS + 1):
        fuente, esperado = cuentas_escritas(semilla)
        ruta = os.path.join(tmp, f"e{semilla}.t")
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(fuente)
        total += 1
        try:
            _, errores = compilar_archivo(ruta)
        except Exception:
            falla("P11 cuentas escritas al compilar", semilla,
                  traceback.format_exc(), fuente)
            continue
        dicho = [x.split(".t:", 1)[1] for x in errores[:1]]
        quiero = [f"{esperado[0]}: {esperado[1]}"] if esperado else []
        if dicho != quiero:
            falla("P11 cuentas escritas al compilar", semilla,
                  f"el compilador dice {errores[:1]}, y tiene que decir {quiero}",
                  fuente)
            continue
        if tcodec:
            trabajos.append((semilla, fuente, ruta, errores))

    def comprobar(semilla, fuente, ruta, errores):
        r = subprocess.run([tcodec, ruta, "--solo-comprobar"], capture_output=True,
                           text=True, cwd=RAIZ, timeout=300,
                           env=dict(os.environ, TCODE_RAIZ="."))
        dados = [x[len("error: "):] for x in r.stderr.splitlines()
                 if x.startswith("error: ")]
        return None if dados == errores else f"tcodec dice {dados}, Python {errores}"

    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        resultados = hilos.map(lambda x: comprobar(*x), trabajos)
        for (semilla, fuente, _, _), problema in zip(trabajos, resultados):
            total += 1
            if problema:
                falla("P11 cuentas escritas, igual en Tcode", semilla, problema,
                      fuente)


def probar_prestamos(tmp, tcodec):
    """P13: lo que se acepta con prestamos hasta el ultimo uso corre limpio,
    y los dos compiladores dicen lo mismo."""
    global total
    trabajos = []
    for semilla in range(1, 2 * CUANTOS + 1):
        fuente = generar_prestamos(semilla)
        ruta = os.path.join(tmp, f"u{semilla}.t")
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(fuente)
        total += 1
        try:
            codigo, errores = compilar_archivo(ruta)
        except Exception:
            falla("P13 no revienta", semilla, traceback.format_exc(), fuente)
            continue
        trabajos.append((semilla, fuente, ruta, codigo, errores))

    def correr(semilla, fuente, ruta, codigo, errores):
        problemas = []
        if tcodec:
            r = subprocess.run([tcodec, ruta, "--solo-comprobar"],
                               capture_output=True, text=True, cwd=RAIZ,
                               timeout=300, env=dict(os.environ, TCODE_RAIZ="."))
            dados = [x[len("error: "):] for x in r.stderr.splitlines()
                     if x.startswith("error: ")]
            if dados[:1] != [e.split("\n")[0] for e in errores[:1]]:
                problemas.append(("P13 igual en Tcode",
                                  f"tcodec dice {dados[:1]}, Python {errores[:1]}"))
        if errores:
            return problemas
        ruta_c = ruta[:-2] + ".c"
        binario = ruta[:-2]
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            return problemas + [("P13 C limpio", r.stderr)]
        e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
        if e.returncode != 0 or "Sanitizer" in e.stderr or "runtime error" in e.stderr:
            problemas.append(("P13 lo aceptado corre limpio",
                              f"codigo {e.returncode}\n{e.stderr}"))
        return problemas

    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        resultados = hilos.map(lambda x: correr(*x), trabajos)
        for (semilla, fuente, _, _, _), problemas in zip(trabajos, resultados):
            total += 1
            for nombre, detalle in problemas:
                falla(nombre, semilla, detalle, fuente)


def probar_tcodec(tmp, tcodec):
    """P12: `tcodec` escribe el mismo C que Python para los programas
    generados y para los validos de P10."""
    global total
    programas = [(f"g{semilla}", generar(semilla))
                 for semilla in range(1, CUANTOS + 1)]
    programas += [(f"v{i}", bueno)
                  for i, (_, _, bueno) in enumerate(casos_de_violacion())]
    trabajos = []
    for nombre, fuente in programas:
        ruta = os.path.join(tmp, f"{nombre}_tcodec.t")
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(fuente)
        total += 1
        try:
            codigo, errores = compilar_archivo(ruta)
        except Exception:
            falla("P12 compila", nombre, traceback.format_exc(), fuente)
            continue
        if errores:
            falla("P12 compila", nombre, "\n".join(errores), fuente)
            continue
        trabajos.append((nombre, fuente, ruta, codigo))

    def escribir(nombre, fuente, ruta, codigo):
        r = subprocess.run([tcodec, ruta, "--mostrar-c"], capture_output=True,
                           text=True, cwd=RAIZ, timeout=300,
                           env=dict(os.environ, TCODE_RAIZ="."))
        if r.returncode != 0:
            return f"tcodec no lo escribe:\n{r.stderr[-400:]}"
        if r.stdout != codigo:
            dado, bueno = r.stdout.splitlines(), codigo.splitlines()
            n = next((i for i, (x, y) in enumerate(zip(dado, bueno)) if x != y),
                     min(len(dado), len(bueno)))
            return (f"linea {n + 1} del C:\n"
                    f"  Tcode:  {dado[n] if n < len(dado) else '(fin)'!r}\n"
                    f"  Python: {bueno[n] if n < len(bueno) else '(fin)'!r}")
        return None

    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        resultados = hilos.map(lambda x: escribir(*x), trabajos)
        for (nombre, fuente, _, _), problema in zip(trabajos, resultados):
            total += 1
            if problema:
                falla("P12 mismo C en Tcode", nombre, problema, fuente)


def probar_errores(tmp):
    """P4: todo error nombra un archivo y una linea que existen."""
    global total
    r = random.Random(99)
    malos = [
        'fn f() { var s: str = nuevo("a"); let v: view = vista(s);\n'
        ' empujar(s, "b"); imprimir(v); }',
        'fn f() { let a: usize = 1; let b: i64 = 2;\n let c: usize = a + b; }',
        'struct P { v: view }\nfn f() -> P { let s: str = nuevo("h");\n'
        ' return P { v: vista(s) }; }',
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


def probar_mutantes(semilla, por_programa=12):
    """P8: romper un programa valido y exigir que el compilador se porte."""
    global total
    fuente = generar(semilla)
    for k in range(por_programa):
        total += 1
        roto, descripcion = mutar(fuente, semilla * 1000 + k)
        nombre = f"m{semilla}_{k}.t"
        try:
            codigo, errores, comp = compilar_a_c(roto, nombre,
                                                 devolver_comp=True)
        except (ErrorLexico, ErrorSintactico) as exc:
            # Un error de sintaxis es una respuesta legitima, pero tiene que
            # decir donde.
            texto = str(exc)
            if not texto.startswith(nombre + ":"):
                falla("P8 rechazo con sitio", f"{semilla}/{k}",
                      f"{descripcion}\nel error no nombra el archivo: {texto!r}",
                      roto)
            continue
        except RecursionError:
            falla("P8 no revienta", f"{semilla}/{k}",
                  f"{descripcion}\nrecursion infinita en el compilador", roto)
            continue
        except Exception:
            falla("P8 no revienta", f"{semilla}/{k}",
                  f"{descripcion}\n{traceback.format_exc()}", roto)
            continue

        n_lineas = len(roto.split("\n"))
        for e in errores + (comp.avisos if comp else []):
            if not e.startswith(nombre + ":"):
                falla("P8 rechazo con sitio", f"{semilla}/{k}",
                      f"{descripcion}\nno nombra el archivo: {e!r}", roto)
                break
            numero = e[len(nombre) + 1:].split(":", 1)[0]
            if not numero.isdigit() or not 1 <= int(numero) <= n_lineas:
                falla("P8 rechazo con sitio", f"{semilla}/{k}",
                      f"{descripcion}\nlinea fuera del archivo "
                      f"(tiene {n_lineas}): {e!r}", roto)
                break

        # Si el mutante COMPILA, el C que sale tiene que compilar tambien:
        # un programa aceptado nunca puede producir C invalido.
        if not errores and codigo is not None:
            with tempfile.TemporaryDirectory() as tmp:
                ruta_c = os.path.join(tmp, "m.c")
                with open(ruta_c, "w", encoding="utf-8") as f:
                    f.write(codigo)
                # Solo compilar, sin enlazar: un mutante puede haberse
                # quedado sin `main`, y un archivo sin `main` es un modulo
                # perfectamente valido. Lo que se comprueba aqui es que el C
                # generado sea C, no que forme un programa.
                r = subprocess.run(
                    ["cc", "-std=c17", "-O0", "-w", "-c", f"-I{RUNTIME}",
                     ruta_c, "-o", os.path.join(tmp, "m.o")],
                    capture_output=True, text=True)
                if r.returncode != 0:
                    falla("P8 aceptado da C valido", f"{semilla}/{k}",
                          f"{descripcion}\n{r.stderr}", roto)


def probar_modulos(semilla):
    """P9: un programa repartido en varios archivos compila y corre igual."""
    global total
    total += 1
    archivos = generar_modulos(semilla)
    fuente = "\n".join(f"--- {k} ---\n{v}" for k, v in sorted(archivos.items()))
    raiz = tempfile.mkdtemp(prefix="tcode-mod-")
    try:
        for ruta, texto in archivos.items():
            destino = os.path.join(raiz, ruta)
            os.makedirs(os.path.dirname(destino), exist_ok=True)
            with open(destino, "w", encoding="utf-8") as f:
                f.write(texto)
        try:
            codigo, errores = compilar_archivo(os.path.join(raiz, "app.t"))
        except Exception:
            falla("P9 modulos", semilla, traceback.format_exc(), fuente)
            return
        if errores:
            falla("P9 modulos", semilla,
                  "no compila:\n" + "\n".join(errores), fuente)
            return
        ruta_c = os.path.join(raiz, "app.c")
        binario = os.path.join(raiz, "app")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla("P9 modulos", semilla, r.stderr, fuente)
            return
        e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
        if e.returncode != 0 or "Sanitizer" in e.stderr:
            falla("P9 modulos", semilla,
                  f"codigo {e.returncode}\n{e.stderr[:600]}", fuente)
    finally:
        shutil.rmtree(raiz, ignore_errors=True)


def main():
    print(f"=== PROPIEDADES sobre {CUANTOS} programas generados ===")
    tmp = tempfile.mkdtemp(prefix="tcode-prop-")
    try:
        for semilla in range(1, CUANTOS + 1):
            probar_programa(semilla, tmp)
        probar_errores(tmp)

        print("=== MODULOS GENERADOS: varios archivos, un programa ===")
        for semilla in range(1, max(4, CUANTOS // 6) + 1):
            probar_modulos(semilla)

        print("=== MUTANTES: programas rotos a proposito ===")
        for semilla in range(1, max(4, CUANTOS // 4) + 1):
            probar_mutantes(semilla)

        print("=== VIOLACIONES: una vista, su duenio invalidado, la vista usada ===")
        probar_violaciones(tmp)

        tcodec = None if SIN_TCODEC else construir_tcodec(tmp)
        print("=== ORACULO: la aritmetica da lo que tiene que dar ===")
        probar_oraculo(tmp, tcodec)
        probar_cuentas_escritas(tmp, tcodec)

        print("=== PRESTAMOS: una vista presta hasta su ultimo uso ===")
        probar_prestamos(tmp, tcodec)

        if tcodec:
            print("=== TCODEC: el compilador en Tcode escribe el mismo C ===")
            probar_tcodec(tmp, tcodec)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"\n{total} comprobaciones sobre {CUANTOS} programas, {fallos} fallas")
    # Solo una pasada como la de `make check` dice las cifras del README.
    if "TCODE_PROGRAMAS" not in os.environ and not SIN_TCODEC:
        from cifras import guardar
        guardar("propiedades", {"comprobaciones": total, "programas": CUANTOS})
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
