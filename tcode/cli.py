"""Compilador de Tcode: fuente .t -> C -> binario nativo."""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import threading

from tcode.lexer import ErrorLexico
from tcode.parser import parsear, ErrorSintactico
from tcode.modulos import cargar, ErrorDeModulo
from tcode.comprobador import comprobar
from tcode.generador import generar
from tcode.explicar import explicar
from tcode import nombres_c

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNTIME = os.path.join(RAIZ, "runtime")

VERSION = "0.1.0"
MARCA = "/* Generado por el compilador de Tcode. No editar a mano. */"


def _lo_generamos_nosotros(ruta):
    """True si ese .c lo escribio tcode: entonces se puede pisar."""
    try:
        with open(ruta, encoding="utf-8") as f:
            return MARCA in f.read(200)
    except OSError:
        return False


def _misma_ruta(ruta_a, ruta_b):
    """Reconoce la misma entrada incluso a traves de enlaces o `..`."""
    try:
        return os.path.samefile(ruta_a, ruta_b)
    except OSError:
        a = os.path.realpath(os.path.abspath(ruta_a))
        b = os.path.realpath(os.path.abspath(ruta_b))
        return a == b


def _modo_nuevo(ejecutable):
    """Los permisos que tendria un archivo recien creado: los de siempre menos
    el `umask`. `mkstemp` crea con 0600 y hay que decirlo a mano."""
    mascara = os.umask(0)
    os.umask(mascara)
    return (0o777 if ejecutable else 0o666) & ~mascara


def _escribir_atomico(ruta, contenido):
    """Escribe completo y solo entonces reemplaza el destino.

    Si la ruta es un enlace simbolico se escribe en lo que apunta: reemplazar
    el enlace lo convertiria en un archivo suelto y dejaria el original igual.
    """
    ruta = os.path.realpath(ruta)
    directorio = os.path.dirname(ruta)
    fd, temporal = tempfile.mkstemp(prefix=".tcode-", dir=directorio)
    try:
        try:
            modo = os.stat(ruta).st_mode & 0o777
        except OSError:
            modo = _modo_nuevo(ejecutable=False)
        os.fchmod(fd, modo)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            fd = -1
            f.write(contenido)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporal, ruta)
    except BaseException:
        if fd >= 0:
            os.close(fd)
        try:
            os.unlink(temporal)
        except OSError:
            pass
        raise


# El analisis es recursivo, como la gramatica: una suma de mil terminos es un
# arbol de mil niveles. Con la pila y el limite de Python por defecto eso
# reventaba con una traza; en un hilo con pila propia cabe de sobra. El parser
# no deja pasar un arbol de mas de LIMITE_HONDURA niveles, asi que esto basta.
PILA = 512 * 1024 * 1024
LIMITE_RECURSION = 200_000
_hondo = threading.local()


def _con_pila_honda(f, *args):
    if getattr(_hondo, "dentro", False):
        return f(*args)
    resultado = []

    def correr():
        _hondo.dentro = True
        try:
            resultado.append((True, f(*args)))
        except BaseException as exc:
            resultado.append((False, exc))

    anterior_pila = threading.stack_size(PILA)
    anterior_limite = sys.getrecursionlimit()
    sys.setrecursionlimit(max(anterior_limite, LIMITE_RECURSION))
    try:
        hilo = threading.Thread(target=correr)
        hilo.start()
        hilo.join()
    finally:
        threading.stack_size(anterior_pila)
        sys.setrecursionlimit(anterior_limite)
    bien, valor = resultado[0]
    if not bien:
        raise valor
    return valor


def compilar_a_c(fuente, archivo, devolver_comp=False, con_lineas=True):
    """Compila una fuente suelta, sin resolver `usar`. Lo usan los tests."""
    return _con_pila_honda(_compilar_a_c, fuente, archivo, devolver_comp,
                           con_lineas)


def _compilar_a_c(fuente, archivo, devolver_comp, con_lineas):
    arbol = parsear(fuente, archivo)
    nombres_c.renombrar(arbol, nombres_c.externas(arbol) | {"main"})
    return _compilar(arbol, archivo, devolver_comp, con_lineas=con_lineas)


def compilar_archivo(ruta, devolver_comp=False, con_lineas=True):
    """Compila un archivo resolviendo sus modulos."""
    return _con_pila_honda(_compilar_archivo, ruta, devolver_comp, con_lineas)


def _compilar_archivo(ruta, devolver_comp, con_lineas):
    mostrada = os.path.relpath(ruta)
    if mostrada.startswith(".."):
        mostrada = os.path.abspath(ruta)
    bonitos = {}
    arbol = cargar(ruta, bonitos)
    return _compilar(arbol, mostrada, devolver_comp, bonitos, con_lineas)


