// std/base64.t — base64 (RFC 4648).
//
//     let texto = base64.codificar(datos);     // a texto, en una linea
//     let datos = base64.decodificar(texto);   // a bytes, puede fallar
//
// `codificar` da una sola linea, sin saltos. El formato de fichero —lineas de
// 76— se hace partiendo el resultado. `decodificar` ignora los saltos y los
// `\r`, asi que acepta lo que escriba `codificar` o el `base64` del sistema.

fn alfabeto() -> view {
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
}

// Los bytes a base64, en una sola linea.
fn codificar(v: view) -> str {
    let a = alfabeto();
    var salida = vacio();
    var i = 0;
    while i < largo(v) {
        let quedan = largo(v) - i;
        let b0 = byte(v, i);
        var b1 = 0;
        var b2 = 0;
        if quedan > 1 { b1 = byte(v, i + 1); }
        if quedan > 2 { b2 = byte(v, i + 2); }
        let n = b0 * 65536 + b1 * 256 + b2;
        empujar_byte(salida, (byte(a, n / 262144 % 64)) como u8);
        empujar_byte(salida, (byte(a, n / 4096 % 64)) como u8);
        if quedan > 1 { empujar_byte(salida, (byte(a, n / 64 % 64)) como u8); }
        else { empujar(salida, "="); }
        if quedan > 2 { empujar_byte(salida, (byte(a, n % 64)) como u8); }
        else { empujar(salida, "="); }
        i = i + 3;
    }
    return salida;
}

// El valor de un caracter del alfabeto, o 64 si no es del alfabeto.
fn valor(b: usize) -> usize {
    if b >= 65 && b <= 90 { return b - 65; }
    if b >= 97 && b <= 122 { return b - 97 + 26; }
    if b >= 48 && b <= 57 { return b - 48 + 52; }
    if b == 43 { return 62; }
    if b == 47 { return 63; }
    return 64;
}

fn decodificar(v: view) -> str ! {
    // Sin saltos de linea ni `\r`: el resto tiene que ser grupos de cuatro.
    var limpio = vacio();
    var i = 0;
    while i < largo(v) {
        let b = byte(v, i);
        if b != 10 && b != 13 { empujar_byte(limpio, b como u8); }
        i = i + 1;
    }
    if largo(limpio) % 4 != 0 { fail "la entrada no es base64"; }
    var salida = vacio();
    i = 0;
    while i < largo(limpio) {
        let ultimo = i + 4 == largo(limpio);
        var rellenos = 0;
        if byte(limpio, i + 3) == 61 { rellenos = 1; }
        if byte(limpio, i + 2) == 61 { rellenos = 2; }
        if rellenos > 0 && !ultimo { fail "la entrada no es base64"; }
        if rellenos == 2 && byte(limpio, i + 3) != 61 { fail "la entrada no es base64"; }
        var n = 0;
        var k = 0;
        while k < 4 {
            var d = 0;
            if k < 4 - rellenos {
                d = valor(byte(limpio, i + k));
                if d == 64 { fail "la entrada no es base64"; }
            }
            n = n * 64 + d;
            k = k + 1;
        }
        empujar_byte(salida, (n / 65536 % 256) como u8);
        if rellenos < 2 { empujar_byte(salida, (n / 256 % 256) como u8); }
        if rellenos < 1 { empujar_byte(salida, (n % 256) como u8); }
        i = i + 4;
    }
    return salida;
}
