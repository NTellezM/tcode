"""
El paquete de una version: reproducible, y se construye sin Python.

    python3 tests/paquete.py            escribe dist/tcode-VERSION.tar.gz
                                        y su .sha256
    python3 tests/paquete.py --probar   ademas lo comprueba

El paquete es `git archive` del commit, comprimido con `gzip -n`: sin fechas
ni nombres de archivo dentro del gzip, el mismo commit da siempre los mismos
bytes con las mismas herramientas. Solo se hace con el arbol limpio: lo que
no esta en un commit no puede estar en una version.

`--probar` lo escribe dos veces y compara, lo abre en otro sitio, y alli,
con un PATH en el que solo hay las herramientas de C y de la shell —ni
Python ni nada del repositorio—, construye tcodec desde la semilla,
comprueba su punto fijo, lo instala y compila y corre un programa.
"""

import hashlib
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(RAIZ, "dist")

# Lo unico que hace falta para construir y usar tcodec.
HERRAMIENTAS = ["sh", "make", "cc", "gcc", "as", "ld", "cmp", "mkdir", "mv",
                "rm", "cat", "install", "ln", "head"]


def version():
    with open(os.path.join(RAIZ, "VERSION"), encoding="utf-8") as f:
        return f.read().strip()


def arbol_limpio():
    r = subprocess.run(["git", "status", "--porcelain"], cwd=RAIZ,
                       capture_output=True, text=True, check=True)
    return r.stdout.strip() == ""


def empaquetar(destino_dir):
    """El .tar.gz del commit actual en `destino_dir`, y su sha256."""
    v = version()
    nombre = f"tcode-{v}.tar.gz"
    tar = subprocess.run(["git", "archive", "--format=tar", f"--prefix=tcode-{v}/",
                          "HEAD"], cwd=RAIZ, capture_output=True, check=True).stdout
    comprimido = subprocess.run(["gzip", "-n", "-9"], input=tar,
                                capture_output=True, check=True).stdout
    os.makedirs(destino_dir, exist_ok=True)
    ruta = os.path.join(destino_dir, nombre)
    with open(ruta, "wb") as f:
        f.write(comprimido)
    suma = hashlib.sha256(comprimido).hexdigest()
    with open(ruta + ".sha256", "w", encoding="utf-8") as f:
        f.write(f"{suma}  {nombre}\n")
    return ruta, suma


def path_minimo(dir_bin):
    """Un directorio con enlaces solo a las herramientas de C y de shell."""
    os.makedirs(dir_bin)
    for h in HERRAMIENTAS:
        ruta = shutil.which(h)
        if ruta is None:
            raise SystemExit(f"falta `{h}` para probar el paquete")
        os.symlink(ruta, os.path.join(dir_bin, h))
    return dir_bin


def probar(ruta, suma):
    fallas = []
    with tempfile.TemporaryDirectory() as tmp:
        # Reproducible: otra vez, los mismos bytes.
        _, otra = empaquetar(os.path.join(tmp, "otra"))
        if otra != suma:
            fallas.append(f"dos paquetes del mismo commit difieren: {suma} y {otra}")

        with tarfile.open(ruta) as t:
            t.extractall(tmp, filter="data")
        dentro = os.path.join(tmp, f"tcode-{version()}")
        entorno = {"PATH": path_minimo(os.path.join(tmp, "bin")),
                   "HOME": tmp, "LC_ALL": "C"}
        if shutil.which("python3", path=entorno["PATH"]):
            fallas.append("el PATH de la prueba tiene Python")
        prefijo = os.path.join(tmp, "prefijo")
        with open(os.path.join(tmp, "hola.t"), "w", encoding="utf-8") as f:
            f.write('use "std/texto";\n'
                    'fn main() { imprimir($"{mayusculas("hola")}\\n"); }\n')
        pasos = [
            (["make", "-s", "tcodec", "PY=false"], dentro),
            (["make", "-s", "punto-fijo-cc", "PY=false"], dentro),
            (["./tcodec", "--version"], dentro),
            (["make", "-s", "instalar", f"PREFIJO={prefijo}", "PY=false"], dentro),
            ([os.path.join(prefijo, "bin", "tcodec"), "hola.t", "-o", "hola"], tmp),
            ([os.path.join(tmp, "hola")], tmp),
        ]
        salidas = []
        for orden, donde in pasos:
            r = subprocess.run(orden, cwd=donde, env=entorno, capture_output=True,
                               text=True)
            salidas.append(r)
            if r.returncode != 0:
                fallas.append(f"{' '.join(orden)}: codigo {r.returncode}\n"
                              f"{(r.stderr or r.stdout)[-400:]}")
                break
        else:
            if salidas[2].stdout.strip() != f"tcodec {version()}":
                fallas.append(f"--version dice {salidas[2].stdout.strip()!r}")
            if salidas[5].stdout != "HOLA\n":
                fallas.append(f"el programa dice {salidas[5].stdout!r}")
    return fallas


def main():
    if not arbol_limpio():
        raise SystemExit("hay cambios sin commit: una version sale de un commit")
    ruta, suma = empaquetar(DIST)
    print(f"{os.path.relpath(ruta, RAIZ)}  {suma}")
    if "--probar" not in sys.argv:
        return 0
    fallas = probar(ruta, suma)
    for f in fallas:
        print(f"  FALLA: {f}")
    if not fallas:
        print("    reproducible, y desde el paquete, sin Python: tcodec, su punto "
              "fijo, instalado y un programa")
    return 1 if fallas else 0


if __name__ == "__main__":
    sys.exit(main())
