// lib/generar.t — el C de cada tipo y de cada firma, escrito en Tcode.
//
// Sexta capa del compilador en su propio lenguaje, y la primera del
// generador. Aqui esta la cara que el C ve de un programa Tcode: como se
// llama cada tipo, y como queda la firma de cada funcion.
//
// La suite compara lo que sale de aqui con lo que emite el generador de
// Python, cadena por cadena, para cada funcion del repositorio.

usar "tipos.t" como T;
usar "tipar.t" como I;
usar "../../lexer/lib/sintaxis.t" como P;
usar "std/texto";
usar "std/lista";

// El nombre C de un tipo compuesto: `[usize; 3]` es `arr_usize_3`.
// Tiene que dar exactamente lo mismo que el generador de Python, porque de
// ahi salen los nombres de todas las funciones que este genera.
fn mangle(t: view) -> str {
    if T.es_referencia(t) {
        var s = nuevo("ref_");
        if empieza_con(t, "&mut ") { s = nuevo("refmut_"); }
        let dentro = T.apuntado(t);
        let m = mangle(dentro);
        empujar(s, vista(m));
        return s;
    }
    if T.es_arreglo(t) {
        let elem = T.elemento(t);
        var s = nuevo("arr_");
        let m = mangle(vista(elem));
        empujar(s, vista(m));
        empujar(s, "_");
        empujar(s, cuantos_de_arreglo(t));
        return s;
    }
    if T.es_bloque(t) {
        var s = nuevo("bloque_");
        let dentro = T.elemento(t);
        let m = mangle(vista(dentro));
        empujar(s, vista(m));
        return s;
    }
    if T.es_mapa(t) {
        let partes = T.partir_tipos(T.entre_angulos(t));
        if largo(partes) != 2 { return nuevo(t); }
        var s = nuevo("mapa_");
        let k = mangle(vista(partes[0]));
        let v = mangle(vista(partes[1]));
        empujar(s, vista(k));
        empujar(s, "_");
        empujar(s, vista(v));
        return s;
    }
    if T.es_lista(t) {
        var s = nuevo("lista_");
        let dentro = T.elemento(t);
        let m = mangle(vista(dentro));
        empujar(s, vista(m));
        return s;
    }
    if T.es_funcion(t) {
        let partes = T.partes_de_funcion(t);
        if largo(partes) == 0 { return nuevo(t); }
        var s = nuevo("fn_");
        var i = 0;
        while i + 1 < largo(partes) {
            if i > 0 { empujar(s, "_"); }
            let pieza = mangle(vista(partes[i]));
            empujar(s, vista(pieza));
            i = i + 1;
        }
        if largo(partes) == 1 { empujar(s, "nada"); }
        empujar(s, "_a_");
        let ultimo = mangle(vista(partes[largo(partes) - 1]));
        empujar(s, vista(ultimo));
        return s;
    }
    // `()` no es un nombre valido en C.
    if igual(t, "()") { return nuevo("nada"); }
    // El alias del modulo —`P.Nodo`— es cosa de quien lee el archivo.
    return I.sin_modulo(t);
}

// El `4` de `[usize; 4]`.
fn cuantos_de_arreglo(t: view) -> str {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 59 {
            return nuevo(recortar(rebanar(t, i + 1, largo(t) - 1)));
        }
        i = i + 1;
    }
    return nuevo("0");
}

// El tipo de C que le corresponde. Los compuestos van envueltos en un
// struct con nombre: en C un arreglo desnudo no se puede asignar ni
// devolver, y envolverlo le devuelve la semantica de valor que el lenguaje
// promete.
fn tipo_c(t: view) -> str {
    if igual(t, "str") { return nuevo("SafeString"); }
    if igual(t, "view") { return nuevo("SafeView"); }
    if igual(t, "bool") { return nuevo("bool"); }
    if igual(t, "usize") { return nuevo("size_t"); }
    if igual(t, "u8") { return nuevo("uint8_t"); }
    if igual(t, "u16") { return nuevo("uint16_t"); }
    if igual(t, "u32") { return nuevo("uint32_t"); }
    if igual(t, "u64") { return nuevo("uint64_t"); }
    if igual(t, "i8") { return nuevo("int8_t"); }
    if igual(t, "i16") { return nuevo("int16_t"); }
    if igual(t, "i32") { return nuevo("int32_t"); }
    if igual(t, "i64") { return nuevo("int64_t"); }
    if igual(t, "f32") { return nuevo("float"); }
    if igual(t, "f64") { return nuevo("double"); }
    if igual(t, "()") || largo(t) == 0 { return nuevo("void"); }

    if T.es_referencia(t) {
        // Un prestamo es un puntero. El de solo lectura sale `const`, asi
        // que el propio compilador de C impide escribir por el.
        let dentro = T.apuntado(t);
        var s = vacio();
        if !empieza_con(t, "&mut ") { empujar(s, "const "); }
        let base = tipo_c(dentro);
        empujar(s, vista(base));
        empujar(s, "*");
        return s;
    }
    if T.es_arreglo(t) || T.es_bloque(t) || T.es_mapa(t) || T.es_lista(t)
    || T.es_funcion(t) {
        var s = nuevo("ss_");
        let m = mangle(t);
        empujar(s, vista(m));
        return s;
    }
    // Un struct se llama igual en los dos lados. El alias con el que se
    // escribio —`P.Nodo`— es cosa de quien lee el archivo: en C no queda.
    return I.sin_modulo(t);
}

// El `T !` de Tcode es un struct: `motivo == NULL` significa que fue bien.
fn tipo_resultado(t: view) -> str {
    var s = nuevo("ss_res_");
    if largo(t) == 0 || igual(t, "()") {
        empujar(s, "unidad");
        return s;
    }
    let m = mangle(t);
    empujar(s, vista(m));
    return s;
}

// La firma en C de una funcion. `main` es el unico nombre que cambia: el de
// verdad lo pone el generador para poder recoger los argumentos.
// C tiene palabras que Tcode no: un `fn union(...)` es legitimo en Tcode y
// no lo es en C. El cargador le pone `ss_id_` delante, y esta capa dice lo
// mismo. `bool`, `true` y `false` no entran: significan lo mismo en los dos.
fn choca_con_c(n: view) -> bool {
    if igual(n, "auto") || igual(n, "break") || igual(n, "case") { return true; }
    if igual(n, "char") || igual(n, "const") || igual(n, "continue") { return true; }
    if igual(n, "default") || igual(n, "do") || igual(n, "double") { return true; }
    if igual(n, "else") || igual(n, "enum") || igual(n, "extern") { return true; }
    if igual(n, "float") || igual(n, "for") || igual(n, "goto") { return true; }
    if igual(n, "if") || igual(n, "inline") || igual(n, "int") { return true; }
    if igual(n, "long") || igual(n, "register") || igual(n, "restrict") { return true; }
    if igual(n, "return") || igual(n, "short") || igual(n, "signed") { return true; }
    if igual(n, "sizeof") || igual(n, "static") || igual(n, "struct") { return true; }
    if igual(n, "switch") || igual(n, "typedef") || igual(n, "union") { return true; }
    if igual(n, "unsigned") || igual(n, "void") || igual(n, "volatile") { return true; }
    if igual(n, "while") || igual(n, "complex") || igual(n, "imaginary") { return true; }
    if igual(n, "noreturn") || igual(n, "alignas") || igual(n, "alignof") { return true; }
    if igual(n, "thread_local") || igual(n, "static_assert") { return true; }
    if igual(n, "generic") { return true; }
    // de la biblioteca de C, que tambien esta incluida
    if igual(n, "malloc") || igual(n, "free") || igual(n, "calloc") { return true; }
    if igual(n, "realloc") || igual(n, "memcpy") || igual(n, "memset") { return true; }
    if igual(n, "strlen") || igual(n, "printf") || igual(n, "fprintf") { return true; }
    if igual(n, "sprintf") || igual(n, "snprintf") || igual(n, "abort") { return true; }
    if igual(n, "exit") || igual(n, "stdin") || igual(n, "stdout") { return true; }
    if igual(n, "stderr") || igual(n, "NULL") || igual(n, "size_t") { return true; }
    return igual(n, "errno");
}

