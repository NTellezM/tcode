// std/compresion.t — inflar lo que comprime el resto del mundo.
//
// Aqui solo se DESCOMPRIME. DEFLATE crudo (RFC 1951) y sus dos envoltorios
// de siempre: zlib (RFC 1950), que es lo que lleva un PNG o un `zlib.compress`
// de Python, y gzip (RFC 1952), que es lo que lleva un `.gz`.
//
//     let texto = inflar_zlib(datos);
//     let texto = inflar_gzip(datos);
//     let texto = inflar_deflate(datos);
//
// `inflar_deflate` entiende los tres tipos de bloque: los guardados sin
// comprimir (BTYPE 00), los de Huffman fijo (BTYPE 01) y los de Huffman
// dinamico (BTYPE 10). Con eso se lee cualquier flujo que salga de zlib,
// gzip, PNG o del `deflate` de Java, que es lo que se pretendia.
//
// Los envoltorios comprueban su suma: `inflar_zlib` mira el adler32 del
// final y `inflar_gzip` el crc32 y el tamaño. Si no cuadran, falla en vez de
// devolver basura.
//
// Lo unico que se ESCRIBE es `deflar_guardado`, y no comprime nada: envuelve
// los datos en un flujo zlib hecho de bloques guardados, que ocupan un poco
// mas que la entrada (cinco bytes por cada 65535). Es un zlib valido que
// cualquier programa del mundo sabe leer, y sirve para dar salida a algo que
// otra herramienta espera comprimido. Comprimir de verdad pide LZ77 y
// Huffman, y eso no esta aqui.

use "std/bytes";
use "std/crc";

// ---------- adler32 ----------

// La suma de verificacion de zlib: dos acumuladores de 16 bits, modulo 65521,
// que empiezan en 1 y 0. Es mas debil que el CRC-32 y por eso es mas barata.
fn adler32(v: view) -> u32 {
    var a: u32 = 1;
    var b: u32 = 0;
    var i = 0;
    while i < largo(v) {
        a = (a + (byte(v, i) como u32)) % 65521;
        b = (b + a) % 65521;
        i = i + 1;
    }
    return (b << 16) | a;
}

// ---------- lectura de bits ----------

// Lee `cuantos` bits (de 1 a 16) en el orden de DEFLATE: dentro de cada byte
// del de menos peso al de mas, y los bytes en el orden en que estan. `pos`
// es la posicion en bits, que va avanzando entre llamadas.
fn deflate_bits(v: view, pos: mut usize, cuantos: usize) -> u32 ! {
    var valor: u32 = 0;
    var i = 0;
    while i < cuantos {
        let idx = pos / 8;
        if idx >= largo(v) { fail "el flujo DEFLATE se acabo antes de tiempo"; }
        let bit = ((byte(v, idx) como u32) >> ((pos % 8) como u32)) & 1;
        valor = valor | (bit << (i como u32));
        pos = pos + 1;
        i = i + 1;
    }
    return valor;
}

// Deja `pos` en el primer bit del byte siguiente. Los bloques guardados
// empiezan en un byte, no donde acabo el bloque anterior.
fn deflate_a_byte(pos: mut usize) {
    pos = pos + ((8 - (pos % 8)) % 8);
}

// ---------- Huffman ----------

// Un arbol de Huffman listo para decodificar, en la forma canonica: cuantas
// claves hay de cada longitud (`cuentas[1..15]`, la 0 no cuenta) y los
// simbolos ordenados por longitud y luego por valor de la clave.
struct Huffman {
    cuentas: bloque<usize>,
    simbolos: bloque<usize>,
}

// Arma el arbol a partir de la longitud de cada simbolo (0 = no se usa).
// `longitudes` trae `nsyms` longitudes desde `desde`, porque las tablas de
// distancia viven pegadas a las de longitud en los bloques dinamicos.
fn deflate_huffman(longitudes: &bloque<usize>, desde: usize, nsyms: usize) -> Huffman {
    var h = Huffman { cuentas: reservar(16), simbolos: reservar(nsyms) };
    var i = 0;
    while i < 16 {
        h.cuentas[i] = 0;
        i = i + 1;
    }
    i = 0;
    while i < nsyms {
        let l = copiar(longitudes[desde + i]);
        h.cuentas[l] = h.cuentas[l] + 1;
        i = i + 1;
    }
    h.cuentas[0] = 0;

    // Donde empieza en `simbolos` la primera clave de cada longitud.
    var inicio: bloque<usize> = reservar(16);
    var suma = 0;
    var len = 1;
    while len < 16 {
        inicio[len] = suma;
        suma = suma + h.cuentas[len];
        len = len + 1;
    }
    i = 0;
    while i < nsyms {
        let l = copiar(longitudes[desde + i]);
        if l != 0 {
            h.simbolos[inicio[l]] = i;
            inicio[l] = inicio[l] + 1;
        }
        i = i + 1;
    }
    return h;
}

