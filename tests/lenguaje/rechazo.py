"""RECHAZO: programas que no deben compilar."""

import os
import tempfile

from .comun import (
    Resultado,
    bloques,
    en_paralelo,
    tcodec_sobre,
)

# Un struct que presta, y una funcion que saca su vista: la base de los casos
# de structs con un campo `view`.
_PALABRA = ("struct Palabra { texto: view, n: usize } "
            "fn texto_de(p: Palabra) -> view { return p.texto; } ")

# Un struct con campos que tienen duenio, para sacarlos de uno en uno.
_MEDIO = ("struct P { nombre: str, edad: usize, sub: Q } struct Q { t: str } "
          "fn toma(p: P) -> usize { return p.edad; } "
          "fn nuevo_p() -> P { return P { nombre: nuevo(\"a\"), edad: 1, "
          "sub: Q { t: nuevo(\"b\") } }; } ")

# Dos enums, uno dentro de otro, para los patrones.
_FORMAS = "enum E2 { A, B(i64) } enum E { X, Y(i64), Z(str, E2) } "

RECHAZO = [
    # Un sitio prestado con `let x: &T = ...` no se modifica ni se mueve
    # mientras `x` se use; por un `&T` no se modifica nada.
    ("modificar la lista de la que se presto un elemento",
     'struct N { s: str } fn main() { var l: lista<N> = []; '
     'anadir(l, N { s: nuevo("a") }); let x: &N = l[0]; '
     'anadir(l, N { s: nuevo("b") }); imprimir(largo(x.s)); }',
     "no se puede modificar `l`: esta prestada por `x`"),
    ("mover lo que se presto",
     'struct N { s: str } fn main() { var p = N { s: nuevo("a") }; '
     'let x: &N = p; let q = p; imprimir(largo(x.s)); imprimir(largo(q.s)); }',
     "no se puede mover `p`: esta prestada por `x`"),
    ("modificar por un prestamo de solo lectura de un sitio",
     'struct N { s: str } fn main() { var p = N { s: nuevo("a") }; '
     'let x: &N = p; empujar(x.s, "z"); }',
     "`x` es un prestamo de solo lectura (`&N`)"),
    ("prestar para modificar algo declarado con `let`",
     'struct N { s: str } fn main() { let p = N { s: nuevo("a") }; '
     'let w: &mut N = p; empujar(w.s, "z"); }',
     "`p` se declaro con `let` y no se puede modificar"),
    ("sacar un elemento sugiere prestarlo",
     'struct N { s: str } fn main() { var l: lista<N> = []; '
     'anadir(l, N { s: nuevo("a") }); let x = l[0]; imprimir(largo(x.s)); }',
     "Si solo quieres leerlo, prestalo: `let x: &N = ...`"),

    # Un prestamo que ya se tiene se pasa a una funcion que presta; pero uno
    # de solo lectura no se pasa a una que modifica.
    ("pasar un `&T` a un parametro `mut`",
     'struct N { s: str } fn cambiar(x: mut N) { empujar(x.s, "!"); } '
     'fn main() -> usize ! { var m: mapa<str, N> = []; '
     'poner(m, "a", N { s: nuevo("a") }); let r = try obtener(m, "a"); '
     'cambiar(r); return 0; }',
     "`r` es un prestamo de solo lectura (`&N`): para modificar lo que apunta "
     "hace falta `&mut N`"),

    ("anadir por un prestamo de solo lectura",
     'fn main() -> usize ! { var m: mapa<str, lista<usize>> = []; '
     'poner(m, "a", [3]); let l: &lista<usize> = try obtener(m, "a"); '
     'anadir(l, 2); return 0; }',
     "`l` es un prestamo de solo lectura"),

    # Lo que no es un nombre (UAX #31) se nombra por su codigo. Antes tcodec
    # tomaba cualquier byte no ASCII por letra, y Python usaba `isalpha()`.
    ("un signo que no es una letra no es un nombre",
     'fn main() { let x = 2 \u00d7 3; }',
     "caracter inesperado U+00D7"),

    ("un espacio de ancho cero no es parte de un nombre",
     'fn main() { let a\u200bb = 1; }',
     "caracter inesperado U+200B"),

    ("un superindice no es un digito",
     'fn main() { let x = \u00b2; }',
     "caracter inesperado U+00B2"),

    ("un numero pegado a una letra no ASCII",
     'fn main() { let x = 1\u00f1; }',
     "numero mal formado cerca de '1\u00f1'"),

    # Un `.t` es UTF-8. Python se escapaba con un `UnicodeDecodeError`, y
    # tcodec tomaba el byte por una letra.
    ("un byte que no es UTF-8",
     b'fn main() {}\n\xff\n',
     "p.t:2: el archivo no es UTF-8 valido"),

    ("un sustituto escrito en UTF-8",
     b'fn main() {\n    let s = "\xed\xa0\x80";\n}\n',
     "p.t:2: el archivo no es UTF-8 valido"),

    # "Trojan Source": un control bidireccional hace que el codigo se vea
    # distinto de como se compila. No vale en ningun sitio. `tcodec` lo
    # aceptaba dentro de un nombre y lo pasaba al C; lo encontro
    # `tests/fuzz.py`.
    ("un control bidireccional en un nombre",
     'fn main() { let x\u202ey = 1; imprimir($"{x\u202ey}"); }',
     "control bidireccional U+202E"),

    ("un control bidireccional en una cadena",
     'fn main() {\n    imprimir("a\u2067b");\n}',
     ":2: control bidireccional U+2067"),

    # ---- la llamada con punto es una llamada: las mismas reglas ----
    ("con punto, lo de delante sigue siendo el primer argumento",
     'fn doble(n: usize) -> usize { return n * 2; }\n'
     'fn main() { let s = nuevo("a"); imprimir(s.doble()); }',
     "`n` de `doble` es `usize` y recibio `str`"),

    ("con punto, modificar pide `var`",
     'fn main() { let xs: lista<usize> = []; xs.anadir(1); }',
     "`xs` se declaro con `let` y no se puede modificar"),

    ("un texto no se compara con un numero",
     'fn main() { let s = nuevo("a"); imprimir(s == 1); }',
     "no se pueden comparar `str`"),

    # La vista implicita es `vista(...)`: presta, y el prestamo se vigila.
    ("una vista implicita presta",
     'fn main() { var s = nuevo("x"); let v: view = s; empujar(s, "y"); imprimir(v); }',
     "no se puede modificar `s`: esta prestada por `v`"),

    ("una vista implicita no sobrevive a su dueno",
     'fn main() { var v: view = "a"; if true { let s = nuevo("x"); v = s; } imprimir(v); }',
     "`v` vive mas que `s`"),

    ("no se devuelve la vista implicita de un local",
     'fn f() -> view { let s = nuevo("x"); return s; }\nfn main() { imprimir(f()); }',
     "no se puede devolver una vista de `s`"),

    ("un str sin nombre no se presta solo",
     'fn main() { let v: view = nuevo("x"); imprimir(v); }',
     "`v` se declaro `view` pero el valor es `str`"),

    # `==` compara lo que no tiene partes. Antes el C no compilaba.
    ("== no compara un enum con datos",
     'enum E { A(usize), B }\nfn main() { let x = E.B; let y = E.B; imprimir(x == y); }',
     "`==` compara enums sin datos, y alguna forma de `E` lleva algo: miralo con `match`"),

    ("== no compara un struct",
     'struct P { a: usize }\n'
     'fn main() { let x = P { a: 1 }; let y = P { a: 1 }; imprimir(x == y); }',
     "`==` no compara `P`, que tiene partes: compara las que te importen"),

    ("== no compara listas",
     'fn main() { let x: lista<usize> = []; let y: lista<usize> = []; imprimir(x != y); }',
     "`==` no compara `lista<usize>`, que tiene partes"),

    ("un rango va de un entero a otro",
     'fn main() { for i en 0.."a" { imprimir(i); } }',
     "un rango va de un entero a otro, y este va de un entero escrito a `view`"),

    ("los extremos de un rango son del mismo tipo",
     'fn main() { let a: u8 = 1; let b: i64 = 3; for i en a..b { imprimir(i); } }',
     "los dos extremos de un rango son del mismo tipo, y aqui son `u8` y `i64`"),

    ("un rango da un solo numero por vuelta",
     'fn main() { for i, j en 0..3 { imprimir(i); } }',
     "un rango da un numero en cada vuelta"),

    ("el numero de un rango no se cambia",
     'fn main() { for i en 0..3 { i = 2; } }',
     "`i` se declaro con `let` y no se puede modificar"),

    # ---- literales: el error es de Tcode, no una truncacion de C ----
    ("un entero no se recorta para caber en u8",
     'fn main() { let x: u8 = 256; imprimir(x); }',
     "no cabe en `u8`"),

    ("un entero positivo no cruza el maximo firmado",
     'fn main() { let x: i8 = 128; imprimir(x); }',
     "no cabe en `i8`"),

    ("un entero negativo no cruza el minimo firmado",
     'fn main() { let x: i8 = -129; imprimir(x); }',
     "no cabe en `i8`"),

    ("una operacion no esconde un literal fuera de rango",
     'fn main() { let x: u8 = 1 + 256; imprimir(x); }',
     "no cabe en `u8`"),

    # ---- cuentas de numeros escritos: se hacen al compilar ----
    ("dos literales se operan en el tipo que se espera, al compilar",
     'fn main() { let y: u8 = 200 + 100; imprimir(y); }',
     "`200 + 100` no cabe en `u8`: es una cuenta de numeros escritos, y se "
     "hace al compilar"),

    ("una cuenta escrita sin tipo es usize, y no baja de cero",
     'fn main() { let n = 1 - 2; imprimir(n); }',
     "`1 - 2` no cabe en `usize`"),

    ("una cuenta escrita divide por cero al compilar",
     'fn main() { let x: i32 = 7 / (3 - 3); imprimir(x); }',
     "`7 / 0` divide por cero"),

    ("una cuenta escrita no desplaza el ancho de su tipo",
     'fn main() { let x: u32 = 1 << 32; imprimir(x); }',
     "`1 << 32` desplaza un `u32` 32 bits, y tiene 32"),

    ("una cuenta escrita toma el tipo de lo que tiene al lado",
     'fn main() { let x: u8 = 3; imprimir(x + (250 + 10)); }',
     "`250 + 10` no cabe en `u8`"),

    ("la cuenta de dentro de un menos es del tipo del destino",
     'fn main() { let c: i8 = -(100 + 28); imprimir(c); }',
     "`100 + 28` no cabe en `i8`"),

    ("una rama escrita de un if se cuenta en su tipo",
     'fn main() { let n: usize = 2; let x: u8 = if n > 1 { 255 + 1 } else { 3 };'
     ' imprimir(x); }',
     "`255 + 1` no cabe en `u8`"),

    ("una cuenta escrita en lo que devuelve una funcion",
     'fn k() -> i16 { return 300 * 300; }\nfn main() { imprimir(k()); }',
     "`300 * 300` no cabe en `i16`"),

    ("la cuenta que para es la primera, de izquierda a derecha",
     'fn main() { imprimir((0 - 1) + (5 / 0)); }',
     "`0 - 1` no cabe en `usize`"),

    ("un entero mayor que u64 no llega a Python ni a C",
     'fn main() { let x = ' + ('9' * 5000) + '; imprimir(x); }',
     "no cabe en `u64`"),

    ("un decimal demasiado grande para f32 no se vuelve infinito",
     'fn main() { let x: f32 = 3.5e38; imprimir(x); }',
     "no cabe en `f32`"),

    ("un decimal demasiado grande para f64 no se vuelve infinito",
     'fn main() { let x: f64 = 1e309; imprimir(x); }',
     "no cabe en `f64`"),

    # El borde es donde C ya redondea a infinito, no el maximo escrito.
    ("un decimal que C redondearia a infinito en f32",
     'fn main() { let x: f32 = 3.4028236e38; imprimir(x); }',
     "no cabe en `f32`"),

    ("un decimal que C redondearia a infinito en f64",
     'fn main() { let x: f64 = 1.7976931348623159e308; imprimir(x); }',
     "no cabe en `f64`"),

    ("un entero escrito no pierde precision en un f64",
     'fn main() { let x: f64 = 9007199254740993; imprimir(x); }',
     "no cabe en `f64` sin perder precision"),

    ("un entero escrito no pierde precision en un f32",
     'fn main() { let x: f32 = 16777217; imprimir(x); }',
     "no cabe en `f32` sin perder precision"),

    # ---- el sistema ----
    ("el fin de la entrada es un fallo, no una cadena",
     'fn main() -> usize { let l = leer_linea(); return 0; }',
     "puede fallar"),

    ("una variable de entorno que no esta es un fallo",
     'fn main() -> usize { let v = variable_entorno("X"); return 0; }',
     "puede fallar"),

    # ---- el borde con C ----
    ("una vista no acaba en cero, y C leeria de mas",
     'externo "x.h" { fn f(s: view) -> usize; } fn main() { }',
     "puede apuntar a la mitad de una cadena"),

    ("una coleccion no significa lo mismo en C",
     'externo "x.h" { fn f(xs: lista<usize>) -> usize; } fn main() { }',
     "no significa lo mismo en C"),

    ("un struct tampoco",
     'struct P { x: usize } externo "x.h" { fn f(p: P) -> usize; }'
     ' fn main() { }',
     "no significa lo mismo en C"),

    ("C no puede fabricar un `str`",
     'externo "x.h" { fn f() -> str; } fn main() { }',
     "C no puede fabricar uno"),

    ("a C no se le presta, se le pasa por valor",
     'externo "x.h" { fn f(s: &str) -> usize; } fn main() { }',
     "no se prestan ni se mutan"),

    ("`cadena_c` solo vale en el borde",
     'fn f() -> cadena_c { return 0; } fn main() { }',
     "que no se puede almacenar"),

    # ---- enum y match ----
    ("a un `match` no le puede faltar una forma",
     'enum E { A, B(usize), C(str) } '
     'fn f(e: &E) -> usize { return match e { E.A -> 0, E.B(n) -> n, }; }'
     ' fn main() { }',
     "le faltan formas: `E.C`"),

    ("un brazo repetido no se ejecuta nunca",
     'enum E { A, B(usize), C(str) } '
     'fn f(e: &E) -> usize { return match e { E.A -> 0, E.A -> 1, _ -> 2, }; }'
     ' fn main() { }',
     "se mira dos veces"),

    ("detras del `_` no queda nada que mirar",
     'enum E { A, B(usize), C(str) } '
     'fn f(e: &E) -> usize { return match e { _ -> 0, E.A -> 1, }; }'
     ' fn main() { }',
     "detras del `_`"),

    ("no se puede mirar una forma que no existe",
     'enum E { A, B(usize), C(str) } '
     'fn f(e: &E) -> usize { return match e { E.Z -> 1, _ -> 0, }; }'
     ' fn main() { }',
     "no tiene la forma `Z`"),

    ("el patron atrapa lo que la forma lleva, ni mas ni menos",
     'enum E { A, B(usize), C(str) } '
     'fn f(e: &E) -> usize { return match e { E.A(x) -> x, _ -> 0, }; }'
     ' fn main() { }',
     "lleva 0 valores, y el patron atrapa 1"),

    ("cada alternativa declara sus propios nombres",
     'enum E { A(usize), B(usize) } '
     'fn f(e: &E) -> usize { return match e { E.A(n) | E.B(m) -> n, }; }'
     ' fn main() { }',
     "`n` no esta declarada"),

    ("construir una forma pide el tipo que lleva",
     'enum E { A, B(usize), C(str) } '
     'fn f() -> E { return E.B(nuevo("x")); } fn main() { }',
     "lleva un `usize` y se le dio un `str`"),

    ("un enum que se contiene a si mismo no tiene tamaño",
     'enum E { A, B(E) } fn main() { }',
     "el tamaño no seria finito"),

    ("`match` mira enums, no cualquier cosa",
     'enum E { A } fn f(n: usize) -> usize { return match n { E.A -> 0, }; }'
     ' fn main() { }',
     "y `usize` no es uno"),

    ("lo que atrapa un patron se presta, no se posee",
     'enum E { A, B(usize), C(str) } '
     'fn f(e: &E) -> str { return match e { E.C(s) -> s, _ -> nuevo(""), }; }'
     ' fn main() { }',
     "devuelve `str`"),

    ("una clausura no cabe en un puntero a funcion",
     'fn usar_fn(f: fn(usize) -> usize) -> usize { return f(1); }'
     ' fn main() -> usize { let n = 2;'
     ' let c = fn[n](x: usize) -> usize { return x + n; };'
     ' return usar_fn(c); }',
     "recibio una clausura"),

    ("una clausura no captura un prestamo",
     'fn f(v: view) -> usize { let g = fn[v](x: usize) -> usize { return x; };'
     ' return g(1); }',
     "una clausura captura por valor"),

    # ---- vistas que salen de una funcion: el que llama queda protegido ----
    ("una vista reasignada no sobrevive al bloque de su duenio",
     'fn main() { var v: view = "";'
     ' if true { let s = nuevo("hola"); v = vista(s); } imprimir(v); }',
     "`v` vive mas que `s`"),

    ("tampoco si la vista sale de una funcion",
     'fn f(s: &str) -> view { return vista(s); }'
     ' fn main() { var v: view = "";'
     ' if true { let s = nuevo("hola"); v = f(s); } imprimir(v); }',
     "`v` vive mas que `s`"),

    ("una vista reasignada presta de su duenio nuevo",
     'fn main() { var s = nuevo("a"); var v: view = ""; v = vista(s);'
     ' empujar(s, "z"); imprimir(v); }',
     "esta prestada por `v`"),

    ("una vista reasignada a algo local no sale de la funcion",
     'fn f() -> view { var v: view = "x"; let s = nuevo("hola");'
     ' v = vista(s); return v; } fn main() { imprimir(f()); }',
     "no se puede devolver una vista de `s`"),

    ("la vista que devuelve una funcion presta de todo lo que le prestaron",
     'fn f(a: &str, b: &str) -> view { return vista(b); }'
     ' fn main() { var a = nuevo("x"); var b = nuevo("y"); let v = f(a, b);'
     ' empujar(b, "z"); imprimir(v); }',
     "no se puede modificar `b`: esta prestada por `v`"),

    ("no se guarda una vista de un temporal prestado",
     'fn f(s: &str) -> view { return vista(s); }'
     ' fn main() { let v = f(nuevo("temporal")); imprimir(v); }',
     "apuntaria a un valor temporal"),

    ("ni la de un `str` recien hecho pasado como vista",
     'fn primero(x: view) -> view { return x; }'
     ' fn main() { let v = primero(nuevo("temporal")); imprimir(v); }',
     "apuntaria a un valor temporal"),

    # ---- una generica con restriccion vale para todo su conjunto ----
    ("el cuerpo de una generica se comprueba con todo lo que admite",
     'fn primera<T: igualable>(xs: &lista<T>) -> T { let t = xs[0]; return t; }'
     ' fn main() { var xs: lista<usize> = []; anadir(xs, 1);'
     ' imprimir(primera(xs)); }',
     "al comprobar `primera` con T = str: la restriccion lo admite"),

    ("tambien si nadie la usa",
     'fn mala<T: texto>(x: T) -> usize { return x + 1; }',
     "al comprobar `mala` con T = str"),

    ("un parametro sin restriccion se prueba con lo que se uso",
     'fn cuenta<T: ordenable, U>(x: T, u: U) -> U { let y = x;'
     ' imprimir(largo(y)); return u; }'
     ' fn main() { imprimir(cuenta("a", 3)); }',
     "con T = f32, U = usize"),

    # ---- structs con un campo `view`: prestan, como una vista ----
    ("un struct que presta no vive mas que su duenio",
     _PALABRA + 'fn main() { var p = Palabra { texto: "", n: 0 };'
     ' if true { let s = nuevo("x"); p = Palabra { texto: vista(s), n: 1 }; }'
     ' imprimir(p.texto); }',
     "`p` vive mas que `s`"),

    ("mientras vive, su duenio no se modifica",
     _PALABRA + 'fn main() { var s = nuevo("x"); let p = Palabra { texto: vista(s), n: 1 };'
     ' empujar(s, "y"); imprimir(p.texto); }',
     "no se puede modificar `s`: esta prestada por `p`"),

    ("no sale de la funcion si presta de algo local",
     _PALABRA + 'fn f() -> Palabra { let s = nuevo("x");'
     ' return Palabra { texto: vista(s), n: 1 }; }',
     "no se puede devolver una vista de `s`"),

    ("la vista que se saca de el presta de lo mismo",
     _PALABRA + 'fn main() { var s = nuevo("x"); let p = Palabra { texto: vista(s), n: 1 };'
     ' let v = texto_de(p); empujar(s, "y"); imprimir(v); imprimir(p.n); }',
     "esta prestada por `p` y `v`"),

    ("una lista no guarda structs que prestan",
     _PALABRA + 'fn main() { var xs: lista<Palabra> = []; imprimir(largo(xs)); }',
     "no es un tipo almacenable"),

    ("un mapa tampoco guarda vistas",
     'fn main() { var m: mapa<str, view> = []; imprimir(largo(m)); }',
     "no es un tipo almacenable"),

    ("un enum no lleva vistas",
     'enum E { A(view), B } fn main() { }',
     "un enum no guarda prestamos"),

    ("no se guarda una vista en algo prestado",
     _PALABRA + 'fn g(p: mut Palabra, v: view) { p.texto = v; }',
     "no se puede guardar un prestamo en `p`"),

    ("una clausura no captura un struct que presta",
     _PALABRA + 'fn main() { let s = nuevo("x"); let p = Palabra { texto: vista(s), n: 1 };'
     ' let f = fn[p]() -> usize { return 1; }; imprimir(f()); }',
     "`p` es `Palabra`, un prestamo"),

    # ---- sacar un campo de su struct ----
    ("un struct a medio mover no se usa entero",
     _MEDIO + 'fn main() { let p = nuevo_p(); let n = p.nombre; imprimir(toma(p));'
     ' imprimir(n); }',
     "`p` esta a medio mover: `p.nombre` se saco"),

    ("un campo sacado no se usa otra vez",
     _MEDIO + 'fn main() { let p = nuevo_p(); let n = p.nombre; let m = p.nombre;'
     ' imprimir(n); imprimir(m); }',
     "`p.nombre` ya se saco"),

    ("un campo no se saca dentro de un `if`",
     _MEDIO + 'fn main() { let p = nuevo_p(); if true { let n = p.nombre;'
     ' imprimir(n); } }',
     "no se puede sacar `p.nombre` dentro de un `if`"),

    ("ni de algo prestado",
     _MEDIO + 'fn f(p: &P) -> str { return p.nombre; }',
     "`p` es prestada: no se puede sacar `p.nombre`"),

    ("ni mientras una vista lo mira",
     _MEDIO + 'fn main() { var p = nuevo_p(); let v = vista(p.nombre);'
     ' let n = p.nombre; imprimir(v); imprimir(n); }',
     "no se puede sacar `p.nombre`: esta prestada por `v`"),

    ("reponerlo dentro de un `if` no lo repone para despues",
     _MEDIO + 'fn main() { var p = nuevo_p(); let n = p.nombre;'
     ' if true { p.nombre = nuevo("x"); } imprimir(toma(p)); imprimir(n); }',
     "`p` esta a medio mover"),

    # ---- patrones anidados, literales y guardas ----
    ("un brazo con condiciones no cubre su forma el solo",
     _FORMAS + 'fn f(e: &E) -> usize { return match e { E.X -> 0, E.Y(1) -> 1,'
     ' E.Z(_, _) -> 2, }; }',
     "le pueden quedar casos de `E.Y` sin mirar"),

    ("un brazo detras de otro que ya lo cubre no se ejecuta nunca",
     _FORMAS + 'fn f(e: &E) -> usize { return match e { E.X -> 0, E.Y(_) -> 1,'
     ' E.Y(3) -> 2, E.Z(_, _) -> 3, }; }',
     "`E.Y` se mira dos veces"),

    ("un literal del patron tiene que ser del tipo de su posicion",
     _FORMAS + 'fn f(e: &E) -> usize { return match e { E.Y("a") -> 1, _ -> 2, }; }',
     "el literal del patron no es uno"),

    ("una forma anidada tiene que ser del enum de su posicion",
     _FORMAS + 'fn f(e: &E) -> usize { return match e { E.Y(E2.A) -> 1, _ -> 2, }; }',
     "el patron pone `E2.A`"),

    ("la guarda es un `bool`",
     _FORMAS + 'fn f(e: &E) -> usize { return match e { E.Y(n) if n -> 1, _ -> 2, }; }',
     "la guarda de un brazo tiene que ser `bool`"),

    ("una guarda no mueve nada",
     _FORMAS + 'fn g(s: str) -> bool { return largo(s) > 0; }'
     ' fn f(e: &E, s: str) -> usize { return match e { E.Y(_) if g(s) -> 1,'
     ' _ -> 2, }; }',
     "una guarda no mueve nada"),

    ("modificar lo capturado pide `mut` en la captura",
     'fn main() { let n: usize = 0;'
     ' let f = fn[n]() -> usize { n = n + 1; return n; }; imprimir(f()); }',
     "capturalo con `fn[mut n]`"),

    ("una clausura que modifica solo se llama desde un `var`",
     'fn main() { let n: usize = 0;'
     ' let f = fn[mut n]() -> usize { n = n + 1; return n; }; imprimir(f()); }',
     "declarala con `var`"),

    ("una generica llama a una clausura que modifica si la recibe `mut`",
     'fn dos<F>(f: F) -> usize { return f() + f(); }'
     ' fn main() { let n: usize = 0;'
     ' var f = fn[mut n]() -> usize { n = n + 1; return n; };'
     ' imprimir(dos(f)); }',
     "recibela como `f: mut F`"),

    ("no se captura lo que no existe",
     'fn main() -> usize { let g = fn[nada](x: usize) -> usize { return x; };'
     ' return g(1); }',
     "no esta declarada, no se puede capturar"),

    ("un `if` que da valor necesita `else`",
     'fn main() -> usize { let x = if true { 1 }; return x; }',
     "necesita `else`"),

    ("las dos ramas de un `if` valor dan el mismo tipo",
     'fn main() -> usize { let x = if true { 1 } else { nuevo("a") }; return 0; }',
     "tienen que dar el mismo tipo"),

    ("`%` no tiene un significado unico con decimales",
     'fn main() -> usize { let a: f64 = 5.5; let b: f64 = 2.0;'
     ' imprimir(a % b); return 0; }',
     "no tiene un significado unico"),

    ("`como?` de un decimal a un entero no dice que hacer con la fraccion",
     'fn main() -> usize { let f: f64 = 3.7; imprimir(f como? usize); return 0; }',
     "di que quieres con la parte decimal"),

    ("los bits no operan sobre decimales",
     'fn main() -> usize { let a: f64 = 2.0; imprimir(a & 1); return 0; }',
     "trabaja sobre los bits de un entero"),

    ("una funcion falible no se puede pasar como valor",
     'fn r(n: usize) -> usize ! { if n == 0 { falla "cero"; } return n; }'
     ' fn f(g: fn(usize) -> usize) -> usize { return g(1); }'
     ' fn main() -> usize { return f(r); }',
     "no puede: quitale el `!`"),

    ("una generica no se puede pasar como valor: no se sabe cual",
     'fn cual<T>(x: T) -> T { return x; }'
     ' fn f(g: fn(usize) -> usize) -> usize { return g(1); }'
     ' fn main() -> usize { return f(cual); }',
     "es generica"),

    ("una funcion como valor comprueba sus argumentos",
     'fn doble(n: usize) -> usize { return n * 2; }'
     ' fn main() -> usize { let g = doble; let s = nuevo("a");'
     ' return g(s); }',
     "toma `usize` ahi y recibio `str`"),

    ("los anchos no se mezclan solos",
     'fn main() -> usize { let a: u8 = 1; let b: u32 = 2; imprimir(a + b); return 0; }',
     "no se mezclan sin conversion explicita"),

    ("`como` es entre numeros, no un molde universal",
     'fn main() -> usize { let s = nuevo("a"); imprimir(s como u8); return 0; }',
     "`como` convierte entre numeros"),

    ("los bits no operan sobre texto",
     'fn main() -> usize { let s = nuevo("a"); imprimir(s & 1); return 0; }',
     "trabaja sobre los bits de un entero"),

    ("un literal de struct generico cuyos campos no dicen el tipo",
     'struct Par<A, B> { a: A, b: B }'
     ' fn vacia<T>() -> lista<T> { var s: lista<T> = []; return s; }'
     ' fn main() -> usize { let p = Par { a: vacia(), b: 2 }; return 0; }',
     "Escribe el tipo en la declaracion"),

    ("un struct generico con el numero de tipos equivocado",
     'struct Par<A, B> { a: A, b: B }'
     ' fn f(p: Par<usize>) -> usize { return 0; }'
     ' fn main() -> usize { return 0; }',
     "toma 2 tipo(s) y se le dieron 1"),

    ("una restriccion falla en la llamada, no dentro del cuerpo",
     'fn suma<T: numero>(ns: &lista<T>) -> T { var t: T = 0; return t; }'
     ' fn main() -> usize { var ss: lista<str> = [];'
     ' anadir(ss, nuevo("a")); imprimir(suma(ss)); return 0; }',
     "pide que `T` sea `numero`, y aqui `T` es `str`"),

    ("una restriccion que no existe",
     'fn f<T: sumable>(x: T) -> T { return x; } fn main() -> usize { return 0; }',
     "no es una restriccion"),

    ("`igual` no compara cosas de tipos distintos",
     'fn f() -> bool { return igual(1, "a"); }',
     "del mismo tipo"),

    ("`igual` no compara structs: habria que decidir que significa",
     'struct P { n: usize } fn f(a: P, b: P) -> bool { return igual(a, b); }',
     "recibio `P`"),

    ("copiar una vista no copia nada",
     'fn f(v: view) -> usize { let c = copiar(v); return 0; }',
     "una vista no es duenia de nada que copiar"),

    # ---- genericas ----
    ("una generica sin argumentos que digan el tipo",
     'fn vacia<T>() -> lista<T> { var s: lista<T> = []; return s; }'
     ' fn main() -> usize { let x = vacia(); return 0; }',
     "no se puede deducir `T`"),

    ("un parametro de tipo es un solo tipo en toda la llamada",
     'fn dos<T>(a: T, b: T) -> T { return a; }'
     ' fn main() -> usize { let s: str = nuevo("x");'
     ' imprimir(dos(1, s)); return 0; }',
     "ya quedo en `usize`"),

    ("el cuerpo de una generica se comprueba con los tipos puestos",
     'fn primeras<T>(xs: &lista<T>) -> lista<T> {'
     ' var salida: lista<T> = []; for x en xs { anadir(salida, x); }'
     ' return salida; }'
     ' fn main() -> usize { var ss: lista<str> = [];'
     ' anadir(ss, nuevo("a")); let d = primeras(ss); return 0; }',
     "al usar `primeras` con T = str"),

    ("un parametro de tipo no puede llamarse como un tipo del lenguaje",
     'fn f<str>(a: str) -> str { return a; } fn main() -> usize { return 0; }',
     "se esperaba 'ident'"),

    ("`falla` con parentesis: el error dice como se escribe",
     'fn f() -> usize ! { falla("roto"); }',
     "no lleva parentesis"),

    # ---- las cuatro clases de la auditoria de safestr.c ----
    ("fallo 2: use-after-free por aliasing a traves de realloc",
     'fn f() { var s: str = nuevo("hola"); empujar(s, vista(s)); }',
     "se presta y se modifica"),

    ("fallo 2 bis: el contrato de vida util de SafeView",
     'fn f() { var s: str = nuevo("hola"); let v: view = vista(s);'
     ' empujar(s, "mas"); imprimir(v); }',
     "esta prestada por `v`"),

    ("fallo 1 y 4: los enteros no se mezclan en silencio",
     'fn f() { let a: usize = 1; let b: i64 = 2; let c: usize = a + b; }',
     "no se mezclan"),

    ("fallo 4: usize no tiene signo",
     'fn f() { let a: usize = 1; let b: usize = -a; }',
     "no tiene signo"),

    # ---- vidas utiles: una vista no puede sobrevivir a lo que presta ----
    ("devolver una vista de un local",
     'fn f() -> view { var s: str = nuevo("hola"); return vista(s); }',
     "no se puede devolver una vista de `s`"),

    ("lo mismo a traves de una variable intermedia",
     'fn f() -> view { var s: str = nuevo("h"); let v: view = vista(s);'
     ' return v; }',
     "no se puede devolver una vista"),

    ("lo mismo a traves de una rebanada",
     'fn f() -> view { var s: str = nuevo("hola");'
     ' return rebanar(vista(s), 0, 2); }',
     "no se puede devolver una vista"),

    ("lo mismo a traves de otra funcion",
     'fn a(v: view) -> view { return v; }'
     ' fn b() -> view { var s: str = nuevo("x"); return a(vista(s)); }',
     "no se puede devolver una vista"),

    ("el prestamo atraviesa la llamada",
     'fn primero(v: view) -> view { return rebanar(v, 0, 1); }'
     ' fn main() -> usize { var s: str = nuevo("hola");'
     ' let p: view = primero(vista(s)); empujar(s, "x"); imprimir(p); return 0; }',
     "esta prestada por `p`"),

    # ---- propiedad ----
    ("uso despues de mover",
     'fn g(x: str) {} fn f() { var s: str = nuevo("a"); g(s); empujar(s, "b"); }',
     "ya se movio"),

    ("mover algo prestado",
     'fn g(x: str) {} fn f() { var s: str = nuevo("a");'
     ' let v: view = vista(s); g(s); imprimir(v); }',
     "no se puede mover"),
    ("mover en un bucle algo declarado fuera",
     'fn g(s: str) {} fn f() { let s: str = nuevo("a"); var i: usize = 0;'
     ' while i < 3 { g(s); i = i + 1; } }',
     "se declaro fuera del bucle"),

    ("reasignar dentro de un `if` no salva el movimiento del bucle",
     'fn g(s: str) {} fn f(c: bool) { var s: str = nuevo("a"); var i: usize = 0;'
     ' while i < 3 { g(s); if c { s = nuevo("b"); } i = i + 1; } }',
     "se declaro fuera del bucle"),


    # ---- mutabilidad ----
    ("modificar un let",
     'fn f() { let s: str = nuevo("a"); empujar(s, "b"); }',
     "no se puede modificar"),

    ("reasignar un let",
     'fn f() { let n: usize = 1; n = 2; }',
     "no se puede modificar"),

    # ---- structs y arreglos ----
    ("struct que se contiene a si mismo",
     'struct P { hijo: P }',
     "se contiene a si mismo"),

    ("sacar un `str` de un struct sin variable dejaria un hueco",
     'struct P { n: str } fn hacer() -> P { return P { n: nuevo("a") }; }'
     ' fn f() { let s: str = hacer().n; }',
     "no se puede sacar `n` de un struct que no esta en una variable"),

    ("sacar un `str` de un arreglo dejaria un hueco",
     'fn f() { var a: [str; 2] = [nuevo("x"), nuevo("y")]; let s: str = a[0]; }',
     "no se puede sacar un elemento"),

    ("prestar un campo bloquea el struct entero",
     'struct P { n: str } fn f() { var p: P = P { n: nuevo("a") };'
     ' let v: view = vista(p.n); empujar(p.n, "b"); imprimir(v); }',
     "esta prestada por `v`"),

    # ---- un prestamo dura hasta el ultimo uso de quien presta ----
    ("una vista usada despues de modificar a su duenio",
     'fn main() { var s = nuevo("hola"); let v = vista(s);'
     ' empujar(s, "!"); imprimir(v); }',
     "no se puede modificar `s`: esta prestada por `v`"),

    ("un bucle vuelve a usar la vista en la vuelta siguiente",
     'fn main() { var s = nuevo("x"); let w = vista(s); var i: usize = 0;'
     ' while i < 2 { imprimir(w); empujar(s, "y"); i = i + 1; } }',
     "no se puede modificar `s`: esta prestada por `w`"),

    ("una vista que se usa despues del if",
     'fn main() { var s = nuevo("z"); let a = vista(s);'
     ' if largo(s) > 0 { empujar(s, "w"); } imprimir(a); }',
     "no se puede modificar `s`: esta prestada por `a`"),

    ("la sentencia que modifica tambien usa la vista",
     'fn crece(x: mut str) -> usize { empujar(x, "!"); return 1; }'
     ' fn main() { var s = nuevo("z"); let a = vista(s);'
     ' let n = crece(s) + largo(a); imprimir(n); }',
     "no se puede modificar `s`: esta prestada por `a`"),

    ("mover algo cuya vista se usa en un bucle de fuera",
     'fn g(x: str) {} fn main() { var i: usize = 0; while i < 2 {'
     ' var s = nuevo("a"); let v = vista(s); imprimir(v); var j: usize = 0;'
     ' while j < 2 { if j == 1 { g(s); } imprimir(v); j = j + 1; } i = i + 1; } }',
     "no se puede mover `s`: esta prestada por `v`"),

    ("usar un struct despues de moverlo",
     'struct P { n: str } fn g(p: P) {} fn f() { var p: P = P { n: nuevo("a") };'
     ' g(p); imprimir(p.n); }',
     "ya se movio"),

    ("campo que no existe",
     'struct P { x: usize } fn f() { let p: P = P { x: 1 }; imprimir(p.y); }',
     "no tiene un campo `y`"),

    ("falta un campo al construir",
     'struct P { x: usize, y: usize } fn f() { let p: P = P { x: 1 }; }',
     "le faltan campos"),

    ("el largo del literal no calza con el tipo",
     'fn f() { let a: [usize; 5] = [1,2]; }',
     "el tipo dice 5"),

    ("elementos de tipos distintos",
     'fn f() { let a: [usize; 2] = [1, true]; }',
     "deberia ser `usize`"),

    ("indexar con algo que no es usize",
     'fn f() { let a: [usize; 2] = [1,2]; let b: bool = true; imprimir(a[b]); }',
     "tiene que ser `usize`"),

    ("indexar algo que no es un arreglo",
     'fn f() { let n: usize = 1; imprimir(n[0]); }',
     "no es un arreglo"),

    ("una lista no puede guardar vistas sin vidas utiles",
     'fn f() { let xs: lista<view> = ["a"]; }',
     "no es un tipo almacenable"),

    ("anadir exige una lista mutable",
     'fn f() { let xs: lista<usize> = []; anadir(xs, 1); }',
     "se declaro con `let`"),

    ("anadir comprueba el tipo del elemento",
     'fn f() { var xs: lista<usize> = []; anadir(xs, true); }',
     "la lista guarda `usize`"),

    ("sacar un duenio de una lista dejaria un hueco",
     'fn f() { var xs: lista<str> = [nuevo("a")]; let s: str = xs[0]; }',
     "no se puede sacar un elemento"),

    # ---- fallos ----
    ("ignorar que una llamada puede fallar",
     'fn f() -> usize ! { falla "x"; }  fn g() -> usize { return f(); }',
     "puede fallar"),

    ("ignorar que leer un archivo puede fallar",
     'fn f() { let s: str = leer_archivo("datos.txt"); }',
     "puede fallar"),

    ("`try` en una funcion que no esta declarada con `!`",
     'fn f() -> usize ! { falla "x"; }  fn g() -> usize { return try f(); }',
     "no esta declarada con `!`"),

    ("`falla` en una funcion que no esta declarada con `!`",
     'fn f() -> usize { falla "x"; }',
     "no esta declarada con `!`"),

    ("`try` sobre algo que no puede fallar",
     'fn a() -> usize { return 1; }  fn g() -> usize ! { return try a(); }',
     "va delante de una llamada"),

    ("el valor de `sino` tiene que ser del mismo tipo",
     'fn f() -> usize ! { falla "x"; }  fn g() -> usize { return f() sino true; }',
     "es `bool`"),

    ("`try` en la condicion de un while",
     'fn f() -> usize ! { falla "x"; }'
     ' fn g() -> usize ! { while try f() > 0 { } return 0; }',
     "se evaluaria una sola vez"),

    # ---- mapas ----
    ("la clave de un mapa tiene que ser `str`",
     'fn f() { var m: mapa<usize, usize> = []; imprimir(largo(m)); }',
     "la clave de un mapa tiene que ser `str`"),

    ("un mapa guarda valores, no prestamos",
     'struct S { a: str } fn f() { var m: mapa<str, &S> = []; imprimir(largo(m)); }',
     "no puede ser ni clave ni valor"),

    ("`sino` no puede dar un prestamo por defecto",
     'struct S { a: str } fn f() { var m: mapa<str, S> = [];'
     ' let s: &S = obtener(m, "x") sino S { a: vacio() }; imprimir(s.a); }',
     "no hay nada que prestar"),

    ("modificar un mapa con un `&T` suyo vivo",
     'struct S { a: str } fn f() -> usize ! { var m: mapa<str, S> = [];'
     ' let s: &S = try obtener(m, "x"); poner(m, "z", S { a: nuevo("w") });'
     ' imprimir(s.a); return 0; }',
     "esta prestada por `s`"),

    ("devolver un `&T` de un mapa local",
     'struct S { a: str } fn f() -> &S ! { var m: mapa<str, S> = [];'
     ' return try obtener(m, "x"); }',
     "muere al cerrar la funcion"),

    ("escribir a traves de un `&T` de solo lectura",
     'struct S { n: usize } fn f(x: &S) { x.n = 5; }',
     "solo para leer"),

    ("`poner` con un `&mut` vivo",
     'struct S { n: usize } fn f() -> usize ! { var m: mapa<str, S> = [];'
     ' let s: &mut S = try obtener_mut(m, "k"); poner(m, "z", S { n: 1 });'
     ' s.n = 2; return 0; }',
     "esta prestada por `s`"),

    ("dos `&mut` del mismo mapa a la vez",
     'struct S { n: usize } fn f() -> usize ! { var m: mapa<str, S> = [];'
     ' let a: &mut S = try obtener_mut(m, "k");'
     ' let b: &mut S = try obtener_mut(m, "j"); a.n = 1; return 0; }',
     "esta prestada por `a`"),

    ("`obtener_mut` sobre un mapa inmutable",
     'struct S { n: usize } fn f() -> usize ! { let m: mapa<str, S> = [];'
     ' let s: &mut S = try obtener_mut(m, "k"); return 0; }',
     "se declaro con `let`"),

    ("de un prestamo no se saca un `str`",
     'struct S { a: str } fn f() -> usize ! {'
     ' var m: mapa<str, S> = []; let r: &S = try obtener(m, "x");'
     ' let sacado: S = r; return 0; }',
     "pero el valor es `&S`"),

    ("un `&T` no se puede mover",
     'struct S { a: str } fn g(x: S) {} fn f() -> usize ! {'
     ' var m: mapa<str, S> = []; let s: &S = try obtener(m, "x");'
     ' g(s); return 0; }',
     "recibio `&S`"),

    ("modificar un mapa con una vista de `obtener` viva",
     'fn f() { var m: mapa<str, str> = [];'
     ' let v: view = obtener(m, "a") sino "?"; poner(m, "b", nuevo("y"));'
     ' imprimir(v); }',
     "esta prestada por `v`"),

    ("devolver la vista que presta un mapa local",
     'fn f() -> view { var m: mapa<str, str> = [];'
     ' return obtener(m, "a") sino "?"; }',
     "no se puede devolver una vista"),

    ("dentro de `{}` no cabe una coleccion",
     'fn f() { var xs: lista<usize> = []; let m: str = $"{xs}"; imprimir(m); }',
     "va un escalar o texto"),

    # `imprimir` y `{}` escriben numeros, `bool` y texto. Lo demas pasaba el
    # comprobador y luego salia `?` o C que no compilaba.
    ("imprimir no muestra un enum",
     'enum Color { Rojo, Verde }\nfn main() { let c = Color.Rojo; imprimir(c); }',
     "`imprimir` no sabe mostrar un `Color`: escribe el nombre de cada forma con un `match`"),

    ("dentro de `{}` no cabe un enum",
     'enum Color { Rojo, Verde }\n'
     'fn main() { let c = Color.Verde; imprimir($"color {c}"); }',
     "va un escalar o texto, y `Color` no lo es: escribe el nombre de cada forma"),

    ("imprimir no muestra una funcion",
     'fn f(x: usize) -> usize { return x; }\nfn main() { let g = f; imprimir(g); }',
     "`imprimir` no sabe mostrar un `fn(usize) -> usize`: muestra un numero"),

    ("dentro de `{}` no cabe una funcion",
     'fn f(x: usize) -> usize { return x; }\n'
     'fn main() { let g = f; imprimir($"{g}"); }',
     "va un escalar o texto, y `fn(usize) -> usize` no lo es"),

    ("imprimir no muestra una lista",
     'fn main() { let xs: lista<usize> = [1]; imprimir(xs); }',
     "`imprimir` no sabe mostrar un `lista<usize>`: muestra sus campos o elementos"),

    ("imprimir no muestra un struct prestado",
     'struct P { a: usize }\nfn g(p: &P) { imprimir(p); }\n'
     'fn main() { let p = P { a: 1 }; g(p); }',
     "`imprimir` no sabe mostrar un `P`: muestra sus campos"),

    ("imprimir no muestra ()",
     'fn u() { }\nfn main() { imprimir(u()); }',
     "`imprimir` no sabe mostrar un `()`"),

    ("`{}` vacio",
     'fn f() { let m: str = $"hola {}"; imprimir(m); }',
     "vacio en una cadena interpolada"),

    ("llave sin cerrar en una interpolada",
     'fn f() { let m: str = $"hola {n"; imprimir(m); }',
     "falta `}` en algun hueco"),
    ("`obtener` puede fallar y hay que decirlo",
     'fn f() { var m: mapa<str, usize> = []; imprimir(obtener(m, "x")); }',
     "puede fallar"),

    ("poner sobre un `let`",
     'fn f() { let m: mapa<str, usize> = []; poner(m, "a", 1); }',
     "se declaro con `let`"),

    ("el valor tiene que ser del tipo del mapa",
     'fn f() { var m: mapa<str, usize> = []; poner(m, "a", true); }',
     "se intento poner `bool`"),

    ("un mapa no admite literal con contenido",
     'fn f() { var m: mapa<str, usize> = [1, 2]; imprimir(largo(m)); }',
     "se llena con `poner`"),

    # ---- orden y salida ----
    ("un struct no tiene orden natural",
     'struct P { a: usize } fn f() { var xs: lista<P> = []; ordenar(xs); }',
     "no tiene un orden natural"),

    ("`ordenar` necesita una lista",
     'fn f() { var s: str = nuevo("a"); ordenar(s); }',
     "opera sobre `lista<T>`"),

    ("`ordenar` sobre un `let`",
     'fn f() { let xs: lista<usize> = []; ordenar(xs); }',
     "se declaro con `let`"),

    ("`quitar` sobre un `let`",
     'fn f() { let m: mapa<str, usize> = []; imprimir(quitar(m, "a")); }',
     "se declaro con `let`"),

    ("`escribir_archivo` puede fallar y hay que decirlo",
     'fn f() { escribir_archivo("x", "y"); }',
     "puede fallar"),

    # ---- recorridos ----
    ("modificar una coleccion mientras se recorre",
     'fn f() { var xs: lista<usize> = []; for x en xs { anadir(xs, 1); } }',
     "esta prestada por `<el for"),

    ("mover el elemento que llego prestado",
     'fn g(s: str) {} fn f() { var xs: lista<str> = []; for s en xs { g(s); } }',
     "llego prestado"),

    ("modificar el elemento que llego prestado",
     'fn f() { var xs: lista<str> = []; for s en xs { empujar(s, "x"); } }',
     "solo para leer"),

    ("modificar un mapa mientras se recorre",
     'fn f() { var m: mapa<str, usize> = []; for k, v en m { poner(m, "x", 1); } }',
     "esta prestada por `<el for"),

    ("quitar de un mapa mientras se recorre",
     'fn f() { var m: mapa<str, usize> = []; for k, v en m { quitar(m, "x"); } }',
     "esta prestada por `<el for"),

    ("mover una clave prestada por el recorrido",
     'fn g(s: str) {} fn f() { var m: mapa<str, usize> = [];'
     ' for k, v en m { g(k); } }',
     "llego prestado"),

    ("dos nombres solo valen para un mapa",
     'fn f() { var xs: lista<usize> = []; for a, b en xs { imprimir(a); } }',
     "son para un mapa"),

    ("`for` no recorre un texto",
     'fn f() { let s: str = nuevo("abc"); for b en s { imprimir(b); } }',
     "no lo es"),

    ("`break` fuera de un bucle",
     'fn f() { break; }',
     "solo tiene sentido dentro"),

    ("`continue` fuera de un bucle",
     'fn f() { if true { continue; } }',
     "solo tiene sentido dentro"),

    # ---- lo que la inferencia no puede adivinar ----
    ("`[]` sin tipo no dice si es lista, arreglo o mapa",
     'fn f() { let xs = []; imprimir(largo(xs)); }',
     "escribe el tipo"),

    ("no se deduce el tipo de algo que no devuelve nada",
     'fn g() {} fn f() { let x = g(); imprimir(0); }',
     "no se puede deducir el tipo"),

    ("prestar para modificar algo recien hecho no sirve de nada",
     'fn g(s: mut str) {} fn f() { g(nuevo("a")); }',
     "modificar algo recien hecho"),

    ("prometer un valor y no devolverlo",
     'fn g() -> usize { imprimir(1); }',
     "hay un camino que llega al final sin `return`"),

    ("devolver solo en una rama",
     'fn g(c: bool) -> usize { if c { return 1; } }',
     "sin `return`"),

    ("un `while` no garantiza la salida",
     'fn g(c: bool) -> usize { while c { return 1; } }',
     "sin `return`"),

    # ---- tipos ----
    ("tipo declarado que no calza",
     'fn f() { let n: usize = "no soy un numero"; }',
     "el valor es `view`"),

    ("condicion que no es bool",
     'fn f() { let n: usize = 1; if n { } }',
     "debe ser `bool`"),

    ("variable no declarada",
     'fn f() { imprimir(x); }',
     "no esta declarada"),

    ("funcion desconocida",
     'fn f() { desconocida(1); }',
     "no es una funcion conocida"),

    ("numero de argumentos",
     'fn g(a: usize, b: usize) {} fn f() { g(1); }',
     "espera 2 argumento"),

    ("declarar dos veces en el mismo bloque",
     'fn f() { let a: usize = 1; let a: usize = 2; }',
     "ya esta declarada"),

    ("una funcion con el nombre de una interna no se llamaria nunca",
     'fn sembrar(n: u64) {} fn main() { sembrar(1); }',
     "es una funcion interna"),

    ("tampoco una externa",
     'externo "stdlib.h" { fn azar(n: usize) -> usize; } fn main() {}',
     "es una funcion interna"),

    ("tapar una variable de un bloque de fuera",
     'fn f(c: bool) { let t: usize = 1; if c { let t: usize = 2; } }',
     "tapa a una variable"),

    ("tapar un parametro dentro de un bucle",
     'fn f(n: usize) { while n > 0 { let n: usize = 0; } }',
     "tapa a una variable"),

    ("prestar una vista no tiene sentido: ya es un prestamo",
     'fn g(v: &view) {}',
     "una vista ya es un prestamo"),

    # ---- prestamo de structs ----
    ("mover algo que llego prestado",
     'struct P { n: str } fn g(p: P) {} fn f(p: &P) { g(p); }',
     "llego prestado"),

    ("modificar un prestamo de solo lectura",
     'struct P { n: str, u: usize } fn f(p: &P) { p.u = 1; }',
     "solo para leer"),

    ("empujar sobre un prestamo de solo lectura",
     'struct P { n: str } fn f(p: &P) { empujar(p.n, "x"); }',
     "solo para leer"),

    ("prestar lo mismo como `&` y como `mut` en una llamada",
     'struct P { u: usize } fn g(a: &P, b: mut P) {}'
     ' fn f() { var p: P = P { u: 1 }; g(p, p); }',
     "se presta dos veces"),

    ("dos prestamos mutables de lo mismo",
     'struct P { u: usize } fn g(a: mut P, b: mut P) {}'
     ' fn f() { var p: P = P { u: 1 }; g(p, p); }',
     "se presta dos veces"),

    ("prestar un `let` para modificarlo",
     'struct P { u: usize } fn g(a: mut P) {}'
     ' fn f() { let p: P = P { u: 1 }; g(p); }',
     "se declaro con `let`"),

    ("el tipo del prestamo tiene que calzar",
     'struct P { u: usize } struct Q { u: usize } fn g(a: &P) {}'
     ' fn f() { var q: Q = Q { u: 1 }; g(q); }',
     "recibio `Q`"),

    ("redimensionar por &mut no invalida una vista viva",
     'fn main() -> usize ! { var m: mapa<str, bloque<str>> = [];'
     ' var b: bloque<str> = reservar(1); b[0] = nuevo("a");'
     ' poner(m, "x", b);'
     ' let p: &mut bloque<str> = try obtener_mut(m, "x");'
     ' let v = vista(p[0]); redimensionar(p, 0); imprimir(v); return 0; }',
     "esta prestada por `v`"),

    ("redimensionar reserva el bloque mientras calcula el tamaño",
     'fn soltar(x: bloque<usize>) -> usize { return 1; }'
     ' fn main() { var b: bloque<usize> = reservar(1);'
     ' redimensionar(b, soltar(b)); }',
     "esta reservada por `redimensionar` mientras se calcula el tamaño"),

    ("intercambiar por &mut no invalida una vista viva",
     'fn main() -> usize ! { var m: mapa<str, bloque<str>> = [];'
     ' var b: bloque<str> = reservar(1); b[0] = nuevo("a");'
     ' poner(m, "x", b);'
     ' let p: &mut bloque<str> = try obtener_mut(m, "x");'
     ' let v = vista(p[0]);'
     ' let old = intercambiar(p[0], nuevo("b"));'
     ' imprimir(v); imprimir(old); return 0; }',
     "esta prestada por `v`"),

    ("intercambiar reserva el destino mientras calcula el reemplazo",
     'fn reemplazar(x: str) -> str { return nuevo("b"); }'
     ' fn main() { var s = nuevo("a");'
     ' let old = intercambiar(s, reemplazar(s)); imprimir(old); }',
     "esta reservada por `intercambiar` mientras se calcula el reemplazo"),
    # ---- prestamos que se escapaban: cada uno era un uso tras liberar ----
    # El fallo 2 de la especificacion, en una funcion propia: `a` crece y
    # `b` queda apuntando al buffer viejo.
    ("una vista que se pasa presta durante la llamada",
     'fn g(a: mut str, b: view) { empujar(a, "xxxxxxxxxxxxxxxxxxxxxxxx"); imprimir(b); }'
     ' fn main() { var s = nuevo("hola"); g(s, vista(s)); }',
     "`s` se presta dos veces en la misma llamada a `g`"),

    ("un `str` donde se pide `view` tambien presta",
     'fn g(a: mut str, b: view) { empujar(a, "x"); imprimir(b); }'
     ' fn main() { var s = nuevo("hola"); g(s, s); }',
     "`s` se presta dos veces en la misma llamada a `g`"),

    ("un campo prestado y modificado en la misma llamada",
     'struct P { a: str, b: str }'
     ' fn g(a: mut str, b: view) { empujar(a, "x"); imprimir(b); }'
     ' fn main() { var p = P { a: nuevo("a"), b: nuevo("b") }; g(p.a, vista(p.a)); }',
     "`p.a` se presta dos veces en la misma llamada a `g`"),

    # Los prestamos de una llamada van por caminos: `p.a` y `p.b` no se
    # tocan, pero `p` contiene a `p.b`, y `p.q` a `p.q.n`.
    ("el struct entero y uno de sus campos en la misma llamada",
     'struct P { a: str, b: str }'
     ' fn k(a: mut P, b: &str) { empujar(a.b, "x"); imprimir(b); }'
     ' fn main() { var p = P { a: nuevo("a"), b: nuevo("b") }; k(p, p.b); }',
     "`p` se presta dos veces en la misma llamada a `k`"),

    ("un campo de dentro y el struct que lo contiene",
     'struct Q { n: usize } struct P { q: Q }'
     ' fn w(a: mut Q, b: &usize) { a.n = b + 1; }'
     ' fn main() { var p = P { q: Q { n: 1 } }; w(p.q, p.q.n); imprimir(p.q.n); }',
     "`p.q` se presta dos veces en la misma llamada a `w`"),

    ("dos elementos de una lista pueden ser el mismo",
     'struct P { a: str, b: str }'
     ' fn g(a: mut str, b: view) { empujar(a, "x"); imprimir(b); }'
     ' fn main() { var v: lista<P> = []; g(v[0].a, vista(v[1].b)); }',
     "`v` se presta dos veces en la misma llamada a `g`"),

    ("un puntero a funcion mira los caminos igual",
     'fn h(a: &mut str, b: &str) { empujar(a, "1"); imprimir(b); }'
     ' struct P { a: str } fn main() { var p = P { a: nuevo("a") };'
     ' let f: fn(&mut str, &str) = h; f(p.a, p.a); }',
     "`p.a` se presta dos veces en la misma llamada a `f` (el argumento 1 y el argumento 2)"),

    ("un puntero a funcion no se salta los prestamos dobles",
     'fn g(a: &mut lista<str>, b: &str) { anadir(a, nuevo("x")); imprimir(b); }'
     ' fn main() { var xs: lista<str> = [nuevo("hola")];'
     ' let f: fn(&mut lista<str>, &str) = g; f(xs, xs[0]); }',
     "`xs` se presta dos veces en la misma llamada a `f`"),

    ("la vista que devuelve un puntero a funcion presta de su argumento",
     'fn primero(v: view) -> view { return v; }'
     ' fn main() { var s = nuevo("hola"); let f: fn(view) -> view = primero;'
     ' let v = f(vista(s)); s = nuevo("x"); imprimir(v); }',
     "no se puede modificar `s`: esta prestada por `v`"),

    ("la vista que devuelve una clausura presta de su argumento",
     'fn main() { var s = nuevo("hola"); let c = fn(x: view) -> view { return x; };'
     ' let v = c(vista(s)); s = nuevo("x"); imprimir(v); }',
     "no se puede modificar `s`: esta prestada por `v`"),

    ("la vista que devuelve una generica presta de su argumento",
     'fn id<T>(x: T) -> T { return x; }'
     ' fn main() { var s = nuevo("hola"); let v = id(vista(s));'
     ' empujar(s, "x"); imprimir(v); }',
     "no se puede modificar `s`: esta prestada por `v`"),

    ("lo que atrapa un patron presta del valor mirado",
     'enum E { A(str), B }'
     ' fn main() { var e = E.A(nuevo("hola"));'
     ' match e { E.A(s) -> { e = E.B; imprimir(s); } E.B -> {} } }',
     "no se puede modificar `e`: esta prestada por `s`"),

    ("lo atrapado guardado en una vista de fuera sigue prestando",
     'enum E { A(str), B }'
     ' fn main() { var e = E.A(nuevo("hola")); var v: view = "";'
     ' match e { E.A(s) -> { v = s; } E.B -> {} } e = E.B; imprimir(v); }',
     "no se puede modificar `e`: esta prestada por `v`"),

    ("un `match` que da una vista presta del valor mirado",
     'enum E { A(str), B }'
     ' fn main() { var e = E.A(nuevo("hola"));'
     ' let v: view = match e { E.A(s) -> s, E.B -> "" }; e = E.B; imprimir(v); }',
     "no se puede modificar `e`: esta prestada por `v`"),

    ("un `match` sobre un temporal no deja guardar lo que atrapa",
     'enum E { A(str), B }'
     ' fn hacer() -> E { return E.A(nuevo("hola")); }'
     ' fn main() { let v: view = match hacer() { E.A(s) -> s, E.B -> "" };'
     ' imprimir(v); }',
     "apuntaria a un valor temporal"),

    ("un `if` que da una vista presta de las dos ramas",
     'fn main() { var a = nuevo("a"); var b = nuevo("b"); let c = true;'
     ' let v = if c { vista(a) } else { vista(b) }; a = nuevo("x");'
     ' imprimir(v); empujar(b, "y"); }',
     "no se puede modificar `a`: esta prestada por `v`"),

    ("`empujar` mira todos los duenios posibles de la vista",
     'fn main() { var s = nuevo("s"); var t = nuevo("t"); let c = true;'
     ' empujar(t, if c { vista(s) } else { vista(t) }); imprimir(t); }',
     "`t` se presta y se modifica en la misma llamada a `empujar`"),

    ("un arreglo no guarda vistas",
     'fn main() { var arr: [view; 2] = ["", ""];'
     ' if true { let s = nuevo("hola"); arr[0] = vista(s); } imprimir(arr[0]); }',
     "no es un tipo almacenable"),

    ("un arreglo no guarda structs que prestan",
     'struct P { a: view }'
     ' fn main() { var s = nuevo("hola"); let arr: [P; 1] = [P { a: vista(s) }];'
     ' imprimir(arr[0].a); }',
     "no es un tipo almacenable"),

    # ---- aritmetica que daba la vuelta en silencio o C invalido ----
    ("un entero sin signo no se niega",
     'fn main() { let n: u8 = 5; let m: u8 = -n; imprimir(m); }',
     "`u8` no tiene signo: no se puede negar"),

    ("`/?` es de los decimales",
     'fn main() { let n: i64 = 7; let m: i64 = 2; imprimir(n /? m); }',
     "`/?` es la division IEEE de los decimales"),

    ("`/?` entre dos enteros escritos tampoco",
     'fn main() { let x: usize = 10 /? 3; imprimir(x); }',
     "`/?` es la division IEEE de los decimales"),

    # ---- lo que antes agotaba la pila del compilador ----
    ("un arbol de mas de 5000 niveles",
     'fn main() { let x: usize = ' + '(' * 6000 + '1' + ')' * 6000
     + '; imprimir(x); }',
     "el programa anida mas de 5000 niveles"),

    ("un error dentro de un hueco dice la linea de la cadena",
     'fn main() {\n\n\n    imprimir($"[{1 +}]");\n}',
     "p.t:4: se esperaba una expresion"),

    # Los encontro el oraculo de P11, o salieron al escribirlo. Un `-3`
    # suelto ya no cabia en un `u8`; una cuenta negada pasaba y daba 249.
    ("una cuenta de numeros escritos no se niega hacia un sin signo",
     'fn main() { let r: u8 = -(3 + 4); imprimir(r); }',
     "`u8` no tiene signo: no se puede negar"),

    # Donde va un decimal, los numeros escritos son decimales: sin resto ni
    # bits. Antes salia un C que no compilaba.
    ("el resto de dos numeros escritos donde va un decimal",
     'fn main() { let r: f64 = 7 % 2; imprimir(r); }',
     "`%` es el resto de una division entera"),

    ("los bits de dos numeros escritos donde va un decimal",
     'fn main() { let a: f64 = 2.0; imprimir(a + (1 << 2)); }',
     "`<<` trabaja sobre los bits de un entero, recibio `f64` y `f64`"),

    # La rama de un `if` que es un numero escrito toma el tipo de la otra: sin
    # mirarla, `300` se recortaba a 44 en un `u8`.
    ("la rama escrita de un if tiene que caber en el tipo de la otra",
     'fn main() { let x: u8 = 7; let c = x > 2;'
     ' imprimir((if c { 300 } else { x }) + 0); }',
     "el literal `300` no cabe en `u8`"),

    ("y la de dos ramas escritas, en el del otro lado",
     'fn main() { let x: u8 = 7; let c = x > 2;'
     ' imprimir((if c { 300 } else { 2 }) + x); }',
     "el literal `300` no cabe en `u8`"),

    ("y el brazo escrito de un match, en el de los otros",
     'enum E { A, B } fn main() { let x: u8 = 7; let e = E.A;'
     ' imprimir(match e { E.A -> 300, E.B -> x }); }',
     "el literal `300` no cabe en `u8`"),
]


TITULO = "programas que no deben compilar"


def correr(suite: Resultado) -> None:
    # Cada programa se escribe como `p.t`, que es lo que dicen sus errores.
    with tempfile.TemporaryDirectory() as tmp:
        def _rechazo(i_caso):
            i, (_, fuente, _) = i_caso
            os.makedirs(os.path.join(tmp, str(i)))
            return tcodec_sobre(fuente, "--solo-comprobar",
                                directorio=os.path.join(tmp, str(i)))

        for (nombre, _, esperado), r in zip(
                RECHAZO, en_paralelo(_rechazo, list(enumerate(RECHAZO)))):
            suite.total += 1
            errores = bloques(r.stderr, "error: ")
            if r.returncode == 0:
                suite.falla(nombre, "compilo, y no deberia")
            elif not any(esperado in e for e in errores):
                suite.falla(nombre, f"se esperaba {esperado!r}, se obtuvo: "
                              f"{errores or r.stderr[-300:]}")
