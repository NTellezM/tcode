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
    c.ambitos.anadir(nuevo_ambito);
}

fn cerrar(c: mut Contexto) {
    if c.ambitos.largo() > 0 {
        redimensionar_ambitos(c, c.ambitos.largo() - 1);
    }
}

// Quitar el ultimo ambito: se copian los de delante y se deja fuera el final.
fn redimensionar_ambitos(c: mut Contexto, cuantos: usize) {
    var quedan: lista<mapa<str, str>> = [];
    var i = 0;
    while i < cuantos {
        var copia: mapa<str, str> = [];
        for k en claves(c.ambitos[i]) {
            let v = obtener(c.ambitos[i], k) sino "";
            poner(copia, vista(k), nuevo(v));
        }
        quedan.anadir(copia);
        i = i + 1;
    }
    c.ambitos = quedan;
}

fn declarar(c: mut Contexto, nombre: view, tipo: view) {
    if c.ambitos.largo() == 0 { abrir(c); }
    let ultimo = c.ambitos.largo() - 1;
    poner(c.ambitos[ultimo], nombre, nuevo(tipo));
}

// El tipo de un nombre, o "" si no se conoce. Del ambito mas de dentro
// hacia fuera, que es lo que hace que una variable tape a otra.
fn buscar(c: &Contexto, nombre: view) -> str {
    var i = c.ambitos.largo();
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
    if anotado.largo() > 0 { return anotado; }
    let clase = vista(n.clase);

    if clase == "entero" { return nuevo("usize"); }
    if clase == "decimal" { return nuevo("f64"); }
    if clase == "cadena" { return nuevo("view"); }
    if clase == "interpolada" { return nuevo("str"); }
    if clase == "booleano" { return nuevo("bool"); }

    if clase == "variable" {
        let local = buscar(c, n.texto);
        if local.largo() > 0 { return local; }
        // El nombre de una funcion sin parentesis detras es un valor: el
        // puntero a esa funcion, con su firma por tipo.
        return firma_de_funcion(c, n.texto);
    }

    // Una clausura ya numerada lleva el nombre de su struct.
    if clase == "cierre" { return copiar(n.texto); }

    // `a..b` en un `for`: los dos extremos son del mismo entero.
    if clase == "rango" && n.hijos.largo() == 2 {
        let t = tipo_de(c, n.hijos[0]);
        return $"rango<{t}>";
    }

    // `if c { a } else { b }` vale lo que valga su primera rama: el
    // comprobador ya exige que las dos den lo mismo.
    if clase == "si_expr" {
        if n.hijos.largo() == 3 { return tipo_de(c, n.hijos[1]); }
        return vacio();
    }

    // `Color.Rojo` es un `Color`.
    if clase == "enum_lit" { return antes_del_punto(n.texto); }

    // Un `match` vale lo que valgan sus brazos, y eso lo dijo el comprobador.
    // Sin lo que dijo, basta con el primer brazo que de algo que se sepa
    // tipar: todos dan lo mismo. Uno que de lo atrapado no se sabe desde
    // aqui, porque lo atrapado solo se declara dentro del brazo.
    if clase == "match" {
        let dicho = anotado_crudo(c, n);
        if dicho.largo() > 0 && !empieza_con(dicho, "{") { return dicho; }
        for h en n.hijos {
            if h.clase == "brazo" {
                for x en h.hijos {
                    if x.clase == "retorno" && x.hijos.largo() > 0 {
                        let t = tipo_de(c, x.hijos[0]);
                        if t.largo() > 0 { return t; }
                    }
                }
            }
        }
        return vacio();
    }

    if clase == "expresion" {
        if n.hijos.largo() > 0 { return tipo_de(c, n.hijos[0]); }
        return vacio();
    }

    if clase == "conversion" {
        // El texto lleva el tipo destino, con `?` delante si es envolvente.
        let t = vista(n.texto);
        if empieza_con(t, "?") { return nuevo(rebanar(t, 1, t.largo())); }
        return nuevo(t);
    }

    if clase == "unaria" {
        if n.texto == "!" { return nuevo("bool"); }
        // Un numero escrito con `-` delante solo cabe en uno con signo: sin
        // mas contexto es un `i64`, como en el comprobador.
        if n.texto == "-" && n.hijos.largo() > 0
        && literal_de(n.hijos[0]) == "entero" {
            return nuevo("i64");
        }
        if n.hijos.largo() > 0 { return tipo_de(c, n.hijos[0]); }
        return vacio();
    }

    if clase == "binaria" {
        let op = vista(n.texto);
        if es_comparacion(op) { return nuevo("bool"); }
        if n.hijos.largo() == 0 { return vacio(); }
        if n.hijos.largo() == 1 { return tipo_de(c, n.hijos[0]); }
        return tipo_cuenta(c, n, "");
    }

    if clase == "try" || clase == "sino" {
        if n.hijos.largo() > 0 { return tipo_de(c, n.hijos[0]); }
        return vacio();
    }

    if clase == "si_expr" {
        // La condicion es el primer hijo; el valor, el segundo.
        if n.hijos.largo() > 1 { return tipo_de(c, n.hijos[1]); }
        return vacio();
    }

    if clase == "literal_struct" {
        // `P.Estado { ... }` es un `Estado`: el modulo es de quien escribe.
        let escrito = sin_modulo(n.texto);
        // `Par { a: -3, b: 1 }` es la copia que dedujo el comprobador.
        if !contiene(escrito, "<") {
            let dicho = anotado_crudo(c, n);
            if es_aplicacion(dicho) {
                let base = base_de_aplicacion(dicho);
                if igual(base, escrito) { return dicho; }
            }
        }
        return escrito;
    }

    if clase == "literal_lista" {
        // `[a, b, c]` sin tipo escrito es un arreglo de tamaño fijo. Un `[]`
        // vacio no dice de que es: eso lo pone la anotacion.
        if n.hijos.largo() == 0 { return vacio(); }
        let elem = tipo_de(c, n.hijos[0]);
        if elem.largo() == 0 { return vacio(); }
        var t = nuevo("[");
        t.empujar(elem);
        t.empujar("; ");
        t.empujar(texto(n.hijos.largo()));
        t.empujar("]");
        return t;
    }

    if clase == "campo" {
        if n.hijos.largo() == 0 { return vacio(); }
        let crudo = tipo_de(c, n.hijos[0]);
        let base = T.apuntado_si(crudo);
        return tipo_de_campo(c, base, n.texto);
    }

    if clase == "indice" {
        if n.hijos.largo() == 0 { return vacio(); }
        let crudo = tipo_de(c, n.hijos[0]);
        let base = T.apuntado_si(crudo);
        return T.elemento(base);
    }

    if clase == "llamada" { return tipo_de_llamada(c, n); }

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
    if clase == "entero" { return "entero"; }
    if clase == "decimal" { return "decimal"; }
    // `-1` ya es un `i64`; `-0.5` sigue sin decidir su ancho.
    if clase == "unaria" && n.texto == "-"
    && n.hijos.largo() == 1 {
        if literal_de(n.hijos[0]) == "decimal" { return "decimal"; }
        return "";
    }
    if clase == "binaria" && !es_comparacion(n.texto)
    && n.hijos.largo() == 2 {
        let izq = literal_de(n.hijos[0]);
        let der = literal_de(n.hijos[1]);
        if izq.largo() > 0 && der.largo() > 0 {
            if izq == "decimal" || der == "decimal" {
                return "decimal";
            }
            return "entero";
        }
    }
    if clase == "si_expr" && n.hijos.largo() == 3 {
        let a = literal_de(n.hijos[1]);
        let b = literal_de(n.hijos[2]);
        if a.largo() > 0 && b.largo() > 0 {
            if a == "decimal" || b == "decimal" { return "decimal"; }
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
    if t == "{entero}" { return nuevo("usize"); }
    if t == "{decimal}" { return nuevo("f64"); }
    if es_numero(t) || t == "bool" { return t; }
    return vacio();
}

fn anotado_crudo(c: &Contexto, n: &P.Nodo) -> str {
    if n.id == 0 || c.dueno.largo() == 0 { return vacio(); }
    let clave = $"{c.dueno}#{n.id}";
    return nuevo(obtener(c.anotados, clave) sino "");
}

fn es_numero(t: view) -> bool {
    if t == "usize" || t == "u8" || t == "u16" { return true; }
    if t == "u32" || t == "u64" || t == "i8" { return true; }
    if t == "i16" || t == "i32" || t == "i64" { return true; }
    return t == "f32" || t == "f64";
}

// El tipo en que se hace la cuenta de una binaria: el mismo que decide el
// comprobador. `1 + x` se hace en el tipo de `x`, y `1 + 2` en el que se
// espera de ella.
fn tipo_cuenta(c: &Contexto, n: &P.Nodo, esperado: view) -> str {
    // Lo que anoto el comprobador: tras mirar la operacion, los dos lados
    // tienen el mismo tipo, y un numero escrito ya tiene el del otro. En un
    // desplazamiento manda el de la izquierda.
    let desplaza = n.texto == "<<" || n.texto == ">>";
    let a_izq = anotado_crudo(c, n.hijos[0]);
    if es_numero(a_izq) { return a_izq; }
    if !desplaza {
        let a_der = anotado_crudo(c, n.hijos[1]);
        if es_numero(a_der) { return a_der; }
    }
    let izq = literal_de(n.hijos[0]);
    let der = literal_de(n.hijos[1]);
    if izq.largo() > 0 && der.largo() > 0 {
        if es_numero(esperado) { return nuevo(esperado); }
        if izq == "decimal" || der == "decimal" { return nuevo("f64"); }
        return nuevo("usize");
    }
    if izq.largo() > 0 {
        let t = tipo_de(c, n.hijos[1]);
        if es_numero(t) { return t; }
    }
    let a = tipo_de(c, n.hijos[0]);
    if es_numero(a) { return a; }
    let otro = tipo_de(c, n.hijos[1]);
    if es_numero(otro) { return otro; }
    if es_numero(esperado) { return nuevo(esperado); }
    return nuevo("usize");
}

fn es_comparacion(op: view) -> bool {
    if op == "==" || op == "!=" { return true; }
    if op == "<" || op == "<=" { return true; }
    if op == ">" || op == ">=" { return true; }
    return op == "&&" || op == "||";
}

// `Par<str, usize>`: un struct generico aplicado a sus tipos. `lista<...>`,
// `mapa<...>`, `bloque<...>` y `fn(...)` no, que esos los pone el lenguaje.
fn es_aplicacion(t: view) -> bool {
    if t.largo() == 0 || !termina_con(t, ">") { return false; }
    var i = 0;
    while i < t.largo() && byte(t, i) != 60 {
        if !es_de_nombre(byte(t, i)) && byte(t, i) != 46 { return false; }
        i = i + 1;
    }
    if i == 0 || i == t.largo() { return false; }
    let base = rebanar(t, 0, i);
    if base == "lista" || base == "mapa" || base == "bloque" {
        return false;
    }
    let primero = byte(t, 0);
    return (primero >= 65 && primero <= 90) || (primero >= 97 && primero <= 122);
}

// El struct generico de una aplicacion, sin alias: `t.Par<A, B>` -> `Par`.
fn base_de_aplicacion(t: view) -> str {
    var i = 0;
    while i < t.largo() && byte(t, i) != 60 { i = i + 1; }
    return sin_alias_tipo(rebanar(t, 0, i));
}

// Los tipos de los campos de una aplicacion, con sus parametros puestos.
fn tipos_de_aplicacion(c: &Contexto, t: view) -> lista<str> {
    var salida: lista<str> = [];
    let base = base_de_aplicacion(t);
    if !tiene(c.struct_params, base) { return salida; }
    let sueltos = lista_de(c.struct_params, vista(base)) sino [];
    let dados = T.partir_tipos(T.entre_angulos(t));
    if dados.largo() != sueltos.largo() { return salida; }
    var ligaduras: mapa<str, str> = [];
    var i = 0;
    while i < sueltos.largo() {
        poner(ligaduras, vista(sueltos[i]), copiar(dados[i]));
        i = i + 1;
    }
    let crudos = mirar_tipos(c, base) sino [];
    for x en crudos { salida.anadir(sustituir(x, ligaduras)); }
    return salida;
}

fn tipo_de_campo(c: &Contexto, struct_: view, campo: view) -> str {
    if es_aplicacion(struct_) {
        let base = base_de_aplicacion(struct_);
        let tipos_a = tipos_de_aplicacion(c, struct_);
        let nombres_a = mirar_nombres(c, base) sino [];
        var k = 0;
        while k < nombres_a.largo() && k < tipos_a.largo() {
            if igual(nombres_a[k], campo) { return copiar(tipos_a[k]); }
            k = k + 1;
        }
        return vacio();
    }
    // `P.Nodo` es `Nodo`: el alias es de quien escribe, no del tipo.
    if !tiene(c.campos, struct_) {
        let corto = sin_modulo(struct_);
        if tiene(c.campos, corto) {
            return tipo_de_campo(c, corto, campo);
        }
    }
    if !tiene(c.campos, struct_) { return vacio(); }
    if !tiene(c.nombres, struct_) { return vacio(); }
    let tipos = mirar_tipos(c, struct_) sino [];
    let nombres = mirar_nombres(c, struct_) sino [];
    var i = 0;
    while i < nombres.largo() && i < tipos.largo() {
        if igual(nombres[i], campo) { return copiar(tipos[i]); }
        i = i + 1;
    }
    return vacio();
}

// Las internas cuyo tipo no depende de sus argumentos.
fn tipo_fijo(nombre: view) -> str {
    if nombre == "vacio" || nombre == "nuevo" { return nuevo("str"); }
    if nombre == "texto" { return nuevo("str"); }
    if nombre == "vista" || nombre == "rebanar" { return nuevo("view"); }
    if nombre == "argumento" { return nuevo("view"); }
    if nombre == "leer_archivo" { return nuevo("str"); }
    // Las que hablan con el sistema. Las tres que devuelven memoria dan un
    // `str` de Tcode, no un prestamo: por eso son internas y no `externo`.
    if nombre == "leer_linea" { return nuevo("str"); }
    if nombre == "entrada_completa" { return nuevo("str"); }
    if nombre == "variable_entorno" { return nuevo("str"); }
    if nombre == "ahora_ms" || nombre == "monotono_ms" {
        return nuevo("i64");
    }
    if nombre == "azar" { return nuevo("usize"); }
    if nombre == "largo" || nombre == "byte" { return nuevo("usize"); }
    if nombre == "n_argumentos" { return nuevo("usize"); }
    if nombre == "igual" || nombre == "menor" { return nuevo("bool"); }
    if nombre == "tiene" || nombre == "quitar" { return nuevo("bool"); }
    if nombre == "raiz" || nombre == "piso" { return nuevo("f64"); }
    if nombre == "techo" || nombre == "redondear" { return nuevo("f64"); }
    return vacio();
}

// `T.apuntado_si` se declara como `apuntado_si`: el nombre del modulo es de
// quien llama, no de la funcion.
// Lo que atrapa un patron de `match` se presta, nunca se posee: un `str`
// se ve como `view`, y lo demas con duenio como `&T`. Es lo que hace que no
// hagan falta ni `ref` ni `&` en los patrones.
fn tipo_atrapado(c: &Contexto, t: view) -> str {
    if t == "str" { return nuevo("view"); }
    if !posee_con_formas(c, t) { return nuevo(t); }
    var r = nuevo("&");
    r.empujar(t);
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
            if posee_con_formas(c, x) { return true; }
        }
        return false;
    }
    // `Q.Vigilada` es `Vigilada`: el alias es de quien escribe, y los tipos
    // se apuntan por su nombre.
    if !tiene(c.variantes, t) && !tiene(c.campos, t) {
        let corto = sin_modulo(t);
        if tiene(c.variantes, corto) || tiene(c.campos, corto) {
            return posee_con_formas(c, corto);
        }
    }
    if tiene(c.variantes, t) {
        let cuales = lista_de(c.variantes, t) sino [];
        for v en cuales {
            var clave = nuevo(t);
            clave.empujar(".");
            clave.empujar(v);
            let lleva = lista_de(c.formas, vista(clave)) sino [];
            for x en lleva {
                if posee_con_formas(c, x) { return true; }
            }
        }
        return false;
    }
    return posee_simple(c, t);
}

