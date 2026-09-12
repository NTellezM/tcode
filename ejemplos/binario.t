// binario.t — un formato binario de verdad: escribirlo, leerlo, verificarlo.
//
// Hasta que hubo anchos fijos y operaciones de bits, esto no se podia
// escribir en Tcode. Ahora cabe en sesenta lineas y el compilador sigue
// comprobandolo todo: cada byte que se lee lleva su indice comprobado, y
// cada conversion que no cabe para el programa en vez de truncar en silencio.
//
//     ./binario

usar "std/bytes";

struct Cabecera {
    version: u16,
    altura: u64,
    anterior: str,      // 4 bytes de resumen
}

fn escribir(c: &Cabecera) -> str {
    var buf = vacio();
    poner_u16(buf, c.version);
    poner_u64(buf, c.altura);
    empujar(buf, vista(c.anterior));
    // Al final, la suma de verificacion de todo lo anterior.
    poner_u32(buf, fletcher32(vista(buf)));
    return buf;
}

fn leer(v: view) -> Cabecera ! {
    if largo(v) < 18 { falla "la cabecera esta cortada"; }
    let cuerpo = rebanar(v, 0, largo(v) - 4);
    let esperada = try leer_u32(v, largo(v) - 4);
    if fletcher32(cuerpo) != esperada { falla "la suma de verificacion no cuadra"; }

    return Cabecera {
        version: try leer_u16(v, 0),
        altura: try leer_u64(v, 2),
        anterior: nuevo(rebanar(v, 10, 14)),
    };
}

// Fletcher-32: dos sumas que se arrastran, con el modulo que evita que
// desborden. Sirve para ver bits trabajando, no para guardar dinero.
fn fletcher32(v: view) -> u32 {
    var a: u32 = 1;
    var b: u32 = 0;
    var i = 0;
    while i < largo(v) {
        a = (a +? (byte(v, i) como u32)) % 65521;
        b = (b +? a) % 65521;
        i = i + 1;
    }
    return (b << 16) | a;
}

fn main() -> usize ! {
    let c = Cabecera { version: 2, altura: 1048576, anterior: nuevo("\xde\xad\xbe\xef") };
    let crudo = escribir(c);
    imprimir($"{largo(crudo)} bytes: {a_hex(vista(crudo))}\n");

    let vuelta = try leer(vista(crudo));
    imprimir($"version {vuelta.version}, altura {vuelta.altura}, anterior {a_hex(vista(vuelta.anterior))}\n");

    // Un byte cambiado y la suma deja de cuadrar. El fallo se sustituye por
    // una cabecera reconocible en vez de propagarse.
    var roto = nuevo(rebanar(vista(crudo), 0, 2));
    empujar_byte(roto, 255);
    empujar(roto, rebanar(vista(crudo), 3, largo(crudo)));
    let control = leer(vista(roto)) sino Cabecera {
        version: 0, altura: 0, anterior: nuevo(""),
    };
    imprimir($"con un byte cambiado: version {control.version}\n");
}
