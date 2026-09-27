"""EJEMPLOS: los de ejemplos/ compilan y corren limpios."""

import os
import shutil
import subprocess
import tempfile

from compilar_c import cc

from .comun import (
    ENTORNO_TCODEC,
    RAIZ,
    RUNTIME,
    Resultado,
    en_paralelo,
    tcodec,
)

TITULO = "los de ejemplos/ compilan y corren limpios"


def correr(suite: Resultado) -> None:
    # La vitrina del lenguaje tiene que estar tan comprobada como el resto: si un
    # ejemplo filtra memoria, lo primero que lee alguien filtra memoria.
    EJEMPLOS = [
        ("ejemplos/hola.t", []),
        ("ejemplos/texto.t", []),
        ("ejemplos/inventario.t", []),
        ("ejemplos/contar.t", ["README.md"]),
        ("ejemplos/ordenar.t", ["README.md"]),
        ("ejemplos/frecuencia.t", ["README.md"]),
        ("ejemplos/informe/informe.t", []),
        ("ejemplos/modulos/escalas.t", []),
        ("ejemplos/binario.t", []),
        ("ejemplos/pruebas.t", []),
        ("ejemplos/lexer/lexer.t", ["ejemplos/hola.t"]),
        ("ejemplos/lexer/parser.t", ["ejemplos/hola.t"]),
    ]
    tmp = tempfile.mkdtemp(prefix="tcode-ejemplos-")
    try:
        trabajos = []
        for relativo, args in EJEMPLOS:
            suite.total += 1
            r = subprocess.run([tcodec(), relativo, "--mostrar-c", "--sin-avisos"],
                               cwd=RAIZ, env=ENTORNO_TCODEC, capture_output=True,
                               text=True, timeout=180)
            if r.returncode != 0:
                suite.falla(f"ejemplo {relativo}", r.stderr[-600:])
                continue
            codigo = r.stdout
            base = os.path.join(tmp, relativo.replace("/", "_")[:-2])
            with open(base + ".c", "w", encoding="utf-8") as f:
                f.write(codigo)
            trabajos.append((relativo, args, base))

        def _correr_ejemplo(trabajo):
            _, args, base = trabajo
            r = cc(
                ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 f"-I{RUNTIME}", base + ".c", os.path.join(RUNTIME, "safestr.c"),
                 "-o", base, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                return r.stderr[:600]
            e = subprocess.run([base] + [os.path.join(RAIZ, a) for a in args],
                               capture_output=True, text=True, timeout=180,
                               cwd=RAIZ)
            if e.returncode != 0 or e.stderr.strip():
                return f"codigo {e.returncode}\n{e.stderr[:600]}"
            return None

        for (relativo, _, _), problema in zip(trabajos,
                                              en_paralelo(_correr_ejemplo, trabajos)):
            if problema:
                suite.falla(f"ejemplo {relativo}", problema)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
