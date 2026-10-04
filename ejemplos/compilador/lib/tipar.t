// lib/tipar.t — decir de que tipo es cada cosa, escrito en Tcode.
//
// Cuarta capa del compilador en su propio lenguaje, despues del lexer, el
// parser y `tipos.t`. Esta responde la pregunta que hace el comprobador en
// cada expresion: ¿de que tipo es esto?
//
// Lo que produce se compara con lo que dice el comprobador de Python para
// cada variable de cada funcion del repositorio. Si difieren, la suite lo
// dice y nombra el archivo.

use "tipos.t" como T;
use "../../lexer/lib/sintaxis.t" como P;
use "std/texto";
use "std/lista";
use "std/mapa";
use "../../lexer/lib/clase.t";

// Lo que se sabe mientras se recorre un archivo.
struct Contexto {
    // Pila de ambitos: nombre -> tipo. El de dentro manda.
    ambitos: list<map<str, T.Tipo>>,
    // Struct -> tipos de sus campos, y sus nombres, en el mismo orden.
    campos: map<str, list<T.Tipo>>,
    nombres: map<str, list<str>>,
    // Funcion -> lo que devuelve.
    retornos: map<str, T.Tipo>,
    // Funcion generica -> sus parametros de tipo, y los tipos de sus
    // argumentos. Hacen falta para elegir la copia: `primeras(xs, 8)` con
    // `xs: list<str>` devuelve `list<str>`, no `list<T>`.
    tipo_params: map<str, list<str>>,
    params: map<str, list<T.Tipo>>,
    // Los mismos parametros pero con su marca (`&`, `mut`): hace falta para
    // saber si una llamada se queda con el valor o solo lo mira.
    params_marcados: map<str, list<str>>,
    // `Enum.Variante` -> lo que lleva esa forma, en orden. Un enum no tiene
    // campos: tiene formas, y solo una a la vez.
    formas: map<str, list<T.Tipo>>,
    // Enum -> los nombres de sus formas, para saber si un tipo es un enum.
    variantes: map<str, list<str>>,
    // Nombres que traen dos modulos a la vez. El cargador de verdad los
    // renombra, y esta capa no sabe a cual: mejor no emitir la llamada.
    repetidas: map<str, usize>,
    // Los propios que chocaban con un modulo, y como quedan en C.
    renombradas: map<str, str>,
    // Las que escribio C. Una funcion de C presta lo que recibe y no se
    // queda con nada, asi que sus argumentos no se mueven.
    externas: map<str, usize>,
    // Struct generico -> sus parametros de tipo: `Par` -> [A, B]. Un
    // `Par<str, usize>` se queda escrito asi, y sus campos se sacan de aqui.
    struct_params: map<str, list<str>>,
    // Lo que el comprobador dejo anotado: `dueno#id` -> el tipo de esa
    // expresion, con los numeros escritos ya decididos por su contexto.
    // `dueno` es la funcion que se esta escribiendo, con el nombre que le da
    // el comprobador; vacio, no se mira nada y el tipo se deduce aqui.
    anotados: map<str, T.Tipo>,
    dueno: str,
}

fn contexto() -> Contexto {
    return Contexto { ambitos: [], campos: [], nombres: [], retornos: [],
        tipo_params: [], params: [], params_marcados: [], formas: [],
        variantes: [], externas: [], repetidas: [],
        renombradas: [], struct_params: [], anotados: [], dueno: vacio() };
}

fn abrir(c: mut Contexto) {
    let nuevo_ambito: map<str, T.Tipo> = [];
    c.ambitos.anadir(nuevo_ambito);
}

fn cerrar(c: mut Contexto) {
    if c.ambitos.largo() > 0 {
        redimensionar_ambitos(c, c.ambitos.largo() - 1);
    }
}

// Quitar el ultimo ambito: se copian los de delante y se deja fuera el final.
fn redimensionar_ambitos(c: mut Contexto, cuantos: usize) {
    var quedan: list<map<str, T.Tipo>> = [];
    var i = 0;
    while i < cuantos {
        var copia: map<str, T.Tipo> = [];
        for k en claves(c.ambitos[i]) {
            let v = T.tipo_de_mapa(c.ambitos[i], k) sino T.ninguno();
            poner(copia, vista(k), v);
        }
        quedan.anadir(copia);
        i = i + 1;
    }
    c.ambitos = quedan;
}

