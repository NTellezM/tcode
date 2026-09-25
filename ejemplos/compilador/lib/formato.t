// lib/formato.t — el formateador de Tcode, escrito en Tcode.
//
// Sin opciones, como `gofmt`: hay un estilo y es este, y formatear dos veces
// da lo mismo. Sangra por hondura de llaves con cuatro espacios, quita los
// espacios del final, deja como mucho una linea en blanco seguida, normaliza
// el espacio alrededor de los simbolos y conserva los comentarios donde
// estaban. No mueve tokens de linea: la salida lexea a los mismos tokens que
// la entrada.
//
// Es el mismo formateador que el de Python, paso a paso: la suite compara
// los dos sobre cada archivo del repositorio.

usar "../../lexer/lib/lexico.t";
usar "std/texto";
usar "std/lista";

fn esta_entre(xs: &lista<str>, x: view) -> bool {
    for y en xs {
        if igual(vista(y), x) { return true; }
    }
    return false;
}

fn antes_de_unario(v: view) -> bool {
    return igual(v, "(") || igual(v, "[") || igual(v, "{") || igual(v, ",")
    || igual(v, ";") || igual(v, ":") || igual(v, "=") || igual(v, "->")
    || igual(v, "&&") || igual(v, "||") || igual(v, "!") || igual(v, "~")
    || igual(v, "+") || igual(v, "-") || igual(v, "*") || igual(v, "/")
    || igual(v, "%") || igual(v, "<") || igual(v, ">") || igual(v, "<=")
    || igual(v, ">=") || igual(v, "==") || igual(v, "!=") || igual(v, "+?")
    || igual(v, "-?") || igual(v, "*?") || igual(v, "/?") || igual(v, "<<")
    || igual(v, ">>") || igual(v, "|") || igual(v, "^") || igual(v, "&");
}

// Palabras detras de las cuales empieza una expresion. `usize !` no cuenta:
// ahi el `!` marca que la funcion puede fallar.
fn abre_expresion(v: view) -> bool {
    return igual(v, "return") || igual(v, "if") || igual(v, "while")
    || igual(v, "en") || igual(v, "try") || igual(v, "sino") || igual(v, "else");
}

fn es_simbolo_del_lexer(v: view) -> bool {
    if largo(v) == 2 { return simbolo_doble(byte(v, 0), byte(v, 1)); }
    if largo(v) == 1 { return es_simbolo(byte(v, 0)); }
    return false;
}

// El valor de un token como lo tiene Python: las cadenas, descifradas.
fn valor_py(t: &Token) -> str {
    if igual(vista(t.tipo), "cadena") || igual(vista(t.tipo), "interpolada") {
        return descifrado_simple(vista(t.valor));
    }
    return copiar(t.valor);
}

// Los escapes resueltos, sin la marca de los `\xNN`: para comparar un valor
// con una palabra basta.
fn descifrado_simple(t: view) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(t) {
        let b = byte(t, i);
        if b == 92 && i + 1 < largo(t) {
            let d = byte(t, i + 1);
            if d == 110 { empujar_byte(r, 10); }
            else if d == 116 { empujar_byte(r, 9); }
            else if d == 48 { empujar_byte(r, 0); }
            else if d == 120 && i + 3 < largo(t) {
                empujar_byte(r, 1);
                i = i + 4;
                continue;
            } else { empujar(r, rebanar(t, i + 1, i + 2)); }
            i = i + 2;
            continue;
        }
        empujar(r, rebanar(t, i, i + 1));
        i = i + 1;
    }
    return r;
}

// Si el `<` de la posicion `i` abre una lista de tipos y no es un menor.
fn es_generico(toks: &lista<Token>, i: usize) -> bool {
    if i == 0 { return false; }
    let ant = valor_py(toks[i - 1]);
    let av = vista(ant);
    if igual(av, "lista") || igual(av, "mapa") || igual(av, "bloque") || igual(av, "fn") {
        return true;
    }
    if !igual(vista(toks[i - 1].tipo), "ident") { return false; }
    if i >= 2 {
        let ant2 = valor_py(toks[i - 2]);
        let a2 = vista(ant2);
        if igual(a2, "fn") || igual(a2, "struct") { return true; }
        if igual(a2, ":") || igual(a2, "->") || igual(a2, "<") || igual(a2, ",") {
            return true;
        }
    }
    return false;
}

