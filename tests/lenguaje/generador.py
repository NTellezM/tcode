"""GENERADOR: la valvula. El comprobador acepta lo que el generador no escribe.

Hay programas que el comprobador acepta y el generador se niega a bajar a C:
una condicion de `si` o de `mientras` que **mueve** algo. Es legal moverlo
—el comprobador lo cuenta—, pero el generador no sabe escribir esa sentencia,
y para no escupir un C que no compila prefiere parar con

    error: <archivo>:<linea>: tcodec no sabe escribir esta si de main. Es un
    fallo del compilador, no de tu programa

Esa es la valvula: `mueve_algo` (`ejemplos/compilador/lib/generar.t`) impide
que una condicion que mueve llegue a emitir C. Si alguien la afloja, un
programa que no se puede escribir se cuela hasta el C.

Ni RECHAZO ni ACEPTA vigilan esto. RECHAZO compila con `--solo-comprobar`, asi
que solo ve los errores del comprobador y aqui no hay ninguno. ACEPTA exige
que el programa corra, y este no debe correr. Por eso cada caso de la valvula
se comprueba en dos pasos:

  1. `--solo-comprobar` **acepta** el programa: el comprobador no tiene nada
     que decir;
  2. la compilacion entera **falla**, y el error es el de la valvula.

El paso 1 es lo que hace que esto no sea un caso de RECHAZO. El 2 es lo que
vigila la valvula. Un caso que no pasara el 1 no estaria probando la valvula:
estaria probando el comprobador, que es donde ya se prueba.

Los CONTROLES son las mismas formas con una condicion que **solo se lee**:
tienen que compilar y correr. Sin ellos, la seccion pasaria rechazando
cualquier cosa —el genero de comprobacion que no comprueba nada—. Y el tercero
es ademas el caso que distingue el gate **por rama** del gate por nodo entero:
`if (if c { p } else { q }).n == 1` se lee entero, pero cada rama posee su
memoria, y un gate por nodo —el que habia antes de `1c01c15`— lo rechazaba.
"""

import os
import tempfile

from .comun import (
    Resultado,
    bloques,
    c_de,
    correr_c,
    en_paralelo,
    tcodec_sobre,
)

# Un caso de la valvula: el nombre, la fuente y un trozo del mensaje del
# generador que tiene que salir. Cada uno tiene su gemelo en CONTROLES.
VALVULA = [
    # Una condicion que mueve por llamada: `usa` se queda con `p`. El
    # comprobador lo acepta —moverse es legal, y el error no es suyo—; el
    # generador no lo sabe escribir.
    ("una condicion de `si` que mueve por llamada",
     'struct P { s: str, n: usize }'
     ' fn usa(p: P) -> bool { return p.n == 1; }'
     ' fn main() { let p = P { s: nuevo("a"), n: 1 };'
     ' if usa(p) { imprimir("si"); } }',
     "tcodec no sabe escribir esta si de `main`"),

    # Lo mismo en un `mientras`: el mismo movimiento, otra sentencia.
    ("una condicion de `mientras` que mueve por llamada",
     'struct P { s: str, n: usize }'
     ' fn usa(p: P) -> bool { return p.n == 1; }'
     ' fn main() { let p = P { s: nuevo("a"), n: 1 };'
     ' while usa(p) { imprimir("si"); } }',
     "tcodec no sabe escribir esta mientras de `main`"),

    # El movimiento por el argumento, no por la condicion: lo que la llamada
    # recibe es un `if` como valor, y la rama que se toma entrega una struct
    # con duenio. El comprobador lo acepta; el generador tampoco lo escribe.
    ("mover el argumento de una llamada dentro de la condicion",
     'struct P { s: str, n: usize }'
     ' fn usa(x: P) -> bool { return x.n == 1; }'
     ' fn main() { let c = true;'
     ' let p = P { s: nuevo("a"), n: 1 };'
     ' let q = P { s: nuevo("b"), n: 2 };'
     ' if usa(if c { p } else { q }) { imprimir("si"); } }',
     "tcodec no sabe escribir esta si de `main`"),
]

