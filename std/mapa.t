// std/mapa.t — lo que se le pide a un mapa y no viene de serie.
//
// `poner`, `obtener`, `tiene`, `quitar`, `claves` y `largo` las pone el
// compilador. Aqui esta el resto.

usar "std/lista";

fn esta_vacio<V>(m: &mapa<str, V>) -> bool {
    return largo(m) == 0;
}

// Lo que hay, o lo que digas si no hay. Es `obtener(...) sino x`, pero con
// nombre: en una expresion larga se lee mejor.
fn obtener_o<V>(m: &mapa<str, V>, clave: view, alterno: V) -> V {
    return copiar(obtener(m, clave) sino alterno);
}

// Suma `cuanto` a lo que haya, o lo empieza en `cuanto`. Es el gesto mas
// comun sobre un mapa de cuentas, y a mano son cuatro lineas.
fn acumular(m: mut mapa<str, usize>, clave: view, cuanto: usize) {
    let previo = obtener(m, clave) sino 0;
    poner(m, clave, previo + cuanto);
}

// Las claves en orden. `claves` las da en el orden de la tabla, que depende
// de como se llenó; esto es lo que se quiere para imprimir o comparar.
fn claves_ordenadas<V>(m: &mapa<str, V>) -> lista<str> {
    var ks = claves(m);
    ordenar(ks);
    return ks;
}

// Mete en `destino` todo lo de `otro`. Lo que ya estaba se queda.
fn completar<V>(destino: mut mapa<str, V>, otro: &mapa<str, V>) {
    for k en claves(otro) {
        if !tiene(destino, vista(k)) {
            let v = obtener(otro, vista(k)) sino copiar(destino[k]);
            poner(destino, vista(k), copiar(v));
        }
    }
}

// Cuantas claves cumplen.
fn cuantas_claves<V, F>(m: &mapa<str, V>, cumple: F) -> usize {
    var n = 0;
    for k en claves(m) {
        if cumple(k) { n = n + 1; }
    }
    return n;
}
