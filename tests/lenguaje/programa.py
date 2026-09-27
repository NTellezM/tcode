"""PROGRAMA: el archivo C entero, escrito por Tcode."""

import concurrent.futures
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

from compilar_c import herramienta
from semilla import SEMILLA

from tcode.cli import compilar_archivo

from .aborta import ABORTA
from .acepta import ACEPTA
from .avisa import AVISA
from .comun import (
    RAIZ,
    RUNTIME,
    SISTEMA_TCODEC,
    Resultado,
    bloques,
    en_paralelo,
    en_procesos,
    tcodec,
)
from .modulos import MODULOS
from .rechazo import RECHAZO


def _errores_python(ruta):
    """Los errores del compilador de Python, el oraculo. Van a otros procesos
    con `en_procesos`: por eso estan aqui fuera."""
    try:
        _, errs = compilar_archivo(ruta)
    except Exception as exc:
        return [str(exc)]
    return errs or []


def _c_python(ruta):
    """El C del compilador de Python y sus errores. Un programa con sintaxis
    que Python no conoce —la de despues de congelarlo— da error y no C."""
    try:
        return compilar_archivo(ruta)
    except Exception as exc:
        return None, [str(exc)]


# Lo que se escribe distinto desde que Python se congelo: `x.f(...)` y
# `a..b`. Un mutante que cae en ello es sintaxis nueva para `tcodec`, y
# para Python sigue siendo un error: no se comparan. `Forma.Variante(...)`
# no es nuevo, y se distingue porque lo de delante es un enum.
_PUNTO_Y_LLAMADA = re.compile(r"(\w+|[)\]])\s*\.\s*[A-Za-z_]\w*\s*\(")


def _sintaxis_nueva(linea, enums):
    if ".." in linea:
        return True
    return any(m.group(1) not in enums for m in _PUNTO_Y_LLAMADA.finditer(linea))


def _avisos_python(ruta):
    """Los avisos del compilador de Python, o None si no compila."""
    try:
        _, errs, comp_a = compilar_archivo(ruta, devolver_comp=True)
    except Exception:
        return None
    return None if errs else comp_a.avisos


TITULO = "el archivo C entero, escrito por Tcode"


