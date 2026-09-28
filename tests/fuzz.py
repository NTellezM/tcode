"""
Fuzzing continuo de `tcodec` sobre el codigo real del repositorio.

Las propiedades (`test_propiedades.py`) rompen programas generados, un numero
fijo de veces. Esto rompe los `.t` de verdad —`std/`, `ejemplos/`, el propio
compilador— durante el tiempo que se le de, y mira que `tcodec` se comporte:

  - Nunca revienta, nunca se cuelga, nunca lo para un sanitizer: o acepta, o
    rechaza con `error: archivo:linea: ...`.
  - Lo que acepta da C que el compilador de C acepta con -Wall -Wextra
    -Werror, y que corre sin que ASan ni UBSan digan nada. Un programa puede
    pararse por una cuenta que se sale o un indice fuera de rango —eso esta
    definido—, pero no tocar memoria que no es suya.

Cada fallo se reduce —lineas y piezas que sobran fuera, mientras falle igual—
y se guarda en `tests/fuzz/hallazgos/`, con de donde salio. `--repetir` los
vuelve a pasar todos: arreglado el fallo, el hallazgo queda como regresion y
lo pasa `make check`.

    python3 tests/fuzz.py                 un minuto
    python3 tests/fuzz.py --segundos 3600 --semilla 7
    python3 tests/fuzz.py --repetir       solo los hallazgos guardados
"""

import argparse
import concurrent.futures
import glob
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from semilla import construir_tcodec  # noqa: E402
from mutador import mutar  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNTIME = os.path.join(RAIZ, "runtime")
HALLAZGOS = os.path.join(RAIZ, "tests", "fuzz", "hallazgos")
ENTORNO = dict(os.environ, TCODE_RAIZ=".", ASAN_OPTIONS="detect_leaks=1")

# Lo que tarda de mas un caso normal es compilar su C con los sanitizers.
TIEMPO_TCODEC = 30
TIEMPO_PROGRAMA = 5

# Entradas que la mutacion por piezas no da: anidamiento hondo, numeros y
# nombres enormes, bytes que no son texto.
_RAROS = [
    "(" * 3000, "[" * 3000, "{" * 3000, "-" * 3000 + "1",
    "9" * 400, "0x" + "f" * 100, "a" * 5000, "\x00", "\xff\xfe", "é", "‮",
    '"' + "\\" * 51, "$\"{" * 200, "//" + "x" * 10000, "/*",
]


def corpus():
    """Los `.t` del repositorio, relativos a la raiz."""
    todos = glob.glob("std/*.t", root_dir=RAIZ) + glob.glob(
        "ejemplos/**/*.t", root_dir=RAIZ, recursive=True)
    return sorted(r for r in todos if not os.path.basename(r).startswith("."))


def mutante(fuente, r):
    """Una a tres mutaciones sobre `fuente`, y lo que se hizo."""
    hecho = []
    for _ in range(r.randint(1, 3)):
        if r.random() < 0.15:
            i = r.randrange(len(fuente) + 1)
            raro = r.choice(_RAROS)
            fuente = fuente[:i] + raro + fuente[i:]
            hecho.append(f"insertado {raro[:20]!r}")
        else:
            fuente, que = mutar(fuente, r.randrange(1 << 30))
            hecho.append(que)
    return fuente, "; ".join(hecho)


def _limpia(texto):
    """Lo que identifica un fallo sin rutas, numeros de linea ni direcciones:
    dos mutantes con el mismo fallo dan la misma firma."""
    texto = re.sub(r"0x[0-9a-f]+", "0x", texto)
    texto = re.sub(r"[\w./-]*\.(t|c|h|inc):\d+(:\d+)?", "<sitio>", texto)
    texto = re.sub(r"==\d+==", "==", texto)
    return re.sub(r"\d+", "N", texto).strip()[:200]


def _sanitizer(texto):
    for linea in texto.splitlines():
        if "ERROR: AddressSanitizer" in linea or "ERROR: LeakSanitizer" in linea:
            return linea
        if "runtime error:" in linea:
            return linea
    return None


