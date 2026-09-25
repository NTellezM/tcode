"""
El oraculo de la aritmetica: programas con lo que tienen que imprimir al lado.

Los demas tests por propiedad comprueban que un programa compila, que corre
limpio bajo los sanitizers y que el C sale siempre igual. Ninguno mira si el
numero que imprime es el bueno, y por eso `1 + x`, con `x: f64 = 2.5`,
imprimio `3` con toda la suite en verde.

Aqui cada programa lleva su salida calculada aparte, en Python, con las
reglas de la especificacion y no con las del compilador:

  - un numero escrito toma el tipo del otro lado de la operacion; si los
    dos lados lo son, el que se espera de la expresion; sin nada que lo
    decida, `usize`, o `f64` si alguno lleva punto, o `i64` con `-` delante;
  - `+`, `-` y `*` sobre enteros paran al desbordar; `/` y `%` paran al
    dividir por cero, y `MIN / -1` por desbordamiento; `MIN % -1` es 0;
  - `+?`, `-?` y `*?` dan la vuelta modulo 2^N;
  - los bits de un entero con signo son los de su complemento a dos; `>>`
    de un negativo rellena con unos; desplazar el ancho o mas para;
  - un decimal que deja de ser un numero para, salvo con `+?`, `-?`, `*?` o
    `/?`, que dan el IEEE de siempre; `absoluto` de un infinito tambien para;
  - `como` para si el valor no cabe exacto; `como?` entre enteros se queda
    con los bits de abajo, y hacia un decimal redondea;
  - todo se evalua de izquierda a derecha, y para la primera operacion que
    falla.

Cada sentencia imprime una linea. A veces la ultima tiene que parar: entonces
se espera la salida hasta ahi y el mensaje con su linea.
"""

import math
import random
import struct

ENTEROS = {
    "i8": (True, 8), "i16": (True, 16), "i32": (True, 32), "i64": (True, 64),
    "u8": (False, 8), "u16": (False, 16), "u32": (False, 32),
    "u64": (False, 64), "usize": (False, 64),
}
# Los bits de mantisa de cada decimal, contando el implicito.
DECIMALES = {"f32": 24, "f64": 53}
NUMERICOS = list(ENTEROS) + list(DECIMALES)

# Decimales que se escriben igual en Tcode y en Python sin redondear dos
# veces: todos son exactos en un `double`, asi que el `f32` sale de una sola
# vuelta, igual que en C.
DECIMALES_F32 = ["0.0", "1.0", "2.5", "-0.75", "0.125", "1024.0", "-3.5",
                 "65536.0", "1.5e10", "3.4028235e38", "-100.25", "7.0"]
DECIMALES_F64 = ["0.0", "1.0", "-2.5", "0.1", "1e308", "-1e-300", "3.75",
                 "123456.789", "1.7976931348623157e308", "-0.5", "1e15"]
# Los de dentro de una cuenta de numeros escritos: pequeños y exactos.
DECIMALES_SUELTOS = ["0.5", "1.25", "2.0", "3.75", "0.125", "10.5", "100.0",
                     "1e3", "2.5e2"]


class Para(Exception):
    """El programa se detiene. `mensaje` es lo que escribe despues de
    `archivo:linea: `; `sitio` dice en que funcion auxiliar, si no es en la
    sentencia misma."""

    def __init__(self, mensaje, sitio=None):
        super().__init__(mensaje)
        self.sitio = sitio


class Descartar(Exception):
    """La sentencia daria algo que no se puede comparar de forma portable,
    como un NaN, que C escribe `nan` o `-nan` segun su signo."""


# ---------- los numeros ----------

def rango(t):
    con_signo, bits = ENTEROS[t]
    if con_signo:
        return -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    return 0, (1 << bits) - 1


def envolver(v, t):
    con_signo, bits = ENTEROS[t]
    v &= (1 << bits) - 1
    if con_signo and v >> (bits - 1):
        v -= 1 << bits
    return v


def a_f32(x):
    """El `float` mas cercano, con infinito si no cabe: lo que hace C."""
    if math.isnan(x) or math.isinf(x):
        return x
    try:
        return struct.unpack("f", struct.pack("f", x))[0]
    except OverflowError:
        return math.copysign(math.inf, x)


def redondear(x, t):
    return a_f32(x) if t == "f32" else x


