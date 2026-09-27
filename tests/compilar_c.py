"""
El compilador de C para las suites, sin repetir trabajo.

Dos cosas se repetian en cada pasada:

- `runtime/safestr.c` se compilaba con cada programa, cientos de veces y
  con los sanitizers puestos. Aqui se compila una vez por juego de opciones
  y cada programa enlaza ese `.o`: un programa pequeño pasa de 0,7 s a 0,1 s.
- Las herramientas grandes —`tcodec` y las capas del compilador escritas en
  Tcode— se compilaban enteras en cada pasada aunque su C no hubiera
  cambiado: `tcodec` con sanitizers son 40 s. Se guardan por el hash de todo
  lo que entra al compilador de C, y si nada cambio se usa el guardado.

    cc([...])           como `subprocess.run`, con el runtime ya compilado
    herramienta([...])  lo mismo, y el binario sale de la cache si se puede

La cache vive en `.cache/herramientas` (o donde diga `TCODE_CACHE`). Borrarla
no rompe nada: la siguiente pasada la vuelve a llenar.
"""

import atexit
import hashlib
import os
import shutil
import subprocess
import tempfile
import threading

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNTIME = os.path.join(RAIZ, "runtime")
SAFESTR_C = os.path.join(RUNTIME, "safestr.c")
CACHE = os.environ.get("TCODE_CACHE") or os.path.join(RAIZ, ".cache", "herramientas")
# Cuantos binarios se guardan: los mas viejos se borran.
GUARDADOS = 40

_cerrojo = threading.Lock()
_objetos: dict[tuple[str, ...], str | None] = {}
_dir_objetos: str | None = None
_version_cc: str | None = None


def _opciones(orden):
    """Las opciones de una orden de `cc` que cambian lo que se compila: las
    que empiezan por `-`, salvo la salida, las rutas de cabeceras y las
    bibliotecas, que solo importan al enlazar o ya van en el hash."""
    fuera = ("-o", "-I", "-l", "-L")
    return [a for a in orden[1:] if a.startswith("-") and not a.startswith(fuera)]


def _runtime(opciones):
    """`safestr.c` compilado con estas opciones, una vez por proceso. None
    si no compila: entonces cada programa lo compila con el suyo y el error
    sale donde siempre."""
    global _dir_objetos
    clave = tuple(opciones)
    with _cerrojo:
        if clave in _objetos:
            return _objetos[clave]
        if _dir_objetos is None:
            _dir_objetos = tempfile.mkdtemp(prefix="tcode-runtime-")
            atexit.register(shutil.rmtree, _dir_objetos, ignore_errors=True)
        objeto = os.path.join(_dir_objetos, f"safestr{len(_objetos)}.o")
        r = subprocess.run(["cc", *opciones, f"-I{RUNTIME}", "-c", SAFESTR_C,
                            "-o", objeto], capture_output=True, text=True)
        _objetos[clave] = objeto if r.returncode == 0 else None
        return _objetos[clave]


def con_runtime(orden):
    """La orden, con `safestr.c` cambiado por su `.o` ya compilado."""
    if SAFESTR_C not in orden or "-c" in orden:
        return list(orden)
    objeto = _runtime(_opciones(orden))
    if objeto is None:
        return list(orden)
    return [objeto if a == SAFESTR_C else a for a in orden]


def cc(orden, **kw):
    """`subprocess.run(orden, **kw)`, enlazando el runtime ya compilado."""
    return subprocess.run(con_runtime(orden), **kw)


def _hash_de(orden):
    """Lo que decide el binario: la version del compilador de C, las
    opciones, y el contenido de cada archivo que entra, del runtime entero
    incluido. Las rutas no: el C de una herramienta se escribe cada vez en
    un directorio temporal distinto."""
    global _version_cc
    if _version_cc is None:
        _version_cc = subprocess.run(["cc", "--version"], capture_output=True,
                                     text=True).stdout
    h = hashlib.sha256(_version_cc.encode())
    salida = orden[orden.index("-o") + 1] if "-o" in orden else None
    for a in orden[1:]:
        if a == salida:
            continue
        if not a.startswith("-") and os.path.isfile(a):
            with open(a, "rb") as f:
                h.update(b"archivo\0" + f.read())
        else:
            h.update(b"opcion\0" + a.encode())
    for nombre in sorted(os.listdir(RUNTIME)):
        ruta = os.path.join(RUNTIME, nombre)
        if os.path.isfile(ruta):
            with open(ruta, "rb") as f:
                h.update(nombre.encode() + b"\0" + f.read())
    return h.hexdigest()


def _podar():
    guardados = sorted((os.path.join(CACHE, n) for n in os.listdir(CACHE)),
                       key=os.path.getmtime, reverse=True)
    for viejo in guardados[GUARDADOS:]:
        try:
            os.remove(viejo)
        except OSError:
            pass


def herramienta(orden, **kw):
    """Compila una herramienta grande como `subprocess.run(orden, **kw)`. Si
    ya se compilo esto mismo, copia el binario guardado y no llama a `cc`."""
    salida = orden[orden.index("-o") + 1]
    clave = _hash_de(orden)
    guardado = os.path.join(CACHE, clave)
    if os.path.isfile(guardado):
        shutil.copy2(guardado, salida)
        os.utime(guardado)
        return subprocess.CompletedProcess(orden, 0, "", "")
    r = cc(orden, **kw)
    if r.returncode == 0 and os.path.isfile(salida):
        try:
            os.makedirs(CACHE, exist_ok=True)
            temporal = guardado + f".{os.getpid()}.tmp"
            shutil.copy2(salida, temporal)
            os.replace(temporal, guardado)
            _podar()
        except OSError:
            pass
    return r
