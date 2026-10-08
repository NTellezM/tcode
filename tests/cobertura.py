#!/usr/bin/env python3
"""
La cobertura de `tcodec`, medida a mano.

`make check` no la corre: la CI no tiene tiempo. Esto es un instrumento que se
coge cuando se quiere mirar que caminos del compilador no pisa nadie.

Construye el compilador desde su C semilla (`bootstrap/tcodec.c`) con
`--coverage`, lo pasa por un subconjunto acotado de la suite —las secciones de
`make rapido`— y por los casos del banco (`bench/*.t`), y le pide a `gcov` las
lineas, las ramas y las funciones. El titular es **las funciones que de verdad
no se ejecutan por este instrumento**: las de los `.t` del compilador. Ojo:
algunas de esas las llaman programas del repositorio (`ejemplos/`,
`programas/`) que el instrumento no ejecuta instrumentados —`contar_nodos`,
`hondura` y `mostrar` las usa `ejemplos/lexer/parser.t`—, y el informe lo dice
al lado de cada una; no estan muertas. Lo demas que gcov ve a cero no se suma
al titular, se desglosa y con su motivo:

  * **runtime generado** (`bootstrap/` y `runtime/`): el C que el compilador
    emite en todo binario. Se mira si el codigo del compilador lo llama de
    verdad (con el lexer de `tests/grafo.py`, que no confunde el texto de una
    cadena con una llamada). Lo que solo aparece dentro de una cadena es texto
    que el generador escribe para otros programas; lo que no aparece es codigo
    que el compilador no llama. Estructuralmente inalcanzable para esta
    metrica.
  * **`std/`**: la biblioteca la compilan los programas, no el compilador. El
    instrumento solo mide el binario del compilador; compilar y correr un
    programa que llame a `std/numero.t:dividir` deja a `dividir` en cero. Es
    una frontera del instrumento, no una funcion muerta.
  * **tablas generadas** (`xid.t`): datos, no logica.

    make cobertura
    python3 tests/cobertura.py                    # `rapido` y el banco
    python3 tests/cobertura.py RECHAZO ACEPTA     # solo esas secciones

Se instrumenta a `-O0`, que es donde gcov dice las lineas y las ramas exactas;
por eso la lista incluye tambien las que el optimizador quitaria, que el
compilador escribe igual porque emite todas las funciones de todos los modulos
que carga.

**No** se instrumentan los programas compilados: eso es otro trabajo. Por eso
lo de `std/` y lo de los programas de ejemplo se etiqueta, no se cuenta.

Necesita `gcov`, el de gcc: si no esta o no funciona, lo dice y sale. Todo lo
que escribe vive en `.cache/cobertura/`; no toca `tcodec` ni el arbol.
"""

import argparse
import glob
import gzip
import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grafo  # noqa: E402  (esta en este mismo directorio)

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNTIME = os.path.join(RAIZ, "runtime")
SEMILLA = os.path.join(RAIZ, "bootstrap", "tcodec.c")
SISTEMA = os.path.join(RAIZ, "ejemplos", "compilador", "lib", "sistema_tcodec.c")
ACOMPANANTES = [os.path.join(RAIZ, "runtime", "safestr.c"), SISTEMA,
                os.path.join(RAIZ, "std", "proceso.c"),
                os.path.join(RAIZ, "std", "terminal.c")]
DIR = os.path.join(RAIZ, ".cache", "cobertura")
OBJETO = os.path.join(DIR, "tcodec.o")
BINARIO = os.path.join(DIR, "tcodec")

# Las secciones rapidas: las mismas de `make rapido` (Makefile: RAPIDAS). Es el
# subconjunto acotado que se usa cuando no se le piden otras por nombre.
RAPIDAS = ["RECHAZO", "AVISA", "ACEPTA", "EQUIVALE", "GENERADOR", "SALIDA",
           "ARCHIVOS", "ABORTA", "MODULOS", "FORMATO", "LINEAS", "EJEMPLOS",
           "ESPECIFICACION", "CONGELADO"]


def correr(orden, **kw):
    return subprocess.run(orden, cwd=RAIZ, capture_output=True, text=True, **kw)


