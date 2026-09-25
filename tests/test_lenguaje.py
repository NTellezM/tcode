#!/usr/bin/env python3
"""
Suite del lenguaje Tcode.

RECHAZO   -> el programa NO debe compilar, y el error debe explicar por que.
ACEPTA    -> compila, corre bajo ASan+UBSan y da exactamente esta salida.

Los cuatro primeros casos de RECHAZO son las cuatro clases de fallo que
encontramos auditando la libreria safestr en C. Que aqui sean errores de compilacion
es la unica razon por la que este lenguaje existe.

Sin argumentos corre todas las secciones. Con nombres, solo esas:

    python3 tests/test_lenguaje.py ACEPTA ABORTA
    python3 tests/test_lenguaje.py --lista
"""

import concurrent.futures
import glob
import os
import shutil
import subprocess
import sys
import tempfile
import traceback

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)

from tcode.cli import compilar_a_c, compilar_archivo
from tcode.comprobador import tipo_de_parametro as _tipo_param
from tcode.generador import Generador as _Gen
from tcode.lexer import ErrorLexico
from tcode.nodos import Funcion as _Fn_t
from tcode.nombres_c import escrito as _escrito_c, legible as _legible_c
from tcode.parser import ErrorSintactico

RUNTIME = os.path.join(RAIZ, "runtime")

# Las secciones, en el orden en que corren. Cada una se puede pedir sola.
SECCIONES = [
    "RECHAZO", "AVISA", "ACEPTA", "SALIDA", "ARCHIVOS", "AUTOANALISIS",
    "TIPOS", "TIPAR", "PROPIEDAD", "FIRMAS", "EXPRESIONES", "CUERPOS",
    "PROGRAMA", "FORMATO", "LINEAS", "ABORTA", "MODULOS", "EJEMPLOS",
]
if "--lista" in sys.argv[1:]:
    print("\n".join(SECCIONES))
    sys.exit(0)
PEDIDAS = [a.upper() for a in sys.argv[1:]]
_desconocidas = [a for a in PEDIDAS if a not in SECCIONES]
if _desconocidas:
    print(f"no hay seccion {', '.join(_desconocidas)}; hay: {' '.join(SECCIONES)}",
          file=sys.stderr)
    sys.exit(2)
# Si corren todas: solo entonces las cifras de la suite son las de la suite.
TODAS = not PEDIDAS


# Lo que mide la suite, para el README: `tests/cifras.py` lo copia ahi. Solo
# se guarda cuando corren todas las secciones.
CIFRAS = {}


def cifra(clave, valor):
    CIFRAS[clave] = valor


def seccion(nombre, titulo):
    """Si esta seccion corre en esta pasada, y su cabecera."""
    assert nombre in SECCIONES, nombre
    if PEDIDAS and nombre not in PEDIDAS:
        return False
    print(f"=== {nombre}: {titulo} ===")
    return True


RECHAZO = [
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
     'struct Palabra { texto: view, n: usize } fn texto_de(p: Palabra) -> view { return p.texto; } fn main() { var p = Palabra { texto: "", n: 0 };'
     ' if true { let s = nuevo("x"); p = Palabra { texto: vista(s), n: 1 }; }'
     ' imprimir(p.texto); }',
     "`p` vive mas que `s`"),

    ("mientras vive, su duenio no se modifica",
     'struct Palabra { texto: view, n: usize } fn texto_de(p: Palabra) -> view { return p.texto; } fn main() { var s = nuevo("x"); let p = Palabra { texto: vista(s), n: 1 };'
     ' empujar(s, "y"); imprimir(p.texto); }',
     "no se puede modificar `s`: esta prestada por `p`"),

    ("no sale de la funcion si presta de algo local",
     'struct Palabra { texto: view, n: usize } fn texto_de(p: Palabra) -> view { return p.texto; } fn f() -> Palabra { let s = nuevo("x");'
     ' return Palabra { texto: vista(s), n: 1 }; }',
     "no se puede devolver una vista de `s`"),

    ("la vista que se saca de el presta de lo mismo",
     'struct Palabra { texto: view, n: usize } fn texto_de(p: Palabra) -> view { return p.texto; } fn main() { var s = nuevo("x"); let p = Palabra { texto: vista(s), n: 1 };'
     ' let v = texto_de(p); empujar(s, "y"); imprimir(v); }',
     "esta prestada por `p` y `v`"),

    ("una lista no guarda structs que prestan",
     'struct Palabra { texto: view, n: usize } fn texto_de(p: Palabra) -> view { return p.texto; } fn main() { var xs: lista<Palabra> = []; imprimir(largo(xs)); }',
     "no es un tipo almacenable"),

    ("un mapa tampoco guarda vistas",
     'fn main() { var m: mapa<str, view> = []; imprimir(largo(m)); }',
     "no es un tipo almacenable"),

    ("un enum no lleva vistas",
     'enum E { A(view), B } fn main() { }',
     "un enum no guarda prestamos"),

    ("no se guarda una vista en algo prestado",
     'struct Palabra { texto: view, n: usize } fn texto_de(p: Palabra) -> view { return p.texto; } fn g(p: mut Palabra, v: view) { p.texto = v; }',
     "no se puede guardar un prestamo en `p`"),

    ("una clausura no captura un struct que presta",
     'struct Palabra { texto: view, n: usize } fn texto_de(p: Palabra) -> view { return p.texto; } fn main() { let s = nuevo("x"); let p = Palabra { texto: vista(s), n: 1 };'
     ' let f = fn[p]() -> usize { return 1; }; imprimir(f()); }',
     "`p` es `Palabra`, un prestamo"),

    # ---- sacar un campo de su struct ----
    ("un struct a medio mover no se usa entero",
     'struct P { nombre: str, edad: usize, sub: Q } struct Q { t: str } fn toma(p: P) -> usize { return p.edad; } fn nuevo_p() -> P { return P { nombre: nuevo("a"), edad: 1, sub: Q { t: nuevo("b") } }; } fn main() { let p = nuevo_p(); let n = p.nombre; imprimir(toma(p));'
     ' imprimir(n); }',
     "`p` esta a medio mover: `p.nombre` se saco"),

    ("un campo sacado no se usa otra vez",
     'struct P { nombre: str, edad: usize, sub: Q } struct Q { t: str } fn toma(p: P) -> usize { return p.edad; } fn nuevo_p() -> P { return P { nombre: nuevo("a"), edad: 1, sub: Q { t: nuevo("b") } }; } fn main() { let p = nuevo_p(); let n = p.nombre; let m = p.nombre;'
     ' imprimir(n); imprimir(m); }',
     "`p.nombre` ya se saco"),

    ("un campo no se saca dentro de un `if`",
     'struct P { nombre: str, edad: usize, sub: Q } struct Q { t: str } fn toma(p: P) -> usize { return p.edad; } fn nuevo_p() -> P { return P { nombre: nuevo("a"), edad: 1, sub: Q { t: nuevo("b") } }; } fn main() { let p = nuevo_p(); if true { let n = p.nombre;'
     ' imprimir(n); } }',
     "no se puede sacar `p.nombre` dentro de un `if`"),

    ("ni de algo prestado",
     'struct P { nombre: str, edad: usize, sub: Q } struct Q { t: str } fn toma(p: P) -> usize { return p.edad; } fn nuevo_p() -> P { return P { nombre: nuevo("a"), edad: 1, sub: Q { t: nuevo("b") } }; } fn f(p: &P) -> str { return p.nombre; }',
     "`p` es prestada: no se puede sacar `p.nombre`"),

    ("ni mientras una vista lo mira",
     'struct P { nombre: str, edad: usize, sub: Q } struct Q { t: str } fn toma(p: P) -> usize { return p.edad; } fn nuevo_p() -> P { return P { nombre: nuevo("a"), edad: 1, sub: Q { t: nuevo("b") } }; } fn main() { var p = nuevo_p(); let v = vista(p.nombre);'
     ' let n = p.nombre; imprimir(v); imprimir(n); }',
     "no se puede sacar `p.nombre`: esta prestada por `v`"),

    ("reponerlo dentro de un `if` no lo repone para despues",
     'struct P { nombre: str, edad: usize, sub: Q } struct Q { t: str } fn toma(p: P) -> usize { return p.edad; } fn nuevo_p() -> P { return P { nombre: nuevo("a"), edad: 1, sub: Q { t: nuevo("b") } }; } fn main() { var p = nuevo_p(); let n = p.nombre;'
     ' if true { p.nombre = nuevo("x"); } imprimir(toma(p)); imprimir(n); }',
     "`p` esta a medio mover"),

    # ---- patrones anidados, literales y guardas ----
    ("un brazo con condiciones no cubre su forma el solo",
     'enum E2 { A, B(i64) } enum E { X, Y(i64), Z(str, E2) } fn f(e: &E) -> usize { return match e { E.X -> 0, E.Y(1) -> 1,'
     ' E.Z(_, _) -> 2, }; }',
     "le pueden quedar casos de `E.Y` sin mirar"),

    ("un brazo detras de otro que ya lo cubre no se ejecuta nunca",
     'enum E2 { A, B(i64) } enum E { X, Y(i64), Z(str, E2) } fn f(e: &E) -> usize { return match e { E.X -> 0, E.Y(_) -> 1,'
     ' E.Y(3) -> 2, E.Z(_, _) -> 3, }; }',
     "`E.Y` se mira dos veces"),

    ("un literal del patron tiene que ser del tipo de su posicion",
     'enum E2 { A, B(i64) } enum E { X, Y(i64), Z(str, E2) } fn f(e: &E) -> usize { return match e { E.Y("a") -> 1, _ -> 2, }; }',
     "el literal del patron no es uno"),

    ("una forma anidada tiene que ser del enum de su posicion",
     'enum E2 { A, B(i64) } enum E { X, Y(i64), Z(str, E2) } fn f(e: &E) -> usize { return match e { E.Y(E2.A) -> 1, _ -> 2, }; }',
     "el patron pone `E2.A`"),

    ("la guarda es un `bool`",
     'enum E2 { A, B(i64) } enum E { X, Y(i64), Z(str, E2) } fn f(e: &E) -> usize { return match e { E.Y(n) if n -> 1, _ -> 2, }; }',
     "la guarda de un brazo tiene que ser `bool`"),

    ("una guarda no mueve nada",
     'enum E2 { A, B(i64) } enum E { X, Y(i64), Z(str, E2) } fn g(s: str) -> bool { return largo(s) > 0; }'
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
     "`p` se presta dos veces en la misma llamada a `g`"),

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
     "<test>:4: se esperaba una expresion"),

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


