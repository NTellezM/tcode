// lib/lexico.t — el analisis lexico de Tcode, escrito en Tcode.
//
// Lo usan `lexer.t`, que imprime los tokens, y `parser.t`, que los analiza.

usar "std/caracter";

struct Token {
    tipo: str, // palabra, ident, entero, cadena, interpolada, simbolo
    valor: str,
    linea: usize,
}

// ------------------------------------------------------------------
// `es_digito`, `es_letra` y `es_alfanumerico` vienen de `std/caracter`, que
// ya trabaja sobre bytes y deja pasar los de UTF-8 por encima de 127 dentro
// de identificadores, que es lo que hace el compilador de verdad. Aqui solo
// queda lo que difiere: un salto de linea no es espacio para el lexer,
// porque hay que contarlo.
// ------------------------------------------------------------------

fn es_espacio(b: usize) -> bool {
    return b == 32 || b == 9 || b == 13;
}

fn palabras_reservadas() -> mapa<str, usize> {
    var m: mapa<str, usize> = [];
    poner(m, "fn", 1); poner(m, "let", 1); poner(m, "var", 1);
    poner(m, "mut", 1); poner(m, "if", 1); poner(m, "else", 1);
    poner(m, "while", 1); poner(m, "for", 1); poner(m, "en", 1);
    poner(m, "break", 1); poner(m, "continue", 1); poner(m, "return", 1);
    poner(m, "struct", 1); poner(m, "usar", 1); poner(m, "try", 1);
    poner(m, "sino", 1); poner(m, "falla", 1); poner(m, "lista", 1);
    poner(m, "mapa", 1); poner(m, "str", 1); poner(m, "view", 1);
    poner(m, "bool", 1);
    poner(m, "enum", 1); poner(m, "match", 1);
    poner(m, "true", 1); poner(m, "false", 1);
    poner(m, "u8", 1); poner(m, "u16", 1); poner(m, "u32", 1);
    poner(m, "u64", 1); poner(m, "usize", 1);
    poner(m, "i8", 1); poner(m, "i16", 1); poner(m, "i32", 1);
    poner(m, "i64", 1);
    poner(m, "f32", 1); poner(m, "f64", 1);
    return m;
}

// Los simbolos de dos caracteres se prueban antes que los de uno, igual que
// en el compilador: si no, `+?` se leeria como `+` seguido de `?`.
fn simbolo_doble(a: usize, b: usize) -> bool {
    if a == 43 && b == 63 { return true; }   // +?
    if a == 45 && b == 63 { return true; }   // -?
    if a == 42 && b == 63 { return true; }   // *?
    if a == 47 && b == 63 { return true; }   // /?
    if a == 45 && b == 62 { return true; }   // ->
    if a == 61 && b == 61 { return true; }   // ==
    if a == 33 && b == 61 { return true; }   // !=
    if a == 60 && b == 61 { return true; }   // <=
    if a == 62 && b == 61 { return true; }   // >=
    if a == 38 && b == 38 { return true; }   // &&
    if a == 124 && b == 124 { return true; } // ||
    if a == 60 && b == 60 { return true; }   // <<
    if a == 62 && b == 62 { return true; }   // >>
    return false;
}

fn es_simbolo(b: usize) -> bool {
    if b == 40 || b == 41 || b == 123 || b == 125 { return true; } // ( ) { }
    if b == 91 || b == 93 || b == 60 || b == 62 { return true; }   // [ ] < >
    if b == 44 || b == 59 || b == 58 || b == 46 { return true; }   // , ; : .
    if b == 61 || b == 43 || b == 45 || b == 42 { return true; }   // = + - *
    if b == 47 || b == 37 || b == 33 || b == 38 { return true; }   // / % ! &
    if b == 124 || b == 36 { return true; }                        // | $
    if b == 94 || b == 126 || b == 63 { return true; }             // ^ ~ ?
    return false;
}

// ------------------------------------------------------------------
// El analisis. Se recorre el texto una vez, sin retroceder.
// ------------------------------------------------------------------

fn agregar(salida: mut lista<Token>, tipo: view, valor: view, linea: usize) {
    anadir(salida, Token {
            tipo: nuevo(tipo),
            valor: nuevo(valor),
            linea: linea,
        });
}

