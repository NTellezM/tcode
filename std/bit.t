// std/bit.t — manejo de bits.
//
//     bit.prueba(x, 3)         // el bit 3, encendido?
//     bit.pon(x, 3)            // lo enciende
//     bit.cuenta(x)            // cuantos hay encendidos
//     bit.a_binario(x, 8)      // "00001010"
//
// Los bits se cuentan desde 0, el de menos peso.

// El bit `n` como numero: 2^n.
fn mascara(n: usize) -> u64 {
    var m: u64 = 1;
    var i = 0;
    while i < n {
        m = m * 2;
        i = i + 1;
    }
    return m;
}

fn prueba(x: u64, n: usize) -> bool {
    return (x / mascara(n)) % 2 == 1;
}

fn pon(x: u64, n: usize) -> u64 {
    return x | mascara(n);
}

// Apagarlo: se quitan los bits que ya estaban en la mascara.
fn quita(x: u64, n: usize) -> u64 {
    return x ^ (x & mascara(n));
}

fn alterna(x: u64, n: usize) -> u64 {
    return x ^ mascara(n);
}

// Cuantos bits hay encendidos.
fn cuenta(x: u64) -> usize {
    var n = 0;
    var v = x;
    while v > 0 {
        if v % 2 == 1 { n = n + 1; }
        v = v / 2;
    }
    return n;
}

// Los `digitos` de menos peso, en binario, con ceros delante.
fn a_binario(x: u64, digitos: usize) -> str {
    var s = vacio();
    var i = digitos;
    while i > 0 {
        i = i - 1;
        if (x / mascara(i)) % 2 == 1 { empujar(s, "1"); }
        else { empujar(s, "0"); }
    }
    return s;
}
