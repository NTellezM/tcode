"""
Comprobador de Tcode: tipos, propiedad, prestamos y mutabilidad.

Aqui viven las cuatro reglas de la especificacion. Un programa que pasa por
aqui no puede tener ninguna de las cuatro clases de fallo que encontramos
auditando la libreria en C.
"""

import re
from decimal import Decimal as NumeroDecimal, InvalidOperation

from tcode.parser import RESTRICCIONES
from tcode import nombres_c
from tcode.nodos import (
    Entero, Cadena, Booleano, Variable, Llamada, Binaria, Unaria,
    Campo, Indice, LiteralStruct, LiteralArreglo, Try, Sino, Falla, Conversion,
    Decimal, SiExpr, Cierre, CampoDef, Parametro,
    Interpolada,
    Declaracion, Asignacion, Si, Mientras, Retorno, ExprSentencia,
    Funcion, Struct, Para, Romper, Continuar,
    Enum, VarianteDef, EnumLit, Match, Brazo, PatronForma,
)

# Enteros de ancho fijo, mas `usize`, que es el que mide cosas de la maquina
# y por eso no lleva ancho escrito. El ancho `None` significa "el de la
# maquina": no se puede saber al compilar, y el C generado lo resuelve con
# `SIZE_MAX`.
SIN_SIGNO = {"u8": 8, "u16": 16, "u32": 32, "u64": 64, "usize": None}
CON_SIGNO = {"i8": 8, "i16": 16, "i32": 32, "i64": 64}
ENTEROS = set(SIN_SIGNO) | set(CON_SIGNO)
# Decimales. La diferencia con todos los demas lenguajes esta en el generador:
# aqui un NaN o un infinito detienen el programa donde aparecen, igual que un
# desbordamiento entero. `+?`, `-?`, `*?` y `/?` dejan el comportamiento IEEE
# de siempre, para quien lo quiera y lo diga.
DECIMALES = {"f32", "f64"}
NUMERICOS = ENTEROS | DECIMALES

# El ancho de ``usize`` es el del destino, que el compilador no conoce: puede
# ser otro que el del proceso que lo ejecuta (`--cc` de otra arquitectura).
# Aqui se acepta lo que cabe en el mas ancho, 64 bits, y el C generado
# comprueba en tiempo de compilacion (`SS_LANG_USIZE_LIT`) que un literal por
# encima de 2^32 - 1 cabe en el `size_t` real.
BITS_USIZE = 64
# Un literal decimal es finito si queda por debajo del punto en que C ya lo
# redondea a infinito: el maximo mas media unidad de la ultima cifra. Justo en
# ese punto el empate va al par, que es infinito. Asi `3.4028235e38`, que es
# como se escribe el maximo de `f32`, vale.
UMBRAL_F32 = NumeroDecimal(2**128 - 2**103)
UMBRAL_F64 = NumeroDecimal(2**1024 - 2**970)
# Bits de mantisa, contando el implicito: un entero mas largo pierde cifras.
MANTISA = {"f32": 24, "f64": 53}
# `intercambiar` y `redimensionar` reservan su destino mientras calculan el
# segundo argumento. La reserva se apunta como un prestamo con su nombre.
RESERVAS = {
    "intercambiar": "mientras se calcula el reemplazo",
    "redimensionar": "mientras se calcula el tamaño nuevo",
}
# Un numero escrito sin punto no decide su tipo: cuadra con cualquier entero,
# y tambien con un decimal, que es lo que hace natural escribir `0` en vez de
# `0.0` donde el contexto ya lo dice.
LITERAL_DECIMAL = "{decimal}"
UNIDAD = "()"

# Un literal entero todavia no tiene ancho: lo toma del contexto. Solo si
# nadie se lo dice se queda en `usize`.
LITERAL = "{entero}"

# Tipos con un orden natural evidente. Un struct no lo tiene: cual de sus
# campos manda es una decision del programa, no del lenguaje.
ORDENABLES = NUMERICOS | {"bool", "str"}
# Lo que `igual` y `menor` saben comparar. Son tipos sin partes: comparar dos
# structs o dos listas exigiria decidir que significa, y eso no se decide por
# la persona en silencio.
IGUALABLES = NUMERICOS | {"bool", "str", "view"}
COMPARABLES = NUMERICOS | {"str", "view"}
NUMEROS = set(NUMERICOS)

# De donde sale la memoria a la que apunta una vista. Es lo unico que hace
# falta saber para decidir si esa vista puede sobrevivir a la funcion.
ESTATICO = "estatico"      # un literal: vive lo que dura el programa
PARAMETRO = "parametro"    # presta de un parametro `view`: es del que llama
LOCAL = "local"            # presta de algo que muere al salir
# Un duenio sin nombre: un valor recien hecho que se libera al acabar la
# sentencia. Una vista suya no se puede guardar.
TEMPORAL = "<temporal>"


def es_arreglo(t):
    return isinstance(t, str) and t.startswith("[")


def es_bloque(t):
    return isinstance(t, str) and t.startswith("bloque<") and t.endswith(">")


def elem_bloque(t):
    return t[len("bloque<"):-1]


def es_lista(t):
    return isinstance(t, str) and t.startswith("lista<") and t.endswith(">")


def es_referencia(t):
    return isinstance(t, str) and t.startswith("&")


def es_referencia_mutable(t):
    return isinstance(t, str) and t.startswith("&mut ")


def apuntado(t):
    """`&Simbolo` -> `Simbolo`; `&mut Simbolo` -> `Simbolo`."""
    return t[5:] if es_referencia_mutable(t) else t[1:]


def es_mapa(t):
    return isinstance(t, str) and t.startswith("mapa<") and t.endswith(">")


def partes_mapa(t):
    """`mapa<str, usize>` -> ("str", "usize"). Respeta anidamientos."""
    interior = t[len("mapa<"):-1]
    prof = 0
    for i, c in enumerate(interior):
        if c == "<":
            prof += 1
        elif c == ">":
            prof -= 1
        elif c == "," and prof == 0:
            return interior[:i].strip(), interior[i + 1:].strip()
    raise AssertionError(f"tipo de mapa mal formado: {t}")


def clave_mapa(t):
    return partes_mapa(t)[0]


def valor_mapa(t):
    return partes_mapa(t)[1]


def elem_lista(t):
    if not es_lista(t):
        raise AssertionError(f"tipo de lista mal formado: {t}")
    return t[6:-1]


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


def sin_prestamo(t):
    """`&T` y `&mut T` valen como `T` para leer: se llega por puntero, pero
    lo que hay al otro lado es un `T`."""
    return apuntado(t) if es_referencia(t) else t


# Tipos que no son duenios de nada: se copian al leerlos, sin quitarle
# memoria a nadie. Son los unicos que se pueden sacar de un prestamo.
COPIABLES = NUMERICOS | {"bool", "view", LITERAL, LITERAL_DECIMAL, UNIDAD}


def es_copiable(t):
    """Lo que se puede sacar de un prestamo: no posee nada detras."""
    return t in COPIABLES or es_funcion(t)


def sustituir_tipo(t, ligaduras):
    """Cambia los parametros de tipo por lo que se les ligo: con `{T: "str"}`,
    `lista<T>` pasa a ser `lista<str>`."""
    if not t or not ligaduras:
        return t
    return re.sub(r"[A-Za-z_][A-Za-z0-9_]*",
                  lambda m: ligaduras.get(m.group(0), m.group(0)), t)


def unificar_tipo(patron, concreto, params, ligaduras, instancias=None):
    """Deduce los parametros de tipo comparando la firma con lo que llega.

    `lista<T>` contra `lista<str>` liga `T` a `str`. Si un mismo parametro
    sale dos veces con tipos distintos, no unifica: eso es un error del que
    llama, no una conversion silenciosa.
    """
    if patron is None or concreto is None:
        return True             # sin informacion: no contradice nada
    if patron in params:
        previo = ligaduras.get(patron)
        if previo is None:
            ligaduras[patron] = concreto
            return True
        return previo == concreto
    if patron == concreto:
        return True
    for marca in ("&mut ", "&"):
        if patron.startswith(marca):
            return (concreto.startswith(marca)
                    and unificar_tipo(patron[len(marca):],
                                      concreto[len(marca):], params, ligaduras))
    if es_lista(patron) and es_lista(concreto):
        return unificar_tipo(elem_lista(patron), elem_lista(concreto),
                             params, ligaduras, instancias)
    if es_mapa(patron) and es_mapa(concreto):
        pk, pv = partes_mapa(patron)
        ck, cv = partes_mapa(concreto)
        return (unificar_tipo(pk, ck, params, ligaduras, instancias)
                and unificar_tipo(pv, cv, params, ligaduras, instancias))
    if es_arreglo(patron) and es_arreglo(concreto):
        pe, pn = partes_arreglo(patron)
        ce, cn = partes_arreglo(concreto)
        return pn == cn and unificar_tipo(pe, ce, params, ligaduras, instancias)

    # `Par<A, B>` contra `Par__usize_str`: la copia ya perdio la forma, asi
    # que se recupera de donde salio.
    ap = aplicacion_generica(patron)
    if ap is not None and instancias is not None:
        base, args = ap
        de_donde = instancias.get(concreto)
        if de_donde is None or de_donde[0] != base or len(de_donde[1]) != len(args):
            return False
        return all(unificar_tipo(a, c, params, ligaduras, instancias)
                   for a, c in zip(args, de_donde[1]))
    return False


def es_funcion(t):
    return isinstance(t, str) and t.startswith("fn(")


def partes_funcion(t):
    """`fn(usize, str) -> bool` -> (["usize", "str"], "bool").

    Sin captura: un valor de este tipo es el nombre de una funcion, nada mas.
    Por eso no posee memoria y se copia como un numero.
    """
    hondura = 0
    for i, ch in enumerate(t):
        if ch == "(":
            hondura += 1
        elif ch == ")":
            hondura -= 1
            if hondura == 0:
                dentro = t[3:i]
                resto = t[i + 1:].strip()
                retorno = resto[2:].strip() if resto.startswith("->") else UNIDAD
                return (partir_tipos(dentro) if dentro.strip() else []), retorno
    return [], UNIDAD


def tipo_de_parametro(p):
    """El tipo de un parametro tal como se escribe en una firma: el prestamo
    se guarda aparte en el nodo, pero en un tipo de funcion tiene que verse."""
    if p.mutable:
        return f"&mut {p.tipo}"
    if p.compartido:
        return f"&{p.tipo}"
    return p.tipo


def firma_funcion(params, retorno):
    """El tipo que le corresponde a una funcion, tal como se escribe."""
    dentro = ", ".join(params)
    if retorno in (None, UNIDAD):
        return f"fn({dentro})"
    return f"fn({dentro}) -> {retorno}"


def partir_tipos(dentro):
    """Parte `usize, lista<str>` por las comas de fuera."""
    piezas, hondura, actual = [], 0, ""
    for i, ch in enumerate(dentro):
        # Un tipo funcion lleva comas dentro de sus parentesis, y la `>` de
        # su `->` no cierra ningun angulo.
        if ch in "<[(":
            hondura += 1
        elif ch in "])" or (ch == ">" and dentro[i - 1:i] != "-"):
            hondura -= 1
        if ch == "," and hondura == 0:
            piezas.append(actual.strip())
            actual = ""
        else:
            actual += ch
    if actual.strip():
        piezas.append(actual.strip())
    return piezas


def aplicacion_generica(t):
    """`Par<usize, str>` -> ("Par", ["usize", "str"]). `lista<...>` no, que
    esa la pone el compilador."""
    if not isinstance(t, str) or "<" not in t or not t.endswith(">"):
        return None
    base = t[:t.index("<")]
    if base in ("lista", "mapa", "bloque", "fn") or not base \
            or not base[0].isalpha():
        return None
    return base, partir_tipos(t[t.index("<") + 1:-1])


def _renombrar_capturas(nodo, nombres, linea):
    """Dentro del cuerpo de una clausura, un nombre capturado es un campo del
    entorno. Se cambia aqui y el resto del comprobador no se entera."""
    from dataclasses import fields, is_dataclass
    if isinstance(nodo, (list, tuple)):
        for i, x in enumerate(nodo):
            if isinstance(x, Variable) and x.nombre in nombres:
                nodo[i] = Campo(Variable("_ss_entorno", linea=linea),
                                x.nombre, linea=x.linea)
            else:
                _renombrar_capturas(x, nombres, linea)
        return
    if not is_dataclass(nodo):
        return
    for campo in fields(nodo):
        valor = getattr(nodo, campo.name)
        if isinstance(valor, Variable) and valor.nombre in nombres:
            setattr(nodo, campo.name,
                    Campo(Variable("_ss_entorno", linea=linea), valor.nombre,
                          linea=valor.linea))
        else:
            _renombrar_capturas(valor, nombres, linea)


def _sustituir_en_arbol(nodo, ligaduras):
    """Pone los tipos ligados en las anotaciones que quedan dentro del cuerpo:
    `var salida: lista<T> = []` tiene que decir `lista<str>` en la copia."""
    from dataclasses import fields, is_dataclass
    if isinstance(nodo, (list, tuple)):
        for x in nodo:
            _sustituir_en_arbol(x, ligaduras)
        return
    if not is_dataclass(nodo):
        return
    for campo in fields(nodo):
        valor = getattr(nodo, campo.name)
        if campo.name in ("tipo", "retorno") and isinstance(valor, str):
            setattr(nodo, campo.name, sustituir_tipo(valor, ligaduras))
        else:
            _sustituir_en_arbol(valor, ligaduras)


def nombre_instancia(nombre, params, ligaduras):
    """Un nombre de C valido y legible por cada juego de tipos."""
    piezas = []
    for tp in params:
        t = ligaduras[tp]
        piezas.append(re.sub(r"[^A-Za-z0-9]+", "_", t).strip("_"))
    return f"{nombre}__{'_'.join(piezas)}"


def encaja(esperado, dado):
    """True si un valor de tipo `dado` sirve donde se pide `esperado`."""
    if esperado == dado:
        return True
    if dado == LITERAL and esperado in NUMERICOS:
        return True            # un numero escrito cuadra con cualquiera
    if dado == LITERAL_DECIMAL and esperado in DECIMALES:
        return True
    # De un prestamo se puede leer, pero no sacar: si lo que se pide es un
    # tipo que posee memoria, aceptarlo aqui seria moverlo fuera del duenio.
    if (es_referencia(dado) and not es_referencia(esperado)
            and es_copiable(esperado)):
        return encaja(esperado, apuntado(dado))
    return False


COMPARACIONES = frozenset({"==", "!=", "<", "<=", ">", ">=", "&&", "||"})


def literal_de(e):
    """`"entero"` o `"decimal"` si aqui hay un numero escrito que todavia no
    tiene tipo —`1`, `2.5`, `1 + 2`, `-0.5`, `if c { 1 } else { 2 }`—, y
    None si no. Un numero asi toma el tipo del otro lado de la operacion, o
    el que se espera de el; sin nada que lo decida, `usize` o `f64`."""
    if isinstance(e, Entero):
        return "entero"
    if isinstance(e, Decimal):
        return "decimal"
    if isinstance(e, Unaria) and e.op == "-":
        # `-1` ya es un `i64`; `-0.5` sigue sin decidir su ancho.
        return "decimal" if literal_de(e.valor) == "decimal" else None
    if isinstance(e, Binaria) and e.op not in COMPARACIONES:
        izq, der = literal_de(e.izq), literal_de(e.der)
        if izq and der:
            return "decimal" if "decimal" in (izq, der) else "entero"
    if isinstance(e, SiExpr):
        a, b = literal_de(e.entonces), literal_de(e.sino_)
        if a and b:
            return "decimal" if "decimal" in (a, b) else "entero"
    return None


# Una cuenta hecha solo de numeros escritos se hace al compilar, en el tipo
# que le toca: si en marcha pararia el programa, es un error ya.
AL_COMPILAR = ": es una cuenta de numeros escritos, y se hace al compilar"


def _limites(t):
    """(minimo, maximo, bits, con signo) de un entero."""
    if t in SIN_SIGNO:
        bits = SIN_SIGNO[t] or BITS_USIZE
        return 0, (1 << bits) - 1, bits, False
    bits = CON_SIGNO[t]
    return -(1 << (bits - 1)), (1 << (bits - 1)) - 1, bits, True


def _envolver(v, t):
    """Los bits de abajo de `v`, leidos como un `t`."""
    _, _, bits, con_signo = _limites(t)
    v &= (1 << bits) - 1
    if con_signo and v >> (bits - 1):
        v -= 1 << bits
    return v


def _solapan(a, b):
    """Si dos caminos pueden ser la misma memoria: `p.a` y `p.a.b` si, uno
    contiene al otro; `p.a` y `p.b` no."""
    return a == b or a.startswith(b + ".") or b.startswith(a + ".")


class _Prestamos:
    """Lo que dejan prestado los argumentos de una llamada, como caminos.
    Dos prestamos de lo mismo solo conviven si ninguno modifica: si no, el
    callee tendria dos nombres para la misma memoria."""

    def __init__(self):
        self.hechos = []        # (camino, quien, mutable)

    def choque(self, camino, mutable):
        """El prestamo anterior que no convive con este, como (lo que se
        presta dos veces, quien lo presto), o None. Primero uno que modifica."""
        for otro, quien, modifica in self.hechos:
            if modifica and _solapan(camino, otro):
                return (min(camino, otro, key=len), quien)
        if mutable:
            for otro, quien, modifica in self.hechos:
                if not modifica and _solapan(camino, otro):
                    return (min(camino, otro, key=len), quien)
        return None

    def apuntar(self, camino, quien, mutable):
        self.hechos.append((camino, quien, mutable))


class _CuentaParada(Exception):
    """La cuenta de numeros escritos que pararia el programa, y donde."""

    def __init__(self, nodo, mensaje):
        super().__init__(mensaje)
        self.nodo = nodo
        self.mensaje = mensaje


def _nombres_de_patron(args):
    """Los nombres que atrapa un patron, a cualquier hondura."""
    salida = set()
    for a in args:
        if isinstance(a, PatronForma):
            salida |= _nombres_de_patron(a.args)
        elif isinstance(a, str) and a != "_":
            salida.add(a)
    return salida


def _nodos_de(nodo):
    """Todo lo que cuelga de `nodo`, el incluido."""
    from dataclasses import fields, is_dataclass
    pila = [nodo]
    while pila:
        x = pila.pop()
        if isinstance(x, (list, tuple)):
            pila.extend(x)
        elif is_dataclass(x):
            yield x
            pila.extend(getattr(x, f.name) for f in fields(x))


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
        # Cuantos bucles habia abiertos al declararla. Moverla desde dentro
        # de un bucle mas hondo la moveria una vez por vuelta.
        self.bucle_al_declarar = 0
        # En cuantos `if`/`match` estaba al declararse, y los campos que se
        # le sacaron: `nombre` o `a.b` -> la linea.
        self.condicional_al_declarar = 0
        self.sacados = {}
        # Para el patron de plegado de un parser: se mueve dentro del bucle y
        # se reasigna en el mismo nivel antes de la siguiente vuelta.
        self.reasignada_directo = False
        self.movida = False
        self.movida_en = 0
        # nombres de las vistas vivas que prestan de esta variable
        self.prestamos = []
        # si es una vista: de quien presta (None = literal, sin dueño), y
        # todos los duenios de los que puede venir, el primero delante
        self.origen = None
        self.origenes = []
        # si es una vista: de donde sale la memoria (ver ESTATICO/PARAMETRO/LOCAL)
        self.procedencia = None
        # parametro recibido en prestamo: no somos duenios, no se puede mover
        self.prestado = False
        # linea del `return` que la entrega, si sale por ahi
        self.entregada_en = 0
        # a que funcion se movio, si se movio
        self.movida_a = None
        # se mueve solo en algunos caminos: lo decide una bandera
        self.movida_condicional = False
        # para los avisos: se leyo su valor alguna vez, se modifico alguna vez
        self.leida = False
        self.mutada = False


