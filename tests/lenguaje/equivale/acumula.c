/* Referencia en C, escrita a mano, del caso `acumula` de la seccion EQUIVALE.
 *
 * Es independiente del compilador: no es el C que emite `tcodec`. El caso lee
 * toda la entrada, la parte en lineas como `std/texto.lineas` (quitando el
 * `\r` de fin de linea), recorta los blancos de cada una como
 * `std/texto.recortar`, convierte los digitos como `std/texto.a_entero`
 * —y una linea sin digitos vale cero, por el `sino 0`— y lleva la suma, el
 * maximo y la cuenta. El codigo de salida es la cuenta.
 */
#include <stdio.h>
#include <stdlib.h>

static int blanco(unsigned char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

int main(void) {
    /* Toda la entrada, como `entrada_completa()`. */
    size_t cap = 1024, len = 0;
    char *todo = malloc(cap);
    if (todo == NULL) {
        return 1;
    }
    size_t n;
    while ((n = fread(todo + len, 1, cap - len, stdin)) != 0) {
        len = len + n;
        if (len == cap) {
            cap = cap * 2;
            char *mas = realloc(todo, cap);
            if (mas == NULL) {
                free(todo);
                return 1;
            }
            todo = mas;
        }
    }
    if (ferror(stdin)) {
        free(todo);
        return 1;
    }

    long long total = 0, maximo = 0;
    size_t cuantos = 0;
    size_t desde = 0;

    while (desde < len) {
        size_t i = desde;
        while (i < len && todo[i] != '\n') {
            i = i + 1;
        }
        size_t hasta = i;
        if (hasta > desde && todo[hasta - 1] == '\r') {
            hasta = hasta - 1;
        }

        size_t a = desde, b = hasta;
        while (a < b && blanco((unsigned char) todo[a])) {
            a = a + 1;
        }
        while (b > a && blanco((unsigned char) todo[b - 1])) {
            b = b - 1;
        }

        if (b > a) {
            /* `a_entero(...) sino 0`: solo digitos, o cero. */
            unsigned long long v = 0;
            int ok = 1;
            for (size_t k = a; k < b; k = k + 1) {
                unsigned char c = (unsigned char) todo[k];
                if (c < '0' || c > '9') {
                    ok = 0;
                    break;
                }
                v = v * 10 + (unsigned long long) (c - '0');
            }
            long long valor = ok ? (long long) v : 0;

            total = total + valor;
            if (valor > maximo) {
                maximo = valor;
            }
            cuantos = cuantos + 1;
            if (cuantos % 2 == 0) {
                total = total - 1;
            }
            printf("%llu %lld %lld\n", (unsigned long long) cuantos, total, maximo);
        }

        if (i < len) {
            desde = i + 1;
        } else {
            break;
        }
    }

    printf("%llu %lld\n", (unsigned long long) cuantos, total);
    free(todo);
    return (int) cuantos;
}
