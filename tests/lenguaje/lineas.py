"""LINEAS: el C generado apunta al `.t`, no a si mismo."""

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
    tcodec,
    tcodec_sobre,
)

TITULO = "el C generado apunta al `.t`, no a si mismo"


def correr(suite: Resultado) -> None:
    # Con `#line`, gdb, valgrind, los sanitizers y los perfiladores hablan del
    # codigo que se escribio. Se comprueba que cada directiva señale una linea
    # que existe de verdad, y que el depurador lo vea.
    import re as _re
    _DIRECTIVA = _re.compile(r'^#line (\d+) "(.*)"$')
    tmp = tempfile.mkdtemp(prefix="tcode-lineas-")
    try:
        marcadas = 0
        MUESTRA = ["ejemplos/hola.t", "ejemplos/texto.t", "ejemplos/binario.t",
                   "ejemplos/pruebas.t", "ejemplos/informe/informe.t",
                   "ejemplos/modulos/escalas.t"]
        for relativo in MUESTRA:
            suite.total += 1
            r = subprocess.run([tcodec(), relativo, "--mostrar-c", "--sin-avisos"],
                               cwd=RAIZ, env=ENTORNO_TCODEC, capture_output=True,
                               text=True, timeout=120)
            if r.returncode != 0:
                suite.falla(f"lineas de {relativo}", r.stderr[-400:])
                continue
            codigo = r.stdout
            vistas = 0
            for linea in codigo.splitlines():
                m = _DIRECTIVA.match(linea)
                if not m:
                    continue
                vistas += 1
                n, archivo = int(m.group(1)), os.path.join(RAIZ, m.group(2))
                if not os.path.isfile(archivo):
                    suite.falla(f"lineas de {relativo}",
                          f"`#line {n} \"{archivo}\"` señala un archivo que no existe")
                    break
                with open(archivo, encoding="utf-8") as f:
                    cuantas = sum(1 for _ in f)
                if not 1 <= n <= cuantas:
                    suite.falla(f"lineas de {relativo}",
                          f"`#line {n} \"{archivo}\"` se sale: el archivo tiene "
                          f"{cuantas} lineas")
                    break
            else:
                if vistas == 0:
                    suite.falla(f"lineas de {relativo}", "no hay ninguna directiva `#line`")
                marcadas += vistas

        # Y que el depurador lo vea de verdad, si esta instalado.
        suite.total += 1
        fuente = ("fn hondo(n: usize) -> usize {\n"
                  "    let a = n * 2;\n"
                  "    let b = a - 100;\n"
                  "    return b;\n"
                  "}\n"
                  "fn main() -> usize { imprimir(hondo(3)); }\n")
        r = tcodec_sobre(fuente, "--mostrar-c", "--sin-avisos", directorio=tmp,
                         nombre="hondo.t")
        codigo = r.stdout
        if r.returncode != 0:
            suite.falla("el depurador ve el `.t`", r.stderr[-400:])
        else:
            ruta_c = os.path.join(tmp, "hondo.c")
            binario = os.path.join(tmp, "hondo")
            with open(ruta_c, "w", encoding="utf-8") as f:
                f.write(codigo)
            r = cc(
                ["cc", "-std=c17", "-O0", "-g", f"-I{RUNTIME}", ruta_c,
                 os.path.join(RUNTIME, "safestr.c"), "-o", binario, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                suite.falla("el depurador ve el `.t`", r.stderr[:400])
            elif shutil.which("gdb") is None:
                print("    (sin gdb: no se pudo comprobar la pila)")
            else:
                e = subprocess.run(["gdb", "-batch", "-ex", "run", "-ex", "bt",
                                    binario], capture_output=True, text=True,
                                   timeout=120)
                # Algunos contenedores instalan gdb pero bloquean ptrace. Eso no
                # dice nada sobre las directivas `#line`: se deja constancia y se
                # conserva la comprobacion real donde el depurador puede arrancar.
                sin_ptrace = ("ptrace: Operation not permitted" in e.stderr
                              or "Could not trace the inferior process" in e.stderr)
                if sin_ptrace:
                    print("    (gdb instalado, pero el entorno bloquea ptrace)")
                elif "hondo.t:3" not in e.stdout:
                    suite.falla("el depurador ve el `.t`",
                          "la pila no señala `hondo.t:3`:\n"
                          + (e.stdout + e.stderr)[-600:])
        print(f"    {marcadas} directivas, todas a una linea que existe")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
