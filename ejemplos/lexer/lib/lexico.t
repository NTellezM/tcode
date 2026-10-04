// lib/lexico.t — el analisis lexico de Tcode, escrito en Tcode.
//
// Lo usan `lexer.t`, que imprime los tokens, y `parser.t`, que los analiza.

use "std/caracter";
use "xid.t";

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

// Si `t` es una palabra reservada. Por su largo primero: el lexer lo
// pregunta por cada nombre, tambien en el hueco de cada cadena interpolada,
// y hacer una tabla cada vez costaba mas que leer el hueco.
// Las palabras reservadas. `list`, `map`, `use` y `fail` son las que antes
// robaban palabras del idioma —`lista`, `mapa`, `usar`, `falla`—: desde la
// fase C esas vuelven a ser palabras normales, y por eso se pueden usar como
// nombre de variable o en mitad de un comentario.
fn es_reservada(t: view) -> bool {
    let n = t.largo();
    if n == 2 {
        return t == "fn" || t == "if" || t == "en" || t == "u8"
        || t == "i8";
    }
    if n == 3 {
        return t == "let" || t == "var" || t == "mut"
        || t == "for" || t == "try" || t == "str"
        || t == "u16" || t == "u32" || t == "u64"
        || t == "i16" || t == "i32" || t == "i64"
        || t == "f32" || t == "f64" || t == "map"
        || t == "use";
    }
    if n == 4 {
        return t == "else" || t == "sino" || t == "view"
        || t == "bool" || t == "true" || t == "enum"
        || t == "fail" || t == "list" || t == "drop";
    }
    if n == 5 {
        return t == "while" || t == "break" || t == "match"
        || t == "false" || t == "usize";
    }
    if n == 6 { return t == "return" || t == "struct" || t == "anchor"; }
    if n == 7 { return t == "externo" || t == "extends"; }
    if n == 8 { return t == "continue" || t == "protocol"; }
    if n == 10 { return t == "implements"; }
    return false;
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
    if a == 46 && b == 46 { return true; }   // ..
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

fn agregar(salida: mut list<Token>, tipo: view, valor: view, linea: usize) {
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
//
// El `archivo:linea: ` de los mensajes se escribe solo si hay error: hacerlo
// antes, por si acaso, era la mitad de lo que tardaba el lexer.
fn fin_de_cadena(fuente: view, desde: usize, interpolada: bool, archivo: view,
    linea: usize, error: mut str) -> usize ! {
    return try fin_de_cadena_en(fuente, desde, interpolada, false, archivo, linea, error);
}

// `en_hueco`: la cadena va dentro del hueco de otra. Si no se cierra, la de
// fuera tampoco, y lo mas probable es que falte la `}` del hueco, como en
// `$"hola {n"`.
fn fin_de_cadena_en(fuente: view, desde: usize, interpolada: bool, en_hueco: bool,
    archivo: view, linea: usize, error: mut str) -> usize ! {
    var i = desde;
    var hondura = 0;
    while true {
        if i >= fuente.largo() || byte(fuente, i) == 10 {
            if interpolada || en_hueco {
                error = $"{archivo}:{linea}: cadena interpolada sin cerrar; falta la comilla, o falta `}}` en algun hueco";
            } else {
                error = $"{archivo}:{linea}: cadena sin cerrar";
            }
            fail "cadena sin cerrar";
        }
        let b = byte(fuente, i);
        // `{{` y `}}` son una llave escrita, pero solo fuera de un hueco:
        // dentro, `}}` puede cerrar un bloque y el hueco.
        if interpolada && hondura == 0 && i + 1 < fuente.largo() {
            let sig = byte(fuente, i + 1);
            if (b == 123 && sig == 123) || (b == 125 && sig == 125) {
                i = i + 2;
                continue;
            }
        }
        // Un hueco se salta crudo: lo lee despues el lexer del hueco, con sus
        // escapes. Una cadena de dentro se salta entera, que sus llaves y sus
        // comillas no son del hueco.
        if hondura > 0 {
            let anidada = b == 36 && i + 1 < fuente.largo() && byte(fuente, i + 1) == 34;
            if b == 34 || anidada {
                var dentro = i + 1;
                if anidada { dentro = i + 2; }
                let cierre = try fin_de_cadena_en(fuente, dentro, anidada, true, archivo, linea,
                    error);
                i = cierre + 1;
                continue;
            }
            if b == 92 {
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
            if i + 1 >= fuente.largo() {
                error = $"{archivo}:{linea}: escape sin cerrar";
                fail "escape sin cerrar";
            }
            let esc = byte(fuente, i + 1);
            if esc == 120 {
                // `\xNN`: dos digitos hexadecimales, ni uno mas ni uno menos.
                var bien = i + 3 < fuente.largo();
                if bien { bien = es_hex(byte(fuente, i + 2)) && es_hex(byte(fuente, i + 3)); }
                if !bien {
                    error = $"{archivo}:{linea}: `\\x` lleva dos digitos hexadecimales detras, como `\\x0a`";
                    fail "escape mal formado";
                }
                i = i + 4;
                continue;
            }
            let conocido = esc == 110 || esc == 116 || esc == 92 || esc == 34 || esc == 48
            || (interpolada && (esc == 123 || esc == 125));
            if !conocido {
                error = $"{archivo}:{linea}: escape desconocido \\{rebanar(fuente, i + 1, i + 2)}";
                fail "escape desconocido";
            }
            i = i + 2;
            continue;
        }
        i = i + 1;
    }
    return i;
}

// Donde acaba una cadena ya leida que va dentro de un hueco: `i` es su
// comilla, o el `$` de una interpolada, y se devuelve lo que va detras de su
// comilla. No comprueba nada: el lexer ya la leyo entera.
fn fin_de_texto(t: view, i: usize) -> usize {
    let interpolada = byte(t, i) == 36;
    var j = i + 1;
    if interpolada { j = i + 2; }
    var hondura = 0;
    while j < t.largo() {
        let b = byte(t, j);
        if interpolada && hondura == 0 && j + 1 < t.largo() {
            let sig = byte(t, j + 1);
            if (b == 123 && sig == 123) || (b == 125 && sig == 125) {
                j = j + 2;
                continue;
            }
        }
        if hondura > 0 && (b == 34 || (b == 36 && j + 1 < t.largo() && byte(t, j + 1) == 34)) {
            j = fin_de_texto(t, j);
            continue;
        }
        if b == 92 {
            j = j + 2;
            continue;
        }
        if interpolada && b == 123 { hondura = hondura + 1; }
        if interpolada && b == 125 && hondura > 0 { hondura = hondura - 1; }
        if b == 34 && hondura == 0 { return j + 1; }
        j = j + 1;
    }
    return t.largo();
}

// La `}` que cierra el hueco que se abre justo antes de `i`, o el largo del
// texto si no la hay. Las cadenas de dentro se saltan enteras: sus llaves no
// son del hueco.
fn cierre_de_hueco(t: view, i: usize) -> usize {
    var hondura = 1;
    var j = i;
    while j < t.largo() {
        let b = byte(t, j);
        if b == 34 || (b == 36 && j + 1 < t.largo() && byte(t, j + 1) == 34) {
            j = fin_de_texto(t, j);
            continue;
        }
        if b == 92 {
            j = j + 2;
            continue;
        }
        if b == 123 { hondura = hondura + 1; }
        if b == 125 {
            hondura = hondura - 1;
            if hondura == 0 { return j; }
        }
        j = j + 1;
    }
    return t.largo();
}

fn es_hex(b: usize) -> bool {
    return (b >= 48 && b <= 57) || (b >= 97 && b <= 102) || (b >= 65 && b <= 70);
}

// `'a'`, como lo escribe Python: comilla simple, y la barra y los de control
// escapados.
fn repr_caracter(c: view) -> str {
    if c == "'" { return nuevo("\"'\""); }
    if c == "\\" { return nuevo("'\\\\'"); }
    if c.largo() == 1 {
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

fn analizar(fuente: view) -> list<Token> ! {
    var error = vacio();
    return try tokens_de(fuente, "<entrada>", error);
}

// La marca de orden de bytes —`U+FEFF`, `EF BB BF` en UTF-8— que muchos
// editores escriben al guardar y que no se ve. Solo vale como primer
// caracter del archivo: se quita de la vista antes de lexear, asi el primer
// token queda en la linea 1 y en la columna que le toca, como si no
// estuviera. En cualquier otro sitio sigue siendo un caracter inesperado, y
// un segundo BOM detras del primero tambien.
fn sin_bom(fuente: view) -> view {
    if fuente.largo() >= 3 && byte(fuente, 0) == 239
    && byte(fuente, 1) == 187 && byte(fuente, 2) == 191 {
        return rebanar(fuente, 3, fuente.largo());
    }
    return fuente;
}

// Los tokens de un archivo. Si no se puede, `error` dice por que y donde,
// con las mismas palabras que el lexer de Python.
fn tokens_de(fuente: view, archivo: view, error: mut str) -> list<Token> ! {
    return try tokens_de_todo(sin_bom(fuente), archivo, false, 1, error);
}

// Lo mismo para un texto que empieza en la linea `linea`: el hueco de una
// cadena interpolada se lee aparte, y sus errores tienen que decir donde
// esta la cadena.
fn tokens_desde(fuente: view, archivo: view, linea: usize, error: mut str) -> list<Token> ! {
    return try tokens_de_todo(fuente, archivo, false, linea, error);
}

// Con `comentarios`, tambien los comentarios, como tokens `comentario`: el
// formateador los necesita para dejarlos donde estaban.
// Donde empieza la primera secuencia que no es UTF-8, o el largo si todo lo
// es: las mismas reglas que el decodificador estricto de Python (RFC 3629),
// sin formas largas, sin sustitutos y sin pasar de U+10FFFF.
fn utf8_invalido(f: view) -> usize {
    var i = 0;
    while i < f.largo() {
        let b = byte(f, i);
        var n = 0;
        var bajo = 128;
        var alto = 191;
        if b < 128 {
            n = 1;
        } else if b >= 194 && b <= 223 {
            n = 2;
        } else if b >= 224 && b <= 239 {
            n = 3;
            if b == 224 { bajo = 160; }
            if b == 237 { alto = 159; }
        } else if b >= 240 && b <= 244 {
            n = 4;
            if b == 240 { bajo = 144; }
            if b == 244 { alto = 143; }
        } else {
            return i;
        }
        if i + n > f.largo() { return i; }
        var k = 1;
        while k < n {
            let c = byte(f, i + k);
            if k == 1 && (c < bajo || c > alto) { return i; }
            if k > 1 && (c < 128 || c > 191) { return i; }
            k = k + 1;
        }
        i = i + n;
    }
    return f.largo();
}

// Cuantos bytes ocupa el caracter que empieza con `b`.
fn largo_utf8(b: usize) -> usize {
    if b < 128 { return 1; }
    if b < 224 { return 2; }
    if b < 240 { return 3; }
    return 4;
}

// El punto de codigo que empieza en `i`, que ya se sabe UTF-8 valido.
fn punto_utf8(f: view, i: usize) -> usize {
    let b = byte(f, i);
    let n = largo_utf8(b);
    if n == 1 { return b; }
    var cp = b % 32;
    if n == 3 { cp = b % 16; }
    if n == 4 { cp = b % 8; }
    var k = 1;
    while k < n {
        cp = cp * 64 + byte(f, i + k) % 64;
        k = k + 1;
    }
    return cp;
}

// Un nombre empieza por `_`, una letra ASCII o un caracter XID_Start, y
// sigue con eso, digitos ASCII o XID_Continue (UAX #31).
fn empieza_nombre(f: view, i: usize) -> bool {
    let b = byte(f, i);
    if b < 128 { return es_minuscula(b) || es_mayuscula(b) || b == 95; }
    return xid_inicio(punto_utf8(f, i));
}

fn sigue_nombre(f: view, i: usize) -> bool {
    let b = byte(f, i);
    if b < 128 { return es_minuscula(b) || es_mayuscula(b) || b == 95 || es_digito(b); }
    return xid_sigue(punto_utf8(f, i));
}

// Si en `i`, que apunta a un `#`, empieza la directiva `#importar`. Vale solo
// al principio de la linea —donde viven los `use`— y con la palabra entera
// detras: asi el `#` sigue siendo un caracter inesperado en cualquier otro
// sitio, y `let x = 1 # 2;` no compila.
fn importar_en(fuente: view, i: usize) -> bool {
    if i + 9 > fuente.largo() { return false; }
    if rebanar(fuente, i + 1, i + 9) != "importar" { return false; }
    if i + 9 < fuente.largo() && sigue_nombre(fuente, i + 9) { return false; }
    var j = i;
    while j > 0 {
        let b = byte(fuente, j - 1);
        if b == 10 { return true; }
        if b != 32 && b != 9 && b != 13 { return false; }
        j = j - 1;
    }
    return true;
}

// `n` en hexadecimal con mayusculas y al menos cuatro cifras, como `U+00D7`.
fn hexadecimal(n: usize) -> str {
    var cifras = vacio();
    var resto = n;
    while resto > 0 || cifras.largo() < 4 {
        let d = resto % 16;
        cifras = $"{rebanar("0123456789ABCDEF", d, d + 1)}{cifras}";
        resto = resto / 16;
    }
    return cifras;
}

fn es_hex_digito(b: usize) -> bool {
    return (b >= 48 && b <= 57) || (b >= 97 && b <= 102) || (b >= 65 && b <= 70);
}

fn valor_hex_digito(b: usize) -> usize {
    if b >= 48 && b <= 57 { return b - 48; }
    if b >= 97 && b <= 102 { return b - 87; }
    return b - 55;
}

// Los digitos hexadecimales, a su valor en decimal: `FF` -> "255".
fn hex_decimal(v: view) -> str {
    var n = 0;
    var k = 0;
    while k < v.largo() {
        n = n * 16 + valor_hex_digito(byte(v, k));
        k = k + 1;
    }
    return $"{n}";
}

// Donde empieza el primer control bidireccional de `fuente`, o su largo si
// no hay ninguno. En UTF-8 son E2 80 AA..AE (U+202A..U+202E) y E2 81 A6..A9
// (U+2066..U+2069).
fn control_bidireccional(fuente: view) -> usize {
    var i = 0;
    while i + 2 < fuente.largo() {
        if byte(fuente, i) == 226 {
            let b1 = byte(fuente, i + 1);
            let b2 = byte(fuente, i + 2);
            if b1 == 128 && b2 >= 170 && b2 <= 174 { return i; }
            if b1 == 129 && b2 >= 166 && b2 <= 169 { return i; }
        }
        i = i + 1;
    }
    return fuente.largo();
}

// `U+202E`, el del control bidireccional que empieza en `i`.
fn nombre_bidireccional(fuente: view, i: usize) -> str {
    let b1 = byte(fuente, i + 1);
    let b2 = byte(fuente, i + 2);
    if b1 == 128 {
        if b2 == 170 { return nuevo("U+202A"); }
        if b2 == 171 { return nuevo("U+202B"); }
        if b2 == 172 { return nuevo("U+202C"); }
        if b2 == 173 { return nuevo("U+202D"); }
        return nuevo("U+202E");
    }
    if b2 == 166 { return nuevo("U+2066"); }
    if b2 == 167 { return nuevo("U+2067"); }
    if b2 == 168 { return nuevo("U+2068"); }
    return nuevo("U+2069");
}

// Cuantos saltos de linea hay antes de la posicion `hasta`.
fn lineas_hasta(fuente: view, hasta: usize) -> usize {
    var n = 0;
    var i = 0;
    while i < hasta && i < fuente.largo() {
        if byte(fuente, i) == 10 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn tokens_de_todo(fuente: view, archivo: view, comentarios: bool, desde_linea: usize,
    error: mut str) -> list<Token> ! {
    // Los controles bidireccionales hacen que el codigo se vea distinto de
    // como se compila ("Trojan Source"): no valen en ningun sitio, tampoco
    // en una cadena o un comentario.
    // Un `.t` es UTF-8: si no, se dice la linea del primer byte que no lo
    // es, como el compilador de Python.
    let roto = utf8_invalido(fuente);
    if roto < fuente.largo() {
        let donde = desde_linea + lineas_hasta(fuente, roto);
        error = $"{archivo}:{donde}: el archivo no es UTF-8 valido";
        fail "no es UTF-8";
    }
    let bidi = control_bidireccional(fuente);
    if bidi < fuente.largo() {
        let donde = desde_linea + lineas_hasta(fuente, bidi);
        let cual = nombre_bidireccional(fuente, bidi);
        error = $"{archivo}:{donde}: control bidireccional {cual}: hace que el codigo se vea distinto de como se compila";
        fail "control bidireccional";
    }
    var salida: list<Token> = [];
    var i = 0;
    var linea = desde_linea;

    while i < fuente.largo() {
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
        if b == 47 && i + 1 < fuente.largo() {
            let sig = byte(fuente, i + 1);
            if sig == 47 {
                let desde = i;
                while i < fuente.largo() && byte(fuente, i) != 10 {
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
                while j + 1 < fuente.largo() {
                    if byte(fuente, j) == 42 && byte(fuente, j + 1) == 47 {
                        cerrado = true;
                        break;
                    }
                    if byte(fuente, j) == 10 { saltos = saltos + 1; }
                    j = j + 1;
                }
                if !cerrado {
                    error = $"{archivo}:{linea}: comentario /* sin cerrar";
                    fail "comentario /* sin cerrar";
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
        if b == 36 && i + 1 < fuente.largo() && byte(fuente, i + 1) == 34 {
            let fin = try fin_de_cadena(fuente, i + 2, true, archivo, linea, error);
            agregar(salida, "interpolada", rebanar(fuente, i + 2, fin), linea);
            i = fin + 1;
            continue;
        }

        // cadena
        if b == 34 {
            let fin = try fin_de_cadena(fuente, i + 1, false, archivo, linea, error);
            agregar(salida, "cadena", rebanar(fuente, i + 1, fin), linea);
            i = fin + 1;
            continue;
        }

        // hexadecimal: `$FF`, `$1a2b`. Sin digito detras, `$` sigue siendo
        // un simbolo (hoy no se usa para nada mas).
        if b == 36 && i + 1 < fuente.largo() && es_hex_digito(byte(fuente, i + 1)) {
            var j = i + 1;
            while j < fuente.largo() && es_hex_digito(byte(fuente, j)) {
                j = j + 1;
            }
            if comentarios {
                agregar(salida, "entero", rebanar(fuente, i, j), linea);
            } else {
                // Sin ceros delante: 16 digitos caben en u64, uno mas no.
                let digitos = rebanar(fuente, i + 1, j);
                var desde = 0;
                while desde + 1 < digitos.largo() && byte(digitos, desde) == 48 {
                    desde = desde + 1;
                }
                if digitos.largo() - desde > 16 {
                    error = $"{archivo}:{linea}: el hexadecimal no cabe en u64";
                    fail "numero mal formado";
                }
                agregar(salida, "entero", hex_decimal(digitos), linea);
            }
            i = j;
            continue;
        }

        // numero
        if es_digito(b) {
            var j = i;
            while j < fuente.largo() && (es_digito(byte(fuente, j))
                || byte(fuente, j) == 95) {
                j = j + 1;
            }
            // Decimal: el punto lleva un digito a cada lado, y luego puede
            // venir un exponente.
            var decimal = false;
            if j + 1 < fuente.largo() && byte(fuente, j) == 46 {
                if es_digito(byte(fuente, j + 1)) {
                    decimal = true;
                    j = j + 1;
                    while j < fuente.largo() && (es_digito(byte(fuente, j))
                        || byte(fuente, j) == 95) {
                        j = j + 1;
                    }
                }
            }
            if j < fuente.largo() {
                if byte(fuente, j) == 101 || byte(fuente, j) == 69 {
                    var k = j + 1;
                    if k < fuente.largo() {
                        if byte(fuente, k) == 43 || byte(fuente, k) == 45 {
                            k = k + 1;
                        }
                    }
                    if k < fuente.largo() {
                        if es_digito(byte(fuente, k)) {
                            decimal = true;
                            j = k;
                            while j < fuente.largo() && es_digito(byte(fuente, j)) {
                                j = j + 1;
                            }
                        }
                    }
                }
            }
            // `12abc` o `1.`: ni numero ni otra cosa. `0..3` si: el numero
            // acaba antes de los dos puntos del rango.
            let rango = j + 1 < fuente.largo() && byte(fuente, j) == 46
            && byte(fuente, j + 1) == 46;
            if j < fuente.largo() && (empieza_nombre(fuente, j) && byte(fuente, j) != 95
                || byte(fuente, j) == 46 && !rango) {
                let visto = repr_texto(rebanar(fuente, i, j + largo_utf8(byte(fuente, j))));
                error = $"{archivo}:{linea}: numero mal formado cerca de {visto}";
                fail "numero mal formado";
            }
            // `1_000` es `1000`: el guion bajo solo ayuda a leerlo. Para el
            // formato, con `comentarios`, el numero se queda como se escribio.
            var limpio = vacio();
            var q = i;
            while q < j {
                if comentarios || byte(fuente, q) != 95 {
                    limpio.empujar(rebanar(fuente, q, q + 1));
                }
                q = q + 1;
            }
            var clase = nuevo("entero");
            if decimal { clase = nuevo("decimal"); }
            agregar(salida, vista(clase), vista(limpio), linea);
            i = j;
            continue;
        }

        // identificador o palabra reservada
        if empieza_nombre(fuente, i) {
            var j = i + largo_utf8(b);
            while j < fuente.largo() && sigue_nombre(fuente, j) {
                j = j + largo_utf8(byte(fuente, j));
            }
            let texto_pieza = rebanar(fuente, i, j);
            if es_reservada(texto_pieza) {
                agregar(salida, "palabra", texto_pieza, linea);
            } else {
                agregar(salida, "ident", texto_pieza, linea);
            }
            i = j;
            continue;
        }

        // la directiva de la biblioteca del compilador: `#importar "x.t"`,
        // una sola palabra, para que el formateador la deje como se escribe.
        if b == 35 && importar_en(fuente, i) {
            agregar(salida, "palabra", "#importar", linea);
            i = i + 9;
            continue;
        }

        // simbolo, de dos en dos primero
        if i + 1 < fuente.largo() && simbolo_doble(b, byte(fuente, i + 1)) {
            agregar(salida, "simbolo", rebanar(fuente, i, i + 2), linea);
            i = i + 2;
            continue;
        }
        if es_simbolo(b) {
            agregar(salida, "simbolo", rebanar(fuente, i, i + 1), linea);
            i = i + 1;
            continue;
        }

        var visto = vacio();
        if b < 128 {
            visto = repr_caracter(rebanar(fuente, i, i + 1));
        } else {
            visto = $"U+{hexadecimal(punto_utf8(fuente, i))}";
        }
        error = $"{archivo}:{linea}: caracter inesperado {visto}";
        fail "caracter inesperado";
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
    while i < t.largo() {
        if byte(t, i) == 39 { hay_simple = true; }
        if byte(t, i) == 34 { hay_doble = true; }
        i = i + 1;
    }
    var comilla = 39;
    if hay_simple && !hay_doble { comilla = 34; }
    var r = vacio();
    empujar_byte(r, comilla como u8);
    i = 0;
    while i < t.largo() {
        let b = byte(t, i);
        if b == 92 { r.empujar("\\\\"); }
        else if b == comilla { r.empujar("\\"); empujar_byte(r, b como u8); }
        else if b == 10 { r.empujar("\\n"); }
        else if b == 9 { r.empujar("\\t"); }
        else if b == 13 { r.empujar("\\r"); }
        else if b == 1 && i + 2 < t.largo() {
            // La marca de un `\xNN` descifrado: Python lo guarda como un
            // caracter suelto y lo muestra `\udcNN`.
            r.empujar("\\udc");
            let alto = byte(t, i + 1);
            let bajo = byte(t, i + 2);
            empujar_byte(r, minuscula_hex(alto) como u8);
            empujar_byte(r, minuscula_hex(bajo) como u8);
            i = i + 2;
        }
        else if b < 32 || b == 127 {
            r.empujar("\\x");
            r.empujar(rebanar("0123456789abcdef", b / 16, b / 16 + 1));
            r.empujar(rebanar("0123456789abcdef", b % 16, b % 16 + 1));
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
