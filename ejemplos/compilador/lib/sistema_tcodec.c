/* sistema_tcodec.c — lo unico que `tcodec` necesita del sistema y Tcode no
   trae: subir el limite de pila y volver a ejecutarse a si mismo. Lo pide
   `tcodec.t` con un bloque `externo`, y se compila y se enlaza junto a el,
   como cualquier `externo "algo.c"`. */

#define _XOPEN_SOURCE 700

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

/* El analisis es recursivo, como la gramatica, y cada nivel de una expresion
   gasta varios KB de pila: con los 8 MB de siempre, mil parentesis anidados
   o una suma de veinte mil terminos la agotaban. La pila del hilo principal
   la fija el limite del sistema al arrancar, asi que se sube el limite y el
   programa se vuelve a ejecutar a si mismo, una vez. Donde no se puede (otro
   sistema, un limite duro mas bajo), sigue con la pila que tenia. */
#define TCODEC_PILA ((rlim_t) 1024 * 1024 * 1024)

int tcodec_pila_honda(void)
{
#if defined(__linux__)
    struct rlimit r;
    if (getenv("TCODEC_PILA_HONDA") != NULL) return 0;
    if (getrlimit(RLIMIT_STACK, &r) != 0) return 0;
    if (r.rlim_cur == RLIM_INFINITY || r.rlim_cur >= TCODEC_PILA) return 0;
    rlim_t quiero = TCODEC_PILA;
    if (r.rlim_max != RLIM_INFINITY && r.rlim_max < quiero) quiero = r.rlim_max;
    if (quiero <= r.rlim_cur) return 0;

    /* Los argumentos, tal como llegaron: `/proc/self/cmdline` los separa con
       ceros. */
    static char texto[1 << 16];
    static char* args[1024];
    FILE* f = fopen("/proc/self/cmdline", "rb");
    if (f == NULL) return 0;
    size_t n = fread(texto, 1, sizeof texto - 1, f);
    int completo = feof(f);
    fclose(f);
    if (!completo || n == 0) return 0;
    texto[n] = '\0';
    size_t cuantos = 0;
    for (size_t i = 0; i < n && cuantos + 1 < sizeof args / sizeof args[0];
         i += strlen(texto + i) + 1)
        args[cuantos++] = texto + i;
    args[cuantos] = NULL;

    r.rlim_cur = quiero;
    if (setrlimit(RLIMIT_STACK, &r) != 0) return 0;
    if (setenv("TCODEC_PILA_HONDA", "1", 1) != 0) return 0;
    fflush(stdout);
    fflush(stderr);
    execv("/proc/self/exe", args);
    return 0;
#else
    return 0;
#endif
}
