"""
Programas al azar que toman vistas de dos `str`, los modifican y las usan,
entre `if` y bucles. Son para P13: un prestamo dura hasta el ultimo uso de la
vista, asi que unos compilan y otros no segun donde este ese ultimo uso.

Lo que se comprueba no se calcula aqui: los que el compilador acepta tienen
que correr limpios bajo ASan (si dijera que una vista ya no se usa y se
usara, leeria memoria liberada), y los dos compiladores tienen que decir lo
mismo de cada uno.
"""

import random

DUENIOS = ["s", "t"]


def _bloque(r, prof, vistas):
    lineas = []
    for _ in range(r.randint(1, 4)):
        k = r.random()
        d = r.choice(DUENIOS)
        if k < 0.25:
            v = f"v{r.randint(0, 999)}"
            while v in vistas:
                v = f"v{r.randint(0, 999)}"
            vistas.append(v)
            lineas.append(f"let {v} = vista({d});")
        elif k < 0.45 and vistas:
            lineas.append(f"imprimir({r.choice(vistas)});")
        elif k < 0.6:
            lineas.append(r.choice([f'empujar({d}, "x");', f'{d} = nuevo("y");']))
        elif k < 0.7 and vistas:
            lineas.append(f"imprimir(largo({r.choice(vistas)}) + largo({d}));")
        elif k < 0.85 and prof < 2:
            # Lo de dentro ve las vistas de fuera; las suyas mueren al cerrar.
            dentro = _bloque(r, prof + 1, list(vistas))
            if r.random() < 0.5:
                lineas.append(f"if largo({d}) > 1 {{")
                lineas += ["    " + x for x in dentro]
                lineas.append("}")
            else:
                i = f"i{prof}"
                lineas.append(f"var {i}: usize = 0;")
                lineas.append(f"while {i} < 2 {{")
                lineas += ["    " + x for x in dentro]
                lineas.append(f"    {i} = {i} + 1;")
                lineas.append("}")
        else:
            lineas.append(f"imprimir({d});")
    return lineas


def generar(semilla):
    r = random.Random(semilla)
    cuerpo = ['var s = nuevo("a");', 'var t = nuevo("b");'] + _bloque(r, 0, [])
    return "fn main() {\n" + "\n".join("    " + x for x in cuerpo) + "\n}\n"
