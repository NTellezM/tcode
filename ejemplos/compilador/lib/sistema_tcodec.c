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
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

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
