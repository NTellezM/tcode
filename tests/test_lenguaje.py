#!/usr/bin/env python3
"""
Suite del lenguaje Tcode.

RECHAZO   -> el programa NO debe compilar, y el error debe explicar por que.
ACEPTA    -> compila, corre bajo ASan+UBSan y da exactamente esta salida.

Los cuatro primeros casos de RECHAZO son las cuatro clases de fallo que
encontramos auditando la libreria safestr en C. Que aqui sean errores de compilacion
es la unica razon por la que este lenguaje existe.
"""

import os
import subprocess
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)

from tcode.cli import compilar_a_c, compilar_archivo
from tcode.lexer import ErrorLexico
from tcode.parser import ErrorSintactico

RUNTIME = os.path.join(RAIZ, "runtime")


RECHAZO = [
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

    ("una funcion falible no se puede pasar como valor en v0",
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
     ' let p: view = primero(vista(s)); empujar(s, "x"); return 0; }',
     "esta prestada por `p`"),

    # ---- propiedad ----
    ("uso despues de mover",
     'fn g(x: str) {} fn f() { var s: str = nuevo("a"); g(s); empujar(s, "b"); }',
     "ya se movio"),

    ("mover algo prestado",
     'fn g(x: str) {} fn f() { var s: str = nuevo("a");'
     ' let v: view = vista(s); g(s); }',
     "no se puede mover"),
    ("mover en un bucle algo declarado fuera",
     'fn g(s: str) {} fn f() { let s: str = nuevo("a"); var i: usize = 0;'
     ' while i < 3 { g(s); i = i + 1; } }',
     "se declaro fuera del bucle"),

    ("reasignar dentro de un `if` no salva el movimiento del bucle",
     'fn g(s: str) {} fn f(c: bool) { var s: str = nuevo("a"); var i: usize = 0;'
     ' while i < 3 { g(s); if c { s = nuevo("b"); } i = i + 1; } }',
     "se declaro fuera del bucle"),


    ("devolver algo prestado",
     'fn f() -> str { var s: str = nuevo("a"); let v: view = vista(s);'
     ' return s; }',
     "no se puede mover"),

    # ---- mutabilidad ----
    ("modificar un let",
     'fn f() { let s: str = nuevo("a"); empujar(s, "b"); }',
     "no se puede modificar"),

    ("reasignar un let",
     'fn f() { let n: usize = 1; n = 2; }',
     "no se puede modificar"),

    # ---- structs y arreglos ----
    ("un campo `view` necesita vidas utiles en el tipo",
     'struct P { v: view }',
     "no puede tener un campo `view`"),

    ("struct que se contiene a si mismo",
     'struct P { hijo: P }',
     "se contiene a si mismo"),

    ("sacar un `str` de un struct dejaria un hueco",
     'struct P { n: str } fn f() { var p: P = P { n: nuevo("a") };'
     ' let s: str = p.n; }',
     "no se puede sacar `n` de un struct"),

    ("sacar un `str` de un arreglo dejaria un hueco",
     'fn f() { var a: [str; 2] = [nuevo("x"), nuevo("y")]; let s: str = a[0]; }',
     "no se puede sacar un elemento"),

    ("prestar un campo bloquea el struct entero",
     'struct P { n: str } fn f() { var p: P = P { n: nuevo("a") };'
     ' let v: view = vista(p.n); empujar(p.n, "b"); }',
     "esta prestada por `v`"),

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
    ("en v0 la clave de un mapa tiene que ser `str`",
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

    ("comparar str con ==",
     'fn f() { let a: str = nuevo("x"); let b: str = nuevo("y");'
     ' let c: bool = a == b; }',
     "usa `igual("),

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
]


ACEPTA = [
    ("asignar a una variable algo que la presta no la lee despues de soltarla",
     '''fn main() -> usize {
            var s = nuevo("lista<P.Nodo>");
            // El valor nuevo lee el viejo. En C lo que cuenta no es donde se
            // calculo la expresion sino donde queda escrita, asi que el
            // valor se guarda antes de soltar lo que habia.
            s = nuevo(rebanar(vista(s), 0, 6));
            var t = nuevo("hola");
            t = nuevo(rebanar(vista(t), 1, 4));
            imprimir($"{s} {t}\\n");
        }''',
     "lista< ola\n"),

    ("la inferencia atraviesa una llamada a una generica",
     '''usar "std/par";
        struct Caja<T> { dentro: lista<T> }
        fn cuantos<T>(c: &Caja<T>) -> usize { return largo(c.dentro); }
        fn main() -> usize {
            var c: Caja<str> = Caja { dentro: [] };
            anadir(c.dentro, nuevo("x"));
            // `cuantos(c)` es una generica: para saber que devuelve hay que
            // elegir su copia, y eso pasa antes de deducir `A` y `B`.
            let p = par(cuantos(c), nuevo("fin"));
            imprimir($"{p.primero} {p.segundo}\\n");
        }''',
     "1 fin\n"),

    ("una lista dinamica escrita entera en Tcode, sobre `bloque<T>`",
     '''usar "std/vector";
        fn main() -> usize ! {
            var v: Vector<str> = Vector { datos: reservar(0), largo: 0 };
            agregar(v, nuevo("uno"));
            agregar(v, nuevo("dos"));
            agregar(v, nuevo("tres"));
            imprimir($"{cuantos(v)} de {capacidad(v)}: {try copia_de(v, 1)}");
            let ultimo = try sacar(v, vacio());
            ajustar(v);
            imprimir($" | {ultimo} | {cuantos(v)} de {capacidad(v)}");

            var n: Vector<usize> = Vector { datos: reservar(0), largo: 0 };
            var i = 0;
            while i < 100 { agregar(n, i * i); i = i + 1; }
            imprimir($" | {cuantos(n)} {try copia_de(n, 99)}\\n");
            return 0;
        }''',
     "3 de 8: dos | tres | 2 de 2 | 100 9801\n"),

    ("un bloque nace a ceros, y a ceros todo tipo es valido",
     '''fn main() -> usize {
            var b: bloque<str> = reservar(3);
            imprimir($"{largo(b)} [{b[0]}]");
            b[0] = nuevo("hola");
            b[2] = nuevo("mundo");
            redimensionar(b, 5);
            imprimir($" | {largo(b)} {b[0]} {b[2]} [{b[4]}]");
            redimensionar(b, 1);
            imprimir($" | {largo(b)} {b[0]}\\n");
        }''',
     "3 [] | 5 hola mundo [] | 1 hola\n"),

    ("`intercambiar` saca de un sitio sin dejar hueco",
     '''fn invertir_texto(xs: mut lista<str>) {
            if largo(xs) == 0 { return; }
            var i = 0;
            var j = largo(xs) - 1;
            while i < j {
                let a = intercambiar(xs[i], vacio());
                let b = intercambiar(xs[j], a);
                intercambiar(xs[i], b);
                i = i + 1;
                j = j - 1;
            }
        }
        fn main() -> usize {
            var xs: lista<str> = [];
            anadir(xs, nuevo("a")); anadir(xs, nuevo("b")); anadir(xs, nuevo("c"));
            invertir_texto(xs);
            for x en xs { imprimir($"{x} "); }
            imprimir("\\n");
        }''',
     "c b a \n"),

    ("una clausura captura por valor, incluso lo que tiene duenio",
     '''usar "std/lista";
        usar "std/texto";

        fn por_largo(a: &str, b: &str) -> bool { return largo(a) < largo(b); }

        fn main() -> usize {
            var xs: lista<str> = [];
            anadir(xs, nuevo("arandano"));
            anadir(xs, nuevo("pera"));
            anadir(xs, nuevo("aguacate"));

            // Captura un `str`: el struct de la clausura lo posee y lo
            // libera solo al acabar el bloque.
            let inicial = nuevo("a");
            let empiezan = fn[inicial](x: &str) -> bool {
                return empieza_con(vista(x), vista(inicial));
            };

            for c en filtradas(xs, empiezan) { imprimir($"{c} "); }
            let cuantas = cuantas_cumplen(xs,
                fn(x: &str) -> bool { return largo(x) > 4; });
            imprimir($"| {cuantas} | ");
            // La misma generica, con una funcion con nombre.
            for c en ordenadas_por(xs, por_largo) { imprimir($"{c} "); }
            imprimir("\\n");
        }''',
     "arandano aguacate | 2 | pera arandano aguacate \n"),

    ("`if` como valor, con ramas que son una expresion",
     '''fn clasificar(n: usize) -> str {
            return if n > 100 { nuevo("grande") } else { nuevo("pequeno") };
        }
        fn main() -> usize {
            let n = 7;
            let x = if n > 3 { 1 } else { 2 };
            let anidado = if n > 3 { if n > 5 { 10 } else { 20 } } else { 30 };
            imprimir($"{x} {clasificar(500)} {anidado}");
            imprimir($" {if n == 7 { "si" } else { "no" }}\\n");
        }''',
     "1 grande 10 si\n"),

    ("decimales, con lo que sale de los numeros parando el programa",
     '''usar "std/numero";
        fn main() -> usize ! {
            let a: f64 = 3.5;
            let b: f64 = 1.5;
            let uno: f64 = 1;            // un numero escrito no decide su tipo
            let z: f64 = 0;
            imprimir($"{a} {uno} {a * b + uno} {a / b}");
            imprimir($" {raiz(4.0)} {piso(3.7)} {techo(3.2)} {redondear(3.5)}");
            imprimir($" {absoluto(0.0 - 2.5)} {cerca(0.1 + 0.2, 0.3, 0.000001)}");
            // IEEE de siempre, pedido a proposito
            imprimir($" {a /? z} {try porcentaje_exacto(1.0, 8.0)}\\n");
            return 0;
        }''',
     "3.5 1.0 6.25 2.33333 2.0 3.0 4.0 4.0 2.5 true inf 12.5\n"),

    ("un entero y un decimal se convierten, y la conversion se comprueba",
     '''fn main() -> usize {
            let n: usize = 7;
            let x = n como f64;
            let exacto: f64 = 3.0;
            imprimir($"{x} {exacto como usize} {x / 2}\\n");
        }''',
     "7.0 3 3.5\n"),

    ("indexar lo que devuelve una llamada no la evalua dos veces ni filtra",
     '''fn hacer() -> lista<usize> {
            var xs: lista<usize> = [];
            anadir(xs, 7); anadir(xs, 9);
            return xs;
        }
        struct Caja { dentro: str }
        fn caja() -> Caja { return Caja { dentro: nuevo("hola") }; }
        fn main() -> usize {
            imprimir($"{hacer()[1]} {caja().dentro}\\n");
        }''',
     "9 hola\n"),

    ("una funcion es un valor: se pasa, se guarda y se llama",
     '''usar "std/lista";

        struct Cosa { nombre: str, n: usize }

        fn por_n(a: &Cosa, b: &Cosa) -> bool { return a.n < b.n; }
        fn al_reves(a: &usize, b: &usize) -> bool { return a > b; }
        fn doble(n: usize) -> usize { return n * 2; }

        fn aplicar(xs: &lista<usize>, f: fn(usize) -> usize) -> lista<usize> {
            var salida: lista<usize> = [];
            for x en xs { anadir(salida, f(x)); }
            return salida;
        }

        fn main() -> usize {
            var cs: lista<Cosa> = [];
            anadir(cs, Cosa { nombre: nuevo("c"), n: 9 });
            anadir(cs, Cosa { nombre: nuevo("a"), n: 2 });
            for c en ordenadas_por(cs, por_n) { imprimir($"{c.n}"); }

            var ns: lista<usize> = [];
            anadir(ns, 3); anadir(ns, 9); anadir(ns, 1);
            imprimir(" ");
            for n en ordenadas_por(ns, al_reves) { imprimir($"{n}"); }

            let g = doble;
            imprimir($" {aplicar(ns, doble)[1]} {g(10)}\\n");
        }''',
     "29 931 18 20\n"),

    ("anchos fijos, bits y conversiones",
     '''fn main() -> usize {
            let a: u8 = 200;
            let b: u8 = 55;
            let c: i32 = 100000;
            let mascara: u32 = 4278190080;
            let v: u32 = 3735928559;
            // Los bits atan mas que las comparaciones: esto es `(v & m) == x`,
            // no `v & (m == x)` como seria en C.
            let alto = (v & mascara) >> 24 == 222;
            imprimir($"{a + b} {c * 2} {v ^ v} {~a} {alto}");
            imprimir($" {v como? u8} {a como u32}\\n");
        }''',
     "255 200000 0 55 true 239 200\n"),

    ("un `str` guarda bytes, no texto",
     '''usar "std/bytes";
        fn main() -> usize {
            let crudo = "\\xde\\xad\\xbe\\xef";
            let acentos = "camión";
            let cero = "a\\x00b";
            imprimir($"{largo(crudo)} {a_hex(crudo)} {largo(acentos)}");
            imprimir($" {acentos} {largo(cero)} {a_hex(cero)}\\n");
        }''',
     "4 deadbeef 7 camión 3 610062\n"),

    ("enteros que van y vuelven de un buffer",
     '''usar "std/bytes";
        fn main() -> usize ! {
            var buf = vacio();
            poner_u32(buf, 3735928559);
            poner_u16(buf, 513);
            poner_u64(buf, 72057594037927936);
            imprimir($"{a_hex(vista(buf))}\\n");
            imprimir($"{try leer_u32(vista(buf), 0)} {try leer_u16(vista(buf), 4)}");
            imprimir($" {try leer_u64(vista(buf), 6)}");
            let vuelta = try de_hex("deadbeef");
            imprimir($" {largo(vuelta)} {leer_u8(vista(buf), 999) sino 0}\\n");
            return 0;
        }''',
     "deadbeef02010100000000000000\n3735928559 513 72057594037927936 4 0\n"),

    ("un contenedor propio, escrito en Tcode y no en el compilador",
     '''struct Pila<T> { cosas: lista<T> }

        fn vacia<T>(p: &Pila<T>) -> bool { return largo(p.cosas) == 0; }
        fn apilar<T>(p: mut Pila<T>, x: T) { anadir(p.cosas, x); }
        fn cima<T>(p: &Pila<T>) -> T ! {
            if vacia(p) { falla "la pila esta vacia"; }
            return copiar(p.cosas[largo(p.cosas) - 1]);
        }

        // Un tipo generico que se contiene a si mismo a traves de una lista.
        struct Nodo<T> { valor: T, hijos: lista<Nodo<T>> }

        fn hojas<T>(n: &Nodo<T>) -> usize {
            if largo(n.hijos) == 0 { return 1; }
            var t = 0;
            for h en n.hijos { t = t + hojas(h); }
            return t;
        }

        fn main() -> usize ! {
            var ps: Pila<str> = Pila { cosas: [] };
            apilar(ps, nuevo("a"));
            apilar(ps, nuevo("b"));
            var pn: Pila<usize> = Pila { cosas: [] };
            apilar(pn, 42);

            var raiz: Nodo<usize> = Nodo { valor: 1, hijos: [] };
            let h1: Nodo<usize> = Nodo { valor: 2, hijos: [] };
            let h2: Nodo<usize> = Nodo { valor: 3, hijos: [] };
            anadir(raiz.hijos, h1);
            anadir(raiz.hijos, h2);

            imprimir($"{try cima(ps)} {try cima(pn)} {vacia(ps)} {hojas(raiz)}\\n");
            return 0;
        }''',
     "b 42 false 2\n"),

    ("`std/par`: devolver dos valores, sin que el compilador sepa nada",
     '''usar "std/par";
        fn dividir_con_resto(a: usize, b: usize) -> Par<usize, usize> ! {
            if b == 0 { falla "division por cero"; }
            return par(a / b, a % b);
        }
        fn main() -> usize ! {
            let r = try dividir_con_resto(17, 5);
            let t = par(nuevo("clave"), 9);
            let v = volteado(t);
            imprimir($"{r.primero} {r.segundo} {t.primero} {v.segundo}\\n");
            return 0;
        }''',
     "3 2 clave clave\n"),

    ("restricciones: el cuerpo dice lo que necesita del elemento",
     '''usar "std/lista";
        fn main() -> usize ! {
            var ns: lista<usize> = [];
            anadir(ns, 3); anadir(ns, 9); anadir(ns, 5);
            var ss: lista<str> = [];
            anadir(ss, nuevo("pera")); anadir(ss, nuevo("uva"));
            let buscado = nuevo("uva");
            invertir(ns);
            let vacia: lista<usize> = [];
            imprimir($"{suma(ns)} {try maximo(ns)} {try minimo(ns)} {suma(vacia)}");
            imprimir($" {try maximo(ss)} {incluye(ss, buscado)}");
            imprimir($" {try posicion(ss, buscado)} {ns[0]}\\n");
            return 0;
        }''',
     "17 9 3 0 uva true 1 5\n"),

    ("`igual` y `menor` valen para cualquier tipo sin partes",
     '''fn main() -> usize {
            let s = nuevo("x");
            imprimir($"{igual(1, 1)} {igual("a", "a")} {menor(2, 9)}");
            imprimir($" {menor("a", "b")} {igual(true, false)} {igual(s, "x")}\\n");
        }''',
     "true true true true false true\n"),

    ("`copiar` es copia profunda: tocar el original no toca la copia",
     '''struct Cosa { nombre: str, n: usize }
        fn main() -> usize {
            var xs: lista<str> = [];
            anadir(xs, nuevo("hola"));
            let copia_xs = copiar(xs);
            empujar(xs[0], "!!");

            var dentro: lista<lista<str>> = [];
            anadir(dentro, copiar(xs));
            let copia_dentro = copiar(dentro);
            empujar(dentro[0][0], "??");

            let c = Cosa { nombre: nuevo("a"), n: 1 };
            let c2 = copiar(c);

            var m: mapa<str, str> = [];
            poner(m, "k", nuevo("v"));
            let m2 = copiar(m);

            imprimir($"{xs[0]} {copia_xs[0]} {dentro[0][0]} {copia_dentro[0][0]}");
            imprimir($" {c2.nombre}{c2.n} {largo(m2)} {copiar(7)}\\n");
        }''',
     "hola!! hola hola!!?? hola!! a1 1 7\n"),

    ("una generica se copia una vez por cada juego de tipos",
     '''struct Punto { x: usize, y: usize }

        fn primero<T>(xs: &lista<T>) -> T ! {
            if largo(xs) == 0 { falla "lista vacia"; }
            return xs[0];
        }

        fn cuantos<K, V>(m: &mapa<K, V>) -> usize { return largo(m); }

        // una generica que llama a otra generica
        fn primero_o<T>(xs: &lista<T>, alterno: T) -> T {
            return primero(xs) sino alterno;
        }

        fn main() -> usize ! {
            var ns: lista<usize> = [];
            anadir(ns, 7);
            var ps: lista<Punto> = [];
            anadir(ps, Punto { x: 1, y: 2 });
            let p = try primero(ps);

            let vacia: lista<usize> = [];
            var m: mapa<str, usize> = [];
            poner(m, "a", 1);

            imprimir($"{try primero(ns)} {p.y} {primero_o(vacia, 99)} {cuantos(m)}\\n");
            return 0;
        }''',
     "7 2 99 1\n"),

    ("la misma generica vale para un tipo que posee y para uno que no",
     '''usar "std/lista";
        fn main() -> usize ! {
            var ns: lista<usize> = [];
            anadir(ns, 3); anadir(ns, 9);
            var xs: lista<str> = [];
            imprimir($"{esta_vacia(ns)} {esta_vacia(xs)} {try ultima_posicion(ns)}\\n");
            return 0;
        }''',
     "false true 1\n"),

    # Los cinco caminos que salen antes de tiempo tienen que soltar los
    # temporales de la sentencia: la limpieza de fin de sentencia se emite
    # detras del `return` y no llega a ejecutarse.
    ("descartar el `str` que devuelve una llamada no filtra ni rompe el C",
     '''fn envuelto(n: usize) -> str {
            var s = nuevo("n=");
            empujar(s, texto(n));
            return s;
        }
        fn main() -> usize {
            // El valor se tira: hay que liberarlo, y no se puede tomar la
            // direccion de una llamada.
            envuelto(7);
            imprimir("ok\\n");
        }''',
     "ok\n"),

    ("un temporal dentro de lo que se devuelve no se filtra",
     '''usar "std/texto";
        fn etiqueta(v: view) -> str { return $"[{rellenar(v, 8)}]"; }
        fn marcar(v: view) -> str ! {
            if largo(v) == 0 { falla "vacio"; }
            return $"<{rellenar(v, 4)}>";
        }
        fn ambas(v: view) -> str ! {
            let a = try marcar(v);
            return $"{etiqueta(v)}{a}";
        }
        fn main() -> usize ! { imprimir($"{try ambas("ab")}\\n"); return 0; }''',
     "[ab      ]<ab  >\n"),

    ("de un prestamo si se copia un escalar",
     '''struct S { a: str, n: usize }
        fn f() -> usize ! {
            var m: mapa<str, S> = [];
            poner(m, "x", S { a: nuevo("hola"), n: 7 });
            let r: &S = try obtener(m, "x");
            let copia: usize = r.n;
            imprimir(copia); imprimir("\\n");
            return 0;
        }
        fn main() -> usize ! { try f(); return 0; }''',
     "7\n"),

    ("aritmetica y control",
     '''fn f(n: usize) -> usize {
            var acc: usize = 0;
            var i: usize = 1;
            while i <= n { acc = acc + i; i = i + 1; }
            return acc;
        }
        fn main() -> usize { imprimir(f(10)); imprimir("\\n"); return 0; }''',
     "55\n"),

    ("prestamo que termina al cerrar el bloque",
     '''fn main() -> usize {
            var s: str = nuevo("hola");
            if true { let v: view = vista(s); imprimir(largo(v)); }
            empujar(s, " mundo");
            imprimir("\\n");
            imprimir(s);
            imprimir("\\n");
            return 0;
        }''',
     "4\nhola mundo\n"),

    ("prestamo mutable, sin tomar posesion",
     '''fn agregar(s: mut str) { empujar(s, "!"); }
        fn main() -> usize {
            var s: str = nuevo("hey");
            agregar(s); agregar(s);
            imprimir(s); imprimir("\\n");
            return 0;
        }''',
     "hey!!\n"),

    ("mover a una funcion y devolverlo",
     '''fn adornar(s: str) -> str { return s; }
        fn main() -> usize {
            let a: str = nuevo("dato");
            let b: str = adornar(a);
            imprimir(b); imprimir("\\n");
            return 0;
        }''',
     "dato\n"),

    ("aritmetica envolvente cuando se pide a proposito",
     '''fn main() -> usize {
            let a: i64 = 2;
            let b: i64 = a *? 3;
            imprimir(b); imprimir("\\n");
            return 0;
        }''',
     "6\n"),

    ("devolver vistas atadas a un parametro",
     '''fn primero(v: view) -> view { return rebanar(v, 0, 1); }
        fn cola(v: view) -> view { return rebanar(v, 1, largo(v)); }
        fn estatica() -> view { return "constante"; }
        fn main() -> usize {
            let s: str = nuevo("tcode!!");
            imprimir(primero(vista(s)));
            imprimir(cola(vista(s)));
            imprimir("\\n");
            imprimir(estatica());
            imprimir("\\n");
            return 0;
        }''',
     "tcode!!\nconstante\n"),

    ("un prestamo que muere libera al duenio",
     '''fn primero(v: view) -> view { return rebanar(v, 0, 1); }
        fn main() -> usize {
            var s: str = nuevo("hola");
            if true { imprimir(primero(vista(s))); }
            empujar(s, " mundo");
            imprimir(s); imprimir("\\n");
            return 0;
        }''',
     "hhola mundo\n"),

    ("structs: campos, construccion y mutacion",
     '''struct Punto { x: usize, y: usize }
        struct Persona { nombre: str, edad: usize }
        fn main() -> usize {
            let a: Punto = Punto { x: 3, y: 4 };
            imprimir(a.x * a.x + a.y * a.y); imprimir("\\n");
            var p: Persona = Persona { nombre: nuevo("Nel"), edad: 40 };
            empujar(p.nombre, "son");
            p.edad = p.edad + 1;
            imprimir(p.nombre); imprimir(" "); imprimir(p.edad);
            imprimir("\\n");
            return 0;
        }''',
     "25\nNelson 41\n"),

    ("arreglos: indexar, escribir y recorrer",
     '''fn main() -> usize {
            var v: [usize; 5] = [10, 20, 30, 40, 50];
            v[2] = 99;
            var suma: usize = 0;
            var i: usize = 0;
            while i < 5 { suma = suma + v[i]; i = i + 1; }
            imprimir(suma); imprimir("\\n");
            return 0;
        }''',
     "219\n"),

    ("un arreglo de `str` se libera elemento por elemento",
     '''fn main() -> usize {
            var eq: [str; 3] = [nuevo("uno"), nuevo("dos"), nuevo("tres")];
            empujar(eq[1], "!");
            var i: usize = 0;
            while i < 3 { imprimir(eq[i]); imprimir(" "); i = i + 1; }
            imprimir("\\n");
            return 0;
        }''',
     "uno dos! tres \n"),

    ("structs anidados y arreglos de struct",
     '''struct Punto { x: usize, y: usize }
        struct Caja { esquina: Punto, ancho: usize }
        fn main() -> usize {
            var cajas: [Caja; 2] = [
                Caja { esquina: Punto { x: 1, y: 2 }, ancho: 10 },
                Caja { esquina: Punto { x: 3, y: 4 }, ancho: 20 }
            ];
            cajas[1].esquina.x = 99;
            imprimir(cajas[0].esquina.y); imprimir(" ");
            imprimir(cajas[1].esquina.x); imprimir(" ");
            imprimir(cajas[1].ancho); imprimir("\\n");
            return 0;
        }''',
     "2 99 20\n"),

    ("un struct devuelto se mueve, no se libera dos veces",
     '''struct Persona { nombre: str, edad: usize }
        fn crear(n: view) -> Persona { return Persona { nombre: nuevo(n), edad: 1 }; }
        fn main() -> usize {
            let p: Persona = crear("Ana");
            imprimir(p.nombre); imprimir("\\n");
            return 0;
        }''',
     "Ana\n"),

    ("fallos: propagar con try, sustituir con sino",
     '''fn dividir(a: usize, b: usize) -> usize ! {
            if b == 0 { falla "division por cero"; }
            return a / b;
        }
        fn media(a: usize, b: usize, n: usize) -> usize ! {
            return try dividir(a + b, n);
        }
        fn main() -> usize {
            imprimir(media(10, 20, 2) sino 0); imprimir("\\n");
            imprimir(media(10, 20, 0) sino 999); imprimir("\\n");
            return 0;
        }''',
     "15\n999\n"),

    ("un fallo libera lo que ya se habia reservado",
     '''fn cargar(nombre: view) -> str ! {
            var s: str = nuevo("dato de ");
            empujar(s, nombre);
            if largo(nombre) == 0 { falla "nombre vacio"; }
            return s;
        }
        fn envolver(nombre: view) -> str ! {
            var acc: str = nuevo("[");
            let dato: str = try cargar(nombre);
            empujar(acc, vista(dato));
            empujar(acc, "]");
            return acc;
        }
        fn main() -> usize {
            let bueno: str = envolver("uno") sino nuevo("(sin dato)");
            imprimir(bueno); imprimir("\\n");
            let malo: str = envolver("") sino nuevo("(sin dato)");
            imprimir(malo); imprimir("\\n");
            return 0;
        }''',
     "[dato de uno]\n(sin dato)\n"),

    ("prestar un struct de un arreglo, para leer y para modificar",
     '''struct Articulo { nombre: str, unidades: usize }
        fn describir(a: &Articulo) -> str {
            var s: str = vacio();
            empujar(s, vista(a.nombre));
            empujar(s, ": ");
            return s;
        }
        fn reponer(a: mut Articulo, cuantas: usize) {
            a.unidades = a.unidades + cuantas;
            empujar(a.nombre, "*");
        }
        fn main() -> usize {
            var inv: [Articulo; 2] = [
                Articulo { nombre: nuevo("tornillos"), unidades: 420 },
                Articulo { nombre: nuevo("tuercas"),   unidades: 310 }
            ];
            reponer(inv[1], 90);
            var i: usize = 0;
            while i < 2 {
                let d: str = describir(inv[i]);
                imprimir(d); imprimir(inv[i].unidades); imprimir("\\n");
                i = i + 1;
            }
            return 0;
        }''',
     "tornillos: 420\ntuercas*: 400\n"),

    ("dos prestamos de solo lectura conviven",
     '''struct P { u: usize }
        fn suma(a: &P, b: &P) -> usize { return a.u + b.u; }
        fn main() -> usize {
            var p: P = P { u: 21 };
            imprimir(suma(p, p)); imprimir("\\n");
            return 0;
        }''',
     "42\n"),

    ("`mut` sobre cualquier tipo, no solo `str`",
     '''fn doblar(n: mut usize) { n = n * 2; }
        fn main() -> usize {
            var x: usize = 7;
            doblar(x); doblar(x);
            imprimir(x); imprimir("\\n");
            return 0;
        }''',
     "28\n"),

    ("mapa: poner, reemplazar, consultar y contar",
     '''fn main() -> usize {
            var m: mapa<str, usize> = [];
            poner(m, "uno", 1);
            poner(m, "dos", 2);
            poner(m, "uno", 11);
            imprimir(largo(m)); imprimir(" ");
            imprimir(tiene(m, "dos")); imprimir(" ");
            imprimir(tiene(m, "tres")); imprimir(" ");
            imprimir(obtener(m, "uno") sino 0); imprimir(" ");
            imprimir(obtener(m, "tres") sino 99); imprimir("\\n");
            return 0;
        }''',
     "2 true false 11 99\n"),

    ("mapa: crece y rehace sin perder nada",
     '''fn clave_de(i: usize) -> str {
            var k: str = nuevo("c");
            let n: str = texto(i);
            empujar(k, vista(n));
            return k;
        }
        fn main() -> usize {
            var m: mapa<str, usize> = [];
            var i: usize = 0;
            while i < 200 {
                let k: str = clave_de(i);
                poner(m, vista(k), i * 3);
                i = i + 1;
            }
            var malas: usize = 0;
            i = 0;
            while i < 200 {
                let k: str = clave_de(i);
                if (obtener(m, vista(k)) sino 999999) != i * 3 {
                    malas = malas + 1;
                }
                i = i + 1;
            }
            let ks: lista<str> = claves(m);
            imprimir(largo(m)); imprimir(" ");
            imprimir(malas); imprimir(" ");
            imprimir(largo(ks)); imprimir("\\n");
            return 0;
        }''',
     "200 0 200\n"),

    ("argumentos: siempre hay al menos el nombre del programa",
     '''fn main() -> usize {
            imprimir(n_argumentos() >= 1); imprimir(" ");
            imprimir(largo(argumento(0)) > 0); imprimir("\\n");
            return 0;
        }''',
     "true true\n"),

    ("ordenar numeros y textos",
     '''fn main() -> usize {
            var n: lista<usize> = [];
            anadir(n, 30); anadir(n, 4); anadir(n, 17); anadir(n, 4);
            ordenar(n);
            var i: usize = 0;
            while i < largo(n) { imprimir(n[i]); imprimir(" "); i = i + 1; }
            var p: lista<str> = [];
            anadir(p, nuevo("pera")); anadir(p, nuevo("ana"));
            anadir(p, nuevo("kiwi"));
            ordenar(p);
            i = 0;
            while i < largo(p) { imprimir(p[i]); imprimir(" "); i = i + 1; }
            imprimir(menor("ana", "pera")); imprimir(" ");
            imprimir(menor("pera", "ana")); imprimir("\\n");
            return 0;
        }''',
     "4 4 17 30 ana kiwi pera true false\n"),

    ("quitar de un mapa cierra el hueco sin perder vecinos",
     '''fn clave_de(i: usize) -> str {
            var k: str = nuevo("c");
            let n: str = texto(i);
            empujar(k, vista(n));
            return k;
        }
        fn main() -> usize {
            var m: mapa<str, usize> = [];
            var i: usize = 0;
            while i < 200 { let k: str = clave_de(i); poner(m, vista(k), i); i = i + 1; }
            i = 0;
            var quitadas: usize = 0;
            while i < 200 {
                let k: str = clave_de(i);
                if quitar(m, vista(k)) { quitadas = quitadas + 1; }
                i = i + 2;
            }
            var malas: usize = 0;
            i = 1;
            while i < 200 {
                let k: str = clave_de(i);
                if (obtener(m, vista(k)) sino 999999) != i { malas = malas + 1; }
                i = i + 2;
            }
            imprimir(quitadas); imprimir(" "); imprimir(largo(m)); imprimir(" ");
            imprimir(malas); imprimir(" "); imprimir(quitar(m, "jamas"));
            imprimir("\\n");
            return 0;
        }''',
     "100 100 0 false\n"),

    ("for con break y continue sobre escalares y duenios",
     '''fn main() -> usize {
            var xs: lista<usize> = [];
            anadir(xs, 5); anadir(xs, 12); anadir(xs, 7);
            anadir(xs, 30); anadir(xs, 1);
            for x en xs {
                if x == 7 { continue; }
                if x > 20 { break; }
                imprimir(x); imprimir(" ");
            }
            var ns: lista<str> = [];
            anadir(ns, nuevo("ana")); anadir(ns, nuevo("beto"));
            anadir(ns, nuevo("cielo"));
            for n en ns {
                let etiqueta: str = texto(largo(vista(n)));
                imprimir(n); imprimir(":"); imprimir(etiqueta); imprimir(" ");
                if largo(vista(n)) > 4 { break; }
            }
            let fijo: [usize; 4] = [9, 8, 7, 6];
            for v en fijo { imprimir(v); }
            imprimir("\\n");
            return 0;
        }''',
     "5 12 ana:3 beto:4 cielo:5 9876\n"),

    ("salir de un `for` libera lo de dentro de la vuelta",
     '''fn main() -> usize {
            var ns: lista<str> = [];
            var i: usize = 0;
            while i < 50 { anadir(ns, nuevo("dato")); i = i + 1; }
            var vueltas: usize = 0;
            for n en ns {
                let copia: str = nuevo("x");
                let otra: str = texto(largo(vista(n)));
                vueltas = vueltas + largo(vista(copia)) + largo(vista(otra));
                if vueltas > 10 { break; }
            }
            imprimir(vueltas); imprimir("\\n");
            return 0;
        }''',
     "12\n"),

    ("recorrer un mapa prestando clave y valor",
     '''fn main() -> usize {
            var m: mapa<str, usize> = [];
            poner(m, "uno", 1); poner(m, "dos", 2); poner(m, "tres", 3);
            poner(m, "cuatro", 4); poner(m, "cinco", 5);
            quitar(m, "tres");
            var suma: usize = 0;
            var letras: usize = 0;
            for k, v en m {
                suma = suma + v;
                letras = letras + largo(vista(k));
            }
            imprimir(suma); imprimir(" "); imprimir(letras); imprimir("\\n");
            return 0;
        }''',
     "12 17\n"),

    ("recorrer un mapa grande sin copiar nada",
     '''fn clave_de(i: usize) -> str {
            var k: str = nuevo("c");
            let n: str = texto(i);
            empujar(k, vista(n));
            return k;
        }
        fn main() -> usize {
            var m: mapa<str, usize> = [];
            var i: usize = 0;
            while i < 300 { let k: str = clave_de(i); poner(m, vista(k), i); i = i + 1; }
            var suma: usize = 0;
            var cuantas: usize = 0;
            for k, v en m { suma = suma + v; cuantas = cuantas + 1; }
            imprimir(cuantas); imprimir(" "); imprimir(suma); imprimir("\\n");
            return 0;
        }''',
     "300 44850\n"),

    ("mapa de textos: reemplazo, prestamo y recorrido",
     '''fn main() -> usize {
            var cfg: mapa<str, str> = [];
            poner(cfg, "host", nuevo("localhost"));
            poner(cfg, "puerto", nuevo("8080"));
            poner(cfg, "host", nuevo("127.0.0.1"));
            imprimir(obtener(cfg, "host") sino "?"); imprimir(" ");
            imprimir(obtener(cfg, "puerto") sino "?"); imprimir(" ");
            imprimir(obtener(cfg, "falta") sino "(nada)"); imprimir(" ");
            var letras: usize = 0;
            for k, v en cfg { letras = letras + largo(vista(k)) + largo(v); }
            imprimir(letras); imprimir(" ");
            imprimir(quitar(cfg, "puerto")); imprimir(" ");
            imprimir(largo(cfg)); imprimir("\\n");
            return 0;
        }''',
     "127.0.0.1 8080 (nada) 23 true 1\n"),

    ("cadenas interpoladas",
     '''fn main() -> usize {
            let quien: str = nuevo("mundo");
            let n: usize = 3;
            let ok: bool = true;
            let m: str = $"hola {quien}, van {n + 1} veces, ok={ok} {{y}}";
            imprimir(m); imprimir("\\n");
            imprimir($"suelta: {n} {quien}\\n");
            var i: usize = 0;
            while i < 3 {
                imprimir($"[{i}]");
                i = i + 1;
            }
            imprimir("\\n");
            return 0;
        }''',
     "hola mundo, van 4 veces, ok=true {y}\nsuelta: 3 mundo\n[0][1][2]\n"),

    ("tabla de simbolos: mapa de structs con prestamo",
     '''struct Simbolo { tipo: str, mutable: bool, usos: usize }
        fn main() -> usize ! {
            var tabla: mapa<str, Simbolo> = [];
            poner(tabla, "n", Simbolo { tipo: nuevo("usize"), mutable: false,
                                        usos: 3 });
            poner(tabla, "s", Simbolo { tipo: nuevo("str"), mutable: true,
                                        usos: 1 });
            if true {
                // El prestamo vive solo aqui dentro: fuera se vuelve a poder
                // tocar la tabla.
                let a: &Simbolo = try obtener(tabla, "n");
                imprimir($"{a.tipo} {a.mutable} {a.usos} ");
            }
            var total: usize = 0;
            for clave, sim en tabla {
                total = total + largo(vista(clave)) + sim.usos;
            }
            imprimir($"{total} {largo(tabla)} {quitar(tabla, \\"s\\")}\\n");
            return 0;
        }''',
     "usize false 3 6 2 true\n"),

    ("modificar en el sitio lo que guarda un mapa",
     '''struct Simbolo { tipo: str, usos: usize }
        fn main() -> usize ! {
            var tabla: mapa<str, Simbolo> = [];
            poner(tabla, "n", Simbolo { tipo: nuevo("usize"), usos: 0 });
            poner(tabla, "s", Simbolo { tipo: nuevo("str"), usos: 0 });
            var i: usize = 0;
            while i < 5 {
                let s: &mut Simbolo = try obtener_mut(tabla, "n");
                s.usos = s.usos + 1;
                empujar(s.tipo, ".");
                i = i + 1;
            }
            var claves_ord: lista<str> = claves(tabla);
            ordenar(claves_ord);
            for c en claves_ord {
                let s: &Simbolo = try obtener(tabla, vista(c));
                imprimir($"{c}:{s.tipo}:{s.usos} ");
            }
            imprimir("\\n");
            return 0;
        }''',
     "n:usize.....:5 s:str:0 \n"),

    ("el tipo se deduce del valor",
     '''struct P { x: usize, y: usize }
        fn main() {
            let n = 42;
            let ok = true;
            let s = nuevo("hola");
            let v = vista(s);
            let p = P { x: 1, y: 2 };
            var xs = [10, 20, 30];
            let t = texto(n);
            let m = $"{n}/{ok}";
            imprimir($"{n} {ok} {s} {largo(v)} {p.x} {xs[1]} {t} {m}\\n");
        }''',
     "42 true hola 4 1 20 42 42/true\n"),

    ("un `str` se presta solo donde se pide una vista",
     '''fn medir(v: view) -> usize { return largo(v); }
        fn juntar(a: view, b: view) -> str {
            var s = nuevo(a);
            empujar(s, b);
            return s;
        }
        fn main() {
            let uno = nuevo("hola");
            let dos = nuevo(" mundo");
            let todo = juntar(uno, dos);
            imprimir($"{medir(uno)} {medir(todo)} {todo}\\n");
        }''',
     "4 10 hola mundo\n"),

    ("se puede prestar un valor recien hecho",
     '''fn medir(v: view) -> usize { return largo(v); }
        fn mayusculas(v: view) -> str {
            var s = nuevo(v);
            empujar(s, "!");
            return s;
        }
        fn cuantos(xs: &lista<str>) -> usize { return largo(xs); }
        fn tres() -> lista<str> {
            var xs: lista<str> = [];
            anadir(xs, nuevo("a")); anadir(xs, nuevo("bb"));
            anadir(xs, nuevo("ccc"));
            return xs;
        }
        fn main() {
            imprimir(medir(mayusculas("hola")));
            imprimir(" ");
            imprimir(cuantos(tres()));
            imprimir(" ");
            var total = 0;
            for x en tres() { total = total + largo(x); }
            imprimir(total);
            imprimir("\\n");
        }''',
     "5 3 6\n"),

    ("la biblioteca estandar: texto",
     '''usar "std/texto";
        fn main() -> usize ! {
            let linea = nuevo("   hola, mundo cruel   ");
            imprimir($"[{recortar(linea)}] ");
            imprimir($"{empieza_con(recortar(linea), "hola")} ");
            imprimir($"{termina_con(recortar(linea), "cruel")} ");
            imprimir($"{contiene(linea, "mundo")} ");
            imprimir($"{indice_de(linea, "mundo") sino 999} ");
            let trozos = try partir("a,b,,c", ",");
            imprimir($"{largo(trozos)} [{unir(trozos, "|")}] ");
            imprimir($"{repetir("-", 5)} ");
            imprimir($"{try reemplazar("aaa", "a", "b")} ");
            imprimir($"{try a_entero(recortar(nuevo("  42  ")))}\\n");
        }''',
     "[hola, mundo cruel] true true true 9 4 [a|b||c] ----- bbb 42\n"),

    ("la biblioteca estandar: contar y mayores",
     '''usar "std/cuenta";
        fn main() {
            let texto = nuevo("uno dos uno tres dos uno");
            let cuenta = contar(palabras(minusculas(texto)));
            imprimir($"{largo(cuenta)} ");
            for p en mayores(cuenta, 2) {
                imprimir($"{p}:{obtener(cuenta, p) sino 0} ");
            }
            imprimir("\\n");
        }''',
     "3 uno:3 dos:2 \n"),

    ("rebanadas de vista",
     '''fn main() -> usize {
            let s: str = nuevo("abcdefgh");
            imprimir(rebanar(vista(s), 2, 5));
            imprimir("\\n");
            return 0;
        }''',
     "cde\n"),

    ("listas dinamicas: crecer, indexar y medir",
     '''fn suma(xs: &lista<usize>) -> usize {
            var total: usize = 0;
            var i: usize = 0;
            while i < largo(xs) { total = total + xs[i]; i = i + 1; }
            return total;
        }
        fn main() -> usize {
            var xs: lista<usize> = [];
            var i: usize = 0;
            while i < 1000 { anadir(xs, i); i = i + 1; }
            imprimir(largo(xs)); imprimir(" "); imprimir(suma(xs));
            imprimir("\\n"); return 0;
        }''',
     "1000 499500\n"),

    ("una lista de duenios libera y mueve cada elemento",
     '''fn main() -> usize {
            var xs: lista<str> = [nuevo("uno"), nuevo("dos")];
            let tercero: str = nuevo("tres");
            anadir(xs, tercero);
            var i: usize = 0;
            while i < largo(xs) { imprimir(xs[i]); imprimir(" "); i = i + 1; }
            imprimir("\\n"); return 0;
        }''',
     "uno dos tres \n"),

    ("reasignar propiedad invalida al duenio anterior",
     '''fn main() -> usize {
            let a: str = nuevo("movido");
            let b: str = a;
            imprimir(b); imprimir("\\n"); return 0;
        }''',
     "movido\n"),

    ("devolver un compuesto entrega sus campos sin liberarlos",
     '''struct Caja { nombre: str }
        fn crear() -> Caja {
            let s: str = nuevo("vivo");
            return Caja { nombre: s };
        }
        fn main() -> usize {
            let c: Caja = crear(); imprimir(c.nombre); imprimir("\\n"); return 0;
        }''',
     "vivo\n"),

    ("sino mueve su alternativa solo en el camino de fallo",
     '''fn elegir(falla_ahora: bool) -> str ! {
            if falla_ahora { falla "pedido"; }
            return nuevo("resultado");
        }
        fn caso(falla_ahora: bool) -> str {
            let respaldo: str = nuevo("respaldo");
            return elegir(falla_ahora) sino respaldo;
        }
        fn main() -> usize {
            let a: str = caso(false); let b: str = caso(true);
            imprimir(a); imprimir(" "); imprimir(b); imprimir("\\n"); return 0;
        }''',
     "resultado respaldo\n"),

    ("listas vacias usan el tipo de retorno y de argumento",
     '''fn vacia() -> lista<usize> { return []; }
        fn contar(xs: lista<usize>) -> usize { return largo(xs); }
        fn main() -> usize {
            let xs: lista<usize> = vacia();
            imprimir(largo(xs)); imprimir(" "); imprimir(contar([]));
            imprimir("\\n"); return 0;
        }''',
     "0 0\n"),

    ("listas recursivas tienen tamano finito",
     '''struct Nodo { valor: usize, hijos: lista<Nodo> }
        fn hoja(n: usize) -> Nodo { return Nodo { valor: n, hijos: [] }; }
        fn main() -> usize {
            var raiz: Nodo = hoja(1);
            anadir(raiz.hijos, hoja(2));
            anadir(raiz.hijos, hoja(3));
            imprimir(raiz.valor + raiz.hijos[0].valor + raiz.hijos[1].valor);
            imprimir("\\n"); return 0;
        }''',
     "6\n"),

    ("texto y bytes permiten procesar cadenas construidas",
     '''fn main() -> usize {
            let n: str = texto(42);
            let b: str = texto(true);
            imprimir(n); imprimir(" "); imprimir(b); imprimir(" ");
            imprimir(byte("Az", 1)); imprimir("\\n"); return 0;
        }''',
     "42 true 122\n"),

    ("un fallo al abrir archivo se puede sustituir",
     '''fn main() -> usize {
            let s: str = leer_archivo("/ruta/que/no/existe/tcode")
                         sino nuevo("sin datos");
            imprimir(s); imprimir("\\n"); return 0;
        }''',
     "sin datos\n"),
]


# Programas que compilan, pero sobre los que el compilador tiene algo que
# decir. Un aviso no impide compilar: apunta a algo que probablemente no era
# lo que se queria. Un `_` delante del nombre lo silencia.
AVISA = [
    ("variable declarada y nunca usada",
     'fn f() { var x: usize = 1; imprimir("hola"); }',
     "`x` se declara y no se usa"),

    ("un guion bajo delante lo silencia",
     'fn f() { var _x: usize = 1; imprimir("hola"); }',
     None),

    ("`var` que nunca se modifica",
     'fn f() { var x: usize = 1; imprimir(x); }',
     "puede ser `let`"),

    ("valores que se asignan y nunca se leen",
     'fn f() { var x: usize = 1; x = 2; imprimir("h"); }',
     "nunca se leen"),

    ("parametro que no se usa",
     'fn g(a: usize, b: usize) -> usize { return a; }',
     "el parametro `b` de `g` no se usa"),

    ("parametro `mut` que nunca se modifica",
     'struct P { u: usize } fn f(p: mut P) -> usize { return p.u; }',
     "podria ser `&P`"),

    ("un programa correcto no dice nada",
     'fn f() -> usize { let a: usize = 1; var b: usize = 2;'
     ' b = b + a; return b; }',
     None),

    ("prestar algo cuenta como usarlo",
     'fn f() { let s: str = nuevo("a"); imprimir(largo(vista(s))); }',
     None),

    ("moverlo tambien cuenta como usarlo",
     'fn g(s: str) -> usize { return largo(vista(s)); }'
     ' fn f() { let s: str = nuevo("a"); imprimir(g(s)); }',
     None),

    ("modificar cuenta como modificar",
     'fn f() { var s: str = nuevo("a"); empujar(s, "b");'
     ' imprimir(largo(vista(s))); }',
     None),
]


# Programas que compilan pero deben ABORTAR en tiempo de ejecucion.
ABORTA = [
    ("un NaN no sigue adelante: para donde aparece",
     'fn main() -> usize { let z: f64 = 0; let a: f64 = 0;'
     ' imprimir(a / z); return 0; }',
     "no dio un numero"),

    ("un infinito tampoco",
     'fn main() -> usize { let g: f64 = 1e308; imprimir(g * 10.0); return 0; }',
     "no dio un numero"),

    ("la raiz de un negativo para, y dice por que",
     'fn main() -> usize { let n: f64 = 0.0 - 1.0; imprimir(raiz(n)); return 0; }',
     "la raiz de un negativo no es un numero"),

    ("una conversion que pierde la parte decimal para",
     'fn main() -> usize { let f: f64 = 3.7; imprimir(f como usize); return 0; }',
     "no cabe en `usize` viniendo de `f64`"),

    ("desbordamiento al multiplicar",
     '''fn main() -> usize {
            var a: usize = 1;
            var i: usize = 0;
            while i < 40 { a = a * 100000; i = i + 1; }
            imprimir(a);
            return 0;
        }''',
     "desbordamiento en `*`"),

    ("resta que se va bajo cero en usize",
     'fn main() -> usize { let a: usize = 1; let b: usize = a - 2;'
     ' imprimir(b); return 0; }',
     "desbordamiento en `-`"),

    ("indice fuera de rango",
     '''fn main() -> usize {
            let v: [usize; 3] = [1, 2, 3];
            var i: usize = 0;
            while i < 10 { imprimir(v[i]); i = i + 1; }
            return 0;
        }''',
     "indice 3 fuera de rango"),

    ("argumento fuera de rango",
     'fn main() -> usize { imprimir(argumento(9)); return 0; }',
     "no hay argumento 9"),

    ("division por cero",
     'fn main() -> usize { let a: usize = 1; let b: usize = 0;'
     ' imprimir(a / b); return 0; }',
     "division por cero"),
]


fallos = 0
total = 0


def falla(nombre, detalle):
    global fallos
    fallos += 1
    print(f"  FALLA: {nombre}\n         {detalle}")


def compilar_y_correr(fuente, tmp, con_sanitizers=True):
    """Devuelve (codigo_de_salida, stdout, stderr) o lanza AssertionError."""
    if "usar " in fuente:
        # Con `usar` hace falta el cargador de modulos, y para eso el fuente
        # tiene que estar en un archivo.
        ruta_t = os.path.join(tmp, "p.t")
        with open(ruta_t, "w", encoding="utf-8") as f:
            f.write(fuente)
        codigo, errores = compilar_archivo(ruta_t)
    else:
        codigo, errores = compilar_a_c(fuente, "<test>")
    assert not errores, "errores inesperados: " + "; ".join(errores)

    ruta_c = os.path.join(tmp, "p.c")
    binario = os.path.join(tmp, "p")
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(codigo)

    orden = ["cc", "-std=c17", "-g", "-Wall", "-Wextra", "-Werror",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"]
    if con_sanitizers:
        orden.insert(3, "-fsanitize=address,undefined")
        orden.insert(4, "-fno-omit-frame-pointer")

    r = subprocess.run(orden, capture_output=True, text=True)
    assert r.returncode == 0, "el C generado no compila:\n" + r.stderr

    e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
    return e.returncode, e.stdout, e.stderr


print("=== RECHAZO: programas que no deben compilar ===")
for nombre, fuente, esperado in RECHAZO:
    total += 1
    try:
        codigo, errores = compilar_a_c(fuente, "<test>")
    except (ErrorLexico, ErrorSintactico) as exc:
        errores = [str(exc)]
    if not errores:
        falla(nombre, "compilo, y no deberia")
        continue
    if not any(esperado in e for e in errores):
        falla(nombre, f"se esperaba {esperado!r}, se obtuvo: {errores}")

print("=== AVISA: compilan igual, pero el compilador tiene algo que decir ===")
for nombre, fuente, esperado in AVISA:
    total += 1
    try:
        codigo, errores, comp = compilar_a_c(fuente, "<test>", devolver_comp=True)
    except (ErrorLexico, ErrorSintactico) as exc:
        falla(nombre, f"no parsea: {exc}")
        continue
    if errores:
        falla(nombre, f"no deberia dar errores: {errores}")
        continue
    if codigo is None:
        falla(nombre, "un aviso no puede impedir que se genere codigo")
        continue
    if esperado is None:
        if comp.avisos:
            falla(nombre, f"no deberia avisar nada, aviso: {comp.avisos}")
    elif not any(esperado in a for a in comp.avisos):
        falla(nombre, f"se esperaba {esperado!r}, hubo: {comp.avisos}")

print("=== ACEPTA: compilan, corren limpio bajo ASan+UBSan ===")
with tempfile.TemporaryDirectory() as tmp:
    for nombre, fuente, salida in ACEPTA:
        total += 1
        try:
            rc, out, err = compilar_y_correr(fuente, tmp)
        except AssertionError as exc:
            falla(nombre, str(exc))
            continue
        if rc != 0:
            falla(nombre, f"salio con codigo {rc}\n{err}")
        elif out != salida:
            falla(nombre, f"salida {out!r}, se esperaba {salida!r}")
        elif "runtime error" in err or "AddressSanitizer" in err:
            falla(nombre, f"sanitizer se quejo:\n{err}")

print("=== ARCHIVOS: lectura real, incluida entrada binaria ===")
with tempfile.TemporaryDirectory() as tmp:
    total += 1
    entrada = os.path.join(tmp, "entrada.bin")
    with open(entrada, "wb") as f:
        f.write(b"uno\n\x00dos")
    ruta = entrada.replace("\\", "\\\\").replace('"', '\\"')
    fuente = f'''fn main() -> usize ! {{
        let datos: str = try leer_archivo("{ruta}");
        imprimir(largo(vista(datos))); imprimir(" ");
        imprimir(byte(vista(datos), 4)); imprimir("\\n");
        return 0;
    }}'''
    try:
        rc, out, err = compilar_y_correr(fuente, tmp)
    except AssertionError as exc:
        falla("leer un archivo completo", str(exc))
    else:
        if rc != 0 or out != "8 0\n":
            falla("leer un archivo completo",
                  f"codigo {rc}, salida {out!r}, stderr {err!r}")
        elif "runtime error" in err or "AddressSanitizer" in err:
            falla("leer un archivo completo", f"sanitizer se quejo:\n{err}")

    # Ida y vuelta: escribir con bytes cero dentro y volver a leerlo.
    total += 1
    salida = os.path.join(tmp, "salida.bin")
    ruta_s = salida.replace("\\", "\\\\").replace('"', '\\"')
    fuente = f'''fn main() -> usize ! {{
        var datos: str = nuevo("ab");
        empujar(datos, "\\0cd");
        try escribir_archivo("{ruta_s}", vista(datos));
        let vuelta: str = try leer_archivo("{ruta_s}");
        imprimir(largo(vista(vuelta))); imprimir(" ");
        imprimir(byte(vista(vuelta), 2)); imprimir(" ");
        imprimir(igual(vista(datos), vista(vuelta))); imprimir("\\n");
        imprimir_error("esto va al diagnostico");
        return 0;
    }}'''
    try:
        rc, out, err = compilar_y_correr(fuente, tmp)
    except AssertionError as exc:
        falla("escribir y volver a leer", str(exc))
    else:
        if rc != 0 or out != "5 0 true\n":
            falla("escribir y volver a leer",
                  f"codigo {rc}, salida {out!r}, stderr {err!r}")
        elif "esto va al diagnostico" not in err:
            falla("escribir y volver a leer",
                  "`imprimir_error` no salio por la salida de error")
        elif "AddressSanitizer" in err:
            falla("escribir y volver a leer", f"sanitizer se quejo:\n{err}")

    # Escribir donde no se puede es un fallo, no un cuelgue.
    total += 1
    fuente = '''fn main() -> usize ! {
        try escribir_archivo("/no/existe/de/verdad.txt", "x");
        return 0;
    }'''
    try:
        rc, out, err = compilar_y_correr(fuente, tmp)
    except AssertionError as exc:
        falla("escribir donde no se puede", str(exc))
    else:
        if rc == 0 or "no se pudo abrir el archivo para escribir" not in err:
            falla("escribir donde no se puede",
                  f"codigo {rc}, stderr {err!r}")

# ------------------------------------------------------------------ lexer
# El lexer de Tcode escrito en Tcode, contra el de Python. Es la prueba mas
# fuerte que tiene el lenguaje: un programa de 250 lineas que produce
# exactamente lo mismo que el original sobre todos los .t del repo, incluido
# el suyo propio.
print("=== AUTOANALISIS: el lexer y el parser en Tcode, contra los de Python ===")
import glob
import traceback
from tcode.lexer import tokenizar as tokenizar_py

with tempfile.TemporaryDirectory() as tmp:
    total += 1
    fuente_lexer = os.path.join(RAIZ, "ejemplos", "lexer", "lexer.t")
    try:
        codigo, errores = compilar_archivo(fuente_lexer)
    except Exception as exc:
        falla("el lexer en Tcode compila", str(exc))
        codigo = None
    if codigo is None or errores:
        falla("el lexer en Tcode compila", f"errores: {errores}")
    else:
        ruta_c = os.path.join(tmp, "lex.c")
        binario = os.path.join(tmp, "lex")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla("el lexer en Tcode compila", r.stderr)
        else:
            archivos = sorted(
                glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                          recursive=True)
                + glob.glob(os.path.join(RAIZ, "std", "*.t")))
            distintos = 0
            tokens_vistos = 0
            for archivo in archivos:
                total += 1
                texto = open(archivo, encoding="utf-8").read()
                esperados = tokenizar_py(texto, archivo)
                e = subprocess.run([binario, archivo], capture_output=True,
                                   text=True, timeout=120)
                if e.returncode != 0 or "Sanitizer" in e.stderr:
                    falla("autoanalisis", f"{os.path.basename(archivo)}: "
                                          f"codigo {e.returncode}\n{e.stderr[:400]}")
                    continue
                obtenidos = []
                for linea in e.stdout.split("\n"):
                    if not linea:
                        continue
                    partes = linea.split("\t", 2)
                    obtenidos.append((partes[1], partes[2] if len(partes) > 2 else ""))
                if len(obtenidos) != len(esperados):
                    falla("autoanalisis",
                          f"{os.path.basename(archivo)}: {len(obtenidos)} tokens "
                          f"contra {len(esperados)}")
                    continue
                # Las cadenas se comparan solo por tipo: el lexer en Tcode las
                # deja crudas, sin resolver escapes, que es todo lo que
                # necesita para saber donde terminan.
                malos = [i for i, ((tp, val), t) in
                         enumerate(zip(obtenidos, esperados))
                         if tp != t.tipo or (tp not in ("cadena", "interpolada")
                                             and val != t.valor)]
                if malos:
                    falla("autoanalisis",
                          f"{os.path.basename(archivo)}: {len(malos)} tokens "
                          f"distintos, el primero en la posicion {malos[0]}")
                else:
                    tokens_vistos += len(obtenidos)
                    distintos += 1
            print(f"    {distintos} archivos, {tokens_vistos} tokens identicos")

            # --- el parser en Tcode, sobre los mismos archivos ---
            total += 1
            from tcode.modulos import cargar as cargar_modulos, ErrorDeModulo
            fuente_parser = os.path.join(RAIZ, "ejemplos", "lexer", "parser.t")
            codigo_p, errores_p = compilar_archivo(fuente_parser)
            if errores_p:
                falla("el parser en Tcode compila", f"errores: {errores_p}")
            else:
                ruta_p = os.path.join(tmp, "par.c")
                bin_p = os.path.join(tmp, "par")
                with open(ruta_p, "w", encoding="utf-8") as f:
                    f.write(codigo_p)
                r = subprocess.run(
                    ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra",
                     "-Werror", "-fsanitize=address,undefined",
                     "-fno-omit-frame-pointer", f"-I{RUNTIME}", ruta_p,
                     os.path.join(RUNTIME, "safestr.c"), "-o", bin_p, "-lm"],
                    capture_output=True, text=True)
                if r.returncode != 0:
                    falla("el parser en Tcode compila", r.stderr)
                else:
                    nodos_vistos = 0
                    coinciden = 0
                    for archivo in archivos:
                        total += 1
                        try:
                            cargar_modulos(archivo)
                            py_acepta = True
                        except (ErrorLexico, ErrorSintactico, ErrorDeModulo):
                            py_acepta = False
                        e = subprocess.run([bin_p, archivo, "--callado"],
                                           capture_output=True, text=True,
                                           timeout=180)
                        if "Sanitizer" in e.stderr:
                            falla("el parser en Tcode",
                                  f"{os.path.basename(archivo)}: "
                                  f"sanitizer\n{e.stderr[:400]}")
                            continue
                        if (e.returncode == 0) != py_acepta:
                            falla("el parser en Tcode",
                                  f"{os.path.basename(archivo)}: acepta="
                                  f"{e.returncode == 0}, el de Python="
                                  f"{py_acepta}")
                            continue
                        if e.returncode == 0:
                            nodos_vistos += int(e.stdout.split()[1])
                        coinciden += 1
                    print(f"    parser: {coinciden} archivos, "
                          f"{nodos_vistos} nodos, sin discrepancias")

            # Entradas hostiles: no puede reventar ni filtrar.
            for nombre, contenido, esperado in [
                ("cadena sin cerrar", 'fn f() { let s: str = "abre\n', "cadena sin cerrar"),
                ("comentario sin cerrar", "fn f() { /* abre\n", "comentario /* sin cerrar"),
                ("byte que no es de Tcode", "fn f() { let x: usize = 1 @ 2; }\n",
                 "caracter inesperado"),
            ]:
                total += 1
                ruta = os.path.join(tmp, "hostil.t")
                with open(ruta, "w", encoding="utf-8") as f:
                    f.write(contenido)
                e = subprocess.run([binario, ruta], capture_output=True,
                                   text=True, timeout=60)
                if e.returncode == 0:
                    falla(f"entrada hostil: {nombre}", "no fallo, y deberia")
                elif esperado not in e.stderr:
                    falla(f"entrada hostil: {nombre}",
                          f"se esperaba {esperado!r}, hubo {e.stderr[:200]!r}")
                elif "Sanitizer" in e.stderr:
                    falla(f"entrada hostil: {nombre}", f"sanitizer:\n{e.stderr}")