# Las mismas formas, con una condicion que solo se lee: compilan y corren.
# (nombre, fuente, salida esperada).
CONTROLES = [
    # El gemelo del primer caso, sin el movimiento: el `si` lee la condicion
    # entera, y por eso `mueve_algo` no tiene nada que vetar.
    ("el `si` de la misma forma con una condicion que solo se lee",
     'struct P { s: str, n: usize }'
     ' fn main() { let c = true;'
     ' let p = P { s: nuevo("a"), n: 1 };'
     ' let q = P { s: nuevo("b"), n: 2 };'
     ' if (if c { p } else { q }).n == 1 { imprimir("uno\\n"); }'
     ' imprimir($"{p.s} {q.s}\\n"); }',
     "uno\na b\n"),

    # Y su `mientras`.
    ("el `mientras` de la misma forma con una condicion que solo se lee",
     'struct P { s: str, n: usize }'
     ' fn main() { var c = true;'
     ' let p = P { s: nuevo("a"), n: 1 };'
     ' let q = P { s: nuevo("b"), n: 2 };'
     ' var vueltas: usize = 0;'
     ' while (if c { p } else { q }).n == 1 {'
     ' c = false; vueltas = vueltas + 1; }'
     ' imprimir($"{vueltas} {p.s} {q.s}\\n"); }',
     "1 a b\n"),

    # El caso mixto: una rama se lee (`p`) y la otra evalua una llamada que
    # mueve **su argumento** (`toma` se queda con `r`). El comprobador graba
    # la condicion entera como lectura —lo que se lee es `.n`—, `r` no se usa
    # despues, y el generador la escribe. Un gate por nodo entero rechazaria
    # tambien esto, porque la rama `toma(r)` nace sin sitio.
    ("el caso mixto: una rama se lee y la otra mueve su argumento",
     'struct P { s: str, n: usize }'
     ' struct R { n: usize }'
     ' fn toma(r: R) -> P { return P { s: nuevo("b"), n: r.n }; }'
     ' fn main() { let c = true;'
     ' let p = P { s: nuevo("a"), n: 1 };'
     ' let r = R { n: 2 };'
     ' if (if c { p } else { toma(r) }).n == 1 { imprimir("uno\\n"); } }',
     "uno\n"),
]


TITULO = "la valvula: lo que el comprobador acepta y el generador no escribe"


def correr(suite: Resultado) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        # ---------- la valvula ----------
        #
        # Cada caso se compila dos veces, en su directorio y como `p.t`: una
        # con `--solo-comprobar` —que tiene que aceptarlo— y otra entera, que
        # tiene que fallar. Las dos pasadas van en paralelo.
        def un_caso(i_caso):
            i, (_, fuente, _) = i_caso
            suyo = os.path.join(tmp, f"v{i}")
            os.mkdir(suyo)
            return (tcodec_sobre(fuente, "--solo-comprobar", directorio=suyo),
                    tcodec_sobre(fuente, directorio=suyo))

        hechos = en_paralelo(un_caso, list(enumerate(VALVULA)))
        for (nombre, _, esperado), (revisado, entero) in zip(VALVULA, hechos):
            suite.total += 1
            if revisado.returncode != 0:
                suite.falla(nombre, "`--solo-comprobar` rechaza el programa, "
                                    "asi que esto no es la valvula sino un "
                                    "rechazo normal: "
                            + (bloques(revisado.stderr, "error: ")
                               or [revisado.stderr])[-1])
                continue
            errores = bloques(entero.stderr, "error: ")
            if entero.returncode == 0:
                suite.falla(nombre, "compilo entero: la valvula se aflojo, un "
                                    "programa que el generador no sabe "
                                    "escribir llego al C")
            elif not any(esperado in e for e in errores):
                suite.falla(nombre, f"se esperaba {esperado!r}, se obtuvo: "
                              f"{errores or entero.stderr[-300:]}")

        # ---------- los controles ----------
        #
        # El C sale, se compila con los sanitizers y corre con su salida.
        trabajos = []
        for i, (nombre, fuente, salida) in enumerate(CONTROLES):
            suite.total += 1
            suyo = os.path.join(tmp, f"c{i}")
            os.mkdir(suyo)
            try:
                trabajos.append((nombre, salida, c_de(fuente, suyo), suyo))
            except AssertionError as exc:
                suite.falla(nombre, str(exc))

        def un_control(trabajo):
            nombre, salida, codigo, suyo = trabajo
            try:
                return nombre, salida, correr_c(codigo, suyo)
            except AssertionError as exc:
                return nombre, salida, str(exc)

        for nombre, salida, res in en_paralelo(un_control, trabajos):
            if isinstance(res, str):
                suite.falla(nombre, res)
                continue
            rc, out, err = res
            if rc != 0:
                suite.falla(nombre, f"salio con codigo {rc}\n{err}")
            elif out != salida:
                suite.falla(nombre, f"salida {out!r}, se esperaba {salida!r}")
            elif "runtime error" in err or "AddressSanitizer" in err:
                suite.falla(nombre, f"sanitizer se quejo:\n{err}")
