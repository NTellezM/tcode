// lib/tipar.t — decir de que tipo es cada cosa, escrito en Tcode.
//
// Cuarta capa del compilador en su propio lenguaje, despues del lexer, el
// parser y `tipos.t`. Esta responde la pregunta que hace el comprobador en
// cada expresion: ¿de que tipo es esto?
//
// Lo que produce se compara con lo que dice el comprobador de Python para
// cada variable de cada funcion del repositorio. Si difieren, la suite lo
// dice y nombra el archivo.

usar "tipos.t" como T;
usar "../../lexer/lib/sintaxis.t" como P;
usar "std/texto";
usar "std/lista";
usar "std/mapa";

// Lo que se sabe mientras se recorre un archivo.
struct Contexto {
    // Pila de ambitos: nombre -> tipo. El de dentro manda.
    ambitos: lista<mapa<str, str>>,
    // Struct -> tipos de sus campos, y sus nombres, en el mismo orden.
    campos: mapa<str, lista<str>>,
    nombres: mapa<str, lista<str>>,
    // Funcion -> lo que devuelve.
    retornos: mapa<str, str>,
    // Funcion generica -> sus parametros de tipo, y los tipos de sus
    // argumentos. Hacen falta para elegir la copia: `primeras(xs, 8)` con
    // `xs: lista<str>` devuelve `lista<str>`, no `lista<T>`.
    tipo_params: mapa<str, lista<str>>,
    params: mapa<str, lista<str>>,
    // Los mismos parametros pero con su marca (`&`, `mut`): hace falta para
    // saber si una llamada se queda con el valor o solo lo mira.
    params_marcados: mapa<str, lista<str>>,
    // `Enum.Variante` -> lo que lleva esa forma, en orden. Un enum no tiene
    // campos: tiene formas, y solo una a la vez.
    formas: mapa<str, lista<str>>,
    // Enum -> los nombres de sus formas, para saber si un tipo es un enum.
    variantes: mapa<str, lista<str>>,
    // Nombres que traen dos modulos a la vez. El cargador de verdad los
    // renombra, y esta capa no sabe a cual: mejor no emitir la llamada.
    repetidas: mapa<str, usize>,
    // Los propios que chocaban con un modulo, y como quedan en C.
    renombradas: mapa<str, str>,
    // Las que escribio C. Una funcion de C presta lo que recibe y no se
    // queda con nada, asi que sus argumentos no se mueven.
    externas: mapa<str, usize>,
    // Struct generico -> sus parametros de tipo: `Par` -> [A, B]. Un
    // `Par<str, usize>` se queda escrito asi, y sus campos se sacan de aqui.
    struct_params: mapa<str, lista<str>>,
    // Lo que el comprobador dejo anotado: `dueno#id` -> el tipo de esa
    // expresion, con los numeros escritos ya decididos por su contexto.
    // `dueno` es la funcion que se esta escribiendo, con el nombre que le da
    // el comprobador; vacio, no se mira nada y el tipo se deduce aqui.
    anotados: mapa<str, str>,
    dueno: str,
}

fn contexto() -> Contexto {
    return Contexto { ambitos: [], campos: [], nombres: [], retornos: [],
        tipo_params: [], params: [], params_marcados: [], formas: [],
        variantes: [], externas: [], repetidas: [],
        renombradas: [], struct_params: [], anotados: [], dueno: vacio() };
}

fn abrir(c: mut Contexto) {
    let nuevo_ambito: mapa<str, str> = [];
    anadir(c.ambitos, nuevo_ambito);
}

fn cerrar(c: mut Contexto) {
    if largo(c.ambitos) > 0 {
        redimensionar_ambitos(c, largo(c.ambitos) - 1);
    }
}

// Quitar el ultimo ambito: se copian los de delante y se deja fuera el final.
fn redimensionar_ambitos(c: mut Contexto, cuantos: usize) {
    var quedan: lista<mapa<str, str>> = [];
    var i = 0;
    while i < cuantos {
        var copia: mapa<str, str> = [];
        for k en claves(c.ambitos[i]) {
            let v = obtener(c.ambitos[i], vista(k)) sino "";
            poner(copia, vista(k), nuevo(v));
        }
        anadir(quedan, copia);
        i = i + 1;
    }
    c.ambitos = quedan;
}

