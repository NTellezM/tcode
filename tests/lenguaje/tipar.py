"""TIPAR: de que tipo es cada variable, dicho por Tcode."""

import os
import shutil
import subprocess
import tempfile

from compilar_c import herramienta

from tcode.cli import compilar_archivo
from tcode.nodos import Funcion as _Fn_t
from tcode.nombres_c import escrito as _escrito_c
from tcode.nombres_c import legible as _legible_c

from .comun import (
    RAIZ,
    RUNTIME,
    Resultado,
    c_de_tcodec,
    corpus_python,
    nombre_escrito,
    structs_escritos,
)

TITULO = "de que tipo es cada variable, dicho por Tcode"


def correr(suite: Resultado) -> None:
    # Cuarta capa del compilador escrita en su propio lenguaje, despues del
    # lexer, el parser y la capa de tipos. Se le pregunta el tipo de cada
    # variable de cada funcion del repositorio, y tiene que decir lo mismo que
    # el comprobador de Python.




    def _tipos_esperados(ruta):
        """Lo que dice el comprobador de Python, dejando fuera lo que el
    compilador se inventa: las copias de una generica, las clausuras, y los
    renombrados por chocar con una palabra de C. Nada de eso esta escrito en
    el archivo, asi que no hay nada que comparar."""
        from tcode.parser import parsear as _p
        codigo, errores, comp = compilar_archivo(ruta, devolver_comp=True)
        if errores:
            return None
        # Con los enums de todo el programa: `Clase.Retorno ->` es el brazo de
        # un enum que trae otro modulo, y sin saberlo el parser no lee el
        # compilador.
        try:
            arbol = _p(open(ruta, encoding="utf-8").read(), ruta,
                       structs_escritos(comp),
                       set(comp.enums))
        except Exception:
            return None
        propias = {d.nombre for d in arbol
                   if isinstance(d, _Fn_t) and not d.tipo_params}
        propio = os.path.relpath(ruta)
        fuera = []
        for entrada in comp.informe:
            f = entrada["funcion"]
            if (f.archivo or propio) != propio:
                continue
            nombre = nombre_escrito(f.nombre, propias)
            if nombre is None:
                continue
            # Las variables y los tipos, como estan escritos: la capa en Tcode
            # lee el arbol tal cual, sin el `ss_id_` de lo que choca con C.
            for sim in entrada["simbolos"]:
                fuera.append(f"{nombre}\t{_escrito_c(sim.nombre)}\t"
                             f"{_legible_c(sim.tipo)}")
        return fuera

    tmp = tempfile.mkdtemp(prefix="tcode-tipar-")
    try:
        suite.total += 1
        codigo, errores = c_de_tcodec(
            os.path.join(RAIZ, "ejemplos", "compilador", "tipar.t"))
        if errores:
            suite.falla("tipar en Tcode", "\n".join(errores))
        else:
            ruta_c = os.path.join(tmp, "tipar.c")
            binario = os.path.join(tmp, "tipar")
            with open(ruta_c, "w", encoding="utf-8") as f:
                f.write(codigo)
            r = herramienta(
                ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
                 "-o", binario, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                suite.falla("tipar en Tcode compila", r.stderr[:600])
            else:
                archivos = corpus_python()
                comparados = simbolos = 0
                for archivo in archivos:
                    esperado = _tipos_esperados(archivo)
                    if esperado is None:
                        continue
                    suite.total += 1
                    e = subprocess.run([binario, archivo], capture_output=True,
                                       text=True, timeout=180)
                    if "Sanitizer" in e.stderr:
                        suite.falla("tipar en Tcode",
                                    f"{os.path.basename(archivo)}: sanitizer\n"
                                    f"{e.stderr[:400]}")
                        continue
                    dado = [linea for linea in e.stdout.splitlines() if linea.strip()]
                    if dado != esperado:
                        d = next((i for i, (a, b) in enumerate(zip(dado, esperado))
                                  if a != b), None)
                        detalle = (f"  Tcode:  {dado[d]!r}\n  Python: {esperado[d]!r}"
                                   if d is not None
                                   else f"{len(dado)} lineas contra {len(esperado)}")
                        suite.falla("tipar en Tcode",
                                    f"{os.path.basename(archivo)}:\n" + detalle)
                        continue
                    comparados += 1
                    simbolos += len(dado)
                # Un archivo que el parser de Python no lee se salta sin decir
                # nada; que se salten de mas lo dice este minimo.
                if comparados < 52:
                    suite.total += 1
                    suite.falla("tipar en Tcode",
                                f"solo {comparados} archivos comparados, se esperaban "
                                f"al menos 52")
                suite.cifra("tipar_archivos", comparados)
                suite.cifra("tipar_variables", simbolos)
                print(f"    {comparados} archivos, {simbolos} variables, "
                      f"mismos tipos que el comprobador de Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
