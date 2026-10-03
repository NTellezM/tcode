// std/toml.t — leer TOML (lo esencial).
//
//     let t = toml.leer(texto) sino [];
//     let host = toml.texto_de(t, "server.host", "localhost");
//     let p    = toml.entero_de(t, "server.port", 80);
//
// Lo que se lee: comentarios `#`, tablas `[a.b]`, claves `clave = valor` (y
// `a.b = valor`), y valores texto (`"..."` y `'...'`), enteros, decimales,
// booleanos y listas `[...]` (tambien partidas en varias lineas).
//
// Las claves se guardan con su ruta entera: `server.host`, no un arbol. Para
// leer configuracion es lo comodo, y evita pelearse con mapas anidados.

usar "std/texto";

enum Valor {
    Texto(str),
    Entero(i64),
    Decimal(f64),
    Cierto,
    Falso,
    Lista(lista<Valor>),
}

// ---------- leer ----------

fn es_digito_ascii(b: usize) -> bool {
    return b >= 48 && b <= 57;
}

fn limpia(v: view) -> str {
    return nuevo(recortar(v));
}

// El trozo entre comillas dobles, con sus escapes.
fn cadena_doble(s: view) -> str ! {
    var salida = vacio();
    var i = 1;
    while i < largo(s) {
        let b = byte(s, i);
        if b == 34 { return salida; }
        if b == 92 {
            i = i + 1;
            if i >= largo(s) { falla "un escape sin acabar"; }
            let e = byte(s, i);
            if e == 110 { empujar_byte(salida, 10); }
            else if e == 116 { empujar_byte(salida, 9); }
            else if e == 114 { empujar_byte(salida, 13); }
            else if e == 34 { empujar_byte(salida, 34); }
            else if e == 92 { empujar_byte(salida, 92); }
            else { falla "un escape desconocido"; }
            i = i + 1;
            continue;
        }
        empujar_byte(salida, b como u8);
        i = i + 1;
    }
    falla "una cadena sin cerrar";
}

// El trozo entre comillas simples: literal, sin escapes.
fn cadena_simple(s: view) -> str ! {
    var i = 1;
    while i < largo(s) {
        if byte(s, i) == 39 { return nuevo(rebanar(s, 1, i)); }
        i = i + 1;
    }
    falla "una cadena sin cerrar";
}

fn lee_entero(s: view) -> i64 ! {
    var i = 0;
    var n: i64 = 0;
    var algo = false;
    var negativo = false;
    if i < largo(s) && byte(s, i) == 45 { negativo = true; i = i + 1; }
    while i < largo(s) {
        let b = byte(s, i);
        if es_digito_ascii(b) {
            // El signo se aplica al ir sumando: asi el `return` es `n` y ya.
            if negativo { n = n * 10 - (b - 48) como i64; }
            else { n = n * 10 + (b - 48) como i64; }
            algo = true;
        }
        else if b == 95 { }
        else { falla "no es un entero"; }
        i = i + 1;
    }
    if !algo { falla "no es un entero"; }
    return n;
}

fn lee_decimal(s: view) -> f64 ! {
    var i = 0;
    var signo: f64 = 1.0;
    if i < largo(s) && byte(s, i) == 45 { signo = -1.0; i = i + 1; }
    else if i < largo(s) && byte(s, i) == 43 { i = i + 1; }
    var entero: f64 = 0.0;
    while i < largo(s) && es_digito_ascii(byte(s, i)) {
        entero = entero * 10.0 + (byte(s, i) - 48) como f64;
        i = i + 1;
    }
    var frac: f64 = 0.0;
    var escala: f64 = 1.0;
    if i < largo(s) && byte(s, i) == 46 {
        i = i + 1;
        while i < largo(s) && es_digito_ascii(byte(s, i)) {
            frac = frac * 10.0 + (byte(s, i) - 48) como f64;
            escala = escala * 10.0;
            i = i + 1;
        }
    }
    var exp: i64 = 0;
    if i < largo(s) && (byte(s, i) == 101 || byte(s, i) == 69) {
        i = i + 1;
        var signo_exp: i64 = 1;
        if i < largo(s) && byte(s, i) == 45 { signo_exp = -1; i = i + 1; }
        else if i < largo(s) && byte(s, i) == 43 { i = i + 1; }
        while i < largo(s) && es_digito_ascii(byte(s, i)) {
            exp = exp * 10 + (byte(s, i) - 48) como i64;
            i = i + 1;
        }
        exp = exp * signo_exp;
    }
    if i < largo(s) { falla "no es un decimal"; }
    var r = (entero + frac / escala) * signo;
    var k: i64 = 0;
    while k < exp { r = r * 10.0; k = k + 1; }
    while k > exp { r = r / 10.0; k = k - 1; }
    return r;
}

// Los trozos de `[a, b, c]`, ya sin el corchete de fuera.
fn trozos(s: view) -> lista<str> ! {
    var salida: lista<str> = [];
    var dentro = false;
    var desde = 0;
    var i = 0;
    while i < largo(s) {
        let b = byte(s, i);
        if b == 34 || b == 39 { dentro = !dentro; }
        else if b == 44 && !dentro {
            anadir(salida, nuevo(recortar(rebanar(s, desde, i))));
            desde = i + 1;
        }
        i = i + 1;
    }
    let ultimo = recortar(rebanar(s, desde, largo(s)));
    if largo(ultimo) > 0 { anadir(salida, nuevo(ultimo)); }
    return salida;
}

