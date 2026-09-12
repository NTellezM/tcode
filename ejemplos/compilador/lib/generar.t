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
fn llamada_c(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let nombre = vista(n.texto);
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
    if igual(nombre, "largo") || igual(nombre, "byte") { return true; }
    if igual(nombre, "nuevo") || igual(nombre, "vacio") { return true; }
    if igual(nombre, "vista") || igual(nombre, "rebanar") { return true; }
    if igual(nombre, "igual") || igual(nombre, "menor") { return true; }
    if igual(nombre, "imprimir") || igual(nombre, "empujar") { return true; }
    if igual(nombre, "anadir") || igual(nombre, "poner") { return true; }
    if igual(nombre, "obtener") || igual(nombre, "tiene") { return true; }
    if igual(nombre, "claves") || igual(nombre, "quitar") { return true; }
    if igual(nombre, "texto") || igual(nombre, "copiar") { return true; }
    if igual(nombre, "ordenar") || igual(nombre, "reservar") { return true; }
    return false;
}
