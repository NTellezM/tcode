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
struct Palabra {{ t: view }}
fn primero(v: view) -> view {{ return v; }}
fn id<T>(x: T) -> T {{ return x; }}
fn crecer(x: mut str) {{ empujar(x, {OTRO}); }}
fn consumir(x: str) -> usize {{ return largo(x); }}
fn sin_vista() -> view ! {{ falla "no"; }}
fn g(a: mut str, b: view) {{ empujar(a, {OTRO}); imprimir(byte(b, 0)); }}
"""

# Como se invalida al duenio `s` (o `e`, o `m`).
INVALIDAN_S = {
    "reasigna": f"s = nuevo({OTRO});",
    "empuja": f"empujar(s, {OTRO});",
    "crece": "crecer(s);",
    "mueve": "imprimir(consumir(s));",
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
    ("mapa", f'var m: mapa<str, str> = []; poner(m, "k", nuevo({LARGO}));',
     'obtener(m, "k") sino "z"', "view",
     {"pone": f'poner(m, "k", nuevo({OTRO}));',
      "quita": 'imprimir(quitar(m, "k"));'}),
]


def _uso(tipo):
    return "imprimir(byte(v.t, 0));" if tipo == "Palabra" else "imprimir(byte(v, 0));"


def _vacia(tipo):
    return 'Palabra { t: "" }' if tipo == "Palabra" else '""'


def _enlaces(expr, tipo):
    """Las dos formas de dejar la vista en `v`: al declararla, o despues. Lo
    que tenia antes se lee, para que no avise de un valor que nadie lee."""
    yield "let", f"let v = {expr};"
    leida = "largo(v.t)" if tipo == "Palabra" else "largo(v)"
    yield "asigna", (f"var v: {tipo} = {_vacia(tipo)}; imprimir({leida}); "
                     f"v = {expr};")


def _programa(cuerpo):
    lineas = "\n".join("    " + l for l in cuerpo)
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
        # La vista sin nombre, prestada a una funcion que modifica al duenio
        # en la misma llamada: el fallo 2 de la especificacion.
        if invalidan is INVALIDAN_S and tipo == "view":
            malo = _programa([dueno, f"g(s, {expr});"])
            bueno = _programa([dueno, f"let copia = nuevo({expr});",
                               "g(s, vista(copia));"])
            yield f"{forma}/llamada", malo, bueno
