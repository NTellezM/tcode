"""Lo que comparten las secciones de la suite del lenguaje: el compilador
que se prueba, como se compila y se corre un programa, y la cuenta de casos,
fallas y cifras de una pasada."""

import atexit
import concurrent.futures
import glob
import os
import shutil
import subprocess
import tempfile

import azucar
import semilla
from compilar_c import cc


RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNTIME = os.path.join(RAIZ, "runtime")


class Resultado:
    """Lo que va contando una pasada: los casos, las fallas, y las cifras que
    `tests/cifras.py` lleva al README."""

    def __init__(self) -> None:
        self.total = 0
        self.fallos = 0
        self.cifras: dict[str, object] = {}

    def falla(self, nombre: str, detalle: str) -> None:
        self.fallos += 1
        print(f"  FALLA: {nombre}\n         {detalle}")

    def cifra(self, clave: str, valor: object) -> None:
        self.cifras[clave] = valor


# ---------- el compilador que se prueba ----------
#
# Es `tcodec`, el compilador escrito en Tcode, con los sanitizers puestos: cada
# programa de la suite prueba tambien su memoria. Se construye desde su C
# semilla, como en `make`; el de Python, en las secciones que lo dicen, hace
# de oraculo de lo que ya sabe hacer.

SANITIZERS = ["-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
              "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
SISTEMA_TCODEC = os.path.join(RAIZ, "ejemplos", "compilador", "lib", "sistema_tcodec.c")
_TCODEC = {"ruta": os.environ.get("TCODE_TCODEC")}
# El binario vive fuera del repositorio: se le dice donde estan `std/` y
# `runtime/`.
ENTORNO_TCODEC = dict(os.environ, TCODE_RAIZ=RAIZ)


def construir_tcodec(directorio):
    """`tcodec` en `directorio`, construido desde su C semilla y compilado con
    los sanitizers; si su C no cambio, sale de la cache."""
    return semilla.construir_tcodec(directorio, SANITIZERS)


def tcodec():
    """El binario de `tcodec`: el que dio `TCODE_TCODEC`, o uno construido
    ahora, una vez por proceso."""
    if not _TCODEC["ruta"]:
        directorio = tempfile.mkdtemp(prefix="tcode-tcodec-")
        atexit.register(shutil.rmtree, directorio, ignore_errors=True)
        _TCODEC["ruta"] = construir_tcodec(directorio)
    return _TCODEC["ruta"]


# El compilador y sus herramientas estan escritos con lo que solo sabe
# `tcodec`. Para el de Python se les quita el azucar (`tests/azucar.py`), sin
# mover lineas, en una copia aparte: asi sigue siendo el oraculo tambien sobre
# el corpus mas grande del repositorio.
_SIN_AZUCAR = {"dir": None, "archivos": None}


def sin_azucar():
    """El directorio de la copia sin azucar y sus `.t`, una vez por proceso."""
    if _SIN_AZUCAR["dir"] is None:
        # Dentro del repositorio, en `.cache/`: desde la raiz, sus rutas se
        # escriben como las de los originales, que es lo que comparan las
        # secciones.
        os.makedirs(os.path.join(RAIZ, ".cache"), exist_ok=True)
        directorio = tempfile.mkdtemp(prefix="sin-azucar-",
                                      dir=os.path.join(RAIZ, ".cache"))
        atexit.register(shutil.rmtree, directorio, ignore_errors=True)
        _SIN_AZUCAR["archivos"] = azucar.copia_sin_azucar(directorio)
        _SIN_AZUCAR["dir"] = directorio
    return _SIN_AZUCAR["dir"], list(_SIN_AZUCAR["archivos"])


def corpus_python(relativo=False):
    """Los `.t` del repositorio que se comparan con el compilador de Python:
    `std/`, `ejemplos/`, y el compilador en su copia sin azucar. Con
    `relativo`, desde la raiz."""
    todos = sorted(glob.glob(os.path.join(RAIZ, "std", "*.t"))
                   + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                               recursive=True))
    propios = [r for r in todos if not os.path.basename(r).startswith(".")
               and not os.path.relpath(r, RAIZ).startswith(azucar.CARPETAS)]
    todos = propios + sin_azucar()[1]
    return [os.path.relpath(r, RAIZ) for r in todos] if relativo else todos


def nombre_estable(ruta):
    """La ruta de un `.t` del corpus desde su raiz: la del repositorio, o la
    de la copia sin azucar, que cambia de nombre en cada pasada. Es la
    semilla de lo que se hace al azar con cada archivo, y asi sale siempre
    lo mismo."""
    completa = os.path.abspath(ruta)
    copia = _SIN_AZUCAR["dir"]
    if copia is not None and completa.startswith(copia + os.sep):
        return os.path.relpath(completa, copia)
    return os.path.relpath(completa, RAIZ)