fn nombre_en_c(n: view) -> str {
    if !choca_con_c(n) { return nuevo(n); }
    var s = nuevo("ss_id_");
    empujar(s, n);
    return s;
}

fn prototipo(nombre: view, params: &lista<str>, marcas: &lista<str>,
    retorno: view, falible: bool) -> str {
    if igual(nombre, "main") && !falible {
        return nuevo("int main(int argc, char** argv)");
    }

    var salida = vacio();
    if falible {
        let r = tipo_resultado(retorno);
        empujar(salida, vista(r));
    } else {
        let r = tipo_c(retorno);
        empujar(salida, vista(r));
    }
    empujar(salida, " ");
    if igual(nombre, "main") { empujar(salida, "ss_main_"); }
    else {
        let en_c = nombre_en_c(nombre);
        empujar(salida, vista(en_c));
    }
    empujar(salida, "(");

    if largo(params) == 0 {
        empujar(salida, "void)");
        return salida;
    }

    var i = 0;
    while i < largo(params) {
        if i > 0 { empujar(salida, ", "); }
        empujar(salida, "SS_LANG_QUIZA_SIN_USAR ");
        let solo = marca_sola(vista(marcas[i]));
        let marca = vista(solo);
        let base = tipo_c(vista(params[i]));
        if empieza_con(marca, "&mut ") || empieza_con(marca, "mut ") {
            empujar(salida, base);
            empujar(salida, "* ");
        } else {
            if empieza_con(marca, "&") {
                empujar(salida, "const ");
                empujar(salida, base);
                empujar(salida, "* ");
            } else {
                empujar(salida, base);
                empujar(salida, " ");
            }
        }
        let pn = nombre_de_param(vista(marcas[i]));
        empujar(salida, vista(pn));
        i = i + 1;
    }
    empujar(salida, ")");
    return salida;
}

// Las marcas llegan como `nombre: &`, con el nombre delante para no tener
// que pasar dos listas. Esto saca la parte de detras.
fn marca_sola(marcado: view) -> str {
    var i = 0;
    while i + 1 < largo(marcado) {
        if byte(marcado, i) == 58 {
            if byte(marcado, i + 1) == 32 {
                return nuevo(rebanar(marcado, i + 2, largo(marcado)));
            }
        }
        i = i + 1;
    }
    return vacio();
}

fn nombre_de_param(marcado: view) -> str {
    var i = 0;
    while i < largo(marcado) {
        if byte(marcado, i) == 58 { return nuevo(rebanar(marcado, 0, i)); }
        i = i + 1;
    }
    return nuevo(marcado);
}

// ------------------------------------------------------------------
// Expresiones
// ------------------------------------------------------------------
//
// El C de una expresion. Solo las que no necesitan emitir lineas aparte:
// un temporal o una bandera hay que declararlos antes, y eso es del cuerpo,
// no de la expresion. Lo que no se sabe hacer sale como `?`, y la suite
// cuenta cuantas se cubren en vez de fingir que son todas.

struct Sitio {
    archivo: str,
    // nombre -> tipo, para elegir el ancho de la aritmetica comprobada
    tipos: mapa<str, str>,
    // nombres que en C son punteros: parametros prestados
    punteros: mapa<str, usize>,
    // nombres que se entregan por algun camino: su liberacion la decide una
    // bandera `ss_vivo_X` en vez de hacerse siempre
    pide_bandera: mapa<str, usize>,
}

fn no_se() -> str { return nuevo("?"); }

fn es_desconocido(c: view) -> bool { return igual(c, "?"); }

fn literal_entero(valor: view, esperado: view) -> str {
    if igual(esperado, "i64") {
        var s = nuevo("(int64_t)");
        empujar(s, valor);
        return s;
    }
    if igual(esperado, "f64") || igual(esperado, "f32") {
        var s = nuevo(valor);
        empujar(s, ".0");
        if igual(esperado, "f32") { empujar(s, "f"); }
        return s;
    }
    // Sin sufijo, un literal por encima de 2^63-1 no cabe en el tipo que C le
    // asigna por defecto y el compilador avisa.
    var s = nuevo("(size_t)");
    empujar(s, valor);
    if mayor_que_i64(valor) { empujar(s, "ULL"); }
    return s;
}

fn mayor_que_i64(valor: view) -> bool {
    let tope = "9223372036854775807";
    if largo(valor) > largo(tope) { return true; }
    if largo(valor) < largo(tope) { return false; }
    return menor(tope, valor);
}

// El tipo de un nombre segun lo que se sabe aqui.
fn tipo_de_nombre(s: &Sitio, nombre: view) -> str {
    if !tiene(s.tipos, nombre) { return vacio(); }
    return nuevo(obtener(s.tipos, nombre) sino "");
}

// La aritmetica comprobada tiene una familia por ancho, y el nombre lo elige
// el tipo de los operandos.
fn familia(op: view) -> str {
    if igual(op, "+") { return nuevo("suma"); }
    if igual(op, "-") { return nuevo("resta"); }
    if igual(op, "*") { return nuevo("mul"); }
    return vacio();
}

fn expresion_c(s: &Sitio, n: &P.Nodo, esperado: view, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);

    if igual(clase, "entero") { return literal_entero(vista(n.texto), esperado); }
    if igual(clase, "booleano") { return nuevo(vista(n.texto)); }

    if igual(clase, "expresion") {
        if largo(n.hijos) == 1 {
            return expresion_c(s, n.hijos[0], esperado, tipos);
        }
        return no_se();
    }

    if igual(clase, "variable") {
        let nombre = vista(n.texto);
        if tiene(s.punteros, nombre) {
            var v = nuevo("(*");
            empujar(v, nombre);
            empujar(v, ")");
            return v;
        }
        return nuevo(nombre);
    }

    if igual(clase, "llamada") {
        return llamada_c(s, n, tipos);
    }

    if igual(clase, "campo") {
        // `sitio_c` ya devuelve el valor, no el puntero: un prestamo sale
        // como `(*x)`, asi que aqui siempre es un punto.
        let base = sitio_c(s, n.hijos[0], tipos);
        if es_desconocido(vista(base)) { return no_se(); }
        var r = copiar(base);
        empujar(r, ".");
        empujar(r, vista(n.texto));
        return r;
    }

    if igual(clase, "indice") {
        return indice_c(s, n, tipos);
    }

    if igual(clase, "binaria") {
        return binaria_c(s, n, esperado, tipos);
    }

    if igual(clase, "unaria") {
        let op = vista(n.texto);
        if largo(n.hijos) != 1 { return no_se(); }
        // `~` lleva molde para que el resultado no se ensanche por el camino.
        if igual(op, "~") { return no_se(); }
        let dentro = expresion_c(s, n.hijos[0], esperado, tipos);
        if es_desconocido(vista(dentro)) { return no_se(); }
        var v = nuevo("(");
        empujar(v, op);
        empujar(v, vista(dentro));
        empujar(v, ")");
        return v;
    }

    return no_se();
}

// Un sitio del que tomar campos o elementos. Una llamada no es un sitio:
// `hacer()[1]` tendria que guardar lo que devuelve antes de indexarlo, o la
// llamada se evaluaria una vez por cada vez que aparece en el C —dos: el
// elemento y el largo— y lo que devuelve no lo liberaria nadie.
fn sitio_c(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);
    if igual(clase, "variable") || igual(clase, "campo")
    || igual(clase, "indice") {
        return expresion_c(s, n, "", tipos);
    }
    return no_se();
}

