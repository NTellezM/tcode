// std/mapa.t — lo que se le pide a un mapa y no viene de serie.
//
// `poner`, `obtener`, `tiene`, `quitar`, `claves` y `largo` las pone el
// compilador. Aqui esta el resto.

use "std/lista";

fn esta_vacio<V>(m: &map<str, V>) -> bool {
    return largo(m) == 0;
}

// Lo que hay, o lo que digas si no hay. Es `obtener(...) sino x`, pero con
// nombre: en una expresion larga se lee mejor.
fn obtener_o<V>(m: &map<str, V>, clave: view, alterno: V) -> V {
    return copiar(obtener(m, clave) sino alterno);
}

// Suma `cuanto` a lo que haya, o lo empieza en `cuanto`. Es el gesto mas
// comun sobre un mapa de cuentas, y a mano son cuatro lineas.
fn acumular(m: mut map<str, usize>, clave: view, cuanto: usize) {
    let previo = obtener(m, clave) sino 0;
    poner(m, clave, previo + cuanto);
}

// Las claves en orden. `claves` las da en el orden de la tabla, que depende
// de como se llenó; esto es lo que se quiere para imprimir o comparar.
fn claves_ordenadas<V>(m: &map<str, V>) -> list<str> {
    var ks = claves(m);
    ordenar(ks);
    return ks;
}

// Los valores en orden de clave, para que el resultado no dependa del orden
// interno de la tabla. Se copian porque la lista resultante es su duenio.
fn valores_ordenados<V>(m: &map<str, V>) -> list<V> ! {
    var salida: list<V> = [];
    for k en claves_ordenadas(m) {
        let v = try obtener(m, vista(k));
        anadir(salida, copiar(v));
    }
    return salida;
}

// Mete todo lo de `otro`, reemplazando las claves que ya estaban.
fn actualizar<V>(destino: mut map<str, V>, otro: &map<str, V>) ! {
    for k en claves(otro) {
        let v = try obtener(otro, vista(k));
        poner(destino, vista(k), copiar(v));
    }
}

// Mete en `destino` todo lo de `otro`. Lo que ya estaba se queda.
fn completar<V>(destino: mut map<str, V>, otro: &map<str, V>) ! {
    for k en claves(otro) {
        if !tiene(destino, vista(k)) {
            let v = try obtener(otro, vista(k));
            poner(destino, vista(k), copiar(v));
        }
    }
}

// Cuantas claves cumplen.
fn cuantas_claves<V, F>(m: &map<str, V>, cumple: F) -> usize {
    var n = 0;
    for k en claves(m) {
        if cumple(k) { n = n + 1; }
    }
    return n;
}