fn declarar(c: mut Contexto, nombre: view, tipo: view) {
    if c.ambitos.largo() == 0 { abrir(c); }
    let ultimo = c.ambitos.largo() - 1;
    poner(c.ambitos[ultimo], nombre, T.leer_tipo(tipo));
}

// El tipo de un nombre, o "" si no se conoce. Del ambito mas de dentro
// hacia fuera, que es lo que hace que una variable tape a otra.
fn buscar(c: &Contexto, nombre: view) -> str {
    var i = c.ambitos.largo();
    while i > 0 {
        i = i - 1;
        if tiene(c.ambitos[i], nombre) {
            return T.escribir_de_mapa(c.ambitos[i], nombre) sino T.escribir_tipo(T.ninguno());
        }
    }
    return vacio();
}

// ------------------------------------------------------------------
// El tipo de una expresion
// ------------------------------------------------------------------

fn tipo_de(c: &Contexto, n: &P.Nodo) -> T.Tipo {
    let anotado = tipo_anotado(c, n);
    if anotado.largo() > 0 { return T.leer_tipo(anotado); }
    let clase = n.clase;

    match clase {
        Clase.Entero -> { return T.leer_tipo("usize"); }
        Clase.Decimal -> { return T.leer_tipo("f64"); }
        Clase.Cadena -> { return T.leer_tipo("view"); }
        Clase.Interpolada -> { return T.leer_tipo("str"); }
        Clase.Booleano -> { return T.leer_tipo("bool"); }
        Clase.Variable -> {
            let local = buscar(c, n.texto);
            if local.largo() > 0 { return T.leer_tipo(local); }
            // El nombre de una funcion sin parentesis detras es un valor: el
            // puntero a esa funcion, con su firma por tipo.
            return T.leer_tipo(firma_de_funcion(c, n.texto));
        }
        // Una clausura ya numerada lleva el nombre de su struct.
        Clase.Cierre -> { return T.leer_tipo(n.texto); }
        // `a..b` en un `for`: los dos extremos son del mismo entero.
        Clase.Rango -> {
            if n.hijos.largo() == 2 {
                let t = tipo_de(c, n.hijos[0]);
                return T.leer_tipo(T.hacer_rango(T.escribir_tipo(t)));
            }
        }
        // `if c { a } else { b }` vale lo que valga su primera rama: el
        // comprobador ya exige que las dos den lo mismo.
        Clase.SiExpr -> {
            if n.hijos.largo() == 3 { return tipo_de(c, n.hijos[1]); }
            return T.ninguno();
            // La condicion es el primer hijo; el valor, el segundo.
            if n.hijos.largo() > 1 { return tipo_de(c, n.hijos[1]); }
            return T.ninguno();
        }
        // `Color.Rojo` es un `Color`.
        Clase.EnumLit -> { return T.leer_tipo(sin_modulo(antes_del_punto(n.texto))); }
        // Un `match` vale lo que valgan sus brazos, y eso lo dijo el comprobador.
        // Sin lo que dijo, basta con el primer brazo que de algo que se sepa
        // tipar: todos dan lo mismo. Uno que de lo atrapado no se sabe desde
        // aqui, porque lo atrapado solo se declara dentro del brazo.
        Clase.Match -> {
            let dicho = anotado_crudo(c, n);
            if dicho.largo() > 0 && !empieza_con(dicho, "{") { return T.leer_tipo(dicho); }
            for h en n.hijos {
                if h.clase == Clase.Brazo {
                    for x en h.hijos {
                        if x.clase == Clase.Retorno && x.hijos.largo() > 0 {
                            let t = tipo_de(c, x.hijos[0]);
                            if T.conocido(t) { return t; }
                        }
                    }
                }
            }
            return T.ninguno();
        }
        Clase.Expresion -> {
            if n.hijos.largo() > 0 { return tipo_de(c, n.hijos[0]); }
            return T.ninguno();
        }
        Clase.Conversion -> {
            // El texto lleva el tipo destino, con `?` delante si es envolvente.
            let t = vista(n.texto);
            if empieza_con(t, "?") { return T.leer_tipo(rebanar(t, 1, t.largo())); }
            return T.leer_tipo(t);
        }
        Clase.Unaria -> {
            if n.texto == "!" { return T.leer_tipo("bool"); }
            // Un numero escrito con `-` delante solo cabe en uno con signo: sin
            // mas contexto es un `i64`, como en el comprobador.
            if n.texto == "-" && n.hijos.largo() > 0
            && literal_de(n.hijos[0]) == "entero" {
                return T.leer_tipo("i64");
            }
            if n.hijos.largo() > 0 { return tipo_de(c, n.hijos[0]); }
            return T.ninguno();
        }
        Clase.Binaria -> {
            let op = vista(n.texto);
            if es_comparacion(op) { return T.leer_tipo("bool"); }
            if n.hijos.largo() == 0 { return T.ninguno(); }
            if n.hijos.largo() == 1 { return tipo_de(c, n.hijos[0]); }
            return T.leer_tipo(tipo_cuenta(c, n, ""));
        }
        Clase.LiteralStruct -> {
            // `P.Estado { ... }` es un `Estado`: el modulo es de quien escribe.
            let escrito = sin_modulo(n.texto);
            // `Par { a: -3, b: 1 }` es la copia que dedujo el comprobador.
            if !contiene(escrito, "<") {
                let dicho = anotado_crudo(c, n);
                if T.es_aplicacion(dicho) {
                    let base = T.base_de_aplicacion(dicho);
                    if igual(base, escrito) { return T.leer_tipo(dicho); }
                }
            }
            return T.leer_tipo(escrito);
        }
        Clase.LiteralLista -> {
            // `[a, b, c]` sin tipo escrito es un arreglo de tamaño fijo. Un `[]`
            // vacio no dice de que es: eso lo pone la anotacion.
            if n.hijos.largo() == 0 { return T.ninguno(); }
            let elem = tipo_de(c, n.hijos[0]);
            if !T.conocido(elem) { return T.ninguno(); }
            return T.leer_tipo(T.hacer_arreglo(T.escribir_tipo(elem), texto(n.hijos.largo())));
        }
        Clase.Campo -> {
            if n.hijos.largo() == 0 { return T.ninguno(); }
            let crudo = tipo_de(c, n.hijos[0]);
            let base = T.apuntado_si(T.escribir_tipo(crudo));
            return T.leer_tipo(tipo_de_campo(c, base, n.texto));
        }
        Clase.Indice -> {
            if n.hijos.largo() == 0 { return T.ninguno(); }
            let crudo = tipo_de(c, n.hijos[0]);
            let base = T.apuntado_si(T.escribir_tipo(crudo));
            return T.leer_tipo(T.elemento(base));
        }
        Clase.Llamada -> { return T.leer_tipo(tipo_de_llamada(c, n)); }
        _ -> {
            if clase == Clase.Try || clase == Clase.Sino {
                if n.hijos.largo() > 0 { return tipo_de(c, n.hijos[0]); }
                return T.ninguno();
            }
        }
    }

    return T.ninguno();
}

