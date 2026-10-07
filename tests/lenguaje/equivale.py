"""EQUIVALE: el mismo programa en Tcode y en C dan lo mismo.

La suite ya comprueba que un programa compila y da esta salida, y que lo que
no debe compilar no compila. Ninguna de esas dos cosas dice lo que de verdad
importa cuando se **traduce** codigo de otro lenguaje a Tcode: que se comporte
igual que el original.

Aqui cada caso lleva su programa en Tcode, una **implementacion de referencia
en C escrita a mano** (`tests/lenguaje/equivale/<caso>.c`) y, si le hace falta,
la entrada que se le pasa por un tubo. El programa de Tcode se compila con
`-Wall -Wextra -Werror` y corre bajo ASan+UBSan; la referencia se compila con
las mismas banderas y **sin** los sanitizers de Tcode, porque no es el
programa que se prueba. Los dos corren con la misma entrada y se exige la
misma salida y el mismo codigo de salida.

La referencia nunca es el C que emite el compilador: si lo fuera, el caso
compararia el compilador consigo mismo y no comprobaria nada. El runner lo
vigila —el C generado lleva la marca `Generado por el compilador de Tcode`— y
falla si un `.c` de `equivale/` la trae.

Esto no inventa nada: en `bench/medir.py` ya se compila el mismo programa
escrito en C a mano y en Tcode, se corren los dos y se exige que la salida sea
identica. Lo que faltaba era traer esa idea a la suite como un genero de caso.
"""

import os
import tempfile

from .comun import (
    RAIZ,
    Resultado,
    c_de,
    correr_c,
    correr_referencia,
    en_paralelo,
)

TITULO = "el Tcode y una referencia en C independiente se comportan igual"

# Los `.c` de las referencias, uno por caso.
REFERENCIAS = os.path.join(RAIZ, "tests", "lenguaje", "equivale")

# La marca del C que emite `tcodec`: una referencia que la traiga no es una
# implementacion independiente.
MARCA_GENERADO = "Generado por el compilador de Tcode"

# Un caso: (nombre, fuente_tcode, referencia, entrada). `referencia` es un
# `.c` de `REFERENCIAS`; `entrada` es el texto que lee el binario por un tubo,
# o `None` si no lee nada.
Caso = tuple[str, str, str, str | None]

CASOS: list[Caso] = [
    # Una rutina traducida de verdad: bucles, condiciones y estado, del estilo
    # de la fisica de un juego. La pelota se mueve, rebota en los cuatro
    # bordes y cuenta los toques; el codigo de salida es esa cuenta, asi que el
    # caso tambien exige que los dos salgan con el mismo.
    ("una pelota que rebota: bucles, condiciones y estado",
     '''fn main() -> usize {
            let ancho: i64 = 10;
            let alto: i64 = 7;
            var x: i64 = 2;
            var y: i64 = 3;
            var vx: i64 = 3;
            var vy: i64 = 2;
            var toques: usize = 0;
            var paso: i64 = 0;
            while paso < 12 {
                x = x + vx;
                y = y + vy;
                if x < 0 {
                    x = 0;
                    vx = 0 - vx;
                    toques = toques + 1;
                }
                if x > ancho {
                    x = ancho;
                    vx = 0 - vx;
                    toques = toques + 1;
                }
                if y < 0 {
                    y = 0;
                    vy = 0 - vy;
                    toques = toques + 1;
                }
                if y > alto {
                    y = alto;
                    vy = 0 - vy;
                    toques = toques + 1;
                }
                imprimir($"{paso} {x} {y}\\n");
                paso = paso + 1;
            }
            imprimir($"{toques}\\n");
            return toques;
        }''',
     "rebote.c", None),

    # Otro automata de los de juego: la regla 110 sobre un anillo de celdas
    # abierto, ocho generaciones. Estado en una lista que se reemplaza entera
    # cada vuelta, y condiciones que miran a los vecinos.
    ("la regla 110 dibujada generacion a generacion",
     '''fn main() -> usize {
            let ancho: usize = 24;
            var actual: list<usize> = [];
            var i: usize = 0;
            while i < ancho {
                anadir(actual, 0);
                i = i + 1;
            }
            actual[ancho / 2] = 1;
            var generacion: usize = 0;
            while generacion < 8 {
                var linea = vacio();
                var k: usize = 0;
                while k < ancho {
                    if actual[k] == 1 {
                        empujar(linea, "#");
                    } else {
                        empujar(linea, ".");
                    }
                    k = k + 1;
                }
                imprimir($"{generacion} {linea}\\n");
                var siguiente: list<usize> = [];
                var j: usize = 0;
                while j < ancho {
                    let izq = if j == 0 { 0 } else { actual[j - 1] };
                    let cen = actual[j];
                    let der = if j + 1 == ancho { 0 } else { actual[j + 1] };
                    let vecindad = izq * 4 + cen * 2 + der;
                    if vecindad == 6 || vecindad == 5 || vecindad == 3
                    || vecindad == 2 || vecindad == 1 {
                        anadir(siguiente, 1);
                    } else {
                        anadir(siguiente, 0);
                    }
                    j = j + 1;
                }
                actual = siguiente;
                generacion = generacion + 1;
            }
            return 0;
        }''',
     "automata.c", None),

    # Con entrada por un tubo: toda la entrada de una vez, partida en lineas,
    # recortada y convertida a numero, con `sino 0` para lo que no lo es. El
    # codigo de salida es la cuenta de lineas con numero.
    ("las lineas de la entrada, sumadas con `entrada_completa`",
     '''use "std/texto";

        fn main() -> usize {
            let todo = entrada_completa() sino nuevo("");
            let ls = lineas(vista(todo));
            var total: i64 = 0;
            var maximo: i64 = 0;
            var cuantos: usize = 0;
            for linea en ls {
                let limpio = recortar(vista(linea));
                if largo(limpio) == 0 {
                    continue;
                }
                let v = a_entero(limpio) sino 0;
                let n = v como i64;
                total = total + n;
                if n > maximo {
                    maximo = n;
                }
                cuantos = cuantos + 1;
                if cuantos % 2 == 0 {
                    total = total - 1;
                }
                imprimir($"{cuantos} {total} {maximo}\\n");
            }
            imprimir($"{cuantos} {total}\\n");
            return cuantos;
        }''',
     "acumula.c", "5\n3\n9\n\n7\n"),
]


