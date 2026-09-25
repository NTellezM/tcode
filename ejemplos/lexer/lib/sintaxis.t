// lib/sintaxis.t — el analisis sintactico de Tcode, escrito en Tcode.
//
// Lo usan `parser.t`, que imprime el arbol, y `compilador/tipos.t`, que se
// apoya en el para responder preguntas sobre los tipos que aparecen.

usar "std/texto";
usar "lexico.t";

struct Nodo {
    clase: str,
    texto: str,
    linea: usize,
    hijos: lista<Nodo>,
}

struct Estado {
    toks: lista<Token>,
    i: usize,
    // Los alias de `usar ... como x`: `x.algo` es un nombre, no el campo
    // `algo` de una variable `x`.
    alias: mapa<str, usize>,
    // Nombres de struct, recogidos antes de analizar: hacen falta para saber
    // que `Punto { x: 1 }` es un literal y no el inicio de un bloque.
    structs: mapa<str, usize>,
    // Nombres de enum, por lo mismo: `Color.Rojo` es una forma, no el campo
    // `Rojo` de una variable `Color`.
    enums: mapa<str, usize>,
    // El archivo, para los mensajes, y el primer error que se encontro:
    // `archivo:linea: mensaje, se encontro 'x'`, como el parser de Python.
    archivo: str,
    error: str,
    // Los parametros de tipo de la funcion o el struct que se esta leyendo:
    // mientras dura, `T` es un tipo mas.
    tipo_params: mapa<str, usize>,
}

// Un estado nuevo sobre unos tokens.
fn estado_de(toks: lista<Token>, archivo: view, structs: mapa<str, usize>,
    enums: mapa<str, usize>) -> Estado {
    return Estado { toks: toks, i: 0, alias: [], structs: structs, enums: enums,
        archivo: nuevo(archivo), error: vacio(), tipo_params: [] };
}

// ------------------------------------------------------------------
// Construccion del arbol. Cada hijo se MUEVE dentro del padre: no hay
// copias, y el arbol entero se libera solo al salir del bloque.
// ------------------------------------------------------------------

fn hoja(clase: view, texto: view, linea: usize) -> Nodo {
    return Nodo { clase: nuevo(clase), texto: nuevo(texto), linea: linea,
        hijos: [] };
}

fn rama(clase: view, linea: usize) -> Nodo {
    return Nodo { clase: nuevo(clase), texto: vacio(), linea: linea,
        hijos: [] };
}

fn contar_nodos(n: &Nodo) -> usize {
    var total = 1;
    for h en n.hijos { total = total + contar_nodos(h); }
    return total;
}

fn hondura(n: &Nodo) -> usize {
    var mayor = 0;
    for h en n.hijos {
        let d = hondura(h);
        if d > mayor { mayor = d; }
    }
    return mayor + 1;
}

fn mostrar(n: &Nodo, sangria: usize) {
    var i = 0;
    while i < sangria { imprimir("  "); i = i + 1; }
    if largo(n.texto) > 0 {
        imprimir($"{n.clase} {n.texto}\n");
    } else {
        imprimir($"{n.clase}\n");
    }
    for h en n.hijos { mostrar(h, sangria + 1); }
}

// ------------------------------------------------------------------
// Lectura de tokens
// ------------------------------------------------------------------

fn tipo_en(e: &Estado, salto: usize) -> view {
    let j = e.i + salto;
    if j >= largo(e.toks) { return "fin"; }
    return vista(e.toks[j].tipo);
}

fn valor_en(e: &Estado, salto: usize) -> view {
    let j = e.i + salto;
    if j >= largo(e.toks) { return ""; }
    return vista(e.toks[j].valor);
}

fn linea_actual(e: &Estado) -> usize {
    if e.i >= largo(e.toks) { return 0; }
    return e.toks[e.i].linea;
}

fn es(e: &Estado, tipo: view, valor: view) -> bool {
    if !igual(tipo_en(e, 0), tipo) { return false; }
    if largo(valor) == 0 { return true; }
    return igual(valor_en(e, 0), valor);
}

fn avanzar(e: mut Estado) { e.i = e.i + 1; }

fn acepta(e: mut Estado, tipo: view, valor: view) -> bool {
    if es(e, tipo, valor) {
        avanzar(e);
        return true;
    }
    return false;
}

// ------------------------------------------------------------------
// Los errores, con las palabras del parser de Python
// ------------------------------------------------------------------

// Lo que se encontro, como lo muestra Python: el texto del token entre
// comillas, recortado si es largo, o `fin de archivo`.
fn visto_en(e: &Estado, k: usize) -> str {
    if k >= largo(e.toks) || igual(vista(e.toks[k].tipo), "fin") {
        return nuevo("fin de archivo");
    }
    var valor = copiar(e.toks[k].valor);
    let clase = vista(e.toks[k].tipo);
    // Python guarda las cadenas ya descifradas.
    if igual(clase, "cadena") || igual(clase, "interpolada") {
        valor = descifrado(vista(valor), igual(clase, "interpolada"));
    }
    if caracteres(vista(valor)) > 72 {
        valor = $"{primeros(vista(valor), 69)}...";
    }
    return repr_texto(vista(valor));
}

