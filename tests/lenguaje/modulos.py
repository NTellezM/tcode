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
    ("un `use` en rombo carga el modulo una sola vez",
     {"lib/base.t": 'fn doble(n: usize) -> usize { return n * 2; }',
      "lib/medio.t": 'use "base.t";\n'
                       'fn cuadruple(n: usize) -> usize { return doble(doble(n)); }',
      "app.t": 'use "lib/medio.t";\nuse "lib/base.t";\n'
                 'fn main() -> usize { imprimir(cuadruple(3)); imprimir("\\n");'
                 ' imprimir(doble(5)); imprimir("\\n"); return 0; }'},
     "app.t", None, "12\n10\n"),

    # La directiva de la biblioteca: `#importar "texto.t"` es
    # `use "std/texto"`, sin escribir la carpeta. Sin alias, con alias, dos a
    # la vez, y los `use` de siempre —el de `std/` y el relativo— al lado.
    ("`#importar \"x.t\"` trae de la biblioteca del compilador",
     {"lib/cuenta.t": 'fn dos() -> usize { return 2; }',
      "app.t": '#importar "texto.t";\n'
                 '#importar "utf8.t" como U;\n'
                 'use "lib/cuenta.t";\n'
                 'use "std/lista";\n'
                 'fn main() -> usize {\n'
                 '    var xs: list<usize> = [];\n'
                 '    anadir(xs, dos());\n'
                 '    anadir(xs, dos());\n'
                 '    imprimir($"{contiene("hola", "ol")} {U.cuantos("camión")}'
                 ' {suma(xs)} {xs[0]}\\n");\n'
                 '    return 0;\n'
                 '}'},
     "app.t", None, "true 6 4 2\n"),

    ("dependencia circular",
     {"a.t": 'use "b.t";\nfn a() {}',
      "b.t": 'use "a.t";\nfn b() {}'},
     "a.t", "dependencia circular", None),

    # Un modulo que se usa no puede tener `main`. `tcodec` lo rechazaba sin
    # archivo ni linea, y Python lo aceptaba sin decir nada si el que lo
    # usaba no tenia su propio `main`. Lo encontro `tests/fuzz.py`.
    ("un modulo con `main`",
     {"lib/m.t": 'fn main() { imprimir("m"); }',
      "a.t": 'use "lib/m.t";\nfn main() -> usize { return 0; }'},
     "a.t", "a.t:1: `lib/m.t` tiene `fn main`", None),

    ("un modulo con `main`, y quien lo usa sin el suyo",
     {"m.t": 'fn main() { imprimir("m"); }',
      "a.t": 'use "m.t" como m;\nfn f() -> usize { return 0; }'},
     "a.t", "a.t:1: `m.t` tiene `fn main`", None),

    # La ruta llega a funciones de C: con un cero en medio, Python se
    # escapaba con un `ValueError` y `tcodec` abortaba. Lo encontro
    # `tests/fuzz.py`.
    ("la ruta de un modulo con un byte cero",
     {"a.t": 'use "a\0b.t";\nfn main() -> usize { return 0; }'},
     "a.t", "a.t:1: la ruta de un modulo no puede llevar un byte cero", None),

    # `lib/m.t/` no es un archivo. Python lo aceptaba —`realpath` quita la
    # barra— y tcodec lo cargaba, pero no casaba el alias y no sabia
    # escribir las llamadas. Lo encontro `tests/fuzz.py`.
    ("la ruta de un modulo con `/` al final",
     {"lib/m.t": 'fn doble(n: usize) -> usize { return n * 2; }',
      "a.t": 'use "lib/m.t/" como m;\nfn main() -> usize { return m.doble(0); }'},
     "a.t", "a.t:1: `lib/m.t/` termina en `/`", None),

    # La funcion de otro modulo, llamada desde donde una variable se llama
    # igual: en C la variable la tapaba.
    ("una variable con el nombre de una funcion de otro modulo",
     {"m.t": 'fn cuadro(x: usize) -> usize { return x + 1; }',
      "a.t": 'use "m.t" como M;\nuse "m.t";\n'
             'fn main() -> usize { let cuadro = 41; imprimir(M.cuadro(cuadro));'
             ' imprimir(cuadro(cuadro)); return 0; }'},
     "a.t", None, "4242"),

    # Un struct con un campo `Q.Tipo` de otro modulo que posee: tcodec no
    # veia el prefijo y no lo liberaba. Lo encontro ASan en el Tamagotchi.
    ("un campo de otro modulo que posee se libera",
     {"q.t": 'struct Hoja { nombres: list<str> }\n'
             'enum Talvez { No, Si(str) }',
      "m.t": 'use "q.t" como Q;\n'
             'struct Lamina { hoja: Q.Hoja, marca: Q.Talvez, id: i64 }\n'
             'fn hacer() -> Lamina { var h = Q.Hoja { nombres: [] };'
             ' anadir(h.nombres, nuevo("a")); return Lamina { hoja: h,'
             ' marca: Q.Talvez.Si(nuevo("b")), id: 7 }; }',
      "a.t": 'use "m.t" como M;\n'
             'fn main() -> usize { let l = M.hacer(); imprimir(l.id); return 0; }'},
     "a.t", None, "7"),

    # `T.partes(x)` es la funcion de `T` aunque haya un local `partes`.
    ("una funcion de otro modulo con el nombre de un local",
     {"m.t": 'fn partes(t: view) -> list<str> { return [nuevo(t), nuevo("b")]; }',
      "a.t": 'use "m.t" como T;\n'
             'fn junta(x: view) -> usize { var partes: list<str> = [];'
             ' let de_x = T.partes(x); for p en de_x { anadir(partes, copiar(p)); }'
             ' return largo(partes); }\n'
             'fn main() -> usize { imprimir(junta("a")); return 0; }'},
     "a.t", None, "2"),

    ("modulo que no existe",
     {"a.t": 'use "fantasma.t";\nfn main() -> usize { return 0; }'},
     "a.t", "no encuentro el modulo", None),

    ("el mismo nombre desde dos sitios, y como arreglarlo",
     {"x.t": 'fn dos() -> usize { return 2; }',
      "a.t": 'use "x.t";\nfn dos() -> usize { return 3; }\n'
               'fn main() -> usize { return dos(); }'},
     "a.t", "llega de dos sitios", None),

    ("lo que usa un modulo usado no se ve sin pedirlo",
     {"hondo.t": 'fn doble(n: usize) -> usize { return n * 2; }',
      "medio.t": 'use "hondo.t"; fn cuatro(n: usize) -> usize { return doble(doble(n)); }',
      "app.t": 'use "medio.t"; fn main() { imprimir($"{doble(cuatro(1))}\\n"); }'},
     "app.t", "que este archivo no usa", None),

    ("una variable local con el nombre de una funcion de otro modulo",
     {"hondo.t": 'fn doble(n: usize) -> usize { return n * 2; }',
      "medio.t": 'use "hondo.t"; fn cuatro(n: usize) -> usize { return doble(doble(n)); }',
      "app.t": 'use "medio.t"; fn main() { let doble = fn(n: usize) -> usize { return n + n; };'
               ' imprimir($"{doble(cuatro(1))}\\n"); }'},
     "app.t", None, "8\n"),

    ("dos modulos con el mismo nombre no se estorban si no se cruzan",
     {"uno.t": 'fn contar(xs: &list<str>) -> usize { return largo(xs); }',
      "dos.t": 'fn contar(xs: &list<usize>) -> usize { return largo(xs) * 2; }',
      "a.t": 'use "uno.t";\nuse "dos.t" como d;\n'
               'fn main() -> usize {\n'
               '    var ss: list<str> = []; anadir(ss, nuevo("a"));\n'
               '    var ns: list<usize> = []; anadir(ns, 1); anadir(ns, 2);\n'
               '    imprimir($"{contar(ss)} {d.contar(ns)}\\n");\n'
               '    return 0;\n}'},
     "a.t", None, "1 4\n"),

    # `x.t` y `lib/x.t` se llaman igual: su prefijo interno lleva la
    # carpeta, y no acaban siendo la misma funcion en C.
    ("dos modulos con el mismo nombre de archivo en carpetas distintas",
     {"x.t": 'fn f() -> usize { return 1; }',
      "lib/x.t": 'fn f() -> usize { return 2; }',
      "a.t": 'use "x.t";\nuse "lib/x.t" como otra;\n'
               'fn main() { imprimir($"{f()} {otra.f()}\\n"); }'},
     "a.t", None, "1 2\n"),

    ("sin alias, el mismo nombre de archivo en dos carpetas choca y lo dice",
     {"x.t": 'fn f() -> usize { return 1; }',
      "lib/x.t": 'fn f() -> usize { return 2; }',
      "a.t": 'use "x.t";\nuse "lib/x.t";\nfn main() { imprimir(f()); }'},
     "a.t", "llega de dos sitios", None),

    ("un struct que llega con nombre de modulo",
     {"tipos.t": 'struct Caja { n: usize }\n'
                   'fn hacer(n: usize) -> Caja { return Caja { n: n }; }',
      "a.t": 'use "tipos.t" como t;\n'
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
      "a.t": 'use "tipos.t" como t;\n'
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
      "a.t": 'use "roto.t";\nfn main() -> usize { return 0; }'},
     "a.t", "roto.t:1", None),

    # Los nombres de struct y enum son globales entre modulos: el choque tiene
    # que decir los dos sitios, que si no hay que buscarlos a mano. Antes solo
    # decia «no admite un struct repetido entre modulos», sin decir cuales.
    ("dos modulos con el mismo struct dicen los dos sitios",
     {"partes.t": 'struct Partes { n: usize }',
      "a.t": 'use "partes.t";\n'
             'struct Partes { m: i64 }\n'
             'fn main() -> usize { return 0; }'},
     "a.t", "a.t:2: el struct `Partes` ya esta definido en partes.t:1", None),

    ("dos modulos con el mismo enum dicen los dos sitios",
     {"color.t": 'enum Color { Rojo }',
      "a.t": 'use "color.t";\n'
             'enum Color { Azul }\n'
             'fn main() -> usize { return 0; }'},
     "a.t", "a.t:2: el enum `Color` ya esta definido en color.t:1", None),

    ("dos modulos con el mismo struct generico dicen los dos sitios",
     {"caja.t": 'struct Caja<T> { v: T }',
      "a.t": 'use "caja.t";\n'
             'struct Caja<T> { w: T }\n'
             'fn main() -> usize { return 0; }'},
     "a.t", "a.t:2: el struct generico `Caja` ya esta definido en caja.t:1", None),

    # Dos genericas con el mismo nombre que no se ven entre si (cada modulo
    # trae la otra con alias): el choque tambien las nombra a las dos.
    ("dos modulos con la misma generica dicen los dos sitios",
     {"base.t": 'fn id<T>(x: T) -> T { return x; }',
      "mid.t": 'use "base.t" como B;\nfn id<T>(x: T) -> T { return x; }',
      "a.t": 'use "mid.t";\nuse "base.t" como B;\n'
             'fn main() -> usize { return 0; }'},
     "a.t", "`id` esta en base.t:1 y mid.t:2", None),
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
