// frecuencia.t — cuenta cuantas veces aparece cada palabra de un archivo.
//
// Es lo que `contar.t` no podia hacer: contar palabras es facil, decir
// CUALES hace falta un mapa.
//
//     ./frecuencia README.md 10

fn es_separador(b: usize) -> bool {
    // Todo lo que no sea letra, digito o guion corta la palabra. Sirve para
    // texto en ASCII; los bytes altos de UTF-8 se dejan pasar, asi que las
    // palabras acentuadas se cuentan enteras.
    if b >= 128 { return false; }
    if b >= 97 && b <= 122 { return false; }
    if b >= 65 && b <= 90 { return false; }
    if b >= 48 && b <= 57 { return false; }
    return b != 45;
}

fn minuscula(b: usize) -> usize {
    if b >= 65 && b <= 90 { return b + 32; }
    return b;
}

fn a_entero(v: view) -> usize {
    var n = 0;
    var i = 0;
    while i < largo(v) {
        let b = byte(v, i);
        if b < 48 || b > 57 { return n; }
        n = n * 10 + (b - 48);
        i = i + 1;
    }
    return n;
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir("uso: ");
        imprimir(argumento(0));
        imprimir(" <archivo> [cuantas]\n");
        return 1;
    }

    var cuantas = 10;
    if n_argumentos() > 2 { cuantas = a_entero(argumento(2)); }
    if cuantas == 0 { cuantas = 10; }

    let contenido = try leer_archivo(argumento(1));
    let texto_completo = vista(contenido);

    var cuenta: mapa<str, usize> = [];
    var palabra = vacio();
    var i = 0;
    var total = 0;

    while i <= largo(texto_completo) {
        // Al pasarse por uno se cierra la ultima palabra sin repetir codigo.
        var corta = true;
        if i < largo(texto_completo) {
            corta = es_separador(byte(texto_completo, i));
        }

        if corta {
            if largo(palabra) > 0 {
                let previo = obtener(cuenta, palabra) sino 0;
                poner(cuenta, palabra, previo + 1);
                total = total + 1;
                palabra = vacio();
            }
        } else {
            // Se acumula el byte crudo: `texto` de un byte daria su valor
            // decimal, no el caracter.
            empujar(palabra, rebanar(texto_completo, i, i + 1));
        }
        i = i + 1;
    }

    imprimir(total); imprimir(" palabras, ");
    imprimir(largo(cuenta)); imprimir(" distintas\n\n");

    // Seleccion de las `cuantas` mayores recorriendo el mapa directamente.
    // Antes hacia falta `claves(cuenta)`, que copia el vocabulario entero;
    // ahora cada vuelta presta las claves que ya estan en la tabla y solo se
    // copia la ganadora de cada linea.
    var mostradas = 0;
    var tope = largo(texto_completo) + 1;

    while mostradas < cuantas {
        var mejor = 0;
        var ganadora = vacio();

        for palabra_actual, veces en cuenta {
            if veces > mejor && veces < tope {
                mejor = veces;
                ganadora = nuevo(palabra_actual);
            }
        }
        if mejor == 0 { return 0; }

        imprimir(mejor);
        imprimir("  ");
        imprimir(ganadora);
        imprimir("\n");
        tope = mejor;
        mostradas = mostradas + 1;
    }
}
