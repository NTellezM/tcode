/* terminal.c — lo que el borde de `externo` no deja hacer desde Tcode.
 *
 * Dos cosas, las dos porque C pide algo que por el borde no pasa:
 *
 *   - El tamaño de la terminal. `ioctl` es VARIADICA: declararla en un
 *     `externo` con tres parametros fijos no compila, porque choca con la de
 *     `<sys/ioctl.h>` —`int ioctl(int, unsigned long, ...)`—. Y `TIOCGWINSZ`
 *     escribe en un `struct winsize` por puntero, que desde Tcode no se puede
 *     fabricar. Aqui se envuelve: por el borde solo cruzan dos `int`.
 *   - Esperar a que haya una tecla con un tope de tiempo. Eso pide `poll`
 *     sobre el descriptor de la entrada, y ademas leer los bytes por el
 *     descriptor y no por `getchar`: stdio se trae de golpe lo que haya y lo
 *     guarda en su buffer, donde `poll` no lo ve y diria que no hay nada
 *     mientras el siguiente `getchar` devuelve un byte.
 *
 * Lleva `_DEFAULT_SOURCE` aunque `tcodec` ya la pase por linea de ordenes:
 * este archivo se puede compilar suelto, y `poll` es POSIX.
 *
 * Compila sin avisos con `-std=c17 -Wall -Wextra -Werror`.
 */

#define _DEFAULT_SOURCE 1

#include <errno.h>
#include <poll.h>
#include <stdbool.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

/* ------------------------------------------------------------------ */
/* El tamaño                                                          */
/* ------------------------------------------------------------------ */

/* 1 si `fd` es un terminal y dice un tamaño con sentido. Se exige que no sea
 * cero: en una pseudoterminal recien abierta y sin tamaño fijado, `ioctl`
 * ACIERTA y devuelve `ws_row == 0`, que como tamaño es peor que no saberlo. */
static int tcode_tamano_en(int fd, int* filas, int* columnas)
{
    struct winsize w;
    if (ioctl(fd, TIOCGWINSZ, &w) != 0) return 0;
    if (w.ws_row == 0 || w.ws_col == 0) return 0;
    if (filas != NULL) *filas = (int) w.ws_row;
    if (columnas != NULL) *columnas = (int) w.ws_col;
    return 1;
}

/* Filas, o -1 si no se pudo saber.
 *
 * Se mira la salida estandar primero, que es donde se dibuja; si esta
 * redirigida a un fichero, la entrada suele seguir siendo la terminal de la
 * que se lee, y su tamaño es el que le interesa a quien dibuja; `stderr` es
 * el ultimo recurso. */
int terminal_filas(void)
{
    int filas = 0;
    if (tcode_tamano_en(1, &filas, NULL)) return filas;
    if (tcode_tamano_en(0, &filas, NULL)) return filas;
    if (tcode_tamano_en(2, &filas, NULL)) return filas;
    return -1;
}

int terminal_columnas(void)
{
    int columnas = 0;
    if (tcode_tamano_en(1, NULL, &columnas)) return columnas;
    if (tcode_tamano_en(0, NULL, &columnas)) return columnas;
    if (tcode_tamano_en(2, NULL, &columnas)) return columnas;
    return -1;
}

/* ------------------------------------------------------------------ */
/* El teclado                                                         */
/* ------------------------------------------------------------------ */

/* stdin sin buffer: cada lectura es un `read` de un byte, y entonces `poll`
 * sobre el descriptor dice la verdad. Con buffer, `getchar` se trae 4096
 * bytes de golpe y `hay_tecla` mentiria sobre los que sobren. */
bool entrada_sin_buffer(void)
{
    static int hecho = 0;
    if (!hecho)
    {
        if (setvbuf(stdin, NULL, _IONBF, 0) != 0) return false;
        hecho = 1;
    }
    return true;
}

static long tcode_ms(void)
{
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t) != 0) return 0;
    return (long) t.tv_sec * 1000L + (long) (t.tv_nsec / 1000000L);
}

/* true si hay algo que leer AHORA, false si se acabo el tiempo. Un
 * `milisegundos` negativo espera sin tope.
 *
 * El fin de la entrada cuenta como "hay algo": asi la lectura que viene
 * detras devuelve el fin de la entrada en vez de bloquearse, y quien llama
 * ve el aviso en lugar de quedarse colgado. */
bool hay_tecla(int milisegundos)
{
    entrada_sin_buffer();
    long limite = (milisegundos < 0) ? -1 : tcode_ms() + (long) milisegundos;
    for (;;)
    {
        long quedan = -1;
        if (milisegundos >= 0)
        {
            quedan = limite - tcode_ms();
            if (quedan < 0) quedan = 0;
        }
        struct pollfd p;
        p.fd = 0;
        p.events = POLLIN;
        p.revents = 0;
        int r = poll(&p, 1, (int) quedan);
        if (r > 0) return true;
        if (r == 0) return false;
        if (errno != EINTR) return false;
        /* Una señal corto la espera: se vuelve a mirar con lo que queda. */
        if (milisegundos >= 0 && tcode_ms() >= limite) return false;
    }
}

/* Un byte leido del descriptor, sin pasar por stdio: lo mismo que `getchar`
 * pero sin buffer que se adelante a `hay_tecla`. -1 al acabarse la entrada. */
int leer_byte_crudo(void)
{
    unsigned char c;
    for (;;)
    {
        ssize_t n = read(0, &c, 1);
        if (n == 1) return (int) c;
        if (n == 0) return -1;
        if (errno != EINTR) return -1;
    }
}
