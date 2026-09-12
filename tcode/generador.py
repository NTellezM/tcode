"""
Genera C a partir del arbol ya comprobado.

Dos cosas que el generador hace y el programador de C tendria que hacer a
mano, que son justo donde se equivoca:

  - insertar `ss_free` al cerrar cada bloque, para los `str` que no se
    movieron;
  - envolver `+`, `-` y `*` en comprobaciones de desbordamiento.
"""

import contextlib
import re

from tcode.nodos import (
    Entero, Cadena, Booleano, Variable, Llamada, Binaria, Unaria,
    Campo, Indice, LiteralStruct, LiteralArreglo, Try, Sino, Falla, Conversion,
    Decimal, SiExpr, Cierre,
    Interpolada,
    Declaracion, Asignacion, Si, Mientras, Retorno, ExprSentencia,
    Funcion, Struct, Para, Romper, Continuar,
)
from tcode.comprobador import (
    INTERNAS, UNIDAD, es_arreglo, partes_arreglo, elem_de, largo_arreglo,
    es_lista, elem_lista, es_mapa, partes_mapa, ORDENABLES,
    es_bloque, elem_bloque,
    es_referencia, es_referencia_mutable, apuntado, sin_prestamo,
    es_funcion, partes_funcion,
)

TIPOS_C = {
    "str": "SafeString",
    "view": "SafeView",
    "bool": "bool",
    "usize": "size_t",
    "u8": "uint8_t", "u16": "uint16_t", "u32": "uint32_t", "u64": "uint64_t",
    "i8": "int8_t", "i16": "int16_t", "i32": "int32_t", "i64": "int64_t",
    "f32": "float", "f64": "double",
    None: "void",
    UNIDAD: "void",
}

# Por cada entero: el sufijo de sus funciones de aritmetica comprobada, el
# tipo de C, y sus limites. `usize` no lleva ancho escrito porque mide cosas
# de la maquina; los demas valen lo mismo en todas.
DECIMALES = {"f32": "float", "f64": "double"}

ARITMETICA = {
    "usize": ("usize", "size_t",  "SIZE_MAX",   None),
    "u8":    ("u8",    "uint8_t", "UINT8_MAX",  None),
    "u16":   ("u16",   "uint16_t","UINT16_MAX", None),
    "u32":   ("u32",   "uint32_t","UINT32_MAX", None),
    "u64":   ("u64",   "uint64_t","UINT64_MAX", None),
    "i8":    ("i8",    "int8_t",  "INT8_MAX",   "INT8_MIN"),
    "i16":   ("i16",   "int16_t", "INT16_MAX",  "INT16_MIN"),
    "i32":   ("i32",   "int32_t", "INT32_MAX",  "INT32_MIN"),
    "i64":   ("i64",   "int64_t", "INT64_MAX",  "INT64_MIN"),
}

