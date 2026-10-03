// std/hash.t — hashes rapidos de contenido, de 32 bits.
//
//     let h = hash.fnv1a("hola");   // un u64 con los 32 bits de abajo
//     let d = hash.djb2("hola");
//
// Son para checksums, tablas propias y direccionar por contenido, no para
// criptografia. La multiplicacion se corta a 32 bits con `%`, porque la
// aritmetica de Tcode comprueba el desbordamiento y aqui se quiere envolver.

// FNV-1a de 32 bits (offset basis y primo de la especificacion).
fn fnv1a(v: view) -> u64 {
    var h: u64 = 2166136261;
    var i = 0;
    while i < largo(v) {
        h = h ^ (byte(v, i) como u64);
        h = (h * 16777619) % 4294967296;
        i = i + 1;
    }
    return h;
}

// djb2 de 32 bits: barato y reparte bien el texto.
fn djb2(v: view) -> u64 {
    var h: u64 = 5381;
    var i = 0;
    while i < largo(v) {
        h = (h * 33 + (byte(v, i) como u64)) % 4294967296;
        i = i + 1;
    }
    return h;
}

// Los 8 digitos hexadecimales del hash, para enseñarlo.
fn a_hex(h: u64) -> str {
    let d = "0123456789abcdef";
    var salida = vacio();
    var i = 8;
    while i > 0 {
        i = i - 1;
        let n = (h / potencia(16, i)) % 16;
        empujar_byte(salida, byte(d, n como usize) como u8);
    }
    return salida;
}

fn potencia(base: u64, exponente: usize) -> u64 {
    var r: u64 = 1;
    var i = 0;
    while i < exponente {
        r = r * base;
        i = i + 1;
    }
    return r;
}