fn declarar(c: mut Contexto, nombre: view, tipo: view) {
    if largo(c.ambitos) == 0 { abrir(c); }
    let ultimo = largo(c.ambitos) - 1;
    poner(c.ambitos[ultimo], nombre, nuevo(tipo));
}

// El tipo de un nombre, o "" si no se conoce. Del ambito mas de dentro
// hacia fuera, que es lo que hace que una variable tape a otra.
fn buscar(c: &Contexto, nombre: view) -> str {
    var i = largo(c.ambitos);
    while i > 0 {
        i = i - 1;
        if tiene(c.ambitos[i], nombre) {
            return nuevo(obtener(c.ambitos[i], nombre) sino "");
        }
    }
    return vacio();
}

// ------------------------------------------------------------------
// El tipo de una expresion
// ------------------------------------------------------------------

fn tipo_de(c: &Contexto, n: &P.Nodo) -> str {
    let anotado = tipo_anotado(c, n);
    if largo(anotado) > 0 { return anotado; }
    let clase = vista(n.clase);

    if igual(clase, "entero") { return nuevo("usize"); }
    if igual(clase, "decimal") { return nuevo("f64"); }
    if igual(clase, "cadena") { return nuevo("view"); }
    if igual(clase, "interpolada") { return nuevo("str"); }
    if igual(clase, "booleano") { return nuevo("bool"); }

    if igual(clase, "variable") {
        let local = buscar(c, vista(n.texto));
        if largo(local) > 0 { return local; }
        // El nombre de una funcion sin parentesis detras es un valor: el
        // puntero a esa funcion, con su firma por tipo.
        return firma_de_funcion(c, vista(n.texto));
    }

    // Una clausura ya numerada lleva el nombre de su struct.
    if igual(clase, "cierre") { return copiar(n.texto); }

    // `if c { a } else { b }` vale lo que valga su primera rama: el
    // comprobador ya exige que las dos den lo mismo.
    if igual(clase, "si_expr") {
        if largo(n.hijos) == 3 { return tipo_de(c, n.hijos[1]); }
        return vacio();
    }

    // `Color.Rojo` es un `Color`.
    if igual(clase, "enum_lit") { return antes_del_punto(vista(n.texto)); }

    // Un `match` vale lo que valgan sus brazos. Basta con mirar el primero
    // que de algo: el comprobador ya exige que todos den lo mismo.
    if igual(clase, "match") {
        for h en n.hijos {
            if igual(vista(h.clase), "brazo") {
                for x en h.hijos {
                    if igual(vista(x.clase), "retorno") {
                        if largo(x.hijos) > 0 { return tipo_de(c, x.hijos[0]); }
                    }
                }
            }
        }
        return vacio();
    }

    if igual(clase, "expresion") {
        if largo(n.hijos) > 0 { return tipo_de(c, n.hijos[0]); }
        return vacio();
    }

    if igual(clase, "conversion") {
        // El texto lleva el tipo destino, con `?` delante si es envolvente.
        let t = vista(n.texto);
        if empieza_con(t, "?") { return nuevo(rebanar(t, 1, largo(t))); }
        return nuevo(t);
    }

    if igual(clase, "unaria") {
        if igual(vista(n.texto), "!") { return nuevo("bool"); }
        // Un numero escrito con `-` delante solo cabe en uno con signo: sin
        // mas contexto es un `i64`, como en el comprobador.
        if igual(vista(n.texto), "-") && largo(n.hijos) > 0
        && igual(literal_de(n.hijos[0]), "entero") {
            return nuevo("i64");
        }
        if largo(n.hijos) > 0 { return tipo_de(c, n.hijos[0]); }
        return vacio();
    }

    if igual(clase, "binaria") {
        let op = vista(n.texto);
        if es_comparacion(op) { return nuevo("bool"); }
        if largo(n.hijos) == 0 { return vacio(); }
        if largo(n.hijos) == 1 { return tipo_de(c, n.hijos[0]); }
        return tipo_cuenta(c, n, "");
    }

    if igual(clase, "try") || igual(clase, "sino") {
        if largo(n.hijos) > 0 { return tipo_de(c, n.hijos[0]); }
        return vacio();
    }

    if igual(clase, "si_expr") {
        // La condicion es el primer hijo; el valor, el segundo.
        if largo(n.hijos) > 1 { return tipo_de(c, n.hijos[1]); }
        return vacio();
    }

    if igual(clase, "literal_struct") {
        // `P.Estado { ... }` es un `Estado`: el modulo es de quien escribe.
        return sin_modulo(vista(n.texto));
    }

    if igual(clase, "literal_lista") {
        // `[a, b, c]` sin tipo escrito es un arreglo de tamaño fijo. Un `[]`
        // vacio no dice de que es: eso lo pone la anotacion.
        if largo(n.hijos) == 0 { return vacio(); }
        let elem = tipo_de(c, n.hijos[0]);
        if largo(elem) == 0 { return vacio(); }
        var t = nuevo("[");
        empujar(t, vista(elem));
        empujar(t, "; ");
        empujar(t, texto(largo(n.hijos)));
        empujar(t, "]");
        return t;
    }

    if igual(clase, "campo") {
        if largo(n.hijos) == 0 { return vacio(); }
        let crudo = tipo_de(c, n.hijos[0]);
        let base = T.apuntado_si(vista(crudo));
        return tipo_de_campo(c, vista(base), vista(n.texto));
    }

    if igual(clase, "indice") {
        if largo(n.hijos) == 0 { return vacio(); }
        let crudo = tipo_de(c, n.hijos[0]);
        let base = T.apuntado_si(vista(crudo));
        return T.elemento(vista(base));
    }

    if igual(clase, "llamada") { return tipo_de_llamada(c, n); }

    return vacio();
}