// El simbolo que sigue, leyendo del flujo los bits que hagan falta. Se
// recorre la tabla por longitudes: `primero` es la clave mas pequeña de esa
// longitud y `codigo` lo que se lleva leido.
fn deflate_simbolo(v: view, pos: mut usize, h: &Huffman) -> usize ! {
    var codigo = 0;
    var primero = 0;
    var indice = 0;
    var len = 1;
    while len < 16 {
        codigo = codigo | ((try deflate_bits(v, pos, 1)) como usize);
        let cuenta = copiar(h.cuentas[len]);
        if codigo - primero < cuenta {
            return copiar(h.simbolos[indice + codigo - primero]);
        }
        indice = indice + cuenta;
        primero = (primero + cuenta) * 2;
        codigo = codigo * 2;
        len = len + 1;
    }
    fail "hay un codigo de Huffman que no existe en la tabla";
}

// ---------- el cuerpo comprimido de un bloque ----------

// Descodifica los simbolos de un bloque ya comprimido y los va escribiendo en
// `salida`, que se conserva entre bloques para que las copias puedan
// referirse a lo ya descomprimido.
fn deflate_cuerpo(v: view, pos: mut usize, salida: mut str,
    lit: &Huffman, dist: &Huffman) ! {
    let bases_long: [usize; 29] = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
    ];
    let extras_long: [usize; 29] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
    ];
    let bases_dist: [usize; 30] = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129,
        193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097,
        6145, 8193, 12289, 16385, 24577
    ];
    let extras_dist: [usize; 30] = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6,
        6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
    ];

    var fin = false;
    while fin == false {
        let simbolo = try deflate_simbolo(v, pos, lit);
        if simbolo < 256 {
            empujar_byte(salida, simbolo como u8);
        } else if simbolo == 256 {
            fin = true;
        } else {
            let idx = simbolo - 257;
            if idx >= 29 { fail "esa longitud de copia no existe"; }
            let cuantos = bases_long[idx]
            + ((try deflate_bits(v, pos, extras_long[idx])) como usize);
            let dsym = try deflate_simbolo(v, pos, dist);
            if dsym >= 30 { fail "esa distancia no existe"; }
            let distancia = bases_dist[dsym]
            + ((try deflate_bits(v, pos, extras_dist[dsym])) como usize);
            if distancia > largo(salida) {
                fail "una distancia apunta antes del principio de los datos";
            }
            // Byte a byte y sin atajo: si la distancia es menor que lo que se
            // copia, la copia se solapa consigo misma y hay que ir viendo lo
            // que se acaba de escribir. Es lo que hace que `"aaaa"` se
            // descomprima con una distancia de 1.
            var k = 0;
            while k < cuantos {
                let b = byte(salida, largo(salida) - distancia) como u8;
                empujar_byte(salida, b);
                k = k + 1;
            }
        }
    }
}

// Un bloque guardado (BTYPE 00): sus bytes van tal cual, entre la longitud y
// su complemento.
fn deflate_guardado(v: view, pos: mut usize, salida: mut str) ! {
    deflate_a_byte(pos);
    let p = pos / 8;
    if p + 4 > largo(v) { fail "el bloque guardado esta cortado"; }
    let n = byte(v, p) | (byte(v, p + 1) << 8);
    let complemento = byte(v, p + 2) | (byte(v, p + 3) << 8);
    if (n ^ 65535) != complemento { fail "la longitud del bloque guardado no cuadra"; }
    if p + 4 + n > largo(v) { fail "el bloque guardado esta cortado"; }
    var i = 0;
    while i < n {
        empujar_byte(salida, byte(v, p + 4 + i) como u8);
        i = i + 1;
    }
    pos = (p + 4 + n) * 8;
}

// ---------- DEFLATE crudo ----------