// Los caracteres de un texto UTF-8, contando cada `\xNN` descifrado como uno.
fn caracteres(t: view) -> usize {
    var n = 0;
    var i = 0;
    while i < largo(t) {
        let b = byte(t, i);
        if b == 1 && i + 2 < largo(t) {
            n = n + 1;
            i = i + 3;
            continue;
        }
        if b < 128 || b >= 192 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn primeros(t: view, cuantos: usize) -> str {
    var n = 0;
    var i = 0;
    while i < largo(t) {
        let b = byte(t, i);
        let empieza = b < 128 || b >= 192;
        if empieza && n == cuantos { break; }
        if empieza { n = n + 1; }
        if b == 1 && i + 2 < largo(t) {
            i = i + 3;
            continue;
        }
        i = i + 1;
    }
    return nuevo(rebanar(t, 0, i));
}

// Una cadena con sus escapes resueltos. Un `\xNN` queda como una marca de
// tres bytes que `repr_texto` sabe mostrar.
fn descifrado(t: view, interpolada: bool) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(t) {
        let b = byte(t, i);
        if b == 92 && i + 1 < largo(t) {
            let d = byte(t, i + 1);
            if d == 110 { empujar_byte(r, 10); i = i + 2; continue; }
            if d == 116 { empujar_byte(r, 9); i = i + 2; continue; }
            if d == 48 { empujar_byte(r, 0); i = i + 2; continue; }
            if d == 120 && i + 3 < largo(t) {
                empujar_byte(r, 1);
                empujar(r, rebanar(t, i + 2, i + 4));
                i = i + 4;
                continue;
            }
            // `\{` y `\}` en una interpolada son una llave escrita: quedan
            // como `{{` y `}}`, que no abren ni cierran un hueco.
            if interpolada && (d == 123 || d == 125) {
                empujar(r, rebanar(t, i + 1, i + 2));
                empujar(r, rebanar(t, i + 1, i + 2));
                i = i + 2;
                continue;
            }
            empujar(r, rebanar(t, i + 1, i + 2));
            i = i + 2;
            continue;
        }
        empujar(r, rebanar(t, i, i + 1));
        i = i + 1;
    }
    return r;
}

// Deja el primer error: `archivo:linea: mensaje, se encontro 'x'`, sobre el
// token `k`. Quien lo llama falla justo despues.
fn error_en(e: mut Estado, mensaje: view, k: usize) {
    if largo(e.error) > 0 { return; }
    var linea = 0;
    if k < largo(e.toks) { linea = e.toks[k].linea; }
    let visto = visto_en(e, k);
    e.error = $"{e.archivo}:{linea}: {mensaje}, se encontro {visto}";
}

fn error_aqui(e: mut Estado, mensaje: view) {
    let k = e.i;
    error_en(e, mensaje, k);
}

fn espera(e: mut Estado, tipo: view, valor: view) -> str ! {
    // `lista<lista<str>>` acaba en dos `>` pegados, que el lexer lee como el
    // desplazamiento `>>`. Donde se espera cerrar un tipo, se parte en dos.
    if igual(valor, ">") {
        if es(e, "simbolo", ">>") {
            e.toks[e.i].valor = nuevo(">");
            return nuevo(">");
        }
    }
    let v = nuevo(valor_en(e, 0));
    if !es(e, tipo, valor) {
        var que = nuevo(valor);
        if largo(que) == 0 { que = nuevo(tipo); }
        let dicho = repr_texto(vista(que));
        error_aqui(e, $"se esperaba {dicho}");
        falla "sintaxis";
    }
    avanzar(e);
    return v;
}

// Un entero escrito: solo digitos, y que quepa en `u64`. Devuelve el texto
// sin ceros delante.
fn entero_literal(e: mut Estado, k: usize) -> str ! {
    let texto_t = copiar(e.toks[k].valor);
    var i = 0;
    while i + 1 < largo(texto_t) && byte(vista(texto_t), i) == 48 { i = i + 1; }
    let limpio = nuevo(rebanar(vista(texto_t), i, largo(texto_t)));
    let tope = "18446744073709551615";
    if largo(limpio) > largo(tope)
    || (largo(limpio) == largo(tope) && menor(tope, vista(limpio))) {
        error_en(e, "el literal entero no cabe en `u64`", k);
        falla "sintaxis";
    }
    return limpio;
}

fn es_tipo_basico(t: view) -> bool {
    return igual(t, "str") || igual(t, "view") || igual(t, "bool") || igual(t, "u8")
    || igual(t, "u16") || igual(t, "u32") || igual(t, "u64") || igual(t, "usize")
    || igual(t, "i8") || igual(t, "i16") || igual(t, "i32") || igual(t, "i64")
    || igual(t, "f32") || igual(t, "f64");
}

// ------------------------------------------------------------------
// Tipos
// ------------------------------------------------------------------

// Los argumentos de `Nombre<A, B>`, con el `<` ya comido.
fn argumentos_de_tipo(e: mut Estado, nombre: view) -> str ! {
    var t = nuevo(nombre);
    empujar(t, "<");
    var primero = true;
    while true {
        let a = try tipo(e);
        if !primero { empujar(t, ", "); }
        primero = false;
        empujar(t, vista(a));
        if !acepta(e, "simbolo", ",") { break; }
    }
    try espera(e, "simbolo", ">");
    empujar(t, ">");
    return t;
}

fn tipo(e: mut Estado) -> str ! {
    let k = e.i;
    // `&T` y `&mut T` como tipo.
    if acepta(e, "simbolo", "&") {
        var t = nuevo("&");
        if acepta(e, "palabra", "mut") { empujar(t, "mut "); }
        let dentro = try tipo(e);
        empujar(t, dentro);
        return t;
    }
    if es(e, "palabra", "") && es_tipo_basico(valor_en(e, 0)) {
        let v = nuevo(valor_en(e, 0));
        avanzar(e);
        return v;
    }
    // `fn(usize, usize) -> bool`: el tipo de una funcion usada como valor.
    if es(e, "palabra", "fn") {
        avanzar(e);
        try espera(e, "simbolo", "(");
        var t = nuevo("fn(");
        if !es(e, "simbolo", ")") {
            var primero = true;
            while true {
                let a = try tipo(e);
                if !primero { empujar(t, ", "); }
                primero = false;
                empujar(t, a);
                if !acepta(e, "simbolo", ",") { break; }
            }
        }
        try espera(e, "simbolo", ")");
        empujar(t, ")");
        if acepta(e, "simbolo", "->") {
            let r = try tipo(e);
            empujar(t, " -> ");
            empujar(t, r);
        }
        return t;
    }
    // Un parametro de tipo de la funcion en curso.
    if es(e, "ident", "") && tiene(e.tipo_params, valor_en(e, 0)) {
        let v = nuevo(valor_en(e, 0));
        avanzar(e);
        return v;
    }
    // `par.Par<usize, str>`: un tipo que llega con nombre de modulo.
    if es(e, "ident", "") && tiene(e.alias, valor_en(e, 0))
    && igual(tipo_en(e, 1), "simbolo") && igual(valor_en(e, 1), ".") {
        var v = nuevo(valor_en(e, 0));
        avanzar(e);
        avanzar(e);
        let miembro = try espera(e, "ident", "");
        empujar(v, ".");
        empujar(v, miembro);
        if acepta(e, "simbolo", "<") { return try argumentos_de_tipo(e, vista(v)); }
        return v;
    }
    // `cadena_c`: un `char*` de C que Tcode copia.
    if es(e, "ident", "cadena_c") {
        avanzar(e);
        return nuevo("cadena_c");
    }
    // El nombre de un struct o de un enum, con o sin argumentos de tipo.
    if es(e, "ident", "") && (tiene(e.structs, valor_en(e, 0)) || tiene(e.enums, valor_en(e, 0))) {
        let v = nuevo(valor_en(e, 0));
        avanzar(e);
        if acepta(e, "simbolo", "<") { return try argumentos_de_tipo(e, vista(v)); }
        return v;
    }
    if es(e, "palabra", "mapa") {
        avanzar(e);
        try espera(e, "simbolo", "<");
        let clave = try tipo(e);
        try espera(e, "simbolo", ",");
        let valor = try tipo(e);
        try espera(e, "simbolo", ">");
        return $"mapa<{clave}, {valor}>";
    }
    // `bloque<T>`: no es palabra reservada, se reconoce por el `<`.
    if es(e, "ident", "bloque") && igual(valor_en(e, 1), "<") {
        avanzar(e);
        try espera(e, "simbolo", "<");
        let dentro = try tipo(e);
        try espera(e, "simbolo", ">");
        return $"bloque<{dentro}>";
    }
    if es(e, "palabra", "lista") {
        avanzar(e);
        try espera(e, "simbolo", "<");
        let dentro = try tipo(e);
        try espera(e, "simbolo", ">");
        return $"lista<{dentro}>";
    }
    // Un arreglo de tamaño fijo: `[usize; 5]`.
    if acepta(e, "simbolo", "[") {
        let dentro = try tipo(e);
        try espera(e, "simbolo", ";");
        let kn = e.i;
        try espera(e, "entero", "");
        let n = try entero_literal(e, kn);
        try espera(e, "simbolo", "]");
        if igual(vista(n), "0") {
            error_en(e, "un arreglo tiene que tener al menos un elemento", k);
            falla "sintaxis";
        }
        return $"[{dentro}; {n}]";
    }
    error_aqui(e, "se esperaba un tipo (str, view, usize, i64, bool, lista<tipo>, mapa<clave, valor>, un struct, o [tipo; N])");
    falla "sintaxis";
}

// ------------------------------------------------------------------
// Expresiones, de menor a mayor precedencia
// ------------------------------------------------------------------

fn match_(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);
    try espera(e, "palabra", "match");
    var n = rama("match", l);
    let v = try expresion(e);
    anadir(n.hijos, v);
    try espera(e, "simbolo", "{");
    var brazos = 0;
    while !es(e, "simbolo", "}") {
        if es(e, "fin", "") {
            error_aqui(e, "match sin cerrar");
            falla "sintaxis";
        }
        let bl = linea_actual(e);
        var b = rama("brazo", bl);
        if es(e, "ident", "_") {
            avanzar(e);
        } else {
            let quien = try espera(e, "ident", "");
            try espera(e, "simbolo", ".");
            let cual = try espera(e, "ident", "");
            if !tiene(e.enums, vista(quien)) {
                error_aqui(e, $"`{quien}` no es un enum");
                falla "sintaxis";
            }
            empujar(b.texto, quien);
            empujar(b.texto, ".");
            empujar(b.texto, cual);
            if acepta(e, "simbolo", "(") {
                if !es(e, "simbolo", ")") {
                    while true {
                        let atrapa = try espera(e, "ident", "");
                        anadir(b.hijos, hoja("atrapa", vista(atrapa), bl));
                        if !acepta(e, "simbolo", ",") { break; }
                    }
                }
                try espera(e, "simbolo", ")");
            }
        }
        try espera(e, "simbolo", "->");
        brazos = brazos + 1;
        if es(e, "simbolo", "{") {
            let cuerpo = try bloque(e);
            anadir(b.hijos, cuerpo);
            anadir(n.hijos, b);
            let _coma = acepta(e, "simbolo", ",");
        } else {
            // Un brazo que da un valor es un `return` de esa expresion: por
            // dentro es lo mismo que un brazo con bloque, y asi el arbol no
            // tiene dos formas de decir la misma cosa.
            let x = try expresion(e);
            var r = rama("retorno", bl);
            anadir(r.hijos, x);
            anadir(b.hijos, r);
            anadir(n.hijos, b);
            if !acepta(e, "simbolo", ",") { break; }
        }
    }
    try espera(e, "simbolo", "}");
    if brazos == 0 {
        error_aqui(e, "un `match` sin brazos no mira nada");
        falla "sintaxis";
    }
    return n;
}

