// Construccion de cadenas: aqui el trabajo es del runtime, no del lenguaje.
fn construir(n: usize) -> str {
    var s: str = vacio();
    var i: usize = 0;
    while i < n {
        empujar(s, "abcdefghij");
        i = i + 1;
    }
    return s;
}

fn main() -> usize {
    var total: usize = 0;
    var r: usize = 0;
    while r < 300 {
        let s: str = construir(20000);
        total = total + largo(vista(s));
        r = r + 1;
    }
    imprimir(total);
    imprimir("\n");
    return 0;
}