print("=== TIPOS: la capa de tipos del comprobador, en Tcode ===")
# La tercera capa del compilador escrita en Tcode, despues del lexer y el
# parser. Se le pregunta lo mismo que al comprobador de Python sobre cada
# tipo que aparece en el repositorio, y tiene que contestar igual.
import shutil
from tcode.comprobador import tipo_de_parametro as _tipo_param
from tcode.nodos import Funcion as _Funcion, Struct as _Struct
from tcode.comprobador import Comprobador as _Comprobador

def _tipos_python(ruta, structs_previos):
    from tcode.parser import parsear as _parsear
    arbol = _parsear(open(ruta, encoding="utf-8").read(), ruta,
                     set(structs_previos))
    c = _Comprobador(ruta)
    for d in arbol:
        if isinstance(d, _Struct):
            c.structs[d.nombre] = d
    tipos = []
    for d in arbol:
        if isinstance(d, _Struct):
            tipos += [x.tipo for x in d.campos]
        elif isinstance(d, _Funcion):
            tipos += [_tipo_param(p) for p in d.params]
            if d.retorno is not None:
                tipos.append(d.retorno)
    return [f"{t}\t{str(c.posee(t)).lower()}\t{str(c.tipo_existe(t)).lower()}"
            for t in sorted(set(tipos))]

