"""
Comprobador de Tcode: tipos, propiedad, prestamos y mutabilidad.

Aqui viven las cuatro reglas de la especificacion. Un programa que pasa por
aqui no puede tener ninguna de las cuatro clases de fallo que encontramos
auditando la libreria en C.
"""

from tcode.nodos import (
    Entero, Cadena, Booleano, Variable, Llamada, Binaria, Unaria,
    Campo, Indice, LiteralStruct, LiteralArreglo, Try, Sino, Falla,
    Declaracion, Asignacion, Si, Mientras, Retorno, ExprSentencia,
    Funcion, Struct,
)

ENTEROS = {"usize", "i64"}
UNIDAD = "()"

# Un literal entero todavia no tiene ancho: lo toma del contexto. Solo si
# nadie se lo dice se queda en `usize`.
LITERAL = "{entero}"

# De donde sale la memoria a la que apunta una vista. Es lo unico que hace
# falta saber para decidir si esa vista puede sobrevivir a la funcion.
ESTATICO = "estatico"      # un literal: vive lo que dura el programa
PARAMETRO = "parametro"    # presta de un parametro `view`: es del que llama
LOCAL = "local"            # presta de algo que muere al salir


def es_arreglo(t):
    return isinstance(t, str) and t.startswith("[")


def partes_arreglo(t):
    """`[usize; 5]` -> ("usize", 5). Aguanta arreglos de arreglos."""
    interior = t[1:-1]
    prof = 0
    for i in range(len(interior) - 1, -1, -1):
        c = interior[i]
        if c == "]":
            prof += 1
        elif c == "[":
            prof -= 1
        elif c == ";" and prof == 0:
            return interior[:i], int(interior[i + 1:])
    raise AssertionError(f"tipo de arreglo mal formado: {t}")


def elem_de(t):
    return partes_arreglo(t)[0]


def largo_arreglo(t):
    return partes_arreglo(t)[1]


def concreto(t):
    return "usize" if t == LITERAL else t


def encaja(esperado, dado):
    """True si un valor de tipo `dado` sirve donde se pide `esperado`."""
    if esperado == dado:
        return True
    if dado == LITERAL and esperado in ENTEROS:
        return True
    return False


class ErrorDeTipos(Exception):
    pass


class Simbolo:
    """Una variable con lo que el comprobador necesita saber de ella."""

    def __init__(self, nombre, tipo, mutable, profundidad, decl=None):
        # nodo del arbol que declaro esta variable, para poder marcarlo
        self.decl = decl
        self.nombre = nombre
        self.tipo = tipo
        self.mutable = mutable
        self.profundidad = profundidad
        self.movida = False
        self.movida_en = 0
        # nombres de las vistas vivas que prestan de esta variable
        self.prestamos = []
        # si es una vista: de quien presta (None = literal, sin dueño)
        self.origen = None
        # si es una vista: de donde sale la memoria (ver ESTATICO/PARAMETRO/LOCAL)
        self.procedencia = None
        # parametro recibido en prestamo: no somos duenios, no se puede mover
        self.prestado = False
        # linea del `return` que la entrega, si sale por ahi
        self.entregada_en = 0
        # a que funcion se movio, si se movio
        self.movida_a = None


