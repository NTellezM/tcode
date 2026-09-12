// banderas.t — lo que hace falta una bandera de propiedad.
//
// Una variable con duenio se entrega por un camino y por el otro no. C no
// sabe por cual se vino, asi que Tcode le pone un `bool` y lo apaga solo.

usar "std/texto";
usar "std/lista";

fn guardar(xs: mut lista<str>, s: str) {
    anadir(xs, s);
}

fn quiza(c: bool) -> usize {
    var xs: lista<str> = [];
    let s = nuevo("hola");
    if c {
        guardar(xs, s);
    }
    return largo(xs);
}

fn main() {
    imprimir($"{quiza(true)} {quiza(false)}\n");
}
