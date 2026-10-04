// Lo que un programa sabe del sitio donde corre: las variables de entorno y
// los directorios del sistema.
//
// Leer el entorno ya lo sabe hacer el lenguaje —`variable_entorno` es un
// interno, no una funcion de esta biblioteca—, asi que aqui van envoltorios
// con nombre y con trato de errores.
//
// Aqui NO hay forma de escribir variables, y es a proposito: el consumidor
// que manda —`tcodec`— solo las lee, y escribir necesitaria `setenv`, que es
// POSIX y en `<stdlib.h>` va detras de macros de caracteristicas que el C
// generado no define: `externo` incluye la cabecera, pero no ve la
// declaracion y el aviso de funcion sin declarar es un error. Si algun dia
// hace falta, el sitio es el compilador, no este modulo.
//
// Todo lo que sale de aqui es `str` propio y no una vista: devolver una vista
// sobre memoria del entorno seria devolver algo que no es nuestro.

// El valor de una variable, o falla con motivo si no esta puesta.
fn variable(nombre: view) -> str ! {
    return try variable_entorno(nombre);
}

// El valor de una variable, o `por_defecto` si no esta puesta.
fn variable_o(nombre: view, por_defecto: view) -> str {
    return variable_entorno(nombre) sino nuevo(por_defecto);
}

// Donde el sistema dice que se escriban los ficheros temporales: el
// directorio, NO un directorio nuevo.
//
// La distincion importa y ya ha costado un susto. El shim en C del compilador
// tenia una funcion con este mismo nombre que creaba un directorio NUEVO y
// unico con `mkdtemp`; quien la sustituya esperando eso acabaria escribiendo en
// una ruta compartida —dos compilaciones pisandose el mismo `/tmp/algo.err`— y
// un `borrar(directorio_temporal())` intentaria borrar `/tmp`. Para un nombre
// unico dentro del temporal, usa `std/archivo.temporal_junto`.
fn directorio_temporal() -> str {
    return variable_entorno("TMPDIR") sino nuevo("/tmp");
}

// La casa del usuario, que es donde van los ficheros de configuracion. Falla
// si no esta puesta, porque inventarse una seria peor que decirlo.
fn directorio_personal() -> str ! {
    return try variable_entorno("HOME");
}