def _compilar(arbol, archivo, devolver_comp=False, nombres_bonitos=None,
              con_lineas=True):
    errores, comp = comprobar(arbol, archivo, nombres_bonitos)
    if errores:
        return (None, errores, comp) if devolver_comp else (None, errores)
    codigo = generar(arbol, comp, archivo, con_lineas)
    return (codigo, [], comp) if devolver_comp else (codigo, [])


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="tcode", description="Compilador del lenguaje Tcode")
    ap.add_argument("--version", action="version",
                    version=f"tcode {VERSION}")
    ap.add_argument("fuente", help="archivo .t")
    ap.add_argument("-o", "--salida", help="binario de salida")
    ap.add_argument("--formatear", action="store_true",
                    help="escribe el archivo con el formato canonico en la "
                         "salida y no compila nada")
    ap.add_argument("--escribir", action="store_true",
                    help="con --formatear, reescribe el archivo en su sitio")
    ap.add_argument("--sin-lineas", action="store_true",
                    help="no poner `#line` en el C generado. Por defecto se "
                         "ponen, y hacen que gdb, valgrind y los sanitizers "
                         "señalen el `.t` en vez del C intermedio; quitarlas "
                         "solo sirve para depurar el propio compilador")
    ap.add_argument("--emitir-c", action="store_true",
                    help="escribe el C generado y no invoca al compilador")
    ap.add_argument("--cc", default=os.environ.get("CC", "cc"))
    ap.add_argument("-O", "--optimizacion", default="2", choices=["0", "1", "2", "3", "s"],
                    help="nivel que se le pasa al compilador de C (por defecto 2). "
                         "Con aritmetica comprobada en bucles cerrados, 3 suele "
                         "recuperar lo que cuesta comprobar: los cuerpos crecen y "
                         "en -O2 dejan de integrarse")
    ap.add_argument("--solo-comprobar", action="store_true",
                    help="analiza y reporta errores, sin generar nada")
    ap.add_argument("--avisos-como-errores", action="store_true",
                    help="no compila si hay avisos")
    ap.add_argument("--sin-avisos", action="store_true",
                    help="no muestra los avisos")
    ap.add_argument("--explicar", action="store_true",
                    help="muestra lo que el compilador infirio: quien es "
                         "duenio de que, quien presta a quien, donde se libera "
                         "cada cosa y de donde sale cada vista")
    args = ap.parse_args(argv)
    try:
        return _ejecutar(args)
    except RecursionError:
        print(f"error: {args.fuente}: el programa anida demasiado hondo para "
              f"el compilador; parte las expresiones o los bloques en trozos",
              file=sys.stderr)
        return 1


