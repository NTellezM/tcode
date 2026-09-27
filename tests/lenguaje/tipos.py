"""TIPOS: la capa de tipos del comprobador, en Tcode."""

import glob
import os
import shutil
import subprocess
import tempfile

from compilar_c import herramienta

from tcode.comprobador import tipo_de_parametro as _tipo_param

from .comun import (
    RAIZ,
    RUNTIME,
    Resultado,
    c_de_tcodec,
)

TITULO = "la capa de tipos del comprobador, en Tcode"


def correr(suite: Resultado) -> None:
    # La tercera capa del compilador escrita en Tcode, despues del lexer y el
    # parser. Se le pregunta lo mismo que al comprobador de Python sobre cada
    # tipo que aparece en el repositorio, y tiene que contestar igual.
    from tcode.comprobador import Comprobador as _Comprobador
    from tcode.nodos import Funcion as _Funcion
    from tcode.nodos import Struct as _Struct

    def _tipos_python(ruta, structs_previos):
        from tcode.parser import parsear as _parsear
        arbol = _parsear(open(ruta, encoding="utf-8").read(), ruta,
                         set(structs_previos))
        c = _Comprobador(ruta)
        for d in arbol:
            if isinstance(d, _Struct):
                c.structs[d.nombre] = d
        tipos = []
        for d in arbol:
            if isinstance(d, _Struct):
                tipos += [x.tipo for x in d.campos]
            elif isinstance(d, _Funcion):
                tipos += [_tipo_param(p) for p in d.params]
                if d.retorno is not None:
                    tipos.append(d.retorno)
        return [f"{t}\t{str(c.posee(t)).lower()}\t{str(c.tipo_existe(t)).lower()}"
                for t in sorted(set(tipos))]

    tmp = tempfile.mkdtemp(prefix="tcode-tipos-")
    try:
        suite.total += 1
        codigo, errores = c_de_tcodec(
            os.path.join(RAIZ, "ejemplos", "compilador", "tipos.t"))
        if errores:
            suite.falla("la capa de tipos en Tcode", "\n".join(errores))
        else:
            ruta_c = os.path.join(tmp, "tipos.c")
            binario = os.path.join(tmp, "tipos")
            with open(ruta_c, "w", encoding="utf-8") as f:
                f.write(codigo)
            r = herramienta(
                ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
                 "-o", binario, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                suite.falla("la capa de tipos en Tcode compila", r.stderr[:600])
            else:
                archivos = sorted(
                    glob.glob(os.path.join(RAIZ, "std", "*.t"))
                    + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                                recursive=True))
                previos: set[str] = set()
                for a in archivos:
                    from tcode.parser import parsear as _p
                    try:
                        previos |= {d.nombre for d in
                                    _p(open(a, encoding="utf-8").read(), a, previos)
                                    if isinstance(d, _Struct)}
                    except Exception:
                        pass
                comparados = tipos_vistos = 0
                for archivo in archivos:
                    suite.total += 1
                    try:
                        esperado = _tipos_python(archivo, previos)
                    except Exception:
                        continue        # lo que el parser de Python no lee, no cuenta
                    e = subprocess.run([binario, archivo], capture_output=True,
                                       text=True, timeout=180)
                    if "Sanitizer" in e.stderr:
                        suite.falla("la capa de tipos en Tcode",
                                    f"{os.path.basename(archivo)}: sanitizer\n"
                                    f"{e.stderr[:400]}")
                        continue
                    salida = [linea for linea in e.stdout.splitlines() if linea.strip()]
                    if salida != esperado:
                        dif = [f"  Tcode: {a!r}\n  Python: {b!r}"
                               for a, b in zip(salida, esperado) if a != b]
                        suite.falla("la capa de tipos en Tcode",
                                    f"{os.path.basename(archivo)}: "
                                    f"{len(salida)} lineas contra {len(esperado)}\n"
                                    + "\n".join(dif[:4]))
                        continue
                    comparados += 1
                    tipos_vistos += len(salida)
                suite.cifra("tipos_archivos", comparados)
                suite.cifra("tipos", tipos_vistos)
                print(f"    {comparados} archivos, {tipos_vistos} tipos, "
                      f"mismas respuestas que el comprobador de Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
