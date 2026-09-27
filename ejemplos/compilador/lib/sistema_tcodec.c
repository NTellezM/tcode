/* sistema_tcodec.c — lo que `tcodec` necesita del sistema y Tcode no trae:
   ejecutar el compilador de C, un directorio temporal, y sustituir un
   archivo entero de una vez. Lo pide `tcodec.t` con un bloque `externo`, y
   se compila y se enlaza junto a el, como cualquier `externo "algo.c"`.

   Cada funcion hace una sola cosa y devuelve un numero o un texto que Tcode
   copia enseguida: no guarda nada de un llamada a otra que no sea suyo. */

#define _XOPEN_SOURCE 700

#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#if defined(__APPLE__)
#  include <mach-o/dyld.h>
#  include <stdint.h>
#endif

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

/* Ejecuta una orden de la shell. Devuelve su codigo de salida, o -1 si no
   se pudo ejecutar o acabo por una senal. */
int tcodec_ejecutar(const char* orden)
{
    fflush(stdout);
    fflush(stderr);
    int r = system(orden);
    if (r == -1 || !WIFEXITED(r)) return -1;
    return WEXITSTATUS(r);
}

/* Un directorio temporal nuevo, o "" si no se pudo. */
const char* tcodec_directorio_temporal(void)
{
    static char ruta[PATH_MAX];
    const char* base = getenv("TMPDIR");
    if (base == NULL || base[0] == '\0') base = "/tmp";
    if (snprintf(ruta, sizeof ruta, "%s/tcodec-XXXXXX", base) >= (int) sizeof ruta)
        return "";
    if (mkdtemp(ruta) == NULL) return "";
    return ruta;
}

/* La ruta de verdad: siguiendo enlaces. Si el archivo no existe todavia, la
   de su directorio con su nombre detras. "" si ni eso se puede. */
const char* tcodec_ruta_real(const char* ruta)
{
    static char salida[PATH_MAX];
    if (realpath(ruta, salida) != NULL) return salida;
    char copia_dir[PATH_MAX];
    char copia_base[PATH_MAX];
    if (strlen(ruta) >= sizeof copia_dir) return "";
    strcpy(copia_dir, ruta);
    strcpy(copia_base, ruta);
    char dir_real[PATH_MAX];
    if (realpath(dirname(copia_dir), dir_real) == NULL) return "";
    if (snprintf(salida, sizeof salida, "%s/%s", dir_real, basename(copia_base))
        >= (int) sizeof salida)
        return "";
    return salida;
}

/* 1 si las dos rutas son el mismo archivo, tambien a traves de enlaces o
   `..`; si alguno no existe, se comparan sus rutas de verdad. */
int tcodec_misma_ruta(const char* a, const char* b)
{
    struct stat sa, sb;
    if (stat(a, &sa) == 0 && stat(b, &sb) == 0)
        return sa.st_dev == sb.st_dev && sa.st_ino == sb.st_ino;
    char ra[PATH_MAX];
    const char* x = tcodec_ruta_real(a);
    if (strlen(x) >= sizeof ra) return 0;
    strcpy(ra, x);
    return strcmp(ra, tcodec_ruta_real(b)) == 0;
}

/* 1 si es un archivo normal que existe. */
int tcodec_es_archivo(const char* ruta)
{
    struct stat s;
    return stat(ruta, &s) == 0 && S_ISREG(s.st_mode);
}

/* Un archivo vacio nuevo en el directorio de `destino`, para escribir alli
   y renombrar despues sin cruzar de disco. "" si no se pudo. */
const char* tcodec_temporal_junto(const char* destino)
{
    static char ruta[PATH_MAX];
    char copia[PATH_MAX];
    if (strlen(destino) >= sizeof copia) return "";
    strcpy(copia, destino);
    if (snprintf(ruta, sizeof ruta, "%s/.tcodec-XXXXXX", dirname(copia))
        >= (int) sizeof ruta)
        return "";
    int fd = mkstemp(ruta);
    if (fd < 0) return "";
    close(fd);
    return ruta;
}

/* Pone `temporal` en el lugar de `destino` de una vez: con los permisos que
   ya tuviera el destino, o los de un archivo nuevo con el `umask` de quien
   ejecuta. 0 si fue bien. */
int tcodec_instalar(const char* temporal, const char* destino, int ejecutable)
{
    struct stat s;
    mode_t modo;
    if (stat(destino, &s) == 0) {
        modo = s.st_mode & 0777;
    } else {
        mode_t mascara = umask(0);
        umask(mascara);
        modo = (ejecutable ? 0777 : 0666) & ~mascara;
    }
    if (chmod(temporal, modo) != 0) return -1;
    return rename(temporal, destino) == 0 ? 0 : -1;
}

/* Borra un archivo; da igual si no estaba. */
void tcodec_borrar(const char* ruta)
{
    (void) remove(ruta);
}

/* Donde esta Tcode —el directorio con `std/` y `runtime/`— para quien no
   dice `TCODE_RAIZ`: se sube desde el propio ejecutable hasta dar con
   `runtime/cabecera.inc`. Como las rutas que ensena el compilador de Python,
   relativa si cae dentro del directorio de trabajo (`.` si es el mismo), y
   entera si no. "" si no se encuentra. */
const char* tcodec_raiz_instalada(void)
{
    static char salida[PATH_MAX];
    char dir[PATH_MAX];
#if defined(__linux__)
    ssize_t n = readlink("/proc/self/exe", dir, sizeof dir - 1);
    if (n <= 0) return "";
    dir[n] = '\0';
#elif defined(__APPLE__)
    char crudo[PATH_MAX];
    uint32_t tam = sizeof crudo;
    if (_NSGetExecutablePath(crudo, &tam) != 0 || realpath(crudo, dir) == NULL) return "";
#else
    return "";
#endif
    for (;;) {
        char* barra = strrchr(dir, '/');
        if (barra == NULL) return "";
        *barra = '\0';
        char prueba[PATH_MAX];
        if (snprintf(prueba, sizeof prueba, "%s/runtime/cabecera.inc", dir)
            >= (int) sizeof prueba)
            return "";
        if (tcodec_es_archivo(prueba)) break;
        if (dir[0] == '\0') return "";
    }
    char trabajo[PATH_MAX];
    char trabajo_real[PATH_MAX];
    if (getcwd(trabajo, sizeof trabajo) != NULL && realpath(trabajo, trabajo_real) != NULL) {
        size_t k = strlen(trabajo_real);
        if (strcmp(dir, trabajo_real) == 0) return ".";
        if (strncmp(dir, trabajo_real, k) == 0 && dir[k] == '/') {
            snprintf(salida, sizeof salida, "%s", dir + k + 1);
            return salida;
        }
    }
    snprintf(salida, sizeof salida, "%s", dir);
    return salida;
}
