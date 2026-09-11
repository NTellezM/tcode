"""
Genera C a partir del arbol ya comprobado.

Dos cosas que el generador hace y el programador de C tendria que hacer a
mano, que son justo donde se equivoca:

  - insertar `ss_free` al cerrar cada bloque, para los `str` que no se
    movieron;
  - envolver `+`, `-` y `*` en comprobaciones de desbordamiento.
"""

import contextlib

from tcode.nodos import (
    Entero, Cadena, Booleano, Variable, Llamada, Binaria, Unaria,
    Campo, Indice, LiteralStruct, LiteralArreglo, Try, Sino, Falla,
    Declaracion, Asignacion, Si, Mientras, Retorno, ExprSentencia,
    Funcion, Struct, Para, Romper, Continuar,
)
from tcode.comprobador import (
    INTERNAS, UNIDAD, es_arreglo, partes_arreglo, elem_de, largo_arreglo,
    es_lista, elem_lista, es_mapa, partes_mapa, ORDENABLES,
)

TIPOS_C = {
    "str": "SafeString",
    "view": "SafeView",
    "usize": "size_t",
    "i64": "int64_t",
    "bool": "bool",
    None: "void",
    UNIDAD: "void",
}

CABECERA = r'''/* Generado por el compilador de Tcode. No editar a mano. */

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "safestr.h"

/* Este archivo lo escribe el compilador, no una persona. Un aviso sobre una
   variable que no se usa, o sobre `x == x`, habla del programa en Tcode y no
   de este C: apuntar aqui no le sirve a nadie. Que Tcode avise por su cuenta
   de esas cosas es otra conversacion, pero el ruido de gcc sobre codigo
   generado se apaga. */
#if defined(__GNUC__) || defined(__clang__)
#  pragma GCC diagnostic ignored "-Wtautological-compare"
#  pragma GCC diagnostic ignored "-Wtype-limits"
#endif

/* Un programa puede no usar todas las comprobaciones; eso no es un aviso
   que le sirva a nadie. */
#if defined(__GNUC__) || defined(__clang__)
#  define SS_LANG_QUIZA_SIN_USAR __attribute__((unused))
/* Un desbordamiento detiene el programa: el camino no vuelve y casi nunca se
   toma. Decirselo al compilador saca ese codigo del bucle caliente. */
#  define SS_LANG_NO_VUELVE  __attribute__((noreturn, cold, noinline))
#  define SS_LANG_RARO(c)    __builtin_expect(!!(c), 0)
#  define SS_LANG_SIEMPRE    __attribute__((always_inline)) inline
#else
#  define SS_LANG_QUIZA_SIN_USAR
#  define SS_LANG_NO_VUELVE
#  define SS_LANG_RARO(c)    (c)
#  define SS_LANG_SIEMPRE
#endif

/* Aritmetica comprobada: en Tcode el desbordamiento no es silencioso.
   Aborta diciendo donde, en vez de seguir con un valor equivocado. */
SS_LANG_QUIZA_SIN_USAR SS_LANG_NO_VUELVE
static void ss_lang_desborde_(const char* op, const char* archivo, int linea)
{
    fprintf(stderr, "%s:%d: desbordamiento en `%s`\n", archivo, linea, op);
    abort();
}

SS_LANG_QUIZA_SIN_USAR SS_LANG_NO_VUELVE
static void ss_lang_division_cero_(const char* archivo, int linea)
{
    fprintf(stderr, "%s:%d: division por cero\n", archivo, linea);
    abort();
}

/* Cada operacion se comprueba antes de confiar en ella.
 *
 * Donde el compilador ofrece los builtins de desbordamiento se usan: salen
 * como la instruccion aritmetica de siempre mas un salto condicional que
 * casi nunca se toma. La version portable que va debajo es correcta pero
 * cuesta: la de multiplicar necesita una division, que son decenas de
 * ciclos, y se nota en un bucle cerrado. */
#if defined(__GNUC__) || defined(__clang__)
#  define SS_LANG_HAY_BUILTINS 1
#endif

#define SS_LANG_DEFINIR_ARIT(sufijo, tipo, tmax, tmin)                        \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_suma_##sufijo(tipo a, tipo b, const char* ar, int ln)     \
{                                                                             \
    tipo r;                                                                   \
    if (ss_lang_suma_desborda_##sufijo(a, b, &r))                             \
        ss_lang_desborde_("+", ar, ln);                                       \
    return r;                                                                 \
}                                                                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_resta_##sufijo(tipo a, tipo b, const char* ar, int ln)    \
{                                                                             \
    tipo r;                                                                   \
    if (ss_lang_resta_desborda_##sufijo(a, b, &r))                            \
        ss_lang_desborde_("-", ar, ln);                                       \
    return r;                                                                 \
}                                                                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_mul_##sufijo(tipo a, tipo b, const char* ar, int ln)      \
{                                                                             \
    tipo r;                                                                   \
    if (ss_lang_mul_desborda_##sufijo(a, b, &r))                              \
        ss_lang_desborde_("*", ar, ln);                                       \
    return r;                                                                 \
}

#ifdef SS_LANG_HAY_BUILTINS

#  define ss_lang_suma_desborda_u(a, b, r)  __builtin_add_overflow((a), (b), (r))
#  define ss_lang_resta_desborda_u(a, b, r) __builtin_sub_overflow((a), (b), (r))
#  define ss_lang_mul_desborda_u(a, b, r)   __builtin_mul_overflow((a), (b), (r))
#  define ss_lang_suma_desborda_i(a, b, r)  __builtin_add_overflow((a), (b), (r))
#  define ss_lang_resta_desborda_i(a, b, r) __builtin_sub_overflow((a), (b), (r))
#  define ss_lang_mul_desborda_i(a, b, r)   __builtin_mul_overflow((a), (b), (r))

#else   /* portable: mas caro, sobre todo al multiplicar */

static int ss_lang_suma_desborda_u(size_t a, size_t b, size_t* r)
{ *r = a + b; return a > SIZE_MAX - b; }

static int ss_lang_resta_desborda_u(size_t a, size_t b, size_t* r)
{ *r = a - b; return a < b; }

static int ss_lang_mul_desborda_u(size_t a, size_t b, size_t* r)
{ *r = a * b; return a != 0 && b > SIZE_MAX / a; }

static int ss_lang_suma_desborda_i(int64_t a, int64_t b, int64_t* r)
{
    if ((b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b)) return 1;
    *r = a + b; return 0;
}

static int ss_lang_resta_desborda_i(int64_t a, int64_t b, int64_t* r)
{
    if ((b < 0 && a > INT64_MAX + b) || (b > 0 && a < INT64_MIN + b)) return 1;
    *r = a - b; return 0;
}

static int ss_lang_mul_desborda_i(int64_t a, int64_t b, int64_t* r)
{
    if (a != 0 && b != 0)
    {
        if (a > 0 ? (b > 0 ? a > INT64_MAX / b : b < INT64_MIN / a)
                  : (b > 0 ? a < INT64_MIN / b : a < INT64_MAX / b))
            return 1;
    }
    *r = a * b; return 0;
}

#endif

SS_LANG_DEFINIR_ARIT(u, size_t, SIZE_MAX, 0)
SS_LANG_DEFINIR_ARIT(i, int64_t, INT64_MAX, INT64_MIN)

#define SS_LANG_SUMA_U(a, b, ar, ln)  ss_lang_suma_u((a), (b), ar, ln)
#define SS_LANG_RESTA_U(a, b, ar, ln) ss_lang_resta_u((a), (b), ar, ln)
#define SS_LANG_MUL_U(a, b, ar, ln)   ss_lang_mul_u((a), (b), ar, ln)
#define SS_LANG_SUMA_I(a, b, ar, ln)  ss_lang_suma_i((a), (b), ar, ln)
#define SS_LANG_RESTA_I(a, b, ar, ln) ss_lang_resta_i((a), (b), ar, ln)
#define SS_LANG_MUL_I(a, b, ar, ln)   ss_lang_mul_i((a), (b), ar, ln)

#define SS_LANG_DIV(a, b, arch, ln) \
    (((b) == 0) ? (ss_lang_division_cero_(arch, ln), 0) : ((a) / (b)))

#define SS_LANG_MOD(a, b, arch, ln) \
    (((b) == 0) ? (ss_lang_division_cero_(arch, ln), 0) : ((a) % (b)))

/* Argumentos de la linea de ordenes.
   `argv` vive tanto como el proceso, asi que una vista suya nunca cuelga:
   por eso `argumento` devuelve `view` y no reserva nada. */
static int    ss_lang_argc_ = 0;
static char** ss_lang_argv_ = NULL;

SS_LANG_QUIZA_SIN_USAR
static size_t ss_lang_n_argumentos_(void)
{
    return (size_t) ss_lang_argc_;
}

SS_LANG_QUIZA_SIN_USAR
static SafeView ss_lang_argumento_(size_t i, const char* arch, int ln)
{
    if (SS_LANG_RARO(i >= (size_t) ss_lang_argc_))
    {
        fprintf(stderr, "%s:%d: no hay argumento %zu (se recibieron %d, "
                        "contando el nombre del programa)\n",
                arch, ln, i, ss_lang_argc_);
        abort();
    }
    return sv(ss_lang_argv_[i]);
}

/* Indexar fuera de rango no lee memoria ajena: detiene el programa. */
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE
static size_t ss_lang_indice_(size_t i, size_t n, const char* arch, int ln)
{
    if (SS_LANG_RARO(i >= n))
    {
        fprintf(stderr, "%s:%d: indice %zu fuera de rango (el arreglo tiene "
                        "%zu elemento%s)\n", arch, ln, i, n, n == 1 ? "" : "s");
        abort();
    }
    return i;
}

SS_LANG_QUIZA_SIN_USAR SS_LANG_NO_VUELVE
static void ss_lang_sin_memoria_(const char* archivo, int linea)
{
    fprintf(stderr, "%s:%d: no hay memoria suficiente\n", archivo, linea);
    abort();
}

SS_LANG_QUIZA_SIN_USAR
static SafeString ss_lang_texto_usize_(size_t valor, const char* ar, int ln)
{
    SafeString s = ss_new();
    if (!ss_appendf(&s, "%zu", valor)) ss_lang_sin_memoria_(ar, ln);
    return s;
}

SS_LANG_QUIZA_SIN_USAR
static SafeString ss_lang_texto_i64_(int64_t valor, const char* ar, int ln)
{
    SafeString s = ss_new();
    if (!ss_appendf(&s, "%lld", (long long) valor)) ss_lang_sin_memoria_(ar, ln);
    return s;
}

SS_LANG_QUIZA_SIN_USAR
static SafeString ss_lang_texto_view_(SafeView valor, const char* ar, int ln)
{
    SafeString s = ss_from_view(valor);
    if (!ss_ok(&s)) ss_lang_sin_memoria_(ar, ln);
    return s;
}

'''