// Analiza lo que hay entre llaves y lo cuelga en orden. `{{` y `}}` son una
// llave escrita, no un hueco. `k` es el token de la cadena, al que apuntan
// los errores.
fn huecos_de(e: mut Estado, t: view, n: mut Nodo, k: usize) ! {
    // Python mira la cadena ya descifrada: un `\"` es una comilla.
    let texto_d = descifrado(t, true);
    let d = vista(texto_d);
    var i = 0;
    while i < largo(d) {
        let c = byte(d, i);
        if c == 123 && i + 1 < largo(d) && byte(d, i + 1) == 123 {
            i = i + 2;
            continue;
        }
        if c == 125 && i + 1 < largo(d) && byte(d, i + 1) == 125 {
            i = i + 2;
            continue;
        }
        if c == 125 {
            error_en(e, "`}` suelto dentro de una cadena interpolada; escribe `}}` si querias la llave", k);
            falla "sintaxis";
        }
        if c != 123 {
            i = i + 1;
            continue;
        }
        var prof = 1;
        var j = i + 1;
        while j < largo(d) && prof > 0 {
            if byte(d, j) == 123 { prof = prof + 1; }
            if byte(d, j) == 125 { prof = prof - 1; }
            if prof > 0 { j = j + 1; }
        }
        if prof != 0 {
            error_en(e, "falta `}` en una cadena interpolada", k);
            falla "sintaxis";
        }
        let dentro = recortar(rebanar(d, i + 1, j));
        if largo(dentro) == 0 {
            error_en(e, "`{}` vacio en una cadena interpolada: pon dentro lo que quieras mostrar", k);
            falla "sintaxis";
        }
        var error_lex = vacio();
        let suyos = tokens_de(dentro, vista(e.archivo), error_lex) sino [];
        if largo(error_lex) > 0 {
            if largo(e.error) == 0 { e.error = error_lex; }
            falla "sintaxis";
        }
        var sub = estado_de(suyos, vista(e.archivo), copiar(e.structs), copiar(e.enums));
        sub.alias = copiar(e.alias);
        sub.tipo_params = copiar(e.tipo_params);
        let x = expresion(sub) sino hoja("vacio", "", 0);
        if largo(sub.error) > 0 {
            if largo(e.error) == 0 { e.error = copiar(sub.error); }
            falla "sintaxis";
        }
        if !es(sub, "fin", "") {
            let dicho = repr_texto(dentro);
            error_en(e, $"sobra algo despues de la expresion {dicho} dentro de la cadena", k);
            falla "sintaxis";
        }
        var x_l = x;
        // El sub-analisis empieza a contar en la linea 1: lo de dentro de un
        // hueco esta donde este la cadena, y los errores tienen que decirlo.
        poner_linea(x_l, n.linea);
        anadir(n.hijos, x_l);
        i = j + 1;
    }
    return;
}