// Indexar comprueba el limite: es la comprobacion que C no hace y por la que
// existe medio Tcode. Va en el C, no en el comprobador, porque el indice se
// sabe al correr.
fn indice_c(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 2 { return no_se(); }
    let suyo = I.tipo_de(tipos, n.hijos[0]);
    let base = T.apuntado_si(vista(suyo));
    let sitio = sitio_c(s, n.hijos[0], tipos);
    if es_desconocido(vista(sitio)) { return no_se(); }
    let idx = expresion_c(s, n.hijos[1], "usize", tipos);
    if es_desconocido(vista(idx)) { return no_se(); }

    var cuantos = vacio();
    if T.es_lista(vista(base)) {
        cuantos = copiar(sitio);
        empujar(cuantos, ".length");
    } else {
        if T.es_bloque(vista(base)) {
            cuantos = copiar(sitio);
            empujar(cuantos, ".n");
        } else {
            if T.es_arreglo(vista(base)) {
                cuantos = cuantos_de_arreglo(vista(base));
            } else {
                return no_se();
            }
        }
    }

    var r = copiar(sitio);
    empujar(r, ".e[ss_lang_indice_(");
    empujar(r, vista(idx));
    empujar(r, ", ");
    empujar(r, vista(cuantos));
    empujar(r, ", \"");
    empujar(r, vista(s.archivo));
    empujar(r, "\", ");
    empujar(r, texto(n.linea));
    empujar(r, ")]");
    return r;
}

fn binaria_c(s: &Sitio, n: &P.Nodo, _esperado: view, tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 2 { return no_se(); }
    let op = vista(n.texto);

    // Lo logico y lo comparativo salen tal cual: en C significan lo mismo.
    if igual(op, "&&") || igual(op, "||") {
        return junta(s, n, "bool", op, tipos);
    }
    if igual(op, "==") || igual(op, "!=") || igual(op, "<") || igual(op, "<=")
    || igual(op, ">") || igual(op, ">=") {
        let t = tipo_operando(s, n, tipos);
        return junta(s, n, vista(t), op, tipos);
    }

    let t = tipo_operando(s, n, tipos);
    if largo(t) == 0 { return no_se(); }
    // Los decimales tienen su propia comprobacion; no se cubre aqui.
    if igual(vista(t), "f32") || igual(vista(t), "f64") { return no_se(); }

    let fam = familia(op);
    if largo(fam) > 0 {
        let izq = expresion_c(s, n.hijos[0], vista(t), tipos);
        let der = expresion_c(s, n.hijos[1], vista(t), tipos);
        if es_desconocido(vista(izq)) || es_desconocido(vista(der)) {
            return no_se();
        }
        var v = nuevo("ss_lang_");
        empujar(v, vista(fam));
        empujar(v, "_");
        empujar(v, vista(t));
        empujar(v, "(");
        empujar(v, vista(izq));
        empujar(v, ", ");
        empujar(v, vista(der));
        empujar(v, ", \"");
        empujar(v, vista(s.archivo));
        empujar(v, "\", ");
        empujar(v, texto(n.linea));
        empujar(v, ")");
        return v;
    }

    if igual(op, "/") || igual(op, "%") {
        let izq = expresion_c(s, n.hijos[0], vista(t), tipos);
        let der = expresion_c(s, n.hijos[1], vista(t), tipos);
        if es_desconocido(vista(izq)) || es_desconocido(vista(der)) {
            return no_se();
        }
        var v = nuevo("SS_LANG_DIV(");
        if igual(op, "%") { v = nuevo("SS_LANG_MOD("); }
        empujar(v, vista(izq));
        empujar(v, ", ");
        empujar(v, vista(der));
        empujar(v, ", \"");
        empujar(v, vista(s.archivo));
        empujar(v, "\", ");
        empujar(v, texto(n.linea));
        empujar(v, ")");
        return v;
    }

    return no_se();
}

// `(izq OP der)`, que es como salen los operadores que C ya tiene.
fn junta(s: &Sitio, n: &P.Nodo, esperado: view, op: view,
    tipos: &I.Contexto) -> str {
    let izq = expresion_c(s, n.hijos[0], esperado, tipos);
    let der = expresion_c(s, n.hijos[1], esperado, tipos);
    if es_desconocido(vista(izq)) || es_desconocido(vista(der)) {
        return no_se();
    }
    var v = nuevo("(");
    empujar(v, vista(izq));
    empujar(v, " ");
    empujar(v, op);
    empujar(v, " ");
    empujar(v, vista(der));
    empujar(v, ")");
    return v;
}

// El tipo con el que operar los dos lados: el del primero que se sepa.
fn tipo_operando(_s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let a = I.tipo_de(tipos, n.hijos[0]);
    if es_entero(vista(a)) { return a; }
    let b = I.tipo_de(tipos, n.hijos[1]);
    if es_entero(vista(b)) { return b; }
    return nuevo("usize");
}

fn es_entero(t: view) -> bool {
    if igual(t, "usize") || igual(t, "i64") { return true; }
    if igual(t, "u8") || igual(t, "u16") || igual(t, "u32") { return true; }
    if igual(t, "u64") || igual(t, "i8") || igual(t, "i16") { return true; }
    return igual(t, "i32");
}

// Solo las llamadas a funciones del programa: las internas tienen cada una
// su forma, y eso es otra capa.
// Las internas que no necesitan emitir nada aparte: se bajan a una llamada
// del runtime y ya. `byte` no esta porque necesita guardar la vista en un
// temporal antes de indexarla.
fn interna_pura(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let nombre = vista(n.texto);

    if igual(nombre, "vacio") { return nuevo("ss_new()"); }

    if igual(nombre, "largo") {
        if largo(n.hijos) != 1 { return no_se(); }
        let sobre = I.tipo_de(tipos, n.hijos[0]);
        if T.es_lista(vista(sobre)) {
            if !igual(vista(n.hijos[0].clase), "variable") { return no_se(); }
            var r = nuevo("(");
            empujar(r, vista(n.hijos[0].texto));
            empujar(r, ".length)");
            return r;
        }
        let v = como_vista(s, n.hijos[0], tipos);
        if es_desconocido(vista(v)) { return no_se(); }
        var r = nuevo("sv_len_of(");
        empujar(r, vista(v));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "nuevo") {
        if largo(n.hijos) != 1 { return no_se(); }
        let v = como_vista(s, n.hijos[0], tipos);
        if es_desconocido(vista(v)) { return no_se(); }
        var r = nuevo("ss_from_view(");
        empujar(r, vista(v));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "vista") {
        if largo(n.hijos) != 1 { return no_se(); }
        if !igual(vista(n.hijos[0].clase), "variable") { return no_se(); }
        return direccion_de(s, vista(n.hijos[0].texto), "ss_view(");
    }

    if igual(nombre, "igual") || igual(nombre, "menor") {
        if largo(n.hijos) != 2 { return no_se(); }
        let a = como_vista(s, n.hijos[0], tipos);
        let b = como_vista(s, n.hijos[1], tipos);
        if es_desconocido(vista(a)) || es_desconocido(vista(b)) {
            return no_se();
        }
        var r = nuevo("sv_equals(");
        if igual(nombre, "menor") { r = nuevo("(sv_cmp("); }
        empujar(r, vista(a));
        empujar(r, ", ");
        empujar(r, vista(b));
        if igual(nombre, "menor") { empujar(r, ") < 0)"); }
        else { empujar(r, ")"); }
        return r;
    }

    if igual(nombre, "rebanar") {
        if largo(n.hijos) != 3 { return no_se(); }
        let v = como_vista(s, n.hijos[0], tipos);
        let a = expresion_c(s, n.hijos[1], "usize", tipos);
        let b = expresion_c(s, n.hijos[2], "usize", tipos);
        if es_desconocido(vista(v)) || es_desconocido(vista(a))
        || es_desconocido(vista(b)) {
            return no_se();
        }
        var r = nuevo("sv_slice(");
        empujar(r, vista(v));
        empujar(r, ", ");
        empujar(r, vista(a));
        empujar(r, ", ");
        empujar(r, vista(b));
        empujar(r, ")");
        return r;
    }

    return no_se();
}