class Juez:
    """Pasa un `.t` por `tcodec` y, si lo acepta, por el compilador de C y
    los sanitizers. Devuelve None si todo se comporto, o la firma del fallo."""

    def __init__(self, tcodec, tmp):
        self.tcodec = tcodec
        self.tmp = tmp
        # `CC` es un solo programa: los sanitizers van en un envoltorio.
        self.cc = os.path.join(tmp, "cc-sanitizers")
        with open(self.cc, "w", encoding="utf-8") as f:
            f.write('#!/bin/sh\nexec cc -g -fsanitize=address,undefined '
                    '-fno-omit-frame-pointer -fno-sanitize-recover=undefined "$@"\n')
        os.chmod(self.cc, 0o755)

    def juzgar(self, ruta, n):
        """`ruta` relativa a la raiz; `n` distingue los binarios."""
        try:
            r = subprocess.run([self.tcodec, ruta, "--mostrar-c"], cwd=RAIZ,
                               env=ENTORNO, capture_output=True,
                               timeout=TIEMPO_TCODEC, stdin=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            return "tcodec: se cuelga"
        err = r.stderr.decode("utf-8", "replace")
        san = _sanitizer(err)
        if san:
            return "tcodec: " + _limpia(san)
        if r.returncode < 0 or r.returncode > 1:
            return f"tcodec: codigo {r.returncode}: {_limpia(err[-200:])}"
        if "fallo del compilador" in err:
            return "tcodec: " + _limpia(err.strip().splitlines()[-1])
        if r.returncode == 1:
            if not re.search(r"^error: .+:\d+: ", err, re.M):
                return f"tcodec: rechaza sin archivo y linea: {_limpia(err[:200])}"
            return None
        # Aceptado: el C tiene que compilar limpio, y correr sin que un
        # sanitizer diga nada. Salvo con `externo`: ese C necesita cabeceras
        # y archivos de C que no son de Tcode, y un mutante los rompe.
        with open(os.path.join(RAIZ, ruta), "rb") as f:
            if re.search(rb"\bexterno\b", f.read()):
                return None
        codigo_c = os.path.join(self.tmp, f"m{n}.c")
        binario = os.path.join(self.tmp, f"m{n}")
        with open(codigo_c, "wb") as f:
            f.write(r.stdout)
        # Un modulo de biblioteca no tiene `main`: se compila, y ya.
        programa = re.search(rb"^int main\(", r.stdout, re.M) is not None
        orden = [self.cc, "-std=c17", "-Wall", "-Wextra", "-Werror",
                 f"-I{RUNTIME}", codigo_c]
        orden += ([os.path.join(RUNTIME, "safestr.c"), "-o", binario, "-lm"]
                  if programa else ["-c", "-o", binario])
        c = subprocess.run(orden, cwd=RAIZ, capture_output=True, text=True,
                           timeout=120)
        if c.returncode != 0:
            primero = next((x for x in c.stderr.splitlines()
                            if "error" in x), c.stderr[:200])
            if "undefined reference" in primero:
                return None     # un `externo` que no enlaza solo: no es de Tcode
            return "C: " + _limpia(primero)
        if not programa:
            os.remove(codigo_c)
            os.remove(binario)
            return None
        try:
            e = subprocess.run([binario], capture_output=True, cwd=self.tmp,
                               timeout=TIEMPO_PROGRAMA, stdin=subprocess.DEVNULL,
                               env=ENTORNO)
        except subprocess.TimeoutExpired:
            return None         # un bucle sin fin es un programa valido
        finally:
            for x in (codigo_c, binario):
                if os.path.exists(x):
                    os.remove(x)
        san = _sanitizer(e.stderr.decode("utf-8", "replace"))
        return "programa: " + _limpia(san) if san else None


def _escribir_junto(origen, fuente, etiqueta):
    """Escribe `fuente` junto a `origen` —para que sus `usar` sigan
    valiendo— con un nombre que `.gitignore` ya ignora."""
    carpeta = os.path.dirname(origen)
    ruta = os.path.join(carpeta, f".mut_fuzz_{os.getpid()}_{etiqueta}.t")
    with open(os.path.join(RAIZ, ruta), "w", encoding="utf-8",
              errors="surrogateescape") as f:
        f.write(fuente)
    return ruta


def reducir(juez, origen, fuente, firma, limite=300):
    """La fuente mas corta que falla con la misma firma: se quitan lineas y
    luego piezas, en trozos cada vez mas chicos."""
    pruebas = [0]

    def falla_igual(texto):
        pruebas[0] += 1
        ruta = _escribir_junto(origen, texto, f"r{pruebas[0]}")
        try:
            return juez.juzgar(ruta, f"r{os.getpid()}") == firma
        finally:
            os.remove(os.path.join(RAIZ, ruta))

    for partir in (lambda t: t.split("\n"),
                   lambda t: re.findall(r"\s+|\w+|.", t, re.S)):
        unir = "\n" if partir("a\nb") == ["a", "b"] else ""
        trozos = partir(fuente)
        n = 2
        while len(trozos) >= 2 and pruebas[0] < limite:
            tam = max(1, len(trozos) // n)
            quitado = False
            for i in range(0, len(trozos), tam):
                resto = trozos[:i] + trozos[i + tam:]
                if resto and falla_igual(unir.join(resto)):
                    trozos, n, quitado = resto, max(n - 1, 2), True
                    break
            if not quitado:
                if tam == 1:
                    break
                n = min(n * 2, len(trozos))
        fuente = unir.join(trozos)
    return fuente


def guardar(origen, fuente, firma, que):
    os.makedirs(HALLAZGOS, exist_ok=True)
    clave = hashlib.sha256(firma.encode()).hexdigest()[:12]
    base = os.path.join(HALLAZGOS, clave)
    if os.path.exists(base + ".t"):
        return None
    with open(base + ".t", "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(fuente)
    with open(base + ".json", "w", encoding="utf-8") as f:
        json.dump({"origen": origen, "firma": firma, "mutacion": que}, f,
                  ensure_ascii=False, indent=2)
        f.write("\n")
    return base + ".t"


def repetir(juez):
    """Cada hallazgo guardado, junto a su origen: ya no tiene que fallar."""
    fallas = 0
    guardados = sorted(glob.glob(os.path.join(HALLAZGOS, "*.t")))
    for ruta in guardados:
        with open(ruta.removesuffix(".t") + ".json", encoding="utf-8") as f:
            datos = json.load(f)
        with open(ruta, encoding="utf-8", errors="surrogateescape") as f:
            fuente = f.read()
        junto = _escribir_junto(datos["origen"], fuente, "repetir")
        try:
            firma = juez.juzgar(junto, "repetir")
        finally:
            os.remove(os.path.join(RAIZ, junto))
        if firma:
            fallas += 1
            print(f"  FALLA: {os.path.relpath(ruta, RAIZ)}\n         {firma}")
    print(f"{len(guardados)} hallazgos guardados, {fallas} fallan todavia")
    return fallas


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--segundos", type=float, default=60)
    p.add_argument("--semilla", type=int, default=None)
    p.add_argument("--trabajos", type=int, default=os.cpu_count() or 2)
    p.add_argument("--repetir", action="store_true",
                   help="solo pasar los hallazgos guardados")
    a = p.parse_args()

    tmp = tempfile.mkdtemp(prefix="tcode-fuzz-")
    try:
        juez = Juez(construir_tcodec(tmp, ["-std=c17", "-O1", "-g",
                                           "-fsanitize=address,undefined",
                                           "-fno-omit-frame-pointer"]), tmp)
        fallas = repetir(juez)
        if a.repetir:
            return 1 if fallas else 0

        semilla = a.semilla if a.semilla is not None else int(time.time())
        print(f"=== FUZZ: {a.segundos:g} s, semilla {semilla} ===")
        r = random.Random(semilla)
        fuentes = {}
        for ruta in corpus():
            with open(os.path.join(RAIZ, ruta), encoding="utf-8") as f:
                fuentes[ruta] = f.read()
        nombres = sorted(fuentes)
        fin = time.monotonic() + a.segundos
        casos = nuevos = 0
        vistas = set()

        def uno(k):
            rk = random.Random(f"{semilla}:{k}")
            origen = rk.choice(nombres)
            fuente, que = mutante(fuentes[origen], rk)
            ruta = _escribir_junto(origen, fuente, str(k))
            try:
                return origen, fuente, que, juez.juzgar(ruta, k)
            finally:
                os.remove(os.path.join(RAIZ, ruta))

        with concurrent.futures.ThreadPoolExecutor(a.trabajos) as ex:
            k = r.randrange(1 << 30)
            pendientes = set()
            while time.monotonic() < fin or pendientes:
                while time.monotonic() < fin and len(pendientes) < a.trabajos * 2:
                    pendientes.add(ex.submit(uno, k))
                    k += 1
                hechos, pendientes = concurrent.futures.wait(
                    pendientes, return_when=concurrent.futures.FIRST_COMPLETED)
                for h in hechos:
                    casos += 1
                    origen, fuente, que, firma = h.result()
                    if firma is None or firma in vistas:
                        continue
                    vistas.add(firma)
                    print(f"  FALLO en un mutante de {origen} ({que}):\n"
                          f"         {firma}")
                    corto = reducir(juez, origen, fuente, firma)
                    guardado = guardar(origen, corto, firma, que)
                    if guardado:
                        nuevos += 1
                        print(f"         reducido a {len(corto)} bytes: "
                              f"{os.path.relpath(guardado, RAIZ)}")
        print(f"{casos} mutantes, {len(vistas)} fallos distintos, "
              f"{nuevos} hallazgos nuevos")
        return 1 if vistas or fallas else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        for resto in glob.glob(os.path.join(RAIZ, "**", f".mut_fuzz_{os.getpid()}_*.t"),
                               recursive=True):
            os.remove(resto)


if __name__ == "__main__":
    sys.exit(main())
