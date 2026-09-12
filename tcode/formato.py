"""
Formateador de Tcode.

Sin opciones, como `gofmt`: hay un estilo y es este. Una opcion de formato es
una discusion que se repite en cada revision de codigo, y no vale lo que
cuesta. Y con la garantia de `black`: formatear dos veces da lo mismo.

Lo que hace:

  - sangra por hondura de llaves, con cuatro espacios
  - quita espacios al final de linea
  - deja como mucho una linea en blanco seguida
  - normaliza el espacio alrededor de `,` `;` y de los parentesis
  - conserva los comentarios donde estaban

Lo que NO hace, a proposito: mover tokens de linea. El formateador no decide
donde parte una expresion larga. Eso significa que no puede estropear nada
—la salida lexea exactamente a los mismos tokens que la entrada, y la suite
lo comprueba— y que quien escribe sigue mandando sobre la forma de su codigo.

Ahi esta la diferencia con `gofmt`, que reparte las lineas por su cuenta: en
un lenguaje joven, un formateador que se equivoca al partir una expresion
hace mas daño que bien. Cuando la gramatica lleve años quieta, se puede.
"""

from tcode.lexer import tokenizar, SIMBOLOS

SANGRIA = "    "

# Detras de estos, un `-`, `&`, `*` o `~` es unario: no lleva espacio detras.
ANTES_DE_UNARIO = {
    "(", "[", "{", ",", ";", ":", "=", "->", "&&", "||", "!", "~",
    "+", "-", "*", "/", "%", "<", ">", "<=", ">=", "==", "!=",
    "+?", "-?", "*?", "/?", "<<", ">>", "|", "^", "&",
}

# Palabras detras de las cuales empieza una expresion. `usize !` no cuenta:
# ahi el `!` marca que la funcion puede fallar, y no es un operador.
ABREN_EXPRESION = {"return", "if", "while", "en", "try", "sino", "else"}

SIN_ESPACIO_ANTES = {",", ";", ")", "]", ".", ":"}
SIN_ESPACIO_DESPUES = {"(", "[", ".", "$"}


def _pegar_seria_otro_token(a, b):
    """Si juntar dos simbolos sin espacio crearia un tercero.

    `>` y `>` pegados son `>>`. Es la unica forma de que el formateador
    cambie lo que el programa significa, asi que se comprueba siempre.
    """
    return (a + b) in SIMBOLOS


def _es_generico(toks, i):
    """Si el `<` de la posicion `i` abre una lista de tipos y no es un menor.

    Se mira lo que va justo antes: `lista`, `mapa`, `bloque`, `fn`, o un
    nombre en la posicion donde se declara una generica.
    """
    if i == 0:
        return False
    ant = toks[i - 1]
    if ant.valor in ("lista", "mapa", "bloque", "fn"):
        return True
    if ant.tipo != "ident":
        return False
    # `fn nombre<T>` o `struct Nombre<T>`
    if i >= 2 and toks[i - 2].valor in ("fn", "struct"):
        return True
    # `Nombre<...>` en posicion de tipo: detras de `:` o `->`
    if i >= 2 and toks[i - 2].valor in (":", "->", "<", ","):
        return True
    return False


def formatear(fuente, archivo="<entrada>"):
    toks = [t for t in tokenizar(fuente, archivo, con_comentarios=True)
            if t.tipo != "fin"]

    # Que `<`/`>` son de un tipo y cuales son comparaciones. Se decide de una
    # vez, contando la hondura, para no tener que adivinarlo al escribir.
    generico = [False] * len(toks)
    pila = []
    for i, t in enumerate(toks):
        if t.tipo == "simbolo" and t.valor == "<" and _es_generico(toks, i):
            generico[i] = True
            pila.append(i)
        elif t.tipo == "simbolo" and t.valor in (">", ">>") and pila:
            generico[i] = True
            pila.pop()
            if t.valor == ">>" and pila:
                pila.pop()

    # Que operadores son unarios. Se decide mirando lo que va justo antes:
    # detras de otro operador, de `(` o de `,` no puede haber un binario.
    unario = [False] * len(toks)
    for i, t in enumerate(toks):
        if t.tipo != "simbolo" or t.valor not in ("-", "&", "~", "!", "*"):
            continue
        if i == 0:
            unario[i] = True
            continue
        ant = toks[i - 1]
        unario[i] = ((ant.tipo == "simbolo" and ant.valor in ANTES_DE_UNARIO
                      and not generico[i - 1])
                     or (ant.tipo == "palabra" and ant.valor in ABREN_EXPRESION))

    # Repartir en lineas segun venian: el formateador no mueve tokens de
    # linea, solo arregla lo que hay dentro de cada una.
    lineas = []
    actual = []
    ultima = toks[0].linea if toks else 1
    for k, t in enumerate(toks):
        if t.linea > ultima:
            lineas.append(actual)
            for _ in range(t.linea - ultima - 1):
                lineas.append([])        # lineas en blanco del original
            actual = []
            ultima = t.linea
        actual.append(k)
    lineas.append(actual)

    return _escribir(lineas, generico, unario, toks)