// El lexer deja las cadenas crudas, con los escapes sin resolver: para el
// analisis lexico da igual. Aqui no da igual, porque lo que se escribe en el
// C son BYTES y lo que se cuenta son bytes. Asi que primero se descifra lo
// que puso quien escribio, y luego se vuelve a escapar para C.
fn desescapar(t: view) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(t) {
        let c = byte(t, i);
        if c != 92 || i + 1 >= largo(t) {
            empujar(r, rebanar(t, i, i + 1));
            i = i + 1;
            continue;
        }
        let d = byte(t, i + 1);
        if d == 110 { empujar_byte(r, 10); i = i + 2; continue; }
        if d == 116 { empujar_byte(r, 9); i = i + 2; continue; }
        if d == 48 { empujar_byte(r, 0); i = i + 2; continue; }
        if d == 120 {
            // `\xNN`: un byte escrito en hexadecimal.
            if i + 3 < largo(t) {
                let alto = de_hex(byte(t, i + 2));
                let bajo = de_hex(byte(t, i + 3));
                if alto < 16 && bajo < 16 {
                    empujar_byte(r, ((alto * 16) + bajo) como ? u8);
                    i = i + 4;
                    continue;
                }
            }
        }
        // `\\`, `\"`, `\{`, `\}`: el segundo tal cual.
        empujar(r, rebanar(t, i + 1, i + 2));
        i = i + 2;
    }
    return r;
}

fn de_hex(c: usize) -> usize {
    if c >= 48 && c <= 57 { return c - 48; }
    if c >= 97 && c <= 102 { return c - 97 + 10; }
    if c >= 65 && c <= 70 { return c - 65 + 10; }
    return 99;
}

fn poner_linea(n: mut Nodo, l: usize) {
    n.linea = l;
    // Por indice y no con `for`: un `for` presta solo para leer, y aqui hay
    // que cambiar lo que se recorre.
    var i = 0;
    while i < largo(n.hijos) {
        poner_linea(n.hijos[i], l);
        i = i + 1;
    }
}

// Los parametros de una funcion o una clausura: `x: T`, `x: mut T`,
// `x: &T` y `x: &mut T`, que presta para modificar como `mut`.
fn parametros(e: mut Estado, n: mut Nodo, l: usize) ! {
    if es(e, "simbolo", ")") { return; }
    while true {
        let pn = try espera(e, "ident", "");
        try espera(e, "simbolo", ":");
        var marca = vacio();
        if acepta(e, "palabra", "mut") {
            marca = nuevo("mut ");
        } else if acepta(e, "simbolo", "&") {
            if acepta(e, "palabra", "mut") { marca = nuevo("mut "); }
            else { marca = nuevo("&"); }
        }
        let t = try tipo(e);
        var pp = rama("param", l);
        empujar(pp.texto, pn);
        empujar(pp.texto, ": ");
        empujar(pp.texto, marca);
        empujar(pp.texto, t);
        anadir(n.hijos, pp);
        if !acepta(e, "simbolo", ",") { break; }
    }
    return;
}

// Los argumentos de una llamada, con el `(` ya comido.
fn cuerpo_llamada(e: mut Estado, nombre: view, l: usize) -> Nodo ! {
    var n = rama("llamada", l);
    empujar(n.texto, nombre);
    if !es(e, "simbolo", ")") {
        while true {
            let x = try expresion(e);
            anadir(n.hijos, x);
            if !acepta(e, "simbolo", ",") { break; }
        }
    }
    try espera(e, "simbolo", ")");
    return n;
}

// Lo de dentro de `Nombre { ... }`, con el `{` todavia sin comer.
fn cuerpo_literal_struct(e: mut Estado, nombre: view, l: usize) -> Nodo ! {
    try espera(e, "simbolo", "{");
    var n = rama("literal_struct", l);
    empujar(n.texto, nombre);
    while !es(e, "simbolo", "}") {
        let campo = try espera(e, "ident", "");
        try espera(e, "simbolo", ":");
        var c = rama("campo", l);
        empujar(c.texto, campo);
        let x = try expresion(e);
        anadir(c.hijos, x);
        anadir(n.hijos, c);
        if !acepta(e, "simbolo", ",") { break; }
    }
    try espera(e, "simbolo", "}");
    return n;
}

