"""
Rechazo por construccion: cada regla del lenguaje, en pares minimos.

Es el oraculo de lo que NO debe compilar que no es ningun compilador. Cada
regla da dos versiones de unas pocas lineas que solo difieren en lo que la
rompe:

  - la segura tiene que compilar y correr limpia bajo ASan y UBSan: prueba
    que el contexto es valido y que la diferencia es lo unico que importa;
  - la rota tiene que rechazarse con el PRIMER error en la linea que dice el
    caso, y diciendo lo que tiene que decir.

Lo sabe la construccion: quien escribio el par sabe que regla rompe y donde.
Cada par se mete en varios contextos —directo en `main`, dentro de un `if`,
de un bucle, de un brazo de `match`, de otra funcion, de una generica—,
que es donde se esconden los agujeros: P10 encontro los suyos cambiando la
forma de transportar una vista, no la regla.

Cada linea de un caso es un texto, o `(texto, marca)`: la marca nombra la
linea para decir que el error va ahi (`"error"`) o para citarla en el
mensaje (`{movida}` en el texto esperado es el numero de esa linea).
"""

LARGO = '"' + "x" * 40 + '"'
OTRO = '"' + "y" * 60 + '"'

# Lo que todos los casos pueden usar.
PRELUDIO = """fn puede(n: usize) -> usize ! { if n > 5 { fail "no"; } return n; }
fn dos(a: usize, b: usize) -> usize { return a + b; }
fn consumir(x: str) -> usize { return largo(x); }
fn g(a: mut str, b: mut str) { empujar(a, b); }
fn leer(x: &str) -> usize { return largo(x); }
enum E { A, B, C }
enum Ctx { Uno, Dos }
struct Q { s: str, n: usize }
enum F { X, Y(usize) }
fn doble_n<T: numero>(x: T) -> T { return x + x; }
fn mismo<T: igualable>(a: T, b: T) -> bool { return igual(a, b); }
"""


class Regla:
    """`antes` y `despues` son iguales en las dos versiones; `segura` y
    `rota` son lo que cambia. `dice` son trozos que el primer error tiene que
    contener. `en_bucle`: si el par tiene sentido dentro de un bucle (mover
    algo de fuera no lo tiene: la segunda vuelta no lo encontraria)."""

    def __init__(self, nombre, antes, segura, rota, despues, dice, en_bucle=True):
        self.nombre = nombre
        self.antes = antes
        self.segura = segura
        self.rota = rota
        self.despues = despues
        self.dice = dice
        self.en_bucle = en_bucle