tmp = tempfile.mkdtemp(prefix="tcode-tipos-")
try:
    total += 1
    codigo, errores = compilar_archivo(
        os.path.join(RAIZ, "ejemplos", "compilador", "tipos.t"))
    if errores:
        falla("la capa de tipos en Tcode", "\n".join(errores))
    else:
        ruta_c = os.path.join(tmp, "tipos.c")
        binario = os.path.join(tmp, "tipos")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla("la capa de tipos en Tcode compila", r.stderr[:600])
        else:
            archivos = sorted(
                glob.glob(os.path.join(RAIZ, "std", "*.t"))
                + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                            recursive=True))
            previos = set()
            for a in archivos:
                from tcode.parser import parsear as _p
                try:
                    previos |= {d.nombre for d in
                                _p(open(a, encoding="utf-8").read(), a, previos)
                                if isinstance(d, _Struct)}
                except Exception:
                    pass
            comparados = tipos_vistos = 0
            for archivo in archivos:
                total += 1
                try:
                    esperado = _tipos_python(archivo, previos)
                except Exception:
                    continue        # lo que el parser de Python no lee, no cuenta
                e = subprocess.run([binario, archivo], capture_output=True,
                                   text=True, timeout=180)
                if "Sanitizer" in e.stderr:
                    falla("la capa de tipos en Tcode",
                          f"{os.path.basename(archivo)}: sanitizer\n"
                          f"{e.stderr[:400]}")
                    continue
                salida = [l for l in e.stdout.splitlines() if l.strip()]
                if salida != esperado:
                    dif = [f"  Tcode: {a!r}\n  Python: {b!r}"
                           for a, b in zip(salida, esperado) if a != b]
                    falla("la capa de tipos en Tcode",
                          f"{os.path.basename(archivo)}: "
                          f"{len(salida)} lineas contra {len(esperado)}\n"
                          + "\n".join(dif[:4]))
                    continue
                comparados += 1
                tipos_vistos += len(salida)
            print(f"    {comparados} archivos, {tipos_vistos} tipos, "
                  f"mismas respuestas que el comprobador de Python")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("=== TIPAR: de que tipo es cada variable, dicho por Tcode ===")
