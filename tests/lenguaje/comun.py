"""Lo que comparten las secciones de la suite del lenguaje: el compilador
que se prueba, como se compila y se corre un programa, y la cuenta de casos,
fallas y cifras de una pasada."""

import atexit
import concurrent.futures
import os
import shutil
import subprocess
import tempfile

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


def compilar_y_correr(fuente, tmp, con_sanitizers=True, apoyo=(), entrada=None):
    """Devuelve (codigo_de_salida, stdout, stderr) o lanza AssertionError."""
    return correr_c(c_de(fuente, tmp), tmp, con_sanitizers, apoyo=apoyo,
                    entrada=entrada)


def en_paralelo(funcion, trabajos):
    """`funcion` sobre cada trabajo, en tantos hilos como nucleos: lo que
    cuesta es el compilador de C y el programa, que son otros procesos. Los
    resultados salen en el orden de los trabajos."""
    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        return list(hilos.map(funcion, trabajos))


def c_de(fuente, tmp):
    """El C que escribe `tcodec` para un programa, o AssertionError si no
    compila."""
    r = tcodec_sobre(fuente, "--mostrar-c", "--sin-avisos", directorio=tmp)
    assert r.returncode == 0, ("errores inesperados: "
                               + ("; ".join(bloques(r.stderr, "error: ")) or r.stderr))
    return r.stdout


def correr_c(codigo, tmp, con_sanitizers=True, apoyo=(), entrada=None):
    """Compila el C en `tmp` y lo corre: (codigo_de_salida, stdout, stderr),
    o AssertionError si el C no compila.

    `apoyo` son los `.c` que acompañan a un modulo de `std/` —los de sus
    bloques `externo`—, con la ruta relativa a la raiz del repositorio.
    `--mostrar-c` no los enlaza, asi que se pasan a mano aqui, y asi tambien
    quedan bajo los sanitizers; explicito en cada caso que los use.

    `entrada`, si no es `None`, es el texto que lee el binario por un tubo.
    Sin ella la entrada es la que herede la suite, que en una terminal de
    verdad es una terminal: un caso que mire el tamaño o las teclas no puede
    depender de eso."""
    ruta_c = os.path.join(tmp, "p.c")
    binario = os.path.join(tmp, "p")
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(codigo)

    orden = ["cc", "-std=c17", "-g", "-Wall", "-Wextra", "-Werror",
             f"-I{RUNTIME}", ruta_c,
             *(os.path.join(RAIZ, a) for a in apoyo),
             os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"]
    if con_sanitizers:
        orden.insert(3, "-fsanitize=address,undefined")
        orden.insert(4, "-fno-omit-frame-pointer")

    r = cc(orden, capture_output=True, text=True)
    assert r.returncode == 0, "el C generado no compila:\n" + r.stderr

    e = subprocess.run([binario], capture_output=True, text=True, timeout=60,
                       input=entrada)
    return e.returncode, e.stdout, e.stderr


def correr_referencia(ruta, tmp, entrada=None):
    """La implementacion de referencia en C de un caso EQUIVALE, compilada y
    corrida: (codigo_de_salida, stdout, stderr).

    Lleva las mismas banderas que el C de `tcodec` —`-std=c17 -g -Wall -Wextra
    -Werror`— y **sin** los sanitizers de Tcode: la referencia no es el
    programa que se prueba, es el original contra el que se compara. Se escribe
    a mano; nunca es el C que emite el compilador.

    `entrada`, si no es `None`, es el texto que lee el binario por un tubo.
    """
    binario = os.path.join(tmp, "referencia")
    orden = ["cc", "-std=c17", "-g", "-Wall", "-Wextra", "-Werror",
             f"-I{RUNTIME}", ruta, "-o", binario, "-lm"]

    r = cc(orden, capture_output=True, text=True)
    assert r.returncode == 0, "la referencia no compila:\n" + r.stderr

    e = subprocess.run([binario], capture_output=True, text=True, timeout=60,
                       input=entrada)
    return e.returncode, e.stdout, e.stderr


def hay_msan():
    """Si esta `clang`, que es el unico con MemorySanitizer."""
    return shutil.which("clang") is not None


def correr_c_msan(codigo, tmp, apoyo=(), entrada=None):
    """Lo mismo, con MemorySanitizer en vez de ASan+UBSan.

    Es un segundo camino para la misma promesa de memoria, y de otro
    implementador: ASan ve lo que se libera mal, MSan ve lo que se **lee sin
    inicializar**, que ASan no mira. Los dos sanitizers no conviven en el
    mismo binario, asi que van en dos pasadas. Necesita `clang`.
    """
    ruta_c = os.path.join(tmp, "m.c")
    binario = os.path.join(tmp, "m")
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(codigo)

    orden = ["clang", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=memory", "-fno-omit-frame-pointer",
             "-fno-sanitize-recover=all", f"-I{RUNTIME}", ruta_c,
             *(os.path.join(RAIZ, a) for a in apoyo),
             os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"]

    r = subprocess.run(orden, capture_output=True, text=True)
    assert r.returncode == 0, "el C generado no compila con MSan:\n" + r.stderr

    e = subprocess.run([binario], capture_output=True, text=True, timeout=60,
                       input=entrada)
    return e.returncode, e.stdout, e.stderr
