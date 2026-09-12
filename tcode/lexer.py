"""Analisis lexico de Tcode."""

from dataclasses import dataclass

PALABRAS = {
    "fn", "let", "var", "mut", "if", "else", "while", "return",
    "true", "false", "str", "view", "bool", "lista", "struct",
    "usar", "try", "sino", "falla", "mapa",
    "for", "en", "break", "continue",
    # Enteros: el ancho va en el nombre, menos en `usize`, que mide cosas de
    # la maquina y por eso vale lo que valga ahi.
    "u8", "u16", "u32", "u64", "usize",
    "i8", "i16", "i32", "i64",
    "f32", "f64",
}

# Los de mas caracteres primero: "+?" tiene que ganarle a "+".
SIMBOLOS = [
    "<<", ">>", "+?", "-?", "*?", "/?", "->", "==", "!=", "<=", ">=", "&&", "||",
    "(", ")", "{", "}", "[", "]", ",", ";", ":", ".", "=", "+", "-", "*", "/",
    "%", "<", ">", "!", "&", "|", "^", "~", "?", "$",
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


def tokenizar(fuente: str, archivo: str = "<entrada>",
              con_comentarios: bool = False) -> list:
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
            c0, j = col(), i
            while i < n and fuente[i] != "\n":
                i += 1
            if con_comentarios:
                toks.append(Token("comentario", fuente[j:i], linea, c0))
            continue
        if fuente.startswith("/*", i):
            c0, l0 = col(), linea
            fin = fuente.find("*/", i + 2)
            if fin < 0:
                raise ErrorLexico(f"{archivo}:{linea}: comentario /* sin cerrar")
            if con_comentarios:
                toks.append(Token("comentario", fuente[i:fin + 2], l0, c0))
            linea += fuente.count("\n", i, fin)
            i = fin + 2
            continue

        # cadena interpolada: $"hola {nombre}, van {n} veces"
        if c == "$" and i + 1 < n and fuente[i + 1] == '"':
            c0, l0 = col(), linea
            i += 2
            partes = []
            # Dentro de `{...}` va una expresion, y una expresion puede llevar
            # cadenas: `$"{unir(xs, ", ")}"`. Se lleva la cuenta de llaves para
            # no cortar en la comilla equivocada.
            prof = 0
            while True:
                if i >= n or fuente[i] == "\n":
                    # Puede faltar la comilla o puede faltar un `}`: desde
                    # aqui no se distingue, asi que se dicen las dos.
                    raise ErrorLexico(
                        f"{archivo}:{l0}: cadena interpolada sin cerrar; "
                        f"falta la comilla, o falta `}}` en algun hueco")
                if fuente[i] == "{":
                    prof += 1
                elif fuente[i] == "}" and prof:
                    prof -= 1
                if fuente[i] == '"' and prof == 0:
                    i += 1
                    break
                if fuente[i] == "\\":
                    if i + 1 >= n:
                        raise ErrorLexico(f"{archivo}:{l0}: escape sin cerrar")
                    esc = fuente[i + 1]
                    if esc == "x":
                        # `\xNN`: un byte escrito en hexadecimal. Hace falta
                        # para poner en una cadena lo que no es texto.
                        hexa = fuente[i + 2:i + 4]
                        if len(hexa) < 2 or any(
                                c not in "0123456789abcdefABCDEF" for c in hexa):
                            raise ErrorLexico(
                                f"{archivo}:{linea}: `\\x` lleva dos digitos "
                                f"hexadecimales detras, como `\\x0a`")
                        partes.append(chr(0xDC00 + int(hexa, 16)))
                        i += 4
                        continue
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
                    if esc == "x":
                        hexa = fuente[i + 2:i + 4]
                        if len(hexa) < 2 or any(
                                c not in "0123456789abcdefABCDEF" for c in hexa):
                            raise ErrorLexico(
                                f"{archivo}:{linea}: `\\x` lleva dos digitos "
                                f"hexadecimales detras, como `\\x0a`")
                        partes.append(chr(0xDC00 + int(hexa, 16)))
                        i += 4
                        continue
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

            # Decimal: el punto tiene que llevar un digito a cada lado. `1.`
            # y `.5` no valen, porque `1.largo()` seria ambiguo y `.5` se
            # confunde con el acceso a un campo.
            decimal = False
            if (j + 1 < n and fuente[j] == "." and fuente[j + 1].isdigit()):
                decimal = True
                j += 1
                while j < n and (fuente[j].isdigit() or fuente[j] == "_"):
                    j += 1
            if j < n and fuente[j] in "eE":
                k = j + 1
                if k < n and fuente[k] in "+-":
                    k += 1
                if k < n and fuente[k].isdigit():
                    decimal = True
                    j = k
                    while j < n and fuente[j].isdigit():
                        j += 1

            if j < n and (fuente[j].isalpha() or fuente[j] == "."):
                raise ErrorLexico(
                    f"{archivo}:{linea}: numero mal formado cerca de "
                    f"{fuente[i:j+1]!r}")
            toks.append(Token("decimal" if decimal else "entero",
                              fuente[i:j].replace("_", ""), linea, c0))
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
