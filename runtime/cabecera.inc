/* Generado por el compilador de Tcode. No editar a mano. */

#include <stdbool.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
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

