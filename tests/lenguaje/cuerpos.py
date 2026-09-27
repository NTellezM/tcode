"""CUERPOS: la funcion entera en C, escrita por Tcode."""

import glob
import os
import shutil
import subprocess
import tempfile

from compilar_c import herramienta

from tcode.cli import compilar_archivo
from tcode.generador import Generador as _Gen

from .comun import (
    RAIZ,
    RUNTIME,
    Resultado,
)

TITULO = "la funcion entera en C, escrita por Tcode"


def correr(suite: Resultado) -> None:
    # Tercera pieza del generador en su propio lenguaje, y la que de verdad
    # cuenta: la firma, el cuerpo, y los `ss_free` puestos solos donde tocan.
    # Se compara con lo que emite el generador de Python, linea por linea.
    #
    # Lo unico que se normaliza son los contadores —temporales e indices de
    # bucle—: el original los cuenta por archivo y esta capa por funcion, asi que
    # se renumeran en los dos por orden de aparicion. Todo lo demas tiene que
    # salir identico.
    #
    # Una funcion que esta capa no sabe hacer entera no se emite a medias: se
    # descarta. Se cuentan las que salen, y se exige un minimo.
    import re as _re_cuerpos

    def _normaliza_tmp(texto):
        def renumera(texto, prefijo):
            visto, n = {}, [0]
            def cambia(m):
                k = m.group(0)
                if k not in visto:
                    n[0] += 1
                    visto[k] = f"{prefijo}{n[0]}"
                return visto[k]
            return _re_cuerpos.sub(prefijo + r"\d+", cambia, texto)
        for prefijo in ("ss_tmp", "ss_i", "ss_k"):
            texto = renumera(texto, prefijo)
        return texto

    _MINIMO_CUERPOS = 420

    tmp = tempfile.mkdtemp(prefix="tcode-cuerpos-")
    try:
        suite.total += 1
        codigo, errores = compilar_archivo(
            os.path.join(RAIZ, "ejemplos", "compilador", "cuerpos.t"))
        if errores:
            suite.falla("cuerpos en Tcode", "\n".join(errores))
        else:
            ruta_c = os.path.join(tmp, "cuerpos.c")
            binario = os.path.join(tmp, "cuerpos")
            with open(ruta_c, "w", encoding="utf-8") as f:
                f.write(codigo)
            r = herramienta(
                ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
                 "-o", binario, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                suite.falla("cuerpos en Tcode compila", r.stderr[:600])
            else:
                archivos = sorted(
                    glob.glob(os.path.join(RAIZ, "std", "*.t"))
                    + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                                recursive=True))
                iguales = 0
                for archivo in archivos:
                    codigo_f, errores_f, comp = compilar_archivo(
                        archivo, devolver_comp=True)
                    if errores_f:
                        continue
                    # El comprobador guarda la ruta relativa a la raiz, y esa
                    # ruta sale en los `#line`. Para comparar hay que darle la
                    # misma al de Tcode, no la absoluta.
                    propio = os.path.relpath(archivo, RAIZ)
                    suite.total += 1
                    e = subprocess.run([binario, propio], capture_output=True,
                                       text=True, timeout=180, cwd=RAIZ)
                    if "Sanitizer" in e.stderr:
                        suite.falla("cuerpos en Tcode",
                              f"{os.path.basename(archivo)}: sanitizer\n"
                              f"{e.stderr[:400]}")
                        continue
                    # El separador va a principio de linea: el C que se compara
                    # puede llevar `@@ ` dentro de un literal —el propio
                    # `cuerpos.t` lo imprime—, y partir por cualquier aparicion
                    # cortaba la funcion por la mitad.
                    for bloque in _re_cuerpos.split(r"^@@ ", e.stdout,
                                                    flags=_re_cuerpos.M)[1:]:
                        nombre, _, cuerpo = bloque.partition("\n")
                        nombre = nombre.strip()
                        # La funcion tal como la dejo el comprobador: con los
                        # tipos deducidos puestos. Sin eso, un `var i = 0;` sin
                        # anotar no tendria tipo y el original saldria mal.
                        d = comp.funciones.get(nombre)
                        if d is None:
                            # Renombrada por el cargador. Si el mismo nombre lo
                            # declaran dos modulos, hay que quedarse con la de
                            # este archivo: la primera que aparezca puede ser la
                            # del otro, y entonces la funcion se saltaba callando.
                            candidatas = [f for k, f in comp.funciones.items()
                                          if k.endswith("__" + nombre)
                                          or k == "ss_id_" + nombre]
                            d = next((f for f in candidatas
                                      if (f.archivo or propio) == propio),
                                     candidatas[0] if candidatas else None)
                        if (d is None or (d.archivo or propio) != propio
                                or d.tipo_params):
                            continue
                        g = _Gen(comp, propio)
                        g.funcion(d)
                        esperado = _normaliza_tmp("\n".join(g.lineas)).strip()
                        dado = _normaliza_tmp(cuerpo).strip()
                        if dado == esperado:
                            iguales += 1
                        else:
                            suite.falla("cuerpos en Tcode",
                                  f"{os.path.relpath(archivo, RAIZ)} :: {nombre}\n"
                                  f"--- Tcode ---\n{dado}\n--- Python ---\n"
                                  f"{esperado}")
                if iguales < _MINIMO_CUERPOS:
                    suite.total += 1
                    suite.falla("cuerpos en Tcode",
                          f"solo {iguales} funciones enteras, se esperaban al "
                          f"menos {_MINIMO_CUERPOS}")
                suite.cifra("cuerpos", iguales)
                print(f"    {iguales} funciones enteras, mismo C que el generador "
                      f"de Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
