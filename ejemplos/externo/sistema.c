/* sistema.c — lo que no cabe en el borde, envuelto en C.
 *
 * El borde de Tcode solo admite los tipos que significan exactamente lo
 * mismo a los dos lados: numeros, `bool` y `str` (que siempre acaba en
 * `\0`). `time(NULL)` no cabe, porque pide un puntero. Asi que se envuelve,
 * y la firma que ve Tcode ya si cabe.
 *
 * Este archivo lo compila y lo enlaza `tcode` solo, porque el programa
 * declara `externo "sistema.c"`. */

#include <stdlib.h>
#include <time.h>

long long ahora_segundos(void)
{
    return (long long) time(NULL);
}

/* `rand` da un entero cualquiera; esto lo deja en [0, tope). */
long long al_azar(long long tope)
{
    if (tope <= 0) return 0;
    return (long long) (rand() % tope);
}

void sembrar(long long semilla)
{
    srand((unsigned) semilla);
}
