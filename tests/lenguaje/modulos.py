"""MODULOS: varios archivos, un solo programa."""

import os
import shutil
import subprocess
import tempfile

from compilar_c import cc

from .comun import (
    ENTORNO_TCODEC,
    RUNTIME,
    Resultado,
    bloques,
    tcodec,
)

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

    # Un modulo que se usa no puede tener `main`. `tcodec` lo rechazaba sin
    # archivo ni linea, y Python lo aceptaba sin decir nada si el que lo
    # usaba no tenia su propio `main`. Lo encontro `tests/fuzz.py`.
    ("un modulo con `main`",
     {"lib/m.t": 'fn main() { imprimir("m"); }',
      "a.t": 'usar "lib/m.t";\nfn main() -> usize { return 0; }'},
     "a.t", "a.t:1: `lib/m.t` tiene `fn main`", None),

    ("un modulo con `main`, y quien lo usa sin el suyo",
     {"m.t": 'fn main() { imprimir("m"); }',
      "a.t": 'usar "m.t" como m;\nfn f() -> usize { return 0; }'},
     "a.t", "a.t:1: `m.t` tiene `fn main`", None),

    # La ruta llega a funciones de C: con un cero en medio, Python se
    # escapaba con un `ValueError` y `tcodec` abortaba. Lo encontro
    # `tests/fuzz.py`.
    ("la ruta de un modulo con un byte cero",
     {"a.t": 'usar "a\0b.t";\nfn main() -> usize { return 0; }'},
     "a.t", "a.t:1: la ruta de un modulo no puede llevar un byte cero", None),

    # `lib/m.t/` no es un archivo. Python lo aceptaba —`realpath` quita la
    # barra— y tcodec lo cargaba, pero no casaba el alias y no sabia
    # escribir las llamadas. Lo encontro `tests/fuzz.py`.
    ("la ruta de un modulo con `/` al final",
     {"lib/m.t": 'fn doble(n: usize) -> usize { return n * 2; }',
      "a.t": 'usar "lib/m.t/" como m;\nfn main() -> usize { return m.doble(0); }'},
     "a.t", "a.t:1: `lib/m.t/` termina en `/`", None),

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

    ("un enum que llega con nombre de modulo",
     {"tipos.t": 'enum Interior { Nada, Numero(usize) }\n'
                   'enum Exterior { Vacio, Dentro(Interior) }\n'
                   'fn hacer(n: usize) -> Exterior {'
                   ' return Exterior.Dentro(Interior.Numero(n)); }',
      "a.t": 'usar "tipos.t" como t;\n'
               'fn leer(e: &t.Exterior) -> usize { return match e {\n'
               '    t.Exterior.Vacio -> 0,\n'
               '    t.Exterior.Dentro(t.Interior.Nada) -> 1,\n'
               '    t.Exterior.Dentro(t.Interior.Numero(n)) -> n,\n'
               '    t.Exterior.Dentro(_) -> 2,\n'
               '}; }\n'
               'fn main() {\n'
               '    let a: t.Exterior = t.Exterior.Vacio;\n'
               '    let b = t.hacer(7);\n'
               '    imprimir($"{leer(a)} {leer(b)}\\n");\n'
               '}'},
     "a.t", None, "0 7\n"),

    ("un error dentro de un modulo dice de que archivo es",
     {"roto.t": 'fn r() { let a: usize = 1; let b: i64 = 2;'
                  ' let c: usize = a + b; }',
      "a.t": 'usar "roto.t";\nfn main() -> usize { return 0; }'},
     "a.t", "roto.t:1", None),
]


TITULO = "varios archivos, un solo programa"


def correr(suite: Resultado) -> None:
    for nombre, archivos, principal, error_esperado, salida in MODULOS:
        suite.total += 1
        tmp = tempfile.mkdtemp()
        try:
            for ruta, texto in archivos.items():
                destino = os.path.join(tmp, ruta)
                os.makedirs(os.path.dirname(destino), exist_ok=True)
                with open(destino, "w", encoding="utf-8") as f:
                    f.write(texto)

            r = subprocess.run([tcodec(), principal, "--mostrar-c", "--sin-avisos"],
                               cwd=tmp, env=ENTORNO_TCODEC, capture_output=True,
                               text=True, timeout=120)
            codigo = r.stdout
            errores = bloques(r.stderr, "error: ") or (
                [r.stderr.strip()] if r.returncode != 0 else [])

            if error_esperado is not None:
                if not errores:
                    suite.falla(nombre, "compilo, y no deberia")
                elif not any(error_esperado in e for e in errores):
                    suite.falla(nombre, f"se esperaba {error_esperado!r}, hubo: {errores}")
                continue

            if errores:
                suite.falla(nombre, f"errores inesperados: {errores}")
                continue

            ruta_c = os.path.join(tmp, "p.c")
            binario = os.path.join(tmp, "p")
            with open(ruta_c, "w", encoding="utf-8") as f:
                f.write(codigo)
            r = cc(
                ["cc", "-std=c17", "-g", "-fsanitize=address,undefined",
                 "-Wall", "-Wextra", "-Werror", f"-I{RUNTIME}", ruta_c,
                 os.path.join(RUNTIME, "safestr.c"), "-o", binario, "-lm"],
                capture_output=True, text=True)
            if r.returncode != 0:
                suite.falla(nombre, "el C generado no compila:\n" + r.stderr)
                continue
            e = subprocess.run([binario], capture_output=True, text=True, timeout=60)
            if e.stdout != salida:
                suite.falla(nombre, f"salida {e.stdout!r}, se esperaba {salida!r}")
            elif "AddressSanitizer" in e.stderr:
                suite.falla(nombre, f"sanitizer:\n{e.stderr}")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
