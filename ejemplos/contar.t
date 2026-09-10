// contar.t — una utilidad que consume entrada externa de verdad.
//
// Lee README.md, recorre todos sus bytes y calcula una version pequena de
// `wc`: lineas, palabras y bytes. La lista dinamica guarda la posicion de
// cada salto de linea; no hace falta conocer su cantidad de antemano.

fn es_espacio(b: usize) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13;
}

fn poner_numero(s: mut str, n: usize) {
    let t: str = texto(n);
    empujar(s, vista(t));
}

fn main() -> usize ! {
    let contenido: str = try leer_archivo("README.md");
    var saltos: lista<usize> = [];
    var palabras: usize = 0;
    var dentro: bool = false;
    var i: usize = 0;

    while i < largo(vista(contenido)) {
        let b: usize = byte(vista(contenido), i);
        if b == 10 {
            anadir(saltos, i);
        }
        if es_espacio(b) {
            dentro = false;
        } else {
            if !dentro {
                palabras = palabras + 1;
                dentro = true;
            }
        }
        i = i + 1;
    }

    // Un archivo no vacio cuya ultima linea no acaba en \n tiene una linea
    // adicional, igual que las herramientas habituales de conteo de texto.
    var lineas: usize = largo(saltos);
    if i > 0 && byte(vista(contenido), i - 1) != 10 {
        lineas = lineas + 1;
    }

    var informe: str = nuevo("README.md: ");
    poner_numero(informe, lineas);
    empujar(informe, " lineas, ");
    poner_numero(informe, palabras);
    empujar(informe, " palabras, ");
    poner_numero(informe, i);
    empujar(informe, " bytes\n");
    imprimir(informe);
    return 0;
}
