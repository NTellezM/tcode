"""Nombres de Tcode que no pueden ir tal cual al C generado.

Tcode no tiene las palabras de C, asi que `union`, `log` o `EOF` son
nombres legales en un programa. Pero el C generado incluye `math.h`,
`stdio.h` y compania, y ahi `log` ya es una funcion y `EOF` una macro:
el C no compilaria, o llamaria a otra cosa. Esos nombres llevan `ss_id_`
delante en todas partes a la vez, asi que el programa significa exactamente
lo mismo; los mensajes quitan el prefijo y dicen el nombre que se escribio.

Es una regla y no una lista de casos: lo que declaran las cabeceras
incluidas (funciones, tipos, macros y etiquetas de struct en C17 estricto),
las palabras de C, lo del runtime (`ss_`, `sv_`, `SS_`, `SV_`, `SafeView`),
los nombres reservados de C (`_Bool`, `__x`) y el struct de una clausura.
El compilador escrito en Tcode aplica la misma regla, en `lib/programa.t`.

No se tocan: `main`, lo que declara un `externo` (es el nombre de la funcion
de C), las formas de un enum (en C siempre van con prefijo: `SS_E_A`,
`v_A`) ni los alias de modulo, que no llegan a C.
"""

import re

from tcode.nodos import (
    Variable, Llamada, Campo, CampoDef, Declaracion, Parametro, Funcion,
    Struct, Enum, VarianteDef, EnumLit, LiteralStruct, Conversion, Para,
    Cierre, Brazo, PatronForma, Interpolada,
)

PREFIJO = "ss_id_"

