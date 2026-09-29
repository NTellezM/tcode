"""
Las tablas de UAX #31 para los nombres de Tcode, en los dos compiladores.

Un nombre empieza por `_`, una letra ASCII o un caracter XID_Start, y sigue
con `_`, letras y digitos ASCII o caracteres XID_Continue. Las tablas salen
de `unicodedata` de este Python, una vez, y se guardan: los dos compiladores
dicen lo mismo aunque cada uno corra con otro Python.

    python3 tests/generar_xid.py      escribe tcode/xid.py y
                                      ejemplos/lexer/lib/xid.t
"""

import os
import subprocess
import unicodedata

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = os.path.join(RAIZ, "tcode", "xid.py")
TC = os.path.join(RAIZ, "ejemplos", "lexer", "lib", "xid.t")

# Hoja del arbol de busqueda: a partir de aqui, rango a rango.
HOJA = 6


def rangos(pertenece):
    """Los rangos de puntos de codigo no ASCII que cumplen `pertenece`."""
    salida = []
    inicio = None
    for cp in range(128, 0x110000):
        dentro = pertenece(chr(cp))
        if dentro and inicio is None:
            inicio = cp
        elif not dentro and inicio is not None:
            salida.append((inicio, cp - 1))
            inicio = None
    if inicio is not None:
        salida.append((inicio, 0x10FFFF))
    return salida


def es_inicio(c):
    return c.isidentifier()


def es_sigue(c):
    return ("a" + c).isidentifier()


def tabla_py(nombre, rs):
    lineas = [f"{nombre}_DESDE = ("]
    for k in range(0, len(rs), 8):
        lineas.append("    " + " ".join(f"{a},"
                                          for a, _ in rs[k:k + 8]))
    lineas.append(")")
    lineas.append(f"{nombre}_HASTA = (")
    for k in range(0, len(rs), 8):
        lineas.append("    " + " ".join(f"{b},"
                                          for _, b in rs[k:k + 8]))
    lineas.append(")")
    return lineas


def escribir_py(inicio, sigue):
    lineas = [
        '"""Generado por tests/generar_xid.py con Unicode '
        f'{unicodedata.unidata_version}. No editar a mano.',
        "",
        "Los caracteres no ASCII que pueden empezar (XID_Start) y seguir",
        '(XID_Continue) un nombre de Tcode."""',
        "",
        "from bisect import bisect_right",
        "",
        f'UNICODE = "{unicodedata.unidata_version}"',
        "",
        *tabla_py("_INICIO", inicio),
        "",
        *tabla_py("_SIGUE", sigue),
        "",
        "",
        "def _en(cp, desde, hasta):",
        "    i = bisect_right(desde, cp) - 1",
        "    return i >= 0 and cp <= hasta[i]",
        "",
        "",
        "def empieza_nombre(c: str) -> bool:",
        '    if c < "\\x80":',
        '        return c == "_" or "a" <= c <= "z" or "A" <= c <= "Z"',
        "    return _en(ord(c), _INICIO_DESDE, _INICIO_HASTA)",
        "",
        "",
        "def sigue_nombre(c: str) -> bool:",
        '    if c < "\\x80":',
        '        return empieza_nombre(c) or "0" <= c <= "9"',
        "    return _en(ord(c), _SIGUE_DESDE, _SIGUE_HASTA)",
        "",
    ]
    with open(PY, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas))


def arbol(rs, hondo):
    """Busqueda binaria escrita como `if`: sin tablas ni memoria."""
    sangria = "    " * hondo
    if len(rs) <= HOJA:
        salida = []
        for a, b in rs:
            cond = f"c == {a}" if a == b else f"c >= {a} && c <= {b}"
            salida.append(f"{sangria}if {cond} {{ return true; }}")
        salida.append(f"{sangria}return false;")
        return salida
    medio = len(rs) // 2
    return ([f"{sangria}if c < {rs[medio][0]} {{"]
            + arbol(rs[:medio], hondo + 1)
            + [f"{sangria}}}"]
            + arbol(rs[medio:], hondo))


def escribir_tc(inicio, sigue):
    lineas = [
        f"// Generado por tests/generar_xid.py con Unicode "
        f"{unicodedata.unidata_version}. No editar a mano.",
        "//",
        "// Los caracteres no ASCII que pueden empezar (XID_Start) y seguir",
        "// (XID_Continue) un nombre de Tcode, como una busqueda binaria.",
        "",
        "fn xid_inicio(c: usize) -> bool {",
        *arbol(inicio, 1),
        "}",
        "",
        "fn xid_sigue(c: usize) -> bool {",
        *arbol(sigue, 1),
        "}",
        "",
    ]
    with open(TC, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas))


def main():
    inicio = rangos(es_inicio)
    sigue = rangos(es_sigue)
    escribir_py(inicio, sigue)
    escribir_tc(inicio, sigue)
    tcodec = os.path.join(RAIZ, "tcodec")
    if os.path.exists(tcodec):
        subprocess.run([tcodec, TC, "--formatear", "--escribir"], check=True,
                       env=dict(os.environ, TCODE_RAIZ=RAIZ))
    print(f"Unicode {unicodedata.unidata_version}: {len(inicio)} rangos de "
          f"inicio y {len(sigue)} de continuacion")


if __name__ == "__main__":
    main()