// `obtener` sobre un mapa de listas devuelve un prestamo, y un prestamo no
// se puede sustituir si falla. Se pregunta antes con `tiene` y aqui se
// entrega una copia, que es lo que el que llama necesita.
fn mirar_tipos(c: &Contexto, struct_: view) -> lista<str> ! {
    return copiar(try obtener(c.campos, struct_));
}

fn mirar_nombres(c: &Contexto, struct_: view) -> lista<str> ! {
    return copiar(try obtener(c.nombres, struct_));
}

// Si un tipo tiene duenio. Es la pregunta de `tipos.t`, con los campos que
// este contexto conoce.
fn posee_simple(c: &Contexto, t: view) -> bool {
    var visitados: mapa<str, usize> = [];
    return T.posee(c.campos, t, visitados) sino false;
}

// `"entero"` o `"decimal"` si el comprobador ve aqui un numero escrito que
// todavia no tiene tipo —`1`, `2.5`, `1 + 2`, `-0.5`, `if c { 1 } else { 2 }`—,
// y `""` si no. Un numero asi toma el tipo del otro lado de la operacion, o
// el que se espera de el; sin nada que lo decida, `usize` o `f64`.
fn literal_de(n: &P.Nodo) -> view {
    let clase = vista(n.clase);
    if igual(clase, "entero") { return "entero"; }
    if igual(clase, "decimal") { return "decimal"; }
    // `-1` ya es un `i64`; `-0.5` sigue sin decidir su ancho.
    if igual(clase, "unaria") && igual(vista(n.texto), "-")
    && largo(n.hijos) == 1 {
        if igual(literal_de(n.hijos[0]), "decimal") { return "decimal"; }
        return "";
    }
    if igual(clase, "binaria") && !es_comparacion(vista(n.texto))
    && largo(n.hijos) == 2 {
        let izq = literal_de(n.hijos[0]);
        let der = literal_de(n.hijos[1]);
        if largo(izq) > 0 && largo(der) > 0 {
            if igual(izq, "decimal") || igual(der, "decimal") {
                return "decimal";
            }
            return "entero";
        }
    }
    if igual(clase, "si_expr") && largo(n.hijos) == 3 {
        let a = literal_de(n.hijos[1]);
        let b = literal_de(n.hijos[2]);
        if largo(a) > 0 && largo(b) > 0 {
            if igual(a, "decimal") || igual(b, "decimal") { return "decimal"; }
            return "entero";
        }
    }
    return "";
}

// Lo que el comprobador dejo anotado de esta expresion, si es un numero o un
// `bool`: son los tipos que deciden en que se hace una cuenta y como se
// escribe un numero, y los que esta capa deducia mal por su cuenta. `""` si
// no dejo nada.
fn tipo_anotado(c: &Contexto, n: &P.Nodo) -> str {
    let t = anotado_crudo(c, n);
    if igual(vista(t), "{entero}") { return nuevo("usize"); }
    if igual(vista(t), "{decimal}") { return nuevo("f64"); }
    if es_numero(vista(t)) || igual(vista(t), "bool") { return t; }
    return vacio();
}

