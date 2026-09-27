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
    // Unico en su archivo, y 0 en lo que no sale del parser. Con el nombre
    // de la funcion donde esta, es como el comprobador le dice al generador
    // de que tipo es cada expresion.
    id: usize,
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
    // Cuanto se ha bajado en el arbol hasta aqui: ver `limite_hondura`.
    hondura: usize,
}

// Un estado nuevo sobre unos tokens.
fn estado_de(toks: lista<Token>, archivo: view, structs: mapa<str, usize>,
    enums: mapa<str, usize>) -> Estado {
    return Estado { toks: toks, i: 0, alias: [], structs: structs, enums: enums,
        archivo: nuevo(archivo), error: vacio(), tipo_params: [], hondura: 0 };
}

// Lo mas hondo que puede ser el arbol: anidamiento, y cadenas de operadores,
// campos o `como`. Todo lo que viene despues es recursivo, y sin un limite un
// archivo con cien mil parentesis agotaria la pila. Es el mismo que en el
// parser de Python.
fn limite_hondura() -> usize { return 5000; }

// Un nivel mas de hondura en el arbol.
fn entrar(e: mut Estado) ! {
    e.hondura = e.hondura + 1;
    if e.hondura > limite_hondura() {
        let tope = limite_hondura();
        error_aqui(e, $"el programa anida mas de {tope} niveles; parte la expresion o el bloque en trozos");
        falla "sintaxis";
    }
}

// ------------------------------------------------------------------
// Construccion del arbol. Cada hijo se MUEVE dentro del padre: no hay
// copias, y el arbol entero se libera solo al salir del bloque.
// ------------------------------------------------------------------

fn hoja(clase: view, texto: view, linea: usize) -> Nodo {
    return Nodo { clase: nuevo(clase), texto: nuevo(texto), linea: linea,
        hijos: [], id: 0 };
}

fn rama(clase: view, linea: usize) -> Nodo {
    return Nodo { clase: nuevo(clase), texto: vacio(), linea: linea,
        hijos: [], id: 0 };
}