# Cuarta capa del compilador escrita en su propio lenguaje, despues del
# lexer, el parser y la capa de tipos. Se le pregunta el tipo de cada
# variable de cada funcion del repositorio, y tiene que decir lo mismo que
# el comprobador de Python.
from tcode.nodos import Funcion as _Fn_t

def _nombre_escrito(nombre, propias):
    """El nombre tal como esta en el archivo.

    El cargador renombra dos cosas: lo que choca con una palabra de C
    (`ss_id_union`) y lo que declaran dos modulos a la vez
    (`propiedad__posee`). Ninguno de los dos esta escrito en la fuente.
    """
    if nombre in propias:
        return nombre
    if nombre.startswith("ss_id_") and nombre[len("ss_id_"):] in propias:
        return nombre[len("ss_id_"):]
    if "__" in nombre:
        corto = nombre.split("__", 1)[1]
        if corto in propias:
            return corto
    return None


def _tipos_esperados(ruta):
    """Lo que dice el comprobador de Python, dejando fuera lo que el
    compilador se inventa: las copias de una generica, las clausuras, y los
    renombrados por chocar con una palabra de C. Nada de eso esta escrito en
    el archivo, asi que no hay nada que comparar."""
    from tcode.parser import parsear as _p
    try:
        arbol = _p(open(ruta, encoding="utf-8").read(), ruta, set())
    except Exception:
        return None
    propias = {d.nombre for d in arbol
               if isinstance(d, _Fn_t) and not d.tipo_params}
    codigo, errores, comp = compilar_archivo(ruta, devolver_comp=True)
    if errores:
        return None
    propio = os.path.relpath(ruta)
    fuera = []
    for entrada in comp.informe:
        f = entrada["funcion"]
        if (f.archivo or propio) != propio:
            continue
        nombre = _nombre_escrito(f.nombre, propias)
        if nombre is None:
            continue
        for sim in entrada["simbolos"]:
            fuera.append(f"{nombre}\t{sim.nombre}\t{sim.tipo}")
    return fuera

