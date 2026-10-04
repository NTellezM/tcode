"""ABORTA: la aritmetica comprobada detiene el programa."""

import tempfile

from .comun import (
    Resultado,
    compilar_y_correr,
)

# Programas que compilan pero deben ABORTAR en tiempo de ejecucion.
ABORTA = [
    # Antes daba una vista vacia, un resultado equivocado que nadie veia.
    ("un indice fuera de rango en una lista detiene el programa",
     'fn main() -> usize { let xs: list<usize> = [1, 2, 3];'
     ' imprimir($"{xs[10]}"); return 0; }',
     "indice 10 fuera de rango (el arreglo tiene 3 elementos)"),

    ("un byte fuera de rango en un texto detiene el programa",
     'fn main() -> usize { let s = nuevo("aeiouind");'
     ' imprimir($"{byte(s, 12)}"); return 0; }',
     "indice 12 fuera de rango (el arreglo tiene 8 elementos)"),

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
     'use "std/texto";'
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

    # La rama escrita de un `if` es del tipo de la otra: la cuenta es de
    # `f32` y se pasa del maximo. Antes se hacia en `f64` y seguia.
    ("un if con una rama escrita no saca la cuenta de su tipo",
     'fn main() { let f: f32 = 3.4028235e38; let c = f < 1.0;'
     ' imprimir((if c { 1.5 } else { f }) * f); }',
     "`*` no dio un numero"),
]


TITULO = "la aritmetica comprobada detiene el programa"


def correr(suite: Resultado) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        for nombre, fuente, esperado in ABORTA:
            suite.total += 1
            try:
                rc, out, err = compilar_y_correr(fuente, tmp, con_sanitizers=False)
            except AssertionError as exc:
                suite.falla(nombre, str(exc))
                continue
            if rc == 0:
                suite.falla(nombre, "termino normalmente, deberia abortar")
            elif esperado not in err:
                suite.falla(nombre, f"se esperaba {esperado!r} en stderr, hubo: {err!r}")

        # `abort()` no vacia `stdout`: con la salida en una tuberia, como aqui, lo
        # ya impreso se perdia. El runtime la vacia antes de cada aborto.
        for nombre, cuerpo in (
                ("desbordamiento", "let x: u8 = 255; let y = x + 1; imprimir(y);"),
                ("indice", "let xs = [1, 2]; let i: usize = 5; imprimir(xs[i]);"),
                ("division", "let c: usize = 0; imprimir(7 / c);")):
            suite.total += 1
            fuente = 'fn main() { imprimir("antes\\n"); ' + cuerpo + ' }'
            try:
                rc, out, err = compilar_y_correr(fuente, tmp, con_sanitizers=False)
            except AssertionError as exc:
                suite.falla(f"lo impreso antes de abortar ({nombre})", str(exc))
                continue
            if rc == 0 or out != "antes\n":
                suite.falla(f"lo impreso antes de abortar ({nombre})",
                            f"codigo {rc}, salida {out!r}")
