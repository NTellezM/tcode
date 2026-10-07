"""EQUIVALE: el Tcode se comporta igual que una implementacion independiente.

La suite ya comprueba que un programa compila y da esta salida, y que lo que
no debe compilar no compila. Ninguna de esas dos cosas dice lo que de verdad
importa cuando se **traduce** codigo de otro lenguaje a Tcode: que se comporte
igual que el original. Aqui hay dos formas de comprobarlo.

**Contra una referencia en C viva.** El caso lleva su programa en Tcode, una
implementacion de referencia en C escrita a mano
(`tests/lenguaje/equivale/<caso>.c`) y, si le hace falta, la entrada que se le
pasa por un tubo. El de Tcode se compila con `-Wall -Wextra -Werror` y corre
bajo ASan+UBSan; la referencia se compila con las mismas banderas y **sin** los
sanitizers de Tcode, porque no es el programa que se prueba. Los dos corren con
la misma entrada y se exige la misma salida y el mismo codigo de salida. La
referencia nunca es el C que emite el compilador —si lo fuera, el caso
compararia el compilador consigo mismo—, y el runner lo vigila: el C generado
lleva la marca `Generado por el compilador de Tcode`, y un `.c` de `equivale/`
que la traiga falla.

**Contra un dorado con receta.** El caso lleva un fichero de salida congelada
en `tests/dorados/<caso>.golden`, capturado de una implementacion que no es
`tcodec`, y su receta `<caso>.receta.json`. La receta es obligatoria y dice de
donde salio (herramienta, version, commit), el comando exacto, la entrada, si
se puede regenerar en esta maquina y el sha256 del fichero: sin receta no hay
dorado, y el runner comprueba el sha256 —y la marca del C generado— antes de
comparar, asi que editarlo a mano se nota. Los dorados regenerables los
reproduce aqui `tests/dorados/generar.py` desde su referencia; los externos
—los del genero PyBoy/ROM, cuya herramienta no esta instalada— se comparan
igual, pero el runner lo dice **en voz alta** en vez de darlos por buenos en
silencio.

Esto no inventa nada: en `bench/medir.py` ya se compila el mismo programa
escrito en C a mano y en Tcode, se corren los dos y se exige que la salida sea
identica. Lo que faltaba era traer esa idea a la suite como un genero de caso.
"""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import Any

from .comun import (
    RAIZ,
    Resultado,
    c_de,
    correr_c,
    correr_referencia,
    en_paralelo,
)

TITULO = "el Tcode y una implementacion independiente se comportan igual"

# Los `.c` de las referencias vivas, uno por caso.
REFERENCIAS = os.path.join(RAIZ, "tests", "lenguaje", "equivale")
# Los dorados congelados y sus recetas.
DORADOS = os.path.join(RAIZ, "tests", "dorados")
GENERADOR = os.path.join(DORADOS, "generar.py")

# La marca del C que emite `tcodec`: ni una referencia ni un dorado pueden
# traerla.
MARCA_GENERADO = "Generado por el compilador de Tcode"
# Lo que una receta tiene que decir, o el dorado no vale.
CLAVES_RECETA = ("caso", "origen", "herramienta", "version", "commit",
                 "comando", "entrada", "codigo_salida", "regenerable",
                 "generador", "sha256")

# Un caso: (nombre, fuente_tcode, referencia, entrada, dorado). `referencia`
# es un `.c` de `REFERENCIAS` o `None`; `dorado` es un nombre de `DORADOS` o
# `None`; un caso lleva uno de los dos. `entrada` es el texto que lee el
# binario por un tubo, o `None` si no lee nada.
Caso = tuple[str, str, str | None, str | None, str | None]

