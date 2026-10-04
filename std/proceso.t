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