REGLAS = [
    Regla("usar lo movido",
          [f"let a = nuevo({LARGO});"],
          ["let b = copiar(a);"], [("let b = a;", "movida")],
          [("imprimir(a);", "error"), "imprimir(b);"],
          ["`a` ya se movio en la linea {movida}"], en_bucle=False),
    Regla("modificar lo prestado",
          [f"var s = nuevo({LARGO});", "let v = vista(s);"],
          ["imprimir(v);", f"empujar(s, {OTRO});"],
          [(f"empujar(s, {OTRO});", "error"), "imprimir(v);"],
          [],
          ["no se puede modificar `s`", "prestada por `v`"]),
    Regla("modificar un let",
          [],
          ["var x = 1;"], ["let x = 1;"],
          [("x = 2;", "error"), "imprimir(x);"],
          ["`x` se declaro con `let`"]),
    Regla("un valor de otro tipo",
          [],
          ["let x: usize = 1;"], [('let x: usize = "a";', "error")],
          ["imprimir(x);"],
          ["`x` se declaro `usize`"]),
    Regla("mezclar enteros sin decirlo",
          ["let a: i64 = 1;", "let b: usize = 2;"],
          ["imprimir(a + (b como i64));"], [("imprimir(a + b);", "error")],
          [],
          ["`i64` y `usize` no se mezclan"]),
    Regla("ignorar un fallo",
          [],
          ["imprimir(puede(1) sino 0);"], [("imprimir(puede(1));", "error")],
          [],
          ["`puede` puede fallar"]),
    Regla("try fuera de una funcion que falla",
          [],
          ["let x = puede(1) sino 0;"], [("let x = try puede(1);", "error")],
          ["imprimir(x);"],
          ["`try`", "no esta declarada con `!`"]),
    Regla("match sin todas las formas",
          ["let e = E.B;"],
          ["match e { E.A -> { imprimir(1); } E.B -> { imprimir(2); } "
           "E.C -> { imprimir(3); } }"],
          [("match e { E.A -> { imprimir(1); } E.B -> { imprimir(2); } }",
            "error")],
          [],
          ["le faltan formas: `E.C`"]),
    Regla("un indice que no es usize",
          ["let xs: list<usize> = [1, 2];", "let i: i64 = 0;"],
          ["imprimir(xs[i como usize]);"], [("imprimir(xs[i]);", "error")],
          [],
          ["un indice tiene que ser `usize`"]),
    Regla("un numero que no cabe",
          [],
          ["let x: u8 = 255;"], [("let x: u8 = 256;", "error")],
          ["imprimir(x);"],
          ["`256` no cabe en `u8`"]),
    Regla("argumentos que faltan",
          [],
          ["imprimir(dos(1, 2));"], [("imprimir(dos(1));", "error")],
          [],
          ["`dos` espera 2 argumento(s) y recibio 1"]),
    Regla("un nombre que no existe",
          ["let esta = 1;"],
          ["imprimir(esta);"], [("imprimir(no_esta);", "error")],
          [],
          ["`no_esta` no esta declarada"]),
    Regla("mover dentro de un bucle",
          [f"let s = nuevo({LARGO});", "var i = 0;"],
          ["while i < 2 { imprimir(leer(s)); i = i + 1; }"],
          [("while i < 2 { imprimir(consumir(s)); i = i + 1; }", "error")],
          [],
          ["`s` se declaro fuera del bucle y se mueve aqui dentro"],
          en_bucle=False),
    Regla("prestar dos veces para modificar",
          [f"var s = nuevo({LARGO});", f"var t = nuevo({OTRO});"],
          ["g(s, t);"], [("g(s, s);", "error")],
          ["imprimir(largo(s));"],
          ["`s` se presta dos veces en la misma llamada a `g`"]),
    Regla("break fuera de un bucle",
          [],
          ["imprimir(1);"], [("break;", "error")],
          [],
          ["`break` solo tiene sentido dentro de un `for` o un `while`"],
          en_bucle=False),
    Regla("comparar un texto con un numero",
          ['let s = nuevo("a");'],
          ['imprimir(s == "a");'], [("imprimir(s == 1);", "error")],
          [],
          ["no se pueden comparar `str`"]),
    Regla("usar un nombre fuera de su bloque",
          ["let c = n_argumentos() > 0;", "if c { let y = 1; imprimir(y); }"],
          ["imprimir(1);"], [("imprimir(y);", "error")],
          [],
          ["`y` no esta declarada"]),
    Regla("una vista que vive mas que su dueno",
          ['var v: view = "";', "imprimir(largo(v));",
           "let c = n_argumentos() > 0;"],
          # La vida de un dueno es su bloque: la segura lo declara fuera.
          [f"let s = nuevo({LARGO});", "if c { v = vista(s); }"],
          [(f"if c {{ let s = nuevo({LARGO}); v = vista(s); }}", "error")],
          ["imprimir(v);"],
          ["`v` vive mas que `s`"]),
    Regla("declarar dos veces en el mismo bloque",
          ["let x = 1;", "imprimir(x);"],
          ["let z = 2;"], [("let x = 2;", "error")],
          ["imprimir(x);"],
          ["`x` ya esta declarada en este bloque"]),
    # ---- genericas ----
    Regla("una restriccion que no se cumple",
          [],
          ["imprimir(doble_n(2));"], [("imprimir(doble_n(true));", "error")],
          [],
          ["`doble_n` pide que `T` sea `numero`", "`T` es `bool`"]),
    Regla("un parametro de tipo con dos tipos",
          [],
          ["imprimir(mismo(1, 2));"], [("imprimir(mismo(1, true));", "error")],
          [],
          ["Un mismo parametro de tipo es un solo tipo"]),
    # ---- clausuras ----
    Regla("usar en una clausura lo que no capturo",
          ["let n = 1;"],
          ["let f = fn[n](x: usize) -> usize { return x + n; };"],
          [("let f = fn(x: usize) -> usize { return x + n; };", "error")],
          ["imprimir(f(1));"],
          ["`n` no esta declarada"]),
    Regla("modificar una captura de solo lectura",
          ["var n = 1;", "imprimir(n);"],
          ["var f = fn[mut n]() { n = n + 1; imprimir(n); };"],
          [("var f = fn[n]() { n = n + 1; imprimir(n); };", "error")],
          ["f();"],
          ["`n` se capturo para leer"]),
    Regla("usar lo que se llevo una clausura",
          [f"let s = nuevo({LARGO});"],
          ["let c = copiar(s);", "let f = fn[c]() -> usize { return largo(c); };"],
          [("let f = fn[s]() -> usize { return largo(s); };", "movida")],
          [("imprimir(largo(s));", "error"), "imprimir(f());"],
          ["`s` ya se movio en la linea {movida}"], en_bucle=False),
    # ---- como ----
    Regla("convertir lo que no es un numero",
          ["let b = true;"],
          ["imprimir(if b { 1 } else { 0 });"], [("imprimir(b como u8);", "error")],
          [],
          ["`como` convierte entre numeros"]),
    Regla("convertir un numero escrito que no cabe",
          [],
          ["imprimir(255 como u8);"], [("imprimir(300 como u8);", "error")],
          [],
          ["`300 como u8` no cabe en `u8`"]),
    # ---- bloques ----
    Regla("sacar de un bloque sin dejar nada",
          ["var b: bloque<str> = reservar(2);"],
          ["let x = copiar(b[0]);"], [("let x = b[0];", "error")],
          ["imprimir(x);"],
          ["no se puede sacar un elemento de un bloque"]),
    Regla("redimensionar lo prestado",
          ["var b: bloque<str> = reservar(2);", "let v = vista(b[0]);"],
          ["imprimir(v);", "redimensionar(b, 4);"],
          [("redimensionar(b, 4);", "error"), "imprimir(v);"],
          [],
          ["no se puede modificar `b`", "prestada por `v`"]),
    Regla("intercambiar por otro tipo",
          ["var b: bloque<str> = reservar(2);"],
          ['let x = intercambiar(b[0], nuevo("z"));'],
          [("let x = intercambiar(b[0], 1);", "error")],
          ["imprimir(x);"],
          ["`intercambiar` pone y saca lo mismo"]),
    # ---- enums y structs ----
    Regla("una forma que no existe",
          [],
          ["let f = F.Y(1);"], [("let f = F.Z;", "error")],
          ["imprimir(igual(1, 1));"],
          ["`F` no tiene la forma `Z`"]),
    Regla("un patron que atrapa de mas",
          ["let f = F.Y(1);"],
          ["match f { F.Y(x) -> { imprimir(x); } _ -> { } }"],
          [("match f { F.Y(x, y) -> { imprimir(x); } _ -> { } }", "error")],
          [],
          ["`F.Y` lleva 1 valor, y el patron atrapa 2"]),
    Regla("una forma con otros valores",
          [],
          ["let f = F.Y(1);"], [("let f = F.Y(1, 2);", "error")],
          ["imprimir(igual(1, 1));"],
          ["`F.Y` lleva 1 valor, y se le dieron 2"]),
    Regla("un campo que no existe",
          ['let q = Q { s: nuevo("a"), n: 1 };'],
          ["imprimir(q.n);"], [("imprimir(q.m);", "error")],
          [],
          ["`Q` no tiene un campo `m`"]),
    Regla("un struct sin todos sus campos",
          [],
          ['let q = Q { s: nuevo("a"), n: 1 };'], [('let q = Q { s: nuevo("a") };', "error")],
          ["imprimir(q.n);"],
          ["a `Q` le faltan campos: `n`"]),
    # ---- numeros y valores ----
    Regla("el resto de un decimal",
          ["let x: f64 = 2.5;"],
          ["imprimir(x / 2.0);"], [("imprimir(x % 2.0);", "error")],
          [],
          ["`%` es el resto de una division entera"]),
    Regla("negar un entero sin signo",
          ["let x: u8 = 3;"],
          ["imprimir(0 -? x);"], [("imprimir(-x);", "error")],
          [],
          ["`u8` no tiene signo"]),
    Regla("interpolar lo que no se muestra",
          ["let xs: list<usize> = [1, 2];"],
          ['imprimir($"{xs[0]}");'], [('imprimir($"{xs}");', "error")],
          [],
          ["dentro de `{{}}` va un escalar o texto"]),
    Regla("una condicion que no es bool",
          ["let n = 1;"],
          ["if n > 0 { imprimir(n); }"], [("if n { imprimir(n); }", "error")],
          [],
          ["la condicion de `if` debe ser `bool`"]),
    Regla("un argumento de otro tipo",
          [],
          ['imprimir(byte("a", 0));'], [('imprimir(byte("a", true));', "error")],
          [],
          ["el argumento 2 de `byte` debe ser `usize`"]),
    Regla("una palabra reservada de antemano no es un nombre",
          [], ["let x = 1;"],
          [("let protocol = 1;", "error")],
          [],
          ["se esperaba 'ident'"]),
    # Guardar un prestamo pediria expresar cuanto vive lo que apunta, y el
    # tipo no lo dice. El mapa ya lo rechazaba; la lista, el arreglo y el
    # bloque no.
    Regla("un prestamo guardado en una lista",
          [],
          ["var l: list<str> = [];"], [("var l: list<&str> = [];", "error")],
          ["imprimir(largo(l));"],
          ["no es un tipo almacenable"]),
]


