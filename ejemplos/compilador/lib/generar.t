// lib/generar.t — el C de cada tipo y de cada firma, escrito en Tcode.
//
// Sexta capa del compilador en su propio lenguaje, y la primera del
// generador. Aqui esta la cara que el C ve de un programa Tcode: como se
// llama cada tipo, y como queda la firma de cada funcion.
//
// La suite compara lo que sale de aqui con lo que emite el generador de
// Python, cadena por cadena, para cada funcion del repositorio.

usar "tipos.t" como T;
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