def entero_a_decimal(v, t):
    """Redondeado una sola vez, al par, como la conversion de C."""
    if t == "f64":
        return float(v)
    magnitud = abs(v)
    bits = magnitud.bit_length()
    if bits <= 24:
        return float(v)
    sobra = bits - 24
    q, resto = divmod(magnitud, 1 << sobra)
    mitad = 1 << (sobra - 1)
    if resto > mitad or (resto == mitad and q & 1):
        q += 1
    return a_f32(math.copysign(float(q << sobra), v))


def cabe_exacto(v, t):
    """Si un entero pasa a decimal sin perder nada."""
    magnitud = abs(v)
    sobra = magnitud.bit_length() - DECIMALES[t]
    return sobra <= 0 or magnitud & ((1 << sobra) - 1) == 0


def texto_de(v, t):
    if t == "bool":
        return "true" if v else "false"
    if t in DECIMALES:
        if math.isnan(v):
            raise Descartar()
        s = "%g" % v
        if not any(c in s for c in ".eni"):
            s += ".0"
        return s
    return str(v)


def dividir_ieee(a, b):
    if b == 0:
        if a == 0 or math.isnan(a):
            return math.nan
        return math.copysign(math.inf, a) * math.copysign(1.0, b)
    return a / b


def operar(op, a, b, t, sitio=None):
    try:
        return _operar(op, a, b, t)
    except Para as p:
        raise Para(str(p), sitio) from None


def _operar(op, a, b, t):
    if op in ("==", "!=", "<", "<=", ">", ">="):
        return {"==": a == b, "!=": a != b, "<": a < b, "<=": a <= b,
                ">": a > b, ">=": a >= b}[op]
    if t in DECIMALES:
        base = op[0]
        if base == "/":
            r = dividir_ieee(a, b)
        else:
            r = {"+": a + b, "-": a - b, "*": a * b}[base]
        r = redondear(r, t)
        if not op.endswith("?") and not math.isfinite(r):
            raise Para(f"`{op}` no dio un numero (NaN o infinito). "
                       f"Si lo querias, escribe `{op}?`.")
        return r

    con_signo, bits = ENTEROS[t]
    lo, hi = rango(t)
    if op in ("+", "-", "*"):
        r = {"+": a + b, "-": a - b, "*": a * b}[op]
        if not lo <= r <= hi:
            raise Para(f"desbordamiento en `{op}`")
        return r
    if op in ("+?", "-?", "*?"):
        return envolver({"+": a + b, "-": a - b, "*": a * b}[op[0]], t)
    if op in ("/", "%"):
        if b == 0:
            raise Para("division por cero")
        if con_signo and a == lo and b == -1:
            if op == "/":
                raise Para("desbordamiento en `/`")
            return 0
        # C trunca hacia cero; Python redondea hacia abajo.
        q = abs(a) // abs(b)
        if (a < 0) != (b < 0):
            q = -q
        return q if op == "/" else a - b * q
    if op in ("&", "|", "^"):
        return envolver({"&": a & b, "|": a | b, "^": a ^ b}[op], t)
    if op in ("<<", ">>"):
        # Cuanto se desplaza llega como `size_t`.
        n = b & ((1 << 64) - 1)
        if n >= bits:
            raise Para(f"desbordamiento en `{op}`")
        if op == "<<":
            return envolver(a << n, t)
        return a >> n
    raise AssertionError(op)


def negar(a, t):
    if t in DECIMALES:
        return -a
    lo, _ = rango(t)
    if a == lo:
        raise Para("desbordamiento en `-`")
    return -a


def convertir(v, origen, destino, envolviendo):
    no_cabe = Para(f"el valor no cabe en `{destino}` viniendo de `{origen}`")
    if origen in ENTEROS and destino in ENTEROS:
        if envolviendo:
            return envolver(v, destino)
        lo, hi = rango(destino)
        if not lo <= v <= hi:
            raise no_cabe
        return v
    if origen in ENTEROS:
        if not envolviendo and not cabe_exacto(v, destino):
            raise no_cabe
        return entero_a_decimal(v, destino)
    if destino in ENTEROS:
        lo, hi = rango(destino)
        if not math.isfinite(v) or v != math.floor(v) or not lo <= v <= hi:
            raise no_cabe
        return int(v)
    if origen == "f32":
        return v
    # De `f64` a `f32`.
    if envolviendo:
        return a_f32(v)
    if not math.isfinite(v) or abs(v) > a_f32(3.4028235e38):
        raise no_cabe
    r = a_f32(v)
    if r != v:
        raise no_cabe
    return r