ACEPTA = [
    # Un `Entero` suelto ya sale como `usize` al deducir, asi que `-3`
    # deducia `A = usize` y despues no cabia.
    ("un negativo deduce un tipo con signo en un struct generico",
     '''struct Par<A, B> { a: A, b: B, }
        fn main() {
            let q = Par { a: -3, b: 1 };
            let z = -7;
            imprimir($"{q.a} {q.b} {z}\\n");
        }''',
     "-3 1 -7\n"),

    # `\{` y `\}` en una interpolada son una llave escrita, como `{{` y `}}`.
    # Antes el lexer las descifraba y el parser las tomaba por un hueco.
    ("una llave escrita con barra en una cadena interpolada",
     '''fn main() {
            let n: usize = 3;
            imprimir($"a \\{ b \\} c {n} {{d}}\\n");
        }''',
     "a { b } c 3 {d}\n"),

    # `partir_tipos` cortaba por las comas de dentro de un `fn(...)` y
    # contaba la `>` de `->` como un angulo que se cierra.
    ("un tipo funcion que recibe otro",
     '''fn doble(n: usize) -> usize { return n * 2; }
        fn aplicar(f: fn(usize) -> usize, n: usize) -> usize { return f(n); }
        fn dos_veces(g: fn(fn(usize) -> usize, usize) -> usize, n: usize) -> usize {
            return g(doble, g(doble, n));
        }
        fn main() { imprimir($"{dos_veces(aplicar, 3)}\\n"); }''',
     "12\n"),

    ("los limites exactos de los enteros siguen siendo validos",
     '''fn main() {
            let a: u8 = 255;
            let b: i8 = 127;
            let c: i8 = -128;
            let d: u64 = 18446744073709551615;
            let e: i64 = 9223372036854775807;
            let f: i64 = -9223372036854775808;
            imprimir($"{a} {b} {c} {d} {e} {f}\\n");
        }''',
     "255 127 -128 18446744073709551615 9223372036854775807 "
     "-9223372036854775808\n"),

    ("los limites finitos de los decimales siguen siendo validos",
     '''fn main() {
            let a: f32 = 3.4028234e38;
            let b: f64 = 1.7976931348623157e308;
            imprimir(a > 0.0); imprimir(" "); imprimir(b > 0.0);
        }''',
     "true true"),

    # Como se escribe el maximo en Rust o Java: redondea a el, no a infinito.
    ("el maximo escrito corto redondea al maximo, no a infinito",
     '''fn main() {
            let a: f32 = 3.4028235e38;
            let b: f64 = 1.7976931348623158e308;
            let c: f64 = 9007199254740992;
            let d: f32 = 16777216;
            imprimir($"{a == 3.4028234e38} {b == 1.7976931348623157e308} ");
            imprimir($"{c} {d}\\n");
        }''',
     "true true 9.0072e+15 1.67772e+07\n"),

    # Un `usize` ancho pasa por `SS_LANG_USIZE_LIT`, que en un destino de 32
    # bits detiene la compilacion de C. Aqui, en 64, vale lo que vale. Y un
    # cero delante no convierte el numero en octal.
    ("un usize ancho y un cero delante",
     '''fn main() {
            let a: usize = 5000000000;
            let b = 010;
            imprimir($"{a} {b}\\n");
        }''',
     "5000000000 10\n"),

    # ---- aritmetica envolvente ----
    #
    # `+?` se generaba con el operador del propio tipo: con signo, dar la
    # vuelta es comportamiento indefinido en C, y un `u16 * u16` pasa por
    # `int`. UBSan lo paraba.
    ("la envolvente da la vuelta sin comportamiento indefinido",
     '''fn main() {
            var x: i64 = 9223372036854775807;
            x = x +? 1;
            var m: u16 = 65535;
            m = m *? 65535;
            var c: i32 = 2147483647;
            c = c +? 2;
            var u: u8 = 0;
            u = u -? 1;
            imprimir($"{x} {m} {c} {u}\\n");
        }''',
     "-9223372036854775808 1 -2147483647 255\n"),

    # ---- banderas de soltar, una por declaracion ----
    #
    # Dos bloques hermanos pueden declarar el mismo nombre. La bandera de
    # "sigue viva" es de cada declaracion, no del nombre: con una por nombre
    # el C no compilaba, o se perdia la de un bloque al mover la del otro.
    ("dos bloques hermanos con el mismo nombre, movido solo en uno",
     '''fn f(c: bool) -> usize {
            var xs: lista<str> = [];
            if c {
                let t = nuevo("uno");
                if largo(xs) == 0 { anadir(xs, t); }
            }
            if largo(xs) < 10 {
                let t = nuevo("dos");
                if c { anadir(xs, t); }
                if largo(xs) > 0 { return largo(xs); }
            }
            return 0;
        }
        fn main() { imprimir($"{f(false)} {f(true)}\\n"); }''',
     "0 2\n"),

    ("una clausura puede usar el nombre de una variable de quien la crea",
     '''fn main() {
            let x: usize = 3;
            let doble = fn(x: usize) -> usize { return x * 2; };
            imprimir($"{doble(x)}\\n");
        }''',
     "6\n"),

    # Lo encontro escribir el compilador en Tcode: el typedef del arreglo
    # salia antes de escribir los cuerpos, y este solo aparece dentro de uno.
    ("recorrer un arreglo literal sin nombre",
     '''fn main() {
            for x en ["uno", "dos", "tres"] {
                imprimir($"{x}\\n");
            }
            var n = 0;
            for k en [1, 2, 3] { n = n + k; }
            imprimir($"{n}\\n");
        }''',
     "uno\ndos\ntres\n6\n"),

    # ---- temporales en las salidas tempranas ----
    #
    # Los cinco los encontro ejecutar bajo AddressSanitizer el compilador
    # escrito en Tcode: el generador perdia memoria, o escribia un C que no
    # compilaba, cuando se salia de una sentencia antes de su limpieza de fin.
    ("un return dentro de un if suelta el temporal de la condicion",
     '''fn f() -> usize {
            var m: mapa<str, usize> = [];
            poner(m, "a", 1);
            poner(m, "b", 2);
            if largo(claves(m)) > 0 {
                return 1;
            }
            return 0;
        }
        fn main() { imprimir($"{f()}\\n"); }''',
     "1\n"),

    ("y un return dentro de dos if suelta los de las dos condiciones",
     '''fn f() -> usize {
            var m: mapa<str, usize> = [];
            poner(m, "a", 1);
            if largo(claves(m)) > 0 {
                if largo(claves(m)) < 10 {
                    return 1;
                }
            }
            return 0;
        }
        fn main() { imprimir($"{f()}\\n"); }''',
     "1\n"),

    ("un break dentro de un if suelta el temporal de la condicion",
     '''fn f() -> usize {
            var m: mapa<str, usize> = [];
            poner(m, "a", 1);
            var n = 0;
            while n < 3 {
                n = n + 1;
                if largo(claves(m)) > 0 {
                    break;
                }
            }
            return n;
        }
        fn main() { imprimir($"{f()}\\n"); }''',
     "1\n"),

    ("un continue lo suelta en cada vuelta",
     '''fn f() -> usize {
            var m: mapa<str, usize> = [];
            poner(m, "a", 1);
            var n = 0;
            while n < 3 {
                n = n + 1;
                if largo(claves(m)) > 5 {
                    n = n + 0;
                } else {
                    if largo(claves(m)) > 0 {
                        continue;
                    }
                }
            }
            return n;
        }
        fn main() { imprimir($"{f()}\\n"); }''',
     "3\n"),

    ("la condicion de un while con temporal propio se suelta en cada vuelta",
     '''fn f() -> usize {
            var m: mapa<str, usize> = [];
            poner(m, "a", 1);
            var n = 0;
            while largo(claves(m)) > n {
                n = n + 1;
            }
            return n;
        }
        fn main() { imprimir($"{f()}\\n"); }''',
     "1\n"),

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

    ("`intercambiar` evalua el sitio una sola vez",
     '''fn siguiente(i: mut usize) -> usize {
            let antes = i;
            i = i + 1;
            return antes;
        }
        fn main() {
            var xs = [10, 20];
            var i = 0;
            let viejo = intercambiar(xs[siguiente(i)], 99);
            imprimir($"{viejo} {xs[0]} {xs[1]} {i}\\n");
        }''',
     "10 99 20 1\n"),

    ("un indice anidado evalua la base una sola vez",
     '''fn siguiente(i: mut usize) -> usize {
            let antes = i;
            i = i + 1;
            return antes;
        }
        fn main() {
            var xs: lista<bloque<usize>> = [];
            var b: bloque<usize> = reservar(1);
            b[0] = 7;
            anadir(xs, b);
            var i = 0;
            let viejo = intercambiar(xs[siguiente(i)][0], 9);
            imprimir($"{viejo} {xs[0][0]} {i}\\n");
        }''',
     "7 9 1\n"),

    ("un indice anidado conserva el cortocircuito",
     '''fn siguiente(i: mut usize) -> usize {
            let antes = i;
            i = i + 1;
            return antes;
        }
        fn main() {
            var xs: lista<bloque<usize>> = [];
            var b: bloque<usize> = reservar(1);
            anadir(xs, b);
            var i = 0;
            if false && xs[siguiente(i)][0] == 1 { imprimir("mal"); }
            imprimir(i);
        }''',
     "0"),

    ("redimensionar evalua el sitio antes que el tamaño",
     '''fn siguiente(i: mut usize) -> usize {
            let antes = i;
            i = i + 1;
            return antes;
        }
        fn main() {
            var xs: lista<bloque<usize>> = [];
            var a: bloque<usize> = reservar(2);
            var b: bloque<usize> = reservar(3);
            anadir(xs, a);
            anadir(xs, b);
            var i = 0;
            redimensionar(xs[siguiente(i)], siguiente(i));
            imprimir($"{largo(xs[0])} {largo(xs[1])} {i}\\n");
        }''',
     "1 3 2\n"),

    ("listas de bloques y mapas registran sus tipos interiores",
     '''fn main() -> usize ! {
            var bloques: lista<bloque<usize>> = [];
            var b: bloque<usize> = reservar(2);
            b[1] = 7;
            anadir(bloques, b);

            var mapas: lista<mapa<str, usize>> = [];
            var m: mapa<str, usize> = [];
            poner(m, "x", 9);
            anadir(mapas, m);
            imprimir($"{bloques[0][1]} {try obtener(mapas[0], "x")}\\n");
            return 0;
        }''',
     "7 9\n"),

    ("un bloque guardado en un mapa se presta para modificar",
     '''fn main() -> usize ! {
            var m: mapa<str, bloque<usize>> = [];
            var b: bloque<usize> = reservar(1);
            b[0] = 4;
            poner(m, "x", b);
            let p: &mut bloque<usize> = try obtener_mut(m, "x");
            redimensionar(p, 2);
            p[1] = 8;
            imprimir($"{largo(p)} {p[0]} {p[1]}\\n");
            return 0;
        }''',
     "2 4 8\n"),

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

    ("`&&` y `||` no evaluan la derecha si la izquierda ya decide",
     '''fn nombre(xs: &lista<str>) -> str {
    imprimir("[se evaluo] ");
    return copiar(xs[0]);
}

fn corto(v: view) -> bool { return largo(v) < 3; }

fn main() {
    var xs: lista<str> = [];
    // Con la lista vacia, la derecha no se puede evaluar: el `&&` corta.
    if largo(xs) == 1 && corto(nombre(xs)) { imprimir("no\\n"); }
    if largo(xs) == 0 || corto(nombre(xs)) { imprimir("corta el ||\\n"); }
    anadir(xs, nuevo("ab"));
    if largo(xs) == 1 && corto(nombre(xs)) { imprimir("si\\n"); }
    let a = largo(xs) > 5 || corto(nombre(xs));
    imprimir($"{a}\\n");
}''',
     "corta el ||\n[se evaluo] si\n[se evaluo] true\n"),

    ("un enum que lleva un struct, y otro enum escrito mas abajo",
     '''// Un enum que lleva un struct, y otro enum escrito mas abajo.
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
    for f en fs { imprimir($"{describir(f)}\\n"); }
    let otra = copiar(fs[4]);
    imprimir($"{describir(otra)}\\n");
}''',
     "nada\n(1, -2)\nazul en (3, 4)\nrojo en (0, 0)\nhola\nhola\n"),

    ("structs con un campo `view`",
     '''struct Palabra { texto: view, n: usize }
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
    imprimir($"{p.texto} {texto_de(q)} {l.primera.texto}|{l.resto} {m.texto} {copiar(m).n}\\n");
}''',
     "hol adios hol|mundo hol 3\n"),

    ("sacar un campo de su struct, y reponerlo",
     '''struct Interior { texto: str, n: usize }
struct P { nombre: str, edad: usize, tags: lista<str>, dentro: Interior }

fn usa(s: str) -> usize { return largo(s); }

fn entrega(p: P) -> str {
    return p.nombre;
}

fn main() {
    var p = P { nombre: nuevo("ana"), edad: 3, tags: [], dentro: Interior { texto: nuevo("hondo"), n: 1 } };
    anadir(p.tags, nuevo("x"));
    let n = p.nombre;
    let t = p.dentro.texto;
    imprimir($"{n} {t} {p.edad} {largo(p.tags)} {p.dentro.n} ");
    imprimir($"{usa(copiar(p.tags[0]))}\\n");
    p.nombre = nuevo("eva");
    p.dentro.texto = nuevo("otra");
    let q = p;
    imprimir($"{q.nombre} {q.dentro.texto} {entrega(q)}\\n");
}''',
     "ana hondo 3 1 1 1\neva otra eva\n"),

    ("sacar un campo en un `return`, en cualquier rama",
     '''struct P { nombre: str, edad: usize, sub: Q }
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
    imprimir($"{n} {nombre_si(p, true)} {nombre_si(nuevo_p("x"), false)}\\n");
}''',
     "ana eva ninguno\n"),

    ("patrones anidados, literales y guardas; y un `break` dentro de un `match`",
     '''enum Forma2 { A, B(i64) }
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
    for f en fs { imprimir($"{describir(f)}\\n"); }
    // Un `break` dentro de un `match` sale del bucle, no del `match`.
    while i < 10 {
        match fs[i] {
            Forma.Punto -> { i = i + 1; }
            Forma.Circulo(r) -> { if r == 500 { break; } i = i + 1; }
            _ -> { i = i + 1; }
        }
    }
    imprimir($"parado en {i}\\n");
}''',
     "punto\ncirculo vacio\ncirculo raro\ncirculo grande\ncirculo\nsaludo\n"
     "cielo de color azul\netiqueta x\npar 3 7\npar cualquiera 8\nparado en 3\n"),

    ("devolver una vista de un parametro prestado",
     '''struct Persona { nombre: str, apellido: str }

        fn nombre_de(p: &Persona) -> view { return vista(p.nombre); }
        fn primera(xs: &lista<str>) -> view { return vista(xs[0]); }
        fn inicial(s: &str) -> view { return rebanar(vista(s), 0, 1); }
        fn la_larga(a: &str, b: &str) -> view {
            if largo(a) >= largo(b) { return vista(a); }
            return vista(b);
        }
        // Un `mut str` tambien: la vista sale despues de modificarlo.
        fn con_punto(s: mut str) -> view {
            empujar(s, ".");
            return vista(s);
        }

        fn main() {
            let p = Persona { nombre: nuevo("Ada"), apellido: nuevo("Lovelace") };
            var xs: lista<str> = [];
            anadir(xs, nuevo("uno"));
            let a = nuevo("corto");
            let b = nuevo("larguisimo");
            var s = nuevo("fin");
            imprimir($"{nombre_de(p)} {primera(xs)} {inicial(a)} {la_larga(a, b)} ");
            // Reasignar en el mismo bloque, o con el duenio fuera, vale.
            var v: view = "literal";
            v = la_larga(a, b);
            imprimir($"{v} {con_punto(s)} ");
            // Pasar un temporal y usar la vista en la misma sentencia vale.
            imprimir($"{inicial(nuevo("zeta"))}\\n");
        }''',
     "Ada uno c larguisimo larguisimo fin. z\n"),

    ("una clausura que modifica lo capturado guarda su estado entre llamadas",
     '''fn repetir<F>(n: usize, f: mut F) {
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
            imprimir($"{contar()} {contar()} ");
            // La generica la recibe `mut`: lo que cambia, cambia aqui.
            repetir(3, contar);
            // Lo capturado es una copia: la `n` de fuera no se entera.
            imprimir($"{contar()} {n} | ");

            let s = nuevo("a");
            var acumula = fn[mut s](x: view) -> usize {
                empujar(s, x);
                return largo(s);
            };
            imprimir($"{acumula("bc")} ");
            // Copiarla copia tambien su estado, y desde ahi van por separado.
            var otra = copiar(acumula);
            imprimir($"{otra("d")} {acumula("e")}\\n");
        }''',
     "1 2 6 0 | 3 4 4\n"),

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

    ("un entero grande exactamente representable se convierte a f64",
     '''fn main() {
            let n: u64 = 9007199254740992;
            imprimir(n como f64); imprimir("\\n");
        }''',
     "9.0072e+15\n"),

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

    ("la aritmetica envolvente con signo no depende del compilador C",
     '''fn main() {
            let max: i8 = 127;
            let uno: i8 = 1;
            let cien: i8 = 100;
            let dos: i8 = 2;
            imprimir(max +? uno); imprimir(" ");
            imprimir(cien *? dos); imprimir(" ");
            let minimo: i8 = max +? uno;
            imprimir(~minimo); imprimir(" ");
            imprimir(minimo >> 1); imprimir(" ");
            imprimir(minimo & max); imprimir(" ");
            imprimir(minimo | uno); imprimir(" ");
            imprimir(minimo ^ uno); imprimir(" ");
            let cero: i8 = 0;
            let menos_uno: i8 = cero - uno;
            imprimir(minimo % menos_uno); imprimir(" ");
            let cinco: i8 = 5;
            imprimir(-cinco); imprimir("\\n");
        }''',
     "-128 -56 127 -64 0 -127 -127 0 -5\n"),

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

    ("devolver un parametro escalar prestado devuelve su valor, no su direccion",
     '''fn subir(n: mut usize) -> usize {
            n = n + 1;
            return n;
        }
        fn mirar(n: &usize) -> usize { return n; }
        fn main() -> usize {
            var x: usize = 7;
            imprimir(subir(x)); imprimir(" ");
            imprimir(mirar(x)); imprimir("\\n");
            return 0;
        }''',
     "8 8\n"),

    ("los argumentos de una funcion se evaluan de izquierda a derecha",
     '''fn siguiente(n: mut usize) -> usize {
            n = n + 1;
            return n;
        }
        fn juntar(a: usize, b: usize) -> usize { return a * 10 + b; }
        fn main() -> usize {
            var n: usize = 0;
            imprimir(juntar(siguiente(n), siguiente(n)));
            imprimir("\\n");
            return 0;
        }''',
     "12\n"),

    ("los argumentos de una funcion externa tambien van de izquierda a derecha",
     '''externo "math.h" {
            fn pow(base: f64, exponente: f64) -> f64;
        }
        fn siguiente(n: mut f64) -> f64 {
            n = n + 1.0;
            return n;
        }
        fn main() {
            var n: f64 = 1.0;
            imprimir(pow(siguiente(n), siguiente(n)));
            imprimir("\\n");
        }''',
     "8.0\n"),

    ("las comparaciones internas evaluan sus operandos de izquierda a derecha",
     '''fn siguiente(n: mut usize) -> usize {
            n = n + 1;
            return n;
        }
        fn main() {
            var n: usize = 0;
            imprimir(menor(siguiente(n), siguiente(n)));
            imprimir("\\n");
        }''',
     "true\n"),

    ("los operadores binarios evaluan primero el operando izquierdo",
     '''fn siguiente(n: mut usize) -> usize {
            n = n + 1;
            return n;
        }
        fn main() {
            var n: usize = 0;
            imprimir(siguiente(n) * 10 + siguiente(n));
            imprimir(" ");
            n = 0;
            imprimir(siguiente(n) < siguiente(n));
            imprimir("\\n");
        }''',
     "12 true\n"),

    ("los literales compuestos evaluan sus valores de izquierda a derecha",
     '''struct Par { a: usize, b: usize }
        enum Dos { Valores(usize, usize) }
        fn siguiente(n: mut usize) -> usize {
            n = n + 1;
            return n;
        }
        fn main() {
            var n: usize = 0;
            let p: Par = Par { a: siguiente(n), b: siguiente(n) };
            imprimir(p.a); imprimir(p.b); imprimir(n); imprimir(" ");
            n = 0;
            let a: [usize; 2] = [siguiente(n), siguiente(n)];
            imprimir(a[0]); imprimir(a[1]); imprimir(n); imprimir(" ");
            n = 0;
            let e: Dos = Dos.Valores(siguiente(n), siguiente(n));
            imprimir(match e { Dos.Valores(x, y) -> x * 10 + y, });
            imprimir(n); imprimir("\\n");
        }''',
     "122 122 122\n"),

    ("rebanar evalua texto, inicio y final de izquierda a derecha",
     '''fn siguiente(n: mut usize) -> usize {
            n = n + 1;
            return n;
        }
        fn main() {
            var n: usize = 0;
            imprimir(rebanar("abcd", siguiente(n), siguiente(n)));
            imprimir("\\n");
        }''',
     "b\n"),

    ("los mutadores evaluan el destino antes que el valor",
     '''fn siguiente(n: mut usize) -> usize {
            n = n + 1;
            return n;
        }
        fn siguiente_texto(n: mut usize) -> str {
            n = n + 1;
            return texto(n);
        }
        fn main() {
            var n: usize = 0;
            var listas: lista<lista<usize>> = [];
            anadir(listas, []); anadir(listas, []); anadir(listas, []);
            anadir(listas[siguiente(n)], siguiente(n));
            imprimir(listas[1][0]); imprimir(" ");
            n = 0;
            var textos: [str; 3] = [nuevo("0"), nuevo("1"), nuevo("2")];
            empujar(textos[siguiente(n)], siguiente_texto(n));
            imprimir(textos[1]); imprimir("\\n");
        }''',
     "2 12\n"),

    ("un arreglo puede contener listas con su typedef declarado antes",
     '''fn main() {
            var xs: [lista<usize>; 2] = [[], []];
            anadir(xs[1], 7);
            imprimir(xs[1][0]); imprimir("\\n");
        }''',
     "7\n"),

    ("poner fija mapa, clave y valor en ese orden",
     '''fn siguiente(n: mut usize) -> usize {
            n = n + 1;
            return n;
        }
        fn siguiente_clave(n: mut usize) -> str {
            n = n + 1;
            return texto(n);
        }
        fn main() {
            var n: usize = 0;
            var ms: [mapa<str, usize>; 4] = [[], [], [], []];
            poner(ms[siguiente(n)], siguiente_clave(n), siguiente(n));
            imprimir(obtener(ms[1], "2") sino 0); imprimir("\\n");
        }''',
     "3\n"),

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
        usar "std/texto";
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
    # En C17 `??=` es un trigrafo: C lo cambiaba por `#` y el largo de al
    # lado leia de mas.
    ("una cadena con `??` sale con los mismos bytes",
     'fn main() { imprimir("??= ??/ ??! ???=\\n"); imprimir(largo("??="));'
     ' imprimir("\\n"); }',
     "??= ??/ ??! ???=\n3\n"),

    # Un `match` suelto con brazos que dan un valor no hacia nada.
    ("un `match` suelto hace lo de sus brazos",
     '''enum E { A, B }
        fn efecto(xs: mut lista<usize>) -> usize { anadir(xs, 1); return 0; }
        fn texto_de(e: &E) -> str {
            return match e { E.A -> nuevo("una cadena en el heap"), E.B -> nuevo("b") };
        }
        fn main() {
            var xs: lista<usize> = [];
            let e = E.A;
            match e { E.A -> imprimir("A\\n"), E.B -> imprimir("B\\n") }
            match e { E.A -> efecto(xs), E.B -> 0 }
            match e { E.A -> texto_de(e), E.B -> nuevo("otra cadena en el heap") }
            imprimir(largo(xs));
            imprimir("\\n");
        }''',
     "A\n1\n"),

    # `%s` y `%.*s` se paraban en el primer cero.
    ("`imprimir` saca los bytes cero de un `str`",
     'fn main() { var s = nuevo("a\\x00b"); empujar(s, "c");'
     ' imprimir(s); imprimir("|"); imprimir($"{s}|\\n"); }',
     "a\x00bc|a\x00bc|\n"),

    ("nombres que en C ya son otra cosa",
     '''enum E { free, otra(str) }
        struct tm { log: usize, EOF: usize }
        fn exp(x: usize) -> usize { return x + 1; }
        fn _Bool(ss_tmp1: usize) -> usize { return ss_tmp1 * 2; }
        fn main() {
            let e = E.otra(nuevo("hola"));
            match e { E.free -> imprimir("f\\n"), E.otra(NAN) -> imprimir($"{NAN}\\n") }
            let p = tm { log: 1, EOF: 2 };
            let stdout = 3;
            var m: mapa<str, usize> = [];
            poner(m, "k", 4);
            for k, argc en m { imprimir($"{k}={argc}\\n"); }
            let size_t: usize = 5;
            var puts = fn[mut size_t]() -> usize { size_t = size_t + 1; return size_t; };
            imprimir(exp(p.log) + p.EOF + stdout + _Bool(1) + puts());
            imprimir("\\n");
        }''',
     "hola\nk=4\n15\n"),

    ("cadenas con llaves, comillas y escapes dentro de un hueco",
     'fn f(a: view) -> view { return a; }'
     ' fn main() {'
     ' imprimir($"[{f("}")}] [{f("a\\"b")}] [{f("x\\ny")}] [{f($"{f("{")}")}]\\n");'
     ' imprimir($"{f(\\"antes\\")}\\n"); }',
     '[}] [a"b] [x\ny] [{]\nantes\n'),

    ("mil parentesis anidados",
     'fn main() { let x: usize = ' + '(' * 1000 + '1' + ')' * 1000
     + '; imprimir(x); imprimir("\\n"); }',
     "1\n"),

    # Un numero escrito toma el tipo del otro lado. El comprobador lo sabia,
    # pero el generador hacia la cuenta en el tipo del literal, `usize`:
    # `1 + x` con `x: f64` daba 3, `0 > x` con `x: i32` negativo daba
    # `false`, y `5 - 10` en un `i64` paraba por desbordamiento.
    # Una generica deduce su tipo como el comprobador tipa: un numero escrito
    # toma el del otro lado, y una conversion, un `if` o `absoluto` dicen el
    # suyo. Antes `mismo(1 + x)` pedia un `usize` y rechazaba el `i16`.
    ("una generica deduce su tipo de una cuenta, una conversion o un if",
     '''fn mismo<T>(x: T) -> T { return x; }
        fn main() {
            let x: i16 = 5;
            let c = x > 1;
            imprimir($"{mismo(1 + x)} {mismo(x como u32)} ");
            imprimir($"{mismo(if c { x } else { 2 })} {mismo(absoluto(x))}\\n");
        }''',
     "6 5 5 5\n"),

    # Una rama entera y otra decimal son un decimal, como `1 + 2.5`.
    ("un if con una rama entera y otra decimal",
     '''fn main() {
            let c = true;
            let v: f64 = if c { 1 } else { 2.5 };
            let w: f32 = if c { 2.5 } else { 1 };
            imprimir($"{v} {w} {if c { 1 } else { 2.5 }}\\n");
        }''',
     "1.0 2.5 1.0\n"),

    # De izquierda a derecha, tambien cuando un operando necesita sentencias
    # propias: antes el `if` de la derecha corria antes que lo de la
    # izquierda, y salia `der izq`.
    ("el operando que necesita sentencias no adelanta a los de antes",
     '''struct P { a: i64, b: i64 }
        fn dice(t: view, n: i64) -> i64 { imprimir(t); return n; }
        fn f(a: i64, b: i64) -> i64 { return a + b; }
        fn main() {
            let c = true;
            let x = dice("izq ", 1) + (if c { dice("der ", 2) } else { 0 });
            imprimir($"= {x}\\n");
            let y = f(dice("a1 ", 1), if c { dice("a2 ", 2) } else { 0 });
            imprimir($"= {y}\\n");
            let p = P { a: dice("c1 ", 1), b: if c { dice("c2 ", 2) } else { 0 } };
            imprimir($"= {p.a + p.b}\\n");
            let arr: [i64; 2] = [dice("e1 ", 1), if c { dice("e2 ", 2) } else { 0 }];
            imprimir($"= {arr[0] + arr[1]}\\n");
        }''',
     "izq der = 3\na1 a2 = 3\nc1 c2 = 3\ne1 e2 = 3\n"),

    # Tambien un valor con duenio: pasa al temporal, y de ahi a la funcion.
    ("un str que va antes tampoco se deja adelantar",
     '''fn dice(t: view) -> str { imprimir(t); return nuevo(t); }
        fn junta(a: str, b: str) -> usize { return largo(a) + largo(b); }
        fn main() {
            let c = true;
            let n = junta(dice("a "), if c { dice("b ") } else { nuevo("") });
            imprimir($"= {n}\\n");
        }''',
     "a b = 4\n"),

    ("un numero escrito se opera en el tipo del otro lado",
     '''fn main() {
            let x: f64 = 2.5;
            let n: i32 = -3;
            let k: u8 = 3;
            let a: i64 = 5 - 10;
            let d: f64 = 1 / 2;
            let w = 0 -? k;
            imprimir($"{1 + x} {2 * x} {0 > n} {1 + n} {a} {d} {w}\\n");
            imprimir($"{-1} {-(2 + 3)} {(1 + n) como i64} {1 << k}\\n");
        }''',
     "3.5 5.0 true -2 -5 0.5 253\n-1 -5 -2 8\n"),
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

    ("una captura `mut` que nunca se modifica",
     'fn f() { let n: usize = 1;'
     ' var g = fn[mut n]() -> usize { return n; }; imprimir(g()); }',
     "puede ir sin `mut`"),
]