def _revisar_independiente(ruta: str) -> None:
    """La referencia no puede ser el C que emite `tcodec`."""
    with open(ruta, encoding="utf-8") as f:
        texto = f.read()
    assert MARCA_GENERADO not in texto, (
        f"{os.path.relpath(ruta, RAIZ)} es el C que emite tcodec, no una "
        "implementacion de referencia independiente")


def _diferencia(tcode: str, c: str) -> str:
    """La primera linea en que difieren dos salidas, para el mensaje."""
    suyas, nuestras = tcode.splitlines(), c.splitlines()
    for i in range(max(len(suyas), len(nuestras))):
        a = suyas[i] if i < len(suyas) else None
        b = nuestras[i] if i < len(nuestras) else None
        if a != b:
            return f"linea {i + 1}: Tcode {a!r}, C {b!r}"
    return f"solo cambia el final ({len(tcode)} y {len(c)} bytes)"


def correr(suite: Resultado) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        # El C de Tcode de cada caso sale en orden; compilarlo con los
        # sanitizers y correrlo junto a su referencia es lo que cuesta y va en
        # paralelo.
        trabajos = []
        for i, (nombre, fuente, referencia, entrada) in enumerate(CASOS):
            suite.total += 1
            suyo = os.path.join(tmp, str(i))
            os.mkdir(suyo)
            ruta_ref = os.path.join(REFERENCIAS, referencia)
            if not os.path.isfile(ruta_ref):
                suite.falla(nombre, f"falta la referencia {referencia}")
                continue
            try:
                _revisar_independiente(ruta_ref)
                codigo = c_de(fuente, suyo)
            except AssertionError as exc:
                suite.falla(nombre, str(exc))
                continue
            trabajos.append((nombre, codigo, ruta_ref, entrada, suyo))

        def uno(trabajo):
            nombre, codigo, ruta_ref, entrada, suyo = trabajo
            try:
                rc_tc, out_tc, err_tc = correr_c(codigo, suyo, entrada=entrada)
            except AssertionError as exc:
                return nombre, f"el C generado no compila:\n{exc}"
            sucio = [m for m in ("AddressSanitizer", "LeakSanitizer",
                                 "runtime error")
                     if m in err_tc]
            if sucio:
                return nombre, (f"el Tcode corre sucio bajo ASan+UBSan "
                                f"({', '.join(sucio)}):\n{err_tc[-500:]}")

            try:
                rc_ref, out_ref, _err_ref = correr_referencia(
                    ruta_ref, suyo, entrada=entrada)
            except AssertionError as exc:
                return nombre, str(exc)

            if out_tc != out_ref:
                return nombre, (
                    "la salida no coincide: "
                    + _diferencia(out_tc, out_ref)
                    + f"\n    referencia: {os.path.relpath(ruta_ref, RAIZ)}")
            if rc_tc != rc_ref:
                return nombre, (f"el codigo de salida no coincide: "
                                f"Tcode {rc_tc}, C {rc_ref}")
            return nombre, None

        for nombre, fallo in en_paralelo(uno, trabajos):
            if fallo:
                suite.falla(nombre, fallo)

        suite.cifra("equivale", len(CASOS))
        print(f"    {len(CASOS)} casos, cada uno contra su referencia en C "
              f"escrita a mano: misma salida y mismo codigo de salida")