# ---------- las expresiones ----------

class Nodo:
    """Una expresion: como se escribe, en que tipo se calcula y cuanto da.

    `calcular` evalua a los hijos de izquierda a derecha y despues la
    operacion; lanza `Para` si algo detiene el programa."""

    def __init__(self, texto, tipo, calcular, literal=False):
        self.texto = texto
        self.tipo = tipo
        self.calcular = calcular
        self.literal = literal


def binaria(op, izq, der, t):
    def calcular():
        a = izq.calcular()
        b = der.calcular()
        return operar(op, a, b, t)
    tipo = "bool" if op in ("==", "!=", "<", "<=", ">", ">=") else t
    return Nodo(f"({izq.texto} {op} {der.texto})", tipo, calcular,
                literal=izq.literal and der.literal)


# Lo que se declara fuera de `main`, igual en todos los programas: una
# funcion que devuelve lo que recibe, una que suma dentro (y para en su
# propia linea), un struct con un campo, y una generica.
def _preludio():
    lineas, sitios = [], {}
    for t in NUMERICOS:
        lineas.append(f"struct Caja_{t} {{ v: {t} }}")
        lineas.append(f"fn pasa_{t}(x: {t}) -> {t} {{ return x; }}")
        lineas.append(f"fn suma_{t}(a: {t}, b: {t}) -> {t} {{ return a + b; }}")
        sitios[f"suma_{t}"] = len(lineas)
    lineas.append("fn mismo<T>(x: T) -> T { return x; }")
    return lineas, sitios


PRELUDIO, SITIOS_PRELUDIO = _preludio()