# Programas que compilan pero deben ABORTAR en tiempo de ejecucion.
ABORTA = [
    # Antes daba una vista vacia, un resultado equivocado que nadie veia.
    ("`rebanar` fuera de rango detiene el programa",
     'fn main() { let s = nuevo("hola"); let v = rebanar(vista(s), 3, 10);'
     ' imprimir(largo(v)); }',
     "rebanar(3, 10) fuera de rango (el texto tiene 4 bytes)"),

    ("`rebanar` con el principio detras del final",
     'fn main() { let s = nuevo("hola"); imprimir(rebanar(vista(s), 3, 2)); }',
     "rebanar(3, 2) fuera de rango"),

    ("`azar(0)` pide un numero de un rango vacio",
     'fn main() -> usize { let n = 0; imprimir(azar(n)); return 0; }',
     "rango vacio"),

    ("un cero en medio de un `str` no va a C cortado",
     'usar "std/texto";'
     ' externo "string.h" { fn strlen(s: str) -> usize; }'
     ' fn main() -> usize { var s = nuevo("HO"); empujar_byte(s, 0);'
     ' empujar(s, "LA"); imprimir(strlen(s)); return 0; }',
     "cero en medio"),

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

    ("una conversion decimal negativa a unsigned para antes del cast",
     'fn main() { let f: f64 = 0.0 - 1.0; imprimir(f como usize); }',
     "no cabe en `usize` viniendo de `f64`"),

    ("una conversion decimal sobre el limite de u64 para antes del cast",
     'fn main() { let f: f64 = 18446744073709551616.0; imprimir(f como u64); }',
     "no cabe en `u64` viniendo de `f64`"),

    ("una conversion de NaN a entero para antes del cast",
     'fn main() { let z: f64 = 0.0; let n = z /? z; imprimir(n como i64); }',
     "no cabe en `i64` viniendo de `f64`"),

    ("u64 maximo no se redondea a 2^64 al convertirlo a f64",
     'fn main() { let n: u64 = 18446744073709551615; imprimir(n como f64); }',
     "no cabe en `f64` viniendo de `u64`"),

    ("un entero sobre la mantisa de f64 no pierde un bit en silencio",
     'fn main() { let n: u64 = 9007199254740993; imprimir(n como f64); }',
     "no cabe en `f64` viniendo de `u64`"),

    ("un entero unsigned no entra en un signed mas estrecho antes del cast",
     'fn main() { let n: u64 = 18446744073709551615; imprimir(n como i64); }',
     "no cabe en `i64` viniendo de `u64`"),

    ("un entero negativo no entra en unsigned antes del cast",
     'fn main() { let z: i64 = 0; let n: i64 = z - 1; imprimir(n como u64); }',
     "no cabe en `u64` viniendo de `i64`"),

    ("un decimal fuera de f32 para antes del estrechamiento",
     'fn main() { let n: f64 = 1e100; imprimir(n como f32); }',
     "no cabe en `f32` viniendo de `f64`"),

    ("un f64 que perderia precision al estrecharse para",
     'fn main() { let n: f64 = 0.1; imprimir(n como f32); }',
     "no cabe en `f32` viniendo de `f64`"),

    ("dividir el minimo signed por menos uno para antes del C indefinido",
     '''fn main() {
            let max: i8 = 127; let uno: i8 = 1;
            let minimo: i8 = max +? uno;
            let cero: i8 = 0; let menos_uno: i8 = cero - uno;
            imprimir(minimo / menos_uno);
        }''',
     "desbordamiento en `/`"),

    ("negar el minimo signed para antes del C indefinido",
     '''fn main() {
            let max: i8 = 127; let uno: i8 = 1;
            let minimo: i8 = max +? uno;
            imprimir(-minimo);
        }''',
     "desbordamiento en `-`"),

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

    # Con el literal delante, la cuenta se hacia en `usize` y no desbordaba.
    ("un literal delante no esquiva el desbordamiento de un `u8`",
     'fn main() { let x: u8 = 255; imprimir(1 + x); }',
     "desbordamiento en `+`"),

    ("ni el de un `i8`",
     'fn main() { let q: i8 = 100; imprimir(100 + q); }',
     "desbordamiento en `+`"),

    ("ni el infinito de un `f32`",
     'fn main() { let f: f32 = 10.0; imprimir(3e38 * f); }',
     "no dio un numero"),

    ("dos literales se operan en el tipo que se espera",
     'fn main() { let y: u8 = 200 + 100; imprimir(y); }',
     "desbordamiento en `+`"),

    # La rama escrita de un `if` es del tipo de la otra: la cuenta es de
    # `f32` y se pasa del maximo. Antes se hacia en `f64` y seguia.
    ("un if con una rama escrita no saca la cuenta de su tipo",
     'fn main() { let f: f32 = 3.4028235e38; let c = f < 1.0;'
     ' imprimir((if c { 1.5 } else { f }) * f); }',
     "`*` no dio un numero"),
]