def structs_escritos(comp):
    """Nombres de struct que el parser puede encontrar en el archivo raiz.

    El cargador ya resolvio los imports y especializo genericas: una
    `Vector<str>` puede figurar internamente como `Vector__str`. Para volver a
    parsear el fuente crudo hacen falta tanto ese nombre como `Vector`.
    """
    nombres = set(comp.structs)
    nombres.update(n.split("__", 1)[0] for n in comp.structs if "__" in n)
    return nombres


def c_de_tcodec(ruta):
    """El C de un `.t` del repositorio escrito por `tcodec`, y sus errores,
    como `compilar_archivo`. Es como se construyen las herramientas escritas
    en Tcode —las capas del compilador, el lexer—: con lo que el compilador
    de Python ya no entiende."""
    return semilla.c_de(tcodec(), ruta)


def escribir_fuente(ruta, fuente):
    """Un `.t` de la suite: texto, o `bytes` para lo que no es UTF-8."""
    if isinstance(fuente, bytes):
        with open(ruta, "wb") as f:
            f.write(fuente)
    else:
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(fuente)


def tcodec_sobre(fuente, *opciones, directorio, nombre="p.t", timeout=120):
    """Escribe `fuente` como `nombre` en `directorio` y se lo pasa a `tcodec`
    desde ahi, con `opciones`: los mensajes dicen `p.t:3: ...`."""
    escribir_fuente(os.path.join(directorio, nombre), fuente)
    return subprocess.run([tcodec(), nombre, *opciones], cwd=directorio,
                          capture_output=True, text=True, timeout=timeout,
                          env=ENTORNO_TCODEC)


def bloques(texto, marca):
    """Los mensajes que empiezan por `marca` (`error: `, `aviso: `), cada uno
    con las lineas sangradas que lo siguen."""
    salida = []
    for linea in texto.splitlines():
        if linea.startswith(marca):
            salida.append(linea[len(marca):])
        elif linea.startswith("  ") and salida:
            salida[-1] += "\n" + linea
    return salida


def nombre_escrito(nombre, propias):
    """El nombre tal como esta en el archivo.

    El cargador renombra dos cosas: lo que choca con una palabra de C
    (`ss_id_union`) y lo que declaran dos modulos a la vez
    (`propiedad__posee`). Ninguno de los dos esta escrito en la fuente.
    """
    if nombre in propias:
        return nombre
    if nombre.startswith("ss_id_") and nombre[len("ss_id_"):] in propias:
        return nombre[len("ss_id_"):]
    if "__" in nombre:
        corto = nombre.split("__", 1)[1]
        if corto in propias:
            return corto
    return None


def compilar_y_correr(fuente, tmp, con_sanitizers=True):
    """Devuelve (codigo_de_salida, stdout, stderr) o lanza AssertionError."""
    return correr_c(c_de(fuente, tmp), tmp, con_sanitizers)


def en_paralelo(funcion, trabajos):
    """`funcion` sobre cada trabajo, en tantos hilos como nucleos: lo que
    cuesta es el compilador de C y el programa, que son otros procesos. Los
    resultados salen en el orden de los trabajos."""
    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        return list(hilos.map(funcion, trabajos))


def en_procesos(funcion, trabajos):
    """Como `en_paralelo`, para lo que cuesta dentro de Python —el
    compilador de Python sobre muchos archivos—, que en hilos iria de uno en
    uno. Un proceso por nucleo, hechos con `fork` para que vean todo lo de
    aqui: `funcion` tiene que estar a nivel de modulo, y lo que devuelve
    tiene que poder viajar entre procesos."""
    import multiprocessing
    with concurrent.futures.ProcessPoolExecutor(
            os.cpu_count() or 2,
            mp_context=multiprocessing.get_context("fork")) as procesos:
        return list(procesos.map(funcion, trabajos))


def c_de(fuente, tmp):
    """El C que escribe `tcodec` para un programa, o AssertionError si no
    compila."""
    r = tcodec_sobre(fuente, "--mostrar-c", "--sin-avisos", directorio=tmp)
    assert r.returncode == 0, ("errores inesperados: "
                               + ("; ".join(bloques(r.stderr, "error: ")) or r.stderr))
    return r.stdout


def correr_c(codigo, tmp, con_sanitizers=True):
    """Compila el C en `tmp` y lo corre: (codigo_de_salida, stdout, stderr),
    o AssertionError si el C no compila."""
    ruta_c = os.path.join(tmp, "p.c")
    binario = os.path.join(tmp, "p")
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(codigo)

    orden = ["cc", "-std=c17", "-g", "-Wall", "-Wextra", "-Werror",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"]
    if con_sanitizers:
        orden.insert(3, "-fsanitize=address,undefined")
        orden.insert(4, "-fno-omit-frame-pointer")

    r = cc(orden, capture_output=True, text=True)
    assert r.returncode == 0, "el C generado no compila:\n" + r.stderr

    e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
    return e.returncode, e.stdout, e.stderr
