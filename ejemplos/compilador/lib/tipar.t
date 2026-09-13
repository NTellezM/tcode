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
    // Las que escribio C. Una funcion de C presta lo que recibe y no se
    // queda con nada, asi que sus argumentos no se mueven.
    externas: mapa<str, usize>,
}

fn contexto() -> Contexto {
    return Contexto { ambitos: [], campos: [], nombres: [], retornos: [],
        tipo_params: [], params: [], params_marcados: [], formas: [],
        variantes: [], externas: [] };
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
    let clase = vista(n.clase);

    if igual(clase, "entero") { return nuevo("usize"); }
    if igual(clase, "decimal") { return nuevo("f64"); }
    if igual(clase, "cadena") { return nuevo("view"); }
    if igual(clase, "interpolada") { return nuevo("str"); }
    if igual(clase, "booleano") { return nuevo("bool"); }

    if igual(clase, "variable") { return buscar(c, vista(n.texto)); }

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
        if largo(n.hijos) > 0 { return tipo_de(c, n.hijos[0]); }
        return vacio();
    }

    if igual(clase, "binaria") {
        let op = vista(n.texto);
        if es_comparacion(op) { return nuevo("bool"); }
        if largo(n.hijos) == 0 { return vacio(); }
        let izq = tipo_de(c, n.hijos[0]);
        if largo(izq) > 0 && !igual(vista(izq), "{entero}") { return izq; }
        if largo(n.hijos) > 1 { return tipo_de(c, n.hijos[1]); }
        return izq;
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

fn es_comparacion(op: view) -> bool {
    if igual(op, "==") || igual(op, "!=") { return true; }
    if igual(op, "<") || igual(op, "<=") { return true; }
    if igual(op, ">") || igual(op, ">=") { return true; }
    return igual(op, "&&") || igual(op, "||");
}

fn tipo_de_campo(c: &Contexto, struct_: view, campo: view) -> str {
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

fn es_de_nombre(b: usize) -> bool {
    if b >= 97 && b <= 122 { return true; }
    if b >= 65 && b <= 90 { return true; }
    if b >= 48 && b <= 57 { return true; }
    return b == 95;
}
