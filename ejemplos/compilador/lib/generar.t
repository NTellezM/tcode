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
    // lo que devuelve la funcion que se esta generando: `try` sale por ahi
    retorno: str,
}

// Que nombres son un puntero en el C generado: los parametros prestados, y
// tambien un local cuyo tipo es un prestamo. `let xs = try obtener(m, k)` da
// un `&lista<str>`, y eso en C es un puntero como cualquier otro.
fn es_puntero(s: &Sitio, tipos: &I.Contexto, nombre: view) -> bool {
    if tiene(s.punteros, nombre) { return true; }
    let t = I.buscar(tipos, nombre);
    return T.es_referencia(vista(t));
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

fn expresion_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, esperado: view, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);

    if igual(clase, "entero") { return literal_entero(vista(n.texto), esperado); }
    if igual(clase, "booleano") { return nuevo(vista(n.texto)); }

    // Una cadena escrita es una vista de si misma: no reserva nada, y vive
    // lo que vive el programa.
    if igual(clase, "cadena") { return como_vista(b, s, n, tipos); }

    if igual(clase, "expresion") {
        if largo(n.hijos) == 1 {
            return expresion_c(b, s, n.hijos[0], esperado, tipos);
        }
        return no_se();
    }

    if igual(clase, "variable") {
        let nombre = vista(n.texto);
        if es_puntero(s, tipos, nombre) {
            var v = nuevo("(*");
            empujar(v, nombre);
            empujar(v, ")");
            return v;
        }
        return nuevo(nombre);
    }

    if igual(clase, "llamada") {
        return llamada_c(b, s, n, tipos);
    }

    if igual(clase, "conversion") { return conversion_c(b, s, n, tipos); }

    if igual(clase, "literal_struct") {
        return literal_struct_c(b, s, n, tipos);
    }

    // `Json.Numero(42)`: la etiqueta de la forma y, en su hueco de la union,
    // lo que lleve. La variante se queda con lo que recibe.
    if igual(clase, "enum_lit") {
        let en_t = I.antes_del_punto(vista(n.texto));
        let cual = I.tras_el_punto(vista(n.texto));
        // Con el alias de un modulo delante no se sabe como quedo el nombre.
        if contiene(vista(cual), ".") { return no_se(); }
        let lleva = I.lista_de(tipos.formas, vista(n.texto)) sino [];
        if largo(lleva) != largo(n.hijos) { return no_se(); }
        let etq = etiqueta(vista(en_t), vista(cual));
        var r = $"({en_t}){{ .etiqueta = {etq}";
        var i = 0;
        for h en n.hijos {
            let valor = expresion_c(b, s, h, vista(lleva[i]), tipos);
            if es_desconocido(vista(valor)) { return no_se(); }
            reclamar(b, vista(valor));
            let pieza = $", .dato.v_{cual}._{i} = {valor}";
            empujar(r, vista(pieza));
            i = i + 1;
        }
        empujar(r, " }");
        return r;
    }

    if igual(clase, "interpolada") { return interpolada_c(b, s, n, tipos); }

    if igual(clase, "si_expr") { return si_expr_c(b, s, n, tipos); }

    if igual(clase, "try") { return try_c(b, s, n, tipos); }
    if igual(clase, "sino") { return sino_c(b, s, n, tipos); }

    // Un decimal va tal cual se escribio, con sufijo si el destino es de
    // 32 bits: `2.5` en un `f32` sin la `f` seria un `double` recortado.
    if igual(clase, "decimal") {
        var r = nuevo(vista(n.texto));
        if !contiene(vista(n.texto), ".") && !contiene(vista(n.texto), "e")
        && !contiene(vista(n.texto), "E") {
            empujar(r, ".0");
        }
        if igual(esperado, "f32") { empujar(r, "f"); }
        return r;
    }

    // `[a, b]` donde se espera una lista: nace vacia y se van metiendo.
    if igual(clase, "literal_lista") && T.es_lista(esperado) {
        let elem = T.elemento(esperado);
        let tmp = nuevo_temporal(b);
        var l = nuevo(tipo_c(esperado));
        empujar(l, " ");
        empujar(l, vista(tmp));
        empujar(l, " = { .e = NULL, .length = 0, .capacity = 0 };");
        emitir(b, vista(l));
        for x en n.hijos {
            let valor = expresion_c(b, s, x, vista(elem), tipos);
            if es_desconocido(vista(valor)) { return no_se(); }
            reclamar(b, vista(valor));
            var mete = nuevo("ss_push_");
            empujar(mete, mangle(esperado));
            empujar(mete, "(&");
            empujar(mete, vista(tmp));
            empujar(mete, ", ");
            empujar(mete, vista(valor));
            empujar(mete, ", \"");
            empujar(mete, vista(s.archivo));
            empujar(mete, "\", ");
            empujar(mete, texto(n.linea));
            empujar(mete, ");");
            emitir(b, vista(mete));
        }
        return copiar(tmp);
    }

    // `[a, b, c]` de tamaño fijo: un literal compuesto de C, de una vez.
    if igual(clase, "literal_lista") && !T.es_mapa(esperado) && largo(n.hijos) > 0 {
        var t = nuevo(esperado);
        if !T.es_arreglo(esperado) { t = I.tipo_de(tipos, n); }
        if !T.es_arreglo(vista(t)) { return no_se(); }
        let elem = T.elemento(vista(t));
        var piezas = vacio();
        var primera = true;
        for x en n.hijos {
            let valor = expresion_c(b, s, x, vista(elem), tipos);
            if es_desconocido(vista(valor)) { return no_se(); }
            if !primera { empujar(piezas, ", "); }
            primera = false;
            empujar(piezas, vista(valor));
        }
        let tc = tipo_c(vista(t));
        return $"({tc}){{{{ {piezas} }}}}";
    }

    // `[]` donde se espera un mapa: la tabla no nace hasta el primer
    // `poner`, que es donde el coste se ve.
    if igual(clase, "literal_lista") {
        if largo(n.hijos) != 0 { return no_se(); }
        if !T.es_mapa(esperado) { return no_se(); }
        var r = nuevo("(");
        empujar(r, tipo_c(esperado));
        empujar(r, "){ .claves = NULL, .valores = NULL, .largo = 0, ");
        empujar(r, ".capacidad = 0 }");
        return r;
    }

    if igual(clase, "campo") {
        // `sitio_c` ya devuelve el valor, no el puntero: un prestamo sale
        // como `(*x)`, asi que aqui siempre es un punto.
        let base = sitio_c(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(base)) { return no_se(); }
        var r = copiar(base);
        empujar(r, ".");
        empujar(r, vista(n.texto));
        return r;
    }

    if igual(clase, "indice") {
        return indice_c(b, s, n, tipos);
    }

    if igual(clase, "binaria") {
        return binaria_c(b, s, n, esperado, tipos);
    }

    if igual(clase, "unaria") {
        let op = vista(n.texto);
        if largo(n.hijos) != 1 { return no_se(); }
        // `~` lleva molde para que el resultado no se ensanche por el camino.
        if igual(op, "~") { return no_se(); }
        let dentro = expresion_c(b, s, n.hijos[0], esperado, tipos);
        if es_desconocido(vista(dentro)) { return no_se(); }
        var v = nuevo("(");
        empujar(v, op);
        empujar(v, vista(dentro));
        empujar(v, ")");
        return v;
    }

    return no_se();
}

// `$"van {n} de {total}"`. Se baja a un `str` que se va llenando: cada
// trozo se agrega tal cual y cada hueco pasa por la misma conversion que
// `imprimir`. No hay formato en tiempo de ejecucion ni un `printf` con
// cadena variable: el tipo de cada hueco se sabe al compilar, y por eso no
// existe aqui el fallo clasico de `%d` con un puntero.
fn interpolada_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo,
    tipos: &I.Contexto) -> str {
    let tmp = nuevo_temporal(b);
    var abre = nuevo("SafeString ");
    empujar(abre, vista(tmp));
    empujar(abre, " = ss_new();");
    emitir(b, vista(abre));
    apuntar_temporal(b, vista(tmp), "str");

    let crudo = vista(n.texto);
    var trozo = vacio();
    var cual = 0;
    var i = 0;
    while i < largo(crudo) {
        let c = byte(crudo, i);
        // `{{` y `}}` son una llave escrita, no un hueco.
        if c == 123 && i + 1 < largo(crudo) && byte(crudo, i + 1) == 123 {
            empujar(trozo, "{");
            i = i + 2;
            continue;
        }
        if c == 125 && i + 1 < largo(crudo) && byte(crudo, i + 1) == 125 {
            empujar(trozo, "}");
            i = i + 2;
            continue;
        }
        if c != 123 {
            empujar(trozo, rebanar(crudo, i, i + 1));
            i = i + 1;
            continue;
        }

        if largo(trozo) > 0 {
            agregar_trozo(b, s, vista(tmp), vista(trozo), n.linea);
            trozo = vacio();
        }
        if cual >= largo(n.hijos) { return no_se(); }
        let dado = hueco_c(b, s, n.hijos[cual], tipos);
        if es_desconocido(vista(dado)) { return no_se(); }
        agregar_vista(b, s, vista(tmp), vista(dado), n.linea);
        cual = cual + 1;

        // Saltar hasta la llave que cierra, contando las de dentro.
        var prof = 1;
        var j = i + 1;
        while j < largo(crudo) && prof > 0 {
            if byte(crudo, j) == 123 { prof = prof + 1; }
            if byte(crudo, j) == 125 { prof = prof - 1; }
            if prof > 0 { j = j + 1; }
        }
        i = j + 1;
    }
    if largo(trozo) > 0 {
        agregar_trozo(b, s, vista(tmp), vista(trozo), n.linea);
    }
    return copiar(tmp);
}

// El texto de un hueco, ya como vista. Un `str` o una `view` se prestan; lo
// demas se convierte a texto en un temporal.
fn hueco_c(b: mut Cuerpo, s: &Sitio, x: &P.Nodo, tipos: &I.Contexto) -> str {
    let t = I.tipo_de(tipos, x);
    if igual(vista(t), "str") || igual(vista(t), "view") {
        return como_vista(b, s, x, tipos);
    }
    let valor = expresion_c(b, s, x, vista(t), tipos);
    if es_desconocido(vista(valor)) { return no_se(); }
    let convertido = texto_de(s, vista(valor), vista(t), x.linea);
    if es_desconocido(vista(convertido)) { return no_se(); }
    let pieza = nuevo_temporal(b);
    var l = nuevo("SafeString ");
    empujar(l, vista(pieza));
    empujar(l, " = ");
    empujar(l, vista(convertido));
    empujar(l, ";");
    emitir(b, vista(l));
    apuntar_temporal(b, vista(pieza), "str");
    var r = nuevo("ss_view(&");
    empujar(r, vista(pieza));
    empujar(r, ")");
    return r;
}

// El `str` que representa un valor. Las mismas reglas que `texto`.
fn texto_de(s: &Sitio, valor: view, t: view, linea: usize) -> str {
    var r = vacio();
    if igual(t, "usize") {
        r = nuevo("ss_lang_texto_usize_(");
        empujar(r, valor);
    } else {
        if igual(t, "f32") || igual(t, "f64") {
            r = nuevo("ss_lang_texto_view_(sv(ss_lang_texto_decimal_(");
            empujar(r, valor);
            empujar(r, "))");
        } else {
            if igual(t, "bool") {
                r = nuevo("ss_lang_texto_view_((");
                empujar(r, valor);
                empujar(r, ") ? sv(\"true\") : sv(\"false\")");
            } else {
                if es_entero(t) {
                    // Un ancho fijo se ensancha al mayor de su signo: hay
                    // una conversion por signo, no una por ancho.
                    if empieza_con(t, "u") {
                        r = nuevo("ss_lang_texto_usize_((size_t) ");
                    } else {
                        r = nuevo("ss_lang_texto_i64_((int64_t) ");
                    }
                    empujar(r, valor);
                } else {
                    return no_se();
                }
            }
        }
    }
    empujar(r, ", \"");
    empujar(r, vista(s.archivo));
    empujar(r, "\", ");
    empujar(r, texto(linea));
    empujar(r, ")");
    return r;
}

fn agregar_trozo(b: mut Cuerpo, s: &Sitio, donde: view, t: view,
    linea: usize) {
    let escrito = literal_c(t);
    var v = nuevo("sv_len(");
    empujar(v, vista(escrito));
    empujar(v, ", ");
    empujar(v, texto(cuantos_bytes(t)));
    empujar(v, ")");
    agregar_vista(b, s, donde, vista(v), linea);
}