def construir():
    """El compilador de `bootstrap/tcodec.c`, con los contadores de gcov.

    Solo se instrumenta el C semilla: los acompanantes son runtime, no
    compilador, y se compilan sin cobertura."""
    # `.cache/cobertura` fue un archivo de la cobertura vieja, la de Python:
    # ahora es un directorio. Cualquiera de los dos se tira y se rehace.
    if os.path.isdir(DIR):
        shutil.rmtree(DIR, ignore_errors=True)
    elif os.path.exists(DIR):
        os.remove(DIR)
    os.makedirs(DIR)
    cc = os.environ.get("CC", "cc")
    base = ["-std=c17", "-O0", "-g", f"-I{RUNTIME}"]

    r = correr([cc, "--coverage", *base, "-c", SEMILLA, "-o", OBJETO])
    if r.returncode != 0:
        return f"no compila {os.path.relpath(SEMILLA, RAIZ)}:\n{r.stderr[:800]}"

    objetos = []
    for fuente in ACOMPANANTES:
        objeto = os.path.join(DIR, os.path.basename(fuente) + ".o")
        r = correr([cc, *base, "-c", fuente, "-o", objeto])
        if r.returncode != 0:
            return f"no compila {os.path.relpath(fuente, RAIZ)}:\n{r.stderr[:800]}"
        objetos.append(objeto)

    r = correr([cc, "--coverage", OBJETO, *objetos, "-o", BINARIO, "-lm"])
    if r.returncode != 0:
        return f"no enlaza el compilador con cobertura:\n{r.stderr[:800]}"
    return None


def correr_corpus(secciones):
    """La suite rapida contra el compilador instrumentado, y el banco."""
    for viejo in glob.glob(os.path.join(DIR, "*.gcda")):
        os.remove(viejo)
    entorno = dict(os.environ, TCODE_TCODEC=BINARIO, TCODE_EN_SERIE="1",
                   TCODE_RAIZ=RAIZ)
    r = correr([sys.executable, os.path.join("tests", "test_lenguaje.py"),
                *secciones], env=entorno)
    resumen = [x for x in r.stdout.splitlines() if x.strip()]
    if resumen:
        print(f"  suite: {resumen[-1]}")
    if r.returncode != 0:
        print("  AVISO: la suite no termino bien; la cobertura es parcial")
        print("    " + "\n    ".join(r.stdout.rstrip().splitlines()[-8:]))
        print("    " + r.stderr.rstrip()[-400:])

    casos = sorted(glob.glob(os.path.join(RAIZ, "bench", "*.t")))
    for fuente in casos:
        correr([BINARIO, os.path.relpath(fuente, RAIZ), "--mostrar-c"], env=entorno)
    print(f"  banco: {len(casos)} casos")
    return r.returncode == 0


