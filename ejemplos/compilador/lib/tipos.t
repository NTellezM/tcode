// lib/tipos.t — la capa de tipos del comprobador, escrita en Tcode.
//
// Un tipo en Tcode es una cadena: `usize`, `lista<str>`, `mapa<str, Cosa>`,
// `bloque<T>`, `[usize; 4]`, `&Cosa`, `fn(&T, &T) -> bool`. Todo lo que el
// comprobador pregunta sobre un tipo sale de leer esa cadena y, para los
// structs, de mirar sus campos.
//
// Aqui estan las dos preguntas de las que cuelga el resto:
//
//     posee(t)        ¿un valor de este tipo es duenio de memoria?
//                     De eso depende si se libera, si se mueve o se copia.
//     tipo_existe(t)  ¿se puede guardar un valor de este tipo?
//
// El lexer y el parser de Tcode ya estan escritos en Tcode; esto es la capa
// siguiente. Se comprueba contra la de Python en cada ejecucion de la suite.

usar "std/texto";

// ------------------------------------------------------------------
// Leer la forma de un tipo
// ------------------------------------------------------------------

fn empieza(t: view, p: view) -> bool {
    return empieza_con(t, p);
}

// Lo que hay entre el primer `<` y el ultimo `>`.
fn entre_angulos(t: view) -> view {
    var desde = 0;
    while desde < largo(t) {
        if byte(t, desde) == 60 { break; }
        desde = desde + 1;
    }
    if desde >= largo(t) { return rebanar(t, 0, 0); }
    return rebanar(t, desde + 1, largo(t) - 1);
}

// Parte por las comas de fuera: `str, lista<usize>` da dos trozos.
fn partir_tipos(dentro: view) -> lista<str> {
    var salida: lista<str> = [];
    var hondura = 0;
    var desde = 0;
    var i = 0;
    while i <= largo(dentro) {
        var corta = false;
        if i == largo(dentro) {
            corta = true;
        } else {
            let b = byte(dentro, i);
            if b == 60 || b == 91 { hondura = hondura + 1; }
            if b == 62 || b == 93 { hondura = hondura - 1; }
            if b == 44 && hondura == 0 { corta = true; }
        }
        if corta {
            let trozo = recortar(rebanar(dentro, desde, i));
            if largo(trozo) > 0 { anadir(salida, nuevo(trozo)); }
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

fn es_lista(t: view) -> bool {
    return empieza(t, "lista<") && termina_con(t, ">");
}

fn es_bloque(t: view) -> bool {
    return empieza(t, "bloque<") && termina_con(t, ">");
}

fn es_mapa(t: view) -> bool {
    return empieza(t, "mapa<") && termina_con(t, ">");
}

fn es_funcion(t: view) -> bool {
    return empieza(t, "fn(");
}

fn es_arreglo(t: view) -> bool {
    return empieza(t, "[");
}

fn es_referencia(t: view) -> bool {
    return empieza(t, "&");
}

fn apuntado(t: view) -> view {
    if empieza(t, "&mut ") { return rebanar(t, 5, largo(t)); }
    return rebanar(t, 1, largo(t));
}

fn elemento(t: view) -> str {
    if es_arreglo(t) {
        // `[usize; 4]`: lo que va antes del `;`
        var i = 1;
        while i < largo(t) {
            if byte(t, i) == 59 { return nuevo(rebanar(t, 1, i)); }
            i = i + 1;
        }
        return nuevo(rebanar(t, 1, largo(t) - 1));
    }
    return nuevo(entre_angulos(t));
}

// El valor de un mapa: el segundo de los dos que van entre angulos.
fn valor_de_mapa(t: view) -> str ! {
    let partes = partir_tipos(entre_angulos(t));
    if largo(partes) != 2 { falla "un mapa lleva clave y valor"; }
    return copiar(partes[1]);
}

// ------------------------------------------------------------------
// Las dos preguntas
// ------------------------------------------------------------------

fn escalar(t: view) -> bool {
    if igual(t, "usize") || igual(t, "bool") || igual(t, "view") { return true; }
    if igual(t, "u8") || igual(t, "u16") || igual(t, "u32") || igual(t, "u64") {
        return true;
    }
    if igual(t, "i8") || igual(t, "i16") || igual(t, "i32") || igual(t, "i64") {
        return true;
    }
    return igual(t, "f32") || igual(t, "f64") || igual(t, "()");
}

// `campos` lleva, por cada struct, los tipos de sus campos.
// `visitados` corta la recursion: un `Nodo` con un campo `lista<Nodo>` se
// contiene a si mismo de forma finita, y preguntarle dos veces no aporta.
fn posee(campos: &mapa<str, lista<str>>, t: view,
    visitados: mut mapa<str, usize>) -> bool ! {
    if es_referencia(t) || es_funcion(t) { return false; }
    if igual(t, "str") { return true; }
    if es_mapa(t) || es_lista(t) || es_bloque(t) { return true; }
    if es_arreglo(t) {
        let dentro = elemento(t);
        return try posee(campos, vista(dentro), visitados);
    }
    if escalar(t) { return false; }

    // Un struct posee si alguno de sus campos posee.
    let nombre = nuevo(t);
    if tiene(visitados, vista(nombre)) { return false; }
    if !tiene(campos, vista(nombre)) { return false; }
    poner(visitados, vista(nombre), 1);

    var alguno = false;
    let suyos = try obtener(campos, vista(nombre));
    for c en suyos {
        if try posee(campos, vista(c), visitados) { alguno = true; }
    }
    return alguno;
}

fn tipo_existe(campos: &mapa<str, lista<str>>, t: view) -> bool {
    if es_referencia(t) {
        return tipo_existe(campos, apuntado(t));
    }
    if igual(t, "str") || escalar(t) { return true; }
    if es_funcion(t) { return true; }
    if es_arreglo(t) {
        let dentro = elemento(t);
        return tipo_existe(campos, vista(dentro));
    }
    if es_mapa(t) {
        let partes = partir_tipos(entre_angulos(t));
        if largo(partes) != 2 { return false; }
        return tipo_existe(campos, vista(partes[0]))
        && tipo_existe(campos, vista(partes[1]));
    }
    if es_lista(t) || es_bloque(t) {
        let dentro = elemento(t);
        // Guardar vistas o arreglos fijos en una coleccion exigiria expresar
        // su vida util o su tamaño, y v0 no los lleva en el tipo.
        if igual(vista(dentro), "view") { return false; }
        if es_arreglo(vista(dentro)) { return false; }
        return tipo_existe(campos, vista(dentro));
    }
    return tiene(campos, t);
}