// La direccion de un sitio con nombre: `&x`, `&p.campo`, `&v.e[i]`. Prestar
// algo recien hecho pediria un temporal del que tomar la direccion, y ese
// temporal habria que soltarlo al acabar la sentencia: otra capa.
fn direccion_del_sitio(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);
    if igual(clase, "variable") {
        // Un `&T` ya ES la direccion: pedirsela otra vez sobra.
        if tiene(s.punteros, vista(n.texto)) { return nuevo(vista(n.texto)); }
        var r = nuevo("&");
        empujar(r, vista(n.texto));
        return r;
    }
    if igual(clase, "campo") || igual(clase, "indice") {
        let donde = expresion_c(s, n, "", tipos);
        if es_desconocido(vista(donde)) { return no_se(); }
        var r = nuevo("&");
        empujar(r, vista(donde));
        return r;
    }
    return no_se();
}

// `ss_view(&x)`, o `ss_view(x)` si `x` ya es un puntero.
fn direccion_de(s: &Sitio, nombre: view, envoltura: view) -> str {
    var r = nuevo(envoltura);
    if !tiene(s.punteros, nombre) { empujar(r, "&"); }
    empujar(r, nombre);
    empujar(r, ")");
    return r;
}

// Un argumento donde se pide una vista: un `view` va tal cual, un `str` se
// presta, y un literal es su propia vista.
fn como_vista(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    if igual(vista(n.clase), "cadena") {
        var r = nuevo("sv_len(");
        empujar(r, literal_c(vista(n.texto)));
        empujar(r, ", ");
        empujar(r, texto(cuantos_bytes(vista(n.texto))));
        empujar(r, ")");
        return r;
    }
    let t = I.tipo_de(tipos, n);
    if igual(vista(t), "str") {
        if !igual(vista(n.clase), "variable") { return no_se(); }
        return direccion_de(s, vista(n.texto), "ss_view(");
    }
    if igual(vista(t), "view") { return expresion_c(s, n, "view", tipos); }
    return no_se();
}

// El literal de C con los mismos bytes. Aqui solo lo que no necesita
// escaparse raro: si lleva algo mas, no se cubre.
fn literal_c(t: view) -> str {
    var r = nuevo("\"");
    var i = 0;
    while i < largo(t) {
        let b = byte(t, i);
        if b == 34 || b == 92 { return no_se(); }
        if b == 10 { empujar(r, "\\n"); }
        else {
            if b == 9 { empujar(r, "\\t"); }
            else { empujar(r, rebanar(t, i, i + 1)); }
        }
        i = i + 1;
    }
    empujar(r, "\"");
    return r;
}

fn cuantos_bytes(t: view) -> usize {
    return largo(t);
}

fn llamada_c(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let nombre = vista(n.texto);
    let pura = interna_pura(s, n, tipos);
    if !es_desconocido(vista(pura)) { return pura; }
    if es_interna(nombre) { return no_se(); }
    if !tiene(tipos.retornos, nombre) { return no_se(); }
    if tiene(tipos.tipo_params, nombre) { return no_se(); }

    let firmados = I.lista_de(tipos.params, nombre) sino [];
    let marcados = I.lista_de(tipos.params_marcados, nombre) sino [];
    var v = nuevo(nombre);
    empujar(v, "(");
    var i = 0;
    for h en n.hijos {
        if i > 0 { empujar(v, ", "); }
        var esperado = vacio();
        if i < largo(firmados) { esperado = copiar(firmados[i]); }

        // Un parametro prestado recibe la direccion, no el valor. Si lo que
        // se le pasa ya es un puntero, se pasa tal cual.
        var presta_el = false;
        if i < largo(marcados) {
            let m = vista(marcados[i]);
            presta_el = empieza_con(m, "&") || empieza_con(m, "mut ");
        }
        if presta_el {
            let dir = direccion_del_sitio(s, h, tipos);
            if es_desconocido(vista(dir)) { return no_se(); }
            empujar(v, vista(dir));
            i = i + 1;
            continue;
        }

        // Pasar una variable con duenio a algo que se la queda es moverla.
        // La bandera la apaga la sentencia; aqui basta con que exista.
        if !presta_el && entrega_variable(s, h, tipos) {
            if !tiene(s.pide_bandera, vista(h.texto)) { return no_se(); }
        }
        let arg = expresion_c(s, h, vista(esperado), tipos);
        if es_desconocido(vista(arg)) { return no_se(); }
        empujar(v, vista(arg));
        i = i + 1;
    }
    empujar(v, ")");
    return v;
}