fn anotado_crudo(c: &Contexto, n: &P.Nodo) -> str {
    if n.id == 0 || largo(c.dueno) == 0 { return vacio(); }
    let clave = $"{c.dueno}#{n.id}";
    return nuevo(obtener(c.anotados, vista(clave)) sino "");
}

fn es_numero(t: view) -> bool {
    if igual(t, "usize") || igual(t, "u8") || igual(t, "u16") { return true; }
    if igual(t, "u32") || igual(t, "u64") || igual(t, "i8") { return true; }
    if igual(t, "i16") || igual(t, "i32") || igual(t, "i64") { return true; }
    return igual(t, "f32") || igual(t, "f64");
}

// El tipo en que se hace la cuenta de una binaria: el mismo que decide el
// comprobador. `1 + x` se hace en el tipo de `x`, y `1 + 2` en el que se
// espera de ella.
fn tipo_cuenta(c: &Contexto, n: &P.Nodo, esperado: view) -> str {
    // Lo que anoto el comprobador: tras mirar la operacion, los dos lados
    // tienen el mismo tipo, y un numero escrito ya tiene el del otro. En un
    // desplazamiento manda el de la izquierda.
    let desplaza = igual(vista(n.texto), "<<") || igual(vista(n.texto), ">>");
    let a_izq = anotado_crudo(c, n.hijos[0]);
    if es_numero(vista(a_izq)) { return a_izq; }
    if !desplaza {
        let a_der = anotado_crudo(c, n.hijos[1]);
        if es_numero(vista(a_der)) { return a_der; }
    }
    let izq = literal_de(n.hijos[0]);
    let der = literal_de(n.hijos[1]);
    if largo(izq) > 0 && largo(der) > 0 {
        if es_numero(esperado) { return nuevo(esperado); }
        if igual(izq, "decimal") || igual(der, "decimal") { return nuevo("f64"); }
        return nuevo("usize");
    }
    if largo(izq) > 0 {
        let t = tipo_de(c, n.hijos[1]);
        if es_numero(vista(t)) { return t; }
    }
    let a = tipo_de(c, n.hijos[0]);
    if es_numero(vista(a)) { return a; }
    let otro = tipo_de(c, n.hijos[1]);
    if es_numero(vista(otro)) { return otro; }
    if es_numero(esperado) { return nuevo(esperado); }
    return nuevo("usize");
}

fn es_comparacion(op: view) -> bool {
    if igual(op, "==") || igual(op, "!=") { return true; }
    if igual(op, "<") || igual(op, "<=") { return true; }
    if igual(op, ">") || igual(op, ">=") { return true; }
    return igual(op, "&&") || igual(op, "||");
}

// `Par<str, usize>`: un struct generico aplicado a sus tipos. `lista<...>`,
// `mapa<...>`, `bloque<...>` y `fn(...)` no, que esos los pone el lenguaje.
fn es_aplicacion(t: view) -> bool {
    if largo(t) == 0 || !termina_con(t, ">") { return false; }
    var i = 0;
    while i < largo(t) && byte(t, i) != 60 {
        if !es_de_nombre(byte(t, i)) && byte(t, i) != 46 { return false; }
        i = i + 1;
    }
    if i == 0 || i == largo(t) { return false; }
    let base = rebanar(t, 0, i);
    if igual(base, "lista") || igual(base, "mapa") || igual(base, "bloque") {
        return false;
    }
    let primero = byte(t, 0);
    return (primero >= 65 && primero <= 90) || (primero >= 97 && primero <= 122);
}

// El struct generico de una aplicacion, sin alias: `t.Par<A, B>` -> `Par`.
fn base_de_aplicacion(t: view) -> str {
    var i = 0;
    while i < largo(t) && byte(t, i) != 60 { i = i + 1; }
    return sin_alias_tipo(rebanar(t, 0, i));
}

