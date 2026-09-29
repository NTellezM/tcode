// base64.t — codifica y decodifica base64 (RFC 4648), como `base64`.
//
//     ./base64 < datos          codifica, en lineas de 76 caracteres
//     ./base64 -d < texto       decodifica; los saltos de linea no cuentan
//
// Lee y escribe bytes: un cero en medio pasa igual que cualquier otro.

fn alfabeto() -> view {
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
}

fn codificar(v: view) -> str {
    let a = alfabeto();
    var salida = vacio();
    var en_linea = 0;
    var i = 0;
    while i < largo(v) {
        let quedan = largo(v) - i;
        let b0 = byte(v, i);
        var b1 = 0;
        var b2 = 0;
        if quedan > 1 { b1 = byte(v, i + 1); }
        if quedan > 2 { b2 = byte(v, i + 2); }
        let n = b0 * 65536 + b1 * 256 + b2;
        var cuatro = vacio();
        empujar_byte(cuatro, (byte(a, n / 262144 % 64)) como u8);
        empujar_byte(cuatro, (byte(a, n / 4096 % 64)) como u8);
        if quedan > 1 { empujar_byte(cuatro, (byte(a, n / 64 % 64)) como u8); } else { empujar(cuatro, "="); }
        if quedan > 2 { empujar_byte(cuatro, (byte(a, n % 64)) como u8); } else { empujar(cuatro, "="); }
        var k = 0;
        while k < 4 {
            if en_linea == 76 {
                empujar(salida, "\n");
                en_linea = 0;
            }
            empujar_byte(salida, (byte(cuatro, k)) como u8);
            en_linea = en_linea + 1;
            k = k + 1;
        }
        i = i + 3;
    }
    if largo(salida) > 0 { empujar(salida, "\n"); }
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
    // Sin saltos de linea: el resto tiene que ser grupos de cuatro.
    var limpio = vacio();
    var i = 0;
    while i < largo(v) {
        let b = byte(v, i);
        if b != 10 && b != 13 { empujar_byte(limpio, (b) como u8); }
        i = i + 1;
    }
    if largo(limpio) % 4 != 0 { falla "la entrada no es base64"; }
    var salida = vacio();
    i = 0;
    while i < largo(limpio) {
        let ultimo = i + 4 == largo(limpio);
        var rellenos = 0;
        if byte(limpio, i + 3) == 61 { rellenos = 1; }
        if byte(limpio, i + 2) == 61 { rellenos = 2; }
        if rellenos > 0 && !ultimo { falla "la entrada no es base64"; }
        if rellenos == 2 && byte(limpio, i + 3) != 61 { falla "la entrada no es base64"; }
        var n = 0;
        var k = 0;
        while k < 4 {
            var d = 0;
            if k < 4 - rellenos {
                d = valor(byte(limpio, i + k));
                if d == 64 { falla "la entrada no es base64"; }
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

fn main() -> usize ! {
    let entrada = try entrada_completa();
    if n_argumentos() > 1 && argumento(1) == "-d" {
        let datos = decodificar(entrada) sino vacio();
        if largo(datos) == 0 && largo(entrada) > 0 {
            // Una entrada que solo son saltos de linea no es un error.
            var solo_saltos = true;
            var i = 0;
            while i < largo(entrada) {
                if byte(entrada, i) != 10 && byte(entrada, i) != 13 { solo_saltos = false; }
                i = i + 1;
            }
            if !solo_saltos {
                imprimir_error("base64: la entrada no es base64\n");
                return 1;
            }
        }
        imprimir(datos);
        return 0;
    }
    imprimir(codificar(entrada));
    return 0;
}