// Si la expresion entrega una variable entera que tiene duenio: eso es un
// movimiento, y un movimiento pide bandera.
fn entrega_variable(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> bool {
    return entrega_suelta(s.punteros, n, tipos);
}

// Lo mismo sin el `Sitio`: la pasada que decide las banderas corre antes de
// que el `Sitio` exista, porque el `Sitio` las lleva dentro.
fn entrega_suelta(punteros: &mapa<str, usize>, n: &P.Nodo,
    tipos: &I.Contexto) -> bool {
    if !igual(vista(n.clase), "variable") { return false; }
    if tiene(punteros, vista(n.texto)) { return false; }
    let t = I.tipo_de(tipos, n);
    if igual(vista(t), "str") { return true; }
    return T.es_lista(vista(t)) || T.es_mapa(vista(t)) || T.es_bloque(vista(t));
}

// ------------------------------------------------------------------
// Banderas de propiedad
// ------------------------------------------------------------------
//
// Una variable con duenio puede entregarse por unos caminos y no por otros:
//
//     var s = nuevo("hola");
//     if c { guardar(s); }    // por aqui se la llevan
//     // y aqui hay que soltarla, pero solo si no se la llevaron
//
// C no sabe cual de los dos caminos se tomo, asi que se le dice con un
// `bool ss_vivo_s`. Rust hace justo esto desde 1.12, y por lo mismo. C++ lo
// evita cobrando siempre: lo movido queda vacio pero valido y su destructor
// corre igual, uno por cada objeto movido. Go y Swift lo mandan al tiempo de
// ejecucion, recolector o cuentas de referencias. Zig no lo resuelve: lo
// escribe el programador con `defer`, y a veces se equivoca.
//
// Tcode cobra lo que Rust —un `bool` en la pila que el compilador de C borra
// en cuanto puede demostrar que sobra— y no pide escribir nada.

// Si el parametro `i` de `nombre` presta en vez de quedarse con el valor.
fn presta_argumento(tipos: &I.Contexto, nombre: view, i: usize) -> bool {
    // `anadir(xs, v)` y `poner(m, k, v)` prestan la coleccion y se quedan
    // con lo demas. Las otras internas cubiertas toman vistas o escalares.
    if igual(nombre, "anadir") || igual(nombre, "poner") { return i == 0; }
    if es_interna(nombre) { return true; }
    let marcados = I.lista_de(tipos.params_marcados, nombre) sino [];
    if i >= largo(marcados) { return true; }
    let m = vista(marcados[i]);
    return empieza_con(m, "&") || empieza_con(m, "mut ");
}

fn apuntar_movida(salida: mut lista<str>, nombre: view) {
    for x en salida {
        if igual(vista(x), nombre) { return; }
    }
    anadir(salida, nuevo(nombre));
}

// Los nombres que este nodo entrega. Sin entrar en los bloques de dentro:
// cada sentencia apaga las suyas, donde toca.
fn movidas_en(punteros: &mapa<str, usize>, n: &P.Nodo, tipos: &I.Contexto,
    salida: mut lista<str>) {
    let clase = vista(n.clase);
    if igual(clase, "bloque") { return; }

    // `let y = x;` y `y = x;` mueven tanto como pasarla a una funcion.
    if igual(clase, "declaracion") && largo(n.hijos) == 1 {
        if entrega_suelta(punteros, n.hijos[0], tipos) {
            apuntar_movida(salida, vista(n.hijos[0].texto));
        }
    }
    if igual(clase, "asignacion") && largo(n.hijos) == 2 {
        if entrega_suelta(punteros, n.hijos[1], tipos) {
            apuntar_movida(salida, vista(n.hijos[1].texto));
        }
    }

    if igual(clase, "llamada") {
        var i = 0;
        for h en n.hijos {
            if !presta_argumento(tipos, vista(n.texto), i) {
                if entrega_suelta(punteros, h, tipos) {
                    apuntar_movida(salida, vista(h.texto));
                }
            }
            i = i + 1;
        }
    }

    for h en n.hijos { movidas_en(punteros, h, tipos, salida); }
}

// Lo mismo entrando en los bloques de dentro: es la pasada que decide quien
// lleva bandera. Declara los locales segun los va encontrando, porque para
// saber si una variable se entrega hay que saber primero que tiene duenio, y
// eso lo dice su tipo. Devolver una variable no cuenta: ahi ya no queda
// nadie a quien mentirle.
fn movidas_hondo(punteros: &mapa<str, usize>, bloque: &P.Nodo,
    tipos: mut I.Contexto, salida: mut lista<str>) {
    I.abrir(tipos);
    for st en bloque.hijos {
        if igual(vista(st.clase), "declaracion") && largo(st.hijos) == 1 {
            let nombre = nombre_declarado(vista(st.texto));
            var tipo = tipo_escrito(vista(st.texto));
            if largo(tipo) == 0 { tipo = I.tipo_de(tipos, st.hijos[0]); }
            movidas_en(punteros, st, tipos, salida);
            I.declarar(tipos, vista(nombre), vista(tipo));
        } else {
            movidas_en(punteros, st, tipos, salida);
        }
        for h en st.hijos {
            if igual(vista(h.clase), "bloque") {
                movidas_hondo(punteros, h, tipos, salida);
            }
        }
    }
    I.cerrar(tipos);
}

fn es_interna(nombre: view) -> bool {
    if igual(nombre, "byte") { return true; }
    if igual(nombre, "largo") || igual(nombre, "nuevo") { return true; }
    if igual(nombre, "vacio") || igual(nombre, "vista") { return true; }
    if igual(nombre, "rebanar") || igual(nombre, "igual") { return true; }
    if igual(nombre, "menor") { return true; }
    if igual(nombre, "imprimir") || igual(nombre, "empujar") { return true; }
    if igual(nombre, "anadir") || igual(nombre, "poner") { return true; }
    if igual(nombre, "obtener") || igual(nombre, "tiene") { return true; }
    if igual(nombre, "claves") || igual(nombre, "quitar") { return true; }
    if igual(nombre, "texto") || igual(nombre, "copiar") { return true; }
    if igual(nombre, "ordenar") || igual(nombre, "reservar") { return true; }
    return false;
}

// ------------------------------------------------------------------
// Sentencias, y la liberacion automatica
// ------------------------------------------------------------------
//
// Aqui esta lo que hace que Tcode sea Tcode: nadie escribe un `ss_free`, y
// al cerrar un bloque se devuelve lo que nacio dentro, en orden inverso al
// que se declaro. En una funcion, lo que se devuelve no se libera.
//
// Se cubre el subconjunto sin banderas: funciones donde ningun valor se
// mueve a otro sitio. Una bandera hace falta cuando un valor se entrega solo
// por algunos caminos, y eso es la parte dificil, no esta.

struct Cuerpo {
    lineas: lista<str>,
    // Lo declarado en cada bloque abierto: `nombre: tipo`, del mas de fuera
    // al mas de dentro.
    bloques: lista<lista<str>>,
    sangria: usize,
    temporal: usize,
    // La ultima posicion marcada con `#line`, para no repetirla.
    ultima_linea: usize,
    // Cuantos bucles se han abierto: cada uno lleva su propio indice.
    bucle: usize,
}

fn nombre_de_indice(n: usize) -> str {
    var s = nuevo("ss_k");
    empujar(s, texto(n));
    return s;
}

fn nombre_de_bucle(n: usize) -> str {
    var s = nuevo("ss_i");
    empujar(s, texto(n));
    return s;
}

fn cuerpo() -> Cuerpo {
    return Cuerpo { lineas: [], bloques: [], sangria: 1, temporal: 0,
        ultima_linea: 0, bucle: 0 };
}

fn sangrar(b: &Cuerpo) -> str {
    var s = vacio();
    var i = 0;
    while i < b.sangria {
        empujar(s, "    ");
        i = i + 1;
    }
    return s;
}

fn emitir(b: mut Cuerpo, texto_linea: view) {
    var l = sangrar(b);
    empujar(l, texto_linea);
    anadir(b.lineas, l);
}

fn emitir_crudo(b: mut Cuerpo, texto_linea: view) {
    anadir(b.lineas, nuevo(texto_linea));
}

// `#line`: le dice al compilador de C de que linea de Tcode viene lo que
// sigue. Va pegada al margen, que una directiva sangrada no es directiva.
fn marcar(b: mut Cuerpo, s: &Sitio, linea: usize) {
    if linea == 0 || linea == b.ultima_linea { return; }
    b.ultima_linea = linea;
    var l = nuevo("#line ");
    empujar(l, texto(linea));
    empujar(l, " \"");
    empujar(l, vista(s.archivo));
    empujar(l, "\"");
    emitir_crudo(b, vista(l));
}

fn nuevo_temporal(b: mut Cuerpo) -> str {
    b.temporal = b.temporal + 1;
    var s = nuevo("ss_tmp");
    empujar(s, texto(b.temporal));
    return s;
}

fn abrir_bloque(b: mut Cuerpo) {
    let vacio_bloque: lista<str> = [];
    anadir(b.bloques, vacio_bloque);
}

fn anotar_duenio(b: mut Cuerpo, nombre: view, tipo: view) {
    if largo(b.bloques) == 0 { abrir_bloque(b); }
    var junto = nuevo(nombre);
    empujar(junto, ": ");
    empujar(junto, tipo);
    let ultimo = largo(b.bloques) - 1;
    anadir(b.bloques[ultimo], junto);
}

// Suelta lo del bloque de dentro, en orden inverso, y lo quita de la pila.
fn cerrar_bloque(b: mut Cuerpo, s: &Sitio) {
    if largo(b.bloques) == 0 { return; }
    let ultimo = largo(b.bloques) - 1;
    liberar_uno(b, s, ultimo, "");
    quitar_ultimo_bloque(b);
}

fn quitar_ultimo_bloque(b: mut Cuerpo) {
    var quedan: lista<lista<str>> = [];
    var i = 0;
    while i + 1 < largo(b.bloques) {
        var copia: lista<str> = [];
        for x en b.bloques[i] { anadir(copia, copiar(x)); }
        anadir(quedan, copia);
        i = i + 1;
    }
    b.bloques = quedan;
}

// Todo lo vivo, de dentro hacia fuera: es lo que hace falta antes de un
// `return`, donde no se cierra un bloque sino todos.
fn liberar_todo(b: mut Cuerpo, s: &Sitio, excepto: view) {
    var i = largo(b.bloques);
    while i > 0 {
        i = i - 1;
        liberar_uno(b, s, i, excepto);
    }
}

fn liberar_uno(b: mut Cuerpo, s: &Sitio, cual: usize, excepto: view) {
    var j = largo(b.bloques[cual]);
    while j > 0 {
        j = j - 1;
        let entrada = copiar(b.bloques[cual][j]);
        let nombre = antes_de_dos_puntos(vista(entrada));
        if igual(vista(nombre), excepto) { continue; }
        let tipo = despues_de_dos_puntos(vista(entrada));
        // Si se entrega por algun camino, quien decide es la bandera: aqui
        // no se sabe por cual se vino.
        if tiene(s.pide_bandera, vista(nombre)) {
            var g = nuevo("if (ss_vivo_");
            empujar(g, vista(nombre));
            empujar(g, ")");
            emitir(b, vista(g));
            emitir(b, "{");
            b.sangria = b.sangria + 1;
            liberacion(b, vista(nombre), vista(tipo));
            b.sangria = b.sangria - 1;
            emitir(b, "}");
            continue;
        }
        liberacion(b, vista(nombre), vista(tipo));
    }
}

// `bool ss_vivo_x = true;` justo detras de la declaracion de `x`.
fn nace_bandera(b: mut Cuerpo, nombre: view) {
    var l = nuevo("bool ss_vivo_");
    empujar(l, nombre);
    empujar(l, " = true;");
    emitir(b, vista(l));
}

// `ss_vivo_x = false;` por cada una que se entrego en el camino que acaba.
fn apagar(b: mut Cuerpo, nombres: &lista<str>) {
    for nm en nombres {
        var l = nuevo("ss_vivo_");
        empujar(l, vista(nm));
        empujar(l, " = false;");
        emitir(b, vista(l));
    }
}

// Lo que hay que soltar, dentro del subconjunto que esta capa emite.
// `T.posee` sabe mas —structs, arreglos— pero pide los campos de todos los
// structs y puede fallar; aqui no hace falta tanto.
fn tiene_duenio(t: view) -> bool {
    if igual(t, "str") { return true; }
    return T.es_lista(t) || T.es_mapa(t) || T.es_bloque(t);
}

fn liberacion(b: mut Cuerpo, nombre: view, tipo: view) {
    if igual(tipo, "str") {
        var l = nuevo("ss_free(&");
        empujar(l, nombre);
        empujar(l, ");");
        emitir(b, vista(l));
        return;
    }
    // Una lista suelta su memoria y se queda vacia. Si sus elementos tienen
    // duenio, cada uno se suelta antes: la lista era su unica duenia.
    if T.es_lista(tipo) {
        let elem = T.elemento(tipo);
        if tiene_duenio(vista(elem)) {
            b.bucle = b.bucle + 1;
            let i = nombre_de_bucle(b.bucle);
            var f = nuevo("for (size_t ");
            empujar(f, vista(i));
            empujar(f, " = 0; ");
            empujar(f, vista(i));
            empujar(f, " < ");
            empujar(f, nombre);
            empujar(f, ".length; ");
            empujar(f, vista(i));
            empujar(f, "++)");
            emitir(b, vista(f));
            emitir(b, "{");
            b.sangria = b.sangria + 1;
            var dentro = nuevo(nombre);
            empujar(dentro, ".e[");
            empujar(dentro, vista(i));
            empujar(dentro, "]");
            liberacion(b, vista(dentro), vista(elem));
            b.sangria = b.sangria - 1;
            emitir(b, "}");
        }
        var l = nuevo("free(");
        empujar(l, nombre);
        empujar(l, ".e);");
        emitir(b, vista(l));
        var a = nuevo(nombre);
        empujar(a, ".e = NULL;");
        emitir(b, vista(a));
        var c = nuevo(nombre);
        empujar(c, ".length = 0;");
        emitir(b, vista(c));
        var d = nuevo(nombre);
        empujar(d, ".capacity = 0;");
        emitir(b, vista(d));
    }
}

fn antes_de_dos_puntos(t: view) -> str {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 58 { return nuevo(rebanar(t, 0, i)); }
        i = i + 1;
    }
    return nuevo(t);
}