def _texto(t):
    """El token tal como se escribe en la fuente.

    Las cadenas llegan ya descifradas (un salto de linea es un salto de
    verdad), asi que hay que volver a escribirlas, y un byte crudo vuelve a
    salir en hexadecimal.
    """
    if t.tipo not in ("cadena", "interpolada"):
        return t.valor
    fuera = ['$"' if t.tipo == "interpolada" else '"']
    for ch in t.valor:
        o = ord(ch)
        if 0xDC00 <= o <= 0xDCFF:
            fuera.append(f"\\x{o - 0xDC00:02x}")
        elif ch == "\n":
            fuera.append("\\n")
        elif ch == "\t":
            fuera.append("\\t")
        elif ch == "\0":
            fuera.append("\\0")
        elif ch == "\\":
            fuera.append("\\\\")
        elif ch == '"':
            fuera.append('\\"')
        else:
            fuera.append(ch)
    fuera.append('"')
    return "".join(fuera)


def _escribir(lineas, generico, unario, toks):
    salida = []
    hondura = 0
    blancos = 0
    primera = True

    for linea in lineas:
        piezas = [toks[k] for k in linea]
        if not piezas:
            blancos += 1
            continue


        if blancos and not primera:
            salida.append(("", None))  # como mucho una en blanco seguida
        blancos = 0
        primera = False

        # Una llave de cierre al principio sale un nivel antes que su bloque.
        sangrado = hondura
        if piezas[0].tipo == "simbolo" and piezas[0].valor in ("}", ")", "]"):
            sangrado = max(0, hondura - 1)
        codigo, comentario = _partir_comentario(linea, toks, generico, unario)
        salida.append((SANGRIA * sangrado + codigo, comentario))

        # Lo que abre y no cierra en esta linea manda sobre la siguiente.
        for t in piezas:
            if t.tipo == "simbolo":
                if t.valor in ("{", "(", "["):
                    hondura += 1
                elif t.valor in ("}", ")", "]"):
                    hondura -= 1
        hondura = max(0, hondura)

    return _alinear_comentarios(salida)


def _partir_comentario(indices, toks, generico, unario):
    """El codigo de la linea y, aparte, el comentario que lo siga."""
    corte = len(indices)
    for j, k in enumerate(indices):
        if toks[k].tipo == "comentario" and j > 0:
            corte = j
            break
    codigo = _juntar(indices[:corte], toks, generico, unario)
    resto = indices[corte:]
    if not resto:
        return codigo, None
    return codigo, _juntar(resto, toks, generico, unario)


def _alinear_comentarios(salida):
    """Los comentarios al final de lineas seguidas se alinean entre ellos.

    Es lo que hace `gofmt`, y se agradece leyendo una tabla de campos: los
    comentarios forman una columna en vez de un borde roto.
    """
    lineas = []
    i = 0
    while i < len(salida):
        if salida[i][1] is None:
            lineas.append(salida[i][0])
            i += 1
            continue
        j = i
        while j < len(salida) and salida[j][1] is not None:
            j += 1
        ancho = max(len(salida[k][0]) for k in range(i, j))
        for k in range(i, j):
            codigo, com = salida[k]
            if codigo:
                lineas.append(codigo.ljust(ancho) + " " + com)
            else:
                lineas.append(com)
        i = j
    return "\n".join(lineas).rstrip("\n") + "\n"


def _juntar(indices, toks, generico, unario):
    fuera = []
    for j, k in enumerate(indices):
        t = toks[k]
        texto = _texto(t)
        if j == 0:
            fuera.append(texto)
            continue
        ant = toks[indices[j - 1]]
        if _pega(ant, indices[j - 1], t, k, generico, unario):
            if (ant.tipo == "simbolo" and t.tipo == "simbolo"
                    and _pegar_seria_otro_token(ant.valor, t.valor)):
                fuera.append(" ")
        else:
            fuera.append(" ")
        fuera.append(texto)
    return "".join(fuera).rstrip()


def _pega(ant, i_ant, t, i, generico, unario):
    """Si los dos van pegados, sin espacio en medio."""
    if t.tipo == "comentario":
        return False
    if ant.tipo == "comentario":
        return False
    if t.tipo == "simbolo" and t.valor in SIN_ESPACIO_ANTES:
        return True
    if ant.tipo == "simbolo" and ant.valor in SIN_ESPACIO_DESPUES:
        return True
    # Dentro de un tipo, `<` y `>` van pegados: `lista<str>`, no
    # `lista < str >`. Pero el `>` que cierra no se pega a lo que venga
    # detras, que ya no es del tipo: `-> lista<T> {`.
    if ant.tipo == "simbolo" and generico[i_ant] and ant.valor == "<":
        return True
    if t.tipo == "simbolo" and generico[i]:
        return True
    # Una llamada o un indice: `f(`, `xs[`, y tambien `f<T>(`.
    if t.tipo == "simbolo" and t.valor in ("(", "["):
        if ant.tipo == "simbolo" and generico[i_ant]:
            return True
        # `f(` si, `return (` no: una palabra reservada no es una llamada.
        return ant.tipo == "ident" or (
            ant.tipo == "simbolo" and ant.valor in (")", "]"))
    # Un unario va pegado a lo suyo: `-1`, `&T`, `!cierto`. Un binario no:
    # `a - 1`. Y el `!` de una funcion falible no es ninguno de los dos, asi
    # que se queda suelto: `-> usize !`.
    if unario[i_ant]:
        return True
    return False