NOMBRES_C = frozenset("""
BUFSIZ CLOCKS_PER_SEC DBL_DECIMAL_DIG DBL_DIG DBL_EPSILON DBL_HAS_SUBNORM
DBL_MANT_DIG DBL_MAX DBL_MAX_10_EXP DBL_MAX_EXP DBL_MIN DBL_MIN_10_EXP
DBL_MIN_EXP DBL_TRUE_MIN DECIMAL_DIG EOF EXIT_FAILURE EXIT_SUCCESS FILE
FILENAME_MAX FLT_DECIMAL_DIG FLT_DIG FLT_EPSILON FLT_EVAL_METHOD
FLT_HAS_SUBNORM FLT_MANT_DIG FLT_MAX FLT_MAX_10_EXP FLT_MAX_EXP FLT_MIN
FLT_MIN_10_EXP FLT_MIN_EXP FLT_RADIX FLT_ROUNDS FLT_TRUE_MIN FOPEN_MAX
FP_ILOGB0 FP_ILOGBNAN FP_INFINITE FP_NAN FP_NORMAL FP_SUBNORMAL FP_ZERO
HUGE_VAL HUGE_VALF HUGE_VALL INFINITY INT16_C INT16_MAX INT16_MIN INT32_C
INT32_MAX INT32_MIN INT64_C INT64_MAX INT64_MIN INT8_C INT8_MAX INT8_MIN
INTMAX_C INTMAX_MAX INTMAX_MIN INTPTR_MAX INTPTR_MIN INT_FAST16_MAX
INT_FAST16_MIN INT_FAST32_MAX INT_FAST32_MIN INT_FAST64_MAX INT_FAST64_MIN
INT_FAST8_MAX INT_FAST8_MIN INT_LEAST16_MAX INT_LEAST16_MIN INT_LEAST32_MAX
INT_LEAST32_MIN INT_LEAST64_MAX INT_LEAST64_MIN INT_LEAST8_MAX
INT_LEAST8_MIN LDBL_DECIMAL_DIG LDBL_DIG LDBL_EPSILON LDBL_HAS_SUBNORM
LDBL_MANT_DIG LDBL_MAX LDBL_MAX_10_EXP LDBL_MAX_EXP LDBL_MIN LDBL_MIN_10_EXP
LDBL_MIN_EXP LDBL_TRUE_MIN L_tmpnam MATH_ERREXCEPT MATH_ERRNO MB_CUR_MAX NAN
NULL PTRDIFF_MAX PTRDIFF_MIN RAND_MAX SAFESTR_H SEEK_CUR SEEK_END SEEK_SET
SIG_ATOMIC_MAX SIG_ATOMIC_MIN SIZE_MAX SafeFreeFn SafeReallocFn SafeString
SafeStringList SafeView TIME_UTC TMP_MAX UINT16_C UINT16_MAX UINT32_C
UINT32_MAX UINT64_C UINT64_MAX UINT8_C UINT8_MAX UINTMAX_C UINTMAX_MAX
UINTPTR_MAX UINT_FAST16_MAX UINT_FAST32_MAX UINT_FAST64_MAX UINT_FAST8_MAX
UINT_LEAST16_MAX UINT_LEAST32_MAX UINT_LEAST64_MAX UINT_LEAST8_MAX WCHAR_MAX
WCHAR_MIN WINT_MAX WINT_MIN abort abs acos acosf acosh acoshf acoshl acosl
alignas aligned_alloc alignof argc argv asctime asin asinf asinh asinhf
asinhl asinl assert at_quick_exit atan atan2 atan2f atan2l atanf atanh
atanhf atanhl atanl atexit atof atoi atol atoll auto break bsearch calloc
case cbrt cbrtf cbrtl ceil ceilf ceill char clearerr clock clock_t complex
const constexpr continue copysign copysignf copysignl cos cosf cosh coshf
coshl cosl ctime default difftime div div_t do double double_t else enum erf
erfc erfcf erfcl erff erfl errno exit exp exp2 exp2f exp2l expf expl expm1
expm1f expm1l extern fabs fabsf fabsl fclose fdim fdimf fdiml feof ferror
fflush fgetc fgetpos fgets float float_t floor floorf floorl fma fmaf fmal
fmax fmaxf fmaxl fmin fminf fminl fmod fmodf fmodl fopen for fpclassify
fpos_t fprintf fputc fputs fread free freopen frexp frexpf frexpl fscanf
fseek fsetpos ftell fwrite generic getc getchar getenv gmtime goto hypot
hypotf hypotl if ilogb ilogbf ilogbl imaginary inline int int16_t int32_t
int64_t int8_t int_fast16_t int_fast32_t int_fast64_t int_fast8_t
int_least16_t int_least32_t int_least64_t int_least8_t intmax_t intptr_t
isfinite isgreater isgreaterequal isinf isless islessequal islessgreater
isnan isnormal isunordered labs ldexp ldexpf ldexpl ldiv ldiv_t lgamma
lgammaf lgammal llabs lldiv lldiv_t llrint llrintf llrintl llround llroundf
llroundl localtime log log10 log10f log10l log1p log1pf log1pl log2 log2f
log2l logb logbf logbl logf logl long lrint lrintf lrintl lround lroundf
lroundl malloc math_errhandling max_align_t mblen mbstowcs mbtowc memchr
memcmp memcpy memmove memset mktime modf modff modfl nan nanf nanl nearbyint
nearbyintf nearbyintl nextafter nextafterf nextafterl nexttoward nexttowardf
nexttowardl noreturn nullptr offsetof perror pow powf powl printf ptrdiff_t
putc putchar puts qsort quick_exit rand realloc register remainder
remainderf remainderl remove remquo remquof remquol rename restrict return
rewind rint rintf rintl round roundf roundl scalbln scalblnf scalblnl scalbn
scalbnf scalbnl scanf setbuf setvbuf short signbit signed sin sinf sinh
sinhf sinhl sinl size_t sizeof snprintf sprintf sqrt sqrtf sqrtl srand
sscanf static static_assert stderr stdin stdout strcat strchr strcmp strcoll
strcpy strcspn strerror strftime strlen strncat strncmp strncpy strpbrk
strrchr strspn strstr strtod strtof strtok strtol strtold strtoll strtoul
strtoull struct strxfrm sv switch system tan tanf tanh tanhf tanhl tanl
tgamma tgammaf tgammal thread_local time time_t timespec timespec_get tm
tmpfile tmpnam trunc truncf truncl typedef typeof typeof_unqual uint16_t
uint32_t uint64_t uint8_t uint_fast16_t uint_fast32_t uint_fast64_t
uint_fast8_t uint_least16_t uint_least32_t uint_least64_t uint_least8_t
uintmax_t uintptr_t ungetc union unsigned va_arg va_copy va_end va_list
va_start vfprintf vfscanf void volatile vprintf vscanf vsnprintf vsprintf
vsscanf wchar_t wcstombs wctomb while
""".split())

_NOMBRE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_CIERRE = re.compile(r"Cierre_[0-9]+")


def choca_con_c(nombre):
    """Si `nombre` no puede ir tal cual en el C generado."""
    if nombre in NOMBRES_C:
        return True
    # Reservados de C: `_Bool`, `__func__`, y todo lo que empiece asi.
    if len(nombre) > 1 and nombre[0] == "_" and (
            nombre[1] == "_" or "A" <= nombre[1] <= "Z"):
        return True
    # El runtime y lo que escribe el generador: `ss_free`, `SV_FMT`,
    # `ss_tmp1`, `SS_E_A`.
    if nombre.startswith(("ss_", "sv_", "SS_", "SV_")):
        return True
    return _CIERRE.fullmatch(nombre) is not None