tmp = tempfile.mkdtemp(prefix="tcode-tipar-")
try:
    total += 1
    codigo, errores = compilar_archivo(
        os.path.join(RAIZ, "ejemplos", "compilador", "tipar.t"))
    if errores:
        falla("tipar en Tcode", "\n".join(errores))
    else:
        ruta_c = os.path.join(tmp, "tipar.c")
        binario = os.path.join(tmp, "tipar")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla("tipar en Tcode compila", r.stderr[:600])
        else:
            archivos = sorted(
                glob.glob(os.path.join(RAIZ, "std", "*.t"))
                + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                            recursive=True))
            comparados = simbolos = 0
            for archivo in archivos:
                esperado = _tipos_esperados(archivo)
                if esperado is None:
                    continue
                total += 1
                e = subprocess.run([binario, archivo], capture_output=True,
                                   text=True, timeout=180)
                if "Sanitizer" in e.stderr:
                    falla("tipar en Tcode",
                          f"{os.path.basename(archivo)}: sanitizer\n"
                          f"{e.stderr[:400]}")
                    continue
                dado = [l for l in e.stdout.splitlines() if l.strip()]
                if dado != esperado:
                    d = next((i for i, (a, b) in enumerate(zip(dado, esperado))
                              if a != b), None)
                    detalle = (f"  Tcode:  {dado[d]!r}\n  Python: {esperado[d]!r}"
                               if d is not None
                               else f"{len(dado)} lineas contra {len(esperado)}")
                    falla("tipar en Tcode",
                          f"{os.path.basename(archivo)}:\n" + detalle)
                    continue
                comparados += 1
                simbolos += len(dado)
            print(f"    {comparados} archivos, {simbolos} variables, "
                  f"mismos tipos que el comprobador de Python")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("=== PROPIEDAD: que le pasa a cada valor, dicho por Tcode ===")