fallos = 0
total = 0


def falla(nombre, detalle):
    global fallos
    fallos += 1
    print(f"  FALLA: {nombre}\n         {detalle}")


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

    ("lo que usa un modulo usado no se ve sin pedirlo",
     {"hondo.t": 'fn doble(n: usize) -> usize { return n * 2; }',
      "medio.t": 'usar "hondo.t"; fn cuatro(n: usize) -> usize { return doble(doble(n)); }',
      "app.t": 'usar "medio.t"; fn main() { imprimir($"{doble(cuatro(1))}\\n"); }'},
     "app.t", "que este archivo no usa", None),

    ("una variable local con el nombre de una funcion de otro modulo",
     {"hondo.t": 'fn doble(n: usize) -> usize { return n * 2; }',
      "medio.t": 'usar "hondo.t"; fn cuatro(n: usize) -> usize { return doble(doble(n)); }',
      "app.t": 'usar "medio.t"; fn main() { let doble = fn(n: usize) -> usize { return n + n; };'
               ' imprimir($"{doble(cuatro(1))}\\n"); }'},
     "app.t", None, "8\n"),

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

    # `x.t` y `lib/x.t` se llaman igual: su prefijo interno lleva la
    # carpeta, y no acaban siendo la misma funcion en C.
    ("dos modulos con el mismo nombre de archivo en carpetas distintas",
     {"x.t": 'fn f() -> usize { return 1; }',
      "lib/x.t": 'fn f() -> usize { return 2; }',
      "a.t": 'usar "x.t";\nusar "lib/x.t" como otra;\n'
               'fn main() { imprimir($"{f()} {otra.f()}\\n"); }'},
     "a.t", None, "1 2\n"),

    ("sin alias, el mismo nombre de archivo en dos carpetas choca y lo dice",
     {"x.t": 'fn f() -> usize { return 1; }',
      "lib/x.t": 'fn f() -> usize { return 2; }',
      "a.t": 'usar "x.t";\nusar "lib/x.t";\nfn main() { imprimir(f()); }'},
     "a.t", "llega de dos sitios", None),

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


