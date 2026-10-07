/* Referencia en C, escrita a mano, del caso `rebote` de la seccion EQUIVALE.
 *
 * Es independiente del compilador: no es el C que emite `tcodec`. El programa
 * Tcode del caso mueve una pelota en una caja con posicion y velocidad
 * enteras, rebota en los bordes y cuenta los toques; esto hace lo mismo, con
 * los mismos limites, el mismo orden y el mismo `return`.
 */
#include <stdio.h>

int main(void) {
    const long long ancho = 10;
    const long long alto = 7;

    long long x = 2, y = 3;
    long long vx = 3, vy = 2;
    unsigned long long toques = 0;

    for (long long paso = 0; paso < 12; paso = paso + 1) {
        x = x + vx;
        y = y + vy;
        if (x < 0) { x = 0; vx = -vx; toques = toques + 1; }
        if (x > ancho) { x = ancho; vx = -vx; toques = toques + 1; }
        if (y < 0) { y = 0; vy = -vy; toques = toques + 1; }
        if (y > alto) { y = alto; vy = -vy; toques = toques + 1; }
        printf("%lld %lld %lld\n", paso, x, y);
    }

    printf("%llu\n", toques);
    return (int) toques;
}
