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

// La carpeta de una ruta, o `.` si la ruta no trae ninguna. Es la carpeta
// que hay que darle a una funcion del sistema cuando se le pide trabajar
// «al lado de» algo: `carpeta_de("a.t")` esta vacia, pero el directorio de
// `a.t` es el actual, y `.` lo dice sin ambiguedad.
fn carpeta_o_actual(ruta: view) -> str {
    let c = carpeta_de(ruta);
    if largo(c) == 0 { return nuevo("."); }
    return nuevo(c);
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

// Las dos rebanan de `ruta`, la vista que entra, y no de `nombre_de(ruta)`,
// que es una vista local: la que sale de la funcion tiene que ser de algo que
// siga vivo, y `ruta` lo esta. Por eso llevan la cuenta del trozo que
// `nombre_de` deja al final.
fn extension(ruta: view) -> view {
    let n = nombre_de(ruta);
    let p = punto_extension(n);
    if p >= largo(n) { return ""; }
    return rebanar(ruta, largo(ruta) - largo(n) + p + 1, largo(ruta));
}

// La ruta sin la extension, pero CON la carpeta: `sin_extension("a/b/c.t")`
// es `a/b/c`, no `c`. Quitar la carpeta es cosa de `nombre_de`, no de esta.
// Es lo que hace el ayudante privado que `tcodec.t` tiene con este nombre.
fn sin_extension(ruta: view) -> view {
    let n = nombre_de(ruta);
    let p = punto_extension(n);
    let desde = largo(ruta) - largo(n);
    if p >= largo(n) { return ruta; }
    return rebanar(ruta, 0, desde + p);
}

fn unir_ruta(a: view, b: view) -> str {
    if largo(a) == 0 { return nuevo(b); }
    if largo(b) == 0 { return nuevo(a); }
    if byte(a, largo(a) - 1) == 47 { return $"{a}{b}"; }
    return $"{a}/{b}";
}

fn sin_ultima(xs: &list<str>) -> list<str> {
    var salida: list<str> = [];
    var i = 0;
    while i + 1 < largo(xs) {
        anadir(salida, nuevo(xs[i]));
        i = i + 1;
    }
    return salida;
}

fn juntar(trozos: &list<str>) -> str {
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
    var trozos: list<str> = [];
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