def compilar_y_correr(fuente, tmp, con_sanitizers=True):
    """Devuelve (codigo_de_salida, stdout, stderr) o lanza AssertionError."""
    return correr_c(c_de(fuente, tmp), tmp, con_sanitizers)


def en_paralelo(funcion, trabajos):
    """`funcion` sobre cada trabajo, en tantos hilos como nucleos: lo que
    cuesta es el compilador de C y el programa, que son otros procesos. Los
    resultados salen en el orden de los trabajos."""
    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 2) as hilos:
        return list(hilos.map(funcion, trabajos))


def c_de(fuente, tmp):
    """El C de un programa, o AssertionError si no compila."""
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
    return codigo


def correr_c(codigo, tmp, con_sanitizers=True):
    """Compila el C en `tmp` y lo corre: (codigo_de_salida, stdout, stderr),
    o AssertionError si el C no compila."""
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


if seccion("RECHAZO", "programas que no deben compilar"):
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

if seccion("AVISA", "compilan igual, pero el compilador tiene algo que decir"):
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

if seccion("ACEPTA", "compilan, corren limpio bajo ASan+UBSan"):
    with tempfile.TemporaryDirectory() as tmp:
        # El C de cada caso sale en orden; compilarlo con los sanitizers y
        # correrlo, que es lo que cuesta, va en paralelo.
        trabajos = []
        for i, (nombre, fuente, salida) in enumerate(ACEPTA):
            total += 1
            suyo = os.path.join(tmp, str(i))
            os.mkdir(suyo)
            try:
                trabajos.append((nombre, salida, c_de(fuente, suyo), suyo))
            except AssertionError as exc:
                falla(nombre, str(exc))

        def _correr_caso(trabajo):
            try:
                return correr_c(trabajo[2], trabajo[3])
            except AssertionError as exc:
                return str(exc)

        for (nombre, salida, _, _), hecho in zip(trabajos,
                                                 en_paralelo(_correr_caso, trabajos)):
            if isinstance(hecho, str):
                falla(nombre, hecho)
                continue
            rc, out, err = hecho
            if rc != 0:
                falla(nombre, f"salio con codigo {rc}\n{err}")
            elif out != salida:
                falla(nombre, f"salida {out!r}, se esperaba {salida!r}")
            elif "runtime error" in err or "AddressSanitizer" in err:
                falla(nombre, f"sanitizer se quejo:\n{err}")

if seccion("SALIDA", "el compilador nunca reemplaza sus fuentes"):
    with tempfile.TemporaryDirectory() as tmp:
        fuente = os.path.join(tmp, "programa.t")
        contenido = 'fn main() { imprimir("intacto"); }\n'
        with open(fuente, "w", encoding="utf-8") as f:
            f.write(contenido)

        total += 1
        r = subprocess.run(
            [sys.executable, "-m", "tcode", fuente, "-o", fuente],
            cwd=RAIZ, capture_output=True, text=True)
        with open(fuente, encoding="utf-8") as f:
            despues = f.read()
        if r.returncode == 0:
            falla("-o no puede ser el fuente", "el compilador acepto la colision")
        elif despues != contenido:
            falla("-o no puede ser el fuente", "el archivo fuente fue modificado")
        elif "propio archivo fuente" not in r.stderr:
            falla("-o no puede ser el fuente", f"diagnostico inesperado: {r.stderr!r}")

        total += 1
        sin_extension = os.path.join(tmp, "programa")
        with open(sin_extension, "w", encoding="utf-8") as f:
            f.write(contenido)
        r = subprocess.run(
            [sys.executable, "-m", "tcode", sin_extension],
            cwd=RAIZ, capture_output=True, text=True)
        with open(sin_extension, encoding="utf-8") as f:
            despues = f.read()
        if r.returncode == 0 or despues != contenido:
            falla("la salida implicita no pisa un fuente sin extension",
                  f"codigo {r.returncode}, contenido {despues!r}")
        elif "propio archivo fuente" not in r.stderr:
            falla("la salida implicita no pisa un fuente sin extension",
                  f"diagnostico inesperado: {r.stderr!r}")

        total += 1
        binario_previo = os.path.join(tmp, "programa-anterior")
        marca_previa = b"binario anterior intacto\n"
        with open(binario_previo, "wb") as f:
            f.write(marca_previa)
        r = subprocess.run(
            [sys.executable, "-m", "tcode", fuente, "--cc", "/bin/false",
             "-o", binario_previo],
            cwd=RAIZ, capture_output=True, text=True)
        with open(binario_previo, "rb") as f:
            despues = f.read()
        if r.returncode == 0:
            falla("un fallo de C conserva el binario anterior",
                  "el compilador C falso se considero exitoso")
        elif despues != marca_previa:
            falla("un fallo de C conserva el binario anterior",
                  f"el destino cambio a {despues!r}")

        # Formatear un enlace escribe en lo que apunta: reemplazarlo lo convertia
        # en un archivo suelto y dejaba el original sin tocar.
        total += 1
        real = os.path.join(tmp, "real.t")
        enlace = os.path.join(tmp, "enlace.t")
        with open(real, "w", encoding="utf-8") as f:
            f.write('fn main() {\nimprimir("a");\n}\n')
        os.symlink(real, enlace)
        r = subprocess.run(
            [sys.executable, "-m", "tcode", enlace, "--formatear", "--escribir"],
            cwd=RAIZ, capture_output=True, text=True)
        with open(real, encoding="utf-8") as f:
            formateado = f.read()
        if r.returncode != 0 or not os.path.islink(enlace):
            falla("formatear un enlace conserva el enlace",
                  f"codigo {r.returncode}, enlace {os.path.islink(enlace)}")
        elif '    imprimir("a");' not in formateado:
            falla("formatear un enlace conserva el enlace",
                  f"el original no se formateo: {formateado!r}")

        # Un binario nuevo respeta el `umask`, como lo haria `cc -o`.
        total += 1
        nuevo_bin = os.path.join(tmp, "con-umask")
        r = subprocess.run(
            ["sh", "-c", 'umask 027 && exec "$@"', "sh", sys.executable, "-m",
             "tcode", fuente, "-o", nuevo_bin],
            cwd=RAIZ, capture_output=True, text=True)
        modo = os.stat(nuevo_bin).st_mode & 0o777 if os.path.exists(nuevo_bin) else None
        if r.returncode != 0 or modo != 0o750:
            falla("un binario nuevo respeta el umask",
                  f"codigo {r.returncode}, modo {oct(modo) if modo else None}, "
                  f"stderr {r.stderr[:300]!r}")

if seccion("ARCHIVOS", "lectura real, incluida entrada binaria"):
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

        # La ruta se calcula antes que los datos. Si C invirtiera los argumentos,
        # `datos` veria 1 y `ruta` intentaria escribir en un lugar inexistente.
        total += 1
        orden = os.path.join(tmp, "orden.bin")
        ruta_o = orden.replace("\\", "\\\\").replace('"', '\\"')
        fuente = f'''fn ruta(n: mut usize) -> view {{
        n = n + 1;
        if n == 1 {{ return "{ruta_o}"; }}
        return "/no/existe/orden.bin";
    }}
    fn datos(n: mut usize) -> view {{
        n = n + 1;
        if n == 2 {{ return "bien"; }}
        return "mal";
    }}
    fn main() -> usize ! {{
        var n: usize = 0;
        try escribir_archivo(ruta(n), datos(n));
        let vuelta = try leer_archivo("{ruta_o}");
        imprimir(vuelta); imprimir(" "); imprimir(n); imprimir("\\n");
        return 0;
    }}'''
        try:
            rc, out, err = compilar_y_correr(fuente, tmp)
        except AssertionError as exc:
            falla("escribir_archivo evalua ruta antes que datos", str(exc))
        else:
            if rc != 0 or out != "bien 2\n":
                falla("escribir_archivo evalua ruta antes que datos",
                      f"codigo {rc}, salida {out!r}, stderr {err!r}")
            elif "runtime error" in err or "AddressSanitizer" in err:
                falla("escribir_archivo evalua ruta antes que datos",
                      f"sanitizer se quejo:\n{err}")

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
if seccion("AUTOANALISIS", "el lexer y el parser en Tcode, contra los de Python"):
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
                cifra("lexer_archivos", distintos)
                cifra("tokens", tokens_vistos)

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
                        cifra("parser_archivos", coinciden)
                        cifra("nodos", nodos_vistos)

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