fn inflar_deflate(datos: view) -> str ! {
    var pos = 0;
    var salida = vacio();
    var ultimo = false;
    while ultimo == false {
        ultimo = (try deflate_bits(datos, pos, 1)) == 1;
        let tipo = try deflate_bits(datos, pos, 2);
        if tipo == 0 {
            try deflate_guardado(datos, pos, salida);
        } else if tipo == 1 {
            // Huffman fijo: las longitudes las fija la RFC 1951 y no viajan
            // en el flujo.
            var llen: bloque<usize> = reservar(288);
            var i = 0;
            while i < 144 { llen[i] = 8; i = i + 1; }
            while i < 256 { llen[i] = 9; i = i + 1; }
            while i < 280 { llen[i] = 7; i = i + 1; }
            while i < 288 { llen[i] = 8; i = i + 1; }
            let lit = deflate_huffman(llen, 0, 288);

            var dlen: bloque<usize> = reservar(30);
            i = 0;
            while i < 30 { dlen[i] = 5; i = i + 1; }
            let dist = deflate_huffman(dlen, 0, 30);
            try deflate_cuerpo(datos, pos, salida, lit, dist);
        } else if tipo == 2 {
            // Huffman dinamico: las longitudes vienen en el propio flujo,
            // comprimidas a su vez con otro arbol de Huffman.
            let hlit = ((try deflate_bits(datos, pos, 5)) como usize) + 257;
            let hdist = ((try deflate_bits(datos, pos, 5)) como usize) + 1;
            let hclen = ((try deflate_bits(datos, pos, 4)) como usize) + 4;
            if hlit > 286 { fail "el flujo pide demasiados codigos de longitud"; }
            if hdist > 30 { fail "el flujo pide demasiadas distancias"; }

            let orden: [usize; 19] = [
                16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
            ];
            var clen: bloque<usize> = reservar(19);
            var i = 0;
            while i < hclen {
                clen[orden[i]] = (try deflate_bits(datos, pos, 3)) como usize;
                i = i + 1;
            }
            let arbol = deflate_huffman(clen, 0, 19);

            var llen: bloque<usize> = reservar(320);
            let total = hlit + hdist;
            var j = 0;
            while j < total {
                let sym = try deflate_simbolo(datos, pos, arbol);
                if sym < 16 {
                    llen[j] = sym;
                    j = j + 1;
                } else {
                    var cuantas = 0;
                    var valor = 0;
                    if sym == 16 {
                        if j == 0 { fail "hay una repeticion sin nada que repetir"; }
                        cuantas = 3 + ((try deflate_bits(datos, pos, 2)) como usize);
                        valor = copiar(llen[j - 1]);
                    } else if sym == 17 {
                        cuantas = 3 + ((try deflate_bits(datos, pos, 3)) como usize);
                    } else if sym == 18 {
                        cuantas = 11 + ((try deflate_bits(datos, pos, 7)) como usize);
                    } else {
                        fail "esa longitud de codigo no existe";
                    }
                    if j + cuantas > total {
                        fail "las longitudes de codigo se salen de la tabla";
                    }
                    var k = 0;
                    while k < cuantas { llen[j] = valor; j = j + 1; k = k + 1; }
                }
            }

            let lit = deflate_huffman(llen, 0, hlit);
            let dist = deflate_huffman(llen, hlit, hdist);
            try deflate_cuerpo(datos, pos, salida, lit, dist);
        } else {
            fail "el flujo usa el tipo de bloque reservado";
        }
    }
    return salida;
}

// ---------- zlib y gzip ----------

fn inflar_zlib(datos: view) -> str ! {
    if largo(datos) < 6 { fail "un flujo zlib no puede ser tan corto"; }
    let cmf = byte(datos, 0);
    let flg = byte(datos, 1);
    if cmf & 15 != 8 { fail "el metodo de compresion no es DEFLATE"; }
    if (cmf * 256 + flg) % 31 != 0 { fail "la cabecera zlib no cuadra"; }
    if flg & 32 != 0 { fail "no se admiten diccionarios predefinidos"; }

    let cuerpo = rebanar(datos, 2, largo(datos) - 4);
    let salida = try inflar_deflate(cuerpo);
    let esperado = try leer_u32(datos, largo(datos) - 4);
    if adler32(vista(salida)) != esperado { fail "el adler32 del flujo no cuadra"; }
    return salida;
}