class Comprobador:
    def __init__(self, archivo="<entrada>"):
        self.archivo = archivo
        self.ambitos = []          # lista de dicts nombre -> Simbolo
        self.structs = {}
        self.funciones = {}
        self.retorno_actual = None
        self.falible_actual = False
        self.en_condicional = 0
        self.en_condicion_bucle = 0
        self.en_retorno = 0
        self.errores = []
        # Lo que se infirio, para poder explicarlo. El comprobador lo sabe
        # todo mientras trabaja y hasta ahora lo tiraba al terminar.
        self.informe = []
        self.simbolos_funcion = None

    # ---------- errores ----------

    def error(self, nodo, mensaje):
        archivo = getattr(nodo, "archivo", "") or self.archivo
        self.errores.append(f"{archivo}:{nodo.linea}: {mensaje}")

    # ---------- ambitos ----------

    def abrir(self):
        self.ambitos.append({})

    def cerrar(self):
        muerto = self.ambitos.pop()
        # Al cerrar el bloque mueren las vistas declaradas aqui: se sueltan
        # los prestamos que tenian sobre variables de bloques exteriores.
        for sim in muerto.values():
            if sim.tipo == "view" and sim.origen is not None:
                duenio = self.buscar(sim.origen)
                if duenio is not None and sim.nombre in duenio.prestamos:
                    duenio.prestamos.remove(sim.nombre)
        return muerto

    def buscar(self, nombre):
        for ambito in reversed(self.ambitos):
            if nombre in ambito:
                return ambito[nombre]
        return None

    def declarar(self, nodo, nombre, tipo, mutable, decl=None):
        if nombre in self.ambitos[-1]:
            self.error(nodo, f"`{nombre}` ya esta declarada en este bloque")
        sim = Simbolo(nombre, tipo, mutable, len(self.ambitos), decl or nodo)
        self.ambitos[-1][nombre] = sim
        if self.simbolos_funcion is not None:
            self.simbolos_funcion.append(sim)
        return sim

    # ---------- reglas de propiedad ----------

    def usar(self, nodo, sim):
        """Leer una variable. Falla si ya se movio."""
        if sim.movida:
            self.error(nodo, f"`{sim.nombre}` ya se movio en la linea "
                             f"{sim.movida_en} y aqui se usa otra vez")
            return False
        return True

    def mover(self, nodo, sim):
        """Consumir el valor de una variable duenia."""
        if not self.usar(nodo, sim):
            return
        if sim.prestado:
            self.error(nodo, f"`{sim.nombre}` llego prestado: esta funcion no "
                             f"es su duenia y no puede entregarlo. Pasa una "
                             f"copia, o recibelo por valor")
            return
        if sim.prestamos:
            self.error(nodo, f"no se puede mover `{sim.nombre}`: esta prestada "
                             f"por {self._lista(sim.prestamos)}")
            return
        # Un `return` es lo ultimo de su camino: la variable sigue viva en
        # todo lo que hay ANTES, incluida una salida temprana por `falla` o
        # `try`. Marcarla como movida para toda la funcion hacia que esas
        # salidas no la liberaran. El propio `return` ya la excluye.
        if self.en_retorno:
            sim.entregada_en = nodo.linea
            return
        sim.movida = True
        sim.movida_en = nodo.linea
        if sim.decl is not None:
            sim.decl.movida = True

    def mutar(self, nodo, sim):
        """Modificar una variable en el sitio."""
        if not self.usar(nodo, sim):
            return
        if not sim.mutable:
            self.error_no_mutable(nodo, sim)
            return
        if sim.prestamos:
            self.error(nodo, f"no se puede modificar `{sim.nombre}`: esta "
                             f"prestada por {self._lista(sim.prestamos)}")

    def error_no_mutable(self, nodo, sim):
        """Por que no se puede modificar. La razon cambia el arreglo."""
        if sim.prestado:
            self.error(nodo, f"`{sim.nombre}` llego prestado solo para leer "
                             f"(`&`): para modificarlo, recibelo como "
                             f"`mut {sim.tipo}`")
        else:
            self.error(nodo, f"`{sim.nombre}` se declaro con `let` y no se "
                             f"puede modificar; usa `var`")

    def prestar(self, nodo, sim, nombre_vista):
        if not self.usar(nodo, sim):
            return
        sim.prestamos.append(nombre_vista)

    @staticmethod
    def _lista(nombres):
        vistos = [f"`{n}`" for n in nombres]
        if len(vistos) == 1:
            return vistos[0]
        return ", ".join(vistos[:-1]) + " y " + vistos[-1]

    # ---------- recorrido ----------

    # ---------- propiedad de un tipo ----------

    def posee(self, tipo, visitados=None):
        """True si un valor de este tipo es duenio de memoria del heap."""
        if tipo == "str":
            return True
        if es_arreglo(tipo):
            return self.posee(elem_de(tipo), visitados)
        st = self.structs.get(tipo)
        if st is None:
            return False
        visitados = visitados or set()
        if tipo in visitados:
            return False                      # ciclo: ya se reporto como error
        visitados = visitados | {tipo}
        return any(self.posee(c.tipo, visitados) for c in st.campos)

    def tipo_existe(self, t):
        if t in {"str", "view", "usize", "i64", "bool"} or t in self.structs:
            return True
        if es_arreglo(t):
            return self.tipo_existe(elem_de(t))
        return False

    def contiene_a(self, tipo, buscado, visitados=None):
        """Detecta structs que se contienen a si mismos: tamaño infinito."""
        if tipo == buscado:
            return True
        if es_arreglo(tipo):
            return self.contiene_a(elem_de(tipo), buscado, visitados)
        st = self.structs.get(tipo)
        if st is None:
            return False
        visitados = visitados or set()
        if tipo in visitados:
            return False
        visitados = visitados | {tipo}
        return any(self.contiene_a(c.tipo, buscado, visitados)
                   for c in st.campos)

    def comprobar_structs(self, structs):
        for st in structs:
            previo = self.structs.get(st.nombre)
            if previo is not None:
                self.error(st, f"el struct `{st.nombre}` ya esta definido en "
                               f"{previo.archivo or '<entrada>'}:{previo.linea}")
            self.structs[st.nombre] = st

        for st in structs:
            vistos = set()
            for c in st.campos:
                if c.nombre in vistos:
                    self.error(st, f"`{st.nombre}` tiene dos campos llamados "
                                   f"`{c.nombre}`")
                vistos.add(c.nombre)

                if c.tipo == "view":
                    # Este es el muro que v0 no cruza: una vista dentro de un
                    # struct necesita que la vida util forme parte del tipo.
                    self.error(st, f"en v0 un struct no puede tener un campo "
                                   f"`view` (`{st.nombre}.{c.nombre}`): habria "
                                   f"que llevar su vida util en el tipo. Usa "
                                   f"`str`, que es duenio de su memoria")
                elif not self.tipo_existe(c.tipo):
                    self.error(st, f"`{st.nombre}.{c.nombre}` usa el tipo "
                                   f"`{c.tipo}`, que no existe")

            if any(self.contiene_a(c.tipo, st.nombre) for c in st.campos):
                self.error(st, f"`{st.nombre}` se contiene a si mismo: no tiene "
                               f"un tamaño finito")

    def comprobar_programa(self, funciones):
        structs = [d for d in funciones if isinstance(d, Struct)]
        funciones = [d for d in funciones if isinstance(d, Funcion)]
        self.comprobar_structs(structs)

        for f in funciones:
            previa = self.funciones.get(f.nombre)
            if previa is not None:
                self.error(f, f"la funcion `{f.nombre}` ya esta definida en "
                              f"{previa.archivo or '<entrada>'}:{previa.linea}")
            self.funciones[f.nombre] = f

        for f in funciones:
            self.comprobar_funcion(f)

        return self.errores

    def comprobar_funcion(self, f: Funcion):
        self.retorno_actual = f.retorno
        self.falible_actual = f.falible
        self.simbolos_funcion = []
        self.abrir()
        for p in f.params:
            if p.prestado and p.tipo == "view":
                marca = "mut" if p.mutable else "&"
                self.error(f, f"`{marca}` sobre `view` no tiene sentido: una "
                              f"vista ya es un prestamo. Quita el `{marca}`")
            sim = self.declarar(f, p.nombre, p.tipo, p.mutable, decl=p)
            sim.prestado = p.prestado
            if p.tipo == "view":
                sim.procedencia = PARAMETRO
        self.bloque(f.cuerpo)
        self.cerrar()
        self.informe.append({"funcion": f, "simbolos": self.simbolos_funcion})
        self.simbolos_funcion = None
        self.retorno_actual = None
        self.falible_actual = False

    def bloque(self, sentencias):
        self.abrir()
        for s in sentencias:
            self.sentencia(s)
        return self.cerrar()

    def sentencia(self, s):
        if isinstance(s, Declaracion):
            tipo = self.expresion(s.valor, destino=s.tipo,
                                  mover_variables=True)
            if tipo is not None and not encaja(s.tipo, tipo):
                self.error(s, f"`{s.nombre}` se declaro `{s.tipo}` pero el "
                              f"valor es `{tipo}`")
            sim = self.declarar(s, s.nombre, s.tipo, s.mutable, decl=s)
            if s.tipo == "view":
                sim.procedencia = self.procedencia_de(s.valor)
                sim.origen = self._origen_de(s.valor)
                if sim.origen is not None:
                    duenio = self.buscar(sim.origen)
                    if duenio is not None:
                        duenio.prestamos.append(s.nombre)
            return

        if isinstance(s, Asignacion):
            base = self.variable_base(s.lugar)
            sim = self.buscar(base) if base else None
            if sim is None:
                self.error(s, f"`{base}` no esta declarada" if base
                              else "destino de asignacion invalido")
                self.expresion(s.valor)
                return

            destino = self.tipo_de_lugar(s.lugar)
            tipo = self.expresion(s.valor, mover_variables=True)

            if not sim.mutable:
                self.error_no_mutable(s, sim)
            if sim.prestamos:
                self.error(s, f"no se puede modificar `{base}`: esta prestada "
                              f"por {self._lista(sim.prestamos)}")
            if destino is not None and tipo is not None and not encaja(destino, tipo):
                self.error(s, f"el destino es `{destino}` y se le asigna "
                              f"un `{tipo}`")

            if isinstance(s.lugar, Variable):
                sim.movida = False          # vuelve a tener un valor valido
            return

        if isinstance(s, Si):
            t = self.expresion(s.cond)
            if t is not None and t != "bool":
                self.error(s, f"la condicion de `if` debe ser `bool`, es `{t}`")
            self.en_condicional += 1
            self.bloque(s.entonces)
            if s.sino is not None:
                self.bloque(s.sino)
            self.en_condicional -= 1
            return

        if isinstance(s, Mientras):
            self.en_condicion_bucle += 1
            t = self.expresion(s.cond)
            self.en_condicion_bucle -= 1
            if t is not None and t != "bool":
                self.error(s, f"la condicion de `while` debe ser `bool`, es `{t}`")
            self.en_condicional += 1
            self.bloque(s.cuerpo)
            self.en_condicional -= 1
            return

        if isinstance(s, Retorno):
            if s.valor is None:
                if self.retorno_actual is not None:
                    self.error(s, f"esta funcion devuelve `{self.retorno_actual}` "
                                  f"y el `return` esta vacio")
                return
            # Una vista solo puede salir de la funcion si la memoria a la
            # que apunta sobrevive: o es estatica, o es del que llama.
            if self.retorno_actual == "view":
                self.comprobar_vista_devuelta(s)

            # devolver una variable duenia la mueve fuera de la funcion (str,
            # struct con campos duenios, arreglo de duenios...)
            self.en_retorno += 1
            tipo = self.expresion(s.valor, mover_variables=True)
            self.en_retorno -= 1
            if self.retorno_actual is None:
                self.error(s, "esta funcion no declara tipo de retorno")
            elif tipo is not None and not encaja(self.retorno_actual, tipo):
                self.error(s, f"esta funcion devuelve `{self.retorno_actual}` "
                              f"y aqui se devuelve `{tipo}`")
            return

        if isinstance(s, Falla):
            if not self.falible_actual:
                self.error(s, "esta funcion no esta declarada con `!`, asi que "
                              "no puede fallar; ponle `!` despues del tipo de "
                              "retorno")
            return

        if isinstance(s, ExprSentencia):
            self.expresion(s.expr)
            return

        raise AssertionError(f"sentencia desconocida: {type(s).__name__}")

    def variable_base(self, lugar):
        """La variable en la raiz de `x`, `p.a.b` o `v[i][j]`."""
        while isinstance(lugar, (Campo, Indice)):
            lugar = lugar.objeto if isinstance(lugar, Campo) else lugar.arreglo
        return lugar.nombre if isinstance(lugar, Variable) else None

    def tipo_de_lugar(self, lugar):
        return self.expresion(lugar)

    def comprobar_vista_devuelta(self, s):
        proc = self.procedencia_de(s.valor)
        if proc != LOCAL:
            return
        duenio = self._origen_de(s.valor)
        de_quien = f" de `{duenio}`" if duenio else ""
        extra = (f"`{duenio}` muere al cerrar la funcion"
                 if duenio else "esa memoria muere al cerrar la funcion")
        self.error(s, f"no se puede devolver una vista{de_quien}: {extra}. "
                      f"Una vista que sale de la funcion tiene que venir de un "
                      f"parametro `view` o de un literal; si quieres entregar "
                      f"el texto, devuelve un `str` con `nuevo(...)`")

    def procedencia_de(self, e):
        """De donde sale la memoria a la que apunta una vista.

        Ante la duda devuelve LOCAL, que es lo restrictivo: preferimos
        rechazar un programa correcto antes que aceptar uno colgante.
        """
        if isinstance(e, Cadena):
            return ESTATICO

        if isinstance(e, Variable):
            sim = self.buscar(e.nombre)
            if sim is None:
                return LOCAL
            if sim.tipo == "view":
                return sim.procedencia or LOCAL
            return LOCAL            # es un `str`: el buffer es de esta funcion

        if isinstance(e, Llamada):
            n = e.nombre

            # vista(x) presta de un `str`. Aunque `x` sea un parametro, si
            # llego por valor esta funcion es su duenia y lo libera al salir.
            if n in ("vista", "nuevo", "vacio"):
                return LOCAL

            if n == "rebanar":
                return self.procedencia_de(e.args[0]) if e.args else LOCAL

            f = self.funciones.get(n)
            if f is None or f.retorno != "view":
                return LOCAL

            # A esa funcion se le aplico esta misma regla, asi que lo que
            # devuelve solo puede ser estatico o venir de sus parametros
            # `view`. Luego la procedencia del resultado es la peor de las
            # vistas que le pasamos nosotros.
            peor = ESTATICO
            for arg, param in zip(e.args, f.params):
                if param.tipo != "view":
                    continue
                p = self.procedencia_de(arg)
                if p == LOCAL:
                    return LOCAL
                if p == PARAMETRO:
                    peor = PARAMETRO
            return peor

        return LOCAL

    def _origen_de(self, expr):
        """De que variable duenia proviene una vista, si es que proviene de una."""
        if isinstance(expr, Llamada):
            if expr.nombre == "vista" and expr.args:
                return self.variable_base(expr.args[0])
            if expr.nombre == "rebanar" and expr.args:
                return self._origen_de(expr.args[0])
            # Una funcion que devuelve `view` solo puede devolver algo
            # derivado de sus parametros `view`: el prestamo del que llama
            # tiene que seguir vivo mientras viva el resultado.
            f = self.funciones.get(expr.nombre)
            if f is not None and f.retorno == "view":
                for arg, param in zip(expr.args, f.params):
                    if param.tipo != "view":
                        continue
                    o = self._origen_de(arg)
                    if o is not None:
                        return o
                return None
        if isinstance(expr, Variable):
            sim = self.buscar(expr.nombre)
            if sim is not None and sim.tipo == "view":
                return sim.origen
        return None

    # ---------- expresiones ----------

    def expresion(self, e, destino=None, mover_variables=False):
        if isinstance(e, Entero):
            return LITERAL
        if isinstance(e, Cadena):
            # Un literal es texto estatico: una vista sin dueño.
            return "view"
        if isinstance(e, Booleano):
            return "bool"

        if isinstance(e, Variable):
            sim = self.buscar(e.nombre)
            if sim is None:
                self.error(e, f"`{e.nombre}` no esta declarada")
                return None
            if mover_variables and self.posee(sim.tipo):
                self.mover(e, sim)
            else:
                self.usar(e, sim)
            return sim.tipo

        if isinstance(e, Unaria):
            t = self.expresion(e.valor)
            if e.op == "!":
                if t is not None and t != "bool":
                    self.error(e, f"`!` necesita un `bool`, recibio `{t}`")
                return "bool"
            if t is not None and t not in ENTEROS:
                self.error(e, f"`-` necesita un entero, recibio `{t}`")
            if t == "usize":
                self.error(e, "`usize` no tiene signo: no se puede negar")
            return t

        if isinstance(e, Try):
            if not self.falible_actual:
                self.error(e, "`try` deja subir la falla al que llamo, pero "
                              "esta funcion no esta declarada con `!`")
            if self.en_condicion_bucle:
                self.error(e, "`try` no puede ir en la condicion de un "
                              "`while`: se evaluaria una sola vez")
            return self.desenvolver(e, e.expr, "try")

        if isinstance(e, Sino):
            if self.en_condicion_bucle:
                self.error(e, "`sino` no puede ir en la condicion de un "
                              "`while`: se evaluaria una sola vez")
            t = self.desenvolver(e, e.expr, "sino")
            alt = self.expresion(e.alternativa, mover_variables=True)
            if t is not None and alt is not None and not encaja(t, alt):
                self.error(e, f"la llamada da `{t}` y el valor de despues de "
                              f"`sino` es `{alt}`")
            return t

        if isinstance(e, Campo):
            return self.campo(e, mover_variables)

        if isinstance(e, Indice):
            return self.indice(e, mover_variables)

        if isinstance(e, LiteralStruct):
            return self.literal_struct(e)

        if isinstance(e, LiteralArreglo):
            return self.literal_arreglo(e, destino)

        if isinstance(e, Binaria):
            return self.binaria(e)

        if isinstance(e, Llamada):
            return self.llamada(e)

        raise AssertionError(f"expresion desconocida: {type(e).__name__}")

    def desenvolver(self, nodo, interna, palabra):
        """Comprueba que lo que sigue a `try`/`sino` sea algo que pueda fallar."""
        if not (isinstance(interna, Llamada)
                and self.funciones.get(interna.nombre) is not None
                and self.funciones[interna.nombre].falible):
            self.error(nodo, f"`{palabra}` va delante de una llamada a una "
                             f"funcion declarada con `!`")
            self.expresion(interna)
            return None
        return self.llamada(interna, desenvuelta=True)

    def campo(self, e: Campo, mover_variables=False):
        base = self.expresion(e.objeto)
        if base is None:
            return None
        st = self.structs.get(base)
        if st is None:
            self.error(e, f"`{base}` no es un struct, no tiene campos")
            return None
        for c in st.campos:
            if c.nombre == e.nombre:
                if mover_variables and self.posee(c.tipo):
                    self.error(e, f"en v0 no se puede sacar `{e.nombre}` de un "
                                  f"struct: dejaria a `{base}` a medio mover. "
                                  f"Mueve el struct entero")
                return c.tipo
        self.error(e, f"`{base}` no tiene un campo `{e.nombre}`")
        return None

    def indice(self, e: Indice, mover_variables=False):
        base = self.expresion(e.arreglo)
        ti = self.expresion(e.indice)
        if ti is not None and not encaja("usize", ti):
            self.error(e, f"un indice tiene que ser `usize`, es `{ti}`")
        if base is None:
            return None
        if not es_arreglo(base):
            self.error(e, f"`{base}` no es un arreglo, no se puede indexar")
            return None
        elem = elem_de(base)
        if mover_variables and self.posee(elem):
            self.error(e, f"en v0 no se puede sacar un elemento de un arreglo: "
                          f"dejaria un hueco. Mueve el arreglo entero")
        return elem

    def literal_struct(self, e: LiteralStruct):
        st = self.structs.get(e.tipo)
        if st is None:
            self.error(e, f"`{e.tipo}` no es un struct conocido")
            for _, v in e.campos:
                self.expresion(v)
            return None

        dados = {}
        for nombre, valor in e.campos:
            definicion = next((c for c in st.campos if c.nombre == nombre), None)
            t = self.expresion(valor, mover_variables=(
                definicion is not None and self.posee(definicion.tipo)))
            if definicion is None:
                self.error(e, f"`{e.tipo}` no tiene un campo `{nombre}`")
                continue
            if nombre in dados:
                self.error(e, f"el campo `{nombre}` se da dos veces")
            dados[nombre] = True
            if t is not None and not encaja(definicion.tipo, t):
                self.error(e, f"`{e.tipo}.{nombre}` es `{definicion.tipo}` y "
                              f"recibio `{t}`")

        faltan = [c.nombre for c in st.campos if c.nombre not in dados]
        if faltan:
            self.error(e, f"a `{e.tipo}` le faltan campos: "
                          f"{', '.join('`' + f + '`' for f in faltan)}")
        return e.tipo

    def literal_arreglo(self, e: LiteralArreglo, esperado=None):
        if not e.elementos:
            self.error(e, "un arreglo tiene que tener al menos un elemento")
            return None

        elem_esperado = None
        if esperado is not None and es_arreglo(esperado):
            elem_esperado, n = partes_arreglo(esperado)
            if n != len(e.elementos):
                self.error(e, f"el tipo dice {n} elemento(s) y el literal "
                              f"tiene {len(e.elementos)}")

        tipos = []
        for x in e.elementos:
            t = self.expresion(x, destino=elem_esperado,
                               mover_variables=(elem_esperado is not None
                                                and self.posee(elem_esperado)))
            tipos.append(t)

        if elem_esperado is not None:
            for i, t in enumerate(tipos):
                if t is not None and not encaja(elem_esperado, t):
                    self.error(e, f"el elemento {i + 1} deberia ser "
                                  f"`{elem_esperado}` y es `{t}`")
            return f"[{elem_esperado}; {len(e.elementos)}]"

        conocidos = [t for t in tipos if t is not None]
        if not conocidos:
            return None
        elem = next((t for t in conocidos if t != LITERAL), conocidos[0])
        for i, t in enumerate(tipos):
            if t is not None and not encaja(elem, t):
                self.error(e, f"los elementos de un arreglo tienen que ser del "
                              f"mismo tipo: el 1 es `{elem}` y el {i + 1} es `{t}`")
        return f"[{concreto(elem)}; {len(e.elementos)}]"

    def binaria(self, e: Binaria):
        ti = self.expresion(e.izq)
        td = self.expresion(e.der)

        if e.op in {"&&", "||"}:
            for t, lado in ((ti, "izquierdo"), (td, "derecho")):
                if t is not None and t != "bool":
                    self.error(e, f"`{e.op}` necesita `bool`, el lado {lado} "
                                  f"es `{t}`")
            return "bool"

        if ti is None or td is None:
            return None

        if ti == LITERAL and td in ENTEROS:
            ti = td
        elif td == LITERAL and ti in ENTEROS:
            td = ti

        if e.op in {"==", "!="}:
            if ti != td:
                self.error(e, f"no se pueden comparar `{ti}` y `{td}`")
            if ti == "str":
                self.error(e, "no se comparan `str` con `==`: usa "
                              "`igual(vista(a), vista(b))`")
            return "bool"

        if e.op in {"<", "<=", ">", ">="}:
            if ti != LITERAL and (ti not in ENTEROS or td not in ENTEROS):
                self.error(e, f"`{e.op}` necesita enteros, recibio `{ti}` y `{td}`")
            elif ti != td:
                self.error(e, f"`{ti}` y `{td}` no se mezclan sin conversion "
                              f"explicita")
            return "bool"

        # aritmetica
        if ti == LITERAL and td == LITERAL:
            return LITERAL
        if ti not in ENTEROS or td not in ENTEROS:
            self.error(e, f"`{e.op}` necesita enteros, recibio `{ti}` y `{td}`")
            return None
        if ti != td:
            self.error(e, f"`{ti}` y `{td}` no se mezclan sin conversion explicita")
        return ti

    # ---------- internas ----------

    def llamada(self, e: Llamada, desenvuelta=False):
        nombre = e.nombre

        if nombre in INTERNAS:
            return self.interna(e)

        f = self.funciones.get(nombre)
        if f is None:
            self.error(e, f"`{nombre}` no es una funcion conocida")
            for a in e.args:
                self.expresion(a)
            return None

        if f.falible and not desenvuelta:
            self.error(e, f"`{nombre}` puede fallar: la llamada tiene que ir "
                          f"detras de `try`, o con `sino <valor>` para dar un "
                          f"valor cuando falle")

        if len(e.args) != len(f.params):
            self.error(e, f"`{nombre}` espera {len(f.params)} argumento(s) y "
                          f"recibio {len(e.args)}")

        # Prestar la misma variable dos veces en una llamada, con una de las
        # dos mutable, deja al callee con dos nombres para lo mismo: puede
        # modificar por uno y leer por el otro sin enterarse.
        prestados_mut, prestados_lec = {}, {}

        for arg, param in zip(e.args, f.params):
            if param.prestado:
                marca = "mut" if param.mutable else "&"
                base = self.variable_base(arg)
                sim = self.buscar(base) if base else None
                if sim is None:
                    self.error(e, f"el parametro `{param.nombre}` de `{nombre}` "
                                  f"es `{marca}`: hay que pasarle una variable, "
                                  f"un campo o un elemento")
                    continue

                tipo_arg = self.tipo_de_lugar(arg)
                if tipo_arg is not None and tipo_arg != param.tipo:
                    self.error(e, f"`{param.nombre}` de `{nombre}` es "
                                  f"`{param.tipo}` y recibio `{tipo_arg}`")

                # Dos prestamos de lo mismo solo conviven si ninguno modifica.
                otro = prestados_mut.get(base)
                if otro is None and param.mutable:
                    otro = prestados_lec.get(base)
                if otro is not None:
                    a, b = sorted([param.nombre, otro])
                    self.error(e, f"`{base}` se presta dos veces en la misma "
                                  f"llamada a `{nombre}` (como `{a}` y como "
                                  f"`{b}`), y al menos uno de los dos puede "
                                  f"modificarlo. v0 mira la variable entera, "
                                  f"asi que rechaza esto aunque sean campos "
                                  f"distintos")

                if param.mutable:
                    self.mutar(arg, sim)
                    prestados_mut[base] = param.nombre
                else:
                    self.usar(arg, sim)
                    prestados_lec[base] = param.nombre
                continue

            mueve = self.posee(param.tipo)
            if mueve and isinstance(arg, Variable):
                sim_arg = self.buscar(arg.nombre)
                if sim_arg is not None:
                    sim_arg.movida_a = nombre
            if mueve and isinstance(arg, Variable) and self.en_condicional:
                self.error(e, f"en v0 no se puede mover `{arg.nombre}` dentro "
                              f"de una rama condicional; sacalo del `if`/`while`")
            t = self.expresion(arg, mover_variables=mueve)
            if t is not None and not encaja(param.tipo, t):
                self.error(e, f"`{param.nombre}` de `{nombre}` es "
                              f"`{param.tipo}` y recibio `{t}`")

        return f.retorno if f.retorno is not None else UNIDAD

    def interna(self, e: Llamada):
        nombre = e.nombre
        firma = INTERNAS[nombre]
        params, retorno = firma["params"], firma["retorno"]

        if len(e.args) != len(params):
            self.error(e, f"`{nombre}` espera {len(params)} argumento(s) y "
                          f"recibio {len(e.args)}")
            for a in e.args:
                self.expresion(a)
            return retorno

        # Paso 1: se evaluan los argumentos. Aqui nacen los prestamos que solo
        # duran lo que dura la llamada, como el `vista(s)` que va dentro de
        # `empujar(s, vista(s))`.
        prestados = []
        for i, arg in enumerate(e.args):
            esperado = params[i]

            if esperado == "@mut":
                continue                    # se trata en el paso 2

            if esperado == "@presta":
                base = self.variable_base(arg)
                sim = self.buscar(base) if base else None
                if sim is None:
                    self.error(e, f"`{nombre}` necesita una variable, un campo "
                                  f"o un elemento, no una expresion suelta")
                    continue
                if self.tipo_de_lugar(arg) != "str":
                    self.error(e, f"`{nombre}` presta de un `str`")
                    continue
                self.usar(arg, sim)
                prestados.append(base)
                continue

            t = self.expresion(arg)
            if (t is not None and esperado != "@cualquiera"
                    and not encaja(esperado, t)):
                # donde se pide una vista, un `str` se lee prestandolo
                if not (esperado == "view" and t == "str"):
                    self.error(e, f"el argumento {i + 1} de `{nombre}` debe ser "
                                  f"`{esperado}` y es `{t}`")

            # Prestar de un `str` exige poder nombrar donde vive. El resultado
            # de una llamada no vive en ningun sitio todavia.
            if (t == "str" and esperado in ("view", "@cualquiera")
                    and not isinstance(arg, (Variable, Campo, Indice))):
                self.error(e, f"el argumento {i + 1} de `{nombre}` es un `str` "
                              f"que no esta guardado en ninguna variable; "
                              f"asignalo primero con `let`")

            if (esperado == "@cualquiera" and t is not None
                    and (es_arreglo(t) or t in self.structs)):
                self.error(e, f"`{nombre}` no sabe mostrar un `{t}`: muestra "
                              f"sus campos o elementos por separado")
            if esperado == "view":
                origen = self._origen_de(arg)
                if origen is None and isinstance(arg, Variable) and t == "str":
                    origen = arg.nombre
                if origen is not None:
                    prestados.append(origen)

        # Paso 2: los efectos, que ya ven los prestamos del paso 1. Esto es lo
        # que rechaza `empujar(s, vista(s))`: el fallo 2 de la especificacion.
        for i, arg in enumerate(e.args):
            if params[i] != "@mut":
                continue
            base = self.variable_base(arg)
            sim = self.buscar(base) if base else None
            if sim is None:
                self.error(e, f"el argumento {i + 1} de `{nombre}` tiene que "
                              f"ser una variable, un campo o un elemento")
                continue
            if self.tipo_de_lugar(arg) != "str":
                self.error(e, f"`{nombre}` opera sobre `str`")
                continue
            if base in prestados:
                self.error(e, f"`{base}` se presta y se modifica en la misma "
                              f"llamada a `{nombre}`: al crecer, el buffer "
                              f"puede moverse y dejar la vista colgando")
                continue
            self.mutar(arg, sim)

        return retorno


# Firmas de las funciones internas.
#   @lugar      -> tiene que ser una variable (se muta o se presta)
#   @cualquiera -> cualquier tipo (imprimir)
INTERNAS = {
    "vacio":    {"params": [],                        "retorno": "str"},
    "nuevo":    {"params": ["view"],                  "retorno": "str"},
    "vista":    {"params": ["@presta"],               "retorno": "view"},
    "empujar":  {"params": ["@mut", "view"],          "retorno": UNIDAD},
    "largo":    {"params": ["view"],                  "retorno": "usize"},
    "igual":    {"params": ["view", "view"],          "retorno": "bool"},
    "rebanar":  {"params": ["view", "usize", "usize"], "retorno": "view"},
    "imprimir": {"params": ["@cualquiera"],           "retorno": UNIDAD},
}


def comprobar(funciones, archivo="<entrada>"):
    c = Comprobador(archivo)
    return c.comprobar_programa(funciones), c
