"""PROGRAMAS: programas de uso real, contra un oraculo que no es Tcode."""

import json
import os
import random
import re
import shutil
import subprocess
import tempfile

from compilar_c import cc

from .comun import (
    ENTORNO_TCODEC,
    RAIZ,
    RUNTIME,
    SANITIZERS,
    Resultado,
    en_paralelo,
    tcodec,
)

TITULO = "programas de uso real, contra un oraculo que no es Tcode"

# Casos al azar por programa, siempre los mismos: la semilla es fija.
CASOS = 40
MAXIMO = 2**63 - 1
MINIMO = -(2**63)
C = dict(os.environ, LC_ALL="C")


# ---------- oraculos ----------

class _Para(Exception):
    """La cuenta que en Tcode para el programa."""


def _calc_linea(texto):
    """Lo que dice `calc` de una linea: el numero, `error`, o `_Para` si la
    aritmetica comprobada tiene que parar el programa. Se evalua a la vez que
    se lee, como el programa: una cuenta que se sale antes de un error de
    sintaxis para el programa."""
    pos = [0]

    def mirar():
        while pos[0] < len(texto) and texto[pos[0]] in " \t":
            pos[0] += 1
        return texto[pos[0]] if pos[0] < len(texto) else ""

    def cabe(v):
        if not MINIMO <= v <= MAXIMO:
            raise _Para
        return v

    class _Error(Exception):
        pass

    def factor():
        c = mirar()
        if c == "-":
            pos[0] += 1
            return cabe(-factor())
        if c == "(":
            pos[0] += 1
            v = expr()
            if mirar() != ")":
                raise _Error
            pos[0] += 1
            return v
        if not c.isascii() or not c.isdigit():
            raise _Error
        v = 0
        while pos[0] < len(texto) and texto[pos[0]] in "0123456789":
            v = cabe(cabe(v * 10) + int(texto[pos[0]]))
            pos[0] += 1
        return v

    def termino():
        v = factor()
        while mirar() in ("*", "/", "%") and mirar():
            op = mirar()
            pos[0] += 1
            w = factor()
            if op == "*":
                v = cabe(v * w)
            else:
                if w == 0:
                    raise _Para
                q = abs(v) // abs(w) * (1 if (v < 0) == (w < 0) else -1)
                v = cabe(q) if op == "/" else v - q * w
        return v

    def expr():
        v = termino()
        while mirar() in ("+", "-") and mirar():
            op = mirar()
            pos[0] += 1
            w = termino()
            v = cabe(v + w if op == "+" else v - w)
        return v

    try:
        v = expr()
        if mirar() != "":
            return "error"
        return str(v)
    except _Error:
        return "error"


def _vida(filas, generaciones):
    alto, ancho = len(filas), len(filas[0])
    vivas = {(x, y) for y in range(alto) for x in range(ancho) if filas[y][x] == "#"}
    for _ in range(generaciones):
        nuevas = set()
        for y in range(alto):
            for x in range(ancho):
                n = sum((x + dx, y + dy) in vivas for dx in (-1, 0, 1)
                        for dy in (-1, 0, 1) if dx or dy)
                if n == 3 or n == 2 and (x, y) in vivas:
                    nuevas.add((x, y))
        vivas = nuevas
    return "".join("".join("#" if (x, y) in vivas else "." for x in range(ancho))
                   + "\n" for y in range(alto))


# ---------- entradas al azar ----------

def _lineas(r, con_cero):
    trozos = ["a", "b", "A", "Z", "0", "9", " ", "\t", "\r", "~", "!", "",
              "\xe9", "\xf1", "\x7f", "\xff", "ab", "Ab"]
    if con_cero:
        trozos.append("\x00")
    lineas = ["".join(r.choice(trozos) for _ in range(r.randint(0, 6)))
              for _ in range(r.randint(0, 60))]
    texto = "\n".join(lineas)
    if lineas and r.random() < 0.7:
        texto += "\n"
    return texto.encode("latin-1")


def _expresion(r, hondo=0):
    grandes = [MAXIMO, MAXIMO - 1, 2**62, 3037000499, 3037000500, 10**18]
    if hondo > 3 or r.random() < 0.3:
        n = r.choice([r.randint(0, 20), r.randint(0, 10**6), r.choice(grandes)])
        return str(n)
    if r.random() < 0.15:
        return "-" + _expresion(r, hondo + 1)
    if r.random() < 0.2:
        return "(" + _expresion(r, hondo + 1) + ")"
    op = r.choice(["+", "-", "*", "/", "%", "*", "+"])
    return f"{_expresion(r, hondo + 1)} {op} {_expresion(r, hondo + 1)}"


