"""
`tcodec` desde su C semilla, sin el compilador de Python.

`bootstrap/tcodec.c` es el C que `tcodec` escribe de si mismo. Compilado da
la etapa 0, y la etapa 0 compila `ejemplos/compilador/tcodec.t` tal como esta
ahora: ese C es el del `tcodec` que se prueba. Es lo mismo que hace `make`.

    etapa0(directorio)                 el binario de la semilla
    c_de(compilador, ruta)             el C de un `.t`, como `compilar_archivo`
    construir_tcodec(directorio, ops)  el `tcodec` de ahora, compilado con `ops`

Los binarios salen de la cache de `compilar_c.herramienta` si su C no cambio.
"""

import os
import subprocess

from compilar_c import RAIZ, RUNTIME, SAFESTR_C, herramienta

SEMILLA = os.path.join(RAIZ, "bootstrap", "tcodec.c")
SISTEMA = os.path.join(RAIZ, "ejemplos", "compilador", "lib", "sistema_tcodec.c")
PROPIO = os.path.join("ejemplos", "compilador", "tcodec.t")
# Desde la raiz y con la raiz relativa: los mensajes y el C dicen las rutas
# como el compilador de Python, y el C no depende de donde este el repositorio.
ENTORNO = dict(os.environ, TCODE_RAIZ=".")


def etapa0(directorio):
    """La semilla compilada, en `directorio`."""
    binario = os.path.join(directorio, "tcodec0")
    r = herramienta(["cc", "-std=c17", "-O1", f"-I{RUNTIME}", SEMILLA, SAFESTR_C,
                     SISTEMA, "-o", binario, "-lm"], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("la semilla no compila:\n" + r.stderr[:600])
    return binario


def c_de(compilador, ruta, timeout=900):
    """El C de `ruta` escrito por el binario `compilador`, y sus errores:
    `(codigo, [])` o `(None, errores)`, como `compilar_archivo`."""
    if os.path.isabs(ruta):
        ruta = os.path.relpath(ruta, RAIZ)
    r = subprocess.run([compilador, ruta, "--mostrar-c"], cwd=RAIZ, env=ENTORNO,
                       capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        errores = [x[len("error: "):] for x in r.stderr.splitlines()
                   if x.startswith("error: ")]
        return None, errores or [r.stderr[:600] or f"codigo {r.returncode}"]
    return r.stdout, []


def construir_tcodec(directorio, opciones):
    """El `tcodec` de ahora en `directorio`: la etapa 0 escribe su C, y se
    compila con `opciones`."""
    codigo, errores = c_de(etapa0(directorio), PROPIO)
    if errores:
        raise RuntimeError("tcodec no compila:\n" + "\n".join(errores))
    ruta_c = os.path.join(directorio, "tcodec.c")
    binario = os.path.join(directorio, "tcodec")
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(codigo)
    r = herramienta(["cc", *opciones, f"-I{RUNTIME}", ruta_c, SAFESTR_C, SISTEMA,
                     "-o", binario, "-lm"], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("el C de tcodec no compila:\n" + r.stderr[:600])
    return binario
