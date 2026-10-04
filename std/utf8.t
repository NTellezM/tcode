// std/utf8.t — leer y escribir texto como caracteres, no como bytes.
//
// Un `str` de Tcode guarda bytes: `largo` cuenta bytes y `byte(v, i)` da uno.
// Eso vale para casi todo, pero no para partir texto en español ni para
// alinear una tabla, porque «camión» son siete bytes y seis caracteres.
//
// Aqui esta lo que hace falta para las dos cosas: descodificar —con las
// comprobaciones de UTF-8, que son las que evitan que una secuencia corta de
// mas o un sustituto pasen por texto valido—, recorrer, trocear contando
// caracteres y medir lo que ocupa al imprimirlo.

// ------------------------------------------------------------- descodificar

// El byte empieza un caracter, o continua el anterior.
fn es_inicio(b: usize) -> bool {
    return b < 128 || (b >= 194 && b <= 244);
}

fn es_continuacion(b: usize) -> bool {
    return b >= 128 && b <= 191;
}

// Cuantos bytes ocupa el caracter que empieza en `i`. Cero si ahi no empieza
// uno valido, si la secuencia se corta o si no lo es: ni las cortas de mas
// —`0xC0` y `0xC1`—, ni los sustitutos, ni nada por encima de U+10FFFF.
fn bytes_de(v: view, i: usize) -> usize {
    if i >= largo(v) { return 0; }
    let b = byte(v, i);
    if b < 128 { return 1; }
    var cuantos = 0;
    if b >= 194 && b <= 223 { cuantos = 2; }
    else if b >= 224 && b <= 239 { cuantos = 3; }
    else if b >= 240 && b <= 244 { cuantos = 4; }
    else { return 0; }
    if i + cuantos > largo(v) { return 0; }
    var k = 1;
    while k < cuantos {
        if !es_continuacion(byte(v, i + k)) { return 0; }
        k = k + 1;
    }
    let b1 = byte(v, i + 1);
    if cuantos == 3 && b == 224 && b1 < 160 { return 0; }
    if cuantos == 3 && b == 237 && b1 > 159 { return 0; }
    if cuantos == 4 && b == 240 && b1 < 144 { return 0; }
    if cuantos == 4 && b == 244 && b1 > 143 { return 0; }
    return cuantos;
}

// El valor del caracter que empieza en `i`. Falla si ahi no hay uno valido.
fn caracter(v: view, i: usize) -> u32 ! {
    let n = bytes_de(v, i);
    if n == 0 { fail "no hay un caracter UTF-8 en esa posicion"; }
    let b = byte(v, i);
    if n == 1 { return b como u32; }
    var c = (b & (255 >> (n + 1))) como u32;
    var k = 1;
    while k < n {
        c = (c << 6) | ((byte(v, i + k) & 63) como u32);
        k = k + 1;
    }
    return c;
}

// Lo mismo, con un valor por defecto en vez de fallar. El de serie para lo
// que no se puede leer es U+FFFD, el caracter de reemplazo.
fn caracter_o(v: view, i: usize, defecto: u32) -> u32 {
    return caracter(v, i) sino defecto;
}

fn reemplazo() -> u32 { return 65533; }

// ---------------------------------------------------------------- recorrer

// El indice del caracter siguiente. Si ahi no hay uno valido avanza un byte:
// asi un texto con un byte roto se recorre entero igual, en vez de perder lo
// que venga detras.
fn siguiente(v: view, i: usize) -> usize {
    let n = bytes_de(v, i);
    if n == 0 { return i + 1; }
    return i + n;
}

// Cuantos caracteres hay.
fn cuantos(v: view) -> usize {
    var i = 0;
    var n = 0;
    while i < largo(v) {
        i = siguiente(v, i);
        n = n + 1;
    }
    return n;
}

// Si todo el texto es UTF-8 valido.
fn valido(v: view) -> bool {
    var i = 0;
    while i < largo(v) {
        let n = bytes_de(v, i);
        if n == 0 { return false; }
        i = i + n;
    }
    return true;
}

