"""ACEPTA: compilan, corren limpio bajo ASan+UBSan."""

import os
import tempfile

from .comun import (
    Resultado,
    c_de,
    correr_c,
    en_paralelo,
)

ACEPTA = [
    ("literales hexadecimales",
     '''fn main() {
            let a: usize = $FF;
            let b: usize = $1a2b;
            let c: u8 = $0;
            let d: u8 = $ff;
            imprimir($"{a} {b} {c} {d}\\n");
        }''',
     "255 6699 0 255\n"),
    # Prestar un sitio: un elemento, un campo o una variable se leen o se
    # modifican por un `&T`/`&mut T` sin copiarlos. Antes habia que
    # `copiar(...)` el elemento entero.
    ("prestar un elemento, un campo o una variable",
     '''struct H { t: str }
        struct N { s: str, hijo: H, hijos: list<N> }
        fn nuevo_n(t: view) -> N { return N { s: nuevo(t), hijo: H { t: nuevo("h") }, hijos: [] }; }
        fn main() {
            var l: list<N> = [];
            anadir(l, nuevo_n("hola"));
            anadir(l, nuevo_n("adios!"));
            let x: &N = l[1];
            let h: &H = x.hijo;
            imprimir($"{largo(x.s)} {largo(h.t)}\\n");
            var p = nuevo_n("abc");
            let w: &mut N = p;
            empujar(w.s, "d");
            let q: &mut N = l[0];
            empujar(q.s, "!");
            var a: [N; 2] = [nuevo_n("x"), nuevo_n("yz")];
            let e: &N = a[1];
            imprimir($"{largo(p.s)} {largo(l[0].s)} {largo(e.s)}\\n");
            anadir(l, nuevo_n("despues"));
            imprimir($"{largo(l)}\\n");
        }''',
     "6 1\n4 5 2\n3\n"),

    # Un local que se llama como una funcion y no se puede llamar: la llamada
    # es a la funcion, tambien cuando su resultado se guarda y hay que saber
    # su tipo. `tcodec` tomaba el tipo del local y no sabia escribir el `let`.
    ("un local que no se llama no tapa a la funcion de su nombre",
     '''fn partes(t: view) -> list<str> { return [nuevo(t), nuevo("b")]; }
        fn junta(x: view) -> usize {
            var partes: list<str> = [];
            let de_x = partes(x);
            for p en de_x { anadir(partes, copiar(p)); }
            return largo(partes);
        }
        fn main() { imprimir($"{junta("a")}\\n"); }''',
     "2\n"),

    # Un prestamo que ya se tiene —lo que da `obtener` u `obtener_mut`, lo
    # que atrapa un `match`— se pasa a una funcion que presta, tal cual. Los
    # dos compiladores lo rechazaban: comparaban `&N` con el `N` del
    # parametro. Lo encontro la seccion FORMAS.
    ("un prestamo que ya se tiene se pasa a una funcion que presta",
     '''struct N { s: str }
        enum E { Nada, Con(N) }
        fn ver(x: &N) -> usize { return largo(x.s); }
        fn cambiar(x: mut N) { empujar(x.s, "!"); }
        fn mirar(e: &E) -> usize { return match e { E.Nada -> 0, E.Con(y) -> ver(y) }; }
        fn main() -> usize ! {
            var m: map<str, N> = [];
            poner(m, "a", N { s: nuevo("hola") });
            let w = try obtener_mut(m, "a");
            cambiar(w);
            let r = try obtener(m, "a");
            let e = E.Con(N { s: nuevo("abc") });
            imprimir($"{ver(r)} {mirar(e)}\\n");
            return 0;
        }''',
     "5 3\n"),

    # Un struct cuyo unico campo con duenio es un enum. tcodec no lo
    # liberaba —lo tomaba por un struct sin nada que soltar— y se perdia la
    # memoria de la forma; Python si. Lo encontro ASan en la biblioteca
    # grafica del Tamagotchi.
    ("un struct con un enum que posee se libera",
     '''enum Nombre { Nadie, Alguien(str) }
        struct Ficha { quien: Nombre, n: i64 }
        struct Par { a: Ficha, b: [Nombre; 2] }
        fn main() {
            let f = Ficha { quien: Nombre.Alguien(nuevo("ana")), n: 3 };
            let p = Par { a: Ficha { quien: Nombre.Alguien(nuevo("eva")), n: 1 },
                b: [Nombre.Nadie, Nombre.Alguien(nuevo("luz"))] };
            imprimir($"{f.n} {p.a.n}\\n");
        }''',
     "3 1\n"),

    # Una variable que se llama igual que una funcion a la que se llama desde
    # ahi. En Tcode son dos cosas; en C la variable tapaba a la funcion y el C
    # no compilaba, en los dos compiladores. Ahora la funcion se renombra en
    # el C como si chocara con otro modulo. Lo encontro la biblioteca RPG del
    # Tamagotchi.
    ("una variable con el nombre de una funcion que se llama",
     '''fn cuadro(x: usize) -> usize { return x + 1; }
        fn usa(cuadro: usize) -> usize { return cuadro(cuadro) * 2; }
        fn main() {
            let cuadro = 41;
            imprimir($"{cuadro(cuadro)} {usa(1)}\\n");
        }''',
     "42 4\n"),

    # `anadir` y `ordenar` por un `&mut list<T>` de `obtener_mut`, como por
    # un parametro `&mut list<T>`. Se rechazaban diciendo que no era una
    # lista; lo encontro revisar la especificacion para 1.0.
    ("anadir y ordenar por un prestamo para modificar",
     '''fn main() -> usize ! {
            var m: map<str, list<usize>> = [];
            poner(m, "a", [3, 1]);
            let l: &mut list<usize> = try obtener_mut(m, "a");
            anadir(l, 2);
            anadir(l, 0);
            ordenar(l);
            imprimir($"{l[0]} {l[3]} {largo(l)}\\n");
            return 0;
        }''',
     "0 3 4\n"),

    # Una lista declarada dentro de un `for` o de un brazo de `match`, y
    # en ningun otro sitio. Los dos compiladores recorrian solo los `if` y
    # los `while` al registrar los tipos: Python escribia C que usaba la
    # lista sin declararla y tcodec se negaba. Lo encontro la seccion
    # REGLAS.
    ("una lista que solo aparece dentro de un for o de un match",
     '''enum C { U, D }
        fn main() {
            let k = C.U;
            match k {
                C.U -> { let xs: list<usize> = [1, 2]; imprimir(xs[1]); }
                C.D -> { }
            }
            let zs = [1, 2];
            for z en zs { let ys: list<bool> = [z == 2]; imprimir(ys[0]); }
            imprimir("\\n");
        }''',
     "2falsetrue\n"),

    # Nombres de UAX #31: letras de cualquier escritura, en structs, campos,
    # funciones y variables. El C los lleva tal cual, y gcc y clang los
    # aceptan.
    ("nombres con letras no ASCII",
     '''struct A\u00f1o { d\u00eda: usize }
        fn doble_\u03c0(x: usize) -> usize { return x * 2; }
        fn main() {
            let \u540d\u524d = A\u00f1o { d\u00eda: 3 };
            let \U0001d465 = doble_\u03c0(\u540d\u524d.d\u00eda);
            imprimir($"{\U0001d465}\\n");
        }''',
     "6\n"),

    # La lista que lleva una forma de un enum se declara aunque el programa
    # no la escriba en ningun otro sitio. Python escribia C que la usaba sin
    # declararla, y `tcodec` se negaba sin decir donde. Lo encontro
    # `tests/fuzz.py`, cortando `ejemplos/json.t`.
    ("una lista dentro de una forma de enum",
     '''enum J { Nada, Lista(list<J>), Num(usize) }
        fn cuenta(v: &J) -> usize {
            match v {
                J.Lista(xs) -> {
                    var n = 0;
                    for x en xs { n = n + cuenta(x); }
                    return n;
                }
                J.Num(k) -> { return k; }
                _ -> { return 0; }
            }
        }
        fn main() {
            let v = J.Lista([J.Num(2), J.Nada, J.Lista([J.Num(1)]), J.Num(5)]);
            imprimir($"{cuenta(v)}\\n");
        }''',
     "8\n"),

    # Asignar un sitio a si mismo no hace nada. Generado como cualquier
    # asignacion, el valor se sacaba, se soltaba lo viejo —el mismo valor—
    # y se volvia a poner ya soltado: `s = s;` con un `str`, una lista o un
    # struct era un uso despues de liberar, y `p.s = p.s;` daba C que no
    # compilaba. Sale `(void) x;`, que ademas clang no toma por un descuido
    # como `x = x;` (-Wself-assign; lo vigila `make compiladores`).
    ("asignar un sitio a si mismo",
     '''struct P { x: usize, s: str }
        fn main() {
            var u: usize = 1;
            u = u;
            var b = true;
            b = b;
            var p = P { x: 2, s: nuevo("a") };
            p.x = p.x;
            p.s = p.s;
            p = p;
            var s = nuevo("t");
            s = s;
            if largo(s) > 0 { s = s; }
            var xs: list<usize> = [3];
            xs[0] = xs[0];
            xs = xs;
            var ts: list<str> = [nuevo("z")];
            ts = ts;
            imprimir($"{u} {b} {p.x} {p.s} {s} {xs[0]} {ts[0]}\\n");
        }''',
     "1 true 2 a t 3 z\n"),

    # Sacar un campo marca ese nodo, no su linea: el destino y la lectura
    # de `p.s` que vienen detras, en la misma linea, no se sacaban tambien.
    ("sacar un campo y reponerlo en la misma linea",
     '''struct P { s: str }
        fn main() { var p = P { s: nuevo("a") }; let t = p.s; '''
     '''p.s = nuevo("b"); imprimir($"{t} {p.s}\\n"); }''',
     "a b\n"),

    # `a == b` entre textos compara lo que dicen, sea cual sea su forma: con
    # duenio, prestado o escrito. Se genera como `igual(a, b)`.
    ("== y != entre textos",
     '''struct P { nombre: str }
        fn main() {
            let s = nuevo("abc");
            let v: view = "abc";
            let p = P { nombre: nuevo("ana") };
            imprimir($"{s == "abc"} {s != "x"} {v == s} {v == "abd"} {p.nombre == "ana"}\\n");
            let a: view = "x";
            let b: view = "x";
            imprimir($"{a == b} {a != b} {s == p.nombre}\\n");
        }''',
     "true true true false true\ntrue false false\n"),

    # Lo que se entrega dentro de un brazo de `match` pide bandera igual que
    # en una rama de `if`. `tcodec` no miraba los brazos y no sabia escribir
    # la funcion.
    ("entregar dentro de un brazo de match",
     '''enum C { A, B, D }
        fn junta(r: str, xs: list<str>) -> str {
            var s = r;
            for x en xs { empujar(s, x); }
            return s;
        }
        fn f(c: C, n: usize) -> str {
            let fuera = nuevo("f");
            match c {
                C.A -> {
                    var r = nuevo("a");
                    var previos: list<str> = [];
                    anadir(previos, nuevo("x"));
                    var i = 0;
                    while i < 3 {
                        if i == n { return nuevo("corto"); }
                        i = i + 1;
                    }
                    empujar(r, fuera);
                    return junta(r, previos);
                }
                C.B -> {
                    let otro = fuera;
                    return otro;
                }
                _ -> { }
            }
            return nuevo("resto");
        }
        fn main() {
            imprimir($"{f(C.A, 1)} {f(C.A, 5)} {f(C.B, 0)} {f(C.D, 0)}\\n");
        }''',
     "corto afx f resto\n"),

    ("todos los brazos de match devuelven",
     '''enum E { A, B }
        fn valor(e: E) -> usize {
            match e {
                E.A -> { return 10; }
                E.B -> { return 20; }
            }
        }
        fn main() { imprimir($"{valor(E.A)} {valor(E.B)}\\n"); }''',
     "10 20\n"),

    ("patrones alternativos con capturas",
     '''enum E { A, B, C(usize), D(usize) }
        fn valor(e: E) -> usize {
            match e {
                E.A | E.B -> { return 1; }
                E.C(n) | E.D(n) -> { return n; }
            }
        }
        fn main() {
            imprimir($"{valor(E.A)} {valor(E.B)} {valor(E.C(3))} {valor(E.D(4))}\\n");
        }''',
     "1 1 3 4\n"),

    # `imprimir` y `{}` escriben numeros, `bool` y texto, tambien prestados.
    ("imprimir y `{}` con prestamos",
     '''fn g(a: &usize, s: &str, m: &mut i64, b: &bool, d: &f64) {
            m = m - 1;
            imprimir(a); imprimir(" "); imprimir(s); imprimir(" "); imprimir(m);
            imprimir(" "); imprimir(b); imprimir(" "); imprimir(d);
            imprimir($" [{a} {s} {m} {b} {d}]\\n");
        }
        fn main() {
            var m: i64 = 7;
            let s = texto(5);
            let d: f64 = 2.5;
            g(3, s, m, true, d);
        }''',
     "3 5 6 true 2.5 [3 5 6 true 2.5]\n"),

    # `x.f(a)` es `f(x, a)`: lo de delante del punto va primero. Vale con las
    # internas y con las funciones de cualquiera, y encadenado.
    ("la llamada con punto",
     '''struct Caja { n: usize, xs: list<usize> }
        fn doble(n: usize) -> usize { return n * 2; }
        fn suma(a: usize, b: usize) -> usize { return a + b; }
        fn main() {
            let x: usize = 3;
            var xs: list<usize> = [];
            xs.anadir(x.doble());
            xs.anadir(x.suma(4).doble());
            var s = nuevo("ab");
            s.empujar("cd");
            let k = Caja { n: 2, xs: [1, 2, 3] };
            imprimir($"{xs[0]} {xs[1]} {xs.largo()} {s} {s.largo()} ");
            imprimir($"{k.xs.largo()} {k.n.doble()}\\n");
        }''',
     "6 14 2 abcd 4 3 4\n"),

    # Donde se pide una vista, un `str` con nombre se presta solo: al
    # declarar una `view`, al asignarle, y al devolverla. Es `vista(...)`
    # sin escribirlo, con el mismo C.
    ("vistas implicitas al declarar, asignar y devolver",
     '''struct Persona { nombre: str, edad: usize }
        struct Palabra { texto: view, n: usize }
        fn nombre_de(p: &Persona) -> view { return p.nombre; }
        fn primera(xs: &list<str>) -> view { return xs[0]; }
        fn main() {
            let p = Persona { nombre: nuevo("Ana"), edad: 3 };
            var xs: list<str> = [];
            xs.anadir(nuevo("uno"));
            xs.anadir(nuevo("dos"));
            var v: view = "nada";
            if xs[0] == "uno" { v = xs[1]; }
            let w: view = p.nombre;
            var pal = Palabra { texto: "", n: 0 };
            pal.texto = xs[0];
            imprimir($"{nombre_de(p)} {primera(xs)} {v} {w} {pal.texto}\\n");
        }''',
     "Ana uno dos Ana uno\n"),

    # La vista que se presta sola a una funcion que devuelve otra vista sale
    # de lo mismo que si se hubiera escrito `vista(...)`: de un campo o un
    # elemento de lo que llego prestado, es de quien llama.
    ("una vista implicita presta de donde sale",
     '''struct Nodo { texto: str, n: usize }
        fn sin_ceros(v: view) -> view {
            var i = 0;
            while i + 1 < largo(v) && byte(v, i) == 48 { i = i + 1; }
            return rebanar(v, i, largo(v));
        }
        fn digitos(n: &Nodo) -> view { return sin_ceros(n.texto); }
        fn primero(xs: &list<str>) -> view { return sin_ceros(xs[0]); }
        fn de_param(s: &str) -> view { return sin_ceros(s); }
        fn main() {
            let n = Nodo { texto: nuevo("0042"), n: 1 };
            let d = sin_ceros(n.texto);
            var xs: list<str> = [];
            xs.anadir(nuevo("007"));
            imprimir($"{digitos(n)} {d} {primero(xs)} {de_param(n.texto)}\\n");
        }''',
     "42 42 7 42\n"),

    # Un enum sin datos se compara con `==` por su etiqueta, tambien el de un
    # campo que llego prestado.
    ("== entre enums sin datos",
     '''enum Color { Rojo, Verde, Azul }
        struct Punto { color: Color, x: usize }
        fn es_verde(p: &Punto) -> bool { return p.color == Color.Verde; }
        fn main() {
            let a = Punto { color: Color.Verde, x: 1 };
            let b = Punto { color: Color.Azul, x: 2 };
            let c = b.color;
            imprimir($"{es_verde(a)} {es_verde(b)} {c == Color.Azul} {c != b.color}\\n");
        }''',
     "true false true false\n"),

    # `for i en a..b` cuenta de `a` a `b` sin llegar. Cada extremo se calcula
    # una vez: cambiar dentro lo que dio el final no alarga el bucle. Con
    # signo, con `break` y `continue`, anidado y vacio.
    ("for sobre un rango",
     '''fn tres() -> usize { imprimir("tres "); return 3; }
        fn main() {
            var suma = 0;
            for i en 0..5 { suma = suma + i; }
            imprimir($"{suma} ");
            let n: i64 = 4;
            for j en -2..n {
                if j == 0 { continue; }
                if j == 3 { break; }
                imprimir($"{j} ");
            }
            for i en 0..tres() { imprimir($"{i} "); }
            var m = 2;
            for i en 0..m { m = m + 1; imprimir($"{i}/{m} "); }
            for k en 5..2 { imprimir("nunca"); }
            var xs: list<str> = [];
            for i en 0..3 {
                let p = $"p{i}";
                if i == 1 { continue; }
                xs.anadir(p);
            }
            for i en 1..xs.largo() { imprimir(xs[i]); }
            for a en 0..2 { for b en a..2 { imprimir($" {a}{b}"); } }
            imprimir("\\n");
        }''',
     "10 -2 -1 1 2 tres 0 1 2 0/3 1/4 p2 00 01 11\n"),

    # Lo que nace dentro de una rama —la interpolacion de un lado de un `if`
    # que da valor, la alternativa de un `sino`— se suelta dentro de ella:
    # su bloque de C se cierra antes que la sentencia. Antes se soltaba al
    # final, fuera de su bloque, y el C no compilaba.
    ("lo que nace en una rama se suelta en la rama",
     '''fn doble(v: view) -> str { return $"{v}{v}"; }
        fn junta(a: str, b: view) -> str { var s = a; empujar(s, b); return s; }
        fn main() {
            let n: usize = 3;
            let c = n > 1;
            let a = if c { $"n={n}" } else { nuevo("x") };
            let b = if c { doble($"ab{n}") } else { nuevo("y") };
            let d = variable_entorno("TCODE_NO_EXISTE") sino $"def{n}";
            let e = variable_entorno("TCODE_NO_EXISTE") sino doble($"cd{n}");
            let f = if !c { nuevo("z") } else { junta(nuevo("p"), $"q{n}") };
            imprimir($"{a} {b} {d} {e} {f}\\n");
        }''',
     "n=3 ab3ab3 def3 cd3cd3 pq3\n"),

    # Un prestamo dura hasta el ultimo uso de quien presta, no hasta el
    # final de su bloque: despues de la ultima vez que se lee `v`, `s` se
    # puede modificar, mover o devolver. Corre limpio bajo ASan.
    ("un prestamo acaba con el ultimo uso de la vista",
     '''fn g(x: str) -> usize { return largo(x); }
        fn devuelve() -> str {
            var s = nuevo("abc");
            let v = vista(s);
            imprimir(v);
            return s;
        }
        fn main() {
            var s = nuevo("hola");
            let v = vista(s);
            imprimir(v);
            empujar(s, "!");
            var t = nuevo("x");
            let w = vista(t);
            var i: usize = 0;
            while i < 2 {
                imprimir(w);
                i = i + 1;
            }
            empujar(t, "y");
            var u = nuevo("z");
            let a = vista(u);
            if largo(a) > 0 { imprimir(a); empujar(u, "w"); }
            let n = g(u);
            let d = devuelve();
            imprimir($" {s} {t} {n} {d}\\n");
        }''',
     "holaxxzabc hola! xy 2 abc\n"),

    # Dos campos distintos de un struct son memoria distinta: se pueden
    # prestar a la vez, tambien para modificarlos, y `vista(p.b)` presta solo
    # `p.b`.
    ("dos campos distintos se prestan en la misma llamada",
     '''struct Q { a: str, n: usize }
        struct P { a: str, b: str, q: Q }
        fn g(a: mut str, b: view) { empujar(a, "x"); imprimir(b); }
        fn h(a: mut str, b: mut str) { empujar(a, "1"); empujar(b, "2"); }
        fn w(a: mut usize, b: &str) { a = a + largo(b); }
        fn main() {
            var p = P { a: nuevo("a"), b: nuevo("b"), q: Q { a: nuevo("qa"), n: 1 } };
            g(p.a, vista(p.b));
            h(p.a, p.b);
            h(p.q.a, p.a);
            g(p.a, p.b);
            w(p.q.n, p.q.a);
            let f: fn(&mut str, &str) = hh;
            f(p.b, p.a);
            imprimir($" {p.a} {p.b} {p.q.a} {p.q.n}\\n");
        }
        fn hh(a: &mut str, b: &str) { empujar(a, vista(b)); }''',
     "bb2 ax12x b2ax12x qa1 4\n"),

    # Una cuenta de numeros escritos se hace al compilar: la que cabe,
    # compila. Envolver con `+?` no para nunca, y la rama de un `if` que no
    # se sabe cual sera se cuenta sola.
    ("las cuentas escritas que caben compilan",
     '''fn main() {
            let a: u8 = 200 + 55;
            let b: u8 = 250 +? 10;
            let c: i8 = (0 - 127 - 1) % (0 - 1);
            let d: i64 = (0 - 7) >> 1;
            let e: u64 = 18446744073709551615 * 1;
            let n: usize = 2;
            let f: u8 = (if n > 1 { 200 } else { 1 }) +? 100;
            imprimir($"{a} {b} {c} {d} {e} {f}\\n");
        }''',
     "255 4 0 -4 18446744073709551615 44\n"),

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
            var xs: list<str> = [];
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
            var m: map<str, usize> = [];
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
            var m: map<str, usize> = [];
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
            var m: map<str, usize> = [];
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
            var m: map<str, usize> = [];
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
            var m: map<str, usize> = [];
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
     '''use "std/par";
        struct Caja<T> { dentro: list<T> }
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
     '''use "std/vector";
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
     '''fn invertir_texto(xs: mut list<str>) {
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
            var xs: list<str> = [];
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
            var xs: list<bloque<usize>> = [];
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
            var xs: list<bloque<usize>> = [];
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
            var xs: list<bloque<usize>> = [];
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
            var bloques: list<bloque<usize>> = [];
            var b: bloque<usize> = reservar(2);
            b[1] = 7;
            anadir(bloques, b);

            var mapas: list<map<str, usize>> = [];
            var m: map<str, usize> = [];
            poner(m, "x", 9);
            anadir(mapas, m);
            imprimir($"{bloques[0][1]} {try obtener(mapas[0], "x")}\\n");
            return 0;
        }''',
     "7 9\n"),

    ("un bloque guardado en un mapa se presta para modificar",
     '''fn main() -> usize ! {
            var m: map<str, bloque<usize>> = [];
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
     '''use "std/lista";
        use "std/texto";

        fn por_largo(a: &str, b: &str) -> bool { return largo(a) < largo(b); }

        fn main() -> usize {
            var xs: list<str> = [];
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
     '''fn nombre(xs: &list<str>) -> str {
    imprimir("[se evaluo] ");
    return copiar(xs[0]);
}

fn corto(v: view) -> bool { return largo(v) < 3; }

fn main() {
    var xs: list<str> = [];
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
    var fs: list<Figura> = [];
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
struct P { nombre: str, edad: usize, tags: list<str>, dentro: Interior }

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
    var fs: list<Forma> = [];
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
        fn primera(xs: &list<str>) -> view { return vista(xs[0]); }
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
            var xs: list<str> = [];
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
     '''use "std/numero";
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
     '''fn hacer() -> list<usize> {
            var xs: list<usize> = [];
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
     '''use "std/lista";

        struct Cosa { nombre: str, n: usize }

        fn por_n(a: &Cosa, b: &Cosa) -> bool { return a.n < b.n; }
        fn al_reves(a: &usize, b: &usize) -> bool { return a > b; }
        fn doble(n: usize) -> usize { return n * 2; }

        fn aplicar(xs: &list<usize>, f: fn(usize) -> usize) -> list<usize> {
            var salida: list<usize> = [];
            for x en xs { anadir(salida, f(x)); }
            return salida;
        }

        fn main() -> usize {
            var cs: list<Cosa> = [];
            anadir(cs, Cosa { nombre: nuevo("c"), n: 9 });
            anadir(cs, Cosa { nombre: nuevo("a"), n: 2 });
            for c en ordenadas_por(cs, por_n) { imprimir($"{c.n}"); }

            var ns: list<usize> = [];
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
     '''use "std/bytes";
        fn main() -> usize {
            let crudo = "\\xde\\xad\\xbe\\xef";
            let acentos = "camión";
            let cero = "a\\x00b";
            imprimir($"{largo(crudo)} {a_hex(crudo)} {largo(acentos)}");
            imprimir($" {acentos} {largo(cero)} {a_hex(cero)}\\n");
        }''',
     "4 deadbeef 7 camión 3 610062\n"),

    ("enteros que van y vuelven de un buffer",
     '''use "std/bytes";
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

    ("UTF-8 cuenta caracteres, no bytes",
     '''use "std/utf8";
        fn main() -> usize {
            let v = "camión";
            imprimir($"{largo(v)} {cuantos(v)} {ancho(v)}\\n");
            imprimir($"[{trozo(v, 0, 3)}][{trozo(v, 4, 6)}][{trozo(v, 1, 1)}]\\n");
            imprimir($"{valido(v)} {es_inicio(195)} {es_inicio(179)}\\n");
        }''',
     "7 6 6\n[cam][ón][]\ntrue true false\n"),

    ("UTF-8: el euro y un emoji van y vuelven",
     '''use "std/bytes";
        use "std/utf8";
        fn main() -> usize ! {
            var s = vacio();
            try codificar(s, 99);
            try codificar(s, 233);
            try codificar(s, 8364);
            try codificar(s, 128512);
            imprimir($"{largo(s)} {cuantos(s)} {ancho(s)}\\n");
            imprimir($"{caracter_o(s, 0, 0)} {caracter_o(s, 1, 0)}");
            imprimir($" {caracter_o(s, 3, 0)} {caracter_o(s, 6, 0)}\\n");
            imprimir($"{a_hex(s)}\\n");
        }''',
     "10 4 5\n99 233 8364 128512\n63c3a9e282acf09f9880\n"),

    ("UTF-8: lo que ocupa cada caracter",
     '''use "std/utf8";
        fn main() -> usize {
            imprimir($"{ancho_de(97)} {ancho_de(233)} {ancho_de(8364)}\\n");
            imprimir($"{ancho_de(128512)} {ancho_de(769)} {ancho_de(44032)}\\n");
            imprimir($"[{recortar_a_ancho("camión", 4)}]");
            imprimir($" [{recortar_a_ancho("日本語", 5)}]\\n");
            imprimir($"{valido("a\\xffb")} {cuantos("a\\xffb")}\\n");
        }''',
     "1 1 1\n2 0 2\n[cami] [日本]\nfalse 3\n"),

    ("la directiva `#importar` trae de `std/` sin escribir la carpeta",
     '''#importar "utf8.t" como U;
        #importar "texto.t";
        fn main() {
            let v = "camión";
            imprimir($"{U.cuantos(v)} {U.ancho(v)} {contiene(v, "mi")}");
            imprimir($" {repetir("ab", 3)}\\n");
        }''',
     "6 6 true ababab\n"),

    ("un literal de lista se queda el valor que le dan",
     '''fn envuelve(x: str) -> list<str> {
            var v: list<str> = [x];
            return v;
        }
        fn main() -> usize {
            var l = envuelve(nuevo("hola"));
            imprimir($"{l[0]}\\n");
            return 0;
        }''',
     "hola\n"),

    ("std/difuso: la distancia de edicion cuenta caracteres, no bytes",
     '''use "std/difuso";
        use "std/prueba";
        fn main() -> usize {
            var p = pruebas();
            afirmar_igual_numero(p, "casa y caza, una letra", distancia("casa", "caza"), 1);
            afirmar_igual_numero(p, "un texto consigo mismo", distancia("igual", "igual"), 0);
            afirmar_igual_numero(p, "contra el vacio son sus caracteres", distancia("", "abc"), 3);
            afirmar_igual_numero(p, "los acentos no cuentan", distancia("camion", "camión"), 0);
            afirmar_igual_numero(p, "el parecido de casa y caza", parecido("casa", "caza"), 75);
            return terminar(p);
        }''',
     "5 comprobaciones, todo bien\n"),

    ("std/grafo: camino mas corto, orden topologico y componentes",
     '''use "std/grafo";
        use "std/prueba";
        fn main() -> usize ! {
            var p = pruebas();
            var g = nuevo_grafo();
            poner_nodo(g, "a");
            poner_nodo(g, "b");
            poner_nodo(g, "c");
            poner_nodo(g, "suelta");
            poner_arista(g, "a", "b", 1);
            poner_arista(g, "b", "c", 2);
            afirmar_igual_numero(p, "alcanzables, sin el origen", largo(alcanzables(g, "a")), 2);
            let c = try camino_mas_corto(g, "a", "c");
            afirmar_igual_numero(p, "el camino lleva tres nodos", largo(c), 3);
            afirmar(p, "y pasa por el de en medio", igual(c[1], "b"));
            afirmar_igual_numero(p, "el orden, cuatro", largo(try orden_topologico(g)), 4);
            afirmar_igual_numero(p, "hay dos componentes", largo(componentes(g)), 2);
            afirmar(p, "hay arista de a a b", hay_arista(g, "a", "b"));
            afirmar(p, "y no al reves", !hay_arista(g, "b", "a"));
            return terminar(p);
        }''',
     "7 comprobaciones, todo bien\n"),

    ("std/arbol: ordena, no duplica y sabe su forma",
     '''use "std/arbol";
        use "std/prueba";
        fn main() -> usize {
            var p = pruebas();
            var a: Arbol<usize> = Arbol { ramas: [], raiz: 0, cuantas: 0, libres: [] };
            meter_en_arbol(a, 5);
            meter_en_arbol(a, 1);
            meter_en_arbol(a, 9);
            meter_en_arbol(a, 5);
            let xs = en_orden(a);
            afirmar_igual_numero(p, "tres nodos, el repetido no entra", largo(xs), 3);
            afirmar(p, "el primero es el menor", xs[0] == 1);
            afirmar_igual_numero(p, "el del medio", xs[1], 5);
            afirmar(p, "el ultimo es el mayor", xs[2] == 9);
            afirmar_igual_numero(p, "cuantos", cuantos_en_arbol(a), 3);
            afirmar_igual_numero(p, "altura", altura_del_arbol(a), 2);
            afirmar_igual_numero(p, "minimo", minimo_del_arbol(a) sino 0, 1);
            afirmar_igual_numero(p, "maximo", maximo_del_arbol(a) sino 0, 9);
            afirmar(p, "esta el cinco", esta_en_arbol(a, 5));
            afirmar(p, "no esta el siete", !esta_en_arbol(a, 7));
            return terminar(p);
        }''',
     "10 comprobaciones, todo bien\n"),

    ("una restriccion de tipo no invalida el copiar de un campo",
     '''use "std/prueba";
        struct Caja<T> { dato: T }
        fn saca<T: ordenable>(c: &Caja<T>) -> T ! {
            return copiar(c.dato);
        }
        fn por_valor<T: ordenable>(c: Caja<T>) -> T ! {
            return copiar(c.dato);
        }
        fn main() -> usize {
            var p = pruebas();
            let c: Caja<usize> = Caja { dato: 7 };
            afirmar_igual_numero(p, "por prestamo", saca(c) sino 0, 7);
            afirmar_igual_numero(p, "por valor", por_valor(c) sino 0, 7);
            return terminar(p);
        }''',
     "2 comprobaciones, todo bien\n"),

    ("std/proceso y std/entorno: lanzar ordenes y leer el entorno",
     '''#importar "proceso.t";
        #importar "entorno.t";
        use "std/prueba";
        fn main() -> usize {
            var p = pruebas();
            afirmar_igual_numero(p, "una que va bien", (ejecutar("true") sino 0) como usize, 0);
            afirmar_igual_numero(p, "una que va mal", (ejecutar("false") sino 0) como usize, 1);
            afirmar_igual_numero(p, "y su codigo", (ejecutar("exit 7") sino 0) como usize, 7);
            afirmar(p, "va_bien lo dice", va_bien("true") sino false);
            afirmar(p, "con valor por defecto", igual(variable_o("TC_NO_ESTA", "otro"), "otro"));
            afirmar(p, "y el temporal no viene vacio", largo(directorio_temporal()) > 0);
            return terminar(p);
        }''',
     "6 comprobaciones, todo bien\n"),

    ("un contenedor propio, escrito en Tcode y no en el compilador",
     '''struct Pila<T> { cosas: list<T> }

        fn vacia<T>(p: &Pila<T>) -> bool { return largo(p.cosas) == 0; }
        fn apilar<T>(p: mut Pila<T>, x: T) { anadir(p.cosas, x); }
        fn cima<T>(p: &Pila<T>) -> T ! {
            if vacia(p) { fail "la pila esta vacia"; }
            return copiar(p.cosas[largo(p.cosas) - 1]);
        }

        // Un tipo generico que se contiene a si mismo a traves de una lista.
        struct Nodo<T> { valor: T, hijos: list<Nodo<T>> }

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
     '''use "std/par";
        fn dividir_con_resto(a: usize, b: usize) -> Par<usize, usize> ! {
            if b == 0 { fail "division por cero"; }
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
     '''use "std/lista";
        fn main() -> usize ! {
            var ns: list<usize> = [];
            anadir(ns, 3); anadir(ns, 9); anadir(ns, 5);
            var ss: list<str> = [];
            anadir(ss, nuevo("pera")); anadir(ss, nuevo("uva"));
            let buscado = nuevo("uva");
            invertir(ns);
            let vacia: list<usize> = [];
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
            var xs: list<str> = [];
            anadir(xs, nuevo("hola"));
            let copia_xs = copiar(xs);
            empujar(xs[0], "!!");

            var dentro: list<list<str>> = [];
            anadir(dentro, copiar(xs));
            let copia_dentro = copiar(dentro);
            empujar(dentro[0][0], "??");

            let c = Cosa { nombre: nuevo("a"), n: 1 };
            let c2 = copiar(c);

            var m: map<str, str> = [];
            poner(m, "k", nuevo("v"));
            let m2 = copiar(m);

            imprimir($"{xs[0]} {copia_xs[0]} {dentro[0][0]} {copia_dentro[0][0]}");
            imprimir($" {c2.nombre}{c2.n} {largo(m2)} {copiar(7)}\\n");
        }''',
     "hola!! hola hola!!?? hola!! a1 1 7\n"),

    ("una generica se copia una vez por cada juego de tipos",
     '''struct Punto { x: usize, y: usize }

        fn primero<T>(xs: &list<T>) -> T ! {
            if largo(xs) == 0 { fail "lista vacia"; }
            return xs[0];
        }

        fn cuantos<K, V>(m: &map<K, V>) -> usize { return largo(m); }

        // una generica que llama a otra generica
        fn primero_o<T>(xs: &list<T>, alterno: T) -> T {
            return primero(xs) sino alterno;
        }

        fn main() -> usize ! {
            var ns: list<usize> = [];
            anadir(ns, 7);
            var ps: list<Punto> = [];
            anadir(ps, Punto { x: 1, y: 2 });
            let p = try primero(ps);

            let vacia: list<usize> = [];
            var m: map<str, usize> = [];
            poner(m, "a", 1);

            imprimir($"{try primero(ns)} {p.y} {primero_o(vacia, 99)} {cuantos(m)}\\n");
            return 0;
        }''',
     "7 2 99 1\n"),

    ("la misma generica vale para un tipo que posee y para uno que no",
     '''use "std/lista";
        fn main() -> usize ! {
            var ns: list<usize> = [];
            anadir(ns, 3); anadir(ns, 9);
            var xs: list<str> = [];
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
     '''use "std/texto";
        fn etiqueta(v: view) -> str { return $"[{rellenar(v, 8)}]"; }
        fn marcar(v: view) -> str ! {
            if largo(v) == 0 { fail "vacio"; }
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
            var m: map<str, S> = [];
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
            if b == 0 { fail "division por cero"; }
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
            if largo(nombre) == 0 { fail "nombre vacio"; }
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
            var listas: list<list<usize>> = [];
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
            var xs: [list<usize>; 2] = [[], []];
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
            var ms: [map<str, usize>; 4] = [[], [], [], []];
            poner(ms[siguiente(n)], siguiente_clave(n), siguiente(n));
            imprimir(obtener(ms[1], "2") sino 0); imprimir("\\n");
        }''',
     "3\n"),

    ("mapa: poner, reemplazar, consultar y contar",
     '''fn main() -> usize {
            var m: map<str, usize> = [];
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
            var m: map<str, usize> = [];
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
            let ks: list<str> = claves(m);
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
            var n: list<usize> = [];
            anadir(n, 30); anadir(n, 4); anadir(n, 17); anadir(n, 4);
            ordenar(n);
            var i: usize = 0;
            while i < largo(n) { imprimir(n[i]); imprimir(" "); i = i + 1; }
            var p: list<str> = [];
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
            var m: map<str, usize> = [];
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
            var xs: list<usize> = [];
            anadir(xs, 5); anadir(xs, 12); anadir(xs, 7);
            anadir(xs, 30); anadir(xs, 1);
            for x en xs {
                if x == 7 { continue; }
                if x > 20 { break; }
                imprimir(x); imprimir(" ");
            }
            var ns: list<str> = [];
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
            var ns: list<str> = [];
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
            var m: map<str, usize> = [];
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
            var m: map<str, usize> = [];
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
            var cfg: map<str, str> = [];
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
            var tabla: map<str, Simbolo> = [];
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
            var tabla: map<str, Simbolo> = [];
            poner(tabla, "n", Simbolo { tipo: nuevo("usize"), usos: 0 });
            poner(tabla, "s", Simbolo { tipo: nuevo("str"), usos: 0 });
            var i: usize = 0;
            while i < 5 {
                let s: &mut Simbolo = try obtener_mut(tabla, "n");
                s.usos = s.usos + 1;
                empujar(s.tipo, ".");
                i = i + 1;
            }
            var claves_ord: list<str> = claves(tabla);
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
        fn cuantos(xs: &list<str>) -> usize { return largo(xs); }
        fn tres() -> list<str> {
            var xs: list<str> = [];
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
     '''use "std/texto";
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
     '''use "std/cuenta";
        use "std/texto";
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
     '''fn suma(xs: &list<usize>) -> usize {
            var total: usize = 0;
            var i: usize = 0;
            while i < largo(xs) { total = total + xs[i]; i = i + 1; }
            return total;
        }
        fn main() -> usize {
            var xs: list<usize> = [];
            var i: usize = 0;
            while i < 1000 { anadir(xs, i); i = i + 1; }
            imprimir(largo(xs)); imprimir(" "); imprimir(suma(xs));
            imprimir("\\n"); return 0;
        }''',
     "1000 499500\n"),

    ("una lista de duenios libera y mueve cada elemento",
     '''fn main() -> usize {
            var xs: list<str> = [nuevo("uno"), nuevo("dos")];
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
            if falla_ahora { fail "pedido"; }
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
     '''fn vacia() -> list<usize> { return []; }
        fn contar(xs: list<usize>) -> usize { return largo(xs); }
        fn main() -> usize {
            let xs: list<usize> = vacia();
            imprimir(largo(xs)); imprimir(" "); imprimir(contar([]));
            imprimir("\\n"); return 0;
        }''',
     "0 0\n"),

    ("listas recursivas tienen tamano finito",
     '''struct Nodo { valor: usize, hijos: list<Nodo> }
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
        fn efecto(xs: mut list<usize>) -> usize { anadir(xs, 1); return 0; }
        fn texto_de(e: &E) -> str {
            return match e { E.A -> nuevo("una cadena en el heap"), E.B -> nuevo("b") };
        }
        fn main() {
            var xs: list<usize> = [];
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
            var m: map<str, usize> = [];
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

    ("prestar un texto y usarlo como vista",
     '''fn main() {
            var xs: list<str> = [nuevo("xxxx")];
            let x: &str = xs[0];
            imprimir(byte(x, 0));
            imprimir("\\n");
        }''',
     "120\n"),

    # Una vista de una vista: prestar el sitio donde vive un `&T`. En C el
    # `const` va en el nivel del puntero (`const T* const*`), no delante del
    # tipo de dentro, que ya es `const T*` y daba `const const T**`.
    ("una vista de una vista",
     '''struct Caja { n: i64 }
        fn mira(_b: & &Caja) -> i64 { return 7; }
        fn main() {
            var c = Caja { n: 1 };
            let p: &Caja = c;
            imprimir($"{mira(p)}\\n");
        }''',
     "7\n"),

    # ---- std/cola ----
    ("std/cola: una FIFO por delante y una doble por los dos lados",
     '''use "std/cola";
        use "std/prueba";
        fn main() -> usize {
            var p = pruebas();
            var c: Cola<usize> = Cola { datos: [], cabeza: 0 };
            afirmar(p, "la cola nace vacia", cola_vacia(c));
            afirmar_igual_numero(p, "cuantos al principio", cuantos_en_cola(c), 0);

            encolar(c, 5);
            encolar(c, 1);
            encolar(c, 9);
            afirmar(p, "con tres no esta vacia", !cola_vacia(c));
            afirmar_igual_numero(p, "cuantos con tres", cuantos_en_cola(c), 3);
            afirmar_igual_numero(p, "el frente es el primero", frente(c) sino 0, 5);
            afirmar_igual_numero(p, "sale en orden 1", desencolar(c) sino 0, 5);
            afirmar_igual_numero(p, "sale en orden 2", desencolar(c) sino 0, 1);
            afirmar_igual_numero(p, "cuantos tras dos", cuantos_en_cola(c), 1);
            afirmar_igual_numero(p, "el frente ya es el otro", frente(c) sino 0, 9);

            var i = 0;
            while i < 100 {
                encolar(c, i);
                i = i + 1;
            }
            afirmar_igual_numero(p, "sale el 9 tras compactar", desencolar(c) sino 0, 9);
            afirmar_igual_numero(p, "y luego el 0", desencolar(c) sino 0, 0);

            var d: Doble<usize> = Doble { datos: [], cabeza: 0 };
            afirmar(p, "la doble nace vacia", doble_vacia(d));
            meter_detras(d, 2);
            meter_detras(d, 3);
            meter_delante(d, 1);
            afirmar_igual_numero(p, "cuantos en la doble", cuantos_en_doble(d), 3);
            afirmar_igual_numero(p, "primero de la doble", primero(d) sino 0, 1);
            afirmar_igual_numero(p, "ultimo de la doble", ultimo(d) sino 0, 3);
            afirmar_igual_numero(p, "saca por delante", sacar_delante(d) sino 0, 1);
            afirmar_igual_numero(p, "saca por detras", sacar_detras(d) sino 0, 3);
            afirmar_igual_numero(p, "queda el del medio", sacar_delante(d) sino 0, 2);
            afirmar(p, "y ya esta vacia", doble_vacia(d));
            return terminar(p);
        }''',
     "19 comprobaciones, todo bien\n"),

    # ---- std/url ----
    ("std/url: las ocho partes, el ida y vuelta y el escape",
     '''use "std/url";
        use "std/prueba";
        fn main() -> usize ! {
            var p = pruebas();
            let u = analizar("https://usuario:secreta@ejemplo.com:8443/a/b?x=1&y=2#tope");
            afirmar(p, "esquema", igual(u.esquema, "https"));
            afirmar(p, "usuario", igual(u.usuario, "usuario"));
            afirmar(p, "contrasena", igual(u.contrasena, "secreta"));
            afirmar(p, "host", igual(u.host, "ejemplo.com"));
            afirmar_igual_numero(p, "puerto", u.puerto como usize, 8443);
            afirmar(p, "ruta", igual(u.ruta, "/a/b"));
            afirmar(p, "consulta", igual(u.consulta, "x=1&y=2"));
            afirmar(p, "fragmento", igual(u.fragmento, "tope"));
            afirmar(p, "vuelve a juntarse", igual(construir(u), "https://usuario:secreta@ejemplo.com:8443/a/b?x=1&y=2#tope"));

            let s = analizar("/solo/ruta");
            afirmar(p, "sin esquema queda vacio", igual(s.esquema, ""));
            afirmar(p, "sin host queda vacio", igual(s.host, ""));
            afirmar(p, "una ruta suelta es ruta", igual(s.ruta, "/solo/ruta"));
            afirmar_igual_numero(p, "sin puerto es cero", s.puerto como usize, 0);
            afirmar(p, "mailto se rearma igual",
                igual(construir(analizar("mailto:a@b.c")), "mailto:a@b.c"));

            afirmar(p, "codifica lo que no es seguro",
                igual(codificar_componente("a b/c"), "a%20b%2Fc"));
            afirmar(p, "deja lo seguro quieto", igual(codificar_componente("Az-9._~"), "Az-9._~"));
            afirmar(p, "decodifica el componente",
                igual(try decodificar_componente("a%20b%2Fc"), "a b/c"));
            afirmar(p, "el mas es espacio en un formulario",
                igual(try decodificar_formulario("a+b"), "a b"));
            afirmar(p, "pero no en una url", igual(try decodificar_componente("a+b"), "a+b"));

            let ps = parametros("a=1&&b=2&c");
            afirmar_igual_numero(p, "dos parametros con valor y uno sin el", largo(ps), 3);
            afirmar(p, "el primero crudo", igual(ps[0].primero, "a") && igual(ps[0].segundo, "1"));
            afirmar(p, "el tercero sin igual",
                igual(ps[2].primero, "c") && igual(ps[2].segundo, ""));
            afirmar(p, "valor_de desescapa", igual(try valor_de("x=1&y=2", "y"), "2"));
            afirmar(p, "el nombre tambien se desescapa",
                igual(try valor_de("a%20b=7", "a b"), "7"));
            return terminar(p);
        }''',
     "24 comprobaciones, todo bien\n"),

    # ---- std/sha256 ----
    ("std/sha256: los vectores conocidos y el resumen por trozos",
     '''use "std/sha256";
        use "std/prueba";
        fn main() -> usize {
            var p = pruebas();
            afirmar(p, "el vacio",
                igual(resumen_hex(""),
                    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"));
            afirmar(p, "abc",
                igual(resumen_hex("abc"),
                    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
            afirmar(p, "el bloque largo",
                igual(resumen_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"));
            afirmar_igual_numero(p, "resumen son 32 bytes", largo(resumen("abc")), 32);

            var r = nuevo_resumen();
            anadir_al_resumen(r, "ab");
            anadir_al_resumen(r, "c");
            afirmar(p, "por trozos da lo mismo",
                igual(terminar_resumen_hex(r),
                    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
            afirmar_igual_numero(p, "terminar_resumen son 32 bytes",
                largo(terminar_resumen(r)), 32);

            afirmar(p, "hmac",
                igual(hmac_sha256("clave",
                        "El veloz murcielago hindu comia feliz cardillo y kiwi."),
                    "893db7db4e5e30a449671db13c265a82bf8e57a7c7da7d8054ca0adb3baf3ebf"));
            return terminar(p);
        }''',
     "7 comprobaciones, todo bien\n"),

    # ---- std/crc ----
    ("std/crc: el vector de zlib y el encadenado por trozos",
     '''use "std/crc";
        use "std/prueba";
        fn main() -> usize {
            var p = pruebas();
            afirmar_igual_numero(p, "el vector de siempre",
                crc32("123456789") como usize, 3421780262);
            afirmar_igual_numero(p, "el vacio es cero", crc32("") como usize, 0);
            afirmar_igual_numero(p, "una sola letra", crc32("a") como usize, 3904355907);

            var suma: u32 = 0;
            suma = crc32_continuar(suma, "1234");
            suma = crc32_continuar(suma, "56789");
            afirmar_igual_numero(p, "por trozos da lo mismo", suma como usize, 3421780262);

            suma = 0;
            suma = crc32_continuar(suma, "");
            suma = crc32_continuar(suma, "123456789");
            afirmar_igual_numero(p, "un trozo vacio no cambia nada", suma como usize, 3421780262);
            return terminar(p);
        }''',
     "5 comprobaciones, todo bien\n"),

    # ---- std/compresion ----
    ("std/compresion: adler32, ida y vuelta y flujos de fuera",
     '''use "std/compresion";
        use "std/bytes";
        use "std/prueba";
        fn main() -> usize ! {
            var p = pruebas();
            afirmar_igual_numero(p, "adler32 del vacio es 1", adler32("") como usize, 1);
            afirmar_igual_numero(p, "adler32 de hola", adler32("hola") como usize, 69861797);

            afirmar(p, "ida y vuelta por bloques guardados",
                igual(try inflar_zlib(deflar_guardado("hola mundo")), "hola mundo"));
            afirmar(p, "el flujo guardado es un zlib de verdad",
                igual(a_hex(deflar_guardado("hola")), "7801010400fbff686f6c61042a01a5"));

            let z_a = "\\x78\\x9c\\xcb\\xc8\\xcf\\x49\\x54\\xc8\\x18\\x25";
            let z_b = "\\x46\\x89\\x51\\x62\\x38\\x13\\x00\\x0a\\xe5\\x61\\x30";
            let z = $"{z_a}{z_b}";
            afirmar_igual_numero(p, "zlib de python mide 1000", largo(try inflar_zlib(z)), 1000);
            afirmar(p, "y empieza como el original",
                igual(rebanar(try inflar_zlib(z), 0, 10), "hola hola "));

            let d = "\\xcb\\xc8\\xcf\\x49\\x54\\xc8\\x18\\x25\\x46\\x89\\x51\\x62\\x38\\x13\\x00";
            afirmar_igual_numero(p, "deflate crudo de python", largo(try inflar_deflate(d)), 1000);

            let g_a = "\\x1f\\x8b\\x08\\x00\\x00\\x00\\x00\\x00\\x00\\x03\\xcb";
            let g_b = "\\xc8\\xcf\\x49\\x54\\xc8\\x18\\x25\\x46\\x89\\x51\\x62";
            let g_c = "\\x38\\x13\\x00\\x33\\xa2\\x50\\x64\\xe8\\x03\\x00\\x00";
            let g = $"{g_a}{g_b}{g_c}";
            afirmar_igual_numero(p, "gzip de python", largo(try inflar_gzip(g)), 1000);
            return terminar(p);
        }''',
     "8 comprobaciones, todo bien\n"),

    # ---- std/prioridad ----
    ("std/prioridad: el monticulo devuelve el minimo primero",
     '''use "std/prioridad";
        use "std/lista";
        use "std/prueba";
        fn main() -> usize {
            var p = pruebas();
            var c: Prioridad<usize> = Prioridad { datos: [] };
            afirmar(p, "nace vacia", prioridad_vacia(c));
            afirmar_igual_numero(p, "cuantos al principio", cuantos_en_prioridad(c), 0);

            meter_con_prioridad(c, 5);
            meter_con_prioridad(c, 1);
            meter_con_prioridad(c, 9);
            meter_con_prioridad(c, 3);
            afirmar(p, "con cuatro no esta vacia", !prioridad_vacia(c));
            afirmar_igual_numero(p, "cuantos con cuatro", cuantos_en_prioridad(c), 4);
            afirmar_igual_numero(p, "el mas pequeno arriba", ver_el_primero(c) sino 0, 1);
            afirmar_igual_numero(p, "y sigue estando tras mirarlo", ver_el_primero(c) sino 0, 1);
            afirmar_igual_numero(p, "sale el 1", sacar_el_primero(c) sino 0, 1);
            afirmar_igual_numero(p, "sale el 3", sacar_el_primero(c) sino 0, 3);
            afirmar_igual_numero(p, "sale el 5", sacar_el_primero(c) sino 0, 5);
            afirmar_igual_numero(p, "sale el 9", sacar_el_primero(c) sino 0, 9);
            afirmar(p, "queda vacia", prioridad_vacia(c));

            let muchos: list<usize> = [7, 2, 8, 1, 5, 3, 9, 0, 6, 4];
            for x en muchos { meter_con_prioridad(c, x); }
            afirmar_igual_numero(p, "diez dentro", cuantos_en_prioridad(c), 10);
            var orden: list<usize> = [];
            while !prioridad_vacia(c) {
                anadir(orden, sacar_el_primero(c) sino 99);
            }
            afirmar_igual_numero(p, "salen ordenados, primero", orden[0], 0);
            afirmar_igual_numero(p, "salen ordenados, ultimo", orden[9], 9);
            afirmar_igual_numero(p, "suman lo mismo", suma(orden), 45);
            return terminar(p);
        }''',
     "15 comprobaciones, todo bien\n"),

    # ---- std/regex ----
    ("std/regex: casar, buscar, capturar y reemplazar",
     '''use "std/regex" como re;
        use "std/prueba";
        fn main() -> usize ! {
            var p = pruebas();
            let digitos = try re.compilar("[0-9]+");
            afirmar(p, "el texto entero casa", re.casamenta(digitos, "123"));
            afirmar(p, "pero no si sobra algo", !re.casamenta(digitos, "12a"));
            afirmar(p, "casa en medio", re.busca(digitos, "a1b"));
            afirmar(p, "y no si no hay cifras", !re.busca(digitos, "abc"));

            let r = try re.buscar(digitos, "a12b");
            afirmar_igual_numero(p, "donde empieza", r.desde, 1);
            afirmar_igual_numero(p, "donde acaba", r.hasta, 3);
            afirmar(p, "lo pillado", igual(rebanar("a12b", r.desde, r.hasta), "12"));

            afirmar(p, "reemplaza la primera",
                igual(re.reemplazar(digitos, "a1b22c", "#"), "a#b22c"));
            afirmar(p, "reemplaza todas",
                igual(re.reemplazar_todo(digitos, "a1b22c", "#"), "a#b#c"));

            let trozos = re.partir(digitos, "a1b22c");
            afirmar_igual_numero(p, "parte en tres", largo(trozos), 3);
            afirmar(p, "trozo 0", igual(trozos[0], "a"));
            afirmar(p, "trozo 1", igual(trozos[1], "b"));
            afirmar(p, "trozo 2", igual(trozos[2], "c"));

            let con_grupos = try re.compilar("(a+)(b+)");
            let cs = try re.capturas(con_grupos, "xxaabbbzz");
            afirmar_igual_numero(p, "tres capturas, con la entera", largo(cs), 3);
            afirmar(p, "captura entera", igual(cs[0], "aabbb"));
            afirmar(p, "captura 1", igual(cs[1], "aa"));
            afirmar(p, "captura 2", igual(cs[2], "bbb"));
            afirmar(p, "los grupos se reordenan",
                igual(re.reemplazar(con_grupos, "aabbb", "$2$1"), "bbbaa"));

            let ancla = try re.compilar("^ab$");
            afirmar(p, "ancla al texto entero", re.casamenta(ancla, "ab"));
            afirmar(p, "y no a un trozo", !re.busca(ancla, "xab"));
            return terminar(p);
        }''',
     "20 comprobaciones, todo bien\n"),

    # ---- std/terminal ----
    ("std/terminal: lo que se ve no son los bytes de escape",
     '''use "std/terminal";
        use "std/color";
        use "std/prueba";
        fn main() -> usize {
            var p = pruebas();

            afirmar(p, "subir dos lineas", igual(subir(2), "\\x1b[2A"));
            afirmar(p, "a la columna 7", igual(a_columna(7), "\\x1b[7G"));
            afirmar(p, "al principio de la linea", igual(a_inicio_de_linea(), "\\x1b[G"));
            afirmar(p, "ocultar el cursor", igual(ocultar_cursor(), "\\x1b[?25l"));

            let con_color = pintar("31", "hola");
            afirmar_igual_numero(p, "los bytes son mas que las letras", largo(con_color), 13);
            afirmar_igual_numero(p, "lo que se ve son cuatro columnas",
                ancho_visible(con_color), 4);
            afirmar(p, "sin los codigos queda el texto", igual(sin_codigos(con_color), "hola"));
            afirmar_igual_numero(p, "sin codigos tampoco hay columnas de mas",
                ancho_visible("camión"), 6);

            afirmar(p, "la barra al 30%", igual(barra(3, 10, 10), "[###.......] 30%"));
            afirmar(p, "la barra llena no se pasa", igual(barra(20, 10, 4), "[####] 100%"));
            afirmar(p, "la barra a cero", igual(barra(0, 7, 3), "[...] 0%"));

            afirmar(p, "el giro 0", igual(giro(0), "|"));
            afirmar(p, "el giro 2", igual(giro(2), "-"));
            afirmar(p, "el giro da la vuelta", igual(giro(5), "/"));

            var lineas: list<str> = [];
            anadir(lineas, pintar("31", "hola"));
            anadir(lineas, nuevo("adios"));
            let caja = marco(lineas);
            afirmar_igual_numero(p, "el marco tiene cuatro filas", largo(caja), 4);
            afirmar(p, "el borde de arriba", igual(caja[0], "+-------+"));
            afirmar(p, "la fila con color se alinea por lo que se ve",
                igual(sin_codigos(caja[1]), "| hola  |"));
            afirmar(p, "la fila corta", igual(caja[2], "| adios |"));
            afirmar(p, "el borde de abajo", igual(caja[3], "+-------+"));
            afirmar_igual_numero(p, "el marco mide lo que el borde", ancho_visible(caja[1]), 9);
            return terminar(p);
        }''',
     "20 comprobaciones, todo bien\n"),

    # ---- std/utf8 ----
    ("std/utf8: los indices de cada caracter y su valor",
     '''use "std/utf8";
        use "std/prueba";
        fn main() -> usize ! {
            var p = pruebas();
            let v = "aé€";
            afirmar_igual_numero(p, "bytes del texto", largo(v), 6);
            afirmar_igual_numero(p, "caracteres del texto", cuantos(v), 3);

            let donde = indices(v);
            afirmar_igual_numero(p, "cuantos indices", largo(donde), 3);
            afirmar_igual_numero(p, "empieza en 0", donde[0], 0);
            afirmar_igual_numero(p, "la e en 1", donde[1], 1);
            afirmar_igual_numero(p, "el euro en 3", donde[2], 3);

            afirmar_igual_numero(p, "caracter 0", try caracter(v, 0) como usize, 97);
            afirmar_igual_numero(p, "caracter 1", try caracter(v, 1) como usize, 233);
            afirmar_igual_numero(p, "caracter 3", try caracter(v, 3) como usize, 8364);
            let fuera = caracter("a", 5) sino 0;
            afirmar_igual_numero(p, "fuera de rango no hay caracter", fuera como usize, 0);

            afirmar(p, "de_caracter vuelve", igual(try de_caracter(8364), "€"));
            afirmar(p, "de_caracter de un ascii", igual(try de_caracter(97), "a"));

            afirmar_igual_numero(p, "siguiente de 0", siguiente(v, 0), 1);
            afirmar_igual_numero(p, "siguiente de 1", siguiente(v, 1), 3);
            afirmar_igual_numero(p, "siguiente de 3", siguiente(v, 3), 6);
            afirmar_igual_numero(p, "sobre un byte roto avanza uno", siguiente("a\\xffb", 1), 2);
            return terminar(p);
        }''',
     "16 comprobaciones, todo bien\n"),

    # ---- std/camino ----
    #
    # `sin_extension` conserva la carpeta: `sin_extension("a/b/c.t")` es
    # `a/b/c`, no `c`. El ayudante privado que `tcodec.t` tiene con ese mismo
    # nombre ya lo hacia asi, y eso decide cual era la intencion; el modulo
    # quitaba tambien la carpeta desde que existe (`c2cba40`) y esto lo fija.
    ("std/camino: la carpeta, la extension y sin ella",
     '''use "std/camino";
        use "std/prueba";
        fn main() -> usize {
            var p = pruebas();
            let con = carpeta_o_actual("a/b/c.t");
            afirmar_igual_texto(p, "la carpeta de una ruta", con, "a/b");
            afirmar_igual_numero(p, "y mide lo que dice", largo(con), 3);
            let suelto = carpeta_o_actual("c.t");
            afirmar_igual_texto(p, "un nombre suelto esta en el actual", suelto, ".");
            afirmar_igual_numero(p, "que es un solo byte", largo(suelto), 1);

            afirmar_igual_texto(p, "la extension de una ruta", extension("a/b/c.t"), "t");
            afirmar_igual_texto(p, "sin la extension, con la carpeta",
                sin_extension("a/b/c.t"), "a/b/c");
            afirmar_igual_numero(p, "el punto, contado desde el principio",
                punto_extension("a/b/c.t"), 5);
            afirmar_igual_texto(p, "la extension del nombre suelto", extension("c.t"), "t");
            afirmar_igual_texto(p, "y el nombre sin ella", sin_extension("c.t"), "c");
            afirmar_igual_texto(p, "sin extension no se toca la ruta",
                sin_extension("a/b/c"), "a/b/c");
            afirmar_igual_texto(p, "un punto al principio no es extension",
                extension(".gitignore"), "");
            afirmar_igual_texto(p, "y ese nombre se queda entero",
                sin_extension(".gitignore"), ".gitignore");
            afirmar_igual_texto(p, "de dos extensiones manda la ultima",
                extension("a/b/c.tar.gz"), "gz");
            afirmar_igual_texto(p, "y sin ella queda la ruta y el resto",
                sin_extension("a/b/c.tar.gz"), "a/b/c.tar");
            return terminar(p);
        }''',
     "14 comprobaciones, todo bien\n"),

    # ---- std/fecha ----
    #
    # Lo que distingue al reloj monotonico de la hora de pared NO es que mida
    # bien una espera: un reloj de pared tambien avanza 100 ms mientras se
    # duerme, asi que exigir los 90 ms de abajo lo pasaria igual. Lo que lo
    # distingue es el ORIGEN de cada uno: la hora de pared cuenta desde 1970
    # —decadas— y el monotonico desde que la maquina arranco —el tiempo
    # encendido—. Leidos en el mismo instante tienen que diferir en mucho mas
    # de un anio, y con un anio de margen sobra: si `monotono_ms` cayera al
    # reloj de pared, las dos lecturas coincidirian y ESTA afirmacion falla.
    # Por eso esta es la que vale; la de la espera y la del no-retroceso se
    # quedan como lo que son, la magnitud y la monotonica en uso.
    ("std/fecha: el reloj monotonico no es la hora de pared",
     '''use "std/fecha";
        use "std/prueba";
        fn main() -> usize {
            var p = pruebas();

            // Un anio en milisegundos, que es el margen: la diferencia real
            // son decadas, y no cabe en 32 bits.
            let un_anio: i64 = 31536000000;
            let diferencia = ahora() - milisegundos_monotonico();
            afirmar(p, "el monotonico y la hora de pared difieren en mas de un anio",
                diferencia > un_anio);

            let antes = milisegundos_monotonico();
            dormir_milisegundos(100);
            let tardo = milisegundos_monotonico() - antes;
            afirmar(p, "dormir 100 ms tarda al menos 90", tardo >= 90);

            let a = milisegundos_monotonico();
            let b = milisegundos_monotonico();
            afirmar(p, "dos lecturas seguidas no retroceden", b >= a);
            return terminar(p);
        }''',
     "3 comprobaciones, todo bien\n"),

]


TITULO = "compilan, corren limpio bajo ASan+UBSan"


def correr(suite: Resultado) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        # El C de cada caso sale en orden; compilarlo con los sanitizers y
        # correrlo, que es lo que cuesta, va en paralelo.
        trabajos = []
        for i, (nombre, fuente, salida) in enumerate(ACEPTA):
            suite.total += 1
            suyo = os.path.join(tmp, str(i))
            os.mkdir(suyo)
            try:
                trabajos.append((nombre, salida, c_de(fuente, suyo), suyo))
            except AssertionError as exc:
                suite.falla(nombre, str(exc))

        def _correr_caso(trabajo):
            try:
                return correr_c(trabajo[2], trabajo[3])
            except AssertionError as exc:
                return str(exc)

        for (nombre, salida, _, _), hecho in zip(trabajos,
                                                 en_paralelo(_correr_caso, trabajos)):
            if isinstance(hecho, str):
                suite.falla(nombre, hecho)
                continue
            rc, out, err = hecho
            if rc != 0:
                suite.falla(nombre, f"salio con codigo {rc}\n{err}")
            elif out != salida:
                suite.falla(nombre, f"salida {out!r}, se esperaba {salida!r}")
            elif "runtime error" in err or "AddressSanitizer" in err:
                suite.falla(nombre, f"sanitizer se quejo:\n{err}")
