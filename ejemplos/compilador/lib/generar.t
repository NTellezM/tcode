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
    return nuevo(t);
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
    // Un struct se llama igual en los dos lados.
    return nuevo(t);
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
    else { empujar(salida, nombre); }
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
        if presta_el && igual(vista(h.clase), "variable") {
            if tiene(s.punteros, vista(h.texto)) {
                empujar(v, vista(h.texto));
            } else {
                empujar(v, "&");
                empujar(v, vista(h.texto));
            }
            i = i + 1;
            continue;
        }

        let arg = expresion_c(s, h, vista(esperado), tipos);
        if es_desconocido(vista(arg)) { return no_se(); }
        empujar(v, vista(arg));
        i = i + 1;
    }
    empujar(v, ")");
    return v;
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
}

fn cuerpo() -> Cuerpo {
    return Cuerpo { lineas: [], bloques: [], sangria: 1, temporal: 0,
        ultima_linea: 0 };
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
fn cerrar_bloque(b: mut Cuerpo) {
    if largo(b.bloques) == 0 { return; }
    let ultimo = largo(b.bloques) - 1;
    liberar_uno(b, ultimo, "");
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
fn liberar_todo(b: mut Cuerpo, excepto: view) {
    var i = largo(b.bloques);
    while i > 0 {
        i = i - 1;
        liberar_uno(b, i, excepto);
    }
}

fn liberar_uno(b: mut Cuerpo, cual: usize, excepto: view) {
    var j = largo(b.bloques[cual]);
    while j > 0 {
        j = j - 1;
        let entrada = copiar(b.bloques[cual][j]);
        let nombre = antes_de_dos_puntos(vista(entrada));
        if igual(vista(nombre), excepto) { continue; }
        let tipo = despues_de_dos_puntos(vista(entrada));
        liberacion(b, vista(nombre), vista(tipo));
    }
}

fn liberacion(b: mut Cuerpo, nombre: view, tipo: view) {
    if igual(tipo, "str") {
        var l = nuevo("ss_free(&");
        empujar(l, nombre);
        empujar(l, ");");
        emitir(b, vista(l));
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
fn sentencia_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo,
    tipos: mut I.Contexto, retorno: view) -> bool {
    let clase = vista(n.clase);
    marcar(b, s, n.linea);

    if igual(clase, "declaracion") {
        if largo(n.hijos) != 1 { return false; }
        let nombre = nombre_declarado(vista(n.texto));
        var tipo = tipo_escrito(vista(n.texto));
        if largo(tipo) == 0 { tipo = I.tipo_de(tipos, n.hijos[0]); }
        if largo(tipo) == 0 { return false; }
        let valor = expresion_c(s, n.hijos[0], vista(tipo), tipos);
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
        if igual(vista(tipo), "str") {
            anotar_duenio(b, vista(nombre), vista(tipo));
        }
        return true;
    }

    if igual(clase, "retorno") {
        if largo(n.hijos) == 0 {
            liberar_todo(b, "");
            emitir(b, "return;");
            return true;
        }
        // Devolver una variable entera no necesita temporal: no hay nada
        // que calcular, y liberar lo demas no la toca.
        if igual(vista(n.hijos[0].clase), "variable") {
            let quien = vista(n.hijos[0].texto);
            liberar_todo(b, quien);
            var r = nuevo("return ");
            empujar(r, expresion_c(s, n.hijos[0], retorno, tipos));
            empujar(r, ";");
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
        // Lo que se entrega no se libera.
        var entregada = vacio();
        if igual(vista(n.hijos[0].clase), "variable") {
            entregada = nuevo(vista(n.hijos[0].texto));
        }
        liberar_todo(b, vista(entregada));
        var r = nuevo("return ");
        empujar(r, vista(tmp));
        empujar(r, ";");
        emitir(b, vista(r));
        return true;
    }

    if igual(clase, "si") {
        if largo(n.hijos) < 2 { return false; }
        let cond = expresion_c(s, n.hijos[0], "bool", tipos);
        if es_desconocido(vista(cond)) { return false; }
        var l = nuevo("if (");
        empujar(l, vista(cond));
        empujar(l, ")");
        emitir(b, vista(l));
        if !bloque_c(b, s, n.hijos[1], tipos, retorno) { return false; }
        if largo(n.hijos) > 2 {
            emitir(b, "else");
            if !bloque_c(b, s, n.hijos[2], tipos, retorno) { return false; }
        }
        return true;
    }

    if igual(clase, "mientras") {
        if largo(n.hijos) != 2 { return false; }
        let cond = expresion_c(s, n.hijos[0], "bool", tipos);
        if es_desconocido(vista(cond)) { return false; }
        var l = nuevo("while (");
        empujar(l, vista(cond));
        empujar(l, ")");
        emitir(b, vista(l));
        return bloque_c(b, s, n.hijos[1], tipos, retorno);
    }

    if igual(clase, "asignacion") {
        if largo(n.hijos) != 2 { return false; }
        if !igual(vista(n.hijos[0].clase), "variable") { return false; }
        let nombre = vista(n.hijos[0].texto);
        let tipo = I.buscar(tipos, nombre);
        // Asignar a algo con duenio pide soltar lo viejo: otra capa.
        if igual(vista(tipo), "str") { return false; }
        let valor = expresion_c(s, n.hijos[1], vista(tipo), tipos);
        if es_desconocido(vista(valor)) { return false; }
        var l = nuevo(nombre);
        empujar(l, " = ");
        empujar(l, vista(valor));
        empujar(l, ";");
        emitir(b, vista(l));
        return true;
    }

    if igual(clase, "romper") { emitir(b, "break;"); return true; }
    if igual(clase, "continuar") { emitir(b, "continue;"); return true; }

    return false;
}

fn bloque_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: mut I.Contexto,
    retorno: view) -> bool {
    emitir(b, "{");
    b.sangria = b.sangria + 1;
    abrir_bloque(b);
    I.abrir(tipos);
    var bien = true;
    for h en n.hijos {
        if bien { bien = sentencia_c(b, s, h, tipos, retorno); }
    }
    if bien && !termina_saliendo(n) { cerrar_bloque(b); }
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
