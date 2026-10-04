// std/azar.t — aleatoriedad sobre `azar` y `sembrar`.
//
//     let n = azar.entero_entre(1, 6);    // un dado
//     let i = azar.indice_al_azar(xs);    // un indice valido de la lista
//     azar.barajar(xs);                    // Fisher-Yates, en su sitio

// Un entero en [desde, hasta], ambos incluidos.
fn entero_entre(desde: usize, hasta: usize) -> usize ! {
    if hasta < desde { fail "el rango esta vacio"; }
    return desde + azar(hasta - desde + 1);
}

// Un indice valido de la lista: de 0 a `largo(xs) - 1`.
fn indice_al_azar<T>(xs: &list<T>) -> usize ! {
    if largo(xs) == 0 { fail "la lista esta vacia"; }
    return azar(largo(xs));
}

// Baraja la lista en su sitio, con Fisher-Yates: cada permutacion sale con la
// misma probabilidad.
fn barajar<T>(xs: mut list<T>) {
    var i = largo(xs);
    while i > 1 {
        let j = azar(i);
        i = i - 1;
        if j != i {
            let guardado = intercambiar(xs[j], copiar(xs[i]));
            let _viejo = intercambiar(xs[i], guardado);
        }
    }
}
