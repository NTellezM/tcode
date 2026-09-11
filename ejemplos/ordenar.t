// ordenar.t — las palabras mas frecuentes de un archivo, ordenadas de verdad.
//
// `frecuencia.t` elegia las mayores recorriendo el vocabulario una vez por
// cada una. Con `ordenar` se ordena una sola vez.
//
//     ./ordenar README.md

fn es_separador(b: usize) -> bool {
    if b >= 128 { return false; }
    if b >= 97 && b <= 122 { return false; }
    if b >= 65 && b <= 90 { return false; }
    return !(b >= 48 && b <= 57);
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error("uso: ");
        imprimir_error(argumento(0));
        imprimir_error(" <archivo>\n");
        return 1;
    }

    let contenido = try leer_archivo(argumento(1));
    let texto_completo = vista(contenido);

    var vistas: mapa<str, usize> = [];
    var palabra = vacio();
    var i = 0;

    while i <= largo(texto_completo) {
        var corta = true;
        if i < largo(texto_completo) {
            corta = es_separador(byte(texto_completo, i));
        }
        if corta {
            if largo(palabra) > 0 {
                poner(vistas, palabra, 1);
                palabra = vacio();
            }
        } else {
            empujar(palabra, rebanar(texto_completo, i, i + 1));
        }
        i = i + 1;
    }

    // Ordenadas alfabeticamente, que es lo que `ordenar` da sobre `lista<str>`.
    var vocabulario = claves(vistas);
    ordenar(vocabulario);

    imprimir(largo(vocabulario));
    imprimir(" palabras distintas, las 8 primeras en orden:\n");

    var mostradas = 0;
    for palabra_ordenada en vocabulario {
        if mostradas == 8 { break; }
        imprimir("  ");
        imprimir(palabra_ordenada);
        imprimir("\n");
        mostradas = mostradas + 1;
    }
}
