// std/bytes.t — leer y escribir enteros en un buffer.
//
// Un `str` de Tcode guarda bytes, no texto: puede tener un cero dentro y no
// se toca nada al copiarlo. Eso es lo que permite usarlo como buffer.
//
// Todo va en orden de red (el byte mas significativo primero), que es el que
// usan los protocolos. Las funciones de lectura fallan si no hay bytes
// suficientes, en vez de leer lo que haya detras.

fn poner_u8(destino: mut str, v: u8) {
    empujar_byte(destino, v);
}

fn poner_u16(destino: mut str, v: u16) {
    empujar_byte(destino, (v >> 8) como u8);
    empujar_byte(destino, (v & 255) como u8);
}

fn poner_u32(destino: mut str, v: u32) {
    empujar_byte(destino, (v >> 24) como u8);
    empujar_byte(destino, ((v >> 16) & 255) como u8);
    empujar_byte(destino, ((v >> 8) & 255) como u8);
    empujar_byte(destino, (v & 255) como u8);
}

fn poner_u64(destino: mut str, v: u64) {
    var i = 8;
    while i > 0 {
        i = i - 1;
        empujar_byte(destino, ((v >> (i * 8)) & 255) como u8);
    }
}

fn leer_u8(v: view, desde: usize) -> u8 ! {
    if desde >= largo(v) { falla "se acabaron los bytes"; }
    return byte(v, desde) como u8;
}

fn leer_u16(v: view, desde: usize) -> u16 ! {
    if desde + 2 > largo(v) { falla "se acabaron los bytes"; }
    var n: u16 = 0;
    var i = 0;
    while i < 2 {
        n = (n << 8) | (byte(v, desde + i) como u16);
        i = i + 1;
    }
    return n;
}

fn leer_u32(v: view, desde: usize) -> u32 ! {
    if desde + 4 > largo(v) { falla "se acabaron los bytes"; }
    var n: u32 = 0;
    var i = 0;
    while i < 4 {
        n = (n << 8) | (byte(v, desde + i) como u32);
        i = i + 1;
    }
    return n;
}

fn leer_u64(v: view, desde: usize) -> u64 ! {
    if desde + 8 > largo(v) { falla "se acabaron los bytes"; }
    var n: u64 = 0;
    var i = 0;
    while i < 8 {
        n = (n << 8) | (byte(v, desde + i) como u64);
        i = i + 1;
    }
    return n;
}

// ---------- hexadecimal ----------

fn a_hex(v: view) -> str {
    let digitos = "0123456789abcdef";
    var salida = vacio();
    var i = 0;
    while i < largo(v) {
        let b = byte(v, i);
        empujar(salida, rebanar(digitos, b / 16, b / 16 + 1));
        empujar(salida, rebanar(digitos, b % 16, b % 16 + 1));
        i = i + 1;
    }
    return salida;
}

fn valor_hex(b: usize) -> usize ! {
    if b >= 48 && b <= 57 { return b - 48; }
    if b >= 97 && b <= 102 { return b - 87; }
    if b >= 65 && b <= 70 { return b - 55; }
    falla "eso no es un digito hexadecimal";
}

fn de_hex(v: view) -> str ! {
    if largo(v) % 2 != 0 { falla "un hexadecimal tiene un numero par de digitos"; }
    var salida = vacio();
    var i = 0;
    while i < largo(v) {
        let alto = try valor_hex(byte(v, i));
        let bajo = try valor_hex(byte(v, i + 1));
        empujar_byte(salida, (alto * 16 + bajo) como u8);
        i = i + 2;
    }
    return salida;
}