# Quinta capa del compilador en su propio lenguaje, y la que de verdad separa
# a Tcode de C: quien es duenio de que memoria y donde deja de serlo. Cada
# variable acaba en `presta`, `prestado`, `nada`, `entrega:N`, `mueve:N` o
# `libera`, y tiene que coincidir con lo que el comprobador de Python sabe
# decir con `--explicar`.
#
# Tres archivos no coinciden todavia, por dos limitaciones de la capa en
# Tcode que estan sin resolver y no se esconden:
#
#   - dos variables con el MISMO NOMBRE en bloques distintos de una funcion:
#     el destino de una se le atribuye a la otra
#   - una llamada repartida en varias lineas: el movimiento se apunta en la
#     linea del argumento, y el comprobador de Python a veces usa otra
#
# La lista esta aqui escrita para que no crezca sin que nadie se entere: si
# un archivo que hoy coincide deja de hacerlo, la suite lo dice.
_PROPIEDAD_PENDIENTES = {
    # nombre repetido en bloques distintos
    "ejemplos/compilador/lib/propiedad.t",
    "ejemplos/compilador/lib/tipar.t",
    "ejemplos/compilador/lib/generar.t",
    # llamada repartida en varias lineas
    "ejemplos/compilador/tipos.t",
    "ejemplos/compilador/firmas.t",
    "ejemplos/compilador/expresiones.t",
    "ejemplos/compilador/cuerpos.t",
}

def _propiedad_esperada(ruta):
    from tcode.parser import parsear as _p
    try:
        arbol = _p(open(ruta, encoding="utf-8").read(), ruta, set())
    except Exception:
        return None
    propias = {d.nombre for d in arbol
               if isinstance(d, _Fn_t) and not d.tipo_params}
    codigo, errores, comp = compilar_archivo(ruta, devolver_comp=True)
    if errores:
        return None
    propio = os.path.relpath(ruta)
    fuera = []
    for entrada in comp.informe:
        f = entrada["funcion"]
        if (f.archivo or propio) != propio:
            continue
        nombre = _nombre_escrito(f.nombre, propias)
        if nombre is None:
            continue
        for sim in entrada["simbolos"]:
            if sim.tipo == "view":
                d = "presta"
            elif sim.prestado:
                d = "prestado"
            elif not comp.posee(sim.tipo):
                d = "nada"
            elif sim.entregada_en:
                d = f"entrega:{sim.entregada_en}"
            elif sim.movida:
                d = f"mueve:{sim.movida_en}"
            else:
                d = "libera"
            fuera.append(f"{nombre}\t{sim.nombre}\t{sim.tipo}\t{d}")
    return fuera

tmp = tempfile.mkdtemp(prefix="tcode-prop-")
try:
    total += 1
    codigo, errores = compilar_archivo(
        os.path.join(RAIZ, "ejemplos", "compilador", "tipar.t"))
    if errores:
        falla("propiedad en Tcode", "\n".join(errores))
    else:
        ruta_c = os.path.join(tmp, "tipar.c")
        binario = os.path.join(tmp, "tipar")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla("propiedad en Tcode compila", r.stderr[:600])
        else:
            archivos = sorted(
                glob.glob(os.path.join(RAIZ, "std", "*.t"))
                + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                            recursive=True))
            comparados = variables = 0
            for archivo in archivos:
                rel = os.path.relpath(archivo, RAIZ)
                esperado = _propiedad_esperada(archivo)
                if esperado is None:
                    continue
                total += 1
                e = subprocess.run([binario, archivo, "--propiedad"],
                                   capture_output=True, text=True, timeout=180)
                if "Sanitizer" in e.stderr:
                    falla("propiedad en Tcode",
                          f"{rel}: sanitizer\n{e.stderr[:400]}")
                    continue
                dado = [l for l in e.stdout.splitlines() if l.strip()]
                coincide = dado == esperado
                if coincide and rel in _PROPIEDAD_PENDIENTES:
                    falla("propiedad en Tcode",
                          f"{rel} ya coincide: quitalo de "
                          f"_PROPIEDAD_PENDIENTES")
                elif not coincide and rel not in _PROPIEDAD_PENDIENTES:
                    d = next((i for i, (a, b) in enumerate(zip(dado, esperado))
                              if a != b), None)
                    detalle = (f"  Tcode:  {dado[d]!r}\n  Python: {esperado[d]!r}"
                               if d is not None
                               else f"{len(dado)} lineas contra {len(esperado)}")
                    falla("propiedad en Tcode", f"{rel}:\n" + detalle)
                elif coincide:
                    comparados += 1
                    variables += len(dado)
            print(f"    {comparados} archivos, {variables} variables, mismo "
                  f"destino que el comprobador de Python "
                  f"({len(_PROPIEDAD_PENDIENTES)} pendientes)")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("=== FIRMAS: la cara en C de cada funcion, dicha por Tcode ===")
