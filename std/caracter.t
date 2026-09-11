// std/caracter.t — clasificacion de bytes ASCII.
//
// Se trabaja con bytes, no con caracteres: los de UTF-8 por encima de 127 se
// tratan como parte de una palabra, que es lo que quiere casi todo el mundo
// al partir texto en español.

fn es_blanco(b: usize) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13;
}

fn es_digito(b: usize) -> bool {
    return b >= 48 && b <= 57;
}

fn es_minuscula(b: usize) -> bool {
    return b >= 97 && b <= 122;
}

fn es_mayuscula(b: usize) -> bool {
    return b >= 65 && b <= 90;
}

fn es_letra(b: usize) -> bool {
    return es_minuscula(b) || es_mayuscula(b) || b == 95 || b >= 128;
}

fn es_alfanumerico(b: usize) -> bool {
    return es_letra(b) || es_digito(b);
}