CASOS: list[Caso] = [
    # ---- contra una referencia en C viva ----
    #
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
     "rebote.c", None, None),

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
     "automata.c", None, None),

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
     "acumula.c", "5\n3\n9\n\n7\n", None),

    # ---- contra un dorado con receta ----
    #
    # El mismo genero que los de arriba, pero congelado: la salida se capturo
    # de la referencia en C `vida.c` y vive en `tests/dorados/vida.golden`. Su
    # receta dice como se regenera aqui, y el runner lo comprueba en cada
    # pasada.
    ("el juego de la vida, contra su dorado congelado",
     '''fn vecinos(t: &list<usize>, ancho: usize, x: usize, y: usize) -> usize {
            var n: usize = 0;
            var dy: usize = 0;
            while dy < 3 {
                var dx: usize = 0;
                while dx < 3 {
                    if dx != 1 || dy != 1 {
                        let xx = (x + ancho - 1 + dx) % ancho;
                        let yy = (y + ancho - 1 + dy) % ancho;
                        n = n + t[yy * ancho + xx];
                    }
                    dx = dx + 1;
                }
                dy = dy + 1;
            }
            return n;
        }

        fn main() -> usize {
            let ancho: usize = 8;
            var actual: list<usize> = [];
            var i: usize = 0;
            while i < ancho * ancho {
                anadir(actual, 0);
                i = i + 1;
            }
            actual[1 * ancho + 2] = 1;
            actual[2 * ancho + 3] = 1;
            actual[3 * ancho + 1] = 1;
            actual[3 * ancho + 2] = 1;
            actual[3 * ancho + 3] = 1;
            var generacion: usize = 0;
            while generacion < 5 {
                var linea = vacio();
                var k: usize = 0;
                while k < ancho * ancho {
                    if actual[k] == 1 {
                        empujar(linea, "#");
                    } else {
                        empujar(linea, ".");
                    }
                    if (k + 1) % ancho == 0 {
                        imprimir($"{linea}\\n");
                        linea = vacio();
                    }
                    k = k + 1;
                }
                var siguiente: list<usize> = [];
                var y: usize = 0;
                while y < ancho {
                    var x: usize = 0;
                    while x < ancho {
                        let n = vecinos(actual, ancho, x, y);
                        let vivo = actual[y * ancho + x];
                        if vivo == 1 {
                            if n == 2 || n == 3 {
                                anadir(siguiente, 1);
                            } else {
                                anadir(siguiente, 0);
                            }
                        } else {
                            if n == 3 {
                                anadir(siguiente, 1);
                            } else {
                                anadir(siguiente, 0);
                            }
                        }
                        x = x + 1;
                    }
                    y = y + 1;
                }
                actual = siguiente;
                generacion = generacion + 1;
            }
            return 0;
        }''',
     None, None, "vida"),

    # El dorado externo: viene de la boot ROM DMG a traves de un emulador, y
    # esa herramienta no esta en esta maquina. La comprobacion vale igual; el
    # runner avisa de que aqui no se puede regenerar.
    ("la cabecera de un cartucho Game Boy, contra un dorado externo",
     '''fn valor_hex(b: usize) -> usize {
            if b >= 48 && b <= 57 { return b - 48; }
            if b >= 65 && b <= 70 { return b - 65 + 10; }
            if b >= 97 && b <= 102 { return b - 97 + 10; }
            return 0;
        }

        fn hex_digito(v: usize) -> str {
            if v < 10 { return texto(v); }
            if v == 10 { return nuevo("A"); }
            if v == 11 { return nuevo("B"); }
            if v == 12 { return nuevo("C"); }
            if v == 13 { return nuevo("D"); }
            if v == 14 { return nuevo("E"); }
            return nuevo("F");
        }

        fn hex2(v: usize) -> str {
            return $"{hex_digito(v / 16)}{hex_digito(v % 16)}";
        }

        fn anadir_hex(destino: mut list<usize>, hex: view) {
            var i: usize = 0;
            while i < largo(hex) {
                let alto = valor_hex(byte(hex, i));
                let bajo = valor_hex(byte(hex, i + 1));
                anadir(destino, alto * 16 + bajo);
                i = i + 2;
            }
        }

        fn main() -> usize {
            var logo: list<usize> = [];
            anadir_hex(logo, "CEED6666CC0D000B03730083000C000D");
            anadir_hex(logo, "0008111F8889000EDCCC6EE6DDDDD999");
            anadir_hex(logo, "BBBB67636E0EECCCDDDC999FBBB9333E");
            var i: usize = 0;
            while i < 48 {
                imprimir(hex2(logo[i]));
                if (i + 1) % 8 == 0 {
                    imprimir("\\n");
                } else {
                    imprimir(" ");
                }
                i = i + 1;
            }
            let region: list<usize> = [84, 67, 79, 68, 69, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 48, 48, 0, 0, 0, 0, 0, 51, 0];
            var x: i64 = 0;
            var j: usize = 0;
            while j < 25 {
                x = x - (region[j] como i64) - 1;
                if x < 0 {
                    x = x + 256;
                }
                j = j + 1;
            }
            imprimir($"checksum 0134-014C: {hex2(x como usize)}\\n");
            imprimir($"logo bytes: {largo(logo)}\\n");
            return 0;
        }''',
     None, None, "gb_cabecera"),
]


