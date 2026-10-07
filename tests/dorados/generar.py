#!/usr/bin/env python3
"""Los dorados de la seccion EQUIVALE, y su procedencia.

Un dorado es la salida que tiene que dar un programa de Tcode, capturada de
una implementacion que no es `tcodec`. Cada uno vive en `tests/dorados/` con su
receta —`<caso>.receta.json`—, y **sin receta no hay dorado**: la receta dice de
donde salio (herramienta, version, commit), el comando exacto, la entrada, si se
puede regenerar en esta maquina y el sha256 del fichero, para que editarlo a
mano se note.

    python3 tests/dorados/generar.py --lista
    python3 tests/dorados/generar.py --comprobar
    python3 tests/dorados/generar.py --escribir vida          # regenera el suyo
    python3 tests/dorados/generar.py --verificar gb_cabecera
    python3 tests/dorados/generar.py --externo gb_cabecera

Los **regenerables** se regeneran aqui: se compila su referencia en C con las
mismas banderas que la suite y se corre con la misma entrada, y la salida tiene
que ser el dorado byte a byte. Los **externos** no: su receta nombra una
herramienta que no esta instalada en esta maquina, y `--externo` lo dice en voz
alta en vez de inventarse el fichero. Para esos, `--verificar` contrasta el
dorado con una implementacion independiente de lo documentado, que es lo que
hace que la comprobacion valga aunque no se pueda regenerar.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DORADOS = os.path.join(RAIZ, "tests", "dorados")
RUNTIME = os.path.join(RAIZ, "runtime")
GENERADOR = "tests/dorados/generar.py"

# La marca del C que emite `tcodec`.
MARCA_GENERADO = "Generado por el compilador de Tcode"

# Lo que una receta tiene que decir. Sin esto no hay dorado.
CLAVES = ("caso", "origen", "herramienta", "version", "commit", "comando",
          "entrada", "codigo_salida", "regenerable", "generador", "sha256")

# El logo de la boot ROM DMG ($0104-$0133), como lo publica Pan Docs, y los 25
# bytes de cabecera $0134-$014C sobre los que corre el checksum: titulo
# `TCODE`, relleno, codigo de licencia nuevo `00`, banderas a cero, licencia
# vieja $33 y version $00. Solo el modelo independiente del dorado externo los
# usa; el programa Tcode lleva los mismos datos escritos en su fuente.
LOGO_DMG = bytes.fromhex(
    "CEED6666CC0D000B03730083000C000D"
    "0008111F8889000EDCCC6EE6DDDDD999"
    "BBBB67636E0EECCCDDDC999FBBB9333E")
CABECERA_DMG = bytes([84, 67, 79, 68, 69] + [0] * 11 + [48, 48]
                     + [0, 0, 0, 0, 0, 51, 0])


def ruta(caso, extension):
    return os.path.join(DORADOS, f"{caso}.{extension}")


def sha256(ruta_del_fichero):
    with open(ruta_del_fichero, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def casos():
    return sorted(n[:-len(".receta.json")] for n in os.listdir(DORADOS)
                  if n.endswith(".receta.json"))


def leer_receta(caso):
    with open(ruta(caso, "receta.json"), encoding="utf-8") as f:
        return json.load(f)


def revisar(caso, receta):
    """La receta dice lo que tiene que decir, o ValueError."""
    faltan = [k for k in CLAVES if k not in receta]
    if faltan:
        raise ValueError(f"la receta no dice {', '.join(faltan)}")
    if receta["caso"] != caso:
        raise ValueError(f"la receta dice ser `{receta['caso']}`")
    if receta["commit"] is None:
        for clave in ("referencia", "referencia_sha256"):
            if not receta.get(clave):
                raise ValueError(f"sin commit hace falta `{clave}`")
    if not receta["regenerable"] and not receta.get("motivo"):
        raise ValueError("un dorado no regenerable tiene que decir por que")


def correr_referencia(receta, tmp):
    """(codigo_de_salida, stdout) de la referencia en C de la receta."""
    fuente = os.path.join(RAIZ, receta["referencia"])
    binario = os.path.join(tmp, "referencia")
    orden = ["cc", "-std=c17", "-g", "-Wall", "-Wextra", "-Werror",
             f"-I{RUNTIME}", fuente, "-o", binario, "-lm"]
    r = subprocess.run(orden, capture_output=True, text=True)
    if r.returncode != 0:
        raise ValueError("la referencia no compila:\n" + r.stderr)
    e = subprocess.run([binario], capture_output=True, text=True,
                       input=receta["entrada"])
    return e.returncode, e.stdout


def modelo_gb_cabecera():
    """Lo que la boot ROM DMG volcaria, calculado aparte del programa Tcode."""
    lineas = [" ".join(f"{b:02X}" for b in LOGO_DMG[i:i + 8])
              for i in range(0, len(LOGO_DMG), 8)]
    x = 0
    for b in CABECERA_DMG:
        x = (x - b - 1) & 0xFF
    lineas.append(f"checksum 0134-014C: {x:02X}")
    lineas.append(f"logo bytes: {len(LOGO_DMG)}")
    return "\n".join(lineas) + "\n"


# Un modelo independiente por dorado externo: lo documentado, calculado aqui.
MODELOS = {"gb_cabecera": modelo_gb_cabecera}


def verificar(caso, receta):
    """Comprueba el dorado entero: hash, referencia, y que se sostenga.

    Devuelve el mensaje de lo que hizo. ValueError si algo no cuadra.
    """
    fichero = ruta(caso, "golden")
    if not os.path.isfile(fichero):
        raise ValueError(f"falta {os.path.relpath(fichero, RAIZ)}")
    if sha256(fichero) != receta["sha256"]:
        raise ValueError("el sha256 del dorado no es el de la receta; "
                         "alguien lo edito a mano")
    if receta.get("referencia"):
        referencia = os.path.join(RAIZ, receta["referencia"])
        if sha256(referencia) != receta["referencia_sha256"]:
            raise ValueError(f"{receta['referencia']} cambio; regenera el dorado")
    with open(fichero, encoding="utf-8") as f:
        contenido = f.read()
    if MARCA_GENERADO in contenido:
        raise ValueError("el dorado es el C que emite tcodec, no una traza de "
                         "referencia")

    if receta["regenerable"]:
        with tempfile.TemporaryDirectory() as tmp:
            codigo, salida = correr_referencia(receta, tmp)
        if codigo != receta["codigo_salida"]:
            raise ValueError(f"la referencia salio con {codigo}, "
                             f"la receta dice {receta['codigo_salida']}")
        if salida != contenido:
            raise ValueError("la receta no reproduce el dorado byte a byte")
        return (f"`{caso}`: regenerable aqui; "
                f"{receta['referencia']} lo reproduce byte a byte")

    modelo = MODELOS.get(caso)
    if modelo is None:
        return (f"`{caso}`: externo y sin modelo independiente; solo queda su "
                f"sha256 y su receta")
    if modelo() != contenido:
        raise ValueError("el modelo independiente no reproduce el dorado")
    return (f"`{caso}`: NO regenerable aqui — {receta['motivo']} —; el modelo "
            f"independiente lo reproduce")


def escribir(caso):
    receta = leer_receta(caso)
    revisar(caso, receta)
    if not receta["regenerable"]:
        raise SystemExit(f"{caso}: es un dorado externo y no se regenera aqui. "
                         f"Corre `--externo {caso}` en la maquina de la receta.")
    with tempfile.TemporaryDirectory() as tmp:
        codigo, salida = correr_referencia(receta, tmp)
    if codigo != receta["codigo_salida"]:
        raise SystemExit(f"{caso}: la referencia salio con {codigo}")
    with open(ruta(caso, "golden"), "w", encoding="utf-8") as f:
        f.write(salida)
    receta["sha256"] = sha256(ruta(caso, "golden"))
    with open(ruta(caso, "receta.json"), "w", encoding="utf-8") as f:
        json.dump(receta, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"`{caso}`: dorado regenerado desde {receta['referencia']} "
          f"({len(salida)} bytes)")


def externo(caso):
    receta = leer_receta(caso)
    if receta["regenerable"]:
        raise SystemExit(f"{caso}: es regenerable; usa `--escribir {caso}`.")
    print(f"`{caso}`: dorado externo, NO regenerable en esta maquina.")
    print(f"  origen:     {receta['origen']}")
    print(f"  hace falta: {receta['motivo']}")
    print(f"  comando:    {receta['comando']}")
    print(f"  generador:  {receta['generador']}")
    print(f"  aqui:       {receta.get('verificacion', 'sin verificacion')}")
    raise SystemExit(1)


def comprobar(pedidos):
    fallos = 0
    for caso in pedidos:
        try:
            receta = leer_receta(caso)
            revisar(caso, receta)
            print("  " + verificar(caso, receta))
        except (ValueError, OSError, json.JSONDecodeError) as exc:
            fallos += 1
            print(f"  FALLA: {caso}: {exc}")
    print(f"{len(pedidos) - fallos} de {len(pedidos)} dorados en pie")
    return 1 if fallos else 0


def main(argumentos):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--lista", action="store_true")
    p.add_argument("--comprobar", nargs="*", metavar="CASO")
    p.add_argument("--escribir", metavar="CASO")
    p.add_argument("--verificar", metavar="CASO")
    p.add_argument("--externo", metavar="CASO")
    a = p.parse_args(argumentos)

    if a.lista:
        for caso in casos():
            receta = leer_receta(caso)
            se_regenera = "regenerable" if receta["regenerable"] else "externo"
            print(f"{caso:<14} {se_regenera:<12} {receta['origen']}")
        return 0
    if a.escribir:
        escribir(a.escribir)
        return 0
    if a.verificar:
        receta = leer_receta(a.verificar)
        revisar(a.verificar, receta)
        print(verificar(a.verificar, receta))
        return 0
    if a.externo:
        externo(a.externo)
        return 0
    if a.comprobar is not None:
        return comprobar(a.comprobar or casos())
    p.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
