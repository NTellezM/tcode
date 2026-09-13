SS_LANG_QUIZA_SIN_USAR
static @RES_STR@ ss_lang_entrada_completa_(void)
{
    SafeString todo = ss_new();
    unsigned char trozo[8192];
    size_t n;
    while ((n = fread(trozo, 1, sizeof(trozo), stdin)) != 0)
    {
        if (!ss_append_len(&todo, (const char*) trozo, n))
        {
            ss_free(&todo);
            return (@RES_STR@){ .motivo = "sin memoria al leer la entrada" };
        }
    }
    if (ferror(stdin))
    {
        ss_free(&todo);
        return (@RES_STR@){ .motivo = "fallo al leer la entrada" };
    }
    return (@RES_STR@){ .motivo = NULL, .valor = todo };
}