fn agregar_vista(b: mut Cuerpo, s: &Sitio, donde: view, que: view,
    linea: usize) {
    var l = nuevo("ss_lang_agregar_texto_(&");
    empujar(l, donde);
    empujar(l, ", ");
    empujar(l, que);
    empujar(l, ", \"");
    empujar(l, vista(s.archivo));
    empujar(l, "\", ");
    empujar(l, texto(linea));
    empujar(l, ");");
    emitir(b, vista(l));
}

// `Punto { x: 1, y: 2 }`. El struct se queda con lo que le pongan: un campo
// con duenio recibe el valor, no una copia, y desde ahi lo suelta el.
fn literal_struct_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo,
    tipos: &I.Contexto) -> str {
    let escrito = vista(n.texto);
    var r = nuevo("(");
    // En C no queda el alias del modulo: `P.Nodo` es `Nodo`.
    empujar(r, tipo_c(escrito));
    empujar(r, "){ ");
    var primero = true;
    for h en n.hijos {
        if !igual(vista(h.clase), "campo") { return no_se(); }
        if largo(h.hijos) != 1 { return no_se(); }
        let suyo = I.tipo_de_campo(tipos, escrito, vista(h.texto));
        let valor = expresion_c(b, s, h.hijos[0], vista(suyo), tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        reclamar(b, vista(valor)); // el struct se lo queda
        if !primero { empujar(r, ", "); }
        primero = false;
        empujar(r, ".");
        empujar(r, vista(h.texto));
        empujar(r, " = ");
        empujar(r, vista(valor));
    }
    empujar(r, " }");
    return r;
}

// `x como u32`. Convertir de verdad comprueba que el valor cabe: si no
// cabe, el programa para donde esta. `como?` es la otra: pedir a proposito
// que se quede con los bits de abajo, que es lo que C hace siempre y sin
// avisar. Las dos se escriben distinto porque son dos intenciones distintas.
fn conversion_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo,
    tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 1 { return no_se(); }
    let escrito = vista(n.texto);
    var envolviendo = false;
    var destino = nuevo(escrito);
    if empieza_con(escrito, "?") {
        envolviendo = true;
        destino = nuevo(rebanar(escrito, 1, largo(escrito)));
    }
    let suyo = I.tipo_de(tipos, n.hijos[0]);
    var origen = T.apuntado_si(vista(suyo));
    if !es_aritmetico(vista(origen)) { origen = nuevo("usize"); }
    let valor = expresion_c(b, s, n.hijos[0], vista(origen), tipos);
    if es_desconocido(vista(valor)) { return no_se(); }
    if igual(vista(origen), vista(destino)) { return valor; }

    if envolviendo {
        var r = nuevo("((");
        empujar(r, tipo_c(vista(destino)));
        empujar(r, ") ");
        empujar(r, vista(valor));
        empujar(r, ")");
        return r;
    }
    var r = nuevo("ss_lang_conv_");
    empujar(r, vista(destino));
    empujar(r, "_de_");
    empujar(r, vista(origen));
    empujar(r, "(");
    empujar(r, vista(valor));
    empujar(r, ", \"");
    empujar(r, vista(s.archivo));
    empujar(r, "\", ");
    empujar(r, texto(n.linea));
    empujar(r, ")");
    return r;
}

fn es_aritmetico(t: view) -> bool {
    if igual(t, "f32") || igual(t, "f64") { return true; }
    return es_entero(t);
}

// Un sitio del que tomar campos o elementos. Una llamada no es un sitio:
// `hacer()[1]` tendria que guardar lo que devuelve antes de indexarlo, o la
// llamada se evaluaria una vez por cada vez que aparece en el C —dos: el
// elemento y el largo— y lo que devuelve no lo liberaria nadie.
fn sitio_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);
    if igual(clase, "variable") || igual(clase, "campo")
    || igual(clase, "indice") {
        return expresion_c(b, s, n, "", tipos);
    }
    // Una llamada no es un sitio: `claves(m).length` la evaluaria una vez
    // por cada aparicion en el C, y lo que devuelve no lo soltaria nadie. Se
    // guarda en un temporal, que se suelta al acabar la sentencia.
    var t = I.tipo_de(tipos, n);
    if largo(t) == 0 { t = nuevo("usize"); }
    let tmp = nuevo_temporal(b);
    let valor = expresion_c(b, s, n, vista(t), tipos);
    if es_desconocido(vista(valor)) { return no_se(); }
    reclamar(b, vista(valor));
    let tc = tipo_c(vista(t));
    emitir(b, $"{tc} {tmp} = {valor};");
    if I.posee_con_formas(tipos, vista(t)) {
        apuntar_temporal(b, vista(tmp), vista(t));
    }
    return tmp;
}

// Indexar comprueba el limite: es la comprobacion que C no hace y por la que
// existe medio Tcode. Va en el C, no en el comprobador, porque el indice se
// sabe al correr.
fn indice_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 2 { return no_se(); }
    let suyo = I.tipo_de(tipos, n.hijos[0]);
    let base = T.apuntado_si(vista(suyo));
    let sitio = sitio_c(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(sitio)) { return no_se(); }
    let idx = expresion_c(b, s, n.hijos[1], "usize", tipos);
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