# Las que viven fuera de un cuerpo: la firma, el parametro, el `return`.
# Van en el preludio, y el error tambien.
ARRIBA = [
    ("devolver lo prometido",
     "fn f(c: bool) -> usize { if c { return 1; } return 2; }",
     "fn f(c: bool) -> usize { if c { return 1; } }",
     "imprimir(f(true));",
     ["`f` promete devolver `usize`"]),
    ("modificar un parametro prestado para leer",
     "fn f(x: mut str) { empujar(x, \"a\"); }",
     "fn f(x: &str) { empujar(x, \"a\"); }",
     f"var s = nuevo({LARGO}); f(s); imprimir(s);",
     ["`x` llego prestado solo para leer"]),
    ("sacar un campo de un parametro prestado",
     "fn f(p: &Q) -> str { return copiar(p.s); }",
     "fn f(p: &Q) -> str { return p.s; }",
     f"let q = Q {{ s: nuevo({LARGO}), n: 1 }}; imprimir(f(q));",
     ["no se puede sacar `p.s`"]),
    ("devolver un valor sin tipo de retorno",
     "fn f() { return; }",
     "fn f() { return 1; }",
     "f();",
     ["esta funcion no declara tipo de retorno"]),
    ("un return vacio que promete un valor",
     "fn f() -> usize { return 1; }",
     "fn f() -> usize { return; }",
     "imprimir(f());",
     ["el `return` esta vacio"]),
    # Un campo de struct guarda un valor con duenio, o es `view` y hace del
    # struct uno que presta. Un `&T` no: nadie sabria de quien presta ni
    # cuanto vive, y en C quedaba el valor copiado sin dueno (dos
    # liberaciones, con ASan).
    ("un campo de struct no guarda un prestamo con `&`",
     "struct A { v: view, n: usize }",
     "struct A { v: &str, n: usize }",
     f"var t = nuevo({LARGO}); var a = A {{ v: vista(t), n: 1 }}; "
     f"imprimir(largo(a.v) + a.n);",
     ["un campo no guarda `&T`", "el campo es `view`"]),
]