// Los tipos de los campos de una aplicacion, con sus parametros puestos.
fn tipos_de_aplicacion(c: &Contexto, t: view) -> lista<str> {
    var salida: lista<str> = [];
    let base = base_de_aplicacion(t);
    if !tiene(c.struct_params, vista(base)) { return salida; }
    let sueltos = lista_de(c.struct_params, vista(base)) sino [];
    let dados = T.partir_tipos(T.entre_angulos(t));
    if largo(dados) != largo(sueltos) { return salida; }
    var ligaduras: mapa<str, str> = [];
    var i = 0;
    while i < largo(sueltos) {
        poner(ligaduras, vista(sueltos[i]), copiar(dados[i]));
        i = i + 1;
    }
    let crudos = mirar_tipos(c, vista(base)) sino [];
    for x en crudos { anadir(salida, sustituir(vista(x), ligaduras)); }
    return salida;
}

fn tipo_de_campo(c: &Contexto, struct_: view, campo: view) -> str {
    if es_aplicacion(struct_) {
        let base = base_de_aplicacion(struct_);
        let tipos_a = tipos_de_aplicacion(c, struct_);
        let nombres_a = mirar_nombres(c, vista(base)) sino [];
        var k = 0;
        while k < largo(nombres_a) && k < largo(tipos_a) {
            if igual(vista(nombres_a[k]), campo) { return copiar(tipos_a[k]); }
            k = k + 1;
        }
        return vacio();
    }
    // `P.Nodo` es `Nodo`: el alias es de quien escribe, no del tipo.
    if !tiene(c.campos, struct_) {
        let corto = sin_modulo(struct_);
        if tiene(c.campos, vista(corto)) {
            return tipo_de_campo(c, vista(corto), campo);
        }
    }
    if !tiene(c.campos, struct_) { return vacio(); }
    if !tiene(c.nombres, struct_) { return vacio(); }
    let tipos = mirar_tipos(c, struct_) sino [];
    let nombres = mirar_nombres(c, struct_) sino [];
    var i = 0;
    while i < largo(nombres) && i < largo(tipos) {
        if igual(vista(nombres[i]), campo) { return copiar(tipos[i]); }
        i = i + 1;
    }
    return vacio();
}

// Las internas cuyo tipo no depende de sus argumentos.
fn tipo_fijo(nombre: view) -> str {
    if igual(nombre, "vacio") || igual(nombre, "nuevo") { return nuevo("str"); }
    if igual(nombre, "texto") { return nuevo("str"); }
    if igual(nombre, "vista") || igual(nombre, "rebanar") { return nuevo("view"); }
    if igual(nombre, "argumento") { return nuevo("view"); }
    if igual(nombre, "leer_archivo") { return nuevo("str"); }
    // Las que hablan con el sistema. Las tres que devuelven memoria dan un
    // `str` de Tcode, no un prestamo: por eso son internas y no `externo`.
    if igual(nombre, "leer_linea") { return nuevo("str"); }
    if igual(nombre, "entrada_completa") { return nuevo("str"); }
    if igual(nombre, "variable_entorno") { return nuevo("str"); }
    if igual(nombre, "ahora_ms") || igual(nombre, "monotono_ms") {
        return nuevo("i64");
    }
    if igual(nombre, "azar") { return nuevo("usize"); }
    if igual(nombre, "largo") || igual(nombre, "byte") { return nuevo("usize"); }
    if igual(nombre, "n_argumentos") { return nuevo("usize"); }
    if igual(nombre, "igual") || igual(nombre, "menor") { return nuevo("bool"); }
    if igual(nombre, "tiene") || igual(nombre, "quitar") { return nuevo("bool"); }
    if igual(nombre, "raiz") || igual(nombre, "piso") { return nuevo("f64"); }
    if igual(nombre, "techo") || igual(nombre, "redondear") { return nuevo("f64"); }
    return vacio();
}

// `T.apuntado_si` se declara como `apuntado_si`: el nombre del modulo es de
// quien llama, no de la funcion.
// Lo que atrapa un patron de `match` se presta, nunca se posee: un `str`
// se ve como `view`, y lo demas con duenio como `&T`. Es lo que hace que no
// hagan falta ni `ref` ni `&` en los patrones.
fn tipo_atrapado(c: &Contexto, t: view) -> str {
    if igual(t, "str") { return nuevo("view"); }
    if !posee_con_formas(c, t) { return nuevo(t); }
    var r = nuevo("&");
    empujar(r, t);
    return r;
}

