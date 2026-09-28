"""PROPIEDAD: que le pasa a cada valor, dicho por Tcode."""

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
)

TITULO = "que le pasa a cada valor, dicho por Tcode"


def correr(suite: Resultado) -> None:
    # Quinta capa del compilador en su propio lenguaje, y la que de verdad separa
    # a Tcode de C: quien es duenio de que memoria y donde deja de serlo. Cada
    # variable acaba en `presta`, `prestado`, `nada`, `entrega:N`, `mueve:N` o
    # `libera`, y tiene que coincidir con lo que el comprobador de Python sabe
    # decir con `--explicar`.
    #
    # No hay excepciones: todos los archivos que ambas implementaciones pueden
    # analizar deben coincidir. El conjunto queda explicito para que una futura
    # divergencia no se pueda incorporar silenciosamente como caso permitido.
    _PROPIEDAD_PENDIENTES: set[str] = set()

    def _propiedad_esperada(ruta):
        from tcode.parser import parsear as _p
        codigo, errores, comp = compilar_archivo(ruta, devolver_comp=True)
        if errores:
            return None
        # Con los enums de todo el programa: `Clase.Retorno ->` es el brazo de
        # un enum que trae otro modulo, y sin saberlo el parser no lee el
        # compilador.
        try:
            arbol = _p(open(ruta, encoding="utf-8").read(), ruta, set(),
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
            for sim in entrada["simbolos"]:
                if sim.tipo == "view":
                    d = "presta"
                elif sim.prestado:
                    d = "prestado"
                elif not comp.posee(sim.tipo):
                    d = "nada"
                elif sim.entregada_en:
                    d = f"entrega:{sim.entregada_en}"
                elif sim.movida:
                    d = f"mueve:{sim.movida_en}"
                else:
                    d = "libera"
                fuera.append(f"{nombre}\t{_escrito_c(sim.nombre)}\t"
                             f"{_legible_c(sim.tipo)}\t{d}")
        return fuera

    tmp = tempfile.mkdtemp(prefix="tcode-prop-")
    try:
        suite.total += 1
        codigo, errores = c_de_tcodec(
            os.path.join(RAIZ, "ejemplos", "compilador", "tipar.t"))
        if errores:
            suite.falla("propiedad en Tcode", "\n".join(errores))
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
                suite.falla("propiedad en Tcode compila", r.stderr[:600])
            else:
                archivos = corpus_python()
                comparados = variables = 0
                for archivo in archivos:
                    rel = os.path.relpath(archivo, RAIZ)
                    esperado = _propiedad_esperada(archivo)
                    if esperado is None:
                        continue
                    suite.total += 1
                    e = subprocess.run([binario, archivo, "--propiedad"],
                                       capture_output=True, text=True, timeout=180)
                    if "Sanitizer" in e.stderr:
                        suite.falla("propiedad en Tcode",
                                    f"{rel}: sanitizer\n{e.stderr[:400]}")
                        continue
                    dado = [linea for linea in e.stdout.splitlines() if linea.strip()]
                    coincide = dado == esperado
                    if coincide and rel in _PROPIEDAD_PENDIENTES:
                        suite.falla("propiedad en Tcode",
                                    f"{rel} ya coincide: quitalo de "
                                    f"_PROPIEDAD_PENDIENTES")
                    elif not coincide and rel not in _PROPIEDAD_PENDIENTES:
                        d = next((i for i, (a, b) in enumerate(zip(dado, esperado))
                                  if a != b), None)
                        detalle = (f"  Tcode:  {dado[d]!r}\n  Python: {esperado[d]!r}"
                                   if d is not None
                                   else f"{len(dado)} lineas contra {len(esperado)}")
                        suite.falla("propiedad en Tcode", f"{rel}:\n" + detalle)
                    elif coincide:
                        comparados += 1
                        variables += len(dado)
                # Un archivo que el parser de Python no lee se salta sin decir
                # nada; que se salten de mas lo dice este minimo.
                if comparados < 45:
                    suite.total += 1
                    suite.falla("propiedad en Tcode",
                                f"solo {comparados} archivos comparados, se esperaban "
                                f"al menos 45")
                suite.cifra("propiedad_archivos", comparados)
                suite.cifra("propiedad_variables", variables)
                print(f"    {comparados} archivos, {variables} variables, mismo "
                      f"destino que el comprobador de Python "
                      f"({len(_PROPIEDAD_PENDIENTES)} pendientes)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