# Primera pieza del generador escrita en su propio lenguaje: como se llama
# cada tipo en C y como queda la firma de cada funcion. Se compara con lo que
# emite el generador de Python, cadena por cadena.
from tcode.generador import Generador as _Gen

def _firmas_esperadas(ruta):
    # Que funciones lleva el archivo, y en que orden, lo dice el arbol recien
    # parseado. Pero la firma se saca de la funcion que dejo el comprobador:
    # el alias con el que se escribio un tipo de otro modulo —`P.Nodo`— lo
    # resuelve el cargador y en C no queda, asi que el arbol crudo daria una
    # firma que ni siquiera compila.
    from tcode.parser import parsear as _p
    try:
        arbol = _p(open(ruta, encoding="utf-8").read(), ruta, set())
    except Exception:
        return None
    codigo, errores, comp = compilar_archivo(ruta, devolver_comp=True)
    if errores:
        return None
    propio = os.path.relpath(ruta, RAIZ)
    g = _Gen(comp, propio)
    escritas = [d.nombre for d in arbol
                if isinstance(d, _Fn_t) and not d.tipo_params]
    salida = []
    for nombre in escritas:
        d = comp.funciones.get(nombre)
        if d is None:
            d = next((f for k, f in comp.funciones.items()
                      if k == "ss_id_" + nombre or k.endswith("__" + nombre)),
                     None)
        if d is None:
            return None
        salida.append(g.prototipo(d))
    return salida

tmp = tempfile.mkdtemp(prefix="tcode-firmas-")
try:
    total += 1
    codigo, errores = compilar_archivo(
        os.path.join(RAIZ, "ejemplos", "compilador", "firmas.t"))
    if errores:
        falla("firmas en Tcode", "\n".join(errores))
    else:
        ruta_c = os.path.join(tmp, "firmas.c")
        binario = os.path.join(tmp, "firmas")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla("firmas en Tcode compila", r.stderr[:600])
        else:
            archivos = sorted(
                glob.glob(os.path.join(RAIZ, "std", "*.t"))
                + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                            recursive=True))
            comparados = firmas = 0
            for archivo in archivos:
                esperado = _firmas_esperadas(archivo)
                if esperado is None:
                    continue
                total += 1
                e = subprocess.run([binario, archivo], capture_output=True,
                                   text=True, timeout=180)
                if "Sanitizer" in e.stderr:
                    falla("firmas en Tcode",
                          f"{os.path.basename(archivo)}: sanitizer\n"
                          f"{e.stderr[:400]}")
                    continue
                dado = [l for l in e.stdout.splitlines() if l.strip()]
                if dado != esperado:
                    d = next((i for i, (a, b) in enumerate(zip(dado, esperado))
                              if a != b), None)
                    detalle = (f"  Tcode:  {dado[d]!r}\n  Python: {esperado[d]!r}"
                               if d is not None
                               else f"{len(dado)} firmas contra {len(esperado)}")
                    falla("firmas en Tcode",
                          f"{os.path.relpath(archivo, RAIZ)}:\n" + detalle)
                    continue
                comparados += 1
                firmas += len(dado)
            print(f"    {comparados} archivos, {firmas} firmas, mismas que el "
                  f"generador de Python")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("=== EXPRESIONES: el C de una expresion, escrito por Tcode ===")
# Segunda pieza del generador en su propio lenguaje. Por cada `return <expr>`
# del repositorio se compara el C que sale, caracter por caracter, con el que
# emite el generador de Python.
#
# Lo que esta capa no sabe hacer todavia sale como `?` y no se compara: se
# cuentan las cubiertas y se exige un minimo, que es mas honesto que decir
# que estan todas.
#
# Hoy cubre literales, variables, prestamos, operadores logicos y de
# comparacion, aritmetica comprobada, division y resto, llamadas a funciones
# del programa, y las internas que no necesitan emitir nada aparte: `vacio`,
# `nuevo`, `vista`, `largo`, `rebanar`, `igual` y `menor`.
#
# Falta lo que necesita emitir lineas propias: `byte` (guarda la vista en un
# temporal antes de indexarla), interpolacion, `try`, clausuras y
# colecciones.
from tcode.nodos import Retorno as _Ret

def _retornos(nodo, fuera):
    from dataclasses import fields as _f, is_dataclass as _isd
    if isinstance(nodo, (list, tuple)):
        for x in nodo:
            _retornos(x, fuera)
        return
    if not _isd(nodo):
        return
    if isinstance(nodo, _Ret) and nodo.valor is not None:
        fuera.append(nodo)
    for campo in _f(nodo):
        _retornos(getattr(nodo, campo.name), fuera)

def _expresiones_esperadas(ruta):
    from tcode.parser import parsear as _p
    try:
        arbol = _p(open(ruta, encoding="utf-8").read(), ruta, set())
    except Exception:
        return None
    codigo, errores, comp = compilar_archivo(ruta, devolver_comp=True)
    if errores:
        return None
    fuera = []
    for d in arbol:
        if not isinstance(d, _Fn_t) or d.tipo_params:
            continue
        g = _Gen(comp, ruta)
        g.func = d
        g.vars = [{}]
        g.pila = [[]]
        for p in d.params:
            g.declarar(p.nombre, p.tipo, p.prestado, p)
        rr = []
        _retornos(d.cuerpo, rr)
        for r in rr:
            try:
                c = g.expr(r.valor, d.retorno)
            except Exception:
                c = "<revienta>"
            fuera.append(f"{d.nombre}\t{r.linea}\t{c}")
    return fuera

_MINIMO_CUBIERTAS = 495

tmp = tempfile.mkdtemp(prefix="tcode-expr-")
try:
    total += 1
    codigo, errores = compilar_archivo(
        os.path.join(RAIZ, "ejemplos", "compilador", "expresiones.t"))
    if errores:
        falla("expresiones en Tcode", "\n".join(errores))
    else:
        ruta_c = os.path.join(tmp, "expresiones.c")
        binario = os.path.join(tmp, "expresiones")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla("expresiones en Tcode compila", r.stderr[:600])
        else:
            archivos = sorted(
                glob.glob(os.path.join(RAIZ, "std", "*.t"))
                + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                            recursive=True))
            cubiertas = vistas = 0
            for archivo in archivos:
                esperado = _expresiones_esperadas(archivo)
                if esperado is None:
                    continue
                total += 1
                e = subprocess.run([binario, archivo], capture_output=True,
                                   text=True, timeout=180)
                if "Sanitizer" in e.stderr:
                    falla("expresiones en Tcode",
                          f"{os.path.basename(archivo)}: sanitizer\n"
                          f"{e.stderr[:400]}")
                    continue
                dado = [l for l in e.stdout.splitlines() if l.strip()]
                if len(dado) != len(esperado):
                    falla("expresiones en Tcode",
                          f"{os.path.relpath(archivo, RAIZ)}: {len(dado)} "
                          f"expresiones contra {len(esperado)}")
                    continue
                for a, b in zip(dado, esperado):
                    vistas += 1
                    if a.endswith("\t?"):
                        continue        # esta capa no la cubre todavia
                    if a != b:
                        falla("expresiones en Tcode",
                              f"{os.path.relpath(archivo, RAIZ)}:\n"
                              f"  Tcode:  {a!r}\n  Python: {b!r}")
                    else:
                        cubiertas += 1
            if cubiertas < _MINIMO_CUBIERTAS:
                total += 1
                falla("expresiones en Tcode",
                      f"solo {cubiertas} expresiones cubiertas, se esperaban "
                      f"al menos {_MINIMO_CUBIERTAS}")
            print(f"    {cubiertas} de {vistas} expresiones, mismo C que el "
                  f"generador de Python")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("=== CUERPOS: la funcion entera en C, escrita por Tcode ===")
# Tercera pieza del generador en su propio lenguaje, y la que de verdad
# cuenta: la firma, el cuerpo, y los `ss_free` puestos solos donde tocan.
# Se compara con lo que emite el generador de Python, linea por linea.
#
# Lo unico que se normaliza son los contadores —temporales e indices de
# bucle—: el original los cuenta por archivo y esta capa por funcion, asi que
# se renumeran en los dos por orden de aparicion. Todo lo demas tiene que
# salir identico.
#
# Una funcion que esta capa no sabe hacer entera no se emite a medias: se
# descarta. Se cuentan las que salen, y se exige un minimo.
import re as _re_cuerpos

def _normaliza_tmp(texto):
    def renumera(texto, prefijo):
        visto, n = {}, [0]
        def cambia(m):
            k = m.group(0)
            if k not in visto:
                n[0] += 1
                visto[k] = f"{prefijo}{n[0]}"
            return visto[k]
        return _re_cuerpos.sub(prefijo + r"\d+", cambia, texto)
    for prefijo in ("ss_tmp", "ss_i", "ss_k"):
        texto = renumera(texto, prefijo)
    return texto

_MINIMO_CUERPOS = 56

tmp = tempfile.mkdtemp(prefix="tcode-cuerpos-")
try:
    total += 1
    codigo, errores = compilar_archivo(
        os.path.join(RAIZ, "ejemplos", "compilador", "cuerpos.t"))
    if errores:
        falla("cuerpos en Tcode", "\n".join(errores))
    else:
        ruta_c = os.path.join(tmp, "cuerpos.c")
        binario = os.path.join(tmp, "cuerpos")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla("cuerpos en Tcode compila", r.stderr[:600])
        else:
            archivos = sorted(
                glob.glob(os.path.join(RAIZ, "std", "*.t"))
                + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"),
                            recursive=True))
            iguales = 0
            for archivo in archivos:
                codigo_f, errores_f, comp = compilar_archivo(
                    archivo, devolver_comp=True)
                if errores_f:
                    continue
                # El comprobador guarda la ruta relativa a la raiz, y esa
                # ruta sale en los `#line`. Para comparar hay que darle la
                # misma al de Tcode, no la absoluta.
                propio = os.path.relpath(archivo, RAIZ)
                total += 1
                e = subprocess.run([binario, propio], capture_output=True,
                                   text=True, timeout=180, cwd=RAIZ)
                if "Sanitizer" in e.stderr:
                    falla("cuerpos en Tcode",
                          f"{os.path.basename(archivo)}: sanitizer\n"
                          f"{e.stderr[:400]}")
                    continue
                for bloque in e.stdout.split("@@ ")[1:]:
                    nombre, _, cuerpo = bloque.partition("\n")
                    nombre = nombre.strip()
                    # La funcion tal como la dejo el comprobador: con los
                    # tipos deducidos puestos. Sin eso, un `var i = 0;` sin
                    # anotar no tendria tipo y el original saldria mal.
                    d = comp.funciones.get(nombre)
                    if d is None:
                        d = next((f for k, f in comp.funciones.items()
                                  if k.endswith("__" + nombre)
                                  or k == "ss_id_" + nombre), None)
                    if (d is None or (d.archivo or propio) != propio
                            or d.tipo_params):
                        continue
                    g = _Gen(comp, propio)
                    g.funcion(d)
                    esperado = _normaliza_tmp("\n".join(g.lineas)).strip()
                    dado = _normaliza_tmp(cuerpo).strip()
                    if dado == esperado:
                        iguales += 1
                    else:
                        falla("cuerpos en Tcode",
                              f"{os.path.relpath(archivo, RAIZ)} :: {nombre}\n"
                              f"--- Tcode ---\n{dado}\n--- Python ---\n"
                              f"{esperado}")
            if iguales < _MINIMO_CUERPOS:
                total += 1
                falla("cuerpos en Tcode",
                      f"solo {iguales} funciones enteras, se esperaban al "
                      f"menos {_MINIMO_CUERPOS}")
            print(f"    {iguales} funciones enteras, mismo C que el generador "
                  f"de Python")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("=== FORMATO: un estilo, y el repositorio ya lo tiene ===")
# Tres propiedades, y la primera es la que importa: el formateador no puede
# perder ni cambiar nada, porque la salida lexea a los mismos tokens que la
# entrada. Las otras dos son que es idempotente y que el repositorio esta
# escrito en el formato canonico.
from tcode.formato import formatear as _formatear
from tcode.lexer import tokenizar as _tokenizar_fmt