def _contextos(regla):
    """(nombre, antes de las lineas, despues de ellas, lo que va fuera de
    `main`, lo que va dentro de `main`): cada sitio donde se mete el par."""
    yield "main", [], [], "", ""
    yield "if", ["let ctx_c = n_argumentos() > 0;", "if ctx_c {"], ["}"], "", ""
    if regla.en_bucle:
        yield ("bucle", ["var ctx_i = 0;", "while ctx_i < 1 {"],
               ["    ctx_i = ctx_i + 1;", "}"], "", "")
        yield "for", ["let ctx_xs = [1];", "for ctx_x en ctx_xs {"], ["}"], "", ""
    yield ("match", ["let ctx_k = Ctx.Uno;", "match ctx_k {", "Ctx.Uno -> {"],
           ["}", "Ctx.Dos -> { }", "}"], "", "")
    yield "funcion", None, None, "fn aux() {", "aux();"
    yield ("generica", None, None, "fn aux<T>(ctx_t: T) {\n    let _t = ctx_t;",
           "aux(1);")


def _armar(lineas_caso, contexto):
    """El programa entero y los numeros de linea de cada marca."""
    nombre, abre, cierra, fuera, dentro = contexto
    cuerpo = []     # (texto, marca)
    for x in lineas_caso:
        cuerpo.append(x if isinstance(x, tuple) else (x, None))

    lineas = PRELUDIO.rstrip("\n").split("\n")
    marcas = {}

    def poner(texto, marca=None, sangria=1):
        lineas.append("    " * sangria + texto)
        if marca:
            marcas[marca] = len(lineas)

    if fuera:
        for t in fuera.split("\n"):
            lineas.append(t)
        for texto, marca in cuerpo:
            poner(texto, marca)
        lineas.append("}")
        lineas.append("fn main() {")
        poner(dentro)
        lineas.append("}")
    else:
        lineas.append("fn main() {")
        hondo = 1
        for t in abre:
            poner(t, sangria=hondo)
            if t.endswith("{"):
                hondo += 1
        for texto, marca in cuerpo:
            poner(texto, marca, hondo)
        for t in cierra:
            if t.strip().startswith("}"):
                hondo -= 1
            poner(t.strip(), sangria=hondo)
        lineas.append("}")
    return "\n".join(lineas) + "\n", marcas


def casos():
    """(nombre, segura, rota, linea del error, lo que tiene que decir)."""
    for regla in REGLAS:
        for contexto in _contextos(regla):
            segura, _ = _armar([*regla.antes, *regla.segura, *regla.despues],
                               contexto)
            rota, marcas = _armar([*regla.antes, *regla.rota, *regla.despues],
                                  contexto)
            dice = [d.format(**marcas) for d in regla.dice]
            yield (f"{regla.nombre} / {contexto[0]}", segura, rota,
                   marcas["error"], dice)
    for nombre, segura, rota, uso, dice in ARRIBA:
        base = PRELUDIO.rstrip("\n").split("\n")
        linea = len(base) + 1
        cola = f"fn main() {{\n    {uso}\n}}\n"
        yield (f"{nombre} / arriba", "\n".join([*base, segura]) + "\n" + cola,
               "\n".join([*base, rota]) + "\n" + cola, linea, dice)