def _cuentas(r):
    rotas = ["2 +", "(3", "4 4", "a", "()", "1 2 +", "--", "((1)"]
    lineas = []
    for _ in range(r.randint(1, 8)):
        lineas.append(r.choice(rotas) if r.random() < 0.15 else _expresion(r))
    return lineas


# ---------- la seccion ----------

def _valor_json(r, hondo=0):
    """Un JSON al azar, con hondo acotado para que no reviente el arbol."""
    if hondo > 4:
        return r.choice([None, True, False, r.randint(-10**6, 10**6)])
    clase = r.randint(0, 5)
    if clase == 0:
        return None
    if clase == 1:
        return r.choice([True, False])
    if clase == 2:
        return r.randint(-10**6, 10**6)
    if clase == 3:
        return r.random() * r.choice([1, 1000, 0.001])
    if clase == 4:
        return [_valor_json(r, hondo + 1) for _ in range(r.randint(0, 4))]
    return {f"k{chr(97 + i)}{r.randint(0, 9)}": _valor_json(r, hondo + 1)
            for i in range(r.randint(0, 4))}


def correr(suite: Resultado) -> None:
    tmp = tempfile.mkdtemp(prefix="tcode-programas-")
    try:
        binarios = {}
        for nombre in ("wc", "base64", "ordenar", "buscar", "calc", "vida", "json"):
            suite.total += 1
            fuente = os.path.join(RAIZ, "programas", nombre + ".t")
            r = subprocess.run([tcodec(), fuente, "--mostrar-c"], capture_output=True,
                               text=True, env=ENTORNO_TCODEC)
            if r.returncode != 0:
                suite.falla(f"{nombre} compila", r.stderr[:600])
                continue
            ruta_c = os.path.join(tmp, nombre + ".c")
            with open(ruta_c, "w", encoding="utf-8") as f:
                f.write(r.stdout)
            binario = os.path.join(tmp, nombre)
            e = cc(["cc", *SANITIZERS, f"-I{RUNTIME}", ruta_c,
                    os.path.join(RUNTIME, "safestr.c"), "-o", binario, "-lm"],
                   capture_output=True, text=True)
            if e.returncode != 0:
                suite.falla(f"{nombre}: su C compila", e.stderr[:600])
                continue
            binarios[nombre] = binario

        def corre(orden, entrada=b"", env=None):
            return subprocess.run(orden, input=entrada, capture_output=True,
                                  timeout=60, cwd=tmp, env=env)

        def limpio(nombre, r):
            texto = r.stderr.decode("utf-8", "replace")
            if "Sanitizer" in texto or "runtime error" in texto:
                return f"{nombre}: un sanitizer dijo algo:\n{texto[:600]}"
            return None

        casos = []
        for k in range(CASOS):
            casos.append(("wc", k))
            casos.append(("base64", k))
            casos.append(("ordenar", k))
            casos.append(("buscar", k))
            casos.append(("calc", k))
            casos.append(("vida", k))
            casos.append(("json", k))

        def uno(caso):
            nombre, k = caso
            if nombre not in binarios:
                return None
            r = random.Random(f"{nombre}:{k}")
            yo = binarios[nombre]
            propio = os.path.join(tmp, f"{nombre}-{k}")

            if nombre == "wc":
                rutas = []
                for j in range(r.randint(1, 3)):
                    ruta = f"{propio}-{j}"
                    with open(ruta, "wb") as f:
                        f.write(r.randbytes(r.randint(0, 400)) if r.random() < 0.5
                                else _lineas(r, True))
                    rutas.append(ruta)
                dado = corre([yo, *rutas])
                esperado = corre(["wc", *rutas], env=C)
                mio = [ln.split() for ln in dado.stdout.decode().splitlines()]
                suyo = [ln.split() for ln in esperado.stdout.decode().splitlines()]
                return limpio(nombre, dado) or (
                    None if mio == suyo else f"wc {k}: {mio} contra {suyo}")

            if nombre == "base64":
                datos = r.randbytes(r.randint(0, 3000))
                dado = corre([yo], datos)
                esperado = corre(["base64"], datos)
                vuelta = corre([yo, "-d"], dado.stdout)
                if limpio(nombre, dado) or limpio(nombre, vuelta):
                    return limpio(nombre, dado) or limpio(nombre, vuelta)
                if dado.stdout != esperado.stdout:
                    return f"base64 {k}: codifica distinto que `base64`"
                if vuelta.stdout != datos:
                    return f"base64 {k}: `-d` no devuelve los datos"
                roto = bytearray(esperado.stdout or b"QQ==\n")
                roto[r.randrange(len(roto))] = ord(r.choice("$*.-_ "))
                mal = corre([yo, "-d"], bytes(roto))
                suyo_mal = corre(["base64", "-d"], bytes(roto))
                if limpio(nombre, mal):
                    return limpio(nombre, mal)
                if (mal.returncode == 0) != (suyo_mal.returncode == 0):
                    return (f"base64 {k}: con {bytes(roto)[:40]!r} sale "
                            f"{mal.returncode} y `base64 -d` {suyo_mal.returncode}")
                return None

            if nombre == "ordenar":
                ruta = propio + ".txt"
                with open(ruta, "wb") as f:
                    f.write(_lineas(r, True))
                opciones = r.choice([[], ["-r"], ["-u"], ["-ru"]])
                dado = corre([yo, *opciones, ruta])
                esperado = corre(["sort", *opciones, ruta], env=C)
                return limpio(nombre, dado) or (
                    None if dado.stdout == esperado.stdout
                    else f"ordenar {k} {opciones}: distinto que `sort`")

            if nombre == "buscar":
                ruta = propio + ".txt"
                with open(ruta, "wb") as f:
                    f.write(_lineas(r, False))
                aguja = r.choice(["a", "b", "Ab", "ab", "", "\t", "zz", "9 "])
                opciones = [o for o in ("-n", "-v", "-i") if r.random() < 0.4]
                dado = corre([yo, *opciones, aguja, ruta])
                esperado = corre(["grep", "-F", "-a", *opciones, "-e", aguja, ruta],
                                 env=C)
                if limpio(nombre, dado):
                    return limpio(nombre, dado)
                if (dado.stdout, dado.returncode) != (esperado.stdout, esperado.returncode):
                    return (f"buscar {k} {opciones} {aguja!r}: sale {dado.returncode}, "
                            f"`grep -F` {esperado.returncode}")
                return None

            if nombre == "calc":
                lineas = _cuentas(r)
                esperado = []
                para = False
                for ln in lineas:
                    try:
                        esperado.append(_calc_linea(ln))
                    except _Para:
                        para = True
                        break
                dado = corre([yo], "\n".join(lineas).encode() + b"\n")
                if limpio(nombre, dado):
                    return limpio(nombre, dado)
                salida = dado.stdout.decode().splitlines()
                if salida != esperado:
                    return f"calc {k}: {lineas} da {salida}, se esperaba {esperado}"
                if para != (dado.returncode != 0):
                    return (f"calc {k}: {lineas} sale con {dado.returncode}, y "
                            f"{'tenia' if para else 'no tenia'} que parar")
                if para and not re.search(
                        rb"desbordamiento|division por cero", dado.stderr):
                    return f"calc {k}: para sin decir por que: {dado.stderr[:200]!r}"
                return None

            if nombre == "json":
                valor = _valor_json(r)
                texto = json.dumps(valor, ensure_ascii=True)
                dado = corre([yo, "-c"], texto.encode())
                if limpio(nombre, dado):
                    return limpio(nombre, dado)
                if dado.returncode != 0:
                    return (f"json {k}: rechaza {texto[:80]!r}: "
                            f"{dado.stderr[:200]!r}")
                try:
                    vuelto = json.loads(dado.stdout)
                except Exception as e:
                    return (f"json {k}: no se vuelve a leer: "
                            f"{dado.stdout[:120]!r} ({e})")
                if vuelto != valor:
                    return (f"json {k}: {texto[:80]!r} vuelve {vuelto!r}, "
                            f"se esperaba {valor!r}")
                mal = corre([yo, "-c"], texto.encode() + b"x")
                if limpio(nombre, mal):
                    return limpio(nombre, mal)
                if mal.returncode == 0:
                    return f"json {k}: acepta basura detras de {texto[:80]!r}"
                return None

            ancho, alto = r.randint(1, 12), r.randint(1, 12)
            filas = ["".join(r.choice(".#") for _ in range(ancho)) for _ in range(alto)]
            generaciones = r.randint(0, 8)
            ruta = propio + ".txt"
            with open(ruta, "w", encoding="utf-8") as f:
                f.write("\n".join(filas) + "\n")
            dado = corre([yo, ruta, str(generaciones)])
            return limpio(nombre, dado) or (
                None if dado.stdout.decode() == _vida(filas, generaciones)
                else f"vida {k}: distinta tras {generaciones} generaciones")

        for caso, falla in zip(casos, en_paralelo(uno, casos)):
            suite.total += 1
            if falla:
                suite.falla(f"programa {caso[0]}", falla)
        suite.cifra("programas_reales", len(binarios))
        suite.cifra("programas_casos", len(casos))
        print(f"    {len(binarios)} programas, {len(casos)} casos contra "
              f"wc, base64, sort, grep y oraculos en Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
