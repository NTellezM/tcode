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
        if igual(y, x) { return true; }
    }
    return false;
}

fn antes_de_unario(v: view) -> bool {
    return v == "(" || v == "[" || v == "{" || v == ","
    || v == ";" || v == ":" || v == "=" || v == "->"
    || v == "&&" || v == "||" || v == "!" || v == "~"
    || v == "+" || v == "-" || v == "*" || v == "/"
    || v == "%" || v == "<" || v == ">" || v == "<="
    || v == ">=" || v == "==" || v == "!=" || v == "+?"
    || v == "-?" || v == "*?" || v == "/?" || v == "<<"
    || v == ">>" || v == "|" || v == "^" || v == "&";
}

// Palabras detras de las cuales empieza una expresion. `usize !` no cuenta:
// ahi el `!` marca que la funcion puede fallar.
fn abre_expresion(v: view) -> bool {
    return v == "return" || v == "if" || v == "while"
    || v == "en" || v == "try" || v == "sino" || v == "else";
}

fn es_simbolo_del_lexer(v: view) -> bool {
    if v.largo() == 2 { return simbolo_doble(byte(v, 0), byte(v, 1)); }
    if v.largo() == 1 { return es_simbolo(byte(v, 0)); }
    return false;
}

// El valor de un token como lo tiene Python: las cadenas, descifradas.
fn valor_py(t: &Token) -> str {
    if t.tipo == "cadena" || t.tipo == "interpolada" {
        return descifrado_simple(t.valor);
    }
    return copiar(t.valor);
}

// Los escapes resueltos, sin la marca de los `\xNN`: para comparar un valor
// con una palabra basta.
fn descifrado_simple(t: view) -> str {
    var r = vacio();
    var i = 0;
    while i < t.largo() {
        let b = byte(t, i);
        if b == 92 && i + 1 < t.largo() {
            let d = byte(t, i + 1);
            if d == 110 { empujar_byte(r, 10); }
            else if d == 116 { empujar_byte(r, 9); }
            else if d == 48 { empujar_byte(r, 0); }
            else if d == 120 && i + 3 < t.largo() {
                empujar_byte(r, 1);
                i = i + 4;
                continue;
            } else { r.empujar(rebanar(t, i + 1, i + 2)); }
            i = i + 2;
            continue;
        }
        r.empujar(rebanar(t, i, i + 1));
        i = i + 1;
    }
    return r;
}

// Si el `<` de la posicion `i` abre una lista de tipos y no es un menor.
// El formateador ve la palabra tal como se escribio, asi que durante el
// transbordo valen las dos formas del nombre.
fn es_generico(toks: &lista<Token>, i: usize) -> bool {
    if i == 0 { return false; }
    let ant = valor_py(toks[i - 1]);
    let av = vista(ant);
    if av == "lista" || av == "mapa" || av == "list" || av == "map"
    || av == "bloque" || av == "fn" {
        return true;
    }
    if toks[i - 1].tipo != "ident" { return false; }
    if i < 2 { return false; }
    let ant2 = valor_py(toks[i - 2]);
    let a2 = vista(ant2);
    if a2 == "fn" || a2 == "struct" { return true; }
    // `Nombre<...>` en posicion de tipo: detras de `:` o `->`. Entre el
    // contexto y el nombre pueden ir `&`, `mut` o los dos: `&mut Par<A, B>`.
    var k = i - 2;
    while k > 0 && (toks[k].valor == "&" || toks[k].valor == "mut") { k = k - 1; }
    let ak = valor_py(toks[k]);
    let a = vista(ak);
    return a == ":" || a == "->" || a == "<" || a == ",";
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
    if clase != "cadena" && clase != "interpolada" { return copiar(t.valor); }
    let v = vista(t.valor);
    var r = nuevo("\"");
    if clase == "interpolada" { r = nuevo("$\""); }
    var i = 0;
    while i < v.largo() {
        let b = byte(v, i);
        // Un hueco sale como se escribio, con los `\xNN` en minusculas como
        // los de fuera: es lo que hace Python, que lo guarda crudo.
        if clase == "interpolada" && b == 123 {
            if i + 1 < v.largo() && byte(v, i + 1) == 123 {
                r.empujar("{{");
                i = i + 2;
                continue;
            }
            let cierre = cierre_de_hueco(v, i + 1);
            r.empujar("{");
            let dentro = hueco_escrito(rebanar(v, i + 1, cierre));
            r.empujar(dentro);
            if cierre < v.largo() { r.empujar("}"); }
            i = cierre + 1;
            continue;
        }
        if b == 92 && i + 1 < v.largo() {
            let d = byte(v, i + 1);
            if d == 120 && i + 3 < v.largo() {
                r.empujar("\\x");
                r.empujar(hex_minuscula(byte(v, i + 2)));
                r.empujar(hex_minuscula(byte(v, i + 3)));
                i = i + 4;
                continue;
            }
            if d == 110 { r.empujar("\\n"); }
            else if d == 116 { r.empujar("\\t"); }
            else if d == 48 { r.empujar("\\0"); }
            else if d == 92 { r.empujar("\\\\"); }
            else if d == 34 { r.empujar("\\\""); }
            // `\{` y `\}` son una llave escrita: se escriben `{{` y `}}`.
            else if d == 123 { r.empujar("{{"); }
            else if d == 125 { r.empujar("}}"); }
            else { r.empujar(rebanar(v, i + 1, i + 2)); }
            i = i + 2;
            continue;
        }
        if b == 10 { r.empujar("\\n"); }
        else if b == 9 { r.empujar("\\t"); }
        else if b == 0 { r.empujar("\\0"); }
        else { r.empujar(rebanar(v, i, i + 1)); }
        i = i + 1;
    }
    r.empujar("\"");
    return r;
}

