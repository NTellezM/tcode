"""FORMAS: cada forma de guardar un tipo dentro de otro, en uno o dos
modulos, con los dos compiladores y bajo ASan.

Los fallos que encontro el Tamagotchi estaban en la combinacion, no en una
regla: un struct con un campo enum que posee, un campo `Q.Tipo` de otro
modulo, un campo arreglo. Ninguno salia en la suite porque nadie habia
escrito esa combinacion. Aqui se escriben todas:

- siete hojas: `i64`, `str`, un enum sin datos, un enum que posee, un struct
  sin dueno, un struct con dueno y `lista<str>`;
- cinco envolturas: campo de struct, arreglo `[T; 2]`, `lista<T>`,
  `mapa<str, T>` y forma de enum; una o dos, una dentro de otra;
- tres sitios: todo en un archivo; los tipos en otro modulo; y las hojas en
  un modulo, las envolturas en otro que las usa, y el programa en un tercero.

Cada caso construye un valor, lo copia, lo pasa por una funcion que lo
devuelve y lo mira de punta a punta. Tiene que dar el mismo C en Python y en
`tcodec`, compilar sin avisos, correr limpio bajo ASan y UBSan —sin fugas— y
escribir lo que se calcula aqui.

Lo que el lenguaje no permite —un arreglo como elemento de lista— no se
escribe. Lo que `tcodec` todavia no escribe —arreglos en un enum— se cuenta
aparte.
"""

import os
import re
import shutil
import subprocess
import tempfile

from tcode.cli import compilar_archivo

from .comun import ENTORNO_TCODEC, RUNTIME, Resultado, en_paralelo, tcodec
from compilar_c import cc


class Tipo:
    """Una forma: como se escribe, como se construye y como se mira.

    `tipo(sitio)` es el texto del tipo visto desde `sitio`, que dice el
    prefijo de las hojas y el de las envolturas: `Q.Caja3` desde el programa,
    `Caja3` desde el modulo que la declara."""

    def __init__(self, ident, hoja, esquema, valor, dentro=None):
        self.ident = ident
        self.hoja = hoja            # True: la declara el modulo de hojas
        self.esquema = esquema      # texto con {H} y {E}: prefijos
        self.valor = valor          # lo que da `ver` sobre lo que da `hacer`
        self.dentro = dentro
        self.declaracion = ""       # struct o enum, con {H} y {E}
        self.hacer = ""             # cuerpo de `hacer`, con {H}, {E}, {T}
        self.ver = ""               # cuerpo de `ver`, sobre `x`
        self.param = "&{T}"         # como recibe `ver` el valor
        self.dueno = True           # si `pasar` y `copiar` tienen sentido
        self.presta = False         # si lo que guarda apunta a memoria de otro

    def tipo(self, sitio):
        return self.esquema.format(**sitio)

    def formato(self, texto, sitio):
        return texto.format(T=self.tipo(sitio), **sitio)


def hojas():
    salida = []

    def hoja(ident, esquema, valor, hacer, ver, param="&{T}", decl="", dueno=True,
             presta=False):
        t = Tipo(ident, True, esquema, valor)
        t.hacer, t.ver, t.param = hacer, ver, param
        t.declaracion, t.dueno, t.presta = decl, dueno, presta
        salida.append(t)

    hoja("entero", "i64", 7, "return 7;", "return x;", param="{T}", dueno=False)
    hoja("texto", "str", 2, 'return nuevo("ab");', "return largo(x) como i64;", param="view")
    # Una vista es el unico prestamo que se puede tener en la mano, porque
    # sale de un literal. Como campo hace del struct uno que presta; en una
    # lista, un mapa, un arreglo o un enum no cabe. Un `&T` no puede ser
    # hoja: una funcion no puede devolver un prestamo a algo suyo.
    hoja("vista", "view", 2, 'return "ab";', "return largo(x) como i64;",
         param="{T}", dueno=False, presta=True)
    hoja("color", "{H}Color", 2, "return {H}Color.Verde;",
         "return match x {{ {H}Color.Rojo -> 1, {H}Color.Verde -> 2 }};",
         param="{T}", decl="enum Color {{ Rojo, Verde }}", dueno=False)
    hoja("quiza", "{H}Quiza", 3, 'return {H}Quiza.Algo(nuevo("xyz"));',
         "return match x {{ {H}Quiza.Nada -> 0, {H}Quiza.Algo(s) -> largo(s) como i64 }};",
         decl="enum Quiza {{ Nada, Algo(str) }}")
    hoja("punto", "{H}Punto", 5, "return {H}Punto {{ x: 5 }};", "return x.x;",
         decl="struct Punto {{ x: i64 }}", dueno=False)
    hoja("nombre", "{H}Nombre", 4, 'return {H}Nombre {{ s: nuevo("abcd") }};',
         "return largo(x.s) como i64;", decl="struct Nombre {{ s: str }}")
    hoja("textos", "lista<str>", 4, 'return [nuevo("a"), nuevo("bc")];',
         "return (largo(x) como i64) + (largo(x[1]) como i64);")
    return salida


