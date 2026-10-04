// std/glob.t — coincidencia de patrones, con `*` y `?`.
//
//     glob.coincide("hola.txt", "*.txt")   -> true
//     glob.coincide("hola.txt", "h?la*")   -> true
//     glob.coincide("hola.txt", "*.md")    -> false
//
// `*` casa con cualquier trozo, tambien con `/`; `?` casa con un caracter.
// Es la regla de `fnmatch`, que es la que se espera en un filtro de nombres.

fn coincide(texto: view, patron: view) -> bool {
    var t = 0;
    var p = 0;
    // Donde estaba la ultima `*`, y hasta donde llego casando. Sin ella,
    // `largo(patron)` es el centinela de "ninguna".
    var estrella = largo(patron);
    var marca = 0;
    while t < largo(texto) {
        if p < largo(patron)
        && (byte(patron, p) == 63 || byte(patron, p) == byte(texto, t)) {
            t = t + 1;
            p = p + 1;
        } else if p < largo(patron) && byte(patron, p) == 42 {
            estrella = p;
            marca = t;
            p = p + 1;
        } else if estrella < largo(patron) {
            // La `*` se come un caracter mas y se vuelve a probar.
            p = estrella + 1;
            marca = marca + 1;
            t = marca;
        } else {
            return false;
        }
    }
    // Lo que quede del patron solo puede ser `*`.
    while p < largo(patron) && byte(patron, p) == 42 { p = p + 1; }
    return p == largo(patron);
}

// Las que coinciden, en orden y copiadas.
fn coincidentes(xs: &list<str>, patron: view) -> list<str> {
    var salida: list<str> = [];
    var i = 0;
    while i < largo(xs) {
        if coincide(xs[i], patron) { anadir(salida, nuevo(xs[i])); }
        i = i + 1;
    }
    return salida;
}