// Lee una cadena entre comillas y devuelve donde termina. El contenido se
// deja crudo, con los escapes sin resolver: al lexer le basta con saber
// donde acaba.
// Dentro de `{...}` de una cadena interpolada va una expresion, y una
// expresion puede llevar cadenas: `$"{unir(xs, ", ")}"`. Se lleva la cuenta
// de llaves para no cortar en la comilla equivocada.
fn fin_de_cadena(fuente: view, desde: usize, interpolada: bool) -> usize ! {
    var i = desde;
    var hondura = 0;
    while i < largo(fuente) {
        let b = byte(fuente, i);
        if b == 10 {
            falla "cadena sin cerrar antes del salto de linea";
        }
        if b == 92 {
            i = i + 2; // escape: se salta el par entero
            continue;
        }
        if interpolada {
            // `{{` y `}}` son una llave escrita, pero solo fuera de un
            // hueco: dentro, `}}` puede cerrar un bloque y el hueco.
            if hondura == 0 && i + 1 < largo(fuente) {
                let sig = byte(fuente, i + 1);
                if (b == 123 && sig == 123) || (b == 125 && sig == 125) {
                    i = i + 2;
                    continue;
                }
            }
            if b == 123 { hondura = hondura + 1; }
            if b == 125 && hondura > 0 { hondura = hondura - 1; }
        }
        if b == 34 && hondura == 0 {
            return i;
        }
        i = i + 1;
    }
    falla "cadena sin cerrar al final del archivo";
}

fn analizar(fuente: view) -> lista<Token> ! {
    let reservadas = palabras_reservadas();
    var salida: lista<Token> = [];
    var i = 0;
    var linea = 1;

    while i < largo(fuente) {
        let b = byte(fuente, i);

        if b == 10 {
            linea = linea + 1;
            i = i + 1;
            continue;
        }
        if es_espacio(b) {
            i = i + 1;
            continue;
        }

        // comentarios
        if b == 47 && i + 1 < largo(fuente) {
            let sig = byte(fuente, i + 1);
            if sig == 47 {
                while i < largo(fuente) && byte(fuente, i) != 10 {
                    i = i + 1;
                }
                continue;
            }
            if sig == 42 {
                var cerrado = false;
                i = i + 2;
                while i + 1 < largo(fuente) {
                    if byte(fuente, i) == 10 { linea = linea + 1; }
                    if byte(fuente, i) == 42 && byte(fuente, i + 1) == 47 {
                        i = i + 2;
                        cerrado = true;
                        break;
                    }
                    i = i + 1;
                }
                if !cerrado { falla "comentario /* sin cerrar"; }
                continue;
            }
        }

        // cadena interpolada
        if b == 36 && i + 1 < largo(fuente) && byte(fuente, i + 1) == 34 {
            let fin = try fin_de_cadena(fuente, i + 2, true);
            agregar(salida, "interpolada", rebanar(fuente, i + 2, fin), linea);
            i = fin + 1;
            continue;
        }

        // cadena
        if b == 34 {
            let fin = try fin_de_cadena(fuente, i + 1, false);
            agregar(salida, "cadena", rebanar(fuente, i + 1, fin), linea);
            i = fin + 1;
            continue;
        }

        // numero
        if es_digito(b) {
            var j = i;
            while j < largo(fuente) && (es_digito(byte(fuente, j))
                || byte(fuente, j) == 95) {
                j = j + 1;
            }
            // Decimal: el punto lleva un digito a cada lado, y luego puede
            // venir un exponente.
            var decimal = false;
            if j + 1 < largo(fuente) && byte(fuente, j) == 46 {
                if es_digito(byte(fuente, j + 1)) {
                    decimal = true;
                    j = j + 1;
                    while j < largo(fuente) && (es_digito(byte(fuente, j))
                        || byte(fuente, j) == 95) {
                        j = j + 1;
                    }
                }
            }
            if j < largo(fuente) {
                if byte(fuente, j) == 101 || byte(fuente, j) == 69 {
                    var k = j + 1;
                    if k < largo(fuente) {
                        if byte(fuente, k) == 43 || byte(fuente, k) == 45 {
                            k = k + 1;
                        }
                    }
                    if k < largo(fuente) {
                        if es_digito(byte(fuente, k)) {
                            decimal = true;
                            j = k;
                            while j < largo(fuente) && es_digito(byte(fuente, j)) {
                                j = j + 1;
                            }
                        }
                    }
                }
            }
            var clase = nuevo("entero");
            if decimal { clase = nuevo("decimal"); }
            agregar(salida, vista(clase), rebanar(fuente, i, j), linea);
            i = j;
            continue;
        }

        // identificador o palabra reservada
        if es_letra(b) {
            var j = i;
            while j < largo(fuente) && es_alfanumerico(byte(fuente, j)) {
                j = j + 1;
            }
            let texto_pieza = rebanar(fuente, i, j);
            if tiene(reservadas, texto_pieza) {
                agregar(salida, "palabra", texto_pieza, linea);
            } else {
                agregar(salida, "ident", texto_pieza, linea);
            }
            i = j;
            continue;
        }

        // simbolo, de dos en dos primero
        if i + 1 < largo(fuente) && simbolo_doble(b, byte(fuente, i + 1)) {
            agregar(salida, "simbolo", rebanar(fuente, i, i + 2), linea);
            i = i + 2;
            continue;
        }
        if es_simbolo(b) {
            agregar(salida, "simbolo", rebanar(fuente, i, i + 1), linea);
            i = i + 1;
            continue;
        }

        falla "caracter inesperado";
    }

    agregar(salida, "fin", "", linea);
    return salida;
}