def envolver(clase, dentro, n):
    """La envoltura `clase` alrededor de `dentro`; `n` numera sus nombres."""
    j = dentro.ident
    if clase == "campo":
        t = Tipo(n, False, "{E}Caja" + str(n), dentro.valor + 1, dentro)
        t.presta = dentro.presta
        t.declaracion = "struct Caja%d {{ v: %s, n: i64 }}" % (n, dentro.esquema)
        t.hacer = "return {E}Caja%d {{ v: hacer_%s(), n: 1 }};" % (n, j)
        t.ver = "return ver_%s(x.v) + x.n;" % j
    elif clase == "arreglo":
        t = Tipo(n, False, "[%s; 2]" % dentro.esquema, dentro.valor * 4, dentro)
        t.hacer = "return [hacer_%s(), hacer_%s()];" % (j, j)
        t.ver = "return ver_%s(x[0]) + 3 * ver_%s(x[1]);" % (j, j)
    elif clase == "lista":
        t = Tipo(n, False, "lista<%s>" % dentro.esquema, 2 + 2 * dentro.valor, dentro)
        t.hacer = ("var l: {T} = []; anadir(l, hacer_%s()); anadir(l, hacer_%s()); "
                   "return l;" % (j, j))
        t.ver = ("var s = largo(x) como i64; for y en x {{ s = s + ver_%s(y); }} "
                 "return s;" % j)
    elif clase == "mapa":
        t = Tipo(n, False, "mapa<str, %s>" % dentro.esquema, 12, dentro)
        t.hacer = ('var m: {T} = []; poner(m, "a", hacer_%s()); '
                   'poner(m, "b", hacer_%s()); return m;' % (j, j))
        t.ver = 'var s = largo(x) como i64; if tiene(x, "a") {{ s = s + 10; }} return s;'
    else:
        t = Tipo(n, False, "{E}Sobre" + str(n), dentro.valor, dentro)
        t.declaracion = "enum Sobre%d {{ Vacio, Con(%s) }}" % (n, dentro.esquema)
        t.hacer = "return {E}Sobre%d.Con(hacer_%s());" % (n, j)
        t.ver = ("return match x {{ {E}Sobre%d.Vacio -> 0, {E}Sobre%d.Con(y) -> ver_%s(y) }};"
                 % (n, n, j))
    t.ident = f"f{n}"
    return t


CLASES = ["campo", "arreglo", "lista", "mapa", "enum"]


def permitida(clase, dentro):
    """(la razon, lo que tiene que decir el error), o None si se escribe.

    La razon se cuenta y el texto se comprueba: lo que el lenguaje no deja
    escribir tiene que rechazarse, y con el mismo primer error en los dos
    compiladores. Lo que empieza por `tcodec:` es un hueco suyo --todavia no
    lo escribe, pero Python si--, y solo se cuenta.
    """
    lleva_arreglo = dentro.esquema.startswith("[")
    if clase == "lista" and lleva_arreglo:
        return "el lenguaje: un arreglo no va en una lista", "no se puede almacenar"
    if clase == "enum" and "[" in dentro.esquema:
        return "tcodec: todavia no escribe arreglos en un enum", None
    # Lo que presta solo cabe como campo de un struct: ahi el struct presta,
    # que es lo que el lenguaje sabe seguir. En una lista, un mapa, un arreglo
    # o un enum no hay donde anotar cuanto vive lo que apuntan.
    if dentro.presta and clase != "campo":
        if clase == "enum":
            return ("el lenguaje: un enum no guarda lo que presta",
                    "un enum no guarda prestamos")
        return (f"el lenguaje: `{clase}` no guarda lo que presta",
                "no se puede almacenar")
    return None


