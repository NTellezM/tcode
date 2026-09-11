"""Analisis lexico de Tcode."""

from dataclasses import dataclass

PALABRAS = {
    "fn", "let", "var", "mut", "if", "else", "while", "return",
    "true", "false", "str", "view", "usize", "i64", "bool", "lista", "struct",
    "usar", "try", "sino", "falla", "mapa",
    "for", "en", "break", "continue",
}

# Los de mas caracteres primero: "+?" tiene que ganarle a "+".
SIMBOLOS = [
    "+?", "-?", "*?", "->", "==", "!=", "<=", ">=", "&&", "||",
    "(", ")", "{", "}", "[", "]", ",", ";", ":", ".", "=", "+", "-", "*", "/",
    "%", "<", ">", "!", "&", "$",
]


class ErrorLexico(Exception):
    pass


@dataclass
class Token:
    tipo: str      # ident | entero | cadena | palabra | simbolo | fin
    valor: str
    linea: int
    col: int

    def __repr__(self):
        return f"{self.tipo}:{self.valor!r}@{self.linea}"


def tokenizar(fuente: str, archivo: str = "<entrada>") -> list:
    toks = []
    i = 0
    linea = 1
    inicio_linea = 0
    n = len(fuente)

    def col():
        return i - inicio_linea + 1

    while i < n:
        c = fuente[i]

        if c == "\n":
            linea += 1
            i += 1
            inicio_linea = i
            continue

        if c in " \t\r":
            i += 1
            continue

        # comentarios
        if fuente.startswith("//", i):
            while i < n and fuente[i] != "\n":
                i += 1
            continue
        if fuente.startswith("/*", i):
            fin = fuente.find("*/", i + 2)
            if fin < 0:
                raise ErrorLexico(f"{archivo}:{linea}: comentario /* sin cerrar")
            linea += fuente.count("\n", i, fin)
            i = fin + 2
            continue

        # cadena interpolada: $"hola {nombre}, van {n} veces"
        if c == "$" and i + 1 < n and fuente[i + 1] == '"':
            c0, l0 = col(), linea
            i += 2
            partes = []
            while True:
                if i >= n or fuente[i] == "\n":
                    raise ErrorLexico(f"{archivo}:{l0}: cadena sin cerrar")
                if fuente[i] == '"':
                    i += 1
                    break
                if fuente[i] == "\\":
                    if i + 1 >= n:
                        raise ErrorLexico(f"{archivo}:{l0}: escape sin cerrar")
                    esc = fuente[i + 1]
                    mapa = {"n": "\n", "t": "\t", "\\": "\\", '"': '"',
                            "0": "\0", "{": "{", "}": "}"}
                    if esc not in mapa:
                        raise ErrorLexico(
                            f"{archivo}:{linea}: escape desconocido \\{esc}")
                    partes.append(mapa[esc])
                    i += 2
                    continue
                partes.append(fuente[i])
                i += 1
            toks.append(Token("interpolada", "".join(partes), l0, c0))
            continue

        # cadena
        if c == '"':
            c0, l0 = col(), linea
            i += 1
            partes = []
            while True:
                if i >= n or fuente[i] == "\n":
                    raise ErrorLexico(f"{archivo}:{l0}: cadena sin cerrar")
                if fuente[i] == '"':
                    i += 1
                    break
                if fuente[i] == "\\":
                    if i + 1 >= n:
                        raise ErrorLexico(f"{archivo}:{l0}: escape sin cerrar")
                    esc = fuente[i + 1]
                    mapa = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "0": "\0"}
                    if esc not in mapa:
                        raise ErrorLexico(
                            f"{archivo}:{linea}: escape desconocido \\{esc}")
                    partes.append(mapa[esc])
                    i += 2
                    continue
                partes.append(fuente[i])
                i += 1
            toks.append(Token("cadena", "".join(partes), l0, c0))
            continue

        # numero
        if c.isdigit():
            c0 = col()
            j = i
            while j < n and (fuente[j].isdigit() or fuente[j] == "_"):
                j += 1
            if j < n and (fuente[j].isalpha() or fuente[j] == "."):
                raise ErrorLexico(
                    f"{archivo}:{linea}: numero mal formado cerca de "
                    f"{fuente[i:j+1]!r}")
            toks.append(Token("entero", fuente[i:j].replace("_", ""), linea, c0))
            i = j
            continue

        # identificador o palabra reservada
        if c.isalpha() or c == "_":
            c0 = col()
            j = i
            while j < n and (fuente[j].isalnum() or fuente[j] == "_"):
                j += 1
            palabra = fuente[i:j]
            toks.append(Token("palabra" if palabra in PALABRAS else "ident",
                              palabra, linea, c0))
            i = j
            continue

        # simbolo
        for s in SIMBOLOS:
            if fuente.startswith(s, i):
                toks.append(Token("simbolo", s, linea, col()))
                i += len(s)
                break
        else:
            raise ErrorLexico(f"{archivo}:{linea}: caracter inesperado {c!r}")

    toks.append(Token("fin", "", linea, 1))
    return toks
