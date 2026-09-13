"""Las internas que hablan con el sistema, y el C de cada una.

Aqui esta lo que no puede pasar por un bloque `externo`, porque tiene que
respetar la propiedad: lo que devuelven es un `str` de Tcode, con su
liberacion automatica, no un `char*` prestado.

Cada entrada es el cuerpo en C de una interna, y solo entra en el programa
que la usa: quien no lee la entrada no carga con el codigo de leerla.
`{res_str}` lo rellena el generador con el nombre del tipo resultado.

En las cinco hay una decision que no es la de C:

  - `leer_linea` crece lo que haga falta. `fgets` corta y deja el resto para
    la vuelta siguiente, que es peor que fallar porque parece que funciona;
    el `bufio.Scanner` de Go deja de leer a los 64 KB y no lo dice.
  - El fin de la entrada es un fallo, no una cadena vacia: una linea en
    blanco no es lo mismo que no haber nada.
  - `variable_entorno` distingue "no esta" de "esta vacia". `getenv` no
    puede: las dos dan algo falso.
  - Hay dos relojes y el nombre dice cual es cual. Medir una duracion con el
    de pared es el error clasico, y el `clock()` de C mide tiempo de CPU
    aunque medio mundo lo use para lo otro.
  - `azar` no tiene el sesgo de `rand() % n`, y el generador es decente.
"""

LEER_LINEA = """SS_LANG_QUIZA_SIN_USAR
static {res_str} ss_lang_leer_linea_(void)
{{
    SafeString linea = ss_new();
    int c = getchar();
    if (c == EOF)
    {{
        ss_free(&linea);
        return ({res_str}){{ .motivo = "fin de la entrada" }};
    }}
    while (c != EOF && c != '\\n')
    {{
        char b = (char) c;
        if (!ss_append_len(&linea, &b, 1))
        {{
            ss_free(&linea);
            return ({res_str}){{ .motivo = "sin memoria al leer la linea" }};
        }}
        c = getchar();
    }}
    /* Un `\\r\\n` de Windows tampoco es parte de la linea. */
    size_t n = ss_len(&linea);
    if (n != 0 && ss_cstr(&linea)[n - 1] == '\\r')
        ss_set_len(&linea, ss_cstr(&linea), n - 1);
    return ({res_str}){{ .motivo = NULL, .valor = linea }};
}}
"""

ENTRADA_COMPLETA = """SS_LANG_QUIZA_SIN_USAR
static {res_str} ss_lang_entrada_completa_(void)
{{
    SafeString todo = ss_new();
    unsigned char trozo[8192];
    size_t n;
    while ((n = fread(trozo, 1, sizeof(trozo), stdin)) != 0)
    {{
        if (!ss_append_len(&todo, (const char*) trozo, n))
        {{
            ss_free(&todo);
            return ({res_str}){{ .motivo = "sin memoria al leer la entrada" }};
        }}
    }}
    if (ferror(stdin))
    {{
        ss_free(&todo);
        return ({res_str}){{ .motivo = "fallo al leer la entrada" }};
    }}
    return ({res_str}){{ .motivo = NULL, .valor = todo }};
}}
"""

VARIABLE_ENTORNO = """SS_LANG_QUIZA_SIN_USAR
static {res_str} ss_lang_variable_entorno_(SafeView nombre)
{{
    if (nombre.len != 0 && memchr(nombre.ptr, 0, nombre.len) != NULL)
        return ({res_str}){{ .motivo = "el nombre lleva un byte cero" }};
    SafeString clave = ss_from_view(nombre);
    if (!ss_ok(&clave))
    {{
        ss_free(&clave);
        return ({res_str}){{ .motivo = "sin memoria para el nombre" }};
    }}
    const char* v = getenv(ss_cstr(&clave));
    ss_free(&clave);
    if (v == NULL)
        return ({res_str}){{ .motivo = "esa variable de entorno no esta" }};
    SafeString valor = ss_from(v);
    if (!ss_ok(&valor))
    {{
        ss_free(&valor);
        return ({res_str}){{ .motivo = "sin memoria para el valor" }};
    }}
    return ({res_str}){{ .motivo = NULL, .valor = valor }};
}}
"""

AHORA_MS = """SS_LANG_QUIZA_SIN_USAR
static int64_t ss_lang_ahora_ms_(void)
{
    /* El reloj de pared: la hora que marca la maquina. Salta con el NTP y
       con el cambio de hora, asi que NO sirve para medir cuanto tardo algo.
       Para eso esta `monotono_ms`, y por eso tienen nombres distintos. */
    struct timespec t;
    if (timespec_get(&t, TIME_UTC) != TIME_UTC) return 0;
    return (int64_t) t.tv_sec * 1000 + (int64_t) (t.tv_nsec / 1000000);
}
"""

