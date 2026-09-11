// El primer programa que compila el lenguaje Tcode.
//
// Hay propiedad, un prestamo y una liberacion automatica aqui dentro, y no
// se menciona ninguna: el compilador las comprueba, tu no las escribes.

fn saludo(nombre: view) -> str {
    var s = nuevo("Hola, ");
    empujar(s, nombre);
    empujar(s, "!");
    return s;
}

fn main() {
    let quien = saludo("mundo");
    imprimir(quien);
    imprimir("\n");

    imprimir(largo(quien));
    imprimir(" bytes\n");
}