fn primario(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);
    let k = e.i;

    // `fn[a, b](x: usize) -> bool { ... }`: una clausura.
    if es(e, "palabra", "fn") {
        avanzar(e);
        var n = rama("cierre", l);
        if acepta(e, "simbolo", "[") {
            if !es(e, "simbolo", "]") {
                while true {
                    let cap = try espera(e, "ident", "");
                    anadir(n.hijos, hoja("captura", cap, l));
                    if !acepta(e, "simbolo", ",") { break; }
                }
            }
            try espera(e, "simbolo", "]");
        }
        try espera(e, "simbolo", "(");
        try parametros(e, n, l);
        try espera(e, "simbolo", ")");
        if acepta(e, "simbolo", "->") {
            let t = try tipo(e);
            var r = rama("retorno_tipo", l);
            empujar(r.texto, t);
            anadir(n.hijos, r);
        }
        if acepta(e, "simbolo", "!") {
            anadir(n.hijos, hoja("falible", "", l));
        }
        let cuerpo = try bloque(e);
        anadir(n.hijos, cuerpo);
        return n;
    }

    // `if c { a } else { b }` como valor: cada rama es una expresion suelta.
    if es(e, "palabra", "if") {
        avanzar(e);
        var n = rama("si_expr", l);
        let c = try expresion(e);
        anadir(n.hijos, c);
        try espera(e, "simbolo", "{");
        let a = try expresion(e);
        anadir(n.hijos, a);
        try espera(e, "simbolo", "}");
        if !acepta(e, "palabra", "else") {
            error_aqui(e, "un `if` que da un valor necesita `else`: sin el no habria valor cuando la condicion es falsa");
            falla "sintaxis";
        }
        try espera(e, "simbolo", "{");
        let b = try expresion(e);
        anadir(n.hijos, b);
        try espera(e, "simbolo", "}");
        return n;
    }

    if es(e, "palabra", "match") { return try match_(e); }

    if es(e, "entero", "") {
        avanzar(e);
        let _v = try entero_literal(e, k);
        return hoja("entero", vista(e.toks[k].valor), l);
    }
    if es(e, "decimal", "") {
        let v = try espera(e, "decimal", "");
        return hoja("decimal", v, l);
    }
    if es(e, "interpolada", "") {
        let v = try espera(e, "interpolada", "");
        var n = rama("interpolada", l);
        empujar(n.texto, vista(v));
        // Los huecos se analizan aqui: dentro de las llaves vale cualquier
        // expresion. El texto crudo se guarda entero para poder sacar
        // despues los trozos literales, que no son nodos.
        try huecos_de(e, vista(v), n, k);
        return n;
    }
    if es(e, "cadena", "") {
        let v = try espera(e, "cadena", "");
        return hoja("cadena", v, l);
    }
    if es(e, "palabra", "true") || es(e, "palabra", "false") {
        let v = nuevo(valor_en(e, 0));
        avanzar(e);
        return hoja("booleano", v, l);
    }
    if acepta(e, "simbolo", "[") {
        var n = rama("literal_lista", l);
        if !es(e, "simbolo", "]") {
            while true {
                let x = try expresion(e);
                anadir(n.hijos, x);
                if !acepta(e, "simbolo", ",") { break; }
            }
        }
        try espera(e, "simbolo", "]");
        return n;
    }

    if es(e, "ident", "") {
        let nombre = nuevo(valor_en(e, 0));
        avanzar(e);

        // `txt.palabras(v)`: nombre calificado por el modulo de donde viene.
        if tiene(e.alias, vista(nombre)) && es(e, "simbolo", ".") {
            avanzar(e);
            let miembro = try espera(e, "ident", "");
            let completo = $"{nombre}.{miembro}";
            if es(e, "simbolo", "{") { return try cuerpo_literal_struct(e, vista(completo), l); }
            try espera(e, "simbolo", "(");
            return try cuerpo_llamada(e, vista(completo), l);
        }

        // Un literal de struct: solo si el nombre es de un struct conocido.
        if tiene(e.structs, vista(nombre)) && es(e, "simbolo", "{") {
            return try cuerpo_literal_struct(e, vista(nombre), l);
        }

        // `Figura.Circulo(2.0)`: construir una variante.
        if tiene(e.enums, vista(nombre)) && es(e, "simbolo", ".") {
            avanzar(e);
            let cual = try espera(e, "ident", "");
            var n = rama("enum_lit", l);
            empujar(n.texto, nombre);
            empujar(n.texto, ".");
            empujar(n.texto, cual);
            if acepta(e, "simbolo", "(") {
                if !es(e, "simbolo", ")") {
                    while true {
                        let x = try expresion(e);
                        anadir(n.hijos, x);
                        if !acepta(e, "simbolo", ",") { break; }
                    }
                }
                try espera(e, "simbolo", ")");
            }
            return n;
        }

        if acepta(e, "simbolo", "(") { return try cuerpo_llamada(e, vista(nombre), l); }
        return hoja("variable", nombre, l);
    }

    if acepta(e, "simbolo", "(") {
        let dentro = try expresion(e);
        try espera(e, "simbolo", ")");
        return dentro;
    }

    error_aqui(e, "se esperaba una expresion");
    falla "sintaxis";
}

fn postfijo(e: mut Estado) -> Nodo ! {
    var n = try primario(e);
    while true {
        let l = linea_actual(e);
        if acepta(e, "simbolo", ".") {
            let campo = try espera(e, "ident", "");
            var p = rama("campo", l);
            empujar(p.texto, campo);
            anadir(p.hijos, n);
            n = p;
            continue;
        }
        if acepta(e, "simbolo", "[") {
            let idx = try expresion(e);
            try espera(e, "simbolo", "]");
            var p = rama("indice", l);
            anadir(p.hijos, n);
            anadir(p.hijos, idx);
            n = p;
            continue;
        }
        break;
    }
    return n;
}

fn unario(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);
    if es(e, "palabra", "try") {
        avanzar(e);
        var n = rama("try", l);
        let dentro = try unario(e);
        anadir(n.hijos, dentro);
        return n;
    }
    if es(e, "simbolo", "!") || es(e, "simbolo", "-") || es(e, "simbolo", "~") {
        let op = nuevo(valor_en(e, 0));
        avanzar(e);
        var n = rama("unaria", l);
        empujar(n.texto, op);
        let dentro = try unario(e);
        anadir(n.hijos, dentro);
        return n;
    }
    return try postfijo(e);
}

// Un nivel de precedencia: `sub` a la izquierda, y mientras el simbolo
// actual este en `ops`, se junta. `ops` viene como texto separado por
// espacios; comparar asi evita repetir la misma funcion diez veces.
fn en_lista(ops: view, sep: usize, cual: view) -> bool {
    var desde = 0;
    var i = 0;
    while i <= largo(ops) {
        var corta = true;
        if i < largo(ops) { corta = byte(ops, i) == sep; }
        if corta {
            if igual(rebanar(ops, desde, i), cual) { return true; }
            desde = i + 1;
        }
        i = i + 1;
    }
    return false;
}

fn nivel(e: mut Estado, ops: view, grado: usize) -> Nodo ! {
    var izq = try siguiente_nivel(e, grado);
    var sigue = true;
    while sigue {
        if !es(e, "simbolo", "") || !en_lista(ops, 32, valor_en(e, 0)) {
            sigue = false;
        } else {
            let l = linea_actual(e);
            let op = nuevo(valor_en(e, 0));
            avanzar(e);
            let der = try siguiente_nivel(e, grado);
            var n = rama("binaria", l);
            empujar(n.texto, op);
            anadir(n.hijos, izq);
            anadir(n.hijos, der);
            izq = n;
        }
    }
    return izq;
}

fn siguiente_nivel(e: mut Estado, grado: usize) -> Nodo ! {
    // `&&` ata mas que `||`: `a || b && c` es `a || (b && c)`.
    if grado == 0 { return try nivel(e, "||", 1); }
    if grado == 1 { return try nivel(e, "&&", 2); }
    if grado == 2 { return try nivel(e, "== !=", 3); }
    if grado == 3 { return try nivel(e, "< <= > >=", 4); }
    // Los bits atan MAS que las comparaciones, no menos: `a & b == c` es
    // `(a & b) == c`, no lo que hace C.
    if grado == 4 { return try nivel(e, "|", 5); }
    if grado == 5 { return try nivel(e, "^", 6); }
    if grado == 6 { return try nivel(e, "&", 7); }
    if grado == 7 { return try nivel(e, "<< >>", 8); }
    if grado == 8 { return try nivel(e, "+ - +? -?", 9); }
    if grado == 9 { return try nivel(e, "* / % *? /?", 10); }
    return try conversion(e);
}

// `x como u8`, `x como? u8`: ata mas que cualquier binario.
fn conversion(e: mut Estado) -> Nodo ! {
    var izq = try unario(e);
    while es(e, "ident", "como") {
        let l = linea_actual(e);
        avanzar(e);
        var n = rama("conversion", l);
        if acepta(e, "simbolo", "?") { empujar(n.texto, "?"); }
        let t = try tipo(e);
        empujar(n.texto, t);
        anadir(n.hijos, izq);
        izq = n;
    }
    return izq;
}