if seccion("TIPOS", "la capa de tipos del comprobador, en Tcode"):
    # La tercera capa del compilador escrita en Tcode, despues del lexer y el
    # parser. Se le pregunta lo mismo que al comprobador de Python sobre cada
    # tipo que aparece en el repositorio, y tiene que contestar igual.
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
                cifra("tipos_archivos", comparados)
                cifra("tipos", tipos_vistos)
                print(f"    {comparados} archivos, {tipos_vistos} tipos, "
                      f"mismas respuestas que el comprobador de Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if seccion("TIPAR", "de que tipo es cada variable, dicho por Tcode"):
    # Cuarta capa del compilador escrita en su propio lenguaje, despues del
    # lexer, el parser y la capa de tipos. Se le pregunta el tipo de cada
    # variable de cada funcion del repositorio, y tiene que decir lo mismo que
    # el comprobador de Python.




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
            # Las variables y los tipos, como estan escritos: la capa en Tcode
            # lee el arbol tal cual, sin el `ss_id_` de lo que choca con C.
            for sim in entrada["simbolos"]:
                fuera.append(f"{nombre}\t{_escrito_c(sim.nombre)}\t"
                             f"{_legible_c(sim.tipo)}")
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
                cifra("tipar_archivos", comparados)
                cifra("tipar_variables", simbolos)
                print(f"    {comparados} archivos, {simbolos} variables, "
                      f"mismos tipos que el comprobador de Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if seccion("PROPIEDAD", "que le pasa a cada valor, dicho por Tcode"):
    # Quinta capa del compilador en su propio lenguaje, y la que de verdad separa
    # a Tcode de C: quien es duenio de que memoria y donde deja de serlo. Cada
    # variable acaba en `presta`, `prestado`, `nada`, `entrega:N`, `mueve:N` o
    # `libera`, y tiene que coincidir con lo que el comprobador de Python sabe
    # decir con `--explicar`.
    #
    # No hay excepciones: todos los archivos que ambas implementaciones pueden
    # analizar deben coincidir. El conjunto queda explicito para que una futura
    # divergencia no se pueda incorporar silenciosamente como caso permitido.
    _PROPIEDAD_PENDIENTES = set()

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
                fuera.append(f"{nombre}\t{_escrito_c(sim.nombre)}\t"
                             f"{_legible_c(sim.tipo)}\t{d}")
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
                cifra("propiedad_archivos", comparados)
                cifra("propiedad_variables", variables)
                print(f"    {comparados} archivos, {variables} variables, mismo "
                      f"destino que el comprobador de Python "
                      f"({len(_PROPIEDAD_PENDIENTES)} pendientes)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if seccion("FIRMAS", "la cara en C de cada funcion, dicha por Tcode"):
    # Primera pieza del generador escrita en su propio lenguaje: como se llama
    # cada tipo en C y como queda la firma de cada funcion. Se compara con lo que
    # emite el generador de Python, cadena por cadena.

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
        # Una funcion de un bloque `externo` no lleva prototipo en el C
        # generado: su firma esta en su cabecera. No hay nada que comparar.
        escritas = [d.nombre for d in arbol
                    if isinstance(d, _Fn_t) and not d.tipo_params
                    and not d.externa]
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
                cifra("firmas_archivos", comparados)
                cifra("firmas", firmas)
                print(f"    {comparados} archivos, {firmas} firmas, mismas que el "
                      f"generador de Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if seccion("EXPRESIONES", "el C de una expresion, escrito por Tcode"):
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

    import re as _re_expr

    def _renumera_tmp(texto):
        visto, n = {}, [0]
        def cambia(m):
            k = m.group(0)
            if k not in visto:
                n[0] += 1
                visto[k] = f"ss_tmp{n[0]}"
            return visto[k]
        return _re_expr.sub(r"ss_tmp\d+", cambia, texto)

    def _expresiones_esperadas(ruta):
        from tcode.parser import parsear as _p
        from tcode import nombres_c as _nc
        try:
            arbol = _p(open(ruta, encoding="utf-8").read(), ruta, set())
        except Exception:
            return None
        # Con los nombres que chocan con C cambiados, como los deja el cargador
        # y como los lee la capa en Tcode.
        _nc.renombrar(arbol, _nc.externas(arbol) | {"main"})
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

    _MINIMO_CUBIERTAS = 700

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
                        # Los numeros de temporal se renumeran por orden de
                        # aparicion, como en CUERPOS y por lo mismo: el original
                        # arrastra el contador entre las expresiones de una
                        # funcion y esta capa empieza cada una de cero. El numero
                        # dice en que orden se genero, no que C sale.
                        if _renumera_tmp(a) != _renumera_tmp(b):
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
                cifra("expresiones_iguales", cubiertas)
                cifra("expresiones", vistas)
                print(f"    {cubiertas} de {vistas} expresiones, mismo C que el "
                      f"generador de Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if seccion("CUERPOS", "la funcion entera en C, escrita por Tcode"):
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

    _MINIMO_CUERPOS = 420

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
                    # El separador va a principio de linea: el C que se compara
                    # puede llevar `@@ ` dentro de un literal —el propio
                    # `cuerpos.t` lo imprime—, y partir por cualquier aparicion
                    # cortaba la funcion por la mitad.
                    for bloque in _re_cuerpos.split(r"^@@ ", e.stdout,
                                                    flags=_re_cuerpos.M)[1:]:
                        nombre, _, cuerpo = bloque.partition("\n")
                        nombre = nombre.strip()
                        # La funcion tal como la dejo el comprobador: con los
                        # tipos deducidos puestos. Sin eso, un `var i = 0;` sin
                        # anotar no tendria tipo y el original saldria mal.
                        d = comp.funciones.get(nombre)
                        if d is None:
                            # Renombrada por el cargador. Si el mismo nombre lo
                            # declaran dos modulos, hay que quedarse con la de
                            # este archivo: la primera que aparezca puede ser la
                            # del otro, y entonces la funcion se saltaba callando.
                            candidatas = [f for k, f in comp.funciones.items()
                                          if k.endswith("__" + nombre)
                                          or k == "ss_id_" + nombre]
                            d = next((f for f in candidatas
                                      if (f.archivo or propio) == propio),
                                     candidatas[0] if candidatas else None)
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
                cifra("cuerpos", iguales)
                print(f"    {iguales} funciones enteras, mismo C que el generador "
                      f"de Python")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if seccion("PROGRAMA", "el archivo C entero, escrito por Tcode"):
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
    var p = P { nombre: nuevo("ana"), edad: 3, tags: [], dentro: Interior { texto: nuevo("hondo"), n: 1 } };
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



    # Mas casos de modulos que los de MODULOS: ciclos de tres, modulos que no
    # estan de varias formas, un nombre propio contra uno traido, y lo que se usa
    # sin pedirlo. `tcodec` tiene que decir lo mismo que el cargador de Python.
    M = 'fn main() { imprimir("x"); }'
    _MODULOS_EXTRA_TCODEC = [
     ("ciclo de tres", {"a.t": 'usar "b.t";\n'+M, "b.t": 'usar "c.t";\nfn b() {}', "c.t": 'usar "a.t";\nfn c() {}'}, "a.t"),
     ("falta sin .t", {"a.t": 'usar "fantasma";\n'+M}, "a.t"),
     ("falta de std", {"a.t": 'usar "std/fantasma";\n'+M}, "a.t"),
     ("falta dentro de otro", {"a.t": 'usar "lib/b.t";\n'+M, "lib/b.t": '\n\nusar "nada.t";\nfn b() {}'}, "a.t"),
     ("propio contra traido", {"x.t": 'fn dos() -> usize { return 2; }', "app.t": 'usar "x.t";\nfn dos() -> usize { return 3; }\n'+M}, "app.t"),
     ("con alias no choca", {"x.t": 'fn dos() -> usize { return 2; }', "y.t": 'fn dos() -> usize { return 22; }', "app.t": 'usar "x.t";\nusar "y.t" como y;\nfn main() { imprimir(dos() + y.dos()); }'}, "app.t"),
     ("sin pedir una funcion", {"c.t": 'fn tres() -> usize { return 3; }', "b.t": 'usar "c.t";\nfn b() -> usize { return tres(); }', "app.t": 'usar "b.t";\nfn main() {\n    imprimir(b());\n    imprimir(tres());\n}'}, "app.t"),
     ("sin pedir un struct", {"c.t": 'struct Caja { n: usize }', "b.t": 'usar "c.t";\nfn b() -> usize { let k = Caja { n: 1 }; return k.n; }', "app.t": 'usar "b.t";\nfn main() {\n    let k = Caja { n: 2 };\n    imprimir(k.n);\n}'}, "app.t"),
     ("sin pedir un enum", {"c.t": 'enum Color { Rojo, Verde }', "b.t": 'usar "c.t";\nfn b() -> usize { let k = Color.Rojo; return 1; }', "app.t": 'usar "b.t";\nfn main() {\n    let k = Color.Verde;\n    imprimir(b());\n}'}, "app.t"),
     ("local con nombre de fuera", {"c.t": 'fn tres() -> usize { return 3; }', "b.t": 'usar "c.t";\nfn b() -> usize { return tres(); }', "app.t": 'usar "b.t";\nfn main() {\n    let f = fn(x: usize) -> usize { return x; };\n    imprimir(b());\n}'}, "app.t"),
     ("dos usar del mismo", {"x.t": 'fn uno() -> usize { return 1; }', "app.t": 'usar "x.t";\nusar "x.t" como otra;\nfn main() { imprimir(uno() + otra.uno()); }'}, "app.t"),
     ("rombo con choque", {"x.t": 'fn f() -> usize { return 1; }', "lib/x.t": 'fn f() -> usize { return 2; }', "app.t": 'usar "x.t";\nusar "lib/x.t";\nfn main() { imprimir(f()); }'}, "app.t"),
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
    # Lo que `tcodec` necesita del sistema, en C, junto a el.
    _SISTEMA_TCODEC = os.path.join("ejemplos", "compilador", "lib", "sistema_tcodec.c")
    # Rechazos cuyo primer error dice `tcodec` igual que Python: todos, tambien
    # los de sintaxis, que dan el lexer y el parser escritos en Tcode.
    _MINIMO_RECHAZOS = 157
    # Mutaciones por archivo para comparar los errores de sintaxis: se rompe un
    # token de cada archivo del repositorio de varias formas, siempre las mismas.
    _MUTACIONES_POR_ARCHIVO = 5

    tmp = tempfile.mkdtemp(prefix="tcode-programa-")
    _cwd_antes = os.getcwd()
    try:
        os.chdir(RAIZ)
        total += 1
        codigo, errores = compilar_archivo(
            os.path.join("ejemplos", "compilador", "tcodec.t"))
        if errores:
            falla("tcodec en Tcode", "\n".join(errores))
        else:
            ruta_c = os.path.join(tmp, "tcodec.c")
            binario = os.path.join(tmp, "tcodec")
            with open(ruta_c, "w", encoding="utf-8") as f:
                f.write(codigo)
            r = subprocess.run(
                ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
                 _SISTEMA_TCODEC,
                 "-o", binario, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                falla("tcodec en Tcode compila", r.stderr[:600])
            else:
                # Desde la raiz y con la raiz relativa: `tcodec` todavia no sabe
                # preguntar por el directorio de trabajo, y los `#line` son
                # relativos a el.
                entorno = dict(os.environ, TCODE_RAIZ=".")

                total += 1
                literal_invalido = os.path.join(tmp, "literal-invalido.t")
                with open(literal_invalido, "w", encoding="utf-8") as f:
                    f.write('fn main() { let x: u8 = 256; imprimir(x); }\n')
                e = subprocess.run([binario, literal_invalido, "--mostrar-c"], capture_output=True,
                                   text=True, timeout=60, env=entorno)
                if e.returncode == 0 or e.stdout:
                    falla("tcodec rechaza literales enteros fuera de rango",
                          f"codigo {e.returncode}, genero {len(e.stdout)} bytes")

                total += 1
                decimal_invalido = os.path.join(tmp, "decimal-invalido.t")
                with open(decimal_invalido, "w", encoding="utf-8") as f:
                    f.write('fn main() { let x: f64 = 1e309; imprimir(x); }\n')
                e = subprocess.run([binario, decimal_invalido, "--mostrar-c"], capture_output=True,
                                   text=True, timeout=60, env=entorno)
                if e.returncode == 0 or e.stdout:
                    falla("tcodec rechaza literales decimales infinitos",
                          f"codigo {e.returncode}, genero {len(e.stdout)} bytes")

                total += 1
                inexacto = os.path.join(tmp, "entero-inexacto.t")
                with open(inexacto, "w", encoding="utf-8") as f:
                    f.write('fn main() { let x: f64 = 9007199254740993; '
                            'imprimir(x); }\n')
                e = subprocess.run([binario, inexacto, "--mostrar-c"], capture_output=True,
                                   text=True, timeout=60, env=entorno)
                if e.returncode == 0 or e.stdout:
                    falla("tcodec rechaza enteros que un decimal redondearia",
                          f"codigo {e.returncode}, genero {len(e.stdout)} bytes")

                total += 1
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
                    falla("tcodec conserva los limites enteros validos",
                          f"errores {errores_literal}, codigo {e.returncode}, "
                          f"stderr {e.stderr[:300]!r}")

                # Clausuras con y sin capturas, una dentro de otra, guardadas en
                # una variable, pasadas a una generica, y punteros a funcion,
                # tambien uno que recibe otro. Nada de eso lo pide un programa del
                # repositorio salvo lo de `pruebas.t`.
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
                                           ("entregado.t", _STR_ENTREGADO_TCODEC)):
                    total += 1
                    ruta_cierre = os.path.join(tmp, nombre_c)
                    with open(ruta_cierre, "w", encoding="utf-8") as f:
                        f.write(fuente_c)
                    esperado_c, errores_c = compilar_archivo(ruta_cierre)
                    e = subprocess.run([binario, ruta_cierre, "--mostrar-c"], capture_output=True,
                                       text=True, timeout=60, env=entorno)
                    if errores_c or e.returncode != 0 or e.stdout != esperado_c:
                        falla(f"tcodec escribe {nombre_c}",
                              f"errores {errores_c}, codigo {e.returncode}, "
                              f"stderr {e.stderr[:300]!r}")

                # El comprobador en Tcode: lo que Python rechaza, tcodec tambien, y
                # con el mismo primer error; lo que Python acepta, tcodec no lo
                # rechaza nunca por una regla del lenguaje.
                def _errores_tcodec(ruta):
                    r = subprocess.run([binario, ruta, "--solo-comprobar"],
                                       capture_output=True, text=True, timeout=120,
                                       env=entorno)
                    bloques = []
                    for linea in r.stderr.splitlines():
                        if linea.startswith("error: "):
                            bloques.append(linea[len("error: "):])
                        elif linea.startswith("  ") and bloques:
                            bloques[-1] += "\n" + linea
                    return r.returncode, bloques, r.stderr

                def _errores_python(ruta):
                    try:
                        _, errs = compilar_archivo(ruta)
                    except Exception as exc:
                        return [str(exc)]
                    return errs or []

                mismos = rechazados = 0
                for i, (nombre, fuente, _esperado) in enumerate(RECHAZO):
                    ruta_r = os.path.join(tmp, f"rechazo-{i}.t")
                    with open(ruta_r, "w", encoding="utf-8") as f:
                        f.write(fuente)
                    de_python = _errores_python(ruta_r)
                    if not de_python:
                        continue
                    rechazados += 1
                    total += 1
                    rc, de_tcodec, crudo = _errores_tcodec(ruta_r)
                    if rc == 0:
                        falla("el comprobador en Tcode rechaza lo que Python rechaza",
                              f"{nombre}: tcodec lo acepto; Python dice "
                              f"{de_python[0][:200]!r}")
                    elif de_tcodec and de_tcodec[0] == de_python[0]:
                        mismos += 1
                total += 1
                if mismos < _MINIMO_RECHAZOS:
                    falla("el comprobador en Tcode da los mismos errores",
                          f"solo {mismos} de {rechazados} con el mismo primer "
                          f"error; se esperaban al menos {_MINIMO_RECHAZOS}")

                correctos = 0
                aceptables = [(n, f) for n, f, *_ in ACEPTA]
                for archivo in sorted(glob.glob(os.path.join("std", "*.t"))
                                      + glob.glob(os.path.join("ejemplos", "**", "*.t"),
                                                  recursive=True)):
                    with open(archivo, encoding="utf-8") as f:
                        aceptables.append((archivo, f.read()))
                for i, (nombre, fuente) in enumerate(aceptables):
                    ruta_a = (nombre if os.path.exists(nombre)
                              else os.path.join(tmp, f"acepta-{i}.t"))
                    if not os.path.exists(nombre):
                        with open(ruta_a, "w", encoding="utf-8") as f:
                            f.write(fuente)
                    if _errores_python(ruta_a):
                        continue
                    correctos += 1
                    total += 1
                    rc, de_tcodec, crudo = _errores_tcodec(ruta_a)
                    if de_tcodec:
                        falla("el comprobador en Tcode no rechaza programas correctos",
                              f"{nombre}: {de_tcodec[0][:300]}")
                cifra("rechazos_iguales", mismos)
                cifra("rechazos", rechazados)
                cifra("correctos", correctos)
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
                        nueva = {
                            "borra": lambda: li[:c] + li[c + n:],
                            "dup": lambda: li[:c] + li[c:c + n] + " " + li[c:],
                            "punto": lambda: li[:c] + ";" + li[c:],
                            "paren": lambda: li[:c] + ")" + li[c:],
                            "llave": lambda: li[:c] + "{" + li[c:],
                            "arroba": lambda: li[:c] + "@" + li[c:],
                            "comilla": lambda: li[:c] + '"' + li[c:],
                            "cero": lambda: li[:c] + "0x" + li[c:],
                            "fn": lambda: li[:c] + "fn " + li[c:],
                        }[forma]()
                        otras = list(lineas)
                        otras[t.linea - 1] = nueva
                        yield f"{forma} en la linea {t.linea}", "\n".join(otras)

                iguales_s = rotos = 0
                for archivo in sorted(glob.glob(os.path.join("std", "*.t"))
                                      + glob.glob(os.path.join("ejemplos", "**", "*.t"),
                                                  recursive=True)):
                    with open(archivo, encoding="utf-8") as f:
                        fuente_o = f.read()
                    for que, fuente_m in _mutantes(fuente_o, archivo):
                        ruta_m = os.path.join(os.path.dirname(archivo),
                                              ".mut_" + os.path.basename(archivo))
                        try:
                            with open(ruta_m, "w", encoding="utf-8") as f:
                                f.write(fuente_m)
                            de_python = _errores_python(ruta_m)
                            if not de_python:
                                continue
                            rotos += 1
                            total += 1
                            rc, de_tcodec, crudo = _errores_tcodec(ruta_m)
                            if de_tcodec and de_tcodec[0] == de_python[0]:
                                iguales_s += 1
                            else:
                                falla("los errores de sintaxis en Tcode",
                                      f"{archivo}, {que}:\n"
                                      f"  Python: {de_python[0][:300]!r}\n"
                                      f"  Tcode:  {(de_tcodec[:1] or [crudo[:300]])[0]!r}")
                        finally:
                            if os.path.exists(ruta_m):
                                os.remove(ruta_m)
                cifra("rotos_iguales", iguales_s)
                cifra("rotos", rotos)
                print(f"    sintaxis: {iguales_s} de {rotos} programas rotos, mismo "
                      f"primer error que el lexer y el parser de Python")


                # Las herramientas de alrededor, contra las de Python: los errores
                # de modulos, los avisos, el formato y `--explicar`.
                def _stderr_bloques(texto, marca):
                    salida = []
                    for linea in texto.splitlines():
                        if linea.startswith(marca):
                            salida.append(linea[len(marca):])
                        elif linea.startswith("  ") and salida:
                            salida[-1] += "\n" + linea
                    return salida

                mods_iguales = mods_total = 0
                for nombre_m, archivos_m, principal_m, *_ in (
                        list(MODULOS) + [(n, a, p) for n, a, p in _MODULOS_EXTRA_TCODEC]):
                    dir_m = tempfile.mkdtemp(dir=tmp)
                    for r_m, t_m in archivos_m.items():
                        d_m = os.path.join(dir_m, r_m)
                        os.makedirs(os.path.dirname(d_m), exist_ok=True)
                        with open(d_m, "w", encoding="utf-8") as f:
                            f.write(t_m)
                    ruta_m = os.path.join(dir_m, principal_m)
                    de_python = _errores_python(ruta_m)
                    r_m = subprocess.run([binario, ruta_m, "--solo-comprobar"],
                                         capture_output=True, text=True, timeout=120,
                                         env=entorno)
                    de_tcodec = _stderr_bloques(r_m.stderr, "error: ")
                    total += 1
                    mods_total += 1
                    if (de_python[:1] == de_tcodec[:1]
                            and (r_m.returncode == 0) == (not de_python)):
                        mods_iguales += 1
                    else:
                        falla("los errores de modulos en Tcode",
                              f"{nombre_m}:\n  Python: {de_python[:1]!r}\n"
                              f"  Tcode:  {de_tcodec[:1] or r_m.stderr[:200]!r}")

                def _avisos_python(ruta):
                    try:
                        _, errs, comp_a = compilar_archivo(ruta, devolver_comp=True)
                    except Exception:
                        return None
                    return None if errs else comp_a.avisos

                aceptados_rutas = []
                for i_a, (n_a, f_a, *_ ) in enumerate(ACEPTA):
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
                for ruta_a in del_repo + aceptados_rutas:
                    esperados = _avisos_python(ruta_a)
                    if esperados is None:
                        continue
                    r_a = subprocess.run([binario, ruta_a, "--solo-comprobar"],
                                         capture_output=True, text=True, timeout=120,
                                         env=entorno)
                    total += 1
                    dados_a = _stderr_bloques(r_a.stderr, "aviso: ")
                    av_cuantos += len(esperados)
                    if dados_a == esperados:
                        av_iguales += 1
                    else:
                        falla("los avisos en Tcode",
                              f"{ruta_a}:\n  Python: {esperados[:3]!r}\n"
                              f"  Tcode:  {dados_a[:3]!r}")
                    total += 1
                    py_e = subprocess.run([sys.executable, "-m", "tcode", ruta_a,
                                           "--explicar", "--sin-avisos"],
                                          capture_output=True, text=True, timeout=120)
                    tc_e = subprocess.run([binario, ruta_a, "--explicar", "--sin-avisos"],
                                          capture_output=True, text=True, timeout=120,
                                          env=entorno)
                    if py_e.stdout == tc_e.stdout:
                        ex_iguales += 1
                    else:
                        a_e, b_e = py_e.stdout.splitlines(), tc_e.stdout.splitlines()
                        d_e = next((i for i, (x, y) in enumerate(zip(a_e, b_e)) if x != y),
                                   min(len(a_e), len(b_e)))
                        falla("--explicar en Tcode",
                              f"{ruta_a}, linea {d_e + 1}:\n"
                              f"  Python: {a_e[d_e] if d_e < len(a_e) else '(fin)'!r}\n"
                              f"  Tcode:  {b_e[d_e] if d_e < len(b_e) else '(fin)'!r}")

                from tcode.formato import formatear as _formatear
                fm_iguales = fm_total = 0
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
                        ruta_f = os.path.join(tmp, f"formato-{k_f}.t")
                        with open(ruta_f, "w", encoding="utf-8") as f:
                            f.write(fuente_f)
                        esperado_f = _formatear(fuente_f, ruta_f)
                        r_f = subprocess.run([binario, ruta_f, "--formatear"],
                                             capture_output=True, text=True, timeout=120,
                                             env=entorno)
                        total += 1
                        fm_total += 1
                        if r_f.returncode == 0 and r_f.stdout == esperado_f:
                            fm_iguales += 1
                        else:
                            falla("--formatear en Tcode",
                                  f"{archivo_f} ({'deformado' if k_f else 'tal cual'})")
                print(f"    herramientas: {mods_iguales} de {mods_total} casos de "
                      f"modulos, avisos iguales en {av_iguales} programas "
                      f"({av_cuantos} avisos), --explicar igual en {ex_iguales}, "
                      f"--formatear igual en {fm_iguales} de {fm_total}")

                iguales = intentados = 0
                for archivo in sorted(
                        glob.glob(os.path.join("std", "*.t"))
                        + glob.glob(os.path.join("ejemplos", "**", "*.t"),
                                    recursive=True)):
                    with open(archivo, encoding="utf-8") as f:
                        if "fn main(" not in f.read():
                            continue
                    esperado, errores_f = compilar_archivo(archivo)
                    if errores_f:
                        continue
                    e = subprocess.run([binario, archivo, "--mostrar-c"], capture_output=True,
                                       text=True, timeout=180, env=entorno)
                    if "Sanitizer" in e.stderr:
                        total += 1
                        falla("tcodec en Tcode", f"{archivo}: sanitizer\n"
                                                f"{e.stderr[:400]}")
                        continue
                    intentados += 1
                    total += 1
                    if e.returncode != 0:
                        # Lo que Python compila, `tcodec` lo escribe entero.
                        falla("tcodec en Tcode",
                              f"{archivo}: lo rechazo\n{e.stderr[:400]}")
                    elif e.stdout != esperado:
                        dado, bueno = e.stdout.splitlines(), esperado.splitlines()
                        n = next((i for i, (x, y) in enumerate(zip(dado, bueno))
                                  if x != y), min(len(dado), len(bueno)))
                        falla("tcodec en Tcode",
                              f"{archivo}, linea {n + 1}:\n"
                              f"  Tcode:  {dado[n] if n < len(dado) else '(fin)'!r}\n"
                              f"  Python: {bueno[n] if n < len(bueno) else '(fin)'!r}")
                    else:
                        iguales += 1
                if iguales < _MINIMO_PROGRAMAS:
                    total += 1
                    falla("tcodec en Tcode",
                          f"solo {iguales} programas enteros, se esperaban al "
                          f"menos {_MINIMO_PROGRAMAS}")
                cifra("programas_enteros", iguales)
                print(f"    {iguales} programas enteros, mismo C que el generador "
                      f"de Python ({intentados} intentados)")

                # Y cada programa de la suite que Python compila: los que
                # corren, los que abortan y los que avisan. Son los que cubren
                # el lenguaje construccion a construccion, asi que aqui se ve
                # si a `tcodec` le falta alguna.
                trabajos_s = []
                for lista_s, casos_s in (("ACEPTA", ACEPTA), ("ABORTA", ABORTA),
                                         ("AVISA", AVISA)):
                    for i_s, caso_s in enumerate(casos_s):
                        dir_s = os.path.join(tmp, f"suite_{lista_s}_{i_s}")
                        os.makedirs(dir_s)
                        ruta_s = os.path.join(dir_s, "p.t")
                        with open(ruta_s, "w", encoding="utf-8") as f:
                            f.write(caso_s[1])
                        esperado_s, errores_s = compilar_archivo(ruta_s)
                        if not errores_s:
                            trabajos_s.append((caso_s[0], ruta_s, esperado_s))

                def _tcodec_escribe(trabajo):
                    return subprocess.run([binario, trabajo[1], "--mostrar-c"],
                                          capture_output=True, text=True,
                                          timeout=180, env=entorno)

                iguales_s = 0
                for (nombre_s, ruta_s, esperado_s), e in zip(
                        trabajos_s, en_paralelo(_tcodec_escribe, trabajos_s)):
                    total += 1
                    if e.returncode != 0:
                        falla("tcodec escribe los programas de la suite",
                              f"{nombre_s}: lo rechazo\n{e.stderr[-400:]}")
                    elif e.stdout != esperado_s:
                        dado, bueno = e.stdout.splitlines(), esperado_s.splitlines()
                        n = next((i for i, (x, y) in enumerate(zip(dado, bueno))
                                  if x != y), min(len(dado), len(bueno)))
                        falla("tcodec escribe los programas de la suite",
                              f"{nombre_s}, linea {n + 1}:\n"
                              f"  Tcode:  {dado[n] if n < len(dado) else '(fin)'!r}\n"
                              f"  Python: {bueno[n] if n < len(bueno) else '(fin)'!r}")
                    else:
                        iguales_s += 1
                cifra("programas_suite", iguales_s)
                print(f"    {iguales_s} de {len(trabajos_s)} programas de la suite, "
                      f"mismo C que el generador de Python")

                # `tcodec` tambien hace el ultimo paso: llama al compilador de C,
                # enlaza lo que piden los `externo`, y deja el binario.
                total += 1
                bin_hola = os.path.join(tmp, "hola")
                e = subprocess.run([binario, os.path.join("ejemplos", "hola.t"),
                                    "-o", bin_hola], capture_output=True, text=True,
                                   timeout=180, env=entorno)
                r_h = (subprocess.run([bin_hola], capture_output=True, text=True,
                                      timeout=60) if e.returncode == 0 else None)
                if e.returncode != 0 or r_h is None or r_h.stdout != "Hola, mundo!\n12 bytes\n":
                    falla("tcodec compila y enlaza un programa",
                          f"codigo {e.returncode}, stderr {e.stderr[:300]!r}")

                total += 1
                bin_reloj = os.path.join(tmp, "reloj")
                e = subprocess.run([binario, os.path.join("ejemplos", "externo", "reloj.t"),
                                    "-o", bin_reloj], capture_output=True, text=True,
                                   timeout=180, env=entorno)
                r_r = (subprocess.run([bin_reloj], capture_output=True, text=True,
                                      timeout=60) if e.returncode == 0 else None)
                if e.returncode != 0 or r_r is None or r_r.returncode != 0:
                    falla("tcodec enlaza el `.c` de un `externo`",
                          f"codigo {e.returncode}, stderr {e.stderr[:300]!r}")

                # La salida nunca es el fuente ni un `.t`, y un fallo del
                # compilador de C deja el binario anterior como estaba.
                total += 1
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
                    falla("tcodec protege el fuente y el binario anterior",
                          f"{e1s.stderr[:200]!r} {e2s.stderr[:200]!r} {e3s.stderr[:200]!r}")

                # El punto fijo. El `tcodec` que compilo Python escribe su propio
                # C; ese C, compilado, tiene que volver a escribir exactamente el
                # mismo. Es la prueba de que el compilador ya no depende de
                # Python para existir: a partir de aqui se puede construir desde
                # su propio C, como hacen Go desde 1.5 y Rust desde su primer
                # `rustc` en Rust.
                total += 1
                propio = os.path.join("ejemplos", "compilador", "tcodec.t")
                e1 = subprocess.run([binario, propio, "--mostrar-c"], capture_output=True,
                                    text=True, timeout=600, env=entorno)
                if e1.returncode != 0 or "Sanitizer" in e1.stderr:
                    falla("punto fijo", f"tcodec no se escribe a si mismo:\n"
                                        f"{e1.stderr[:400]}")
                else:
                    ruta_c2 = os.path.join(tmp, "etapa2.c")
                    binario2 = os.path.join(tmp, "etapa2")
                    with open(ruta_c2, "w", encoding="utf-8") as f:
                        f.write(e1.stdout)
                    r2 = subprocess.run(
                        ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra",
                         "-Werror", "-fsanitize=address,undefined",
                         "-fno-omit-frame-pointer", f"-I{RUNTIME}", ruta_c2,
                         os.path.join(RUNTIME, "safestr.c"), _SISTEMA_TCODEC,
                         "-o", binario2,
                         "-lm"],
                        capture_output=True, text=True)
                    if r2.returncode != 0:
                        falla("punto fijo", f"su propio C no compila:\n"
                                            f"{r2.stderr[:600]}")
                    else:
                        e2 = subprocess.run([binario2, propio, "--mostrar-c"],
                                            capture_output=True, text=True,
                                            timeout=600, env=entorno)
                        if (e2.returncode != 0 or "Sanitizer" in e2.stderr
                                or e2.stdout != e1.stdout):
                            falla("punto fijo", "la etapa 2 no reproduce el C "
                                                f"de la etapa 1\n{e2.stderr[:400]}")
                        else:
                            print(f"    punto fijo: tcodec compilado desde su "
                                  f"propio C lo reproduce byte a byte "
                                  f"({len(e1.stdout.encode())} bytes)")
                            cifra("punto_fijo_bytes", len(e1.stdout.encode()))
                            # Y sin nadie mas: `tcodec` se construye a si mismo,
                            # llamando el al compilador de C, y ese binario
                            # vuelve a escribir el mismo C.
                            total += 1
                            binario3 = os.path.join(tmp, "etapa3")
                            e3 = subprocess.run([binario, propio, "-o", binario3],
                                                capture_output=True, text=True,
                                                timeout=900, env=entorno)
                            e4 = (subprocess.run([binario3, propio, "--mostrar-c"],
                                                 capture_output=True, text=True,
                                                 timeout=600, env=entorno)
                                  if e3.returncode == 0 else None)
                            if e4 is None or e4.returncode != 0 or e4.stdout != e1.stdout:
                                falla("tcodec se construye a si mismo",
                                      f"{e3.stderr[:400]}")
                            else:
                                print("    tcodec se construye a si mismo sin "
                                      "Python, y reproduce su C")
    finally:
        os.chdir(_cwd_antes)
        shutil.rmtree(tmp, ignore_errors=True)

if seccion("FORMATO", "un estilo, y el repositorio ya lo tiene"):

    # Un unario va pegado a su parentesis: `!(a)`, no `! (a)`.
    total += 1
    _con_unario = _formatear_1 = None
    from tcode.formato import formatear as _formatear_1
    _con_unario = _formatear_1("fn main() {\nlet a = true;\nif !(a) { imprimir(-(1)); }\n}\n")
    if "!(a)" not in _con_unario or "-(1)" not in _con_unario:
        falla("un unario va pegado a su parentesis", repr(_con_unario))

    # Un aviso sobre una clausura dice `clausura`, tambien pasada la decima:
    # los nombres se cambian enteros, y `Cierre_1` no es un trozo de `Cierre_10`.
    total += 1
    _once = "fn main() {\n" + "".join(
        f"    let f{i} = fn(x: usize) -> usize {{ return x; }};\n    imprimir(f{i}(1));\n"
        for i in range(10)) + "    let g = fn(x: usize, sobra: usize) -> usize { return x; };\n" \
        "    imprimir(g(1, 2));\n}\n"
    with tempfile.TemporaryDirectory() as _tmp_av:
        _ruta_av = os.path.join(_tmp_av, "once.t")
        with open(_ruta_av, "w", encoding="utf-8") as f:
            f.write(_once)
        _, _errs_av, _comp_av = compilar_archivo(_ruta_av, devolver_comp=True)
        if _errs_av or not any("de `clausura` no se usa" in a for a in _comp_av.avisos):
            falla("un aviso sobre una clausura dice `clausura`",
                  f"{_errs_av} {_comp_av.avisos if _comp_av else None}")
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
    cifra("formato_archivos", len(_TODOS))
    print(f"    {len(_TODOS)} archivos: mismos tokens, idempotente, y ya "
          f"en formato canonico")

if seccion("LINEAS", "el C generado apunta al `.t`, no a si mismo"):
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
                # Algunos contenedores instalan gdb pero bloquean ptrace. Eso no
                # dice nada sobre las directivas `#line`: se deja constancia y se
                # conserva la comprobacion real donde el depurador puede arrancar.
                sin_ptrace = ("ptrace: Operation not permitted" in e.stderr
                              or "Could not trace the inferior process" in e.stderr)
                if sin_ptrace:
                    print("    (gdb instalado, pero el entorno bloquea ptrace)")
                elif f"hondo.t:3" not in e.stdout:
                    falla("el depurador ve el `.t`",
                          "la pila no señala `hondo.t:3`:\n"
                          + (e.stdout + e.stderr)[-600:])
        print(f"    {marcadas} directivas, todas a una linea que existe")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if seccion("ABORTA", "la aritmetica comprobada detiene el programa"):
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

        # `abort()` no vacia `stdout`: con la salida en una tuberia, como aqui, lo
        # ya impreso se perdia. El runtime la vacia antes de cada aborto.
        for nombre, cuerpo in (
                ("desbordamiento", "let x: u8 = 255; let y = x + 1; imprimir(y);"),
                ("indice", "let xs = [1, 2]; let i: usize = 5; imprimir(xs[i]);"),
                ("division", "let c: usize = 0; imprimir(7 / c);")):
            total += 1
            fuente = 'fn main() { imprimir("antes\\n"); ' + cuerpo + ' }'
            try:
                rc, out, err = compilar_y_correr(fuente, tmp, con_sanitizers=False)
            except AssertionError as exc:
                falla(f"lo impreso antes de abortar ({nombre})", str(exc))
                continue
            if rc == 0 or out != "antes\n":
                falla(f"lo impreso antes de abortar ({nombre})",
                      f"codigo {rc}, salida {out!r}")

    # ---------------------------------------------------------------- modulos
if seccion("MODULOS", "varios archivos, un solo programa"):
    import shutil
    from tcode.modulos import cargar, ErrorDeModulo
    from tcode.cli import _compilar


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

if seccion("EJEMPLOS", "los de ejemplos/ compilan y corren limpios"):
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
        trabajos = []
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
            trabajos.append((relativo, args, base))

        def _correr_ejemplo(trabajo):
            _, args, base = trabajo
            r = subprocess.run(
                ["cc", "-std=c17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 f"-I{RUNTIME}", base + ".c", os.path.join(RUNTIME, "safestr.c"),
                 "-o", base, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                return r.stderr[:600]
            e = subprocess.run([base] + [os.path.join(RAIZ, a) for a in args],
                               capture_output=True, text=True, timeout=180,
                               cwd=RAIZ)
            if e.returncode != 0 or e.stderr.strip():
                return f"codigo {e.returncode}\n{e.stderr[:600]}"
            return None

        for (relativo, _, _), problema in zip(trabajos,
                                              en_paralelo(_correr_ejemplo, trabajos)):
            if problema:
                falla(f"ejemplo {relativo}", problema)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

print(f"\n{total} casos, {fallos} fallas")
if TODAS:
    cifra("casos", total)
    sys.path.insert(0, os.path.join(RAIZ, "tests"))
    from cifras import guardar as _guardar_cifras
    _guardar_cifras("lenguaje", CIFRAS)
sys.exit(1 if fallos else 0)
