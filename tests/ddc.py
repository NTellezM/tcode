"""
Compilacion doble diversa: la semilla no esconde nada.

`bootstrap/tcodec.c` son 6 MB de C que nadie lee, y de el sale el
compilador. Si la semilla trajera algo que no esta en `tcodec.t` —el ataque
de "Reflections on Trusting Trust"—, pasaria a cada `tcodec` que se
construye con ella sin aparecer en ningun fuente.

La prueba de David A. Wheeler (DDC) es construir el compilador por dos
caminos que no comparten nada y ver que escriben lo mismo:

  A. la semilla -> la etapa 0 -> el `tcodec` de ahora -> el C de `tcodec.t`
  B. el compilador de Python, sin la semilla, compila `tcodec.t` sin azucar
     -> `cc` -> un `tcodec` -> el C de `tcodec.t`

Si A y B dan el mismo C byte a byte, lo que hay en la semilla es lo que
dice `tcodec.t`: una puerta escondida tendria que estar tambien, igual, en
el compilador de Python, que es otro programa en otro lenguaje.

    python3 tests/ddc.py
"""

import os
import shutil
import subprocess
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tests"))
sys.path.insert(0, RAIZ)

import azucar  # noqa: E402
from semilla import construir_tcodec  # noqa: E402

PROPIO = os.path.join("ejemplos", "compilador", "tcodec.t")
ENTORNO = dict(os.environ, TCODE_RAIZ=".")


def c_de_tcodec(binario):
    r = subprocess.run([binario, PROPIO, "--mostrar-c"], cwd=RAIZ, env=ENTORNO,
                       capture_output=True, text=True, timeout=900)
    if r.returncode != 0:
        raise SystemExit(f"{binario} no escribe su C:\n{r.stderr[:600]}")
    return r.stdout


def main():
    tmp = tempfile.mkdtemp(prefix="tcode-ddc-")
    try:
        # A: desde la semilla, como `make`.
        a = c_de_tcodec(construir_tcodec(os.path.join(tmp), ["-std=c17", "-O1"]))

        # B: desde Python, sin la semilla.
        copia = os.path.join(tmp, "sin")
        azucar.copia_sin_azucar(copia)
        c_py = os.path.join(tmp, "tcodec_py.c")
        r = subprocess.run([sys.executable, "-m", "tcode.cli", PROPIO, "--emitir-c",
                            "-o", c_py[:-2]], cwd=copia, capture_output=True,
                           text=True, env=dict(os.environ, PYTHONPATH=RAIZ))
        if r.returncode != 0:
            raise SystemExit(f"Python no compila tcodec.t:\n{r.stderr[:600]}")
        binario_b = os.path.join(tmp, "tcodec_py")
        r = subprocess.run(["cc", "-std=c17", "-O1", f"-I{os.path.join(RAIZ, 'runtime')}",
                            c_py, os.path.join(RAIZ, "runtime", "safestr.c"),
                            os.path.join(RAIZ, "ejemplos", "compilador", "lib",
                                         "sistema_tcodec.c"),
                            "-o", binario_b, "-lm"], capture_output=True, text=True)
        if r.returncode != 0:
            raise SystemExit(f"el C de Python no compila:\n{r.stderr[:600]}")
        b = c_de_tcodec(binario_b)

        if a != b:
            da, db = a.splitlines(), b.splitlines()
            n = next((i for i, (x, y) in enumerate(zip(da, db)) if x != y),
                     min(len(da), len(db)))
            print(f"  FALLA: los dos caminos dan otro C, linea {n + 1}")
            return 1
        print(f"=== DDC: la semilla y Python dan el mismo tcodec ===\n"
              f"    {len(a)} bytes de C, iguales por los dos caminos")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
