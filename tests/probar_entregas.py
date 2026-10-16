#!/usr/bin/env python3
"""Corre un programa de generador_entregas.py bajo AddressSanitizer.

    python3 tests/probar_entregas.py SEMILLA

Imprime BIEN si da la salida que el generador calcula y los sanitizers no
ven nada; si no, FALLA y por que. Es lo mismo que la propiedad P15 de
test_propiedades.py, para una semilla suelta.
"""

import os
import re
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
TCODEC = os.path.join(os.path.dirname(AQUI), "tcodec")
sys.path.insert(0, AQUI)

import generador_entregas  # noqa: E402

PROBLEMA = re.compile(
    r"ERROR: AddressSanitizer: [a-z-]+|ERROR: LeakSanitizer: [a-z ]+|runtime error")


def main():
    fuente, esperado = generador_entregas.generar(int(sys.argv[1]))
    tmp = tempfile.mkdtemp(prefix="tcode-entregas-")
    ruta = os.path.join(tmp, "p.t")
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(fuente)
    binario = os.path.join(tmp, "p")
    r = subprocess.run([TCODEC, ruta, "-o", binario, "--asan", "--sin-avisos"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("FALLA: no compila\n" + r.stderr)
        return 1
    e = subprocess.run([binario], capture_output=True, text=True,
                       env=dict(os.environ, ASAN_OPTIONS="detect_leaks=1"))
    m = PROBLEMA.search(e.stderr)
    if e.stdout == esperado and e.returncode == 0 and not m:
        print("BIEN")
        return 0
    print("FALLA:", m.group(0) if m else "", "salida", repr(e.stdout),
          "esperada", repr(esperado), "codigo", e.returncode)
    return 1


if __name__ == "__main__":
    sys.exit(main())