// Un hueco tal cual, salvo los `\xNN`, que van en minusculas.
fn hueco_escrito(h: view) -> str {
    var r = vacio();
    var i = 0;
    while i < h.largo() {
        if byte(h, i) == 92 && i + 1 < h.largo() {
            if byte(h, i + 1) == 120 && i + 3 < h.largo() {
                r.empujar("\\x");
                r.empujar(hex_minuscula(byte(h, i + 2)));
                r.empujar(hex_minuscula(byte(h, i + 3)));
                i = i + 4;
                continue;
            }
            r.empujar(rebanar(h, i, i + 2));
            i = i + 2;
            continue;
        }
        r.empujar(rebanar(h, i, i + 1));
        i = i + 1;
    }
    return r;
}

// Los caracteres de un texto UTF-8: lo que mide Python al alinear.
fn ancho(t: view) -> usize {
    var n = 0;
    var i = 0;
    while i < t.largo() {
        let b = byte(t, i);
        if b < 128 || b >= 192 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn sin_espacio_final(t: view) -> str {
    var fin = t.largo();
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
    if tt == "comentario" || ta == "comentario" { return false; }
    let v = vista(toks[i].valor);
    let va = vista(toks[i_ant].valor);
    let ts = tt == "simbolo";
    let as_ = ta == "simbolo";
    if ts && (v == "," || v == ";" || v == ")" || v == "]"
        || v == "." || v == ":") {
        return true;
    }
    if as_ && (va == "(" || va == "[" || va == "." || igual(va, "$")) {
        return true;
    }
    // `como?`: el `?` es parte de la conversion.
    if ts && v == "?" && va == "como" { return true; }
    // Un rango va pegado: `0..n`.
    if (ts && v == "..") || (as_ && va == "..") { return true; }
    // Dentro de un tipo, `<` y `>` van pegados.
    if as_ && mc.generico[i_ant] && va == "<" { return true; }
    if ts && mc.generico[i] { return true; }
    // Una llamada o un indice: `f(`, `xs[`, y tambien `f<T>(`.
    if ts && (v == "(" || v == "[") {
        if as_ && mc.generico[i_ant] { return true; }
        // Un unario va pegado tambien a su parentesis: `!(a)`.
        if mc.unario[i_ant] { return true; }
        // Un tipo funcion o una clausura: `fn(usize) -> bool`, `fn[n](x)`.
        if ta == "palabra" && va == "fn" { return true; }
        return ta == "ident" || (as_ && (va == ")" || va == "]"));
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
            fuera.empujar(texto_t);
            j = j + 1;
            continue;
        }
        let ka = indices[j - 1];
        if pega(toks, ka, k, mc) {
            let ambos = toks[ka].tipo == "simbolo"
            && toks[k].tipo == "simbolo";
            if ambos {
                let junto = $"{toks[ka].valor}{toks[k].valor}";
                // `>` y `>` pegados serian `>>`: otro token.
                if es_simbolo_del_lexer(junto) { fuera.empujar(" "); }
            }
        } else {
            fuera.empujar(" ");
        }
        fuera.empujar(texto_t);
        j = j + 1;
    }
    return sin_espacio_final(fuera);
}

// Formatea un archivo. Si no se puede leer como Tcode, `error` dice por que.
fn formatear(fuente: view, archivo: view, error: mut str) -> str ! {
    let todos = try tokens_de_todo(fuente, archivo, true, 1, error);
    var toks: lista<Token> = [];
    for t en todos {
        if t.tipo != "fin" { toks.anadir(copiar(t)); }
    }

    // Que `<` y `>` son de un tipo y cuales son comparaciones.
    var generico: lista<bool> = [];
    var unario: lista<bool> = [];
    for _t en toks {
        generico.anadir(false);
        unario.anadir(false);
    }
    var pila: lista<usize> = [];
    var i = 0;
    while i < toks.largo() {
        let es_s = toks[i].tipo == "simbolo";
        let v = vista(toks[i].valor);
        if es_s && v == "<" && es_generico(toks, i) {
            generico[i] = true;
            pila.anadir(i);
        } else if es_s && (v == ">" || v == ">>") && pila.largo() > 0 {
            generico[i] = true;
            quitar_ultimo(pila);
            if v == ">>" && pila.largo() > 0 { quitar_ultimo(pila); }
        }
        i = i + 1;
    }

    // Que operadores son unarios, mirando lo que va justo antes.
    i = 0;
    while i < toks.largo() {
        let v = vista(toks[i].valor);
        let es_op = toks[i].tipo == "simbolo"
        && (v == "-" || v == "&" || v == "~" || v == "!" || v == "*");
        if es_op {
            if i == 0 {
                unario[i] = true;
            } else {
                let ta = vista(toks[i - 1].tipo);
                let va = valor_py(toks[i - 1]);
                unario[i] = (ta == "simbolo" && antes_de_unario(va)
                    && !generico[i - 1])
                || (ta == "palabra" && abre_expresion(va));
            }
        }
        i = i + 1;
    }
    let mc = Marcas { generico: generico, unario: unario };

    // Repartir en lineas segun venian.
    var lineas: lista<lista<usize>> = [];
    var actual: lista<usize> = [];
    var ultima: usize = 1;
    if toks.largo() > 0 { ultima = toks[0].linea; }
    var k = 0;
    while k < toks.largo() {
        let l = toks[k].linea;
        if l > ultima {
            lineas.anadir(actual);
            actual = [];
            var b = ultima + 1;
            while b < l {
                let vacia: lista<usize> = [];
                lineas.anadir(vacia);
                b = b + 1;
            }
            ultima = l;
        }
        actual.anadir(k);
        k = k + 1;
    }
    lineas.anadir(actual);

    // Escribir: el codigo de cada linea y, aparte, su comentario.
    var codigos: lista<str> = [];
    var comentarios: lista<str> = [];
    var con_comentario: lista<bool> = [];
    var hondura: i64 = 0;
    var blancos = 0;
    var primera = true;
    for linea en lineas {
        if linea.largo() == 0 {
            blancos = blancos + 1;
            continue;
        }
        if blancos > 0 && !primera {
            codigos.anadir(vacio());
            comentarios.anadir(vacio());
            con_comentario.anadir(false);
        }
        blancos = 0;
        primera = false;
        var sangrado = hondura;
        let p0 = linea[0];
        if toks[p0].tipo == "simbolo" {
            let v0 = vista(toks[p0].valor);
            if v0 == "}" || v0 == ")" || v0 == "]" {
                sangrado = hondura - 1;
                if sangrado < 0 { sangrado = 0; }
            }
        }
        var corte = linea.largo();
        var j = 1;
        while j < linea.largo() {
            if toks[linea[j]].tipo == "comentario" {
                corte = j;
                break;
            }
            j = j + 1;
        }
        var sangria = vacio();
        var q: i64 = 0;
        while q < sangrado {
            sangria.empujar("    ");
            q = q + 1;
        }
        let codigo = juntar(linea, 0, corte, toks, mc);
        sangria.empujar(codigo);
        codigos.anadir(sangria);
        if corte < linea.largo() {
            comentarios.anadir(juntar(linea, corte, linea.largo(), toks, mc));
            con_comentario.anadir(true);
        } else {
            comentarios.anadir(vacio());
            con_comentario.anadir(false);
        }
        for x en linea {
            if toks[x].tipo == "simbolo" {
                let v = vista(toks[x].valor);
                if v == "{" || v == "(" || v == "[" { hondura = hondura + 1; }
                if v == "}" || v == ")" || v == "]" { hondura = hondura - 1; }
            }
        }
        if hondura < 0 { hondura = 0; }
    }

    // Los comentarios al final de lineas seguidas se alinean entre ellos.
    var salida = vacio();
    var n = 0;
    while n < codigos.largo() {
        if !con_comentario[n] {
            salida.empujar(codigos[n]);
            salida.empujar("\n");
            n = n + 1;
            continue;
        }
        var m = n;
        var mayor = 0;
        while m < codigos.largo() && con_comentario[m] {
            let a = ancho(codigos[m]);
            if a > mayor { mayor = a; }
            m = m + 1;
        }
        var r = n;
        while r < m {
            if codigos[r].largo() > 0 {
                salida.empujar(codigos[r]);
                var relleno = ancho(codigos[r]);
                while relleno < mayor {
                    salida.empujar(" ");
                    relleno = relleno + 1;
                }
                salida.empujar(" ");
            }
            salida.empujar(comentarios[r]);
            salida.empujar("\n");
            r = r + 1;
        }
        n = m;
    }
    // Sin saltos al final salvo uno.
    var fin = salida.largo();
    while fin > 0 && byte(salida, fin - 1) == 10 { fin = fin - 1; }
    var limpio = nuevo(rebanar(salida, 0, fin));
    limpio.empujar("\n");
    return limpio;
}

fn quitar_ultimo(xs: mut lista<usize>) {
    var quedan: lista<usize> = [];
    var i = 0;
    while i + 1 < xs.largo() {
        quedan.anadir(xs[i]);
        i = i + 1;
    }
    xs = quedan;
}