fn inflar_gzip(datos: view) -> str ! {
    if largo(datos) < 18 { fail "un flujo gzip no puede ser tan corto"; }
    if byte(datos, 0) != 31 || byte(datos, 1) != 139 {
        fail "no tiene la marca de gzip";
    }
    if byte(datos, 2) != 8 { fail "el metodo de compresion no es DEFLATE"; }
    let flg = byte(datos, 3);

    // Los campos opcionales de la cabecera, cada uno con su bandera.
    var pos = 10;
    if flg & 4 != 0 {
        if pos + 2 > largo(datos) { fail "la cabecera gzip esta cortada"; }
        let xlen = byte(datos, pos) | (byte(datos, pos + 1) << 8);
        pos = pos + 2 + xlen;
    }
    if flg & 8 != 0 { pos = try deflate_salta_cadena(datos, pos); }
    if flg & 16 != 0 { pos = try deflate_salta_cadena(datos, pos); }
    if flg & 2 != 0 { pos = pos + 2; }
    if pos + 8 > largo(datos) { fail "el flujo gzip esta cortado"; }

    let cuerpo = rebanar(datos, pos, largo(datos) - 8);
    let salida = try inflar_deflate(cuerpo);
    let esperado_crc = try deflate_u32_menor(datos, largo(datos) - 8);
    let esperado_tam = try deflate_u32_menor(datos, largo(datos) - 4);
    if crc32(vista(salida)) != esperado_crc { fail "el crc32 del flujo no cuadra"; }
    if (largo(salida) % 4294967296) como u32 != esperado_tam {
        fail "el tamaño del flujo gzip no cuadra";
    }
    return salida;
}

// El crc32 y el tamaño de la cola de gzip van en orden de byte MENOR, al
// reves que el adler32 de zlib, que va en orden de red como los enteros de
// `std/bytes`.
fn deflate_u32_menor(v: view, desde: usize) -> u32 ! {
    if desde + 4 > largo(v) { fail "el flujo se acabo antes de tiempo"; }
    return (byte(v, desde) como u32)
    | ((byte(v, desde + 1) como u32) << 8)
    | ((byte(v, desde + 2) como u32) << 16)
    | ((byte(v, desde + 3) como u32) << 24);
}

// Salta un texto acabado en cero (nombre o comentario de la cabecera gzip).
fn deflate_salta_cadena(v: view, desde: usize) -> usize ! {
    var p = desde;
    while p < largo(v) {
        if byte(v, p) == 0 { return p + 1; }
        p = p + 1;
    }
    fail "la cabecera gzip esta cortada";
}

// ---------- escribir: bloques guardados ----------

// El envoltorio zlib, con bloques GUARDADOS: no comprime absolutamente nada.
// La salida es la entrada mas cinco bytes por cada 65535 y mas los seis de la
// cabecera y el adler32. Es un flujo zlib valido para `zlib.decompress` y
// para cualquier descompresor, y por eso sirve para dar salida a algo que
// otra herramienta espera con cabecera zlib. Para comprimir de verdad hacen
// falta LZ77 y Huffman, que este modulo no trae.
fn deflar_guardado(datos: view) -> str {
    var salida = vacio();
    // CMF: DEFLATE con ventana de 32K. FLG: sin diccionario, y el par
    // (CMF*256+FLG) tiene que ser multiplo de 31.
    empujar_byte(salida, $78);
    empujar_byte(salida, $01);

    var desde = 0;
    var seguir = true;
    while seguir {
        let quedan = largo(datos) - desde;
        let n = if quedan > 65535 { 65535 } else { quedan };
        let ultimo = desde + n >= largo(datos);
        // El bloque guardado empieza en byte: BFINAL en el bit 0 y BTYPE 00,
        // y como los bits de relleno son ceros, queda un solo byte.
        if ultimo { empujar_byte(salida, 1); } else { empujar_byte(salida, 0); }
        empujar_byte(salida, (n & 255) como u8);
        empujar_byte(salida, ((n >> 8) & 255) como u8);
        let complemento = n ^ 65535;
        empujar_byte(salida, (complemento & 255) como u8);
        empujar_byte(salida, ((complemento >> 8) & 255) como u8);
        var i = 0;
        while i < n {
            empujar_byte(salida, byte(datos, desde + i) como u8);
            i = i + 1;
        }
        desde = desde + n;
        if ultimo { seguir = false; }
    }
    // El adler32 va al final y en orden de red.
    poner_u32(salida, adler32(datos));
    return salida;
}