fn despues_de_dos_puntos(t: view) -> str {
    var i = 0;
    while i + 1 < largo(t) {
        if byte(t, i) == 58 {
            return nuevo(rebanar(t, i + 2, largo(t)));
        }
        i = i + 1;
    }
    return vacio();
}

// Una sentencia. Devuelve false si esta capa no la sabe hacer: entonces la
// funcion entera se descarta, porque media funcion generada no vale nada.
// Lo que esta sentencia entrego, apagado aqui mismo: el camino se acaba.
fn apagar_las_de(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) {
    var salen: lista<str> = [];
    movidas_en(s.punteros, n, tipos, salen);
    var vivas: lista<str> = [];
    for nm en salen {
        if tiene(s.pide_bandera, vista(nm)) { anadir(vivas, copiar(nm)); }
    }
    apagar(b, vivas);
}

// `for k, v en m` lleva dos nombres separados por coma.
fn lleva_coma(t: view) -> bool {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 44 { return true; }
        i = i + 1;
    }
    return false;
}

fn mueve_algo(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> bool {
    var salen: lista<str> = [];
    movidas_en(s.punteros, n, tipos, salen);
    return largo(salen) > 0;
}

fn sentencia_c(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo,
    tipos: mut I.Contexto, retorno: view, falible: bool) -> bool {
    let clase = vista(n.clase);
    marcar(b, s, n.linea);

    if igual(clase, "declaracion") {
        if largo(n.hijos) != 1 { return false; }
        let nombre = nombre_declarado(vista(n.texto));
        var tipo = tipo_escrito(vista(n.texto));
        if largo(tipo) == 0 { tipo = I.tipo_de(tipos, n.hijos[0]); }
        if largo(tipo) == 0 { return false; }

        var valor = vacio();
        let cual = vista(n.hijos[0].clase);

        if igual(cual, "try") {
            // `try f(...)`: se guarda el resultado, y si trae motivo se sale
            // por el mismo camino sin tocar lo que ya esta vivo.
            if !falible { return false; }
            valor = try_c(b, s, n.hijos[0], tipos, retorno);
        } else {
            if igual(cual, "literal_lista") && largo(n.hijos[0].hijos) == 0 {
                // Una lista vacia no reserva nada: nace en el primer
                // `anadir`, que es donde el coste se ve.
                if !T.es_lista(vista(tipo)) { return false; }
                let tmp = nuevo_temporal(b);
                var l = nuevo(tipo_c(vista(tipo)));
                empujar(l, " ");
                empujar(l, vista(tmp));
                empujar(l, " = { .e = NULL, .length = 0, .capacity = 0 };");
                emitir(b, vista(l));
                valor = copiar(tmp);
            } else {
                valor = expresion_c(s, n.hijos[0], vista(tipo), tipos);
            }
        }
        if es_desconocido(vista(valor)) { return false; }

        var l = nuevo("SS_LANG_QUIZA_SIN_USAR ");
        empujar(l, tipo_c(vista(tipo)));
        empujar(l, " ");
        empujar(l, vista(nombre));
        empujar(l, " = ");
        empujar(l, vista(valor));
        empujar(l, ";");
        emitir(b, vista(l));

        I.declarar(tipos, vista(nombre), vista(tipo));
        if igual(vista(tipo), "str") || T.es_lista(vista(tipo)) {
            anotar_duenio(b, vista(nombre), vista(tipo));
            if tiene(s.pide_bandera, vista(nombre)) {
                nace_bandera(b, vista(nombre));
            }
        }
        apagar_las_de(b, s, n, tipos);
        return true;
    }

    if igual(clase, "expresion") {
        if largo(n.hijos) != 1 { return false; }
        if anadir_c(b, s, n.hijos[0], tipos) {
            apagar_las_de(b, s, n, tipos);
            return true;
        }
        // Una llamada suelta a una funcion que no devuelve nada. Si
        // devolviera algo con duenio habria que soltarlo aqui mismo, y eso
        // es otra capa: por ahora se descarta la funcion entera.
        if !igual(vista(n.hijos[0].clase), "llamada") { return false; }
        let quien = vista(n.hijos[0].texto);
        if es_interna(quien) { return false; }
        if !tiene(tipos.retornos, quien) { return false; }
        let devuelve = nuevo(obtener(tipos.retornos, quien) sino "?");
        if largo(vista(devuelve)) > 0 { return false; }
        let hecha = llamada_c(s, n.hijos[0], tipos);
        if es_desconocido(vista(hecha)) { return false; }
        var l = copiar(hecha);
        empujar(l, ";");
        emitir(b, vista(l));
        apagar_las_de(b, s, n, tipos);
        return true;
    }

    if igual(clase, "falla") {
        // Salir por el camino malo: se suelta todo y se devuelve el motivo.
        if !falible { return false; }
        liberar_todo(b, s, "");
        var l = nuevo("return (");
        empujar(l, tipo_resultado(retorno));
        empujar(l, "){ .motivo = ");
        empujar(l, literal_c(vista(n.texto)));
        empujar(l, " };");
        emitir(b, vista(l));
        return true;
    }

    if igual(clase, "retorno") {
        if largo(n.hijos) == 0 {
            liberar_todo(b, s, "");
            if falible {
                var l = nuevo("return (");
                empujar(l, tipo_resultado(retorno));
                empujar(l, "){ .motivo = NULL };");
                emitir(b, vista(l));
                return true;
            }
            emitir(b, "return;");
            return true;
        }
        // Devolver una variable entera no necesita temporal: no hay nada
        // que calcular, y liberar lo demas no la toca.
        if igual(vista(n.hijos[0].clase), "variable") {
            let quien = vista(n.hijos[0].texto);
            liberar_todo(b, s, quien);
            let c = expresion_c(s, n.hijos[0], retorno, tipos);
            var r = nuevo("return ");
            if falible {
                empujar(r, "(");
                empujar(r, tipo_resultado(retorno));
                empujar(r, "){ .motivo = NULL, .valor = ");
                empujar(r, vista(c));
                empujar(r, " };");
            } else {
                empujar(r, vista(c));
                empujar(r, ";");
            }
            emitir(b, vista(r));
            return true;
        }

        let valor = expresion_c(s, n.hijos[0], retorno, tipos);
        if es_desconocido(vista(valor)) { return false; }
        // El valor se guarda antes de soltar nada: puede leer justo lo que
        // se va a liberar.
        let tmp = nuevo_temporal(b);
        var l = nuevo(tipo_c(retorno));
        empujar(l, " ");
        empujar(l, vista(tmp));
        empujar(l, " = ");
        empujar(l, vista(valor));
        empujar(l, ";");
        emitir(b, vista(l));
        // Antes de liberar, y no despues: lo que se apague detras de un
        // `return` no se ejecuta nunca, y la liberacion veria la bandera
        // encendida todavia.
        apagar_las_de(b, s, n, tipos);
        // Lo que se entrega no se libera.
        var entregada = vacio();
        if igual(vista(n.hijos[0].clase), "variable") {
            entregada = nuevo(vista(n.hijos[0].texto));
        }
        liberar_todo(b, s, vista(entregada));
        var r = nuevo("return ");
        if falible {
            // En una falible lo que se devuelve va envuelto: `motivo` a
            // NULL dice que fue bien.
            empujar(r, "(");
            empujar(r, tipo_resultado(retorno));
            empujar(r, "){ .motivo = NULL, .valor = ");
            empujar(r, vista(tmp));
            empujar(r, " };");
        } else {
            empujar(r, vista(tmp));
            empujar(r, ";");
        }
        emitir(b, vista(r));
        return true;
    }

    if igual(clase, "si") {
        if largo(n.hijos) < 2 { return false; }
        if mueve_algo(s, n.hijos[0], tipos) { return false; }
        let cond = expresion_c(s, n.hijos[0], "bool", tipos);
        if es_desconocido(vista(cond)) { return false; }
        var l = nuevo("if (");
        empujar(l, vista(cond));
        empujar(l, ")");
        emitir(b, vista(l));
        if !bloque_c(b, s, n.hijos[1], tipos, retorno, falible) {
            return false;
        }
        if largo(n.hijos) > 2 {
            emitir(b, "else");
            if !bloque_c(b, s, n.hijos[2], tipos, retorno, falible) {
                return false;
            }
        }
        return true;
    }

    if igual(clase, "mientras") {
        if largo(n.hijos) != 2 { return false; }
        if mueve_algo(s, n.hijos[0], tipos) { return false; }
        let cond = expresion_c(s, n.hijos[0], "bool", tipos);
        if es_desconocido(vista(cond)) { return false; }
        var l = nuevo("while (");
        empujar(l, vista(cond));
        empujar(l, ")");
        emitir(b, vista(l));
        return bloque_c(b, s, n.hijos[1], tipos, retorno, falible);
    }

    if igual(clase, "asignacion") {
        if largo(n.hijos) != 2 { return false; }
        if !igual(vista(n.hijos[0].clase), "variable") { return false; }
        let nombre = vista(n.hijos[0].texto);
        let tipo = I.buscar(tipos, nombre);
        let valor = expresion_c(s, n.hijos[1], vista(tipo), tipos);
        if es_desconocido(vista(valor)) { return false; }
        let destino = expresion_c(s, n.hijos[0], vista(tipo), tipos);
        if es_desconocido(vista(destino)) { return false; }

        // Asignar a algo con duenio pide soltar lo viejo. Solo lo que
        // `liberacion` sabe soltar entero: un mapa se iria sin liberar.
        if tiene_duenio(vista(tipo)) {
            if !igual(vista(tipo), "str") && !T.es_lista(vista(tipo)) {
                return false;
            }
            // El valor se guarda antes de soltar lo viejo, porque en C lo
            // que cuenta no es donde se calculo la expresion sino donde
            // queda escrita: `s = nuevo(rebanar(vista(s), 0, 6))` leeria
            // `s` despues de haberlo soltado.
            let tmp = nuevo_temporal(b);
            var g = nuevo(tipo_c(vista(tipo)));
            empujar(g, " ");
            empujar(g, vista(tmp));
            empujar(g, " = ");
            empujar(g, vista(valor));
            empujar(g, ";");
            emitir(b, vista(g));

            if tiene(s.pide_bandera, nombre) {
                // Si ya se lo llevaron, aqui no hay nada que devolver:
                // soltarlo seria soltarlo dos veces.
                var w = nuevo("if (ss_vivo_");
                empujar(w, nombre);
                empujar(w, ")");
                emitir(b, vista(w));
                emitir(b, "{");
                b.sangria = b.sangria + 1;
                liberacion(b, vista(destino), vista(tipo));
                b.sangria = b.sangria - 1;
                emitir(b, "}");
                var a = copiar(destino);
                empujar(a, " = ");
                empujar(a, vista(tmp));
                empujar(a, ";");
                emitir(b, vista(a));
                var enciende = nuevo("ss_vivo_");
                empujar(enciende, nombre);
                empujar(enciende, " = true;");
                emitir(b, vista(enciende));
                apagar_las_de(b, s, n, tipos);
                return true;
            }
            liberacion(b, vista(destino), vista(tipo));
            var a = copiar(destino);
            empujar(a, " = ");
            empujar(a, vista(tmp));
            empujar(a, ";");
            emitir(b, vista(a));
            apagar_las_de(b, s, n, tipos);
            return true;
        }

        var l = copiar(destino);
        empujar(l, " = ");
        empujar(l, vista(valor));
        empujar(l, ";");
        emitir(b, vista(l));
        apagar_las_de(b, s, n, tipos);
        return true;
    }

    if igual(clase, "para") {
        if largo(n.hijos) != 2 { return false; }
        // `for k, v en mapa`: recorrer una tabla es otra capa.
        if lleva_coma(vista(n.texto)) { return false; }
        // La coleccion tiene que ser una variable: `for x en f(...)` se
        // calcula una sola vez y eso pide un temporal que soltar al final.
        if !igual(vista(n.hijos[0].clase), "variable") { return false; }
        let suyo = I.tipo_de(tipos, n.hijos[0]);
        let sobre = T.apuntado_si(vista(suyo));
        if !T.es_lista(vista(sobre)) { return false; }
        let lugar = expresion_c(s, n.hijos[0], vista(sobre), tipos);
        if es_desconocido(vista(lugar)) { return false; }

        b.bucle = b.bucle + 1;
        let i = nombre_de_indice(b.bucle);
        var f = nuevo("for (size_t ");
        empujar(f, vista(i));
        empujar(f, " = 0; ");
        empujar(f, vista(i));
        empujar(f, " < ");
        empujar(f, vista(lugar));
        empujar(f, ".length; ");
        empujar(f, vista(i));
        empujar(f, "++)");
        emitir(b, vista(f));
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        abrir_bloque(b);
        I.abrir(tipos);

        // El elemento se presta, no se copia: un `str` copiado tendria dos
        // duenios. Los escalares van por valor, que no hay nada que duplicar.
        let elem = T.elemento(vista(sobre));
        let quien = vista(n.texto);
        var acceso = copiar(lugar);
        empujar(acceso, ".e[");
        empujar(acceso, vista(i));
        empujar(acceso, "]");
        var d = nuevo("SS_LANG_QUIZA_SIN_USAR ");
        let presta = tiene_duenio(vista(elem));
        if presta {
            empujar(d, "const ");
            empujar(d, tipo_c(vista(elem)));
            empujar(d, "* ");
            empujar(d, quien);
            empujar(d, " = &");
        } else {
            empujar(d, tipo_c(vista(elem)));
            empujar(d, " ");
            empujar(d, quien);
            empujar(d, " = ");
        }
        empujar(d, vista(acceso));
        empujar(d, ";");
        emitir(b, vista(d));
        I.declarar(tipos, quien, vista(elem));
        let ya_era = tiene(s.punteros, quien);
        if presta { poner(s.punteros, quien, 1); }

        var bien = true;
        for st en n.hijos[1].hijos {
            if bien { bien = sentencia_c(b, s, st, tipos, retorno, falible); }
        }
        if bien && !termina_saliendo(n.hijos[1]) { cerrar_bloque(b, s); }
        else { quitar_ultimo_bloque(b); }

        if presta && !ya_era { quitar(s.punteros, quien); }
        I.cerrar(tipos);
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        return bien;
    }

    if igual(clase, "romper") { emitir(b, "break;"); return true; }
    if igual(clase, "continuar") { emitir(b, "continue;"); return true; }

    return false;
}

fn bloque_c(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo, tipos: mut I.Contexto,
    retorno: view, falible: bool) -> bool {
    emitir(b, "{");
    b.sangria = b.sangria + 1;
    abrir_bloque(b);
    I.abrir(tipos);
    var bien = true;
    for h en n.hijos {
        if bien { bien = sentencia_c(b, s, h, tipos, retorno, falible); }
    }
    if bien && !termina_saliendo(n) { cerrar_bloque(b, s); }
    else { quitar_ultimo_bloque(b); }
    I.cerrar(tipos);
    b.sangria = b.sangria - 1;
    emitir(b, "}");
    return bien;
}

// Un bloque que acaba en `return` no cierra nada: ya se solto todo alli.
fn termina_saliendo(n: &P.Nodo) -> bool {
    if largo(n.hijos) == 0 { return false; }
    let ultimo = largo(n.hijos) - 1;
    let c = vista(n.hijos[ultimo].clase);
    return igual(c, "retorno") || igual(c, "romper") || igual(c, "continuar");
}

fn nombre_declarado(texto: view) -> str {
    var desde = 0;
    var i = 0;
    while i < largo(texto) {
        if byte(texto, i) == 32 { desde = i + 1; break; }
        i = i + 1;
    }
    var j = desde;
    while j < largo(texto) {
        if byte(texto, j) == 58 { return nuevo(rebanar(texto, desde, j)); }
        j = j + 1;
    }
    return nuevo(rebanar(texto, desde, largo(texto)));
}

fn tipo_escrito(texto: view) -> str {
    var i = 0;
    while i + 1 < largo(texto) {
        if byte(texto, i) == 58 {
            if byte(texto, i + 1) == 32 {
                return nuevo(recortar(rebanar(texto, i + 2, largo(texto))));
            }
        }
        i = i + 1;
    }
    return vacio();
}

// `try f(...)`: deja el resultado en un temporal, sale si trae motivo, y
// devuelve el C que lee el valor.
fn try_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto,
    retorno: view) -> str {
    if largo(n.hijos) != 1 { return no_se(); }
    if !igual(vista(n.hijos[0].clase), "llamada") { return no_se(); }
    let llamado = vista(n.hijos[0].texto);
    if !tiene(tipos.retornos, llamado) { return no_se(); }
    let suyo = nuevo(obtener(tipos.retornos, llamado) sino "");

    let c = llamada_c(s, n.hijos[0], tipos);
    if es_desconocido(vista(c)) { return no_se(); }

    let tmp = nuevo_temporal(b);
    var l = nuevo(tipo_resultado(vista(suyo)));
    empujar(l, " ");
    empujar(l, vista(tmp));
    empujar(l, " = ");
    empujar(l, vista(c));
    empujar(l, ";");
    emitir(b, vista(l));

    var cond = nuevo("if (");
    empujar(cond, vista(tmp));
    empujar(cond, ".motivo != NULL)");
    emitir(b, vista(cond));
    emitir(b, "{");
    b.sangria = b.sangria + 1;
    liberar_todo(b, s, "");
    var sale = nuevo("return (");
    empujar(sale, tipo_resultado(retorno));
    empujar(sale, "){ .motivo = ");
    empujar(sale, vista(tmp));
    empujar(sale, ".motivo };");
    emitir(b, vista(sale));
    b.sangria = b.sangria - 1;
    emitir(b, "}");

    var leer = copiar(tmp);
    empujar(leer, ".valor");
    return leer;
}