CABECERA = r'''/* Generado por el compilador de Tcode. No editar a mano. */

#include <stdbool.h>
#include <stdint.h>
#include <math.h>
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
static void ss_lang_no_es_numero_(const char* op, const char* consejo,
                                  const char* archivo, int linea)
{
    fprintf(stderr, "%s:%d: `%s` no dio un numero (NaN o infinito). %s\n",
            archivo, linea, op, consejo);
    abort();
}

SS_LANG_QUIZA_SIN_USAR SS_LANG_NO_VUELVE
static void ss_lang_no_cabe_(const char* de, const char* a,
                             const char* archivo, int linea)
{
    fprintf(stderr, "%s:%d: el valor no cabe en `%s` viniendo de `%s`\n",
            archivo, linea, a, de);
    abort();
}

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

/* Deteccion de desborde. Con los builtins del compilador es una instruccion;
   sin ellos, la formula portable, que comprueba ANTES de operar porque en los
   con signo desbordar ya es comportamiento indefinido. */
#ifdef SS_LANG_HAY_BUILTINS
#  define SS_LANG_DESB_SUMA_U(a, b, r, tmax)  __builtin_add_overflow((a), (b), (r))
#  define SS_LANG_DESB_RESTA_U(a, b, r, tmax) __builtin_sub_overflow((a), (b), (r))
#  define SS_LANG_DESB_MUL_U(a, b, r, tmax)   __builtin_mul_overflow((a), (b), (r))
#  define SS_LANG_DESB_SUMA_I(a, b, r, tmax, tmin)  __builtin_add_overflow((a), (b), (r))
#  define SS_LANG_DESB_RESTA_I(a, b, r, tmax, tmin) __builtin_sub_overflow((a), (b), (r))
#  define SS_LANG_DESB_MUL_I(a, b, r, tmax, tmin)   __builtin_mul_overflow((a), (b), (r))
#else
#  define SS_LANG_DESB_SUMA_U(a, b, r, tmax)                                  \
     ((a) > (tmax) - (b) ? 1 : (*(r) = (a) + (b), 0))
#  define SS_LANG_DESB_RESTA_U(a, b, r, tmax)                                 \
     ((a) < (b) ? 1 : (*(r) = (a) - (b), 0))
#  define SS_LANG_DESB_MUL_U(a, b, r, tmax)                                   \
     (((a) != 0 && (b) > (tmax) / (a)) ? 1 : (*(r) = (a) * (b), 0))
#  define SS_LANG_DESB_SUMA_I(a, b, r, tmax, tmin)                            \
     ((((b) > 0 && (a) > (tmax) - (b)) || ((b) < 0 && (a) < (tmin) - (b)))     \
      ? 1 : (*(r) = (a) + (b), 0))
#  define SS_LANG_DESB_RESTA_I(a, b, r, tmax, tmin)                           \
     ((((b) < 0 && (a) > (tmax) + (b)) || ((b) > 0 && (a) < (tmin) + (b)))     \
      ? 1 : (*(r) = (a) - (b), 0))
#  define SS_LANG_DESB_MUL_I(a, b, r, tmax, tmin)                             \
     (((a) != 0 && (b) != 0 &&                                                \
       ((a) > 0 ? ((b) > 0 ? (a) > (tmax) / (b) : (b) < (tmin) / (a))          \
                : ((b) > 0 ? (a) < (tmin) / (b) : (a) < (tmax) / (b))))        \
      ? 1 : (*(r) = (a) * (b), 0))
#endif

/* Una familia por ancho de entero. Solo se emiten los anchos que el programa
   usa: un programa con `usize` no carga con las nueve. */
#define SS_LANG_ARIT_U(sufijo, tipo, tmax)                                    \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_suma_##sufijo(tipo a, tipo b, const char* ar, int ln)     \
{ tipo r = 0;                                                              \
  if (SS_LANG_DESB_SUMA_U(a, b, &r, tmax))                    \
      { ss_lang_desborde_("+", ar, ln); }                    \
  return r; }                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_resta_##sufijo(tipo a, tipo b, const char* ar, int ln)    \
{ tipo r = 0;                                                              \
  if (SS_LANG_DESB_RESTA_U(a, b, &r, tmax))                    \
      { ss_lang_desborde_("-", ar, ln); }                    \
  return r; }                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_mul_##sufijo(tipo a, tipo b, const char* ar, int ln)      \
{ tipo r = 0;                                                              \
  if (SS_LANG_DESB_MUL_U(a, b, &r, tmax))                    \
      { ss_lang_desborde_("*", ar, ln); }                    \
  return r; }                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_desp_izq_##sufijo(tipo a, size_t n, const char* ar, int ln)\
{ if (n >= sizeof(tipo) * 8) { ss_lang_desborde_("<<", ar, ln); }             \
  return (tipo) (a << n); }                                                   \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_desp_der_##sufijo(tipo a, size_t n, const char* ar, int ln)\
{ if (n >= sizeof(tipo) * 8) { ss_lang_desborde_(">>", ar, ln); }             \
  return (tipo) (a >> n); }

#define SS_LANG_ARIT_I(sufijo, tipo, utipo, tmax, tmin)                       \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_suma_##sufijo(tipo a, tipo b, const char* ar, int ln)     \
{ tipo r = 0;                                                              \
  if (SS_LANG_DESB_SUMA_I(a, b, &r, tmax, tmin))                    \
      { ss_lang_desborde_("+", ar, ln); }                    \
  return r; }                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_resta_##sufijo(tipo a, tipo b, const char* ar, int ln)    \
{ tipo r = 0;                                                              \
  if (SS_LANG_DESB_RESTA_I(a, b, &r, tmax, tmin))                    \
      { ss_lang_desborde_("-", ar, ln); }                    \
  return r; }                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_mul_##sufijo(tipo a, tipo b, const char* ar, int ln)      \
{ tipo r = 0;                                                              \
  if (SS_LANG_DESB_MUL_I(a, b, &r, tmax, tmin))                    \
      { ss_lang_desborde_("*", ar, ln); }                    \
  return r; }                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_abs_##sufijo(tipo a, const char* ar, int ln)              \
{ /* el absoluto del minimo no cabe en el tipo: es el unico caso. */          \
  if (a == tmin) { ss_lang_desborde_("absoluto", ar, ln); }                   \
  return a < 0 ? (tipo) -a : a; }                                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_desp_izq_##sufijo(tipo a, size_t n, const char* ar, int ln)\
{ if (n >= sizeof(tipo) * 8) { ss_lang_desborde_("<<", ar, ln); }             \
  /* desplazar un negativo es indefinido en C: se hace sobre los bits. */     \
  return (tipo) ((utipo) ((utipo) a << n)); }                                 \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_desp_der_##sufijo(tipo a, size_t n, const char* ar, int ln)\
{ if (n >= sizeof(tipo) * 8) { ss_lang_desborde_(">>", ar, ln); }             \
  return (tipo) (a >> n); }

/* Decimales. Un calculo que sale de los numeros —un NaN, un infinito— no
   sigue adelante: para donde aparece. Es la misma regla que ya vale para el
   desbordamiento entero, y la diferencia con C, Go, Rust y Swift, donde un
   NaN nacido en el paso 3 se descubre en el paso 900 habiendolo contaminado
   todo. `+?`, `-?`, `*?` y `/?` dejan el IEEE de siempre, dicho a proposito.

   Se comprueba el RESULTADO, no los operandos: una sola comparacion cubre
   NaN, infinito por division entre cero y desborde a infinito. */
#define SS_LANG_ARIT_F(sufijo, tipo)                                          \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_fin_##sufijo(tipo r, const char* op, const char* consejo, \
                                 const char* ar, int ln)                      \
{                                                                             \
    if (!isfinite(r)) { ss_lang_no_es_numero_(op, consejo, ar, ln); }         \
    return r;                                                                 \
}

/* Conversion entre anchos. La comprobacion es de ida y vuelta: se convierte,
   se vuelve a convertir al tipo de origen, y si no sale lo mismo es que no
   cabia. Vale para cualquier pareja, con signo o sin el, y no se apoya en
   comparar limites de tipos distintos, que es de donde salen los avisos del
   compilador de C y los errores sutiles. `como?` no pasa por aqui. */
#define SS_LANG_CONV(destino, tipo_d, origen, tipo_o)                         \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo_d ss_lang_conv_##destino##_de_##origen(                           \
        tipo_o v, const char* ar, int ln)                                     \
{                                                                             \
    tipo_d r = (tipo_d) v;                                                    \
    if ((tipo_o) r != v) { ss_lang_no_cabe_(#origen, #destino, ar, ln); }      \
    return r;                                                                 \
}

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

/* Agrega texto a un `str` y aborta si no hay memoria. Lo usan las cadenas
   interpoladas, donde no hay un sitio razonable al que devolver el fallo. */
/* Un decimal se escribe con `%g`, pero si sale entero se le pone `.0`: un
   `f64` que vale 1 tiene que verse como `1.0` y no como `1`, que es lo que
   hacen C y Go y lo que confunde al leer una salida. El buffer es estatico
   por llamada, asi que el resultado se usa y se copia en el acto. */
SS_LANG_QUIZA_SIN_USAR
static const char* ss_lang_texto_decimal_(double v)
{
    static char buf[40];
    snprintf(buf, sizeof buf, "%g", v);
    for (const char* p = buf; *p; p++)
        if (*p == '.' || *p == 'e' || *p == 'n' || *p == 'i') return buf;
    size_t n = strlen(buf);
    if (n + 2 < sizeof buf) { buf[n] = '.'; buf[n + 1] = '0'; buf[n + 2] = 0; }
    return buf;
}

SS_LANG_QUIZA_SIN_USAR
static void ss_lang_empujar_byte_(SafeString* s, uint8_t b,
                                  const char* archivo, int linea)
{
    char c = (char) b;
    if (!ss_append_len(s, &c, 1)) ss_lang_sin_memoria_(archivo, linea);
}

SS_LANG_QUIZA_SIN_USAR
static void ss_lang_agregar_texto_(SafeString* s, SafeView v,
                                   const char* archivo, int linea)
{
    if (!ss_append_view(s, v))
        ss_lang_sin_memoria_(archivo, linea);
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


def bytes_de(texto):
    """Los bytes que representa una cadena de la fuente. Lo normal es UTF-8;
    lo marcado con `\\xNN` es ese byte y nada mas."""
    salida = bytearray()
    for ch in texto:
        o = ord(ch)
        if 0xDC00 <= o <= 0xDCFF:
            salida.append(o - 0xDC00)
        else:
            salida.extend(ch.encode("utf-8"))
    return bytes(salida)


class _ParamSuelto:
    """Un parametro sacado de un tipo de funcion, para que la generacion de
    argumentos no tenga que saber si detras hay una declaracion o una
    variable."""
    __slots__ = ("tipo", "prestado")

    def __init__(self, tipo, prestado):
        self.tipo = tipo
        self.prestado = prestado


class _FirmaSuelta:
    __slots__ = ("params",)

    def __init__(self, params):
        self.params = params


def hondura_tipo(t):
    """Cuanto anida un tipo: `lista<lista<str>>` mas que `lista<str>`."""
    return t.count("<") + t.count("[")


def mangle(t):
    """Nombre C valido para un tipo: `[usize; 3]` -> `arr_usize_3`."""
    if es_funcion(t):
        params, retorno = partes_funcion(t)
        piezas = "_".join(mangle(x) for x in params) or "nada"
        return f"fn_{piezas}_a_{mangle(retorno)}"
    if es_referencia(t):
        marca = "refmut" if es_referencia_mutable(t) else "ref"
        return f"{marca}_{mangle(apuntado(t))}"
    if es_arreglo(t):
        elem, n = partes_arreglo(t)
        return f"arr_{mangle(elem)}_{n}"
    if es_mapa(t):
        k, v = partes_mapa(t)
        return f"mapa_{mangle(k)}_{mangle(v)}"
    if es_bloque(t):
        return f"bloque_{mangle(elem_bloque(t))}"
    if es_lista(t):
        return f"lista_{mangle(elem_lista(t))}"
    return t.replace("()", "nada")


class Generador:
    def __init__(self, comprobador, archivo="<entrada>"):
        self.c = comprobador
        self.archivo = archivo
        self.lineas = []
        self.sangria = 0
        # pila de bloques: cada uno con los `str` declarados que hay que liberar
        self.pila = []
        self.copiadores = {}    # tipo -> nombre del copiador generado
        self.aritmeticas = set()  # anchos de entero cuya aritmetica hace falta
        self.conversiones = set()  # (destino, origen) de cada `como`
        self.tipos_funcion = {}   # tipo de funcion -> nombre de su typedef
        self.decimales = set()    # anchos decimales cuya comprobacion hace falta
        self.bloques = {}         # tipo bloque -> nombre de su struct en C
        self.con_lineas = True    # emitir `#line` apuntando al `.t`
        self.ultima_pos = None
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
        # Valores duenios creados al vuelo por una expresion (hoy, las
        # cadenas interpoladas). Quien se los queda los "reclama"; los que
        # sobran al terminar la sentencia se liberan ahi mismo.
        self.temporales = []
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
        if es_funcion(t):
            return self.registrar_funcion_tipo(t)
        if es_arreglo(t):
            return self.registrar_arreglo(t)
        if es_referencia(t):
            # Un prestamo es un puntero. El de solo lectura sale `const`, asi
            # que el propio compilador de C impide escribir por el.
            interno = self.tipo_c(apuntado(t))
            return f"{interno}*" if es_referencia_mutable(t) else f"const {interno}*"
        if es_bloque(t):
            return self.registrar_bloque(t)
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

    def lineas_liberacion(self, expr_c, tipo, sangria=1):
        """Las lineas de C que devuelven la memoria de `expr_c`.

        Reutiliza `liberacion`, que ya sabe de textos, structs, listas y
        mapas, capturando lo que emite en vez de escribirlo donde toque.
        """
        guardadas, sangria_previa = self.lineas, self.sangria
        self.lineas, self.sangria = [], sangria
        self.liberacion(expr_c, tipo)
        salida = self.lineas
        self.lineas, self.sangria = guardadas, sangria_previa
        return salida

    def registrar_funcion_tipo(self, t):
        """Un tipo de funcion necesita su `typedef`: en C el puntero a funcion
        no se puede escribir dentro de otra declaracion sin volverse ilegible."""
        if t in self.tipos_funcion:
            return self.tipos_funcion[t]
        nombre = f"ss_{mangle(t)}"
        self.tipos_funcion[t] = nombre
        params, retorno = partes_funcion(t)
        for x in params:
            if es_funcion(x):
                self.registrar_funcion_tipo(x)
        if es_funcion(retorno):
            self.registrar_funcion_tipo(retorno)
        return nombre

    def necesita_copiador(self, tipo):
        """Anota que hace falta un copiador para este tipo, y para lo que
        lleve dentro. Se emiten despues, de dentro hacia fuera."""
        # Un `str` se copia con `ss_clone`, que ya esta en el runtime, y un
        # escalar se copia solo: ninguno de los dos necesita generar nada.
        if tipo == "str" or not self.c.posee(tipo) or tipo in self.copiadores:
            return
        self.copiadores[tipo] = f"ss_copia_{mangle(tipo)}"
        if es_bloque(tipo):
            self.necesita_copiador(elem_bloque(tipo))
        elif es_lista(tipo):
            self.necesita_copiador(elem_lista(tipo))
        elif es_mapa(tipo):
            self.necesita_copiador(partes_mapa(tipo)[1])
        elif es_arreglo(tipo):
            self.necesita_copiador(partes_arreglo(tipo)[0])
        elif tipo in self.c.structs:
            for c in self.c.structs[tipo].campos:
                self.necesita_copiador(c.tipo)

    def copia_de(self, expr_c, tipo):
        """Una expresion C que es una copia independiente de `expr_c`.

        Un escalar se copia solo. Lo demas lleva memoria detras, y de eso se
        encarga un copiador generado: uno por tipo, recursivo, que es el
        espejo exacto de `liberacion`. Si `liberacion` sabe soltarlo, este
        sabe duplicarlo.
        """
        if not self.c.posee(tipo):
            return expr_c
        if tipo == "str":
            return f"ss_clone(&{expr_c})"
        self.necesita_copiador(tipo)
        return f"{self.copiadores[tipo]}(&{expr_c})"

    def cuerpo_copiador(self, tipo, nombre):
        """El copiador de un tipo compuesto, ya con su nombre de C."""
        tc = self.tipo_c(tipo)
        lineas = ["SS_LANG_QUIZA_SIN_USAR",
                  f"static {tc} {nombre}(const {tc}* p)", "{"]
        if es_bloque(tipo):
            elem = elem_bloque(tipo)
            te = self.tipo_c(elem)
            lineas += [
                f"    {tc} r = {{ NULL, 0 }};",
                "    if (p->n == 0) return r;",
                f"    r.e = ({te}*) calloc(p->n, sizeof({te}));",
                "    if (r.e == NULL) ss_lang_sin_memoria_(__FILE__, __LINE__);",
                "    r.n = p->n;",
                "    for (size_t i = 0; i < p->n; i++)",
                f"        r.e[i] = {self.copia_de('p->e[i]', elem)};",
                "    return r;",
            ]
        elif es_lista(tipo):
            elem = elem_lista(tipo)
            te = self.tipo_c(elem)
            lineas += [
                f"    {tc} r = {{ NULL, 0, 0 }};",
                "    if (p->length == 0) return r;",
                f"    r.e = ({te}*) calloc(p->length, sizeof({te}));",
                "    if (r.e == NULL) ss_lang_sin_memoria_(__FILE__, __LINE__);",
                "    r.capacity = p->length;",
                "    for (size_t i = 0; i < p->length; i++)",
                f"        r.e[i] = {self.copia_de('p->e[i]', elem)};",
                "    r.length = p->length;",
                "    return r;",
            ]
        elif es_mapa(tipo):
            k, v = partes_mapa(tipo)
            tck, tcv = self.tipo_c(k), self.tipo_c(v)
            lineas += [
                f"    {tc} r = {{ NULL, NULL, 0, 0 }};",
                "    if (p->capacidad == 0) return r;",
                f"    r.claves = ({tck}*) calloc(p->capacidad, sizeof({tck}));",
                f"    r.valores = ({tcv}*) calloc(p->capacidad, sizeof({tcv}));",
                "    if (r.claves == NULL || r.valores == NULL)",
                "        ss_lang_sin_memoria_(__FILE__, __LINE__);",
                "    r.capacidad = p->capacidad;",
                "    r.largo = p->largo;",
                "    for (size_t i = 0; i < p->capacidad; i++)",
                "    {",
                "        if (p->claves[i].data == NULL) continue;",
                "        r.claves[i] = ss_clone(&p->claves[i]);",
                f"        r.valores[i] = {self.copia_de('p->valores[i]', v)};",
                "    }",
                "    return r;",
            ]
        elif es_arreglo(tipo):
            elem, n = partes_arreglo(tipo)
            lineas += [
                f"    {tc} r;",
                f"    for (size_t i = 0; i < {n}; i++)",
                f"        r.e[i] = {self.copia_de('p->e[i]', elem)};",
                "    return r;",
            ]
        else:
            lineas.append(f"    {tc} r;")
            for c in self.c.structs[tipo].campos:
                lineas.append(f"    r.{c.nombre} = "
                              f"{self.copia_de('p->' + c.nombre, c.tipo)};")
            lineas.append("    return r;")
        lineas += ["}", ""]
        return lineas

    def _tipo_obtener(self, v):
        """Lo que devuelve `obtener` para un mapa cuyo valor es `v`."""
        if not self.c.posee(v):
            return v
        return "view" if v == "str" else f"&{v}"

    def registrar_bloque(self, t):
        if t not in self.bloques:
            self.bloques[t] = f"ss_{mangle(t)}"
            self.tipo_c(elem_bloque(t))
        return self.bloques[t]

    def registrar_mapa(self, t):
        if t not in self.mapas:
            k, v = partes_mapa(t)
            self.tipo_c(k)
            self.tipo_c(v)
            # `claves` devuelve una lista de claves y `obtener` un `V !`:
            # los dos tipos tienen que existir antes de emitir los typedefs.
            self.registrar_lista(f"lista<{k}>")
            self.tipo_resultado(self._tipo_obtener(v))
            if self.c.es_compuesto(v):
                self.tipo_resultado(f"&mut {v}")
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
            elif t and es_bloque(t):
                self.registrar_bloque(t)
                mirar(elem_bloque(t))
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

    def marcar(self, nodo):
        """`#line`: le dice al compilador de C de que linea de Tcode viene lo
        que sigue.

        Con esto, gdb, valgrind, los sanitizers y los perfiladores dejan de
        hablar del `.c` intermedio y sealan el `.t` que escribio la persona.
        No hace falta escribir un depurador: hace falta no perder el sitio.

        Va pegada al margen: una directiva sangrada no es una directiva.
        """
        if not self.con_lineas:
            return
        linea = getattr(nodo, "linea", None)
        if not linea:
            return
        archivo = getattr(nodo, "archivo", "") or self.archivo
        if (archivo, linea) == self.ultima_pos:
            return
        self.ultima_pos = (archivo, linea)
        escapado = archivo.replace("\\", "\\\\").replace('"', '\\"')
        self.lineas.append(f'#line {linea} "{escapado}"')

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
        """Si en C esa variable es un puntero.

        Lo es un parametro prestado, y tambien una variable local cuyo tipo
        es un prestamo: `let x = try obtener(m, k);` guarda un `&V`.
        """
        v = self.buscar(nombre)
        if not v:
            return False
        return bool(v[1]) or es_referencia(v[0] or "")

    def fue_movida(self, nombre):
        """Si el valor se movio a otro sitio, aqui ya no somos duenios."""
        v = self.buscar(nombre)
        return bool(v and v[2] is not None and getattr(v[2], "movida", False))

    def ref(self, nombre):
        """Como referirse a `nombre` cuando se necesita un SafeString*."""
        return nombre if self.es_puntero(nombre) else f"&{nombre}"

    @staticmethod
    def literal_c(texto):
        """Un literal de C con los mismos BYTES, escapado.

        Un `\\xNN` de la fuente llega marcado como U+DC00+NN (la convencion
        de sustitutos): asi un byte crudo no se confunde con el caracter
        Unicode del mismo numero, que en UTF-8 ocuparia dos bytes."""
        salida = ['"']
        for b in bytes_de(texto):
            if b == 0x5C: salida.append("\\\\")
            elif b == 0x22: salida.append('\\"')
            elif b == 0x0A: salida.append("\\n")
            elif b == 0x09: salida.append("\\t")
            elif 0x20 <= b < 0x7F: salida.append(chr(b))
            else: salida.append(f"\\{b:03o}")
        salida.append('"')
        return "".join(salida)

    def texto_de(self, expresion_c, tipo, nodo):
        """El `str` que representa un valor. Mismas reglas que `texto`."""
        pos = f"{self.arch(nodo)}, {nodo.linea}"
        if tipo == "usize":
            return f"ss_lang_texto_usize_({expresion_c}, {pos})"
        if tipo in DECIMALES:
            return (f"ss_lang_texto_view_(sv(ss_lang_texto_decimal_"
                    f"({expresion_c})), {pos})")
        if tipo in ARITMETICA:
            # Un ancho fijo se ensancha al mayor de su signo: una funcion de
            # conversion por signo, no una por ancho.
            if tipo.startswith("u"):
                return f"ss_lang_texto_usize_((size_t) {expresion_c}, {pos})"
            return f"ss_lang_texto_i64_((int64_t) {expresion_c}, {pos})"
        if tipo == "bool":
            return (f"ss_lang_texto_view_(({expresion_c}) ? sv(\"true\") "
                    f": sv(\"false\"), {pos})")
        return f"ss_lang_texto_view_({expresion_c}, {pos})"

    def nuevo_tmp(self):
        self.tmp += 1
        return f"ss_tmp{self.tmp}"

    def arch(self, nodo=None):
        a = (getattr(nodo, "archivo", "") or self.archivo) if nodo else self.archivo
        return '"' + a.replace("\\", "\\\\").replace('"', '\\"') + '"'

    # ---------- programa ----------

    def generar(self, decls):
        # Una generica no se genera: no hay un tipo que poner. Lo que se
        # genera son las copias que el comprobador hizo al ver con que tipos
        # se usa, y a partir de aqui son funciones normales.
        decls = [d for d in decls
                 if not (isinstance(d, Funcion) and d.tipo_params)
                 and not (isinstance(d, Struct) and d.tipo_params)]
        decls += list(getattr(self.c, "structs_instanciados", ()))
        decls += list(getattr(self.c, "instanciadas", ()))

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

        # Bloques, listas y mapas son `typedef` de structs sin nombre, asi
        # que no se pueden declarar antes: cada uno tiene que ir detras de lo
        # que lleva dentro. `lista<mapa<str, str>>` necesita el mapa primero.
        # Se ordenan por dependencia; un ciclo no puede darse, porque pasar
        # por un struct con nombre corta la cadena (esos si van declarados
        # arriba) y sin eso el tipo seria infinito.
        agregados = {}
        for t, nombre in self.bloques.items():
            agregados[t] = (
                f"typedef struct {{ {self.tipo_c(elem_bloque(t))}* e; "
                f"size_t n; }} {nombre};", [elem_bloque(t)])
        for t, nombre in self.listas.items():
            elem = elem_lista(t)
            agregados[t] = (
                f"typedef struct {{ {self.tipo_c(elem)}* e; size_t length; "
                f"size_t capacity; }} {nombre};", [elem])
        # Tabla de direccionamiento abierto con sondeo lineal. Sin borrado en
        # v0, asi que no hacen falta lapidas: una celda con clave vacia es una
        # celda libre y la busqueda puede parar ahi.
        for t, nombre in self.mapas.items():
            k, v = partes_mapa(t)
            agregados[t] = (
                f"typedef struct {{ {self.tipo_c(k)}* claves; "
                f"{self.tipo_c(v)}* valores; size_t largo; "
                f"size_t capacidad; }} {nombre};", [k, v])

        puestos = set()
        en_curso = set()

        def poner_tipo(t):
            if t in puestos or t not in agregados or t in en_curso:
                return
            en_curso.add(t)
            for dependencia in agregados[t][1]:
                poner_tipo(dependencia)
            en_curso.discard(t)
            puestos.add(t)
            self.lineas.append(agregados[t][0])

        for t in sorted(agregados):
            poner_tipo(t)
        if agregados:
            self.lineas.append("")

        # structs, en orden de dependencia
        for st in self.orden_structs(structs):
            self.lineas.append(f"struct {st.nombre}")
            self.lineas.append("{")
            for c in st.campos:
                self.lineas.append(f"    {self.tipo_c(c.tipo)} {c.nombre};")
            self.lineas.append("};")
            self.lineas.append("")

        # Prototipos primero: dos structs pueden referirse de forma finita a
        # traves de listas (A contiene lista<B>, B contiene lista<A>).
        for st in self.orden_structs(structs):
            if self.c.posee(st.nombre):
                self.lineas.append(f"static void ss_drop_{st.nombre}({st.nombre}* p);")
        if any(self.c.posee(st.nombre) for st in structs):
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
        # Bloques: reservar y cambiar de tamaño. Siempre a ceros, y al
        # encoger se libera lo que se queda fuera antes de soltar la memoria.
        for t, nombre in self.bloques.items():
            elem = elem_bloque(t)
            tc_elem = self.tipo_c(elem)
            m = mangle(t)
            self.lineas.extend([
                "SS_LANG_QUIZA_SIN_USAR",
                f"static {nombre} ss_lang_bloque_nuevo_{m}(size_t n,",
                "        const char* archivo, int linea)",
                "{",
                f"    {nombre} b = {{ NULL, 0 }};",
                "    if (n == 0) return b;",
                f"    if (n > SIZE_MAX / sizeof({tc_elem}))",
                "        ss_lang_sin_memoria_(archivo, linea);",
                f"    b.e = ({tc_elem}*) calloc(n, sizeof({tc_elem}));",
                "    if (b.e == NULL) ss_lang_sin_memoria_(archivo, linea);",
                "    b.n = n;",
                "    return b;",
                "}",
                "",
                "SS_LANG_QUIZA_SIN_USAR",
                f"static void ss_lang_bloque_cambiar_{m}({nombre}* p, size_t n,",
                "        const char* archivo, int linea)",
                "{",
                "    if (n == p->n) return;",
                *( ["    if (n < p->n)",
                    "        for (size_t i = n; i < p->n; i++)",
                    "        {",
                    *self.lineas_liberacion("p->e[i]", elem, 3),
                    "        }"] if self.c.posee(elem) else []),
                "    if (n == 0)",
                "    {",
                "        free(p->e); p->e = NULL; p->n = 0; return;",
                "    }",
                f"    if (n > SIZE_MAX / sizeof({tc_elem}))",
                "        ss_lang_sin_memoria_(archivo, linea);",
                f"    void* memoria = realloc(p->e, n * sizeof({tc_elem}));",
                "    if (memoria == NULL) ss_lang_sin_memoria_(archivo, linea);",
                f"    p->e = ({tc_elem}*) memoria;",
                "    /* Lo nuevo nace a ceros, que en Tcode es un valor valido. */",
                "    if (n > p->n)",
                f"        memset(p->e + p->n, 0, (n - p->n) * sizeof({tc_elem}));",
                "    p->n = n;",
                "}",
                "",
            ])

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
            res_v = self.tipo_resultado(self._tipo_obtener(v))
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
                (f"    nuevo.valores = ({tc_v}*) calloc(nueva, sizeof({tc_v}));"
                 if self.c.posee(v) else
                 f"    nuevo.valores = ({tc_v}*) malloc(nueva * sizeof({tc_v}));"),
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
                *(["        /* el valor viejo era nuestro */"]
                  + self.lineas_liberacion("p->valores[i]", v, 2)
                  if self.c.posee(v) else []),
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
                (f"    return ({res_v}){{ .motivo = NULL, "
                 f".valor = ss_view(&p->valores[i]) }};" if v == "str" else
                 f"    return ({res_v}){{ .motivo = NULL, "
                 f".valor = &p->valores[i] }};" if self.c.posee(v) else
                 f"    return ({res_v}){{ .motivo = NULL, .valor = p->valores[i] }};"),
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
                *([] if not self.c.es_compuesto(v) else [
                    "SS_LANG_QUIZA_SIN_USAR",
                    f"static {self.tipo_resultado(f'&mut {v}')} "
                    f"ss_mapa_obtener_mut_{m}({nombre}* p, SafeView clave)",
                    "{",
                    "    if (p->capacidad == 0)",
                    f'        return ({self.tipo_resultado(f"&mut {v}")})'
                    f'{{ .motivo = "la clave no esta en el mapa" }};',
                    f"    size_t i = ss_mapa_sitio_{m}(p, clave);",
                    "    if (p->claves[i].data == NULL)",
                    f'        return ({self.tipo_resultado(f"&mut {v}")})'
                    f'{{ .motivo = "la clave no esta en el mapa" }};',
                    f"    return ({self.tipo_resultado(f'&mut {v}')})"
                    f"{{ .motivo = NULL, .valor = &p->valores[i] }};",
                    "}",
                    "",
                ]),
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
                *(self.lineas_liberacion("p->valores[i]", v, 1)
                  + [f"    memset(&p->valores[i], 0, sizeof({tc_v}));"]
                  if self.c.posee(v) else []),
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
                "        if (p->claves[i].data != NULL)",
                "        {",
                "            ss_free(&p->claves[i]);",
                *(self.lineas_liberacion("p->valores[i]", v, 3)
                  if self.c.posee(v) else []),
                "        }",
                "    free(p->claves); free(p->valores);",
                "    p->claves = NULL; p->valores = NULL;",
                "    p->largo = 0; p->capacidad = 0;",
                "}",
                "",
            ])


        # liberadores de los structs que poseen memoria
        for st in self.orden_structs(structs):
            if not self.c.posee(st.nombre):
                continue
            self.lineas.append("SS_LANG_QUIZA_SIN_USAR")
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

        # Copiadores. Se descubren generando las funciones, asi que el hueco
        # se reserva aqui y se rellena al final: un copiador puede necesitar
        # otro, y los prototipos van todos delante.
        hueco_funciones = len(self.lineas)
        hueco_aritmetica = len(self.lineas)
        hueco_copiadores = len(self.lineas)

        for f in funciones:
            if f.nombre != "main":
                self.lineas.append(self.prototipo(f) + ";")
        self.lineas.append("")

        for f in funciones:
            self.funcion(f)
            self.lineas.append("")

        # De dentro hacia fuera: el copiador de `lista<Cosa>` llama al de
        # `Cosa`, asi que el de `Cosa` tiene que estar definido antes.
        copiadores = []
        vistos = set()
        while len(vistos) < len(self.copiadores):
            for tipo, nombre in list(self.copiadores.items()):
                if tipo in vistos:
                    continue
                vistos.add(tipo)
                copiadores.append((tipo, nombre))
        copiadores.sort(key=lambda tn: hondura_tipo(tn[0]))
        cuerpo = []
        for tipo, nombre in copiadores:
            cuerpo.append(f"static {self.tipo_c(tipo)} {nombre}"
                          f"(const {self.tipo_c(tipo)}* p);")
        cuerpo.append("")
        for tipo, nombre in copiadores:
            cuerpo.extend(self.cuerpo_copiador(tipo, nombre))
        self.lineas[hueco_copiadores:hueco_copiadores] = cuerpo

        # Solo los anchos que el programa usa, y solo las conversiones que
        # aparecen: un programa de `usize` no carga con las nueve familias.
        arit = []
        for t in sorted(self.aritmeticas):
            suf, tc, tmax, tmin = ARITMETICA[t]
            if tmin is None:
                arit.append(f"SS_LANG_ARIT_U({suf}, {tc}, {tmax})")
            else:
                sin_signo = TIPOS_C[t.replace("i", "u", 1)]
                arit.append(f"SS_LANG_ARIT_I({suf}, {tc}, {sin_signo}, "
                            f"{tmax}, {tmin})")
        for t in sorted(self.decimales):
            arit.append(f"SS_LANG_ARIT_F({t}, {DECIMALES[t]})")
        for destino, origen in sorted(self.conversiones):
            arit.append(f"SS_LANG_CONV({destino}, {TIPOS_C[destino]}, "
                        f"{origen}, {TIPOS_C[origen]})")
        if arit:
            arit.append("")
        self.lineas[hueco_aritmetica:hueco_aritmetica] = arit

        tipos_fn = []
        for t, nombre in self.tipos_funcion.items():
            params, retorno = partes_funcion(t)
            firma = ", ".join(self.tipo_c(x) for x in params) or "void"
            tipos_fn.append(f"typedef {self.tipo_c(retorno)} "
                            f"(*{nombre})({firma});")
        if tipos_fn:
            tipos_fn.append("")
        self.lineas[hueco_funciones:hueco_funciones] = tipos_fn

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
        self.marcar(f)
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

        if es_bloque(tipo):
            elem = elem_bloque(tipo)
            if self.c.posee(elem):
                self.bucle += 1
                i = f"ss_i{self.bucle}"
                self.emitir(f"for (size_t {i} = 0; {i} < {expr_c}.n; {i}++)")
                self.emitir("{")
                self.sangria += 1
                self.liberacion(f"{expr_c}.e[{i}]", elem)
                self.sangria -= 1
                self.emitir("}")
            self.emitir(f"free({expr_c}.e);")
            self.emitir(f"{expr_c}.e = NULL;")
            self.emitir(f"{expr_c}.n = 0;")
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
        """Todo lo que esta vivo aqui: los temporales de la sentencia en curso
        y las variables de todos los bloques abiertos.

        Los cinco sitios que salen antes de tiempo (`falla`, los tres caminos
        de `return` y la rama de fallo de `try`) pasan por aqui. Si los
        temporales no se soltaran, `return $"{rellenar(v, 8)}"` filtraria el
        `str` de `rellenar`: la limpieza de fin de sentencia se emite despues
        del `return` y no se ejecuta nunca.

        No se vacia la lista: `try` llama desde dentro de una rama, y el
        camino en que no falla tiene que soltarlos igual al acabar.
        """
        for t in self.temporales:
            self.liberacion(t, self.tipo_var(t) or "str")
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

    def reclamar(self, valor_c):
        """Quien se queda con un temporal lo dice, y deja de liberarse aqui."""
        if valor_c in self.temporales:
            self.temporales.remove(valor_c)

    def sentencia(self, s):
        self.marcar(s)
        anteriores = self.temporales
        self.temporales = []
        with self.camino():
            self._sentencia(s)
        for t in self.temporales:
            # Un temporal puede ser un `str`, una lista o un mapa: se libera
            # segun lo que sea, no siempre con `ss_free`.
            self.liberacion(t, self.tipo_var(t) or "str")
        self.temporales = anteriores

    def _sentencia(self, s):
        if isinstance(s, Declaracion):
            tc = self.tipo_c(s.tipo)
            # Una variable declarada y no usada es legitima en Tcode; el aviso
            # de gcc apuntaria a este C, que el usuario no escribio.
            valor_c = self.expr(s.valor, s.tipo)
            self.reclamar(valor_c)      # la variable se queda con el temporal
            self.emitir(f"SS_LANG_QUIZA_SIN_USAR {tc} {s.nombre} = {valor_c};")
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

            # El valor se calcula ANTES de soltar el viejo: la expresion
            # puede leer el destino, y ademas puede haberlo movido.
            valor_c = self.expr(s.valor, tipo)
            self.reclamar(valor_c)

            if self.c.posee(tipo):
                # Y se guarda en un temporal antes de liberar, porque en C lo
                # que cuenta no es donde se genero la expresion sino donde
                # queda escrita: `s = nuevo(rebanar(vista(s), ...))` leeria
                # `s` despues de soltarlo.
                guardado = self.nuevo_tmp()
                self.emitir(f"{self.tipo_c(tipo)} {guardado} = {valor_c};")
                self.declarar(guardado, tipo)
                valor_c = guardado
                con_bandera = (isinstance(s.lugar, Variable)
                               and s.lugar.nombre in self.con_bandera)
                if con_bandera:
                    # Si ya se lo llevaron, aqui no hay nada que devolver:
                    # liberarlo seria soltarlo dos veces.
                    bandera = f"ss_vivo_{s.lugar.nombre}"
                    self.emitir(f"if ({bandera})")
                    self.emitir("{")
                    self.sangria += 1
                    self.liberacion(destino, tipo)
                    self.sangria -= 1
                    self.emitir("}")
                    self.emitir(f"{destino} = {valor_c};")
                    self.emitir(f"{bandera} = true;")
                    return
                # el valor viejo se pierde: devolverlo antes de pisarlo
                self.liberacion(destino, tipo)

            self.emitir(f"{destino} = {valor_c};")
            return

        if isinstance(s, Si):
            self.emitir(f"if ({self.expr(s.cond, 'bool')})")
            self.bloque(s.entonces)
            if s.sino is not None:
                self.emitir("else")
                self.bloque(s.sino)
            return

        if isinstance(s, Para):
            tipo = sin_prestamo(self._tipo_de(s.coleccion) or "")
            if isinstance(s.coleccion, (Variable, Campo, Indice)):
                lugar = self.lugar(s.coleccion)
            else:
                # `for x en f(...)`: la coleccion se calcula UNA vez. Si se
                # dejara la llamada en la condicion del bucle se repetiria en
                # cada vuelta, y cada vuelta filtraria una copia.
                lugar = self.nuevo_tmp()
                valor = self.expr(s.coleccion, tipo)
                self.reclamar(valor)
                self.emitir(f"{self.tipo_c(tipo)} {lugar} = {valor};")
                self.declarar(lugar, tipo)
                if self.c.posee(tipo):
                    self.temporales.append(lugar)
            self.bucle += 1
            i = f"ss_k{self.bucle}"

            if es_mapa(tipo):
                k, v = partes_mapa(tipo)
                # Se recorren las celdas de la tabla y se saltan las vacias.
                # Nadie copia una clave: se presta la que ya esta ahi.
                self.emitir(f"for (size_t {i} = 0; {i} < {lugar}.capacidad;"
                            f" {i}++)")
                self.emitir("{")
                self.sangria += 1
                self.emitir(f"if ({lugar}.claves[{i}].data == NULL) continue;")
            else:
                tope = (f"{lugar}.length" if es_lista(tipo)
                        else str(largo_arreglo(tipo)))
                self.emitir(f"for (size_t {i} = 0; {i} < {tope}; {i}++)")
                self.emitir("{")
                self.sangria += 1

            self.pila.append([])
            self.vars.append({})
            self.bucles.append(len(self.pila))

            # El elemento se presta, no se copia: un `str` copiado tendria dos
            # duenios. Los escalares van por valor porque no hay nada que
            # duplicar.
            if es_mapa(tipo):
                elem, tipo_valor = partes_mapa(tipo)
                acceso = f"{lugar}.claves[{i}]"
            else:
                elem = elem_lista(tipo) if es_lista(tipo) else elem_de(tipo)
                tipo_valor = None
                acceso = f"{lugar}.e[{i}]"

            if self.c.posee(elem):
                self.emitir(f"SS_LANG_QUIZA_SIN_USAR const "
                            f"{self.tipo_c(elem)}* {s.variable} = &{acceso};")
                self.declarar(s.variable, elem, True)
            else:
                self.emitir(f"SS_LANG_QUIZA_SIN_USAR {self.tipo_c(elem)} "
                            f"{s.variable} = {acceso};")
                self.declarar(s.variable, elem)

            if tipo_valor is not None and s.valor is not None:
                self.emitir(f"SS_LANG_QUIZA_SIN_USAR {self.tipo_c(tipo_valor)} "
                            f"{s.valor} = {lugar}.valores[{i}];")
                self.declarar(s.valor, tipo_valor)

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
            self.temporales = []
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
            self.reclamar(valor)
            envolver = (lambda v: f"({self.tipo_resultado(self.func.retorno)})"
                                  f"{{ .motivo = NULL, .valor = {v} }}") \
                       if falible else (lambda v: v)
            if devuelta is not None:
                self._apagar_ahora()
                self.liberar_todo(excepto=entregadas)
                self.emitir(f"return {envolver(devuelta)};")
                self.temporales = []
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
                self.temporales = []
            return

        if isinstance(s, ExprSentencia):
            c = self.expr(s.expr, None)
            tipo = self._tipo_de(s.expr)

            # Una sentencia suelta descarta el valor. Si ese valor era duenio
            # de memoria, aqui es donde se devuelve: `try espera(...)` como
            # sentencia tira el `str` que devuelve, y nadie mas lo iba a
            # liberar.
            if c and tipo not in (None, UNIDAD) and self.c.posee(tipo):
                self.reclamar(c)
                # `liberacion` toma la direccion de lo que libera, y el
                # resultado de una llamada no tiene direccion: `f();` a secas
                # daba `ss_free(&f())`, que ni siquiera es C. Se guarda antes.
                if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", c):
                    tmp = self.nuevo_tmp()
                    self.emitir(f"{self.tipo_c(tipo)} {tmp} = {c};")
                    self.declarar(tmp, tipo)
                    c = tmp
                self.liberacion(c, tipo)
                return

            # `try f();` y `f() sino x;` ya emitieron todo el trabajo al
            # generarse; lo que devuelven es el valor, y como sentencia suelta
            # no haria nada. Emitirlo daria un aviso de C sobre codigo que el
            # usuario no escribio.
            if c and not isinstance(s.expr, (Try, Sino)):
                self.emitir(c + ";")
            return

        raise AssertionError(type(s).__name__)

    def _tipo_de(self, e):
        if isinstance(e, Entero):
            return "usize"
        if isinstance(e, Decimal):
            return "f64"
        if isinstance(e, Cadena):
            return "view"
        if isinstance(e, Booleano):
            return "bool"
        if isinstance(e, Variable):
            return self.tipo_var(e.nombre) or "usize"
        if isinstance(e, Llamada):
            if e.nombre in ("obtener", "obtener_mut", "tiene", "claves",
                            "quitar") and e.args:
                tm = self._tipo_de(e.args[0])
                if es_mapa(tm):
                    k, v = partes_mapa(tm)
                    if e.nombre == "obtener":
                        # Un valor duenio no sale del mapa: sale prestado.
                        return self._tipo_obtener(v)
                    if e.nombre == "obtener_mut":
                        return f"&mut {v}"
                    if e.nombre in ("tiene", "quitar"):
                        return "bool"
                    return f"lista<{k}>"
            if e.nombre in ("raiz", "piso", "techo", "redondear") and e.args:
                t = sin_prestamo(self._tipo_de(e.args[0]) or "f64")
                return t if t in DECIMALES else "f64"
            if e.nombre == "absoluto" and e.args:
                return sin_prestamo(self._tipo_de(e.args[0]) or "f64")
            if e.nombre == "intercambiar" and e.args:
                return sin_prestamo(self._tipo_de(e.args[0]) or "usize")
            if e.nombre == "copiar" and e.args:
                # Una copia tiene el tipo de lo copiado, ya sin el prestamo.
                t = sin_prestamo(self._tipo_de(e.args[0]) or "usize")
                return t
            if e.nombre in INTERNAS:
                return INTERNAS[e.nombre]["retorno"]
            f = self.c.funciones.get(e.nombre)
            return f.retorno if f else "usize"
        if isinstance(e, Conversion):
            return e.a_tipo
        if isinstance(e, SiExpr):
            t = self._tipo_de(e.entonces)
            return t if t not in (None, "usize") else self._tipo_de(e.sino_)
        if isinstance(e, Try):
            return self._tipo_de(e.expr)
        if isinstance(e, Sino):
            return self._tipo_de(e.expr)
        if isinstance(e, Campo):
            base = self._tipo_de(e.objeto)
            if es_referencia(base):
                base = apuntado(base)
            st = self.c.structs.get(base)
            if st:
                for c in st.campos:
                    if c.nombre == e.nombre:
                        return c.tipo
            return "usize"
        if isinstance(e, Indice):
            base = sin_prestamo(self._tipo_de(e.arreglo) or "")
            if es_arreglo(base):
                return elem_de(base)
            if es_bloque(base):
                return elem_bloque(base)
            if es_lista(base):
                return elem_lista(base)
            return "usize"
        if isinstance(e, Interpolada):
            return "str"
        if isinstance(e, LiteralStruct):
            return e.tipo
        if isinstance(e, Cierre):
            return e.tipo_struct
        if isinstance(e, LiteralArreglo):
            elem = self._tipo_de(e.elementos[0]) if e.elementos else "usize"
            return f"[{elem}; {len(e.elementos)}]"
        if isinstance(e, Binaria):
            if e.op in {"==", "!=", "<", "<=", ">", ">=", "&&", "||"}:
                return "bool"
            return self._tipo_de(e.izq)
        if isinstance(e, Unaria):
            return "bool" if e.op == "!" else self._tipo_de(e.valor)
        if isinstance(e, Conversion):
            return e.a_tipo
        return "usize"

    # ---------- expresiones ----------

    def expr(self, e, esperado):
        if isinstance(e, Entero):
            if esperado in DECIMALES:
                # `let x: f64 = 0;` — un numero escrito no decide su tipo.
                return f"{e.valor}.0f" if esperado == "f32" else f"{e.valor}.0"
            if esperado == "i64":
                return f"(int64_t){e.valor}"
            # Sin sufijo, un literal por encima de 2^63-1 no cabe en el tipo
            # que C le asigna por defecto y el compilador avisa. `ULL` le dice
            # cual es sin cambiar el valor.
            sufijo = "ULL" if e.valor > 9223372036854775807 else ""
            return f"(size_t){e.valor}{sufijo}"

        if isinstance(e, Cadena):
            return (f"sv_len({self.literal_c(e.valor)}, "
                    f"{len(bytes_de(e.valor))})")

        if isinstance(e, Decimal):
            # Tal cual se escribio, con sufijo si el destino es de 32 bits.
            lit = e.valor if ("." in e.valor or "e" in e.valor.lower()) \
                  else e.valor + ".0"
            return f"{lit}f" if esperado == "f32" else lit

        if isinstance(e, Booleano):
            return "true" if e.valor else "false"

        if isinstance(e, Interpolada):
            # Se baja a un `str` que se va llenando: cada trozo se agrega tal
            # cual y cada expresion pasa por la misma conversion que
            # `imprimir`. No hay formato en tiempo de ejecucion ni printf con
            # cadena variable: el tipo de cada hueco se conoce al compilar.
            tmp = self.nuevo_tmp()
            self.emitir(f"SafeString {tmp} = ss_new();")
            self.declarar(tmp, "str")
            self.temporales.append(tmp)
            for k, trozo in enumerate(e.trozos):
                if trozo:
                    lit = self.literal_c(trozo)
                    self.emitir(f"ss_lang_agregar_texto_(&{tmp}, "
                                f"sv_len({lit}, {len(bytes_de(trozo))}), "
                                f"{self.arch(e)}, {e.linea});")
                if k < len(e.expresiones):
                    x = e.expresiones[k]
                    tx = self._tipo_de(x)
                    if tx == "str":
                        # `como_vista` sabe guardar en un temporal lo que no
                        # tiene sitio propio, como `{unir(xs, ", ")}`.
                        vista = self.como_vista(x)
                    elif tx == "view":
                        vista = self.como_vista(x)
                    else:
                        conv = self.expr(x, tx)
                        pieza = self.nuevo_tmp()
                        self.emitir(f"SafeString {pieza} = "
                                    f"{self.texto_de(conv, tx, e)};")
                        self.declarar(pieza, "str")
                        self.temporales.append(pieza)
                        vista = f"ss_view(&{pieza})"
                    self.emitir(f"ss_lang_agregar_texto_(&{tmp}, {vista}, "
                                f"{self.arch(e)}, {e.linea});")
            return tmp

        if isinstance(e, Variable) and getattr(e, "es_funcion", False):
            return e.nombre

        if isinstance(e, Variable):
            if getattr(e, "mueve", False) and e.nombre in self.con_bandera:
                self.pendientes.append(e.nombre)
            # un parametro `mut str` llega como puntero
            if self.es_puntero(e.nombre):
                return f"(*{e.nombre})"
            return e.nombre

        if isinstance(e, Unaria):
            if e.op == "~":
                return self.unaria_bits(e, esperado)
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

        if isinstance(e, Cierre):
            # La clausura es su struct: lo capturado, por valor. Lo que posee
            # memoria se movio al capturarlo, asi que aqui se entrega.
            st = self.c.structs[e.tipo_struct]
            piezas = []
            for c in st.campos:
                if c.nombre == "ss_vacio":
                    piezas.append(".ss_vacio = 0")
                    continue
                v = Variable(c.nombre, linea=e.linea)
                # Capturar lo que posee memoria es entregarlo: a partir de
                # aqui el duenio es el struct de la clausura.
                v.mueve = self.c.posee(c.tipo)
                piezas.append(f".{c.nombre} = {self.expr(v, c.tipo)}")
            partes = ", ".join(piezas)
            return f"({e.tipo_struct}){{ {partes} }}"

        if isinstance(e, LiteralStruct):
            st = self.c.structs.get(e.tipo)
            tipos = {c.nombre: c.tipo for c in st.campos} if st else {}
            piezas = []
            for n, v in e.campos:
                valor = self.expr(v, tipos.get(n))
                # El struct se queda con el campo: si venia de un temporal de
                # la sentencia, deja de liberarse ahi.
                self.reclamar(valor)
                piezas.append(f".{n} = {valor}")
            return f"({e.tipo}){{ {', '.join(piezas)} }}"

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
                    self.reclamar(valor)
                    self.emitir(f"ss_push_{mangle(esperado)}(&{tmp}, {valor}, "
                                f"{self.arch(e)}, {e.linea});")
                return tmp
            t = esperado if (esperado and es_arreglo(esperado)) else self._tipo_de(e)
            elem = elem_de(t)
            partes = ", ".join(self.expr(x, elem) for x in e.elementos)
            return f"({self.tipo_c(t)}){{{{ {partes} }}}}"

        if isinstance(e, SiExpr):
            # Se baja a una variable y un `if`, no al `?:` de C: cada rama
            # puede necesitar emitir lineas propias (un temporal, una
            # bandera), y dentro de `?:` no caben.
            t = self._tipo_de(e) or "usize"
            tmp = self.nuevo_tmp()
            self.emitir(f"{self.tipo_c(t)} {tmp};")
            self.declarar(tmp, t)
            self.emitir(f"if ({self.expr(e.cond, 'bool')})")
            self.emitir("{")
            self.sangria += 1
            with self.camino():
                self.emitir(f"{tmp} = {self.expr(e.entonces, t)};")
            self.sangria -= 1
            self.emitir("}")
            self.emitir("else")
            self.emitir("{")
            self.sangria += 1
            with self.camino():
                self.emitir(f"{tmp} = {self.expr(e.sino_, t)};")
            self.sangria -= 1
            self.emitir("}")
            if self.c.posee(t):
                self.temporales.append(tmp)
            return tmp

        if isinstance(e, Conversion):
            return self.conversion(e)

        if isinstance(e, Binaria):
            return self.binaria(e, esperado)

        if isinstance(e, Llamada):
            return self.llamada(e, esperado)

        raise AssertionError(type(e).__name__)

    def como_lugar(self, e):
        """Un sitio del que tomar campos o elementos.

        Una llamada no es un sitio: `hacer()[1]` tiene que guardar lo que
        devuelve antes de indexarlo. Si no, la llamada se evalua una vez por
        cada vez que aparece en el C (dos: el elemento y el largo) y lo que
        devuelve no lo libera nadie.
        """
        if isinstance(e, (Variable, Campo, Indice)):
            return self.lugar(e)
        t = self._tipo_de(e) or "usize"
        tmp = self.nuevo_tmp()
        valor = self.expr(e, t)
        self.reclamar(valor)
        self.emitir(f"{self.tipo_c(t)} {tmp} = {valor};")
        self.declarar(tmp, t)
        if self.c.posee(t):
            self.temporales.append(tmp)
        return tmp

    def lugar(self, e):
        """C para un sitio al que se puede leer y escribir."""
        if isinstance(e, Variable):
            return f"(*{e.nombre})" if self.es_puntero(e.nombre) else e.nombre
        if isinstance(e, Campo):
            # `como_lugar` ya devuelve el valor, no el puntero: un prestamo
            # sale como `(*x)`, asi que aqui siempre es un punto.
            return f"{self.como_lugar(e.objeto)}.{e.nombre}"
        if isinstance(e, Indice):
            base = self._tipo_de(e.arreglo)
            idx = self.expr(e.indice, "usize")
            sitio = self.como_lugar(e.arreglo)
            if es_bloque(base):
                return (f"{sitio}.e[ss_lang_indice_({idx}, {sitio}.n, "
                        f"{self.arch(e)}, {e.linea})]")
            if es_lista(base):
                return (f"{sitio}.e[ss_lang_indice_({idx}, {sitio}.length, "
                        f"{self.arch(e)}, {e.linea})]")
            n = largo_arreglo(base) if es_arreglo(base) else 0
            return (f"{sitio}.e"
                    f"[ss_lang_indice_({idx}, {n}, {self.arch(e)}, {e.linea})]")
        return self.expr(e, None)

    def unaria_bits(self, e, esperado):
        t = self._tipo_de(e.valor)
        if t not in ARITMETICA:
            t = esperado if esperado in ARITMETICA else "usize"
        return f"(({self.tipo_c(t)}) ~{self.expr(e.valor, t)})"

    def binaria(self, e: Binaria, esperado):
        t = self._tipo_de(e.izq)
        if t not in ARITMETICA and t not in DECIMALES:
            t = self._tipo_de(e.der)
        if t not in ARITMETICA and t not in DECIMALES:
            if esperado in ARITMETICA or esperado in DECIMALES:
                t = esperado
            else:
                t = "usize"
        pos = f"{self.arch(e)}, {e.linea}"

        if t in DECIMALES:
            izq = self.expr(e.izq, t)
            der = self.expr(e.der, t)
            if e.op in {"+", "-", "*", "/"}:
                self.decimales.add(t)
                consejo = f"Si lo querias, escribe `{e.op}?`."
                return (f"ss_lang_fin_{t}(({izq} {e.op} {der}), "
                        f"\"{e.op}\", \"{consejo}\", {pos})")
            if e.op in {"+?", "-?", "*?", "/?"}:
                return f"({izq} {e.op[0]} {der})"
            return f"({izq} {e.op} {der})"

        # El desplazamiento tiene dos tipos: lo que se mueve y cuanto se mueve.
        if e.op in {"<<", ">>"}:
            self.usar_aritmetica(t)
            izq = self.expr(e.izq, t)
            der = self.expr(e.der, "usize")
            fn = "izq" if e.op == "<<" else "der"
            return f"ss_lang_desp_{fn}_{ARITMETICA[t][0]}({izq}, {der}, {pos})"

        izq = self.expr(e.izq, t)
        der = self.expr(e.der, t)

        if e.op in {"+", "-", "*"}:
            self.usar_aritmetica(t)
            nombre = {"+": "suma", "-": "resta", "*": "mul"}[e.op]
            return f"ss_lang_{nombre}_{ARITMETICA[t][0]}({izq}, {der}, {pos})"

        if e.op in {"+?", "-?", "*?"}:
            # Envolvente, pedida a proposito. El molde deja claro que el
            # resultado no se ensancha por el camino.
            return f"(({self.tipo_c(t)}) ({izq} {e.op[0]} {der}))"

        if e.op == "/":
            return f"SS_LANG_DIV({izq}, {der}, {pos})"
        if e.op == "%":
            return f"SS_LANG_MOD({izq}, {der}, {pos})"
        if e.op in {"&", "|", "^"}:
            return f"(({self.tipo_c(t)}) ({izq} {e.op} {der}))"

        return f"({izq} {e.op} {der})"

    def conversion(self, e):
        origen = sin_prestamo(self._tipo_de(e.valor) or "usize")
        if origen not in ARITMETICA and origen not in DECIMALES:
            origen = "usize"
        destino = e.a_tipo
        valor = self.expr(e.valor, origen)
        if origen == destino:
            return valor
        if e.envolviendo:
            # Pedida a proposito: se queda con los bits de abajo.
            return f"(({self.tipo_c(destino)}) {valor})"
        self.conversiones.add((destino, origen))
        return (f"ss_lang_conv_{destino}_de_{origen}({valor}, "
                f"{self.arch(e)}, {e.linea})")

    def usar_aritmetica(self, tipo):
        """Anota que el programa necesita las operaciones de este ancho. Solo
        se emiten las que se usan: un programa con `usize` no carga con las
        nueve familias."""
        if tipo in ARITMETICA:
            self.aritmeticas.add(tipo)

    def llamada(self, e: Llamada, esperado=None):
        n = e.nombre

        if n == "vacio":
            return "ss_new()"
        if n == "nuevo":
            return f"ss_from_view({self.como_vista(e.args[0])})"
        if n == "vista":
            return f"ss_view({self.dir_de(e.args[0])})"
        if n == "largo":
            t = self._tipo_de(e.args[0])
            t = apuntado(t) if es_referencia(t) else t
            if es_bloque(t):
                return f"({self.como_lugar(e.args[0])}.n)"
            if es_mapa(t):
                return f"({self.lugar(e.args[0])}.largo)"
            if es_lista(t):
                if isinstance(e.args[0], (Variable, Campo, Indice)):
                    return f"({self.lugar(e.args[0])}.length)"
                tmp = self.nuevo_tmp()
                valor = self.expr(e.args[0], t)
                self.reclamar(valor)
                self.emitir(f"{self.tipo_c(t)} {tmp} = {valor};")
                self.declarar(tmp, t)
                self.temporales.append(tmp)
                return f"({tmp}.length)"
            if es_arreglo(t):
                return f"((size_t){largo_arreglo(t)})"
            return f"sv_len_of({self.como_vista(e.args[0])})"
        if n in ("igual", "menor"):
            ta = sin_prestamo(self._tipo_de(e.args[0]) or "view")
            op = "==" if n == "igual" else "<"
            if ta in ("str", "view"):
                if n == "igual":
                    return (f"sv_equals({self.como_vista(e.args[0])}, "
                            f"{self.como_vista(e.args[1])})")
                return (f"(sv_cmp({self.como_vista(e.args[0])}, "
                        f"{self.como_vista(e.args[1])}) < 0)")
            # Escalares: la comparacion de C, que es la que el lector espera.
            return (f"({self.expr(e.args[0], ta)} {op} "
                    f"{self.expr(e.args[1], ta)})")
        if n == "rebanar":
            return (f"sv_slice({self.como_vista(e.args[0])}, "
                    f"{self.expr(e.args[1], 'usize')}, "
                    f"{self.expr(e.args[2], 'usize')})")
        if n == "empujar":
            return (f"ss_append_view({self.dir_de(e.args[0])}, "
                    f"{self.como_vista(e.args[1])})")
        if n == "empujar_byte":
            return (f"ss_lang_empujar_byte_({self.dir_de(e.args[0])}, "
                    f"{self.expr(e.args[1], 'u8')}, {self.arch(e)}, {e.linea})")
        if n == "imprimir":
            return self.imprimir(e.args[0])
        if n == "anadir":
            lista = e.args[0]
            tipo_lista = self._tipo_de(lista)
            elem = elem_lista(tipo_lista)
            valor = self.expr(e.args[1], elem)
            # La lista se queda con el valor: si venia de un temporal de la
            # sentencia, deja de liberarse ahi. Sin esto, `anadir(xs, $"...")`
            # mete el texto en la lista y lo libera al acabar la linea.
            self.reclamar(valor)
            return (f"ss_push_{mangle(tipo_lista)}({self.dir_de(lista)}, {valor}, "
                    f"{self.arch(e)}, {e.linea})")
        if n in ("raiz", "piso", "techo", "redondear", "absoluto"):
            t = sin_prestamo(self._tipo_de(e.args[0]) or "f64")
            if t not in DECIMALES and t not in ARITMETICA:
                t = "f64"
            valor = self.expr(e.args[0], t)
            if t in DECIMALES:
                sufijo = "f" if t == "f32" else ""
                fn = {"raiz": "sqrt", "piso": "floor", "techo": "ceil",
                      "redondear": "round", "absoluto": "fabs"}[n]
                self.decimales.add(t)
                # `raiz` de un negativo da NaN: la misma regla que todo lo
                # demas, y por eso pasa por la comprobacion.
                consejo = {
                    "raiz": "Comprueba el signo antes: la raiz de un negativo "
                            "no es un numero.",
                }.get(n, "Comprueba el valor antes de operar con el.")
                return (f"ss_lang_fin_{t}({fn}{sufijo}({valor}), "
                        f"\"{n}\", \"{consejo}\", "
                        f"{self.arch(e)}, {e.linea})")
            # Entero con signo: el valor absoluto de `tmin` no cabe en el tipo.
            self.usar_aritmetica(t)
            return (f"ss_lang_abs_{ARITMETICA[t][0]}({valor}, "
                    f"{self.arch(e)}, {e.linea})")

        if n == "reservar":
            t = esperado if esperado and es_bloque(esperado) else None
            if t is None:
                t = self._tipo_de(e) or "bloque<usize>"
            nombre = self.registrar_bloque(t)
            te = self.tipo_c(elem_bloque(t))
            return (f"ss_lang_bloque_nuevo_{mangle(t)}("
                    f"{self.expr(e.args[0], 'usize')}, {self.arch(e)}, {e.linea})")

        if n == "redimensionar":
            t = self._tipo_de(e.args[0]) or "bloque<usize>"
            t = apuntado(t) if es_referencia(t) else t
            self.registrar_bloque(t)
            return (f"ss_lang_bloque_cambiar_{mangle(t)}({self.dir_de(e.args[0])}, "
                    f"{self.expr(e.args[1], 'usize')}, {self.arch(e)}, {e.linea})")

        if n == "intercambiar":
            destino_nodo, valor_nodo = e.args
            t = self._tipo_de(destino_nodo) or "usize"
            sitio = self.lugar(destino_nodo)
            nuevo = self.expr(valor_nodo, t)
            self.reclamar(nuevo)
            tmp = self.nuevo_tmp()
            # Se saca primero y se pone despues: si el valor nuevo viniera
            # del mismo sitio, hacerlo al reves lo perderia.
            self.emitir(f"{self.tipo_c(t)} {tmp} = {sitio};")
            self.declarar(tmp, t)
            self.emitir(f"{sitio} = {nuevo};")
            return tmp

        if n == "copiar":
            a = e.args[0]
            t = sin_prestamo(self._tipo_de(a) or "")
            if not self.c.posee(t):
                return self.expr(a, t)      # un escalar se copia solo
            if isinstance(a, (Variable, Campo, Indice)):
                return self.copia_de(f"(*{self.dir_de(a)})", t)
            crudo = self._tipo_de(a) or t
            if es_referencia(crudo):
                # Llega prestado y en C eso es un puntero: se copia lo que
                # hay al otro lado, no el puntero.
                return self.copia_de(f"(*{self.expr(a, crudo)})", t)
            # Lo que no vive en ningun sitio hay que guardarlo para poder
            # tomarle la direccion; y como ya es nuestro, se libera al acabar.
            tmp = self.nuevo_tmp()
            valor = self.expr(a, t)
            self.reclamar(valor)
            self.emitir(f"{self.tipo_c(t)} {tmp} = {valor};")
            self.declarar(tmp, t)
            self.temporales.append(tmp)
            return self.copia_de(tmp, t)

        if n == "texto":
            a = e.args[0]
            t = self._tipo_de(a)
            pos = f"{self.arch(e)}, {e.linea}"
            if t == "usize":
                return f"ss_lang_texto_usize_({self.expr(a, t)}, {pos})"
            if t in DECIMALES:
                return (f"ss_lang_texto_view_(sv(ss_lang_texto_decimal_"
                        f"({self.expr(a, t)})), {pos})")
            if t in ARITMETICA:
                if t.startswith("u"):
                    return (f"ss_lang_texto_usize_((size_t) "
                            f"{self.expr(a, t)}, {pos})")
                return f"ss_lang_texto_i64_((int64_t) {self.expr(a, t)}, {pos})"
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
        if n in ("poner", "obtener", "obtener_mut", "tiene", "claves", "quitar"):
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
            if n == "obtener_mut":
                return f"ss_mapa_obtener_mut_{m}({dir_mapa}, {clave})"
            _, tv = partes_mapa(tm)
            valor = self.expr(e.args[2], tv)
            # El mapa se queda con el valor: si venia de un temporal de la
            # sentencia, deja de liberarse ahi.
            self.reclamar(valor)
            return (f"ss_mapa_poner_{m}({dir_mapa}, {clave}, {valor}, "
                    f"{self.arch(e)}, {e.linea})")

        if n == "n_argumentos":
            return "ss_lang_n_argumentos_()"

        if n == "argumento":
            return (f"ss_lang_argumento_({self.expr(e.args[0], 'usize')}, "
                    f"{self.arch(e)}, {e.linea})")

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

        # funcion del usuario, o una variable que guarda una
        f = self.c.funciones.get(n)
        if f is None:
            tv = self.tipo_var(n) or ""
            if es_funcion(tv):
                f = _FirmaSuelta([
                    _ParamSuelto(apuntado(x) if es_referencia(x) else x,
                                 es_referencia(x))
                    for x in partes_funcion(tv)[0]])
        args = []
        for i, a in enumerate(e.args):
            p = f.params[i] if f and i < len(f.params) else None
            if p is not None and p.prestado:
                if isinstance(a, (Variable, Campo, Indice)):
                    args.append(self.dir_de(a))
                else:
                    # Prestar algo recien hecho: se guarda en un temporal para
                    # poder tomarle la direccion, y se libera al acabar la
                    # sentencia como cualquier otro valor descartado.
                    tmp = self.nuevo_tmp()
                    valor = self.expr(a, p.tipo)
                    self.reclamar(valor)
                    self.emitir(f"{self.tipo_c(p.tipo)} {tmp} = {valor};")
                    self.declarar(tmp, p.tipo)
                    if self.c.posee(p.tipo):
                        self.temporales.append(tmp)
                    args.append(f"&{tmp}")
            else:
                # `str` donde se pide `view`: se presta sin escribirlo.
                if (p is not None and p.tipo == "view"
                        and self._tipo_de(a) == "str"):
                    args.append(self.como_vista(a))
                    continue
                arg_c = self.expr(a, p.tipo if p else None)
                if p is not None and self.c.posee(p.tipo):
                    self.reclamar(arg_c)     # la funcion se lo queda
                args.append(arg_c)
        destino = "ss_main_" if n == "main" else n
        return f"{destino}({', '.join(args)})"

    def dir_de(self, a):
        """La direccion de un sitio con nombre: `&x`, `&p.campo`, `&v.e[i]`."""
        if isinstance(a, Variable):
            # Un `&T` ya ES la direccion: pedirsela otra vez sobra.
            if es_referencia(self.tipo_var(a.nombre) or ""):
                return a.nombre
            return self.ref(a.nombre)
        return f"&{self.lugar(a)}"

    def como_vista(self, a):
        """Un argumento donde se pide una SafeView."""
        t = self._tipo_de(a)
        if es_referencia(t) and apuntado(t) == "str":
            # Un `&mut str` ya es el puntero que necesita `ss_view`.
            return f"ss_view({self.lugar(a)})"
        if t != "str":
            return self.expr(a, "view")
        if isinstance(a, (Variable, Campo, Indice)):
            return f"ss_view({self.dir_de(a)})"
        # Un `str` recien hecho no tiene sitio del que tomar la direccion: se
        # guarda en un temporal, que se libera al acabar la sentencia.
        tmp = self.nuevo_tmp()
        valor = self.expr(a, "str")
        self.reclamar(valor)
        self.emitir(f"SafeString {tmp} = {valor};")
        self.declarar(tmp, "str")
        self.temporales.append(tmp)
        return f"ss_view(&{tmp})"

    def imprimir(self, a, destino="stdout"):
        """`imprimir` va al resultado; `imprimir_error` al diagnostico.

        Separarlos no es cosmetico: es lo que permite encauzar la salida de
        una herramienta sin que se le cuelen los mensajes de uso.
        """
        f = "printf(" if destino == "stdout" else f"fprintf({destino}, "
        t = self._tipo_de(a)
        if t == "str":
            if isinstance(a, (Variable, Campo, Indice)):
                return f'{f}"%s", ss_cstr({self.dir_de(a)}))'
            return f'{f}SV_FMT, SV_ARG({self.como_vista(a)}))'
        if t == "view":
            return f'{f}SV_FMT, SV_ARG({self.como_vista(a)}))'
        if t == "usize":
            return f'{f}"%zu", {self.expr(a, "usize")})'
        if t in DECIMALES:
            self.decimales_impresos = True
            return f'{f}"%s", ss_lang_texto_decimal_({self.expr(a, t)}))'
        if t in ARITMETICA:
            # Un ancho fijo se ensancha al mayor para imprimirlo: asi hay un
            # solo formato por signo y no nueve.
            if t.startswith("u"):
                return f'{f}"%llu", (unsigned long long){self.expr(a, t)})'
            return f'{f}"%lld", (long long){self.expr(a, t)})'
        if t == "bool":
            return f'{f}"%s", ({self.expr(a, "bool")}) ? "true" : "false")'
        return f'{f}"%s", "?")'


def generar(funciones, comprobador, archivo="<entrada>", con_lineas=True):
    g = Generador(comprobador, archivo)
    g.con_lineas = con_lineas
    return g.generar(funciones)
