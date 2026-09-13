static uint64_t ss_lang_azar_estado_[4];
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
                "vacio\n", archivo, linea);
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