def escrito(nombre):
    """El nombre que se escribio, sin el prefijo que le puso el cargador."""
    return nombre[len(PREFIJO):] if nombre.startswith(PREFIJO) else nombre


def legible(texto):
    """Un mensaje con los nombres como se escribieron."""
    return _NOMBRE.sub(lambda m: escrito(m.group(0)), texto)


def callado(nombre):
    """Un `_` delante dice que un nombre sin usar es a proposito."""
    return escrito(nombre).startswith("_")


def externas(decls):
    """Los nombres declarados en un `externo`: son los de las funciones de C,
    y cambiarlos seria llamar a otra."""
    return {d.nombre for d in decls
            if isinstance(d, Funcion) and getattr(d, "externa", False)}


def renombrar(decls, intocables):
    """Pone `ss_id_` delante de cada nombre que chocaria con C, en todo el
    arbol. `intocables` son los que se quedan como estan."""

    def uno(n):
        if not isinstance(n, str) or n in intocables or not choca_con_c(n):
            return n
        return PREFIJO + n

    def calificado(n):
        # `alias.nombre`: el alias no llega a C.
        if isinstance(n, str) and "." in n:
            alias, miembro = n.rsplit(".", 1)
            return f"{alias}.{uno(miembro)}"
        return uno(n)

    def tipo(t):
        # Un nombre seguido de `.` es el alias de un modulo.
        if not isinstance(t, str):
            return t
        return _NOMBRE.sub(
            lambda m: (m.group(0) if t[m.end():m.end() + 1] == "."
                       else uno(m.group(0))), t)

    def patron(args):
        salida = []
        for a in args:
            if isinstance(a, str):
                salida.append(a if a == "_" else uno(a))
                continue
            if isinstance(a, PatronForma):
                a.enum = calificado(a.enum)
                a.args = patron(a.args)
            else:
                visita(a)
            salida.append(a)
        return salida

    def visita(x):
        from dataclasses import fields, is_dataclass
        if isinstance(x, (list, tuple)):
            for y in x:
                visita(y)
            return
        if not is_dataclass(x):
            return
        hechos = set()
        if isinstance(x, (Variable, Campo, CampoDef, Declaracion, Parametro,
                          Funcion, Struct, Enum)):
            x.nombre = uno(x.nombre)
        if isinstance(x, Llamada):
            x.nombre = calificado(x.nombre)
        if isinstance(x, (EnumLit, LiteralStruct)):
            x.tipo = calificado(x.tipo)
        elif isinstance(x, (CampoDef, Declaracion, Parametro)):
            x.tipo = tipo(x.tipo)
        if isinstance(x, (Funcion, Cierre)):
            x.retorno = tipo(x.retorno)
        if isinstance(x, Conversion):
            x.a_tipo = tipo(x.a_tipo)
        if isinstance(x, (Funcion, Struct)):
            x.tipo_params = [uno(p) for p in x.tipo_params]
        if isinstance(x, Funcion):
            x.restricciones = {uno(k): v for k, v in x.restricciones.items()}
        if isinstance(x, VarianteDef):
            # La forma no: en C va siempre con prefijo.
            x.tipos = [tipo(t) for t in x.tipos]
            hechos.add("tipos")
        if isinstance(x, Para):
            x.variable = uno(x.variable)
            x.valor = uno(x.valor)
            hechos.add("valor")
        if isinstance(x, Cierre):
            x.capturas = [uno(n) for n in x.capturas]
            x.mutables = [uno(n) for n in x.mutables]
            hechos.update(("capturas", "mutables"))
        if isinstance(x, LiteralStruct):
            x.campos = [(uno(n), v) for n, v in x.campos]
            for _, v in x.campos:
                visita(v)
            hechos.add("campos")
        if isinstance(x, Brazo):
            x.nombres = patron(x.nombres)
            hechos.add("nombres")
        if isinstance(x, PatronForma):
            x.enum = calificado(x.enum)
            x.args = patron(x.args)
            hechos.add("args")
        if isinstance(x, Interpolada):
            hechos.add("trozos")
        for f in fields(x):
            if f.name in hechos:
                continue
            valor = getattr(x, f.name)
            if isinstance(valor, (list, tuple)) or is_dataclass(valor):
                visita(valor)

    visita(decls)
