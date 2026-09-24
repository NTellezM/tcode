// bloques.t — memoria de una pieza, y un vector escrito en Tcode encima.
//
// `bloque<T>` nace a ceros y conoce su tamaño: indexarlo comprueba el
// limite. `std/vector` crece sobre el sin que el compilador sepa nada de
// vectores, que es lo que en C pide `realloc` a mano y en Rust `unsafe`.

usar "std/vector";

fn main() -> usize ! {
    var b: bloque<usize> = reservar(4);
    b[2] = 7;
    redimensionar(b, 6);
    imprimir($"{largo(b)} {b[2]} {b[5]}\n");

    var v: Vector<str> = Vector { datos: reservar(0), largo: 0 };
    agregar(v, nuevo("x"));
    agregar(v, nuevo("y"));
    imprimir($"{cuantos(v)} de {capacidad(v)}\n");
    let ultimo = try sacar(v, vacio());
    let primero = try copia_de(v, 0);
    ajustar(v);
    imprimir($"{ultimo} {primero} {capacidad(v)}\n");
    return 0;
}