def _ejecutar(args):
    if not os.path.isfile(args.fuente):
        print(f"tcode: no encuentro {args.fuente}", file=sys.stderr)
        return 2

    try:
        if args.formatear:
            from tcode.formato import formatear
            with open(args.fuente, encoding="utf-8") as f:
                fuente = f.read()
            salida = formatear(fuente, args.fuente)
            if args.escribir:
                if salida != fuente:
                    _escribir_atomico(args.fuente, salida)
                    print(f"formateado {args.fuente}")
            else:
                sys.stdout.write(salida)
            return 0

        codigo, errores, comp = compilar_archivo(args.fuente, devolver_comp=True,
                                                  con_lineas=not args.sin_lineas)
    except (ErrorLexico, ErrorSintactico, ErrorDeModulo) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"tcode: no se pudo leer: {exc}", file=sys.stderr)
        return 2

    avisos = comp.avisos if comp is not None else []

    if errores:
        for e in errores:
            print(f"error: {e}", file=sys.stderr)
        n = len(errores)
        print(f"\n{n} error{'es' if n != 1 else ''}. No se genero nada.",
              file=sys.stderr)
        return 1

    if avisos and not args.sin_avisos:
        for a in avisos:
            print(f"aviso: {a}", file=sys.stderr)
        if args.avisos_como_errores:
            n = len(avisos)
            print(f"\n{n} aviso{'s' if n != 1 else ''} tratado"
                  f"{'s' if n != 1 else ''} como error. No se genero nada.",
                  file=sys.stderr)
            return 1

    if args.explicar:
        print(explicar(comp, args.fuente))
        return 0

    if args.solo_comprobar:
        n = len(avisos)
        resumen = "sin errores" if not n else \
            f"sin errores, {n} aviso{'s' if n != 1 else ''}"
        print(f"{args.fuente}: {resumen}")
        return 0

    base = args.salida or os.path.splitext(args.fuente)[0]

    # Con --emitir-c el C es el producto y va junto al fuente. Sin la opcion
    # es un intermedio y va a un temporal: escribirlo junto al fuente pisaria
    # un `<base>.c` del usuario, y borrarlo despues lo destruiria.
    if args.emitir_c:
        ruta_c = base + ".c"
        if os.path.exists(ruta_c) and not _lo_generamos_nosotros(ruta_c):
            print(f"tcode: {ruta_c} ya existe y no lo genero tcode, asi que "
                  f"no lo piso. Usa -o para elegir otro nombre.",
                  file=sys.stderr)
            return 2
        try:
            _escribir_atomico(ruta_c, codigo)
        except OSError as exc:
            print(f"tcode: no se pudo escribir `{ruta_c}`: {exc}",
                  file=sys.stderr)
            return 2
        print(ruta_c)
        return 0

    # `-o fuente.t` y un fuente sin extension hacian que `cc -o` truncara el
    # programa original. Se comprueba despues de --emitir-c porque en ese modo
    # el producto real es `<base>.c`, no `base`.
    if _misma_ruta(base, args.fuente):
        print(f"tcode: la salida `{base}` es el propio archivo fuente; elige "
              "otro nombre con `-o`.", file=sys.stderr)
        return 2
    if os.path.splitext(base)[1] == ".t":
        print(f"tcode: la salida `{base}` parece un fuente `.t`; elige otro "
              "nombre para no sobrescribir codigo.", file=sys.stderr)
        return 2

    if "main" not in comp.funciones:
        print(f"tcode: {args.fuente} no tiene `fn main`, asi que no es un "
              f"programa. Si es un modulo, compila el archivo que lo usa; "
              f"si no, anade `fn main() -> usize {{ ... }}`.", file=sys.stderr)
        return 1

    tmp = tempfile.mkdtemp(prefix="tcode-")
    salida_tmp = None
    try:
        ruta_c = os.path.join(tmp, os.path.basename(base) + ".c")
        with open(ruta_c, "w", encoding="utf-8") as f:
            f.write(codigo)

        # Un `externo "algo.c"` no se incluye: se compila y se enlaza junto
        # al programa. Es la salida completa: lo que no cabe en el borde se
        # envuelve en dos lineas de C propias, sin salir de `tcode`.
        acompanan, faltan = [], []
        for f in comp.funciones.values():
            if not getattr(f, "externa", False):
                continue
            if not f.cabecera.endswith(".c"):
                continue
            junto = os.path.join(os.path.dirname(f.archivo or "."), f.cabecera)
            if junto in acompanan or junto in faltan:
                continue
            (acompanan if os.path.isfile(junto) else faltan).append(junto)
        if faltan:
            for x in faltan:
                print(f"tcode: `externo` pide `{x}` y ese archivo no esta.",
                      file=sys.stderr)
            return 2

        # El enlazador trabaja sobre un vecino temporal. Solo un resultado
        # completo reemplaza el binario anterior, y el rename no cruza discos.
        # Un `base` que es enlace se reemplaza en su destino, como el C.
        destino_bin = os.path.realpath(base)
        try:
            try:
                modo_salida = os.stat(destino_bin).st_mode & 0o777
            except OSError:
                modo_salida = _modo_nuevo(ejecutable=True)
            fd_salida, salida_tmp = tempfile.mkstemp(
                prefix=".tcode-bin-", dir=os.path.dirname(destino_bin))
            os.close(fd_salida)
        except OSError as exc:
            print(f"tcode: no se pudo preparar la salida `{base}`: {exc}",
                  file=sys.stderr)
            return 2

        orden = [args.cc, "-std=c17", f"-O{args.optimizacion}", "-Wall", "-Wextra",
                 f"-I{RUNTIME}", ruta_c, os.path.join(RUNTIME, "safestr.c"),
                 *acompanan,
                 "-o", salida_tmp,
                 # `raiz`, `piso` y compania viven en libm. En glibc moderna
                 # ya va dentro de libc, pero enlazarla no estorba y hace
                 # falta en todo lo demas.
                 "-lm"]
        r = subprocess.run(orden, capture_output=True, text=True)
        if r.returncode != 0:
            if any(getattr(f, "externa", False)
                   for f in comp.funciones.values()):
                print("tcode: el C generado no compilo. Con bloques "
                      "`externo` de por medio, lo mas probable es que una "
                      "firma no coincida con la de C.", file=sys.stderr)
            else:
                print("tcode: el C generado no compilo. Es un fallo del "
                      "compilador, no de tu programa.", file=sys.stderr)
            print(r.stderr, file=sys.stderr)
            return 1
        if r.stderr.strip():
            print(r.stderr, file=sys.stderr)
        try:
            os.chmod(salida_tmp, modo_salida)
            os.replace(salida_tmp, destino_bin)
            salida_tmp = None
        except OSError as exc:
            print(f"tcode: no se pudo instalar la salida `{base}`: {exc}",
                  file=sys.stderr)
            return 2
    finally:
        if salida_tmp is not None:
            try:
                os.unlink(salida_tmp)
            except OSError:
                pass
        shutil.rmtree(tmp, ignore_errors=True)

    print(base)
    return 0


if __name__ == "__main__":
    sys.exit(main())
