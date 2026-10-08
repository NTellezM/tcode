"""FORMATO: un estilo, y el repositorio ya lo tiene."""

import glob
import os
import shutil
import subprocess
import tempfile

from .comun import (
    ENTORNO_TCODEC,
    RAIZ,
    Resultado,
    bloques,
    en_paralelo,
    tcodec,
    tcodec_sobre,
)

TITULO = "un estilo, y el repositorio ya lo tiene"


def correr(suite: Resultado) -> None:
    _tmp_fmt = tempfile.mkdtemp(prefix="tcode-formato-")

    # El préstamo no oculta que `Caja<T>` es un tipo genérico.
    suite.total += 1
    _prestamo_generico = tcodec_sobre(
        "struct Caja<T> { valor: T }\nfn mirar<T>(c: &Caja<T>) {}\n",
        "--formatear", directorio=_tmp_fmt, nombre="prestamo_generico.t").stdout
    if "c: &Caja<T>" not in _prestamo_generico:
        suite.falla("un préstamo de tipo genérico queda unido",
                    repr(_prestamo_generico))

    # Un unario va pegado a su parentesis: `!(a)`, no `! (a)`.
    suite.total += 1
    _con_unario = tcodec_sobre(
        "fn main() {\nlet a = true;\nif !(a) { imprimir(-(1)); }\n}\n",
        "--formatear", directorio=_tmp_fmt).stdout
    if "!(a)" not in _con_unario or "-(1)" not in _con_unario:
        suite.falla("un unario va pegado a su parentesis", repr(_con_unario))

    # El formateador no mira los tipos: decide si un `<` abre una lista de
    # tipos y si un simbolo es unario comparando el VALOR del token anterior,
    # y con una cadena lo descifra (`valor_py` -> `descifrado_simple`,
    # formato.t:58). Un programa que no compilaria —`"abc" < 1`— formatea
    # igual, y tiene que salir tal cual entro.
    suite.total += 1
    _cadena_antes_de_operador = tcodec_sobre(
        'fn main() {\n    let x = "abc" < 1;\n    let y = "def" - 2;\n}\n',
        "--formatear", directorio=_tmp_fmt, nombre="cadena_operador.t").stdout
    if _cadena_antes_de_operador != (
            'fn main() {\n    let x = "abc" < 1;\n    let y = "def" - 2;\n}\n'):
        suite.falla("una cadena antes de un operador no se toca",
                    repr(_cadena_antes_de_operador))

    # Un aviso sobre una clausura dice `clausura`, tambien pasada la decima:
    # los nombres se cambian enteros, y `Cierre_1` no es un trozo de `Cierre_10`.
    suite.total += 1
    _once = "fn main() {\n" + "".join(
        f"    let f{i} = fn(x: usize) -> usize {{ return x; }};\n    imprimir(f{i}(1));\n"
        for i in range(10)) + "    let g = fn(x: usize, sobra: usize) -> usize { return x; };\n" \
        "    imprimir(g(1, 2));\n}\n"
    _r_av = tcodec_sobre(_once, "--solo-comprobar", directorio=_tmp_fmt, nombre="once.t")
    _avisos_once = bloques(_r_av.stderr, "aviso: ")
    if _r_av.returncode != 0 or not any("de `clausura` no se usa" in a for a in _avisos_once):
        suite.falla("un aviso sobre una clausura dice `clausura`",
                    f"codigo {_r_av.returncode}: {_avisos_once or _r_av.stderr[-300:]}")

    # Dos propiedades: que es idempotente y que el repositorio esta escrito en
    # el formato canonico. La segunda es mas fuerte que "mismos tokens": exige
    # el mismo texto byte a byte, asi que cualquier perdida se ve.
    _TODOS = sorted(
        glob.glob(os.path.join(RAIZ, "std", "*.t"))
        + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"), recursive=True)
        + glob.glob(os.path.join(RAIZ, "bench", "*.t"))
        + glob.glob(os.path.join(RAIZ, "programas", "*.t")))

    def _formatear_dos_veces(i_archivo):
        """Lo que da `tcodec --formatear` sobre el archivo, y otra vez sobre
        eso: (codigo, uno, dos, error)."""
        i, archivo = i_archivo
        uno = subprocess.run([tcodec(), archivo, "--formatear"], env=ENTORNO_TCODEC,
                             capture_output=True, text=True, timeout=120)
        if uno.returncode != 0:
            return None, None, uno.stderr[-400:]
        dir_i = os.path.join(_tmp_fmt, f"f{i}")
        os.makedirs(dir_i)
        dos = tcodec_sobre(uno.stdout, "--formatear", directorio=dir_i,
                           nombre=os.path.basename(archivo))
        if dos.returncode != 0:
            return uno.stdout, None, dos.stderr[-400:]
        return uno.stdout, dos.stdout, None

    sin_formato = []
    for archivo, (uno, dos, error) in zip(
            _TODOS, en_paralelo(_formatear_dos_veces, list(enumerate(_TODOS)))):
        suite.total += 1
        if error is not None:
            suite.falla(f"formato de {os.path.relpath(archivo, RAIZ)}", error)
            continue
        with open(archivo, encoding="utf-8") as f:
            fuente = f.read()
        if uno != dos:
            suite.falla(f"formato de {os.path.relpath(archivo, RAIZ)}",
                        "formatear dos veces no da lo mismo")
            continue
        if uno != fuente:
            sin_formato.append(os.path.relpath(archivo, RAIZ))
    shutil.rmtree(_tmp_fmt, ignore_errors=True)
    if sin_formato:
        suite.total += 1
        suite.falla("el repositorio esta formateado",
                    "sin formatear: " + ", ".join(sin_formato[:6])
                    + "; arreglalo con `make formato`")
    suite.cifra("formato_archivos", len(_TODOS))
    print(f"    {len(_TODOS)} archivos: idempotente, y ya en formato canonico")