fn hex_minuscula(b: usize) -> str {
    if b >= 65 && b <= 70 {
        var r = vacio();
        empujar_byte(r, (b + 32) como u8);
        return r;
    }
    var r = vacio();
    empujar_byte(r, b como u8);
    return r;
}

// El token tal como se escribe: las cadenas se descifran y se vuelven a
// escribir, como hace Python, que las guarda descifradas.
fn texto_de(t: &Token) -> str {
    let clase = vista(t.tipo);
    if !igual(clase, "cadena") && !igual(clase, "interpolada") { return copiar(t.valor); }
    let v = vista(t.valor);
    var r = nuevo("\"");
    if igual(clase, "interpolada") { r = nuevo("$\""); }
    var i = 0;
    while i < largo(v) {
        let b = byte(v, i);
        // Un hueco sale como se escribio, con los `\xNN` en minusculas como
        // los de fuera: es lo que hace Python, que lo guarda crudo.
        if igual(clase, "interpolada") && b == 123 {
            if i + 1 < largo(v) && byte(v, i + 1) == 123 {
                empujar(r, "{{");
                i = i + 2;
                continue;
            }
            let cierre = cierre_de_hueco(v, i + 1);
            empujar(r, "{");
            let dentro = hueco_escrito(rebanar(v, i + 1, cierre));
            empujar(r, vista(dentro));
            if cierre < largo(v) { empujar(r, "}"); }
            i = cierre + 1;
            continue;
        }
        if b == 92 && i + 1 < largo(v) {
            let d = byte(v, i + 1);
            if d == 120 && i + 3 < largo(v) {
                empujar(r, "\\x");
                empujar(r, hex_minuscula(byte(v, i + 2)));
                empujar(r, hex_minuscula(byte(v, i + 3)));
                i = i + 4;
                continue;
            }
            if d == 110 { empujar(r, "\\n"); }
            else if d == 116 { empujar(r, "\\t"); }
            else if d == 48 { empujar(r, "\\0"); }
            else if d == 92 { empujar(r, "\\\\"); }
            else if d == 34 { empujar(r, "\\\""); }
            // `\{` y `\}` son una llave escrita: se escriben `{{` y `}}`.
            else if d == 123 { empujar(r, "{{"); }
            else if d == 125 { empujar(r, "}}"); }
            else { empujar(r, rebanar(v, i + 1, i + 2)); }
            i = i + 2;
            continue;
        }
        if b == 10 { empujar(r, "\\n"); }
        else if b == 9 { empujar(r, "\\t"); }
        else if b == 0 { empujar(r, "\\0"); }
        else { empujar(r, rebanar(v, i, i + 1)); }
        i = i + 1;
    }
    empujar(r, "\"");
    return r;
}

// Un hueco tal cual, salvo los `\xNN`, que van en minusculas.
fn hueco_escrito(h: view) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(h) {
        if byte(h, i) == 92 && i + 1 < largo(h) {
            if byte(h, i + 1) == 120 && i + 3 < largo(h) {
                empujar(r, "\\x");
                empujar(r, hex_minuscula(byte(h, i + 2)));
                empujar(r, hex_minuscula(byte(h, i + 3)));
                i = i + 4;
                continue;
            }
            empujar(r, rebanar(h, i, i + 2));
            i = i + 2;
            continue;
        }
        empujar(r, rebanar(h, i, i + 1));
        i = i + 1;
    }
    return r;
}

