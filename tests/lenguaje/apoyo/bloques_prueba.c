/* Apoyo de ACEPTA: funciones de C que reciben bloques de Tcode (puntero y
   largo, `const` si se leen y sin el si se escriben). */
#include <stdint.h>
#include <stddef.h>

uint64_t suma_bytes(const uint8_t* b, size_t b_n)
{
    uint64_t s = 0;
    for (size_t i = 0; i < b_n; i++) s += b[i];
    return s;
}

void doblar(uint32_t* v, size_t v_n, uint32_t mas)
{
    for (size_t i = 0; i < v_n; i++) v[i] = v[i] * 2 + mas;
}