def formas():
    """Todas las formas de una y dos envolturas, y las que se saltan."""
    base = hojas()
    salida, saltadas = [], []
    n = 0
    for h in base:
        for c1 in CLASES:
            n += 1
            uno = envolver(c1, h, n)
            permiso = permitida(c1, h)
            if permiso:
                saltadas.append((uno, permiso[0], permiso[1]))
                continue
            salida.append(uno)
            for c2 in CLASES:
                n += 1
                dos = envolver(c2, uno, n)
                permiso = permitida(c2, uno)
                if permiso:
                    saltadas.append((dos, permiso[0], permiso[1]))
                    continue
                salida.append(dos)
    return base, salida, saltadas


def piezas(t):
    """Todas las formas que hacen falta para escribir `t`, de dentro afuera."""
    salida = []
    while t is not None:
        salida.append(t)
        t = t.dentro
    return list(reversed(salida))


# Donde vive cada cosa. Cada sitio da los prefijos con que se ven las hojas
# ({H}) y las envolturas ({E}) desde cada archivo.
SITIOS = {
    "un archivo": {
        "hojas": None, "envolturas": None,
        "programa": {"H": "", "E": ""},
    },
    "otro modulo": {
        "hojas": "tipos.t", "envolturas": "tipos.t",
        "en_hojas": {"H": "", "E": ""},
        "en_envolturas": {"H": "", "E": ""},
        "programa": {"H": "Q.", "E": "Q."},
        "usar": 'usar "tipos.t" como Q;\n',
    },
    "dos modulos": {
        "hojas": "hojas.t", "envolturas": "tipos.t",
        "en_hojas": {"H": "", "E": ""},
        "en_envolturas": {"H": "H.", "E": ""},
        "programa": {"H": "H.", "E": "Q."},
        "usar": 'usar "tipos.t" como Q;\nusar "hojas.t" como H;\n',
        "usar_envolturas": 'usar "hojas.t" como H;\n',
    },
}


def programa(sitio, casos):
    """Los archivos de un programa con `casos`: {ruta: texto}."""
    s = SITIOS[sitio]
    en_programa = s["programa"]
    declarados, funciones, cuerpo = {}, {}, []
    for caso in casos:
        for t in piezas(caso):
            if t.declaracion and t.ident not in declarados:
                donde = ("hojas" if t.hoja else "envolturas")
                vista = s.get(f"en_{donde}", en_programa)
                declarados[t.ident] = (s[donde], t.declaracion.format(**vista))
            if t.ident in funciones:
                continue
            tipo = t.tipo(en_programa)
            param = t.param.format(T=tipo)
            f = [f"fn hacer_{t.ident}() -> {tipo} {{ {t.formato(t.hacer, en_programa)} }}",
                 f"fn ver_{t.ident}(x: {param}) -> i64 {{ {t.formato(t.ver, en_programa)} }}"]
            if t.dueno:
                f.append(f"fn pasar_{t.ident}(x: {tipo}) -> {tipo} {{ return x; }}")
            funciones[t.ident] = "\n".join(f)
        j = caso.ident
        cuerpo.append(f"    let a_{j} = hacer_{j}();\n"
                      f"    let c_{j} = pasar_{j}(copiar(a_{j}));\n"
                      f'    imprimir($"{{ver_{j}(a_{j})}} {{ver_{j}(c_{j})}}\\n");')
    # Los modulos existen aunque no declaren nada: el programa los usa.
    archivos = {r: [] for r in (s["hojas"], s["envolturas"]) if r}
    for ruta, texto in declarados.values():
        ruta = ruta or "p.t"
        archivos.setdefault(ruta, []).append(texto)
    salida = {}
    for ruta, decls in archivos.items():
        if ruta == "p.t":
            continue
        cabeza = s.get("usar_envolturas", "") if ruta == "tipos.t" else ""
        salida[ruta] = cabeza + "\n".join(decls) + "\n"
    propias = "\n".join(archivos.get("p.t", []))
    salida["p.t"] = (s.get("usar", "") + propias + "\n" + "\n".join(funciones.values())
                     + "\nfn main() {\n" + "\n".join(cuerpo) + "\n}\n")
    return salida


def esperado(casos):
    return "".join(f"{c.valor} {c.valor}\n" for c in casos)


