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
    poner(m, "externo", 1);
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
// donde acaba, y comprobar que cada escape existe. Dentro de `{...}` de una
// cadena interpolada va una expresion, y una expresion puede llevar cadenas:
// `$"{unir(xs, ", ")}"`. Se lleva la cuenta de llaves para no cortar en la
// comilla equivocada. Si falla, deja el mensaje en `error`, como el lexer de
// Python.
fn fin_de_cadena(fuente: view, desde: usize, interpolada: bool, prefijo: view,
    error: mut str) -> usize ! {
    var i = desde;
    var hondura = 0;
    while true {
        if i >= largo(fuente) || byte(fuente, i) == 10 {
            if interpolada {
                error = $"{prefijo}cadena interpolada sin cerrar; falta la comilla, o falta `}}` en algun hueco";
            } else {
                error = $"{prefijo}cadena sin cerrar";
            }
            falla "cadena sin cerrar";
        }
        let b = byte(fuente, i);
        // `{{` y `}}` son una llave escrita, pero solo fuera de un hueco:
        // dentro, `}}` puede cerrar un bloque y el hueco.
        if interpolada && hondura == 0 && i + 1 < largo(fuente) {
            let sig = byte(fuente, i + 1);
            if (b == 123 && sig == 123) || (b == 125 && sig == 125) {
                i = i + 2;
                continue;
            }
        }
        if interpolada {
            if b == 123 { hondura = hondura + 1; }
            if b == 125 && hondura > 0 { hondura = hondura - 1; }
        }
        if b == 34 && hondura == 0 { return i; }
        if b == 92 {
            if i + 1 >= largo(fuente) {
                error = $"{prefijo}escape sin cerrar";
                falla "escape sin cerrar";
            }
            let esc = byte(fuente, i + 1);
            if esc == 120 {
                // `\xNN`: dos digitos hexadecimales, ni uno mas ni uno menos.
                var bien = i + 3 < largo(fuente);
                if bien { bien = es_hex(byte(fuente, i + 2)) && es_hex(byte(fuente, i + 3)); }
                if !bien {
                    error = $"{prefijo}`\\x` lleva dos digitos hexadecimales detras, como `\\x0a`";
                    falla "escape mal formado";
                }
                i = i + 4;
                continue;
            }
            let conocido = esc == 110 || esc == 116 || esc == 92 || esc == 34 || esc == 48
            || (interpolada && (esc == 123 || esc == 125));
            if !conocido {
                error = $"{prefijo}escape desconocido \\{rebanar(fuente, i + 1, i + 2)}";
                falla "escape desconocido";
            }
            i = i + 2;
            continue;
        }
        i = i + 1;
    }
    return i;
}

fn es_hex(b: usize) -> bool {
    return (b >= 48 && b <= 57) || (b >= 97 && b <= 102) || (b >= 65 && b <= 70);
}

// `'a'`, como lo escribe Python: comilla simple, y la barra y los de control
// escapados.
fn repr_caracter(c: view) -> str {
    if igual(c, "'") { return nuevo("\"'\""); }
    if igual(c, "\\") { return nuevo("'\\\\'"); }
    if largo(c) == 1 {
        let b = byte(c, 0);
        if b == 10 { return nuevo("'\\n'"); }
        if b == 9 { return nuevo("'\\t'"); }
        if b == 13 { return nuevo("'\\r'"); }
        if b < 32 || b == 127 {
            let alto = rebanar("0123456789abcdef", b / 16, b / 16 + 1);
            let bajo = rebanar("0123456789abcdef", b % 16, b % 16 + 1);
            return $"'\\x{alto}{bajo}'";
        }
    }
    return $"'{c}'";
}

fn analizar(fuente: view) -> lista<Token> ! {
    var error = vacio();
    return try tokens_de(fuente, "<entrada>", error);
}

// Los tokens de un archivo. Si no se puede, `error` dice por que y donde,
// con las mismas palabras que el lexer de Python.
fn tokens_de(fuente: view, archivo: view, error: mut str) -> lista<Token> ! {
    return try tokens_de_todo(fuente, archivo, false, error);
}

