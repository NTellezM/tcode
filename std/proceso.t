// Lanzar programas y saber como acabaron. Es lo que necesita un compilador
// para llamar a `cc`, y lo que hasta ahora resolvia `tcodec` con un shim en C.
//
// `system` devuelve el ESTADO que devuelve `wait`, no el codigo de salida: en
// POSIX el codigo de verdad son los bits 8 a 15. Aqui se saca con aritmetica
// en vez de con la macro `WEXITSTATUS`, que es una macro de C y no cruza el
// borde de `externo`.
//
// El parametro es `view` a proposito: el borde con C no acepta vistas, asi que
// la conversion a `str` propio se hace aqui dentro y quien llama puede pasar un
// literal tranquilamente.
//
// Tambien sabe quedarse con lo que la orden imprime: `salida_de`. Eso pide
// `proceso.c`, al lado de este archivo, porque `popen` devuelve un `FILE*` y el
// texto crece sin saber cuanto: nada de eso cruza el borde.

externo "stdlib.h" {
    fn system(orden: str) -> i32;
}

// Lanza la orden por el shell, espera a que termine y devuelve su codigo de
// salida. Falla solo si no se pudo lanzar: que el programa salga con error es
// una respuesta, no un fallo.
fn ejecutar(orden: view) -> i32 ! {
    let estado = system(nuevo(orden));
    if estado < 0 { fail "no se pudo lanzar la orden"; }
    if estado == (127 como i32) { fail "el shell no encontro esa orden"; }
    return (estado >> 8) & (255 como i32);
}

// Si la orden acaba bien. Es el atajo que se usa casi siempre.
fn va_bien(orden: view) -> bool ! {
    return try ejecutar(orden) == 0;
}

// ------------------------------------------------------- lo que imprime

// `popen` devuelve un `FILE*` y el texto crece sin saber cuanto: nada de eso
// cabe en el borde, asi que se envuelve en `proceso.c`, al lado de este
// archivo.
//
// El buffer es de C. Al volver de `capturar_salida`, Tcode se queda una copia
// —eso lo hace el borde con `cadena_c`— y `capturar_liberar` suelta el
// original despues, cuando la copia ya existe.
externo "proceso.c" {
    fn capturar_salida(orden: str) -> cadena_c;
    fn capturar_fallo() -> i32;
    fn capturar_estado() -> i32;
    fn capturar_truncada() -> i32;
    fn capturar_largo() -> usize;
    fn capturar_tope(tope: usize);
    fn capturar_liberar();
}

// Lo que imprime una orden por su salida estandar, con un tope para que una
// orden que no para no se coma la memoria.
//
// Falla si no se pudo lanzar, si el shell no la encontro, o si la salida no
// cabia en el tope. Que la orden salga con error NO es un fallo: es una
// respuesta, igual que en `ejecutar`, y el texto se devuelve igual. Del codigo
// de salida solo se mira el 127 con el que el shell dice que no encontro la
// orden; `capturar_estado` esta debajo para quien lo necesite.
//
// El texto es de Tcode en cuanto vuelve: la copia la hace el borde, y el
// buffer de C se suelta aqui mismo, antes de cualquier `fail`.
fn salida_de_hasta(orden: view, tope: usize) -> str ! {
    capturar_tope(tope);
    let texto = capturar_salida(nuevo(orden));
    let fallo = capturar_fallo();
    let estado = capturar_estado();
    let truncada = capturar_truncada();
    capturar_liberar();
    if fallo != 0 { fail "no se pudo lanzar la orden"; }
    if truncada != 0 { fail "la orden imprime mas de lo que cabe en el tope"; }
    if estado < 0 { fail "no se pudo recoger el final de la orden"; }
    if ((estado >> 8) & (255 como i32)) == (127 como i32) {
        fail "el shell no encontro esa orden";
    }
    return texto;
}

// Lo que imprime una orden, con el tope de siempre: 8 MiB.
fn salida_de(orden: view) -> str ! {
    return try salida_de_hasta(orden, 8388608);
}