@dataclass
class Trabajo:
    """Un caso listo para correr: su C, y su referencia viva o su dorado."""

    nombre: str
    codigo: str
    suyo: str
    entrada: str | None
    ruta_ref: str
    referencia: str
    dorado: str | None
    golden: str
    receta: dict[str, Any] | None
    ruta_golden: str


def _sha256(ruta: str) -> str:
    with open(ruta, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def _revisar_independiente(ruta: str) -> None:
    """La referencia no puede ser el C que emite `tcodec`."""
    with open(ruta, encoding="utf-8") as f:
        texto = f.read()
    assert MARCA_GENERADO not in texto, (
        f"{os.path.relpath(ruta, RAIZ)} es el C que emite tcodec, no una "
        "implementacion de referencia independiente")


def _leer_dorado(dorado: str) -> tuple[str, dict[str, Any], str]:
    """El dorado, su receta ya comprobada, y la ruta del fichero.

    Sin receta no hay dorado: se exigen sus claves, el sha256 del fichero, y la
    referencia con su hash si el dorado se regenera desde ella.
    """
    ruta_golden = os.path.join(DORADOS, dorado + ".golden")
    ruta_receta = os.path.join(DORADOS, dorado + ".receta.json")
    assert os.path.isfile(ruta_golden), f"falta el dorado {dorado}.golden"
    assert os.path.isfile(ruta_receta), f"falta la receta {dorado}.receta.json"
    with open(ruta_golden, "rb") as f:
        crudo = f.read()
    assert MARCA_GENERADO.encode() not in crudo, (
        f"{dorado}.golden es el C que emite tcodec, no una traza de referencia")
    with open(ruta_receta, encoding="utf-8") as f:
        receta = json.load(f)
    faltan = [k for k in CLAVES_RECETA if k not in receta]
    assert not faltan, f"{dorado}.receta.json no dice {', '.join(faltan)}"
    assert receta["caso"] == dorado, (
        f"{dorado}.receta.json dice ser `{receta['caso']}`")
    assert _sha256(ruta_golden) == receta["sha256"], (
        f"{dorado}.golden no tiene el sha256 de su receta: alguien lo edito a mano")
    if receta["commit"] is None:
        assert receta.get("referencia") and receta.get("referencia_sha256"), (
            f"sin commit, {dorado}.receta.json necesita `referencia` y "
            "`referencia_sha256`")
        referencia = os.path.join(RAIZ, receta["referencia"])
        assert os.path.isfile(referencia), f"falta {receta['referencia']}"
        _revisar_independiente(referencia)
        assert _sha256(referencia) == receta["referencia_sha256"], (
            f"{receta['referencia']} cambio: regenera el dorado")
    if not receta["regenerable"]:
        assert receta.get("motivo"), (
            f"{dorado} no se regenera aqui y su receta no dice por que")
    return crudo.decode("utf-8"), receta, ruta_golden


def _aviso_dorado(receta: dict[str, Any]) -> str:
    """Lo que el runner dice del dorado, en voz alta si es externo."""
    caso = receta["caso"]
    ruta_receta = os.path.relpath(
        os.path.join(DORADOS, str(caso) + ".receta.json"), RAIZ)
    if receta["regenerable"]:
        return (f"    dorado `{caso}`: regenerable aqui desde "
                f"{receta['referencia']} ({receta['generador']})")
    return (f"    DORADO EXTERNO NO REGENERABLE AQUI: `{caso}`\n"
            f"      origen:     {receta['origen']}\n"
            f"      hace falta: {receta['motivo']}\n"
            f"      receta:     {ruta_receta}")


def _diferencia(tcode: str, otro: str) -> str:
    """La primera linea en que difieren dos salidas, para el mensaje."""
    suyas, nuestras = tcode.splitlines(), otro.splitlines()
    for i in range(max(len(suyas), len(nuestras))):
        a = suyas[i] if i < len(suyas) else None
        b = nuestras[i] if i < len(nuestras) else None
        if a != b:
            return f"linea {i + 1}: Tcode {a!r}, otro {b!r}"
    return f"solo cambia el final ({len(tcode)} y {len(otro)} bytes)"


def _preparar(nombre: str, fuente: str, referencia: str | None,
              entrada: str | None, dorado: str | None, suyo: str) -> Trabajo:
    if dorado:
        golden, receta, ruta_golden = _leer_dorado(dorado)
        assert entrada == receta["entrada"], (
            f"la entrada del caso no es la de la receta de `{dorado}`")
        return Trabajo(nombre, c_de(fuente, suyo), suyo, entrada, "", "",
                       dorado, golden, receta, ruta_golden)
    assert referencia is not None, f"el caso `{nombre}` no tiene referencia ni dorado"
    ruta_ref = os.path.join(REFERENCIAS, referencia)
    assert os.path.isfile(ruta_ref), f"falta la referencia {referencia}"
    _revisar_independiente(ruta_ref)
    return Trabajo(nombre, c_de(fuente, suyo), suyo, entrada, ruta_ref,
                   referencia, None, "", None, "")


def _contra_dorado(t: Trabajo, rc: int, out: str) -> tuple[str, str | None, str]:
    assert t.receta is not None and t.dorado is not None
    aviso = _aviso_dorado(t.receta)
    if out != t.golden:
        return t.nombre, (
            "la salida no coincide con el dorado: "
            + _diferencia(out, t.golden)
            + f"\n    dorado: {os.path.relpath(t.ruta_golden, RAIZ)}"), aviso
    if rc != t.receta["codigo_salida"]:
        return t.nombre, (
            f"el codigo de salida {rc} no es el del dorado "
            f"({t.receta['codigo_salida']})"), aviso
    # La receta tiene que sostenerse: el generador regenera el dorado (o lo
    # contrasta con su modelo independiente) y falla si no sale lo mismo.
    r = subprocess.run([sys.executable, GENERADOR, "--comprobar", t.dorado],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return t.nombre, ("la receta del dorado no se sostiene:\n"
                          + (r.stdout + r.stderr).strip()), aviso
    return t.nombre, None, aviso


def _correr_uno(t: Trabajo) -> tuple[str, str | None, str]:
    """(nombre, fallo o None, aviso del dorado)."""
    try:
        rc, out, err = correr_c(t.codigo, t.suyo, entrada=t.entrada)
    except AssertionError as exc:
        return t.nombre, f"el C generado no compila:\n{exc}", ""
    sucio = [m for m in ("AddressSanitizer", "LeakSanitizer", "runtime error")
             if m in err]
    if sucio:
        return t.nombre, (f"el Tcode corre sucio bajo ASan+UBSan "
                          f"({', '.join(sucio)}):\n{err[-500:]}"), ""

    if t.dorado is not None:
        return _contra_dorado(t, rc, out)

    try:
        rc_ref, out_ref, _err_ref = correr_referencia(
            t.ruta_ref, t.suyo, entrada=t.entrada)
    except AssertionError as exc:
        return t.nombre, str(exc), ""
    if out != out_ref:
        return t.nombre, ("la salida no coincide: " + _diferencia(out, out_ref)
                          + f"\n    referencia: {os.path.relpath(t.ruta_ref, RAIZ)}"), ""
    if rc != rc_ref:
        return t.nombre, (f"el codigo de salida no coincide: "
                          f"Tcode {rc}, C {rc_ref}"), ""
    return t.nombre, None, ""


def correr(suite: Resultado) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        # El C de Tcode de cada caso sale en orden; compilarlo con los
        # sanitizers y correrlo junto a su referencia o su dorado es lo que
        # cuesta y va en paralelo.
        trabajos: list[Trabajo] = []
        for i, (nombre, fuente, referencia, entrada, dorado) in enumerate(CASOS):
            suite.total += 1
            suyo = os.path.join(tmp, str(i))
            os.mkdir(suyo)
            try:
                trabajo = _preparar(nombre, fuente, referencia, entrada,
                                    dorado, suyo)
            except AssertionError as exc:
                suite.falla(nombre, str(exc))
                continue
            trabajos.append(trabajo)

        for nombre, fallo, aviso in en_paralelo(_correr_uno, trabajos):
            if fallo:
                suite.falla(nombre, fallo)
            if aviso:
                print(aviso)

        dorados = sum(1 for caso in CASOS if caso[4])
        suite.cifra("equivale", len(CASOS))
        suite.cifra("equivale_dorados", dorados)
        print(f"    {len(CASOS)} casos: {len(CASOS) - dorados} contra una "
              f"referencia en C viva y {dorados} contra un dorado con receta")
