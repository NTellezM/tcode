"""SALIDA: el compilador nunca reemplaza sus fuentes."""

import os
import subprocess
import tempfile

from .comun import (
    RAIZ,
    ENTORNO_TCODEC,
    Resultado,
    tcodec,
)

TITULO = "el compilador nunca reemplaza sus fuentes"


def correr(suite: Resultado) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        fuente = os.path.join(tmp, "programa.t")
        contenido = 'fn main() { imprimir("intacto"); }\n'
        with open(fuente, "w", encoding="utf-8") as f:
            f.write(contenido)

        suite.total += 1
        r = subprocess.run([tcodec(), fuente, "-o", fuente], env=ENTORNO_TCODEC,
                           capture_output=True, text=True)
        with open(fuente, encoding="utf-8") as f:
            despues = f.read()
        if r.returncode == 0:
            suite.falla("-o no puede ser el fuente", "el compilador acepto la colision")
        elif despues != contenido:
            suite.falla("-o no puede ser el fuente", "el archivo fuente fue modificado")
        elif "propio archivo fuente" not in r.stderr:
            suite.falla("-o no puede ser el fuente", f"diagnostico inesperado: {r.stderr!r}")

        suite.total += 1
        sin_extension = os.path.join(tmp, "programa")
        with open(sin_extension, "w", encoding="utf-8") as f:
            f.write(contenido)
        r = subprocess.run([tcodec(), sin_extension], env=ENTORNO_TCODEC,
                           capture_output=True, text=True)
        with open(sin_extension, encoding="utf-8") as f:
            despues = f.read()
        if r.returncode == 0 or despues != contenido:
            suite.falla("la salida implicita no pisa un fuente sin extension",
                        f"codigo {r.returncode}, contenido {despues!r}")
        elif "propio archivo fuente" not in r.stderr:
            suite.falla("la salida implicita no pisa un fuente sin extension",
                        f"diagnostico inesperado: {r.stderr!r}")

        suite.total += 1
        binario_previo = os.path.join(tmp, "programa-anterior")
        marca_previa = b"binario anterior intacto\n"
        with open(binario_previo, "wb") as f:
            f.write(marca_previa)
        r = subprocess.run([tcodec(), fuente, "--cc", "/bin/false", "-o", binario_previo],
                           env=ENTORNO_TCODEC, capture_output=True, text=True)
        with open(binario_previo, "rb") as f:
            despues_bin = f.read()
        if r.returncode == 0:
            suite.falla("un fallo de C conserva el binario anterior",
                        "el compilador C falso se considero exitoso")
        elif despues_bin != marca_previa:
            suite.falla("un fallo de C conserva el binario anterior",
                        f"el destino cambio a {despues_bin!r}")

        # Formatear un enlace escribe en lo que apunta: reemplazarlo lo convertia
        # en un archivo suelto y dejaba el original sin tocar.
        suite.total += 1
        real = os.path.join(tmp, "real.t")
        enlace = os.path.join(tmp, "enlace.t")
        with open(real, "w", encoding="utf-8") as f:
            f.write('fn main() {\nimprimir("a");\n}\n')
        os.symlink(real, enlace)
        r = subprocess.run([tcodec(), enlace, "--formatear", "--escribir"],
                           env=ENTORNO_TCODEC, capture_output=True, text=True)
        with open(real, encoding="utf-8") as f:
            formateado = f.read()
        if r.returncode != 0 or not os.path.islink(enlace):
            suite.falla("formatear un enlace conserva el enlace",
                        f"codigo {r.returncode}, enlace {os.path.islink(enlace)}")
        elif '    imprimir("a");' not in formateado:
            suite.falla("formatear un enlace conserva el enlace",
                        f"el original no se formateo: {formateado!r}")

        # Un binario nuevo respeta el `umask`, como lo haria `cc -o`.
        suite.total += 1
        nuevo_bin = os.path.join(tmp, "con-umask")
        r = subprocess.run(
            ["sh", "-c", 'umask 027 && exec "$@"', "sh", tcodec(), fuente, "-o", nuevo_bin],
            env=ENTORNO_TCODEC, capture_output=True, text=True)
        modo = os.stat(nuevo_bin).st_mode & 0o777 if os.path.exists(nuevo_bin) else None
        if r.returncode != 0 or modo != 0o750:
            suite.falla("un binario nuevo respeta el umask",
                        f"codigo {r.returncode}, modo {oct(modo) if modo else None}, "
                        f"stderr {r.stderr[:300]!r}")

        # Una sola version: la de `VERSION` y la que dice tcodec.
        suite.total += 1
        with open(os.path.join(RAIZ, "VERSION"), encoding="utf-8") as f:
            version = f.read().strip()
        dice_tcodec = subprocess.run([tcodec(), "--version"], env=ENTORNO_TCODEC,
                                     capture_output=True, text=True).stdout.strip()
        if dice_tcodec != f"tcodec {version}":
            suite.falla("una sola version",
                        f"VERSION {version!r}, tcodec {dice_tcodec!r}")

        # Instalado en un prefijo, compila desde cualquier sitio y sin
        # `TCODE_RAIZ`, tambien con `std/`; y desinstalado no deja nada.
        suite.total += 1
        prefijo = os.path.join(tmp, "prefijo")
        fuera = os.path.join(tmp, "fuera")
        os.makedirs(fuera)
        with open(os.path.join(fuera, "h.t"), "w", encoding="utf-8") as f:
            f.write('usar "std/texto";\n'
                    'fn main() { imprimir($"{mayusculas("hola")}\\n"); }\n')
        sin_raiz = {k: v for k, v in os.environ.items() if k != "TCODE_RAIZ"}
        pasos = [
            ["make", "-s", "-C", RAIZ, "instalar", f"PREFIJO={prefijo}"],
            [os.path.join(prefijo, "bin", "tcodec"), "h.t", "-o", "h"],
            [os.path.join(fuera, "h")],
            ["make", "-s", "-C", RAIZ, "desinstalar", f"PREFIJO={prefijo}"],
        ]
        salidas = [subprocess.run(p, cwd=fuera, env=sin_raiz, capture_output=True,
                                  text=True) for p in pasos]
        quedan = [os.path.relpath(os.path.join(d, n), prefijo)
                  for d, _, ns in os.walk(prefijo) for n in ns]
        if any(s.returncode != 0 for s in salidas) or salidas[2].stdout != "HOLA\n":
            malo = next((s for s in salidas if s.returncode != 0), salidas[2])
            suite.falla("instalar, compilar fuera y desinstalar",
                        f"{malo.args[0]}: codigo {malo.returncode}, "
                        f"{(malo.stderr or malo.stdout)[:300]!r}")
        elif quedan:
            suite.falla("instalar, compilar fuera y desinstalar",
                        f"desinstalar deja {quedan}")
