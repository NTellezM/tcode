"""Analisis sintactico de Tcode: tokens -> arbol. Descenso recursivo."""

from tcode.lexer import tokenizar, Token
from tcode.nodos import (
    Entero, Cadena, Booleano, Variable, Llamada, Binaria, Unaria,
    Campo, Indice, LiteralStruct, LiteralArreglo, Try, Sino, Falla, Conversion,
    Interpolada,
    Declaracion, Asignacion, Si, Mientras, Retorno, ExprSentencia,
    Parametro, Funcion, CampoDef, Struct, Usar, Para, Romper, Continuar,
)

ENTEROS = {"u8", "u16", "u32", "u64", "usize", "i8", "i16", "i32", "i64"}
TIPOS = {"str", "view", "bool"} | ENTEROS

# Conjuntos de tipos con nombre. Una restriccion no es una interfaz que haya
# que implementar: es la lista de tipos que valen, y por eso no hace falta
# escribir nada en ningun sitio para que un tipo la cumpla.
RESTRICCIONES = {
    "numero":    set(ENTEROS),
    "igualable": ENTEROS | {"bool", "str", "view"},
    "ordenable": ENTEROS | {"str", "view"},
    "texto":     {"str", "view"},
}


class ErrorSintactico(Exception):
    pass


class Parser:
    def __init__(self, toks, archivo="<entrada>", structs_previos=None):
        self.toks = toks
        self.i = 0
        self.archivo = archivo
        # Se recogen antes de parsear porque hacen falta para desambiguar:
        # `Punto { x: 1 }` es un literal solo si `Punto` es un struct. Sin
        # esto, el `s` de `if s { }` se leeria como el inicio de uno.
        # Los parametros de tipo de la funcion que se esta leyendo. Mientras
        # dura, `T` es un tipo mas: no se resuelve aqui, se resuelve al
        # instanciar en cada llamada.
        self.tipo_params = set()
        # Los alias de `usar ... como x` de ESTE archivo: `x.algo` es un
        # nombre, no un campo de una variable llamada `x`.
        self.alias = set()
        self.structs = set(structs_previos or ())
        self.structs |= {t.valor for j, t in enumerate(toks)
                        if t.tipo == "palabra" and t.valor == "struct"
                        and j + 1 < len(toks) and toks[j + 1].tipo == "ident"
                        for t in [toks[j + 1]]}

    # ---------- utilidades ----------

    @property
    def actual(self) -> Token:
        return self.toks[self.i]

    def error(self, mensaje, tok=None):
        t = tok or self.actual
        visto = "fin de archivo" if t.tipo == "fin" else repr(t.valor)
        raise ErrorSintactico(f"{self.archivo}:{t.linea}: {mensaje}, se encontro {visto}")

    def es(self, tipo, valor=None) -> bool:
        t = self.actual
        return t.tipo == tipo and (valor is None or t.valor == valor)

    def acepta(self, tipo, valor=None):
        if self.es(tipo, valor):
            t = self.actual
            self.i += 1
            return t
        return None

    def espera(self, tipo, valor=None) -> Token:
        # `lista<lista<str>>` acaba en dos `>` pegados, que el lexer lee como
        # el desplazamiento `>>`. Donde se espera cerrar un tipo, se parte en
        # dos: es lo mismo que hizo C++11 despues de veinte años obligando a
        # escribir `> >` con un espacio en medio.
        if (tipo, valor) == ("simbolo", ">") and self.es("simbolo", ">>"):
            t = self.actual
            suelto = Token("simbolo", ">", t.linea, t.col)
            self.toks[self.i] = suelto
            return suelto
        t = self.acepta(tipo, valor)
        if t is None:
            que = valor if valor is not None else tipo
            self.error(f"se esperaba {que!r}")
        return t

    # ---------- alto nivel ----------

    def programa(self) -> list:
        decls = []
        while self.es("palabra", "usar"):
            tok = self.actual
            self.i += 1
            ruta = self.espera("cadena").valor
            alias = None
            # `como` no es palabra reservada: solo significa esto aqui, y asi
            # sigue valiendo como nombre de variable.
            if self.actual.tipo == "ident" and self.actual.valor == "como":
                self.i += 1
                alias = self.espera("ident").valor
                self.alias.add(alias)
            self.espera("simbolo", ";")
            decls.append(Usar(ruta, linea=tok.linea, alias=alias))

        while not self.es("fin"):
            if self.es("palabra", "usar"):
                self.error("los `usar` van todos al principio del archivo")
            if self.es("palabra", "struct"):
                decls.append(self.struct())
            else:
                decls.append(self.funcion())
        return decls

    def lista_tipo_params(self, de_quien):
        """`<T>`, `<A, B>`, `<T: numero>`. Vale igual para `fn` y `struct`."""
        tipo_params = []
        restricciones = {}
        if not self.acepta("simbolo", "<"):
            return tipo_params, restricciones
        while True:
            tp = self.espera("ident").valor
            if tp in TIPOS:
                self.error(f"`{tp}` ya es un tipo del lenguaje: un parametro "
                           f"de tipo necesita otro nombre")
            if tp in self.structs:
                self.error(f"`{tp}` ya es un struct: un parametro de tipo "
                           f"necesita otro nombre")
            if tp in tipo_params:
                self.error(f"`{tp}` esta repetido en `{de_quien}<...>`")
            tipo_params.append(tp)
            # `<T: numero>`: lo que se le exige. Es un conjunto de tipos con
            # nombre, no una interfaz que haya que implementar.
            if self.acepta("simbolo", ":"):
                r = self.espera("ident").valor
                if r not in RESTRICCIONES:
                    self.error(f"`{r}` no es una restriccion; hay "
                               + ", ".join("`" + x + "`"
                                           for x in sorted(RESTRICCIONES)))
                restricciones[tp] = r
            if not self.acepta("simbolo", ","):
                break
        self.espera("simbolo", ">")
        if not tipo_params:
            self.error(f"`{de_quien}<>` no declara ningun parametro de tipo")
        return tipo_params, restricciones

    def struct(self) -> Struct:
        tok = self.espera("palabra", "struct")
        nombre = self.espera("ident").valor
        tipo_params = self.lista_tipo_params(nombre)[0]
        self.tipo_params = set(tipo_params)
        self.espera("simbolo", "{")
        campos = []
        while not self.es("simbolo", "}"):
            if self.es("fin"):
                self.error("struct sin cerrar")
            ct = self.actual
            cn = self.espera("ident").valor
            self.espera("simbolo", ":")
            campos.append(CampoDef(cn, self.tipo(), ct.linea))
            if not self.acepta("simbolo", ","):
                break
        self.espera("simbolo", "}")
        self.tipo_params = set()
        return Struct(nombre, campos, linea=tok.linea,
                      tipo_params=tipo_params)

    def funcion(self) -> Funcion:
        tok = self.espera("palabra", "fn")
        nombre = self.espera("ident").valor

        # `fn primeras<T>(...)`: los parametros de tipo valen dentro de la
        # firma y del cuerpo, y en ningun otro sitio.
        tipo_params, restricciones = self.lista_tipo_params(nombre)
        self.tipo_params = set(tipo_params)

        self.espera("simbolo", "(")

        params = []
        if not self.es("simbolo", ")"):
            while True:
                pn = self.espera("ident").valor
                self.espera("simbolo", ":")
                # Tres formas de escribir lo mismo:
                #   `x: mut T`  y `x: &mut T`  prestan para modificar
                #   `x: &T`                     presta para leer
                mutable = self.acepta("palabra", "mut") is not None
                compartido = False
                if not mutable and self.acepta("simbolo", "&"):
                    mutable = self.acepta("palabra", "mut") is not None
                    compartido = not mutable
                params.append(Parametro(pn, self.tipo(), mutable, compartido))
                if not self.acepta("simbolo", ","):
                    break
        self.espera("simbolo", ")")

        retorno = self.tipo() if self.acepta("simbolo", "->") else None
        falible = self.acepta("simbolo", "!") is not None
        cuerpo = self.bloque()
        self.tipo_params = set()
        return Funcion(nombre, params, retorno, cuerpo, falible,
                       linea=tok.linea, tipo_params=tipo_params,
                       restricciones=restricciones)

    def tipo(self) -> str:
        t = self.actual

        # `&T` como tipo: un prestamo de solo lectura. En la posicion de un
        # parametro se sigue escribiendo igual, pero alli se guarda aparte.
        if self.es("simbolo", "&"):
            self.i += 1
            if self.acepta("palabra", "mut"):
                return f"&mut {self.tipo()}"
            return f"&{self.tipo()}"

        if t.tipo == "palabra" and t.valor in TIPOS:
            self.i += 1
            return t.valor

        # `fn(usize, usize) -> bool`: el tipo de una funcion usada como valor.
        if self.es("palabra", "fn"):
            self.i += 1
            self.espera("simbolo", "(")
            params = []
            if not self.es("simbolo", ")"):
                while True:
                    params.append(self.tipo())
                    if not self.acepta("simbolo", ","):
                        break
            self.espera("simbolo", ")")
            dentro = ", ".join(params)
            if self.acepta("simbolo", "->"):
                return f"fn({dentro}) -> {self.tipo()}"
            return f"fn({dentro})"

        # parametro de tipo de la funcion en curso
        if t.tipo == "ident" and t.valor in self.tipo_params:
            self.i += 1
            return t.valor

        # tipo traido por un modulo con alias: `par.Par<usize, str>`
        if (t.tipo == "ident" and t.valor in self.alias
                and self.toks[self.i + 1].tipo == "simbolo"
                and self.toks[self.i + 1].valor == "."):
            self.i += 2
            miembro = self.espera("ident").valor
            nombre = f"{t.valor}.{miembro}"
            if self.acepta("simbolo", "<"):
                args = []
                while True:
                    args.append(self.tipo())
                    if not self.acepta("simbolo", ","):
                        break
                self.espera("simbolo", ">")
                return f"{nombre}<{', '.join(args)}>"
            return nombre

        # nombre de struct, con o sin argumentos de tipo
        if t.tipo == "ident" and t.valor in self.structs:
            self.i += 1
            if self.acepta("simbolo", "<"):
                args = []
                while True:
                    args.append(self.tipo())
                    if not self.acepta("simbolo", ","):
                        break
                self.espera("simbolo", ">")
                return f"{t.valor}<{', '.join(args)}>"
            return t.valor

        # Coleccion dinamica y duenia. El tipo del elemento forma parte del
        # tipo concreto: no hay borrado de tipos ni casts escondidos.
        if self.acepta("palabra", "mapa"):
            self.espera("simbolo", "<")
            clave = self.tipo()
            self.espera("simbolo", ",")
            valor = self.tipo()
            self.espera("simbolo", ">")
            return f"mapa<{clave}, {valor}>"

        if self.acepta("palabra", "lista"):
            self.espera("simbolo", "<")
            elem = self.tipo()
            self.espera("simbolo", ">")
            return f"lista<{elem}>"

        # arreglo de tamaño fijo: [usize; 5]
        if self.acepta("simbolo", "["):
            elem = self.tipo()
            self.espera("simbolo", ";")
            n = self.espera("entero").valor
            self.espera("simbolo", "]")
            if int(n) <= 0:
                self.error("un arreglo tiene que tener al menos un elemento", t)
            return f"[{elem}; {n}]"

        self.error("se esperaba un tipo (str, view, usize, i64, bool, "
                   "lista<tipo>, mapa<clave, valor>, un struct, o [tipo; N])")

    def bloque(self) -> list:
        self.espera("simbolo", "{")
        cuerpo = []
        while not self.es("simbolo", "}"):
            if self.es("fin"):
                self.error("bloque sin cerrar")
            cuerpo.append(self.sentencia())
        self.espera("simbolo", "}")
        return cuerpo

    # ---------- sentencias ----------

    def sentencia(self):
        t = self.actual

        if self.es("palabra", "let") or self.es("palabra", "var"):
            mutable = t.valor == "var"
            self.i += 1
            nombre = self.espera("ident").valor
            # El tipo se escribe solo cuando aporta algo: casi siempre se
            # deduce del valor, y repetirlo es decir lo mismo dos veces.
            tipo = self.tipo() if self.acepta("simbolo", ":") else None
            self.espera("simbolo", "=")
            valor = self.expr()
            self.espera("simbolo", ";")
            return Declaracion(nombre, tipo, valor, mutable, linea=t.linea)

        if self.es("palabra", "if"):
            self.i += 1
            cond = self.expr()
            entonces = self.bloque()
            sino = None
            if self.acepta("palabra", "else"):
                sino = self.bloque() if self.es("simbolo", "{") else [self.sentencia()]
            return Si(cond, entonces, sino, linea=t.linea)

        if self.es("palabra", "for"):
            self.i += 1
            nombre = self.espera("ident").valor
            valor = None
            if self.acepta("simbolo", ","):
                valor = self.espera("ident").valor
            self.espera("palabra", "en")
            coleccion = self.expr()
            return Para(nombre, coleccion, self.bloque(), valor, linea=t.linea)

        if self.es("palabra", "break"):
            self.i += 1
            self.espera("simbolo", ";")
            return Romper(linea=t.linea)

        if self.es("palabra", "continue"):
            self.i += 1
            self.espera("simbolo", ";")
            return Continuar(linea=t.linea)

        if self.es("palabra", "while"):
            self.i += 1
            cond = self.expr()
            return Mientras(cond, self.bloque(), linea=t.linea)

        if self.es("palabra", "falla"):
            self.i += 1
            if self.es("simbolo", "("):
                raise ErrorSintactico(
                    f"{self.archivo}:{t.linea}: `falla` no lleva parentesis; "
                    f'se escribe `falla "el motivo";`')
            motivo = self.espera("cadena").valor
            self.espera("simbolo", ";")
            return Falla(motivo, linea=t.linea)

        if self.es("palabra", "return"):
            self.i += 1
            valor = None if self.es("simbolo", ";") else self.expr()
            self.espera("simbolo", ";")
            return Retorno(valor, linea=t.linea)

        # Asignacion a un lugar: `x = ..`, `p.campo = ..`, `v[i] = ..`.
        # Se parsea la expresion y se mira si lo que sigue es un `=` suelto.
        e = self.expr()
        if self.es("simbolo", "="):
            self.i += 1
            valor = self.expr()
            self.espera("simbolo", ";")
            if not isinstance(e, (Variable, Campo, Indice)):
                self.error("a la izquierda de `=` tiene que haber una "
                           "variable, un campo o un elemento", t)
            return Asignacion(e, valor, linea=t.linea)

        self.espera("simbolo", ";")
        return ExprSentencia(e, linea=t.linea)

    # ---------- expresiones, de menor a mayor precedencia ----------

    def _binaria_izq(self, sub, ops):
        izq = sub()
        while self.actual.tipo == "simbolo" and self.actual.valor in ops:
            op = self.actual
            self.i += 1
            izq = Binaria(op.valor, izq, sub(), linea=op.linea)
        return izq

    def expr(self):
        e = self.o()
        if self.es("palabra", "sino"):
            tok = self.actual
            self.i += 1
            return Sino(e, self.o(), linea=tok.linea)
        return e

    def o(self):
        return self._binaria_izq(self.y, {"||"})

    def y(self):
        return self._binaria_izq(self.igualdad, {"&&"})

    def igualdad(self):
        return self._binaria_izq(self.comparacion, {"==", "!="})

    def comparacion(self):
        return self._binaria_izq(self.bits_o, {"<", "<=", ">", ">="})

    # Los operadores de bits atan MAS que las comparaciones, no menos. En C
    # `a & b == c` significa `a & (b == c)`, que no es lo que nadie quiere y
    # lleva cuarenta años obligando a poner parentesis. Aqui, como en Rust y
    # en Go, `a & b == c` es `(a & b) == c`.
    def bits_o(self):
        return self._binaria_izq(self.bits_x, {"|"})

    def bits_x(self):
        return self._binaria_izq(self.bits_y, {"^"})

    def bits_y(self):
        return self._binaria_izq(self.desplazamiento, {"&"})

    def desplazamiento(self):
        return self._binaria_izq(self.suma, {"<<", ">>"})

    def suma(self):
        return self._binaria_izq(self.producto, {"+", "-", "+?", "-?"})

    def producto(self):
        return self._binaria_izq(self.conversion, {"*", "/", "%", "*?"})

    def conversion(self):
        """`x como u8`, `x como? u8`. Ata mas que cualquier operador binario:
        `a + b como u8` es `a + (b como u8)`, que es lo que se lee."""
        e = self.unario()
        while self.actual.tipo == "ident" and self.actual.valor == "como":
            tok = self.actual
            self.i += 1
            envolviendo = self.acepta("simbolo", "?") is not None
            e = Conversion(e, self.tipo(), envolviendo, linea=tok.linea)
        return e

    def unario(self):
        if self.es("palabra", "try"):
            tok = self.actual
            self.i += 1
            return Try(self.unario(), linea=tok.linea)
        if self.actual.tipo == "simbolo" and self.actual.valor in {"!", "-", "~"}:
            op = self.actual
            self.i += 1
            return Unaria(op.valor, self.unario(), linea=op.linea)
        return self.postfijo()

    def postfijo(self):
        e = self.primario()
        while True:
            t = self.actual
            if self.acepta("simbolo", "."):
                e = Campo(e, self.espera("ident").valor, linea=t.linea)
                continue
            if self.acepta("simbolo", "["):
                idx = self.expr()
                self.espera("simbolo", "]")
                e = Indice(e, idx, linea=t.linea)
                continue
            return e

    def interpolada(self, tok):
        """Parte el contenido en trozos literales y expresiones.

        Cada expresion se vuelve a analizar con el mismo parser, asi que
        dentro de las llaves vale cualquier expresion del lenguaje y los
        errores salen con las reglas de siempre. `{{` y `}}` escriben llaves.
        """
        trozos, expresiones = [], []
        actual = []
        texto = tok.valor
        i = 0
        while i < len(texto):
            c = texto[i]
            if c == "{" and i + 1 < len(texto) and texto[i + 1] == "{":
                actual.append("{"); i += 2; continue
            if c == "}" and i + 1 < len(texto) and texto[i + 1] == "}":
                actual.append("}"); i += 2; continue
            if c == "}":
                self.error("`}` suelto dentro de una cadena interpolada; "
                           "escribe `}}` si querias la llave", tok)
            if c != "{":
                actual.append(c); i += 1; continue

            # {expresion}: se busca la llave de cierre respetando anidamiento
            prof = 1
            j = i + 1
            while j < len(texto) and prof > 0:
                if texto[j] == "{":
                    prof += 1
                elif texto[j] == "}":
                    prof -= 1
                if prof > 0:
                    j += 1
            if prof != 0:
                self.error("falta `}` en una cadena interpolada", tok)
            dentro = texto[i + 1:j].strip()
            if not dentro:
                self.error("`{}` vacio en una cadena interpolada: pon dentro "
                           "lo que quieras mostrar", tok)

            sub = Parser(tokenizar(dentro, self.archivo), self.archivo)
            # El sub-parser tiene que saber lo mismo que este: dentro de un
            # hueco vale cualquier expresion, incluida `txt.palabras(v)`.
            sub.structs = self.structs
            sub.alias = self.alias
            sub.tipo_params = self.tipo_params
            sub.structs = self.structs
            expr = sub.expr()
            if not sub.es("fin"):
                self.error(f"sobra algo despues de la expresion {dentro!r} "
                           f"dentro de la cadena", tok)
            _marcar(expr, self.archivo)
            for nodo in _todos(expr):
                nodo.linea = tok.linea

            trozos.append("".join(actual))
            actual = []
            expresiones.append(expr)
            i = j + 1

        trozos.append("".join(actual))
        return Interpolada(trozos, expresiones, linea=tok.linea)

    def cuerpo_literal_struct(self, nombre, linea):
        """Lo de dentro de `Nombre { ... }`, con el `{` todavia sin comer."""
        self.espera("simbolo", "{")
        campos = []
        while not self.es("simbolo", "}"):
            cn = self.espera("ident").valor
            self.espera("simbolo", ":")
            campos.append((cn, self.expr()))
            if not self.acepta("simbolo", ","):
                break
        self.espera("simbolo", "}")
        return LiteralStruct(nombre, campos, linea=linea)

    def cuerpo_llamada(self, nombre, linea):
        """Los argumentos de una llamada, con el `(` ya comido."""
        args = []
        if not self.es("simbolo", ")"):
            while True:
                args.append(self.expr())
                if not self.acepta("simbolo", ","):
                    break
        self.espera("simbolo", ")")
        return Llamada(nombre, args, linea=linea)

    def primario(self):
        t = self.actual

        if t.tipo == "entero":
            self.i += 1
            return Entero(int(t.valor), linea=t.linea)

        if t.tipo == "interpolada":
            self.i += 1
            return self.interpolada(t)

        if t.tipo == "cadena":
            self.i += 1
            return Cadena(t.valor, linea=t.linea)

        if self.es("palabra", "true") or self.es("palabra", "false"):
            self.i += 1
            return Booleano(t.valor == "true", linea=t.linea)

        if self.acepta("simbolo", "["):
            elementos = []
            if not self.es("simbolo", "]"):
                while True:
                    elementos.append(self.expr())
                    if not self.acepta("simbolo", ","):
                        break
            self.espera("simbolo", "]")
            return LiteralArreglo(elementos, linea=t.linea)

        if t.tipo == "ident":
            self.i += 1

            # `txt.palabras(v)`: nombre calificado por el modulo de donde
            # viene, no el campo `palabras` de una variable `txt`.
            if t.valor in self.alias and self.es("simbolo", "."):
                self.i += 1
                miembro = self.espera("ident").valor
                completo = f"{t.valor}.{miembro}"
                if self.es("simbolo", "{"):
                    return self.cuerpo_literal_struct(completo, t.linea)
                self.espera("simbolo", "(")
                return self.cuerpo_llamada(completo, t.linea)

            # literal de struct: solo si el nombre es de un struct conocido
            if t.valor in self.structs and self.es("simbolo", "{"):
                return self.cuerpo_literal_struct(t.valor, t.linea)

            if self.acepta("simbolo", "("):
                return self.cuerpo_llamada(t.valor, t.linea)
            return Variable(t.valor, linea=t.linea)

        if self.acepta("simbolo", "("):
            e = self.expr()
            self.espera("simbolo", ")")
            return e

        self.error("se esperaba una expresion")