// Donde empieza cada caracter. Es lo que usan `trozo` y `recortar_a_ancho`,
// y sirve para recorrer al reves.
fn indices(v: view) -> list<usize> {
    var xs: list<usize> = [];
    var i = 0;
    while i < largo(v) {
        anadir(xs, i);
        i = siguiente(v, i);
    }
    return xs;
}

// El trozo que va del caracter `desde` al `hasta`, contando caracteres y no
// bytes. Los indices fuera de rango se recortan.
fn trozo(v: view, desde: usize, hasta: usize) -> view {
    let xs = indices(v);
    if largo(xs) == 0 { return rebanar(v, 0, 0); }
    if desde >= largo(xs) { return rebanar(v, largo(v), largo(v)); }
    if hasta <= desde { return rebanar(v, xs[desde], xs[desde]); }
    if hasta >= largo(xs) { return rebanar(v, xs[desde], largo(v)); }
    return rebanar(v, xs[desde], xs[hasta]);
}

// --------------------------------------------------------------- codificar

// Escribe el caracter al final de `destino`. Falla si el valor no es un
// caracter: ni un sustituto ni nada por encima de U+10FFFF.
fn codificar(destino: mut str, c: u32) ! {
    if c > 1114111 || (c >= 55296 && c <= 57343) {
        fail "eso no es un caracter";
    }
    if c < 128 {
        empujar_byte(destino, c como u8);
        return;
    }
    if c < 2048 {
        empujar_byte(destino, (192 | (c >> 6)) como u8);
        empujar_byte(destino, (128 | (c & 63)) como u8);
        return;
    }
    if c < 65536 {
        empujar_byte(destino, (224 | (c >> 12)) como u8);
        empujar_byte(destino, (128 | ((c >> 6) & 63)) como u8);
        empujar_byte(destino, (128 | (c & 63)) como u8);
        return;
    }
    empujar_byte(destino, (240 | (c >> 18)) como u8);
    empujar_byte(destino, (128 | ((c >> 12) & 63)) como u8);
    empujar_byte(destino, (128 | ((c >> 6) & 63)) como u8);
    empujar_byte(destino, (128 | (c & 63)) como u8);
}

// El caracter como un texto nuevo.
fn de_caracter(c: u32) -> str ! {
    var s = vacio();
    try codificar(s, c);
    return s;
}

// -------------------------------------------------------------- lo que ocupa

// Lo que ocupa el caracter al imprimirlo: 0 si es una marca que se pega al
// anterior, 2 si es de ancho doble —los ideogramas y los emoji— y 1 si no.
//
// Es una aproximacion por rangos, no la tabla entera de Unicode: cubre lo que
// se ve en una tabla de texto y no pretende ser un motor de composicion.
fn ancho_de(c: u32) -> usize {
    if (c >= 768 && c <= 879) || (c >= 6832 && c <= 6911)
    || (c >= 7616 && c <= 7679) || (c >= 8400 && c <= 8447)
    || (c >= 65056 && c <= 65071) {
        return 0;
    }
    if (c >= 4352 && c <= 4447) || (c >= 11904 && c <= 42191)
    || (c >= 44032 && c <= 55203) || (c >= 63744 && c <= 64255)
    || (c >= 65040 && c <= 65049) || (c >= 65280 && c <= 65376)
    || (c >= 65504 && c <= 65510) || (c >= 127744 && c <= 129791)
    || (c >= 131072 && c <= 262141) {
        return 2;
    }
    return 1;
}

// Lo que ocupa el texto entero al imprimirlo. Es lo que hay que usar para
// alinear columnas: `largo` cuenta bytes y no vale para eso.
fn ancho(v: view) -> usize {
    var i = 0;
    var n = 0;
    while i < largo(v) {
        n = n + ancho_de(caracter_o(v, i, reemplazo()));
        i = siguiente(v, i);
    }
    return n;
}

// El trozo mas largo que cabe en `columnas`, cortando por caracter y sin
// partir ninguno por la mitad.
fn recortar_a_ancho(v: view, columnas: usize) -> view {
    var i = 0;
    var n = 0;
    while i < largo(v) {
        let w = ancho_de(caracter_o(v, i, reemplazo()));
        if n + w > columnas { break; }
        n = n + w;
        i = siguiente(v, i);
    }
    return rebanar(v, 0, i);
}
