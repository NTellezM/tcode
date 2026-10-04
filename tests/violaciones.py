"""
Programas que toman una vista, invalidan a su duenio y la usan despues.

Es la forma de todo uso tras liberar: una vista apunta a memoria de otro, y
ese otro se reasigna, crece, se mueve o se libera mientras la vista vive. El
generador de `generador_programas.py` produce programas validos por
construccion, asi que nunca prueba esto; aqui se prueba a proposito, con cada
forma que el lenguaje tiene de fabricar o transportar una vista.

Cada caso da dos programas:

  - el malo, donde la vista sigue viva al invalidar al duenio: el
    compilador tiene que rechazarlo;
  - el bueno, donde la vista muere en un bloque antes: tiene que compilar y
    correr limpio bajo AddressSanitizer.

Los textos son largos a proposito: una cadena corta cabe en la capacidad que
ya tenia el buffer, `empujar` no lo mueve, y un uso tras liberar pasaria
desapercibido incluso para ASan.
"""

LARGO = '"' + "x" * 40 + '"'
OTRO = '"' + "y" * 60 + '"'

# Lo que se declara fuera de `main` para que cada forma exista.
PRELUDIO = f"""enum E {{ A(str), B }}
enum K {{ Uno, Dos }}
struct Palabra {{ t: view }}
struct Caja {{ p: Palabra }}
fn primero(v: view) -> view {{ return v; }}
fn id<T>(x: T) -> T {{ return x; }}
fn crecer(x: mut str) {{ empujar(x, {OTRO}); }}
fn consumir(x: str) -> usize {{ return largo(x); }}
fn sin_vista() -> view ! {{ fail "no"; }}
fn g(a: mut str, b: view) {{ empujar(a, {OTRO}); imprimir(byte(b, 0)); }}
fn palabra(t: view) -> Palabra {{ return Palabra {{ t: t }}; }}
fn eco(p: Palabra) -> Palabra {{ return p; }}
fn caja(t: view) -> Caja {{ return Caja {{ p: Palabra {{ t: t }} }}; }}
fn hp(a: mut str, b: Palabra) {{ empujar(a, {OTRO}); imprimir(byte(b.t, 0)); }}
"""

# Como se invalida al duenio `s` (o `e`, o `m`).
INVALIDAN_S = {
    "reasigna": f"s = nuevo({OTRO});",
    "empuja": f"empujar(s, {OTRO});",
    "crece": "crecer(s);",
    "mueve": "imprimir(consumir(s));",
}

# Como se invalida al duenio `xs`, que es un contenedor y no un
# `str` suelto. `xs[0] = ...` no vale: reemplaza el `SafeString`
# en el sitio, y el puntero al sitio no cambia.
INVALIDAN_XS = {
    "anade": f"anadir(xs, nuevo({OTRO}));",
    "reasigna": f"xs = [nuevo({OTRO})];",
}

