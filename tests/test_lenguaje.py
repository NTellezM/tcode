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

from tcode.cli import compilar_a_c
from tcode.lexer import ErrorLexico
from tcode.parser import ErrorSintactico

RUNTIME = os.path.join(RAIZ, "runtime")


RECHAZO = [
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

    ("un movimiento dentro de una rama no es incondicional",
     'fn tomar(s: str) {} fn f() { let s: str = nuevo("a");'
     ' if true { tomar(s); } }',
     "no se puede mover `s` dentro"),

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

    ("el valor de un mapa no puede poseer memoria",
     'fn f() { var m: mapa<str, str> = []; imprimir(largo(m)); }',
     "no puede poseer memoria"),

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
    codigo, errores = compilar_a_c(fuente, "<test>")
    assert not errores, "errores inesperados: " + "; ".join(errores)

    ruta_c = os.path.join(tmp, "p.c")
    binario = os.path.join(tmp, "p")
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(codigo)

    orden = ["cc", "-std=c17", "-g", "-Wall", "-Wextra", "-Werror",
             f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
             "-o", binario]
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

    ("el mismo nombre en dos modulos",
     {"x.t": 'fn dos() -> usize { return 2; }',
      "a.t": 'usar "x.t";\nfn dos() -> usize { return 3; }\n'
               'fn main() -> usize { return dos(); }'},
     "a.t", "ya esta definida en", None),

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
             os.path.join(RUNTIME, "safestr.c"), "-o", binario],
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

print(f"\n{total} casos, {fallos} fallas")
sys.exit(1 if fallos else 0)