def gcov_json():
    """El JSON de gcov, o `(None, motivo)` si no se puede."""
    gcov = shutil.which("gcov")
    if not gcov:
        return None, ("no esta gcov. Es parte de gcc: instala gcc o el paquete "
                      "que lo traiga, y vuelve a probar.")
    for viejo in glob.glob(os.path.join(DIR, "*.gcov.json.gz")):
        os.remove(viejo)
    r = subprocess.run([gcov, "-j", "-b", "-c", "-o", DIR, OBJETO], cwd=DIR,
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, f"gcov fallo:\n{r.stderr[:800]}"
    salidas = sorted(glob.glob(os.path.join(DIR, "*.gcov.json.gz")))
    if not salidas:
        return None, "gcov no escribio ningun .gcov.json.gz"
    datos = {"files": []}
    for salida in salidas:
        with gzip.open(salida, "rt", encoding="utf-8") as f:
            datos["files"].extend(json.load(f)["files"])
    return datos, None


def _vacio():
    return {"lineas": 0, "cubiertas": 0, "funciones": 0, "cubiertas_fn": 0,
            "ramas": 0, "tomadas": 0, "alcanzadas": 0, "dos_vias": 0,
            "ambos": 0, "sin_ejecutar": 0}


def _sumar(destino, fuente):
    for clave, valor in fuente.items():
        destino[clave] += valor


def _grupo(nombre):
    """Los tres bloques del binario: el compilador, la biblioteca y el resto."""
    if os.path.basename(nombre) == "xid.t":
        return "tablas generadas"
    if nombre.startswith(("ejemplos/compilador/", "ejemplos/lexer/")):
        return "tcodec (compilador y lexer)"
    if nombre.startswith("std/"):
        return "std/ (biblioteca)"
    return "arranque y runtime"


def _categoria(nombre):
    """De que clase es un fichero, para saber si su cero es un fallo o un limite.

    `compilador` es lo unico que el titular cuenta: codigo que el compilador
    lleva dentro. `runtime` es C generado; `std` es la biblioteca que compilan
    los programas; `tablas` son datos."""
    if nombre.startswith(("bootstrap/", "runtime/")):
        return "runtime"
    if nombre.startswith("std/"):
        return "std"
    if os.path.basename(nombre) == "xid.t":
        return "tablas"
    return "compilador"


def medir(datos):
    """Las cuentas que se resumen, y la lista de funciones sin ejecutar."""
    total = _vacio()
    por_fichero: dict[str, dict[str, int]] = {}
    nunca: list[tuple[str, int, str]] = []
    for f in datos["files"]:
        nombre = f["file"]
        if os.path.isabs(nombre):
            nombre = os.path.relpath(nombre, RAIZ)
        cuenta = _vacio()
        for fn in f.get("functions", []):
            cuenta["funciones"] += 1
            if fn["execution_count"] > 0:
                cuenta["cubiertas_fn"] += 1
            else:
                cuenta["sin_ejecutar"] += 1
                nunca.append((nombre, fn["start_line"], fn["name"]))
        for ln in f.get("lines", []):
            c = ln.get("count")
            if c is None:
                continue
            cuenta["lineas"] += 1
            if c > 0:
                cuenta["cubiertas"] += 1
            ramas = ln.get("branches") or []
            cuenta["ramas"] += len(ramas)
            cuenta["tomadas"] += sum(1 for b in ramas if b["count"] > 0)
            if c > 0:
                cuenta["alcanzadas"] += len(ramas)
            if len(ramas) == 2:
                cuenta["dos_vias"] += 1
                if all(b["count"] > 0 for b in ramas):
                    cuenta["ambos"] += 1
        por_fichero[nombre] = cuenta
        _sumar(total, cuenta)
    nunca.sort(key=lambda x: (x[0], x[1]))
    return total, por_fichero, nunca


# --- La clasificacion de lo que gcov ve a cero -----------------------------

def _llamados(fuente):
    """Los nombres que `fuente` llama de verdad (no los de una definicion ni
    los que solo estan dentro de una cadena)."""
    toks = grafo.tokenizar(fuente)
    fuera = set()
    for i, t in enumerate(toks):
        if t.tipo != "ident" or i + 1 >= len(toks):
            continue
        siguiente = toks[i + 1]
        if siguiente.tipo != "simbolo" or siguiente.valor != "(":
            continue
        if i >= 1 and toks[i - 1].tipo == "palabra" and toks[i - 1].valor == "fn":
            continue  # `fn nombre(`, una definicion
        if i >= 2 and toks[i - 1].tipo == "simbolo" and toks[i - 1].valor == "!" \
                and toks[i - 2].tipo == "palabra" and toks[i - 2].valor == "fn":
            continue  # `fn! nombre(`, tambien una definicion
        fuera.add(t.valor)
    return fuera


def _texto_de_cadenas(fuente):
    """Lo que dicen las cadenas de `fuente`, para ver quien solo las nombra."""
    return " ".join(t.valor for t in grafo.tokenizar(fuente) if t.tipo == "cadena")


def _menciona(nombre, texto):
    return re.search(r"\b" + re.escape(nombre) + r"\b", texto) is not None


def _escena():
    """Lo que hace falta para juzgar un cero, leido del repositorio."""
    comps = grafo.archivos()
    binario = grafo.en_binario()
    llamados = {rel: _llamados(grafo.leer(os.path.join(grafo.RAIZ, rel)))
                for rel in comps}
    cadenas = {rel: _texto_de_cadenas(grafo.leer(os.path.join(grafo.RAIZ, rel)))
               for rel in comps}
    return comps, binario, llamados, cadenas


def _quienes_llaman(nombre, comps, llamados):
    return sorted(rel for rel in comps if nombre in llamados[rel])


def clasificar(nunca):
    """Para cada funcion a cero, su categoria y su motivo, calculados.

    Devuelve `[(categoria, motivo, (fichero, linea, funcion))]`."""
    comps, binario, llamados, cadenas = _escena()
    todas = grafo.llamadas()
    salida = []
    for nombre, linea, fn in nunca:
        cat = _categoria(nombre)
        if cat == "runtime":
            llaman = _quienes_llaman(fn, comps, llamados)
            if llaman:
                motivo = "runtime emitido con llamadas reales en: " + ", ".join(llaman)
            elif any(_menciona(fn, cadenas[rel]) for rel in comps):
                motivo = "runtime emitido, solo texto que el generador escribe para otros programas"
            else:
                motivo = "runtime emitido, sin ninguna llamada en el codigo del compilador"
        elif cat == "std":
            llaman = _quienes_llaman(fn, comps, llamados)
            if llaman:
                motivo = ("fuera del alcance: la llaman programas que el instrumento no "
                          "ejecuta instrumentados (" + ", ".join(llaman) + ")")
            else:
                motivo = ("fuera del alcance: la biblioteca la compilan los programas; "
                          "sin llamadas en los `.t` cubiertos")
        elif cat == "tablas":
            motivo = "tablas generadas: datos, no logica"
        else:
            llamantes = sorted({(ca, cf) for (ca, cf, b, fb) in todas
                                if b == nombre and fb == fn})
            dentro = [(ca, cf) for ca, cf in llamantes
                      if ca in binario and (ca, cf) != (nombre, fn)]
            fuera = [(ca, cf) for ca, cf in llamantes if ca not in binario]
            if dentro:
                motivo = ("con llamada dentro del binario, pero no la ejecuta "
                          "este corpus (rama defensiva o camino no probado)")
            elif fuera:
                ficheros = ", ".join(sorted({ca for ca, _cf in fuera}))
                motivo = "solo la llama codigo que no entra en el binario: " + ficheros
            elif llamantes:
                motivo = "solo se llama a si misma: recursiva sin entrada"
            else:
                motivo = "sin ninguna llamada en los ficheros cubiertos"
        salida.append((cat, motivo, (nombre, linea, fn)))
    return salida


def centinela(parte, entero):
    if not entero:
        return "-"
    return f"{100.0 * parte / entero:.1f}%"


def _resumen(c):
    return (f"lineas {centinela(c['cubiertas'], c['lineas']):>6s} "
            f"({c['cubiertas']}/{c['lineas']})"
            f"   funciones {centinela(c['cubiertas_fn'], c['funciones']):>6s} "
            f"({c['cubiertas_fn']}/{c['funciones']})"
            f"   ramas {centinela(c['tomadas'], c['ramas']):>6s} "
            f"({c['tomadas']}/{c['ramas']})"
            f"   ambos sentidos {centinela(c['ambos'], c['dos_vias']):>6s}")


def _por_motivo(clasif, categoria):
    """`[(motivo, [(fichero, linea, funcion)])]`, agrupado y estable."""
    grupos: dict[str, list[tuple[str, int, str]]] = {}
    for cat, motivo, sitio in clasif:
        if cat == categoria:
            grupos.setdefault(motivo, []).append(sitio)
    return sorted(grupos.items())


def _listar(sitios, sangria):
    fichero = None
    for nombre, linea, fn in sitios:
        if nombre != fichero:
            fichero = nombre
            print(f"{sangria}{nombre}:")
        print(f"{sangria}  {linea:6d}  {fn}")


def _listar_compacto(sitios, sangria):
    for nombre, linea, fn in sitios:
        print(f"{sangria}{fn} ({nombre}:{linea})")


def imprimir(total, por_fichero, nunca):
    clasif = clasificar(nunca)
    print("\n=== cobertura de tcodec (gcov, -O0) ===")
    print(f"  total: {_resumen(total)}")
    print(f"  funciones que el instrumento no ve ejecutar: {total['sin_ejecutar']}")

    n_comp = sum(1 for c, _m, _s in clasif if c == "compilador")
    n_de_fuera = sum(1 for c, m, _s in clasif if c == "compilador"
                     and m.startswith("solo la llama codigo que no entra"))
    print(f"\n  DE VERDAD NO EJECUTADAS POR ESTE INSTRUMENTO "
          f"(`.t` del compilador): {n_comp}")
    print("  (el titular; lo de abajo es fuera del alcance del instrumento, "
          "y no se suma)")
    if n_de_fuera:
        print(f"  AVISO: {n_de_fuera} de esas {n_comp} NO estan muertas: las usan")
        print("  programas del repositorio, que el instrumento no ejecuta")
        print("  instrumentados (las de `solo la llama codigo que no entra en el")
        print("  binario`; `docs/llamadas.md` dice quien). No se borran.")
    for motivo, sitios in _por_motivo(clasif, "compilador"):
        print(f"    {motivo}: {len(sitios)}")
        _listar(sitios, "      ")

    fuera = [c for c, _m, _s in clasif if c != "compilador"]
    print(f"\n  FUERA DEL ALCANCE DEL INSTRUMENTO (no son fallos, no se suman): {len(fuera)}")
    print("    runtime emitido (bootstrap/ y runtime/: C generado): "
          f"{sum(1 for c, _m, _s in clasif if c == 'runtime')}")
    for motivo, sitios in _por_motivo(clasif, "runtime"):
        print(f"      {motivo}: {len(sitios)}")
        _listar_compacto(sitios, "        ")
    print("    std/ (la biblioteca la compilan los programas; "
          "el instrumento solo mide el compilador): "
          f"{sum(1 for c, _m, _s in clasif if c == 'std')}")
    for motivo, sitios in _por_motivo(clasif, "std"):
        print(f"      {motivo}: {len(sitios)}")
        _listar_compacto(sitios, "        ")
    tablas = sum(1 for c, _m, _s in clasif if c == "tablas")
    if tablas:
        print(f"    tablas generadas (xid.t): {tablas}")

    grupos: dict[str, dict[str, int]] = {}
    for nombre, cuenta in por_fichero.items():
        _sumar(grupos.setdefault(_grupo(nombre), _vacio()), cuenta)
    print("\n  por grupo:")
    for nombre in sorted(grupos):
        print(f"    {nombre:28s} {_resumen(grupos[nombre])}")

    print("\n  por fichero:")
    for nombre in sorted(por_fichero, key=lambda n: -por_fichero[n]["lineas"]):
        c = por_fichero[nombre]
        if not c["lineas"]:
            continue
        cola = ""
        if _categoria(nombre) == "runtime":
            cola = "   [fuera de alcance: runtime emitido]"
        elif _categoria(nombre) == "std":
            cola = "   [fuera de alcance: no se instrumenta el programa compilado]"
        print(f"    {nombre:45s} lineas {c['cubiertas']:5d}/{c['lineas']:<5d} "
              f"{centinela(c['cubiertas'], c['lineas']):>6s}   "
              f"sin ejecutar: {c['sin_ejecutar']}{cola}")


def main(argumentos):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("secciones", nargs="*",
                   help=f"secciones de la suite (por defecto: {' '.join(RAPIDAS)})")
    a = p.parse_args(argumentos)
    secciones = [s.upper() for s in a.secciones] or RAPIDAS

    print("construyendo tcodec con --coverage...")
    fallo = construir()
    if fallo:
        print(f"cobertura: {fallo}", file=sys.stderr)
        return 1

    print(f"corriendo {' '.join(secciones)} y el banco...")
    completa = correr_corpus(secciones)

    print("midiendo con gcov...")
    datos, fallo = gcov_json()
    if datos is None:
        print(f"cobertura: {fallo}", file=sys.stderr)
        return 1

    total, por_fichero, nunca = medir(datos)
    imprimir(total, por_fichero, nunca)
    return 0 if completa else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
