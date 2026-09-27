"""AVISA: compilan igual, pero el compilador tiene algo que decir."""

import tempfile

from .comun import (
    Resultado,
    bloques,
    tcodec_sobre,
)

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


TITULO = "compilan igual, pero el compilador tiene algo que decir"


def correr(suite: Resultado) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        for nombre, fuente, esperado in AVISA:
            suite.total += 1
            r = tcodec_sobre(fuente, "--mostrar-c", directorio=tmp)
            avisos = bloques(r.stderr, "aviso: ")
            if r.returncode != 0:
                suite.falla(nombre, f"no deberia dar errores: "
                              f"{bloques(r.stderr, 'error: ') or r.stderr[-300:]}")
                continue
            if not r.stdout:
                suite.falla(nombre, "un aviso no puede impedir que se genere codigo")
                continue
            if esperado is None:
                if avisos:
                    suite.falla(nombre, f"no deberia avisar nada, aviso: {avisos}")
            elif not any(esperado in a for a in avisos):
                suite.falla(nombre, f"se esperaba {esperado!r}, hubo: {avisos}")
