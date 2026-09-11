// contar.t — una utilidad que consume entrada externa de verdad.
//
// Recorre todos los bytes del archivo que se le pase y calcula una version
// pequena de `wc`: lineas, palabras y bytes. La lista dinamica guarda la
// posicion de cada salto de linea; no hace falta conocer su cantidad de
// antemano.
//
//     ./contar README.md

fn es_espacio(b: usize) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13;
}

fn poner_numero(s: mut str, n: usize) {
    let t = texto(n);
    empujar(s, t);
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir("uso: ");
        imprimir(argumento(0));
        imprimir(" <archivo>\n");
        return 1;
    }

    let ruta = argumento(1);
    let contenido = try leer_archivo(ruta);
    var saltos: lista<usize> = [];
    var palabras = 0;
    var dentro = false;
    var i = 0;

    while i < largo(contenido) {
        let b = byte(contenido, i);
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
    var lineas = largo(saltos);
    if i > 0 && byte(contenido, i - 1) != 10 {
        lineas = lineas + 1;
    }

    var informe = nuevo(ruta);
    empujar(informe, ": ");
    poner_numero(informe, lineas);
    empujar(informe, " lineas, ");
    poner_numero(informe, palabras);
    empujar(informe, " palabras, ");
    poner_numero(informe, i);
    empujar(informe, " bytes\n");
    imprimir(informe);
}
