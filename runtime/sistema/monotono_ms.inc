SS_LANG_QUIZA_SIN_USAR
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