def probar(sitio, casos, tmp):
    """None si todo va bien; si no, que fallo."""
    os.makedirs(tmp, exist_ok=True)
    for ruta, texto in programa(sitio, casos).items():
        with open(os.path.join(tmp, ruta), "w", encoding="utf-8") as f:
            f.write(texto)
    principal = os.path.join(tmp, "p.t")
    de_python, errores = compilar_archivo(principal)
    t = subprocess.run([tcodec(), principal, "--mostrar-c", "--sin-avisos"],
                       capture_output=True, text=True, timeout=300, env=ENTORNO_TCODEC)
    if errores:
        return f"Python lo rechaza: {errores[0]}"
    if t.returncode != 0:
        return f"tcodec lo rechaza: {t.stderr.strip()[:300]}"
    if t.stdout != de_python:
        dado, bueno = t.stdout.splitlines(), de_python.splitlines()
        i = next((k for k, (x, y) in enumerate(zip(dado, bueno)) if x != y),
                 min(len(dado), len(bueno)))
        return (f"otro C que Python, linea {i + 1}:\n"
                f"           tcodec: {dado[i] if i < len(dado) else '(fin)'!r}\n"
                f"           Python: {bueno[i] if i < len(bueno) else '(fin)'!r}")
    ruta_c, binario = os.path.join(tmp, "p.c"), os.path.join(tmp, "p")
    with open(ruta_c, "w", encoding="utf-8") as f:
        f.write(t.stdout)
    r = cc(["cc", "-std=c17", "-O1", "-g", "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer", "-Wall", "-Wextra", "-Werror", f"-I{RUNTIME}",
            ruta_c, os.path.join(RUNTIME, "safestr.c"), "-o", binario, "-lm"],
           capture_output=True, text=True)
    if r.returncode != 0:
        return "el C no compila:\n" + r.stderr[:600]
    e = subprocess.run([binario], capture_output=True, text=True, timeout=120)
    if "Sanitizer" in e.stderr or "runtime error" in e.stderr:
        return "sanitizer:\n" + e.stderr[:800]
    if e.returncode != 0:
        return f"termina con {e.returncode}: {e.stderr[:300]}"
    if e.stdout != esperado(casos):
        return f"escribe {e.stdout[:200]!r}, se esperaba {esperado(casos)[:200]!r}"
    return None


def _sin_ruta(texto):
    """`p.t:12: lo que dice` -> `12: lo que dice`, para comparar los dos."""
    m = re.match(r"^.+?:(\d+): (.*)$", texto, re.S)
    return f"{m.group(1)}: {m.group(2)}" if m else texto


def probar_rechazo(sitio, caso, dice, tmp):
    """None si esa forma se rechaza igual en los dos, y con ese error.

    Es lo que el lenguaje no deja escribir: no vale con que no compile, tiene
    que decirlo el mismo primer error en los dos compiladores.
    """
    os.makedirs(tmp, exist_ok=True)
    for ruta, texto in programa(sitio, [caso]).items():
        with open(os.path.join(tmp, ruta), "w", encoding="utf-8") as f:
            f.write(texto)
    principal = os.path.join(tmp, "p.t")
    _codigo, errores = compilar_archivo(principal)
    if not errores:
        return "Python lo acepta, y no se escribe"
    t = subprocess.run([tcodec(), principal, "--solo-comprobar", "--sin-avisos"],
                       capture_output=True, text=True, timeout=300,
                       env=ENTORNO_TCODEC)
    if t.returncode == 0:
        return "tcodec lo acepta, y no se escribe"
    de_tcodec = [x[len("error: "):] for x in t.stderr.splitlines()
                 if x.startswith("error: ")]
    if not de_tcodec:
        return f"tcodec no dice archivo ni linea: {t.stderr.strip()[:200]}"
    suyo, mio = _sin_ruta(de_tcodec[0]), _sin_ruta(errores[0])
    if suyo != mio:
        return (f"otro primer error que Python:\n"
                f"           tcodec: {suyo!r}\n           Python: {mio!r}")
    if dice not in mio:
        return f"dice {mio!r}, y tendria que decir {dice!r}"
    return None


