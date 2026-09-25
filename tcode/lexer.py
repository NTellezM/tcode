"""Analisis lexico de Tcode."""

from dataclasses import dataclass

PALABRAS = {
    "fn", "let", "var", "mut", "if", "else", "while", "return",
    "true", "false", "str", "view", "bool", "lista", "struct",
    "usar", "try", "sino", "falla", "mapa",
    # Un valor que es una cosa U otra, y el compilador obliga a mirar cual.
    "enum", "match",
    # La puerta a C. Es la unica, y se ve desde lejos.
    "externo",
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


HEXA = "0123456789abcdefABCDEF"


def fin_de_cadena(fuente, i, archivo="<entrada>", linea=1, validar=True):
    """Donde acaba una cadena escrita dentro de un hueco: `i` es su `"`, o el
    `$` de una interpolada, y se devuelve lo que va detras de su comilla.

    Lo de dentro de un hueco se copia tal cual, con sus escapes y sus llaves,
    porque lo lee despues el lexer del hueco. Pero hay que saber donde acaba
    cada cadena de dentro: una `}` o un `\\"` suyos no son del hueco. Con
    `validar`, los escapes se comprueban igual que en una cadena suelta; sin
    el, el texto ya paso por aqui y no puede fallar.
    """
    n = len(fuente)
    interpolada = fuente[i] == "$"
    i += 2 if interpolada else 1
    prof = 0
    while True:
        if i >= n or fuente[i] == "\n":
            if not validar:
                return n
            # La de fuera tampoco se cierra: lo mas probable es que falte la
            # `}` del hueco, como en `$"hola {n"`.
            raise ErrorLexico(
                f"{archivo}:{linea}: cadena interpolada sin cerrar; falta la "
                f"comilla, o falta `}}` en algun hueco")
        c = fuente[i]
        if interpolada and prof == 0 and fuente[i:i + 2] in ("{{", "}}"):
            i += 2
            continue
        if prof > 0:
            if c == '"' or fuente.startswith('$"', i):
                i = fin_de_cadena(fuente, i, archivo, linea, validar)
                continue
            if c == "\\":
                i += 2
                continue
        if interpolada and c == "{":
            prof += 1
        elif interpolada and c == "}" and prof:
            prof -= 1
        if c == '"' and prof == 0:
            return i + 1
        if c == "\\":
            if validar:
                if i + 1 >= n:
                    raise ErrorLexico(f"{archivo}:{linea}: escape sin cerrar")
                esc = fuente[i + 1]
                if esc == "x":
                    hexa = fuente[i + 2:i + 4]
                    if len(hexa) < 2 or any(x not in HEXA for x in hexa):
                        raise ErrorLexico(
                            f"{archivo}:{linea}: `\\x` lleva dos digitos "
                            f"hexadecimales detras, como `\\x0a`")
                    i += 4
                    continue
                if esc not in 'nt\\"0' + ("{}" if interpolada else ""):
                    raise ErrorLexico(
                        f"{archivo}:{linea}: escape desconocido \\{esc}")
            i += 2
            continue
        i += 1


def tokenizar(fuente: str, archivo: str = "<entrada>",
              con_comentarios: bool = False, linea: int = 1) -> list:
    """`linea` es donde empieza `fuente`: el hueco de una cadena interpolada
    se lee aparte, y sus errores tienen que decir donde esta la cadena."""
    toks = []
    i = 0
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
                # `{{` y `}}` son una llave escrita, pero solo FUERA de un
                # hueco: dentro, `}}` puede ser el cierre de un bloque y el
                # del hueco, como en `$"{if c { a } else { b }}"`.
                if prof == 0 and (fuente.startswith("{{", i)
                                  or fuente.startswith("}}", i)):
                    # Se pasan tal cual: quien las convierte en una llave
                    # suelta es el parser, al partir los huecos.
                    partes.append(fuente[i])
                    partes.append(fuente[i + 1])
                    i += 2
                    continue
                # Un hueco se copia crudo: lo lee despues el lexer del hueco,
                # con sus escapes. Una cadena de dentro se salta entera, que
                # sus llaves y sus comillas no son del hueco.
                if prof > 0 and (fuente[i] == '"'
                                 or fuente.startswith('$"', i)):
                    j = fin_de_cadena(fuente, i, archivo, l0)
                    partes.append(fuente[i:j])
                    i = j
                    continue
                if prof > 0 and fuente[i] == "\\" and i + 1 < n:
                    partes.append(fuente[i:i + 2])
                    i += 2
                    continue
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
                        if len(hexa) < 2 or any(c not in HEXA for c in hexa):
                            raise ErrorLexico(
                                f"{archivo}:{linea}: `\\x` lleva dos digitos "
                                f"hexadecimales detras, como `\\x0a`")
                        partes.append(chr(0xDC00 + int(hexa, 16)))
                        i += 4
                        continue
                    # `\{` y `\}` son una llave escrita, lo mismo que `{{`
                    # y `}}`: se dejan asi para que el parser no las tome
                    # por un hueco.
                    mapa = {"n": "\n", "t": "\t", "\\": "\\", '"': '"',
                            "0": "\0", "{": "{{", "}": "}}"}
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
                        if len(hexa) < 2 or any(c not in HEXA for c in hexa):
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
