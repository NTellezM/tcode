SS_LANG_QUIZA_SIN_USAR
static @RES_STR@ ss_lang_variable_entorno_(SafeView nombre)
{
    if (nombre.len != 0 && memchr(nombre.ptr, 0, nombre.len) != NULL)
        return (@RES_STR@){ .motivo = "el nombre lleva un byte cero" };
    SafeString clave = ss_from_view(nombre);
    if (!ss_ok(&clave))
    {
        ss_free(&clave);
        return (@RES_STR@){ .motivo = "sin memoria para el nombre" };
    }
    const char* v = getenv(ss_cstr(&clave));
    ss_free(&clave);
    if (v == NULL)
        return (@RES_STR@){ .motivo = "esa variable de entorno no esta" };
    SafeString valor = ss_from(v);
    if (!ss_ok(&valor))
    {
        ss_free(&valor);
        return (@RES_STR@){ .motivo = "sin memoria para el valor" };
    }
    return (@RES_STR@){ .motivo = NULL, .valor = valor };
}
