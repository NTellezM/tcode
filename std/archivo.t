// std/archivo.t — ficheros: leerlos, escribirlos, y las preguntas al
// sistema de ficheros que `std/camino` no puede contestar.
//
// `std/camino` solo mira el texto de una ruta —parte, junta, normaliza— y no
// toca el disco. Lo que si lo toca vive aqui: resolver enlaces, comparar dos
// rutas, mirar si algo es un fichero, crear un temporal al lado del destino,
// instalarlo encima y borrar.
//
// La puerta a C es `externo` contra las cabeceras del sistema, sin un `.c`
// de por medio: por el borde solo cruzan `str` (que acaba en `\0`), numeros
// y `bool`. Donde C pide un buffer —`realpath`— se le da un `str` con sitio
// de sobra; donde devuelve un puntero opaco —`opendir`— no se cruza, y la
// pregunta se hace con las funciones que si cruzan.

use "std/camino" como camino;
use "std/texto";

// ------------------------------------------------------------------
// La puerta al sistema de ficheros
// ------------------------------------------------------------------

// Modos de `access`, los de POSIX: 0 existe, 1 ejecutable, 2 escribible,
// 4 legible. `access` resuelve la ruta entera y sigue enlaces, asi que
// contesta por el fichero de verdad, no por el nombre.
externo "unistd.h" {
    fn access(ruta: str, modo: i32) -> i32;
    fn close(fd: i32) -> i32;
}

// `remove` borra un fichero o una carpeta vacia; `rename` es la sustitucion
// de una vez, atomica dentro del mismo sistema de ficheros.
externo "stdio.h" {
    fn remove(ruta: str) -> i32;
    fn rename(viejo: str, nuevo: str) -> i32;
}

// `chmod` es el que deja ejecutable el binario recien instalado; `umask`
// solo se toca para leerlo —se pone a cero y se devuelve enseguida— y saber
// que permisos tendria un fichero nuevo.
externo "sys/stat.h" {
    fn chmod(ruta: str, modo: u32) -> i32;
    fn umask(mascara: u32) -> u32;
}

// `realpath` escribe la ruta resuelta en el segundo argumento. Ese buffer lo
// pone `buffer_de_ruta`, que tiene el tamaño de `PATH_MAX` en Linux (4096);
// en macOS son 1024, asi que tambien llega.
//
// El parametro va como `buffer` y no como `str`: por el borde un `str` cruza
// como `const char*`, y C necesita escribir ahi. `buffer` dice justo eso, y
// es lo unico que le quita el `const`. `mkstemp` va igual, porque sustituye
// las `X` de la plantilla en el sitio.
externo "stdlib.h" {
    fn realpath(ruta: str, reservado: buffer) -> bool;
    fn mkstemp(plantilla: buffer) -> i32;
}

// ------------------------------------------------------------------
// Escribir
// ------------------------------------------------------------------

// Todo el texto de una vez. La ruta y el contenido pueden ser vistas: la
// interna los copia. Si algo falla —abrir, escribir o cerrar— falla, en vez
// de dejar un fichero a medias en silencio.
fn escribir_todo(ruta: view, texto: view) -> bool ! {
    try escribir_archivo(ruta, texto);
    return true;
}

// ------------------------------------------------------------------
// Preguntar por una ruta
// ------------------------------------------------------------------

// Una carpeta. `access` resuelve la ruta y sigue enlaces, asi que `ruta/.`
// solo existe si `ruta` es un directorio: en un fichero, el punto del medio
// da ENOTDIR. Se evita `stat` a proposito, que recibe un struct por puntero
// y ese no cruza el borde.
fn es_directorio(ruta: view) -> bool {
    if access(nuevo(ruta), 0) != 0 { return false; }
    return access($"{ruta}/.", 0) == 0;
}

// Un fichero que existe y no es una carpeta. Un tubo, un dispositivo o un
// zocalo tambien salen `true`: separarlos de un fichero normal pide el modo
// de `stat`, y eso no cruza. Para lo que se comprueba aqui —fuentes,
// cabeceras, binarios— la diferencia no se nota.
fn es_archivo(ruta: view) -> bool {
    return access(nuevo(ruta), 0) == 0 && !es_directorio(ruta);
}

// Borra un fichero, o una carpeta vacia. `false` si no se pudo; no distingue
// «no estaba» de «no se dejo», que para el que llama da lo mismo.
fn borrar(ruta: view) -> bool {
    return remove(nuevo(ruta)) == 0;
}

// Un `str` del tamaño de una ruta entera, con la capacidad ya reservada:
// `realpath` escribe dentro y no puede quedarse corto. 4096 es `PATH_MAX` en
// Linux; en macOS son 1024, y sobra.
fn buffer_de_ruta() -> str {
    return repetir(" ", 4096);
}

