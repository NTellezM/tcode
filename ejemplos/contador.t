usar "std/texto";
usar "std/caracter";

// Palabras: las separadas por blancos, sin contar el de delante ni el de detras.
fn contador_palabras(texto: view) -> usize {
    var suma = 0;
    var dentro = false;
    for i en 0..largo(texto) {
        if !es_blanco(byte(texto, i)) {
            dentro = true;
        } else if dentro {
            suma = suma + 1;
            dentro = false;
        }
    }
    if dentro { suma = suma + 1; }
    return suma;
}

// Letras: las que lo son de verdad.
fn contador_letras(texto: view) -> usize {
    var suma = 0;
    for i en 0..largo(texto) {
        if es_letra(byte(texto, i)) { suma = suma + 1; }
    }
    return suma;
}

// Simbolos de fin de frase: los que estan en `simbolos`.
fn contador_simbolos(texto: view, simbolos: view) -> usize {
    var suma = 0;
    for i en 0..largo(texto) {
        for j en 0..largo(simbolos) {
            if byte(texto, i) == byte(simbolos, j) {
                suma = suma + 1;
                break;
            }
        }
    }
    return suma;
}

// El indice de Coleman-Liau.
fn formula(palabras: usize, letras: usize, simbolos: usize) -> f64 {
    let l = ((letras como f64) / (palabras como f64)) * 100.0;
    let s = ((simbolos como f64) / (palabras como f64)) * 100.0;
    return 0.0588 * l - 0.296 * s - 15.8;
}

fn grado(total: i64) {
    if total < 1 {
        imprimir("Before Grade 1\n");
    } else if total >= 16 {
        imprimir("Grade 16+\n");
    } else {
        imprimir($"Grade {total}\n");
    }
}

fn main() ! {
    imprimir("Text: ");
    let texto = try leer_linea();
    let palabras = contador_palabras(texto);
    let letras = contador_letras(texto);
    let simbolos = contador_simbolos(texto, ".?!");
    let total = formula(palabras, letras, simbolos);
    grado(redondear(total) como i64);
}