def mangle(t):
    """Nombre C valido para un tipo: `[usize; 3]` -> `arr_usize_3`."""
    if es_arreglo(t):
        elem, n = partes_arreglo(t)
        return f"arr_{mangle(elem)}_{n}"
    if es_mapa(t):
        k, v = partes_mapa(t)
        return f"mapa_{mangle(k)}_{mangle(v)}"
    if es_lista(t):
        return f"lista_{mangle(elem_lista(t))}"
    return t


class Generador:
    def __init__(self, comprobador, archivo="<entrada>"):
        self.c = comprobador
        self.archivo = archivo
        self.lineas = []
        self.sangria = 0
        # pila de bloques: cada uno con los `str` declarados que hay que liberar
        self.pila = []
        self.tmp = 0
        # El generador lleva su propia tabla: los ambitos del comprobador ya
        # se cerraron cuando llegamos aqui.
        self.vars = []
        self.arreglos = {}     # tipo Tcode -> nombre del typedef en C
        self.listas = {}       # tipo Tcode -> nombre del typedef en C
        self.mapas = {}        # idem para mapa<K, V>
        self.resultados = {}   # tipo Tcode -> nombre del typedef de resultado
        self.usa_leer_archivo = False
        self.usa_escribir_archivo = False
        self.bucle = 0         # contador para variables de bucle de liberacion
        self.func = None       # funcion que se esta generando
        # Variables que se mueven en algun punto: llevan una bandera en
        # tiempo de ejecucion, porque el punto donde se liberan depende del
        # camino que tome el programa.
        self.con_bandera = set()
        self.pendientes = []
        # Profundidad de la pila de bloques donde empieza el bucle actual:
        # `break` y `continue` tienen que liberar desde ahi hacia dentro.
        self.bucles = []

    # ---------- utilidades ----------

    # ---------- tipos ----------

    def tipo_c(self, t):
        """Nombre C de un tipo. Los arreglos van envueltos en un struct.

        En C un arreglo desnudo no se puede asignar, ni pasar por valor, ni
        devolver: se degrada a puntero. Envolverlo en un struct le devuelve la
        semantica de valor que el lenguaje promete.
        """
        if es_arreglo(t):
            return self.registrar_arreglo(t)
        if es_mapa(t):
            return self.registrar_mapa(t)
        if es_lista(t):
            return self.registrar_lista(t)
        return TIPOS_C.get(t, t)

    def tipo_resultado(self, t):
        """El `T !` de Tcode es un struct: motivo == NULL significa que fue
        bien. Un solo puntero en vez de un booleano mas el valor."""
        clave = t if t not in (None, UNIDAD) else UNIDAD
        if clave not in self.resultados:
            sufijo = "unidad" if clave is UNIDAD else mangle(clave)
            self.resultados[clave] = f"ss_res_{sufijo}"
        return self.resultados[clave]

    def registrar_arreglo(self, t):
        if t not in self.arreglos:
            elem, _ = partes_arreglo(t)
            if es_arreglo(elem):
                self.registrar_arreglo(elem)
            self.arreglos[t] = f"ss_{mangle(t)}"
        return self.arreglos[t]

    def registrar_mapa(self, t):
        if t not in self.mapas:
            k, v = partes_mapa(t)
            self.tipo_c(k)
            self.tipo_c(v)
            # `claves` devuelve una lista de claves y `obtener` un `V !`:
            # los dos tipos tienen que existir antes de emitir los typedefs.
            self.registrar_lista(f"lista<{k}>")
            self.tipo_resultado(v)
            self.mapas[t] = f"ss_{mangle(t)}"
        return self.mapas[t]

    def registrar_lista(self, t):
        if t not in self.listas:
            elem = elem_lista(t)
            if es_lista(elem):
                self.registrar_lista(elem)
            self.listas[t] = f"ss_{mangle(t)}"
        return self.listas[t]

    def recolectar_tipos(self, decls):
        """Registra todos los tipos de arreglo que aparecen en el programa."""
        def mirar(t):
            if t and es_arreglo(t):
                self.registrar_arreglo(t)
            elif t and es_mapa(t):
                self.registrar_mapa(t)
            elif t and es_lista(t):
                self.registrar_lista(t)

        for d in decls:
            if isinstance(d, Struct):
                for c in d.campos:
                    mirar(c.tipo)
            elif isinstance(d, Funcion):
                mirar(d.retorno)
                if d.falible:
                    if d.retorno not in (None, UNIDAD):
                        mirar(d.retorno)
                    self.tipo_resultado(d.retorno)
                for p in d.params:
                    mirar(p.tipo)
                self._mirar_cuerpo(d.cuerpo, mirar)

        # Las llamadas falibles internas necesitan que exista su tipo de
        # resultado. Recorrer el AST evita meter soporte de archivos en el C
        # de programas que no lo usan.
        from dataclasses import fields, is_dataclass

        def recorrer(x):
            if isinstance(x, Llamada) and x.nombre == "leer_archivo":
                self.usa_leer_archivo = True
                self.tipo_resultado("str")
            if isinstance(x, Llamada) and x.nombre == "escribir_archivo":
                self.usa_escribir_archivo = True
                self.tipo_resultado(UNIDAD)
            if isinstance(x, (list, tuple)):
                for y in x:
                    recorrer(y)
            elif is_dataclass(x):
                for campo in fields(x):
                    recorrer(getattr(x, campo.name))

        recorrer(decls)

    def _mirar_cuerpo(self, sentencias, mirar):
        for s in sentencias:
            if isinstance(s, Declaracion):
                mirar(s.tipo)
            elif isinstance(s, Si):
                self._mirar_cuerpo(s.entonces, mirar)
                if s.sino:
                    self._mirar_cuerpo(s.sino, mirar)
            elif isinstance(s, Mientras):
                self._mirar_cuerpo(s.cuerpo, mirar)

    def orden_structs(self, structs):
        """Un struct por valor necesita el tamaño del que lleva dentro, asi
        que hay que definirlos en orden de dependencia."""
        por_nombre = {st.nombre: st for st in structs}
        listos, salida = set(), []

        def visitar(nombre):
            if nombre in listos or nombre not in por_nombre:
                return
            listos.add(nombre)
            for c in por_nombre[nombre].campos:
                t = c.tipo
                while es_arreglo(t):
                    t = elem_de(t)
                visitar(t)
            salida.append(por_nombre[nombre])

        for st in structs:
            visitar(st.nombre)
        return salida

    def emitir(self, texto=""):
        self.lineas.append("    " * self.sangria + texto if texto else "")

    def declarar(self, nombre, tipo, por_puntero=False, decl=None):
        self.vars[-1][nombre] = (tipo, por_puntero, decl)

    def buscar(self, nombre):
        for ambito in reversed(self.vars):
            if nombre in ambito:
                return ambito[nombre]
        return None

    def tipo_var(self, nombre):
        v = self.buscar(nombre)
        return v[0] if v else None

    def es_puntero(self, nombre):
        v = self.buscar(nombre)
        return bool(v and v[1])

    def fue_movida(self, nombre):
        """Si el valor se movio a otro sitio, aqui ya no somos duenios."""
        v = self.buscar(nombre)
        return bool(v and v[2] is not None and getattr(v[2], "movida", False))

    def ref(self, nombre):
        """Como referirse a `nombre` cuando se necesita un SafeString*."""
        return nombre if self.es_puntero(nombre) else f"&{nombre}"

    def nuevo_tmp(self):
        self.tmp += 1
        return f"ss_tmp{self.tmp}"

    def arch(self, nodo=None):
        a = (getattr(nodo, "archivo", "") or self.archivo) if nodo else self.archivo
        return '"' + a.replace("\\", "\\\\").replace('"', '\\"') + '"'

    # ---------- programa ----------

    def generar(self, decls):
        structs = [d for d in decls if isinstance(d, Struct)]
        funciones = [d for d in decls if isinstance(d, Funcion)]

        self.lineas.append(CABECERA)
        self.recolectar_tipos(decls)

        # Las listas solo guardan un puntero a sus elementos. Declarar antes
        # los nombres de struct permite `lista<Nodo>` incluso dentro de Nodo.
        for st in structs:
            self.lineas.append(f"typedef struct {st.nombre} {st.nombre};")
        if structs:
            self.lineas.append("")

        # Tipos de lista, de dentro hacia fuera. El elemento puede estar aun
        # incompleto porque aqui solo aparece detras de un puntero.
        for t in sorted(self.listas, key=lambda x: x.count("lista<")):
            elem = elem_lista(t)
            self.lineas.append(
                f"typedef struct {{ {self.tipo_c(elem)}* e; size_t length; "
                f"size_t capacity; }} {self.listas[t]};")
        if self.listas:
            self.lineas.append("")

        # Tabla de direccionamiento abierto con sondeo lineal. Sin borrado en
        # v0, asi que no hacen falta lapidas: una celda con clave vacia es una
        # celda libre y la busqueda puede parar ahi.
        for t, nombre in self.mapas.items():
            k, v = partes_mapa(t)
            self.lineas.append(
                f"typedef struct {{ {self.tipo_c(k)}* claves; "
                f"{self.tipo_c(v)}* valores; size_t largo; "
                f"size_t capacidad; }} {nombre};")
        if self.mapas:
            self.lineas.append("")

        # structs, en orden de dependencia
        for st in self.orden_structs(structs):
            self.lineas.append(f"struct {st.nombre}")
            self.lineas.append("{")
            for c in st.campos:
                self.lineas.append(f"    {self.tipo_c(c.tipo)} {c.nombre};")
            self.lineas.append("};")
            self.lineas.append("")

        # envoltorios de arreglo, de dentro hacia fuera
        for t in sorted(self.arreglos, key=lambda x: x.count("[")):
            elem, n = partes_arreglo(t)
            self.lineas.append(
                f"typedef struct {{ {self.tipo_c(elem)} e[{n}]; }} "
                f"{self.arreglos[t]};")
        if self.arreglos:
            self.lineas.append("")

        for t, nombre in self.resultados.items():
            if t is UNIDAD or t == UNIDAD:
                self.lineas.append(
                    f"typedef struct {{ const char* motivo; }} {nombre};")
            else:
                self.lineas.append(
                    f"typedef struct {{ const char* motivo; "
                    f"{self.tipo_c(t)} valor; }} {nombre};")
        if self.resultados:
            self.lineas.append("")

        if self.usa_escribir_archivo:
            res = self.tipo_resultado(UNIDAD)
            self.lineas.extend([
                "SS_LANG_QUIZA_SIN_USAR",
                f"static {res} ss_lang_escribir_archivo_(SafeView ruta, SafeView datos)",
                "{",
                "    if (ruta.len != 0 && memchr(ruta.ptr, 0, ruta.len) != NULL)",
                f'        return ({res}){{ .motivo = "la ruta contiene un byte cero" }};',
                "",
                "    SafeString copia = ss_from_view(ruta);",
                "    if (!ss_ok(&copia))",
                "    {",
                "        ss_free(&copia);",
                f'        return ({res}){{ .motivo = "sin memoria para la ruta" }};',
                "    }",
                '    FILE* f = fopen(ss_cstr(&copia), "wb");',
                "    ss_free(&copia);",
                "    if (f == NULL)",
                f'        return ({res}){{ .motivo = "no se pudo abrir el archivo para escribir" }};',
                "",
                "    bool fallo = false;",
                "    if (datos.len != 0)",
                "        fallo = fwrite(datos.ptr, 1, datos.len, f) != datos.len;",
                "    if (fclose(f) != 0) fallo = true;",
                "    if (fallo)",
                f'        return ({res}){{ .motivo = "fallo al escribir el archivo" }};',
                f"    return ({res}){{ .motivo = NULL }};",
                "}",
                "",
            ])

        if self.usa_leer_archivo:
            res = self.tipo_resultado("str")
            self.lineas.extend([
                "SS_LANG_QUIZA_SIN_USAR",
                f"static {res} ss_lang_leer_archivo_(SafeView ruta)",
                "{",
                "    if (ruta.len != 0 && memchr(ruta.ptr, 0, ruta.len) != NULL)",
                f'        return ({res}){{ .motivo = "la ruta contiene un byte cero" }};',
                "    SafeString nombre = ss_from_view(ruta);",
                "    if (!ss_ok(&nombre))",
                "    {",
                "        ss_free(&nombre);",
                f'        return ({res}){{ .motivo = "sin memoria para la ruta" }};',
                "    }",
                "    FILE* f = fopen(ss_cstr(&nombre), \"rb\");",
                "    ss_free(&nombre);",
                "    if (f == NULL)",
                f'        return ({res}){{ .motivo = "no se pudo abrir el archivo" }};',
                "    SafeString contenido = ss_new();",
                "    unsigned char bloque[8192];",
                "    size_t n;",
                "    while ((n = fread(bloque, 1, sizeof(bloque), f)) != 0)",
                "    {",
                "        if (!ss_append_len(&contenido, (const char*) bloque, n))",
                "        {",
                "            fclose(f);",
                "            ss_free(&contenido);",
                f'            return ({res}){{ .motivo = "sin memoria al leer el archivo" }};',
                "        }",
                "    }",
                "    bool fallo_lectura = ferror(f) != 0;",
                "    if (fclose(f) != 0) fallo_lectura = true;",
                "    if (fallo_lectura)",
                "    {",
                "        ss_free(&contenido);",
                f'        return ({res}){{ .motivo = "fallo al leer el archivo" }};',
                "    }",
                f"    return ({res}){{ .motivo = NULL, .valor = contenido }};",
                "}",
                "",
            ])

        # Una funcion de crecimiento por cada T concreto. No hay `void*` en
        # la interfaz generada: el compilador de C tambien comprueba el tipo.
        for t, nombre in self.listas.items():
            elem = elem_lista(t)
            tc_elem = self.tipo_c(elem)
            self.lineas.extend([
                "SS_LANG_QUIZA_SIN_USAR",
                f"static void ss_push_{mangle(t)}({nombre}* p, {tc_elem} valor,",
                "        const char* archivo, int linea)",
                "{",
                "    if (p->length == p->capacity)",
                "    {",
                "        if (p->length == SIZE_MAX)",
                "            ss_lang_sin_memoria_(archivo, linea);",
                "        size_t nueva = p->capacity == 0 ? 8 : p->capacity;",
                "        if (nueva < p->length + 1)",
                "        {",
                "            nueva = nueva > SIZE_MAX / 2 ? SIZE_MAX : nueva * 2;",
                "            if (nueva < p->length + 1) nueva = p->length + 1;",
                "        }",
                "        if (nueva > SIZE_MAX / sizeof(*p->e))",
                "            ss_lang_sin_memoria_(archivo, linea);",
                "        void* memoria = realloc(p->e, nueva * sizeof(*p->e));",
                "        if (memoria == NULL) ss_lang_sin_memoria_(archivo, linea);",
                f"        p->e = ({tc_elem}*) memoria;",
                "        p->capacity = nueva;",
                "    }",
                "    p->e[p->length++] = valor;",
                "}",
                "",
            ])

        # Ordenacion por cada lista<T> con orden natural. Se apoya en qsort
        # de la biblioteca estandar: el comparador es concreto por tipo, asi
        # que el compilador de C tambien lo comprueba.
        for t, nombre in self.listas.items():
            elem = elem_lista(t)
            if elem not in ORDENABLES:
                continue
            tc_elem = self.tipo_c(elem)
            m = mangle(t)
            if elem == "str":
                cuerpo = ["    return ss_cmp((const SafeString*) a, "
                          "(const SafeString*) b);"]
            else:
                cuerpo = [
                    f"    {tc_elem} x = *(const {tc_elem}*) a;",
                    f"    {tc_elem} y = *(const {tc_elem}*) b;",
                    "    return (x > y) - (x < y);",
                ]
            self.lineas.extend([
                "SS_LANG_QUIZA_SIN_USAR",
                f"static int ss_cmp_{m}(const void* a, const void* b)",
                "{",
                *cuerpo,
                "}",
                "",
                "SS_LANG_QUIZA_SIN_USAR",
                f"static void ss_ordenar_{m}({nombre}* p)",
                "{",
                "    if (p->length > 1)",
                f"        qsort(p->e, p->length, sizeof(*p->e), ss_cmp_{m});",
                "}",
                "",
            ])

        # Un juego de funciones por cada mapa<K, V> concreto.
        for t, nombre in self.mapas.items():
            k, v = partes_mapa(t)
            m = mangle(t)
            tc_k, tc_v = self.tipo_c(k), self.tipo_c(v)
            lista_k = self.tipo_c(f"lista<{k}>")
            res_v = self.tipo_resultado(v)
            self.lineas.extend([
                "SS_LANG_QUIZA_SIN_USAR",
                f"static size_t ss_mapa_sitio_{m}(const {nombre}* p, SafeView clave)",
                "{",
                "    /* La capacidad es potencia de dos, asi que el resto es",
                "       una mascara. Sondeo lineal: bueno con la cache y sin",
                "       lapidas, porque en v0 no se borra. */",
                "    size_t mascara = p->capacidad - 1;",
                "    size_t i = (size_t) sv_hash(clave) & mascara;",
                "    while (p->claves[i].data != NULL)",
                "    {",
                "        if (sv_equals(ss_view(&p->claves[i]), clave)) return i;",
                "        i = (i + 1) & mascara;",
                "    }",
                "    return i;   /* celda libre: aqui iria */",
                "}",
                "",
                "SS_LANG_QUIZA_SIN_USAR",
                f"static void ss_mapa_crecer_{m}({nombre}* p, const char* archivo, int linea)",
                "{",
                "    size_t nueva = p->capacidad == 0 ? 16 : p->capacidad * 2;",
                "    if (nueva < p->capacidad) ss_lang_sin_memoria_(archivo, linea);",
                f"    if (nueva > SIZE_MAX / sizeof({tc_k})",
                f"        || nueva > SIZE_MAX / sizeof({tc_v}))",
                "        ss_lang_sin_memoria_(archivo, linea);",
                "",
                f"    {nombre} nuevo;",
                f"    nuevo.claves = ({tc_k}*) calloc(nueva, sizeof({tc_k}));",
                f"    nuevo.valores = ({tc_v}*) malloc(nueva * sizeof({tc_v}));",
                "    if (nuevo.claves == NULL || nuevo.valores == NULL)",
                "    {",
                "        free(nuevo.claves); free(nuevo.valores);",
                "        ss_lang_sin_memoria_(archivo, linea);",
                "    }",
                "    nuevo.largo = p->largo;",
                "    nuevo.capacidad = nueva;",
                "",
                "    /* Se reubican las claves tal cual: nadie copia texto. */",
                "    for (size_t i = 0; i < p->capacidad; i++)",
                "    {",
                "        if (p->claves[i].data == NULL) continue;",
                f"        size_t j = ss_mapa_sitio_{m}(&nuevo, ss_view(&p->claves[i]));",
                "        nuevo.claves[j] = p->claves[i];",
                "        nuevo.valores[j] = p->valores[i];",
                "    }",
                "    free(p->claves); free(p->valores);",
                "    *p = nuevo;",
                "}",
                "",
                "SS_LANG_QUIZA_SIN_USAR",
                f"static void ss_mapa_poner_{m}({nombre}* p, SafeView clave, {tc_v} valor,",
                "        const char* archivo, int linea)",
                "{",
                "    /* Se crece al 70% de ocupacion: por encima, el sondeo",
                "       lineal empieza a formar cadenas largas. */",
                "    if (p->capacidad == 0 || (p->largo + 1) * 10 >= p->capacidad * 7)",
                f"        ss_mapa_crecer_{m}(p, archivo, linea);",
                "",
                f"    size_t i = ss_mapa_sitio_{m}(p, clave);",
                "    if (p->claves[i].data != NULL)",
                "    {",
                "        p->valores[i] = valor;   /* ya estaba: se reemplaza */",
                "        return;",
                "    }",
                "    p->claves[i] = ss_from_view(clave);",
                "    if (!ss_ok(&p->claves[i])) ss_lang_sin_memoria_(archivo, linea);",
                "    p->valores[i] = valor;",
                "    p->largo++;",
                "}",
                "",
                "SS_LANG_QUIZA_SIN_USAR",
                f"static bool ss_mapa_tiene_{m}(const {nombre}* p, SafeView clave)",
                "{",
                "    if (p->capacidad == 0) return false;",
                f"    return p->claves[ss_mapa_sitio_{m}(p, clave)].data != NULL;",
                "}",
                "",
                "SS_LANG_QUIZA_SIN_USAR",
                f"static {res_v} ss_mapa_obtener_{m}(const {nombre}* p, SafeView clave)",
                "{",
                "    if (p->capacidad == 0)",
                f'        return ({res_v}){{ .motivo = "la clave no esta en el mapa" }};',
                f"    size_t i = ss_mapa_sitio_{m}(p, clave);",
                "    if (p->claves[i].data == NULL)",
                f'        return ({res_v}){{ .motivo = "la clave no esta en el mapa" }};',
                f"    return ({res_v}){{ .motivo = NULL, .valor = p->valores[i] }};",
                "}",
                "",
                "SS_LANG_QUIZA_SIN_USAR",
                f"static {lista_k} ss_mapa_claves_{m}(const {nombre}* p,",
                "        const char* archivo, int linea)",
                "{",
                f"    {lista_k} salida = {{ NULL, 0, 0 }};",
                "    for (size_t i = 0; i < p->capacidad; i++)",
                "    {",
                "        if (p->claves[i].data == NULL) continue;",
                f"        {tc_k} copia = ss_clone(&p->claves[i]);",
                "        if (!ss_ok(&copia)) ss_lang_sin_memoria_(archivo, linea);",
                f"        ss_push_{mangle('lista<' + k + '>')}(&salida, copia, archivo, linea);",
                "    }",
                "    return salida;",
                "}",
                "",
                "SS_LANG_QUIZA_SIN_USAR",
                f"static bool ss_mapa_quitar_{m}({nombre}* p, SafeView clave)",
                "{",
                "    if (p->capacidad == 0) return false;",
                "    size_t mascara = p->capacidad - 1;",
                f"    size_t i = ss_mapa_sitio_{m}(p, clave);",
                "    if (p->claves[i].data == NULL) return false;",
                "",
                "    ss_free(&p->claves[i]);",
                "    p->claves[i] = ss_new();",
                "    p->largo--;",
                "",
                "    /* Sin lapidas: se cierra el hueco arrastrando hacia atras",
                "       las entradas del mismo grupo que quedarian inalcanzables.",
                "       Es lo que permite que la busqueda pueda parar en la",
                "       primera celda libre. */",
                "    size_t j = i;",
                "    for (;;)",
                "    {",
                "        j = (j + 1) & mascara;",
                "        if (p->claves[j].data == NULL) break;",
                "        size_t k = (size_t) sv_hash(ss_view(&p->claves[j])) & mascara;",
                "        bool mover = (i <= j) ? (k <= i || k > j)",
                "                              : (k <= i && k > j);",
                "        if (mover)",
                "        {",
                "            p->claves[i] = p->claves[j];",
                "            p->valores[i] = p->valores[j];",
                "            p->claves[j] = ss_new();",
                "            i = j;",
                "        }",
                "    }",
                "    return true;",
                "}",
                "",
                "SS_LANG_QUIZA_SIN_USAR",
                f"static void ss_mapa_libre_{m}({nombre}* p)",
                "{",
                "    for (size_t i = 0; i < p->capacidad; i++)",
                "        if (p->claves[i].data != NULL) ss_free(&p->claves[i]);",
                "    free(p->claves); free(p->valores);",
                "    p->claves = NULL; p->valores = NULL;",
                "    p->largo = 0; p->capacidad = 0;",
                "}",
                "",
            ])

        # Prototipos primero: dos structs pueden referirse de forma finita a
        # traves de listas (A contiene lista<B>, B contiene lista<A>).
        for st in self.orden_structs(structs):
            if self.c.posee(st.nombre):
                self.lineas.append(f"static void ss_drop_{st.nombre}({st.nombre}* p);")
        if any(self.c.posee(st.nombre) for st in structs):
            self.lineas.append("")

        # liberadores de los structs que poseen memoria
        for st in self.orden_structs(structs):
            if not self.c.posee(st.nombre):
                continue
            self.lineas.append(f"static void ss_drop_{st.nombre}({st.nombre}* p)")
            self.lineas.append("{")
            self.sangria = 1
            marca = len(self.lineas)
            for c in st.campos:
                self.liberacion(f"p->{c.nombre}", c.tipo)
            self.lineas.extend(self.lineas[marca:marca])
            self.sangria = 0
            self.lineas.append("}")
            self.lineas.append("")

        for f in funciones:
            if f.nombre != "main":
                self.lineas.append(self.prototipo(f) + ";")
        self.lineas.append("")

        for f in funciones:
            self.funcion(f)
            self.lineas.append("")

        return "\n".join(self.lineas)

    def prototipo(self, f: Funcion):
        if f.nombre == "main" and not f.falible:
            return "int main(int argc, char** argv)"
        params = []
        for p in f.params:
            tc = self.tipo_c(p.tipo)
            if p.mutable:
                params.append(f"SS_LANG_QUIZA_SIN_USAR {tc}* {p.nombre}")
            elif p.compartido:
                # solo lectura: el `const` lo documenta y lo hace cumplir el
                # propio compilador de C
                params.append(f"SS_LANG_QUIZA_SIN_USAR const {tc}* {p.nombre}")
            else:
                params.append(f"SS_LANG_QUIZA_SIN_USAR {tc} {p.nombre}")
        if f.falible:
            ret = self.tipo_resultado(f.retorno)
        elif f.retorno in (None, UNIDAD):
            ret = "void"
        else:
            ret = self.tipo_c(f.retorno)
        nombre = "ss_main_" if f.nombre == "main" else f.nombre
        return f"{ret} {nombre}({', '.join(params) or 'void'})"

    def funcion(self, f: Funcion):
        self.func = f
        self.emitir(self.prototipo(f))
        self.emitir("{")
        self.sangria += 1
        if f.nombre == "main" and not f.falible:
            self.emitir("ss_lang_argc_ = argc;")
            self.emitir("ss_lang_argv_ = argv;")
        # los parametros `str` por valor son propiedad de la funcion: se liberan
        propios = [p.nombre for p in f.params
                   if self.c.posee(p.tipo) and not p.prestado]
        self.pila.append(list(propios))
        self.vars.append({})
        self.con_bandera = set()
        for p in f.params:
            self.declarar(p.nombre, p.tipo, p.prestado, decl=p)
        for p in f.params:
            if p.movida and self.c.posee(p.tipo) and not p.prestado:
                self.con_bandera.add(p.nombre)
                self.emitir(f"bool ss_vivo_{p.nombre} = true;")

        for s in f.cuerpo:
            self.sentencia(s)

        # Si el cuerpo ya termino en `return`, todo lo que siga es codigo
        # muerto: el `return` se encargo de liberar.
        if not self._termina_en_retorno(f.cuerpo):
            self.liberar_bloque(self.pila[-1])
            if f.falible:
                self.emitir(f"return ({self.tipo_resultado(f.retorno)})"
                            f"{{ .motivo = NULL }};")
            elif f.nombre == "main":
                self.emitir("return 0;")
        self.pila.pop()
        self.vars.pop()
        self.sangria -= 1
        self.emitir("}")

        # `main` falible: un envoltorio que informa y devuelve codigo distinto
        # de cero, para que el fallo no se pierda al salir del programa.
        if f.nombre == "main" and f.falible:
            self.emitir("")
            self.emitir("int main(int argc, char** argv)")
            self.emitir("{")
            self.sangria += 1
            self.emitir("ss_lang_argc_ = argc;")
            self.emitir("ss_lang_argv_ = argv;")
            self.emitir(f"{self.tipo_resultado(f.retorno)} r = ss_main_();")
            self.emitir("if (r.motivo != NULL)")
            self.emitir("{")
            self.sangria += 1
            self.emitir(r'fprintf(stderr, "error: %s\n", r.motivo);')
            self.emitir("return 1;")
            self.sangria -= 1
            self.emitir("}")
            self.emitir("return (int) r.valor;"
                        if f.retorno not in (None, UNIDAD) else "return 0;")
            self.sangria -= 1
            self.emitir("}")
        self.func = None

    # ---------- liberacion automatica ----------

    def liberacion(self, expr_c, tipo):
        """Emite lo que haga falta para devolver la memoria de `expr_c`."""
        if tipo == "str":
            self.emitir(f"ss_free(&{expr_c});")
            return

        if es_mapa(tipo):
            self.emitir(f"ss_mapa_libre_{mangle(tipo)}(&{expr_c});")
            return

        if es_lista(tipo):
            elem = elem_lista(tipo)
            if self.c.posee(elem):
                self.bucle += 1
                i = f"ss_i{self.bucle}"
                self.emitir(f"for (size_t {i} = 0; {i} < {expr_c}.length; {i}++)")
                self.emitir("{")
                self.sangria += 1
                self.liberacion(f"{expr_c}.e[{i}]", elem)
                self.sangria -= 1
                self.emitir("}")
            self.emitir(f"free({expr_c}.e);")
            self.emitir(f"{expr_c}.e = NULL;")
            self.emitir(f"{expr_c}.length = 0;")
            self.emitir(f"{expr_c}.capacity = 0;")
            return

        if es_arreglo(tipo):
            elem, n = partes_arreglo(tipo)
            if not self.c.posee(elem):
                return
            self.bucle += 1
            i = f"ss_i{self.bucle}"
            self.emitir(f"for (size_t {i} = 0; {i} < {n}; {i}++)")
            self.emitir("{")
            self.sangria += 1
            self.liberacion(f"{expr_c}.e[{i}]", elem)
            self.sangria -= 1
            self.emitir("}")
            return

        if tipo in self.c.structs and self.c.posee(tipo):
            self.emitir(f"ss_drop_{tipo}(&{expr_c});")

    def liberar_bloque(self, nombres, excepto=None):
        excepciones = excepto if isinstance(excepto, set) else {excepto}
        for n in reversed(nombres):
            if n in excepciones:
                continue
            if n in self.con_bandera:
                # se movio en algun camino: lo decide la bandera
                self.emitir(f"if (ss_vivo_{n})")
                self.emitir("{")
                self.sangria += 1
                self.liberacion(n, self.tipo_var(n))
                self.sangria -= 1
                self.emitir("}")
                continue
            if self.fue_movida(n):
                continue
            self.liberacion(n, self.tipo_var(n))

    def liberar_todo(self, excepto=None):
        for marco in reversed(self.pila):
            self.liberar_bloque(marco, excepto)

    @staticmethod
    def movidas_en(nodo):
        """Variables cuya propiedad entrega esta expresion."""
        from dataclasses import fields, is_dataclass
        nombres = set()

        def recorrer(x):
            if isinstance(x, Variable) and getattr(x, "mueve", False):
                nombres.add(x.nombre)
            if isinstance(x, (list, tuple)):
                for y in x:
                    recorrer(y)
            elif is_dataclass(x):
                for campo in fields(x):
                    recorrer(getattr(x, campo.name))

        recorrer(nodo)
        return nombres

    # ---------- sentencias ----------

    def bloque(self, sentencias):
        self.emitir("{")
        self.sangria += 1
        self.pila.append([])
        self.vars.append({})
        for s in sentencias:
            self.sentencia(s)
        if not self._termina_en_retorno(sentencias):
            self.liberar_bloque(self.pila[-1])
        self.pila.pop()
        self.vars.pop()
        self.sangria -= 1
        self.emitir("}")

    @staticmethod
    def _termina_en_retorno(sentencias):
        return bool(sentencias) and isinstance(sentencias[-1], Retorno)

    # ---------- propiedad que depende del camino ----------
    #
    # Un valor puede entregarse en unos caminos y no en otros: la alternativa
    # de un `sino`, o una variable que se mueve despues de un `falla`. Para
    # esos casos el generador lleva una bandera en tiempo de ejecucion y la
    # liberacion pregunta por ella.
    #
    # El invariante es uno solo:
    #
    #     generar el uso que entrega una variable con bandera OBLIGA a apagar
    #     esa bandera en el mismo camino, antes de salir de el.
    #
    # `expr` lo anota al generar el uso (no sabe donde esta); quien abre un
    # camino lo vacia antes de cerrarlo. Si aparece una construccion nueva que
    # abre caminos y no vacia, `revisar_banderas` lo dice en vez de dejar una
    # fuga silenciosa.

    def _apagar_ahora(self):
        """Apaga ya lo pendiente. Lo usa `return`, que no vuelve."""
        for n in dict.fromkeys(self.pendientes):
            self.emitir(f"ss_vivo_{n} = false;")
        self.pendientes = []

    @contextlib.contextmanager
    def camino(self):
        """Abre un camino de ejecucion.

        Lo que se entregue dentro se apaga aqui dentro, antes de cerrarlo. Se
        hace con un `with` a proposito: una construccion nueva que abra
        caminos no puede olvidarse del vaciado, porque no hay nada que
        recordar. Es la diferencia entre una regla y una costumbre.
        """
        anteriores = self.pendientes
        self.pendientes = []
        try:
            yield
        finally:
            for n in dict.fromkeys(self.pendientes):
                self.emitir(f"ss_vivo_{n} = false;")
            self.pendientes = anteriores

    def sentencia(self, s):
        with self.camino():
            self._sentencia(s)

    def _sentencia(self, s):
        if isinstance(s, Declaracion):
            tc = self.tipo_c(s.tipo)
            # Una variable declarada y no usada es legitima en Tcode; el aviso
            # de gcc apuntaria a este C, que el usuario no escribio.
            self.emitir(f"SS_LANG_QUIZA_SIN_USAR {tc} {s.nombre} = "
                        f"{self.expr(s.valor, s.tipo)};")
            self.declarar(s.nombre, s.tipo, decl=s)
            if self.c.posee(s.tipo):
                self.pila[-1].append(s.nombre)
                if s.movida:
                    self.con_bandera.add(s.nombre)
                    self.emitir(f"bool ss_vivo_{s.nombre} = true;")
            return

        if isinstance(s, Asignacion):
            destino = self.lugar(s.lugar)
            tipo = self._tipo_de(s.lugar)
            if self.c.posee(tipo):
                # el valor viejo se pierde: devolverlo antes de pisarlo
                self.liberacion(destino, tipo)
            self.emitir(f"{destino} = {self.expr(s.valor, tipo)};")
            return

        if isinstance(s, Si):
            self.emitir(f"if ({self.expr(s.cond, 'bool')})")
            self.bloque(s.entonces)
            if s.sino is not None:
                self.emitir("else")
                self.bloque(s.sino)
            return

        if isinstance(s, Para):
            tipo = self._tipo_de(s.coleccion)
            elem = elem_lista(tipo) if es_lista(tipo) else elem_de(tipo)
            tope = (f"{self.lugar(s.coleccion)}.length" if es_lista(tipo)
                    else str(largo_arreglo(tipo)))
            self.bucle += 1
            i = f"ss_k{self.bucle}"
            self.emitir(f"for (size_t {i} = 0; {i} < {tope}; {i}++)")
            self.emitir("{")
            self.sangria += 1
            self.pila.append([])
            self.vars.append({})
            self.bucles.append(len(self.pila))

            # El elemento se presta, no se copia: un `str` copiado tendria dos
            # duenios. Los escalares van por valor porque no hay nada que
            # duplicar.
            acceso = f"{self.lugar(s.coleccion)}.e[{i}]"
            if self.c.posee(elem):
                self.emitir(f"const {self.tipo_c(elem)}* {s.variable} = "
                            f"&{acceso};")
                self.declarar(s.variable, elem, True)
            else:
                self.emitir(f"SS_LANG_QUIZA_SIN_USAR {self.tipo_c(elem)} "
                            f"{s.variable} = {acceso};")
                self.declarar(s.variable, elem)

            for x in s.cuerpo:
                self.sentencia(x)
            if not self._termina_en_retorno(s.cuerpo):
                self.liberar_bloque(self.pila[-1])
            self.bucles.pop()
            self.pila.pop()
            self.vars.pop()
            self.sangria -= 1
            self.emitir("}")
            return

        if isinstance(s, (Romper, Continuar)):
            # Salir del bucle salta el cierre de los bloques de dentro, asi
            # que hay que liberarlos aqui. Los de fuera siguen vivos.
            self._apagar_ahora()
            desde = self.bucles[-1] - 1 if self.bucles else 0
            for marco in reversed(self.pila[desde:]):
                self.liberar_bloque(marco)
            self.emitir("break;" if isinstance(s, Romper) else "continue;")
            return

        if isinstance(s, Mientras):
            self.bucles.append(len(self.pila) + 1)
            self.emitir(f"while ({self.expr(s.cond, 'bool')})")
            self.bloque(s.cuerpo)
            self.bucles.pop()
            return

        if isinstance(s, Falla):
            lit = s.motivo.replace("\\", "\\\\").replace('"', '\\"') \
                          .replace("\n", "\\n").replace("\t", "\\t")
            self.liberar_todo()
            self.emitir(f"return ({self.tipo_resultado(self.func.retorno)})"
                        f'{{ .motivo = "{lit}" }};')
            return

        if isinstance(s, Retorno):
            falible = self.func is not None and self.func.falible
            if s.valor is None:
                self.liberar_todo()
                if falible:
                    self.emitir(f"return ({self.tipo_resultado(self.func.retorno)})"
                                f"{{ .motivo = NULL }};")
                else:
                    self.emitir("return;")
                return
            # Si se devuelve una variable duenia, esa NO se libera: se entrega.
            devuelta = s.valor.nombre if isinstance(s.valor, Variable) else None
            entregadas = self.movidas_en(s.valor)
            # Una variable con bandera se entrega solo en algunos caminos
            # (la alternativa de un `sino`, por ejemplo). Excluirla aqui la
            # dejaria sin liberar en los demas: quien decide es la bandera.
            entregadas -= self.con_bandera
            if devuelta is not None:
                entregadas.add(devuelta)
            valor = self.expr(s.valor, self.func.retorno if self.func else None)
            envolver = (lambda v: f"({self.tipo_resultado(self.func.retorno)})"
                                  f"{{ .motivo = NULL, .valor = {v} }}") \
                       if falible else (lambda v: v)
            if devuelta is not None:
                self._apagar_ahora()
                self.liberar_todo(excepto=entregadas)
                self.emitir(f"return {envolver(devuelta)};")
            else:
                tmp = self.nuevo_tmp()
                tipo_devuelto = self.func.retorno if self.func else self._tipo_de(s.valor)
                self.emitir(f"{self.tipo_c(tipo_devuelto)} {tmp} = {valor};")
                # Antes de liberar y de salir: lo que se apague despues de un
                # `return` no se ejecuta nunca, y la liberacion veria la
                # bandera todavia encendida.
                self._apagar_ahora()
                self.liberar_todo(excepto=entregadas)
                self.emitir(f"return {envolver(tmp)};")
            return

        if isinstance(s, ExprSentencia):
            c = self.expr(s.expr, None)
            if c:
                self.emitir(c + ";")
            return

        raise AssertionError(type(s).__name__)

    def _tipo_de(self, e):
        if isinstance(e, Entero):
            return "usize"
        if isinstance(e, Cadena):
            return "view"
        if isinstance(e, Booleano):
            return "bool"
        if isinstance(e, Variable):
            return self.tipo_var(e.nombre) or "usize"
        if isinstance(e, Llamada):
            if e.nombre in ("obtener", "tiene", "claves", "quitar") and e.args:
                tm = self._tipo_de(e.args[0])
                if es_mapa(tm):
                    k, v = partes_mapa(tm)
                    if e.nombre == "obtener":
                        return v
                    if e.nombre in ("tiene", "quitar"):
                        return "bool"
                    return f"lista<{k}>"
            if e.nombre in INTERNAS:
                return INTERNAS[e.nombre]["retorno"]
            f = self.c.funciones.get(e.nombre)
            return f.retorno if f else "usize"
        if isinstance(e, Try):
            return self._tipo_de(e.expr)
        if isinstance(e, Sino):
            return self._tipo_de(e.expr)
        if isinstance(e, Campo):
            base = self._tipo_de(e.objeto)
            st = self.c.structs.get(base)
            if st:
                for c in st.campos:
                    if c.nombre == e.nombre:
                        return c.tipo
            return "usize"
        if isinstance(e, Indice):
            base = self._tipo_de(e.arreglo)
            if es_arreglo(base):
                return elem_de(base)
            if es_lista(base):
                return elem_lista(base)
            return "usize"
        if isinstance(e, LiteralStruct):
            return e.tipo
        if isinstance(e, LiteralArreglo):
            elem = self._tipo_de(e.elementos[0]) if e.elementos else "usize"
            return f"[{elem}; {len(e.elementos)}]"
        if isinstance(e, Binaria):
            if e.op in {"==", "!=", "<", "<=", ">", ">=", "&&", "||"}:
                return "bool"
            return self._tipo_de(e.izq)
        if isinstance(e, Unaria):
            return "bool" if e.op == "!" else self._tipo_de(e.valor)
        return "usize"

    # ---------- expresiones ----------

    def expr(self, e, esperado):
        if isinstance(e, Entero):
            if esperado == "i64":
                return f"(int64_t){e.valor}"
            # Sin sufijo, un literal por encima de 2^63-1 no cabe en el tipo
            # que C le asigna por defecto y el compilador avisa. `ULL` le dice
            # cual es sin cambiar el valor.
            sufijo = "ULL" if e.valor > 9223372036854775807 else ""
            return f"(size_t){e.valor}{sufijo}"

        if isinstance(e, Cadena):
            lit = (e.valor.replace("\\", "\\\\").replace('"', '\\"')
                          .replace("\n", "\\n").replace("\t", "\\t")
                          .replace("\0", "\\0"))
            return f'sv_len("{lit}", {len(e.valor.encode("utf-8"))})'

        if isinstance(e, Booleano):
            return "true" if e.valor else "false"

        if isinstance(e, Variable):
            if getattr(e, "mueve", False) and e.nombre in self.con_bandera:
                self.pendientes.append(e.nombre)
            # un parametro `mut str` llega como puntero
            if self.es_puntero(e.nombre):
                return f"(*{e.nombre})"
            return e.nombre

        if isinstance(e, Unaria):
            return f"({e.op}{self.expr(e.valor, esperado)})"

        if isinstance(e, Try):
            interna = e.expr
            t = self._tipo_de(interna)
            tmp = self.nuevo_tmp()
            llamada = self.llamada(interna)
            self.emitir(f"{self.tipo_resultado(t)} {tmp} = {llamada};")
            self.emitir(f"if ({tmp}.motivo != NULL)")
            self.emitir("{")
            self.sangria += 1
            self.liberar_todo()
            self.emitir(f"return ({self.tipo_resultado(self.func.retorno)})"
                        f"{{ .motivo = {tmp}.motivo }};")
            self.sangria -= 1
            self.emitir("}")
            return "" if t in (None, UNIDAD) else f"{tmp}.valor"

        if isinstance(e, Sino):
            interna = e.expr
            t = self._tipo_de(interna)
            tmp = self.nuevo_tmp()
            llamada = self.llamada(interna)
            self.emitir(f"{self.tipo_resultado(t)} {tmp} = {llamada};")
            if t in (None, UNIDAD):
                return ""
            elegido = self.nuevo_tmp()
            self.emitir(f"{self.tipo_c(t)} {elegido};")
            self.emitir(f"if ({tmp}.motivo != NULL)")
            self.emitir("{")
            self.sangria += 1
            # Si la alternativa entrega una variable con bandera, `expr` ya
            # lo anoto al generarla; lo unico propio de `sino` es que el
            # apagado va DENTRO de esta rama, no al final de la sentencia.
            with self.camino():
                alt = self.expr(e.alternativa, t)
                self.emitir(f"{elegido} = {alt};")
            self.sangria -= 1
            self.emitir("}")
            self.emitir("else")
            self.emitir("{")
            self.sangria += 1
            self.emitir(f"{elegido} = {tmp}.valor;")
            self.sangria -= 1
            self.emitir("}")
            return elegido

        if isinstance(e, (Campo, Indice)):
            return self.lugar(e)

        if isinstance(e, LiteralStruct):
            st = self.c.structs.get(e.tipo)
            tipos = {c.nombre: c.tipo for c in st.campos} if st else {}
            partes = ", ".join(
                f".{n} = {self.expr(v, tipos.get(n))}" for n, v in e.campos)
            return f"({e.tipo}){{ {partes} }}"

        if isinstance(e, LiteralArreglo):
            if esperado and es_mapa(esperado):
                # El mapa vacio no reserva nada: la tabla nace en el primer
                # `poner`, que es donde el coste se ve.
                return (f"({self.tipo_c(esperado)}){{ .claves = NULL, "
                        f".valores = NULL, .largo = 0, .capacidad = 0 }}")
            if esperado and es_lista(esperado):
                elem = elem_lista(esperado)
                tmp = self.nuevo_tmp()
                self.emitir(f"{self.tipo_c(esperado)} {tmp} = "
                            "{ .e = NULL, .length = 0, .capacity = 0 };")
                for x in e.elementos:
                    valor = self.expr(x, elem)
                    self.emitir(f"ss_push_{mangle(esperado)}(&{tmp}, {valor}, "
                                f"{self.arch(e)}, {e.linea});")
                return tmp
            t = esperado if (esperado and es_arreglo(esperado)) else self._tipo_de(e)
            elem = elem_de(t)
            partes = ", ".join(self.expr(x, elem) for x in e.elementos)
            return f"({self.tipo_c(t)}){{{{ {partes} }}}}"

        if isinstance(e, Binaria):
            return self.binaria(e, esperado)

        if isinstance(e, Llamada):
            return self.llamada(e)

        raise AssertionError(type(e).__name__)

    def lugar(self, e):
        """C para un sitio al que se puede leer y escribir."""
        if isinstance(e, Variable):
            return f"(*{e.nombre})" if self.es_puntero(e.nombre) else e.nombre
        if isinstance(e, Campo):
            return f"{self.lugar(e.objeto)}.{e.nombre}"
        if isinstance(e, Indice):
            base = self._tipo_de(e.arreglo)
            idx = self.expr(e.indice, "usize")
            if es_lista(base):
                lista = self.lugar(e.arreglo)
                return (f"{lista}.e[ss_lang_indice_({idx}, {lista}.length, "
                        f"{self.arch(e)}, {e.linea})]")
            n = largo_arreglo(base) if es_arreglo(base) else 0
            return (f"{self.lugar(e.arreglo)}.e"
                    f"[ss_lang_indice_({idx}, {n}, {self.arch(e)}, {e.linea})]")
        return self.expr(e, None)

    def binaria(self, e: Binaria, esperado):
        t = self._tipo_de(e.izq)
        if t not in {"usize", "i64"}:
            t = self._tipo_de(e.der)
        sufijo = "I" if t == "i64" else "U"
        izq = self.expr(e.izq, t)
        der = self.expr(e.der, t)
        pos = f"{self.arch(e)}, {e.linea}"

        if e.op in {"+", "-", "*"}:
            macro = {"+": "SUMA", "-": "RESTA", "*": "MUL"}[e.op]
            return f"SS_LANG_{macro}_{sufijo}({izq}, {der}, {pos})"

        if e.op in {"+?", "-?", "*?"}:
            return f"({izq} {e.op[0]} {der})"      # envolvente, pedida a proposito

        if e.op == "/":
            return f"SS_LANG_DIV({izq}, {der}, {pos})"
        if e.op == "%":
            return f"SS_LANG_MOD({izq}, {der}, {pos})"

        return f"({izq} {e.op} {der})"

    def llamada(self, e: Llamada):
        n = e.nombre

        if n == "vacio":
            return "ss_new()"
        if n == "nuevo":
            return f"ss_from_view({self.como_vista(e.args[0])})"
        if n == "vista":
            return f"ss_view({self.dir_de(e.args[0])})"
        if n == "largo":
            t = self._tipo_de(e.args[0])
            if es_mapa(t):
                return f"({self.lugar(e.args[0])}.largo)"
            if es_lista(t):
                return f"({self.lugar(e.args[0])}.length)"
            if es_arreglo(t):
                return f"((size_t){largo_arreglo(t)})"
            return f"sv_len_of({self.como_vista(e.args[0])})"
        if n == "igual":
            return (f"sv_equals({self.como_vista(e.args[0])}, "
                    f"{self.como_vista(e.args[1])})")
        if n == "rebanar":
            return (f"sv_slice({self.como_vista(e.args[0])}, "
                    f"{self.expr(e.args[1], 'usize')}, "
                    f"{self.expr(e.args[2], 'usize')})")
        if n == "empujar":
            return (f"ss_append_view({self.dir_de(e.args[0])}, "
                    f"{self.como_vista(e.args[1])})")
        if n == "imprimir":
            return self.imprimir(e.args[0])
        if n == "anadir":
            lista = e.args[0]
            tipo_lista = self._tipo_de(lista)
            elem = elem_lista(tipo_lista)
            valor = self.expr(e.args[1], elem)
            return (f"ss_push_{mangle(tipo_lista)}({self.dir_de(lista)}, {valor}, "
                    f"{self.arch(e)}, {e.linea})")
        if n == "texto":
            a = e.args[0]
            t = self._tipo_de(a)
            pos = f"{self.arch(e)}, {e.linea}"
            if t == "usize":
                return f"ss_lang_texto_usize_({self.expr(a, t)}, {pos})"
            if t == "i64":
                return f"ss_lang_texto_i64_({self.expr(a, t)}, {pos})"
            if t == "bool":
                v = self.expr(a, t)
                return f"ss_lang_texto_view_(({v}) ? sv(\"true\") : sv(\"false\"), {pos})"
            if t == "str":
                return f"ss_lang_texto_view_(ss_view({self.dir_de(a)}), {pos})"
            return f"ss_lang_texto_view_({self.como_vista(a)}, {pos})"
        if n == "byte":
            vista = self.como_vista(e.args[0])
            idx = self.expr(e.args[1], "usize")
            tmp = self.nuevo_tmp()
            self.emitir(f"SafeView {tmp} = {vista};")
            return (f"((size_t)(unsigned char){tmp}.ptr[ss_lang_indice_("
                    f"{idx}, {tmp}.len, {self.arch(e)}, {e.linea})])")
        if n in ("poner", "obtener", "tiene", "claves", "quitar"):
            lugar = e.args[0]
            tm = self._tipo_de(lugar)
            m = mangle(tm)
            dir_mapa = self.dir_de(lugar)
            if n == "claves":
                return (f"ss_mapa_claves_{m}({dir_mapa}, "
                        f"{self.arch(e)}, {e.linea})")
            clave = self.como_vista(e.args[1])
            if n == "tiene":
                return f"ss_mapa_tiene_{m}({dir_mapa}, {clave})"
            if n == "quitar":
                return f"ss_mapa_quitar_{m}({dir_mapa}, {clave})"
            if n == "obtener":
                return f"ss_mapa_obtener_{m}({dir_mapa}, {clave})"
            _, tv = partes_mapa(tm)
            valor = self.expr(e.args[2], tv)
            return (f"ss_mapa_poner_{m}({dir_mapa}, {clave}, {valor}, "
                    f"{self.arch(e)}, {e.linea})")

        if n == "n_argumentos":
            return "ss_lang_n_argumentos_()"

        if n == "argumento":
            return (f"ss_lang_argumento_({self.expr(e.args[0], 'usize')}, "
                    f"{self.arch(e)}, {e.linea})")

        if n == "menor":
            return (f"(sv_cmp({self.como_vista(e.args[0])}, "
                    f"{self.como_vista(e.args[1])}) < 0)")

        if n == "ordenar":
            t = self._tipo_de(e.args[0])
            return f"ss_ordenar_{mangle(t)}({self.dir_de(e.args[0])})"

        if n == "imprimir_error":
            return self.imprimir(e.args[0], "stderr")

        if n == "escribir_archivo":
            return (f"ss_lang_escribir_archivo_({self.como_vista(e.args[0])}, "
                    f"{self.como_vista(e.args[1])})")

        if n == "leer_archivo":
            return f"ss_lang_leer_archivo_({self.como_vista(e.args[0])})"

        # funcion del usuario
        f = self.c.funciones.get(n)
        args = []
        for i, a in enumerate(e.args):
            p = f.params[i] if f and i < len(f.params) else None
            if p is not None and p.prestado:
                args.append(self.dir_de(a))
            else:
                args.append(self.expr(a, p.tipo if p else None))
        destino = "ss_main_" if n == "main" else n
        return f"{destino}({', '.join(args)})"

    def dir_de(self, a):
        """La direccion de un sitio con nombre: `&x`, `&p.campo`, `&v.e[i]`."""
        if isinstance(a, Variable):
            return self.ref(a.nombre)
        return f"&{self.lugar(a)}"

    def como_vista(self, a):
        """Un argumento donde se pide una SafeView."""
        if self._tipo_de(a) == "str" and isinstance(a, (Variable, Campo, Indice)):
            return f"ss_view({self.dir_de(a)})"
        return self.expr(a, "view")

    def imprimir(self, a, destino="stdout"):
        """`imprimir` va al resultado; `imprimir_error` al diagnostico.

        Separarlos no es cosmetico: es lo que permite encauzar la salida de
        una herramienta sin que se le cuelen los mensajes de uso.
        """
        f = "printf(" if destino == "stdout" else f"fprintf({destino}, "
        t = self._tipo_de(a)
        if t == "str":
            return f'{f}"%s", ss_cstr({self.dir_de(a)}))'
        if t == "view":
            return f'{f}SV_FMT, SV_ARG({self.como_vista(a)}))'
        if t == "usize":
            return f'{f}"%zu", {self.expr(a, "usize")})'
        if t == "i64":
            return f'{f}"%lld", (long long){self.expr(a, "i64")})'
        if t == "bool":
            return f'{f}"%s", ({self.expr(a, "bool")}) ? "true" : "false")'
        return f'{f}"%s", "?")'


def generar(funciones, comprobador, archivo="<entrada>"):
    return Generador(comprobador, archivo).generar(funciones)
