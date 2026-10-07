/* Referencia en C, escrita a mano, del caso `automata` de la seccion EQUIVALE.
 *
 * Es independiente del compilador: no es el C que emite `tcodec`. El programa
 * Tcode del caso hace evolucionar un automata celular de la regla 110 sobre
 * 24 celdas, con los bordes a cero, ocho generaciones, y dibuja cada una con
 * `#` y `.`; esto hace lo mismo.
 */
#include <stdio.h>

enum { ANCHO = 24, GENERACIONES = 8 };

int main(void) {
    int actual[ANCHO];
    int siguiente[ANCHO];

    for (int i = 0; i < ANCHO; i = i + 1) {
        actual[i] = 0;
    }
    actual[ANCHO / 2] = 1;

    for (int generacion = 0; generacion < GENERACIONES; generacion = generacion + 1) {
        char linea[ANCHO + 1];
        for (int k = 0; k < ANCHO; k = k + 1) {
            linea[k] = actual[k] == 1 ? '#' : '.';
        }
        linea[ANCHO] = '\0';
        printf("%d %s\n", generacion, linea);

        for (int j = 0; j < ANCHO; j = j + 1) {
            int izq = j == 0 ? 0 : actual[j - 1];
            int cen = actual[j];
            int der = j + 1 == ANCHO ? 0 : actual[j + 1];
            int vecindad = izq * 4 + cen * 2 + der;
            siguiente[j] = (vecindad == 6 || vecindad == 5 || vecindad == 3
                            || vecindad == 2 || vecindad == 1) ? 1 : 0;
        }

        for (int j = 0; j < ANCHO; j = j + 1) {
            actual[j] = siguiente[j];
        }
    }

    return 0;
}