class Comprobador:
    def __init__(self, archivo="<entrada>"):
        self.archivo = archivo
        self.ambitos = []          # lista de dicts nombre -> Simbolo
        self.structs = {}
        # nombre -> Enum. Un enum no es un struct: no tiene campos, tiene
        # formas, y solo una a la vez.
        self.enums = {}
        self.funciones = {}
        # `fn f<T>(...)`: la plantilla, sin comprobar. De cada una salen
        # copias con los tipos ya puestos, una por juego de tipos usado.
        self.genericas = {}
        self.instancias = {}        # (nombre, tipos) -> nombre de la copia
        self.instanciadas = []      # las copias, en orden, para el generador
        self.instanciando = []      # pila, para cortar la recursion infinita
        self.contexto_instancia = []  # para que el error diga con que tipos
        self.nombre_original = {}   # copia -> generica, para los mensajes
        self.structs_genericos = {}   # plantillas de `struct Par<A, B>`
        self.structs_instanciados = []  # las copias, para el generador
        self.args_instancia = {}    # copia -> (base, argumentos de tipo)
        self.cierres = {}       # struct de cierre -> nombre de su funcion
        self.n_cierres = 0
        # Los structs de las clausuras que modifican lo que capturaron:
        # llamarlas las modifica.
        self.cierres_mut = set()
        # Las clausuras que se estan comprobando, de dentro afuera: que
        # capturaron con `mut` y que han modificado de verdad.
        self.pila_cierres = []
        self.retorno_actual = None
        self.falible_actual = False
        self.en_condicional = 0
        self.en_condicion_bucle = 0
        # Las cuentas de numeros escritos que esperan su tipo, en el orden en
        # que se comprobaron, y las que ya se hicieron.
        self.escritas = []
        self.contadas = set()
        # Dentro de la guarda de un brazo: ahi no se mueve nada, porque se
        # evalua aunque el brazo no llegue a casar.
        self.en_guarda = 0
        # Mirando el objeto de un `p.x` (no es usar `p` entera), y
        # escribiendo en un campo (no es leerlo).
        self.por_campo = 0
        self.escribiendo = 0
        self.en_bucle = 0
        # Profundidad de bucle cuyas sentencias estamos escribiendo
        # directamente, sin un `if` de por medio.
        self.en_bucle_directo = 0
        self.movidas_en_bucle = []
        self.en_retorno = 0
        # el nodo que un `return` entrega directamente, si es una variable
        self.retorno_directo = None
        self.errores = []
        # Lo que se infirio, para poder explicarlo. El comprobador lo sabe
        # todo mientras trabaja y hasta ahora lo tiraba al terminar.
        self.informe = []
        self.simbolos_funcion = None
        self.avisos = []

    # ---------- errores ----------

    def error(self, nodo, mensaje):
        archivo = getattr(nodo, "archivo", "") or self.archivo
        self.errores.append(f"{archivo}:{nodo.linea}: {self._legible(mensaje)}"
                            + self._por_instanciar())

    def _legible(self, mensaje):
        """La copia de una generica se llama `primeras__str`, y lo que choca
        con C, `ss_id_log`: nombres que nadie escribio. En un mensaje va el
        nombre de verdad. Se cambian nombres enteros: `Cierre_1` no es un
        trozo de `Cierre_10`."""
        return re.sub(r"[A-Za-z_][A-Za-z0-9_]*",
                      lambda m: nombres_c.escrito(
                          self.nombre_original.get(m.group(0), m.group(0))),
                      mensaje)

    def _por_instanciar(self):
        """Un error dentro de una generica no se entiende sin saber con que
        tipos se la uso, ni desde donde. Es lo que hace ilegibles los errores
        de plantillas: se dice aqui, en una linea, de dentro hacia fuera."""
        if not self.contexto_instancia:
            return ""
        partes = []
        for nombre, ligaduras, sitio in reversed(self.contexto_instancia):
            tipos = self._legible(
                ", ".join(f"{k} = {v}" for k, v in ligaduras.items()))
            if sitio is None:
                partes.append(f"\n  al comprobar `{nombre}` con {tipos}: la "
                              f"restriccion lo admite, asi que el cuerpo tiene "
                              f"que valer tambien asi")
            else:
                partes.append(f"\n  al usar `{nombre}` con {tipos}, desde "
                              f"{sitio}")
        return "".join(partes)

    def aviso(self, nodo, mensaje):
        """No impide compilar. Apunta al codigo que escribio la persona."""
        archivo = getattr(nodo, "archivo", "") or self.archivo
        linea = f"{archivo}:{nodo.linea}: {self._legible(mensaje)}"
        # Un aviso sobre el cuerpo de una generica es el mismo aviso por cada
        # juego de tipos con que se use. Se dice una vez.
        if self.contexto_instancia and linea in self.avisos:
            return
        self.avisos.append(linea)

    # ---------- ambitos ----------

    def abrir(self):
        self.ambitos.append({})

    def cerrar(self):
        muerto = self.ambitos.pop()
        # Al cerrar el bloque mueren las vistas declaradas aqui: se sueltan
        # los prestamos que tenian sobre variables de bloques exteriores.
        for sim in muerto.values():
            if self.presta(sim.tipo):
                for origen in sim.origenes:
                    duenio = self.buscar(origen)
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
        elif any(nombre in a for a in self.ambitos[:-1]):
            # Tapar una variable de un bloque que envuelve a este es un error,
            # como en Zig, C# y Java (Rust y Go lo dejan). Leer el codigo sin
            # saber a cual de las dos se refiere un nombre es donde nacen los
            # fallos, y en C la de fuera se vuelve innombrable: una salida
            # temprana desde dentro no podria liberarla.
            self.error(nodo, f"`{nombre}` tapa a una variable del mismo nombre "
                             f"de un bloque de fuera. Usa otro nombre")

        sim = Simbolo(nombre, tipo, mutable, len(self.ambitos), decl or nodo)
        sim.bucle_al_declarar = self.en_bucle
        sim.condicional_al_declarar = self.en_condicional
        self.ambitos[-1][nombre] = sim
        if self.simbolos_funcion is not None:
            self.simbolos_funcion.append(sim)
        return sim

    # ---------- reglas de propiedad ----------

    def usar(self, nodo, sim, lectura=True):
        """Leer una variable. Falla si ya se movio."""
        if lectura:
            sim.leida = True
        if sim.movida:
            self.error(nodo, f"`{sim.nombre}` ya se movio en la linea "
                             f"{sim.movida_en} y aqui se usa otra vez")
            return False
        if sim.sacados and not self.por_campo:
            ruta, linea = next(iter(sim.sacados.items()))
            self.error(nodo, f"`{sim.nombre}` esta a medio mover: "
                             f"`{sim.nombre}.{ruta}` se saco en la linea "
                             f"{linea}. Dale otro valor antes de usarla "
                             f"entera, o usa solo sus otros campos")
            return False
        return True

    def mover(self, nodo, sim):
        """Consumir el valor de una variable duenia."""
        if self.en_guarda:
            self.error(nodo, f"una guarda no mueve nada: `{sim.nombre}` se "
                             f"moveria aunque el brazo no case. Presta, o "
                             f"usa `copiar(...)`")
            return
        if not self.usar(nodo, sim):
            return
        # Si llego prestado, la razon de verdad es esa, y el mensaje de la
        # rama condicional solo despistaria.
        if sim.prestado:
            self.error(nodo, f"`{sim.nombre}` llego prestado: esta funcion no "
                             f"es su duenia y no puede entregarlo. Pasa una "
                             f"copia, o recibelo por valor")
            return
        # Mover dentro de un `if` es correcto: el generador lleva una bandera
        # y libera segun el camino que se tomo. Dentro de un BUCLE solo es
        # correcto si la variable nace en la misma vuelta; si se declaro
        # fuera, la segunda vuelta la moveria otra vez.
        if self.en_bucle > sim.bucle_al_declarar and not self.en_retorno:
            # Puede seguir siendo correcto: si mas abajo, en el mismo nivel
            # del bucle, se le da otro valor, la siguiente vuelta la encuentra
            # viva. Se anota y se resuelve al cerrar el bucle.
            sim.reasignada_directo = False
            if self.movidas_en_bucle:
                self.movidas_en_bucle[-1].append((sim, nodo))
        if sim.prestamos:
            self.error(nodo, f"no se puede mover `{sim.nombre}`: "
                             f"{self._ocupada(sim)}")
            return
        # Una sola regla, en vez de un caso especial por construccion:
        #
        #   `return x` entrega x ahi mismo y no vuelve, asi que el propio
        #   `return` la excluye de la liberacion y no hace falta bandera.
        #   CUALQUIER otro movimiento puede no llegar a ocurrir —la
        #   alternativa de un `sino`, un argumento en una expresion que se
        #   evalua a medias— y entonces la variable sigue siendo nuestra por
        #   el otro camino.
        #
        # Ante la duda, bandera: cuesta un `bool` que el compilador de C
        # elimina en cuanto puede demostrar que sobra.
        if self.en_retorno and nodo is self.retorno_directo:
            sim.entregada_en = nodo.linea
            return
        sim.movida = True
        sim.movida_en = nodo.linea
        if sim.decl is not None:
            sim.decl.movida = True

    def mutar(self, nodo, sim, por_referencia=False):
        """Modificar una variable en el sitio."""
        if self._escribe_en_captura(nodo):
            return
        sim.mutada = True
        # Modificar un campo no es usar el struct entero.
        self.por_campo += isinstance(nodo, Campo)
        sigue = self.usar(nodo, sim, lectura=False)
        self.por_campo -= isinstance(nodo, Campo)
        if not sigue:
            return
        if por_referencia and es_referencia(sim.tipo):
            if not es_referencia_mutable(sim.tipo):
                self.error(nodo, f"`{sim.nombre}` es un prestamo de solo "
                                 f"lectura (`{sim.tipo}`): para modificar lo "
                                 f"que apunta hace falta `&mut "
                                 f"{apuntado(sim.tipo)}`")
            elif sim.prestamos:
                self.error(nodo, f"no se puede modificar `{sim.nombre}`: "
                                 f"{self._ocupada(sim)}")
            return
        if not sim.mutable:
            self.error_no_mutable(nodo, sim)
            return
        if sim.prestamos:
            self.error(nodo, f"no se puede modificar `{sim.nombre}`: "
                             f"{self._ocupada(sim)}")

    def _escribe_en_captura(self, lugar):
        """Si `lugar` es algo que capturo la clausura que se comprueba, lo
        apunta como modificado. Si se capturo sin `mut`, lo dice y devuelve
        True: el error ya esta dado."""
        campo = None
        sitio = lugar
        while isinstance(lugar, (Campo, Indice)):
            if (isinstance(lugar, Campo) and isinstance(lugar.objeto, Variable)
                    and lugar.objeto.nombre == "_ss_entorno"):
                campo = lugar.nombre
            lugar = lugar.objeto if isinstance(lugar, Campo) else lugar.arreglo
        if campo is None or not self.pila_cierres:
            return False
        cierre = self.pila_cierres[-1]
        if campo in cierre["mutables"]:
            cierre["modificadas"].add(campo)
            return False
        self.error(sitio, f"`{campo}` se capturo para leer: para modificarlo "
                          f"dentro de la clausura, capturalo con "
                          f"`fn[mut {campo}]`")
        return True

    def error_no_mutable(self, nodo, sim):
        """Por que no se puede modificar. La razon cambia el arreglo."""
        if sin_prestamo(sim.tipo) in self.cierres_mut:
            # Lo que se modifica es la clausura: se la llama, y guarda lo que
            # capturo con `mut`.
            if isinstance(sim.decl, Parametro):
                arreglo = "recibela con `mut` delante del tipo"
                # En una generica, el tipo que se escribio: `f: mut F`.
                if self.contexto_instancia:
                    plantilla = self.genericas.get(self.contexto_instancia[-1][0])
                    for p in (plantilla.params if plantilla else []):
                        if p.nombre == sim.nombre:
                            arreglo = f"recibela como `{p.nombre}: mut {p.tipo}`"
            else:
                arreglo = "declarala con `var`"
            self.error(nodo, f"`{sim.nombre}` es una clausura que modifica lo "
                             f"que capturo, y llamarla la modifica: {arreglo}")
        elif sim.prestado:
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

    @classmethod
    def _ocupada(cls, sim):
        """Por que no se puede tocar: prestamos vivos o una reserva de
        `intercambiar`/`redimensionar` mientras calculan su argumento."""
        prestamos = [n for n in sim.prestamos if n not in RESERVAS]
        reservas = [n for n in sim.prestamos if n in RESERVAS]
        if prestamos:
            return f"esta prestada por {cls._lista(prestamos)}"
        n = reservas[0]
        return f"esta reservada por `{n}` {RESERVAS[n]}"

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
        if es_referencia(tipo) or es_funcion(tipo):
            return False        # presta, o es solo un nombre de funcion
        if tipo == "str":
            return True
        if es_mapa(tipo):
            # Posee su tabla, y ademas las claves, que son `str`.
            return True
        if es_bloque(tipo) or es_lista(tipo):
            # Incluso un bloque de escalares posee su memoria.
            return True
        if es_arreglo(tipo):
            return self.posee(elem_de(tipo), visitados)
        visitados = visitados or set()
        if tipo in visitados:
            return False                      # ciclo: ya se reporto como error
        en = self.enums.get(tipo)
        if en is not None:
            # Un enum posee si ALGUNA de sus formas posee: en tiempo de
            # ejecucion solo hay una, pero cual sea no se sabe aqui.
            return any(self.posee(t, visitados | {tipo})
                       for v in en.variantes for t in v.tipos)
        st = self.structs.get(tipo)
        if st is None:
            return False
        return any(self.posee(c.tipo, visitados | {tipo}) for c in st.campos)

    def es_compuesto(self, t):
        """Tiene partes: se puede leer un campo o modificarlo en el sitio.
        Un escalar no lo es; prestarlo no aporta nada sobre copiarlo."""
        return (t == "str" or es_bloque(t) or es_lista(t) or es_mapa(t)
                or es_arreglo(t)
                or t in self.structs or t in self.enums)

    def tipo_existe(self, t):
        if es_referencia(t):
            # Prestar un escalar no aporta nada escrito a mano, pero en una
            # generica `&T` tiene que valer para todo `T`: si no, `fn(&T, &T)`
            # no se podria usar con numeros.
            return self.tipo_existe(apuntado(t))
        if es_funcion(t):
            params, retorno = partes_funcion(t)
            return (all(self.tipo_existe(x) for x in params)
                    and (retorno == UNIDAD or self.tipo_existe(retorno)))
        if (t in NUMERICOS or t in {"str", "view", "bool"}
                or t in self.structs or t in self.enums):
            return True
        if es_arreglo(t):
            # Un arreglo tampoco guarda vistas: cada elemento se puede
            # reasignar por un indice que no se conoce al compilar, y no
            # habria forma de saber de quien presta cada uno.
            elem = elem_de(t)
            return (elem != "view" and not self.es_prestado_st(elem)
                    and self.tipo_existe(elem))
        if es_mapa(t):
            k, v = partes_mapa(t)
            # Un mapa tampoco guarda vistas: nadie sabria cuanto viven.
            return (self.tipo_existe(k) and self.tipo_existe(v)
                    and not any(x == "view" or self.es_prestado_st(x)
                                for x in (k, v)))
        if es_bloque(t):
            elem = elem_bloque(t)
            return (elem != "view" and not es_arreglo(elem)
                    and not self.es_prestado_st(elem)
                    and self.tipo_existe(elem))
        if es_lista(t):
            elem = elem_lista(t)
            # Guardar vistas en una coleccion exigiria expresar su vida util.
            return (elem != "view" and not es_arreglo(elem)
                    and not self.es_prestado_st(elem) and self.tipo_existe(elem))
        return False

    def contiene_a(self, tipo, buscado, visitados=None):
        """Detecta structs que se contienen a si mismos: tamaño infinito."""
        if tipo == buscado:
            return True
        if es_arreglo(tipo):
            return self.contiene_a(elem_de(tipo), buscado, visitados)
        if es_mapa(tipo):
            # Igual que la lista: guarda punteros, no valores por copia.
            return False
        if es_lista(tipo):
            # La lista contiene un puntero, no el elemento por valor: corta el
            # ciclo de tamaño (y permite arboles como lista<Nodo>).
            return False
        visitados = visitados or set()
        if tipo in visitados:
            return False
        en = self.enums.get(tipo)
        if en is not None:
            return any(self.contiene_a(t, buscado, visitados | {tipo})
                       for v in en.variantes for t in v.tipos)
        st = self.structs.get(tipo)
        if st is None:
            return False
        return any(self.contiene_a(c.tipo, buscado, visitados | {tipo})
                   for c in st.campos)

    # ---------- structs genericos ----------

    def resolver_tipo(self, t, nodo):
        """Cambia `Par<usize, str>` por la copia concreta, creandola si hace
        falta. Recorre el tipo entero: tambien dentro de listas y mapas."""
        if not isinstance(t, str) or "<" not in t and "[" not in t:
            return t
        for marca in ("&mut ", "&"):
            if t.startswith(marca):
                return marca + self.resolver_tipo(t[len(marca):], nodo)
        if es_bloque(t):
            return f"bloque<{self.resolver_tipo(elem_bloque(t), nodo)}>"
        if es_lista(t):
            return f"lista<{self.resolver_tipo(elem_lista(t), nodo)}>"
        if es_mapa(t):
            k, v = partes_mapa(t)
            return (f"mapa<{self.resolver_tipo(k, nodo)}, "
                    f"{self.resolver_tipo(v, nodo)}>")
        if es_arreglo(t):
            elem, n = partes_arreglo(t)
            return f"[{self.resolver_tipo(elem, nodo)}; {n}]"
        ap = aplicacion_generica(t)
        if ap is None:
            return t
        base, args = ap
        return self.instanciar_struct(base, [self.resolver_tipo(a, nodo)
                                             for a in args], nodo)

    def instanciar_struct(self, base, args, nodo):
        import copy as _copy
        plantilla = self.structs_genericos.get(base)
        if plantilla is None:
            self.error(nodo, f"`{base}` no es un struct generico")
            return base
        if len(args) != len(plantilla.tipo_params):
            self.error(nodo, f"`{base}` toma {len(plantilla.tipo_params)} "
                             f"tipo(s) y se le dieron {len(args)}")
            return base
        ligaduras = dict(zip(plantilla.tipo_params, args))
        nombre = nombre_instancia(base, plantilla.tipo_params, ligaduras)
        if nombre in self.structs:
            self.args_instancia.setdefault(nombre, (base, list(args)))
            return nombre

        copia = _copy.deepcopy(plantilla)
        copia.nombre = nombre
        copia.tipo_params = []
        # Se registra antes de resolver los campos: un `Nodo<T>` con un campo
        # `lista<Nodo<T>>` se refiere a si mismo, y eso es finito.
        self.structs[nombre] = copia
        self.nombre_original[nombre] = base
        self.args_instancia[nombre] = (base, list(args))
        for c in copia.campos:
            c.tipo = self.resolver_tipo(sustituir_tipo(c.tipo, ligaduras), nodo)
        self.structs_instanciados.append(copia)
        return nombre

    # ---------- el borde con C ----------
    #
    # En el borde solo caben los tipos que significan EXACTAMENTE lo mismo a
    # los dos lados. Es lo que permite que no haya `unsafe` por llamada como
    # en Rust: no hay nada que marcar, porque desde Tcode no se puede
    # escribir una llamada que rompa la memoria. Lo que haga la funcion de C
    # es cosa de C, y su nombre esta escrito en el `externo`.
    #
    # `str` entra como `const char*` porque el runtime garantiza el `\0`
    # final. `view` NO: una vista puede apuntar a la mitad de una cadena y
    # no termina en nada. Es la comprobacion que Rust deja en manos de
    # `CString::new` y que aqui hace el compilador.

    BORDE_ENTRADA = set(NUMERICOS) | {"bool", "str"}
    BORDE_SALIDA = set(NUMERICOS) | {"bool", "cadena_c", UNIDAD}

    def comprobar_externa(self, f):
        for p in f.params:
            t = tipo_de_parametro(p)
            if p.mutable or p.compartido or es_referencia(t):
                self.error(f, f"`{f.nombre}` es de C: sus parametros no se "
                              f"prestan ni se mutan, se pasan por valor")
            elif t == "view":
                self.error(f, f"`{f.nombre}.{p.nombre}` es una `view`, y una "
                              f"vista puede apuntar a la mitad de una cadena: "
                              f"no acaba en `\\0` y C leeria de mas. Pasa un "
                              f"`str`, que si acaba, o haz `nuevo(v)` antes")
            elif t not in self.BORDE_ENTRADA:
                self.error(f, f"`{f.nombre}.{p.nombre}` es `{t}`, y eso no "
                              f"significa lo mismo en C. En el borde caben "
                              f"los numeros, `bool` y `str`; para lo demas, "
                              f"envuelvelo en una funcion de C tuya")
        r = f.retorno or UNIDAD
        if r not in self.BORDE_SALIDA:
            if r == "str":
                self.error(f, f"`{f.nombre}` devuelve `str`, y un `str` es de "
                              f"Tcode: C no puede fabricar uno. Si devuelve un "
                              f"`char*` que no hay que liberar, dilo con "
                              f"`cadena_c` y Tcode lo copia")
            else:
                self.error(f, f"`{f.nombre}` devuelve `{r}`, y eso no "
                              f"significa lo mismo en C. En el borde caben "
                              f"los numeros, `bool`, `cadena_c` y nada")
        # De aqui en adelante `cadena_c` ya no existe: lo que ve Tcode es un
        # `str` suyo, con su liberacion y todo. La copia la hace la llamada.
        if r == "cadena_c":
            f.devuelve_cstr = True
            f.retorno = "str"

    def comprobar_enums(self, enums):
        """Registra los enum y comprueba que sus variantes tienen sentido.

        Va antes que los structs porque un struct puede llevar un enum
        dentro, y para saber si ese struct posee memoria hay que saber ya si
        el enum la posee.
        """
        for en in enums:
            previo = self.enums.get(en.nombre) or self.structs.get(en.nombre)
            if previo is not None:
                self.error(en, f"`{en.nombre}` ya esta definido en "
                               f"{previo.archivo or '<entrada>'}:{previo.linea}")
            self.enums[en.nombre] = en

    def comprobar_formas(self, enums):
        """Lo que lleva cada forma. Va despues de los structs: una forma
        puede llevar uno, y antes no existia."""
        for en in enums:
            for v in en.variantes:
                for i, t in enumerate(v.tipos):
                    v.tipos[i] = self.resolver_tipo(t, en)
                    if not self.tipo_existe(v.tipos[i]):
                        self.error(en, f"`{en.nombre}.{v.nombre}` lleva un "
                                       f"`{v.tipos[i]}`, que no es un tipo")
                    elif v.tipos[i] == "view":
                        self.error_enum_prestado(en, v, v.tipos[i])
                    # Un enum que se contiene a si mismo por valor tendria
                    # tamaño infinito, igual que un struct.
                    if self.contiene_a(v.tipos[i], en.nombre):
                        self.error(en, f"`{en.nombre}.{v.nombre}` contiene un "
                                       f"`{en.nombre}`: el tamaño no seria "
                                       f"finito. Metelo en una `lista`, que "
                                       f"guarda un puntero")
                    # Tampoco un struct que presta.
                    if self.es_prestado_st(v.tipos[i]):
                        self.error_enum_prestado(en, v, v.tipos[i])

    def error_enum_prestado(self, en, v, t):
        self.error(en, f"`{en.nombre}.{v.nombre}` lleva un `{t}`, que presta: "
                       f"un enum no guarda prestamos, porque al mirarlo nadie "
                       f"sabria de quien presta. Usa `str`, o un struct con "
                       f"duenio")

    def es_prestado_st(self, t, vistos=None):
        """Un struct que presta: lleva una `view`, o un struct que presta.
        Se trata como una vista: apunta a memoria de otro."""
        st = self.structs.get(t)
        if st is None:
            return False
        vistos = set() if vistos is None else vistos
        if t in vistos:
            return False
        vistos.add(t)
        return any(c.tipo == "view" or self.es_prestado_st(c.tipo, vistos)
                   for c in st.campos)

    def presta(self, t):
        """Si un valor de este tipo apunta a memoria de otro."""
        return (t == "view" or es_referencia(t or "")
                or self.es_prestado_st(t))

    def variante_de(self, tipo, nombre):
        en = self.enums.get(tipo)
        if en is None:
            return None
        return next((v for v in en.variantes if v.nombre == nombre), None)

    def comprobar_structs(self, structs):
        concretos = []
        for st in structs:
            previo = (self.structs.get(st.nombre)
                      or self.structs_genericos.get(st.nombre))
            if previo is not None:
                self.error(st, f"el struct `{st.nombre}` ya esta definido en "
                               f"{previo.archivo or '<entrada>'}:{previo.linea}")
            if st.tipo_params:
                self.structs_genericos[st.nombre] = st
            else:
                self.structs[st.nombre] = st
                concretos.append(st)

        # Los tipos escritos en el programa se resuelven de una vez: a partir
        # de aqui nadie mas tiene que saber que existian los genericos.
        for st in concretos:
            for c in st.campos:
                c.tipo = self.resolver_tipo(c.tipo, st)

        structs = concretos + self.structs_instanciados
        for st in structs:
            vistos = set()
            for c in st.campos:
                if c.nombre in vistos:
                    self.error(st, f"`{st.nombre}` tiene dos campos llamados "
                                   f"`{c.nombre}`")
                vistos.add(c.nombre)

                # Un campo `view` hace del struct uno que presta: se le trata
                # como a una vista, sin anotar vidas en el tipo.
                if not self.tipo_existe(c.tipo):
                    self.error(st, f"`{st.nombre}.{c.nombre}` usa el tipo "
                                   f"`{c.tipo}`, que no existe")

            if any(self.contiene_a(c.tipo, st.nombre) for c in st.campos):
                self.error(st, f"`{st.nombre}` se contiene a si mismo: no tiene "
                               f"un tamaño finito")


    def _resolver_en_arbol(self, nodo, sitio=None):
        """Cambia cada `Par<usize, str>` escrito en el arbol por su copia.
        Despues de esto, nadie mas tiene que saber que hubo un generico.

        `sitio` es el ultimo nodo con linea que se vio: un `Parametro` no
        tiene, y un error suyo tiene que apuntar a la funcion.
        """
        from dataclasses import fields, is_dataclass
        if isinstance(nodo, (list, tuple)):
            for x in nodo:
                self._resolver_en_arbol(x, sitio)
            return
        if not is_dataclass(nodo):
            return
        if getattr(nodo, "linea", None) is not None:
            sitio = nodo
        for campo in fields(nodo):
            valor = getattr(nodo, campo.name)
            if campo.name in ("tipo", "retorno") and isinstance(valor, str):
                setattr(nodo, campo.name, self.resolver_tipo(valor, sitio or nodo))
            else:
                self._resolver_en_arbol(valor, sitio)

    def comprobar_programa(self, funciones):
        structs = [d for d in funciones if isinstance(d, Struct)]
        enums = [d for d in funciones if isinstance(d, Enum)]
        funciones = [d for d in funciones if isinstance(d, Funcion)]
        self.comprobar_enums(enums)
        self.comprobar_structs(structs)
        self.comprobar_formas(enums)
        for f in funciones:
            if not f.tipo_params:
                self._resolver_en_arbol(f, f)

        for f in funciones:
            if f.externa:
                self.comprobar_externa(f)
        for f in funciones:
            if f.nombre in INTERNAS:
                # La interna ganaria siempre, y en silencio: la funcion propia
                # no se llamaria nunca. Go deja tapar `len` y es fuente de
                # sustos; Zig lo evita marcando las suyas con `@`. Aqui se dice.
                self.error(f, f"`{f.nombre}` es una funcion interna del "
                              f"lenguaje: una funcion propia con ese nombre no "
                              f"se llamaria nunca. Ponle otro nombre")
            previa = self.funciones.get(f.nombre) or self.genericas.get(f.nombre)
            if previa is not None:
                self.error(f, f"la funcion `{f.nombre}` ya esta definida en "
                              f"{previa.archivo or '<entrada>'}:{previa.linea}")
            if f.tipo_params:
                self.genericas[f.nombre] = f
            else:
                self.funciones[f.nombre] = f

        # Una generica no se comprueba tal cual: sus tipos no existen todavia.
        # Se comprueba cada copia, cuando se sabe con que tipos se usa.
        # Una externa no tiene cuerpo que comprobar: solo su borde.
        for f in funciones:
            if not f.tipo_params and not f.externa:
                self.comprobar_funcion(f)

        self.comprobar_restricciones()
        return self.errores

    def comprobar_restricciones(self):
        """El cuerpo de una generica con restriccion vale para CADA tipo que
        la cumple, no solo para los que se usan: si compila, compila para
        todo `T` del conjunto. Como los conjuntos son finitos, basta con
        probarlos todos, salvo los que dejan la firma sin sentido. Un
        parametro sin restriccion se deja en los tipos
        con que se uso; si alguno no la tiene y nadie la usa, no se sabe con
        que probar, y se deja."""
        from itertools import product
        for nombre, plantilla in list(self.genericas.items()):
            if not plantilla.restricciones:
                continue
            params = plantilla.tipo_params
            hechas = [tipos for (n, tipos) in list(self.instancias)
                      if n == nombre]
            bases = list(hechas)
            if not bases and all(t in plantilla.restricciones for t in params):
                bases = [None]
            probadas = set(hechas)
            for base in bases:
                opciones = []
                for i, t in enumerate(params):
                    if t in plantilla.restricciones:
                        r = plantilla.restricciones[t]
                        opciones.append(sorted(RESTRICCIONES[r]))
                    else:
                        opciones.append([base[i]])
                for juego in product(*opciones):
                    if juego in probadas:
                        continue
                    probadas.add(juego)
                    ligaduras = dict(zip(params, juego))
                    if self._firma_valida(plantilla, ligaduras):
                        self._probar_juego(plantilla, params, ligaduras)

    def _firma_valida(self, plantilla, ligaduras):
        """Si con estos tipos la firma tiene sentido. Un `T = view` sobre un
        `&lista<T>` no lo tiene: nadie podria llamarla asi, y el cuerpo no
        tiene que valer para lo que no se puede escribir."""
        for p in plantilla.params:
            t = sustituir_tipo(p.tipo, ligaduras)
            if not self.tipo_existe(t) or (p.prestado and t == "view"):
                return False
        r = sustituir_tipo(plantilla.retorno, ligaduras)
        return r in (None, UNIDAD) or self.tipo_existe(r)

    def _probar_juego(self, plantilla, params, ligaduras):
        """Comprueba la copia sin quedarsela: lo que cambie al hacerla se
        deshace, y solo quedan los errores."""
        import copy as _copy
        guardado = {k: _copy.copy(v) for k, v in vars(self).items()}
        antes = len(self.errores)
        try:
            self._instanciar_con(plantilla, plantilla, params, ligaduras, None)
            nuevos = self.errores[antes:]
        finally:
            for k, v in guardado.items():
                setattr(self, k, v)
        for x in nuevos:
            if x not in self.errores:
                self.errores.append(x)

    # ---------- genericas: una copia por juego de tipos ----------

    def tipo_probable(self, e):
        """El tipo de una expresion, sin anotar usos ni movimientos.

        Solo sirve para deducir los parametros de tipo antes de comprobar la
        llamada de verdad. Si no lo sabe dice `None`, y entonces el error
        pide que se le ponga nombre al argumento.
        """
        if isinstance(e, (Try, Sino)):
            return self.tipo_probable(e.expr)
        if isinstance(e, Variable):
            sim = self.buscar(e.nombre)
            if sim is not None:
                return sim.tipo
            # El nombre de una funcion usado como valor.
            f = self.funciones.get(e.nombre)
            if f is not None and not f.falible:
                return firma_funcion([tipo_de_parametro(p) for p in f.params],
                                     f.retorno)
            return None
        if isinstance(e, Cierre):
            # Una clausura escrita en el sitio: hay que crear su struct antes
            # de poder deducir con que se llama a la generica. Se hace una
            # sola vez; `expresion` la ve ya hecha y no la repite.
            return self.cierre(e)
        if isinstance(e, Cadena):
            return "view"
        if isinstance(e, Entero):
            return "usize"
        if isinstance(e, Decimal):
            return "f64"
        if isinstance(e, Booleano):
            return "bool"
        if isinstance(e, Interpolada):
            return "str"
        if isinstance(e, (Campo, Indice)):
            try:
                return self.tipo_de_lugar(e)
            except Exception:
                return None
        if isinstance(e, LiteralStruct):
            return e.tipo
        if isinstance(e, Unaria):
            if e.op == "!":
                return "bool"
            # Un numero escrito con `-` delante solo cabe en uno con signo:
            # sin mas contexto es un `i64`, como en `let x = -7;`. Aqui un
            # `Entero` suelto ya sale como `usize`, asi que se mira el nodo.
            if e.op == "-" and literal_de(e.valor) == "entero":
                return "i64"
            t = self.tipo_probable(e.valor)
            return "i64" if t == LITERAL else t
        if isinstance(e, Conversion):
            return e.a_tipo
        if isinstance(e, SiExpr):
            # Una rama que es un numero escrito toma el tipo de la otra.
            if literal_de(e.entonces) and not literal_de(e.sino_):
                return self.tipo_probable(e.sino_)
            if literal_de(e):
                return "f64" if literal_de(e) == "decimal" else "usize"
            return self.tipo_probable(e.entonces)
        if isinstance(e, Binaria):
            if e.op in ("&&", "||", "==", "!=", "<", "<=", ">", ">="):
                return "bool"
            # Aritmetica: el tipo es el de los operandos; un numero escrito
            # no decide nada por su cuenta, toma el del otro lado.
            izq, der = literal_de(e.izq), literal_de(e.der)
            if izq and der:
                return "f64" if "decimal" in (izq, der) else "usize"
            if izq:
                return self.tipo_probable(e.der)
            a = self.tipo_probable(e.izq)
            b = self.tipo_probable(e.der)
            if a in (None, LITERAL):
                return b if b != LITERAL else "usize"
            return a
        if isinstance(e, Llamada):
            # Las que devuelven el tipo de lo que reciben, como al comprobar.
            if e.nombre in ("absoluto", "raiz", "piso", "techo", "redondear") \
                    and len(e.args) == 1:
                lit = literal_de(e.args[0])
                if lit:
                    return "i64" if lit == "entero" and e.nombre == "absoluto" else "f64"
                t = self.tipo_probable(e.args[0])
                return sin_prestamo(t) if t is not None else None
            if e.nombre in INTERNAS:
                return INTERNAS[e.nombre].get("retorno")
            f = self.funciones.get(e.nombre)
            if f is not None:
                return f.retorno
            plantilla = self.genericas.get(e.nombre)
            if plantilla is not None:
                # Para saber que devuelve hay que elegir la copia. Se intenta
                # en silencio: si no sale, el error lo dara la llamada de
                # verdad, con su sitio y su contexto.
                marca = len(self.errores)
                copia = self.instanciar(e, plantilla)
                if copia is None or len(self.errores) > marca:
                    del self.errores[marca:]
                    return None
                e.nombre = copia
                return self.funciones[copia].retorno
            return None
        return None

    def instanciar(self, e, plantilla):
        """Deduce los tipos de una llamada a una generica y devuelve el nombre
        de la copia con esos tipos, creandola la primera vez."""
        import copy as _copy

        params = plantilla.tipo_params
        ligaduras = {}
        if len(e.args) == len(plantilla.params):
            for arg, p in zip(e.args, plantilla.params):
                concreto = self.tipo_probable(arg)
                if concreto is not None and es_referencia(concreto):
                    concreto = apuntado(concreto)
                antes = dict(ligaduras)
                if not unificar_tipo(p.tipo, concreto, params, ligaduras,
                                     self.args_instancia):
                    choca = next((t for t in params
                                  if t in antes and t in p.tipo), None)
                    if choca is not None:
                        self.error(e, f"`{choca}` en `{plantilla.nombre}` ya "
                                      f"quedo en `{antes[choca]}` por un "
                                      f"argumento anterior, y `{p.nombre}` "
                                      f"pide `{concreto}`. Un mismo parametro "
                                      f"de tipo es un solo tipo en toda la "
                                      f"llamada")
                    else:
                        self.error(e, f"`{p.nombre}` de `{plantilla.nombre}` "
                                      f"es `{p.tipo}` y recibio `{concreto}`")
                    return None

        faltan = [t for t in params if t not in ligaduras]
        if faltan:
            self.error(e, f"no se puede deducir {', '.join('`' + t + '`' for t in faltan)} "
                          f"en la llamada a `{plantilla.nombre}`: los argumentos "
                          f"no lo dicen. Guarda el argumento en una variable con "
                          f"su tipo escrito y pasa esa")
            return None

        # La restriccion se comprueba aqui, en la llamada, no dentro del
        # cuerpo: asi el error apunta a donde esta el problema de verdad y
        # dice que se pedia, en vez de salir de tres niveles mas adentro.
        for tp, restriccion in plantilla.restricciones.items():
            valido = RESTRICCIONES[restriccion]
            puesto = ligaduras.get(tp)
            if puesto is not None and puesto not in valido:
                self.error(e, f"`{plantilla.nombre}` pide que `{tp}` sea "
                              f"`{restriccion}`, y aqui `{tp}` es `{puesto}`. "
                              f"`{restriccion}` son: "
                              + ", ".join("`" + x + "`" for x in sorted(valido)))
                return None

        sitio = f"{getattr(e, 'archivo', '') or self.archivo}:{e.linea}"
        return self._instanciar_con(e, plantilla, params, ligaduras, sitio)

    def _instanciar_con(self, e, plantilla, params, ligaduras, sitio):
        """La copia de `plantilla` para estos tipos, comprobada, si no estaba
        hecha. `sitio` es desde donde se pide, para los mensajes; None si la
        pide la comprobacion de la restriccion y no una llamada."""
        import copy as _copy
        clave = (plantilla.nombre, tuple(ligaduras[t] for t in params))
        if clave in self.instancias:
            return self.instancias[clave]

        nombre = nombre_instancia(plantilla.nombre, params, ligaduras)
        if clave in self.instanciando:
            # Una generica que se llama a si misma con tipos nuevos cada vez
            # no termina nunca de instanciarse. Se corta aqui.
            self.error(e, f"`{plantilla.nombre}` se instancia sin fin: una "
                          f"generica no puede llamarse a si misma con un tipo "
                          f"que dependa de su propio parametro")
            return None

        copia = _copy.deepcopy(plantilla)
        copia.nombre = nombre
        copia.tipo_params = []
        copia.retorno = self.resolver_tipo(
            sustituir_tipo(copia.retorno, ligaduras), e)
        for p in copia.params:
            p.tipo = self.resolver_tipo(sustituir_tipo(p.tipo, ligaduras), e)
        _sustituir_en_arbol(copia.cuerpo, ligaduras)
        self._resolver_en_arbol(copia.cuerpo, copia)

        self.instancias[clave] = nombre
        self.nombre_original[nombre] = plantilla.nombre
        self.funciones[nombre] = copia

        # Se comprueba con el estado de la funcion en curso guardado: la copia
        # es una funcion entera, con sus propios simbolos y su propio retorno.
        guardado = (self.retorno_actual, self.falible_actual,
                    self.simbolos_funcion, self.ambitos)
        self.ambitos = []
        self.instanciando.append(clave)
        self.contexto_instancia.append((plantilla.nombre, dict(ligaduras), sitio))
        try:
            self.comprobar_funcion(copia)
        finally:
            self.contexto_instancia.pop()
            self.instanciando.pop()
            (self.retorno_actual, self.falible_actual,
             self.simbolos_funcion, self.ambitos) = guardado
        self.instanciadas.append(copia)
        return nombre

    def comprobar_funcion(self, f: Funcion):
        self.retorno_actual = f.retorno
        self.falible_actual = f.falible
        self.simbolos_funcion = []
        if f.retorno is not None and not self.tipo_existe(f.retorno):
            self.error(f, f"la funcion `{f.nombre}` devuelve el tipo "
                          f"`{f.retorno}`, que no se puede almacenar")
        self.abrir()
        for p in f.params:
            if not self.tipo_existe(p.tipo):
                self.error(f, f"el parametro `{p.nombre}` usa el tipo "
                              f"`{p.tipo}`, que no se puede almacenar")
            if p.prestado and p.tipo == "view":
                marca = "mut" if p.mutable else "&"
                self.error(f, f"`{marca}` sobre `view` no tiene sentido: una "
                              f"vista ya es un prestamo. Quita el `{marca}`")
            sim = self.declarar(f, p.nombre, p.tipo, p.mutable, decl=p)
            sim.prestado = p.prestado
            if p.tipo == "view" or (not p.prestado and self.es_prestado_st(p.tipo)):
                sim.procedencia = PARAMETRO
        self.bloque(f.cuerpo)
        self.cerrar()
        # Prometer un valor y no devolverlo deja al que llama leyendo basura.
        # `main` es la excepcion: si no dice otra cosa, sale con cero.
        if (f.retorno not in (None, UNIDAD) and f.nombre != "main"
                and not self._siempre_sale(f.cuerpo)):
            self.error(f, f"`{f.nombre}` promete devolver `{f.retorno}` pero "
                          f"hay un camino que llega al final sin `return`")

        self.avisar_sin_usar(f, self.simbolos_funcion)
        self.informe.append({"funcion": f, "simbolos": self.simbolos_funcion})
        self.simbolos_funcion = None
        self.retorno_actual = None
        self.falible_actual = False

    def avisar_sin_usar(self, f, simbolos):
        """Un `_` delante silencia el aviso, como en Rust: dice que es a
        proposito y quien lea el codigo no tiene que preguntarse por que."""
        params = {p.nombre: p for p in f.params}

        for sim in simbolos:
            if nombres_c.callado(sim.nombre):
                continue
            nodo = sim.decl if sim.decl is not None else f
            p = params.get(sim.nombre)

            if p is not None:
                if not sim.leida and not sim.mutada:
                    self.aviso(f, f"el parametro `{sim.nombre}` de "
                                  f"`{f.nombre}` no se usa; si es a proposito "
                                  f"llamalo `_{sim.nombre}`")
                elif p.mutable and not sim.mutada:
                    self.aviso(f, f"`{sim.nombre}` se recibe como "
                                  f"`mut {sim.tipo}` y nunca se modifica; "
                                  f"podria ser `&{sim.tipo}`")
                continue

            if not sim.leida and not sim.mutada:
                self.aviso(nodo, f"`{sim.nombre}` se declara y no se usa; si "
                                 f"es a proposito llamala `_{sim.nombre}`")
            elif not sim.leida:
                self.aviso(nodo, f"a `{sim.nombre}` se le asignan valores que "
                                 f"nunca se leen")
            elif sim.mutable and not sim.mutada:
                self.aviso(nodo, f"`{sim.nombre}` se declara `var` y nunca se "
                                 f"modifica; puede ser `let`")

    def cuerpo_de_bucle(self, sentencias):
        """Como `bloque`, pero sabiendo que estas sentencias son el nivel
        directo del bucle. Al cerrarlo comprueba los movimientos que se
        hicieron sobre variables declaradas fuera."""
        anterior = self.en_bucle_directo
        self.en_bucle_directo = self.en_bucle
        self.abrir()
        for s in sentencias:
            self.sentencia(s)
        self.cerrar()
        self.en_bucle_directo = anterior

        # Basta con mirar si sigue movida al cerrar la vuelta: la union de
        # las ramas de un `if` ya deja `movida` en cierto si ALGUN camino la
        # movio y no le dio otro valor. No hace falta exigir que la
        # reasignacion este al nivel directo del bucle.
        for sim, nodo in self.movidas_en_bucle.pop():
            if sim.movida:
                self.error(nodo, f"`{sim.nombre}` se declaro fuera del bucle y "
                                 f"se mueve aqui dentro, asi que la siguiente "
                                 f"vuelta lo moveria otra vez. Declaralo dentro "
                                 f"del bucle, o dale otro valor antes de cerrar "
                                 f"la vuelta")

    # ---------- caminos excluyentes ----------
    #
    # Las dos ramas de un `if` no se ejecutan las dos. Mover algo en una no
    # deberia impedir moverlo en la otra, ni contar despues si esa rama
    # termino en `return`. Para eso se guarda el estado de movimientos antes
    # de cada rama y se junta al final.

    def _simbolos_vivos(self):
        for ambito in self.ambitos:
            for sim in ambito.values():
                yield sim

    def _foto(self):
        return {id(sim): (sim.movida, sim.movida_en, sim.entregada_en,
                          sim.reasignada_directo, sim)
                for sim in self._simbolos_vivos()}

    def match(self, e, destino=None, mover_variables=True):
        """`match x { ... }`: mirar que forma tiene un enum.

        Tres cosas que no todos los lenguajes hacen:

        - Es exhaustivo. Si falta una forma, el error la nombra. Rust, Swift,
          Zig y los ML lo hacen; Go no tiene con que, y el `switch` de C ni
          se entera. Sin esto, anadir una variante es un fallo silencioso en
          todos los sitios donde ya se miraba.
        - Lo que atrapa el patron se presta o se posee segun el valor que se
          mira. Si el `match` es sobre un `&Figura`, el `s` de
          `Figura.Texto(s)` es una vista prestada, y no hay que escribir
          `ref`, `&`, ni `as_ref()`: en Rust esto costo anios de `match *x`
          y `ref mut` hasta que llegaron los modos de ligadura por defecto.
        - Cada brazo es un camino que excluye a los demas, asi que lo que uno
          mueve no lo han movido los otros. Es la misma regla del `if`, y la
          que hace que las banderas de propiedad salgan bien solas.
        """
        tv = self.expresion(e.valor, mover_variables=False)
        if tv is None:
            return None
        base = sin_prestamo(tv)
        en = self.enums.get(base)
        if en is None:
            self.error(e, f"`match` mira las formas de un enum, y `{tv}` no "
                          f"es uno")
            return None
        e.tipo = base

        antes = self._foto()
        fotos = []
        # Las formas con un brazo que vale para todas ellas, y las que tienen
        # alguno, aunque sea con condiciones.
        vistas = {}
        con_brazo = set()
        tipo_comun = None
        escritos = []
        hay_comodin = False
        for b in e.brazos:
            if hay_comodin:
                self.error(e, "hay brazos detras del `_`, y no se miran "
                              "nunca: el `_` vale para todo lo que quede")
                break
            self._restaurar(antes)
            # Un brazo con guarda, o con algo que no sea un nombre en alguna
            # posicion, puede no casar: no cubre su forma el solo.
            condicionado = (b.guarda is not None
                            or any(not isinstance(a, str) for a in b.nombres))
            if b.variante is None:
                if b.nombres:
                    self.error(e, "el brazo `_` no atrapa nada")
                if b.guarda is None:
                    hay_comodin = True
            else:
                v = self.variante_de(base, b.variante)
                if v is None:
                    cuales = ", ".join(f"`{base}.{x.nombre}`"
                                       for x in en.variantes)
                    self.error(e, f"`{base}` no tiene la forma "
                                  f"`{b.variante}`; tiene {cuales}")
                    continue
                if b.variante in vistas:
                    self.error(e, f"`{base}.{b.variante}` se mira dos veces; "
                                  f"el segundo brazo no se ejecuta nunca")
                con_brazo.add(b.variante)
                if not condicionado:
                    vistas[b.variante] = True
                if not self._patron_valido(e, base, b.variante, b.nombres):
                    continue

            self.abrir()
            self.en_condicional += 1
            if b.variante is not None:
                self._declarar_patron(e, base, b.variante, b.nombres)
            if b.guarda is not None:
                self.en_guarda += 1
                tg = self.expresion(b.guarda, mover_variables=False)
                self.en_guarda -= 1
                if tg is not None and tg != "bool":
                    self.error(e, f"la guarda de un brazo tiene que ser "
                                  f"`bool`, es `{tg}`")
            t = None
            for i, st in enumerate(b.cuerpo):
                if b.es_expresion and isinstance(st, Retorno) and st.valor is not None:
                    t = self.expresion(st.valor, destino=destino,
                                       mover_variables=mover_variables)
                    if t in (LITERAL, LITERAL_DECIMAL):
                        escritos.append(st.valor)
                else:
                    self.sentencia(st)
            self.en_condicional -= 1
            self.cerrar()
            fotos.append(self._foto())
            if b.es_expresion:
                if t not in (None, LITERAL, LITERAL_DECIMAL):
                    if tipo_comun is None:
                        tipo_comun = t
                    elif not encaja(t, tipo_comun) and not encaja(tipo_comun, t):
                        self.error(e, f"los brazos de un `match` tienen que "
                                      f"dar el mismo tipo, y dan "
                                      f"`{tipo_comun}` y `{t}`")

        # La union de todos los caminos: movido en uno cuenta como movido.
        if fotos:
            juntas = fotos[0]
            for otra in fotos[1:]:
                self._juntar_ramas(juntas, otra)
                juntas = self._foto()

        if not hay_comodin:
            faltan = [v.nombre for v in en.variantes
                      if v.nombre not in con_brazo]
            a_medias = [v.nombre for v in en.variantes
                        if v.nombre in con_brazo and v.nombre not in vistas]
            if faltan:
                lista_f = ", ".join(f"`{base}.{x}`" for x in faltan)
                self.error(e, f"al `match` le faltan formas: {lista_f}. "
                              f"Ponlas, o pon un brazo `_` para lo que quede; "
                              f"si no, el dia que anadas una variante este "
                              f"sitio se quedaria callado")
            elif a_medias:
                lista_f = ", ".join(f"`{base}.{x}`" for x in a_medias)
                self.error(e, f"al `match` le pueden quedar casos de "
                              f"{lista_f} sin mirar: sus brazos tienen guarda "
                              f"o un patron que puede no casar. Pon uno que "
                              f"valga para todos, o un brazo `_`")
        # Un brazo que es un numero escrito toma el tipo de los demas, y tiene
        # que caber en el.
        if sin_prestamo(tipo_comun or "") in NUMERICOS:
            for valor in escritos:
                self.comprobar_literal(valor, sin_prestamo(tipo_comun))
                self.fijar_literal(valor, sin_prestamo(tipo_comun))
        e.resultado = tipo_comun or ""
        return tipo_comun

    def _juntar_ramas(self, tras_a, tras_b):
        """Lo que sobrevive a dos caminos que se excluyen: movido en uno o en
        el otro cuenta como movido, porque desde fuera no se sabe cual paso."""
        for clave, (mov_a, linea_a, ent_a, rea_a, sim) in tras_a.items():
            mov_b, linea_b, ent_b, rea_b, _ = tras_b.get(
                clave, (mov_a, linea_a, ent_a, rea_a, sim))
            sim.movida = mov_a or mov_b
            sim.movida_en = linea_a if mov_a else linea_b
            sim.entregada_en = ent_a or ent_b
            sim.reasignada_directo = rea_a or rea_b

    def _restaurar(self, foto):
        for movida, movida_en, entregada, reasignada, sim in foto.values():
            sim.movida = movida
            sim.movida_en = movida_en
            sim.entregada_en = entregada
            sim.reasignada_directo = reasignada

    @staticmethod
    def _termina(sentencias):
        """True si el bloque no continua: sale por `return`, `falla`,
        `break` o `continue`."""
        if not sentencias:
            return False
        return isinstance(sentencias[-1], (Retorno, Falla, Romper, Continuar))

    def _siempre_sale(self, sentencias):
        """True si TODOS los caminos de este bloque salen de la funcion.

        Un `while` no cuenta: puede no dar ni una vuelta. Un `if` cuenta solo
        si tiene `else` y los dos lados salen.
        """
        if not sentencias:
            return False
        ultima = sentencias[-1]
        if isinstance(ultima, (Retorno, Falla)):
            return True
        if isinstance(ultima, Si) and ultima.sino is not None:
            return (self._siempre_sale(ultima.entonces)
                    and self._siempre_sale(ultima.sino))
        return False

    def bloque(self, sentencias):
        # Un bloque anidado ya no es el nivel directo del bucle: lo que se
        # asigne aqui dentro puede no ejecutarse, asi que no restaura nada.
        anterior = self.en_bucle_directo
        self.en_bucle_directo = -1
        self.abrir()
        for s in sentencias:
            self.sentencia(s)
        salida = self.cerrar()
        self.en_bucle_directo = anterior
        return salida

    def sentencia(self, s):
        desde = len(self.escritas)
        self._sentencia(s)
        self.contar_pendientes(desde)

    def _sentencia(self, s):
        if isinstance(s, Declaracion):
            if s.tipo is None:
                # Sin tipo escrito: se deduce del valor. `destino=None` hace
                # que un `[]` no sepa si es lista, arreglo o mapa, y entonces
                # el error pide el tipo en vez de adivinar.
                tipo = self.expresion(s.valor, mover_variables=True)
                if tipo is None:
                    return
                if tipo == LITERAL:
                    self.comprobar_literal(s.valor, "usize")
                    tipo = concreto(tipo)
                if not self.tipo_existe(tipo):
                    self.error(s, f"no se puede deducir el tipo de "
                                  f"`{s.nombre}`: escribelo con `: tipo`")
                    return
                # El generador espera siempre un tipo concreto.
                s.tipo = tipo
            else:
                self.comprobar_mapa_valido(s, s.tipo)
                if not self.tipo_existe(s.tipo):
                    if es_referencia(s.tipo):
                        self.error(s, f"`{s.tipo}` no tiene sentido: "
                                      f"`{apuntado(s.tipo)}` es un escalar, y "
                                      f"prestarlo no aporta nada sobre copiarlo")
                    else:
                        self.error(s, f"`{s.tipo}` no es un tipo almacenable; "
                                      "las listas y los arreglos no pueden "
                                      "guardar `view`, y las listas tampoco "
                                      "arreglos fijos")
                tipo = self.expresion(s.valor, destino=s.tipo,
                                      mover_variables=True)
                if tipo is not None and not encaja(s.tipo, tipo):
                    self.error(s, f"`{s.nombre}` se declaro `{s.tipo}` pero el "
                                  f"valor es `{tipo}`")
            sim = self.declarar(s, s.nombre, s.tipo, s.mutable, decl=s)
            # Una vista y un `&T` son lo mismo para esto: apuntan a memoria
            # de otro, y mientras vivan ese otro no se puede mover ni tocar.
            if self.presta(s.tipo):
                sim.procedencia = self.procedencia_de(s.valor)
                sim.prestado = es_referencia(s.tipo)
                self._apuntar(s, sim, s.valor)
            return

        if isinstance(s, Asignacion):
            base = self.variable_base(s.lugar)
            sim = self.buscar(base) if base else None
            if sim is None:
                self.error(s, f"`{base}` no esta declarada" if base
                              else "destino de asignacion invalido")
                self.expresion(s.valor)
                return

            self.escribiendo += 1
            destino = self.tipo_de_lugar(s.lugar)
            self.escribiendo -= 1
            tipo = self.expresion(s.valor, destino=destino, mover_variables=True)

            if self._escribe_en_captura(s.lugar):
                return
            sim.mutada = True
            # Escribir a traves de un `&mut T` no es reasignar la variable:
            # la variable sigue apuntando al mismo sitio. Lo que se exige es
            # que el prestamo sea mutable.
            por_referencia = es_referencia(sim.tipo)
            if por_referencia:
                if not es_referencia_mutable(sim.tipo):
                    self.error(s, f"`{base}` es un prestamo de solo lectura "
                                  f"(`{sim.tipo}`): para modificar lo que "
                                  f"apunta hace falta `&mut "
                                  f"{apuntado(sim.tipo)}`")
            elif not sim.mutable:
                self.error_no_mutable(s, sim)
            if sim.prestamos:
                self.error(s, f"no se puede modificar `{base}`: "
                              f"{self._ocupada(sim)}")
            if destino is not None and tipo is not None and not encaja(destino, tipo):
                self.error(s, f"el destino es `{destino}` y se le asigna "
                              f"un `{tipo}`")

            # Una vista guardada en un campo: el struct de la raiz presta
            # tambien de ella. Si la raiz llego prestada, quien la presto no
            # sabria de donde presta ahora, salvo que sea un literal.
            if isinstance(s.lugar, Campo) and self.presta(tipo):
                if sim.prestado or es_referencia(sim.tipo):
                    if self.procedencia_de(s.valor) != ESTATICO:
                        self.error(s, f"no se puede guardar un prestamo en "
                                      f"`{base}`: llego prestada, y quien la "
                                      f"presto no sabria de donde presta "
                                      f"ahora. Guarda un literal, o devuelve "
                                      f"el valor")
                elif self.es_prestado_st(sim.tipo):
                    nueva = self.procedencia_de(s.valor)
                    for p in (LOCAL, PARAMETRO):
                        if p in (sim.procedencia, nueva):
                            sim.procedencia = p
                            break
                    self._apuntar(s, sim, s.valor)

            # Lo que se habia sacado vuelve a estar, si se repone en el mismo
            # nivel en que vive la variable. Dentro de un `if`, el otro camino
            # no lo repuso.
            if (self.en_condicional == sim.condicional_al_declarar
                    and self.en_bucle == sim.bucle_al_declarar):
                ruta = self._ruta_de_campo(s.lugar)[0]
                if isinstance(s.lugar, Variable):
                    sim.sacados = {}
                elif ruta is not None:
                    sim.sacados = {r: l for r, l in sim.sacados.items()
                                   if r != ruta and not r.startswith(ruta + ".")}
            if isinstance(s.lugar, Variable):
                sim.movida = False          # vuelve a tener un valor valido
                if self.en_bucle_directo == self.en_bucle:
                    sim.reasignada_directo = True
                if self.presta(sim.tipo):
                    # Lo peor de lo que tuvo y de lo que tiene ahora: si la
                    # asignacion va en una rama, la otra puede no haberla
                    # hecho.
                    nueva = self.procedencia_de(s.valor)
                    for p in (LOCAL, PARAMETRO):
                        if p in (sim.procedencia, nueva):
                            sim.procedencia = p
                            break
                    self._apuntar(s, sim, s.valor)
            return

        if isinstance(s, Si):
            t = self.expresion(s.cond)
            if t is not None and t != "bool":
                self.error(s, f"la condicion de `if` debe ser `bool`, es `{t}`")
            self.en_condicional += 1

            antes = self._foto()
            self.bloque(s.entonces)
            tras_entonces = self._foto()
            entonces_sale = self._termina(s.entonces)

            if s.sino is not None:
                self._restaurar(antes)
                self.bloque(s.sino)
                tras_sino = self._foto()
                sino_sale = self._termina(s.sino)
            else:
                tras_sino = antes
                sino_sale = False

            # Se junta lo que sobrevive: una rama que no continua no aporta.
            for clave, (mov_a, linea_a, ent_a, rea_a, sim) in tras_entonces.items():
                mov_b, linea_b, ent_b, rea_b, _ = tras_sino.get(
                    clave, (mov_a, linea_a, ent_a, rea_a, sim))
                if entonces_sale and not sino_sale:
                    sim.movida, sim.movida_en = mov_b, linea_b
                    sim.entregada_en, sim.reasignada_directo = ent_b, rea_b
                elif sino_sale and not entonces_sale:
                    sim.movida, sim.movida_en = mov_a, linea_a
                    sim.entregada_en, sim.reasignada_directo = ent_a, rea_a
                else:
                    sim.movida = mov_a or mov_b
                    sim.movida_en = linea_a if mov_a else linea_b
                    sim.entregada_en = ent_a or ent_b
                    sim.reasignada_directo = rea_a or rea_b

            self.en_condicional -= 1
            return

        if isinstance(s, Para):
            # Recorrer algo prestado es recorrer lo que presta: la coleccion
            # no se toca, solo se lee.
            tipo = sin_prestamo(self.expresion(s.coleccion) or "") or None
            elem = tipo_valor = None

            if tipo is not None and es_mapa(tipo):
                k, v = partes_mapa(tipo)
                elem, tipo_valor = k, v
            elif tipo is not None and (es_lista(tipo) or es_arreglo(tipo)):
                elem = elem_lista(tipo) if es_lista(tipo) else elem_de(tipo)
                if s.valor is not None:
                    self.error(s, "los dos nombres de `for k, v en ...` son "
                                  "para un mapa; una lista solo da el elemento")
            elif tipo is not None:
                self.error(s, f"`for` recorre una `lista<T>`, un arreglo o un "
                              f"`mapa<K, V>`, y `{tipo}` no lo es")

            # El bucle presta la coleccion mientras dura: modificarla por
            # dentro moveria los elementos bajo los pies del recorrido. Es la
            # invalidacion de iteradores, dicha antes de compilar.
            base = self.variable_base(s.coleccion)
            duenio = self.buscar(base) if base else None
            marca = f"<el for de la linea {s.linea}>"
            if duenio is not None:
                duenio.prestamos.append(marca)

            self.abrir()
            self.en_bucle += 1
            self.movidas_en_bucle.append([])
            self.en_condicional += 1
            if elem is not None:
                sim = self.declarar(s, s.variable, elem, False, decl=s)
                # Se recibe prestado del contenedor: ni se mueve ni se modifica.
                sim.prestado = True
                sim.leida = True
            if tipo_valor is not None and s.valor is not None:
                sv = self.declarar(s, s.valor, tipo_valor, False, decl=s)
                sv.leida = True
                # Un valor escalar llega por copia; uno duenio, prestado.
                if self.posee(tipo_valor):
                    sv.prestado = True
            self.cuerpo_de_bucle(s.cuerpo)
            self.en_condicional -= 1
            self.en_bucle -= 1
            self.cerrar()

            if duenio is not None and marca in duenio.prestamos:
                duenio.prestamos.remove(marca)
            return

        if isinstance(s, (Romper, Continuar)):
            if not self.en_bucle:
                palabra = "break" if isinstance(s, Romper) else "continue"
                self.error(s, f"`{palabra}` solo tiene sentido dentro de un "
                              f"`for` o un `while`")
            return

        if isinstance(s, Mientras):
            self.en_condicion_bucle += 1
            t = self.expresion(s.cond)
            self.en_condicion_bucle -= 1
            self.en_bucle += 1
            self.movidas_en_bucle.append([])
            if t is not None and t != "bool":
                self.error(s, f"la condicion de `while` debe ser `bool`, es `{t}`")
            self.en_condicional += 1
            self.cuerpo_de_bucle(s.cuerpo)
            self.en_condicional -= 1
            self.en_bucle -= 1
            return

        if isinstance(s, Retorno):
            if s.valor is None:
                if self.retorno_actual is not None:
                    self.error(s, f"esta funcion devuelve `{self.retorno_actual}` "
                                  f"y el `return` esta vacio")
                return
            # Una vista solo puede salir de la funcion si la memoria a la
            # que apunta sobrevive: o es estatica, o es del que llama.
            if self.presta(self.retorno_actual):
                self.comprobar_vista_devuelta(s)

            # devolver una variable duenia la mueve fuera de la funcion (str,
            # struct con campos duenios, arreglo de duenios...)
            self.en_retorno += 1
            previo = self.retorno_directo
            self.retorno_directo = s.valor if isinstance(s.valor, Variable) else None
            tipo = self.expresion(s.valor, destino=self.retorno_actual,
                                  mover_variables=True)
            self.retorno_directo = previo
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

    def camino_de(self, lugar):
        """Lo que presta un sitio, como camino: `p.a.b`. Un indice no se
        sigue —`v[i]` y `v[j]` pueden ser el mismo elemento—, asi que
        `v[i].x` presta todo `v`."""
        partes = []
        while isinstance(lugar, (Campo, Indice)):
            if isinstance(lugar, Indice):
                partes = []
                lugar = lugar.arreglo
            else:
                partes.insert(0, lugar.nombre)
                lugar = lugar.objeto
        if not isinstance(lugar, Variable):
            return None
        return ".".join([lugar.nombre] + partes)

    def tipo_de_lugar(self, lugar):
        # Escribir en `x` no es leer `x`. Mirar su tipo tampoco, asi que la
        # variable suelta se resuelve sin pasar por `usar`.
        if isinstance(lugar, Variable):
            sim = self.buscar(lugar.nombre)
            return sim.tipo if sim is not None else None
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
        if isinstance(e, Try):
            return self.procedencia_de(e.expr)
        if isinstance(e, Sino):
            # Lo peor de los dos caminos: el resultado puede venir de
            # cualquiera de ellos.
            a = self.procedencia_de(e.expr)
            b = self.procedencia_de(e.alternativa)
            if LOCAL in (a, b):
                return LOCAL
            return PARAMETRO if PARAMETRO in (a, b) else ESTATICO
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
            if sim.tipo == "view" or self.es_prestado_st(sim.tipo):
                return sim.procedencia or LOCAL
            return LOCAL            # es un `str`: el buffer es de esta funcion

        if isinstance(e, LiteralStruct):
            # Lo peor de lo que prestan sus campos.
            st = self.structs.get(e.tipo)
            tipos = {c.nombre: c.tipo for c in st.campos} if st else {}
            peor = ESTATICO
            for nombre, valor in e.campos:
                if self.presta(tipos.get(nombre)):
                    p = self.procedencia_de(valor)
                    if p == LOCAL:
                        return LOCAL
                    if p == PARAMETRO:
                        peor = PARAMETRO
            return peor

        if isinstance(e, Campo):
            raiz = self.variable_base(e)
            sim = self.buscar(raiz) if raiz else None
            if sim is not None and self.presta(self._tipo_simple(e)):
                if sim.prestado or es_referencia(sim.tipo):
                    return PARAMETRO
                if self.es_prestado_st(sim.tipo):
                    return sim.procedencia or LOCAL
            return LOCAL

        if isinstance(e, Llamada):
            n = e.nombre

            # vista(x) presta de un `str`. Aunque `x` sea un parametro, si
            # llego por valor esta funcion es su duenia y lo libera al salir.
            # argv vive tanto como el proceso: una vista suya nunca cuelga
            if n == "argumento":
                return ESTATICO

            # `vista(x)` de algo que llego PRESTADO apunta a memoria de quien
            # llamo, asi que sobrevive a la funcion igual que un parametro
            # `view`. Solo es local si el duenio es local.
            if n == "vista" and e.args:
                base = self.variable_base(e.args[0])
                sim_base = self.buscar(base) if base else None
                if sim_base is not None and sim_base.prestado:
                    return PARAMETRO
                return LOCAL

            # La vista que devuelve `obtener` vive dentro del mapa; sobrevive
            # solo si el mapa tambien.
            if n in ("obtener", "obtener_mut") and e.args:
                base = self.variable_base(e.args[0])
                sim_base = self.buscar(base) if base else None
                if sim_base is not None and sim_base.prestado:
                    return PARAMETRO
                return LOCAL

            if n in ("nuevo", "vacio"):
                return LOCAL

            if n == "rebanar":
                return self.procedencia_de(e.args[0]) if e.args else LOCAL

            if (n == "copiar" and len(e.args) == 1
                    and self.presta(self._tipo_simple(e.args[0]))):
                return self.procedencia_de(e.args[0])

            f = self.funciones.get(n)
            if f is None or not self.presta(f.retorno) \
                    or es_referencia(f.retorno or ""):
                return LOCAL

            # A esa funcion se le aplico esta misma regla, asi que lo que
            # devuelve solo puede ser estatico o venir de sus parametros
            # `view`. Luego la procedencia del resultado es la peor de las
            # vistas que le pasamos nosotros.
            peor = ESTATICO
            for arg, param in zip(e.args, f.params):
                if param.tipo == "view" or (not param.prestado
                                            and self.es_prestado_st(param.tipo)):
                    p = self.procedencia_de(arg)
                elif param.prestado:
                    base = self.variable_base(arg)
                    sim_base = self.buscar(base) if base else None
                    p = (PARAMETRO if sim_base is not None and sim_base.prestado
                         else LOCAL)
                else:
                    continue
                if p == LOCAL:
                    return LOCAL
                if p == PARAMETRO:
                    peor = PARAMETRO
            return peor

        return LOCAL

    def _origen_de(self, expr):
        """De que variable duenia proviene una vista, si es que proviene de
        una: la primera de las posibles."""
        for o in self._origenes_de(expr):
            if o != TEMPORAL:
                return o
        return None

    def _origenes_de(self, expr):
        """Todas las variables duenias de las que puede venir una vista, en
        orden y sin repetir. TEMPORAL si puede venir de un valor sin nombre,
        que se libera al acabar la sentencia."""
        salida = []

        def junta(xs):
            for x in xs:
                if x is not None and x not in salida:
                    salida.append(x)

        # `try f(..)` y `f(..) sino alt` no cambian de donde sale el valor;
        # con `sino`, de cualquiera de los dos.
        if isinstance(expr, Try):
            return self._origenes_de(expr.expr)
        if isinstance(expr, Sino):
            junta(self._origenes_de(expr.expr))
            junta(self._origenes_de(expr.alternativa))
            return salida
        if isinstance(expr, Llamada):
            if expr.nombre == "vista" and expr.args:
                return [self.variable_base(expr.args[0])] \
                    if self.variable_base(expr.args[0]) else []
            if expr.nombre == "rebanar" and expr.args:
                return self._origenes_de(expr.args[0])
            if expr.nombre in ("obtener", "obtener_mut") and expr.args:
                base = self.variable_base(expr.args[0])
                return [base] if base else [TEMPORAL]
            # Una funcion que devuelve `view` solo puede devolver algo
            # derivado de lo que le prestaron: un parametro `view`, o uno
            # `&T`/`mut T`. No se sabe de cual, asi que de todos: el
            # prestamo del que llama sigue vivo mientras viva el resultado.
            if (expr.nombre == "copiar" and len(expr.args) == 1
                    and self.presta(self._tipo_simple(expr.args[0]))):
                # La copia de algo que presta presta de lo mismo.
                return self._origenes_de(expr.args[0])
            f = self.funciones.get(expr.nombre)
            if f is not None and self.presta(f.retorno) \
                    and not es_referencia(f.retorno or ""):
                for arg, param in zip(expr.args, f.params):
                    if param.tipo == "view" or (not param.prestado
                                                and self.es_prestado_st(param.tipo)):
                        de_arg = self._origenes_de(arg)
                        if (not de_arg and not isinstance(arg, Variable)
                                and self.procedencia_de(arg) == LOCAL):
                            # Un `str` recien hecho donde se pide una vista.
                            de_arg = [TEMPORAL]
                        junta(de_arg)
                    elif param.prestado:
                        base = self.variable_base(arg)
                        junta([base] if base else [TEMPORAL])
                        # Si lo prestado presta a su vez, tambien de lo suyo.
                        sim_b = self.buscar(base) if base else None
                        if sim_b is not None and self.es_prestado_st(sim_b.tipo):
                            junta(sim_b.origenes)
            # Llamar a una variable que guarda una funcion: su tipo dice lo
            # mismo que la firma, y la regla es la misma.
            sim_f = self.buscar(expr.nombre) if f is None else None
            if sim_f is not None and es_funcion(sim_f.tipo):
                params, retorno = partes_funcion(sim_f.tipo)
                if self.presta(retorno):
                    for arg, pt in zip(expr.args, params):
                        if es_referencia(pt):
                            base = self.variable_base(arg)
                            junta([base] if base else [TEMPORAL])
                            sim_b = self.buscar(base) if base else None
                            if sim_b is not None and self.presta(sim_b.tipo):
                                junta(sim_b.origenes)
                        elif self.presta(pt):
                            de_arg = self._origenes_de(arg)
                            if (not de_arg and not isinstance(arg, Variable)
                                    and self.procedencia_de(arg) == LOCAL):
                                de_arg = [TEMPORAL]
                            junta(de_arg)
            return salida
        if isinstance(expr, SiExpr):
            # Puede ser cualquiera de las dos ramas.
            junta(self._origenes_de(expr.entonces))
            junta(self._origenes_de(expr.sino_))
            return salida
        if isinstance(expr, Match):
            # Lo que da cada brazo; y si da algo que atrapo el patron, el
            # valor mirado: lo atrapado es un prestamo suyo.
            mirado = None
            for b in expr.brazos:
                if not b.es_expresion or not b.cuerpo:
                    continue
                valor = b.cuerpo[0].valor
                junta(self._origenes_de(valor))
                atrapados = _nombres_de_patron(b.nombres)
                if atrapados and any(isinstance(n, Variable)
                                     and n.nombre in atrapados
                                     for n in _nodos_de(valor)):
                    if mirado is None:
                        mirado = self._origenes_mirado(expr.valor) or [TEMPORAL]
                    junta(mirado)
            return salida
        if isinstance(expr, Variable):
            sim = self.buscar(expr.nombre)
            if sim is not None and (sim.tipo == "view"
                                    or self.es_prestado_st(sim.tipo)):
                return list(sim.origenes)
            if sim is not None and sim.tipo == "str":
                return [expr.nombre]
        if isinstance(expr, LiteralStruct):
            # Un struct que presta, de lo que prestan sus campos.
            st = self.structs.get(expr.tipo)
            tipos = {c.nombre: c.tipo for c in st.campos} if st else {}
            for nombre, valor in expr.campos:
                if self.presta(tipos.get(nombre)):
                    de = self._origenes_de(valor)
                    if (not de and not isinstance(valor, Variable)
                            and self.procedencia_de(valor) == LOCAL):
                        de = [TEMPORAL]
                    junta(de)
            return salida
        if isinstance(expr, (Campo, Indice)):
            # Un sitio dentro de una variable: presta de ella. Si es la vista
            # de un struct que presta, de lo mismo que el. Si la variable
            # llego prestada, la memoria es de quien llama.
            raiz = self.variable_base(expr)
            sim = self.buscar(raiz) if raiz else None
            if sim is None or sim.prestado or es_referencia(sim.tipo):
                return salida
            if (self.es_prestado_st(sim.tipo)
                    and self.presta(self._tipo_simple(expr))):
                return list(sim.origenes)
            return [raiz]
        return salida

    def _prestados_por(self, arg, tipo):
        """Lo que un argumento deja prestado mientras dura la llamada, como
        caminos, cuando va a un sitio que presta (`view`, un struct que
        presta). Un `str` suelto donde se pide `view` se presta entero, y
        `vista(p.a)`, solo `p.a`; una vista con nombre ya tiene sus prestamos
        apuntados en sus duenios, que se prestan enteros."""
        if isinstance(arg, Variable):
            sim = self.buscar(arg.nombre)
            if sim is not None and sin_prestamo(sim.tipo) == "str":
                return [arg.nombre]
            return []
        if tipo is not None and sin_prestamo(tipo) == "str" \
                and isinstance(arg, (Campo, Indice)):
            camino = self.camino_de(arg)
            return [camino] if camino else []
        if (isinstance(arg, Llamada) and arg.nombre == "vista" and len(arg.args) == 1
                and isinstance(arg.args[0], (Campo, Indice))):
            # `vista` solo mira un `str`: lo demas ya es un error.
            camino = self.camino_de(arg.args[0])
            return [camino] if camino else []
        return [o for o in self._origenes_de(arg) if o != TEMPORAL]

    def _tipo_simple(self, e):
        """El tipo de una variable o de un campo, sin comprobar nada."""
        if isinstance(e, Variable):
            sim = self.buscar(e.nombre)
            return sin_prestamo(sim.tipo) if sim is not None else None
        if isinstance(e, Campo):
            base = self._tipo_simple(e.objeto)
            st = self.structs.get(base) if base else None
            for c in (st.campos if st else []):
                if c.nombre == e.nombre:
                    return c.tipo
        return None

    def _apuntar(self, nodo, sim, valor):
        """La vista `sim` pasa a apuntar a lo que da `valor`: cada duenio
        queda prestado mientras ella viva, y tiene que vivir al menos lo
        mismo. Lo que ya prestaba lo sigue prestando: si la asignacion va en
        una rama, la otra puede no haberla hecho."""
        nuevos = self._origenes_de(valor)
        if TEMPORAL in nuevos:
            self.error(nodo, f"`{sim.nombre}` apuntaria a un valor temporal, "
                             f"que se libera al acabar esta sentencia: guarda "
                             f"ese valor en una variable y presta de ella")
        nivel = self._nivel(sim)
        for origen in nuevos:
            if origen == TEMPORAL or origen in sim.origenes:
                continue
            duenio = self.buscar(origen)
            if duenio is None:
                continue
            if self._nivel(duenio) > nivel:
                self.error(nodo, f"`{sim.nombre}` vive mas que `{origen}`: "
                                 f"`{origen}` muere al cerrar su bloque y "
                                 f"`{sim.nombre}` seguiria apuntando a ella. "
                                 f"Declara `{origen}` fuera del bloque, o haz "
                                 f"de `{sim.nombre}` un `str` con `nuevo(...)`")
                continue
            sim.origenes.append(origen)
            duenio.prestamos.append(sim.nombre)
        if sim.origen is None and sim.origenes:
            sim.origen = sim.origenes[0]

    def _nivel(self, sim):
        """En que bloque esta declarado: 0 es el de fuera."""
        for i in range(len(self.ambitos) - 1, -1, -1):
            if self.ambitos[i].get(sim.nombre) is sim:
                return i
        return 0

    # ---------- expresiones ----------

    def comprobar_literal(self, e, destino):
        """Comprueba la magnitud antes de que C pueda truncarla o hacerla inf.

        El signo menos es un nodo separado. Mirarlo junto al literal permite
        aceptar exactamente ``INT_MIN``, cuya magnitud es una unidad mayor que
        ``INTMAX``, sin relajar el limite para los positivos.
        """
        # El contexto tambien alcanza los numeros dentro de una expresion
        # puramente literal: `let x: u8 = 1 + 256` no debe esquivar el limite
        # solo por tener un operador en medio. En desplazamientos, la cantidad
        # es un `usize`, no el tipo del valor desplazado.
        if isinstance(e, Binaria):
            if (destino in DECIMALES and literal_de(e)
                    and e.op in {"%", "&", "|", "^", "<<", ">>"}):
                # Los numeros escritos son decimales aqui, y con decimales
                # no hay resto ni bits.
                if e.op == "%":
                    self.error(e, "`%` es el resto de una division entera; con "
                                  "decimales no tiene un significado unico")
                else:
                    self.error(e, f"`{e.op}` trabaja sobre los bits de un "
                                  f"entero, recibio `{destino}` y `{destino}`")
                return
            self.comprobar_literal(e.izq, destino)
            self.comprobar_literal(
                e.der, "usize" if e.op in {"<<", ">>"} else destino)
            return
        if isinstance(e, SiExpr):
            # Cada rama que sea un numero escrito tiene que caber.
            self.comprobar_literal(e.entonces, destino)
            self.comprobar_literal(e.sino_, destino)
            return

        negativo = (isinstance(e, Unaria) and e.op == "-"
                    and isinstance(e.valor, (Entero, Decimal)))
        literal = e.valor if negativo else e

        if isinstance(literal, Entero):
            valor = literal.valor
            if destino in SIN_SIGNO:
                bits = SIN_SIGNO[destino] or BITS_USIZE
                cabe = not negativo and valor <= (1 << bits) - 1
            elif destino in CON_SIGNO:
                bits = CON_SIGNO[destino]
                limite = ((1 << (bits - 1)) if negativo
                          else (1 << (bits - 1)) - 1)
                cabe = valor <= limite
            elif destino in DECIMALES:
                # Un entero escrito tiene que caber exacto: `2^53 + 1` en un
                # `f64` se redondearia en silencio, igual que con `como`.
                significativo = valor >> max((valor & -valor).bit_length() - 1, 0)
                cabe = significativo.bit_length() <= MANTISA[destino]
            else:
                return
            if not cabe:
                signo = "-" if negativo else ""
                exacto = " sin perder precision" if destino in DECIMALES else ""
                self.error(e, f"el literal `{signo}{valor}` no cabe en "
                              f"`{destino}`{exacto}")
            return

        if isinstance(literal, Decimal) and destino in DECIMALES:
            try:
                valor = NumeroDecimal(literal.valor)
            except InvalidOperation:
                self.error(e, "el literal decimal no es un numero valido")
                return
            umbral = UMBRAL_F32 if destino == "f32" else UMBRAL_F64
            if not valor.is_finite() or abs(valor) >= umbral:
                signo = "-" if negativo else ""
                self.error(e, f"el literal `{signo}{literal.valor}` no cabe "
                              f"en `{destino}` como numero finito")

    def expresion(self, e, destino=None, mover_variables=False):
        """El tipo de `e`, comprobandola. Queda anotado en el nodo, en
        `tipo_resuelto`: el generador lo lee de ahi en vez de deducirlo otra
        vez por su cuenta, que es como se equivocaba."""
        t = self._expresion(e, destino, mover_variables)
        e.tipo_resuelto = t
        if t in (LITERAL, LITERAL_DECIMAL) and sin_prestamo(destino or "") in NUMERICOS:
            self.fijar_literal(e, sin_prestamo(destino))
        elif t == LITERAL and not isinstance(e, Entero):
            # Una cuenta que todavia no sabe su tipo: se lo dira quien la
            # use, o al acabar la sentencia sera `usize`.
            self.escritas.append(e)
        return t

    def fijar_literal(self, e, tipo):
        """Un numero escrito ya sabe su tipo: se lo dice el otro lado de la
        operacion, o el sitio donde va. Se anota en el y en todo lo que es
        numero escrito por debajo; un desplazamiento cuenta en `usize`. Y si
        es una cuenta de enteros, se hace ya."""
        antes = getattr(e, "tipo_resuelto", LITERAL)
        self._fijar_literal(e, tipo)
        if antes == LITERAL and tipo in ENTEROS and literal_de(e) == "entero":
            self.contar_escrita(e, tipo)

    def _fijar_literal(self, e, tipo):
        if getattr(e, "tipo_resuelto", LITERAL) not in (LITERAL, LITERAL_DECIMAL):
            return
        if not literal_de(e):
            return
        e.tipo_resuelto = tipo
        if isinstance(e, Binaria):
            self._fijar_literal(e.izq, tipo)
            self._fijar_literal(e.der, "usize" if e.op in {"<<", ">>"} else tipo)
        elif isinstance(e, Unaria):
            self._fijar_literal(e.valor, tipo)
        elif isinstance(e, SiExpr):
            self._fijar_literal(e.entonces, tipo)
            self._fijar_literal(e.sino_, tipo)

    def contar_escrita(self, e, tipo):
        """Hace una cuenta de numeros escritos en su tipo. Lo que en marcha
        pararia el programa —desbordarse, dividir por cero, desplazar el
        ancho o mas— para aqui, con su linea: `let x: u8 = 200 + 100;` no
        es un programa que aborte, es un programa mal escrito."""
        try:
            self._valor_escrito(e, tipo)
        except _CuentaParada as p:
            self.error(p.nodo, p.mensaje)

    def contar_pendientes(self, desde):
        """Las cuentas de la sentencia que nadie tipo: son `usize`. De fuera
        adentro, que la de fuera hace tambien las suyas."""
        for e in reversed(self.escritas[desde:]):
            if getattr(e, "tipo_resuelto", LITERAL) == LITERAL:
                self.contar_escrita(e, "usize")
        del self.escritas[desde:]

    def _valor_escrito(self, e, tipo):
        """El valor de la cuenta, o None si depende de algo que solo se sabe
        en marcha: la condicion de un `if`. Cada nodo se cuenta una vez."""
        if id(e) in self.contadas:
            return None
        self.contadas.add(id(e))
        minimo, maximo, bits, con_signo = _limites(tipo)
        if isinstance(e, Entero):
            # Uno que no cabe ya tiene su error.
            return e.valor if minimo <= e.valor <= maximo else None
        if isinstance(e, SiExpr):
            self._valor_escrito(e.entonces, tipo)
            self._valor_escrito(e.sino_, tipo)
            return None
        if not isinstance(e, Binaria):
            return None
        op = e.op
        a = self._valor_escrito(e.izq, tipo)
        b = self._valor_escrito(e.der, "usize" if op in {"<<", ">>"} else tipo)
        if a is None or b is None:
            return None
        cuenta = f"`{a} {op} {b}`"
        if op in {"+", "-", "*", "+?", "-?", "*?"}:
            r = a + b if op[0] == "+" else a - b if op[0] == "-" else a * b
            if op.endswith("?"):
                return _envolver(r, tipo)
            if not minimo <= r <= maximo:
                raise _CuentaParada(e, f"{cuenta} no cabe en `{tipo}`{AL_COMPILAR}")
            return r
        if op in {"/", "%"}:
            if b == 0:
                raise _CuentaParada(e, f"{cuenta} divide por cero{AL_COMPILAR}")
            if con_signo and a == minimo and b == -1:
                if op == "/":
                    raise _CuentaParada(e, f"{cuenta} no cabe en `{tipo}`{AL_COMPILAR}")
                return 0
            # Como C: el cociente se trunca hacia cero.
            q = abs(a) // abs(b)
            if (a < 0) != (b < 0):
                q = -q
            return q if op == "/" else a - b * q
        if op in {"&", "|", "^"}:
            return _envolver(a & b if op == "&" else a | b if op == "|" else a ^ b,
                             tipo)
        if op in {"<<", ">>"}:
            if b >= bits:
                raise _CuentaParada(e, f"{cuenta} desplaza un `{tipo}` {b} bits, "
                                       f"y tiene {bits}{AL_COMPILAR}")
            return _envolver(a << b, tipo) if op == "<<" else a >> b
        return None

    def _expresion(self, e, destino=None, mover_variables=False):
        if destino in NUMERICOS:
            self.comprobar_literal(e, destino)
        if isinstance(e, Entero):
            return LITERAL
        if isinstance(e, Decimal):
            return LITERAL_DECIMAL
        if isinstance(e, Cadena):
            # Un literal es texto estatico: una vista sin dueño.
            return "view"
        if isinstance(e, Booleano):
            return "bool"

        if isinstance(e, Interpolada):
            for x in e.expresiones:
                t = self.expresion(x)
                if t is None:
                    continue
                if es_arreglo(t) or es_lista(t) or es_mapa(t) or t in self.structs:
                    self.error(e, f"dentro de `{{}}` va un escalar o texto, y "
                                  f"`{t}` no lo es")
            return "str"

        if isinstance(e, Variable):
            sim = self.buscar(e.nombre)
            if sim is None:
                # El nombre de una funcion, sin parentesis detras, es un valor:
                # el puntero a esa funcion. Sin captura, asi que no posee nada.
                f = self.funciones.get(e.nombre)
                if f is not None:
                    if f.falible:
                        self.error(e, f"`{e.nombre}` puede fallar, y en v0 una "
                                      f"funcion que se pasa como valor no "
                                      f"puede: quitale el `!` o envuelvela")
                        return None
                    e.es_funcion = True
                    return firma_funcion([tipo_de_parametro(p)
                                          for p in f.params], f.retorno)
                if e.nombre in self.genericas:
                    self.error(e, f"`{e.nombre}` es generica: hay una funcion "
                                  f"por cada juego de tipos, y aqui no se sabe "
                                  f"cual. Envuelvela en una funcion normal")
                    return None
                self.error(e, f"`{e.nombre}` no esta declarada")
                return None
            if mover_variables and self.posee(sim.tipo):
                self.mover(e, sim)
                # El generador necesita distinguir una lectura de una entrega
                # de propiedad. Guardarlo en el propio uso evita reconstruir
                # despues el contexto semantico a partir de los tipos.
                e.mueve = True
            else:
                self.usar(e, sim)
            return sim.tipo

        if isinstance(e, Unaria):
            t = self.expresion(e.valor)
            if e.op == "~":
                if t == LITERAL:
                    self.fijar_literal(e.valor, "usize")
                    return "usize"
                if t is not None and t not in ENTEROS:
                    self.error(e, f"`~` da la vuelta a los bits de un entero, "
                                  f"recibio `{t}`")
                return t
            if e.op == "!":
                if t is not None and t != "bool":
                    self.error(e, f"`!` necesita un `bool`, recibio `{t}`")
                return "bool"
            if t == LITERAL:
                # Con un destino firmado, el literal toma ese ancho. Esto es
                # esencial para que su minimo (por ejemplo `-128` en i8) sea
                # representable. Sin contexto conserva el valor por defecto.
                if destino in CON_SIGNO or destino in DECIMALES:
                    self.fijar_literal(e.valor, destino)
                    return destino
                if destino in SIN_SIGNO:
                    # Un `-3` suelto ya lo dice `comprobar_literal`: no cabe.
                    # Una cuenta, `-(3 + 4)`, no la mira nadie mas.
                    if not isinstance(e.valor, Entero):
                        self.error(e, f"`{destino}` no tiene signo: no se "
                                      f"puede negar")
                    self.fijar_literal(e.valor, destino)
                    return destino
                self.comprobar_literal(e, "i64")
                self.fijar_literal(e.valor, "i64")
                return "i64"
            if t == LITERAL_DECIMAL:
                return LITERAL_DECIMAL
            if t in DECIMALES:
                return t
            if t is not None and t not in ENTEROS:
                self.error(e, f"`-` necesita un entero, recibio `{t}`")
            if t in SIN_SIGNO:
                self.error(e, f"`{t}` no tiene signo: no se puede negar")
            return t

        if isinstance(e, Cierre):
            return e.tipo_struct or self.cierre(e)

        if isinstance(e, SiExpr):
            tc = self.expresion(e.cond)
            if tc is not None and tc != "bool":
                self.error(e, f"la condicion de un `if` tiene que ser `bool`, "
                              f"y es `{tc}`")
            # Las dos ramas son caminos que se excluyen: lo que una mueve, la
            # otra no lo ha movido. Es la misma regla que el `if` sentencia.
            antes = self._foto()
            self.en_condicional += 1
            ta = self.expresion(e.entonces, destino=destino,
                                mover_variables=mover_variables)
            tras_a = self._foto()
            self._restaurar(antes)
            tb = self.expresion(e.sino_, destino=destino,
                                mover_variables=mover_variables)
            tras_b = self._foto()
            self.en_condicional -= 1
            self._juntar_ramas(tras_a, tras_b)
            # Una rama que es un numero escrito toma el tipo de la otra, y
            # tiene que caber en el.
            if ta in (LITERAL, LITERAL_DECIMAL) and sin_prestamo(tb or "") in NUMERICOS:
                self.comprobar_literal(e.entonces, sin_prestamo(tb))
                self.fijar_literal(e.entonces, sin_prestamo(tb))
            elif tb in (LITERAL, LITERAL_DECIMAL) and sin_prestamo(ta or "") in NUMERICOS:
                self.comprobar_literal(e.sino_, sin_prestamo(ta))
                self.fijar_literal(e.sino_, sin_prestamo(ta))
            elif ta == LITERAL and tb == LITERAL_DECIMAL:
                self.fijar_literal(e.entonces, LITERAL_DECIMAL)
                ta = LITERAL_DECIMAL
            elif tb == LITERAL and ta == LITERAL_DECIMAL:
                self.fijar_literal(e.sino_, LITERAL_DECIMAL)
                tb = LITERAL_DECIMAL
            if ta is not None and tb is not None and not encaja(ta, tb) \
                    and not encaja(tb, ta):
                self.error(e, f"las dos ramas de un `if` tienen que dar el "
                              f"mismo tipo, y dan `{ta}` y `{tb}`")
            if ta in (None, LITERAL, LITERAL_DECIMAL):
                return tb if tb is not None else ta
            return ta

        if isinstance(e, EnumLit):
            en = self.enums.get(e.tipo)
            if en is None:
                self.error(e, f"`{e.tipo}` no es un enum")
                return None
            v = self.variante_de(e.tipo, e.variante)
            if v is None:
                cuales = ", ".join(f"`{e.tipo}.{x.nombre}`"
                                   for x in en.variantes)
                self.error(e, f"`{e.tipo}` no tiene la forma `{e.variante}`; "
                              f"tiene {cuales}")
                return None
            if len(e.args) != len(v.tipos):
                cuantos = (f"{len(v.tipos)} valor"
                           + ("es" if len(v.tipos) != 1 else ""))
                self.error(e, f"`{e.tipo}.{e.variante}` lleva {cuantos}, y se "
                              f"le dieron {len(e.args)}")
                return None
            for arg, t in zip(e.args, v.tipos):
                # La variante se queda con lo que le dan: entregarselo es un
                # movimiento, igual que meterlo en un struct.
                ta = self.expresion(arg, destino=t,
                                    mover_variables=self.posee(t))
                if ta is not None and not encaja(t, ta):
                    self.error(e, f"`{e.tipo}.{e.variante}` lleva un `{t}` y "
                                  f"se le dio un `{ta}`")
            return e.tipo

        if isinstance(e, Match):
            return self.match(e, destino, mover_variables)

        if isinstance(e, Conversion):
            t = sin_prestamo(self.expresion(e.valor) or "")
            # Un numero escrito sin nada al lado sale de su tipo de siempre.
            if t == LITERAL:
                self.fijar_literal(e.valor, "usize")
            elif t == LITERAL_DECIMAL:
                self.fijar_literal(e.valor, "f64")
            if e.a_tipo not in NUMERICOS:
                self.error(e, f"`como` convierte entre numeros, y `{e.a_tipo}` "
                              f"no es uno")
            elif t and t not in (LITERAL, LITERAL_DECIMAL) and t not in NUMERICOS:
                self.error(e, f"`como` convierte entre numeros, y `{t}` no es "
                              f"uno")
            elif (e.envolviendo and e.a_tipo in ENTEROS
                    and (t in DECIMALES or t == LITERAL_DECIMAL)):
                # `como?` se queda con los bits de abajo, y de un decimal a un
                # entero eso no significa nada: no hay bits que recortar, hay
                # que decidir que se hace con la parte fraccionaria.
                self.error(e, f"`como?` de un decimal a `{e.a_tipo}` no tiene "
                              f"sentido: di que quieres con la parte decimal "
                              f"—`piso`, `techo` o `redondear` de "
                              f"`std/numero`— y luego `como {e.a_tipo}`")
            elif t == e.a_tipo:
                self.aviso(e, f"`como {e.a_tipo}` sobre algo que ya es "
                              f"`{e.a_tipo}`: no hace nada")
            return e.a_tipo

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
            alt = self.expresion(e.alternativa, destino=t, mover_variables=True)

            if t is not None and es_referencia(t):
                self.error(e, f"`sino` no vale aqui: la llamada devuelve un "
                              f"prestamo (`{t}`) y no hay nada que prestar "
                              f"cuando falla. Usa `try`, o pregunta antes con "
                              f"`tiene(...)`")
            elif t is not None and alt is not None and not encaja(t, alt):
                self.error(e, f"la llamada da `{t}` y el valor de despues de "
                              f"`sino` es `{alt}`")
            return t

        if isinstance(e, Campo):
            return self.campo(e, mover_variables)

        if isinstance(e, Indice):
            return self.indice(e, mover_variables)

        if isinstance(e, LiteralStruct):
            return self.literal_struct(e, destino)

        if isinstance(e, LiteralArreglo):
            return self.literal_arreglo(e, destino)

        if isinstance(e, Binaria):
            return self.binaria(e)

        if isinstance(e, Llamada):
            return self.llamada(e, destino=destino)

        raise AssertionError(f"expresion desconocida: {type(e).__name__}")

    def comprobar_mapa_valido(self, nodo, tipo):
        """Los limites de `mapa<K, V>` en v0, dichos donde se declara."""
        if not es_mapa(tipo):
            return
        k, v = partes_mapa(tipo)
        if k != "str":
            self.error(nodo, f"en v0 la clave de un mapa tiene que ser `str`, "
                             f"y aqui es `{k}`")
        if es_referencia(v) or es_referencia(k):
            self.error(nodo, "un mapa guarda valores, no prestamos: `&T` no "
                             "puede ser ni clave ni valor")

    def interna_mapa(self, e: Llamada, nombre):
        """`poner`, `obtener`, `tiene` y `claves` sobre `mapa<K, V>`."""
        esperados = {"poner": 3, "obtener": 2, "obtener_mut": 2, "tiene": 2,
                     "claves": 1, "quitar": 2}[nombre]
        retorno_si_falla = {"poner": UNIDAD, "obtener": None,
                            "obtener_mut": None, "tiene": "bool",
                            "claves": None, "quitar": "bool"}[nombre]

        if len(e.args) != esperados:
            self.error(e, f"`{nombre}` espera {esperados} argumento(s) y "
                          f"recibio {len(e.args)}")
            for a in e.args:
                self.expresion(a)
            return retorno_si_falla

        lugar = e.args[0]
        base = self.variable_base(lugar)
        sim = self.buscar(base) if base else None
        tipo_mapa = self.tipo_de_lugar(lugar) if sim is not None else None

        if sim is None:
            self.error(e, f"el primer argumento de `{nombre}` tiene que ser "
                          f"una variable, un campo o un elemento")
            for a in e.args[1:]:
                self.expresion(a)
            return retorno_si_falla

        if not es_mapa(tipo_mapa):
            self.error(e, f"`{nombre}` opera sobre `mapa<K, V>`, recibio "
                          f"`{tipo_mapa}`")
            for a in e.args[1:]:
                self.expresion(a)
            return retorno_si_falla

        k, v = partes_mapa(tipo_mapa)

        if nombre == "claves":
            self.usar(lugar, sim)
            return f"lista<{k}>"

        # La clave se lee prestada: el mapa guarda su propia copia.
        tc = self.expresion(e.args[1])
        if tc is not None and not encaja(k, tc) and not (k == "str" and tc == "view"):
            self.error(e, f"la clave del mapa es `{k}` y se paso `{tc}`")

        if nombre == "tiene":
            self.usar(lugar, sim)
            return "bool"

        if nombre == "obtener_mut":
            # Prestar para modificar: el mapa tiene que ser modificable, y
            # mientras dure el prestamo nadie mas puede tocarlo.
            if not self.es_compuesto(v):
                self.error(e, f"`obtener_mut` presta para modificar algo que "
                              f"vive en el mapa; `{v}` es un escalar, asi que "
                              f"usa `obtener` y vuelve a `poner`")
                return v
            self.mutar(lugar, sim)
            return f"&mut {v}"

        if nombre == "quitar":
            # Devuelve si habia algo que quitar: asi el que llama puede
            # distinguir "lo borre" de "no estaba" sin consultar antes.
            self.mutar(lugar, sim)
            return "bool"

        if nombre == "obtener":
            self.usar(lugar, sim)
            # Un valor escalar cabe en el retorno; uno duenio no se puede
            # sacar sin dejar el mapa a medias, asi que se presta.
            # Para texto se presta como `view`, que es lo que se quiere leer;
            # para lo demas, como `&V`.
            if not self.posee(v):
                return v
            return "view" if v == "str" else f"&{v}"

        # poner: muta el mapa, y el valor entra por copia
        tv = self.expresion(e.args[2], destino=v,
                            mover_variables=self.posee(v))
        if tv is not None and not encaja(v, tv):
            self.error(e, f"el mapa guarda `{v}` y se intento poner `{tv}`")
        self.mutar(lugar, sim)
        return UNIDAD

    def desenvolver(self, nodo, interna, palabra):
        """Comprueba que lo que sigue a `try`/`sino` sea algo que pueda fallar."""
        es_falible = False
        if isinstance(interna, Llamada):
            # Una generica todavia no tiene copia: la plantilla ya dice si
            # puede fallar, que es lo unico que hace falta saber aqui.
            f = (self.funciones.get(interna.nombre)
                 or self.genericas.get(interna.nombre))
            firma = INTERNAS.get(interna.nombre)
            es_falible = bool((f is not None and f.falible)
                               or (firma is not None and firma.get("falible")))
        if not es_falible:
            self.error(nodo, f"`{palabra}` va delante de una llamada a una "
                             f"funcion declarada con `!`")
            self.expresion(interna)
            return None
        return self.llamada(interna, desenvuelta=True)

    def _ruta_de_campo(self, e):
        """`p.a.b` -> ("a.b", "p"): la cadena de campos desde una variable.
        (None, None) si por medio hay un indice, una llamada u otra cosa."""
        nombres = []
        while isinstance(e, Campo):
            nombres.append(e.nombre)
            e = e.objeto
        if not isinstance(e, Variable) or not nombres:
            return None, None
        return ".".join(reversed(nombres)), e.nombre

    def campo(self, e: Campo, mover_variables=False):
        ruta, raiz = self._ruta_de_campo(e)
        sim_raiz = self.buscar(raiz) if raiz else None
        # Lo ya sacado no se usa; el error se da una vez y se sigue.
        ya_sacado = False
        if (not self.por_campo and not self.escribiendo
                and sim_raiz is not None and sim_raiz.sacados):
            for r, linea in sim_raiz.sacados.items():
                if ruta == r or ruta.startswith(r + "."):
                    self.error(e, f"`{raiz}.{r}` ya se saco en la linea "
                                  f"{linea} y aqui se usa otra vez")
                    ya_sacado = True
                    break
                if r.startswith(ruta + "."):
                    self.error(e, f"`{raiz}.{ruta}` esta a medio mover: "
                                  f"`{raiz}.{r}` se saco en la linea {linea}")
                    ya_sacado = True
                    break
        encadenado = isinstance(e.objeto, (Variable, Campo))
        self.por_campo += encadenado
        base = self.expresion(e.objeto)
        self.por_campo -= encadenado
        if base is None:
            return None
        if es_referencia(base):
            base = apuntado(base)       # `p.x` sobre un `&P` mira dentro
        st = self.structs.get(base)
        if st is None:
            self.error(e, f"`{base}` no es un struct, no tiene campos")
            return None
        for c in st.campos:
            if c.nombre == e.nombre:
                if (mover_variables and self.posee(c.tipo)
                        and not self.por_campo and not ya_sacado):
                    self._sacar_campo(e, base, ruta, sim_raiz)
                return c.tipo
        self.error(e, f"`{base}` no tiene un campo `{e.nombre}`")
        return None

    def _sacar_campo(self, e, base, ruta, sim):
        """Mover un campo con duenio fuera de su struct. En C se copia y su
        sitio queda a ceros, que en Tcode es un valor valido: al liberar el
        struct, ese campo no suelta nada. Aqui se apunta, para que nadie use
        el campo, ni el struct entero, hasta que se reponga."""
        if sim is None:
            self.error(e, f"no se puede sacar `{e.nombre}` de un struct que "
                          f"no esta en una variable: dejaria a `{base}` a "
                          f"medio mover. Guarda antes el struct, o usa "
                          f"`copiar(...)`")
            return
        nombre = f"{sim.nombre}.{ruta}"
        if sim.prestado or es_referencia(sim.tipo) or sim.tipo == "view":
            self.error(e, f"`{sim.nombre}` es prestada: no se puede sacar "
                          f"`{nombre}` de algo que no es tuyo. Usa "
                          f"`copiar(...)`")
            return
        if self.en_guarda:
            self.error(e, f"una guarda no mueve nada: `{nombre}` se moveria "
                          f"aunque el brazo no case. Presta, o usa "
                          f"`copiar(...)`")
            return
        if not self.en_retorno and (
                self.en_condicional > sim.condicional_al_declarar
                or self.en_bucle > sim.bucle_al_declarar):
            self.error(e, f"no se puede sacar `{nombre}` dentro de un `if`, "
                          f"un `match` o un bucle: despues no se sabria si "
                          f"sigue ahi. Sacalo donde vive `{sim.nombre}`, o "
                          f"deja otro valor en su sitio con "
                          f"`intercambiar(...)`")
            return
        if sim.prestamos:
            self.error(e, f"no se puede sacar `{nombre}`: "
                          f"{self._ocupada(sim)}")
            return
        sim.sacados[ruta] = e.linea
        e.sacado = True

    def indice(self, e: Indice, mover_variables=False):
        base = self.expresion(e.arreglo)
        ti = self.expresion(e.indice)
        if ti is not None and not encaja("usize", ti):
            self.error(e, f"un indice tiene que ser `usize`, es `{ti}`")
        if base is None:
            return None
        base = sin_prestamo(base)
        if not es_arreglo(base) and not es_lista(base) and not es_bloque(base):
            self.error(e, f"`{base}` no es un arreglo, no se puede indexar")
            return None
        if es_arreglo(base):
            elem = elem_de(base)
        elif es_bloque(base):
            elem = elem_bloque(base)
        else:
            elem = elem_lista(base)
        if mover_variables and self.posee(elem):
            que = ("un bloque" if es_bloque(base)
                   else "una lista" if es_lista(base) else "un arreglo")
            self.error(e, f"no se puede sacar un elemento de {que} y dejar el "
                          f"hueco sin duenio. Si quieres sacarlo, di que dejas "
                          f"en su sitio: `intercambiar(...)`. Si solo quieres "
                          f"leerlo, `copiar(...)`")
        return elem

    def _patron_valido(self, e, base, variante, args):
        """Si lo que va en cada posicion de `base.variante(...)` encaja con
        lo que lleva la forma: el numero, las formas anidadas y los
        literales."""
        v = self.variante_de(base, variante)
        if len(args) != len(v.tipos):
            cuantos = (f"{len(v.tipos)} valor"
                       + ("es" if len(v.tipos) != 1 else ""))
            self.error(e, f"`{base}.{variante}` lleva {cuantos}, y "
                          f"el patron atrapa {len(args)}")
            return False
        for i, (arg, t) in enumerate(zip(args, v.tipos)):
            if isinstance(arg, str):
                continue
            if isinstance(arg, PatronForma):
                otro = self.enums.get(t)
                if otro is None or arg.enum != t:
                    self.error(e, f"`{base}.{variante}` lleva un `{t}` en la "
                                  f"posicion {i + 1}, y el patron pone "
                                  f"`{arg.enum}.{arg.variante}`")
                    return False
                if self.variante_de(t, arg.variante) is None:
                    cuales = ", ".join(f"`{t}.{x.nombre}`"
                                       for x in otro.variantes)
                    self.error(e, f"`{t}` no tiene la forma "
                                  f"`{arg.variante}`; tiene {cuales}")
                    return False
                if not self._patron_valido(e, t, arg.variante, arg.args):
                    return False
                continue
            lit = arg.valor
            numero = (isinstance(lit, Entero)
                      or (isinstance(lit, Unaria) and lit.op == "-"
                          and isinstance(lit.valor, Entero)))
            if numero and t in ENTEROS:
                self.comprobar_literal(lit, t)
            elif not ((isinstance(lit, Cadena) and t == "str")
                      or (isinstance(lit, Booleano) and t == "bool")):
                self.error(e, f"`{base}.{variante}` lleva un `{t}` en la "
                              f"posicion {i + 1}, y el literal del patron no "
                              f"es uno")
                return False
        return True

    def _declarar_patron(self, e, base, variante, args):
        """Lo que atrapa el patron, prestado: un `match` MIRA, no desmonta.
        Rust deja sacar el valor de dentro, y a cambio tiene que llevar la
        cuenta de un enum medio movido; aqui quien quiera quedarse con lo de
        dentro escribe `copiar(...)`. Un `str` prestado es una `view`."""
        v = self.variante_de(base, variante)
        for arg, t in zip(args, v.tipos):
            if isinstance(arg, PatronForma):
                self._declarar_patron(e, t, arg.variante, arg.args)
            elif isinstance(arg, str) and arg != "_":
                if self.posee(t):
                    tp = "view" if t == "str" else f"&{t}"
                else:
                    tp = t
                sim = self.declarar(e, arg, tp, False)
                if tp != t:
                    # Lo atrapado apunta dentro del valor mirado: mientras
                    # viva, ese valor no se mueve ni se modifica.
                    for origen in self._origenes_mirado(e.valor):
                        duenio = self.buscar(origen)
                        if duenio is None or origen in sim.origenes:
                            continue
                        sim.origenes.append(origen)
                        duenio.prestamos.append(arg)
                    if sim.origenes:
                        sim.origen = sim.origenes[0]

    def _origenes_mirado(self, valor):
        """De que variables es lo que atrapa un patron: de la variable del
        valor mirado, y si esa es un prestamo, tambien de lo que presta."""
        base = self.variable_base(valor)
        sim = self.buscar(base) if base else None
        if sim is None:
            return []
        salida = [base]
        if self.presta(sim.tipo):
            salida.extend(o for o in sim.origenes if o not in salida)
        return salida

    def cierre(self, e: Cierre):
        """Una clausura se convierte en un struct con lo capturado y una
        funcion que lo recibe. A partir de ahi no hay nada nuevo: el struct
        posee lo que posean sus campos, se libera solo, y se copia con
        `copiar` como cualquier otro."""
        import copy as _copy

        self.n_cierres += 1
        nombre_struct = f"Cierre_{self.n_cierres}"
        nombre_fn = f"ss_cierre_{self.n_cierres}"

        campos = []
        vistos = set()
        for nombre in e.capturas:
            if nombre in vistos:
                self.error(e, f"`{nombre}` se captura dos veces")
                continue
            vistos.add(nombre)
            sim = self.buscar(nombre)
            if sim is None:
                self.error(e, f"`{nombre}` no esta declarada, no se puede "
                              f"capturar")
                continue
            if self.presta(sim.tipo):
                arreglo = (f"Captura un `str` con `copiar({nombre})`"
                           if sim.tipo == "view" or es_referencia(sim.tipo)
                           else f"Captura lo que necesites de `{nombre}`")
                self.error(e, f"`{nombre}` es `{sim.tipo}`, un prestamo: una "
                              f"clausura captura por valor, y guardar un "
                              f"prestamo exigiria saber cuanto vive. "
                              f"{arreglo}")
                continue
            campos.append(CampoDef(nombre, sim.tipo, e.linea))
            # Capturar por valor mueve lo que posee memoria, igual que
            # pasarlo a una funcion.
            if self.posee(sim.tipo):
                self.mover(e, sim)
            else:
                self.usar(e, sim)

        if not campos:
            # Un struct vacio no es C valido. Una clausura sin capturas es
            # solo una funcion sin nombre, y el campo sobra en cuanto el
            # compilador de C optimiza.
            campos.append(CampoDef("ss_vacio", "u8", e.linea))
        st = Struct(nombre_struct, campos, linea=e.linea, archivo=e.archivo)
        self.structs[nombre_struct] = st
        self.structs_instanciados.append(st)
        # En un mensaje, `Cierre_3` no le dice nada a nadie, ni `ss_cierre_3`.
        self.nombre_original[nombre_struct] = "clausura"
        self.nombre_original[nombre_fn] = "clausura"

        # El cuerpo ve lo capturado como campos del entorno. Si algo se
        # capturo con `mut`, el entorno llega prestado para modificar: lo
        # que cambie sigue ahi en la llamada siguiente.
        cuerpo = _copy.deepcopy(e.cuerpo)
        _renombrar_capturas(cuerpo, vistos, e.linea)
        modifica = bool(e.mutables)
        if modifica:
            self.cierres_mut.add(nombre_struct)
        entorno = Parametro("_ss_entorno", nombre_struct, modifica, not modifica)
        f = Funcion(nombre_fn, [entorno] + list(e.params), e.retorno, cuerpo,
                    e.falible, linea=e.linea, archivo=e.archivo)
        self.funciones[nombre_fn] = f
        self.instanciadas.append(f)
        self.cierres[nombre_struct] = nombre_fn

        guardado = (self.retorno_actual, self.falible_actual,
                    self.simbolos_funcion, self.ambitos)
        self.ambitos = []
        propia = {"mutables": set(e.mutables), "modificadas": set()}
        self.pila_cierres.append(propia)
        try:
            self.comprobar_funcion(f)
        finally:
            self.pila_cierres.pop()
            (self.retorno_actual, self.falible_actual,
             self.simbolos_funcion, self.ambitos) = guardado
        for nombre in e.mutables:
            if (nombre not in propia["modificadas"]
                    and not nombres_c.callado(nombre)):
                self.aviso(e, f"`{nombre}` se captura con `mut` y nunca se "
                              f"modifica; puede ir sin `mut`")

        e.tipo_struct = nombre_struct
        e.funcion = nombre_fn
        return nombre_struct

    def tipo_de_literal_generico(self, e: LiteralStruct, destino):
        """`Par { a: 7, b: nuevo("x") }` no dice sus tipos. Se sacan de donde
        va a parar, y si de ahi no salen, de lo que hay en los campos."""
        plantilla = self.structs_genericos[e.tipo]
        params = plantilla.tipo_params

        ap = aplicacion_generica(destino) if destino else None
        if destino and self.nombre_original.get(destino) == e.tipo:
            return destino          # ya viene resuelto de la anotacion
        if ap and ap[0] == e.tipo and len(ap[1]) == len(params):
            return self.instanciar_struct(e.tipo, ap[1], e)

        ligaduras = {}
        for nombre, valor in e.campos:
            definicion = next((c for c in plantilla.campos
                               if c.nombre == nombre), None)
            if definicion is None:
                continue
            concreto = self.tipo_probable(valor)
            if concreto == LITERAL:
                concreto = "usize"
            if concreto is not None and es_referencia(concreto):
                concreto = apuntado(concreto)
            unificar_tipo(definicion.tipo, concreto, params, ligaduras,
                          self.args_instancia)

        faltan = [t for t in params if t not in ligaduras]
        if faltan:
            self.error(e, f"no se puede deducir "
                          + ", ".join("`" + t + "`" for t in faltan)
                          + f" en `{e.tipo} {{ ... }}`: ni los campos ni el "
                          f"sitio donde va lo dicen. Escribe el tipo en la "
                          f"declaracion: `let x: {e.tipo}<...> = ...`")
            return None
        return self.instanciar_struct(e.tipo, [ligaduras[t] for t in params], e)

    def literal_struct(self, e: LiteralStruct, destino=None):
        if e.tipo in self.structs_genericos:
            resuelto = self.tipo_de_literal_generico(e, destino)
            if resuelto is None:
                for _, v in e.campos:
                    self.expresion(v)
                return None
            e.tipo = resuelto

        st = self.structs.get(e.tipo)
        if st is None:
            self.error(e, f"`{e.tipo}` no es un struct conocido")
            for _, v in e.campos:
                self.expresion(v)
            return None

        dados = {}
        for nombre, valor in e.campos:
            definicion = next((c for c in st.campos if c.nombre == nombre), None)
            t = self.expresion(valor, destino=(definicion.tipo
                                                if definicion is not None else None),
                               mover_variables=(
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
        # `[]` con un mapa esperado es el mapa vacio. No hay literal con
        # contenido: un mapa se llena con `poner`, que es donde se ve el coste.
        if esperado is not None and es_mapa(esperado):
            if e.elementos:
                self.error(e, "un mapa se llena con `poner`; el unico literal "
                              "que admite es `[]`")
            return esperado

        es_literal_lista = esperado is not None and es_lista(esperado)
        if not e.elementos and not es_literal_lista:
            if esperado is None:
                self.error(e, "`[]` vacio no dice si es una lista, un arreglo "
                              "o un mapa: escribe el tipo, como "
                              "`let xs: lista<usize> = [];`")
            else:
                self.error(e, "un arreglo tiene que tener al menos un elemento")
            return None

        elem_esperado = None
        if es_literal_lista:
            elem_esperado = elem_lista(esperado)
        elif esperado is not None and es_arreglo(esperado):
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
            return esperado if es_literal_lista else \
                f"[{elem_esperado}; {len(e.elementos)}]"

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
        if e.op in {"&&", "||"}:
            # C puede no evaluar el lado derecho. Hasta tener movimientos
            # sensibles al flujo, no se permite entregar propiedad ahi.
            self.en_condicional += 1
            td = self.expresion(e.der)
            self.en_condicional -= 1
        else:
            td = self.expresion(e.der)

        if e.op in {"&&", "||"}:
            for t, lado in ((ti, "izquierdo"), (td, "derecho")):
                if t is not None and t != "bool":
                    self.error(e, f"`{e.op}` necesita `bool`, el lado {lado} "
                                  f"es `{t}`")
            return "bool"

        if ti is None or td is None:
            return None

        # Un prestamo se lee como lo que presta: `a > b` con dos `&usize`
        # compara los numeros, no las direcciones.
        ti, td = sin_prestamo(ti), sin_prestamo(td)

        # Un numero escrito toma el tipo del otro lado.
        desplaza = e.op in {"<<", ">>"}
        if ti in (LITERAL, LITERAL_DECIMAL) and td in NUMERICOS:
            self.comprobar_literal(e.izq, td)
            self.fijar_literal(e.izq, td)
            ti = td
        elif td in (LITERAL, LITERAL_DECIMAL) and ti in NUMERICOS:
            self.comprobar_literal(e.der, ti)
            self.fijar_literal(e.der, "usize" if desplaza else ti)
            td = ti
        if ti == LITERAL and td == LITERAL_DECIMAL:
            self.fijar_literal(e.izq, LITERAL_DECIMAL)
            ti = td
        elif td == LITERAL and ti == LITERAL_DECIMAL:
            self.fijar_literal(e.der, LITERAL_DECIMAL)
            td = ti
        if desplaza and td in NUMERICOS:
            # Cuanto se desplaza llega siempre como `usize`.
            self.fijar_literal(e.der, "usize")

        if e.op in {"==", "!="}:
            if ti != td:
                self.error(e, f"no se pueden comparar `{ti}` y `{td}`")
            if ti == "str":
                self.error(e, "no se comparan `str` con `==`: usa "
                              "`igual(vista(a), vista(b))`")
            if ti in DECIMALES:
                # No se prohibe: comparar con `0.0` exacto a veces es lo que
                # se quiere. Pero casi nunca, y el aviso lo dice una vez.
                self.aviso(e, f"`{e.op}` entre decimales compara bit a bit: "
                              f"`0.1 + 0.2` no es `0.3`. Si querias "
                              f"'aproximadamente', usa `cerca(a, b, tolerancia)` "
                              f"de `std/numero`")
            return "bool"

        if e.op in {"<", "<=", ">", ">="}:
            if ti not in (LITERAL, LITERAL_DECIMAL) and (
                    ti not in NUMERICOS or td not in NUMERICOS):
                self.error(e, f"`{e.op}` necesita enteros, recibio `{ti}` y `{td}`")
            elif ti != td:
                self.error(e, f"`{ti}` y `{td}` no se mezclan sin conversion "
                              f"explicita")
            return "bool"

        if e.op in {"&", "|", "^", "<<", ">>"}:
            if ti == LITERAL and td == LITERAL:
                return LITERAL
            if ti not in ENTEROS or td not in ENTEROS:
                self.error(e, f"`{e.op}` trabaja sobre los bits de un entero, "
                              f"recibio `{ti}` y `{td}`")
                return None
            if e.op in {"<<", ">>"}:
                # Lo que se desplaza y cuanto se desplaza son cosas distintas:
                # `x << 3` no pide que el 3 sea del tipo de x.
                return ti
            if ti != td:
                self.error(e, f"`{ti}` y `{td}` no se mezclan sin conversion "
                              f"explicita")
            return ti

        # aritmetica
        if (e.op == "/?" and LITERAL_DECIMAL not in (ti, td)
                and ti not in DECIMALES and td not in DECIMALES):
            # Entre enteros no hay IEEE que pedir: dividir por cero o
            # `MIN / -1` no tienen un resultado al que volver.
            self.error(e, "`/?` es la division IEEE de los decimales; entre "
                          "enteros no hay vuelta que dar. Usa `/`, que se "
                          "detiene al dividir por cero")
            return None
        if ti in (LITERAL, LITERAL_DECIMAL) and td in (LITERAL, LITERAL_DECIMAL):
            return LITERAL_DECIMAL if LITERAL_DECIMAL in (ti, td) else LITERAL
        if e.op == "%" and (ti in DECIMALES or td in DECIMALES):
            self.error(e, "`%` es el resto de una division entera; con "
                          "decimales no tiene un significado unico")
            return None
        if ti not in NUMERICOS or td not in NUMERICOS:
            self.error(e, f"`{e.op}` necesita enteros, recibio `{ti}` y `{td}`")
            return None
        if ti != td:
            self.error(e, f"`{ti}` y `{td}` no se mezclan sin conversion explicita")
        return ti

    # ---------- internas ----------

    def llamada(self, e: Llamada, desenvuelta=False, destino=None):
        nombre = e.nombre

        if nombre in INTERNAS:
            if INTERNAS[nombre].get("falible") and not desenvuelta:
                self.error(e, f"`{nombre}` puede fallar: la llamada tiene que ir "
                              f"detras de `try`, o con `sino <valor>` para dar un "
                              f"valor cuando falle")
            return self.interna(e, destino)

        # Una variable que guarda una clausura se llama igual que una
        # funcion: por dentro es su struct mas la funcion que lo recibe.
        sim_cierre = self.buscar(nombre)
        if sim_cierre is not None and sin_prestamo(sim_cierre.tipo) in self.cierres:
            # El entorno se pasa como primer argumento, prestado. A partir de
            # ahi es una llamada normal y todo lo demas vale tal cual.
            tipo_c = sin_prestamo(sim_cierre.tipo)
            e.nombre = nombre = self.cierres[tipo_c]
            e.args = ([Variable(sim_cierre.nombre, linea=e.linea)]
                      + list(e.args))

        # Una variable que guarda una funcion se llama como cualquier otra.
        sim_valor = self.buscar(nombre)
        if sim_valor is not None and es_funcion(sim_valor.tipo):
            self.usar(e, sim_valor)
            params, retorno = partes_funcion(sim_valor.tipo)
            if len(e.args) != len(params):
                self.error(e, f"`{nombre}` es `{sim_valor.tipo}` y espera "
                              f"{len(params)} argumento(s), recibio "
                              f"{len(e.args)}")
            # Los prestamos de una misma llamada, como en una funcion con
            # nombre: la firma del puntero dice lo mismo que la de ella.
            prestamos = _Prestamos()
            for i, (arg, esperado_t) in enumerate(zip(e.args, params)):
                # Un `&X` en la firma presta: se le pasa el sitio, no el valor.
                presta = es_referencia(esperado_t)
                interno = apuntado(esperado_t) if presta else esperado_t
                t = self.expresion(arg, destino=interno,
                                   mover_variables=(not presta
                                                    and self.posee(interno)))
                cual = f"el argumento {i + 1}"
                if presta:
                    base = self.variable_base(arg)
                    sim_base = self.buscar(base) if base else None
                    if sim_base is not None:
                        mutable = es_referencia_mutable(esperado_t)
                        camino = self.camino_de(arg)
                        choque = prestamos.choque(camino, mutable)
                        if choque is not None:
                            self.error(e, f"`{choque[0]}` se presta dos veces en "
                                          f"la misma llamada a `{nombre}` "
                                          f"({choque[1]} y {cual}), y al menos uno "
                                          f"de los dos puede modificarlo")
                        prestamos.apuntar(camino, cual, mutable)
                        if mutable:
                            self.mutar(arg, sim_base)
                        else:
                            self.usar(arg, sim_base)
                elif self.presta(interno):
                    for camino in self._prestados_por(arg, t):
                        choque = prestamos.choque(camino, False)
                        if choque is not None:
                            self.error(e, f"`{choque[0]}` se presta dos veces en "
                                          f"la misma llamada a `{nombre}` "
                                          f"({choque[1]} y {cual}), y al menos "
                                          f"uno de los dos puede modificarlo")
                        prestamos.apuntar(camino, cual, False)
                if t is not None and not encaja(interno, sin_prestamo(t)):
                    if not (interno == "view" and sin_prestamo(t) == "str"):
                        self.error(e, f"`{nombre}` toma `{esperado_t}` ahi y "
                                      f"recibio `{t}`")
            return retorno

        if nombre in self.genericas:
            # Se elige la copia por los tipos que llegan, y a partir de aqui
            # la llamada es a una funcion normal como cualquier otra.
            resuelto = self.instanciar(e, self.genericas[nombre])
            if resuelto is None:
                for a in e.args:
                    self.expresion(a)
                return None
            e.nombre = nombre = resuelto

        f = self.funciones.get(nombre)
        if f is None:
            if nombre in self.genericas:
                return None
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

        # Prestar lo mismo dos veces en una llamada, con una de las dos
        # mutable, deja al callee con dos nombres para lo mismo: puede
        # modificar por uno y leer por el otro sin enterarse. Dos campos
        # distintos no son lo mismo: `g(p.a, p.b)` vale.
        prestamos = _Prestamos()

        for arg, param in zip(e.args, f.params):
            if param.prestado:
                marca = "mut" if param.mutable else "&"
                base = self.variable_base(arg)
                sim = self.buscar(base) if base else None
                if sim is None:
                    # Un valor recien hecho —`contar(palabras(t))`— tambien se
                    # puede prestar: vive hasta el final de la sentencia, que
                    # es mas que lo que dura la llamada. El generador lo guarda
                    # en un temporal y lo libera ahi.
                    t_arg = self.expresion(arg)
                    if t_arg is not None and not encaja(param.tipo, t_arg):
                        self.error(e, f"`{param.nombre}` de `{nombre}` es "
                                      f"`{param.tipo}` y recibio `{t_arg}`")
                    elif param.mutable:
                        self.error(e, f"`{param.nombre}` de `{nombre}` es "
                                      f"`mut`: modificar algo recien hecho no "
                                      f"le sirve a nadie, pasale una variable")
                    continue

                tipo_arg = self.tipo_de_lugar(arg)
                if tipo_arg is not None and tipo_arg != param.tipo:
                    self.error(e, f"`{param.nombre}` de `{nombre}` es "
                                  f"`{param.tipo}` y recibio `{tipo_arg}`")

                # Dos prestamos de lo mismo solo conviven si ninguno modifica.
                camino = self.camino_de(arg)
                choque = prestamos.choque(camino, param.mutable)
                if choque is not None:
                    a, b = sorted([param.nombre, choque[1]])
                    self.error(e, f"`{choque[0]}` se presta dos veces en la misma "
                                  f"llamada a `{nombre}` (como `{a}` y como "
                                  f"`{b}`), y al menos uno de los dos puede "
                                  f"modificarlo")
                prestamos.apuntar(camino, param.nombre, param.mutable)

                if param.mutable:
                    self.mutar(arg, sim)
                    # Prestar para modificar tambien es usar: quien lo recibe
                    # casi siempre lee antes de escribir, y avisar de que
                    # "nunca se lee" seria falso.
                    sim.leida = True
                else:
                    self.usar(arg, sim)
                continue

            # Una funcion de C recibe un `const char*`: mira la cadena, no
            # se la queda. Tcode se la presta y la sigue teniendo.
            mueve = self.posee(param.tipo) and not f.externa
            if mueve and isinstance(arg, Variable):
                sim_arg = self.buscar(arg.nombre)
                if sim_arg is not None:
                    sim_arg.movida_a = nombre
            t = self.expresion(arg, destino=param.tipo, mover_variables=mueve)

            # Una vista que se pasa tambien presta, aunque no tenga nombre:
            # `g(s, vista(s))` con `a: mut str` dejaria a `g` modificando por
            # un lado lo que lee por el otro, y al crecer el buffer la vista
            # quedaria colgando. Es el fallo 2 de la especificacion.
            if self.presta(param.tipo) and not f.externa:
                for camino in self._prestados_por(arg, t):
                    choque = prestamos.choque(camino, False)
                    if choque is not None:
                        a, b = sorted([param.nombre, choque[1]])
                        self.error(e, f"`{choque[0]}` se presta dos veces en la "
                                      f"misma llamada a `{nombre}` (como `{a}` "
                                      f"y como `{b}`), y al menos uno de los "
                                      f"dos puede modificarlo")
                    prestamos.apuntar(camino, param.nombre, False)

            # Donde se pide una vista, un `str` se lee prestandolo. Es la
            # misma regla que ya valia para las internas: escribir `vista(s)`
            # no aporta nada que el comprobador no sepa.
            if param.tipo == "view" and t == "str":
                # Tambien vale un `str` recien hecho: el generador lo guarda
                # en un temporal, que vive hasta el final de la sentencia.
                continue

            if t is not None and not encaja(param.tipo, t):
                if t in self.cierres and es_funcion(param.tipo):
                    self.error(e, f"`{param.nombre}` de `{nombre}` es "
                                  f"`{param.tipo}`, un puntero a funcion, y "
                                  f"recibio una clausura. Una clausura lleva "
                                  f"dentro lo que capturo, asi que no cabe en "
                                  f"un puntero: haz el parametro generico "
                                  f"(`{param.nombre}: F`) y valdra para las "
                                  f"dos")
                else:
                    self.error(e, f"`{param.nombre}` de `{nombre}` es "
                                  f"`{param.tipo}` y recibio `{t}`")

        return f.retorno if f.retorno is not None else UNIDAD

    def interna(self, e: Llamada, destino=None):
        nombre = e.nombre
        firma = INTERNAS[nombre]
        params, retorno = firma["params"], firma["retorno"]

        # Operaciones cuyo tipo depende de sus argumentos. Mantenerlas aqui,
        # explicitas, hace que el C generado siga sin casts implicitos.
        if nombre in ("igual", "menor"):
            if len(e.args) != 2:
                self.error(e, f"`{nombre}` espera 2 argumentos y recibio "
                              f"{len(e.args)}")
                for a in e.args:
                    self.expresion(a)
                return "bool"
            ta = sin_prestamo(self.expresion(e.args[0]) or "")
            tb = sin_prestamo(self.expresion(e.args[1]) or "")
            validos = IGUALABLES if nombre == "igual" else COMPARABLES
            # `str` y `view` son lo mismo para comparar: uno se presta al otro.
            def texto(t):
                return t in ("str", "view")
            for t in (ta, tb):
                if t and t != LITERAL and t not in validos:
                    self.error(e, f"`{nombre}` compara "
                                  f"{', '.join('`' + x + '`' for x in sorted(validos))}"
                                  f", y recibio `{t}`")
                    return "bool"
            if ta and tb and not (texto(ta) and texto(tb)):
                a = "usize" if ta == LITERAL else ta
                b = "usize" if tb == LITERAL else tb
                if a != b:
                    self.error(e, f"`{nombre}` compara dos valores del mismo "
                                  f"tipo, y recibio `{ta}` y `{tb}`")
            return "bool"

        if nombre in ("raiz", "piso", "techo", "redondear", "absoluto"):
            if len(e.args) != 1:
                self.error(e, f"`{nombre}` espera 1 argumento y recibio "
                              f"{len(e.args)}")
                for a in e.args:
                    self.expresion(a)
                return None
            t = sin_prestamo(self.expresion(e.args[0]) or "")
            if t == LITERAL_DECIMAL:
                return "f64"
            if nombre == "absoluto":
                if t == LITERAL:
                    return "i64"
                if t not in DECIMALES and t not in CON_SIGNO:
                    self.error(e, f"`absoluto` necesita un numero con signo, "
                                  f"recibio `{t}`")
                    return None
                return t
            if t == LITERAL:
                return "f64"
            if t not in DECIMALES:
                self.error(e, f"`{nombre}` trabaja sobre decimales, recibio "
                              f"`{t}`")
                return None
            return t

        if nombre == "reservar":
            if len(e.args) != 1:
                self.error(e, f"`reservar` espera 1 argumento (cuantos) y "
                              f"recibio {len(e.args)}")
                for a in e.args:
                    self.expresion(a)
                return None
            t = self.expresion(e.args[0])
            if t is not None and not encaja("usize", t):
                self.error(e, f"`reservar` espera cuantos elementos, un "
                              f"`usize`, y recibio `{t}`")
            if destino is None or not es_bloque(destino):
                self.error(e, "`reservar(n)` necesita saber de que: escribelo "
                              "en la declaracion, "
                              "`var b: bloque<str> = reservar(4);`")
                return None
            return destino

        if nombre == "redimensionar":
            if len(e.args) != 2:
                self.error(e, f"`redimensionar` espera 2 argumentos y recibio "
                              f"{len(e.args)}")
                for a in e.args:
                    self.expresion(a)
                return UNIDAD
            base = self.variable_base(e.args[0])
            sim = self.buscar(base) if base else None
            # El sitio puede ser un campo (`v.datos`), asi que el tipo sale
            # del lugar, no de la variable que lo contiene.
            t_sitio = sin_prestamo(self.tipo_de_lugar(e.args[0]) or "")
            if sim is None or not es_bloque(t_sitio):
                self.error(e, "`redimensionar` cambia el tamaño de un bloque, "
                              "y necesita un sitio que lo sea: una variable, "
                              "un campo o un elemento")
                self.expresion(e.args[1])
                return UNIDAD
            self.mutar(e.args[0], sim,
                       por_referencia=es_referencia(sim.tipo))
            marca = "redimensionar"
            sim.prestamos.append(marca)
            try:
                t = self.expresion(e.args[1])
            finally:
                sim.prestamos.remove(marca)
            if t is not None and not encaja("usize", t):
                self.error(e, f"`redimensionar` espera el tamaño nuevo, un "
                              f"`usize`, y recibio `{t}`")
            return UNIDAD

        if nombre == "intercambiar":
            if len(e.args) != 2:
                self.error(e, f"`intercambiar` espera 2 argumentos y recibio "
                              f"{len(e.args)}")
                for a in e.args:
                    self.expresion(a)
                return None
            destino_nodo, valor = e.args
            base = self.variable_base(destino_nodo)
            sim = self.buscar(base) if base else None
            if sim is None:
                self.error(e, "`intercambiar` necesita un sitio: una variable, "
                              "un campo o un elemento, no una expresion suelta")
                self.expresion(valor)
                return None
            t = self.tipo_de_lugar(destino_nodo)
            if t is not None and self.presta(t):
                self.error(e, f"`intercambiar` no cambia prestamos: `{t}` "
                              f"apunta a memoria de otro. Asigna con `=`")
            self.mutar(destino_nodo, sim,
                       por_referencia=es_referencia(sim.tipo))
            # El sitio queda reservado hasta que se haya calculado el valor
            # nuevo. De lo contrario `intercambiar(s, f(s))` podria mover y
            # liberar `s` antes de devolver el valor viejo.
            marca = "intercambiar"
            sim.prestamos.append(marca)
            try:
                tv = self.expresion(valor, destino=t,
                                    mover_variables=(t is not None
                                                     and self.posee(t)))
            finally:
                sim.prestamos.remove(marca)
            if t is not None and tv is not None and not encaja(t, tv):
                self.error(e, f"`intercambiar` pone y saca lo mismo: el sitio "
                              f"es `{t}` y el valor es `{tv}`")
            return t

        if nombre == "copiar":
            if len(e.args) != 1:
                self.error(e, f"`copiar` espera 1 argumento y recibio "
                              f"{len(e.args)}")
                for a in e.args:
                    self.expresion(a)
                return None
            # Copiar es leer, no mover: el original se queda donde estaba.
            t = self.expresion(e.args[0])
            if t is None:
                return None
            t = sin_prestamo(t)
            if t == "view":
                self.error(e, "una vista no es duenia de nada que copiar: si "
                              "quieres el texto, `nuevo(v)` te da un `str`")
                return "str"
            if t == LITERAL:
                return "usize"
            if not self.tipo_existe(t):
                self.error(e, f"`copiar` no sabe copiar un `{t}`")
                return t
            return t

        if nombre == "largo":
            if len(e.args) != 1:
                self.error(e, f"`largo` espera 1 argumento y recibio {len(e.args)}")
                for a in e.args:
                    self.expresion(a)
                return "usize"
            t = self.expresion(e.args[0])
            t = sin_prestamo(t) if t else t
            if t is not None and t != "view" and t != "str" \
                    and not es_arreglo(t) and not es_lista(t) \
                    and not es_mapa(t) and not es_bloque(t):
                self.error(e, f"`largo` opera sobre texto, arreglos, listas o "
                              f"mapas, recibio `{t}`")
            return "usize"

        if nombre == "anadir":
            if len(e.args) != 2:
                self.error(e, f"`anadir` espera 2 argumentos y recibio "
                              f"{len(e.args)}")
                for a in e.args:
                    self.expresion(a)
                return UNIDAD
            lugar, valor = e.args
            base = self.variable_base(lugar)
            sim = self.buscar(base) if base else None
            tipo_lista = self.tipo_de_lugar(lugar) if sim is not None else None
            if sim is None:
                self.error(e, "el primer argumento de `anadir` tiene que ser "
                              "una variable, un campo o un elemento")
            elif not es_lista(tipo_lista):
                self.error(e, f"`anadir` opera sobre `lista<T>`, recibio "
                              f"`{tipo_lista}`")
            else:
                # Evaluar el valor antes de registrar la mutacion detecta los
                # usos/movimientos y conserva el orden real de evaluacion.
                elem = elem_lista(tipo_lista)
                t = self.expresion(valor, destino=elem,
                                   mover_variables=self.posee(elem))
                if t is not None and not encaja(elem, t):
                    self.error(e, f"la lista guarda `{elem}` y se intento "
                                  f"agregar `{t}`")
                self.mutar(lugar, sim)
                return UNIDAD
            self.expresion(valor)
            return UNIDAD

        if nombre == "ordenar":
            if len(e.args) != 1:
                self.error(e, f"`ordenar` espera 1 argumento y recibio "
                              f"{len(e.args)}")
                for a in e.args:
                    self.expresion(a)
                return UNIDAD
            lugar = e.args[0]
            base = self.variable_base(lugar)
            sim = self.buscar(base) if base else None
            t = self.tipo_de_lugar(lugar) if sim is not None else None
            if sim is None:
                self.error(e, "`ordenar` necesita una variable, un campo o un "
                              "elemento")
            elif not es_lista(t):
                self.error(e, f"`ordenar` opera sobre `lista<T>`, recibio `{t}`")
            elif elem_lista(t) not in ORDENABLES:
                self.error(e, f"`{elem_lista(t)}` no tiene un orden natural; "
                              f"`ordenar` funciona sobre "
                              f"{', '.join('`' + x + '`' for x in sorted(ORDENABLES))}")
            else:
                self.mutar(lugar, sim)
            return UNIDAD

        if nombre in ("poner", "obtener", "obtener_mut", "tiene", "claves",
                      "quitar"):
            return self.interna_mapa(e, nombre)

        if nombre == "texto":
            if len(e.args) != 1:
                self.error(e, f"`texto` espera 1 argumento y recibio {len(e.args)}")
                for a in e.args:
                    self.expresion(a)
                return "str"
            t = sin_prestamo(self.expresion(e.args[0]) or "")
            if t and t not in ENTEROS | {LITERAL, "bool", "view", "str"}:
                self.error(e, f"`texto` convierte escalares o texto, recibio `{t}`")
            return "str"

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
                t_presta = self.tipo_de_lugar(arg)
                if es_referencia(t_presta):
                    t_presta = apuntado(t_presta)
                if t_presta != "str":
                    self.error(e, f"`{nombre}` presta de un `str`")
                    continue
                self.usar(arg, sim)
                prestados.append(base)
                continue

            t = self.expresion(arg)
            if (t is not None and esperado != "@cualquiera"
                    and not encaja(esperado, t)):
                # donde se pide una vista, un `str` se lee prestandolo
                if not (esperado == "view" and sin_prestamo(t or "") == "str"):
                    self.error(e, f"el argumento {i + 1} de `{nombre}` debe ser "
                                  f"`{esperado}` y es `{t}`")

            # Un `str` recien hecho tambien vale donde se pide una vista: el
            # generador lo guarda en un temporal que vive hasta el final de la
            # sentencia y lo libera ahi. Es la misma regla que ya valia para
            # las funciones de uno, y no tenerla aqui obligaba a escribir un
            # `let` que no decia nada: `imprimir(marco("x"))` es lo natural.

            if (esperado == "@cualquiera" and t is not None
                    and (es_arreglo(t) or t in self.structs)):
                self.error(e, f"`{nombre}` no sabe mostrar un `{t}`: muestra "
                              f"sus campos o elementos por separado")
            if esperado == "view":
                # Todos los duenios posibles, no el primero: con
                # `if c { vista(a) } else { vista(b) }` puede ser cualquiera.
                origenes = [o for o in self._origenes_de(arg) if o != TEMPORAL]
                if (not origenes and isinstance(arg, Variable)
                        and t == "str"):
                    origenes = [arg.nombre]
                prestados.extend(origenes)

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
            t_lugar = self.tipo_de_lugar(arg)
            # Un `&mut str` es un `str` al que se llega por puntero: para
            # `empujar` es lo mismo.
            if es_referencia(t_lugar):
                t_lugar = apuntado(t_lugar)
            if t_lugar != "str":
                self.error(e, f"`{nombre}` opera sobre `str`")
                continue
            if base in prestados:
                self.error(e, f"`{base}` se presta y se modifica en la misma "
                              f"llamada a `{nombre}`: al crecer, el buffer "
                              f"puede moverse y dejar la vista colgando")
                continue
            self.mutar(arg, sim,
                       por_referencia=(not isinstance(arg, Variable)
                                       or es_referencia(sim.tipo)))

        return retorno


# Firmas de las funciones internas.
#   @lugar      -> tiene que ser una variable (se muta o se presta)
#   @cualquiera -> cualquier tipo (imprimir)
INTERNAS = {
    "vacio":    {"params": [],                        "retorno": "str"},
    "nuevo":    {"params": ["view"],                  "retorno": "str"},
    "vista":    {"params": ["@presta"],               "retorno": "view"},
    "empujar":  {"params": ["@mut", "view"],          "retorno": UNIDAD},
    # Un byte crudo, no texto. Es lo que permite construir un buffer binario
    # y no solo leerlo.
    "empujar_byte": {"params": ["@mut", "u8"],        "retorno": UNIDAD},
    "largo":    {"params": ["@dimensionable"],        "retorno": "usize"},
    # El tipo sale de los argumentos, en `interna`: comparan cualquier par
    # de valores del mismo tipo sin partes.
    "igual":    {"params": ["@comparable", "@comparable"], "retorno": "bool"},
    "rebanar":  {"params": ["view", "usize", "usize"], "retorno": "view"},
    "imprimir": {"params": ["@cualquiera"],           "retorno": UNIDAD},
    "anadir":   {"params": ["@lista_mut", "@elemento"], "retorno": UNIDAD},
    "texto":    {"params": ["@escalar"],              "retorno": "str"},
    # Copia profunda. El tipo sale del argumento, en `interna`.
    "copiar":   {"params": ["@copiable"],             "retorno": None},
    # Saca lo que hay en un sitio dejando otro valor en su lugar. Es lo que
    # permite mover algo fuera de una lista sin dejar un hueco sin duenio.
    "intercambiar": {"params": ["@lugar_mut", "@valor_igual"], "retorno": None},
    # Memoria cruda, pero no insegura: un bloque nace a ceros, y en Tcode
    # todo tipo puesto a ceros es un valor valido y vacio. Eso es lo que
    # permite escribir una lista en Tcode sin ranuras sin inicializar.
    "reservar": {"params": ["usize"],                 "retorno": None},
    "redimensionar": {"params": ["@bloque_mut", "usize"], "retorno": UNIDAD},
    # Decimales. Devuelven lo mismo que reciben; `raiz` de un negativo daria
    # NaN, y eso detiene el programa como cualquier otro NaN.
    "raiz":     {"params": ["@decimal"],              "retorno": None},
    "piso":     {"params": ["@decimal"],              "retorno": None},
    "techo":    {"params": ["@decimal"],              "retorno": None},
    "redondear": {"params": ["@decimal"],             "retorno": None},
    "absoluto": {"params": ["@con_signo"],            "retorno": None},
    "byte":     {"params": ["view", "usize"],         "retorno": "usize"},
    "n_argumentos": {"params": [],                    "retorno": "usize"},
    "argumento":    {"params": ["usize"],             "retorno": "view"},
    "leer_archivo": {"params": ["view"], "retorno": "str", "falible": True},
    "escribir_archivo": {"params": ["view", "view"], "retorno": UNIDAD,
                         "falible": True},
    "imprimir_error": {"params": ["@cualquiera"],     "retorno": UNIDAD},
    # ---- el sistema ----
    #
    # Lo que no puede pasar por `externo` porque tiene que respetar la
    # propiedad: lo que devuelven es un `str` de Tcode, con su liberacion.
    #
    # Una linea de la entrada, sin el salto. Crece lo que haga falta: no hay
    # limite ni recorte silencioso como el `bufio.Scanner` de Go, que a los
    # 64 KB deja de leer y no lo dice. El fin de la entrada es un fallo, no
    # una cadena vacia, para que no se confunda con una linea en blanco.
    "leer_linea": {"params": [], "retorno": "str", "falible": True},
    "entrada_completa": {"params": [], "retorno": "str", "falible": True},
    # `getenv` no distingue "no esta" de "esta vacia"; esto si, porque una
    # cosa es un fallo y la otra un valor.
    "variable_entorno": {"params": ["view"], "retorno": "str",
                         "falible": True},
    # Dos relojes, con el nombre diciendo cual es cual. Medir una duracion
    # con el de pared es el error clasico —salta con el NTP— y el `clock()`
    # de C mide tiempo de CPU aunque todo el mundo lo use para lo otro.
    "ahora_ms":    {"params": [],                     "retorno": "i64"},
    "monotono_ms": {"params": [],                     "retorno": "i64"},
    # Azar sin el sesgo de `rand() % n`, y con semilla para poder repetir.
    "azar":     {"params": ["usize"],                 "retorno": "usize"},
    "sembrar":  {"params": ["u64"],                   "retorno": UNIDAD},
    "menor":    {"params": ["@comparable", "@comparable"], "retorno": "bool"},
    "ordenar":  {"params": ["@lista_mut"],            "retorno": UNIDAD},
    # Mapas. El tipo concreto sale de `interna_mapa`, que mira el mapa real.
    "poner":    {"params": ["@mapa_mut", "@clave", "@valor"], "retorno": UNIDAD},
    "obtener":  {"params": ["@mapa", "@clave"], "retorno": None, "falible": True},
    "tiene":    {"params": ["@mapa", "@clave"],       "retorno": "bool"},
    "claves":   {"params": ["@mapa"],                 "retorno": None},
    "quitar":   {"params": ["@mapa_mut", "@clave"],   "retorno": "bool"},
    "obtener_mut": {"params": ["@mapa_mut", "@clave"], "retorno": None,
                    "falible": True},
}


def comprobar(funciones, archivo="<entrada>", nombres_bonitos=None):
    c = Comprobador(archivo)
    if nombres_bonitos:
        # El cargador renombro lo que chocaba entre modulos. Los mensajes
        # hablan del nombre que se escribio, no del que se invento.
        c.nombre_original.update(nombres_bonitos)
    return c.comprobar_programa(funciones), c
