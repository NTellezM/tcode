// Bucle entero puro: mide el coste de la aritmetica comprobada.
fn main() -> usize {
    var acc: usize = 0;
    var i: usize = 0;
    while i < 200000000 {
        acc = acc + i % 7;
        i = i + 1;
    }
    imprimir(acc);
    imprimir("\n");
    return 0;
}