MONOTONO_MS = """SS_LANG_QUIZA_SIN_USAR
static int64_t ss_lang_monotono_ms_(void)
{
    /* Solo avanza, nunca salta: es el que sirve para medir duraciones. C17
       no tiene ninguno, asi que se usa el de POSIX cuando esta; donde no
       este, cae al de pared, que es lo unico que hay. */
#if defined(CLOCK_MONOTONIC)
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t) == 0)
        return (int64_t) t.tv_sec * 1000 + (int64_t) (t.tv_nsec / 1000000);
#endif
    struct timespec p;
    if (timespec_get(&p, TIME_UTC) != TIME_UTC) return 0;
    return (int64_t) p.tv_sec * 1000 + (int64_t) (p.tv_nsec / 1000000);
}
"""

# xoshiro256++, y un recorte sin sesgo. Lo comparten `azar` y `sembrar`.
SEMILLA = """static uint64_t ss_lang_azar_estado_[4];
static bool ss_lang_azar_lista_ = false;

static uint64_t ss_lang_revolver_(uint64_t x)
{
    x += 0x9E3779B97F4A7C15u;
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9u;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBu;
    return x ^ (x >> 31);
}

SS_LANG_QUIZA_SIN_USAR
static void ss_lang_sembrar_(uint64_t semilla)
{
    for (int i = 0; i < 4; i++)
    {
        semilla = ss_lang_revolver_(semilla);
        ss_lang_azar_estado_[i] = semilla;
    }
    ss_lang_azar_lista_ = true;
}

static uint64_t ss_lang_rotar_(uint64_t x, int k)
{
    return (x << k) | (x >> (64 - k));
}

static uint64_t ss_lang_siguiente_azar_(void)
{
    if (!ss_lang_azar_lista_)
    {
        /* Sin semilla puesta, una del reloj: dos ejecuciones distintas dan
           cosas distintas, que es lo que se espera sin decir nada. */
        struct timespec t;
        uint64_t s = 0;
        if (timespec_get(&t, TIME_UTC) == TIME_UTC)
            s = (uint64_t) t.tv_sec * 1000000000u + (uint64_t) t.tv_nsec;
        ss_lang_sembrar_(s ^ (uint64_t) (uintptr_t) &t);
    }
    uint64_t* s = ss_lang_azar_estado_;
    uint64_t r = ss_lang_rotar_(s[0] + s[3], 23) + s[0];
    uint64_t t = s[1] << 17;
    s[2] ^= s[0];
    s[3] ^= s[1];
    s[1] ^= s[2];
    s[0] ^= s[3];
    s[2] ^= t;
    s[3] = ss_lang_rotar_(s[3], 45);
    return r;
}

SS_LANG_QUIZA_SIN_USAR
static size_t ss_lang_azar_(size_t tope, const char* archivo, int linea)
{
    if (tope == 0)
    {
        fprintf(stderr, "%s:%d: `azar(0)` pide un numero de un rango "
                "vacio\\n", archivo, linea);
        abort();
    }
    /* `rand() % n` esta sesgado: si `n` no divide al rango, los primeros
       valores salen mas veces. Aqui se descarta lo que sobra del ultimo
       trozo incompleto, que es lo que hacen Rust y Go. */
    uint64_t limite = UINT64_MAX - (UINT64_MAX % (uint64_t) tope) - 1;
    uint64_t x;
    do { x = ss_lang_siguiente_azar_(); } while (x > limite);
    return (size_t) (x % (uint64_t) tope);
}
"""

# nombre de la interna -> su C. `_semilla` no es una interna: es lo que
# comparten `azar` y `sembrar`, y entra si aparece cualquiera de las dos.
SISTEMA = {
    "leer_linea": LEER_LINEA,
    "entrada_completa": ENTRADA_COMPLETA,
    "variable_entorno": VARIABLE_ENTORNO,
    "ahora_ms": AHORA_MS,
    "monotono_ms": MONOTONO_MS,
    "_semilla": SEMILLA,
}

# Que ayudante trae cada interna. `azar` y `sembrar` comparten el mismo, y
# ninguna de las dos aparece como clave de SISTEMA porque el codigo es uno.
TRAE = {
    "leer_linea": ["leer_linea"],
    "entrada_completa": ["entrada_completa"],
    "variable_entorno": ["variable_entorno"],
    "ahora_ms": ["ahora_ms"],
    # El monotono cae en el de pared donde no haya monotono de verdad, pero
    # su C ya lleva ese respaldo dentro: no arrastra al otro.
    "monotono_ms": ["monotono_ms"],
    "azar": ["_semilla"],
    "sembrar": ["_semilla"],
}

# El orden importa: `monotono_ms` cae en el de pared si no hay monotono, y
# el sembrado sin semilla usa el reloj.
ORDEN = ["ahora_ms", "monotono_ms", "_semilla", "leer_linea",
         "entrada_completa", "variable_entorno"]
