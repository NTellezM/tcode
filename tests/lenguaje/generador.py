"""GENERADOR: la valvula. El comprobador acepta lo que el generador no escribe.

Hay programas que el comprobador acepta y el generador se niega a bajar a C:
una condicion de `si` que **mueve** algo, o una de `mientras` que lo mueve y
el cuerpo lo repone antes de cerrar la vuelta. Es legal moverlo —el
comprobador lo cuenta—, pero el generador no sabe escribir esa sentencia,
y para no escupir un C que no compila prefiere parar con

    error: <archivo>:<linea>: tcodec no sabe escribir esta si de main. Es un
    fallo del compilador, no de tu programa

Esa es la valvula: `mueve_algo` (`ejemplos/compilador/lib/generar.t`) impide
que una condicion que mueve llegue a emitir C. Si alguien la afloja, un
programa que no se puede escribir se cuela hasta el C.

En un `mientras` la condicion corre en cada vuelta, igual que el cuerpo: si
lo movido sigue movido al cerrar la vuelta, quien para es el **comprobador**
(ver RECHAZO), no la valvula. Lo que le queda a la valvula es el movimiento
que el cuerpo repone antes de cerrar: el comprobador lo da por saldado —como
el del propio cuerpo— y el generador sigue sin saber escribir la sentencia.

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

Y hay un cuarto control, el de la ultima valvula: cuando la condicion **es**
un `if` como valor y la entrega esta en una de sus ramas, esa rama la apaga el
propio emisor del valor (`si_expr_c`, con `apagar_lo_de_rama`), asi que la
sentencia si se sabe escribir. La valvula mira solo lo que corre siempre —la
condicion de ese valor—: con la entrega ahi, en cambio, no hay quien apague la
bandera y el generador sigue negandose.
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

    # Lo mismo en un `mientras`: el mismo movimiento, otra sentencia. Cuando
    # el valor movido sigue movido al cerrar la vuelta, quien rechaza es el
    # comprobador (ver el caso gemelo en RECHAZO), asi que aqui va con el
    # cuerpo reponiendolo, que es lo que le deja a la valvula.
    ("una condicion de `mientras` que mueve por llamada",
     'struct P { s: str, n: usize }'
     ' fn usa(p: P) -> bool { return p.n == 1; }'
     ' fn main() { var p = P { s: nuevo("a"), n: 1 }; var i = 0;'
     ' while usa(p) { p = P { s: nuevo("b"), n: 1 }; i = i + 1;'
     ' if i > 2 { break; } } }',
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

    # El control del caso de ACEPTA «la condicion de un `si` con una llamada
    # que mueve en una rama»: alli la entrega esta en una RAMA del `if` como
    # valor, y el emisor de ese valor (`si_expr_c`) apaga la bandera en la
    # rama que se tomo. Aqui la entrega esta en la CONDICION del valor, que
    # corre siempre y no la apaga nadie: el generador tiene que seguir
    # negandose, o el programa suelta dos veces lo que la llamada se llevo.
    ("mover la condicion del `if` que es la condicion",
     'struct P { s: str, n: usize }'
     ' fn usa(p: P) -> bool { return p.n == 1; }'
     ' fn main() { let p = P { s: nuevo("a"), n: 1 };'
     ' if if usa(p) { true } else { false } { imprimir("si"); } }',
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

    # Y su `mientras`, que es la forma que ahora rechaza el comprobador si
    # mueve: leida, tiene que seguir compilando y corriendo.
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

    # El control del ultimo caso de la valvula: la entrega esta en una rama
    # del `if` como valor que es la condicion, y el emisor de ese valor apaga
    # la bandera en la rama que se tomo. `mueve_algo` miraba las ramas y lo
    # vetaba; ahora mira solo lo que corre siempre, y este tiene que salir.
    ("la condicion de un `si` con una llamada que mueve en una rama",
     'struct P { s: str, n: usize }'
     ' fn usa(p: P) -> bool { return p.n == 1; }'
     ' fn main() { let c = true;'
     ' let p = P { s: nuevo("a"), n: 1 };'
     ' if if c { usa(p) } else { true } { imprimir("si\\n"); } }',
     "si\n"),

    # La combinacion: la condicion de un `si` es un `match` como valor y un
    # brazo entrega. Corre una sola vez, y el emisor del `match`
    # (`match_valor`) apaga la bandera en el brazo que se tomo. Es la misma
    # historia que el control de arriba, por el otro camino.
    ("la condicion de un `si` con un brazo de `match` que mueve",
     'struct P { s: str, n: usize }'
     ' enum E { A, B }'
     ' fn usa(p: P) -> bool { return p.n == 1; }'
     ' fn main() { let e = E.A;'
     ' let p = P { s: nuevo("a"), n: 1 };'
     ' if match e { E.A -> usa(p), E.B -> true } { imprimir("si\\n"); } }',
     "si\n"),
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