// Con `comentarios`, tambien los comentarios, como tokens `comentario`: el
// formateador los necesita para dejarlos donde estaban.
fn tokens_de_todo(fuente: view, archivo: view, comentarios: bool,
    error: mut str) -> lista<Token> ! {
    let reservadas = palabras_reservadas();
    var salida: lista<Token> = [];
    var i = 0;
    var linea = 1;

    while i < largo(fuente) {
        let b = byte(fuente, i);
        let prefijo = $"{archivo}:{linea}: ";

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
                let desde = i;
                while i < largo(fuente) && byte(fuente, i) != 10 {
                    i = i + 1;
                }
                if comentarios {
                    agregar(salida, "comentario", rebanar(fuente, desde, i), linea);
                }
                continue;
            }
            if sig == 42 {
                var cerrado = false;
                var j = i + 2;
                var saltos = 0;
                while j + 1 < largo(fuente) {
                    if byte(fuente, j) == 42 && byte(fuente, j + 1) == 47 {
                        cerrado = true;
                        break;
                    }
                    if byte(fuente, j) == 10 { saltos = saltos + 1; }
                    j = j + 1;
                }
                if !cerrado {
                    error = $"{prefijo}comentario /* sin cerrar";
                    falla "comentario /* sin cerrar";
                }
                if comentarios {
                    agregar(salida, "comentario", rebanar(fuente, i, j + 2), linea);
                }
                linea = linea + saltos;
                i = j + 2;
                continue;
            }
        }

        // cadena interpolada
        if b == 36 && i + 1 < largo(fuente) && byte(fuente, i + 1) == 34 {
            let fin = try fin_de_cadena(fuente, i + 2, true, vista(prefijo), error);
            agregar(salida, "interpolada", rebanar(fuente, i + 2, fin), linea);
            i = fin + 1;
            continue;
        }

        // cadena
        if b == 34 {
            let fin = try fin_de_cadena(fuente, i + 1, false, vista(prefijo), error);
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
            // `12abc` o `1.`: ni numero ni otra cosa.
            if j < largo(fuente) && (es_letra(byte(fuente, j)) && byte(fuente, j) != 95
                || byte(fuente, j) == 46) {
                let visto = repr_texto(rebanar(fuente, i, j + 1));
                error = $"{prefijo}numero mal formado cerca de {visto}";
                falla "numero mal formado";
            }
            // `1_000` es `1000`: el guion bajo solo ayuda a leerlo.
            var limpio = vacio();
            var q = i;
            while q < j {
                if byte(fuente, q) != 95 { empujar(limpio, rebanar(fuente, q, q + 1)); }
                q = q + 1;
            }
            var clase = nuevo("entero");
            if decimal { clase = nuevo("decimal"); }
            agregar(salida, vista(clase), vista(limpio), linea);
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

        let visto = repr_caracter(rebanar(fuente, i, i + 1));
        error = $"{prefijo}caracter inesperado {visto}";
        falla "caracter inesperado";
    }

    agregar(salida, "fin", "", linea);
    return salida;
}

// Un texto como lo escribe `repr` en Python: entre comillas simples, salvo
// que lleve una y ninguna doble; la barra, los saltos y los de control, con
// su escape. Lo de UTF-8 va tal cual, como hace Python con lo imprimible.
fn repr_texto(t: view) -> str {
    var hay_simple = false;
    var hay_doble = false;
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 39 { hay_simple = true; }
        if byte(t, i) == 34 { hay_doble = true; }
        i = i + 1;
    }
    var comilla = 39;
    if hay_simple && !hay_doble { comilla = 34; }
    var r = vacio();
    empujar_byte(r, comilla como u8);
    i = 0;
    while i < largo(t) {
        let b = byte(t, i);
        if b == 92 { empujar(r, "\\\\"); }
        else if b == comilla { empujar(r, "\\"); empujar_byte(r, b como u8); }
        else if b == 10 { empujar(r, "\\n"); }
        else if b == 9 { empujar(r, "\\t"); }
        else if b == 13 { empujar(r, "\\r"); }
        else if b == 1 && i + 2 < largo(t) {
            // La marca de un `\xNN` descifrado: Python lo guarda como un
            // caracter suelto y lo muestra `\udcNN`.
            empujar(r, "\\udc");
            let alto = byte(t, i + 1);
            let bajo = byte(t, i + 2);
            empujar_byte(r, minuscula_hex(alto) como u8);
            empujar_byte(r, minuscula_hex(bajo) como u8);
            i = i + 2;
        }
        else if b < 32 || b == 127 {
            empujar(r, "\\x");
            empujar(r, rebanar("0123456789abcdef", b / 16, b / 16 + 1));
            empujar(r, rebanar("0123456789abcdef", b % 16, b % 16 + 1));
        }
        else { empujar_byte(r, b como u8); }
        i = i + 1;
    }
    empujar_byte(r, comilla como u8);
    return r;
}

fn minuscula_hex(b: usize) -> usize {
    if b >= 65 && b <= 70 { return b + 32; }
    return b;
}