// `obtener` sobre un mapa de listas devuelve un prestamo, y un prestamo no
// se puede sustituir si falla. Se pregunta antes con `tiene` y aqui se
// entrega una copia, que es lo que el que llama necesita.
fn mirar_tipos(c: &Contexto, struct_: view) -> list<T.Tipo> ! {
    return copiar(try obtener(c.campos, struct_));
}

fn mirar_nombres(c: &Contexto, struct_: view) -> list<str> ! {
    return copiar(try obtener(c.nombres, struct_));
}

// `"entero"` o `"decimal"` si el comprobador ve aqui un numero escrito que
// todavia no tiene tipo —`1`, `2.5`, `1 + 2`, `-0.5`, `if c { 1 } else { 2 }`—,
// y `""` si no. Un numero asi toma el tipo del otro lado de la operacion, o
// el que se espera de el; sin nada que lo decida, `usize` o `f64`.
fn literal_de(n: &P.Nodo) -> view {
    let clase = n.clase;
    match clase {
        Clase.Entero -> { return "entero"; }
        Clase.Decimal -> { return "decimal"; }
        // `-1` ya es un `i64`; `-0.5` sigue sin decidir su ancho.
        Clase.Unaria -> {
            if n.texto == "-" && n.hijos.largo() == 1 {
                if literal_de(n.hijos[0]) == "decimal" { return "decimal"; }
                return "";
            }
        }
        Clase.Binaria -> {
            if !es_comparacion(n.texto) && n.hijos.largo() == 2 {
                let izq = literal_de(n.hijos[0]);
                let der = literal_de(n.hijos[1]);
                if izq.largo() > 0 && der.largo() > 0 {
                    if izq == "decimal" || der == "decimal" {
                        return "decimal";
                    }
                    return "entero";
                }
            }
        }
        Clase.SiExpr -> {
            if n.hijos.largo() == 3 {
                let a = literal_de(n.hijos[1]);
                let b = literal_de(n.hijos[2]);
                if a.largo() > 0 && b.largo() > 0 {
                    if a == "decimal" || b == "decimal" { return "decimal"; }
                    return "entero";
                }
            }
        }
        _ -> { }
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
    return T.escribir_de_mapa(c.anotados, clave) sino T.escribir_tipo(T.ninguno());
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
        let t = T.escribir_tipo(tipo_de(c, n.hijos[1]));
        if es_numero(t) { return t; }
    }
    let a = T.escribir_tipo(tipo_de(c, n.hijos[0]));
    if es_numero(a) { return a; }
    let otro = T.escribir_tipo(tipo_de(c, n.hijos[1]));
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

// Los tipos de los campos de una aplicacion, con sus parametros puestos.
fn tipos_de_aplicacion(c: &Contexto, t: view) -> list<str> {
    var salida: list<str> = [];
    let base = T.base_de_aplicacion(t);
    if !tiene(c.struct_params, base) { return salida; }
    let sueltos = lista_de(c.struct_params, vista(base)) sino [];
    let dados = T.partes(t);
    if dados.largo() != sueltos.largo() { return salida; }
    var ligaduras: map<str, str> = [];
    var i = 0;
    while i < sueltos.largo() {
        poner(ligaduras, vista(sueltos[i]), copiar(dados[i]));
        i = i + 1;
    }
    let crudos = mirar_tipos(c, base) sino [];
    for x en crudos { salida.anadir(T.escribir_tipo(T.sustituir_tipo(x, ligaduras))); }
    return salida;
}

fn tipo_de_campo(c: &Contexto, struct_: view, campo: view) -> str {
    if T.es_aplicacion(struct_) {
        let base = T.base_de_aplicacion(struct_);
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
        if igual(nombres[i], campo) { return T.escribir_tipo(tipos[i]); }
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
    if nombre == "leer_parte_archivo" { return nuevo("str"); }
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
    return T.hacer_prestado(t);
}

// Si un tipo tiene duenio: la regla de `tipos.t`, con lo que este contexto
// sabe de structs, genericas y enums.
fn posee_con_formas(c: &Contexto, t: view) -> bool {
    var vistos: map<str, usize> = [];
    return T.posee_en(T.leer_tipo(t), c.campos, c.struct_params, c.variantes, c.formas, vistos);
}

// `Color.Rojo` -> `Color`; `m.Color.Rojo` -> `m.Color`.
fn antes_del_punto(t: view) -> str {
    var i = t.largo();
    while i > 0 {
        i = i - 1;
        if byte(t, i) == 46 { return nuevo(rebanar(t, 0, i)); }
    }
    return nuevo(t);
}

fn tras_el_punto(t: view) -> str {
    var i = t.largo();
    while i > 0 {
        i = i - 1;
        if byte(t, i) == 46 {
            return nuevo(rebanar(t, i + 1, t.largo()));
        }
    }
    return vacio();
}

// El tipo con cada struct generico aplicado cambiado por el nombre de su
// copia, a cualquier hondura: `list<Par<str, usize>>` ->
// `list<Par__str_usize>`. Es lo que hace el comprobador de Python antes de
// generar; aqui el tipo escrito se queda como estaba y esto se usa al
// escribirlo.
fn nombre_resuelto(t: view) -> str {
    // Sin angulos ni corchetes no lleva ninguna aplicacion.
    if !contiene(t, "<") && !contiene(t, "[") { return nuevo(t); }
    // Lo que lleva tipos dentro se resuelve parte a parte y se vuelve a
    // montar.
    if T.es_referencia(t) || T.es_lista(t) || T.es_bloque(t) || T.es_mapa(t)
    || T.es_arreglo(t) {
        var nuevas: list<str> = [];
        for parte en T.partes(t) { nuevas.anadir(nombre_resuelto(parte)); }
        return T.con_partes(t, nuevas);
    }
    if !T.es_aplicacion(t) { return nuevo(t); }
    var args: list<str> = [];
    for a en T.partes(t) { args.anadir(nombre_resuelto(a)); }
    return T.nombre_de_copia(T.base_de_aplicacion(t), args);
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
        let crudo = T.escribir_tipo(tipo_de(c, n.hijos[0]));
        let primero = T.apuntado_si(crudo);
        if nombre == "copiar" { return copiar(primero); }
        if nombre == "intercambiar" { return copiar(primero); }
        if nombre == "absoluto" { return copiar(primero); }
        if nombre == "claves" {
            let partes = T.partes(primero);
            if partes.largo() == 2 {
                return T.hacer_lista(partes[0]);
            }
            return vacio();
        }
        if nombre == "obtener" || nombre == "obtener_mut" {
            let partes = T.partes(primero);
            if partes.largo() != 2 { return vacio(); }
            let valor = copiar(partes[1]);
            // Un valor con duenio no sale del mapa: sale prestado. Y un
            // `str` prestado es una vista, que es lo mismo con otro nombre.
            if nombre == "obtener_mut" {
                return T.hacer_prestado_mut(valor);
            }
            if valor == "str" { return nuevo("view"); }
            if posee_con_formas(c, valor) {
                return T.hacer_prestado(valor);
            }
            return valor;
        }
    }

    // Una variable que guarda una clausura o una funcion se llama igual que
    // una funcion: la clausura es su struct mas `ss_cierre_N`. Se busca por
    // el nombre entero, como en el generador: `T.partes(x)` es la funcion de
    // `T` aunque haya un local `partes`. Un local que no se puede llamar no
    // cambia nada: la llamada es a la funcion de su nombre.
    let local = buscar(c, n.texto);
    if local.largo() > 0 {
        let t = T.apuntado_si(local);
        let de_cierre = funcion_de_cierre(t);
        if de_cierre.largo() > 0 {
            return T.escribir_de_mapa(c.retornos, de_cierre) sino T.escribir_tipo(T.ninguno());
        }
        if T.es_funcion(t) {
            let partes = T.partes_de_funcion(t);
            if partes.largo() == 0 { return vacio(); }
            return copiar(partes[partes.largo() - 1]);
        }
    }

    // Una funcion del programa. `B.hecho` se busca como la escribe quien
    // llama: si dos modulos declaran `hecho`, el nombre a secas es de los dos.
    var clave = nuevo(nombre);
    if tiene(c.retornos, n.texto) { clave = copiar(n.texto); }
    if !tiene(c.retornos, clave) { return vacio(); }
    let retorno = T.escribir_de_mapa(c.retornos, clave) sino T.escribir_tipo(T.ninguno());
    if !tiene(c.tipo_params, clave) { return retorno; }

    // Generica: se eligen los tipos mirando los argumentos, igual que hace
    // el comprobador, y se ponen en el tipo de retorno.
    let sueltos = lista_de(c.tipo_params, vista(clave)) sino [];
    if sueltos.largo() == 0 { return retorno; }
    let declarados = T.tipos_de_mapa(c.params, vista(clave)) sino [];
    var ligaduras: map<str, str> = [];
    var i = 0;
    while i < declarados.largo() && i < n.hijos.largo() {
        let dado = tipo_de(c, n.hijos[i]);
        T.ligar_tipo(declarados[i], dado, sueltos, ligaduras);
        i = i + 1;
    }
    return T.sustituir(retorno, ligaduras);
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
    let tipos = T.tipos_de_mapa(c.params, nombre) sino [];
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
        t.empujar(T.escribir_tipo(tipos[i]));
        i = i + 1;
    }
    t.empujar(")");
    let retorno = T.escribir_de_mapa(c.retornos, nombre) sino T.escribir_tipo(T.ninguno());
    if retorno.largo() > 0 && retorno != "()" {
        t.empujar(" -> ");
        t.empujar(retorno);
    }
    return t;
}

fn lista_de(m: &map<str, list<str>>, clave: view) -> list<str> ! {
    return copiar(try obtener(m, clave));
}