fn expresion(e: mut Estado) -> Nodo ! {
    let n = try siguiente_nivel(e, 0);
    if es(e, "palabra", "sino") {
        let l = linea_actual(e);
        avanzar(e);
        let alt = try siguiente_nivel(e, 0);
        var s = rama("sino", l);
        anadir(s.hijos, n);
        anadir(s.hijos, alt);
        return s;
    }
    return n;
}

// ------------------------------------------------------------------
// Sentencias
// ------------------------------------------------------------------

fn bloque(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);
    try espera(e, "simbolo", "{");
    var n = rama("bloque", l);
    while !es(e, "simbolo", "}") {
        if es(e, "fin", "") {
            error_aqui(e, "bloque sin cerrar");
            falla "sintaxis";
        }
        let st = try sentencia(e);
        anadir(n.hijos, st);
    }
    try espera(e, "simbolo", "}");
    return n;
}

fn es_lugar(n: &Nodo) -> bool {
    let c = vista(n.clase);
    return igual(c, "variable") || igual(c, "campo") || igual(c, "indice");
}

fn sentencia(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);
    let k = e.i;

    if es(e, "palabra", "let") || es(e, "palabra", "var") {
        let clave = nuevo(valor_en(e, 0));
        avanzar(e);
        let nombre = try espera(e, "ident", "");
        // El tipo es opcional: casi siempre se deduce del valor.
        var t = vacio();
        if acepta(e, "simbolo", ":") {
            let escrito = try tipo(e);
            t = nuevo(escrito);
        }
        try espera(e, "simbolo", "=");
        var n = rama("declaracion", l);
        empujar(n.texto, clave);
        empujar(n.texto, " ");
        empujar(n.texto, nombre);
        if largo(t) > 0 {
            empujar(n.texto, ": ");
            empujar(n.texto, t);
        }
        let v = try expresion(e);
        anadir(n.hijos, v);
        try espera(e, "simbolo", ";");
        return n;
    }

    if es(e, "palabra", "if") {
        avanzar(e);
        var n = rama("si", l);
        let cond = try expresion(e);
        anadir(n.hijos, cond);
        let entonces = try bloque(e);
        anadir(n.hijos, entonces);
        if acepta(e, "palabra", "else") {
            if es(e, "simbolo", "{") {
                let sino_b = try bloque(e);
                anadir(n.hijos, sino_b);
            } else {
                // `else if`: la rama es un bloque con ese `if` dentro, que es
                // lo que significa y lo que escribe el C. Asi nadie de detras
                // tiene que saber que la rama podia no ser un bloque.
                let sino_s = try sentencia(e);
                var envuelta = rama("bloque", sino_s.linea);
                anadir(envuelta.hijos, sino_s);
                anadir(n.hijos, envuelta);
            }
        }
        return n;
    }

    if es(e, "palabra", "for") {
        avanzar(e);
        var n = rama("para", l);
        let uno = try espera(e, "ident", "");
        empujar(n.texto, uno);
        if acepta(e, "simbolo", ",") {
            let dos = try espera(e, "ident", "");
            empujar(n.texto, ", ");
            empujar(n.texto, dos);
        }
        try espera(e, "palabra", "en");
        let coleccion = try expresion(e);
        anadir(n.hijos, coleccion);
        let cuerpo = try bloque(e);
        anadir(n.hijos, cuerpo);
        return n;
    }

    if es(e, "palabra", "break") {
        avanzar(e);
        try espera(e, "simbolo", ";");
        return hoja("romper", "", l);
    }

    if es(e, "palabra", "continue") {
        avanzar(e);
        try espera(e, "simbolo", ";");
        return hoja("continuar", "", l);
    }

    if es(e, "palabra", "while") {
        avanzar(e);
        var n = rama("mientras", l);
        let cond = try expresion(e);
        anadir(n.hijos, cond);
        let cuerpo = try bloque(e);
        anadir(n.hijos, cuerpo);
        return n;
    }

    // Un `match` suelto mira y hace: no lleva `;` detras, como no lo llevan
    // `if` ni `while`. El que da un valor va detras de un `return` o un `=`.
    if es(e, "palabra", "match") {
        var n = rama("expresion", l);
        let m = try match_(e);
        anadir(n.hijos, m);
        return n;
    }

    if es(e, "palabra", "falla") {
        avanzar(e);
        if es(e, "simbolo", "(") {
            // Aqui Python no dice lo que encontro: dice como se escribe.
            if largo(e.error) == 0 {
                e.error = $"{e.archivo}:{l}: `falla` no lleva parentesis; se escribe `falla \"el motivo\";`";
            }
            falla "sintaxis";
        }
        let motivo = try espera(e, "cadena", "");
        try espera(e, "simbolo", ";");
        return hoja("falla", motivo, l);
    }

    if es(e, "palabra", "return") {
        avanzar(e);
        var n = rama("retorno", l);
        if !es(e, "simbolo", ";") {
            let v = try expresion(e);
            anadir(n.hijos, v);
        }
        try espera(e, "simbolo", ";");
        return n;
    }

    // asignacion o expresion suelta
    let izq = try expresion(e);
    if acepta(e, "simbolo", "=") {
        var n = rama("asignacion", l);
        let der = try expresion(e);
        try espera(e, "simbolo", ";");
        if !es_lugar(izq) {
            error_en(e, "a la izquierda de `=` tiene que haber una variable, un campo o un elemento", k);
            falla "sintaxis";
        }
        anadir(n.hijos, izq);
        anadir(n.hijos, der);
        return n;
    }
    try espera(e, "simbolo", ";");
    var n = rama("expresion", l);
    anadir(n.hijos, izq);
    return n;
}

// ------------------------------------------------------------------
// Declaraciones de alto nivel
// ------------------------------------------------------------------

