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
  P5  El compilador nunca revienta: ni una excepcion se escapa, con entrada
      valida o invalida.
  P6  `--explicar` funciona sobre todo programa aceptado, y nombra todas sus
      funciones.
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
      bajo ASan.
  P11 Un programa de aritmetica imprime lo que tiene que imprimir, y para
      donde tiene que parar. Las demas propiedades miran que el programa
      corra limpio, no que el numero sea el bueno: `1 + x`, con
      `x: f64 = 2.5`, imprimio `3` con todas en verde. Aqui cada programa
      lleva su salida calculada aparte, con las reglas de la
      especificacion (`tests/oraculo.py`), con todos los enteros y los dos
      decimales, numeros escritos a los dos lados, conversiones, `if` como
      valor, llamadas, genericas, campos y arreglos. Una cuenta hecha solo
      de numeros escritos se hace al compilar: la que pararia el programa
      no compila, con el error que dice el oraculo.
  P13 Un prestamo dura hasta el ultimo uso de la vista. En programas que
      toman vistas, modifican a sus duenios y las usan entre `if` y bucles,
      lo que el compilador acepta corre limpio bajo ASan.
  P14 Un valor que se mueve por algunos caminos y por otros no se libera
      exactamente una vez, por cualquier camino.
"""

import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile
import traceback

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)
sys.path.insert(0, os.path.join(RAIZ, "tests"))

from generador_programas import generar, generar_modulos
from mutador import mutar
from violaciones import casos as casos_de_violacion
from oraculo import generar as generar_oraculo, cuentas_escritas
from prestamos import generar as generar_prestamos
from sentencias import CASOS as CASOS_DE_SENTENCIA

RUNTIME = os.path.join(RAIZ, "runtime")
from semilla import construir_tcodec as desde_la_semilla
from compilar_c import cc
CUANTOS = int(os.environ.get("TCODE_PROGRAMAS", "60"))

fallos = 0
total = 0
TCODEC = None


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


def bloques(texto, marca):
    """Los mensajes que empiezan por `marca` (`error: `, `aviso: `), cada uno
    con las lineas sangradas que lo siguen."""
    salida = []
    for linea in texto.splitlines():
        if linea.startswith(marca):
            salida.append(linea[len(marca):])
        elif linea.startswith("  ") and salida:
            salida[-1] += "\n" + linea
    return salida


def compilar(fuente, nombre, tmp, *opciones):
    """Escribe `fuente` como `nombre` en `tmp` y lo pasa a `tcodec`: devuelve
    `(codigo, errores, avisos)`. El C sale por la salida estandar, los
    mensajes por la de error."""
    ruta = os.path.join(tmp, nombre)
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(fuente)
    r = subprocess.run([TCODEC, nombre, "--mostrar-c", *opciones],
                       cwd=tmp, capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, TCODE_RAIZ=RAIZ))
    errores = bloques(r.stderr, "error: ")
    avisos = bloques(r.stderr, "aviso: ")
    codigo = r.stdout if r.returncode == 0 and not errores else None
    return codigo, errores, avisos


def compilar_archivo(ruta, tmp):
    """`compilar`, para un archivo que ya esta escrito."""
    with open(ruta, encoding="utf-8") as f:
        fuente = f.read()
    return compilar(fuente, os.path.basename(ruta), tmp)


def funciones_de(fuente):
    """Los nombres de las funciones que declara el fuente, en orden."""
    return re.findall(r"\bfn!?\s+([A-Za-z_][A-Za-z0-9_]*)", fuente)


def probar_programa(semilla, tmp):
    """P3, P5, P6 y P7 sobre un programa generado. Si llega hasta el C, lo
    devuelve para P1 y P2, que corren todos a la vez en `correr_programas`."""
    global total
    fuente = generar(semilla)
    nombre = f"p{semilla}"

    # P5: compilar no puede reventar el compilador
    total += 1
    try:
        codigo, errores, avisos = compilar(fuente, nombre + ".t", tmp)
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
    for a in avisos:
        if not a.startswith(nombre + ".t:"):
            falla("P7 avisos ubicados", semilla,
                  f"el aviso no nombra el archivo: {a!r}", fuente)
            break
        numero = a[len(nombre) + 3:].split(":", 1)[0]
        if not numero.isdigit() or not 1 <= int(numero) <= n_lineas:
            falla("P7 avisos ubicados", semilla,
                  f"linea fuera del archivo (tiene {n_lineas}): {a!r}", fuente)
            break

    # P6: se puede explicar, y nombra todas sus funciones
    total += 1
    try:
        r = subprocess.run([TCODEC, nombre + ".t", "--explicar"],
                           cwd=tmp, capture_output=True, text=True, timeout=300,
                           env=dict(os.environ, TCODE_RAIZ=RAIZ))
        texto = r.stdout
    except Exception:
        falla("P6 explicable", semilla, traceback.format_exc(), fuente)
        return
    faltan = [f"fn {f}(" for f in funciones_de(fuente)
              if f"fn {f}(" not in texto and f"fn {f}__" not in texto]
    if faltan:
        falla("P6 explicable", semilla,
              f"--explicar no nombra: {', '.join(faltan)}", fuente)

    # P3: el compilador es determinista
    total += 1
    otra, _, _ = compilar(fuente, nombre + ".t", tmp)
    if otra != codigo:
        falla("P3 determinista", semilla,
              "dos compilaciones del mismo fuente dan C distinto", fuente)

    ruta_c = os.path.join(tmp, nombre + ".c")
    binario = os.path.join(tmp, nombre)
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(codigo)
    return semilla, fuente, ruta_c, binario


def correr_programas(listos):
    """P1 y P2 de los programas que llegaron al C, todos a la vez: lo que
    cuesta es el compilador de C y el programa, que son otros procesos."""
    global total

    def uno(listo):
        _, _, ruta_c, binario = listo
        # P1: el C generado compila sin un solo aviso
        r = cc(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            return "P1 C limpio", r.stderr
        # P2: corre limpio bajo los sanitizers
        try:
            e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            return "P2 memoria limpia", "el programa no termino"
        if e.returncode != 0 or "Sanitizer" in e.stderr or "runtime error" in e.stderr:
            return "P2 memoria limpia", f"codigo {e.returncode}\n{e.stderr}"
        return None

    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        resultados = list(hilos.map(uno, listos))
    for (semilla, fuente, _, _), problema in zip(listos, resultados):
        total += 1
        if problema and problema[0].startswith("P1"):
            falla(problema[0], semilla, problema[1], fuente)
            continue
        total += 1
        if problema:
            falla(problema[0], semilla, problema[1], fuente)


def probar_violaciones(tmp):
    """P10: una vista no sobrevive a que su duenio se invalide."""
    global total
    buenos = []
    for nombre, malo, bueno in casos_de_violacion():
        total += 1
        try:
            _, errores, _ = compilar(malo, "malo.t", tmp)
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
            codigo, errores, _ = compilar(bueno, "bueno.t", tmp)
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
        r = cc(
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


def probar_sentencias(tmp):
    """P14: un valor que se mueve por algunos caminos y por otros no se
    libera exactamente una vez, por cualquier camino."""
    global total
    listos = []
    for i, (nombre, fuente) in enumerate(CASOS_DE_SENTENCIA):
        total += 1
        try:
            codigo, errores, _ = compilar(fuente, f"sent{i}.t", tmp)
        except Exception:
            falla("P14 compila", nombre, traceback.format_exc(), fuente)
            continue
        if errores:
            falla("P14 compila", nombre, "\n".join(errores), fuente)
            continue
        ruta_c = os.path.join(tmp, f"sent{i}.c")
        binario = os.path.join(tmp, f"sent{i}")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        listos.append((nombre, fuente, ruta_c, binario))

    def uno(listo):
        _, _, ruta_c, binario = listo
        r = cc(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            return "P14 C limpio", r.stderr
        try:
            e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            return "P14 memoria limpia", "el programa no termino"
        if e.returncode != 0 or "Sanitizer" in e.stderr or "runtime error" in e.stderr:
            return "P14 memoria limpia", f"codigo {e.returncode}\n{e.stderr}"
        return None

    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        resultados = list(hilos.map(uno, listos))
    for (nombre, fuente, _, _), problema in zip(listos, resultados):
        total += 1
        if problema:
            falla(problema[0], nombre, problema[1], fuente)


def probar_oraculo(tmp):
    """P11: la salida es la que dice el oraculo."""
    global total
    programas = []
    for semilla in range(1, CUANTOS + 1):
        fuente, salida, parada = generar_oraculo(semilla)
        ruta = os.path.join(tmp, f"o{semilla}.t")
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(fuente)
        total += 1
        try:
            codigo, errores, _ = compilar(fuente, f"o{semilla}.t", tmp)
        except Exception:
            falla("P11 el oraculo compila", semilla, traceback.format_exc(), fuente)
            continue
        if errores:
            falla("P11 el oraculo compila", semilla, "\n".join(errores), fuente)
            continue
        programas.append((semilla, fuente, ruta, codigo, salida, parada))

    def correr(semilla, fuente, ruta, codigo, salida, parada):
        problemas = []
        ruta_c = ruta[:-2] + ".c"
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        # Dos veces: con los builtins de desborde del compilador, y con la
        # version portable de `runtime/cabecera.inc`, que sin esto no se
        # ejecutaria nunca. Las dos tienen que dar lo mismo.
        for extra, cual in (([], ""), (["-DSS_LANG_SIN_BUILTINS"], " (portable)")):
            problemas += correr_binario(ruta, ruta_c, extra, cual, salida, parada)
        return problemas

    def correr_binario(ruta, ruta_c, extra, cual, salida, parada):
        problemas = []
        binario = ruta[:-2] + ("_portable" if extra else "")
        r = cc(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer", *extra,
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            return [(f"P11 C limpio{cual}", r.stderr)]
        e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
        if "Sanitizer" in e.stderr or "runtime error" in e.stderr:
            problemas.append((f"P11 memoria limpia{cual}", e.stderr))
        if e.stdout != salida:
            dados, esperados = e.stdout.splitlines(), salida.splitlines()
            for i, (x, y) in enumerate(zip(dados, esperados)):
                if x != y:
                    problemas.append((f"P11 salida correcta{cual}",
                                      f"linea {i + 1} de la salida: da {x!r}, "
                                      f"tenia que dar {y!r}"))
                    break
            else:
                problemas.append((f"P11 salida correcta{cual}",
                                  f"da {len(dados)} lineas, tenia que dar "
                                  f"{len(esperados)}\n{e.stderr[:300]}"))
        if parada:
            linea, mensaje = parada
            if e.returncode == 0 \
                    or f"{os.path.basename(ruta)}:{linea}: {mensaje}" not in e.stderr:
                problemas.append((f"P11 para donde tiene que parar{cual}",
                                  f"tenia que parar en la linea {linea}: "
                                  f"{mensaje}\ncodigo {e.returncode}: "
                                  f"{e.stderr[:300]}"))
        elif e.returncode != 0:
            problemas.append((f"P11 no para sin motivo{cual}",
                              f"codigo {e.returncode}: {e.stderr[:300]}"))
        return problemas

    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        resultados = hilos.map(lambda x: correr(*x), programas)
        for (semilla, fuente, *_), problemas in zip(programas, resultados):
            total += 1
            for propiedad, detalle in problemas:
                falla(propiedad, semilla, detalle, fuente)


def probar_cuentas_escritas(tmp):
    """P11, al compilar: una cuenta de numeros escritos que pararia el
    programa es un error, con el mensaje que dice el oraculo."""
    global total
    for semilla in range(1, 5 * CUANTOS + 1):
        fuente, esperado = cuentas_escritas(semilla)
        ruta = os.path.join(tmp, f"e{semilla}.t")
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(fuente)
        total += 1
        try:
            _, errores, _ = compilar(fuente, f"e{semilla}.t", tmp)
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


def probar_prestamos(tmp):
    """P13: lo que se acepta con prestamos hasta el ultimo uso corre limpio
    bajo ASan."""
    global total
    trabajos = []
    for semilla in range(1, 2 * CUANTOS + 1):
        fuente = generar_prestamos(semilla)
        ruta = os.path.join(tmp, f"u{semilla}.t")
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(fuente)
        total += 1
        try:
            codigo, errores, _ = compilar(fuente, f"u{semilla}.t", tmp)
        except Exception:
            falla("P13 no revienta", semilla, traceback.format_exc(), fuente)
            continue
        trabajos.append((semilla, fuente, ruta, codigo, errores))

    def correr(semilla, fuente, ruta, codigo, errores):
        if errores:
            return []
        ruta_c = ruta[:-2] + ".c"
        binario = ruta[:-2]
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = cc(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            return [("P13 C limpio", r.stderr)]
        e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
        if e.returncode != 0 or "Sanitizer" in e.stderr or "runtime error" in e.stderr:
            return [("P13 lo aceptado corre limpio",
                     f"codigo {e.returncode}\n{e.stderr}")]
        return []

    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        resultados = hilos.map(lambda x: correr(*x), trabajos)
        for (semilla, fuente, _, _, _), problemas in zip(trabajos, resultados):
            total += 1
            for nombre, detalle in problemas:
                falla(nombre, semilla, detalle, fuente)


def probar_errores(tmp):
    """P4: todo error nombra un archivo y una linea que existen."""
    global total
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
            _, errores, _ = compilar(fuente, nombre, tmp)
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


def probar_mutantes(semilla, tmp, por_programa=12):
    """P8: romper un programa valido y exigir que el compilador se porte."""
    global total
    fuente = generar(semilla)
    for k in range(por_programa):
        total += 1
        roto, descripcion = mutar(fuente, semilla * 1000 + k)
        nombre = f"m{semilla}_{k}.t"
        try:
            codigo, errores, avisos = compilar(roto, nombre, tmp)
        except Exception:
            falla("P8 no revienta", f"{semilla}/{k}",
                  f"{descripcion}\n{traceback.format_exc()}", roto)
            continue

        n_lineas = len(roto.split("\n"))
        for e in errores + avisos:
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
            with tempfile.TemporaryDirectory() as tmp2:
                ruta_c = os.path.join(tmp2, "m.c")
                with open(ruta_c, "w", encoding="utf-8") as f:
                    f.write(codigo)
                # Solo compilar, sin enlazar: un mutante puede haberse
                # quedado sin `main`, y un archivo sin `main` es un modulo
                # perfectamente valido. Lo que se comprueba aqui es que el C
                # generado sea C, no que forme un programa.
                r = subprocess.run(
                    ["cc", "-std=c17", "-O0", "-w", "-c", f"-I{RUNTIME}",
                     ruta_c, "-o", os.path.join(tmp2, "m.o")],
                    capture_output=True, text=True)
                if r.returncode != 0:
                    falla("P8 aceptado da C valido", f"{semilla}/{k}",
                          f"{descripcion}\n{r.stderr}", roto)


def probar_modulos(semilla, tmp):
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
            with open(os.path.join(raiz, "app.t"), encoding="utf-8") as f:
                app = f.read()
            codigo, errores, _ = compilar(app, "app.t", raiz)
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
        r = cc(
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
    global TCODEC, total
    print(f"=== PROPIEDADES sobre {CUANTOS} programas generados ===")
    tmp = tempfile.mkdtemp(prefix="tcode-prop-")
    try:
        # tcodec, desde su semilla, una vez para toda la pasada.
        TCODEC = desde_la_semilla(tmp, ["-std=c17", "-O1"])
        if TCODEC is None:
            print("no se pudo construir tcodec", file=sys.stderr)
            return 1

        listos = [probar_programa(semilla, tmp) for semilla in range(1, CUANTOS + 1)]
        correr_programas([x for x in listos if x])
        probar_errores(tmp)

        print("=== MODULOS GENERADOS: varios archivos, un programa ===")
        for semilla in range(1, max(4, CUANTOS // 6) + 1):
            probar_modulos(semilla, tmp)

        print("=== MUTANTES: programas rotos a proposito ===")
        for semilla in range(1, max(4, CUANTOS // 4) + 1):
            probar_mutantes(semilla, tmp)

        print("=== VIOLACIONES: una vista, su duenio invalidado, la vista usada ===")
        probar_violaciones(tmp)

        print("=== SENTENCIAS: un valor que se mueve por algunos caminos ===")
        probar_sentencias(tmp)

        print("=== ORACULO: la aritmetica da lo que tiene que dar ===")
        probar_oraculo(tmp)
        probar_cuentas_escritas(tmp)

        print("=== PRESTAMOS: una vista presta hasta su ultimo uso ===")
        probar_prestamos(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"\n{total} comprobaciones sobre {CUANTOS} programas, {fallos} fallas")
    # Solo una pasada como la de `make check` dice las cifras del README.
    if "TCODE_PROGRAMAS" not in os.environ:
        from cifras import guardar
        guardar("propiedades", {"comprobaciones": total, "programas": CUANTOS})
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