// Un numero a cada nodo, en preorden.
fn numerar(n: mut Nodo, cuenta: mut usize) {
    cuenta = cuenta + 1;
    n.id = cuenta;
    var i = 0;
    while i < n.hijos.largo() {
        numerar(n.hijos[i], cuenta);
        i = i + 1;
    }
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
    if n.texto.largo() > 0 {
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
    if j >= e.toks.largo() { return "fin"; }
    return vista(e.toks[j].tipo);
}

fn valor_en(e: &Estado, salto: usize) -> view {
    let j = e.i + salto;
    if j >= e.toks.largo() { return ""; }
    return vista(e.toks[j].valor);
}

fn linea_actual(e: &Estado) -> usize {
    if e.i >= e.toks.largo() { return 0; }
    return e.toks[e.i].linea;
}

fn es(e: &Estado, tipo: view, valor: view) -> bool {
    if !igual(tipo_en(e, 0), tipo) { return false; }
    if valor.largo() == 0 { return true; }
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
    if k >= e.toks.largo() || e.toks[k].tipo == "fin" {
        return nuevo("fin de archivo");
    }
    var valor = copiar(e.toks[k].valor);
    let clase = vista(e.toks[k].tipo);
    // Python guarda las cadenas ya descifradas.
    if clase == "cadena" || clase == "interpolada" {
        valor = descifrado(valor, clase == "interpolada");
    }
    if caracteres(valor) > 72 {
        valor = $"{primeros(vista(valor), 69)}...";
    }
    return repr_texto(valor);
}

// Los caracteres de un texto UTF-8, contando cada `\xNN` descifrado como uno.
fn caracteres(t: view) -> usize {
    var n = 0;
    var i = 0;
    while i < t.largo() {
        let b = byte(t, i);
        if b == 1 && i + 2 < t.largo() {
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
    while i < t.largo() {
        let b = byte(t, i);
        let empieza = b < 128 || b >= 192;
        if empieza && n == cuantos { break; }
        if empieza { n = n + 1; }
        if b == 1 && i + 2 < t.largo() {
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
    while i < t.largo() {
        let b = byte(t, i);
        // Un hueco queda crudo, como lo deja Python: lo lee despues el lexer
        // del hueco, que es quien resuelve sus escapes.
        if interpolada && b == 123 {
            if i + 1 < t.largo() && byte(t, i + 1) == 123 {
                r.empujar("{{");
                i = i + 2;
                continue;
            }
            let cierre = cierre_de_hueco(t, i + 1);
            var hasta = cierre + 1;
            if hasta > t.largo() { hasta = t.largo(); }
            r.empujar(rebanar(t, i, hasta));
            i = hasta;
            continue;
        }
        if b == 92 && i + 1 < t.largo() {
            let d = byte(t, i + 1);
            if d == 110 { empujar_byte(r, 10); i = i + 2; continue; }
            if d == 116 { empujar_byte(r, 9); i = i + 2; continue; }
            if d == 48 { empujar_byte(r, 0); i = i + 2; continue; }
            if d == 120 && i + 3 < t.largo() {
                empujar_byte(r, 1);
                r.empujar(rebanar(t, i + 2, i + 4));
                i = i + 4;
                continue;
            }
            // `\{` y `\}` en una interpolada son una llave escrita: quedan
            // como `{{` y `}}`, que no abren ni cierran un hueco.
            if interpolada && (d == 123 || d == 125) {
                r.empujar(rebanar(t, i + 1, i + 2));
                r.empujar(rebanar(t, i + 1, i + 2));
                i = i + 2;
                continue;
            }
            r.empujar(rebanar(t, i + 1, i + 2));
            i = i + 2;
            continue;
        }
        r.empujar(rebanar(t, i, i + 1));
        i = i + 1;
    }
    return r;
}

// Deja el primer error: `archivo:linea: mensaje, se encontro 'x'`, sobre el
// token `k`. Quien lo llama falla justo despues.
fn error_en(e: mut Estado, mensaje: view, k: usize) {
    if e.error.largo() > 0 { return; }
    var linea = 0;
    if k < e.toks.largo() { linea = e.toks[k].linea; }
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
    if valor == ">" {
        if es(e, "simbolo", ">>") {
            e.toks[e.i].valor = nuevo(">");
            return nuevo(">");
        }
    }
    let v = nuevo(valor_en(e, 0));
    if !es(e, tipo, valor) {
        var que = nuevo(valor);
        if que.largo() == 0 { que = nuevo(tipo); }
        let dicho = repr_texto(que);
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
    while i + 1 < texto_t.largo() && byte(texto_t, i) == 48 { i = i + 1; }
    let limpio = nuevo(rebanar(texto_t, i, texto_t.largo()));
    let tope = "18446744073709551615";
    if limpio.largo() > tope.largo()
    || (limpio.largo() == tope.largo() && menor(tope, limpio)) {
        error_en(e, "el literal entero no cabe en `u64`", k);
        falla "sintaxis";
    }
    return limpio;
}

fn es_tipo_basico(t: view) -> bool {
    return t == "str" || t == "view" || t == "bool" || t == "u8"
    || t == "u16" || t == "u32" || t == "u64" || t == "usize"
    || t == "i8" || t == "i16" || t == "i32" || t == "i64"
    || t == "f32" || t == "f64";
}

// ------------------------------------------------------------------
// Tipos
// ------------------------------------------------------------------

// Los argumentos de `Nombre<A, B>`, con el `<` ya comido.
fn argumentos_de_tipo(e: mut Estado, nombre: view) -> str ! {
    var t = nuevo(nombre);
    t.empujar("<");
    var primero = true;
    while true {
        let a = try tipo(e);
        if !primero { t.empujar(", "); }
        primero = false;
        t.empujar(a);
        if !acepta(e, "simbolo", ",") { break; }
    }
    try espera(e, "simbolo", ">");
    t.empujar(">");
    return t;
}

fn tipo(e: mut Estado) -> str ! {
    let k = e.i;
    // `&T` y `&mut T` como tipo.
    if acepta(e, "simbolo", "&") {
        var t = nuevo("&");
        if acepta(e, "palabra", "mut") { t.empujar("mut "); }
        let dentro = try tipo(e);
        t.empujar(dentro);
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
                if !primero { t.empujar(", "); }
                primero = false;
                t.empujar(a);
                if !acepta(e, "simbolo", ",") { break; }
            }
        }
        try espera(e, "simbolo", ")");
        t.empujar(")");
        if acepta(e, "simbolo", "->") {
            let r = try tipo(e);
            t.empujar(" -> ");
            t.empujar(r);
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
    && tipo_en(e, 1) == "simbolo" && valor_en(e, 1) == "." {
        var v = nuevo(valor_en(e, 0));
        avanzar(e);
        avanzar(e);
        let miembro = try espera(e, "ident", "");
        v.empujar(".");
        v.empujar(miembro);
        if acepta(e, "simbolo", "<") { return try argumentos_de_tipo(e, v); }
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
        if acepta(e, "simbolo", "<") { return try argumentos_de_tipo(e, v); }
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
    if es(e, "ident", "bloque") && valor_en(e, 1) == "<" {
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
        if n == "0" {
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
    n.hijos.anadir(v);
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
            if !tiene(e.enums, quien) {
                error_aqui(e, $"`{quien}` no es un enum");
                falla "sintaxis";
            }
            b.texto.empujar(quien);
            b.texto.empujar(".");
            b.texto.empujar(cual);
            try posiciones_patron(e, b);
        }
        // Una guarda: el brazo solo vale si ademas se cumple esto.
        if acepta(e, "palabra", "if") {
            var g = rama("guarda", linea_actual(e));
            let cond = try expresion(e);
            g.hijos.anadir(cond);
            b.hijos.anadir(g);
        }
        try espera(e, "simbolo", "->");
        brazos = brazos + 1;
        if es(e, "simbolo", "{") {
            let cuerpo = try bloque(e);
            b.hijos.anadir(cuerpo);
            n.hijos.anadir(b);
            let _coma = acepta(e, "simbolo", ",");
        } else {
            // Un brazo que da un valor es un `return` de esa expresion: por
            // dentro es lo mismo que un brazo con bloque, y asi el arbol no
            // tiene dos formas de decir la misma cosa.
            let x = try expresion(e);
            var r = rama("retorno", bl);
            r.hijos.anadir(x);
            b.hijos.anadir(r);
            n.hijos.anadir(b);
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

// `(a, _, 3, Forma.Otra(b))` detras de una forma, colgado de `n` en orden:
// un nombre es una hoja `atrapa` (tambien `_`), una forma anidada una rama
// `patron` con lo suyo dentro, y un literal una rama `literal`.
fn posiciones_patron(e: mut Estado, n: mut Nodo) ! {
    if !acepta(e, "simbolo", "(") { return; }
    if !es(e, "simbolo", ")") {
        while true {
            try posicion_patron(e, n);
            if !acepta(e, "simbolo", ",") { break; }
        }
    }
    try espera(e, "simbolo", ")");
    return;
}

fn posicion_patron(e: mut Estado, n: mut Nodo) ! {
    let l = linea_actual(e);
    if es(e, "ident", "") && tipo_en(e, 1) == "simbolo" && valor_en(e, 1) == "." {
        let quien = try espera(e, "ident", "");
        try espera(e, "simbolo", ".");
        let cual = try espera(e, "ident", "");
        if !tiene(e.enums, quien) {
            error_aqui(e, $"`{quien}` no es un enum");
            falla "sintaxis";
        }
        var p = rama("patron", l);
        p.texto = $"{quien}.{cual}";
        try posiciones_patron(e, p);
        n.hijos.anadir(p);
        return;
    }
    if es(e, "ident", "") {
        let nombre = try espera(e, "ident", "");
        n.hijos.anadir(hoja("atrapa", nombre, l));
        return;
    }
    if es(e, "entero", "") || es(e, "cadena", "") || es(e, "palabra", "true")
    || es(e, "palabra", "false")
    || (es(e, "simbolo", "-") && tipo_en(e, 1) == "entero") {
        var lit = rama("literal", l);
        let x = try unario(e);
        lit.hijos.anadir(x);
        n.hijos.anadir(lit);
        return;
    }
    error_aqui(e, "en un patron va un nombre, `_`, un literal o una forma");
    falla "sintaxis";
}

// Analiza lo que hay entre llaves y lo cuelga en orden. `{{` y `}}` son una
// llave escrita, no un hueco. `k` es el token de la cadena, al que apuntan
// los errores.
fn huecos_de(e: mut Estado, t: view, n: mut Nodo, k: usize) ! {
    // Python mira la cadena ya descifrada: un `\"` es una comilla.
    let texto_d = descifrado(t, true);
    let d = vista(texto_d);
    var i = 0;
    while i < d.largo() {
        let c = byte(d, i);
        if c == 123 && i + 1 < d.largo() && byte(d, i + 1) == 123 {
            i = i + 2;
            continue;
        }
        if c == 125 && i + 1 < d.largo() && byte(d, i + 1) == 125 {
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
        // El hueco llega crudo: sus cadenas se saltan enteras, que sus
        // llaves y sus escapes no son del hueco.
        let j = cierre_de_hueco(d, i + 1);
        if j >= d.largo() {
            error_en(e, "falta `}` en una cadena interpolada", k);
            falla "sintaxis";
        }
        let dentro = comillas_de_antes(recortar(rebanar(d, i + 1, j)));
        if dentro.largo() == 0 {
            error_en(e, "`{}` vacio en una cadena interpolada: pon dentro lo que quieras mostrar", k);
            falla "sintaxis";
        }
        // Lo de dentro esta en la linea de la cadena: sus errores tienen que
        // decirlo.
        var error_lex = vacio();
        let suyos = tokens_desde(dentro, e.archivo, n.linea, error_lex) sino [];
        if error_lex.largo() > 0 {
            if e.error.largo() == 0 { e.error = error_lex; }
            falla "sintaxis";
        }
        var sub = estado_de(suyos, e.archivo, copiar(e.structs), copiar(e.enums));
        sub.alias = copiar(e.alias);
        sub.tipo_params = copiar(e.tipo_params);
        sub.hondura = e.hondura;
        let x = expresion(sub) sino hoja("vacio", "", 0);
        if sub.error.largo() > 0 {
            if e.error.largo() == 0 { e.error = copiar(sub.error); }
            falla "sintaxis";
        }
        if !es(sub, "fin", "") {
            let dicho = repr_texto(dentro);
            error_en(e, $"sobra algo despues de la expresion {dicho} dentro de la cadena", k);
            falla "sintaxis";
        }
        var x_l = x;
        // Todo lo de dentro de un hueco esta en la linea de la cadena.
        poner_linea(x_l, n.linea);
        n.hijos.anadir(x_l);
        i = j + 1;
    }
    return;
}

// Antes, un hueco se leia ya descifrado, y sus cadenas se escribian
// `{f(\"x\")}`. Sigue valiendo: fuera de una cadena, `\"` es una comilla.
fn comillas_de_antes(h: view) -> str {
    var r = vacio();
    var i = 0;
    while i < h.largo() {
        let b = byte(h, i);
        if b == 34 || (b == 36 && i + 1 < h.largo() && byte(h, i + 1) == 34) {
            let fin = fin_de_texto(h, i);
            r.empujar(rebanar(h, i, fin));
            i = fin;
            continue;
        }
        if b == 92 && i + 1 < h.largo() && byte(h, i + 1) == 34 {
            r.empujar("\"");
            i = i + 2;
            continue;
        }
        r.empujar(rebanar(h, i, i + 1));
        i = i + 1;
    }
    return r;
}

// El lexer deja las cadenas crudas, con los escapes sin resolver: para el
// analisis lexico da igual. Aqui no da igual, porque lo que se escribe en el
// C son BYTES y lo que se cuenta son bytes. Asi que primero se descifra lo
// que puso quien escribio, y luego se vuelve a escapar para C.
fn desescapar(t: view) -> str {
    var r = vacio();
    var i = 0;
    while i < t.largo() {
        let c = byte(t, i);
        if c != 92 || i + 1 >= t.largo() {
            r.empujar(rebanar(t, i, i + 1));
            i = i + 1;
            continue;
        }
        let d = byte(t, i + 1);
        if d == 110 { empujar_byte(r, 10); i = i + 2; continue; }
        if d == 116 { empujar_byte(r, 9); i = i + 2; continue; }
        if d == 48 { empujar_byte(r, 0); i = i + 2; continue; }
        if d == 120 {
            // `\xNN`: un byte escrito en hexadecimal.
            if i + 3 < t.largo() {
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
        r.empujar(rebanar(t, i + 1, i + 2));
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
    while i < n.hijos.largo() {
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
        pp.texto.empujar(pn);
        pp.texto.empujar(": ");
        pp.texto.empujar(marca);
        pp.texto.empujar(t);
        n.hijos.anadir(pp);
        if !acepta(e, "simbolo", ",") { break; }
    }
    return;
}

// Los argumentos de una llamada, con el `(` ya comido.
fn cuerpo_llamada(e: mut Estado, nombre: view, l: usize) -> Nodo ! {
    var n = rama("llamada", l);
    n.texto.empujar(nombre);
    if !es(e, "simbolo", ")") {
        while true {
            let x = try expresion(e);
            n.hijos.anadir(x);
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
    n.texto.empujar(nombre);
    while !es(e, "simbolo", "}") {
        let campo = try espera(e, "ident", "");
        try espera(e, "simbolo", ":");
        var c = rama("campo", l);
        c.texto.empujar(campo);
        let x = try expresion(e);
        c.hijos.anadir(x);
        n.hijos.anadir(c);
        if !acepta(e, "simbolo", ",") { break; }
    }
    try espera(e, "simbolo", "}");
    return n;
}

fn primario(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);
    let k = e.i;

    // `fn[a, mut b](x: usize) -> bool { ... }`: una clausura. Lo que se
    // captura con `mut` lleva un hijo `mut`.
    if es(e, "palabra", "fn") {
        avanzar(e);
        var n = rama("cierre", l);
        if acepta(e, "simbolo", "[") {
            if !es(e, "simbolo", "]") {
                while true {
                    let con_mut = acepta(e, "palabra", "mut");
                    let cap = try espera(e, "ident", "");
                    var hc = hoja("captura", cap, l);
                    if con_mut { hc.hijos.anadir(hoja("mut", "", l)); }
                    n.hijos.anadir(hc);
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
            r.texto.empujar(t);
            n.hijos.anadir(r);
        }
        if acepta(e, "simbolo", "!") {
            n.hijos.anadir(hoja("falible", "", l));
        }
        let cuerpo = try bloque(e);
        n.hijos.anadir(cuerpo);
        return n;
    }

    // `if c { a } else { b }` como valor: cada rama es una expresion suelta.
    if es(e, "palabra", "if") {
        avanzar(e);
        var n = rama("si_expr", l);
        let c = try expresion(e);
        n.hijos.anadir(c);
        try espera(e, "simbolo", "{");
        let a = try expresion(e);
        n.hijos.anadir(a);
        try espera(e, "simbolo", "}");
        if !acepta(e, "palabra", "else") {
            error_aqui(e, "un `if` que da un valor necesita `else`: sin el no habria valor cuando la condicion es falsa");
            falla "sintaxis";
        }
        try espera(e, "simbolo", "{");
        let b = try expresion(e);
        n.hijos.anadir(b);
        try espera(e, "simbolo", "}");
        return n;
    }

    if es(e, "palabra", "match") { return try match_(e); }

    if es(e, "entero", "") {
        avanzar(e);
        let _v = try entero_literal(e, k);
        return hoja("entero", e.toks[k].valor, l);
    }
    if es(e, "decimal", "") {
        let v = try espera(e, "decimal", "");
        return hoja("decimal", v, l);
    }
    if es(e, "interpolada", "") {
        let v = try espera(e, "interpolada", "");
        var n = rama("interpolada", l);
        n.texto.empujar(v);
        // Los huecos se analizan aqui: dentro de las llaves vale cualquier
        // expresion. El texto crudo se guarda entero para poder sacar
        // despues los trozos literales, que no son nodos.
        try huecos_de(e, v, n, k);
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
                n.hijos.anadir(x);
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
        if tiene(e.alias, nombre) && es(e, "simbolo", ".") {
            avanzar(e);
            let miembro = try espera(e, "ident", "");
            let completo = $"{nombre}.{miembro}";
            if es(e, "simbolo", "{") { return try cuerpo_literal_struct(e, completo, l); }
            try espera(e, "simbolo", "(");
            return try cuerpo_llamada(e, completo, l);
        }

        // Un literal de struct: solo si el nombre es de un struct conocido.
        if tiene(e.structs, nombre) && es(e, "simbolo", "{") {
            return try cuerpo_literal_struct(e, nombre, l);
        }

        // `Figura.Circulo(2.0)`: construir una variante.
        if tiene(e.enums, nombre) && es(e, "simbolo", ".") {
            avanzar(e);
            let cual = try espera(e, "ident", "");
            var n = rama("enum_lit", l);
            n.texto.empujar(nombre);
            n.texto.empujar(".");
            n.texto.empujar(cual);
            if acepta(e, "simbolo", "(") {
                if !es(e, "simbolo", ")") {
                    while true {
                        let x = try expresion(e);
                        n.hijos.anadir(x);
                        if !acepta(e, "simbolo", ",") { break; }
                    }
                }
                try espera(e, "simbolo", ")");
            }
            return n;
        }

        if acepta(e, "simbolo", "(") { return try cuerpo_llamada(e, nombre, l); }
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
    let antes = e.hondura;
    while true {
        let l = linea_actual(e);
        if acepta(e, "simbolo", ".") {
            try entrar(e);
            let campo = try espera(e, "ident", "");
            // `xs.anadir(v)` es `anadir(xs, v)`: lo de delante del punto va
            // primero. Un alias de modulo o una variante ya se leyeron antes,
            // en `primario`.
            if acepta(e, "simbolo", "(") {
                let args = try cuerpo_llamada(e, campo, l);
                var llamada = rama("llamada", l);
                llamada.texto.empujar(campo);
                llamada.hijos.anadir(n);
                for a en args.hijos { llamada.hijos.anadir(copiar(a)); }
                n = llamada;
                continue;
            }
            var p = rama("campo", l);
            p.texto.empujar(campo);
            p.hijos.anadir(n);
            n = p;
            continue;
        }
        if acepta(e, "simbolo", "[") {
            try entrar(e);
            let idx = try expresion(e);
            try espera(e, "simbolo", "]");
            var p = rama("indice", l);
            p.hijos.anadir(n);
            p.hijos.anadir(idx);
            n = p;
            continue;
        }
        break;
    }
    e.hondura = antes;
    return n;
}

fn unario(e: mut Estado) -> Nodo ! {
    try entrar(e);
    let n = try unario_dentro(e);
    e.hondura = e.hondura - 1;
    return n;
}

fn unario_dentro(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);
    if es(e, "palabra", "try") {
        avanzar(e);
        var n = rama("try", l);
        let dentro = try unario(e);
        n.hijos.anadir(dentro);
        return n;
    }
    if es(e, "simbolo", "!") || es(e, "simbolo", "-") || es(e, "simbolo", "~") {
        let op = nuevo(valor_en(e, 0));
        avanzar(e);
        var n = rama("unaria", l);
        n.texto.empujar(op);
        let dentro = try unario(e);
        n.hijos.anadir(dentro);
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
    while i <= ops.largo() {
        var corta = true;
        if i < ops.largo() { corta = byte(ops, i) == sep; }
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
    let antes = e.hondura;
    var sigue = true;
    while sigue {
        if !es(e, "simbolo", "") || !en_lista(ops, 32, valor_en(e, 0)) {
            sigue = false;
        } else {
            let l = linea_actual(e);
            let op = nuevo(valor_en(e, 0));
            avanzar(e);
            try entrar(e);
            let der = try siguiente_nivel(e, grado);
            var n = rama("binaria", l);
            n.texto.empujar(op);
            n.hijos.anadir(izq);
            n.hijos.anadir(der);
            izq = n;
        }
    }
    e.hondura = antes;
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
    let antes = e.hondura;
    while es(e, "ident", "como") {
        let l = linea_actual(e);
        avanzar(e);
        try entrar(e);
        var n = rama("conversion", l);
        if acepta(e, "simbolo", "?") { n.texto.empujar("?"); }
        let t = try tipo(e);
        n.texto.empujar(t);
        n.hijos.anadir(izq);
        izq = n;
    }
    e.hondura = antes;
    return izq;
}

fn expresion(e: mut Estado) -> Nodo ! {
    let n = try siguiente_nivel(e, 0);
    if es(e, "palabra", "sino") {
        let l = linea_actual(e);
        avanzar(e);
        let alt = try siguiente_nivel(e, 0);
        var s = rama("sino", l);
        s.hijos.anadir(n);
        s.hijos.anadir(alt);
        return s;
    }
    return n;
}

// ------------------------------------------------------------------
// Sentencias
// ------------------------------------------------------------------

fn bloque(e: mut Estado) -> Nodo ! {
    try entrar(e);
    let n = try bloque_dentro(e);
    e.hondura = e.hondura - 1;
    return n;
}

fn bloque_dentro(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);
    try espera(e, "simbolo", "{");
    var n = rama("bloque", l);
    while !es(e, "simbolo", "}") {
        if es(e, "fin", "") {
            error_aqui(e, "bloque sin cerrar");
            falla "sintaxis";
        }
        let st = try sentencia(e);
        n.hijos.anadir(st);
    }
    try espera(e, "simbolo", "}");
    return n;
}

fn es_lugar(n: &Nodo) -> bool {
    let c = vista(n.clase);
    return c == "variable" || c == "campo" || c == "indice";
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
        n.texto.empujar(clave);
        n.texto.empujar(" ");
        n.texto.empujar(nombre);
        if t.largo() > 0 {
            n.texto.empujar(": ");
            n.texto.empujar(t);
        }
        let v = try expresion(e);
        n.hijos.anadir(v);
        try espera(e, "simbolo", ";");
        return n;
    }

    if es(e, "palabra", "if") {
        avanzar(e);
        var n = rama("si", l);
        let cond = try expresion(e);
        n.hijos.anadir(cond);
        let entonces = try bloque(e);
        n.hijos.anadir(entonces);
        if acepta(e, "palabra", "else") {
            if es(e, "simbolo", "{") {
                let sino_b = try bloque(e);
                n.hijos.anadir(sino_b);
            } else {
                // `else if`: la rama es un bloque con ese `if` dentro, que es
                // lo que significa y lo que escribe el C. Asi nadie de detras
                // tiene que saber que la rama podia no ser un bloque.
                let sino_s = try sentencia(e);
                var envuelta = rama("bloque", sino_s.linea);
                envuelta.hijos.anadir(sino_s);
                n.hijos.anadir(envuelta);
            }
        }
        return n;
    }

    if es(e, "palabra", "for") {
        avanzar(e);
        var n = rama("para", l);
        let uno = try espera(e, "ident", "");
        n.texto.empujar(uno);
        if acepta(e, "simbolo", ",") {
            let dos = try espera(e, "ident", "");
            n.texto.empujar(", ");
            n.texto.empujar(dos);
        }
        try espera(e, "palabra", "en");
        let coleccion = try expresion(e);
        // `for i en a..b`: de `a` a `b`, sin llegar a `b`.
        if acepta(e, "simbolo", "..") {
            var r = rama("rango", l);
            r.hijos.anadir(coleccion);
            let hasta = try expresion(e);
            r.hijos.anadir(hasta);
            n.hijos.anadir(r);
        } else {
            n.hijos.anadir(coleccion);
        }
        let cuerpo = try bloque(e);
        n.hijos.anadir(cuerpo);
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
        n.hijos.anadir(cond);
        let cuerpo = try bloque(e);
        n.hijos.anadir(cuerpo);
        return n;
    }

    // Un `match` suelto mira y hace: no lleva `;` detras, como no lo llevan
    // `if` ni `while`. El que da un valor va detras de un `return` o un `=`.
    if es(e, "palabra", "match") {
        var n = rama("expresion", l);
        let m = try match_(e);
        n.hijos.anadir(m);
        return n;
    }

    if es(e, "palabra", "falla") {
        avanzar(e);
        if es(e, "simbolo", "(") {
            // Aqui Python no dice lo que encontro: dice como se escribe.
            if e.error.largo() == 0 {
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
            n.hijos.anadir(v);
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
        n.hijos.anadir(izq);
        n.hijos.anadir(der);
        return n;
    }
    try espera(e, "simbolo", ";");
    var n = rama("expresion", l);
    n.hijos.anadir(izq);
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
        if es_tipo_basico(tp) {
            error_aqui(e, $"`{tp}` ya es un tipo del lenguaje: un parametro de tipo necesita otro nombre");
            falla "sintaxis";
        }
        if tiene(e.structs, tp) {
            error_aqui(e, $"`{tp}` ya es un struct: un parametro de tipo necesita otro nombre");
            falla "sintaxis";
        }
        if tiene(vistos, tp) {
            error_aqui(e, $"`{tp}` esta repetido en `{de_quien}<...>`");
            falla "sintaxis";
        }
        poner(vistos, vista(tp), 1);
        poner(e.tipo_params, vista(tp), 1);
        n.hijos.anadir(hoja("tipo_param", tp, l));
        if acepta(e, "simbolo", ":") {
            let r = try espera(e, "ident", "");
            let rv = vista(r);
            if rv != "decimal" && rv != "entero" && rv != "igualable"
            && rv != "numero" && rv != "ordenable" && rv != "texto" {
                error_aqui(e, $"`{r}` no es una restriccion; hay `decimal`, `entero`, `igualable`, `numero`, `ordenable`, `texto`");
                falla "sintaxis";
            }
            if restricciones { n.hijos.anadir(hoja("restriccion", rv, l)); }
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
        n.texto.empujar(nombre);
        e.tipo_params = [];
        try lista_tipo_params(e, n, nombre, l, false);
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
            c.texto.empujar(campo);
            c.texto.empujar(": ");
            c.texto.empujar(t);
            n.hijos.anadir(c);
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
        n.texto.empujar(cabecera);
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
            f.texto.empujar(nombre);
            f.hijos.anadir(hoja("externa", cabecera, fl));
            try espera(e, "simbolo", "(");
            if !es(e, "simbolo", ")") {
                while true {
                    let pn = try espera(e, "ident", "");
                    try espera(e, "simbolo", ":");
                    let pt = try tipo(e);
                    var pp = rama("param", fl);
                    pp.texto.empujar(pn);
                    pp.texto.empujar(": ");
                    pp.texto.empujar(pt);
                    f.hijos.anadir(pp);
                    if !acepta(e, "simbolo", ",") { break; }
                }
            }
            try espera(e, "simbolo", ")");
            if acepta(e, "simbolo", "->") {
                let r = try tipo(e);
                f.hijos.anadir(hoja("retorno_tipo", r, fl));
            }
            if es(e, "simbolo", "!") {
                error_en(e, "una funcion de C no falla como las de Tcode: devuelve lo que devuelva y lo miras tu", kf);
                falla "sintaxis";
            }
            try espera(e, "simbolo", ";");
            n.hijos.anadir(f);
        }
        try espera(e, "simbolo", "}");
        if n.hijos.largo() == 0 {
            error_en(e, "un `externo` vacio no trae nada", k);
            falla "sintaxis";
        }
        return n;
    }

    if es(e, "palabra", "enum") {
        avanzar(e);
        let nombre = try espera(e, "ident", "");
        var n = rama("enum", l);
        n.texto.empujar(nombre);
        try espera(e, "simbolo", "{");
        var vistos: mapa<str, usize> = [];
        while !es(e, "simbolo", "}") {
            if es(e, "fin", "") {
                error_aqui(e, "enum sin cerrar");
                falla "sintaxis";
            }
            let vn = try espera(e, "ident", "");
            if tiene(vistos, vn) {
                error_aqui(e, $"`{nombre}.{vn}` esta declarada dos veces");
                falla "sintaxis";
            }
            poner(vistos, vista(vn), 1);
            var v = rama("variante", linea_actual(e));
            v.texto.empujar(vn);
            if acepta(e, "simbolo", "(") {
                while true {
                    let t = try tipo(e);
                    v.hijos.anadir(hoja("lleva", t, linea_actual(e)));
                    if !acepta(e, "simbolo", ",") { break; }
                }
                try espera(e, "simbolo", ")");
            }
            n.hijos.anadir(v);
            if !acepta(e, "simbolo", ",") { break; }
        }
        try espera(e, "simbolo", "}");
        if n.hijos.largo() == 0 {
            error_aqui(e, $"`enum {nombre}` no declara ninguna variante: un valor que no puede tomar ninguna forma no sirve para nada");
            falla "sintaxis";
        }
        return n;
    }

    try espera(e, "palabra", "fn");
    let nombre = try espera(e, "ident", "");
    var n = rama("fn", l);
    n.texto.empujar(nombre);

    // `fn primeras<T>(...)`: parametros de tipo. Dentro de la firma y del
    // cuerpo, `T` es un tipo mas.
    e.tipo_params = [];
    try lista_tipo_params(e, n, nombre, l, true);

    try espera(e, "simbolo", "(");
    try parametros(e, n, l);
    try espera(e, "simbolo", ")");

    if acepta(e, "simbolo", "->") {
        let t = try tipo(e);
        var r = rama("retorno_tipo", l);
        r.texto.empujar(t);
        n.hijos.anadir(r);
    }
    if acepta(e, "simbolo", "!") {
        n.hijos.anadir(hoja("falible", "", l));
    }

    let cuerpo = try bloque(e);
    n.hijos.anadir(cuerpo);
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
    while i + 1 < toks.largo() {
        if igual(toks[i].valor, palabra) {
            if toks[i + 1].tipo == "ident" {
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
    while i < ruta.largo() {
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

// Lo que ya se leyo de cada archivo en una compilacion: sus tokens, los
// structs y enums que declara, y su arbol cuando alguien lo pidio. Un modulo
// se leia y se analizaba otra vez por cada archivo que lo usa —57 analisis
// para los 14 archivos de `tcodec`—; ahora una.
struct Leidos {
    // Donde esta `std/`: la raiz de Tcode.
    raiz: str,
    indice: mapa<str, usize>,
    tokens: lista<lista<Token>>,
    structs: lista<mapa<str, usize>>,
    enums: lista<mapa<str, usize>>,
    arboles: lista<Nodo>,
    con_arbol: lista<bool>,
}

fn leidos() -> Leidos {
    return leidos_en(".");
}

fn leidos_en(raiz: view) -> Leidos {
    return Leidos { raiz: nuevo(raiz), indice: [], tokens: [], structs: [], enums: [],
        arboles: [], con_arbol: [] };
}

// El sitio de `ruta` en lo leido, leyendola la primera vez. Si no se puede
// leer, o esta vacia, uno que no esta: `largo(l.tokens)` o mas.
fn leido(ruta: view, l: mut Leidos) -> usize {
    if tiene(l.indice, ruta) { return obtener(l.indice, ruta) sino 0; }
    let texto = leer_archivo(ruta) sino vacio();
    if texto.largo() == 0 { return l.tokens.largo(); }
    let toks = analizar(texto) sino [];
    let k = l.tokens.largo();
    poner(l.indice, ruta, k);
    l.structs.anadir(recoger_tras(toks, "struct"));
    l.enums.anadir(recoger_tras(toks, "enum"));
    l.tokens.anadir(toks);
    l.arboles.anadir(rama("programa", 1));
    l.con_arbol.anadir(false);
    return k;
}

// Donde se busca lo que pide un `usar`, como el cargador de Python: `std/`
// en la raiz de Tcode, y lo demas junto al archivo que lo pide; con `.t` y
// sin el. Nunca desde donde se ejecuta: el mismo programa se lee igual desde
// cualquier sitio.
fn candidatos_de(dir: view, pedido: view, raiz: view) -> lista<str> {
    var candidatos: lista<str> = [];
    var junto = vacio();
    if empieza_con(pedido, "std/") {
        if raiz.largo() > 0 && raiz != "." {
            junto.empujar(raiz);
            junto.empujar("/");
        }
    } else if dir.largo() > 0 {
        junto.empujar(dir);
        junto.empujar("/");
    }
    junto.empujar(pedido);
    candidatos.anadir(copiar(junto));
    if !termina_con(pedido, ".t") {
        junto.empujar(".t");
        candidatos.anadir(junto);
    }
    return candidatos;
}

// Los modulos que este archivo pide, analizados. Un solo nivel: lo que usen
// ellos a su vez no se sigue, porque desde aqui no se nombra.
fn modulos_usados(ruta: view, toks: &lista<Token>) -> lista<Usado> {
    var l = leidos();
    return modulos_usados_con(ruta, toks, l);
}

fn modulos_usados_con(ruta: view, toks: &lista<Token>, l: mut Leidos) -> lista<Usado> {
    var salida: lista<Usado> = [];
    let dir = carpeta(ruta);
    var i = 0;
    while i + 1 < toks.largo() {
        if toks[i].valor == "usar" {
            if toks[i + 1].tipo == "cadena" {
                let pedido = nuevo(toks[i + 1].valor);
                var alias = vacio();
                if i + 3 < toks.largo() {
                    if toks[i + 2].valor == "como" {
                        alias = nuevo(toks[i + 3].valor);
                    }
                }
                for c en candidatos_de(dir, pedido, l.raiz) {
                    let k = leido(c, l);
                    if k >= l.tokens.largo() { continue; }
                    if l.tokens[k].largo() == 0 { break; }
                    if !l.con_arbol[k] {
                        let otros = copiar(l.tokens[k]);
                        let nombres = visibles_con(c, otros, "struct", l);
                        let formas = visibles_con(c, otros, "enum", l);
                        var e = estado_de(otros, c, nombres, formas);
                        l.arboles[k] = programa(e) sino rama("programa", 1);
                        l.con_arbol[k] = true;
                    }
                    anadir(salida, Usado { alias: copiar(alias),
                            ruta: copiar(c), arbol: copiar(l.arboles[k]) });
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
    var l = leidos();
    return visibles_con(ruta, toks, palabra, l);
}

fn visibles_con(ruta: view, toks: &lista<Token>, palabra: view,
    l: mut Leidos) -> mapa<str, usize> {
    var m = recoger_tras(toks, palabra);
    let dir = carpeta(ruta);

    var i = 0;
    while i + 1 < toks.largo() {
        if toks[i].valor == "usar" {
            if toks[i + 1].tipo == "cadena" {
                for c en candidatos_de(dir, toks[i + 1].valor, l.raiz) {
                    let k = leido(c, l);
                    if k >= l.tokens.largo() { continue; }
                    if palabra == "struct" {
                        for nombre en claves(l.structs[k]) { poner(m, vista(nombre), 1); }
                    } else {
                        for nombre en claves(l.enums[k]) { poner(m, vista(nombre), 1); }
                    }
                    break;
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
            raiz.hijos.anadir(hoja("alias", a, linea_actual(e)));
            poner(e.alias, a, 1);
        }
        try espera(e, "simbolo", ";");
        raiz.hijos.anadir(hoja("usar", ruta, linea_actual(e)));
    }
    while tipo_en(e, 0) != "fin" {
        if es(e, "palabra", "usar") {
            error_aqui(e, "los `usar` van todos al principio del archivo");
            falla "sintaxis";
        }
        let d = try declaracion(e);
        raiz.hijos.anadir(d);
    }
    var cuenta: usize = 0;
    numerar(raiz, cuenta);
    return raiz;
}

// ------------------------------------------------------------------
// Programa
// ------------------------------------------------------------------