// `<T>`, `<A, B>`, `<T: numero>`: igual para `fn` y `struct`. Con
// `restricciones`, cuelga cada una en el nodo; un struct las acepta pero no
// las guarda, como el original.
fn lista_tipo_params(e: mut Estado, n: mut Nodo, de_quien: view, l: usize,
    restricciones: bool) ! {
    var vistos: mapa<str, usize> = [];
    if !acepta(e, "simbolo", "<") { return; }
    while true {
        let tp = try espera(e, "ident", "");
        if es_tipo_basico(vista(tp)) {
            error_aqui(e, $"`{tp}` ya es un tipo del lenguaje: un parametro de tipo necesita otro nombre");
            falla "sintaxis";
        }
        if tiene(e.structs, vista(tp)) {
            error_aqui(e, $"`{tp}` ya es un struct: un parametro de tipo necesita otro nombre");
            falla "sintaxis";
        }
        if tiene(vistos, vista(tp)) {
            error_aqui(e, $"`{tp}` esta repetido en `{de_quien}<...>`");
            falla "sintaxis";
        }
        poner(vistos, vista(tp), 1);
        poner(e.tipo_params, vista(tp), 1);
        anadir(n.hijos, hoja("tipo_param", vista(tp), l));
        if acepta(e, "simbolo", ":") {
            let r = try espera(e, "ident", "");
            let rv = vista(r);
            if !igual(rv, "decimal") && !igual(rv, "entero") && !igual(rv, "igualable")
            && !igual(rv, "numero") && !igual(rv, "ordenable") && !igual(rv, "texto") {
                error_aqui(e, $"`{r}` no es una restriccion; hay `decimal`, `entero`, `igualable`, `numero`, `ordenable`, `texto`");
                falla "sintaxis";
            }
            if restricciones { anadir(n.hijos, hoja("restriccion", rv, l)); }
        }
        if !acepta(e, "simbolo", ",") { break; }
    }
    try espera(e, "simbolo", ">");
    return;
}

fn declaracion(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);
    let k = e.i;

    if es(e, "palabra", "struct") {
        avanzar(e);
        let nombre = try espera(e, "ident", "");
        var n = rama("struct", l);
        empujar(n.texto, nombre);
        e.tipo_params = [];
        try lista_tipo_params(e, n, vista(nombre), l, false);
        try espera(e, "simbolo", "{");
        while !es(e, "simbolo", "}") {
            if es(e, "fin", "") {
                error_aqui(e, "struct sin cerrar");
                falla "sintaxis";
            }
            let campo = try espera(e, "ident", "");
            try espera(e, "simbolo", ":");
            let t = try tipo(e);
            var c = rama("campo_def", linea_actual(e));
            empujar(c.texto, campo);
            empujar(c.texto, ": ");
            empujar(c.texto, t);
            anadir(n.hijos, c);
            if !acepta(e, "simbolo", ",") { break; }
        }
        try espera(e, "simbolo", "}");
        e.tipo_params = [];
        return n;
    }

    // `externo "math.h" { fn sqrt(x: f64) -> f64; }`: la puerta a C. Las
    // firmas no llevan cuerpo, y cada una sale como una `fn` mas, marcada.
    if es(e, "palabra", "externo") {
        avanzar(e);
        let cabecera = try espera(e, "cadena", "");
        var n = rama("externo", l);
        empujar(n.texto, cabecera);
        try espera(e, "simbolo", "{");
        while !es(e, "simbolo", "}") {
            if es(e, "fin", "") {
                error_aqui(e, "`externo` sin cerrar");
                falla "sintaxis";
            }
            let fl = linea_actual(e);
            let kf = e.i;
            try espera(e, "palabra", "fn");
            let nombre = try espera(e, "ident", "");
            if es(e, "simbolo", "<") {
                error_en(e, "una funcion de C no puede ser generica: C no tiene con que", kf);
                falla "sintaxis";
            }
            var f = rama("fn", fl);
            empujar(f.texto, nombre);
            anadir(f.hijos, hoja("externa", vista(cabecera), fl));
            try espera(e, "simbolo", "(");
            if !es(e, "simbolo", ")") {
                while true {
                    let pn = try espera(e, "ident", "");
                    try espera(e, "simbolo", ":");
                    let pt = try tipo(e);
                    var pp = rama("param", fl);
                    empujar(pp.texto, pn);
                    empujar(pp.texto, ": ");
                    empujar(pp.texto, vista(pt));
                    anadir(f.hijos, pp);
                    if !acepta(e, "simbolo", ",") { break; }
                }
            }
            try espera(e, "simbolo", ")");
            if acepta(e, "simbolo", "->") {
                let r = try tipo(e);
                anadir(f.hijos, hoja("retorno_tipo", vista(r), fl));
            }
            if es(e, "simbolo", "!") {
                error_en(e, "una funcion de C no falla como las de Tcode: devuelve lo que devuelva y lo miras tu", kf);
                falla "sintaxis";
            }
            try espera(e, "simbolo", ";");
            anadir(n.hijos, f);
        }
        try espera(e, "simbolo", "}");
        if largo(n.hijos) == 0 {
            error_en(e, "un `externo` vacio no trae nada", k);
            falla "sintaxis";
        }
        return n;
    }

    if es(e, "palabra", "enum") {
        avanzar(e);
        let nombre = try espera(e, "ident", "");
        var n = rama("enum", l);
        empujar(n.texto, nombre);
        try espera(e, "simbolo", "{");
        var vistos: mapa<str, usize> = [];
        while !es(e, "simbolo", "}") {
            if es(e, "fin", "") {
                error_aqui(e, "enum sin cerrar");
                falla "sintaxis";
            }
            let vn = try espera(e, "ident", "");
            if tiene(vistos, vista(vn)) {
                error_aqui(e, $"`{nombre}.{vn}` esta declarada dos veces");
                falla "sintaxis";
            }
            poner(vistos, vista(vn), 1);
            var v = rama("variante", linea_actual(e));
            empujar(v.texto, vn);
            if acepta(e, "simbolo", "(") {
                while true {
                    let t = try tipo(e);
                    anadir(v.hijos, hoja("lleva", vista(t), linea_actual(e)));
                    if !acepta(e, "simbolo", ",") { break; }
                }
                try espera(e, "simbolo", ")");
            }
            anadir(n.hijos, v);
            if !acepta(e, "simbolo", ",") { break; }
        }
        try espera(e, "simbolo", "}");
        if largo(n.hijos) == 0 {
            error_aqui(e, $"`enum {nombre}` no declara ninguna variante: un valor que no puede tomar ninguna forma no sirve para nada");
            falla "sintaxis";
        }
        return n;
    }

    try espera(e, "palabra", "fn");
    let nombre = try espera(e, "ident", "");
    var n = rama("fn", l);
    empujar(n.texto, nombre);

    // `fn primeras<T>(...)`: parametros de tipo. Dentro de la firma y del
    // cuerpo, `T` es un tipo mas.
    e.tipo_params = [];
    try lista_tipo_params(e, n, vista(nombre), l, true);

    try espera(e, "simbolo", "(");
    try parametros(e, n, l);
    try espera(e, "simbolo", ")");

    if acepta(e, "simbolo", "->") {
        let t = try tipo(e);
        var r = rama("retorno_tipo", l);
        empujar(r.texto, t);
        anadir(n.hijos, r);
    }
    if acepta(e, "simbolo", "!") {
        anadir(n.hijos, hoja("falible", "", l));
    }

    let cuerpo = try bloque(e);
    anadir(n.hijos, cuerpo);
    e.tipo_params = [];
    return n;
}