// Los caracteres de un texto UTF-8: lo que mide Python al alinear.
fn ancho(t: view) -> usize {
    var n = 0;
    var i = 0;
    while i < largo(t) {
        let b = byte(t, i);
        if b < 128 || b >= 192 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn sin_espacio_final(t: view) -> str {
    var fin = largo(t);
    while fin > 0 {
        let b = byte(t, fin - 1);
        if b == 32 || b == 9 || b == 10 || b == 13 || b == 11 || b == 12 {
            fin = fin - 1;
        } else {
            break;
        }
    }
    return nuevo(rebanar(t, 0, fin));
}

struct Marcas {
    generico: lista<bool>,
    unario: lista<bool>,
}

// Si los dos van pegados, sin espacio en medio.
fn pega(toks: &lista<Token>, i_ant: usize, i: usize, mc: &Marcas) -> bool {
    let tt = vista(toks[i].tipo);
    let ta = vista(toks[i_ant].tipo);
    if igual(tt, "comentario") || igual(ta, "comentario") { return false; }
    let v = vista(toks[i].valor);
    let va = vista(toks[i_ant].valor);
    let ts = igual(tt, "simbolo");
    let as_ = igual(ta, "simbolo");
    if ts && (igual(v, ",") || igual(v, ";") || igual(v, ")") || igual(v, "]")
        || igual(v, ".") || igual(v, ":")) {
        return true;
    }
    if as_ && (igual(va, "(") || igual(va, "[") || igual(va, ".") || igual(va, "$")) {
        return true;
    }
    // Dentro de un tipo, `<` y `>` van pegados.
    if as_ && mc.generico[i_ant] && igual(va, "<") { return true; }
    if ts && mc.generico[i] { return true; }
    // Una llamada o un indice: `f(`, `xs[`, y tambien `f<T>(`.
    if ts && (igual(v, "(") || igual(v, "[")) {
        if as_ && mc.generico[i_ant] { return true; }
        // Un unario va pegado tambien a su parentesis: `!(a)`.
        if mc.unario[i_ant] { return true; }
        // Un tipo funcion o una clausura: `fn(usize) -> bool`, `fn[n](x)`.
        if igual(ta, "palabra") && igual(va, "fn") { return true; }
        return igual(ta, "ident") || (as_ && (igual(va, ")") || igual(va, "]")));
    }
    // Un unario va pegado a lo suyo.
    if mc.unario[i_ant] { return true; }
    return false;
}

fn juntar(indices: &lista<usize>, desde: usize, hasta: usize, toks: &lista<Token>,
    mc: &Marcas) -> str {
    var fuera = vacio();
    var j = desde;
    while j < hasta {
        let k = indices[j];
        let texto_t = texto_de(toks[k]);
        if j == desde {
            empujar(fuera, vista(texto_t));
            j = j + 1;
            continue;
        }
        let ka = indices[j - 1];
        if pega(toks, ka, k, mc) {
            let ambos = igual(vista(toks[ka].tipo), "simbolo")
            && igual(vista(toks[k].tipo), "simbolo");
            if ambos {
                let junto = $"{toks[ka].valor}{toks[k].valor}";
                // `>` y `>` pegados serian `>>`: otro token.
                if es_simbolo_del_lexer(vista(junto)) { empujar(fuera, " "); }
            }
        } else {
            empujar(fuera, " ");
        }
        empujar(fuera, vista(texto_t));
        j = j + 1;
    }
    return sin_espacio_final(vista(fuera));
}

// Formatea un archivo. Si no se puede leer como Tcode, `error` dice por que.
fn formatear(fuente: view, archivo: view, error: mut str) -> str ! {
    let todos = try tokens_de_todo(fuente, archivo, true, 1, error);
    var toks: lista<Token> = [];
    for t en todos {
        if !igual(vista(t.tipo), "fin") { anadir(toks, copiar(t)); }
    }

    // Que `<` y `>` son de un tipo y cuales son comparaciones.
    var generico: lista<bool> = [];
    var unario: lista<bool> = [];
    for _t en toks {
        anadir(generico, false);
        anadir(unario, false);
    }
    var pila: lista<usize> = [];
    var i = 0;
    while i < largo(toks) {
        let es_s = igual(vista(toks[i].tipo), "simbolo");
        let v = vista(toks[i].valor);
        if es_s && igual(v, "<") && es_generico(toks, i) {
            generico[i] = true;
            anadir(pila, i);
        } else if es_s && (igual(v, ">") || igual(v, ">>")) && largo(pila) > 0 {
            generico[i] = true;
            quitar_ultimo(pila);
            if igual(v, ">>") && largo(pila) > 0 { quitar_ultimo(pila); }
        }
        i = i + 1;
    }

    // Que operadores son unarios, mirando lo que va justo antes.
    i = 0;
    while i < largo(toks) {
        let v = vista(toks[i].valor);
        let es_op = igual(vista(toks[i].tipo), "simbolo")
        && (igual(v, "-") || igual(v, "&") || igual(v, "~") || igual(v, "!") || igual(v, "*"));
        if es_op {
            if i == 0 {
                unario[i] = true;
            } else {
                let ta = vista(toks[i - 1].tipo);
                let va = valor_py(toks[i - 1]);
                unario[i] = (igual(ta, "simbolo") && antes_de_unario(vista(va))
                    && !generico[i - 1])
                || (igual(ta, "palabra") && abre_expresion(vista(va)));
            }
        }
        i = i + 1;
    }
    let mc = Marcas { generico: generico, unario: unario };

    // Repartir en lineas segun venian.
    var lineas: lista<lista<usize>> = [];
    var actual: lista<usize> = [];
    var ultima: usize = 1;
    if largo(toks) > 0 { ultima = toks[0].linea; }
    var k = 0;
    while k < largo(toks) {
        let l = toks[k].linea;
        if l > ultima {
            anadir(lineas, actual);
            actual = [];
            var b = ultima + 1;
            while b < l {
                let vacia: lista<usize> = [];
                anadir(lineas, vacia);
                b = b + 1;
            }
            ultima = l;
        }
        anadir(actual, k);
        k = k + 1;
    }
    anadir(lineas, actual);

    // Escribir: el codigo de cada linea y, aparte, su comentario.
    var codigos: lista<str> = [];
    var comentarios: lista<str> = [];
    var con_comentario: lista<bool> = [];
    var hondura: i64 = 0;
    var blancos = 0;
    var primera = true;
    for linea en lineas {
        if largo(linea) == 0 {
            blancos = blancos + 1;
            continue;
        }
        if blancos > 0 && !primera {
            anadir(codigos, vacio());
            anadir(comentarios, vacio());
            anadir(con_comentario, false);
        }
        blancos = 0;
        primera = false;
        var sangrado = hondura;
        let p0 = linea[0];
        if igual(vista(toks[p0].tipo), "simbolo") {
            let v0 = vista(toks[p0].valor);
            if igual(v0, "}") || igual(v0, ")") || igual(v0, "]") {
                sangrado = hondura - 1;
                if sangrado < 0 { sangrado = 0; }
            }
        }
        var corte = largo(linea);
        var j = 1;
        while j < largo(linea) {
            if igual(vista(toks[linea[j]].tipo), "comentario") {
                corte = j;
                break;
            }
            j = j + 1;
        }
        var sangria = vacio();
        var q: i64 = 0;
        while q < sangrado {
            empujar(sangria, "    ");
            q = q + 1;
        }
        let codigo = juntar(linea, 0, corte, toks, mc);
        empujar(sangria, vista(codigo));
        anadir(codigos, sangria);
        if corte < largo(linea) {
            anadir(comentarios, juntar(linea, corte, largo(linea), toks, mc));
            anadir(con_comentario, true);
        } else {
            anadir(comentarios, vacio());
            anadir(con_comentario, false);
        }
        for x en linea {
            if igual(vista(toks[x].tipo), "simbolo") {
                let v = vista(toks[x].valor);
                if igual(v, "{") || igual(v, "(") || igual(v, "[") { hondura = hondura + 1; }
                if igual(v, "}") || igual(v, ")") || igual(v, "]") { hondura = hondura - 1; }
            }
        }
        if hondura < 0 { hondura = 0; }
    }

    // Los comentarios al final de lineas seguidas se alinean entre ellos.
    var salida = vacio();
    var n = 0;
    while n < largo(codigos) {
        if !con_comentario[n] {
            empujar(salida, vista(codigos[n]));
            empujar(salida, "\n");
            n = n + 1;
            continue;
        }
        var m = n;
        var mayor = 0;
        while m < largo(codigos) && con_comentario[m] {
            let a = ancho(vista(codigos[m]));
            if a > mayor { mayor = a; }
            m = m + 1;
        }
        var r = n;
        while r < m {
            if largo(codigos[r]) > 0 {
                empujar(salida, vista(codigos[r]));
                var relleno = ancho(vista(codigos[r]));
                while relleno < mayor {
                    empujar(salida, " ");
                    relleno = relleno + 1;
                }
                empujar(salida, " ");
            }
            empujar(salida, vista(comentarios[r]));
            empujar(salida, "\n");
            r = r + 1;
        }
        n = m;
    }
    // Sin saltos al final salvo uno.
    var fin = largo(salida);
    while fin > 0 && byte(vista(salida), fin - 1) == 10 { fin = fin - 1; }
    var limpio = nuevo(rebanar(vista(salida), 0, fin));
    empujar(limpio, "\n");
    return limpio;
}

fn quitar_ultimo(xs: mut lista<usize>) {
    var quedan: lista<usize> = [];
    var i = 0;
    while i + 1 < largo(xs) {
        anadir(quedan, xs[i]);
        i = i + 1;
    }
    xs = quedan;
}