// Como `posee_simple`, pero sabiendo ademas de enums: uno posee si alguna
// de sus formas posee.
fn posee_con_formas(c: &Contexto, t: view) -> bool {
    // Un struct generico aplicado posee si posee alguno de sus campos, con
    // los tipos ya puestos.
    if es_aplicacion(t) {
        let tipos_a = tipos_de_aplicacion(c, t);
        for x en tipos_a {
            if posee_con_formas(c, vista(x)) { return true; }
        }
        return false;
    }
    // `Q.Vigilada` es `Vigilada`: el alias es de quien escribe, y los tipos
    // se apuntan por su nombre.
    if !tiene(c.variantes, t) && !tiene(c.campos, t) {
        let corto = sin_modulo(t);
        if tiene(c.variantes, vista(corto)) || tiene(c.campos, vista(corto)) {
            return posee_con_formas(c, vista(corto));
        }
    }
    if tiene(c.variantes, t) {
        let cuales = lista_de(c.variantes, t) sino [];
        for v en cuales {
            var clave = nuevo(t);
            empujar(clave, ".");
            empujar(clave, vista(v));
            let lleva = lista_de(c.formas, vista(clave)) sino [];
            for x en lleva {
                if posee_con_formas(c, vista(x)) { return true; }
            }
        }
        return false;
    }
    return posee_simple(c, t);
}

// `Color.Rojo` -> `Color`.
fn antes_del_punto(t: view) -> str {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 46 { return nuevo(rebanar(t, 0, i)); }
        i = i + 1;
    }
    return nuevo(t);
}

fn tras_el_punto(t: view) -> str {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 46 {
            return nuevo(rebanar(t, i + 1, largo(t)));
        }
        i = i + 1;
    }
    return vacio();
}

// El tipo con cada struct generico aplicado cambiado por el nombre de su
// copia, a cualquier hondura: `lista<Par<str, usize>>` ->
// `lista<Par__str_usize>`. Es lo que hace el comprobador de Python antes de
// generar; aqui el tipo escrito se queda como estaba y esto se usa al
// escribirlo.
fn nombre_resuelto(t: view) -> str {
    if empieza_con(t, "&mut ") {
        let d = nombre_resuelto(rebanar(t, 5, largo(t)));
        return $"&mut {d}";
    }
    if empieza_con(t, "&") {
        let d = nombre_resuelto(rebanar(t, 1, largo(t)));
        return $"&{d}";
    }
    if T.es_lista(t) {
        let e = T.elemento(t);
        let d = nombre_resuelto(vista(e));
        return $"lista<{d}>";
    }
    if T.es_bloque(t) {
        let e = T.elemento(t);
        let d = nombre_resuelto(vista(e));
        return $"bloque<{d}>";
    }
    if T.es_mapa(t) {
        let partes = T.partir_tipos(T.entre_angulos(t));
        if largo(partes) != 2 { return nuevo(t); }
        let k = nombre_resuelto(vista(partes[0]));
        let v = nombre_resuelto(vista(partes[1]));
        return $"mapa<{k}, {v}>";
    }
    if T.es_arreglo(t) {
        let e = T.elemento(t);
        let d = nombre_resuelto(vista(e));
        let n = cuantos_en_arreglo(t);
        return $"[{d}; {n}]";
    }
    if !es_aplicacion(t) { return nuevo(t); }
    var r = base_de_aplicacion(t);
    empujar(r, "__");
    let args = T.partir_tipos(T.entre_angulos(t));
    var i = 0;
    while i < largo(args) {
        if i > 0 { empujar(r, "_"); }
        let d = nombre_resuelto(vista(args[i]));
        let limpio = sanear_nombre(vista(d));
        empujar(r, vista(limpio));
        i = i + 1;
    }
    return r;
}

// `[T; N]` -> `N`.
fn cuantos_en_arreglo(t: view) -> str {
    var i = largo(t);
    while i > 0 && byte(t, i - 1) != 32 { i = i - 1; }
    if largo(t) == 0 { return vacio(); }
    return nuevo(rebanar(t, i, largo(t) - 1));
}