fn binaria_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, _esperado: view, tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 2 { return no_se(); }
    let op = vista(n.texto);

    // Lo logico y lo comparativo salen tal cual: en C significan lo mismo.
    if igual(op, "&&") || igual(op, "||") {
        return junta(b, s, n, "bool", op, tipos);
    }
    if igual(op, "==") || igual(op, "!=") || igual(op, "<") || igual(op, "<=")
    || igual(op, ">") || igual(op, ">=") {
        let t = tipo_operando(s, n, tipos);
        return junta(b, s, n, vista(t), op, tipos);
    }

    let t = tipo_operando(s, n, tipos);
    if largo(t) == 0 { return no_se(); }

    // Los decimales no desbordan: se van a infinito o a NaN, callando. En
    // Tcode eso para el programa donde aparece, asi que cada operacion pasa
    // por una comprobacion de que el resultado sigue siendo un numero. El
    // que quiera lo de IEEE lo pide con `+?`, `-?`, `*?` o `/?`.
    if igual(vista(t), "f32") || igual(vista(t), "f64") {
        let izq = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        let der = expresion_c(b, s, n.hijos[1], vista(t), tipos);
        if es_desconocido(vista(izq)) || es_desconocido(vista(der)) {
            return no_se();
        }
        if empieza_con(op, "+?") || empieza_con(op, "-?")
        || empieza_con(op, "*?") || empieza_con(op, "/?") {
            var v = nuevo("(");
            empujar(v, vista(izq));
            empujar(v, " ");
            empujar(v, rebanar(op, 0, 1));
            empujar(v, " ");
            empujar(v, vista(der));
            empujar(v, ")");
            return v;
        }
        if !igual(op, "+") && !igual(op, "-") && !igual(op, "*")
        && !igual(op, "/") {
            return no_se();
        }
        var v = nuevo("ss_lang_fin_");
        empujar(v, vista(t));
        empujar(v, "((");
        empujar(v, vista(izq));
        empujar(v, " ");
        empujar(v, op);
        empujar(v, " ");
        empujar(v, vista(der));
        empujar(v, "), \"");
        empujar(v, op);
        empujar(v, "\", \"Si lo querias, escribe `");
        empujar(v, op);
        empujar(v, "?`.\", \"");
        empujar(v, vista(s.archivo));
        empujar(v, "\", ");
        empujar(v, texto(n.linea));
        empujar(v, ")");
        return v;
    }

    // El desplazamiento tiene dos tipos: lo que se mueve y cuanto se mueve.
    // Y se comprueba, porque en C desplazar mas que el ancho es indefinido.
    if igual(op, "<<") || igual(op, ">>") {
        let izq = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        let der = expresion_c(b, s, n.hijos[1], "usize", tipos);
        if es_desconocido(vista(izq)) || es_desconocido(vista(der)) {
            return no_se();
        }
        var v = nuevo("ss_lang_desp_");
        if igual(op, "<<") { empujar(v, "izq_"); } else { empujar(v, "der_"); }
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

    // Bits, y aritmetica envolvente pedida a proposito. El molde deja claro
    // que el resultado no se ensancha por el camino: en C, `u8 & u8` da un
    // `int`.
    if igual(op, "&") || igual(op, "|") || igual(op, "^")
    || igual(op, "+?") || igual(op, "-?") || igual(op, "*?") {
        let izq = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        let der = expresion_c(b, s, n.hijos[1], vista(t), tipos);
        if es_desconocido(vista(izq)) || es_desconocido(vista(der)) {
            return no_se();
        }
        var v = nuevo("((");
        empujar(v, tipo_c(vista(t)));
        empujar(v, ") (");
        empujar(v, vista(izq));
        empujar(v, " ");
        empujar(v, rebanar(op, 0, 1));
        empujar(v, " ");
        empujar(v, vista(der));
        empujar(v, "))");
        return v;
    }

    let fam = familia(op);
    if largo(fam) > 0 {
        let izq = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        let der = expresion_c(b, s, n.hijos[1], vista(t), tipos);
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
        let izq = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        let der = expresion_c(b, s, n.hijos[1], vista(t), tipos);
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
fn junta(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, esperado: view, op: view,
    tipos: &I.Contexto) -> str {
    let izq = expresion_c(b, s, n.hijos[0], esperado, tipos);
    let der = expresion_c(b, s, n.hijos[1], esperado, tipos);
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
    if es_aritmetico(vista(a)) { return a; }
    let otro = I.tipo_de(tipos, n.hijos[1]);
    if es_aritmetico(vista(otro)) { return otro; }
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
fn interna_pura(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let nombre = vista(n.texto);

    if igual(nombre, "vacio") { return nuevo("ss_new()"); }

    if igual(nombre, "n_argumentos") { return nuevo("ss_lang_n_argumentos_()"); }

    if igual(nombre, "argumento") {
        if largo(n.hijos) != 1 { return no_se(); }
        let i = expresion_c(b, s, n.hijos[0], "usize", tipos);
        if es_desconocido(vista(i)) { return no_se(); }
        var r = nuevo("ss_lang_argumento_(");
        empujar(r, vista(i));
        empujar(r, ", \"");
        empujar(r, vista(s.archivo));
        empujar(r, "\", ");
        empujar(r, texto(n.linea));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "largo") {
        if largo(n.hijos) != 1 { return no_se(); }
        let sobre = I.tipo_de(tipos, n.hijos[0]);
        if T.es_mapa(vista(sobre)) {
            let donde = sitio_c(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(donde)) { return no_se(); }
            var r = nuevo("(");
            empujar(r, vista(donde));
            empujar(r, ".largo)");
            return r;
        }
        if T.es_lista(vista(sobre)) {
            let donde = sitio_c(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(donde)) { return no_se(); }
            var r = nuevo("(");
            empujar(r, vista(donde));
            empujar(r, ".length)");
            return r;
        }
        let v = como_vista(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(v)) { return no_se(); }
        var r = nuevo("sv_len_of(");
        empujar(r, vista(v));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "nuevo") {
        if largo(n.hijos) != 1 { return no_se(); }
        let v = como_vista(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(v)) { return no_se(); }
        var r = nuevo("ss_from_view(");
        empujar(r, vista(v));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "vista") {
        if largo(n.hijos) != 1 { return no_se(); }
        let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(donde)) { return no_se(); }
        var r = nuevo("ss_view(");
        empujar(r, vista(donde));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "igual") || igual(nombre, "menor") {
        if largo(n.hijos) != 2 { return no_se(); }
        let uno = como_vista(b, s, n.hijos[0], tipos);
        let dos = como_vista(b, s, n.hijos[1], tipos);
        if es_desconocido(vista(uno)) || es_desconocido(vista(dos)) {
            return no_se();
        }
        var r = nuevo("sv_equals(");
        if igual(nombre, "menor") { r = nuevo("(sv_cmp("); }
        empujar(r, vista(uno));
        empujar(r, ", ");
        empujar(r, vista(dos));
        if igual(nombre, "menor") { empujar(r, ") < 0)"); }
        else { empujar(r, ")"); }
        return r;
    }

    // `byte(v, i)` no cabe en una sola expresion de C: hay que guardar la
    // vista en un temporal y luego indexarla, porque si no se calcularia dos
    // veces —una para el elemento y otra para el largo— y `byte(f(), 0)`
    // llamaria a `f` dos veces. Es la primera interna que necesita emitir
    // una linea propia, y por eso esta capa recibe el cuerpo.
    if igual(nombre, "byte") {
        if largo(n.hijos) != 2 { return no_se(); }
        let v = como_vista(b, s, n.hijos[0], tipos);
        let i = expresion_c(b, s, n.hijos[1], "usize", tipos);
        if es_desconocido(vista(v)) || es_desconocido(vista(i)) {
            return no_se();
        }
        let tmp = nuevo_temporal(b);
        var l = nuevo("SafeView ");
        empujar(l, vista(tmp));
        empujar(l, " = ");
        empujar(l, vista(v));
        empujar(l, ";");
        emitir(b, vista(l));

        var r = nuevo("((size_t)(unsigned char)");
        empujar(r, vista(tmp));
        empujar(r, ".ptr[ss_lang_indice_(");
        empujar(r, vista(i));
        empujar(r, ", ");
        empujar(r, vista(tmp));
        empujar(r, ".len, \"");
        empujar(r, vista(s.archivo));
        empujar(r, "\", ");
        empujar(r, texto(n.linea));
        empujar(r, ")])");
        return r;
    }

    // Los mapas. El nombre de cada operacion lleva dentro el tipo del mapa,
    // porque cada uno tiene su propia tabla generada: no hay una funcion
    // generica que reciba tamanios y punteros a void.
    if igual(nombre, "poner") || igual(nombre, "obtener")
    || igual(nombre, "obtener_mut") || igual(nombre, "tiene")
    || igual(nombre, "claves") || igual(nombre, "quitar") {
        if largo(n.hijos) == 0 { return no_se(); }
        let suyo = I.tipo_de(tipos, n.hijos[0]);
        let tm = T.apuntado_si(vista(suyo));
        if !T.es_mapa(vista(tm)) { return no_se(); }
        let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(donde)) { return no_se(); }

        var r = nuevo("ss_mapa_");
        empujar(r, nombre);
        empujar(r, "_");
        empujar(r, mangle(vista(tm)));
        empujar(r, "(");
        empujar(r, vista(donde));

        if igual(nombre, "claves") {
            if largo(n.hijos) != 1 { return no_se(); }
            empujar(r, ", \"");
            empujar(r, vista(s.archivo));
            empujar(r, "\", ");
            empujar(r, texto(n.linea));
            empujar(r, ")");
            return r;
        }

        if largo(n.hijos) < 2 { return no_se(); }
        let clave = como_vista(b, s, n.hijos[1], tipos);
        if es_desconocido(vista(clave)) { return no_se(); }
        empujar(r, ", ");
        empujar(r, vista(clave));

        if !igual(nombre, "poner") {
            if largo(n.hijos) != 2 { return no_se(); }
            empujar(r, ")");
            return r;
        }

        if largo(n.hijos) != 3 { return no_se(); }
        let tv = T.valor_de_mapa(vista(tm)) sino vacio();
        if largo(vista(tv)) == 0 { return no_se(); }
        let valor = expresion_c(b, s, n.hijos[2], vista(tv), tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        reclamar(b, vista(valor)); // el mapa se lo queda
        empujar(r, ", ");
        empujar(r, vista(valor));
        empujar(r, ", \"");
        empujar(r, vista(s.archivo));
        empujar(r, "\", ");
        empujar(r, texto(n.linea));
        empujar(r, ")");
        return r;
    }

    // `copiar(x)`: una copia independiente, hasta el fondo. Cada tipo lleva
    // su copiador generado, espejo exacto de su liberacion.
    if igual(nombre, "copiar") {
        if largo(n.hijos) != 1 { return no_se(); }
        let crudo = I.tipo_de(tipos, n.hijos[0]);
        let t = T.apuntado_si(vista(crudo));
        if largo(vista(t)) == 0 { return no_se(); }
        if !I.posee_con_formas(tipos, vista(t)) {
            // Un escalar se copia solo.
            return expresion_c(b, s, n.hijos[0], vista(t), tipos);
        }
        var donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(donde)) && T.es_referencia(vista(crudo)) {
            // Llega prestado, y en C eso ya es la direccion.
            donde = expresion_c(b, s, n.hijos[0], vista(crudo), tipos);
        }
        if es_desconocido(vista(donde)) { return no_se(); }
        if igual(vista(t), "str") {
            var r = nuevo("ss_clone(");
            empujar(r, vista(donde));
            empujar(r, ")");
            return r;
        }
        // El copiador se escribe aparte, al final: se apunta que hace falta.
        anadir(b.copias, I.sin_alias_tipo(vista(t)));
        var r = nuevo("ss_copia_");
        empujar(r, mangle(vista(t)));
        empujar(r, "(");
        empujar(r, vista(donde));
        empujar(r, ")");
        return r;
    }

    // `imprimir` va a la salida; `imprimir_error`, al diagnostico. Separarlos
    // es lo que permite encauzar la salida de una herramienta sin que se le
    // cuelen los mensajes de uso. El formato sale del tipo, que se sabe al
    // compilar: no hay `%d` con un puntero que valga.
    if igual(nombre, "imprimir") || igual(nombre, "imprimir_error") {
        if largo(n.hijos) != 1 { return no_se(); }
        var r = nuevo("printf(");
        if igual(nombre, "imprimir_error") { r = nuevo("fprintf(stderr, "); }
        let t = I.tipo_de(tipos, n.hijos[0]);
        let clase = vista(n.hijos[0].clase);
        if igual(vista(t), "str") && (igual(clase, "variable")
            || igual(clase, "campo") || igual(clase, "indice")) {
            let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(donde)) { return no_se(); }
            empujar(r, "\"%s\", ss_cstr(");
            empujar(r, vista(donde));
            empujar(r, "))");
            return r;
        }
        if igual(vista(t), "str") || igual(vista(t), "view") {
            let v = como_vista(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(v)) { return no_se(); }
            empujar(r, "SV_FMT, SV_ARG(");
            empujar(r, vista(v));
            empujar(r, "))");
            return r;
        }
        let valor = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        if igual(vista(t), "usize") {
            empujar(r, "\"%zu\", ");
        } else {
            if igual(vista(t), "f32") || igual(vista(t), "f64") {
                empujar(r, "\"%s\", ss_lang_texto_decimal_(");
                empujar(r, vista(valor));
                empujar(r, "))");
                return r;
            }
            if igual(vista(t), "bool") {
                empujar(r, "\"%s\", (");
                empujar(r, vista(valor));
                empujar(r, ") ? \"true\" : \"false\")");
                return r;
            }
            if !es_entero(vista(t)) { return no_se(); }
            // Un ancho fijo se ensancha al mayor para imprimirlo: un formato
            // por signo y no nueve.
            if empieza_con(vista(t), "u") {
                empujar(r, "\"%llu\", (unsigned long long)");
            } else {
                empujar(r, "\"%lld\", (long long)");
            }
        }
        empujar(r, vista(valor));
        empujar(r, ")");
        return r;
    }

    // `texto(x)`: el `str` que representa un valor, con las mismas reglas
    // que un hueco de una cadena interpolada.
    if igual(nombre, "texto") {
        if largo(n.hijos) != 1 { return no_se(); }
        let t = I.tipo_de(tipos, n.hijos[0]);
        if igual(vista(t), "str") || igual(vista(t), "view") {
            let v = como_vista(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(v)) { return no_se(); }
            var r = nuevo("ss_lang_texto_view_(");
            empujar(r, vista(v));
            empujar(r, ", \"");
            empujar(r, vista(s.archivo));
            empujar(r, "\", ");
            empujar(r, texto(n.linea));
            empujar(r, ")");
            return r;
        }
        let valor = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        return texto_de(s, vista(valor), vista(t), n.linea);
    }

    // `raiz`, `piso`, `techo`, `redondear` y `absoluto`. Sobre un decimal
    // pasan por la comprobacion de finitud: `raiz` de un negativo da NaN, y
    // eso para donde aparece como cualquier otro NaN. Sobre un entero con
    // signo, `absoluto` del minimo no cabe en el tipo: es el unico caso.
    if igual(nombre, "raiz") || igual(nombre, "piso") || igual(nombre, "techo")
    || igual(nombre, "redondear") || igual(nombre, "absoluto") {
        if largo(n.hijos) != 1 { return no_se(); }
        let crudo = I.tipo_de(tipos, n.hijos[0]);
        var t = T.apuntado_si(vista(crudo));
        if !es_aritmetico(vista(t)) { t = nuevo("f64"); }
        let valor = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        if igual(vista(t), "f32") || igual(vista(t), "f64") {
            var fn_c = nuevo("fabs");
            if igual(nombre, "raiz") { fn_c = nuevo("sqrt"); }
            if igual(nombre, "piso") { fn_c = nuevo("floor"); }
            if igual(nombre, "techo") { fn_c = nuevo("ceil"); }
            if igual(nombre, "redondear") { fn_c = nuevo("round"); }
            var r = nuevo("ss_lang_fin_");
            empujar(r, vista(t));
            empujar(r, "(");
            empujar(r, vista(fn_c));
            if igual(vista(t), "f32") { empujar(r, "f"); }
            empujar(r, "(");
            empujar(r, vista(valor));
            empujar(r, "), \"");
            empujar(r, nombre);
            empujar(r, "\", \"");
            if igual(nombre, "raiz") {
                empujar(r, "Comprueba el signo antes: la raiz de un negativo ");
                empujar(r, "no es un numero.");
            } else {
                empujar(r, "Comprueba el valor antes de operar con el.");
            }
            empujar(r, "\", \"");
            empujar(r, vista(s.archivo));
            empujar(r, "\", ");
            empujar(r, texto(n.linea));
            empujar(r, ")");
            return r;
        }
        if !igual(nombre, "absoluto") { return no_se(); }
        var r = nuevo("ss_lang_abs_");
        empujar(r, vista(t));
        empujar(r, "(");
        empujar(r, vista(valor));
        empujar(r, ", \"");
        empujar(r, vista(s.archivo));
        empujar(r, "\", ");
        empujar(r, texto(n.linea));
        empujar(r, ")");
        return r;
    }

    // `ordenar(xs)`: cada tipo de lista lleva su propia ordenacion generada.
    if igual(nombre, "ordenar") {
        if largo(n.hijos) != 1 { return no_se(); }
        let crudo = I.tipo_de(tipos, n.hijos[0]);
        let t = T.apuntado_si(vista(crudo));
        if !T.es_lista(vista(t)) { return no_se(); }
        let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(donde)) { return no_se(); }
        var r = nuevo("ss_ordenar_");
        empujar(r, mangle(vista(t)));
        empujar(r, "(");
        empujar(r, vista(donde));
        empujar(r, ")");
        return r;
    }

    // `empujar_byte(s, b)`: un byte crudo, no texto. Es lo que permite
    // construir un buffer binario y no solo leerlo.
    if igual(nombre, "empujar_byte") {
        if largo(n.hijos) != 2 { return no_se(); }
        let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(donde)) { return no_se(); }
        let valor = expresion_c(b, s, n.hijos[1], "u8", tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        var r = nuevo("ss_lang_empujar_byte_(");
        empujar(r, vista(donde));
        empujar(r, ", ");
        empujar(r, vista(valor));
        empujar(r, ", \"");
        empujar(r, vista(s.archivo));
        empujar(r, "\", ");
        empujar(r, texto(n.linea));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "rebanar") {
        if largo(n.hijos) != 3 { return no_se(); }
        let v = como_vista(b, s, n.hijos[0], tipos);
        let desde = expresion_c(b, s, n.hijos[1], "usize", tipos);
        let hasta = expresion_c(b, s, n.hijos[2], "usize", tipos);
        if es_desconocido(vista(v)) || es_desconocido(vista(desde))
        || es_desconocido(vista(hasta)) {
            return no_se();
        }
        var r = nuevo("sv_slice(");
        empujar(r, vista(v));
        empujar(r, ", ");
        empujar(r, vista(desde));
        empujar(r, ", ");
        empujar(r, vista(hasta));
        empujar(r, ")");
        return r;
    }

    return no_se();
}