# (nombre, lo que se declara en `main`, la expresion que da la vista, el
# tipo de la vista, como se usa, como se invalida)
FORMAS = [
    ("vista", f"var s = nuevo({LARGO});", "vista(s)", "view", INVALIDAN_S),
    ("rebanar", f"var s = nuevo({LARGO});", "rebanar(vista(s), 0, 3)",
     "view", INVALIDAN_S),
    ("if", f"var s = nuevo({LARGO}); let c = largo(s) > 1;",
     'if c { vista(s) } else { "z" }', "view", INVALIDAN_S),
    ("sino", f"var s = nuevo({LARGO});", "sin_vista() sino vista(s)", "view",
     INVALIDAN_S),
    ("funcion", f"var s = nuevo({LARGO});", "primero(vista(s))", "view",
     INVALIDAN_S),
    ("puntero", f"var s = nuevo({LARGO}); let f: fn(view) -> view = primero;",
     "f(vista(s))", "view", INVALIDAN_S),
    ("clausura",
     f"var s = nuevo({LARGO}); let cl = fn(x: view) -> view {{ return x; }};",
     "cl(vista(s))", "view", INVALIDAN_S),
    ("generica", f"var s = nuevo({LARGO});", "id(vista(s))", "view",
     INVALIDAN_S),
    ("struct", f"var s = nuevo({LARGO});", "Palabra { t: vista(s) }",
     "Palabra", INVALIDAN_S),
    ("match", f"var e = E.A(nuevo({LARGO}));",
     'match e { E.A(t) -> t, E.B -> "z" }', "view",
     {"reasigna": "e = E.B;"}),
    ("mapa", f'var m: map<str, str> = []; poner(m, "k", nuevo({LARGO}));',
     'obtener(m, "k") sino "z"', "view",
     {"pone": f'poner(m, "k", nuevo({OTRO}));',
      "quita": 'imprimir(quitar(m, "k"));'}),
    ("str_prestado", f"var xs: list<str> = [nuevo({LARGO})];",
     "xs[0]", "&str", INVALIDAN_XS),
    # El struct que presta es la otra cara del prestamo: se trata como una
    # vista, y esa vista es su campo. Antes habia una sola forma (el literal);
    # aqui se transporta como cualquier vista, y con dos campos de hondo.
    ("palabra", f"var s = nuevo({LARGO});",
     "Palabra { t: vista(s) }", "Palabra", INVALIDAN_S),
    ("palabra_rebanar", f"var s = nuevo({LARGO});",
     "Palabra { t: rebanar(vista(s), 0, 3) }", "Palabra", INVALIDAN_S),
    ("palabra_funcion", f"var s = nuevo({LARGO});",
     "palabra(vista(s))", "Palabra", INVALIDAN_S),
    ("palabra_eco", f"var s = nuevo({LARGO});",
     "eco(Palabra { t: vista(s) })", "Palabra", INVALIDAN_S),
    ("palabra_if", f"var s = nuevo({LARGO}); let c = largo(s) > 1;",
     'if c { Palabra { t: vista(s) } } else { Palabra { t: "" } }',
     "Palabra", INVALIDAN_S),
    ("palabra_match", f"var s = nuevo({LARGO}); let k = K.Uno;",
     'match k { K.Uno -> Palabra { t: vista(s) }, K.Dos -> Palabra { t: "" } }',
     "Palabra", INVALIDAN_S),
    ("caja", f"var s = nuevo({LARGO});",
     "Caja { p: Palabra { t: vista(s) } }", "Caja", INVALIDAN_S),
    ("caja_funcion", f"var s = nuevo({LARGO});",
     "caja(vista(s))", "Caja", INVALIDAN_S),
    ("caja_if", f"var s = nuevo({LARGO}); let c = largo(s) > 1;",
     'if c { Caja { p: Palabra { t: vista(s) } } } '
     'else { Caja { p: Palabra { t: "" } } }', "Caja", INVALIDAN_S),
    # Composicion de dos capas: la vista pasa por dos formas antes de
    # llegar a su variable. Lo que importa no es cada capa suelta —eso
    # ya esta— sino que la procedencia se propague por las dos.
    ("id_de_primero", f"var s = nuevo({LARGO});",
     "id(primero(vista(s)))", "view", INVALIDAN_S),
    ("primero_de_id", f"var s = nuevo({LARGO});",
     "primero(id(vista(s)))", "view", INVALIDAN_S),
    ("if_de_primero", f"var s = nuevo({LARGO}); let c = largo(s) > 1;",
     'if c { primero(vista(s)) } else { "z" }', "view", INVALIDAN_S),
    ("primero_de_if", f"var s = nuevo({LARGO}); let c = largo(s) > 1;",
     'primero(if c { vista(s) } else { "z" })', "view", INVALIDAN_S),
    # Composicion de tres capas con funciones: la vista nace de
    # `vista(s)`, va dentro del valor de un `if`, y ese `if` es
    # argumento de `primero`, cuyo resultado pasa por `id`. Tres
    # funciones encadenadas, cada una tiene que propagar la procedencia.
    ("id_de_primero_de_if",
     f"var s = nuevo({LARGO}); let c = largo(s) > 1;",
     'id(primero(if c { vista(s) } else { "z" }))', "view", INVALIDAN_S),
    # Y la clausura con un `if` dentro, sin la generica: el caso de la
    # auditoria ("clausura generica") no se puede probar hoy porque el
    # comprobador no acepta `aplica<T, F>` con T = view.
    ("clausura_de_if",
     f"var s = nuevo({LARGO}); let c = largo(s) > 1; "
     f"let cl = fn(x: view) -> view {{ return x; }};",
     'cl(if c { vista(s) } else { "z" })', "view", INVALIDAN_S),
]


def _uso(tipo):
    if tipo == "Palabra":
        return "imprimir(byte(v.t, 0));"
    if tipo == "Caja":
        return "imprimir(byte(v.p.t, 0));"
    return "imprimir(byte(v, 0));"


def _vacia(tipo):
    if tipo == "Palabra":
        return 'Palabra { t: "" }'
    if tipo == "Caja":
        return 'Caja { p: Palabra { t: "" } }'
    return '""'


def _leida(tipo):
    """Algo del valor que el programa lea, para que no avise de uno sin leer."""
    if tipo == "Palabra":
        return "largo(v.t)"
    if tipo == "Caja":
        return "largo(v.p.t)"
    return "largo(v)"


def _enlaces(expr, tipo):
    """Las dos formas de dejar la vista en `v`: al declararla, o
    despues. Lo que tenia antes se lee, para que no avise de un
    valor que nadie lee. Un `&T` se declara con su tipo —sin el,
    `xs[0]` se tomaria por un movimiento— y no admite la variante
    `asigna`: un prestamo no puede nacer vacio."""
    if tipo.startswith("&"):
        yield "let", f"let v: {tipo} = {expr};"
        return
    yield "let", f"let v = {expr};"
    yield "asigna", (f"var v: {tipo} = {_vacia(tipo)}; imprimir({_leida(tipo)}); "
                     f"v = {expr};")


def _programa(cuerpo):
    lineas = "\n".join("    " + linea for linea in cuerpo)
    return f"{PRELUDIO}\nfn main() {{\n{lineas}\n    imprimir(\"\\n\");\n}}\n"


def casos():
    """(nombre, malo, bueno) de cada combinacion."""
    for forma, dueno, expr, tipo, invalidan in FORMAS:
        for enlace, texto in _enlaces(expr, tipo):
            for como, invalida in invalidan.items():
                malo = _programa([dueno, texto, invalida, _uso(tipo)])
                bueno = _programa([dueno, "if true {", "    " + texto,
                                   "    " + _uso(tipo), "}", invalida])
                yield f"{forma}/{enlace}/{como}", malo, bueno
        # La vista —o el struct que presta— sin nombre, prestada a una funcion
        # que modifica al duenio en la misma llamada: el fallo 2 de la
        # especificacion.
        if invalidan is INVALIDAN_S and tipo in ("view", "Palabra"):
            llama = "g" if tipo == "view" else "hp"
            malo = _programa([dueno, f"{llama}(s, {expr});"])
            if tipo == "view":
                bueno = _programa([dueno, f"let copia = nuevo({expr});",
                                   "g(s, vista(copia));"])
            else:
                bueno = _programa([dueno, 'hp(s, palabra("z"));'])
            yield f"{forma}/llamada", malo, bueno
