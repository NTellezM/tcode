// contar.t — una version pequena de `wc`: lineas, palabras y bytes.
//
// Consume entrada externa de verdad, y recorre el archivo una sola vez: la
// lista dinamica guarda la posicion de cada salto de linea sin conocer su
// cantidad de antemano.
//
//     ./contar README.md

usar "std/texto";
usar "std/caracter";

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir($"uso: {argumento(0)} <archivo>\n");
        return 1;
    }

    let ruta = argumento(1);
    let contenido = try leer_archivo(ruta);
    var saltos: lista<usize> = [];
    var cuantas_palabras = 0;
    var dentro = false;
    var i = 0;

    while i < largo(contenido) {
        let b = byte(contenido, i);
        if b == 10 {
            anadir(saltos, i);
        }
        if es_blanco(b) {
            dentro = false;
        } else {
            if !dentro {
                cuantas_palabras = cuantas_palabras + 1;
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

    imprimir($"{ruta}: {lineas} lineas, {cuantas_palabras} palabras, {i} bytes\n");
}
