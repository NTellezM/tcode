SS_LANG_QUIZA_SIN_USAR
static int64_t ss_lang_ahora_ms_(void)
{
    /* El reloj de pared: la hora que marca la maquina. Salta con el NTP y
       con el cambio de hora, asi que NO sirve para medir cuanto tardo algo.
       Para eso esta `monotono_ms`, y por eso tienen nombres distintos. */
    struct timespec t;
    if (timespec_get(&t, TIME_UTC) != TIME_UTC) return 0;
    return (int64_t) t.tv_sec * 1000 + (int64_t) (t.tv_nsec / 1000000);
}