_TODOS = sorted(
    glob.glob(os.path.join(RAIZ, "std", "*.t"))
    + glob.glob(os.path.join(RAIZ, "ejemplos", "**", "*.t"), recursive=True)
    + glob.glob(os.path.join(RAIZ, "bench", "*.t")))
sin_formato = []
for archivo in _TODOS:
    total += 1
    with open(archivo, encoding="utf-8") as f:
        fuente = f.read()
    try:
        uno = _formatear(fuente, archivo)
        dos = _formatear(uno, archivo)
    except Exception:
        falla(f"formato de {os.path.relpath(archivo, RAIZ)}",
              traceback.format_exc())
        continue
    antes = [(t.tipo, t.valor) for t in _tokenizar_fmt(fuente, archivo)]
    despues = [(t.tipo, t.valor) for t in _tokenizar_fmt(uno, archivo)]
    if antes != despues:
        donde = next((i for i, (a, b) in enumerate(zip(antes, despues))
                      if a != b), min(len(antes), len(despues)))
        falla(f"formato de {os.path.relpath(archivo, RAIZ)}",
              f"cambia los tokens en la posicion {donde}: "
              f"{antes[donde:donde + 3]} -> {despues[donde:donde + 3]}")
        continue
    if uno != dos:
        falla(f"formato de {os.path.relpath(archivo, RAIZ)}",
              "formatear dos veces no da lo mismo")
        continue
    if uno != fuente:
        sin_formato.append(os.path.relpath(archivo, RAIZ))
if sin_formato:
    total += 1
    falla("el repositorio esta formateado",
          "sin formatear: " + ", ".join(sin_formato[:6])
          + "; arreglalo con `make formato`")
print(f"    {len(_TODOS)} archivos: mismos tokens, idempotente, y ya "
      f"en formato canonico")

print("=== LINEAS: el C generado apunta al `.t`, no a si mismo ===")
# Con `#line`, gdb, valgrind, los sanitizers y los perfiladores hablan del
# codigo que se escribio. Se comprueba que cada directiva señale una linea
# que existe de verdad, y que el depurador lo vea.
import re as _re
_DIRECTIVA = _re.compile(r'^#line (\d+) "(.*)"$')
tmp = tempfile.mkdtemp(prefix="tcode-lineas-")
try:
    marcadas = 0
    MUESTRA = ["ejemplos/hola.t", "ejemplos/texto.t", "ejemplos/binario.t",
               "ejemplos/pruebas.t", "ejemplos/informe/informe.t",
               "ejemplos/modulos/escalas.t"]
    for relativo in MUESTRA:
        total += 1
        ruta = os.path.join(RAIZ, relativo)
        codigo, errores = compilar_archivo(ruta)
        if errores:
            falla(f"lineas de {relativo}", "\n".join(errores))
            continue
        vistas = 0
        for l in codigo.splitlines():
            m = _DIRECTIVA.match(l)
            if not m:
                continue
            vistas += 1
            n, archivo = int(m.group(1)), m.group(2)
            if not os.path.isfile(archivo):
                falla(f"lineas de {relativo}",
                      f"`#line {n} \"{archivo}\"` señala un archivo que no existe")
                break
            with open(archivo, encoding="utf-8") as f:
                cuantas = sum(1 for _ in f)
            if not 1 <= n <= cuantas:
                falla(f"lineas de {relativo}",
                      f"`#line {n} \"{archivo}\"` se sale: el archivo tiene "
                      f"{cuantas} lineas")
                break
        else:
            if vistas == 0:
                falla(f"lineas de {relativo}", "no hay ninguna directiva `#line`")
            marcadas += vistas

    # Y que el depurador lo vea de verdad, si esta instalado.
    total += 1
    fuente = ("fn hondo(n: usize) -> usize {\n"
              "    let a = n * 2;\n"
              "    let b = a - 100;\n"
              "    return b;\n"
              "}\n"
              "fn main() -> usize { imprimir(hondo(3)); }\n")
    ruta_t = os.path.join(tmp, "hondo.t")
    with open(ruta_t, "w", encoding="utf-8") as f:
        f.write(fuente)
    codigo, errores = compilar_archivo(ruta_t)
    if errores:
        falla("el depurador ve el `.t`", "\n".join(errores))
    else:
        ruta_c = os.path.join(tmp, "hondo.c")
        binario = os.path.join(tmp, "hondo")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O0", "-g", f"-I{RUNTIME}", ruta_c,
             os.path.join(RUNTIME, "safestr.c"), "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla("el depurador ve el `.t`", r.stderr[:400])
        elif shutil.which("gdb") is None:
            print("    (sin gdb: no se pudo comprobar la pila)")
        else:
            e = subprocess.run(["gdb", "-batch", "-ex", "run", "-ex", "bt",
                                binario], capture_output=True, text=True,
                               timeout=120)
            if f"hondo.t:3" not in e.stdout:
                falla("el depurador ve el `.t`",
                      "la pila no señala `hondo.t:3`:\n" + e.stdout[-600:])
    print(f"    {marcadas} directivas, todas a una linea que existe")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("=== ABORTA: la aritmetica comprobada detiene el programa ===")
with tempfile.TemporaryDirectory() as tmp:
    for nombre, fuente, esperado in ABORTA:
        total += 1
        try:
            rc, out, err = compilar_y_correr(fuente, tmp, con_sanitizers=False)
        except AssertionError as exc:
            falla(nombre, str(exc))
            continue
        if rc == 0:
            falla(nombre, "termino normalmente, deberia abortar")
        elif esperado not in err:
            falla(nombre, f"se esperaba {esperado!r} en stderr, hubo: {err!r}")

# ---------------------------------------------------------------- modulos
print("=== MODULOS: varios archivos, un solo programa ===")
import shutil
from tcode.modulos import cargar, ErrorDeModulo
from tcode.cli import _compilar

MODULOS = [
    ("un `usar` en rombo carga el modulo una sola vez",
     {"lib/base.t": 'fn doble(n: usize) -> usize { return n * 2; }',
      "lib/medio.t": 'usar "base.t";\n'
                       'fn cuadruple(n: usize) -> usize { return doble(doble(n)); }',
      "app.t": 'usar "lib/medio.t";\nusar "lib/base.t";\n'
                 'fn main() -> usize { imprimir(cuadruple(3)); imprimir("\\n");'
                 ' imprimir(doble(5)); imprimir("\\n"); return 0; }'},
     "app.t", None, "12\n10\n"),

    ("dependencia circular",
     {"a.t": 'usar "b.t";\nfn a() {}',
      "b.t": 'usar "a.t";\nfn b() {}'},
     "a.t", "dependencia circular", None),

    ("modulo que no existe",
     {"a.t": 'usar "fantasma.t";\nfn main() -> usize { return 0; }'},
     "a.t", "no encuentro el modulo", None),

    ("el mismo nombre desde dos sitios, y como arreglarlo",
     {"x.t": 'fn dos() -> usize { return 2; }',
      "a.t": 'usar "x.t";\nfn dos() -> usize { return 3; }\n'
               'fn main() -> usize { return dos(); }'},
     "a.t", "llega de dos sitios", None),

    ("dos modulos con el mismo nombre no se estorban si no se cruzan",
     {"uno.t": 'fn contar(xs: &lista<str>) -> usize { return largo(xs); }',
      "dos.t": 'fn contar(xs: &lista<usize>) -> usize { return largo(xs) * 2; }',
      "a.t": 'usar "uno.t";\nusar "dos.t" como d;\n'
               'fn main() -> usize {\n'
               '    var ss: lista<str> = []; anadir(ss, nuevo("a"));\n'
               '    var ns: lista<usize> = []; anadir(ns, 1); anadir(ns, 2);\n'
               '    imprimir($"{contar(ss)} {d.contar(ns)}\\n");\n'
               '    return 0;\n}'},
     "a.t", None, "1 4\n"),

    ("un struct que llega con nombre de modulo",
     {"tipos.t": 'struct Caja { n: usize }\n'
                   'fn hacer(n: usize) -> Caja { return Caja { n: n }; }',
      "a.t": 'usar "tipos.t" como t;\n'
               'fn leer(c: &t.Caja) -> usize { return c.n; }\n'
               'fn main() -> usize {\n'
               '    let c: t.Caja = t.Caja { n: 7 };\n'
               '    let d = t.hacer(9);\n'
               '    imprimir($"{leer(c)} {leer(d)}\\n");\n'
               '    return 0;\n}'},
     "a.t", None, "7 9\n"),

    ("un error dentro de un modulo dice de que archivo es",
     {"roto.t": 'fn r() { let a: usize = 1; let b: i64 = 2;'
                  ' let c: usize = a + b; }',
      "a.t": 'usar "roto.t";\nfn main() -> usize { return 0; }'},
     "a.t", "roto.t:1", None),
]

for nombre, archivos, principal, error_esperado, salida in MODULOS:
    total += 1
    tmp = tempfile.mkdtemp()
    try:
        for ruta, texto in archivos.items():
            destino = os.path.join(tmp, ruta)
            os.makedirs(os.path.dirname(destino), exist_ok=True)
            with open(destino, "w", encoding="utf-8") as f:
                f.write(texto)

        try:
            decls = cargar(os.path.join(tmp, principal))
            codigo, errores = _compilar(decls, principal)
        except ErrorDeModulo as exc:
            codigo, errores = None, [str(exc)]

        if error_esperado is not None:
            if not errores:
                falla(nombre, "compilo, y no deberia")
            elif not any(error_esperado in e for e in errores):
                falla(nombre, f"se esperaba {error_esperado!r}, hubo: {errores}")
            continue

        if errores:
            falla(nombre, f"errores inesperados: {errores}")
            continue

        ruta_c = os.path.join(tmp, "p.c")
        binario = os.path.join(tmp, "p")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-g", "-fsanitize=address,undefined",
             "-Wall", "-Wextra", "-Werror", f"-I{RUNTIME}", ruta_c,
             os.path.join(RUNTIME, "safestr.c"), "-o", binario, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla(nombre, "el C generado no compila:\n" + r.stderr)
            continue
        e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
        if e.stdout != salida:
            falla(nombre, f"salida {e.stdout!r}, se esperaba {salida!r}")
        elif "AddressSanitizer" in e.stderr:
            falla(nombre, f"sanitizer:\n{e.stderr}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

print("=== EJEMPLOS: los de ejemplos/ compilan y corren limpios ===")
# La vitrina del lenguaje tiene que estar tan comprobada como el resto: si un
# ejemplo filtra memoria, lo primero que lee alguien filtra memoria.
EJEMPLOS = [
    ("ejemplos/hola.t", []),
    ("ejemplos/texto.t", []),
    ("ejemplos/inventario.t", []),
    ("ejemplos/contar.t", ["README.md"]),
    ("ejemplos/ordenar.t", ["README.md"]),
    ("ejemplos/frecuencia.t", ["README.md"]),
    ("ejemplos/informe/informe.t", []),
    ("ejemplos/modulos/escalas.t", []),
    ("ejemplos/binario.t", []),
    ("ejemplos/pruebas.t", []),
    ("ejemplos/lexer/lexer.t", ["ejemplos/hola.t"]),
    ("ejemplos/lexer/parser.t", ["ejemplos/hola.t"]),
]
tmp = tempfile.mkdtemp(prefix="tcode-ejemplos-")
try:
    for relativo, args in EJEMPLOS:
        total += 1
        ruta = os.path.join(RAIZ, relativo)
        codigo, errores = compilar_archivo(ruta)
        if errores:
            falla(f"ejemplo {relativo}", "\n".join(errores))
            continue
        base = os.path.join(tmp, relativo.replace("/", "_")[:-2])
        with open(base + ".c", "w", encoding="utf-8") as f:
            f.write(codigo)
        r = subprocess.run(
            ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             f"-I{RUNTIME}", base + ".c", os.path.join(RUNTIME, "safestr.c"),
             "-o", base, "-lm"],
            capture_output=True, text=True)
        if r.returncode != 0:
            falla(f"ejemplo {relativo}", r.stderr[:600])
            continue
        e = subprocess.run([base] + [os.path.join(RAIZ, a) for a in args],
                           capture_output=True, text=True, timeout=180,
                           cwd=RAIZ)
        if e.returncode != 0 or e.stderr.strip():
            falla(f"ejemplo {relativo}",
                  f"codigo {e.returncode}\n{e.stderr[:600]}")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print(f"\n{total} casos, {fallos} fallas")
sys.exit(1 if fallos else 0)
