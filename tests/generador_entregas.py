"""
Programas que ENTREGAN valores con duenio a funciones que pueden fallar.

Es la zona por la que salio la doble liberacion de 2026-10-16 (un `str`
entregado dentro de un `try` cuya llamada fallaba: el camino de error lo
soltaba otra vez). El generador general (`generador_programas.py`) tiene
`try` y `sino`, pero no combina «entregar» × «fallar despues de recibir» ×
«salir antes» × «campos», que es donde viven las banderas `ss_vivo_`.

Cada escenario es una pareja `envia_k` / `recibe_k`:

  - el VALOR: un `str`, una `list<str>`, un struct con un `str` dentro, un
    `bloque<str>` o un enum con un `str` en la variante;
  - COMO se entrega: `try recibe(v, ...)`, `recibe(v, ...) sino ALT`, metido
    en un struct antes de entregarlo, en un bucle que entrega uno por vuelta,
    o devuelto por quien lo recibe y vuelto a usar;
  - CUANDO falla quien lo recibe: antes de mirarlo, despues de mirarlo, o
    nunca; y si `envia` sale antes con el valor todavia suyo.

El generador sabe lo que da cada escenario (la medida del valor, o la
alternativa si falla), asi que la propiedad es doble: la salida es la
esperada, y AddressSanitizer + LeakSanitizer no ven nada.
"""

import random

PALABRAS = ["ana", "beto", "cielo", "duna", "eco", "faro", "gris", "hilo"]
VALORES = ["str", "lista", "caja", "bloque", "enum"]
FORMAS = ["try", "sino", "en_caja", "bucle", "devuelto"]
FALLOS = ["antes", "despues", "nunca"]

PRELUDIO = """struct Caja { s: str, n: usize }
enum Hay { Algo(str), Nada }

fn medida_caja(c: &Caja) -> usize { return largo(c.s) + c.n; }
fn medida_hay(h: &Hay) -> usize {
    match h {
        Hay.Algo(s) -> { return largo(s) + 1; },
        Hay.Nada -> { return 0; }
    }
}
fn medida_bloque(b: &bloque<str>) -> usize {
    var t: usize = 0;
    var i = 0;
    while i < largo(b) { t = t + largo(b[i]); i = i + 1; }
    return t;
}
fn medida_lista(xs: &list<str>) -> usize {
    var t: usize = 0;
    for x en xs { t = t + largo(x); }
    return t;
}
"""