def probar_hueco(sitio, caso, razon, tmp):
    """None si sigue siendo un hueco de `tcodec`: Python lo escribe y el no.

    Un hueco se cuenta, pero no se deja crecer: si Python tambien lo rechaza,
    o si `tcodec` aprende a escribirlo, esto lo dice para quitar la excepcion
    --como la lista de rechazos que solo entiende `tcodec`.
    """
    os.makedirs(tmp, exist_ok=True)
    for ruta, texto in programa(sitio, [caso]).items():
        with open(os.path.join(tmp, ruta), "w", encoding="utf-8") as f:
            f.write(texto)
    principal = os.path.join(tmp, "p.t")
    _codigo, errores = compilar_archivo(principal)
    t = subprocess.run([tcodec(), principal, "--solo-comprobar", "--sin-avisos"],
                       capture_output=True, text=True, timeout=300,
                       env=ENTORNO_TCODEC)
    if not errores and t.returncode != 0:
        return None                     # el hueco sigue: Python lo escribe
    if errores and t.returncode == 0:
        return "Python lo rechaza y tcodec lo acepta: no es un hueco suyo"
    if errores:
        return (f"ya no es un hueco suyo: Python tambien lo rechaza "
                f"({_sin_ruta(errores[0])!r}); quitalo de la lista")
    return f"tcodec ya lo escribe ({razon}): quita el hueco de la lista"


def nombre(caso):
    return " en ".join(p.esquema.replace("{H}", "").replace("{E}", "")
                       for p in reversed(piezas(caso)))


TITULO = "cada forma de un tipo dentro de otro, en uno o dos modulos"


def correr(suite: Resultado) -> None:
    _, casos, saltadas = formas()
    # Lo que no se escribe, se rechaza: y lo dicen los dos igual. Lo que es
    # un hueco de `tcodec` --Python lo escribe-- se vigila aparte.
    rechazos = [(caso, razon, dice) for caso, razon, dice in saltadas if dice]
    huecos = [(caso, razon) for caso, razon, dice in saltadas if dice is None]
    tmp = tempfile.mkdtemp(prefix="tcode-formas-")
    try:
        def _sitio(sitio):
            # Todos los casos de un sitio en un programa; si falla, uno a uno
            # para decir cuales.
            malo = probar(sitio, casos, os.path.join(tmp, sitio.replace(" ", "_")))
            if malo is None:
                return []
            fallos = []
            for i, caso in enumerate(casos):
                solo = probar(sitio, [caso], os.path.join(tmp, f"{sitio}_{i}".replace(" ", "_")))
                if solo is not None:
                    fallos.append((nombre(caso), solo))
            return fallos or [("todos juntos", malo)]

        def _hueco(sitio):
            fallos = []
            for i, (caso, razon) in enumerate(huecos):
                carpeta = f"hueco_{sitio}_{i}".replace(" ", "_")
                que = probar_hueco(sitio, caso, razon, os.path.join(tmp, carpeta))
                if que is not None:
                    fallos.append((nombre(caso), que))
            return fallos

        def _rechazo(sitio):
            # Cada forma rechazada se prueba suelta: el primer error tiene que
            # ser el suyo, y el mismo en los dos.
            fallos = []
            for i, (caso, _razon, dice) in enumerate(rechazos):
                carpeta = f"rechazo_{sitio}_{i}".replace(" ", "_")
                que = probar_rechazo(sitio, caso, dice, os.path.join(tmp, carpeta))
                if que is not None:
                    fallos.append((nombre(caso), que))
            return fallos

        for sitio, fallos in zip(SITIOS, en_paralelo(_sitio, list(SITIOS))):
            suite.total += len(casos)
            for quien, que in fallos:
                suite.falla(f"{sitio}: {quien}", que)
        for sitio, fallos in zip(SITIOS, en_paralelo(_rechazo, list(SITIOS))):
            suite.total += len(rechazos)
            for quien, que in fallos:
                suite.falla(f"{sitio}: {quien}: no se escribe, y no se "
                            f"rechaza igual en los dos", que)
        for sitio, fallos in zip(SITIOS, en_paralelo(_hueco, list(SITIOS))):
            suite.total += len(huecos)
            for quien, que in fallos:
                suite.falla(f"{sitio}: {quien}: el hueco de tcodec ha cambiado",
                            que)
        por_razon: dict[str, int] = {}
        for _caso, razon, _dice in saltadas:
            por_razon[razon] = por_razon.get(razon, 0) + 1
        print(f"    {len(casos)} formas en {len(SITIOS)} sitios; sin escribir: "
              + "; ".join(f"{n} ({r})" for r, n in sorted(por_razon.items()))
              + f"; de esas, {len(rechazos)} se comprueba que se rechazan y "
              + f"{len(huecos)} son huecos de tcodec que Python si escribe")
        suite.cifra("formas", len(casos) * len(SITIOS))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