// La direccion de un sitio con nombre: `&x`, `&p.campo`, `&v.e[i]`. Prestar
// algo recien hecho pediria un temporal del que tomar la direccion, y ese
// temporal habria que soltarlo al acabar la sentencia: otra capa.
fn direccion_del_sitio(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);
    if igual(clase, "variable") {
        // Un `&T` ya ES la direccion: pedirsela otra vez sobra.
        if es_puntero(s, tipos, vista(n.texto)) {
            return nuevo(vista(n.texto));
        }
        var r = nuevo("&");
        empujar(r, vista(n.texto));
        return r;
    }
    if igual(clase, "campo") || igual(clase, "indice") {
        let donde = expresion_c(b, s, n, "", tipos);
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
fn como_vista(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
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
        let clase = vista(n.clase);
        if igual(clase, "variable") || igual(clase, "campo")
        || igual(clase, "indice") {
            let donde = direccion_del_sitio(b, s, n, tipos);
            if es_desconocido(vista(donde)) { return no_se(); }
            var r = nuevo("ss_view(");
            empujar(r, vista(donde));
            empujar(r, ")");
            return r;
        }
        // Un `str` recien hecho no tiene sitio del que tomar la direccion:
        // se guarda en un temporal, que se suelta al acabar la sentencia.
        let tmp = nuevo_temporal(b);
        let valor = expresion_c(b, s, n, "str", tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        reclamar(b, vista(valor));
        var l = nuevo("SafeString ");
        empujar(l, vista(tmp));
        empujar(l, " = ");
        empujar(l, vista(valor));
        empujar(l, ";");
        emitir(b, vista(l));
        apuntar_temporal(b, vista(tmp), "str");
        var r = nuevo("ss_view(&");
        empujar(r, vista(tmp));
        empujar(r, ")");
        return r;
    }
    if igual(vista(t), "view") { return expresion_c(b, s, n, "view", tipos); }
    return no_se();
}

// El literal de C con los mismos bytes. Aqui solo lo que no necesita
// escaparse raro: si lleva algo mas, no se cubre.
// Un literal de C con los mismos BYTES, escapado. Lo que no sea imprimible
// va en octal: asi un byte crudo no depende de como lo lea el compilador de
// C ni de en que juego de caracteres este el archivo.
fn literal_c(crudo: view) -> str {
    let bytes = P.desescapar(crudo);
    let t = vista(bytes);
    var r = nuevo("\"");
    var i = 0;
    while i < largo(t) {
        let c = byte(t, i);
        if c == 92 { empujar(r, "\\\\"); }
        else {
            if c == 34 { empujar(r, "\\\""); }
            else {
                if c == 10 { empujar(r, "\\n"); }
                else {
                    if c == 9 { empujar(r, "\\t"); }
                    else {
                        if c >= 32 && c < 127 {
                            empujar(r, rebanar(t, i, i + 1));
                        } else {
                            let oct = en_octal(c);
                            empujar(r, "\\");
                            empujar(r, vista(oct));
                        }
                    }
                }
            }
        }
        i = i + 1;
    }
    empujar(r, "\"");
    return r;
}

// Tres digitos siempre: `\1` seguido de un `2` seria `\12`, otro byte.
fn en_octal(c: usize) -> str {
    var r = vacio();
    var d = 0;
    while d < 3 {
        let peso = potencia_ocho(2 - d);
        let cifra = (c / peso) % 8;
        empujar(r, texto(cifra));
        d = d + 1;
    }
    return r;
}

fn potencia_ocho(n: usize) -> usize {
    if n == 0 { return 1; }
    if n == 1 { return 8; }
    return 64;
}

fn cuantos_bytes(crudo: view) -> usize {
    let t = P.desescapar(crudo);
    return largo(vista(t));
}

fn llamada_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let nombre = vista(n.texto);
    let pura = interna_pura(b, s, n, tipos);
    if !es_desconocido(vista(pura)) { return pura; }
    if igual(nombre, "leer_archivo") || igual(nombre, "leer_linea")
    || igual(nombre, "entrada_completa") || igual(nombre, "variable_entorno")
    || igual(nombre, "ahora_ms") || igual(nombre, "monotono_ms")
    || igual(nombre, "sembrar") || igual(nombre, "azar") {
        return interna_del_sistema(b, s, n, tipos);
    }
    if es_interna(nombre) { return no_se(); }
    if !tiene(tipos.retornos, nombre) { return no_se(); }
    // Una llamada a C pide convertir el `str` a `const char*` comprobando el
    // cero de en medio. Esta capa todavia no lo hace, asi que no la emite.
    if tiene(tipos.externas, nombre) { return no_se(); }
    if tiene(tipos.repetidas, nombre) { return no_se(); }

    var firmados = I.lista_de(tipos.params, nombre) sino [];
    let marcados = I.lista_de(tipos.params_marcados, nombre) sino [];
    // En C no queda el alias del modulo: `I.tipo_de` se llama `tipo_de`.
    var en_c = I.sin_modulo(nombre);
    // Un nombre propio que tambien traia un modulo: el cargador le pone el
    // nombre del archivo delante. Llamado con el alias del modulo seria el
    // otro, y ese no se sabe como quedo: no se emite.
    if tiene(tipos.renombradas, nombre) {
        en_c = nuevo(obtener(tipos.renombradas, nombre) sino "");
    }
    if contiene(nombre, ".") && tiene(tipos.renombradas, vista(en_c)) {
        return no_se();
    }
    // `union` es legitimo en Tcode y no en C: se llama como se declaro.
    en_c = nombre_en_c(vista(en_c));

    // Una generica: se eligen los tipos mirando los argumentos, igual que el
    // comprobador, y se llama a la copia con ese juego de tipos. El nombre
    // de la copia lleva los tipos dentro, saneados para que sean C.
    var pedido = vacio();
    if tiene(tipos.tipo_params, nombre) {
        let sueltos = I.lista_de(tipos.tipo_params, nombre) sino [];
        var ligaduras: mapa<str, str> = [];
        var k = 0;
        while k < largo(firmados) && k < largo(n.hijos) {
            let dado = I.tipo_de(tipos, n.hijos[k]);
            let limpio = T.apuntado_si(vista(dado));
            I.unificar(vista(firmados[k]), vista(limpio), sueltos, ligaduras);
            k = k + 1;
        }
        empujar(en_c, "__");
        var primero = true;
        for tp en sueltos {
            if !tiene(ligaduras, vista(tp)) { return no_se(); }
            let ligado = nuevo(obtener(ligaduras, vista(tp)) sino "");
            if !primero { empujar(en_c, "_"); }
            primero = false;
            let limpio = sanear(vista(ligado));
            empujar(en_c, vista(limpio));
        }
        // Lo que hace falta para escribir la copia: de que plantilla sale,
        // como se llama y que tipo va en cada parametro. Sin el alias del
        // modulo: la copia se escribe en el modulo de la plantilla.
        pedido = I.sin_modulo(nombre);
        empujar(pedido, "\t");
        empujar(pedido, vista(en_c));
        for tp en sueltos {
            let ligado = obtener(ligaduras, vista(tp)) sino "";
            let sin_alias = I.sin_alias_tipo(ligado);
            empujar(pedido, "\t");
            empujar(pedido, vista(tp));
            empujar(pedido, "=");
            empujar(pedido, vista(sin_alias));
        }
        var puestos: lista<str> = [];
        for f en firmados { anadir(puestos, I.sustituir(vista(f), ligaduras)); }
        firmados = puestos;
    }
    var v = copiar(en_c);
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
            let clase_h = vista(h.clase);
            if igual(clase_h, "variable") || igual(clase_h, "campo")
            || igual(clase_h, "indice") {
                let dir = direccion_del_sitio(b, s, h, tipos);
                if es_desconocido(vista(dir)) { return no_se(); }
                empujar(v, vista(dir));
                i = i + 1;
                continue;
            }
            // Prestar algo recien hecho: se guarda en un temporal para poder
            // tomarle la direccion, y se suelta al acabar la sentencia como
            // cualquier otro valor descartado.
            if largo(esperado) == 0 { return no_se(); }
            let tmp = nuevo_temporal(b);
            let valor = expresion_c(b, s, h, vista(esperado), tipos);
            if es_desconocido(vista(valor)) { return no_se(); }
            reclamar(b, vista(valor));
            let tc = tipo_c(vista(esperado));
            emitir(b, $"{tc} {tmp} = {valor};");
            if I.posee_con_formas(tipos, vista(esperado)) {
                apuntar_temporal(b, vista(tmp), vista(esperado));
            }
            empujar(v, "&");
            empujar(v, vista(tmp));
            i = i + 1;
            continue;
        }

        // Donde se pide una vista, un `str` se lee prestandolo: escribir
        // `vista(s)` no le aportaria nada al compilador.
        if igual(vista(esperado), "view") {
            let suyo = I.tipo_de(tipos, h);
            if igual(vista(suyo), "str") {
                let arg = como_vista(b, s, h, tipos);
                if es_desconocido(vista(arg)) { return no_se(); }
                empujar(v, vista(arg));
                i = i + 1;
                continue;
            }
        }

        // Pasar una variable con duenio a algo que se la queda es moverla.
        // La bandera la apaga la sentencia; aqui basta con que exista.
        if !presta_el && entrega_variable(s, h, tipos) {
            if !lleva_bandera(b, s, vista(h.texto)) { return no_se(); }
        }
        let arg = expresion_c(b, s, h, vista(esperado), tipos);
        if es_desconocido(vista(arg)) { return no_se(); }
        empujar(v, vista(arg));
        i = i + 1;
    }
    // Despues de los argumentos: una generica que se llama dentro de otro
    // argumento se crea antes, como en el original.
    if largo(pedido) > 0 { anadir(b.instancias, pedido); }
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
    // Un struct que posee se mueve igual que un `str`: si solo se miraran
    // las colecciones, pasar un `Nodo` a quien se lo queda no pediria
    // bandera y se soltaria dos veces.
    return I.posee_con_formas(tipos, vista(t));
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
    if igual(nombre, "anadir") { return i == 0; }
    // La clave se copia dentro de la tabla: se presta. Solo el valor se
    // queda en el mapa.
    if igual(nombre, "poner") { return i < 2; }
    if es_interna(nombre) { return true; }
    // Un parametro `view` mira el texto, no se lo queda.
    let firmados = I.lista_de(tipos.params, nombre) sino [];
    if i < largo(firmados) {
        if igual(vista(firmados[i]), "view") { return true; }
    }
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

    if igual(clase, "enum_lit") {
        for h en n.hijos {
            if entrega_suelta(punteros, h, tipos) {
                apuntar_movida(salida, vista(h.texto));
            }
        }
    }

    if igual(clase, "literal_struct") {
        for h en n.hijos {
            for x en h.hijos {
                if entrega_suelta(punteros, x, tipos) {
                    apuntar_movida(salida, vista(x.texto));
                }
            }
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
    let ninguna: lista<str> = [];
    movidas_hondo_en(punteros, bloque, tipos, salida, ninguna);
}

// `visibles` son las declaraciones que se ven desde aqui, como
// `nombre@linea`. Cada bloque trabaja sobre su propia copia: lo que se
// declara dentro no se ve fuera, y asi no hace falta deshacer nada.
fn movidas_hondo_en(punteros: &mapa<str, usize>, bloque: &P.Nodo,
    tipos: mut I.Contexto, salida: mut lista<str>, visibles: &lista<str>) {
    var mias: lista<str> = [];
    for x en visibles { anadir(mias, copiar(x)); }
    I.abrir(tipos);
    for st en bloque.hijos {
        // Lo que entrega esta sentencia se mira ANTES de declarar lo que
        // declara: `let y = x;` entrega la `x` de fuera.
        var salen: lista<str> = [];
        movidas_en(punteros, st, tipos, salen);
        for nm en salen {
            let k = visible_en(mias, vista(nm));
            apuntar_movida(salida, vista(k));
        }
        if igual(vista(st.clase), "declaracion") && largo(st.hijos) == 1 {
            let nombre = nombre_declarado(vista(st.texto));
            var tipo = tipo_escrito(vista(st.texto));
            if largo(tipo) == 0 { tipo = I.tipo_de(tipos, st.hijos[0]); }
            I.declarar(tipos, vista(nombre), vista(tipo));
            anadir(mias, clave_de(vista(nombre), st.linea));
        }
        // Un `for` declara su variable para el cuerpo. Sin ella, lo que se
        // calcula a partir de ella —`var p = copiar(l)`— no tiene tipo, y no
        // se sabria que `p` posee ni que se entrega.
        let es_para = igual(vista(st.clase), "para") && largo(st.hijos) == 2;
        if es_para {
            I.abrir(tipos);
            let suyo = I.tipo_de(tipos, st.hijos[0]);
            let sobre = T.apuntado_si(vista(suyo));
            let uno = primer_nombre(vista(st.texto));
            let dos = segundo_nombre(vista(st.texto));
            if T.es_mapa(vista(sobre)) {
                let partes = T.partir_tipos(T.entre_angulos(vista(sobre)));
                if largo(partes) == 2 {
                    I.declarar(tipos, vista(uno), vista(partes[0]));
                    if largo(dos) > 0 {
                        I.declarar(tipos, vista(dos), vista(partes[1]));
                    }
                }
            } else {
                let elem = T.elemento(vista(sobre));
                I.declarar(tipos, vista(uno), vista(elem));
            }
        }
        for h en st.hijos {
            if igual(vista(h.clase), "bloque") {
                movidas_hondo_en(punteros, h, tipos, salida, mias);
            }
        }
        if es_para { I.cerrar(tipos); }
    }
    I.cerrar(tipos);
}

fn visible_en(visibles: &lista<str>, nombre: view) -> str {
    var i = largo(visibles);
    while i > 0 {
        i = i - 1;
        let n = antes_de_arroba(vista(visibles[i]));
        if igual(vista(n), nombre) { return copiar(visibles[i]); }
    }
    return clave_de(nombre, 0);
}

// Las que hablan con el sistema y pueden fallar. No llevan argumentos que
// convertir, asi que su C es el nombre y ya.
fn interna_del_sistema(b: mut Cuerpo, s: &Sitio, n: &P.Nodo,
    tipos: &I.Contexto) -> str {
    let nombre = vista(n.texto);
    if igual(nombre, "leer_archivo") {
        if largo(n.hijos) != 1 { return no_se(); }
        let ruta = como_vista(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(ruta)) { return no_se(); }
        var r = nuevo("ss_lang_leer_archivo_(");
        empujar(r, vista(ruta));
        empujar(r, ")");
        return r;
    }
    if igual(nombre, "variable_entorno") {
        if largo(n.hijos) != 1 { return no_se(); }
        let v = como_vista(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(v)) { return no_se(); }
        return $"ss_lang_variable_entorno_({v})";
    }
    if igual(nombre, "sembrar") {
        if largo(n.hijos) != 1 { return no_se(); }
        let x = expresion_c(b, s, n.hijos[0], "u64", tipos);
        if es_desconocido(vista(x)) { return no_se(); }
        return $"ss_lang_sembrar_({x})";
    }
    if igual(nombre, "azar") {
        if largo(n.hijos) != 1 { return no_se(); }
        let x = expresion_c(b, s, n.hijos[0], "usize", tipos);
        if es_desconocido(vista(x)) { return no_se(); }
        return $"ss_lang_azar_({x}, \"{s.archivo}\", {n.linea})";
    }
    if largo(n.hijos) != 0 { return no_se(); }
    var r = nuevo("ss_lang_");
    empujar(r, nombre);
    empujar(r, "_()");
    return r;
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
    // La misma forma que `bloques`, con `nombre@linea` de cada declaracion.
    // Las banderas se deciden por declaracion y no por nombre: tres `r` en
    // tres bloques son tres variables, y que una se entregue no dice nada
    // de las otras dos.
    claves: lista<lista<str>>,
    sangria: usize,
    temporal: usize,
    // La ultima posicion marcada con `#line`, para no repetirla.
    ultima_linea: usize,
    // Cuantos bucles se han abierto: cada uno lleva su propio indice.
    bucle: usize,
    // Lo que nace a mitad de una sentencia y no tiene nombre: el `str` que
    // devuelve `tipo_c(t)` dentro de `empujar(s, tipo_c(t))`. Vive hasta el
    // final de la sentencia, y se suelta ahi. Van como `nombre: tipo`, igual
    // que los bloques.
    temporales: lista<str>,
    // Los temporales de las sentencias que envuelven a la actual, de fuera
    // hacia dentro. Una salida temprana tiene que soltarlos todos: la
    // limpieza de fin de cada una se emite despues y no se alcanza.
    fuera: lista<lista<str>>,
    // Cuantos bloques habia abiertos al empezar el bucle mas de dentro.
    // Salir de un bucle salta el cierre de los bloques de dentro, asi que
    // hay que soltarlos a mano; los de fuera siguen vivos.
    bucles: lista<usize>,
    // Cuantas listas de `fuera` habia al abrir cada bucle: `break` y
    // `continue` sueltan solo las de las sentencias de dentro del bucle.
    bucles_t: lista<usize>,
    // La primera sentencia que esta capa no supo hacer, y de que clase era.
    // No cambia nada de lo que se emite: sirve para poder decir que falta
    // sin tener que adivinarlo contando nodos.
    fallo_linea: usize,
    fallo_clase: str,
    // Las copias de genericas que piden las llamadas, en el orden en que se
    // terminan de escribir: `plantilla\tnombre_c\tT=tipo...`.
    instancias: lista<str>,
    // Los tipos que se copian con un copiador generado, en orden.
    copias: lista<str>,
}

// Lo apunta el sitio mas hondo, y solo la primera vez: si un `if` falla
// porque falla algo de dentro, lo que interesa es lo de dentro.
fn apuntar_fallo(b: mut Cuerpo, n: &P.Nodo) {
    if b.fallo_linea != 0 { return; }
    b.fallo_linea = n.linea;
    b.fallo_clase = nuevo(vista(n.clase));
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
    return Cuerpo { lineas: [], bloques: [], claves: [], sangria: 1, temporal: 0,
        ultima_linea: 0, bucle: 0, bucles: [], temporales: [], fuera: [], bucles_t: [],
        fallo_linea: 0, fallo_clase: vacio(), instancias: [], copias: [] };
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
    let vacias: lista<str> = [];
    anadir(b.claves, vacias);
}

// `clave` es `nombre@linea` de la declaracion: la bandera se busca por ella.
fn anotar_duenio(b: mut Cuerpo, nombre: view, tipo: view, clave: view) {
    if largo(b.bloques) == 0 { abrir_bloque(b); }
    var junto = nuevo(nombre);
    empujar(junto, ": ");
    empujar(junto, tipo);
    let ultimo = largo(b.bloques) - 1;
    anadir(b.bloques[ultimo], junto);
    anadir(b.claves[ultimo], nuevo(clave));
}

fn clave_de(nombre: view, linea: usize) -> str {
    var k = nuevo(nombre);
    empujar(k, "@");
    empujar(k, texto(linea));
    return k;
}

fn antes_de_arroba(t: view) -> str {
    var i = largo(t);
    while i > 0 {
        i = i - 1;
        if byte(t, i) == 64 { return nuevo(rebanar(t, 0, i)); }
    }
    return nuevo(t);
}

// La declaracion visible de un nombre, de dentro hacia fuera. Si no la hay,
// es un parametro: esos se apuntan con la linea 0.
fn clave_visible(b: &Cuerpo, nombre: view) -> str {
    var i = largo(b.bloques);
    while i > 0 {
        i = i - 1;
        var j = largo(b.bloques[i]);
        while j > 0 {
            j = j - 1;
            let n = antes_de_dos_puntos(vista(b.bloques[i][j]));
            if igual(vista(n), nombre) { return copiar(b.claves[i][j]); }
        }
    }
    return clave_de(nombre, 0);
}

fn lleva_bandera(b: &Cuerpo, s: &Sitio, nombre: view) -> bool {
    let k = clave_visible(b, nombre);
    return tiene(s.pide_bandera, vista(k));
}

// Suelta lo del bloque de dentro, en orden inverso, y lo quita de la pila.
fn cerrar_bloque(b: mut Cuerpo, s: &Sitio, tipos: &I.Contexto) {
    if largo(b.bloques) == 0 { return; }
    let ultimo = largo(b.bloques) - 1;
    liberar_uno(b, s, tipos, ultimo, "");
    quitar_ultimo_bloque(b);
}

// Deja el cuerpo como estaba en `hasta` lineas. Lo usa el `while` cuya
// condicion hay que rehacer dentro del bucle.
fn recortar_lineas(b: mut Cuerpo, hasta: usize) {
    var quedan: lista<str> = [];
    var i = 0;
    while i < hasta {
        anadir(quedan, copiar(b.lineas[i]));
        i = i + 1;
    }
    b.lineas = quedan;
}

// Un temporal de sentencia: nace aqui y se suelta al acabar la sentencia,
// salvo que alguien se quede con el.
fn apuntar_temporal(b: mut Cuerpo, nombre: view, tipo: view) {
    var junto = nuevo(nombre);
    empujar(junto, ": ");
    empujar(junto, tipo);
    anadir(b.temporales, junto);
}

// Quien se queda con un temporal lo dice, y deja de soltarse aqui.
fn reclamar(b: mut Cuerpo, valor: view) {
    var quedan: lista<str> = [];
    for t en b.temporales {
        let n = antes_de_dos_puntos(vista(t));
        if !igual(vista(n), valor) { anadir(quedan, copiar(t)); }
    }
    b.temporales = quedan;
}

fn soltar_temporales(b: mut Cuerpo, tipos: &I.Contexto) {
    var i = 0;
    while i < largo(b.temporales) {
        let entrada = copiar(b.temporales[i]);
        let n = antes_de_dos_puntos(vista(entrada));
        let t = despues_de_dos_puntos(vista(entrada));
        liberacion(b, tipos, vista(n), vista(t));
        i = i + 1;
    }
}

// Lo que ya se solto al salir no se suelta otra vez.
fn olvidar_temporales(b: mut Cuerpo) {
    let vacia: lista<str> = [];
    b.temporales = vacia;
}

fn quitar_ultimo_bucle(b: mut Cuerpo) {
    if largo(b.bucles) == 0 { return; }
    var quedan: lista<usize> = [];
    var i = 0;
    while i + 1 < largo(b.bucles) {
        anadir(quedan, b.bucles[i]);
        i = i + 1;
    }
    b.bucles = quedan;
    var quedan_t: lista<usize> = [];
    var j = 0;
    while j + 1 < largo(b.bucles_t) {
        anadir(quedan_t, b.bucles_t[j]);
        j = j + 1;
    }
    b.bucles_t = quedan_t;
}

fn quitar_ultimo_bloque(b: mut Cuerpo) {
    var quedan: lista<lista<str>> = [];
    var sus_claves: lista<lista<str>> = [];
    var i = 0;
    while i + 1 < largo(b.bloques) {
        var copia: lista<str> = [];
        for x en b.bloques[i] { anadir(copia, copiar(x)); }
        anadir(quedan, copia);
        var ks: lista<str> = [];
        for x en b.claves[i] { anadir(ks, copiar(x)); }
        anadir(sus_claves, ks);
        i = i + 1;
    }
    b.bloques = quedan;
    b.claves = sus_claves;
}

// Todo lo vivo, de dentro hacia fuera: es lo que hace falta antes de un
// `return`, donde no se cierra un bloque sino todos.
fn liberar_todo(b: mut Cuerpo, s: &Sitio, tipos: &I.Contexto,
    excepto: view) {
    // Los de la sentencia en curso primero: `return $"{rellenar(v, 8)}"`
    // dejaria el `str` de `rellenar` sin soltar, porque la limpieza de fin
    // de sentencia se emite DESPUES del `return` y no se ejecuta nunca.
    soltar_temporales(b, tipos);
    // Y los de las sentencias que la envuelven: en `if largo(claves(m)) > 0
    // { return 1; }` la lista de `claves` es de la condicion del `if`, no del
    // `return`, y sin esto se escapaba por ese camino.
    soltar_fuera_desde(b, tipos, 0);
    var i = largo(b.bloques);
    while i > 0 {
        i = i - 1;
        liberar_uno(b, s, tipos, i, excepto);
    }
}

// Las listas de `fuera` desde `desde`, de dentro hacia fuera. Se sueltan
// sin quitarlas: el camino que no sale tiene que soltarlas igual al acabar
// cada sentencia.
fn soltar_fuera_desde(b: mut Cuerpo, tipos: &I.Contexto, desde: usize) {
    var k = largo(b.fuera);
    while k > desde {
        k = k - 1;
        let copia = copiar(b.fuera[k]);
        for entrada en copia {
            let n = antes_de_dos_puntos(vista(entrada));
            let t = despues_de_dos_puntos(vista(entrada));
            liberacion(b, tipos, vista(n), vista(t));
        }
    }
}

fn quitar_ultima_fuera(b: mut Cuerpo) {
    if largo(b.fuera) == 0 { return; }
    var quedan: lista<lista<str>> = [];
    var i = 0;
    while i + 1 < largo(b.fuera) {
        anadir(quedan, copiar(b.fuera[i]));
        i = i + 1;
    }
    b.fuera = quedan;
}

fn liberar_uno(b: mut Cuerpo, s: &Sitio, tipos: &I.Contexto,
    cual: usize, excepto: view) {
    var j = largo(b.bloques[cual]);
    while j > 0 {
        j = j - 1;
        let entrada = copiar(b.bloques[cual][j]);
        let nombre = antes_de_dos_puntos(vista(entrada));
        if igual(vista(nombre), excepto) { continue; }
        let tipo = despues_de_dos_puntos(vista(entrada));
        // Si se entrega por algun camino, quien decide es la bandera: aqui
        // no se sabe por cual se vino.
        if tiene(s.pide_bandera, vista(b.claves[cual][j])) {
            var g = nuevo("if (ss_vivo_");
            empujar(g, vista(nombre));
            empujar(g, ")");
            emitir(b, vista(g));
            emitir(b, "{");
            b.sangria = b.sangria + 1;
            liberacion(b, tipos, vista(nombre), vista(tipo));
            b.sangria = b.sangria - 1;
            emitir(b, "}");
            continue;
        }
        liberacion(b, tipos, vista(nombre), vista(tipo));
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

fn liberacion(b: mut Cuerpo, tipos: &I.Contexto, nombre: view,
    tipo: view) {
    if igual(tipo, "str") {
        var l = nuevo("ss_free(&");
        empujar(l, nombre);
        empujar(l, ");");
        emitir(b, vista(l));
        return;
    }
    // Una lista suelta su memoria y se queda vacia. Si sus elementos tienen
    // duenio, cada uno se suelta antes: la lista era su unica duenia.
    // Un arreglo no tiene memoria propia que devolver: vive entero donde se
    // declaro. Lo que haya que soltar son sus elementos, si poseen, uno a uno.
    if T.es_arreglo(tipo) {
        let elem = T.elemento(tipo);
        if !I.posee_con_formas(tipos, vista(elem)) { return; }
        b.bucle = b.bucle + 1;
        let i = nombre_de_bucle(b.bucle);
        let cuantos = cuantos_de_arreglo(tipo);
        var f = nuevo("for (size_t ");
        empujar(f, vista(i));
        empujar(f, " = 0; ");
        empujar(f, vista(i));
        empujar(f, " < ");
        empujar(f, vista(cuantos));
        empujar(f, "; ");
        empujar(f, vista(i));
        empujar(f, "++)");
        emitir(b, vista(f));
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        var dentro = nuevo(nombre);
        empujar(dentro, ".e[");
        empujar(dentro, vista(i));
        empujar(dentro, "]");
        liberacion(b, tipos, vista(dentro), vista(elem));
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        return;
    }

    // Un mapa suelta su tabla, sus claves y sus valores de una vez: lleva
    // su propio liberador generado, como cada tipo de mapa lleva el suyo.
    if T.es_mapa(tipo) {
        var l = nuevo("ss_mapa_libre_");
        empujar(l, mangle(tipo));
        empujar(l, "(&");
        empujar(l, nombre);
        empujar(l, ");");
        emitir(b, vista(l));
        return;
    }

    if T.es_lista(tipo) {
        let elem = T.elemento(tipo);
        if I.posee_con_formas(tipos, vista(elem)) {
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
            liberacion(b, tipos, vista(dentro), vista(elem));
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
        return;
    }

    // Un struct que posee lleva su liberador generado, que suelta sus campos
    // en orden. El nombre no lleva el alias del modulo: en C no queda.
    if I.posee_con_formas(tipos, tipo) {
        let corto = I.sin_modulo(tipo);
        var l = nuevo("ss_drop_");
        empujar(l, vista(corto));
        empujar(l, "(&");
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
// Lo que esta sentencia entrego, apagado aqui mismo: el camino se acaba.
fn apagar_las_de(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) {
    var salen: lista<str> = [];
    movidas_en(s.punteros, n, tipos, salen);
    var vivas: lista<str> = [];
    for nm en salen {
        if lleva_bandera(b, s, vista(nm)) { anadir(vivas, copiar(nm)); }
    }
    apagar(b, vivas);
}

fn primer_nombre(t: view) -> str {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 44 { return nuevo(recortar(rebanar(t, 0, i))); }
        i = i + 1;
    }
    return nuevo(recortar(t));
}

fn segundo_nombre(t: view) -> str {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 44 {
            return nuevo(recortar(rebanar(t, i + 1, largo(t))));
        }
        i = i + 1;
    }
    return vacio();
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

// Cada sentencia tiene sus propios temporales, y al acabar se sueltan. Los
// de fuera se guardan y se devuelven: una sentencia puede llevar otras
// dentro, y las de dentro no heredan lo que quedo a medias fuera.
fn sentencia_c(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo,
    tipos: mut I.Contexto, retorno: view, falible: bool) -> bool {
    var antes: lista<str> = [];
    for t en b.temporales { anadir(antes, copiar(t)); }
    var de_fuera: lista<str> = [];
    for t en antes { anadir(de_fuera, copiar(t)); }
    anadir(b.fuera, de_fuera);
    let vacia: lista<str> = [];
    b.temporales = vacia;

    let bien = una_sentencia(b, s, n, tipos, retorno, falible);
    if bien { soltar_temporales(b, tipos); }
    b.temporales = antes;
    quitar_ultima_fuera(b);
    return bien;
}

fn una_sentencia(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo,
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
            valor = try_c(b, s, n.hijos[0], tipos);
        } else {
            valor = expresion_c(b, s, n.hijos[0], vista(tipo), tipos);
        }
        if es_desconocido(vista(valor)) { return false; }
        // La variable se queda con el temporal: deja de soltarse al acabar
        // la sentencia, porque ahora tiene duenio con nombre.
        reclamar(b, vista(valor));

        var l = nuevo("SS_LANG_QUIZA_SIN_USAR ");
        empujar(l, tipo_c(vista(tipo)));
        empujar(l, " ");
        empujar(l, vista(nombre));
        empujar(l, " = ");
        empujar(l, vista(valor));
        empujar(l, ";");
        emitir(b, vista(l));

        I.declarar(tipos, vista(nombre), vista(tipo));
        if I.posee_con_formas(tipos, vista(tipo)) {
            let clave = clave_de(vista(nombre), n.linea);
            anotar_duenio(b, vista(nombre), vista(tipo), vista(clave));
            if tiene(s.pide_bandera, vista(clave)) {
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
        if empujar_c(b, s, n.hijos[0], tipos) {
            apagar_las_de(b, s, n, tipos);
            return true;
        }
        // `poner(m, k, v)` devuelve algo que casi nadie mira: como sentencia
        // se escribe la llamada y se tira el valor, como en C.
        if igual(vista(n.hijos[0].clase), "llamada")
        && igual(vista(n.hijos[0].texto), "poner") {
            let hecha = interna_pura(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(hecha)) { return false; }
            var l = copiar(hecha);
            empujar(l, ";");
            emitir(b, vista(l));
            apagar_las_de(b, s, n, tipos);
            return true;
        }
        // Un `match` suelto mira y hace: el `switch` va tal cual, sin
        // temporal donde dejar nada.
        if igual(vista(n.hijos[0].clase), "match") {
            if !match_c(b, s, n.hijos[0], tipos, retorno, falible, "") {
                return false;
            }
            apagar_las_de(b, s, n, tipos);
            return true;
        }
        // Cualquier otra expresion suelta. Descarta su valor, y si ese valor
        // tenia duenio, este es el sitio donde se devuelve: `try espera(...)`
        // como sentencia tira el `str` que devuelve, y nadie mas lo iba a
        // soltar.
        let x = vista(n.hijos[0].clase);
        let hecha = expresion_c(b, s, n.hijos[0], "", tipos);
        if es_desconocido(vista(hecha)) { return false; }
        let t = tipo_suelto(n.hijos[0], tipos);
        if largo(hecha) > 0 && largo(vista(t)) > 0 && !igual(vista(t), "()")
        && I.posee_con_formas(tipos, vista(t)) {
            reclamar(b, vista(hecha));
            var suelto = copiar(hecha);
            // `liberacion` toma la direccion de lo que suelta, y el
            // resultado de una llamada no tiene direccion: `f();` a secas
            // daria `ss_free(&f())`, que ni siquiera es C. Se guarda antes.
            if !es_identificador(vista(hecha)) {
                let tmp = nuevo_temporal(b);
                var g = nuevo(tipo_c(vista(t)));
                empujar(g, " ");
                empujar(g, vista(tmp));
                empujar(g, " = ");
                empujar(g, vista(hecha));
                empujar(g, ";");
                emitir(b, vista(g));
                suelto = copiar(tmp);
            }
            liberacion(b, tipos, vista(suelto), vista(t));
            apagar_las_de(b, s, n, tipos);
            return true;
        }
        // `try f();` y `f() sino x;` ya emitieron todo su trabajo: lo que
        // devuelven es el valor, y como sentencia no haria nada.
        if largo(hecha) > 0 && !igual(x, "try") && !igual(x, "sino") {
            var l = copiar(hecha);
            empujar(l, ";");
            emitir(b, vista(l));
        }
        apagar_las_de(b, s, n, tipos);
        return true;
    }

    if igual(clase, "falla") {
        // Salir por el camino malo: se suelta todo y se devuelve el motivo.
        if !falible { return false; }
        liberar_todo(b, s, tipos, "");
        var l = nuevo("return (");
        empujar(l, tipo_resultado(retorno));
        empujar(l, "){ .motivo = ");
        empujar(l, literal_c(vista(n.texto)));
        empujar(l, " };");
        emitir(b, vista(l));
        olvidar_temporales(b);
        return true;
    }

    if igual(clase, "retorno") {
        if largo(n.hijos) == 0 {
            liberar_todo(b, s, tipos, "");
            if falible {
                var l = nuevo("return (");
                empujar(l, tipo_resultado(retorno));
                empujar(l, "){ .motivo = NULL };");
                emitir(b, vista(l));
                olvidar_temporales(b);
                return true;
            }
            emitir(b, "return;");
            olvidar_temporales(b);
            return true;
        }
        // Devolver una variable entera no necesita temporal: no hay nada
        // que calcular, y liberar lo demas no la toca.
        if igual(vista(n.hijos[0].clase), "variable") {
            let quien = vista(n.hijos[0].texto);
            // Si lleva bandera porque se entrega por otro camino, al
            // devolverla tambien se entrega: se apaga antes de salir, o la
            // liberacion la veria encendida.
            if lleva_bandera(b, s, quien) {
                var apaga = nuevo("ss_vivo_");
                empujar(apaga, quien);
                empujar(apaga, " = false;");
                emitir(b, vista(apaga));
            }
            liberar_todo(b, s, tipos, quien);
            let c = expresion_c(b, s, n.hijos[0], retorno, tipos);
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
            olvidar_temporales(b);
            return true;
        }

        // Un `match` que da valor puede llevar brazos con sentencias, y eso
        // solo se genera desde aqui, donde el sitio se puede modificar.
        var valor = vacio();
        if igual(vista(n.hijos[0].clase), "match") {
            valor = match_valor(b, s, n.hijos[0], tipos, retorno, falible);
        } else {
            valor = expresion_c(b, s, n.hijos[0], retorno, tipos);
        }
        if es_desconocido(vista(valor)) { return false; }
        // Lo que se devuelve no se suelta: se entrega.
        reclamar(b, vista(valor));
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
        liberar_todo(b, s, tipos, vista(entregada));
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
        olvidar_temporales(b);
        return true;
    }

    if igual(clase, "si") {
        if largo(n.hijos) < 2 { return false; }
        if mueve_algo(s, n.hijos[0], tipos) { return false; }
        let cond = expresion_c(b, s, n.hijos[0], "bool", tipos);
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

        // Casi toda condicion sale entera en una expresion de C y va donde
        // va. Pero alguna necesita lineas propias —`byte` guarda la vista en
        // un temporal antes de indexarla— y esas lineas tienen que correr en
        // CADA vuelta: dejarlas fuera del bucle seria mirar, en la segunda,
        // algo calculado antes de que el cuerpo lo cambiara.
        let marca = largo(b.lineas);
        let temporal_antes = b.temporal;
        let bucle_antes = b.bucle;
        var temporales_antes: lista<str> = [];
        for t en b.temporales { anadir(temporales_antes, copiar(t)); }
        let cond = expresion_c(b, s, n.hijos[0], "bool", tipos);
        if es_desconocido(vista(cond)) { return false; }
        if largo(b.lineas) == marca {
            var l = nuevo("while (");
            empujar(l, vista(cond));
            empujar(l, ")");
            emitir(b, vista(l));
            anadir(b.bucles, largo(b.bloques));
            anadir(b.bucles_t, largo(b.fuera));
            let salio = bloque_c(b, s, n.hijos[1], tipos, retorno, falible);
            quitar_ultimo_bucle(b);
            return salio;
        }

        // Dejo lineas: se deshace y se rehace dentro.
        recortar_lineas(b, marca);
        b.temporal = temporal_antes;
        b.bucle = bucle_antes;
        b.temporales = temporales_antes;
        emitir(b, "while (true)");
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        abrir_bloque(b);
        anadir(b.bucles, largo(b.bloques) - 1);
        anadir(b.bucles_t, largo(b.fuera));
        I.abrir(tipos);
        let base = largo(b.temporales);
        var dentro = expresion_c(b, s, n.hijos[0], "bool", tipos);
        if es_desconocido(vista(dentro)) { return false; }
        // Si la condicion dejo temporales con duenio, se sueltan en cada
        // vuelta, antes de decidir: dejarlos para el final de la sentencia
        // los liberaria fuera del bucle, donde ya no existen, y se escaparia
        // uno por vuelta.
        if largo(b.temporales) > base {
            let vale = nuevo_temporal(b);
            var cap = nuevo("bool ");
            empujar(cap, vista(vale));
            empujar(cap, " = ");
            empujar(cap, vista(dentro));
            empujar(cap, ";");
            emitir(b, vista(cap));
            var k = base;
            while k < largo(b.temporales) {
                let entrada = copiar(b.temporales[k]);
                let nt = antes_de_dos_puntos(vista(entrada));
                let tt = despues_de_dos_puntos(vista(entrada));
                liberacion(b, tipos, vista(nt), vista(tt));
                k = k + 1;
            }
            var quedan: lista<str> = [];
            var q = 0;
            while q < base {
                anadir(quedan, copiar(b.temporales[q]));
                q = q + 1;
            }
            b.temporales = quedan;
            dentro = copiar(vale);
        }
        var g = nuevo("if (!(");
        empujar(g, vista(dentro));
        empujar(g, "))");
        emitir(b, vista(g));
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        emitir(b, "break;");
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        var bien = true;
        for st en n.hijos[1].hijos {
            if bien {
                bien = sentencia_c(b, s, st, tipos, retorno, falible);
                if !bien { apuntar_fallo(b, st); }
            }
        }
        if bien && !termina_saliendo(n.hijos[1]) { cerrar_bloque(b, s, tipos); }
        else { quitar_ultimo_bloque(b); }
        quitar_ultimo_bucle(b);
        I.cerrar(tipos);
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        return bien;
    }

    if igual(clase, "asignacion") {
        if largo(n.hijos) != 2 { return false; }
        let a_que = vista(n.hijos[0].clase);
        if !igual(a_que, "variable") && !igual(a_que, "campo")
        && !igual(a_que, "indice") {
            return false;
        }
        // Solo una variable entera lleva bandera: un campo se apunta por su
        // struct, y eso es otra capa.
        var nombre = vacio();
        if igual(a_que, "variable") { nombre = nuevo(vista(n.hijos[0].texto)); }
        let tipo = I.tipo_de(tipos, n.hijos[0]);
        if largo(tipo) == 0 { return false; }
        let valor = expresion_c(b, s, n.hijos[1], vista(tipo), tipos);
        if es_desconocido(vista(valor)) { return false; }
        reclamar(b, vista(valor));
        let destino = expresion_c(b, s, n.hijos[0], vista(tipo), tipos);
        if es_desconocido(vista(destino)) { return false; }

        // Asignar a algo con duenio pide soltar lo viejo. `liberacion` ya sabe
        // soltar cualquier cosa que posea: `str`, listas, mapas y structs.
        if I.posee_con_formas(tipos, vista(tipo)) {
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

            if lleva_bandera(b, s, vista(nombre)) {
                // Si ya se lo llevaron, aqui no hay nada que devolver:
                // soltarlo seria soltarlo dos veces.
                var w = nuevo("if (ss_vivo_");
                empujar(w, vista(nombre));
                empujar(w, ")");
                emitir(b, vista(w));
                emitir(b, "{");
                b.sangria = b.sangria + 1;
                liberacion(b, tipos, vista(destino), vista(tipo));
                b.sangria = b.sangria - 1;
                emitir(b, "}");
                var a = copiar(destino);
                empujar(a, " = ");
                empujar(a, vista(tmp));
                empujar(a, ";");
                emitir(b, vista(a));
                var enciende = nuevo("ss_vivo_");
                empujar(enciende, vista(nombre));
                empujar(enciende, " = true;");
                emitir(b, vista(enciende));
                apagar_las_de(b, s, n, tipos);
                return true;
            }
            liberacion(b, tipos, vista(destino), vista(tipo));
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
        // `for x en ...` o, sobre un mapa, `for clave, valor en m`.
        let uno = primer_nombre(vista(n.texto));
        let dos = segundo_nombre(vista(n.texto));
        // Un sitio con nombre: variable, campo o elemento. `for x en f(...)`
        // no, que se calcula una sola vez y eso pide un temporal que soltar
        // al final.
        let que = vista(n.hijos[0].clase);
        let suyo = I.tipo_de(tipos, n.hijos[0]);
        let sobre = T.apuntado_si(vista(suyo));
        let es_mapa_ = T.es_mapa(vista(sobre));
        let es_arreglo_ = T.es_arreglo(vista(sobre));
        if !T.es_lista(vista(sobre)) && !es_mapa_ && !es_arreglo_ { return false; }
        if largo(dos) > 0 && !es_mapa_ { return false; }
        var lugar = vacio();
        if igual(que, "variable") || igual(que, "campo") || igual(que, "indice") {
            lugar = sitio_c(b, s, n.hijos[0], tipos);
        } else {
            // `for x en f(...)`: la coleccion se calcula UNA vez. Dejar la
            // llamada en la condicion la repetiria en cada vuelta, y cada
            // vuelta filtraria una copia.
            let tmp = nuevo_temporal(b);
            let valor = expresion_c(b, s, n.hijos[0], vista(sobre), tipos);
            if es_desconocido(vista(valor)) { return false; }
            reclamar(b, vista(valor));
            var l = nuevo(tipo_c(vista(sobre)));
            empujar(l, " ");
            empujar(l, vista(tmp));
            empujar(l, " = ");
            empujar(l, vista(valor));
            empujar(l, ";");
            emitir(b, vista(l));
            apuntar_temporal(b, vista(tmp), vista(sobre));
            lugar = copiar(tmp);
        }
        if es_desconocido(vista(lugar)) { return false; }

        b.bucle = b.bucle + 1;
        let i = nombre_de_indice(b.bucle);
        var f = nuevo("for (size_t ");
        empujar(f, vista(i));
        empujar(f, " = 0; ");
        empujar(f, vista(i));
        empujar(f, " < ");
        if es_arreglo_ {
            let cuantos = cuantos_de_arreglo(vista(sobre));
            empujar(f, vista(cuantos));
            empujar(f, "; ");
        } else {
            empujar(f, vista(lugar));
            // Una tabla se recorre por sus celdas, y se saltan las vacias.
            if es_mapa_ { empujar(f, ".capacidad; "); }
            else { empujar(f, ".length; "); }
        }
        empujar(f, vista(i));
        empujar(f, "++)");
        emitir(b, vista(f));
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        if es_mapa_ {
            var salta = nuevo("if (");
            empujar(salta, vista(lugar));
            empujar(salta, ".claves[");
            empujar(salta, vista(i));
            empujar(salta, "].data == NULL) continue;");
            emitir(b, vista(salta));
        }
        abrir_bloque(b);
        anadir(b.bucles, largo(b.bloques) - 1);
        anadir(b.bucles_t, largo(b.fuera));
        I.abrir(tipos);

        // El elemento se presta, no se copia: un `str` copiado tendria dos
        // duenios. Los escalares van por valor, que no hay nada que duplicar.
        // Sobre un mapa lo que se recorre son las claves, y nadie copia una:
        // se presta la que ya esta en la tabla.
        var elem = T.elemento(vista(sobre));
        if es_mapa_ {
            let partes = T.partir_tipos(T.entre_angulos(vista(sobre)));
            if largo(partes) != 2 { return false; }
            elem = copiar(partes[0]);
        }
        let quien = vista(uno);
        let elem_posee = I.posee_con_formas(tipos, vista(elem));
        var acceso = copiar(lugar);
        if es_mapa_ { empujar(acceso, ".claves["); }
        else { empujar(acceso, ".e["); }
        empujar(acceso, vista(i));
        empujar(acceso, "]");
        var d = nuevo("SS_LANG_QUIZA_SIN_USAR ");
        let presta = elem_posee;
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
        if largo(dos) > 0 {
            // El valor va tal cual: un escalar se copia solo.
            let tv = T.valor_de_mapa(vista(sobre)) sino vacio();
            if largo(tv) == 0 { return false; }
            var dv = nuevo("SS_LANG_QUIZA_SIN_USAR ");
            empujar(dv, tipo_c(vista(tv)));
            empujar(dv, " ");
            empujar(dv, vista(dos));
            empujar(dv, " = ");
            empujar(dv, vista(lugar));
            empujar(dv, ".valores[");
            empujar(dv, vista(i));
            empujar(dv, "];");
            emitir(b, vista(dv));
            I.declarar(tipos, vista(dos), vista(tv));
        }
        let ya_era = tiene(s.punteros, quien);
        if presta { poner(s.punteros, quien, 1); }

        var bien = true;
        for st en n.hijos[1].hijos {
            if bien {
                bien = sentencia_c(b, s, st, tipos, retorno, falible);
                if !bien { apuntar_fallo(b, st); }
            }
        }
        if bien && !termina_saliendo(n.hijos[1]) { cerrar_bloque(b, s, tipos); }
        else { quitar_ultimo_bloque(b); }

        if presta && !ya_era { quitar(s.punteros, quien); }
        quitar_ultimo_bucle(b);
        I.cerrar(tipos);
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        return bien;
    }

    if igual(clase, "romper") || igual(clase, "continuar") {
        // Los temporales de las sentencias de dentro del bucle —la condicion
        // de un `if` que contiene el `break`— no llegan a su limpieza de fin.
        // Los del propio bucle si: siguen haciendo falta.
        soltar_temporales(b, tipos);
        if largo(b.bucles_t) > 0 {
            soltar_fuera_desde(b, tipos, b.bucles_t[largo(b.bucles_t) - 1] + 1);
        }
        // Lo que nacio dentro del bucle no lo cierra nadie si se sale por
        // aqui: se suelta ahora, de dentro hacia fuera.
        var desde = 0;
        if largo(b.bucles) > 0 { desde = b.bucles[largo(b.bucles) - 1]; }
        var i = largo(b.bloques);
        while i > desde {
            i = i - 1;
            liberar_uno(b, s, tipos, i, "");
        }
        if igual(clase, "romper") { emitir(b, "break;"); }
        else { emitir(b, "continue;"); }
        return true;
    }

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
        if bien {
            bien = sentencia_c(b, s, h, tipos, retorno, falible);
            if !bien { apuntar_fallo(b, h); }
        }
    }
    if bien && !termina_saliendo(n) { cerrar_bloque(b, s, tipos); }
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
// Lo que da una llamada que puede fallar cuando sale bien. Una del programa
// lo dice su firma; una interna como `obtener` sale del tipo del mapa.
fn tipo_si_va_bien(n: &P.Nodo, tipos: &I.Contexto) -> str {
    let llamado = vista(n.texto);
    if tiene(tipos.retornos, llamado) {
        return nuevo(obtener(tipos.retornos, llamado) sino "");
    }
    if igual(llamado, "obtener") || igual(llamado, "leer_archivo")
    || igual(llamado, "leer_linea") || igual(llamado, "entrada_completa")
    || igual(llamado, "variable_entorno") {
        return I.tipo_de(tipos, n);
    }
    return vacio();
}

fn try_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let retorno = vista(s.retorno);
    if largo(n.hijos) != 1 { return no_se(); }
    if !igual(vista(n.hijos[0].clase), "llamada") { return no_se(); }
    let suyo = tipo_si_va_bien(n.hijos[0], tipos);
    // Vacio puede ser "no la conozco" o "no devuelve nada": solo lo segundo
    // vale, y lo dice que este en las firmas.
    if largo(vista(suyo)) == 0
    && !tiene(tipos.retornos, vista(n.hijos[0].texto)) {
        return no_se();
    }

    // El temporal se reserva antes de generar la llamada, como el original:
    // la llamada puede reservar los suyos, y el orden decide los numeros.
    let tmp = nuevo_temporal(b);
    let c = llamada_c(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(c)) { return no_se(); }

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
    liberar_todo(b, s, tipos, "");
    var sale = nuevo("return (");
    empujar(sale, tipo_resultado(retorno));
    empujar(sale, "){ .motivo = ");
    empujar(sale, vista(tmp));
    empujar(sale, ".motivo };");
    emitir(b, vista(sale));
    b.sangria = b.sangria - 1;
    emitir(b, "}");

    // Sin valor no hay nada que leer: el trabajo ya esta emitido.
    if largo(vista(suyo)) == 0 || igual(vista(suyo), "()") { return vacio(); }
    var leer = copiar(tmp);
    empujar(leer, ".valor");
    return leer;
}

// `f(x) sino otra_cosa`: si falla, el valor de al lado. Es la unica forma
// de que un fallo no se propague, y por eso se escribe: en Tcode no hay
// forma callada de ignorar uno.
fn sino_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 2 { return no_se(); }
    if !igual(vista(n.hijos[0].clase), "llamada") { return no_se(); }
    let suyo = tipo_si_va_bien(n.hijos[0], tipos);
    if largo(vista(suyo)) == 0 { return no_se(); }

    // El temporal se reserva antes de generar la llamada, como el original:
    // la llamada puede reservar los suyos, y el orden decide los numeros.
    let tmp = nuevo_temporal(b);
    let c = llamada_c(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(c)) { return no_se(); }

    var l = nuevo(tipo_resultado(vista(suyo)));
    empujar(l, " ");
    empujar(l, vista(tmp));
    empujar(l, " = ");
    empujar(l, vista(c));
    empujar(l, ";");
    emitir(b, vista(l));

    let elegido = nuevo_temporal(b);
    var d = nuevo(tipo_c(vista(suyo)));
    empujar(d, " ");
    empujar(d, vista(elegido));
    empujar(d, ";");
    emitir(b, vista(d));

    var cond = nuevo("if (");
    empujar(cond, vista(tmp));
    empujar(cond, ".motivo != NULL)");
    emitir(b, vista(cond));
    emitir(b, "{");
    b.sangria = b.sangria + 1;
    let alt = expresion_c(b, s, n.hijos[1], vista(suyo), tipos);
    if es_desconocido(vista(alt)) { return no_se(); }
    var pone = copiar(elegido);
    empujar(pone, " = ");
    empujar(pone, vista(alt));
    empujar(pone, ";");
    emitir(b, vista(pone));
    b.sangria = b.sangria - 1;
    emitir(b, "}");
    emitir(b, "else");
    emitir(b, "{");
    b.sangria = b.sangria + 1;
    var otro = copiar(elegido);
    empujar(otro, " = ");
    empujar(otro, vista(tmp));
    empujar(otro, ".valor;");
    emitir(b, vista(otro));
    b.sangria = b.sangria - 1;
    emitir(b, "}");
    return elegido;
}

// `anadir(xs, v)`: la lista se queda con el valor.
fn anadir_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> bool {
    if !igual(vista(n.clase), "llamada") { return false; }
    if !igual(vista(n.texto), "anadir") { return false; }
    if largo(n.hijos) != 2 { return false; }
    let suya = I.tipo_de(tipos, n.hijos[0]);
    let sobre = T.apuntado_si(vista(suya));
    if !T.es_lista(vista(sobre)) { return false; }
    let elem = T.elemento(vista(sobre));
    // Meter una variable con duenio en una lista la mueve: la lista se la
    // queda y desde aqui la suelta ella.
    if entrega_variable(s, n.hijos[1], tipos) {
        if !lleva_bandera(b, s, vista(n.hijos[1].texto)) { return false; }
    }
    let valor = expresion_c(b, s, n.hijos[1], vista(elem), tipos);
    if es_desconocido(vista(valor)) { return false; }
    reclamar(b, vista(valor)); // la lista se lo queda

    let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(donde)) { return false; }
    var l = nuevo("ss_push_");
    empujar(l, mangle(vista(sobre)));
    empujar(l, "(");
    empujar(l, vista(donde));
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

// `if c { a } else { b }` como valor. Se baja a una variable y un `if`, no
// al `?:` de C: cada rama puede necesitar emitir lineas propias, y dentro
// de `?:` no caben.
fn si_expr_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 3 { return no_se(); }
    var t = I.tipo_de(tipos, n);
    if largo(t) == 0 { t = nuevo("usize"); }
    let tmp = nuevo_temporal(b);
    var d = nuevo(tipo_c(vista(t)));
    empujar(d, " ");
    empujar(d, vista(tmp));
    empujar(d, ";");
    emitir(b, vista(d));
    let cond = expresion_c(b, s, n.hijos[0], "bool", tipos);
    if es_desconocido(vista(cond)) { return no_se(); }
    var l = nuevo("if (");
    empujar(l, vista(cond));
    empujar(l, ")");
    emitir(b, vista(l));
    var k = 1;
    while k < 3 {
        if k == 2 { emitir(b, "else"); }
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        let rama_c = expresion_c(b, s, n.hijos[k], vista(t), tipos);
        if es_desconocido(vista(rama_c)) { return no_se(); }
        var pone = copiar(tmp);
        empujar(pone, " = ");
        empujar(pone, vista(rama_c));
        empujar(pone, ";");
        emitir(b, vista(pone));
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        k = k + 1;
    }
    if I.posee_con_formas(tipos, vista(t)) {
        apuntar_temporal(b, vista(tmp), vista(t));
    }
    return copiar(tmp);
}

// `SS_FIGURA_CIRCULO`: el nombre en C de una forma.
fn etiqueta(enum_: view, variante: view) -> str {
    let a = mayusculas(enum_);
    let v = mayusculas(variante);
    var r = nuevo("SS_");
    empujar(r, vista(a));
    empujar(r, "_");
    empujar(r, vista(v));
    return r;
}

fn mayusculas(t: view) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(t) {
        let c = byte(t, i);
        if c >= 97 && c <= 122 { empujar_byte(r, (c - 32) como ? u8); }
        else { empujar(r, rebanar(t, i, i + 1)); }
        i = i + 1;
    }
    return r;
}

// El `switch` de un `match` suelto. Cada brazo es un bloque propio: lo que
// nazca dentro se suelta al salir. Lo que atrapa el patron se presta
// siempre —un `match` mira, no desmonta—, asi que un `str` se ve como
// `view` y lo demas con duenio como un puntero.
// `destino` es la variable de C donde dejar el valor si el `match` da uno,
// o vacio si es suelto.
fn match_c(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo, tipos: mut I.Contexto,
    retorno: view, falible: bool, destino: view) -> bool {
    if largo(n.hijos) < 2 { return false; }
    let crudo = I.tipo_de(tipos, n.hijos[0]);
    let apuntado = T.apuntado_si(vista(crudo));
    let base = I.sin_modulo(vista(apuntado));
    if !tiene(tipos.variantes, vista(base)) { return false; }
    let sitio = sitio_c(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(sitio)) { return false; }

    var sw = nuevo("switch (");
    empujar(sw, vista(sitio));
    empujar(sw, ".etiqueta)");
    emitir(b, vista(sw));
    emitir(b, "{");
    var todos = true;
    var k = 1;
    while k < largo(n.hijos) {
        if !igual(vista(n.hijos[k].clase), "brazo") { return false; }
        let variante = I.tras_el_punto(vista(n.hijos[k].texto));
        if largo(vista(n.hijos[k].texto)) == 0 {
            todos = false;
            emitir(b, "default:");
        } else {
            let et = etiqueta(vista(base), vista(variante));
            var c = nuevo("case ");
            empujar(c, vista(et));
            empujar(c, ":");
            emitir(b, vista(c));
        }
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        abrir_bloque(b);
        I.abrir(tipos);

        var clave = copiar(base);
        empujar(clave, ".");
        empujar(clave, vista(variante));
        let lleva = I.lista_de(tipos.formas, vista(clave)) sino [];
        var i = 0;
        var bien = true;
        for h en n.hijos[k].hijos {
            let que = vista(h.clase);
            if igual(que, "atrapa") {
                if i >= largo(lleva) { return false; }
                let t = vista(lleva[i]);
                var dentro = copiar(sitio);
                empujar(dentro, ".dato.v_");
                empujar(dentro, vista(variante));
                empujar(dentro, "._");
                empujar(dentro, texto(i));
                var l = nuevo("SS_LANG_QUIZA_SIN_USAR ");
                if igual(t, "str") {
                    empujar(l, "SafeView ");
                    empujar(l, vista(h.texto));
                    empujar(l, " = ss_view(&");
                    empujar(l, vista(dentro));
                    empujar(l, ");");
                    I.declarar(tipos, vista(h.texto), "view");
                } else {
                    if I.posee_con_formas(tipos, t) {
                        empujar(l, "const ");
                        empujar(l, tipo_c(t));
                        empujar(l, "* ");
                        empujar(l, vista(h.texto));
                        empujar(l, " = &");
                        empujar(l, vista(dentro));
                        empujar(l, ";");
                        var ref = nuevo("&");
                        empujar(ref, t);
                        I.declarar(tipos, vista(h.texto), vista(ref));
                    } else {
                        empujar(l, tipo_c(t));
                        empujar(l, " ");
                        empujar(l, vista(h.texto));
                        empujar(l, " = ");
                        empujar(l, vista(dentro));
                        empujar(l, ";");
                        I.declarar(tipos, vista(h.texto), t);
                    }
                }
                emitir(b, vista(l));
                i = i + 1;
            }
            if igual(que, "bloque") {
                for st en h.hijos {
                    if bien {
                        bien = sentencia_c(b, s, st, tipos, retorno, falible);
                        if !bien { apuntar_fallo(b, st); }
                    }
                }
                if !bien { return false; }
                if termina_saliendo(h) { quitar_ultimo_bloque(b); }
                else { cerrar_bloque(b, s, tipos); }
            }
            // Un brazo que da un valor: se deja en el destino. Sus
            // temporales son suyos y se sueltan aqui, antes de salir del
            // brazo, igual que los de una sentencia.
            if igual(que, "retorno") {
                if largo(destino) == 0 || largo(h.hijos) != 1 { return false; }
                marcar(b, s, h.linea);
                var antes: lista<str> = [];
                for x en b.temporales { anadir(antes, copiar(x)); }
                olvidar_temporales(b);
                let tv = I.tipo_de(tipos, h.hijos[0]);
                let valor = expresion_c(b, s, h.hijos[0], vista(tv), tipos);
                if es_desconocido(vista(valor)) { return false; }
                reclamar(b, vista(valor));
                var pone = nuevo(destino);
                empujar(pone, " = ");
                empujar(pone, vista(valor));
                empujar(pone, ";");
                emitir(b, vista(pone));
                soltar_temporales(b, tipos);
                b.temporales = antes;
                cerrar_bloque(b, s, tipos);
            }
        }
        emitir(b, "break;");
        I.cerrar(tipos);
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        k = k + 1;
    }
    // Un `match` es exhaustivo, asi que este `default` no se alcanza nunca.
    // Esta para que el compilador de C no tenga que adivinarlo.
    if todos { emitir(b, "default: break;"); }
    emitir(b, "}");
    return true;
}

// El `match` usado como valor: un temporal a ceros y el `switch` encima. A
// ceros porque en Tcode todo valor a ceros es valido, asi que el compilador
// de C no tiene de que quejarse aunque no sepa que el `switch` lo cubre todo.
fn match_valor(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo, tipos: mut I.Contexto,
    retorno: view, falible: bool) -> str {
    var t = I.tipo_de(tipos, n);
    if largo(t) == 0 { t = nuevo("usize"); }
    let tmp = nuevo_temporal(b);
    var d = nuevo(tipo_c(vista(t)));
    empujar(d, " ");
    empujar(d, vista(tmp));
    empujar(d, " = {0};");
    emitir(b, vista(d));
    if I.posee_con_formas(tipos, vista(t)) {
        apuntar_temporal(b, vista(tmp), vista(t));
    }
    if !match_c(b, s, n, tipos, retorno, falible, vista(tmp)) { return no_se(); }
    return copiar(tmp);
}

// Un tipo hecho nombre de C: cada racha de lo que no sea letra o cifra pasa
// a ser un `_`, y sin `_` en los bordes. `lista<str>` da `lista_str`.
fn sanear(t: view) -> str {
    var r = vacio();
    var pendiente = false;
    var i = 0;
    while i < largo(t) {
        let c = byte(t, i);
        let bueno = (c >= 97 && c <= 122) || (c >= 65 && c <= 90)
        || (c >= 48 && c <= 57);
        if bueno {
            if pendiente && largo(r) > 0 { empujar(r, "_"); }
            pendiente = false;
            empujar(r, rebanar(t, i, i + 1));
        } else {
            pendiente = true;
        }
        i = i + 1;
    }
    return r;
}

// De que tipo es lo que da una expresion suelta. Una llamada del programa
// lo dice su firma; un `try` o un `sino`, lo que da cuando va bien.
fn tipo_suelto(n: &P.Nodo, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);
    if (igual(clase, "try") || igual(clase, "sino")) && largo(n.hijos) > 0 {
        return tipo_si_va_bien(n.hijos[0], tipos);
    }
    if igual(clase, "llamada") && tiene(tipos.retornos, vista(n.texto)) {
        return nuevo(obtener(tipos.retornos, vista(n.texto)) sino "");
    }
    return I.tipo_de(tipos, n);
}

fn es_identificador(v: view) -> bool {
    if largo(v) == 0 { return false; }
    var i = 0;
    while i < largo(v) {
        let c = byte(v, i);
        let letra = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95;
        let cifra = c >= 48 && c <= 57;
        if !letra && ! (cifra && i > 0) { return false; }
        i = i + 1;
    }
    return true;
}

// `empujar(s, v)`: pegar texto al final de un `str`. No mueve nada, porque
// lo que se pega se copia: la vista de origen sigue siendo de quien era.
fn empujar_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> bool {
    if !igual(vista(n.clase), "llamada") { return false; }
    if !igual(vista(n.texto), "empujar") { return false; }
    if largo(n.hijos) != 2 { return false; }
    let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(donde)) { return false; }
    let que = como_vista(b, s, n.hijos[1], tipos);
    if es_desconocido(vista(que)) { return false; }
    var l = nuevo("ss_append_view(");
    empujar(l, vista(donde));
    empujar(l, ", ");
    empujar(l, vista(que));
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
