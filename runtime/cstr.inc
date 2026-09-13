/* Un `str` de Tcode acaba siempre en `\0`, asi que vale como
   `const char*`. Lo que no puede llevar es un `\0` EN MEDIO: C
   leeria hasta ahi y creeria que la cadena acaba antes. Eso no
   es un fallo de memoria, es una verdad a medias, y Tcode para
   el programa donde esta en vez de pasarsela a nadie. */
SS_LANG_QUIZA_SIN_USAR
static const char* ss_lang_cstr_(const SafeString* s,
                                 const char* archivo, int linea)
{
    const char* p = ss_cstr(s);
    size_t n = ss_len(s);
    if (n != 0 && memchr(p, 0, n) != NULL)
    {
        fprintf(stderr, "%s:%d: esta cadena lleva un cero en "
                "medio y va a una funcion de C, que la leeria "
                "cortada\n", archivo, linea);
        abort();
    }
    return p;
}