def correr(suite: Resultado) -> None:
    # El paso que separa "piezas que coinciden" de "un compilador": el `.c`
    # completo —cabecera, aritmetica, prototipos y todas las funciones, `main`
    # incluida— escrito por `tcodec.t` y comparado byte a byte con el que escribe
    # el generador de Python. Lo que `tcodec` no sabe escribir entero lo rechaza
    # sin escribir medio archivo; se cuentan los programas identicos y se exige un
    # minimo.
    _CIERRES_TCODEC = r"""usar "std/lista";

fn sumar(a: usize, b: usize) -> usize { return a + b; }
fn aplicar(f: fn(usize, usize) -> usize, x: usize, y: usize) -> usize {
    return f(x, y);
}
fn doble_de<F>(f: F, x: usize) -> usize { return f(x) * 2; }

fn main() {
    let base: usize = 10;
    let tope: usize = 3;
    let mas = fn[base](x: usize) -> usize { return x + base; };
    imprimir($"{mas(5)}\n");
    imprimir($"{doble_de(mas, 1)}\n");
    imprimir($"{aplicar(sumar, 2, 3)}\n");
    let g = sumar;
    imprimir($"{g(4, 4)}\n");
    var ns: lista<usize> = [];
    anadir(ns, 1); anadir(ns, 5); anadir(ns, 2);
    let chicos = cuantas_cumplen(ns, fn[tope](n: &usize) -> bool { return n < tope; });
    imprimir($"{chicos}\n");
    let anidada = fn[base](x: usize) -> usize {
        let k: usize = base;
        let otra = fn[k](y: usize) -> usize { return y * k; };
        return otra(x) + 1;
    };
    imprimir($"{anidada(2)}\n");
}
"""

    # `&&` ata mas que `||`, y `1_000` es `1000`: el parser y el lexer en Tcode
    # los leian distinto, y el C salia distinto.
    _PRECEDENCIA_TCODEC = r"""fn main() {
    let a = true;
    let b = true;
    let c = false;
    let x: usize = 1_000;
    imprimir($"{a || b && c} {x}\n");
}
"""

    # Una clausura dentro de una generica: una por copia, numeradas en el orden
    # en que el comprobador crea las copias.
    _CIERRE_EN_GENERICA_TCODEC = r"""usar "std/lista";

fn contar_si<T>(xs: &lista<T>, n: usize) -> usize {
    let tope = n;
    let pequeno = fn[tope](i: usize) -> bool { return i < tope; };
    var k: usize = 0;
    var i: usize = 0;
    while i < largo(xs) {
        if pequeno(i) { k = k + 1; }
        i = i + 1;
    }
    return k;
}

fn envolver<T>(x: T) -> usize {
    let f = fn(y: usize) -> usize { return y + 1; };
    let _x = x;
    return f(1);
}

fn main() {
    var ns: lista<usize> = [];
    anadir(ns, 1); anadir(ns, 2); anadir(ns, 3);
    var ts: lista<str> = [];
    anadir(ts, nuevo("a"));
    let mas = fn(z: usize) -> usize { return z * 2; };
    imprimir($"{contar_si(ns, 2)} {contar_si(ts, 5)} {envolver(3)} {mas(4)}\n");
}
"""

    # Capturar lo que tiene duenio lo mueve al struct de la clausura, que se
    # libera con su liberador; la variable lleva bandera.
    _CAPTURA_CON_DUENIO_TCODEC = r"""usar "std/lista";

fn main() {
    let prefijo = nuevo("pre-");
    let marca = fn[prefijo](x: &str) -> str {
        var r = copiar(prefijo);
        empujar(r, vista(x));
        return r;
    };
    let hola = nuevo("hola");
    let dicho = marca(hola);
    imprimir($"{dicho}\n");
    var ns: lista<str> = [];
    anadir(ns, nuevo("uva")); anadir(ns, nuevo("aguacate"));
    let tope = nuevo("xxxx");
    let cortos = filtradas(ns, fn[tope](x: &str) -> bool { return largo(x) < largo(tope); });
    imprimir($"{largo(cortos)}\n");
}
"""

    # `escribir_archivo`: su ayudante, y su tipo resultado donde le toca.
    _ESCRIBIR_ARCHIVO_TCODEC = r"""fn guardar(ruta: view, texto: view) -> usize ! {
    try escribir_archivo(ruta, texto);
    return largo(texto);
}
fn main() -> usize ! {
    let n = try guardar("/dev/null", "hola\n");
    imprimir($"{n}\n");
    return 0;
}
"""

    # `\{` en una interpolada es una llave escrita en los dos compiladores.
    _LLAVE_ESCRITA_TCODEC = r"""fn main() {
    let n: usize = 3;
    imprimir($"a \{ b \} c {n} {{d}}\n");
}
"""

    # Una clausura que modifica lo capturado: su entorno llega para modificar, y
    # una generica la recibe `mut`.
    _CIERRE_QUE_MODIFICA_TCODEC = r"""fn repetir<F>(n: usize, f: mut F) {
    var i: usize = 0;
    while i < n {
        f();
        i = i + 1;
    }
}

fn main() {
    let n: usize = 0;
    var contar = fn[mut n]() -> usize {
        n = n + 1;
        return n;
    };
    repetir(2, contar);
    let s = nuevo("a");
    var acumula = fn[mut s](x: view) -> usize {
        empujar(s, x);
        return largo(s);
    };
    imprimir($"{contar()} {acumula("bc")}\n");
}
"""

    # Patrones anidados, literales y guardas: una fila de `if` con `goto` al
    # final; y un `break` dentro del `switch` de un `match`, que sale del bucle.
    _PATRONES_TCODEC = r"""enum Forma2 { A, B(i64) }
enum Color { Rojo, Verde, Otro(str) }
enum Forma { Punto, Circulo(i64), Etiqueta(str, Color), Par(Forma2, usize) }

fn describir(f: &Forma) -> str {
    return match f {
        Forma.Punto -> nuevo("punto"),
        Forma.Circulo(0) -> nuevo("circulo vacio"),
        Forma.Circulo(-1) -> nuevo("circulo raro"),
        Forma.Circulo(r) if r > 100 -> nuevo("circulo grande"),
        Forma.Circulo(_) -> nuevo("circulo"),
        Forma.Etiqueta("hola", _) -> nuevo("saludo"),
        Forma.Etiqueta(s, Color.Otro(c)) -> $"{s} de color {c}",
        Forma.Etiqueta(s, _) -> $"etiqueta {s}",
        Forma.Par(Forma2.B(x), n) if x > 0 -> $"par {x} {n}",
        Forma.Par(_, n) -> $"par cualquiera {n}",
    };
}

fn main() {
    var i: usize = 0;
    var fs: lista<Forma> = [];
    anadir(fs, Forma.Punto);
    anadir(fs, Forma.Circulo(0));
    anadir(fs, Forma.Circulo(-1));
    anadir(fs, Forma.Circulo(500));
    anadir(fs, Forma.Circulo(5));
    anadir(fs, Forma.Etiqueta(nuevo("hola"), Color.Rojo));
    anadir(fs, Forma.Etiqueta(nuevo("cielo"), Color.Otro(nuevo("azul"))));
    anadir(fs, Forma.Etiqueta(nuevo("x"), Color.Verde));
    anadir(fs, Forma.Par(Forma2.B(3), 7));
    anadir(fs, Forma.Par(Forma2.A, 8));
    for f en fs { imprimir($"{describir(f)}\n"); }
    // Un `break` dentro de un `match` sale del bucle, no del `match`.
    while i < 10 {
        match fs[i] {
            Forma.Punto -> { i = i + 1; }
            Forma.Circulo(r) -> { if r == 500 { break; } i = i + 1; }
            _ -> { i = i + 1; }
        }
    }
    imprimir($"parado en {i}\n");
}
"""

    # Sacar un campo de su struct: se copia y su sitio queda a ceros.
    _CAMPO_SACADO_TCODEC = r"""struct Interior { texto: str, n: usize }
struct P { nombre: str, edad: usize, tags: lista<str>, dentro: Interior }

fn usa(s: str) -> usize { return largo(s); }

fn entrega(p: P) -> str {
    return p.nombre;
}

fn main() {
    var p = P { nombre: nuevo("ana"), edad: 3, tags: [],
        dentro: Interior { texto: nuevo("hondo"), n: 1 } };
    anadir(p.tags, nuevo("x"));
    let n = p.nombre;
    let t = p.dentro.texto;
    imprimir($"{n} {t} {p.edad} {largo(p.tags)} {p.dentro.n} ");
    imprimir($"{usa(copiar(p.tags[0]))}\n");
    p.nombre = nuevo("eva");
    p.dentro.texto = nuevo("otra");
    let q = p;
    imprimir($"{q.nombre} {q.dentro.texto} {entrega(q)}\n");
}
"""

    _CAMPO_SACADO_RETORNO_TCODEC = r"""struct P { nombre: str, edad: usize, sub: Q }
struct Q { t: str }

fn nuevo_p(n: view) -> P { return P { nombre: nuevo(n), edad: 1, sub: Q { t: nuevo("b") } }; }

// Sacar en un `return` vale en cualquier rama: la funcion se va, y lo que
// queda del struct se suelta ahi.
fn nombre_si(p: P, c: bool) -> str {
    if c { return p.nombre; }
    return nuevo("ninguno");
}

fn main() {
    var p = nuevo_p("ana");
    let n = p.nombre;
    p.nombre = nuevo("eva");
    imprimir($"{n} {nombre_si(p, true)} {nombre_si(nuevo_p("x"), false)}\n");
}
"""

    # Structs con un campo `view`: en C, un `SafeView` dentro del struct.
    _STRUCT_PRESTADO_TCODEC = r"""struct Palabra { texto: view, n: usize }
struct Linea { primera: Palabra, resto: view }

fn primera_de(s: &str) -> Palabra {
    return Palabra { texto: rebanar(vista(s), 0, 3), n: 3 };
}

fn texto_de(p: Palabra) -> view { return p.texto; }

fn mas_larga(a: Palabra, b: Palabra) -> Palabra {
    if a.n >= b.n { return a; }
    return b;
}

fn main() {
    let s = nuevo("hola mundo");
    let t = nuevo("adios");
    let p = primera_de(s);
    var q = Palabra { texto: vista(t), n: 5 };
    let l = Linea { primera: p, resto: rebanar(vista(s), 5, 10) };
    q.n = 2;
    let m = mas_larga(p, q);
    imprimir($"{p.texto} {texto_de(q)} {l.primera.texto}|{l.resto} {m.texto} {copiar(m).n}\n");
}
"""

    # `&&` con un `str` recien hecho prestado a la derecha: la derecha va dentro
    # de un `if`, y no delante de la sentencia.
    _CORTOCIRCUITO_TCODEC = r"""fn nombre(xs: &lista<str>) -> str {
    imprimir("[se evaluo] ");
    return copiar(xs[0]);
}

fn corto(v: view) -> bool { return largo(v) < 3; }

fn main() {
    var xs: lista<str> = [];
    // Con la lista vacia, la derecha no se puede evaluar: el `&&` corta.
    if largo(xs) == 1 && corto(nombre(xs)) { imprimir("no\n"); }
    if largo(xs) == 0 || corto(nombre(xs)) { imprimir("corta el ||\n"); }
    anadir(xs, nuevo("ab"));
    if largo(xs) == 1 && corto(nombre(xs)) { imprimir("si\n"); }
    let a = largo(xs) > 5 || corto(nombre(xs));
    imprimir($"{a}\n");
}
"""

    # Un enum que lleva un struct y otro enum escrito mas abajo: los tipos van
    # en C en orden de dependencia, con los copiadores de lo que llevan.
    _ENUM_CON_STRUCT_TCODEC = r"""// Un enum que lleva un struct, y otro enum escrito mas abajo.
enum Figura { Nada, Punto(Punto), Con(Color, Punto), Nombrada(Etiqueta) }

struct Punto { x: i64, y: i64 }
struct Etiqueta { texto: str, color: Color }

enum Color { Rojo, Otro(str) }

fn describir(f: &Figura) -> str {
    return match f {
        Figura.Nada -> nuevo("nada"),
        Figura.Punto(p) -> $"({p.x}, {p.y})",
        Figura.Con(Color.Otro(c), p) -> $"{c} en ({p.x}, {p.y})",
        Figura.Con(_, p) -> $"rojo en ({p.x}, {p.y})",
        Figura.Nombrada(e) -> copiar(e.texto),
    };
}

fn main() {
    var fs: lista<Figura> = [];
    anadir(fs, Figura.Nada);
    anadir(fs, Figura.Punto(Punto { x: 1, y: -2 }));
    anadir(fs, Figura.Con(Color.Otro(nuevo("azul")), Punto { x: 3, y: 4 }));
    anadir(fs, Figura.Con(Color.Rojo, Punto { x: 0, y: 0 }));
    anadir(fs, Figura.Nombrada(Etiqueta { texto: nuevo("hola"), color: Color.Rojo }));
    for f en fs { imprimir($"{describir(f)}\n"); }
    let otra = copiar(fs[4]);
    imprimir($"{describir(otra)}\n");
}
"""

    # Un operando que necesita sentencias propias, en una operacion, una llamada,
    # un struct y un arreglo: los de antes se adelantan en temporales.
    _ORDEN_TCODEC = r"""struct P { a: i64, b: i64 }
fn dice(t: view, n: i64) -> i64 { imprimir(t); return n; }
fn f(a: i64, b: i64) -> i64 { return a + b; }
fn main() {
    let c = true;
    let x = dice("izq ", 1) + (if c { dice("der ", 2) } else { 0 });
    let y = f(dice("a1 ", 1), if c { dice("a2 ", 2) } else { 0 });
    let p = P { a: dice("c1 ", 1), b: if c { dice("c2 ", 2) } else { 0 } };
    let arr: [i64; 2] = [dice("e1 ", 1), if c { dice("e2 ", 2) } else { 0 }];
    imprimir($"{x} {y} {p.a + p.b} {arr[0] + arr[1]}\n");
}
"""

    # Copias de una generica dentro de otra: salen en el orden en que las hace
    # el comprobador, la de dentro antes solo si se hizo antes.
    _COPIAS_ANIDADAS_TCODEC = r"""fn mismo<T>(x: T) -> T { return x; }
fn g(x: i32) -> u8 { return 1; }
fn main() {
    let x: i32 = 1;
    let c = x > 0;
    imprimir($"{mismo(g(mismo(x)))} {mismo(mismo(x) == x)}\n");
    imprimir($"{mismo((mismo(x) como u32))} {mismo(if c { x } else { 2 })}\n");
}
"""

    # Un `str` que sale de un `if` y se entrega a una funcion: la funcion se lo
    # queda, y la sentencia no lo suelta. `tcodec` lo soltaba otra vez.
    _STR_ENTREGADO_TCODEC = r"""fn junta(a: str, b: str) -> usize { return largo(a) + largo(b); }
fn main() {
    let c = true;
    let n = junta(nuevo("a"), if c { nuevo("bb") } else { nuevo("") });
    imprimir($"= {n}\n");
}
"""

    _FN_ANIDADA_TCODEC = r"""fn doble(n: usize) -> usize { return n * 2; }
fn aplicar(f: fn(usize) -> usize, n: usize) -> usize { return f(n); }
fn dos_veces(g: fn(fn(usize) -> usize, usize) -> usize, n: usize) -> usize {
    return g(doble, g(doble, n));
}
fn main() { imprimir($"{dos_veces(aplicar, 3)}\n"); }
"""

    # En C una variable ya esta en ambito dentro de su propio inicializador:
    # `Caja caja = caja();` llamaria a la variable. Los dos lo calculan antes.
    _SU_INICIALIZADOR_TCODEC = r"""struct Caja { n: usize }
fn caja() -> Caja { return Caja { n: 4 }; }
fn doble(n: usize) -> usize { return n * 2; }
fn main() {
    let caja = caja();
    let doble = doble(caja.n) + 1;
    let largo = largo("abc");
    imprimir($"{caja.n} {doble} {largo}\n");
}
"""



    # Mas casos de modulos que los de MODULOS: ciclos de tres, modulos que no
    # estan de varias formas, un nombre propio contra uno traido, y lo que se usa
    # sin pedirlo. `tcodec` tiene que decir lo mismo que el cargador de Python.
    M = 'fn main() { imprimir("x"); }'
    _MODULOS_EXTRA_TCODEC = [
        ("ciclo de tres", {
            "a.t": 'usar "b.t";\n'+M,
            "b.t": 'usar "c.t";\nfn b() {}',
            "c.t": 'usar "a.t";\nfn c() {}',
        }, "a.t"),
        ("falta sin .t", {
            "a.t": 'usar "fantasma";\n'+M,
        }, "a.t"),
        ("falta de std", {
            "a.t": 'usar "std/fantasma";\n'+M,
        }, "a.t"),
        ("falta dentro de otro", {
            "a.t": 'usar "lib/b.t";\n'+M,
            "lib/b.t": '\n\nusar "nada.t";\nfn b() {}',
        }, "a.t"),
        ("propio contra traido", {
            "x.t": 'fn dos() -> usize { return 2; }',
            "app.t": 'usar "x.t";\nfn dos() -> usize { return 3; }\n'+M,
        }, "app.t"),
        ("con alias no choca", {
            "x.t": 'fn dos() -> usize { return 2; }',
            "y.t": 'fn dos() -> usize { return 22; }',
            "app.t": 'usar "x.t";\nusar "y.t" como y;\nfn main() { imprimir(dos() + y.dos()); }',
        }, "app.t"),
        ("sin pedir una funcion", {
            "c.t": 'fn tres() -> usize { return 3; }',
            "b.t": 'usar "c.t";\nfn b() -> usize { return tres(); }',
            "app.t": 'usar "b.t";\nfn main() {\n    imprimir(b());\n    imprimir(tres());\n}',
        }, "app.t"),
        ("sin pedir un struct", {
            "c.t": 'struct Caja { n: usize }',
            "b.t": 'usar "c.t";\nfn b() -> usize { let k = Caja { n: 1 }; return k.n; }',
            "app.t": 'usar "b.t";\nfn main() {\n    let k = Caja { n: 2 };\n    imprimir(k.n);\n}',
        }, "app.t"),
        ("sin pedir un enum", {
            "c.t": 'enum Color { Rojo, Verde }',
            "b.t": 'usar "c.t";\nfn b() -> usize { let k = Color.Rojo; return 1; }',
            "app.t": 'usar "b.t";\nfn main() {\n    let k = Color.Verde;\n    imprimir(b());\n}',
        }, "app.t"),
        ("local con nombre de fuera", {
            "c.t": 'fn tres() -> usize { return 3; }',
            "b.t": 'usar "c.t";\nfn b() -> usize { return tres(); }',
            "app.t": ('usar "b.t";\nfn main() {\n'
                      '    let f = fn(x: usize) -> usize { return x; };\n    imprimir(b());\n}'),
        }, "app.t"),
        ("dos usar del mismo", {
            "x.t": 'fn uno() -> usize { return 1; }',
            "app.t": ('usar "x.t";\nusar "x.t" como otra;\n'
                      'fn main() { imprimir(uno() + otra.uno()); }'),
        }, "app.t"),
        ("rombo con choque", {
            "x.t": 'fn f() -> usize { return 1; }',
            "lib/x.t": 'fn f() -> usize { return 2; }',
            "app.t": 'usar "x.t";\nusar "lib/x.t";\nfn main() { imprimir(f()); }',
        }, "app.t"),
    ]

    # Un programa para cada aviso, y los casos raros: `_x`, lo que atrapa un
    # `match`, las variables de un `for`, una clausura y una generica con dos
    # copias, que avisa una vez.
    _AVISOS_TCODEC = [r"""fn f(x: usize, y: usize, _z: usize) -> usize { return x; }
fn g(s: mut str) -> usize { return largo(vista(s)); }
fn h(s: mut str) { empujar(s, "!"); }
fn main() {
    let a = 1;
    var b: usize = 2;
    var c: usize = 3;
    c = 4;
    var d: usize = 5;
    imprimir($"{b}\n");
    var t = nuevo("x");
    h(t);
    let _u = 9;
    imprimir($"{f(1, 2, 3)} {g(t)} {d}\n");
}
""", r"""enum Forma { Punto, Circulo(f64), Texto(str) }
fn area(f: &Forma) -> f64 {
    return match f {
        Forma.Punto -> 0.0,
        Forma.Circulo(r) -> 3.0,
        Forma.Texto(s) -> 1.0,
    };
}
fn main() {
    let x: f64 = 1.5;
    let y = x como f64;
    if x == 1.5 { imprimir("igual\n"); }
    var ns: lista<usize> = [];
    anadir(ns, 1);
    for n en ns { imprimir("v\n"); }
    let k = fn(q: usize, w: usize) -> usize { let sin = 1; return q; };
    imprimir($"{area(Forma.Punto)} {y} {k(1, 2)}\n");
}
""", r"""fn primero<T>(xs: &lista<T>, n: usize) -> usize {
    let nada = 0;
    var v: usize = 1;
    return largo(xs);
}
fn main() {
    var a: lista<usize> = [];
    var b: lista<str> = [];
    anadir(b, nuevo("x"));
    imprimir($"{primero(a, 1)} {primero(b, 2)}\n");
}
"""]

    _MINIMO_PROGRAMAS = 25
    # Rechazos cuyo primer error dice `tcodec` igual que Python: todos, tambien
    # los de sintaxis, que dan el lexer y el parser escritos en Tcode.
    _MINIMO_RECHAZOS = 157
    # Mutaciones por archivo para comparar los errores de sintaxis: se rompe un
    # token de cada archivo del repositorio de varias formas, siempre las mismas.
    _MUTACIONES_POR_ARCHIVO = 5

    tmp = tempfile.mkdtemp(prefix="tcode-programa-")
    _cwd_antes = os.getcwd()
    _fondo = None
    try:
        os.chdir(RAIZ)
        # El mismo `tcodec` que prueban las demas secciones.
        suite.total += 1
        try:
            binario, no_se_construye = tcodec(), None
        except RuntimeError as exc:
            binario, no_se_construye = None, str(exc)
        if no_se_construye:
            suite.falla("tcodec en Tcode", no_se_construye)
        else:
            # Desde la raiz y con la raiz relativa, como el compilador de
            # Python: los mensajes y los `#line` son relativos a ella.
            entorno = dict(os.environ, TCODE_RAIZ=".")

            # El punto fijo, al final de la seccion, son pasos largos y en
            # fila: `tcodec` con los sanitizers escribiendo su propio C, y
            # construyendose a si mismo. Empiezan ya, en otros dos hilos,
            # mientras corre todo lo demas.
            propio = os.path.join("ejemplos", "compilador", "tcodec.t")

            def _punto_fijo():
                e1 = subprocess.run([binario, propio, "--mostrar-c"],
                                    capture_output=True, text=True,
                                    timeout=600, env=entorno)
                r2 = e2 = None
                if e1.returncode == 0 and "Sanitizer" not in e1.stderr:
                    ruta_c2 = os.path.join(tmp, "etapa2.c")
                    binario2 = os.path.join(tmp, "etapa2")
                    with open(ruta_c2, "w", encoding="utf-8") as f:
                        f.write(e1.stdout)
                    r2 = herramienta(
                        ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra",
                         "-Werror", "-fsanitize=address,undefined",
                         "-fno-omit-frame-pointer", f"-I{RUNTIME}", ruta_c2,
                         os.path.join(RUNTIME, "safestr.c"), SISTEMA_TCODEC,
                         "-o", binario2, "-lm"],
                        capture_output=True, text=True)
                    if r2.returncode == 0:
                        e2 = subprocess.run([binario2, propio, "--mostrar-c"],
                                            capture_output=True, text=True,
                                            timeout=600, env=entorno)
                return e1, r2, e2

            def _se_construye():
                binario3 = os.path.join(tmp, "etapa3")
                e3 = subprocess.run([binario, propio, "-o", binario3],
                                    capture_output=True, text=True,
                                    timeout=900, env=entorno)
                e4 = (subprocess.run([binario3, propio, "--mostrar-c"],
                                     capture_output=True, text=True,
                                     timeout=600, env=entorno)
                      if e3.returncode == 0 else None)
                return e3, e4

            _fondo = concurrent.futures.ThreadPoolExecutor(2)
            _punto_fijo_f = _fondo.submit(_punto_fijo)
            _se_construye_f = _fondo.submit(_se_construye)

            suite.total += 1
            literal_invalido = os.path.join(tmp, "literal-invalido.t")
            with open(literal_invalido, "w", encoding="utf-8") as f:
                f.write('fn main() { let x: u8 = 256; imprimir(x); }\n')
            e = subprocess.run([binario, literal_invalido, "--mostrar-c"], capture_output=True,
                               text=True, timeout=60, env=entorno)
            if e.returncode == 0 or e.stdout:
                suite.falla("tcodec rechaza literales enteros fuera de rango",
                            f"codigo {e.returncode}, genero {len(e.stdout)} bytes")

            suite.total += 1
            decimal_invalido = os.path.join(tmp, "decimal-invalido.t")
            with open(decimal_invalido, "w", encoding="utf-8") as f:
                f.write('fn main() { let x: f64 = 1e309; imprimir(x); }\n')
            e = subprocess.run([binario, decimal_invalido, "--mostrar-c"], capture_output=True,
                               text=True, timeout=60, env=entorno)
            if e.returncode == 0 or e.stdout:
                suite.falla("tcodec rechaza literales decimales infinitos",
                            f"codigo {e.returncode}, genero {len(e.stdout)} bytes")

            suite.total += 1
            inexacto = os.path.join(tmp, "entero-inexacto.t")
            with open(inexacto, "w", encoding="utf-8") as f:
                f.write('fn main() { let x: f64 = 9007199254740993; '
                        'imprimir(x); }\n')
            e = subprocess.run([binario, inexacto, "--mostrar-c"], capture_output=True,
                               text=True, timeout=60, env=entorno)
            if e.returncode == 0 or e.stdout:
                suite.falla("tcodec rechaza enteros que un decimal redondearia",
                            f"codigo {e.returncode}, genero {len(e.stdout)} bytes")

            suite.total += 1
            literal_valido = os.path.join(tmp, "literal-valido.t")
            with open(literal_valido, "w", encoding="utf-8") as f:
                f.write('fn main() { let a: i8 = -128; '
                        'let b: u64 = 18446744073709551615; '
                        'let c: f32 = 3.4028234e38; '
                        'let d: f64 = 1.7976931348623157e308; '
                        'let g: f32 = 3.4028235e38; '
                        'let h: usize = 5000000000; let k = 010; '
                        'let m: i8 = -0128; '
                        'imprimir($"{a} {b} {c} {d} {g} {h} {k} {m}\\n"); }\n')
            esperado_literal, errores_literal = compilar_archivo(literal_valido)
            e = subprocess.run([binario, literal_valido, "--mostrar-c"], capture_output=True,
                               text=True, timeout=60, env=entorno)
            if errores_literal or e.returncode != 0 or e.stdout != esperado_literal:
                suite.falla("tcodec conserva los limites enteros validos",
                            f"errores {errores_literal}, codigo {e.returncode}, "
                            f"stderr {e.stderr[:300]!r}")

            # Clausuras con y sin capturas, una dentro de otra, guardadas en
            # una variable, pasadas a una generica, y punteros a funcion,
            # tambien uno que recibe otro. Nada de eso lo pide un programa del
            # repositorio salvo lo de `pruebas.t`.
            escritos_c = []
            for nombre_c, fuente_c in (("cierres.t", _CIERRES_TCODEC),
                                       ("anidado.t", _FN_ANIDADA_TCODEC),
                                       ("precedencia.t", _PRECEDENCIA_TCODEC),
                                       ("generica.t", _CIERRE_EN_GENERICA_TCODEC),
                                       ("captura.t", _CAPTURA_CON_DUENIO_TCODEC),
                                       ("escribe.t", _ESCRIBIR_ARCHIVO_TCODEC),
                                       ("llave.t", _LLAVE_ESCRITA_TCODEC),
                                       ("modifica.t", _CIERRE_QUE_MODIFICA_TCODEC),
                                       ("patrones.t", _PATRONES_TCODEC),
                                       ("sacado.t", _CAMPO_SACADO_TCODEC),
                                       ("sacado2.t", _CAMPO_SACADO_RETORNO_TCODEC),
                                       ("prestado.t", _STRUCT_PRESTADO_TCODEC),
                                       ("corto.t", _CORTOCIRCUITO_TCODEC),
                                       ("enum_st.t", _ENUM_CON_STRUCT_TCODEC),
                                       ("orden.t", _ORDEN_TCODEC),
                                       ("copias.t", _COPIAS_ANIDADAS_TCODEC),
                                       ("entregado.t", _STR_ENTREGADO_TCODEC),
                                       ("inicial.t", _SU_INICIALIZADOR_TCODEC)):
                ruta_cierre = os.path.join(tmp, nombre_c)
                with open(ruta_cierre, "w", encoding="utf-8") as f:
                    f.write(fuente_c)
                escritos_c.append((nombre_c, ruta_cierre))
            trabajos_c = [(n, r, *hecho) for (n, r), hecho in zip(
                escritos_c, en_procesos(_c_python, [r for _, r in escritos_c]))]

            # Lo que cuesta de aqui en adelante es `tcodec`, con los
            # sanitizers puestos: cada bucle calcula antes lo de Python y
            # despues le pide a `tcodec` todo a la vez.
            def _tcodec(*args, timeout=120):
                return subprocess.run([binario, *args], capture_output=True,
                                      text=True, timeout=timeout, env=entorno)

            for (nombre_c, _, esperado_c, errores_c), e in zip(
                    trabajos_c, en_paralelo(lambda t: _tcodec(t[1], "--mostrar-c"),
                                            trabajos_c)):
                suite.total += 1
                if errores_c or e.returncode != 0 or e.stdout != esperado_c:
                    suite.falla(f"tcodec escribe {nombre_c}",
                                f"errores {errores_c}, codigo {e.returncode}, "
                                f"stderr {e.stderr[:300]!r}")

            # El comprobador en Tcode: lo que Python rechaza, tcodec tambien, y
            # con el mismo primer error; lo que Python acepta, tcodec no lo
            # rechaza nunca por una regla del lenguaje.
            def _errores_tcodec(ruta):
                r = subprocess.run([binario, ruta, "--solo-comprobar"],
                                   capture_output=True, text=True, timeout=120,
                                   env=entorno)
                return r.returncode, bloques(r.stderr, "error: "), r.stderr

            mismos = rechazados = 0
            escritos_r = []
            for i, (nombre, fuente, _esperado) in enumerate(RECHAZO):
                ruta_r = os.path.join(tmp, f"rechazo-{i}.t")
                with open(ruta_r, "w", encoding="utf-8") as f:
                    f.write(fuente)
                escritos_r.append((nombre, ruta_r))
            trabajos_r = [(nombre, ruta_r, de_python)
                          for (nombre, ruta_r), de_python in zip(
                              escritos_r, en_procesos(_errores_python,
                                                      [r for _, r in escritos_r]))
                          if de_python]
            for (nombre, _, de_python), (rc, de_tcodec, _crudo) in zip(
                    trabajos_r, en_paralelo(lambda t: _errores_tcodec(t[1]),
                                            trabajos_r)):
                rechazados += 1
                suite.total += 1
                if rc == 0:
                    suite.falla("el comprobador en Tcode rechaza lo que Python rechaza",
                                f"{nombre}: tcodec lo acepto; Python dice "
                                f"{de_python[0][:200]!r}")
                elif de_tcodec and de_tcodec[0] == de_python[0]:
                    mismos += 1
            suite.total += 1
            if mismos < _MINIMO_RECHAZOS:
                suite.falla("el comprobador en Tcode da los mismos errores",
                            f"solo {mismos} de {rechazados} con el mismo primer "
                            f"error; se esperaban al menos {_MINIMO_RECHAZOS}")

            correctos = 0
            aceptables = [(n, f) for n, f, *_ in ACEPTA]
            for archivo in sorted(glob.glob(os.path.join("std", "*.t"))
                                  + glob.glob(os.path.join("ejemplos", "**", "*.t"),
                                              recursive=True)):
                with open(archivo, encoding="utf-8") as f:
                    aceptables.append((archivo, f.read()))
            escritos_a = []
            for i, (nombre, fuente) in enumerate(aceptables):
                ruta_a = (nombre if os.path.exists(nombre)
                          else os.path.join(tmp, f"acepta-{i}.t"))
                if not os.path.exists(nombre):
                    with open(ruta_a, "w", encoding="utf-8") as f:
                        f.write(fuente)
                escritos_a.append((nombre, ruta_a))
            trabajos_a = [t for t, de_python in zip(
                escritos_a, en_procesos(_errores_python, [r for _, r in escritos_a]))
                          if not de_python]
            for (nombre, _), (_rc, de_tcodec, _crudo) in zip(
                    trabajos_a, en_paralelo(lambda t: _errores_tcodec(t[1]),
                                            trabajos_a)):
                correctos += 1
                suite.total += 1
                if de_tcodec:
                    suite.falla("el comprobador en Tcode no rechaza programas correctos",
                                f"{nombre}: {de_tcodec[0][:300]}")
            suite.cifra("rechazos_iguales", mismos)
            suite.cifra("rechazos", rechazados)
            suite.cifra("correctos", correctos)
            print(f"    comprobador: {mismos} de {rechazados} rechazos con el "
                  f"mismo primer error, y ninguno de {correctos} programas "
                  f"correctos rechazado")

            # Los errores de sintaxis, sobre el codigo real: cada archivo del
            # repositorio roto de varias formas —un token de menos, de mas,
            # un simbolo fuera de sitio, una cadena sin cerrar, un caracter
            # que no existe— y el primer error tiene que ser el mismo. Los
            # mutantes van junto al original para que sus `usar` sigan
            # valiendo, y se borran siempre.
            import random as _random

            from tcode.lexer import tokenizar as _tokenizar

            def _mutantes(fuente, semilla):
                rnd = _random.Random(semilla)
                lineas = fuente.split("\n")
                toks = [t for t in _tokenizar(fuente, "x") if t.tipo != "fin"]
                for _ in range(_MUTACIONES_POR_ARCHIVO):
                    t = rnd.choice(toks)
                    li = lineas[t.linea - 1]
                    c = t.col - 1
                    literal = t.tipo in ("cadena", "interpolada")
                    forma = rnd.choice(["borra", "dup", "punto", "paren", "llave",
                                        "arroba", "comilla", "cero", "fn"])
                    if literal:
                        forma = rnd.choice(["punto", "paren", "arroba", "comilla"])
                    n = len(t.valor)
                    if forma == "borra":
                        nueva = li[:c] + li[c + n:]
                    elif forma == "dup":
                        nueva = li[:c] + li[c:c + n] + " " + li[c:]
                    else:
                        # Lo que se mete delante del token.
                        nueva = li[:c] + {"punto": ";", "paren": ")", "llave": "{",
                                          "arroba": "@", "comilla": '"', "cero": "0x",
                                          "fn": "fn "}[forma] + li[c:]
                    otras = list(lineas)
                    otras[t.linea - 1] = nueva
                    yield f"{forma} en la linea {t.linea}", "\n".join(otras), nueva

            # Cada mutante con su nombre, para que esten todos a la vez
            # mientras `tcodec` los lee.
            iguales_s = rotos = 0
            mutantes = []
            escritos_m = []
            fuentes_m = sorted(glob.glob(os.path.join("std", "*.t"))
                               + glob.glob(os.path.join("ejemplos", "**", "*.t"),
                                           recursive=True))
            enums = set()
            for archivo in fuentes_m:
                with open(archivo, encoding="utf-8") as f:
                    enums.update(re.findall(r"\benum\s+(\w+)", f.read()))
            try:
                for archivo in fuentes_m:
                    with open(archivo, encoding="utf-8") as f:
                        fuente_o = f.read()
                    for k_m, (que, fuente_m, linea_m) in enumerate(
                            _mutantes(fuente_o, archivo)):
                        if _sintaxis_nueva(linea_m, enums):
                            continue
                        ruta_m = os.path.join(os.path.dirname(archivo),
                                              f".mut_{k_m}_" + os.path.basename(archivo))
                        escritos_m.append(ruta_m)
                        with open(ruta_m, "w", encoding="utf-8") as f:
                            f.write(fuente_m)
                        mutantes.append((archivo, que, ruta_m))
                trabajos_m = [(archivo, que, ruta_m, de_python)
                              for (archivo, que, ruta_m), de_python in zip(
                                  mutantes, en_procesos(
                                      _errores_python, [t[2] for t in mutantes]))
                              if de_python]
                for (archivo, que, _, de_python), (_rc, de_tcodec, crudo) in zip(
                        trabajos_m, en_paralelo(lambda t: _errores_tcodec(t[2]),
                                                trabajos_m)):
                    rotos += 1
                    suite.total += 1
                    if de_tcodec and de_tcodec[0] == de_python[0]:
                        iguales_s += 1
                    else:
                        suite.falla("los errores de sintaxis en Tcode",
                                    f"{archivo}, {que}:\n"
                                    f"  Python: {de_python[0][:300]!r}\n"
                                    f"  Tcode:  {(de_tcodec[:1] or [crudo[:300]])[0]!r}")
            finally:
                for ruta_m in escritos_m:
                    if os.path.exists(ruta_m):
                        os.remove(ruta_m)
            suite.cifra("rotos_iguales", iguales_s)
            suite.cifra("rotos", rotos)
            print(f"    sintaxis: {iguales_s} de {rotos} programas rotos, mismo "
                  f"primer error que el lexer y el parser de Python")

            # Las herramientas de alrededor, contra las de Python: los errores
            # de modulos, los avisos, el formato y `--explicar`.
            mods_iguales = mods_total = 0
            trabajos_mo = []
            for nombre_m, archivos_m, principal_m, *_ in (
                    list(MODULOS) + [(n, a, p) for n, a, p in _MODULOS_EXTRA_TCODEC]):
                dir_m = tempfile.mkdtemp(dir=tmp)
                for r_m, t_m in archivos_m.items():
                    d_m = os.path.join(dir_m, r_m)
                    os.makedirs(os.path.dirname(d_m), exist_ok=True)
                    with open(d_m, "w", encoding="utf-8") as f:
                        f.write(t_m)
                ruta_m = os.path.join(dir_m, principal_m)
                trabajos_mo.append((nombre_m, ruta_m, _errores_python(ruta_m)))
            for (nombre_m, _, de_python), r_m in zip(
                    trabajos_mo, en_paralelo(lambda t: _tcodec(t[1], "--solo-comprobar"),
                                             trabajos_mo)):
                de_tcodec = bloques(r_m.stderr, "error: ")
                suite.total += 1
                mods_total += 1
                if (de_python[:1] == de_tcodec[:1]
                        and (r_m.returncode == 0) == (not de_python)):
                    mods_iguales += 1
                else:
                    suite.falla("los errores de modulos en Tcode",
                                f"{nombre_m}:\n  Python: {de_python[:1]!r}\n"
                                f"  Tcode:  {de_tcodec[:1] or r_m.stderr[:200]!r}")

            aceptados_rutas = []
            for i_a, (_, f_a, *_ ) in enumerate(ACEPTA):
                r_a = os.path.join(tmp, f"acepta-h-{i_a}.t")
                with open(r_a, "w", encoding="utf-8") as f:
                    f.write(f_a)
                aceptados_rutas.append(r_a)
            for i_a, f_a in enumerate(_AVISOS_TCODEC):
                r_a = os.path.join(tmp, f"avisos-{i_a}.t")
                with open(r_a, "w", encoding="utf-8") as f:
                    f.write(f_a)
                aceptados_rutas.append(r_a)
            del_repo = sorted(glob.glob(os.path.join("std", "*.t"))
                              + glob.glob(os.path.join("ejemplos", "**", "*.t"),
                                          recursive=True))
            av_iguales = av_cuantos = 0
            ex_iguales = 0
            trabajos_av = [(ruta_a, esperados) for ruta_a, esperados in zip(
                del_repo + aceptados_rutas,
                en_procesos(_avisos_python, del_repo + aceptados_rutas))
                           if esperados is not None]

            # Los tres son otros procesos: el `--explicar` de Python
            # tambien, porque es lo que ve quien lo usa.
            def _avisos_y_explicar(trabajo):
                ruta_a = trabajo[0]
                return (_tcodec(ruta_a, "--solo-comprobar"),
                        subprocess.run([sys.executable, "-m", "tcode", ruta_a,
                                        "--explicar", "--sin-avisos"],
                                       capture_output=True, text=True, timeout=120),
                        _tcodec(ruta_a, "--explicar", "--sin-avisos"))

            for (ruta_a, esperados), (r_a, py_e, tc_e) in zip(
                    trabajos_av, en_paralelo(_avisos_y_explicar, trabajos_av)):
                suite.total += 1
                dados_a = bloques(r_a.stderr, "aviso: ")
                av_cuantos += len(esperados)
                if dados_a == esperados:
                    av_iguales += 1
                else:
                    suite.falla("los avisos en Tcode",
                                f"{ruta_a}:\n  Python: {esperados[:3]!r}\n"
                                f"  Tcode:  {dados_a[:3]!r}")
                suite.total += 1
                if py_e.stdout == tc_e.stdout:
                    ex_iguales += 1
                else:
                    a_e, b_e = py_e.stdout.splitlines(), tc_e.stdout.splitlines()
                    d_e = next((i for i, (x, y) in enumerate(zip(a_e, b_e)) if x != y),
                               min(len(a_e), len(b_e)))
                    suite.falla("--explicar en Tcode",
                                f"{ruta_a}, linea {d_e + 1}:\n"
                                f"  Python: {a_e[d_e] if d_e < len(a_e) else '(fin)'!r}\n"
                                f"  Tcode:  {b_e[d_e] if d_e < len(b_e) else '(fin)'!r}")

            from tcode.formato import formatear as _formatear
            fm_iguales = fm_total = 0
            trabajos_f: list[tuple[str, int, str, str]] = []
            for archivo_f in del_repo:
                with open(archivo_f, encoding="utf-8") as f:
                    original_f = f.read()
                rnd_f = _random.Random(archivo_f)
                deformado = []
                for li in original_f.split("\n"):
                    x = rnd_f.random()
                    if x < 0.3:
                        li = li.lstrip()
                    elif x < 0.4:
                        li = "  " + li
                    if rnd_f.random() < 0.2:
                        li += "   "
                    deformado.append(li)
                    if rnd_f.random() < 0.05:
                        deformado.extend(["", "", ""])
                for k_f, fuente_f in enumerate((original_f, "\n".join(deformado))):
                    ruta_f = os.path.join(tmp, f"formato-{len(trabajos_f)}.t")
                    with open(ruta_f, "w", encoding="utf-8") as f:
                        f.write(fuente_f)
                    trabajos_f.append((archivo_f, k_f, ruta_f,
                                       _formatear(fuente_f, ruta_f)))
            for (archivo_f, k_f, _, esperado_f), r_f in zip(
                    trabajos_f, en_paralelo(lambda t: _tcodec(t[2], "--formatear"),
                                            trabajos_f)):
                suite.total += 1
                fm_total += 1
                if r_f.returncode == 0 and r_f.stdout == esperado_f:
                    fm_iguales += 1
                else:
                    suite.falla("--formatear en Tcode",
                                f"{archivo_f} ({'deformado' if k_f else 'tal cual'})")
            print(f"    herramientas: {mods_iguales} de {mods_total} casos de "
                  f"modulos, avisos iguales en {av_iguales} programas "
                  f"({av_cuantos} avisos), --explicar igual en {ex_iguales}, "
                  f"--formatear igual en {fm_iguales} de {fm_total}")

            iguales = intentados = 0
            con_main = []
            for archivo in sorted(
                    glob.glob(os.path.join("std", "*.t"))
                    + glob.glob(os.path.join("ejemplos", "**", "*.t"),
                                recursive=True)):
                with open(archivo, encoding="utf-8") as f:
                    if "fn main(" in f.read():
                        con_main.append(archivo)
            trabajos_e = [(archivo, esperado) for archivo, (esperado, errores_f) in zip(
                con_main, en_procesos(_c_python, con_main)) if not errores_f]
            for (archivo, esperado), e in zip(
                    trabajos_e, en_paralelo(
                        lambda t: _tcodec(t[0], "--mostrar-c", timeout=180),
                        trabajos_e)):
                if "Sanitizer" in e.stderr:
                    suite.total += 1
                    suite.falla("tcodec en Tcode", f"{archivo}: sanitizer\n"
                                            f"{e.stderr[:400]}")
                    continue
                intentados += 1
                suite.total += 1
                if e.returncode != 0:
                    # Lo que Python compila, `tcodec` lo escribe entero.
                    suite.falla("tcodec en Tcode",
                                f"{archivo}: lo rechazo\n{e.stderr[:400]}")
                elif e.stdout != esperado:
                    dado, bueno = e.stdout.splitlines(), esperado.splitlines()
                    n = next((i for i, (x, y) in enumerate(zip(dado, bueno))
                              if x != y), min(len(dado), len(bueno)))
                    suite.falla("tcodec en Tcode",
                                f"{archivo}, linea {n + 1}:\n"
                                f"  Tcode:  {dado[n] if n < len(dado) else '(fin)'!r}\n"
                                f"  Python: {bueno[n] if n < len(bueno) else '(fin)'!r}")
                else:
                    iguales += 1
            if iguales < _MINIMO_PROGRAMAS:
                suite.total += 1
                suite.falla("tcodec en Tcode",
                            f"solo {iguales} programas enteros, se esperaban al "
                            f"menos {_MINIMO_PROGRAMAS}")
            suite.cifra("programas_enteros", iguales)
            print(f"    {iguales} programas enteros, mismo C que el generador "
                  f"de Python ({intentados} intentados)")

            # Y cada programa de la suite que Python compila: los que
            # corren, los que abortan y los que avisan. Son los que cubren
            # el lenguaje construccion a construccion, asi que aqui se ve
            # si a `tcodec` le falta alguna.
            escritos_s = []
            for lista_s, casos_s in (("ACEPTA", ACEPTA), ("ABORTA", ABORTA),
                                     ("AVISA", AVISA)):
                for i_s, caso_s in enumerate(casos_s):
                    dir_s = os.path.join(tmp, f"suite_{lista_s}_{i_s}")
                    os.makedirs(dir_s)
                    ruta_s = os.path.join(dir_s, "p.t")
                    with open(ruta_s, "w", encoding="utf-8") as f:
                        f.write(caso_s[1])
                    escritos_s.append((caso_s[0], ruta_s))
            trabajos_s = [(nombre_s, ruta_s, esperado_s)
                          for (nombre_s, ruta_s), (esperado_s, errores_s) in zip(
                              escritos_s, en_procesos(_c_python,
                                                      [r for _, r in escritos_s]))
                          if not errores_s]

            def _tcodec_escribe(trabajo):
                return subprocess.run([binario, trabajo[1], "--mostrar-c"],
                                      capture_output=True, text=True,
                                      timeout=180, env=entorno)

            iguales_s = 0
            for (nombre_s, _, esperado_s), e in zip(
                    trabajos_s, en_paralelo(_tcodec_escribe, trabajos_s)):
                suite.total += 1
                if e.returncode != 0:
                    suite.falla("tcodec escribe los programas de la suite",
                                f"{nombre_s}: lo rechazo\n{e.stderr[-400:]}")
                elif e.stdout != esperado_s:
                    dado, bueno = e.stdout.splitlines(), esperado_s.splitlines()
                    n = next((i for i, (x, y) in enumerate(zip(dado, bueno))
                              if x != y), min(len(dado), len(bueno)))
                    suite.falla("tcodec escribe los programas de la suite",
                                f"{nombre_s}, linea {n + 1}:\n"
                                f"  Tcode:  {dado[n] if n < len(dado) else '(fin)'!r}\n"
                                f"  Python: {bueno[n] if n < len(bueno) else '(fin)'!r}")
                else:
                    iguales_s += 1
            suite.cifra("programas_suite", iguales_s)
            print(f"    {iguales_s} de {len(trabajos_s)} programas de la suite, "
                  f"mismo C que el generador de Python")

            # Un nombre que declaran dos modulos, y uno usa al otro: `B.hecho`
            # es el de `b.t` aunque el ultimo `hecho` visto sea el de `a.t`.
            # `tcodec` los tipaba por el nombre a secas.
            suite.total += 1
            dir_r = os.path.join(tmp, "repetida")
            os.makedirs(os.path.join(dir_r, "lib"))
            for nombre_r, fuente_r in (
                    ("lib/b.t", 'fn hecho(t: view) -> str { return nuevo(t); }\n'),
                    ("lib/a.t", 'usar "b.t" como B;\n'
                                'struct Cosa { n: usize }\n'
                                'fn hecho(n: usize) -> Cosa { return Cosa { n: n }; }\n'
                                'fn usa_a() -> usize { let c = hecho(3); '
                                'let _s = B.hecho("x"); return c.n; }\n'),
                    ("main.t", 'usar "lib/b.t" como B;\nusar "lib/a.t" como A;\n'
                               'fn main() {\n    let d = B.hecho("hola");\n'
                               '    imprimir($"{d} {A.usa_a()}\\n");\n}\n')):
                with open(os.path.join(dir_r, nombre_r), "w", encoding="utf-8") as f:
                    f.write(fuente_r)
            principal_r = os.path.join(dir_r, "main.t")
            esperado_r, errores_r = compilar_archivo(principal_r)
            e = subprocess.run([binario, principal_r, "--mostrar-c"],
                               capture_output=True, text=True, timeout=180,
                               env=entorno)
            if errores_r or e.returncode != 0 or e.stdout != esperado_r:
                suite.falla("tcodec escribe una funcion repetida entre modulos",
                            f"{errores_r[:1]} {e.stderr[-300:]!r}")

            # `tcodec` tambien hace el ultimo paso: llama al compilador de C,
            # enlaza lo que piden los `externo`, y deja el binario.
            suite.total += 1
            bin_hola = os.path.join(tmp, "hola")
            e = subprocess.run([binario, os.path.join("ejemplos", "hola.t"),
                                "-o", bin_hola], capture_output=True, text=True,
                               timeout=180, env=entorno)
            r_h = (subprocess.run([bin_hola], capture_output=True, text=True,
                                  timeout=60) if e.returncode == 0 else None)
            if e.returncode != 0 or r_h is None or r_h.stdout != "Hola, mundo!\n12 bytes\n":
                suite.falla("tcodec compila y enlaza un programa",
                            f"codigo {e.returncode}, stderr {e.stderr[:300]!r}")

            suite.total += 1
            bin_reloj = os.path.join(tmp, "reloj")
            e = subprocess.run([binario, os.path.join("ejemplos", "externo", "reloj.t"),
                                "-o", bin_reloj], capture_output=True, text=True,
                               timeout=180, env=entorno)
            r_r = (subprocess.run([bin_reloj], capture_output=True, text=True,
                                  timeout=60) if e.returncode == 0 else None)
            if e.returncode != 0 or r_r is None or r_r.returncode != 0:
                suite.falla("tcodec enlaza el `.c` de un `externo`",
                            f"codigo {e.returncode}, stderr {e.stderr[:300]!r}")

            # La salida nunca es el fuente ni un `.t`, y un fallo del
            # compilador de C deja el binario anterior como estaba.
            suite.total += 1
            fuente_s = os.path.join(tmp, "prog.t")
            shutil.copy(os.path.join("ejemplos", "hola.t"), fuente_s)
            antes_s = open(fuente_s, encoding="utf-8").read()
            e1s = subprocess.run([binario, fuente_s, "-o", fuente_s],
                                 capture_output=True, text=True, timeout=60, env=entorno)
            e2s = subprocess.run([binario, fuente_s, "-o", os.path.join(tmp, "x.t")],
                                 capture_output=True, text=True, timeout=60, env=entorno)
            viejo = os.path.join(tmp, "viejo")
            with open(viejo, "w", encoding="utf-8") as f:
                f.write("binario anterior")
            e3s = subprocess.run([binario, fuente_s, "--cc", "false", "-o", viejo],
                                 capture_output=True, text=True, timeout=60, env=entorno)
            if (e1s.returncode == 0 or "propio archivo fuente" not in e1s.stderr
                    or e2s.returncode == 0 or "parece un fuente" not in e2s.stderr
                    or e3s.returncode == 0
                    or open(viejo, encoding="utf-8").read() != "binario anterior"
                    or open(fuente_s, encoding="utf-8").read() != antes_s):
                suite.falla("tcodec protege el fuente y el binario anterior",
                            f"{e1s.stderr[:200]!r} {e2s.stderr[:200]!r} {e3s.stderr[:200]!r}")

            # El punto fijo. El `tcodec` que compilo Python escribe su propio
            # C; ese C, compilado, tiene que volver a escribir exactamente el
            # mismo. Es la prueba de que el compilador ya no depende de
            # Python para existir: a partir de aqui se puede construir desde
            # su propio C, como hacen Go desde 1.5 y Rust desde su primer
            # `rustc` en Rust.
            suite.total += 1
            e1, r2, e2 = _punto_fijo_f.result()
            if e1.returncode != 0 or "Sanitizer" in e1.stderr:
                suite.falla("punto fijo", f"tcodec no se escribe a si mismo:\n"
                                    f"{e1.stderr[:400]}")
            else:
                if r2.returncode != 0:
                    suite.falla("punto fijo", f"su propio C no compila:\n"
                                        f"{r2.stderr[:600]}")
                else:
                    if (e2.returncode != 0 or "Sanitizer" in e2.stderr
                            or e2.stdout != e1.stdout):
                        suite.falla("punto fijo", "la etapa 2 no reproduce el C "
                                            f"de la etapa 1\n{e2.stderr[:400]}")
                    else:
                        print(f"    punto fijo: tcodec compilado desde su "
                              f"propio C lo reproduce byte a byte "
                              f"({len(e1.stdout.encode())} bytes)")
                        # La semilla solo tiene que saber construir el
                        # `tcodec` de ahora; si ademas es su punto fijo, se dice.
                        with open(SEMILLA, encoding="utf-8") as f:
                            al_dia = f.read() == e1.stdout
                        print("    semilla: " + ("al dia, es este mismo C" if al_dia
                                                 else "de una version anterior; "
                                                      "`make semilla` la pone al dia"))
                        suite.cifra("punto_fijo_bytes", len(e1.stdout.encode()))
                        # Y sin nadie mas: `tcodec` se construye a si mismo,
                        # llamando el al compilador de C, y ese binario
                        # vuelve a escribir el mismo C.
                        suite.total += 1
                        e3, e4 = _se_construye_f.result()
                        if e4 is None or e4.returncode != 0 or e4.stdout != e1.stdout:
                            suite.falla("tcodec se construye a si mismo",
                                        f"{e3.stderr[:400]}")
                        else:
                            print("    tcodec se construye a si mismo sin "
                                  "Python, y reproduce su C")
    finally:
        if _fondo is not None:
            _fondo.shutdown(wait=True)
        os.chdir(_cwd_antes)
        shutil.rmtree(tmp, ignore_errors=True)