class Oraculo:
    def __init__(self, semilla):
        self.r = random.Random(semilla)
        self.variables = {}
        self.declaraciones = []
        self.funciones = []
        self.cajas = {}
        self.arreglos = {}
        self.resultados = 0

    # ----- hojas -----

    def valor_inicial(self, t):
        if t in DECIMALES:
            texto = self.r.choice(DECIMALES_F32 if t == "f32" else DECIMALES_F64)
            return redondear(float(texto), t), texto
        lo, hi = rango(t)
        candidatos = [0, 1, 2, 3, 7, 100, hi, hi - 1, hi // 2,
                      self.r.randint(0, min(hi, 1000)), self.r.randint(0, hi)]
        if lo < 0:
            candidatos += [-1, -2, lo, lo + 1, -self.r.randint(1, 1000) // 1,
                           self.r.randint(lo, hi)]
        v = max(lo, min(hi, self.r.choice(candidatos)))
        return v, str(v)

    def variable(self, t):
        existentes = self.variables.setdefault(t, [])
        if existentes and (len(existentes) >= 4 or self.r.random() < 0.6):
            nombre, valor = self.r.choice(existentes)
        else:
            valor, texto = self.valor_inicial(t)
            nombre = f"{t}_{len(existentes)}"
            self.declaraciones.append(f"let {nombre}: {t} = {texto};")
            existentes.append((nombre, valor))
        return Nodo(nombre, t, lambda v=valor: v)

    def sin_parar(self, t):
        """Una expresion que se puede poner en una declaracion: no para."""
        for _ in range(6):
            e = self.expresion(t, anclada=False, prof=2)
            try:
                valor = e.calcular()
                texto_de(valor, t)
                return e, valor
            except (Para, Descartar):
                continue
        e = self.numero_escrito(t)
        return e, e.calcular()

    def caja(self, t):
        existentes = self.cajas.setdefault(t, [])
        if existentes and (len(existentes) >= 2 or self.r.random() < 0.6):
            nombre, valor = self.r.choice(existentes)
        else:
            # El valor primero: puede declarar otras cajas del mismo tipo.
            e, valor = self.sin_parar(t)
            nombre = f"caja_{t}_{len(existentes)}"
            self.declaraciones.append(f"let {nombre} = Caja_{t} {{ v: {e.texto} }};")
            existentes.append((nombre, valor))
        return Nodo(f"{nombre}.v", t, lambda v=valor: v)

    def elemento(self, t):
        existentes = self.arreglos.setdefault(t, [])
        if existentes and (len(existentes) >= 2 or self.r.random() < 0.6):
            nombre, valores = self.r.choice(existentes)
        else:
            partes = [self.sin_parar(t) for _ in range(3)]
            nombre = f"arr_{t}_{len(existentes)}"
            valores = [v for _, v in partes]
            textos = ", ".join(e.texto for e, _ in partes)
            self.declaraciones.append(f"let {nombre}: [{t}; 3] = [{textos}];")
            existentes.append((nombre, valores))
        i = self.r.randint(0, 2)
        return Nodo(f"{nombre}[{i}]", t, lambda v=valores[i]: v)

    def numero_escrito(self, t):
        """Un numero escrito que cabe en `t`, calculado en `t`."""
        if t in DECIMALES:
            if self.r.random() < 0.3:
                n = self.r.randint(0, 20)
                return Nodo(str(n), t, lambda v=float(n): v, literal=True)
            texto = self.r.choice(DECIMALES_SUELTOS)
            return Nodo(texto, t, lambda v=redondear(float(texto), t): v,
                        literal=True)
        _, hi = rango(t)
        v = self.r.choice([0, 1, 2, 3, 5, 10, 16, 100, 127,
                           self.r.randint(0, 50), min(hi, 255), hi, hi // 2])
        v = min(v, hi)
        return Nodo(str(v), t, lambda v=v: v, literal=True)

    def cuenta_escrita(self, t, prof=0):
        """Una expresion solo de numeros escritos, calculada en `t`."""
        if prof >= 2 or self.r.random() < 0.5:
            return self.numero_escrito(t)
        if t in DECIMALES:
            op = self.r.choice(["+", "-", "*", "/", "+?", "*?"])
        else:
            op = self.r.choice(["+", "-", "*", "/", "%", "+?", "-?", "*?",
                                "&", "|", "^"])
        return binaria(op, self.cuenta_escrita(t, prof + 1),
                       self.cuenta_escrita(t, prof + 1), t)

    # ----- expresiones con tipo -----

    def expresion(self, t, anclada=True, prof=0):
        """Una expresion de tipo `t`. Si no esta `anclada`, puede ser solo
        de numeros escritos: entonces toma el tipo de lo que tiene al lado."""
        if not anclada and self.r.random() < 0.35:
            return self.cuenta_escrita(t)
        opciones = ["variable"] * 3
        if prof < 3:
            opciones += ["aritmetica"] * 4 + ["conversion"] * 2
            if t in ENTEROS:
                opciones += ["bits", "desplazamiento", "complemento"]
            if t in DECIMALES or ENTEROS[t][0]:
                opciones += ["negacion"]
            if t == "i64":
                opciones += ["negativo_escrito"]
            opciones += ["si", "pasa", "suma", "generica", "campo", "indice",
                         "retorno"]
            if t in DECIMALES or ENTEROS[t][0]:
                opciones += ["absoluto"]
        cual = self.r.choice(opciones)

        if cual == "campo":
            return self.caja(t)
        if cual == "indice":
            return self.elemento(t)

        if cual == "si":
            s = self.r.choice(NUMERICOS)
            op = self.r.choice(["<", "<=", ">", ">="] if s in DECIMALES
                               else ["==", "!=", "<", ">"])
            cond = binaria(op, self.expresion(s, True, prof + 1),
                           self.expresion(s, False, prof + 1), s)
            if self.r.random() < 0.5:
                a, b = self.expresion(t, True, prof + 1), self.expresion(t, False, prof + 1)
            else:
                a, b = self.expresion(t, False, prof + 1), self.expresion(t, True, prof + 1)
            def calcular():
                return a.calcular() if cond.calcular() else b.calcular()
            return Nodo(f"(if {cond.texto} {{ {a.texto} }} else {{ {b.texto} }})",
                        t, calcular)

        if cual == "pasa":
            x = self.expresion(t, False, prof + 1)
            return Nodo(f"pasa_{t}({x.texto})", t, x.calcular)

        if cual == "suma":
            a = self.expresion(t, False, prof + 1)
            b = self.expresion(t, False, prof + 1)
            def calcular():
                va = a.calcular()
                vb = b.calcular()
                return operar("+", va, vb, t, sitio=f"suma_{t}")
            return Nodo(f"suma_{t}({a.texto}, {b.texto})", t, calcular)

        if cual == "generica":
            x = self.expresion(t, True, prof + 1)
            return Nodo(f"mismo({x.texto})", t, x.calcular)

        if cual == "retorno":
            # Una funcion que devuelve una cuenta de numeros escritos: toma el
            # tipo que la funcion promete.
            x = self.cuenta_escrita(t)
            nombre = f"k{len(self.funciones) + 1}"
            self.funciones.append(f"fn {nombre}() -> {t} {{ return {x.texto}; }}")
            def calcular():
                try:
                    return x.calcular()
                except Para as p:
                    raise Para(str(p), nombre) from None
            return Nodo(f"{nombre}()", t, calcular)

        if cual == "absoluto":
            x = self.expresion(t, True, prof + 1)
            def calcular():
                v = x.calcular()
                if t in ENTEROS and v == rango(t)[0]:
                    raise Para("desbordamiento en `absoluto`")
                if t in DECIMALES and not math.isfinite(v):
                    raise Para("`absoluto` no dio un numero (NaN o infinito). "
                               "Comprueba el valor antes de operar con el.")
                return abs(v)
            return Nodo(f"absoluto({x.texto})", t, calcular)

        if cual == "variable":
            return self.variable(t)

        if cual in ("aritmetica", "bits"):
            if cual == "bits":
                op = self.r.choice(["&", "|", "^"])
            elif t in DECIMALES:
                op = self.r.choice(["+", "-", "*", "/", "+?", "-?", "*?", "/?"])
            else:
                op = self.r.choice(["+", "-", "*", "/", "%", "+?", "-?", "*?"])
            if self.r.random() < 0.5:
                izq = self.expresion(t, True, prof + 1)
                der = self.expresion(t, False, prof + 1)
            else:
                izq = self.expresion(t, False, prof + 1)
                der = self.expresion(t, True, prof + 1)
            return binaria(op, izq, der, t)

        if cual == "desplazamiento":
            op = self.r.choice(["<<", ">>"])
            izq = self.expresion(t, True, prof + 1)
            _, bits = ENTEROS[t]
            _, hi = rango(t)
            if self.r.random() < 0.6:
                # Un numero escrito toma el tipo de lo desplazado: tiene que
                # caber en el.
                n = min(self.r.choice([0, 1, 3, bits - 1, bits, bits + 1]), hi)
                der = Nodo(str(n), t, lambda n=n: n, literal=True)
            else:
                der = self.variable(self.r.choice(list(ENTEROS)))
            return binaria(op, izq, der, t)

        if cual == "complemento":
            x = self.expresion(t, True, prof + 1)
            return Nodo(f"~{x.texto}", t,
                        lambda: envolver(~x.calcular(), t))

        if cual == "negacion":
            x = self.expresion(t, True, prof + 1)
            return Nodo(f"-{x.texto}" if x.texto.startswith("(") else f"-({x.texto})",
                        t, lambda: negar(x.calcular(), t))

        if cual == "negativo_escrito":
            # `-5` o `-(2 + 3)` sin nada al lado que lo decida es un `i64`.
            x = self.cuenta_escrita("i64")
            texto = f"-{x.texto}" if x.texto.startswith("(") else f"-{x.texto}"
            return Nodo(texto, "i64", lambda: negar(x.calcular(), "i64"))

        # Conversion: de otro tipo, o de un numero escrito con el suyo, que
        # sin nada al lado es un `usize`, o un `i64` con `-` delante.
        envolviendo = self.r.random() < 0.3
        origen = self.r.choice([u for u in NUMERICOS if u != t])
        if self.r.random() < 0.2 and t not in ("usize", "i64"):
            n = self.r.choice([0, 1, 200, 300, 70000, 5000000000])
            if self.r.random() < 0.3:
                x = Nodo(f"-{n}", "i64", lambda n=n: -n)
                origen = "i64"
            else:
                x = Nodo(str(n), "usize", lambda n=n: n)
                origen = "usize"
        else:
            x = self.expresion(origen, True, prof + 1)
        if origen in DECIMALES and t in ENTEROS:
            envolviendo = False
        palabra = "como?" if envolviendo else "como"
        fuente = x.texto if x.texto[0] == "(" or x.texto[0].isalnum() else f"({x.texto})"
        return Nodo(f"({fuente} {palabra} {t})", t,
                    lambda: convertir(x.calcular(), origen, t, envolviendo))

    # ----- sentencias -----

    def sentencia(self):
        """(texto, lo que imprime) o (texto, Para)."""
        t = self.r.choice(NUMERICOS)
        forma = self.r.choice(["hueco", "hueco", "imprimir", "let", "let",
                               "compara", "suelta", "negativa", "asigna"])
        if forma == "asigna":
            # Lo que se asigna a una variable toma su tipo.
            inicial = self.expresion(t, anclada=False)
            otra = self.expresion(t, anclada=False)
            op = self.r.choice(["+", "-", "*", "+?", "-?", "*?"])
            self.resultados += 1
            nombre = f"m{self.resultados}"
            texto = (f"var {nombre}: {t} = {inicial.texto}; "
                     f"{nombre} = ({nombre} {op} {otra.texto}); "
                     f'imprimir($"{{{nombre}}}\\n");')
            def calcular():
                v0 = inicial.calcular()
                return operar(op, v0, otra.calcular(), t)
            e = Nodo(nombre, t, calcular)
        elif forma == "compara":
            op = self.r.choice(["<", "<=", ">", ">="] if t in DECIMALES
                               else ["==", "!=", "<", "<=", ">", ">="])
            if self.r.random() < 0.5:
                e = binaria(op, self.expresion(t, True), self.expresion(t, False), t)
            else:
                e = binaria(op, self.expresion(t, False), self.expresion(t, True), t)
            texto = f'imprimir($"{{{e.texto}}}\\n");'
        elif forma == "suelta":
            # Solo numeros escritos, sin nada que decida su tipo.
            t = self.r.choice(["usize", "f64"])
            e = self.cuenta_escrita(t)
            if t == "f64" and all(c not in e.texto for c in ".e"):
                # Sin un solo punto, los numeros escritos son enteros.
                raise Descartar()
            texto = f'imprimir($"{{{e.texto}}}\\n");'
        elif forma == "negativa":
            # `-(...)` de numeros escritos, con el tipo del destino.
            t = self.r.choice(["i8", "i16", "i32", "i64", "f32", "f64"])
            x = self.cuenta_escrita(t)
            e = Nodo(f"-{x.texto}" if x.texto.startswith("(") else f"-{x.texto}",
                     t, lambda: negar(x.calcular(), t))
            self.resultados += 1
            nombre = f"r{self.resultados}"
            texto = f'let {nombre}: {t} = {e.texto}; imprimir($"{{{nombre}}}\\n");'
        elif forma == "let":
            e = self.expresion(t, anclada=False)
            self.resultados += 1
            nombre = f"r{self.resultados}"
            texto = f'let {nombre}: {t} = {e.texto}; imprimir($"{{{nombre}}}\\n");'
        elif forma == "imprimir":
            e = self.expresion(t, True)
            texto = f'imprimir({e.texto}); imprimir("\\n");'
        else:
            e = self.expresion(t, True)
            texto = f'imprimir($"{{{e.texto}}}\\n");'
        try:
            valor = e.calcular()
        except Para as p:
            return texto, p
        return texto, texto_de(valor, e.tipo) + "\n"

    def programa(self, cuantas=None):
        """(fuente, salida esperada, (linea, mensaje) o None)."""
        cuantas = cuantas or self.r.randint(8, 20)
        sentencias, salida, parada = [], [], None
        intentos = 0
        while len(sentencias) < cuantas and intentos < cuantas * 20:
            intentos += 1
            try:
                texto, esperado = self.sentencia()
            except Descartar:
                continue
            if isinstance(esperado, Para):
                # Parar solo puede ser lo ultimo.
                if len(sentencias) >= cuantas // 2 and self.r.random() < 0.3:
                    sentencias.append(texto)
                    parada = esperado
                    break
                continue
            sentencias.append(texto)
            salida.append(esperado)
        lineas = list(PRELUDIO)
        sitios = dict(SITIOS_PRELUDIO)
        for f in self.funciones:
            lineas.append(f)
            sitios[f.split()[1].split("(")[0]] = len(lineas)
        lineas.append("fn main() {")
        lineas += ["    " + d for d in self.declaraciones]
        primera = len(lineas) + 1
        lineas += ["    " + s for s in sentencias]
        lineas.append("}")
        fuente = "\n".join(lineas) + "\n"
        donde = None
        if parada is not None:
            linea = (sitios[parada.sitio] if parada.sitio
                     else primera + len(sentencias) - 1)
            donde = (linea, str(parada))
        return fuente, "".join(salida), donde


def generar(semilla, cuantas=None):
    return Oraculo(semilla).programa(cuantas)


if __name__ == "__main__":
    import sys
    fuente, salida, parada = generar(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
    print(fuente)
    print("--- salida esperada ---")
    print(salida, end="")
    if parada:
        print(f"--- para en la linea {parada[0]}: {parada[1]}")
