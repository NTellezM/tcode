"""EXPRESIONES: el C de una expresion, escrito por Tcode."""

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

TITULO = "el C de una expresion, escrito por Tcode"


def correr(suite: Resultado) -> None:
    # Segunda pieza del generador en su propio lenguaje. Por cada `return <expr>`
    # del repositorio se compara el C que sale, caracter por caracter, con el que
    # emite el generador de Python.
    #
    # Lo que esta capa no sabe hacer todavia sale como `?` y no se compara: se
    # cuentan las cubiertas y se exige un minimo, que es mas honesto que decir
    # que estan todas.
    #
    # Hoy cubre literales, variables, prestamos, operadores logicos y de
    # comparacion, aritmetica comprobada, division y resto, llamadas a funciones
    # del programa, y las internas que no necesitan emitir nada aparte: `vacio`,
    # `nuevo`, `vista`, `largo`, `rebanar`, `igual` y `menor`.
    #
    # Falta lo que necesita emitir lineas propias: `byte` (guarda la vista en un
    # temporal antes de indexarla), interpolacion, `try`, clausuras y
    # colecciones.
    from tcode.nodos import Retorno as _Ret

    def _retornos(nodo, fuera):
        from dataclasses import fields as _f
        from dataclasses import is_dataclass as _isd
        if isinstance(nodo, (list, tuple)):
            for x in nodo:
                _retornos(x, fuera)
            return
        if not _isd(nodo):
            return
        if isinstance(nodo, _Ret) and nodo.valor is not None:
            fuera.append(nodo)
        for campo in _f(nodo):
            _retornos(getattr(nodo, campo.name), fuera)

    import re as _re_expr

    def _renumera_tmp(texto):
        visto, n = {}, [0]
        def cambia(m):
            k = m.group(0)
            if k not in visto:
                n[0] += 1
                visto[k] = f"ss_tmp{n[0]}"
            return visto[k]
        return _re_expr.sub(r"ss_tmp\d+", cambia, texto)

    def _expresiones_esperadas(ruta):
        from tcode import nombres_c as _nc
        from tcode.parser import parsear as _p
        try:
            arbol = _p(open(ruta, encoding="utf-8").read(), ruta, set())
        except Exception:
            return None
        # Con los nombres que chocan con C cambiados, como los deja el cargador
        # y como los lee la capa en Tcode.
        _nc.renombrar(arbol, _nc.externas(arbol) | {"main"})
        codigo, errores, comp = compilar_archivo(ruta, devolver_comp=True)
        if errores:
            return None
        fuera = []
        for d in arbol:
            if not isinstance(d, _Fn_t) or d.tipo_params:
                continue
            g = _Gen(comp, ruta)
            g.func = d
            g.vars = [{}]
            g.pila = [[]]
            for p in d.params:
                g.declarar(p.nombre, p.tipo, p.prestado, p)
            rr = []
            _retornos(d.cuerpo, rr)
            for r in rr:
                try:
                    c = g.expr(r.valor, d.retorno)
                except Exception:
                    c = "<revienta>"
                fuera.append(f"{d.nombre}\t{r.linea}\t{c}")
        return fuera

    _MINIMO_CUBIERTAS = 700

    tmp = tempfile.mkdtemp(prefix="tcode-expr-")
    try:
        suite.total += 1
        codigo, errores = c_de_tcodec(
            os.path.join(RAIZ, "ejemplos", "compilador", "expresiones.t"))
        if errores:
            suite.falla("expresiones en Tcode", "\n".join(errores))
        else:
            ruta_c = os.path.join(tmp, "expresiones.c")
            binario = os.path.join(tmp, "expresiones")
            with open(ruta_c, "w", encoding="utf-8") as f:
                f.write(codigo)
            r = herramienta(
                ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
                 "-o", binario, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                suite.falla("expresiones en Tcode compila", r.stderr[:600])
            else:
                archivos = sorted(
                    glob.glob(os.path.join(RAIZ, "std", "*.t"))
                    + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                                recursive=True))
                cubiertas = vistas = 0
                for archivo in archivos:
                    esperado = _expresiones_esperadas(archivo)
                    if esperado is None:
                        continue
                    suite.total += 1
                    e = subprocess.run([binario, archivo], capture_output=True,
                                       text=True, timeout=180)
                    if "Sanitizer" in e.stderr:
                        suite.falla("expresiones en Tcode",
                                    f"{os.path.basename(archivo)}: sanitizer\n"
                                    f"{e.stderr[:400]}")
                        continue
                    dado = [linea for linea in e.stdout.splitlines() if linea.strip()]
                    if len(dado) != len(esperado):
                        suite.falla("expresiones en Tcode",
                                    f"{os.path.relpath(archivo, RAIZ)}: {len(dado)} "
                                    f"expresiones contra {len(esperado)}")
                        continue
                    for a, b in zip(dado, esperado):
                        vistas += 1
                        if a.endswith("\t?"):
                            continue        # esta capa no la cubre todavia
                        # Los numeros de temporal se renumeran por orden de
                        # aparicion, como en CUERPOS y por lo mismo: el original
                        # arrastra el contador entre las expresiones de una
                        # funcion y esta capa empieza cada una de cero. El numero
                        # dice en que orden se genero, no que C sale.
                        if _renumera_tmp(a) != _renumera_tmp(b):
                            suite.falla("expresiones en Tcode",
                                        f"{os.path.relpath(archivo, RAIZ)}:\n"
                                        f"  Tcode:  {a!r}\n  Python: {b!r}")
                        else:
                            cubiertas += 1
                if cubiertas < _MINIMO_CUBIERTAS:
                    suite.total += 1
                    suite.falla("expresiones en Tcode",
                                f"solo {cubiertas} expresiones cubiertas, se esperaban "
                                f"al menos {_MINIMO_CUBIERTAS}")
                suite.cifra("expresiones_iguales", cubiertas)
                suite.cifra("expresiones", vistas)
                print(f"    {cubiertas} de {vistas} expresiones, mismo C que el "
                      f"generador de Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