fn recoger_structs(toks: &lista<Token>) -> mapa<str, usize> {
    return recoger_tras(toks, "struct");
}

fn recoger_enums(toks: &lista<Token>) -> mapa<str, usize> {
    return recoger_tras(toks, "enum");
}

// Los nombres que van detras de una palabra: `struct Punto` -> `Punto`.
fn recoger_tras(toks: &lista<Token>, palabra: view) -> mapa<str, usize> {
    var m: mapa<str, usize> = [];
    var i = 0;
    while i + 1 < largo(toks) {
        if igual(vista(toks[i].valor), palabra) {
            if igual(vista(toks[i + 1].tipo), "ident") {
                poner(m, vista(toks[i + 1].valor), 1);
            }
        }
        i = i + 1;
    }
    return m;
}

// El directorio de una ruta, sin la barra final. `a/b/c.t` -> `a/b`.
fn carpeta(ruta: view) -> str {
    var corte = 0;
    var i = 0;
    while i < largo(ruta) {
        if byte(ruta, i) == 47 { corte = i; }
        i = i + 1;
    }
    return nuevo(rebanar(ruta, 0, corte));
}

// Los structs que ve un archivo: los suyos y los de lo que trae con `usar`.
//
// El parser de Python los recibe del cargador de modulos; aqui se leen las
// dependencias directamente. Con una vuelta basta: un struct que llega de
// tercera mano no se usa como literal sin nombrarlo antes.
// Un modulo que este archivo usa, ya leido, con el alias que le dio quien
// lo usa: `usar "lib/tipar.t" como I;` -> alias `I`, y sus funciones se
// llaman `I.algo` desde aqui.
struct Usado {
    alias: str,
    // El archivo del que sale, tal como se encontro.
    ruta: str,
    arbol: Nodo,
}

// Los modulos que este archivo pide, analizados. Un solo nivel: lo que usen
// ellos a su vez no se sigue, porque desde aqui no se nombra.
fn modulos_usados(ruta: view, toks: &lista<Token>) -> lista<Usado> {
    var salida: lista<Usado> = [];
    let dir = carpeta(ruta);
    var i = 0;
    while i + 1 < largo(toks) {
        if igual(vista(toks[i].valor), "usar") {
            if igual(vista(toks[i + 1].tipo), "cadena") {
                let pedido = nuevo(toks[i + 1].valor);
                var alias = vacio();
                if i + 3 < largo(toks) {
                    if igual(vista(toks[i + 2].valor), "como") {
                        alias = nuevo(toks[i + 3].valor);
                    }
                }
                var candidatos: lista<str> = [];
                var junto = nuevo(vista(dir));
                if largo(junto) > 0 { empujar(junto, "/"); }
                empujar(junto, vista(pedido));
                anadir(candidatos, copiar(junto));
                empujar(junto, ".t");
                anadir(candidatos, junto);
                anadir(candidatos, copiar(pedido));
                var suelto = copiar(pedido);
                empujar(suelto, ".t");
                anadir(candidatos, suelto);

                for c en candidatos {
                    let texto = leer_archivo(vista(c)) sino vacio();
                    if largo(texto) == 0 { continue; }
                    let otros = analizar(vista(texto)) sino [];
                    if largo(otros) == 0 { break; }
                    let nombres = visibles(vista(c), otros, "struct");
                    let formas = visibles(vista(c), otros, "enum");
                    var e = estado_de(otros, vista(c), nombres, formas);
                    let arbol = programa(e) sino rama("programa", 1);
                    anadir(salida, Usado { alias: copiar(alias),
                            ruta: copiar(c), arbol: arbol });
                    break;
                }
            }
        }
        i = i + 1;
    }
    return salida;
}

fn structs_visibles(ruta: view, toks: &lista<Token>) -> mapa<str, usize> {
    return visibles(ruta, toks, "struct");
}

fn enums_visibles(ruta: view, toks: &lista<Token>) -> mapa<str, usize> {
    return visibles(ruta, toks, "enum");
}

// Los nombres declarados tras `palabra`, aqui y en lo que este archivo usa.
fn visibles(ruta: view, toks: &lista<Token>, palabra: view) -> mapa<str, usize> {
    var m = recoger_tras(toks, palabra);
    let dir = carpeta(ruta);

    var i = 0;
    while i + 1 < largo(toks) {
        if igual(vista(toks[i].valor), "usar") {
            if igual(vista(toks[i + 1].tipo), "cadena") {
                let pedido = nuevo(toks[i + 1].valor);
                var candidatos: lista<str> = [];
                // Junto al archivo que lo pide, y desde donde se ejecuta.
                var junto = nuevo(vista(dir));
                if largo(junto) > 0 { empujar(junto, "/"); }
                empujar(junto, vista(pedido));
                anadir(candidatos, copiar(junto));
                empujar(junto, ".t");
                anadir(candidatos, junto);
                anadir(candidatos, copiar(pedido));
                var suelto = copiar(pedido);
                empujar(suelto, ".t");
                anadir(candidatos, suelto);

                for c en candidatos {
                    let texto = leer_archivo(vista(c)) sino vacio();
                    if largo(texto) > 0 {
                        let otros = analizar(vista(texto)) sino [];
                        for nombre en recoger_tras(otros, palabra) {
                            poner(m, vista(nombre), 1);
                        }
                        break;
                    }
                }
            }
        }
        i = i + 1;
    }
    return m;
}

fn programa(e: mut Estado) -> Nodo ! {
    var raiz = rama("programa", 1);
    while acepta(e, "palabra", "usar") {
        let ruta = try espera(e, "cadena", "");
        // `usar "x" como a;`: `como` no es palabra reservada, es un ident.
        if es(e, "ident", "como") {
            avanzar(e);
            let a = try espera(e, "ident", "");
            anadir(raiz.hijos, hoja("alias", a, linea_actual(e)));
            poner(e.alias, a, 1);
        }
        try espera(e, "simbolo", ";");
        anadir(raiz.hijos, hoja("usar", ruta, linea_actual(e)));
    }
    while !igual(tipo_en(e, 0), "fin") {
        if es(e, "palabra", "usar") {
            error_aqui(e, "los `usar` van todos al principio del archivo");
            falla "sintaxis";
        }
        let d = try declaracion(e);
        anadir(raiz.hijos, d);
    }
    return raiz;
}

// ------------------------------------------------------------------
// Programa
// ------------------------------------------------------------------