// `anadir(xs, v)`: la lista se queda con el valor.
fn anadir_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> bool {
    if !igual(vista(n.clase), "llamada") { return false; }
    if !igual(vista(n.texto), "anadir") { return false; }
    if largo(n.hijos) != 2 { return false; }
    if !igual(vista(n.hijos[0].clase), "variable") { return false; }
    let sobre = I.tipo_de(tipos, n.hijos[0]);
    if !T.es_lista(vista(sobre)) { return false; }
    let elem = T.elemento(vista(sobre));
    // Meter una variable con duenio en una lista la mueve: la lista se la
    // queda y desde aqui la suelta ella.
    if entrega_variable(s, n.hijos[1], tipos) {
        if !tiene(s.pide_bandera, vista(n.hijos[1].texto)) { return false; }
    }
    let valor = expresion_c(s, n.hijos[1], vista(elem), tipos);
    if es_desconocido(vista(valor)) { return false; }

    var l = nuevo("ss_push_");
    empujar(l, mangle(vista(sobre)));
    empujar(l, "(");
    if !tiene(s.punteros, vista(n.hijos[0].texto)) { empujar(l, "&"); }
    empujar(l, vista(n.hijos[0].texto));
    empujar(l, ", ");
    empujar(l, vista(valor));
    empujar(l, ", \"");
    empujar(l, vista(s.archivo));
    empujar(l, "\", ");
    empujar(l, texto(n.linea));
    empujar(l, ");");
    emitir(b, vista(l));
    return true;
}

// Lo que cierra una funcion falible que llega al final sin fallar.
fn emitir_final_bien(b: mut Cuerpo, retorno: view) {
    var l = nuevo("return (");
    empujar(l, tipo_resultado(retorno));
    empujar(l, "){ .motivo = NULL };");
    emitir(b, vista(l));
}