def _todos(nodo, vistos=None):
    """Todos los nodos de un arbol, para poder fijarles la linea."""
    from dataclasses import fields, is_dataclass
    vistos = vistos if vistos is not None else set()
    if id(nodo) in vistos:
        return
    vistos.add(id(nodo))
    if isinstance(nodo, (list, tuple)):
        for x in nodo:
            yield from _todos(x, vistos)
        return
    if not is_dataclass(nodo):
        return
    if hasattr(nodo, "linea"):
        yield nodo
    for f in fields(nodo):
        yield from _todos(getattr(nodo, f.name), vistos)


def _marcar(nodo, archivo, vistos=None):
    """Deja el archivo de origen en cada nodo, para los mensajes de error."""
    from dataclasses import fields, is_dataclass
    vistos = vistos if vistos is not None else set()
    if id(nodo) in vistos:
        return
    vistos.add(id(nodo))
    if isinstance(nodo, (list, tuple)):
        for x in nodo:
            _marcar(x, archivo, vistos)
        return
    if not is_dataclass(nodo):
        return
    if hasattr(nodo, "archivo") and not nodo.archivo:
        nodo.archivo = archivo
    for f in fields(nodo):
        _marcar(getattr(nodo, f.name), archivo, vistos)


def parsear(fuente: str, archivo="<entrada>", structs_previos=None) -> list:
    """`structs_previos` trae los nombres de struct de los modulos ya
    cargados: hacen falta para saber que `Punto { x: 1 }` es un literal y no
    el inicio de un bloque."""
    decls = Parser(tokenizar(fuente, archivo), archivo,
                   structs_previos).programa()
    _marcar(decls, archivo)
    return decls
