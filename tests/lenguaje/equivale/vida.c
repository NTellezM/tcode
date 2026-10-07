/* Referencia en C, escrita a mano, del caso `vida` de la seccion EQUIVALE.
 *
 * Es independiente del compilador: no es el C que emite `tcodec`. El programa
 * Tcode del caso hace evolucionar un tablero de 8x8 con las reglas del Juego
 * de la Vida de Conway, con los bordes envueltos (toro), cinco generaciones, y
 * dibuja cada una con `#` y `.`; esto hace lo mismo. La salida de este `.c` es
 * el dorado congelado `tests/dorados/vida.golden`.
 */
#include <stdio.h>

enum { ANCHO = 8, GENERACIONES = 5 };

static int vecinos(const int *t, int x, int y) {
    int n = 0;
    for (int dy = 0; dy < 3; dy = dy + 1) {
        for (int dx = 0; dx < 3; dx = dx + 1) {
            if (dx != 1 || dy != 1) {
                int xx = (x + ANCHO - 1 + dx) % ANCHO;
                int yy = (y + ANCHO - 1 + dy) % ANCHO;
                n = n + t[yy * ANCHO + xx];
            }
        }
    }
    return n;
}

int main(void) {
    int actual[ANCHO * ANCHO];
    int siguiente[ANCHO * ANCHO];

    for (int i = 0; i < ANCHO * ANCHO; i = i + 1) {
        actual[i] = 0;
    }
    actual[1 * ANCHO + 2] = 1;
    actual[2 * ANCHO + 3] = 1;
    actual[3 * ANCHO + 1] = 1;
    actual[3 * ANCHO + 2] = 1;
    actual[3 * ANCHO + 3] = 1;

    for (int generacion = 0; generacion < GENERACIONES; generacion = generacion + 1) {
        for (int y = 0; y < ANCHO; y = y + 1) {
            for (int x = 0; x < ANCHO; x = x + 1) {
                putchar(actual[y * ANCHO + x] == 1 ? '#' : '.');
            }
            putchar('\n');
        }

        for (int y = 0; y < ANCHO; y = y + 1) {
            for (int x = 0; x < ANCHO; x = x + 1) {
                int n = vecinos(actual, x, y);
                int vivo = actual[y * ANCHO + x];
                if (vivo == 1) {
                    siguiente[y * ANCHO + x] = (n == 2 || n == 3) ? 1 : 0;
                } else {
                    siguiente[y * ANCHO + x] = (n == 3) ? 1 : 0;
                }
            }
        }

        for (int i = 0; i < ANCHO * ANCHO; i = i + 1) {
            actual[i] = siguiente[i];
        }
    }

    return 0;
}
