"""REGLAS: cada regla rechaza lo que la rompe, por construccion."""

import os
import shutil
import tempfile

from reglas import casos

from .comun import (
    Resultado,
    bloques,
    correr_c,
    en_paralelo,
    tcodec_sobre,
)

TITULO = "cada regla rechaza lo que la rompe, por construccion"


def correr(suite: Resultado) -> None:
    # El oraculo de rechazo que no es ningun compilador: ver `tests/reglas.py`.
    tmp = tempfile.mkdtemp(prefix="tcode-reglas-")
    try:
        todos = list(casos())

        def uno(i_caso):
            i, (nombre, segura, rota, linea, dice) = i_caso
            fallas = []
            dir_rota = os.path.join(tmp, f"{i}-rota")
            dir_segura = os.path.join(tmp, f"{i}-segura")
            os.makedirs(dir_rota)
            os.makedirs(dir_segura)

            r = tcodec_sobre(rota, "--solo-comprobar", directorio=dir_rota)
            errores = bloques(r.stderr, "error: ")
            if r.returncode == 0:
                fallas.append(("la rota no compila", "compilo, y rompe la regla", rota))
            elif not errores or not errores[0].startswith(f"p.t:{linea}: "):
                fallas.append(("el error sale en su linea",
                               f"se esperaba la linea {linea}; salio "
                               f"{(errores or [r.stderr])[0][:300]!r}", rota))
            elif not all(d in errores[0] for d in dice):
                fallas.append(("el error dice que regla rompe",
                               f"se esperaba {dice}; dijo {errores[0][:300]!r}", rota))

            s = tcodec_sobre(segura, "--mostrar-c", directorio=dir_segura)
            if s.returncode != 0:
                fallas.append(("la segura compila",
                               "; ".join(bloques(s.stderr, "error: ")) or s.stderr[:300],
                               segura))
            else:
                try:
                    codigo, _salida, err = correr_c(s.stdout, dir_segura)
                    if codigo != 0 or "Sanitizer" in err or "runtime error" in err:
                        fallas.append(("la segura corre limpia",
                                       f"codigo {codigo}\n{err[:400]}", segura))
                except AssertionError as exc:
                    fallas.append(("el C de la segura compila", str(exc)[:400], segura))
            return nombre, fallas

        rotas = seguras = 0
        for nombre, fallas in en_paralelo(uno, list(enumerate(todos))):
            suite.total += 2
            rotas += 1
            seguras += 1
            for que, detalle, fuente in fallas:
                suite.falla(f"{nombre}: {que}", f"{detalle}\n--- programa ---\n{fuente}")
        reglas = len({n.split(" / ")[0] for n, *_ in todos})
        suite.cifra("reglas", reglas)
        suite.cifra("reglas_pares", len(todos))
        print(f"    {reglas} reglas en {len(todos)} pares: la rota se rechaza en "
              f"su linea, la segura corre limpia bajo ASan")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