fn valor_de(s: view) -> Valor ! {
    let t = recortar(s);
    if largo(t) == 0 { falla "un valor vacio"; }
    let b = byte(t, 0);
    if b == 34 { return Valor.Texto(try cadena_doble(t)); }
    if b == 39 { return Valor.Texto(try cadena_simple(t)); }
    if b == 91 {
        let fin = largo(t);
        if byte(t, fin - 1) != 93 { falla "una lista sin cerrar"; }
        var xs: lista<Valor> = [];
        for trozo en try trozos(rebanar(t, 1, fin - 1)) {
            anadir(xs, try valor_de(trozo));
        }
        return Valor.Lista(xs);
    }
    if igual(t, "true") { return Valor.Cierto; }
    if igual(t, "false") { return Valor.Falso; }
    // Entero si no hay punto ni exponente; decimal si los hay.
    var hay = false;
    var i = 0;
    while i < largo(t) {
        let c = byte(t, i);
        if c == 46 || c == 101 || c == 69 { hay = true; }
        i = i + 1;
    }
    if hay { return Valor.Decimal(try lee_decimal(t)); }
    return Valor.Entero(try lee_entero(t));
}

// Cuenta corchetes de fuera, para saber si una lista ya cerro.
fn corchetes_cierran(s: view) -> bool {
    var hondo = 0;
    var dentro = false;
    var i = 0;
    while i < largo(s) {
        let b = byte(s, i);
        if b == 34 || b == 39 { dentro = !dentro; }
        else if !dentro && b == 91 { hondo = hondo + 1; }
        else if !dentro && b == 93 { hondo = hondo - 1; }
        i = i + 1;
    }
    return hondo <= 0;
}

fn leer(texto: view) -> mapa<str, Valor> ! {
    var t: mapa<str, Valor> = [];
    let ls = lineas(texto);
    var prefijo = vacio();
    var i = 0;
    while i < largo(ls) {
        let l = recortar(ls[i]);
        i = i + 1;
        if largo(l) == 0 { continue; }
        if byte(l, 0) == 35 { continue; }
        if byte(l, 0) == 91 {
            if largo(l) > 1 && byte(l, 1) == 91 {
                falla "`[[tabla]]` (listas de tablas) todavia no se lee";
            }
            let fin = indice_de(l, "]") sino largo(l);
            let dentro = recortar(rebanar(l, 1, fin));
            if largo(dentro) == 0 { falla "una tabla sin nombre"; }
            prefijo = $"{dentro}.";
            continue;
        }
        let igual = indice_de(l, "=") sino largo(l);
        if igual >= largo(l) { falla "una linea sin `=`"; }
        let clave = limpia(rebanar(l, 0, igual));
        if largo(clave) == 0 { falla "una clave vacia"; }
        var resto = limpia(rebanar(l, igual + 1, largo(l)));
        // Una lista puede seguir en las lineas de abajo.
        while largo(resto) > 0 && byte(resto, 0) == 91 && !corchetes_cierran(resto)
        && i < largo(ls) {
            empujar(resto, " ");
            empujar(resto, recortar(ls[i]));
            i = i + 1;
        }
        poner(t, nuevo($"{prefijo}{clave}"), try valor_de(resto));
    }
    return t;
}

// ---------- consultar ----------

fn tiene_clave(t: &mapa<str, Valor>, clave: view) -> bool {
    for k, v en t {
        if igual(k, clave) { return true; }
    }
    return false;
}

fn texto_de(t: &mapa<str, Valor>, clave: view, alterno: view) -> str {
    for k, v en t {
        if igual(k, clave) {
            match v {
                Valor.Texto(s) -> { return nuevo(s); }
                _ -> { return nuevo(alterno); }
            }
        }
    }
    return nuevo(alterno);
}

fn entero_de(t: &mapa<str, Valor>, clave: view, alterno: i64) -> i64 {
    for k, v en t {
        if igual(k, clave) {
            match v {
                Valor.Entero(n) -> { return n; }
                _ -> { return alterno; }
            }
        }
    }
    return alterno;
}

fn decimal_de(t: &mapa<str, Valor>, clave: view, alterno: f64) -> f64 {
    for k, v en t {
        if igual(k, clave) {
            match v {
                Valor.Decimal(x) -> { return x; }
                Valor.Entero(n) -> { return n como f64; }
                _ -> { return alterno; }
            }
        }
    }
    return alterno;
}

fn cierto_de(t: &mapa<str, Valor>, clave: view, alterno: bool) -> bool {
    for k, v en t {
        if igual(k, clave) {
            match v {
                Valor.Cierto -> { return true; }
                Valor.Falso -> { return false; }
                _ -> { return alterno; }
            }
        }
    }
    return alterno;
}

fn lista_de(t: &mapa<str, Valor>, clave: view) -> lista<Valor> ! {
    for k, v en t {
        if igual(k, clave) {
            match v {
                Valor.Lista(xs) -> { return copiar(xs); }
                _ -> { falla "esa clave no es una lista"; }
            }
        }
    }
    falla "no esta esa clave";
}