// `realpath` sobre una ruta, o fallo si no existe. El resultado se lee del
// buffer hasta el cero que pone C: la vista sigue midiendo 4096 —el `str`
// no cambia de largo—, pero la cadena acaba antes.
fn camino_resuelto(ruta: view) -> str ! {
    let cual = nuevo(ruta);
    var buf = buffer_de_ruta();
    if !realpath(cual, buf) {
        fail "no se pudo resolver la ruta: no existe, o su carpeta no existe";
    }
    let dentro = vista(buf);
    var fin = 0;
    while fin < largo(dentro) && byte(dentro, fin) != 0 {
        fin = fin + 1;
    }
    return nuevo(rebanar(dentro, 0, fin));
}

// La ruta de verdad: `.` y `..` resueltos, los enlaces seguidos, y entera.
// Si el fichero todavia no existe, la de su carpeta con su nombre detras,
// que es lo que permite comparar dos rutas antes de crear nada.
fn ruta_real(ruta: view) -> str ! {
    let entera = camino_resuelto(ruta) sino vacio();
    if largo(entera) > 0 { return entera; }

    let carpeta = camino.carpeta_de(ruta);
    let nombre = camino.nombre_de(ruta);
    if largo(carpeta) == 0 || largo(nombre) == 0 {
        fail "no se pudo resolver la ruta";
    }
    let base = camino_resuelto(carpeta) sino vacio();
    if largo(base) == 0 {
        fail "no existe la ruta ni su carpeta";
    }
    return camino.unir_ruta(base, nombre);
}

// Si las dos rutas son el mismo sitio, tambien con `..` de por medio o por
// un enlace. Se comparan sus rutas resueltas: dos enlaces duros al mismo
// fichero, con nombres distintos, no se reconocen como iguales —eso pide el
// inodo, y `stat` no cruza el borde—, pero un enlace simbolico si.
fn misma_ruta(a: view, b: view) -> bool {
    let ra = ruta_real(a) sino vacio();
    let rb = ruta_real(b) sino vacio();
    if largo(ra) == 0 || largo(rb) == 0 { return false; }
    return igual(ra, rb);
}

// ------------------------------------------------------------------
// Poner un fichero en su sitio
// ------------------------------------------------------------------

// Un fichero temporal NUEVO en la misma carpeta que el destino, para
// escribir ahi y renombrarlo encima sin cruzar de sistema de ficheros.
// `mkstemp` sustituye las `X` de la plantilla por su cuenta, en el sitio, y
// lo crea con 0600; por eso la plantilla va como `buffer`.
fn temporal_junto(destino: view) -> str ! {
    let carpeta = camino.carpeta_o_actual(destino);
    var plantilla = $"{carpeta}/.tcodec-XXXXXX";
    let fd = mkstemp(plantilla);
    if fd < 0 {
        fail "no se pudo crear un temporal junto al destino";
    }
    close(fd);
    return plantilla;
}

// Los permisos de un fichero nuevo: los de siempre —0666, o 0777 si va a
// ser ejecutable— menos el `umask` de quien compila.
fn permisos_nuevos(ejecutable: bool) -> u32 {
    let mascara = umask(0);
    umask(mascara);
    var base: u32 = 438;          // 0666
    if ejecutable { base = 511; } // 0777
    return base & ~mascara;
}

// Pone `temporal` en el sitio de `destino` de una vez: le da los permisos
// que le tocarian, con la ejecucion si se pide, y lo renombra encima. Si el
// destino ya existia y era ejecutable, no se le quita —no hay `stat` para
// copiarle el modo entero, pero el bit que importa si—.
fn instalar(temporal: view, destino: view, ejecutable: bool) -> bool ! {
    let t = nuevo(temporal);
    let d = nuevo(destino);
    var modo = permisos_nuevos(ejecutable);
    if access(d, 0) == 0 && access(d, 1) == 0 {
        modo = modo | 73; // 0111
    }
    if chmod(t, modo) != 0 {
        fail "no se pudieron poner los permisos del temporal";
    }
    if rename(t, d) != 0 {
        fail "no se pudo poner el temporal en el sitio del destino";
    }
    return true;
}

// ------------------------------------------------------------------
// Leer por partes
// ------------------------------------------------------------------

// Recorre el archivo de principio a fin. Cada parte solo vive durante la
// llamada a `visitar`, así que la memoria usada no crece con el archivo.
fn por_partes<F>(ruta: view, tamano: usize, visitar: F) ! {
    if tamano == 0 { fail "el tamano de cada parte tiene que ser mayor que cero"; }
    var desde = 0;
    var seguir = true;
    while seguir {
        let parte = try leer_parte_archivo(ruta, desde, tamano);
        if largo(parte) == 0 {
            seguir = false;
        } else {
            visitar(vista(parte));
            desde = desde + largo(parte);
        }
    }
}

// La variante que conserva las partes. Es útil si se necesitan después; para
// memoria acotada usa `por_partes`.
fn partes_de_archivo(ruta: view, tamano: usize) -> list<str> ! {
    if tamano == 0 { fail "el tamano de cada parte tiene que ser mayor que cero"; }
    var salida: list<str> = [];
    var desde = 0;
    var seguir = true;
    while seguir {
        let parte = try leer_parte_archivo(ruta, desde, tamano);
        if largo(parte) == 0 {
            seguir = false;
        } else {
            desde = desde + largo(parte);
            anadir(salida, parte);
        }
    }
    return salida;
}
