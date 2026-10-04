// banderas.t — lo que hace falta una bandera de propiedad.
//
// Una variable con duenio se entrega por un camino y por el otro no. C no
// sabe por cual se vino, asi que Tcode le pone un `bool` y lo apaga solo.

use "std/texto";
use "std/lista";

fn guardar(xs: mut list<str>, s: str) {
    anadir(xs, s);
}

fn quiza(c: bool) -> usize {
    var xs: list<str> = [];
    let s = nuevo("hola");
    if c {
        guardar(xs, s);
    }
    return largo(xs);
}

fn main() {
    imprimir($"{quiza(true)} {quiza(false)}\n");
}
