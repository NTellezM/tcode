// std/uuid.t — identificadores unicos (UUID v4), sobre `azar`.
//
//     uuid.sembrar_del_reloj();
//     let id = uuid.v4();   // "9f1c8e2a-...-4...-a...-..."
//
// La version 4 es azar puro: 122 bits al azar y los bits que dicen la version
// y la variante. Para que dos ejecuciones no repitan, siembra el azar antes
// —`sembrar_del_reloj()` hace una mezcla barata del reloj—.

use "std/azar" como azar;

fn sembrar_del_reloj() {
    let t = ahora_ms() como u64;
    let m = monotono_ms() como u64;
    // El reloj de pared, arriba; el monotono, abajo. Sin desbordar.
    sembrar((t % 65536) * 4294967296 + (m % 4294967296));
}

fn v4() -> str {
    var b: list<usize> = [];
    var i = 0;
    while i < 16 {
        anadir(b, azar(256));
        i = i + 1;
    }
    b[6] = (b[6] & 15) | 64;  // version 4
    b[8] = (b[8] & 63) | 128; // variante 10xx
    return formatear(b);
}

fn formatear(b: &list<usize>) -> str {
    let d = "0123456789abcdef";
    var salida = vacio();
    var i = 0;
    while i < 16 {
        if i == 4 || i == 6 || i == 8 || i == 10 { empujar(salida, "-"); }
        let n = b[i];
        empujar_byte(salida, byte(d, n / 16) como u8);
        empujar_byte(salida, byte(d, n % 16) como u8);
        i = i + 1;
    }
    return salida;
}
