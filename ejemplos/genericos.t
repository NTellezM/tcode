// genericos.t — structs genericos: una copia por juego de tipos.
//
// `Caja<usize>` y `Caja<str>` son dos structs distintos en el C generado,
// cada uno con su tamaño y su liberador, como las plantillas de C++ o los
// genericos de Rust. No hay `void*` ni tamaños pasados a mano como en C.

usar "std/par";

struct Caja<T> { dentro: T, cuantas: usize }

fn contar(c: &Caja < str >) -> usize { return c.cuantas + largo(c.dentro); }

fn meter(xs: mut lista<Caja<usize>>, n: usize) {
    anadir(xs, Caja { dentro: n, cuantas: 1 });
}

fn main() {
    let dos = par(nuevo("clave"), 9);
    imprimir($"{dos.primero} {dos.segundo}\n");
    let v = volteado(dos);
    imprimir($"{v.primero} {v.segundo}\n");
    let c: Caja<str> = Caja { dentro: nuevo("hola"), cuantas: 2 };
    imprimir($"{contar(c)}\n");

    var xs: lista<Caja<usize>> = [];
    meter(xs, 3);
    meter(xs, 4);
    // Una generica deduce sus tipos de los argumentos: lo que no dice su
    // tipo por si mismo va antes a una variable con el tipo escrito.
    let copia: lista<Caja<usize>> = copiar(xs);
    let otra: Caja<str> = Caja { dentro: nuevo("dentro"), cuantas: 0 };
    let hondo = par(copia, otra);
    imprimir($"{largo(hondo.primero)} {hondo.segundo.dentro} {xs[1].dentro}\n");
}
