"""FIRMAS: la cara en C de cada funcion, dicha por Tcode."""

import glob
import os
import shutil
import subprocess
import tempfile

from compilar_c import herramienta

from tcode.cli import compilar_archivo
from tcode.generador import Generador as _Gen
from tcode.nodos import Funcion as _Fn_t

from .comun import (
    RAIZ,
    RUNTIME,
    Resultado,
    c_de_tcodec,
)

TITULO = "la cara en C de cada funcion, dicha por Tcode"


def correr(suite: Resultado) -> None:
    # Primera pieza del generador escrita en su propio lenguaje: como se llama
    # cada tipo en C y como queda la firma de cada funcion. Se compara con lo que
    # emite el generador de Python, cadena por cadena.

    def _firmas_esperadas(ruta):
        # Que funciones lleva el archivo, y en que orden, lo dice el arbol recien
        # parseado. Pero la firma se saca de la funcion que dejo el comprobador:
        # el alias con el que se escribio un tipo de otro modulo —`P.Nodo`— lo
        # resuelve el cargador y en C no queda, asi que el arbol crudo daria una
        # firma que ni siquiera compila.
        from tcode.parser import parsear as _p
        try:
            arbol = _p(open(ruta, encoding="utf-8").read(), ruta, set())
        except Exception:
            return None
        codigo, errores, comp = compilar_archivo(ruta, devolver_comp=True)
        if errores:
            return None
        propio = os.path.relpath(ruta, RAIZ)
        g = _Gen(comp, propio)
        # Una funcion de un bloque `externo` no lleva prototipo en el C
        # generado: su firma esta en su cabecera. No hay nada que comparar.
        escritas = [d.nombre for d in arbol
                    if isinstance(d, _Fn_t) and not d.tipo_params
                    and not d.externa]
        salida = []
        for nombre in escritas:
            d = comp.funciones.get(nombre)
            if d is None:
                d = next((f for k, f in comp.funciones.items()
                          if k == "ss_id_" + nombre or k.endswith("__" + nombre)),
                         None)
            if d is None:
                return None
            salida.append(g.prototipo(d))
        return salida

    tmp = tempfile.mkdtemp(prefix="tcode-firmas-")
    try:
        suite.total += 1
        codigo, errores = c_de_tcodec(
            os.path.join(RAIZ, "ejemplos", "compilador", "firmas.t"))
        if errores:
            suite.falla("firmas en Tcode", "\n".join(errores))
        else:
            ruta_c = os.path.join(tmp, "firmas.c")
            binario = os.path.join(tmp, "firmas")
            with open(ruta_c, "w", encoding="utf-8") as f:
                f.write(codigo)
            r = herramienta(
                ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
                 "-o", binario, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                suite.falla("firmas en Tcode compila", r.stderr[:600])
            else:
                archivos = sorted(
                    glob.glob(os.path.join(RAIZ, "std", "*.t"))
                    + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                                recursive=True))
                comparados = firmas = 0
                for archivo in archivos:
                    esperado = _firmas_esperadas(archivo)
                    if esperado is None:
                        continue
                    suite.total += 1
                    e = subprocess.run([binario, archivo], capture_output=True,
                                       text=True, timeout=180)
                    if "Sanitizer" in e.stderr:
                        suite.falla("firmas en Tcode",
                                    f"{os.path.basename(archivo)}: sanitizer\n"
                                    f"{e.stderr[:400]}")
                        continue
                    dado = [linea for linea in e.stdout.splitlines() if linea.strip()]
                    if dado != esperado:
                        d = next((i for i, (a, b) in enumerate(zip(dado, esperado))
                                  if a != b), None)
                        detalle = (f"  Tcode:  {dado[d]!r}\n  Python: {esperado[d]!r}"
                                   if d is not None
                                   else f"{len(dado)} firmas contra {len(esperado)}")
                        suite.falla("firmas en Tcode",
                                    f"{os.path.relpath(archivo, RAIZ)}:\n" + detalle)
                        continue
                    comparados += 1
                    firmas += len(dado)
                suite.cifra("firmas_archivos", comparados)
                suite.cifra("firmas", firmas)
                print(f"    {comparados} archivos, {firmas} firmas, mismas que el "
                      f"generador de Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