// `Color.Rojo` -> `Color`.
fn antes_del_punto(t: view) -> str {
    var i = 0;
    while i < t.largo() {
        if byte(t, i) == 46 { return nuevo(rebanar(t, 0, i)); }
        i = i + 1;
    }
    return nuevo(t);
}

fn tras_el_punto(t: view) -> str {
    var i = 0;
    while i < t.largo() {
        if byte(t, i) == 46 {
            return nuevo(rebanar(t, i + 1, t.largo()));
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
        let d = nombre_resuelto(rebanar(t, 5, t.largo()));
        return $"&mut {d}";
    }
    if empieza_con(t, "&") {
        let d = nombre_resuelto(rebanar(t, 1, t.largo()));
        return $"&{d}";
    }
    if T.es_lista(t) {
        let e = T.elemento(t);
        let d = nombre_resuelto(e);
        return $"lista<{d}>";
    }
    if T.es_bloque(t) {
        let e = T.elemento(t);
        let d = nombre_resuelto(e);
        return $"bloque<{d}>";
    }
    if T.es_mapa(t) {
        let partes = T.partir_tipos(T.entre_angulos(t));
        if partes.largo() != 2 { return nuevo(t); }
        let k = nombre_resuelto(partes[0]);
        let v = nombre_resuelto(partes[1]);
        return $"mapa<{k}, {v}>";
    }
    if T.es_arreglo(t) {
        let e = T.elemento(t);
        let d = nombre_resuelto(e);
        let n = cuantos_en_arreglo(t);
        return $"[{d}; {n}]";
    }
    if !es_aplicacion(t) { return nuevo(t); }
    var r = base_de_aplicacion(t);
    r.empujar("__");
    let args = T.partir_tipos(T.entre_angulos(t));
    var i = 0;
    while i < args.largo() {
        if i > 0 { r.empujar("_"); }
        let d = nombre_resuelto(args[i]);
        let limpio = sanear_nombre(d);
        r.empujar(limpio);
        i = i + 1;
    }
    return r;
}

// `[T; N]` -> `N`.
fn cuantos_en_arreglo(t: view) -> str {
    var i = t.largo();
    while i > 0 && byte(t, i - 1) != 32 { i = i - 1; }
    if t.largo() == 0 { return vacio(); }
    return nuevo(rebanar(t, i, t.largo() - 1));
}

// Un nombre de C con lo que no sea letra o cifra cambiado por `_`, sin
// repetirlo ni dejarlo en los bordes: lo que hace el comprobador con cada
// tipo que va en el nombre de una copia.
fn sanear_nombre(t: view) -> str {
    var r = vacio();
    var pendiente = false;
    var i = 0;
    while i < t.largo() {
        let c = byte(t, i);
        let bueno = (c >= 97 && c <= 122) || (c >= 65 && c <= 90)
        || (c >= 48 && c <= 57);
        if bueno {
            if pendiente && r.largo() > 0 { r.empujar("_"); }
            pendiente = false;
            r.empujar(rebanar(t, i, i + 1));
        } else {
            pendiente = true;
        }
        i = i + 1;
    }
    return r;
}

fn sin_modulo(nombre: view) -> str {
    var i = 0;
    while i < nombre.largo() {
        if byte(nombre, i) == 46 {
            return nuevo(rebanar(nombre, i + 1, nombre.largo()));
        }
        i = i + 1;
    }
    return nuevo(nombre);
}

fn tipo_de_llamada(c: &Contexto, n: &P.Nodo) -> str {
    let corto = sin_modulo(n.texto);
    let nombre = vista(corto);

    let fijo = tipo_fijo(nombre);
    if fijo.largo() > 0 { return fijo; }

    // Las que devuelven algo sacado de su primer argumento.
    if n.hijos.largo() > 0 {
        let crudo = tipo_de(c, n.hijos[0]);
        let primero = T.apuntado_si(crudo);
        if nombre == "copiar" { return copiar(primero); }
        if nombre == "intercambiar" { return copiar(primero); }
        if nombre == "absoluto" { return copiar(primero); }
        if nombre == "claves" {
            let partes = T.partir_tipos(T.entre_angulos(primero));
            if partes.largo() == 2 {
                var t = nuevo("lista<");
                t.empujar(partes[0]);
                t.empujar(">");
                return t;
            }
            return vacio();
        }
        if nombre == "obtener" || nombre == "obtener_mut" {
            let partes = T.partir_tipos(T.entre_angulos(primero));
            if partes.largo() != 2 { return vacio(); }
            let valor = copiar(partes[1]);
            // Un valor con duenio no sale del mapa: sale prestado. Y un
            // `str` prestado es una vista, que es lo mismo con otro nombre.
            if nombre == "obtener_mut" {
                var t = nuevo("&mut ");
                t.empujar(valor);
                return t;
            }
            if valor == "str" { return nuevo("view"); }
            if posee_simple(c, valor) {
                var t = nuevo("&");
                t.empujar(valor);
                return t;
            }
            return valor;
        }
    }

    // Una variable que guarda una clausura o una funcion se llama igual que
    // una funcion: la clausura es su struct mas `ss_cierre_N`.
    let local = buscar(c, nombre);
    if local.largo() > 0 {
        let t = T.apuntado_si(local);
        let de_cierre = funcion_de_cierre(t);
        if de_cierre.largo() > 0 {
            return nuevo(obtener(c.retornos, de_cierre) sino "");
        }
        if T.es_funcion(t) {
            let partes = T.partes_de_funcion(t);
            if partes.largo() == 0 { return vacio(); }
            return copiar(partes[partes.largo() - 1]);
        }
        return vacio();
    }

    // Una funcion del programa. `B.hecho` se busca como la escribe quien
    // llama: si dos modulos declaran `hecho`, el nombre a secas es de los dos.
    var clave = nuevo(nombre);
    if tiene(c.retornos, n.texto) { clave = copiar(n.texto); }
    if !tiene(c.retornos, clave) { return vacio(); }
    let retorno = nuevo(obtener(c.retornos, clave) sino "");
    if !tiene(c.tipo_params, clave) { return retorno; }

    // Generica: se eligen los tipos mirando los argumentos, igual que hace
    // el comprobador, y se ponen en el tipo de retorno.
    let sueltos = lista_de(c.tipo_params, vista(clave)) sino [];
    if sueltos.largo() == 0 { return retorno; }
    let declarados = lista_de(c.params, vista(clave)) sino [];
    var ligaduras: mapa<str, str> = [];
    var i = 0;
    while i < declarados.largo() && i < n.hijos.largo() {
        let dado = tipo_de(c, n.hijos[i]);
        let limpio = T.apuntado_si(dado);
        unificar(declarados[i], limpio, sueltos, ligaduras);
        i = i + 1;
    }
    return sustituir(retorno, ligaduras);
}

// `Cierre_3` -> `ss_cierre_3`, la funcion que recibe ese entorno. Vacio si
// el tipo no es el de una clausura.
fn funcion_de_cierre(t: view) -> str {
    if !empieza_con(t, "Cierre_") { return vacio(); }
    let n = rebanar(t, 7, t.largo());
    if n.largo() == 0 { return vacio(); }
    var i = 0;
    while i < n.largo() {
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
    while i < tipos.largo() {
        if i > 0 { t.empujar(", "); }
        if i < marcas.largo() {
            if marcas[i] == "&" { t.empujar("&"); }
            if marcas[i] == "mut " || marcas[i] == "&mut " {
                t.empujar("&mut ");
            }
        }
        t.empujar(tipos[i]);
        i = i + 1;
    }
    t.empujar(")");
    let retorno = obtener(c.retornos, nombre) sino "";
    if retorno.largo() > 0 && retorno != "()" {
        t.empujar(" -> ");
        t.empujar(retorno);
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
    if dado.largo() == 0 { return; }
    for s en sueltos {
        if igual(patron, s) {
            if !tiene(ligaduras, patron) { poner(ligaduras, patron, nuevo(dado)); }
            return;
        }
    }
    let p = T.apuntado_si(patron);
    let d = T.apuntado_si(dado);
    if largo(T.entre_angulos(p)) == 0 { return; }
    if largo(T.entre_angulos(d)) == 0 { return; }
    let pp = T.partir_tipos(T.entre_angulos(p));
    let dd = T.partir_tipos(T.entre_angulos(d));
    if pp.largo() != dd.largo() { return; }
    var i = 0;
    while i < pp.largo() {
        unificar(pp[i], dd[i], sueltos, ligaduras);
        i = i + 1;
    }
}

// Cambia cada parametro de tipo por lo que se le ligo, respetando los bordes
// del identificador: `lista<T>` con `T = str` da `lista<str>`.
fn sustituir(t: view, ligaduras: &mapa<str, str>) -> str {
    var salida = vacio();
    var desde = 0;
    var i = 0;
    while i <= t.largo() {
        var corta = true;
        if i < t.largo() { corta = !es_de_nombre(byte(t, i)); }
        if corta {
            if i > desde {
                let pieza = rebanar(t, desde, i);
                if tiene(ligaduras, pieza) {
                    salida.empujar(obtener(ligaduras, pieza) sino "");
                } else {
                    salida.empujar(pieza);
                }
            }
            if i < t.largo() { salida.empujar(rebanar(t, i, i + 1)); }
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
    while i < t.largo() {
        if es_de_nombre(byte(t, i)) {
            var j = i;
            while j < t.largo() && es_de_nombre(byte(t, j)) { j = j + 1; }
            if j < t.largo() && byte(t, j) == 46 {
                i = j + 1; // `P.` fuera
                continue;
            }
            r.empujar(rebanar(t, i, j));
            i = j;
            continue;
        }
        r.empujar(rebanar(t, i, i + 1));
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
