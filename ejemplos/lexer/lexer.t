// lexer.t — el analisis lexico de Tcode, escrito en Tcode.
//
// Es el primer programa grande del lenguaje y su primera prueba de fuego:
// si el diseño no aguanta, se nota aqui y no en un ejemplo de veinte lineas.
//
//     ./lexer archivo.t

struct Token {
    tipo: str,      // palabra, ident, entero, cadena, interpolada, simbolo
    valor: str,
    linea: usize,
}

// ------------------------------------------------------------------
// Clasificacion de bytes. Se trabaja sobre bytes, no sobre caracteres:
// los de UTF-8 por encima de 127 se dejan pasar dentro de identificadores
// y cadenas, que es lo que hace el compilador de verdad.
// ------------------------------------------------------------------

fn es_espacio(b: usize) -> bool {
    return b == 32 || b == 9 || b == 13;
}

fn es_digito(b: usize) -> bool {
    return b >= 48 && b <= 57;
}

fn es_letra(b: usize) -> bool {
    if b >= 97 && b <= 122 { return true; }
    if b >= 65 && b <= 90 { return true; }
    if b == 95 { return true; }
    return b >= 128;
}

fn es_alfanumerico(b: usize) -> bool {
    return es_letra(b) || es_digito(b);
}

fn palabras_reservadas() -> mapa<str, usize> {
    var m: mapa<str, usize> = [];
    poner(m, "fn", 1);       poner(m, "let", 1);      poner(m, "var", 1);
    poner(m, "mut", 1);      poner(m, "if", 1);       poner(m, "else", 1);
    poner(m, "while", 1);    poner(m, "for", 1);      poner(m, "en", 1);
    poner(m, "break", 1);    poner(m, "continue", 1); poner(m, "return", 1);
    poner(m, "struct", 1);   poner(m, "usar", 1);     poner(m, "try", 1);
    poner(m, "sino", 1);     poner(m, "falla", 1);    poner(m, "lista", 1);
    poner(m, "mapa", 1);     poner(m, "str", 1);      poner(m, "view", 1);
    poner(m, "usize", 1);    poner(m, "i64", 1);      poner(m, "bool", 1);
    poner(m, "true", 1);     poner(m, "false", 1);
    return m;
}

// Los simbolos de dos caracteres se prueban antes que los de uno, igual que
// en el compilador: si no, `+?` se leeria como `+` seguido de `?`.
fn simbolo_doble(a: usize, b: usize) -> bool {
    if a == 43 && b == 63 { return true; }     // +?
    if a == 45 && b == 63 { return true; }     // -?
    if a == 42 && b == 63 { return true; }     // *?
    if a == 45 && b == 62 { return true; }     // ->
    if a == 61 && b == 61 { return true; }     // ==
    if a == 33 && b == 61 { return true; }     // !=
    if a == 60 && b == 61 { return true; }     // <=
    if a == 62 && b == 61 { return true; }     // >=
    if a == 38 && b == 38 { return true; }     // &&
    if a == 124 && b == 124 { return true; }   // ||
    return false;
}

fn es_simbolo(b: usize) -> bool {
    if b == 40 || b == 41 || b == 123 || b == 125 { return true; }  // ( ) { }
    if b == 91 || b == 93 || b == 60 || b == 62 { return true; }    // [ ] < >
    if b == 44 || b == 59 || b == 58 || b == 46 { return true; }    // , ; : .
    if b == 61 || b == 43 || b == 45 || b == 42 { return true; }    // = + - *
    if b == 47 || b == 37 || b == 33 || b == 38 { return true; }    // / % ! &
    if b == 124 || b == 36 { return true; }                        // | $
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
fn fin_de_cadena(fuente: view, desde: usize) -> usize ! {
    var i: usize = desde;
    while i < largo(fuente) {
        let b: usize = byte(fuente, i);
        if b == 10 {
            falla "cadena sin cerrar antes del salto de linea";
        }
        if b == 92 {
            i = i + 2;      // escape: se salta el par entero
            continue;
        }
        if b == 34 {
            return i;
        }
        i = i + 1;
    }
    falla "cadena sin cerrar al final del archivo";
}

fn analizar(fuente: view) -> lista<Token> ! {
    let reservadas: mapa<str, usize> = palabras_reservadas();
    var salida: lista<Token> = [];
    var i: usize = 0;
    var linea: usize = 1;

    while i < largo(fuente) {
        let b: usize = byte(fuente, i);

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
            let sig: usize = byte(fuente, i + 1);
            if sig == 47 {
                while i < largo(fuente) && byte(fuente, i) != 10 {
                    i = i + 1;
                }
                continue;
            }
            if sig == 42 {
                var cerrado: bool = false;
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
            let fin: usize = try fin_de_cadena(fuente, i + 2);
            agregar(salida, "interpolada", rebanar(fuente, i + 2, fin), linea);
            i = fin + 1;
            continue;
        }

        // cadena
        if b == 34 {
            let fin: usize = try fin_de_cadena(fuente, i + 1);
            agregar(salida, "cadena", rebanar(fuente, i + 1, fin), linea);
            i = fin + 1;
            continue;
        }

        // numero
        if es_digito(b) {
            var j: usize = i;
            while j < largo(fuente) && (es_digito(byte(fuente, j))
                                        || byte(fuente, j) == 95) {
                j = j + 1;
            }
            agregar(salida, "entero", rebanar(fuente, i, j), linea);
            i = j;
            continue;
        }

        // identificador o palabra reservada
        if es_letra(b) {
            var j: usize = i;
            while j < largo(fuente) && es_alfanumerico(byte(fuente, j)) {
                j = j + 1;
            }
            let texto_pieza: view = rebanar(fuente, i, j);
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

// ------------------------------------------------------------------
// Programa
// ------------------------------------------------------------------

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t> [--contar]\n");
        return 1;
    }

    let ruta: view = argumento(1);
    let fuente: str = try leer_archivo(ruta);
    let tokens: lista<Token> = try analizar(vista(fuente));

    var solo_contar: bool = false;
    if n_argumentos() > 2 { solo_contar = igual(argumento(2), "--contar"); }

    if solo_contar {
        var por_tipo: mapa<str, usize> = [];
        for t en tokens {
            let cuantos: usize = obtener(por_tipo, vista(t.tipo)) sino 0;
            poner(por_tipo, vista(t.tipo), cuantos + 1);
        }
        imprimir($"{ruta}: {largo(tokens)} tokens\n");

        var nombres: lista<str> = claves(por_tipo);
        ordenar(nombres);
        for nombre en nombres {
            let cuantos: usize = obtener(por_tipo, vista(nombre)) sino 0;
            imprimir($"  {nombre}  {cuantos}\n");
        }
        return 0;
    }

    for t en tokens {
        imprimir($"{t.linea}\t{t.tipo}\t{t.valor}\n");
    }
    return 0;
}
