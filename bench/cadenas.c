/* Lo mismo en C, usando safestr a mano como lo haria una persona.
   Mide lo que cuesta el LENGUAJE sobre la libreria, no la libreria. */
#include <stdio.h>
#include "safestr.h"

static SafeString construir(size_t n)
{
    SafeString s = ss_new();
    for (size_t i = 0; i < n; i++)
        ss_append_view(&s, sv_len("abcdefghij", 10));
    return s;
}

int main(void)
{
    size_t total = 0;
    for (size_t r = 0; r < 300; r++) {
        SafeString s = construir(20000);
        total += sv_len_of(ss_view(&s));
        ss_free(&s);
    }
    printf("%zu\n", total);
    return 0;
}
