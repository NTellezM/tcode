"""ESPECIFICACION: lo que dice docs/ESPECIFICACION.md es lo que hace tcodec."""

import os
import re
import tempfile

from .comun import (
    RAIZ,
    Resultado,
    bloques,
    correr_c,
    tcodec_sobre,
)

TITULO = "lo que dice la especificacion es lo que hace tcodec"

ESPEC = os.path.join(RAIZ, "docs", "ESPECIFICACION.md")
COMPROBAR = os.path.join(RAIZ, "ejemplos", "compilador", "lib", "comprobar.t")


def _internas_de_tcodec():
    """Los nombres que conoce `firma_interna`: la lista de verdad."""
    with open(COMPROBAR, encoding="utf-8") as f:
        texto = f.read()
    inicio = texto.index("fn firma_interna(")
    cuerpo = texto[inicio:texto.index("\n}\n", inicio)]
    return set(re.findall(r'nombre == "(\w+)"', cuerpo))


def _internas_del_indice(espec):
    """Los nombres de la tabla del indice de funciones internas."""
    inicio = espec.index("### Índice de funciones internas")
    fin = espec.index("\n### ", inicio + 1)
    nombres = set()
    for linea in espec[inicio:fin].splitlines():
        if linea.startswith("| `"):
            firma = linea.split("|")[1]
            nombres.update(re.findall(r"(\w+)\(", firma))
    return nombres


def correr(suite: Resultado) -> None:
    with open(ESPEC, encoding="utf-8") as f:
        espec = f.read()

    # El indice nombra todas las internas, y solo esas.
    suite.total += 1
    de_tcodec = _internas_de_tcodec()
    del_indice = _internas_del_indice(espec)
    if de_tcodec != del_indice:
        suite.falla("el indice de funciones internas es el de tcodec",
                    f"faltan en el indice: {sorted(de_tcodec - del_indice)}; "
                    f"sobran: {sorted(del_indice - de_tcodec)}")

    # El programa de muestra de la gramatica compila, corre limpio y ya esta
    # en formato canonico.
    bloques_muestra = re.findall(r"```tcode muestra\n(.*?)```", espec, re.S)
    suite.total += 1
    if len(bloques_muestra) != 1:
        suite.falla("la gramatica trae su programa de muestra",
                    f"hay {len(bloques_muestra)} bloques `tcode muestra`")
    else:
        muestra = bloques_muestra[0]
        with tempfile.TemporaryDirectory() as tmp:
            r = tcodec_sobre(muestra, "--mostrar-c", directorio=tmp)
            if r.returncode != 0:
                suite.falla("el programa de muestra compila",
                            "; ".join(bloques(r.stderr, "error: ")) or r.stderr[:400])
            else:
                codigo, _salida, err = correr_c(r.stdout, tmp)
                if codigo != 0 or "Sanitizer" in err or "runtime error" in err:
                    suite.falla("el programa de muestra corre limpio",
                                f"codigo {codigo}\n{err[:400]}")
            suite.total += 1
            f = tcodec_sobre(muestra, "--formatear", directorio=tmp)
            if f.returncode != 0 or f.stdout != muestra:
                suite.falla("el programa de muestra esta en formato canonico",
                            f.stderr[:300] or "--formatear lo cambia")

    # Ya no es un borrador de v0.
    suite.total += 1
    if re.search(r"\bv0\b", espec):
        suite.falla("la especificacion no habla de v0",
                    "queda algun `v0`: lo que dice tiene que ser lo de ahora")

    suite.cifra("internas", len(de_tcodec))
    print(f"    {len(de_tcodec)} funciones internas en el indice, y el programa "
          f"de muestra de la gramatica compila y corre limpio")