class Escenario:
    def __init__(self, r, k):
        self.k = k
        self.valor = r.choice(VALORES)
        self.forma = r.choice(FORMAS)
        self.fallo = r.choice(FALLOS)
        self.salida_temprana = r.random() < 0.3
        self.temprana_toma = r.random() < 0.5   # si la salida temprana se da
        self.palabra = r.choice(PALABRAS)
        self.n = r.randint(1, 9)
        self.alt = r.randint(100, 999)
        self.vueltas = r.randint(1, 3)

    # --- el valor, su tipo y lo que mide
    def tipo(self):
        return {"str": "str", "lista": "list<str>", "caja": "Caja",
                "bloque": "bloque<str>", "enum": "Hay"}[self.valor]

    def construir(self):
        p = self.palabra
        if self.valor == "str":
            return [f'let v = nuevo("{p}");']
        if self.valor == "lista":
            return [f'var v: list<str> = [];', f'anadir(v, nuevo("{p}"));', f'anadir(v, nuevo("{p}{p}"));']
        if self.valor == "caja":
            return [f'let v = Caja {{ s: nuevo("{p}"), n: {self.n} }};']
        if self.valor == "bloque":
            return [f'var v: bloque<str> = reservar(2);', f'v[0] = nuevo("{p}");', f'v[1] = nuevo("{p}");']
        return [f'let v = Hay.Algo(nuevo("{p}"));']

    def medir(self, x):
        return {"str": f"largo({x})", "lista": f"medida_lista({x})", "caja": f"medida_caja({x})",
                "bloque": f"medida_bloque({x})", "enum": f"medida_hay({x})"}[self.valor]

    def medida(self):
        p = len(self.palabra)
        return {"str": p, "lista": 3 * p, "caja": p + self.n, "bloque": 2 * p, "enum": p + 1}[self.valor]

    # --- el codigo
    def recibe(self):
        t = self.tipo()
        k = self.k
        if self.forma == "en_caja":
            t = "Caja"
        ret = t if self.forma == "devuelto" else "usize"
        cuerpo = []
        if self.fallo == "antes":
            cuerpo.append('    if falla { fail "antes"; }')
        mira = self.medir("x") if self.forma != "en_caja" else "medida_caja(x)"
        cuerpo.append(f"    let m = {mira};")
        if self.fallo == "despues":
            cuerpo.append('    if falla && m > 0 { fail "despues"; }')
        cuerpo.append("    return x;" if self.forma == "devuelto" else "    return m;")
        return [f"fn recibe_{k}(x: {t}, falla: bool) -> {ret} ! {{", *cuerpo, "}"]

    def envia(self):
        k = self.k
        falla = "true" if self.fallo != "nunca" else "false"
        c = [f"fn envia_{k}() -> usize ! {{"]
        if self.forma != "bucle":  # en el bucle se hace uno por vuelta
            c += ["    " + l for l in self.construir()]
        if self.salida_temprana:
            toma = "true" if self.temprana_toma else "false"
            c.append(f"    if {toma} {{ return 7; }}")
        if self.forma == "try":
            c.append(f"    let r = try recibe_{k}(v, {falla});")
            c.append("    return r + 1;")
        elif self.forma == "sino":
            c.append(f"    let r = recibe_{k}(v, {falla}) sino {self.alt};")
            c.append("    return r + 1;")
        elif self.forma == "en_caja":
            # el valor dentro de un struct, y el struct entregado
            if self.valor == "str":
                c.append(f"    let caja = Caja {{ s: v, n: {self.n} }};")
            else:
                c.append(f"    let tam = {self.medir('v')};")
                c.append(f'    let caja = Caja {{ s: nuevo("{self.palabra}"), n: tam }};')
            c.append(f"    let r = try recibe_{k}(caja, {falla});")
            c.append("    return r + 1;")
        elif self.forma == "bucle":
            c.append("    var total: usize = 0;")
            c.append("    var i = 0;")
            c.append(f"    while i < {self.vueltas} {{")
            c += ["        " + l for l in self.construir()]
            c.append(f"        total = total + (recibe_{k}(v, {falla}) sino {self.alt});")
            c.append("        i = i + 1;")
            c.append("    }")
            c.append("    return total;")
        else:  # devuelto: quien lo recibe lo devuelve y se vuelve a usar
            c.append(f"    let w = try recibe_{k}(v, {falla});")
            c.append(f"    return {self.medir('w')} + 2;")
        c.append("}")
        return c

    def esperado(self):
        """Lo que suma `main` por este escenario (`envia_k() sino 50`)."""
        if self.salida_temprana and self.temprana_toma:
            return 7
        falla = self.fallo != "nunca"
        p = len(self.palabra)
        if self.forma == "try":
            return 50 if falla else self.medida() + 1
        if self.forma == "sino":
            return (self.alt if falla else self.medida()) + 1
        if self.forma == "en_caja":
            if self.valor == "str":
                m = p + self.n
            else:
                m = p + self.medida()
            return 50 if falla else m + 1
        if self.forma == "bucle":
            return self.vueltas * (self.alt if falla else self.medida())
        return 50 if falla else self.medida() + 2


def generar(semilla, cuantos=8):
    """(fuente, salida esperada) de un programa con `cuantos` escenarios."""
    r = random.Random(semilla)
    es = [Escenario(r, k) for k in range(cuantos)]
    lineas = [PRELUDIO]
    for e in es:
        lineas += e.recibe() + [""] + e.envia() + [""]
    lineas.append("fn main() {")
    lineas.append("    var total: usize = 0;")
    for e in es:
        lineas.append(f"    total = total + (envia_{e.k}() sino 50);")
    lineas.append('    imprimir($"{total}\\n");')
    lineas.append("}")
    return "\n".join(lineas) + "\n", f"{sum(e.esperado() for e in es)}\n"
