// std/camino.t — rutas de archivo, con `/` (como en Unix).
//
//     camino.nombre_de("a/b/c.t")   -> "c.t"
//     camino.carpeta_de("a/b/c.t")  -> "a/b"
//     camino.extension("c.t")       -> "t"
//     camino.unir_ruta("a", "b")    -> "a/b"
//
// Las funciones que miran una parte devuelven una VISTA de la ruta: no copian
// nada. `normalizar` si devuelve un `str`, porque recompone.

// La posicion de la ultima barra, o `largo(ruta)` si no hay ninguna.
fn ultima_barra(ruta: view) -> usize {
    var i = largo(ruta);
    while i > 0 {
        i = i - 1;
        if byte(ruta, i) == 47 { return i; }
    }
    return largo(ruta);
}

fn absoluta(ruta: view) -> bool {
    return largo(ruta) > 0 && byte(ruta, 0) == 47;
}

fn nombre_de(ruta: view) -> view {
    let b = ultima_barra(ruta);
    if b >= largo(ruta) { return ruta; }
    return rebanar(ruta, b + 1, largo(ruta));
}

fn carpeta_de(ruta: view) -> view {
    let b = ultima_barra(ruta);
    if b >= largo(ruta) { return ""; }
    if b == 0 { return "/"; }
    return rebanar(ruta, 0, b);
}

// El punto de la extension, o `largo(n)` si no tiene. Un punto al principio
// —`.gitignore`— no cuenta como extension.
fn punto_extension(n: view) -> usize {
    var i = largo(n);
    while i > 1 {
        i = i - 1;
        if byte(n, i) == 46 { return i; }
    }
    return largo(n);
}

fn extension(ruta: view) -> view {
    let n = nombre_de(ruta);
    let p = punto_extension(n);
    if p >= largo(n) { return ""; }
    return rebanar(n, p + 1, largo(n));
}

fn sin_extension(ruta: view) -> view {
    let n = nombre_de(ruta);
    let p = punto_extension(n);
    if p >= largo(n) { return n; }
    return rebanar(n, 0, p);
}

fn unir_ruta(a: view, b: view) -> str {
    if largo(a) == 0 { return nuevo(b); }
    if largo(b) == 0 { return nuevo(a); }
    if byte(a, largo(a) - 1) == 47 { return $"{a}{b}"; }
    return $"{a}/{b}";
}

fn sin_ultima(xs: &lista<str>) -> lista<str> {
    var salida: lista<str> = [];
    var i = 0;
    while i + 1 < largo(xs) {
        anadir(salida, nuevo(xs[i]));
        i = i + 1;
    }
    return salida;
}

fn juntar(trozos: &lista<str>) -> str {
    var salida = vacio();
    var i = 0;
    while i < largo(trozos) {
        if i > 0 { empujar(salida, "/"); }
        empujar(salida, trozos[i]);
        i = i + 1;
    }
    return salida;
}

// Colapsa `//`, `.` y `..`. Si la ruta es absoluta, conserva la barra inicial;
// si no queda nada, devuelve ".".
fn normalizar(ruta: view) -> str {
    let raiz = absoluta(ruta);
    var trozos: lista<str> = [];
    var desde = 0;
    var i = 0;
    while i <= largo(ruta) {
        if i == largo(ruta) || byte(ruta, i) == 47 {
            let t = rebanar(ruta, desde, i);
            if largo(t) > 0 && !igual(t, ".") {
                if igual(t, "..") && largo(trozos) > 0
                && !igual(trozos[largo(trozos) - 1], "..") {
                    trozos = sin_ultima(trozos);
                } else if !igual(t, "..") || !raiz {
                    anadir(trozos, nuevo(t));
                }
            }
            desde = i + 1;
        }
        i = i + 1;
    }
    let cuerpo = juntar(trozos);
    if raiz { return $"/{cuerpo}"; }
    if largo(cuerpo) == 0 { return nuevo("."); }
    return cuerpo;
}
