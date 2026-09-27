"""
El compilador escrito con lo que solo sabe `tcodec`, pasado a lo que entiende
el de Python.

`tcodec` esta escrito con llamadas con punto (`xs.anadir(v)`) y con `==`
entre textos (`clase == "para"`). Son solo azucar: `tcodec` los traduce a
`anadir(xs, v)` y a `igual(clase, "para")` antes de escribir C. Aqui se hace
lo mismo sobre el texto, sin mover ninguna linea, para que el compilador de
Python —congelado— siga sirviendo de oraculo sobre el codigo del compilador,
que es el corpus mas grande del repositorio. Y la suite comprueba que es solo
azucar: sin el, el C que escribe `tcodec` es el mismo byte a byte.

    quitar(texto)          el texto sin azucar
    copia_sin_azucar(dir)  el compilador entero sin azucar, en `dir`

Lo que no se sabe deshacer sin saber los tipos —un `==` entre dos textos sin
ningun literal, un rango, una vista implicita al declarar o al devolver— se
queda como esta, y el de Python no entenderia ese archivo: PROGRAMA lo dice.
En el codigo del compilador eso se escribe en su forma larga.
"""

import os
import re
import shutil

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Lo que esta escrito con lo que solo sabe `tcodec`.
CARPETAS = (os.path.join("ejemplos", "compilador"), os.path.join("ejemplos", "lexer"))

_MARCA = re.compile(r"\x00(\d+)\x01")
_PUNTO = re.compile(r"\.([A-Za-z_]\w*)\(")
_IGUALDAD = re.compile(r" (==|!=) ")


def _fin_de_cadena(linea, i):
    """El `"` que cierra la cadena que empieza en `i`; dentro de las llaves
    de una interpolada puede haber otras cadenas."""
    interpolada = linea[i] == "$"
    j = i + (2 if interpolada else 1)
    llaves = 0
    while j < len(linea):
        c = linea[j]
        if c == "\\":
            j += 2
            continue
        if interpolada and c == "{":
            llaves += 1
        elif interpolada and c == "}":
            llaves -= 1
        elif c == '"' and llaves == 0:
            return j
        elif c == '"' or (c == "$" and linea[j + 1:j + 2] == '"'):
            j = _fin_de_cadena(linea, j)
        j += 1
    return len(linea) - 1


def _tapar(linea):
    """La linea con cada cadena cambiada por una marca sin espacios, y el
    comentario del final aparte: asi se busca solo en el codigo."""
    guardadas, salida, i = [], "", 0
    while i < len(linea):
        if linea.startswith("//", i):
            guardadas.append(linea[i:])
            return salida + f"\x00{len(guardadas) - 1}\x01", guardadas
        c = linea[i]
        if c == '"' or (c == "$" and linea[i + 1:i + 2] == '"'):
            j = _fin_de_cadena(linea, i)
            guardadas.append(linea[i:j + 1])
            salida += f"\x00{len(guardadas) - 1}\x01"
            i = j + 1
            continue
        salida += c
        i += 1
    return salida, guardadas


def _destapar(linea, guardadas):
    return _MARCA.sub(lambda m: guardadas[int(m.group(1))], linea)


def _pareja(s, i, paso):
    """Desde el `(`/`[` de `s[i]` hacia delante, o el `)`/`]` hacia atras, el
    que lo cierra."""
    abre, cierra = ("([{", ")]}") if paso > 0 else (")]}", "([{")
    hondo = 0
    while 0 <= i < len(s):
        if s[i] in abre:
            hondo += 1
        elif s[i] in cierra:
            hondo -= 1
            if hondo == 0:
                return i
        i += paso
    return -1


def _es_nombre(c):
    return c.isalnum() or c == "_"


def _receptor(s, punto):
    """Donde empieza lo que va delante del `.` de `s[punto]`: un nombre con
    sus campos, indices y llamadas. -1 si no hay nada."""
    j = punto - 1
    while j >= 0:
        if s[j] in ")]":
            j = _pareja(s, j, -1)
            if j < 0:
                return -1
            j -= 1
            continue
        if _es_nombre(s[j]):
            while j >= 0 and _es_nombre(s[j]):
                j -= 1
            if j >= 0 and s[j] == "." and (j == 0 or s[j - 1] != "."):
                j -= 1
                continue
            break
        break
    return j + 1 if j + 1 < punto else -1


