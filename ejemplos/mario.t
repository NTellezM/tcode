usar "std/texto";

fn fila(spaces: usize, bricks: usize) {
    for _i en 0..spaces { imprimir(" "); }
    for _i en 0..bricks { imprimir("#"); }
}

fn main() ! {
    var n: usize = 0;
    while n < 1 {
        imprimir("Height: ");
        let linea = try leer_linea();
        n = a_entero(recortar(linea)) sino 0;
    }
    for i en 0..n {
        fila(n - i - 1, i + 1);
        fila(2, i + 1);
        imprimir("\n");
    }
}
