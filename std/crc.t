// std/crc.t — CRC-32, la suma de verificacion de zlib, gzip y PNG.
//
// Es el CRC-32 de siempre: polinomio invertido $EDB88320, registro inicial
// todo a unos y resultado invertido al final. Va byte a byte y sin tabla,
// porque para el tamaño de estos flujos la tabla no compensa y asi el modulo
// no gasta memoria.
//
//     let suma = crc32(datos);
//
// Para ir por trozos se encadena `crc32_continuar`, que trabaja con el mismo
// convenio que el `crc32` de zlib: la `previa` es el resultado ya terminado
// (0 si es el primer trozo) y lo que devuelve tambien. Encadenar trozos da
// exactamente lo mismo que llamar una vez con todo junto:
//
//     var suma: u32 = 0;
//     suma = crc32_continuar(suma, primer_trozo);
//     suma = crc32_continuar(suma, segundo_trozo);
//     // suma == crc32(primer_trozo + segundo_trozo)

fn crc32(v: view) -> u32 {
    return crc32_continuar(0, v);
}

fn crc32_continuar(previa: u32, v: view) -> u32 {
    var c: u32 = previa ^ $FFFFFFFF;
    var i = 0;
    while i < largo(v) {
        c = c ^ (byte(v, i) como u32);
        var k = 0;
        while k < 8 {
            if c & 1 == 1 {
                c = (c >> 1) ^ $EDB88320;
            } else {
                c = c >> 1;
            }
            k = k + 1;
        }
        i = i + 1;
    }
    return c ^ $FFFFFFFF;
}
