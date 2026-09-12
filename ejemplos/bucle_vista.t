// bucle_vista.t — la condicion de un bucle se vuelve a mirar cada vuelta.
//
// `byte(vista(s), 0)` no cabe en una expresion de C: hay que guardar la
// vista en un temporal y luego indexarla. Si ese temporal se calculara una
// sola vez, antes del bucle, la segunda vuelta miraria una vista de la `s`
// vieja —la que el cuerpo ya solto— y eso es leer memoria devuelta.
//
// Es justo la clase de fallo por la que existe el lenguaje, asi que la
// condicion se emite DENTRO del bucle y se recalcula en cada vuelta.

usar "std/texto";

fn cuantas() -> usize {
    var s = nuevo("aaa");
    var n = 0;
    while byte(vista(s), 0) == 97 {
        s = nuevo("zzz");
        n = n + 1;
    }
    return n;
}

fn main() {
    // Una sola vuelta: al empezar la segunda, `s` ya es "zzz".
    imprimir($"{cuantas()}\n");
}