def _sin_punto(s):
    """Una llamada con punto menos: `r.f(a)` -> `f(r, a)`. None si no hay."""
    for m in _PUNTO.finditer(s):
        punto = m.start()
        if punto > 0 and s[punto - 1] == ".":
            continue
        desde = _receptor(s, punto)
        if desde < 0:
            continue
        receptor = s[desde:punto]
        # `G.f(x)` es de un modulo y `Forma.Variante(x)`, de un enum: esos
        # se escriben asi en los dos compiladores.
        if re.fullmatch(r"[A-Z]\w*", receptor):
            continue
        if receptor[0].isdigit():
            continue
        abre = m.end() - 1
        cierra = _pareja(s, abre, 1)
        if cierra < 0:
            continue
        dentro = s[abre + 1:cierra]
        args = receptor + (", " + dentro if dentro.strip() else "")
        return s[:desde] + f"{m.group(1)}({args})" + s[cierra + 1:]
    return None


def _operando_izq(s, i):
    """Donde empieza el operando que acaba en `s[i - 1]`."""
    j = i - 1
    while j >= 0:
        if s[j] in ")]}":
            j = _pareja(s, j, -1)
            if j < 0:
                return -1
            j -= 1
            continue
        if s[j] in " ([{,!":
            break
        j -= 1
    return j + 1


def _operando_der(s, i):
    """Donde acaba (sin incluir) el operando que empieza en `s[i]`."""
    j = i
    while j < len(s):
        if s[j] in "([{":
            j = _pareja(s, j, 1)
            if j < 0:
                return -1
            j += 1
            continue
        if s[j] in " )]},;":
            break
        j += 1
    return j


def _sin_igualdad(s, guardadas):
    """Un `==` o `!=` con un texto escrito a un lado, a `igual`. None si no
    hay."""
    for m in _IGUALDAD.finditer(s):
        desde = _operando_izq(s, m.start())
        hasta = _operando_der(s, m.end())
        if desde < 0 or hasta < 0 or desde == m.start() or hasta == m.end():
            continue
        a, b = s[desde:m.start()], s[m.end():hasta]

        def es_texto(x):
            marca = _MARCA.fullmatch(x)
            return marca is not None and guardadas[int(marca.group(1))].startswith(('"', '$"'))
        if not (es_texto(a) or es_texto(b)):
            continue
        negada = "!" if m.group(1) == "!=" else ""
        return s[:desde] + f"{negada}igual({a}, {b})" + s[hasta:]
    return None


def quitar(texto):
    """`texto` sin llamadas con punto ni `==` entre textos, con las mismas
    lineas."""
    salida = []
    for linea in texto.split("\n"):
        s, guardadas = _tapar(linea)
        for _ in range(500):
            nueva = _sin_punto(s)
            if nueva is None:
                nueva = _sin_igualdad(s, guardadas)
            if nueva is None:
                break
            s = nueva
        salida.append(_destapar(s, guardadas))
    return "\n".join(salida)


def copia_sin_azucar(destino):
    """Las carpetas del compilador, sin azucar, en `destino`, con la misma
    forma que en el repositorio y `std/` al lado: los `usar` valen igual, y
    desde `destino` los mensajes y el C dicen las mismas rutas. Devuelve los
    `.t` copiados."""
    copiados = []
    for carpeta in CARPETAS:
        origen = os.path.join(RAIZ, carpeta)
        for dirpath, _dirs, archivos in os.walk(origen):
            relativo = os.path.relpath(dirpath, RAIZ)
            os.makedirs(os.path.join(destino, relativo), exist_ok=True)
            for nombre in archivos:
                if nombre.startswith("."):
                    continue
                if not nombre.endswith((".t", ".c", ".h")):
                    continue
                de = os.path.join(dirpath, nombre)
                a = os.path.join(destino, relativo, nombre)
                if nombre.endswith(".t"):
                    with open(de, encoding="utf-8") as f:
                        texto = f.read()
                    with open(a, "w", encoding="utf-8") as f:
                        f.write(quitar(texto))
                    copiados.append(a)
                else:
                    shutil.copy2(de, a)
    for enlace in ("std", "runtime"):
        ruta = os.path.join(destino, enlace)
        if not os.path.exists(ruta):
            os.symlink(os.path.join(RAIZ, enlace), ruta)
    return sorted(copiados)
