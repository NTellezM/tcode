"""AUTOANALISIS: el lexer y el parser en Tcode, contra los de Python."""

import glob
import os
import subprocess
import tempfile

from compilar_c import herramienta

from tcode.lexer import ErrorLexico
from tcode.parser import ErrorSintactico

from .comun import (
    RAIZ,
    RUNTIME,
    Resultado,
    c_de_tcodec,
)

TITULO = "el lexer y el parser en Tcode, contra los de Python"


def correr(suite: Resultado) -> None:
    from tcode.lexer import tokenizar as tokenizar_py

    with tempfile.TemporaryDirectory() as tmp:
        suite.total += 1
        fuente_lexer = os.path.join(RAIZ, "ejemplos", "lexer", "lexer.t")
        try:
            codigo, errores = c_de_tcodec(fuente_lexer)
        except Exception as exc:
            suite.falla("el lexer en Tcode compila", str(exc))
            codigo = None
        if codigo is None or errores:
            suite.falla("el lexer en Tcode compila", f"errores: {errores}")
        else:
            ruta_c = os.path.join(tmp, "lex.c")
            binario = os.path.join(tmp, "lex")
            with open(ruta_c, "w", encoding="utf-8") as f:
                f.write(codigo)
            r = herramienta(
                ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
                 "-o", binario, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                suite.falla("el lexer en Tcode compila", r.stderr)
            else:
                archivos = sorted(
                    glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                              recursive=True)
                    + glob.glob(os.path.join(RAIZ, "std", "*.t")))
                distintos = 0
                tokens_vistos = 0
                for archivo in archivos:
                    suite.total += 1
                    texto = open(archivo, encoding="utf-8").read()
                    esperados = tokenizar_py(texto, archivo)
                    e = subprocess.run([binario, archivo], capture_output=True,
                                       text=True, timeout=120)
                    if e.returncode != 0 or "Sanitizer" in e.stderr:
                        suite.falla("autoanalisis", f"{os.path.basename(archivo)}: "
                                              f"codigo {e.returncode}\n{e.stderr[:400]}")
                        continue
                    obtenidos = []
                    for linea in e.stdout.split("\n"):
                        if not linea:
                            continue
                        partes = linea.split("\t", 2)
                        obtenidos.append((partes[1], partes[2] if len(partes) > 2 else ""))
                    if len(obtenidos) != len(esperados):
                        suite.falla("autoanalisis",
                                    f"{os.path.basename(archivo)}: {len(obtenidos)} tokens "
                                    f"contra {len(esperados)}")
                        continue
                    # Las cadenas se comparan solo por tipo: el lexer en Tcode las
                    # deja crudas, sin resolver escapes, que es todo lo que
                    # necesita para saber donde terminan.
                    malos = [i for i, ((tp, val), t) in
                             enumerate(zip(obtenidos, esperados))
                             if tp != t.tipo or (tp not in ("cadena", "interpolada")
                                                 and val != t.valor)]
                    if malos:
                        suite.falla("autoanalisis",
                                    f"{os.path.basename(archivo)}: {len(malos)} tokens "
                                    f"distintos, el primero en la posicion {malos[0]}")
                    else:
                        tokens_vistos += len(obtenidos)
                        distintos += 1
                print(f"    {distintos} archivos, {tokens_vistos} tokens identicos")
                suite.cifra("lexer_archivos", distintos)
                suite.cifra("tokens", tokens_vistos)

                # --- el parser en Tcode, sobre los mismos archivos ---
                suite.total += 1
                from tcode.modulos import ErrorDeModulo
                from tcode.modulos import cargar as cargar_modulos
                fuente_parser = os.path.join(RAIZ, "ejemplos", "lexer", "parser.t")
                codigo_p, errores_p = c_de_tcodec(fuente_parser)
                if errores_p:
                    suite.falla("el parser en Tcode compila", f"errores: {errores_p}")
                else:
                    ruta_p = os.path.join(tmp, "par.c")
                    bin_p = os.path.join(tmp, "par")
                    with open(ruta_p, "w", encoding="utf-8") as f:
                        f.write(codigo_p)
                    r = herramienta(
                        ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra",
                         "-Werror", "-fsanitize=address,undefined",
                         "-fno-omit-frame-pointer", f"-I{RUNTIME}", ruta_p,
                         os.path.join(RUNTIME, "safestr.c"), "-o", bin_p, "-lm"],
                        capture_output=True, text=True)
                    if r.returncode != 0:
                        suite.falla("el parser en Tcode compila", r.stderr)
                    else:
                        nodos_vistos = 0
                        coinciden = 0
                        for archivo in archivos:
                            suite.total += 1
                            try:
                                cargar_modulos(archivo)
                                py_acepta = True
                            except (ErrorLexico, ErrorSintactico, ErrorDeModulo):
                                py_acepta = False
                            e = subprocess.run([bin_p, archivo, "--callado"],
                                               capture_output=True, text=True,
                                               timeout=180)
                            if "Sanitizer" in e.stderr:
                                suite.falla("el parser en Tcode",
                                            f"{os.path.basename(archivo)}: "
                                            f"sanitizer\n{e.stderr[:400]}")
                                continue
                            if (e.returncode == 0) != py_acepta:
                                suite.falla("el parser en Tcode",
                                            f"{os.path.basename(archivo)}: acepta="
                                            f"{e.returncode == 0}, el de Python="
                                            f"{py_acepta}")
                                continue
                            if e.returncode == 0:
                                nodos_vistos += int(e.stdout.split()[1])
                            coinciden += 1
                        print(f"    parser: {coinciden} archivos, "
                              f"{nodos_vistos} nodos, sin discrepancias")
                        suite.cifra("parser_archivos", coinciden)
                        suite.cifra("nodos", nodos_vistos)

                # Entradas hostiles: no puede reventar ni filtrar.
                for nombre, contenido, esperado in [
                    ("cadena sin cerrar", 'fn f() { let s: str = "abre\n', "cadena sin cerrar"),
                    ("comentario sin cerrar", "fn f() { /* abre\n", "comentario /* sin cerrar"),
                    ("byte que no es de Tcode", "fn f() { let x: usize = 1 @ 2; }\n",
                     "caracter inesperado"),
                ]:
                    suite.total += 1
                    ruta = os.path.join(tmp, "hostil.t")
                    with open(ruta, "w", encoding="utf-8") as f:
                        f.write(contenido)
                    e = subprocess.run([binario, ruta], capture_output=True,
                                       text=True, timeout=60)
                    if e.returncode == 0:
                        suite.falla(f"entrada hostil: {nombre}", "no fallo, y deberia")
                    elif esperado not in e.stderr:
                        suite.falla(f"entrada hostil: {nombre}",
                                    f"se esperaba {esperado!r}, hubo {e.stderr[:200]!r}")
                    elif "Sanitizer" in e.stderr:
                        suite.falla(f"entrada hostil: {nombre}", f"sanitizer:\n{e.stderr}")