// Un nombre de C con lo que no sea letra o cifra cambiado por `_`, sin
// repetirlo ni dejarlo en los bordes: lo que hace el comprobador con cada
// tipo que va en el nombre de una copia.
fn sanear_nombre(t: view) -> str {
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

fn sin_modulo(nombre: view) -> str {
    var i = 0;
    while i < largo(nombre) {
        if byte(nombre, i) == 46 {
            return nuevo(rebanar(nombre, i + 1, largo(nombre)));
        }
        i = i + 1;
    }
    return nuevo(nombre);
}

fn tipo_de_llamada(c: &Contexto, n: &P.Nodo) -> str {
    let corto = sin_modulo(vista(n.texto));
    let nombre = vista(corto);

    let fijo = tipo_fijo(nombre);
    if largo(fijo) > 0 { return fijo; }

    // Las que devuelven algo sacado de su primer argumento.
    if largo(n.hijos) > 0 {
        let crudo = tipo_de(c, n.hijos[0]);
        let primero = T.apuntado_si(vista(crudo));
        if igual(nombre, "copiar") { return copiar(primero); }
        if igual(nombre, "intercambiar") { return copiar(primero); }
        if igual(nombre, "absoluto") { return copiar(primero); }
        if igual(nombre, "claves") {
            let partes = T.partir_tipos(T.entre_angulos(vista(primero)));
            if largo(partes) == 2 {
                var t = nuevo("lista<");
                empujar(t, vista(partes[0]));
                empujar(t, ">");
                return t;
            }
            return vacio();
        }
        if igual(nombre, "obtener") || igual(nombre, "obtener_mut") {
            let partes = T.partir_tipos(T.entre_angulos(vista(primero)));
            if largo(partes) != 2 { return vacio(); }
            let valor = copiar(partes[1]);
            // Un valor con duenio no sale del mapa: sale prestado. Y un
            // `str` prestado es una vista, que es lo mismo con otro nombre.
            if igual(nombre, "obtener_mut") {
                var t = nuevo("&mut ");
                empujar(t, vista(valor));
                return t;
            }
            if igual(vista(valor), "str") { return nuevo("view"); }
            if posee_simple(c, vista(valor)) {
                var t = nuevo("&");
                empujar(t, vista(valor));
                return t;
            }
            return valor;
        }
    }

    // Una variable que guarda una clausura o una funcion se llama igual que
    // una funcion: la clausura es su struct mas `ss_cierre_N`.
    let local = buscar(c, nombre);
    if largo(local) > 0 {
        let t = T.apuntado_si(vista(local));
        let de_cierre = funcion_de_cierre(vista(t));
        if largo(de_cierre) > 0 {
            return nuevo(obtener(c.retornos, vista(de_cierre)) sino "");
        }
        if T.es_funcion(vista(t)) {
            let partes = T.partes_de_funcion(vista(t));
            if largo(partes) == 0 { return vacio(); }
            return copiar(partes[largo(partes) - 1]);
        }
        return vacio();
    }

    // Una funcion del programa.
    if !tiene(c.retornos, nombre) { return vacio(); }
    let retorno = nuevo(obtener(c.retornos, nombre) sino "");
    if !tiene(c.tipo_params, nombre) { return retorno; }

    // Generica: se eligen los tipos mirando los argumentos, igual que hace
    // el comprobador, y se ponen en el tipo de retorno.
    let sueltos = lista_de(c.tipo_params, nombre) sino [];
    if largo(sueltos) == 0 { return retorno; }
    let declarados = lista_de(c.params, nombre) sino [];
    var ligaduras: mapa<str, str> = [];
    var i = 0;
    while i < largo(declarados) && i < largo(n.hijos) {
        let dado = tipo_de(c, n.hijos[i]);
        let limpio = T.apuntado_si(vista(dado));
        unificar(vista(declarados[i]), vista(limpio), sueltos, ligaduras);
        i = i + 1;
    }
    return sustituir(vista(retorno), ligaduras);
}

// `Cierre_3` -> `ss_cierre_3`, la funcion que recibe ese entorno. Vacio si
// el tipo no es el de una clausura.
fn funcion_de_cierre(t: view) -> str {
    if !empieza_con(t, "Cierre_") { return vacio(); }
    let n = rebanar(t, 7, largo(t));
    if largo(n) == 0 { return vacio(); }
    var i = 0;
    while i < largo(n) {
        if byte(n, i) < 48 || byte(n, i) > 57 { return vacio(); }
        i = i + 1;
    }
    return $"ss_cierre_{n}";
}

// El tipo de una funcion usada como valor, escrito como en el comprobador:
// `fn(&str) -> bool`. Vacio si no es una funcion normal del programa: una
// generica no tiene una sola firma, y una de C no se pasa como valor.
fn firma_de_funcion(c: &Contexto, nombre: view) -> str {
    if !tiene(c.retornos, nombre) { return vacio(); }
    if tiene(c.tipo_params, nombre) || tiene(c.externas, nombre) { return vacio(); }
    let tipos = lista_de(c.params, nombre) sino [];
    let marcas = lista_de(c.params_marcados, nombre) sino [];
    var t = nuevo("fn(");
    var i = 0;
    while i < largo(tipos) {
        if i > 0 { empujar(t, ", "); }
        if i < largo(marcas) {
            if igual(vista(marcas[i]), "&") { empujar(t, "&"); }
            if igual(vista(marcas[i]), "mut ") || igual(vista(marcas[i]), "&mut ") {
                empujar(t, "&mut ");
            }
        }
        empujar(t, vista(tipos[i]));
        i = i + 1;
    }
    empujar(t, ")");
    let retorno = obtener(c.retornos, nombre) sino "";
    if largo(retorno) > 0 && !igual(retorno, "()") {
        empujar(t, " -> ");
        empujar(t, retorno);
    }
    return t;
}

fn lista_de(m: &mapa<str, lista<str>>, clave: view) -> lista<str> ! {
    return copiar(try obtener(m, clave));
}

// `lista<T>` contra `lista<str>` liga `T` a `str`. Con la forma justa que
// hace falta: los tipos de Tcode son cadenas y se comparan por su borde.
fn unificar(patron: view, dado: view, sueltos: &lista<str>,
    ligaduras: mut mapa<str, str>) {
    if largo(dado) == 0 { return; }
    for s en sueltos {
        if igual(patron, vista(s)) {
            if !tiene(ligaduras, patron) { poner(ligaduras, patron, nuevo(dado)); }
            return;
        }
    }
    let p = T.apuntado_si(patron);
    let d = T.apuntado_si(dado);
    if largo(T.entre_angulos(vista(p))) == 0 { return; }
    if largo(T.entre_angulos(vista(d))) == 0 { return; }
    let pp = T.partir_tipos(T.entre_angulos(vista(p)));
    let dd = T.partir_tipos(T.entre_angulos(vista(d)));
    if largo(pp) != largo(dd) { return; }
    var i = 0;
    while i < largo(pp) {
        unificar(vista(pp[i]), vista(dd[i]), sueltos, ligaduras);
        i = i + 1;
    }
}

// Cambia cada parametro de tipo por lo que se le ligo, respetando los bordes
// del identificador: `lista<T>` con `T = str` da `lista<str>`.
fn sustituir(t: view, ligaduras: &mapa<str, str>) -> str {
    var salida = vacio();
    var desde = 0;
    var i = 0;
    while i <= largo(t) {
        var corta = true;
        if i < largo(t) { corta = !es_de_nombre(byte(t, i)); }
        if corta {
            if i > desde {
                let pieza = rebanar(t, desde, i);
                if tiene(ligaduras, pieza) {
                    empujar(salida, obtener(ligaduras, pieza) sino "");
                } else {
                    empujar(salida, pieza);
                }
            }
            if i < largo(t) { empujar(salida, rebanar(t, i, i + 1)); }
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

// `lista<P.Nodo>` -> `lista<Nodo>`. El alias de un modulo es de quien lo
// escribe: visto desde otro archivo no significa nada, y el cargador de
// verdad reescribe el arbol entero sin ellos.
fn sin_alias_tipo(t: view) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(t) {
        if es_de_nombre(byte(t, i)) {
            var j = i;
            while j < largo(t) && es_de_nombre(byte(t, j)) { j = j + 1; }
            if j < largo(t) && byte(t, j) == 46 {
                i = j + 1; // `P.` fuera
                continue;
            }
            empujar(r, rebanar(t, i, j));
            i = j;
            continue;
        }
        empujar(r, rebanar(t, i, i + 1));
        i = i + 1;
    }
    return r;
}

fn es_de_nombre(b: usize) -> bool {
    if b >= 97 && b <= 122 { return true; }
    if b >= 65 && b <= 90 { return true; }
    if b >= 48 && b <= 57 { return true; }
    return b == 95;
}
