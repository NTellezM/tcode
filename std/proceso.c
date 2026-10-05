/* proceso.c — capturar lo que imprime una orden.
 *
 * Lo que el borde de `externo` no deja hacer desde Tcode:
 *
 *   - `popen` devuelve un `FILE*`, que es un puntero opaco y no cruza.
 *   - El texto crece sin saber cuanto: hace falta memoria que se pide y se
 *     suelta, y por el borde solo sale `cadena_c`, que Tcode COPIA y no
 *     libera.
 *
 * Asi que el buffer es de este archivo, vive en una variable estatica, y
 * `capturar_liberar()` es quien lo suelta. Tcode copia primero —eso lo hace
 * `ss_from` al volver de `capturar_salida`— y llama a `capturar_liberar()`
 * despues: en el momento de la copia el puntero ya no hace falta.
 *
 * Se elige `popen` y no `pipe`+`fork`+`exec` a proposito: `system` —lo que ya
 * usa `std/proceso.t`— tambien pasa por `/bin/sh`, asi que `ejecutar` y
 * `capturar_salida` entienden la orden igual (`|`, `>`, variables, `~`). Con
 * `exec` habria que partir la orden en `argv` a mano y las dos funciones
 * dejarian de coincidir. Lo que se pierde: `popen` solo da UN flujo, asi que
 * `stderr` se queda donde estaba; para separarlo hace falta `pipe`+`poll`,
 * que es otro contrato.
 *
 * Lleva `_DEFAULT_SOURCE` aunque `tcodec` ya la pase por linea de ordenes:
 * este archivo se puede compilar suelto, y `popen` es POSIX.
 */

#define _DEFAULT_SOURCE 1

#include <stdio.h>
#include <stdlib.h>

/* Tope por defecto: 8 MiB. Una orden que imprime sin parar (`yes`, un `cat`
 * de /dev/zero) no puede comerse la memoria del proceso. */
#define PROCESO_TOPE ((size_t) 8 * 1024 * 1024)

static char* proceso_texto = NULL;    /* lo que dio la ultima captura */
static size_t proceso_largo = 0;
static int proceso_estado_crudo = -1; /* lo que devolvio pclose */
static int proceso_fallo_ = 0;        /* 1 = popen o pclose fallaron */
static int proceso_truncada_ = 0;     /* 1 = se llego al tope */
static size_t proceso_tope_ = PROCESO_TOPE;

/* El tope, en bytes. Vale para la proxima captura; 0 lo deja en el de
 * defecto. */
void capturar_tope(size_t tope)
{
    proceso_tope_ = (tope == 0) ? PROCESO_TOPE : tope;
}

static void proceso_soltar(void)
{
    free(proceso_texto);
    proceso_texto = NULL;
    proceso_largo = 0;
}

/* Suelta el buffer de la captura anterior. Se llama sola al principio de
 * cada `capturar_salida`; llamarla a mano es para no tenerlo vivo mas de lo
 * necesario. Quien la llama es Tcode, despues de copiar el texto. */
void capturar_liberar(void)
{
    proceso_soltar();
}

/* Lo que imprime `orden` por su salida estandar, sin el codigo de salida.
 * Devuelve "" si no se pudo lanzar; `capturar_fallo()` lo distingue de una
 * orden que no imprimio nada. */
const char* capturar_salida(const char* orden)
{
    proceso_soltar();
    proceso_estado_crudo = -1;
    proceso_fallo_ = 0;
    proceso_truncada_ = 0;

    if (orden == NULL || orden[0] == '\0')
    {
        /* `popen("")` lanza un shell que no hace nada y "funciona": mejor
         * decirlo que devolver una cadena vacia enganosa. */
        proceso_fallo_ = 1;
        return "";
    }

    FILE* tubo = popen(orden, "r");
    if (tubo == NULL)
    {
        proceso_fallo_ = 1;
        return "";
    }

    /* El buffer empieza en 4 KiB, pero nunca por encima del tope: con un tope
     * menor hay que cortar en el primer bloque, no despues de leerlo entero. */
    size_t capacidad = 4096;
    if (capacidad > proceso_tope_) capacidad = proceso_tope_;

    char* texto = (char*) malloc(capacidad + 1);
    if (texto == NULL)
    {
        pclose(tubo);
        proceso_fallo_ = 1;
        return "";
    }
    size_t largo = 0;

    for (;;)
    {
        if (largo == capacidad)
        {
            if (capacidad >= proceso_tope_)
            {
                /* El buffer ya mide el tope entero. Queda libre el byte del
                 * terminador, y ahi se prueba si hay mas: si el `fread` no
                 * trae nada, la salida media justo el tope y no se corto
                 * nada; si trae algo, se paso y se corta. Sin esta prueba,
                 * una salida que cabe exacta se confundiria con una
                 * truncada. */
                if (fread(texto + largo, 1, 1, tubo) == 0) break;
                proceso_truncada_ = 1;
                break;
            }
            size_t nueva = capacidad * 2;
            if (nueva > proceso_tope_) nueva = proceso_tope_;
            char* mas = (char*) realloc(texto, nueva + 1);
            if (mas == NULL)
            {
                /* Sin memoria: se queda lo leido, que es mejor que nada, y
                 * se dice. */
                proceso_fallo_ = 1;
                break;
            }
            texto = mas;
            capacidad = nueva;
        }
        size_t n = fread(texto + largo, 1, capacidad - largo, tubo);
        if (n == 0) break;
        largo += n;
    }

    /* Aqui se cierra el tubo. Si se corto por el tope, el hijo puede estar
     * bloqueado escribiendo: al cerrar el extremo de lectura recibe SIGPIPE y
     * muere, asi que `pclose` no se queda colgado. */
    int estado = pclose(tubo);
    if (estado < 0 && !proceso_fallo_) proceso_fallo_ = 1;

    texto[largo] = '\0';
    proceso_texto = texto;
    proceso_largo = largo;
    proceso_estado_crudo = estado;
    return proceso_texto;
}

/* El estado crudo de `wait`, como el que devuelve `system`: el codigo de
 * salida son los bits 8..15. -1 si no hubo captura. */
int capturar_estado(void)
{
    return proceso_estado_crudo;
}

/* 1 si `popen` o `pclose` fallaron, 0 si la orden llego a correr. */
int capturar_fallo(void)
{
    return proceso_fallo_;
}

/* 1 si la salida no cabia en el tope y se corto. */
int capturar_truncada(void)
{
    return proceso_truncada_;
}

/* Cuantos bytes se capturaron de verdad, util sobre todo al truncar. */
size_t capturar_largo(void)
{
    return proceso_largo;
}
