SS_LANG_QUIZA_SIN_USAR
static @RES_STR@ ss_lang_leer_linea_(void)
{
    SafeString linea = ss_new();
    int c = getchar();
    if (c == EOF)
    {
        ss_free(&linea);
        return (@RES_STR@){ .motivo = "fin de la entrada" };
    }
    while (c != EOF && c != '\n')
    {
        char b = (char) c;
        if (!ss_append_len(&linea, &b, 1))
        {
            ss_free(&linea);
            return (@RES_STR@){ .motivo = "sin memoria al leer la linea" };
        }
        c = getchar();
    }
    /* Un `\r\n` de Windows tampoco es parte de la linea. */
    size_t n = ss_len(&linea);
    if (n != 0 && ss_cstr(&linea)[n - 1] == '\r')
        ss_set_len(&linea, ss_cstr(&linea), n - 1);
    return (@RES_STR@){ .motivo = NULL, .valor = linea };
}
