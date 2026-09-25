// lib/comprobar.t — el comprobador, escrito en Tcode.
//
// La ultima capa que faltaba para que el compilador no necesite a Python: la
// que dice que un programa NO vale. Tipos, propiedad, prestamos, mutabilidad
// y fallos, con las mismas reglas y los mismos mensajes que el comprobador de
// Python, en el mismo orden. La suite compara los dos sobre cada programa que
// tiene que rechazarse, y exige que ninguno correcto se rechace.
//
// Trabaja sobre los arboles del programa entero, con las clausuras ya
// numeradas por quien escribe el C. Lo que todavia no mira: los cuerpos de
// las genericas, que el original comprueba en cada copia.

usar "tipar.t" como I;
usar "tipos.t" como T;
usar "generar.t" como G;
usar "../../lexer/lib/sintaxis.t" como P;
usar "std/texto";
usar "std/lista";

// ------------------------------------------------------------------
// Los tipos basicos, como en el original
// ------------------------------------------------------------------

// Un numero escrito todavia no tiene ancho, y uno con punto tampoco.
fn literal() -> view { return "{entero}"; }
fn literal_decimal() -> view { return "{decimal}"; }
fn unidad() -> view { return "()"; }

fn es_sin_signo(t: view) -> bool {
    return igual(t, "u8") || igual(t, "u16") || igual(t, "u32")
    || igual(t, "u64") || igual(t, "usize");
}

fn es_con_signo(t: view) -> bool {
    return igual(t, "i8") || igual(t, "i16") || igual(t, "i32")
    || igual(t, "i64");
}

fn es_tipo_entero(t: view) -> bool { return es_sin_signo(t) || es_con_signo(t); }

fn es_decimal(t: view) -> bool { return igual(t, "f32") || igual(t, "f64"); }

fn es_numerico(t: view) -> bool { return es_tipo_entero(t) || es_decimal(t); }

fn es_referencia_mutable(t: view) -> bool { return empieza_con(t, "&mut "); }

fn sin_prestamo(t: view) -> str { return T.apuntado_si(t); }

// Lo que no posee nada detras: se puede sacar de un prestamo.
fn es_copiable(t: view) -> bool {
    return es_numerico(t) || igual(t, "bool") || igual(t, "view")
    || igual(t, literal()) || igual(t, literal_decimal()) || igual(t, unidad())
    || T.es_funcion(t);
}

// Un valor de tipo `dado` sirve donde se pide `esperado`.
fn encaja(esperado: view, dado: view) -> bool {
    if igual(esperado, dado) { return true; }
    if igual(dado, literal()) && es_numerico(esperado) { return true; }
    if igual(dado, literal_decimal()) && es_decimal(esperado) { return true; }
    if T.es_referencia(dado) && !T.es_referencia(esperado) && es_copiable(esperado) {
        return encaja(esperado, T.apuntado(dado));
    }
    return false;
}

fn concreto(t: view) -> str {
    if igual(t, literal()) { return nuevo("usize"); }
    return nuevo(t);
}

// `mapa<K, V>` -> [K, V].
fn clave_y_valor(t: view) -> lista<str> {
    return T.partir_tipos(T.entre_angulos(t));
}

// `[T; N]` -> T y N, respetando arreglos de arreglos.
fn elem_arreglo(t: view) -> str {
    var hondo = 0;
    var i = largo(t) - 1;
    while i > 1 {
        i = i - 1;
        let c = byte(t, i);
        if c == 93 { hondo = hondo + 1; }
        if c == 91 { hondo = hondo - 1; }
        if c == 59 && hondo == 0 { return nuevo(rebanar(t, 1, i)); }
    }
    return vacio();
}

fn largo_arreglo(t: view) -> str {
    var hondo = 0;
    var i = largo(t) - 1;
    while i > 1 {
        i = i - 1;
        let c = byte(t, i);
        if c == 93 { hondo = hondo + 1; }
        if c == 91 { hondo = hondo - 1; }
        if c == 59 && hondo == 0 {
            return nuevo(recortar(rebanar(t, i + 1, largo(t) - 1)));
        }
    }
    return vacio();
}

fn elem_lista(t: view) -> str { return nuevo(rebanar(t, 6, largo(t) - 1)); }
fn elem_bloque(t: view) -> str { return nuevo(rebanar(t, 7, largo(t) - 1)); }

// `a`, `b` y `c` -> "`a`, `b` y `c`".
fn lista_legible(nombres: &lista<str>) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(nombres) {
        if i > 0 {
            if i + 1 == largo(nombres) { empujar(r, " y "); } else { empujar(r, ", "); }
        }
        empujar(r, "`");
        empujar(r, vista(nombres[i]));
        empujar(r, "`");
        i = i + 1;
    }
    return r;
}

// "`a`, `b`, `c`": todos con coma, como `", ".join` del original.
fn con_comas(nombres: &lista<str>) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(nombres) {
        if i > 0 { empujar(r, ", "); }
        empujar(r, "`");
        empujar(r, vista(nombres[i]));
        empujar(r, "`");
        i = i + 1;
    }
    return r;
}

fn numericos() -> lista<str> {
    var r: lista<str> = [];
    anadir(r, nuevo("u8")); anadir(r, nuevo("u16")); anadir(r, nuevo("u32"));
    anadir(r, nuevo("u64")); anadir(r, nuevo("usize")); anadir(r, nuevo("i8"));
    anadir(r, nuevo("i16")); anadir(r, nuevo("i32")); anadir(r, nuevo("i64"));
    anadir(r, nuevo("f32")); anadir(r, nuevo("f64"));
    return r;
}

fn igualables() -> lista<str> {
    var r = numericos();
    anadir(r, nuevo("bool")); anadir(r, nuevo("str")); anadir(r, nuevo("view"));
    ordenar(r);
    return r;
}

fn comparables() -> lista<str> {
    var r = numericos();
    anadir(r, nuevo("str")); anadir(r, nuevo("view"));
    ordenar(r);
    return r;
}

fn ordenables() -> lista<str> {
    var r = numericos();
    anadir(r, nuevo("bool")); anadir(r, nuevo("str"));
    ordenar(r);
    return r;
}

fn restriccion_admite(r: view) -> lista<str> {
    var s: lista<str> = [];
    if igual(r, "numero") { s = numericos(); }
    if igual(r, "entero") {
        for t en numericos() {
            if es_tipo_entero(vista(t)) { anadir(s, copiar(t)); }
        }
    }
    if igual(r, "decimal") { anadir(s, nuevo("f32")); anadir(s, nuevo("f64")); }
    if igual(r, "igualable") { s = igualables(); }
    if igual(r, "ordenable") { s = comparables(); }
    if igual(r, "texto") { anadir(s, nuevo("str")); anadir(s, nuevo("view")); }
    ordenar(s);
    return s;
}

fn esta_entre(xs: &lista<str>, x: view) -> bool {
    for y en xs {
        if igual(vista(y), x) { return true; }
    }
    return false;
}

// ------------------------------------------------------------------
// Las internas
// ------------------------------------------------------------------

struct Interna {
    existe: bool,
    params: lista<str>,
    retorno: str,
    falible: bool,
}

fn firma_interna(nombre: view) -> Interna {
    var ps: lista<str> = [];
    var r = vacio();
    var fal = false;
    var existe = true;
    if igual(nombre, "vacio") { r = nuevo("str"); }
    else if igual(nombre, "nuevo") { anadir(ps, nuevo("view")); r = nuevo("str"); }
    else if igual(nombre, "vista") { anadir(ps, nuevo("@presta")); r = nuevo("view"); }
    else if igual(nombre, "empujar") {
        anadir(ps, nuevo("@mut")); anadir(ps, nuevo("view")); r = nuevo("()");
    }
    else if igual(nombre, "empujar_byte") {
        anadir(ps, nuevo("@mut")); anadir(ps, nuevo("u8")); r = nuevo("()");
    }
    else if igual(nombre, "largo") { anadir(ps, nuevo("@dimensionable")); r = nuevo("usize"); }
    else if igual(nombre, "igual") || igual(nombre, "menor") {
        anadir(ps, nuevo("@comparable")); anadir(ps, nuevo("@comparable"));
        r = nuevo("bool");
    }
    else if igual(nombre, "rebanar") {
        anadir(ps, nuevo("view")); anadir(ps, nuevo("usize")); anadir(ps, nuevo("usize"));
        r = nuevo("view");
    }
    else if igual(nombre, "imprimir") || igual(nombre, "imprimir_error") {
        anadir(ps, nuevo("@cualquiera")); r = nuevo("()");
    }
    else if igual(nombre, "anadir") {
        anadir(ps, nuevo("@lista_mut")); anadir(ps, nuevo("@elemento")); r = nuevo("()");
    }
    else if igual(nombre, "texto") { anadir(ps, nuevo("@escalar")); r = nuevo("str"); }
    else if igual(nombre, "copiar") { anadir(ps, nuevo("@copiable")); }
    else if igual(nombre, "intercambiar") {
        anadir(ps, nuevo("@lugar_mut")); anadir(ps, nuevo("@valor_igual"));
    }
    else if igual(nombre, "reservar") { anadir(ps, nuevo("usize")); }
    else if igual(nombre, "redimensionar") {
        anadir(ps, nuevo("@bloque_mut")); anadir(ps, nuevo("usize")); r = nuevo("()");
    }
    else if igual(nombre, "raiz") || igual(nombre, "piso") || igual(nombre, "techo")
    || igual(nombre, "redondear") {
        anadir(ps, nuevo("@decimal"));
    }
    else if igual(nombre, "absoluto") { anadir(ps, nuevo("@con_signo")); }
    else if igual(nombre, "byte") {
        anadir(ps, nuevo("view")); anadir(ps, nuevo("usize")); r = nuevo("usize");
    }
    else if igual(nombre, "n_argumentos") { r = nuevo("usize"); }
    else if igual(nombre, "argumento") { anadir(ps, nuevo("usize")); r = nuevo("view"); }
    else if igual(nombre, "leer_archivo") {
        anadir(ps, nuevo("view")); r = nuevo("str"); fal = true;
    }
    else if igual(nombre, "escribir_archivo") {
        anadir(ps, nuevo("view")); anadir(ps, nuevo("view")); r = nuevo("()"); fal = true;
    }
    else if igual(nombre, "leer_linea") || igual(nombre, "entrada_completa") {
        r = nuevo("str"); fal = true;
    }
    else if igual(nombre, "variable_entorno") {
        anadir(ps, nuevo("view")); r = nuevo("str"); fal = true;
    }
    else if igual(nombre, "ahora_ms") || igual(nombre, "monotono_ms") { r = nuevo("i64"); }
    else if igual(nombre, "azar") { anadir(ps, nuevo("usize")); r = nuevo("usize"); }
    else if igual(nombre, "sembrar") { anadir(ps, nuevo("u64")); r = nuevo("()"); }
    else if igual(nombre, "ordenar") { anadir(ps, nuevo("@lista_mut")); r = nuevo("()"); }
    else if igual(nombre, "poner") {
        anadir(ps, nuevo("@mapa_mut")); anadir(ps, nuevo("@clave"));
        anadir(ps, nuevo("@valor")); r = nuevo("()");
    }
    else if igual(nombre, "obtener") {
        anadir(ps, nuevo("@mapa")); anadir(ps, nuevo("@clave")); fal = true;
    }
    else if igual(nombre, "tiene") {
        anadir(ps, nuevo("@mapa")); anadir(ps, nuevo("@clave")); r = nuevo("bool");
    }
    else if igual(nombre, "claves") { anadir(ps, nuevo("@mapa")); }
    else if igual(nombre, "quitar") {
        anadir(ps, nuevo("@mapa_mut")); anadir(ps, nuevo("@clave")); r = nuevo("bool");
    }
    else if igual(nombre, "obtener_mut") {
        anadir(ps, nuevo("@mapa_mut")); anadir(ps, nuevo("@clave")); fal = true;
    }
    else { existe = false; }
    return Interna { existe: existe, params: ps, retorno: r, falible: fal };
}

fn nombra_interna(nombre: view) -> bool {
    let f = firma_interna(nombre);
    return f.existe;
}

// ------------------------------------------------------------------
// El mundo: lo que se sabe del programa entero
// ------------------------------------------------------------------

struct Param {
    nombre: str,
    tipo: str,
    mutable: bool,
    compartido: bool,
}

struct Funcion {
    // Como se llama por dentro: con el modulo delante si chocaba con otra.
    nombre: str,
    archivo: str,
    linea: usize,
    params: lista<Param>,
    // Vacio si no dice que devuelve.
    retorno: str,
    falible: bool,
    externa: bool,
    // De C, y devuelve `cadena_c`: por dentro es un `str`.
    cadena_c: bool,
    tipo_params: lista<str>,
    // `T=numero`, en el orden en que se escribieron.
    restricciones: lista<str>,
    // Donde esta su arbol: el modulo y la posicion, o la clausura.
    modulo: usize,
    posicion: usize,
    de_cierre: bool,
}

struct Mundo {
    funciones: lista<Funcion>,
    indice: mapa<str, usize>,
    // Structs concretos y plantillas: tipos y nombres de sus campos.
    st_tipos: mapa<str, lista<str>>,
    st_nombres: mapa<str, lista<str>>,
    // Struct generico -> sus parametros de tipo.
    st_params: mapa<str, lista<str>>,
    // Enum -> sus formas; `Enum.Forma` -> lo que lleva.
    en_variantes: mapa<str, lista<str>>,
    en_formas: mapa<str, lista<str>>,
    // Nombre por dentro -> el que se escribio, para los mensajes.
    bonitos: mapa<str, str>,
    // Las funciones de las clausuras, que nacen al comprobarlas: la N-1 es
    // `ss_cierre_N`, escrita en el modulo `cierres_mod[N-1]`.
    cierres: lista<P.Nodo>,
    cierres_mod: lista<usize>,
    n_cierres: usize,
    // Los structs de las clausuras que modifican lo que capturaron:
    // llamarlas las modifica.
    cierres_mut: lista<str>,
    // `dueno#k` -> N: la k-esima clausura del cuerpo de `dueno` (una
    // funcion, `plantilla|T1|T2` para la copia de una generica, o
    // `ss_cierre_M`) es `Cierre_N`.
    numeracion: mapa<str, usize>,
    // Lo que hace falta para comprobar la copia de una generica: el arbol de
    // cada modulo y como se ven los nombres desde el.
    arboles: lista<P.Nodo>,
    modulos: lista<str>,
    contextos: lista<I.Contexto>,
    // Las copias ya creadas: `plantilla|T1|T2`.
    copias: lista<str>,
    // Los structs en el orden en que existen para el original: los escritos,
    // y despues cada copia de un generico y cada clausura segun nacen, con
    // el nombre que les da el original (`Par__str_usize`) y su tipo aqui.
    orden_structs: lista<str>,
    tipo_de_struct: lista<str>,
    // El tipo de cada expresion, por modulo: `dueno#id` -> tipo, con los
    // numeros escritos ya decididos por su contexto. El generador lo lee de
    // aqui en vez de deducirlo otra vez.
    anotados: lista<mapa<str, str>>,
    // Las copias de genericas y las clausuras, en el orden en que nacen: una
    // clausura al verla, una copia despues de comprobar su cuerpo. Es el
    // orden en que el generador las escribe.
    orden_copias: lista<str>,
}

fn param_de(texto: view) -> Param {
    var corte = 0;
    while corte < largo(texto) && byte(texto, corte) != 58 { corte = corte + 1; }
    let nombre = recortar(rebanar(texto, 0, corte));
    var resto = recortar(rebanar(texto, corte + 1, largo(texto)));
    var mutable = false;
    var compartido = false;
    if empieza_con(resto, "mut ") {
        mutable = true;
        resto = recortar(rebanar(resto, 4, largo(resto)));
    } else if empieza_con(resto, "&mut ") {
        mutable = true;
        resto = recortar(rebanar(resto, 5, largo(resto)));
    } else if empieza_con(resto, "&") {
        compartido = true;
        resto = recortar(rebanar(resto, 1, largo(resto)));
    }
    return Param { nombre: nuevo(nombre), tipo: I.sin_alias_tipo(resto),
        mutable: mutable, compartido: compartido };
}

fn prestado(p: &Param) -> bool { return p.mutable || p.compartido; }

// Lo que dice la firma de un nodo `fn`.
fn funcion_de(d: &P.Nodo, nombre: view, archivo: view, modulo: usize,
    posicion: usize, externa: bool) -> Funcion {
    var ps: lista<Param> = [];
    var ret = vacio();
    var fal = false;
    var tps: lista<str> = [];
    var rs: lista<str> = [];
    for h en d.hijos {
        let clase = vista(h.clase);
        if igual(clase, "param") { anadir(ps, param_de(vista(h.texto))); }
        if igual(clase, "retorno_tipo") { ret = I.sin_alias_tipo(vista(h.texto)); }
        if igual(clase, "falible") { fal = true; }
        if igual(clase, "tipo_param") { anadir(tps, copiar(h.texto)); }
        if igual(clase, "restriccion") && largo(tps) > 0 {
            let tp = vista(tps[largo(tps) - 1]);
            anadir(rs, $"{tp}={h.texto}");
        }
    }
    var cadena = false;
    if externa && igual(vista(ret), "cadena_c") { cadena = true; }
    return Funcion { nombre: nuevo(nombre), archivo: nuevo(archivo), linea: d.linea,
        params: ps, retorno: ret, falible: fal, externa: externa, cadena_c: cadena,
        tipo_params: tps, restricciones: rs, modulo: modulo, posicion: posicion,
        de_cierre: false };
}

fn tiene_sueltos(f: &Funcion) -> bool { return largo(f.tipo_params) > 0; }

fn buscar_funcion(m: &Mundo, nombre: view) -> usize ! {
    if !tiene(m.indice, nombre) { falla "no es una funcion"; }
    return obtener(m.indice, nombre) sino 0;
}

// El nombre de una funcion tal como la ve un modulo: el alias de modulo
// fuera, o el nombre que le puso el cargador si chocaba con otra.
fn resolver_nombre(tipos: &I.Contexto, nombre: view) -> str {
    if tiene(tipos.renombradas, nombre) {
        return nuevo(obtener(tipos.renombradas, nombre) sino "");
    }
    return I.sin_modulo(nombre);
}

// Un struct generico aplicado: `Par<i64, usize>`.
fn es_struct_aplicado(m: &Mundo, t: view) -> bool {
    if !I.es_aplicacion(t) { return false; }
    let base = I.base_de_aplicacion(t);
    return tiene(m.st_params, vista(base));
}

fn es_struct(m: &Mundo, t: view) -> bool {
    if es_struct_aplicado(m, t) { return true; }
    return tiene(m.st_tipos, t) && !tiene(m.st_params, t);
}

fn es_enum(m: &Mundo, t: view) -> bool { return tiene(m.en_variantes, t); }

// Los campos de un struct, con los tipos de una aplicacion ya puestos.
fn campos_tipos(m: &Mundo, t: view) -> lista<str> {
    var salida: lista<str> = [];
    if es_struct_aplicado(m, t) {
        let base = I.base_de_aplicacion(t);
        let sueltos = I.lista_de(m.st_params, vista(base)) sino [];
        let dados = T.partir_tipos(T.entre_angulos(t));
        if largo(dados) != largo(sueltos) { return salida; }
        var lig: mapa<str, str> = [];
        var i = 0;
        while i < largo(sueltos) {
            poner(lig, vista(sueltos[i]), copiar(dados[i]));
            i = i + 1;
        }
        let crudos = I.lista_de(m.st_tipos, vista(base)) sino [];
        for x en crudos { anadir(salida, I.sustituir(vista(x), lig)); }
        return salida;
    }
    return I.lista_de(m.st_tipos, t) sino [];
}

fn campos_nombres(m: &Mundo, t: view) -> lista<str> {
    if es_struct_aplicado(m, t) {
        let base = I.base_de_aplicacion(t);
        return I.lista_de(m.st_nombres, vista(base)) sino [];
    }
    return I.lista_de(m.st_nombres, t) sino [];
}

fn campo_tipo(m: &Mundo, t: view, campo: view) -> str {
    let ns = campos_nombres(m, t);
    let ts = campos_tipos(m, t);
    var i = 0;
    while i < largo(ns) && i < largo(ts) {
        if igual(vista(ns[i]), campo) { return copiar(ts[i]); }
        i = i + 1;
    }
    return vacio();
}

fn formas_de(m: &Mundo, en_t: view, forma: view) -> lista<str> {
    let clave = $"{en_t}.{forma}";
    return I.lista_de(m.en_formas, vista(clave)) sino [];
}

fn tiene_forma(m: &Mundo, en_t: view, forma: view) -> bool {
    let vs = I.lista_de(m.en_variantes, en_t) sino [];
    return esta_entre(vs, forma);
}

// Un valor de este tipo es duenio de memoria del heap.
fn posee_memoria(m: &Mundo, t: view) -> bool {
    var vistos: lista<str> = [];
    return posee_desde(m, t, vistos);
}

fn posee_desde(m: &Mundo, t: view, vistos: mut lista<str>) -> bool {
    if T.es_referencia(t) || T.es_funcion(t) { return false; }
    if igual(t, "str") { return true; }
    if T.es_mapa(t) || T.es_bloque(t) || T.es_lista(t) { return true; }
    if T.es_arreglo(t) {
        let e = elem_arreglo(t);
        return posee_desde(m, vista(e), vistos);
    }
    if esta_entre(vistos, t) { return false; }
    if es_enum(m, t) {
        anadir(vistos, nuevo(t));
        let vs = I.lista_de(m.en_variantes, t) sino [];
        for v en vs {
            for x en formas_de(m, t, vista(v)) {
                if posee_desde(m, vista(x), vistos) { return true; }
            }
        }
        return false;
    }
    if !es_struct(m, t) { return false; }
    anadir(vistos, nuevo(t));
    for x en campos_tipos(m, t) {
        if posee_desde(m, vista(x), vistos) { return true; }
    }
    return false;
}

// Tiene partes: se puede mirar o modificar por dentro.
fn es_compuesto(m: &Mundo, t: view) -> bool {
    return igual(t, "str") || T.es_bloque(t) || T.es_lista(t) || T.es_mapa(t)
    || T.es_arreglo(t) || es_struct(m, t) || es_enum(m, t);
}

// Se puede guardar un valor de este tipo.
fn almacenable(m: &Mundo, t: view) -> bool {
    if T.es_referencia(t) { return almacenable(m, T.apuntado(t)); }
    if T.es_funcion(t) {
        let partes = T.partes_de_funcion(t);
        if largo(partes) == 0 { return false; }
        var i = 0;
        while i + 1 < largo(partes) {
            if !almacenable(m, vista(partes[i])) { return false; }
            i = i + 1;
        }
        let r = vista(partes[largo(partes) - 1]);
        return igual(r, "()") || almacenable(m, r);
    }
    if es_numerico(t) || igual(t, "str") || igual(t, "view") || igual(t, "bool") {
        return true;
    }
    if es_struct(m, t) || es_enum(m, t) { return true; }
    if T.es_arreglo(t) {
        // Un arreglo tampoco guarda vistas: cada elemento se puede reasignar
        // por un indice que no se conoce al compilar, y no habria forma de
        // saber de quien presta cada uno.
        let e = elem_arreglo(t);
        return !igual(vista(e), "view") && !es_prestado_st(m, vista(e))
        && almacenable(m, vista(e));
    }
    if T.es_mapa(t) {
        let ps = clave_y_valor(t);
        if largo(ps) != 2 { return false; }
        // Un mapa tampoco guarda vistas: nadie sabria cuanto viven.
        return almacenable(m, vista(ps[0])) && almacenable(m, vista(ps[1]))
        && !igual(vista(ps[0]), "view") && !es_prestado_st(m, vista(ps[0]))
        && !igual(vista(ps[1]), "view") && !es_prestado_st(m, vista(ps[1]));
    }
    if T.es_bloque(t) {
        let e = elem_bloque(t);
        return !igual(vista(e), "view") && !T.es_arreglo(vista(e))
        && !es_prestado_st(m, vista(e)) && almacenable(m, vista(e));
    }
    if T.es_lista(t) {
        let e = elem_lista(t);
        return !igual(vista(e), "view") && !T.es_arreglo(vista(e))
        && !es_prestado_st(m, vista(e)) && almacenable(m, vista(e));
    }
    return false;
}

// Un struct que presta: lleva una `view`, o un struct que presta. Se trata
// como una vista: apunta a memoria de otro.
fn es_prestado_st(m: &Mundo, t: view) -> bool {
    var vistos: lista<str> = [];
    return presta_st(m, t, vistos);
}

fn presta_st(m: &Mundo, t: view, vistos: mut lista<str>) -> bool {
    if !es_struct(m, t) || esta_entre(vistos, t) { return false; }
    anadir(vistos, nuevo(t));
    for ct en campos_tipos(m, t) {
        if igual(vista(ct), "view") || presta_st(m, vista(ct), vistos) { return true; }
    }
    return false;
}

// Si un valor de este tipo apunta a memoria de otro.
fn presta_tipo(m: &Mundo, t: view) -> bool {
    return igual(t, "view") || T.es_referencia(t) || es_prestado_st(m, t);
}

fn error_enum_prestado(c: mut Comprobacion, m: &Mundo, linea: usize, en_n: view, forma: view,
    t: view) {
    error(c, m, linea, $"`{en_n}.{forma}` lleva un `{t}`, que presta: un enum no guarda prestamos, porque al mirarlo nadie sabria de quien presta. Usa `str`, o un struct con duenio");
}

// Un struct o enum que se contiene a si mismo por valor.
fn se_contiene(m: &Mundo, t: view, buscado: view, vistos: mut lista<str>) -> bool {
    if igual(t, buscado) { return true; }
    if T.es_arreglo(t) {
        let e = elem_arreglo(t);
        return se_contiene(m, vista(e), buscado, vistos);
    }
    if T.es_mapa(t) || T.es_lista(t) { return false; }
    if esta_entre(vistos, t) { return false; }
    if es_enum(m, t) {
        anadir(vistos, nuevo(t));
        let vs = I.lista_de(m.en_variantes, t) sino [];
        for v en vs {
            for x en formas_de(m, t, vista(v)) {
                if se_contiene(m, vista(x), buscado, vistos) { return true; }
            }
        }
        return false;
    }
    if !es_struct(m, t) { return false; }
    anadir(vistos, nuevo(t));
    for x en campos_tipos(m, t) {
        if se_contiene(m, vista(x), buscado, vistos) { return true; }
    }
    return false;
}

// ------------------------------------------------------------------
// Simbolos y ambitos
// ------------------------------------------------------------------

struct Simbolo {
    nombre: str,
    tipo: str,
    mutable: bool,
    prestado: bool,
    movida: bool,
    movida_en: usize,
    entregada_en: usize,
    reasignada_directo: bool,
    bucle_al_declarar: usize,
    // En cuantos `if`/`match` estaba al declararse, y los campos que se le
    // sacaron, en orden: `ruta\tlinea`, con `nombre` o `a.b` de ruta.
    condicional_al_declarar: usize,
    sacados: lista<str>,
    // Las vistas vivas que prestan de esta variable, y las reservas.
    prestamos: lista<str>,
    // Si es una vista: de quien presta, y de donde sale su memoria. En
    // `origenes`, todos los duenios de los que puede venir, el primero
    // delante.
    origen: str,
    origenes: lista<str>,
    procedencia: str,
    // Para los avisos: se leyo alguna vez, se modifico alguna vez, donde se
    // declaro, si es un parametro, y su sitio en la historia de la funcion.
    leida: bool,
    mutada: bool,
    linea_decl: usize,
    es_param: bool,
    historia: usize,
    // A que funcion se entrego, si se entrego pasandola a una.
    movida_a: str,
}

struct Comprobacion {
    archivo: str,
    modulo: usize,
    // Todos los simbolos vivos, de fuera hacia dentro; `inicios` dice donde
    // empieza cada ambito.
    simbolos: lista<Simbolo>,
    inicios: lista<usize>,
    errores: lista<str>,
    retorno: str,
    falible: bool,
    en_condicional: usize,
    en_condicion_bucle: usize,
    en_bucle: usize,
    // El nivel de bucle cuyas sentencias se escriben directamente; -1 si
    // hay algo de por medio.
    en_bucle_directo: i64,
    // Por cada bucle abierto: los movimientos de variables de fuera, como
    // pares indice, linea.
    movidas_en_bucle: lista<lista<usize>>,
    en_retorno: usize,
    // Las copias de genericas que se estan comprobando, de fuera hacia
    // dentro: `al usar `f` con T = str, desde archivo:linea`.
    instanciando: lista<str>,
    // De quien es el cuerpo que se esta mirando, para numerar sus clausuras.
    dueno: str,
    // Los avisos: no impiden compilar.
    avisos: lista<str>,
    // Cada simbolo que ha declarado la funcion en curso, con su estado final:
    // al cerrar su bloque se guarda aqui como quedo.
    historia: lista<Simbolo>,
    // Lo que `--explicar` dice de cada funcion comprobada, en orden.
    informe: lista<str>,
    // La clausura que se esta comprobando, si hay una: lo que capturo con
    // `mut` y lo que de eso ha modificado de verdad.
    en_cierre: bool,
    capturas_mut: lista<str>,
    modificadas: lista<str>,
    // La plantilla de cada copia de generica que se esta comprobando, a la
    // par que `instanciando`.
    plantillas: lista<usize>,
    // Dentro de la guarda de un brazo: ahi no se mueve nada, porque se
    // evalua aunque el brazo no llegue a casar.
    en_guarda: usize,
    // Mirando el objeto de un `p.x` (no es usar `p` entera), y escribiendo
    // en un campo (no es leerlo).
    por_campo: usize,
    escribiendo: usize,
    // Los campos sacados de su struct en todo el programa, para el
    // generador: `archivo\tlinea\tp.a.b`.
    sacados: lista<str>,
}

fn estado(archivo: view, modulo: usize) -> Comprobacion {
    return Comprobacion { archivo: nuevo(archivo), modulo: modulo, simbolos: [],
        inicios: [], errores: [], retorno: vacio(), falible: false,
        en_condicional: 0, en_condicion_bucle: 0, en_bucle: 0,
        en_bucle_directo: 0, movidas_en_bucle: [], en_retorno: 0, instanciando: [],
        dueno: vacio(), avisos: [], historia: [], informe: [], en_cierre: false,
        capturas_mut: [], modificadas: [], plantillas: [], en_guarda: 0,
        por_campo: 0, escribiendo: 0, sacados: [] };
}

// Lo que el mensaje dice en vez de los nombres que puso el compilador: una
// copia de struct generico se llama como su plantilla, una clausura es una
// clausura, y una funcion renombrada, como se escribio.
fn legible(m: &Mundo, mensaje: view) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(mensaje) {
        let c = byte(mensaje, i);
        if I.es_de_nombre(c) && (i == 0 || !I.es_de_nombre(byte(mensaje, i - 1))) {
            var j = i;
            while j < largo(mensaje) && I.es_de_nombre(byte(mensaje, j)) { j = j + 1; }
            let palabra = rebanar(mensaje, i, j);
            let resto = rebanar(mensaje, j, largo(mensaje));
            if j < largo(mensaje) && byte(mensaje, j) == 60 && tiene(m.st_params, palabra)
            && !empieza_con(resto, "<...>") {
                // `Par<i64, usize>` -> `Par`: se salta lo que va entre angulos.
                let dicho = G.escrito(palabra);
                empujar(r, vista(dicho));
                var hondo = 0;
                var k = j;
                while k < largo(mensaje) {
                    if byte(mensaje, k) == 60 { hondo = hondo + 1; }
                    if byte(mensaje, k) == 62 && !(k > 0 && byte(mensaje, k - 1) == 45) {
                        hondo = hondo - 1;
                        if hondo == 0 { k = k + 1; break; }
                    }
                    k = k + 1;
                }
                i = k;
                continue;
            }
            // `ss_cierre_3` es la funcion de `Cierre_3`: tambien una clausura.
            var como_struct = vacio();
            if empieza_con(palabra, "ss_cierre_") {
                como_struct = $"Cierre_{rebanar(palabra, 10, largo(palabra))}";
            }
            let de_fn = largo(como_struct) > 0
            && largo(I.funcion_de_cierre(vista(como_struct))) > 0;
            if de_fn || (empieza_con(palabra, "Cierre_")
                && largo(I.funcion_de_cierre(palabra)) > 0) {
                empujar(r, "clausura");
                i = j;
                continue;
            }
            // Lo que choca con C lleva `ss_id_` delante: se dice como se
            // escribio.
            if tiene(m.bonitos, palabra) {
                let dicho = G.escrito(obtener(m.bonitos, palabra) sino "");
                empujar(r, vista(dicho));
                i = j;
                continue;
            }
            let dicho = G.escrito(palabra);
            empujar(r, vista(dicho));
            i = j;
            continue;
        }
        empujar(r, rebanar(mensaje, i, i + 1));
        i = i + 1;
    }
    return r;
}

fn error(c: mut Comprobacion, m: &Mundo, linea: usize, mensaje: view) {
    let claro = legible(m, mensaje);
    var todo = $"{c.archivo}:{linea}: {claro}";
    // Un error dentro de una generica no se entiende sin saber con que tipos
    // se la uso, ni desde donde: de dentro hacia fuera.
    var i = largo(c.instanciando);
    while i > 0 {
        i = i - 1;
        empujar(todo, "\n  ");
        empujar(todo, vista(c.instanciando[i]));
    }
    anadir(c.errores, todo);
}

// Un aviso no impide compilar. Dentro de una generica es el mismo por cada
// juego de tipos: se dice una vez.
fn aviso(c: mut Comprobacion, m: &Mundo, linea: usize, mensaje: view) {
    let claro = legible(m, mensaje);
    let todo = $"{c.archivo}:{linea}: {claro}";
    if largo(c.instanciando) > 0 && esta_entre(c.avisos, vista(todo)) { return; }
    anadir(c.avisos, todo);
}

fn abrir_ambito(c: mut Comprobacion) { anadir(c.inicios, largo(c.simbolos)); }

// Buscar de dentro hacia fuera. `largo(simbolos)` si no esta.
fn buscar_simbolo(c: &Comprobacion, nombre: view) -> usize {
    var i = largo(c.simbolos);
    while i > 0 {
        i = i - 1;
        if igual(vista(c.simbolos[i].nombre), nombre) { return i; }
    }
    return largo(c.simbolos);
}

fn existe(c: &Comprobacion, i: usize) -> bool { return i < largo(c.simbolos); }

fn soltar_prestamo(c: mut Comprobacion, i: usize, quien: view) {
    var quedan: lista<str> = [];
    var quitado = false;
    for p en c.simbolos[i].prestamos {
        if !quitado && igual(vista(p), quien) { quitado = true; continue; }
        anadir(quedan, copiar(p));
    }
    c.simbolos[i].prestamos = quedan;
}

// Al cerrar un ambito mueren sus vistas, y con ellas los prestamos que
// tenian sobre variables de fuera.
fn cerrar_ambito(c: mut Comprobacion) {
    if largo(c.inicios) == 0 { return; }
    let desde = c.inicios[largo(c.inicios) - 1];
    var muertos: lista<Simbolo> = [];
    var vivos: lista<Simbolo> = [];
    var i = 0;
    while i < largo(c.simbolos) {
        if i < desde { anadir(vivos, copiar(c.simbolos[i])); }
        else { anadir(muertos, copiar(c.simbolos[i])); }
        i = i + 1;
    }
    c.simbolos = vivos;
    for s en muertos {
        if s.historia < largo(c.historia) { c.historia[s.historia] = copiar(s); }
    }
    var otros: lista<usize> = [];
    var k = 0;
    while k + 1 < largo(c.inicios) {
        anadir(otros, c.inicios[k]);
        k = k + 1;
    }
    c.inicios = otros;
    // Solo lo que presta tiene duenios apuntados.
    for s en muertos {
        if largo(s.origenes) > 0 {
            for o en s.origenes {
                let d = buscar_simbolo(c, vista(o));
                if existe(c, d) && esta_entre(c.simbolos[d].prestamos, vista(s.nombre)) {
                    soltar_prestamo(c, d, vista(s.nombre));
                }
            }
        }
    }
}

// Tapar una variable de fuera es un error, como declarar dos veces la misma.
fn declarar_simbolo(c: mut Comprobacion, m: &Mundo, linea: usize, nombre: view, tipo: view,
    mutable: bool) -> usize {
    var desde = 0;
    if largo(c.inicios) > 0 { desde = c.inicios[largo(c.inicios) - 1]; }
    var en_este = false;
    var fuera = false;
    var i = 0;
    while i < largo(c.simbolos) {
        if igual(vista(c.simbolos[i].nombre), nombre) {
            if i >= desde { en_este = true; } else { fuera = true; }
        }
        i = i + 1;
    }
    if en_este {
        error(c, m, linea, $"`{nombre}` ya esta declarada en este bloque");
    } else if fuera {
        error(c, m, linea, $"`{nombre}` tapa a una variable del mismo nombre de un bloque de fuera. Usa otro nombre");
    }
    let nuevo_s = Simbolo { nombre: nuevo(nombre), tipo: nuevo(tipo),
        mutable: mutable, prestado: false, movida: false, movida_en: 0,
        entregada_en: 0, reasignada_directo: false,
        bucle_al_declarar: c.en_bucle, condicional_al_declarar: c.en_condicional, sacados: [],
        prestamos: [], origen: vacio(), origenes: [],
        procedencia: vacio(), leida: false, mutada: false, linea_decl: linea,
        es_param: false, historia: largo(c.historia), movida_a: vacio() };
    anadir(c.historia, copiar(nuevo_s));
    anadir(c.simbolos, nuevo_s);
    return largo(c.simbolos) - 1;
}

// ------------------------------------------------------------------
// Las reglas de propiedad
// ------------------------------------------------------------------

// Leer una variable. Falla si ya se movio.
fn leer(c: mut Comprobacion, m: &Mundo, linea: usize, i: usize) -> bool {
    c.simbolos[i].leida = true;
    if c.simbolos[i].movida {
        let n = copiar(c.simbolos[i].nombre);
        let cuando = c.simbolos[i].movida_en;
        error(c, m, linea, $"`{n}` ya se movio en la linea {cuando} y aqui se usa otra vez");
        return false;
    }
    return !a_medio_mover(c, m, linea, i);
}

// Si `i` tiene algun campo sacado y se usa entera, lo dice.
fn a_medio_mover(c: mut Comprobacion, m: &Mundo, linea: usize, i: usize) -> bool {
    if largo(c.simbolos[i].sacados) == 0 || c.por_campo > 0 { return false; }
    let n = copiar(c.simbolos[i].nombre);
    let primero = copiar(c.simbolos[i].sacados[0]);
    let ruta = antes_de_tab(vista(primero));
    let cuando = despues_de_tab(vista(primero));
    error(c, m, linea, $"`{n}` esta a medio mover: `{n}.{ruta}` se saco en la linea {cuando}. Dale otro valor antes de usarla entera, o usa solo sus otros campos");
    return true;
}

fn antes_de_tab(t: view) -> str {
    var i = 0;
    while i < largo(t) && byte(t, i) != 9 { i = i + 1; }
    return nuevo(rebanar(t, 0, i));
}

fn despues_de_tab(t: view) -> str {
    var i = 0;
    while i < largo(t) && byte(t, i) != 9 { i = i + 1; }
    if i >= largo(t) { return vacio(); }
    return nuevo(rebanar(t, i + 1, largo(t)));
}

fn es_reserva(n: view) -> bool {
    return igual(n, "intercambiar") || igual(n, "redimensionar");
}

// Por que no se puede tocar: prestamos vivos, o una reserva.
fn ocupada(c: &Comprobacion, i: usize) -> str {
    var prestamos: lista<str> = [];
    var reservas: lista<str> = [];
    for p en c.simbolos[i].prestamos {
        if es_reserva(vista(p)) { anadir(reservas, copiar(p)); }
        else { anadir(prestamos, copiar(p)); }
    }
    if largo(prestamos) > 0 {
        let l = lista_legible(prestamos);
        return $"esta prestada por {l}";
    }
    let n = vista(reservas[0]);
    if igual(n, "intercambiar") {
        return nuevo("esta reservada por `intercambiar` mientras se calcula el reemplazo");
    }
    return nuevo("esta reservada por `redimensionar` mientras se calcula el tamaño nuevo");
}

fn error_llego_prestado(c: mut Comprobacion, m: &Mundo, linea: usize, i: usize) {
    let n = copiar(c.simbolos[i].nombre);
    error(c, m, linea, $"`{n}` llego prestado: esta funcion no es su duenia y no puede entregarlo. Pasa una copia, o recibelo por valor");
}

// Consumir el valor de una variable duenia. `directo` es el `return x` que
// la entrega ahi mismo.
fn mover(c: mut Comprobacion, m: &Mundo, linea: usize, i: usize, directo: bool) {
    if c.en_guarda > 0 {
        let n = copiar(c.simbolos[i].nombre);
        error(c, m, linea, $"una guarda no mueve nada: `{n}` se moveria aunque el brazo no case. Presta, o usa `copiar(...)`");
        return;
    }
    if !leer(c, m, linea, i) { return; }
    if c.simbolos[i].prestado {
        error_llego_prestado(c, m, linea, i);
        return;
    }
    if c.en_bucle > c.simbolos[i].bucle_al_declarar && c.en_retorno == 0 {
        c.simbolos[i].reasignada_directo = false;
        if largo(c.movidas_en_bucle) > 0 {
            let k = largo(c.movidas_en_bucle) - 1;
            anadir(c.movidas_en_bucle[k], i);
            anadir(c.movidas_en_bucle[k], linea);
        }
    }
    if largo(c.simbolos[i].prestamos) > 0 {
        let n = copiar(c.simbolos[i].nombre);
        let por = ocupada(c, i);
        error(c, m, linea, $"no se puede mover `{n}`: {por}");
        return;
    }
    if c.en_retorno > 0 && directo {
        c.simbolos[i].entregada_en = linea;
        return;
    }
    c.simbolos[i].movida = true;
    c.simbolos[i].movida_en = linea;
}

fn error_no_mutable(c: mut Comprobacion, m: &Mundo, linea: usize, i: usize) {
    let n = copiar(c.simbolos[i].nombre);
    let de_tipo = sin_prestamo(vista(c.simbolos[i].tipo));
    if esta_entre(m.cierres_mut, vista(de_tipo)) {
        // Lo que se modifica es la clausura: se la llama, y guarda lo que
        // capturo con `mut`.
        var arreglo = nuevo("declarala con `var`");
        if c.simbolos[i].es_param {
            arreglo = nuevo("recibela con `mut` delante del tipo");
            // En una generica, el tipo que se escribio: `f: mut F`.
            if largo(c.plantillas) > 0 {
                let k = c.plantillas[largo(c.plantillas) - 1];
                for p en m.funciones[k].params {
                    if igual(vista(p.nombre), vista(n)) {
                        arreglo = $"recibela como `{n}: mut {p.tipo}`";
                    }
                }
            }
        }
        error(c, m, linea, $"`{n}` es una clausura que modifica lo que capturo, y llamarla la modifica: {arreglo}");
    } else if c.simbolos[i].prestado {
        let t = copiar(c.simbolos[i].tipo);
        error(c, m, linea, $"`{n}` llego prestado solo para leer (`&`): para modificarlo, recibelo como `mut {t}`");
    } else {
        error(c, m, linea, $"`{n}` se declaro con `let` y no se puede modificar; usa `var`");
    }
}

fn error_solo_lectura(c: mut Comprobacion, m: &Mundo, linea: usize, nombre: view, t: view) {
    let dentro = T.apuntado(t);
    error(c, m, linea, $"`{nombre}` es un prestamo de solo lectura (`{t}`): para modificar lo que apunta hace falta `&mut {dentro}`");
}

// Si `lugar` es algo que capturo la clausura que se comprueba, lo apunta
// como modificado. Si se capturo sin `mut`, lo dice y devuelve `true`: el
// error ya esta dado.
fn escribe_en_captura(c: mut Comprobacion, m: &Mundo, lugar: &P.Nodo) -> bool {
    if !c.en_cierre { return false; }
    var campo = vacio();
    var x = copiar(lugar);
    while (igual(vista(x.clase), "campo") || igual(vista(x.clase), "indice"))
    && largo(x.hijos) > 0 {
        if igual(vista(x.clase), "campo") && igual(vista(x.hijos[0].clase), "variable")
        && igual(vista(x.hijos[0].texto), "_ss_entorno") {
            campo = copiar(x.texto);
        }
        let dentro = copiar(x.hijos[0]);
        x = dentro;
    }
    if largo(campo) == 0 { return false; }
    if esta_entre(c.capturas_mut, vista(campo)) {
        if !esta_entre(c.modificadas, vista(campo)) { anadir(c.modificadas, copiar(campo)); }
        return false;
    }
    error(c, m, lugar.linea, $"`{campo}` se capturo para leer: para modificarlo dentro de la clausura, capturalo con `fn[mut {campo}]`");
    return true;
}

// Modificar una variable en el sitio. `lugar` es lo que se modifica.
fn mutar(c: mut Comprobacion, m: &Mundo, lugar: &P.Nodo, linea: usize, i: usize,
    por_referencia: bool) {
    if escribe_en_captura(c, m, lugar) { return; }
    c.simbolos[i].mutada = true;
    if c.simbolos[i].movida {
        let n = copiar(c.simbolos[i].nombre);
        let cuando = c.simbolos[i].movida_en;
        error(c, m, linea, $"`{n}` ya se movio en la linea {cuando} y aqui se usa otra vez");
        return;
    }
    // Modificar un campo no es usar el struct entero.
    let por_campo = igual(vista(lugar.clase), "campo");
    if por_campo { c.por_campo = c.por_campo + 1; }
    let a_medias = a_medio_mover(c, m, linea, i);
    if por_campo { c.por_campo = c.por_campo - 1; }
    if a_medias { return; }
    let t = copiar(c.simbolos[i].tipo);
    let n = copiar(c.simbolos[i].nombre);
    if por_referencia && T.es_referencia(vista(t)) {
        if !es_referencia_mutable(vista(t)) {
            error_solo_lectura(c, m, linea, vista(n), vista(t));
        } else if largo(c.simbolos[i].prestamos) > 0 {
            let por = ocupada(c, i);
            error(c, m, linea, $"no se puede modificar `{n}`: {por}");
        }
        return;
    }
    if !c.simbolos[i].mutable {
        error_no_mutable(c, m, linea, i);
        return;
    }
    if largo(c.simbolos[i].prestamos) > 0 {
        let por = ocupada(c, i);
        error(c, m, linea, $"no se puede modificar `{n}`: {por}");
    }
}

// ------------------------------------------------------------------
// Caminos que se excluyen: fotos del estado de los movimientos
// ------------------------------------------------------------------

// Cuatro numeros por simbolo vivo: movida, en que linea, entregada, y si se
// le dio otro valor al nivel directo del bucle.
fn foto(c: &Comprobacion) -> lista<usize> {
    var f: lista<usize> = [];
    for s en c.simbolos {
        if s.movida { anadir(f, 1); } else { anadir(f, 0); }
        anadir(f, s.movida_en);
        anadir(f, s.entregada_en);
        if s.reasignada_directo { anadir(f, 1); } else { anadir(f, 0); }
    }
    return f;
}

fn restaurar_foto(c: mut Comprobacion, f: &lista<usize>) {
    var i = 0;
    while i < largo(c.simbolos) && 4 * i + 3 < largo(f) {
        c.simbolos[i].movida = f[4 * i] == 1;
        c.simbolos[i].movida_en = f[4 * i + 1];
        c.simbolos[i].entregada_en = f[4 * i + 2];
        c.simbolos[i].reasignada_directo = f[4 * i + 3] == 1;
        i = i + 1;
    }
}

// Lo que sobrevive a dos caminos: movido en uno cuenta como movido.
fn juntar_ramas(c: mut Comprobacion, a: &lista<usize>, b: &lista<usize>) {
    var i = 0;
    while i < largo(c.simbolos) && 4 * i + 3 < largo(a) {
        var mb = a[4 * i];
        var lb = a[4 * i + 1];
        var eb = a[4 * i + 2];
        var rb = a[4 * i + 3];
        if 4 * i + 3 < largo(b) {
            mb = b[4 * i];
            lb = b[4 * i + 1];
            eb = b[4 * i + 2];
            rb = b[4 * i + 3];
        }
        let ma = a[4 * i];
        c.simbolos[i].movida = ma == 1 || mb == 1;
        if ma == 1 { c.simbolos[i].movida_en = a[4 * i + 1]; }
        else { c.simbolos[i].movida_en = lb; }
        if a[4 * i + 2] != 0 { c.simbolos[i].entregada_en = a[4 * i + 2]; }
        else { c.simbolos[i].entregada_en = eb; }
        c.simbolos[i].reasignada_directo = a[4 * i + 3] == 1 || rb == 1;
        i = i + 1;
    }
}

fn clase_de(n: &P.Nodo) -> str { return copiar(n.clase); }

// El bloque no continua: sale por `return`, `falla`, `break` o `continue`.
fn bloque_termina(n: &P.Nodo) -> bool {
    if largo(n.hijos) == 0 { return false; }
    let ultima = vista(n.hijos[largo(n.hijos) - 1].clase);
    return igual(ultima, "retorno") || igual(ultima, "falla")
    || igual(ultima, "romper") || igual(ultima, "continuar");
}

// Todos los caminos de este bloque salen de la funcion.
fn siempre_sale(n: &P.Nodo) -> bool {
    if largo(n.hijos) == 0 { return false; }
    let k = largo(n.hijos) - 1;
    let clase = vista(n.hijos[k].clase);
    if igual(clase, "retorno") || igual(clase, "falla") { return true; }
    if igual(clase, "si") && largo(n.hijos[k].hijos) == 3 {
        return siempre_sale(n.hijos[k].hijos[1]) && siempre_sale_rama(n.hijos[k].hijos[2]);
    }
    return false;
}

// La rama `else` puede ser un bloque o, en `else if`, otra sentencia.
fn siempre_sale_rama(n: &P.Nodo) -> bool {
    if igual(vista(n.clase), "bloque") { return siempre_sale(n); }
    var b = P.rama("bloque", n.linea);
    anadir(b.hijos, copiar(n));
    return siempre_sale(b);
}

fn termina_rama(n: &P.Nodo) -> bool {
    if igual(vista(n.clase), "bloque") { return bloque_termina(n); }
    let clase = vista(n.clase);
    return igual(clase, "retorno") || igual(clase, "falla")
    || igual(clase, "romper") || igual(clase, "continuar");
}

// La variable en la raiz de `x`, `p.a.b` o `v[i][j]`.
fn variable_base(n: &P.Nodo) -> str {
    let clase = vista(n.clase);
    if igual(clase, "variable") { return copiar(n.texto); }
    if (igual(clase, "campo") || igual(clase, "indice")) && largo(n.hijos) > 0 {
        return variable_base(n.hijos[0]);
    }
    return vacio();
}

// ------------------------------------------------------------------
// De donde sale la memoria de una vista
// ------------------------------------------------------------------

fn procedencia_de(c: &Comprobacion, m: &Mundo, n: &P.Nodo) -> str {
    let clase = vista(n.clase);
    if igual(clase, "try") && largo(n.hijos) > 0 { return procedencia_de(c, m, n.hijos[0]); }
    if igual(clase, "sino") && largo(n.hijos) == 2 {
        let a = procedencia_de(c, m, n.hijos[0]);
        let b = procedencia_de(c, m, n.hijos[1]);
        if igual(vista(a), "local") || igual(vista(b), "local") { return nuevo("local"); }
        if igual(vista(a), "parametro") || igual(vista(b), "parametro") {
            return nuevo("parametro");
        }
        return nuevo("estatico");
    }
    if igual(clase, "cadena") { return nuevo("estatico"); }
    if igual(clase, "variable") {
        let i = buscar_simbolo(c, vista(n.texto));
        if !existe(c, i) { return nuevo("local"); }
        if igual(vista(c.simbolos[i].tipo), "view") || es_prestado_st(m, vista(c.simbolos[i].tipo)) {
            if largo(c.simbolos[i].procedencia) > 0 { return copiar(c.simbolos[i].procedencia); }
            return nuevo("local");
        }
        return nuevo("local");
    }
    if igual(clase, "literal_struct") {
        // Lo peor de lo que prestan sus campos.
        let st = I.sin_modulo(vista(n.texto));
        var peor = nuevo("estatico");
        for h en n.hijos {
            if largo(h.hijos) == 0 { continue; }
            if !presta_tipo(m, tipo_del_campo(m, vista(st), vista(h.texto))) { continue; }
            let p = procedencia_de(c, m, h.hijos[0]);
            if igual(vista(p), "local") { return nuevo("local"); }
            if igual(vista(p), "parametro") { peor = nuevo("parametro"); }
        }
        return peor;
    }
    if igual(clase, "campo") {
        let raiz = variable_base(n);
        let i = buscar_simbolo(c, vista(raiz));
        let tc = tipo_simple(c, m, n);
        if largo(raiz) > 0 && existe(c, i) && presta_tipo(m, vista(tc)) {
            let t = copiar(c.simbolos[i].tipo);
            if c.simbolos[i].prestado || T.es_referencia(vista(t)) { return nuevo("parametro"); }
            if es_prestado_st(m, vista(t)) {
                if largo(c.simbolos[i].procedencia) > 0 { return copiar(c.simbolos[i].procedencia); }
                return nuevo("local");
            }
        }
        return nuevo("local");
    }
    if igual(clase, "llamada") {
        let nombre = resolver_nombre(c_tipos_vacio(), vista(n.texto));
        let nn = vista(nombre);
        if igual(nn, "argumento") { return nuevo("estatico"); }
        if (igual(nn, "vista") || igual(nn, "obtener") || igual(nn, "obtener_mut"))
        && largo(n.hijos) > 0 {
            let base = variable_base(n.hijos[0]);
            let i = buscar_simbolo(c, vista(base));
            if largo(base) > 0 && existe(c, i) && c.simbolos[i].prestado {
                return nuevo("parametro");
            }
            return nuevo("local");
        }
        if igual(nn, "nuevo") || igual(nn, "vacio") { return nuevo("local"); }
        if igual(nn, "rebanar") {
            if largo(n.hijos) > 0 { return procedencia_de(c, m, n.hijos[0]); }
            return nuevo("local");
        }
        if igual(nn, "copiar") && largo(n.hijos) == 1 {
            let tc = tipo_simple(c, m, n.hijos[0]);
            if presta_tipo(m, vista(tc)) { return procedencia_de(c, m, n.hijos[0]); }
        }
        let k = buscar_funcion(m, nn) sino largo(m.funciones);
        if k >= largo(m.funciones) || tiene_sueltos(m.funciones[k]) { return nuevo("local"); }
        let ret = copiar(m.funciones[k].retorno);
        if !presta_tipo(m, vista(ret)) || T.es_referencia(vista(ret)) { return nuevo("local"); }
        var peor = nuevo("estatico");
        var i = 0;
        while i < largo(n.hijos) && i < largo(m.funciones[k].params) {
            var p = vacio();
            let pt = vista(m.funciones[k].params[i].tipo);
            if igual(pt, "view")
            || (!prestado(m.funciones[k].params[i]) && es_prestado_st(m, pt)) {
                p = procedencia_de(c, m, n.hijos[i]);
            } else if prestado(m.funciones[k].params[i]) {
                let base = variable_base(n.hijos[i]);
                let j = buscar_simbolo(c, vista(base));
                if largo(base) > 0 && existe(c, j) && c.simbolos[j].prestado {
                    p = nuevo("parametro");
                } else {
                    p = nuevo("local");
                }
            }
            if igual(vista(p), "local") { return nuevo("local"); }
            if igual(vista(p), "parametro") { peor = nuevo("parametro"); }
            i = i + 1;
        }
        return peor;
    }
    return nuevo("local");
}

// Un contexto sin nada: para resolver nombres que no dependen del modulo.
fn c_tipos_vacio() -> I.Contexto { return I.contexto(); }

// De que variable duenia sale una vista, si sale de alguna: la primera de
// las posibles.
fn origen_de(c: &Comprobacion, m: &Mundo, n: &P.Nodo) -> str {
    for o en origenes_de(c, m, n) {
        if !igual(vista(o), "<temporal>") { return copiar(o); }
    }
    return vacio();
}

fn juntar_origenes(salida: mut lista<str>, de: &lista<str>) {
    for x en de {
        if largo(x) > 0 && !esta_entre(salida, vista(x)) { anadir(salida, copiar(x)); }
    }
}

// Todas las variables duenias de las que puede venir una vista, en orden y
// sin repetir. `<temporal>` si puede venir de un valor sin nombre, recien
// hecho, que se libera al acabar la sentencia: una vista suya no se guarda.
fn origenes_de(c: &Comprobacion, m: &Mundo, n: &P.Nodo) -> lista<str> {
    var salida: lista<str> = [];
    let clase = vista(n.clase);
    if igual(clase, "try") && largo(n.hijos) > 0 { return origenes_de(c, m, n.hijos[0]); }
    if igual(clase, "sino") && largo(n.hijos) == 2 {
        juntar_origenes(salida, origenes_de(c, m, n.hijos[0]));
        juntar_origenes(salida, origenes_de(c, m, n.hijos[1]));
        return salida;
    }
    if igual(clase, "llamada") {
        let nombre = I.sin_modulo(vista(n.texto));
        let nn = vista(nombre);
        if igual(nn, "vista") && largo(n.hijos) > 0 {
            let base = variable_base(n.hijos[0]);
            if largo(base) > 0 { anadir(salida, base); }
            return salida;
        }
        if igual(nn, "rebanar") && largo(n.hijos) > 0 { return origenes_de(c, m, n.hijos[0]); }
        if (igual(nn, "obtener") || igual(nn, "obtener_mut")) && largo(n.hijos) > 0 {
            let base = variable_base(n.hijos[0]);
            if largo(base) > 0 { anadir(salida, base); } else { anadir(salida, nuevo("<temporal>")); }
            return salida;
        }
        if igual(nn, "copiar") && largo(n.hijos) == 1 {
            // La copia de algo que presta presta de lo mismo. El tipo va
            // aparte: dentro del `&&` se calcularia siempre.
            let tc = tipo_simple(c, m, n.hijos[0]);
            if presta_tipo(m, vista(tc)) { return origenes_de(c, m, n.hijos[0]); }
        }
        // Una funcion que devuelve `view` solo puede devolver algo derivado
        // de lo que le prestaron. No se sabe de cual, asi que de todos.
        let k = funcion_vista(c, m, vista(n.texto));
        if k < largo(m.funciones) {
            let ret = vista(m.funciones[k].retorno);
            if largo(ret) > 0 && !T.es_referencia(ret)
            && (presta_tipo(m, ret) || lleva_suelto(ret, m.funciones[k].tipo_params)) {
                juntar_origenes(salida, origenes_de_args(c, m, n, 0, k));
            }
            return salida;
        }
        let iv = buscar_simbolo(c, vista(n.texto));
        if existe(c, iv) {
            // Una clausura: el entorno va delante, prestado, y lo demas como
            // en su funcion.
            let tv = sin_prestamo(vista(c.simbolos[iv].tipo));
            let de_cierre = I.funcion_de_cierre(vista(tv));
            let kc = buscar_funcion(m, vista(de_cierre)) sino largo(m.funciones);
            if largo(de_cierre) > 0 && kc < largo(m.funciones) {
                let ret = vista(m.funciones[kc].retorno);
                if presta_tipo(m, ret) && !T.es_referencia(ret) {
                    var entorno: lista<str> = [];
                    anadir(entorno, copiar(n.texto));
                    juntar_origenes(salida, entorno);
                    juntar_origenes(salida, origenes_de_args(c, m, n, 1, kc));
                }
            } else if T.es_funcion(vista(c.simbolos[iv].tipo)) {
                // Un puntero a funcion: su tipo dice lo mismo que la firma.
                juntar_origenes(salida, origenes_de_puntero(c, m, n, vista(c.simbolos[iv].tipo)));
            }
        }
        return salida;
    }
    if igual(clase, "si_expr") && largo(n.hijos) == 3 {
        // Puede ser cualquiera de las dos ramas.
        juntar_origenes(salida, origenes_de(c, m, n.hijos[1]));
        juntar_origenes(salida, origenes_de(c, m, n.hijos[2]));
        return salida;
    }
    if igual(clase, "match") && largo(n.hijos) > 0 {
        // Lo que da cada brazo; y si da algo que atrapo el patron, el valor
        // mirado: lo atrapado es un prestamo suyo.
        var mirado: lista<str> = [];
        var visto = false;
        var k = 1;
        while k < largo(n.hijos) {
            for h en n.hijos[k].hijos {
                if !igual(vista(h.clase), "retorno") || largo(h.hijos) != 1 { continue; }
                juntar_origenes(salida, origenes_de(c, m, h.hijos[0]));
                var atrapados: lista<str> = [];
                atrapados_de(n.hijos[k], atrapados);
                if largo(atrapados) > 0 && menciona(h.hijos[0], atrapados) {
                    if !visto {
                        mirado = origenes_mirado(c, m, n.hijos[0]);
                        if largo(mirado) == 0 { anadir(mirado, nuevo("<temporal>")); }
                        visto = true;
                    }
                    juntar_origenes(salida, mirado);
                }
            }
            k = k + 1;
        }
        return salida;
    }
    if igual(clase, "variable") {
        let i = buscar_simbolo(c, vista(n.texto));
        if existe(c, i) && (igual(vista(c.simbolos[i].tipo), "view")
            || es_prestado_st(m, vista(c.simbolos[i].tipo))) {
            return copiar(c.simbolos[i].origenes);
        }
        if existe(c, i) && igual(vista(c.simbolos[i].tipo), "str") {
            anadir(salida, copiar(n.texto));
        }
    }
    if igual(clase, "literal_struct") {
        // Un struct que presta, de lo que prestan sus campos.
        let st = I.sin_modulo(vista(n.texto));
        for h en n.hijos {
            if largo(h.hijos) == 0 { continue; }
            if !presta_tipo(m, tipo_del_campo(m, vista(st), vista(h.texto))) { continue; }
            var de = origenes_de(c, m, h.hijos[0]);
            if largo(de) == 0 && !igual(vista(h.hijos[0].clase), "variable")
            && es_local(procedencia_de(c, m, h.hijos[0])) {
                anadir(de, nuevo("<temporal>"));
            }
            juntar_origenes(salida, de);
        }
        return salida;
    }
    if igual(clase, "campo") || igual(clase, "indice") {
        // Un sitio dentro de una variable: presta de ella. Si es la vista de
        // un struct que presta, de lo mismo que el. Si la variable llego
        // prestada, la memoria es de quien llama.
        let raiz = variable_base(n);
        let i = buscar_simbolo(c, vista(raiz));
        if largo(raiz) == 0 || !existe(c, i) { return salida; }
        let t = copiar(c.simbolos[i].tipo);
        if c.simbolos[i].prestado || T.es_referencia(vista(t)) { return salida; }
        let tc = tipo_simple(c, m, n);
        if es_prestado_st(m, vista(t)) && presta_tipo(m, vista(tc)) {
            return copiar(c.simbolos[i].origenes);
        }
        anadir(salida, copiar(raiz));
    }
    return salida;
}

// La funcion de un nombre como la ve el modulo que se comprueba. Sin su
// contexto, por el nombre sin modulo.
fn funcion_vista(c: &Comprobacion, m: &Mundo, escrito: view) -> usize {
    if c.modulo < largo(m.contextos) {
        return funcion_llamada(m, m.contextos[c.modulo], escrito);
    }
    let corto = I.sin_modulo(escrito);
    return buscar_funcion(m, vista(corto)) sino largo(m.funciones);
}

// Si el tipo `t` nombra alguno de los parametros de tipo `sueltos`.
fn lleva_suelto(t: view, sueltos: &lista<str>) -> bool {
    var i = 0;
    while i < largo(t) {
        if I.es_de_nombre(byte(t, i)) {
            var j = i;
            while j < largo(t) && I.es_de_nombre(byte(t, j)) { j = j + 1; }
            if esta_entre(sueltos, rebanar(t, i, j)) { return true; }
            i = j;
        } else {
            i = i + 1;
        }
    }
    return false;
}

// Lo que presta el resultado de llamar a `m.funciones[k]` con los
// argumentos de `n`, desde el parametro `desde` (en una clausura, el 0 es su
// entorno). En una generica cuenta tambien todo parametro cuyo tipo lleve
// uno suelto: aqui no se sabe con que tipos se copio, salvo que el argumento
// sea un `str`, que no presta de nada.
fn origenes_de_args(c: &Comprobacion, m: &Mundo, n: &P.Nodo, desde: usize,
    k: usize) -> lista<str> {
    var salida: lista<str> = [];
    var i = desde;
    while i < largo(m.funciones[k].params) && i - desde < largo(n.hijos) {
        let arg = copiar(n.hijos[i - desde]);
        let pt = vista(m.funciones[k].params[i].tipo);
        let del_arg = tipo_simple(c, m, arg);
        let suelto = lleva_suelto(pt, m.funciones[k].tipo_params)
        && !igual(vista(del_arg), "str");
        if igual(pt, "view")
        || (!prestado(m.funciones[k].params[i]) && (es_prestado_st(m, pt) || suelto)) {
            var de_arg = origenes_de(c, m, arg);
            if !suelto && largo(de_arg) == 0 && !igual(vista(arg.clase), "variable")
            && es_local(procedencia_de(c, m, arg)) {
                // Un `str` recien hecho donde se pide una vista.
                anadir(de_arg, nuevo("<temporal>"));
            }
            juntar_origenes(salida, de_arg);
        } else if prestado(m.funciones[k].params[i]) {
            let base = variable_base(arg);
            var de_arg: lista<str> = [];
            if largo(base) > 0 { anadir(de_arg, copiar(base)); } else { anadir(de_arg, nuevo("<temporal>")); }
            juntar_origenes(salida, de_arg);
            // Si lo prestado presta a su vez, tambien de lo suyo.
            let j = buscar_simbolo(c, vista(base));
            if largo(base) > 0 && existe(c, j) && es_prestado_st(m, vista(c.simbolos[j].tipo)) {
                juntar_origenes(salida, c.simbolos[j].origenes);
            }
        }
        i = i + 1;
    }
    return salida;
}

// Lo que presta el resultado de llamar a una variable que guarda una funcion:
// su tipo dice lo mismo que una firma.
fn origenes_de_puntero(c: &Comprobacion, m: &Mundo, n: &P.Nodo, tipo: view) -> lista<str> {
    var salida: lista<str> = [];
    let partes = T.partes_de_funcion(tipo);
    if largo(partes) == 0 { return salida; }
    if !presta_tipo(m, vista(partes[largo(partes) - 1])) { return salida; }
    var i = 0;
    while i + 1 < largo(partes) && i < largo(n.hijos) {
        let pt = vista(partes[i]);
        if T.es_referencia(pt) {
            let base = variable_base(n.hijos[i]);
            var de_arg: lista<str> = [];
            if largo(base) > 0 { anadir(de_arg, copiar(base)); } else { anadir(de_arg, nuevo("<temporal>")); }
            juntar_origenes(salida, de_arg);
            let j = buscar_simbolo(c, vista(base));
            if largo(base) > 0 && existe(c, j) && presta_tipo(m, vista(c.simbolos[j].tipo)) {
                juntar_origenes(salida, c.simbolos[j].origenes);
            }
        } else if presta_tipo(m, pt) {
            var de_arg = origenes_de(c, m, n.hijos[i]);
            if largo(de_arg) == 0 && !igual(vista(n.hijos[i].clase), "variable")
            && es_local(procedencia_de(c, m, n.hijos[i])) {
                anadir(de_arg, nuevo("<temporal>"));
            }
            juntar_origenes(salida, de_arg);
        }
        i = i + 1;
    }
    return salida;
}

// De que variables es lo que atrapa un patron: de la del valor mirado, y si
// esa es un prestamo, tambien de lo que presta.
fn origenes_mirado(c: &Comprobacion, m: &Mundo, valor: &P.Nodo) -> lista<str> {
    var salida: lista<str> = [];
    let base = variable_base(valor);
    let i = buscar_simbolo(c, vista(base));
    if largo(base) == 0 || !existe(c, i) { return salida; }
    anadir(salida, copiar(base));
    if presta_tipo(m, vista(c.simbolos[i].tipo)) {
        juntar_origenes(salida, c.simbolos[i].origenes);
    }
    return salida;
}

// Los nombres que atrapa el patron de un brazo, a cualquier hondura.
fn atrapados_de(b: &P.Nodo, salida: mut lista<str>) {
    for h en b.hijos {
        if igual(vista(h.clase), "atrapa") && !igual(vista(h.texto), "_") {
            anadir(salida, copiar(h.texto));
        } else if igual(vista(h.clase), "patron") {
            atrapados_de(h, salida);
        }
    }
}

// Si en `n` se lee alguna de estas variables.
fn menciona(n: &P.Nodo, nombres: &lista<str>) -> bool {
    if igual(vista(n.clase), "variable") && esta_entre(nombres, vista(n.texto)) { return true; }
    for h en n.hijos {
        if menciona(h, nombres) { return true; }
    }
    return false;
}

// Las variables que un argumento deja prestadas mientras dura la llamada,
// cuando va a un sitio que presta (`view`, un struct que presta). Un `str`
// suelto donde se pide `view` se presta entero; una vista con nombre ya
// tiene sus prestamos apuntados en sus duenios.
fn prestados_por(c: &Comprobacion, m: &Mundo, arg: &P.Nodo, t: view) -> lista<str> {
    var salida: lista<str> = [];
    let clase = vista(arg.clase);
    if igual(clase, "variable") {
        let i = buscar_simbolo(c, vista(arg.texto));
        if existe(c, i) {
            let limpio = sin_prestamo(vista(c.simbolos[i].tipo));
            if igual(vista(limpio), "str") { anadir(salida, copiar(arg.texto)); }
        }
        return salida;
    }
    let limpio = sin_prestamo(t);
    if igual(vista(limpio), "str") && (igual(clase, "campo") || igual(clase, "indice")) {
        let base = variable_base(arg);
        if largo(base) > 0 { anadir(salida, base); }
        return salida;
    }
    for o en origenes_de(c, m, arg) {
        if !igual(vista(o), "<temporal>") { anadir(salida, copiar(o)); }
    }
    return salida;
}

// El tipo de un campo de un struct, o vacio.
fn tipo_del_campo(m: &Mundo, st: view, campo_n: view) -> str {
    let ns = campos_nombres(m, st);
    let ts = campos_tipos(m, st);
    var i = 0;
    while i < largo(ns) && i < largo(ts) {
        if igual(vista(ns[i]), campo_n) { return copiar(ts[i]); }
        i = i + 1;
    }
    return vacio();
}

// El tipo de una variable o de un campo, sin comprobar nada.
fn tipo_simple(c: &Comprobacion, m: &Mundo, n: &P.Nodo) -> str {
    if igual(vista(n.clase), "variable") {
        let i = buscar_simbolo(c, vista(n.texto));
        if existe(c, i) { return sin_prestamo(vista(c.simbolos[i].tipo)); }
        return vacio();
    }
    if igual(vista(n.clase), "campo") && largo(n.hijos) > 0 {
        let base = tipo_simple(c, m, n.hijos[0]);
        if largo(base) == 0 || !es_struct(m, vista(base)) { return vacio(); }
        return tipo_del_campo(m, vista(base), vista(n.texto));
    }
    return vacio();
}

fn es_local(procedencia: str) -> bool { return igual(vista(procedencia), "local"); }

// En que bloque esta declarado el simbolo `i`: 0 es el de fuera.
fn nivel_de_simbolo(c: &Comprobacion, i: usize) -> usize {
    var n = 0;
    var k = 0;
    while k < largo(c.inicios) {
        if c.inicios[k] <= i { n = k; }
        k = k + 1;
    }
    return n;
}

// La vista `i` pasa a apuntar a lo que da `valor`: cada duenio queda
// prestado mientras ella viva, y tiene que vivir al menos lo mismo. Lo que
// ya prestaba lo sigue prestando: si la asignacion va en una rama, la otra
// puede no haberla hecho.
fn apuntar(c: mut Comprobacion, m: &Mundo, linea: usize, i: usize, valor: &P.Nodo) {
    let nuevos = origenes_de(c, m, valor);
    let nombre = copiar(c.simbolos[i].nombre);
    if esta_entre(nuevos, "<temporal>") {
        error(c, m, linea, $"`{nombre}` apuntaria a un valor temporal, que se libera al acabar esta sentencia: guarda ese valor en una variable y presta de ella");
    }
    let suyo = nivel_de_simbolo(c, i);
    for o en nuevos {
        if igual(vista(o), "<temporal>") || esta_entre(c.simbolos[i].origenes, vista(o)) { continue; }
        let d = buscar_simbolo(c, vista(o));
        if !existe(c, d) { continue; }
        if nivel_de_simbolo(c, d) > suyo {
            error(c, m, linea, $"`{nombre}` vive mas que `{o}`: `{o}` muere al cerrar su bloque y `{nombre}` seguiria apuntando a ella. Declara `{o}` fuera del bloque, o haz de `{nombre}` un `str` con `nuevo(...)`");
            continue;
        }
        anadir(c.simbolos[i].origenes, copiar(o));
        anadir(c.simbolos[d].prestamos, copiar(nombre));
    }
    if largo(c.simbolos[i].origen) == 0 && largo(c.simbolos[i].origenes) > 0 {
        c.simbolos[i].origen = copiar(c.simbolos[i].origenes[0]);
    }
}

// ------------------------------------------------------------------
// Literales que no caben
// ------------------------------------------------------------------

fn comprobar_literal(c: mut Comprobacion, m: &Mundo, n: &P.Nodo, destino: view) {
    let clase = vista(n.clase);
    if igual(clase, "binaria") && largo(n.hijos) == 2 {
        let op_b = vista(n.texto);
        // Los numeros escritos son decimales aqui, y con decimales no hay
        // resto ni bits.
        if es_decimal(destino) && largo(I.literal_de(n)) > 0
        && (igual(op_b, "%") || igual(op_b, "&") || igual(op_b, "|")
            || igual(op_b, "^") || igual(op_b, "<<") || igual(op_b, ">>")) {
            if igual(op_b, "%") {
                error(c, m, n.linea, "`%` es el resto de una division entera; con decimales no tiene un significado unico");
            } else {
                error(c, m, n.linea, $"`{op_b}` trabaja sobre los bits de un entero, recibio `{destino}` y `{destino}`");
            }
            return;
        }
        comprobar_literal(c, m, n.hijos[0], destino);
        let op = vista(n.texto);
        if igual(op, "<<") || igual(op, ">>") {
            comprobar_literal(c, m, n.hijos[1], "usize");
        } else {
            comprobar_literal(c, m, n.hijos[1], destino);
        }
        return;
    }
    // Cada rama que sea un numero escrito tiene que caber.
    if igual(clase, "si_expr") && largo(n.hijos) == 3 {
        comprobar_literal(c, m, n.hijos[1], destino);
        comprobar_literal(c, m, n.hijos[2], destino);
        return;
    }
    var negativo = false;
    var lit = copiar(n);
    if igual(clase, "unaria") && igual(vista(n.texto), "-") && largo(n.hijos) == 1 {
        let hc = vista(n.hijos[0].clase);
        if igual(hc, "entero") || igual(hc, "decimal") {
            negativo = true;
            lit = copiar(n.hijos[0]);
        }
    }
    var signo = vacio();
    if negativo { signo = nuevo("-"); }
    if igual(vista(lit.clase), "entero") {
        let valor = G.sin_ceros_izquierda(vista(lit.texto));
        var cabe = true;
        if es_tipo_entero(destino) {
            cabe = G.cabe_literal_entero(valor, destino, negativo);
        } else if es_decimal(destino) {
            cabe = G.entero_exacto_en(valor, destino);
        } else {
            return;
        }
        if !cabe {
            var exacto = vacio();
            if es_decimal(destino) { exacto = nuevo(" sin perder precision"); }
            error(c, m, n.linea, $"el literal `{signo}{valor}` no cabe en `{destino}`{exacto}");
        }
        return;
    }
    if igual(vista(lit.clase), "decimal") && es_decimal(destino) {
        if !G.cabe_literal_decimal(vista(lit.texto), destino) {
            error(c, m, n.linea, $"el literal `{signo}{lit.texto}` no cabe en `{destino}` como numero finito");
        }
    }
}

// ------------------------------------------------------------------
// Genericas: que tipos pone cada llamada
// ------------------------------------------------------------------

fn es_param_de_tipo(sueltos: &lista<str>, t: view) -> bool { return esta_entre(sueltos, t); }

// `lista<T>` contra `lista<str>` liga `T` a `str`. Falso si contradice lo que
// ya estaba ligado.
fn unificar_tipo(patron: view, dado: view, sueltos: &lista<str>,
    lig: mut mapa<str, str>) -> bool {
    if largo(patron) == 0 || largo(dado) == 0 { return true; }
    if es_param_de_tipo(sueltos, patron) {
        if !tiene(lig, patron) {
            poner(lig, patron, nuevo(dado));
            // El orden en que se ligan es el del mensaje de una copia.
            let orden = nuevo(obtener(lig, "\t") sino "");
            poner(lig, "\t", $"{orden}{patron}\t");
            return true;
        }
        let previo = obtener(lig, patron) sino "";
        return igual(previo, dado);
    }
    if igual(patron, dado) { return true; }
    if empieza_con(patron, "&mut ") {
        return empieza_con(dado, "&mut ")
        && unificar_tipo(rebanar(patron, 5, largo(patron)), rebanar(dado, 5, largo(dado)),
            sueltos, lig);
    }
    if empieza_con(patron, "&") {
        return empieza_con(dado, "&")
        && unificar_tipo(rebanar(patron, 1, largo(patron)), rebanar(dado, 1, largo(dado)),
            sueltos, lig);
    }
    if T.es_lista(patron) && T.es_lista(dado) {
        let a = elem_lista(patron);
        let b = elem_lista(dado);
        return unificar_tipo(vista(a), vista(b), sueltos, lig);
    }
    if T.es_mapa(patron) && T.es_mapa(dado) {
        let a = clave_y_valor(patron);
        let b = clave_y_valor(dado);
        if largo(a) != 2 || largo(b) != 2 { return false; }
        return unificar_tipo(vista(a[0]), vista(b[0]), sueltos, lig)
        && unificar_tipo(vista(a[1]), vista(b[1]), sueltos, lig);
    }
    if T.es_arreglo(patron) && T.es_arreglo(dado) {
        let na = largo_arreglo(patron);
        let nb = largo_arreglo(dado);
        let ea = elem_arreglo(patron);
        let eb = elem_arreglo(dado);
        return igual(vista(na), vista(nb)) && unificar_tipo(vista(ea), vista(eb), sueltos, lig);
    }
    // `Par<A, B>` contra `Par<usize, str>`.
    if I.es_aplicacion(patron) && I.es_aplicacion(dado) {
        let ba = I.base_de_aplicacion(patron);
        let bb = I.base_de_aplicacion(dado);
        if !igual(vista(ba), vista(bb)) { return false; }
        let xs = T.partir_tipos(T.entre_angulos(patron));
        let ys = T.partir_tipos(T.entre_angulos(dado));
        if largo(xs) != largo(ys) { return false; }
        var i = 0;
        while i < largo(xs) {
            if !unificar_tipo(vista(xs[i]), vista(ys[i]), sueltos, lig) { return false; }
            i = i + 1;
        }
        return true;
    }
    return false;
}

// ------------------------------------------------------------------
// Lo que se sabe de una expresion sin anotar usos
// ------------------------------------------------------------------

// El tipo de una funcion como valor: `fn(&str) -> bool`.
fn firma_de(f: &Funcion) -> str {
    var t = nuevo("fn(");
    var i = 0;
    while i < largo(f.params) {
        if i > 0 { empujar(t, ", "); }
        if f.params[i].mutable { empujar(t, "&mut "); }
        else if f.params[i].compartido { empujar(t, "&"); }
        empujar(t, vista(f.params[i].tipo));
        i = i + 1;
    }
    empujar(t, ")");
    if largo(f.retorno) > 0 && !igual(vista(f.retorno), "()") {
        empujar(t, " -> ");
        empujar(t, vista(f.retorno));
    }
    return t;
}

// La funcion de un nombre tal como lo ve este modulo.
fn funcion_llamada(m: &Mundo, tipos: &I.Contexto, nombre: view) -> usize {
    let dentro = resolver_nombre(tipos, nombre);
    return buscar_funcion(m, vista(dentro)) sino largo(m.funciones);
}

fn tipo_probable(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> str {
    let clase = vista(n.clase);
    if (igual(clase, "try") || igual(clase, "sino")) && largo(n.hijos) > 0 {
        return tipo_probable(c, m, tipos, n.hijos[0]);
    }
    if igual(clase, "variable") {
        let i = buscar_simbolo(c, vista(n.texto));
        if existe(c, i) { return copiar(c.simbolos[i].tipo); }
        let k = funcion_llamada(m, tipos, vista(n.texto));
        if k < largo(m.funciones) && !tiene_sueltos(m.funciones[k]) && !m.funciones[k].falible {
            return firma_de(m.funciones[k]);
        }
        return vacio();
    }
    if igual(clase, "cierre") { return cierre(c, m, tipos, n); }
    if igual(clase, "cadena") { return nuevo("view"); }
    if igual(clase, "entero") { return nuevo("usize"); }
    if igual(clase, "decimal") { return nuevo("f64"); }
    if igual(clase, "booleano") { return nuevo("bool"); }
    if igual(clase, "interpolada") { return nuevo("str"); }
    if igual(clase, "campo") || igual(clase, "indice") {
        return tipo_de_lugar(c, m, tipos, n);
    }
    if igual(clase, "literal_struct") { return I.sin_modulo(vista(n.texto)); }
    if igual(clase, "unaria") && largo(n.hijos) > 0 {
        if igual(vista(n.texto), "!") { return nuevo("bool"); }
        if igual(vista(n.texto), "-") && igual(I.literal_de(n.hijos[0]), "entero") {
            return nuevo("i64");
        }
        let t = tipo_probable(c, m, tipos, n.hijos[0]);
        if igual(vista(t), literal()) { return nuevo("i64"); }
        return t;
    }
    if igual(clase, "conversion") {
        let destino = vista(n.texto);
        if empieza_con(destino, "?") { return nuevo(rebanar(destino, 1, largo(destino))); }
        return nuevo(destino);
    }
    // Una rama que es un numero escrito toma el tipo de la otra.
    if igual(clase, "si_expr") && largo(n.hijos) == 3 {
        let lit_a = I.literal_de(n.hijos[1]);
        let lit_b = I.literal_de(n.hijos[2]);
        if largo(lit_a) > 0 && largo(lit_b) == 0 {
            return tipo_probable(c, m, tipos, n.hijos[2]);
        }
        if largo(lit_a) > 0 {
            if igual(lit_a, "decimal") || igual(lit_b, "decimal") { return nuevo("f64"); }
            return nuevo("usize");
        }
        return tipo_probable(c, m, tipos, n.hijos[1]);
    }
    if igual(clase, "binaria") && largo(n.hijos) == 2 {
        let op = vista(n.texto);
        if igual(op, "&&") || igual(op, "||") || igual(op, "==") || igual(op, "!=")
        || igual(op, "<") || igual(op, "<=") || igual(op, ">") || igual(op, ">=") {
            return nuevo("bool");
        }
        // Un numero escrito no decide nada por su cuenta: toma el tipo del
        // otro lado.
        let lit_i = I.literal_de(n.hijos[0]);
        let lit_d = I.literal_de(n.hijos[1]);
        if largo(lit_i) > 0 && largo(lit_d) > 0 {
            if igual(lit_i, "decimal") || igual(lit_d, "decimal") { return nuevo("f64"); }
            return nuevo("usize");
        }
        if largo(lit_i) > 0 { return tipo_probable(c, m, tipos, n.hijos[1]); }
        let a = tipo_probable(c, m, tipos, n.hijos[0]);
        let b = tipo_probable(c, m, tipos, n.hijos[1]);
        if largo(a) == 0 || igual(vista(a), literal()) {
            if igual(vista(b), literal()) { return nuevo("usize"); }
            return b;
        }
        return a;
    }
    if igual(clase, "llamada") {
        let nombre = I.sin_modulo(vista(n.texto));
        // Las que devuelven el tipo de lo que reciben, como al comprobar.
        if (igual(nombre, "absoluto") || igual(nombre, "raiz") || igual(nombre, "piso")
            || igual(nombre, "techo") || igual(nombre, "redondear")) && largo(n.hijos) == 1 {
            let lit = I.literal_de(n.hijos[0]);
            if largo(lit) > 0 {
                if igual(lit, "entero") && igual(nombre, "absoluto") { return nuevo("i64"); }
                return nuevo("f64");
            }
            let t_a = tipo_probable(c, m, tipos, n.hijos[0]);
            return T.apuntado_si(vista(t_a));
        }
        let fi = firma_interna(vista(nombre));
        if fi.existe { return copiar(fi.retorno); }
        let k = funcion_llamada(m, tipos, vista(n.texto));
        if k >= largo(m.funciones) { return vacio(); }
        if !tiene_sueltos(m.funciones[k]) { return copiar(m.funciones[k].retorno); }
        // Para saber que devuelve hay que elegir la copia, en silencio.
        let antes = largo(c.errores);
        let inst = instanciar(c, m, tipos, n, k);
        if !inst.ok || largo(c.errores) > antes {
            truncar_errores(c, antes);
            return vacio();
        }
        return copiar(inst.retorno);
    }
    return vacio();
}

fn truncar_errores(c: mut Comprobacion, cuantos: usize) {
    var quedan: lista<str> = [];
    var i = 0;
    while i < cuantos && i < largo(c.errores) {
        anadir(quedan, copiar(c.errores[i]));
        i = i + 1;
    }
    c.errores = quedan;
}

// Una generica con los tipos que pone una llamada.
struct Instancia {
    ok: bool,
    params: lista<Param>,
    retorno: str,
    // `T = str, U = usize`, en el orden en que se ligaron.
    ligadas: str,
    // `plantilla|T1|T2`, con los tipos en el orden de la plantilla.
    clave: str,
    // Como se llama la copia en el original: `primeras__str`.
    copia: str,
}

fn instanciar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    k: usize) -> Instancia {
    let f = copiar(m.funciones[k]);
    let nombre = vista(f.nombre);
    let sueltos = copiar(f.tipo_params);
    var lig: mapa<str, str> = [];
    let fallo = Instancia { ok: false, params: [], retorno: vacio(), ligadas: vacio(),
        clave: vacio(), copia: vacio() };
    if largo(n.hijos) == largo(f.params) {
        var i = 0;
        while i < largo(f.params) {
            var dado = tipo_probable(c, m, tipos, n.hijos[i]);
            if T.es_referencia(vista(dado)) { dado = nuevo(T.apuntado(vista(dado))); }
            var antes: mapa<str, str> = [];
            for x en claves(lig) {
                if igual(vista(x), "\t") { continue; }
                let v = obtener(lig, vista(x)) sino "";
                poner(antes, vista(x), nuevo(v));
            }
            let pt = vista(f.params[i].tipo);
            if !unificar_tipo(pt, vista(dado), sueltos, lig) {
                var choca = vacio();
                for tp en sueltos {
                    if largo(choca) == 0 && tiene(antes, vista(tp)) && contiene(pt, vista(tp)) {
                        choca = copiar(tp);
                    }
                }
                let pn = vista(f.params[i].nombre);
                if largo(choca) > 0 {
                    let ya = obtener(antes, vista(choca)) sino "";
                    error(c, m, n.linea, $"`{choca}` en `{nombre}` ya quedo en `{ya}` por un argumento anterior, y `{pn}` pide `{dado}`. Un mismo parametro de tipo es un solo tipo en toda la llamada");
                } else {
                    let visto = texto_o_none(vista(dado));
                    error(c, m, n.linea, $"`{pn}` de `{nombre}` es `{pt}` y recibio `{visto}`");
                }
                return fallo;
            }
            i = i + 1;
        }
    }
    var faltan: lista<str> = [];
    for tp en sueltos {
        if !tiene(lig, vista(tp)) { anadir(faltan, copiar(tp)); }
    }
    if largo(faltan) > 0 {
        let cuales = con_comas(faltan);
        error(c, m, n.linea, $"no se puede deducir {cuales} en la llamada a `{nombre}`: los argumentos no lo dicen. Guarda el argumento en una variable con su tipo escrito y pasa esa");
        return fallo;
    }
    for r en f.restricciones {
        var corte = 0;
        while corte < largo(r) && byte(vista(r), corte) != 61 { corte = corte + 1; }
        let tp = rebanar(vista(r), 0, corte);
        let cual = rebanar(vista(r), corte + 1, largo(r));
        let validos = restriccion_admite(cual);
        let puesto = obtener(lig, tp) sino "";
        if largo(puesto) > 0 && !esta_entre(validos, puesto) {
            let lista_v = con_comas(validos);
            error(c, m, n.linea, $"`{nombre}` pide que `{tp}` sea `{cual}`, y aqui `{tp}` es `{puesto}`. `{cual}` son: {lista_v}");
            return fallo;
        }
    }
    var ps: lista<Param> = [];
    for p en f.params {
        anadir(ps, Param { nombre: copiar(p.nombre), tipo: I.sustituir(vista(p.tipo), lig),
                mutable: p.mutable, compartido: p.compartido });
    }
    var ligadas = vacio();
    let orden = obtener(lig, "\t") sino "";
    var desde = 0;
    var i = 0;
    while i < largo(orden) {
        if byte(orden, i) == 9 {
            let tp = rebanar(orden, desde, i);
            let puesto = obtener(lig, tp) sino "";
            if largo(ligadas) > 0 { empujar(ligadas, ", "); }
            let pieza = $"{tp} = {puesto}";
            empujar(ligadas, vista(pieza));
            desde = i + 1;
        }
        i = i + 1;
    }
    var clave = copiar(f.nombre);
    var copia = copiar(f.nombre);
    empujar(copia, "__");
    var primero_t = true;
    for tp en sueltos {
        empujar(clave, "|");
        empujar(clave, obtener(lig, vista(tp)) sino "");
        let puesto = nuevo(obtener(lig, vista(tp)) sino "");
        let resuelto = I.nombre_resuelto(vista(puesto));
        if !primero_t { empujar(copia, "_"); }
        primero_t = false;
        empujar(copia, G.sanear(vista(resuelto)));
    }
    let hecha = esta_entre(m.copias, vista(clave));
    let inst = Instancia { ok: true, params: ps, retorno: I.sustituir(vista(f.retorno), lig),
        ligadas: ligadas, clave: copiar(clave), copia: copiar(copia) };
    if !hecha {
        anadir(m.copias, copiar(clave));
        comprobar_copia(c, m, n, k, inst, lig, false);
        anadir(m.orden_copias, copiar(inst.copia));
    }
    return inst;
}

// El cuerpo de una generica con restriccion vale para CADA tipo que la
// cumple, no solo para los que se usan: si compila, compila para todo `T`
// del conjunto. Como los conjuntos son finitos, basta con probarlos todos,
// salvo los que dejan la firma sin sentido. Un parametro sin restriccion se
// deja en los tipos con que se uso; si alguno no la tiene y nadie la usa, no
// se sabe con que probar, y se deja.
fn comprobar_restricciones(c: mut Comprobacion, m: mut Mundo) {
    let total = largo(m.funciones);
    var e = 0;
    while e < total {
        let f = copiar(m.funciones[e]);
        let k = e;
        e = e + 1;
        if f.de_cierre || f.externa || !tiene_sueltos(f) || largo(f.restricciones) == 0 {
            continue;
        }
        var restr: mapa<str, str> = [];
        for r en f.restricciones {
            var corte = 0;
            while corte < largo(r) && byte(vista(r), corte) != 61 { corte = corte + 1; }
            poner(restr, rebanar(vista(r), 0, corte), nuevo(rebanar(vista(r), corte + 1, largo(r))));
        }
        let prefijo = $"{f.nombre}|";
        var probadas: lista<str> = [];
        var bases: lista<lista<str>> = [];
        for cl en m.copias {
            if empieza_con(vista(cl), vista(prefijo)) {
                anadir(probadas, copiar(cl));
                anadir(bases, partir_por_barra(rebanar(vista(cl), largo(prefijo), largo(cl))));
            }
        }
        if largo(bases) == 0 {
            var todos = true;
            for tp en f.tipo_params {
                if !tiene(restr, vista(tp)) { todos = false; }
            }
            if todos {
                let ninguna: lista<str> = [];
                anadir(bases, ninguna);
            }
        }
        for base en bases {
            var opciones: lista<lista<str>> = [];
            var i = 0;
            var alguna_vacia = false;
            while i < largo(f.tipo_params) {
                let tp = vista(f.tipo_params[i]);
                if tiene(restr, tp) {
                    let cual = obtener(restr, tp) sino "";
                    anadir(opciones, restriccion_admite(cual));
                } else {
                    var una: lista<str> = [];
                    if i < largo(base) { anadir(una, copiar(base[i])); }
                    if largo(una) == 0 { alguna_vacia = true; }
                    anadir(opciones, una);
                }
                i = i + 1;
            }
            if alguna_vacia || largo(opciones) == 0 { continue; }
            // Todas las combinaciones, la ultima posicion la que mas cambia.
            var cuenta: lista<usize> = [];
            for _o en opciones { anadir(cuenta, 0); }
            var sigue = true;
            while sigue {
                var juego: lista<str> = [];
                var clave = copiar(f.nombre);
                var j = 0;
                while j < largo(opciones) {
                    let t = copiar(opciones[j][cuenta[j]]);
                    empujar(clave, "|");
                    empujar(clave, vista(t));
                    anadir(juego, t);
                    j = j + 1;
                }
                if !esta_entre(probadas, vista(clave)) {
                    anadir(probadas, copiar(clave));
                    if firma_valida(m, f, juego) { probar_juego(c, m, k, juego); }
                }
                // La siguiente.
                var p = largo(opciones);
                sigue = false;
                while p > 0 && !sigue {
                    p = p - 1;
                    if cuenta[p] + 1 < largo(opciones[p]) {
                        cuenta[p] = cuenta[p] + 1;
                        sigue = true;
                    } else {
                        cuenta[p] = 0;
                    }
                }
            }
        }
    }
}

fn partir_por_barra(t: view) -> lista<str> {
    var salida: lista<str> = [];
    var desde = 0;
    var i = 0;
    while i <= largo(t) {
        if i == largo(t) || byte(t, i) == 124 {
            anadir(salida, nuevo(rebanar(t, desde, i)));
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

// Las ligaduras de `f` para un juego de tipos, en el orden de la plantilla.
fn ligaduras_de_juego(f: &Funcion, juego: &lista<str>) -> mapa<str, str> {
    var lig: mapa<str, str> = [];
    var orden = vacio();
    var i = 0;
    while i < largo(f.tipo_params) && i < largo(juego) {
        poner(lig, vista(f.tipo_params[i]), copiar(juego[i]));
        empujar(orden, vista(f.tipo_params[i]));
        empujar(orden, "\t");
        i = i + 1;
    }
    poner(lig, "\t", orden);
    return lig;
}

// Si con estos tipos la firma tiene sentido. Un `T = view` sobre un
// `&lista<T>` no lo tiene: nadie podria llamarla asi, y el cuerpo no tiene
// que valer para lo que no se puede escribir.
fn firma_valida(m: &Mundo, f: &Funcion, juego: &lista<str>) -> bool {
    let lig = ligaduras_de_juego(f, juego);
    for p en f.params {
        let t = I.sustituir(vista(p.tipo), lig);
        if !almacenable(m, vista(t)) || (prestado(p) && igual(vista(t), "view")) { return false; }
    }
    let r = I.sustituir(vista(f.retorno), lig);
    return largo(r) == 0 || igual(vista(r), "()") || almacenable(m, vista(r));
}

// Comprueba la copia de `k` para este juego sin quedarsela: lo que cambie
// al hacerla se deshace, y solo quedan los errores.
fn probar_juego(c: mut Comprobacion, m: mut Mundo, k: usize, juego: &lista<str>) {
    let f = copiar(m.funciones[k]);
    let lig = ligaduras_de_juego(f, juego);
    var ps: lista<Param> = [];
    for p en f.params {
        anadir(ps, Param { nombre: copiar(p.nombre), tipo: I.sustituir(vista(p.tipo), lig),
                mutable: p.mutable, compartido: p.compartido });
    }
    var ligadas = vacio();
    var clave = copiar(f.nombre);
    var copia = copiar(f.nombre);
    empujar(copia, "__");
    var i = 0;
    while i < largo(f.tipo_params) && i < largo(juego) {
        if i > 0 {
            empujar(ligadas, ", ");
            empujar(copia, "_");
        }
        empujar(ligadas, $"{f.tipo_params[i]} = {juego[i]}");
        empujar(clave, "|");
        empujar(clave, vista(juego[i]));
        let resuelto = I.nombre_resuelto(vista(juego[i]));
        empujar(copia, G.sanear(vista(resuelto)));
        i = i + 1;
    }
    let inst = Instancia { ok: true, params: ps, retorno: I.sustituir(vista(f.retorno), lig),
        ligadas: ligadas, clave: copiar(clave), copia: copia };
    let c_antes = copiar(c);
    let m_antes = Mundo { funciones: copiar(m.funciones), indice: copiar(m.indice),
        st_tipos: copiar(m.st_tipos), st_nombres: copiar(m.st_nombres),
        st_params: copiar(m.st_params), en_variantes: copiar(m.en_variantes),
        en_formas: copiar(m.en_formas), bonitos: copiar(m.bonitos), cierres: copiar(m.cierres),
        cierres_mod: copiar(m.cierres_mod), n_cierres: m.n_cierres,
        cierres_mut: copiar(m.cierres_mut), numeracion: copiar(m.numeracion), arboles: [],
        modulos: [], contextos: [], copias: copiar(m.copias),
        orden_structs: copiar(m.orden_structs), tipo_de_struct: copiar(m.tipo_de_struct),
        anotados: [], orden_copias: copiar(m.orden_copias) };
    let antes = largo(c.errores);
    anadir(m.copias, copiar(clave));
    let nodo = copiar(m.arboles[f.modulo].hijos[f.posicion]);
    let archivo_antes = copiar(c.archivo);
    c.archivo = copiar(f.archivo);
    comprobar_copia(c, m, nodo, k, inst, lig, true);
    var nuevos: lista<str> = [];
    var q = antes;
    while q < largo(c.errores) {
        anadir(nuevos, copiar(c.errores[q]));
        q = q + 1;
    }
    c = c_antes;
    c.archivo = archivo_antes;
    m.funciones = copiar(m_antes.funciones);
    m.indice = copiar(m_antes.indice);
    m.st_tipos = copiar(m_antes.st_tipos);
    m.st_nombres = copiar(m_antes.st_nombres);
    m.st_params = copiar(m_antes.st_params);
    m.en_variantes = copiar(m_antes.en_variantes);
    m.en_formas = copiar(m_antes.en_formas);
    m.bonitos = copiar(m_antes.bonitos);
    m.cierres = copiar(m_antes.cierres);
    m.cierres_mod = copiar(m_antes.cierres_mod);
    m.n_cierres = m_antes.n_cierres;
    m.cierres_mut = copiar(m_antes.cierres_mut);
    m.numeracion = copiar(m_antes.numeracion);
    m.copias = copiar(m_antes.copias);
    m.orden_copias = copiar(m_antes.orden_copias);
    m.orden_structs = copiar(m_antes.orden_structs);
    m.tipo_de_struct = copiar(m_antes.tipo_de_struct);
    for x en nuevos {
        if !esta_entre(c.errores, vista(x)) { anadir(c.errores, copiar(x)); }
    }
}

// Los tipos puestos en el arbol de una copia: en los parametros, el
// retorno, las declaraciones y las conversiones.
fn sustituir_en_arbol(n: mut P.Nodo, lig: &mapa<str, str>) {
    let clase = copiar(n.clase);
    if igual(vista(clase), "param") || igual(vista(clase), "declaracion") {
        let t = copiar(n.texto);
        var j = 0;
        while j < largo(t) && byte(vista(t), j) != 58 { j = j + 1; }
        if j < largo(t) {
            let tipo = I.sustituir(rebanar(vista(t), j + 1, largo(t)), lig);
            n.texto = $"{rebanar(vista(t), 0, j + 1)}{tipo}";
        }
    } else if igual(vista(clase), "retorno_tipo") || igual(vista(clase), "conversion") {
        let t = copiar(n.texto);
        n.texto = I.sustituir(vista(t), lig);
    }
    var i = 0;
    while i < largo(n.hijos) {
        sustituir_en_arbol(n.hijos[i], lig);
        i = i + 1;
    }
}

// El cuerpo de una generica se comprueba con los tipos puestos, en mitad de
// quien la llama, como otra funcion entera.
fn comprobar_copia(c: mut Comprobacion, m: mut Mundo, n: &P.Nodo, k: usize,
    inst: &Instancia, lig: &mapa<str, str>, sin_llamada: bool) {
    var f = copiar(m.funciones[k]);
    f.params = copiar(inst.params);
    f.retorno = copiar(inst.retorno);
    f.tipo_params = [];
    // La copia vive solo aqui: el bucle del programa no la vuelve a mirar.
    f.de_cierre = true;
    // Se llama como en el original, y los mensajes dicen el de la plantilla.
    let plantilla = copiar(f.nombre);
    f.nombre = copiar(inst.copia);
    poner(m.bonitos, vista(inst.copia), plantilla);
    let modulo = f.modulo;
    var nodo = copiar(m.arboles[modulo].hijos[f.posicion]);
    sustituir_en_arbol(nodo, lig);
    // Sus tipos, ya puestos, piden las copias de structs que haga falta.
    registrar_tipo(m, vista(f.retorno));
    for p en copiar(f.params) { registrar_tipo(m, vista(p.tipo)); }
    for h en nodo.hijos {
        if igual(vista(h.clase), "bloque") { registrar_en_nodo(m, h); }
    }
    let kc = largo(m.funciones);
    anadir(m.funciones, f);
    let tipos = copiar(m.contextos[modulo]);
    let simbolos = copiar(c.simbolos);
    let inicios = copiar(c.inicios);
    let retorno = copiar(c.retorno);
    let falible = c.falible;
    let archivo = copiar(c.archivo);
    let nombre = copiar(m.funciones[k].nombre);
    let ligadas = legible(m, vista(inst.ligadas));
    if sin_llamada {
        anadir(c.instanciando, $"al comprobar `{nombre}` con {ligadas}: la restriccion lo admite, asi que el cuerpo tiene que valer tambien asi");
    } else {
        anadir(c.instanciando, $"al usar `{nombre}` con {ligadas}, desde {archivo}:{n.linea}");
    }
    anadir(c.plantillas, k);
    let dueno = copiar(c.dueno);
    let modulo_antes = c.modulo;
    c.simbolos = [];
    c.inicios = [];
    c.archivo = copiar(m.modulos[modulo]);
    c.modulo = modulo;
    comprobar_funcion(c, m, tipos, kc, nodo, vista(inst.clave));
    c.dueno = dueno;
    c.modulo = modulo_antes;
    var quedan: lista<str> = [];
    var q = 0;
    while q + 1 < largo(c.instanciando) {
        anadir(quedan, copiar(c.instanciando[q]));
        q = q + 1;
    }
    c.instanciando = quedan;
    var otras: lista<usize> = [];
    var q2 = 0;
    while q2 + 1 < largo(c.plantillas) {
        anadir(otras, c.plantillas[q2]);
        q2 = q2 + 1;
    }
    c.plantillas = otras;
    c.simbolos = simbolos;
    c.inicios = inicios;
    c.retorno = retorno;
    c.falible = falible;
    c.archivo = archivo;
}

// `None` en un mensaje del original: sin tipo conocido.
fn texto_o_none(t: view) -> str {
    if largo(t) == 0 { return nuevo("None"); }
    return nuevo(t);
}

// Escribir en `x` no es leer `x`: la variable suelta se resuelve sin usarla.
fn tipo_de_lugar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> str {
    if igual(vista(n.clase), "variable") {
        let i = buscar_simbolo(c, vista(n.texto));
        if existe(c, i) { return copiar(c.simbolos[i].tipo); }
        return vacio();
    }
    return comprobar_expresion(c, m, tipos, n, "", false);
}

// ------------------------------------------------------------------
// Expresiones
// ------------------------------------------------------------------

// El tipo de `n`, comprobandola. Queda anotado para el generador, que lo lee
// en vez de deducirlo otra vez por su cuenta, que es como se equivocaba.
fn comprobar_expresion(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    destino: view, mover_variables: bool) -> str {
    let t = comprobar_expresion_sin_anotar(c, m, tipos, n, destino, mover_variables);
    anotar(c, m, n, vista(t));
    let destino_p = sin_prestamo(destino);
    if (igual(vista(t), literal()) || igual(vista(t), literal_decimal()))
    && es_numerico(vista(destino_p)) {
        fijar_literal(c, m, n, vista(destino_p));
    }
    return t;
}

fn clave_anotada(c: &Comprobacion, n: &P.Nodo) -> str {
    return $"{c.dueno}#{n.id}";
}

fn anotar(c: &Comprobacion, m: mut Mundo, n: &P.Nodo, t: view) {
    if n.id == 0 || c.modulo >= largo(m.anotados) { return; }
    let clave = clave_anotada(c, n);
    poner(m.anotados[c.modulo], vista(clave), nuevo(t));
}

// Un numero escrito ya sabe su tipo: se lo dice el otro lado de la operacion,
// o el sitio donde va. Se anota en el y en todo lo que es numero escrito por
// debajo; un desplazamiento cuenta en `usize`.
fn fijar_literal(c: &Comprobacion, m: mut Mundo, n: &P.Nodo, tipo: view) {
    if c.modulo >= largo(m.anotados) { return; }
    if n.id > 0 {
        let clave = clave_anotada(c, n);
        let actual = obtener(m.anotados[c.modulo], vista(clave)) sino literal();
        if !igual(actual, literal()) && !igual(actual, literal_decimal()) { return; }
    }
    if largo(I.literal_de(n)) == 0 { return; }
    anotar(c, m, n, tipo);
    let clase = vista(n.clase);
    if igual(clase, "binaria") && largo(n.hijos) == 2 {
        fijar_literal(c, m, n.hijos[0], tipo);
        if igual(vista(n.texto), "<<") || igual(vista(n.texto), ">>") {
            fijar_literal(c, m, n.hijos[1], "usize");
        } else {
            fijar_literal(c, m, n.hijos[1], tipo);
        }
    } else if igual(clase, "unaria") && largo(n.hijos) == 1 {
        fijar_literal(c, m, n.hijos[0], tipo);
    } else if igual(clase, "si_expr") && largo(n.hijos) == 3 {
        fijar_literal(c, m, n.hijos[1], tipo);
        fijar_literal(c, m, n.hijos[2], tipo);
    }
}

fn comprobar_expresion_sin_anotar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto,
    n: &P.Nodo, destino: view, mover_variables: bool) -> str {
    if es_numerico(destino) { comprobar_literal(c, m, n, destino); }
    let clase = vista(n.clase);
    if igual(clase, "entero") { return nuevo(literal()); }
    if igual(clase, "decimal") { return nuevo(literal_decimal()); }
    if igual(clase, "cadena") { return nuevo("view"); }
    if igual(clase, "booleano") { return nuevo("bool"); }
    if igual(clase, "expresion") && largo(n.hijos) == 1 {
        return comprobar_expresion(c, m, tipos, n.hijos[0], destino, mover_variables);
    }
    if igual(clase, "interpolada") {
        for x en n.hijos {
            let t = comprobar_expresion(c, m, tipos, x, "", false);
            if largo(t) == 0 { continue; }
            if T.es_arreglo(vista(t)) || T.es_lista(vista(t)) || T.es_mapa(vista(t))
            || es_struct(m, vista(t)) {
                error(c, m, n.linea, $"dentro de `{{}}` va un escalar o texto, y `{t}` no lo es");
            }
        }
        return nuevo("str");
    }
    if igual(clase, "variable") {
        return variable(c, m, tipos, n, mover_variables, false);
    }
    if igual(clase, "unaria") { return unaria(c, m, tipos, n, destino); }
    if igual(clase, "cierre") { return cierre(c, m, tipos, n); }
    if igual(clase, "si_expr") { return si_expr(c, m, tipos, n, destino, mover_variables); }
    if igual(clase, "enum_lit") { return enum_lit(c, m, tipos, n); }
    if igual(clase, "match") { return comprobar_match(c, m, tipos, n, destino, mover_variables); }
    if igual(clase, "conversion") { return comprobar_conversion(c, m, tipos, n); }
    if igual(clase, "try") {
        if !c.falible {
            error(c, m, n.linea, "`try` deja subir la falla al que llamo, pero esta funcion no esta declarada con `!`");
        }
        if c.en_condicion_bucle > 0 {
            error(c, m, n.linea, "`try` no puede ir en la condicion de un `while`: se evaluaria una sola vez");
        }
        return desenvolver(c, m, tipos, n, n.hijos[0], "try");
    }
    if igual(clase, "sino") {
        if c.en_condicion_bucle > 0 {
            error(c, m, n.linea, "`sino` no puede ir en la condicion de un `while`: se evaluaria una sola vez");
        }
        let t = desenvolver(c, m, tipos, n, n.hijos[0], "sino");
        let alt = comprobar_expresion(c, m, tipos, n.hijos[1], vista(t), true);
        if largo(t) > 0 && T.es_referencia(vista(t)) {
            error(c, m, n.linea, $"`sino` no vale aqui: la llamada devuelve un prestamo (`{t}`) y no hay nada que prestar cuando falla. Usa `try`, o pregunta antes con `tiene(...)`");
        } else if largo(t) > 0 && largo(alt) > 0 && !encaja(vista(t), vista(alt)) {
            error(c, m, n.linea, $"la llamada da `{t}` y el valor de despues de `sino` es `{alt}`");
        }
        return t;
    }
    if igual(clase, "campo") { return campo(c, m, tipos, n, mover_variables); }
    if igual(clase, "indice") { return indice(c, m, tipos, n, mover_variables); }
    if igual(clase, "literal_struct") { return literal_struct(c, m, tipos, n, destino); }
    if igual(clase, "literal_lista") { return literal_arreglo(c, m, tipos, n, destino); }
    if igual(clase, "binaria") { return binaria(c, m, tipos, n); }
    if igual(clase, "llamada") { return llamada(c, m, tipos, n, false, destino); }
    return vacio();
}

fn variable(c: mut Comprobacion, m: &Mundo, tipos: &I.Contexto, n: &P.Nodo,
    mover_variables: bool, directo: bool) -> str {
    let nombre = vista(n.texto);
    let i = buscar_simbolo(c, nombre);
    if !existe(c, i) {
        // El nombre de una funcion sin parentesis es un valor: su puntero.
        let k = funcion_llamada(m, tipos, nombre);
        if k < largo(m.funciones) && !tiene_sueltos(m.funciones[k]) {
            if m.funciones[k].falible {
                error(c, m, n.linea, $"`{nombre}` puede fallar, y en v0 una funcion que se pasa como valor no puede: quitale el `!` o envuelvela");
                return vacio();
            }
            return firma_de(m.funciones[k]);
        }
        if k < largo(m.funciones) {
            error(c, m, n.linea, $"`{nombre}` es generica: hay una funcion por cada juego de tipos, y aqui no se sabe cual. Envuelvela en una funcion normal");
            return vacio();
        }
        error(c, m, n.linea, $"`{nombre}` no esta declarada");
        return vacio();
    }
    let t = copiar(c.simbolos[i].tipo);
    if mover_variables && posee_memoria(m, vista(t)) {
        mover(c, m, n.linea, i, directo);
    } else {
        let _leida = leer(c, m, n.linea, i);
    }
    return t;
}

fn unaria(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    destino: view) -> str {
    let t = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let op = vista(n.texto);
    if igual(op, "~") {
        if igual(vista(t), literal()) {
            fijar_literal(c, m, n.hijos[0], "usize");
            return nuevo("usize");
        }
        if largo(t) > 0 && !es_tipo_entero(vista(t)) {
            error(c, m, n.linea, $"`~` da la vuelta a los bits de un entero, recibio `{t}`");
        }
        return t;
    }
    if igual(op, "!") {
        if largo(t) > 0 && !igual(vista(t), "bool") {
            error(c, m, n.linea, $"`!` necesita un `bool`, recibio `{t}`");
        }
        return nuevo("bool");
    }
    if igual(vista(t), literal()) {
        // Un `-3` suelto ya lo dice `comprobar_literal`: no cabe. Una cuenta,
        // `-(3 + 4)`, no la mira nadie mas.
        if es_sin_signo(destino) && !igual(vista(n.hijos[0].clase), "entero") {
            error(c, m, n.linea, $"`{destino}` no tiene signo: no se puede negar");
        }
        if es_numerico(destino) {
            fijar_literal(c, m, n.hijos[0], destino);
            return nuevo(destino);
        }
        comprobar_literal(c, m, n, "i64");
        fijar_literal(c, m, n.hijos[0], "i64");
        return nuevo("i64");
    }
    if igual(vista(t), literal_decimal()) { return t; }
    if es_decimal(vista(t)) { return t; }
    if largo(t) > 0 && !es_tipo_entero(vista(t)) {
        error(c, m, n.linea, $"`-` necesita un entero, recibio `{t}`");
    }
    if es_sin_signo(vista(t)) {
        error(c, m, n.linea, $"`{t}` no tiene signo: no se puede negar");
    }
    return t;
}

fn si_expr(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    destino: view, mover_variables: bool) -> str {
    let tc = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    if largo(tc) > 0 && !igual(vista(tc), "bool") {
        error(c, m, n.linea, $"la condicion de un `if` tiene que ser `bool`, y es `{tc}`");
    }
    let antes = foto(c);
    c.en_condicional = c.en_condicional + 1;
    let ta = comprobar_expresion(c, m, tipos, n.hijos[1], destino, mover_variables);
    let tras_a = foto(c);
    restaurar_foto(c, antes);
    let tb = comprobar_expresion(c, m, tipos, n.hijos[2], destino, mover_variables);
    let tras_b = foto(c);
    c.en_condicional = c.en_condicional - 1;
    juntar_ramas(c, tras_a, tras_b);
    // Una rama que es un numero escrito toma el tipo de la otra, y tiene que
    // caber en el.
    let tb_p = T.apuntado_si(vista(tb));
    let ta_p = T.apuntado_si(vista(ta));
    if (igual(vista(ta), literal()) || igual(vista(ta), literal_decimal()))
    && es_numerico(vista(tb_p)) {
        comprobar_literal(c, m, n.hijos[1], vista(tb_p));
        fijar_literal(c, m, n.hijos[1], vista(tb_p));
    } else if (igual(vista(tb), literal()) || igual(vista(tb), literal_decimal()))
    && es_numerico(vista(ta_p)) {
        comprobar_literal(c, m, n.hijos[2], vista(ta_p));
        fijar_literal(c, m, n.hijos[2], vista(ta_p));
    } else if igual(vista(ta), literal()) && igual(vista(tb), literal_decimal()) {
        fijar_literal(c, m, n.hijos[1], literal_decimal());
        return copiar(tb);
    } else if igual(vista(tb), literal()) && igual(vista(ta), literal_decimal()) {
        fijar_literal(c, m, n.hijos[2], literal_decimal());
        return copiar(ta);
    }
    if largo(ta) > 0 && largo(tb) > 0 && !encaja(vista(ta), vista(tb))
    && !encaja(vista(tb), vista(ta)) {
        error(c, m, n.linea, $"las dos ramas de un `if` tienen que dar el mismo tipo, y dan `{ta}` y `{tb}`");
    }
    if largo(ta) == 0 || igual(vista(ta), literal()) || igual(vista(ta), literal_decimal()) {
        if largo(tb) > 0 { return tb; }
        return ta;
    }
    return ta;
}

fn cuantos_valores(n: usize) -> str {
    if n == 1 { return nuevo("1 valor"); }
    return $"{n} valores";
}

fn enum_lit(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> str {
    let crudo = I.antes_del_punto(vista(n.texto));
    let en_t = I.sin_modulo(vista(crudo));
    let forma = I.tras_el_punto(vista(n.texto));
    if !es_enum(m, vista(en_t)) {
        error(c, m, n.linea, $"`{en_t}` no es un enum");
        return vacio();
    }
    if !tiene_forma(m, vista(en_t), vista(forma)) {
        let cuales = formas_legibles(m, vista(en_t));
        error(c, m, n.linea, $"`{en_t}` no tiene la forma `{forma}`; tiene {cuales}");
        return vacio();
    }
    let lleva = formas_de(m, vista(en_t), vista(forma));
    if largo(n.hijos) != largo(lleva) {
        let cuantos = cuantos_valores(largo(lleva));
        let dados = largo(n.hijos);
        error(c, m, n.linea, $"`{en_t}.{forma}` lleva {cuantos}, y se le dieron {dados}");
        return vacio();
    }
    var i = 0;
    while i < largo(lleva) {
        let t = vista(lleva[i]);
        let ta = comprobar_expresion(c, m, tipos, n.hijos[i], t, posee_memoria(m, t));
        if largo(ta) > 0 && !encaja(t, vista(ta)) {
            error(c, m, n.linea, $"`{en_t}.{forma}` lleva un `{t}` y se le dio un `{ta}`");
        }
        i = i + 1;
    }
    return en_t;
}

fn formas_legibles(m: &Mundo, en_t: view) -> str {
    let vs = I.lista_de(m.en_variantes, en_t) sino [];
    var todas: lista<str> = [];
    for v en vs { anadir(todas, $"{en_t}.{v}"); }
    return con_comas(todas);
}

fn comprobar_conversion(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> str {
    let dado = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let t = sin_prestamo(vista(dado));
    // Un numero escrito sin nada al lado sale de su tipo de siempre.
    if igual(vista(t), literal()) { fijar_literal(c, m, n.hijos[0], "usize"); }
    else if igual(vista(t), literal_decimal()) { fijar_literal(c, m, n.hijos[0], "f64"); }
    var a = copiar(n.texto);
    var envolviendo = false;
    if empieza_con(vista(a), "?") {
        envolviendo = true;
        a = nuevo(rebanar(vista(a), 1, largo(a)));
    }
    a = I.sin_alias_tipo(vista(a));
    if !es_numerico(vista(a)) {
        error(c, m, n.linea, $"`como` convierte entre numeros, y `{a}` no es uno");
    } else if largo(t) > 0 && !igual(vista(t), literal()) && !igual(vista(t), literal_decimal())
    && !es_numerico(vista(t)) {
        error(c, m, n.linea, $"`como` convierte entre numeros, y `{t}` no es uno");
    } else if envolviendo && es_tipo_entero(vista(a))
    && (es_decimal(vista(t)) || igual(vista(t), literal_decimal())) {
        error(c, m, n.linea, $"`como?` de un decimal a `{a}` no tiene sentido: di que quieres con la parte decimal —`piso`, `techo` o `redondear` de `std/numero`— y luego `como {a}`");
    } else if igual(vista(t), vista(a)) {
        aviso(c, m, n.linea, $"`como {a}` sobre algo que ya es `{a}`: no hace nada");
    }
    return a;
}

// Lo que sigue a `try` o `sino` tiene que poder fallar.
fn desenvolver(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, nodo: &P.Nodo,
    dentro: &P.Nodo, palabra: view) -> str {
    var falible = false;
    if igual(vista(dentro.clase), "llamada") {
        let k = funcion_llamada(m, tipos, vista(dentro.texto));
        if k < largo(m.funciones) && m.funciones[k].falible { falible = true; }
        let nombre = I.sin_modulo(vista(dentro.texto));
        let fi = firma_interna(vista(nombre));
        if fi.existe && fi.falible { falible = true; }
    }
    if !falible {
        error(c, m, nodo.linea, $"`{palabra}` va delante de una llamada a una funcion declarada con `!`");
        let _t = comprobar_expresion(c, m, tipos, dentro, "", false);
        return vacio();
    }
    return llamada(c, m, tipos, dentro, true, "");
}

// `p.a.b` -> `p\ta.b`: la cadena de campos desde una variable. Vacio si
// por medio hay un indice, una llamada u otra cosa.
fn ruta_de_campo(n: &P.Nodo) -> str {
    var nombres: lista<str> = [];
    var x = copiar(n);
    while igual(vista(x.clase), "campo") && largo(x.hijos) > 0 {
        anadir(nombres, copiar(x.texto));
        let dentro = copiar(x.hijos[0]);
        x = dentro;
    }
    if !igual(vista(x.clase), "variable") || largo(nombres) == 0 { return vacio(); }
    var r = copiar(x.texto);
    empujar(r, "\t");
    var k = largo(nombres);
    while k > 0 {
        k = k - 1;
        empujar(r, vista(nombres[k]));
        if k > 0 { empujar(r, "."); }
    }
    return r;
}

// Mover un campo con duenio fuera de su struct. En C se copia y su sitio
// queda a ceros, que en Tcode es un valor valido: al liberar el struct, ese
// campo no suelta nada. Aqui se apunta, para que nadie use el campo, ni el
// struct entero, hasta que se reponga.
fn sacar_campo(c: mut Comprobacion, m: &Mundo, n: &P.Nodo, base: view, raiz: view, ruta: view,
    i: usize) {
    if !existe(c, i) {
        let campo_n = copiar(n.texto);
        error(c, m, n.linea, $"no se puede sacar `{campo_n}` de un struct que no esta en una variable: dejaria a `{base}` a medio mover. Guarda antes el struct, o usa `copiar(...)`");
        return;
    }
    let nombre = $"{raiz}.{ruta}";
    let t = copiar(c.simbolos[i].tipo);
    if c.simbolos[i].prestado || T.es_referencia(vista(t)) || igual(vista(t), "view") {
        error(c, m, n.linea, $"`{raiz}` es prestada: no se puede sacar `{nombre}` de algo que no es tuyo. Usa `copiar(...)`");
        return;
    }
    if c.en_guarda > 0 {
        error(c, m, n.linea, $"una guarda no mueve nada: `{nombre}` se moveria aunque el brazo no case. Presta, o usa `copiar(...)`");
        return;
    }
    if c.en_retorno == 0 && (c.en_condicional > c.simbolos[i].condicional_al_declarar
        || c.en_bucle > c.simbolos[i].bucle_al_declarar) {
        error(c, m, n.linea, $"no se puede sacar `{nombre}` dentro de un `if`, un `match` o un bucle: despues no se sabria si sigue ahi. Sacalo donde vive `{raiz}`, o deja otro valor en su sitio con `intercambiar(...)`");
        return;
    }
    if largo(c.simbolos[i].prestamos) > 0 {
        let por = ocupada(c, i);
        error(c, m, n.linea, $"no se puede sacar `{nombre}`: {por}");
        return;
    }
    anadir(c.simbolos[i].sacados, $"{ruta}\t{n.linea}");
    anadir(c.sacados, $"{c.archivo}\t{n.linea}\t{nombre}");
}

fn campo(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    mover_variables: bool) -> str {
    let camino = ruta_de_campo(n);
    let raiz = antes_de_tab(vista(camino));
    let ruta = despues_de_tab(vista(camino));
    var ir = largo(c.simbolos);
    if largo(camino) > 0 { ir = buscar_simbolo(c, vista(raiz)); }
    // Lo ya sacado no se usa; el error se da una vez y se sigue.
    var ya_sacado = false;
    if c.por_campo == 0 && c.escribiendo == 0 && existe(c, ir) {
        for sacado en copiar(c.simbolos[ir].sacados) {
            if ya_sacado { break; }
            let r = antes_de_tab(vista(sacado));
            let cuando = despues_de_tab(vista(sacado));
            if igual(vista(ruta), vista(r)) || empieza_con(vista(ruta), $"{r}.") {
                error(c, m, n.linea, $"`{raiz}.{r}` ya se saco en la linea {cuando} y aqui se usa otra vez");
                ya_sacado = true;
            } else if empieza_con(vista(r), $"{ruta}.") {
                error(c, m, n.linea, $"`{raiz}.{ruta}` esta a medio mover: `{raiz}.{r}` se saco en la linea {cuando}");
                ya_sacado = true;
            }
        }
    }
    let oc = vista(n.hijos[0].clase);
    let encadenado = igual(oc, "variable") || igual(oc, "campo");
    if encadenado { c.por_campo = c.por_campo + 1; }
    let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    if encadenado { c.por_campo = c.por_campo - 1; }
    if largo(crudo) == 0 { return vacio(); }
    let base = sin_prestamo(vista(crudo));
    if !es_struct(m, vista(base)) {
        error(c, m, n.linea, $"`{base}` no es un struct, no tiene campos");
        return vacio();
    }
    let nombre = vista(n.texto);
    let ns = campos_nombres(m, vista(base));
    let ts = campos_tipos(m, vista(base));
    var i = 0;
    while i < largo(ns) && i < largo(ts) {
        if igual(vista(ns[i]), nombre) {
            if mover_variables && posee_memoria(m, vista(ts[i])) && c.por_campo == 0
            && !ya_sacado {
                sacar_campo(c, m, n, vista(base), vista(raiz), vista(ruta), ir);
            }
            return copiar(ts[i]);
        }
        i = i + 1;
    }
    error(c, m, n.linea, $"`{base}` no tiene un campo `{nombre}`");
    return vacio();
}

fn indice(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    mover_variables: bool) -> str {
    let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let ti = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    if largo(ti) > 0 && !encaja("usize", vista(ti)) {
        error(c, m, n.linea, $"un indice tiene que ser `usize`, es `{ti}`");
    }
    if largo(crudo) == 0 { return vacio(); }
    let base = sin_prestamo(vista(crudo));
    let b = vista(base);
    if !T.es_arreglo(b) && !T.es_lista(b) && !T.es_bloque(b) {
        error(c, m, n.linea, $"`{base}` no es un arreglo, no se puede indexar");
        return vacio();
    }
    var elem = vacio();
    if T.es_arreglo(b) { elem = elem_arreglo(b); }
    else if T.es_bloque(b) { elem = elem_bloque(b); }
    else { elem = elem_lista(b); }
    if mover_variables && posee_memoria(m, vista(elem)) {
        var que = nuevo("un arreglo");
        if T.es_bloque(b) { que = nuevo("un bloque"); }
        else if T.es_lista(b) { que = nuevo("una lista"); }
        error(c, m, n.linea, $"no se puede sacar un elemento de {que} y dejar el hueco sin duenio. Si quieres sacarlo, di que dejas en su sitio: `intercambiar(...)`. Si solo quieres leerlo, `copiar(...)`");
    }
    return elem;
}

// `Par { a: 7, b: nuevo("x") }` no dice sus tipos: salen de donde va, o de
// lo que hay en los campos.
fn tipo_de_literal_generico(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto,
    n: &P.Nodo, base: view, destino: view) -> str {
    let sueltos = I.lista_de(m.st_params, base) sino [];
    if largo(destino) > 0 && I.es_aplicacion(destino) {
        let bd = I.base_de_aplicacion(destino);
        let args = T.partir_tipos(T.entre_angulos(destino));
        if igual(vista(bd), base) && largo(args) == largo(sueltos) {
            registrar_tipo(m, destino);
            return nuevo(destino);
        }
    }
    var lig: mapa<str, str> = [];
    let ns = I.lista_de(m.st_nombres, base) sino [];
    let ts = I.lista_de(m.st_tipos, base) sino [];
    for h en n.hijos {
        var k = 0;
        while k < largo(ns) && !igual(vista(ns[k]), vista(h.texto)) { k = k + 1; }
        if k >= largo(ns) || k >= largo(ts) || largo(h.hijos) == 0 { continue; }
        var dado = tipo_probable(c, m, tipos, h.hijos[0]);
        if igual(vista(dado), literal()) { dado = nuevo("usize"); }
        if T.es_referencia(vista(dado)) { dado = nuevo(T.apuntado(vista(dado))); }
        let _u = unificar_tipo(vista(ts[k]), vista(dado), sueltos, lig);
    }
    var faltan: lista<str> = [];
    for tp en sueltos {
        if !tiene(lig, vista(tp)) { anadir(faltan, copiar(tp)); }
    }
    if largo(faltan) > 0 {
        let cuales = con_comas(faltan);
        error(c, m, n.linea, $"no se puede deducir {cuales} en `{base} {{ ... }}`: ni los campos ni el sitio donde va lo dicen. Escribe el tipo en la declaracion: `let x: {base}<...> = ...`");
        return vacio();
    }
    var t = nuevo(base);
    empujar(t, "<");
    var i = 0;
    while i < largo(sueltos) {
        if i > 0 { empujar(t, ", "); }
        let puesto = obtener(lig, vista(sueltos[i])) sino "";
        empujar(t, puesto);
        i = i + 1;
    }
    empujar(t, ">");
    registrar_tipo(m, vista(t));
    return t;
}

fn literal_struct(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    destino: view) -> str {
    var tipo = I.sin_modulo(vista(n.texto));
    if tiene(m.st_params, vista(tipo)) {
        let resuelto = tipo_de_literal_generico(c, m, tipos, n, vista(tipo), destino);
        if largo(resuelto) == 0 {
            for h en n.hijos {
                if largo(h.hijos) > 0 { let _t = comprobar_expresion(c, m, tipos, h.hijos[0], "", false); }
            }
            return vacio();
        }
        tipo = resuelto;
    }
    if !es_struct(m, vista(tipo)) {
        error(c, m, n.linea, $"`{tipo}` no es un struct conocido");
        for h en n.hijos {
            if largo(h.hijos) > 0 { let _t = comprobar_expresion(c, m, tipos, h.hijos[0], "", false); }
        }
        return vacio();
    }
    var dados: lista<str> = [];
    for h en n.hijos {
        let nombre = vista(h.texto);
        let def = campo_tipo(m, vista(tipo), nombre);
        var mueve = false;
        if largo(def) > 0 { mueve = posee_memoria(m, vista(def)); }
        var t = vacio();
        if largo(h.hijos) > 0 { t = comprobar_expresion(c, m, tipos, h.hijos[0], vista(def), mueve); }
        if largo(def) == 0 {
            error(c, m, n.linea, $"`{tipo}` no tiene un campo `{nombre}`");
            continue;
        }
        if esta_entre(dados, nombre) {
            error(c, m, n.linea, $"el campo `{nombre}` se da dos veces");
        }
        anadir(dados, nuevo(nombre));
        if largo(t) > 0 && !encaja(vista(def), vista(t)) {
            error(c, m, n.linea, $"`{tipo}.{nombre}` es `{def}` y recibio `{t}`");
        }
    }
    var faltan: lista<str> = [];
    for x en campos_nombres(m, vista(tipo)) {
        if !esta_entre(dados, vista(x)) { anadir(faltan, copiar(x)); }
    }
    if largo(faltan) > 0 {
        let cuales = con_comas(faltan);
        error(c, m, n.linea, $"a `{tipo}` le faltan campos: {cuales}");
    }
    return tipo;
}

fn literal_arreglo(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    esperado: view) -> str {
    if largo(esperado) > 0 && T.es_mapa(esperado) {
        if largo(n.hijos) > 0 {
            error(c, m, n.linea, "un mapa se llena con `poner`; el unico literal que admite es `[]`");
        }
        return nuevo(esperado);
    }
    let es_lista_esperada = largo(esperado) > 0 && T.es_lista(esperado);
    if largo(n.hijos) == 0 && !es_lista_esperada {
        if largo(esperado) == 0 {
            error(c, m, n.linea, "`[]` vacio no dice si es una lista, un arreglo o un mapa: escribe el tipo, como `let xs: lista<usize> = [];`");
        } else {
            error(c, m, n.linea, "un arreglo tiene que tener al menos un elemento");
        }
        return vacio();
    }
    var elem_esperado = vacio();
    if es_lista_esperada {
        elem_esperado = elem_lista(esperado);
    } else if largo(esperado) > 0 && T.es_arreglo(esperado) {
        elem_esperado = elem_arreglo(esperado);
        let cuantos = largo_arreglo(esperado);
        let hay = texto(largo(n.hijos));
        if !igual(vista(cuantos), vista(hay)) {
            error(c, m, n.linea, $"el tipo dice {cuantos} elemento(s) y el literal tiene {hay}");
        }
    }
    var tipos_e: lista<str> = [];
    var mueve = false;
    if largo(elem_esperado) > 0 { mueve = posee_memoria(m, vista(elem_esperado)); }
    for x en n.hijos {
        anadir(tipos_e, comprobar_expresion(c, m, tipos, x, vista(elem_esperado), mueve));
    }
    if largo(elem_esperado) > 0 {
        var i = 0;
        while i < largo(tipos_e) {
            let t = vista(tipos_e[i]);
            if largo(t) > 0 && !encaja(vista(elem_esperado), t) {
                let k = i + 1;
                error(c, m, n.linea, $"el elemento {k} deberia ser `{elem_esperado}` y es `{t}`");
            }
            i = i + 1;
        }
        if es_lista_esperada { return nuevo(esperado); }
        let hay = largo(n.hijos);
        return $"[{elem_esperado}; {hay}]";
    }
    var conocidos: lista<str> = [];
    for t en tipos_e {
        if largo(t) > 0 { anadir(conocidos, copiar(t)); }
    }
    if largo(conocidos) == 0 { return vacio(); }
    var elem = copiar(conocidos[0]);
    for t en conocidos {
        if !igual(vista(t), literal()) { elem = copiar(t); break; }
    }
    var i = 0;
    while i < largo(tipos_e) {
        let t = vista(tipos_e[i]);
        if largo(t) > 0 && !encaja(vista(elem), t) {
            let k = i + 1;
            error(c, m, n.linea, $"los elementos de un arreglo tienen que ser del mismo tipo: el 1 es `{elem}` y el {k} es `{t}`");
        }
        i = i + 1;
    }
    let final = concreto(vista(elem));
    let hay = largo(n.hijos);
    return $"[{final}; {hay}]";
}

fn binaria(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> str {
    let op = vista(n.texto);
    let crudo_i = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    var crudo_d = vacio();
    let logico = igual(op, "&&") || igual(op, "||");
    if logico {
        c.en_condicional = c.en_condicional + 1;
        crudo_d = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
        c.en_condicional = c.en_condicional - 1;
    } else {
        crudo_d = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    }
    if logico {
        if largo(crudo_i) > 0 && !igual(vista(crudo_i), "bool") {
            error(c, m, n.linea, $"`{op}` necesita `bool`, el lado izquierdo es `{crudo_i}`");
        }
        if largo(crudo_d) > 0 && !igual(vista(crudo_d), "bool") {
            error(c, m, n.linea, $"`{op}` necesita `bool`, el lado derecho es `{crudo_d}`");
        }
        return nuevo("bool");
    }
    if largo(crudo_i) == 0 || largo(crudo_d) == 0 { return vacio(); }
    var ti = sin_prestamo(vista(crudo_i));
    var td = sin_prestamo(vista(crudo_d));
    let li = igual(vista(ti), literal()) || igual(vista(ti), literal_decimal());
    let ld = igual(vista(td), literal()) || igual(vista(td), literal_decimal());
    let desplaza = igual(op, "<<") || igual(op, ">>");
    if li && es_numerico(vista(td)) {
        comprobar_literal(c, m, n.hijos[0], vista(td));
        fijar_literal(c, m, n.hijos[0], vista(td));
        ti = copiar(td);
    } else if ld && es_numerico(vista(ti)) {
        comprobar_literal(c, m, n.hijos[1], vista(ti));
        if desplaza { fijar_literal(c, m, n.hijos[1], "usize"); }
        else { fijar_literal(c, m, n.hijos[1], vista(ti)); }
        td = copiar(ti);
    }
    if igual(vista(ti), literal()) && igual(vista(td), literal_decimal()) {
        fijar_literal(c, m, n.hijos[0], literal_decimal());
        ti = copiar(td);
    } else if igual(vista(td), literal()) && igual(vista(ti), literal_decimal()) {
        fijar_literal(c, m, n.hijos[1], literal_decimal());
        td = copiar(ti);
    }
    // Cuanto se desplaza llega siempre como `usize`.
    if desplaza && es_numerico(vista(td)) { fijar_literal(c, m, n.hijos[1], "usize"); }
    let a = vista(ti);
    let b = vista(td);
    if igual(op, "==") || igual(op, "!=") {
        if !igual(a, b) {
            error(c, m, n.linea, $"no se pueden comparar `{ti}` y `{td}`");
        }
        if igual(a, "str") {
            error(c, m, n.linea, "no se comparan `str` con `==`: usa `igual(vista(a), vista(b))`");
        }
        if es_decimal(a) {
            aviso(c, m, n.linea, $"`{op}` entre decimales compara bit a bit: `0.1 + 0.2` no es `0.3`. Si querias 'aproximadamente', usa `cerca(a, b, tolerancia)` de `std/numero`");
        }
        return nuevo("bool");
    }
    if igual(op, "<") || igual(op, "<=") || igual(op, ">") || igual(op, ">=") {
        if !igual(a, literal()) && !igual(a, literal_decimal())
        && (!es_numerico(a) || !es_numerico(b)) {
            error(c, m, n.linea, $"`{op}` necesita enteros, recibio `{ti}` y `{td}`");
        } else if !igual(a, b) {
            error(c, m, n.linea, $"`{ti}` y `{td}` no se mezclan sin conversion explicita");
        }
        return nuevo("bool");
    }
    if igual(op, "&") || igual(op, "|") || igual(op, "^") || igual(op, "<<") || igual(op, ">>") {
        if igual(a, literal()) && igual(b, literal()) { return nuevo(literal()); }
        if !es_tipo_entero(a) || !es_tipo_entero(b) {
            error(c, m, n.linea, $"`{op}` trabaja sobre los bits de un entero, recibio `{ti}` y `{td}`");
            return vacio();
        }
        if igual(op, "<<") || igual(op, ">>") { return nuevo(a); }
        if !igual(a, b) {
            error(c, m, n.linea, $"`{ti}` y `{td}` no se mezclan sin conversion explicita");
        }
        return nuevo(a);
    }
    // aritmetica
    if igual(op, "/?") && !igual(a, literal_decimal()) && !igual(b, literal_decimal())
    && !es_decimal(a) && !es_decimal(b) {
        // Entre enteros no hay IEEE que pedir: dividir por cero o `MIN / -1`
        // no tienen un resultado al que volver.
        error(c, m, n.linea, "`/?` es la division IEEE de los decimales; entre enteros no hay vuelta que dar. Usa `/`, que se detiene al dividir por cero");
        return vacio();
    }
    let lit_a = igual(a, literal()) || igual(a, literal_decimal());
    let lit_b = igual(b, literal()) || igual(b, literal_decimal());
    if lit_a && lit_b {
        if igual(a, literal_decimal()) || igual(b, literal_decimal()) {
            return nuevo(literal_decimal());
        }
        return nuevo(literal());
    }
    if igual(op, "%") && (es_decimal(a) || es_decimal(b)) {
        error(c, m, n.linea, "`%` es el resto de una division entera; con decimales no tiene un significado unico");
        return vacio();
    }
    if !es_numerico(a) || !es_numerico(b) {
        error(c, m, n.linea, $"`{op}` necesita enteros, recibio `{ti}` y `{td}`");
        return vacio();
    }
    if !igual(a, b) {
        error(c, m, n.linea, $"`{ti}` y `{td}` no se mezclan sin conversion explicita");
    }
    return nuevo(a);
}

// `match`: exhaustivo, lo que atrapa se presta, y cada brazo es un camino.
fn comprobar_match(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    destino: view, mover_variables: bool) -> str {
    let tv = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    if largo(tv) == 0 { return vacio(); }
    let base = sin_prestamo(vista(tv));
    if !es_enum(m, vista(base)) {
        error(c, m, n.linea, $"`match` mira las formas de un enum, y `{tv}` no es uno");
        return vacio();
    }
    let antes = foto(c);
    var fotos: lista<lista<usize>> = [];
    // Las formas con un brazo que vale para todas ellas, y las que tienen
    // alguno, aunque sea con condiciones.
    var vistas: lista<str> = [];
    var con_brazo: lista<str> = [];
    var comun = vacio();
    var escritos: lista<P.Nodo> = [];
    var hay_comodin = false;
    var k = 1;
    while k < largo(n.hijos) {
        let b = copiar(n.hijos[k]);
        k = k + 1;
        if hay_comodin {
            error(c, m, n.linea, "hay brazos detras del `_`, y no se miran nunca: el `_` vale para todo lo que quede");
            break;
        }
        restaurar_foto(c, antes);
        let posiciones = posiciones_de(b);
        var guarda: i64 = -1;
        var h_i = 0;
        for h en b.hijos {
            if igual(vista(h.clase), "guarda") { guarda = h_i como i64; }
            h_i = h_i + 1;
        }
        // Un brazo con guarda, o con algo que no sea un nombre en alguna
        // posicion, puede no casar: no cubre su forma el solo.
        var condicionado = guarda >= 0;
        for p en posiciones {
            if !igual(vista(p.clase), "atrapa") { condicionado = true; }
        }
        var forma = vacio();
        if largo(b.texto) == 0 {
            if largo(posiciones) > 0 { error(c, m, n.linea, "el brazo `_` no atrapa nada"); }
            if guarda < 0 { hay_comodin = true; }
        } else {
            forma = I.tras_el_punto(vista(b.texto));
            if !tiene_forma(m, vista(base), vista(forma)) {
                let cuales = formas_legibles(m, vista(base));
                error(c, m, n.linea, $"`{base}` no tiene la forma `{forma}`; tiene {cuales}");
                continue;
            }
            if esta_entre(vistas, vista(forma)) {
                error(c, m, n.linea, $"`{base}.{forma}` se mira dos veces; el segundo brazo no se ejecuta nunca");
            }
            if !esta_entre(con_brazo, vista(forma)) { anadir(con_brazo, copiar(forma)); }
            if !condicionado { anadir(vistas, copiar(forma)); }
            if !patron_valido(c, m, n.linea, vista(base), vista(forma), posiciones) { continue; }
        }
        abrir_ambito(c);
        c.en_condicional = c.en_condicional + 1;
        if largo(forma) > 0 {
            let mirado = origenes_mirado(c, m, n.hijos[0]);
            declarar_patron(c, m, n.linea, vista(base), vista(forma), posiciones, mirado);
        }
        if guarda >= 0 {
            let g = copiar(b.hijos[guarda como usize]);
            c.en_guarda = c.en_guarda + 1;
            let tg = comprobar_expresion(c, m, tipos, g.hijos[0], "", false);
            c.en_guarda = c.en_guarda - 1;
            if largo(tg) > 0 && !igual(vista(tg), "bool") {
                error(c, m, n.linea, $"la guarda de un brazo tiene que ser `bool`, es `{tg}`");
            }
        }
        var t = vacio();
        var es_expresion = false;
        for h en b.hijos {
            if igual(vista(h.clase), "retorno") { es_expresion = true; }
        }
        for h en b.hijos {
            let hc = vista(h.clase);
            if igual(hc, "retorno") && largo(h.hijos) > 0 {
                t = comprobar_expresion(c, m, tipos, h.hijos[0], destino, mover_variables);
                if igual(vista(t), literal()) || igual(vista(t), literal_decimal()) {
                    anadir(escritos, copiar(h.hijos[0]));
                }
            } else if igual(hc, "bloque") {
                for st en h.hijos { comprobar_sentencia(c, m, tipos, st); }
            }
        }
        c.en_condicional = c.en_condicional - 1;
        cerrar_ambito(c);
        anadir(fotos, foto(c));
        if es_expresion && largo(t) > 0 && !igual(vista(t), literal())
        && !igual(vista(t), literal_decimal()) {
            if largo(comun) == 0 {
                comun = copiar(t);
            } else if !encaja(vista(t), vista(comun)) && !encaja(vista(comun), vista(t)) {
                error(c, m, n.linea, $"los brazos de un `match` tienen que dar el mismo tipo, y dan `{comun}` y `{t}`");
            }
        }
    }
    if largo(fotos) > 0 {
        var juntas = copiar(fotos[0]);
        var j = 1;
        while j < largo(fotos) {
            juntar_ramas(c, juntas, fotos[j]);
            juntas = foto(c);
            j = j + 1;
        }
    }
    if !hay_comodin {
        var faltan: lista<str> = [];
        var a_medias: lista<str> = [];
        for v en I.lista_de(m.en_variantes, vista(base)) sino [] {
            if !esta_entre(con_brazo, vista(v)) {
                anadir(faltan, $"{base}.{v}");
            } else if !esta_entre(vistas, vista(v)) {
                anadir(a_medias, $"{base}.{v}");
            }
        }
        if largo(faltan) > 0 {
            let cuales = con_comas(faltan);
            error(c, m, n.linea, $"al `match` le faltan formas: {cuales}. Ponlas, o pon un brazo `_` para lo que quede; si no, el dia que anadas una variante este sitio se quedaria callado");
        } else if largo(a_medias) > 0 {
            let cuales = con_comas(a_medias);
            error(c, m, n.linea, $"al `match` le pueden quedar casos de {cuales} sin mirar: sus brazos tienen guarda o un patron que puede no casar. Pon uno que valga para todos, o un brazo `_`");
        }
    }
    // Un brazo que es un numero escrito toma el tipo de los demas, y tiene que
    // caber en el.
    let comun_p = sin_prestamo(vista(comun));
    if es_numerico(vista(comun_p)) {
        for v en escritos {
            comprobar_literal(c, m, v, vista(comun_p));
            fijar_literal(c, m, v, vista(comun_p));
        }
    }
    return comun;
}

// Lo que va en cada posicion de un patron, en orden: hojas `atrapa` y ramas
// `patron` y `literal`.
fn posiciones_de(b: &P.Nodo) -> lista<P.Nodo> {
    var salida: lista<P.Nodo> = [];
    for h en b.hijos {
        let hc = vista(h.clase);
        if igual(hc, "atrapa") || igual(hc, "patron") || igual(hc, "literal") {
            anadir(salida, copiar(h));
        }
    }
    return salida;
}

// Si lo que va en cada posicion de `base.forma(...)` encaja con lo que lleva
// la forma: el numero, las formas anidadas y los literales.
fn patron_valido(c: mut Comprobacion, m: &Mundo, linea: usize, base: view, forma: view,
    posiciones: &lista<P.Nodo>) -> bool {
    let lleva = formas_de(m, base, forma);
    if largo(posiciones) != largo(lleva) {
        let cuantos = cuantos_valores(largo(lleva));
        let atrapados = largo(posiciones);
        error(c, m, linea, $"`{base}.{forma}` lleva {cuantos}, y el patron atrapa {atrapados}");
        return false;
    }
    var i = 0;
    while i < largo(posiciones) {
        let t = copiar(lleva[i]);
        let p = copiar(posiciones[i]);
        i = i + 1;
        let pc = vista(p.clase);
        if igual(pc, "atrapa") { continue; }
        if igual(pc, "patron") {
            let quien = I.antes_del_punto(vista(p.texto));
            let cual = I.tras_el_punto(vista(p.texto));
            if !es_enum(m, vista(t)) || !igual(vista(quien), vista(t)) {
                error(c, m, linea, $"`{base}.{forma}` lleva un `{t}` en la posicion {i}, y el patron pone `{p.texto}`");
                return false;
            }
            if !tiene_forma(m, vista(t), vista(cual)) {
                let cuales = formas_legibles(m, vista(t));
                error(c, m, linea, $"`{t}` no tiene la forma `{cual}`; tiene {cuales}");
                return false;
            }
            if !patron_valido(c, m, linea, vista(t), vista(cual), posiciones_de(p)) { return false; }
            continue;
        }
        let lit = copiar(p.hijos[0]);
        let lc = vista(lit.clase);
        var numero = igual(lc, "entero");
        if igual(lc, "unaria") && igual(vista(lit.texto), "-") && largo(lit.hijos) > 0 {
            numero = igual(vista(lit.hijos[0].clase), "entero");
        }
        if numero && es_tipo_entero(vista(t)) {
            comprobar_literal(c, m, lit, vista(t));
        } else if !((igual(lc, "cadena") && igual(vista(t), "str"))
            || (igual(lc, "booleano") && igual(vista(t), "bool"))) {
            error(c, m, linea, $"`{base}.{forma}` lleva un `{t}` en la posicion {i}, y el literal del patron no es uno");
            return false;
        }
    }
    return true;
}

// Lo que atrapa el patron, prestado: un `match` mira, no desmonta. Un `str`
// prestado es una `view`, y lo demas con duenio un `&T`.
fn declarar_patron(c: mut Comprobacion, m: &Mundo, linea: usize, base: view, forma: view,
    posiciones: &lista<P.Nodo>, mirado: &lista<str>) {
    let lleva = formas_de(m, base, forma);
    var i = 0;
    while i < largo(posiciones) && i < largo(lleva) {
        let t = copiar(lleva[i]);
        let p = copiar(posiciones[i]);
        i = i + 1;
        if igual(vista(p.clase), "patron") {
            let cual = I.tras_el_punto(vista(p.texto));
            declarar_patron(c, m, linea, vista(t), vista(cual), posiciones_de(p), mirado);
        } else if igual(vista(p.clase), "atrapa") && !igual(vista(p.texto), "_") {
            var tp = copiar(t);
            if posee_memoria(m, vista(t)) {
                if igual(vista(t), "str") { tp = nuevo("view"); } else { tp = $"&{t}"; }
            }
            let si = declarar_simbolo(c, m, linea, vista(p.texto), vista(tp), false);
            if !igual(vista(tp), vista(t)) {
                // Lo atrapado apunta dentro del valor mirado: mientras viva,
                // ese valor no se mueve ni se modifica.
                for o en mirado {
                    let d = buscar_simbolo(c, vista(o));
                    if !existe(c, d) || esta_entre(c.simbolos[si].origenes, vista(o)) { continue; }
                    anadir(c.simbolos[si].origenes, copiar(o));
                    anadir(c.simbolos[d].prestamos, copiar(p.texto));
                }
                if largo(c.simbolos[si].origenes) > 0 {
                    c.simbolos[si].origen = copiar(c.simbolos[si].origenes[0]);
                }
            }
        }
    }
}

// Una clausura es su struct con lo capturado mas su funcion, que se
// comprueba aqui, en mitad de quien la escribe, como en el original.
// Dentro del cuerpo, un nombre capturado es un campo del entorno.
fn renombrar_capturas(n: mut P.Nodo, nombres: &lista<str>, linea: usize) {
    var i = 0;
    while i < largo(n.hijos) {
        if igual(vista(n.hijos[i].clase), "variable")
        && esta_entre(nombres, vista(n.hijos[i].texto)) {
            var campo_e = P.rama("campo", n.hijos[i].linea);
            campo_e.texto = copiar(n.hijos[i].texto);
            anadir(campo_e.hijos, P.hoja("variable", "_ss_entorno", linea));
            n.hijos[i] = campo_e;
        } else {
            renombrar_capturas(n.hijos[i], nombres, linea);
        }
        i = i + 1;
    }
}

// La funcion de una clausura: el entorno prestado delante, y despues lo
// suyo, con lo capturado leido del entorno. Si algo se capturo con `mut`, el
// entorno llega para modificar: lo que cambie sigue ahi en la llamada
// siguiente.
fn nodo_de_cierre(n: &P.Nodo, numero: usize, capturadas: &lista<str>,
    modifica: bool) -> P.Nodo {
    var f = P.rama("fn", n.linea);
    f.texto = $"ss_cierre_{numero}";
    var entorno = P.rama("param", n.linea);
    entorno.texto = $"_ss_entorno: &Cierre_{numero}";
    if modifica { entorno.texto = $"_ss_entorno: mut Cierre_{numero}"; }
    anadir(f.hijos, entorno);
    for h en n.hijos {
        if igual(vista(h.clase), "captura") { continue; }
        var x = copiar(h);
        if igual(vista(x.clase), "bloque") { renombrar_capturas(x, capturadas, n.linea); }
        anadir(f.hijos, x);
    }
    return f;
}

// Las clausuras de un cuerpo, numeradas `#0`, `#1`... en preorden. Las de
// dentro de otra son de la otra: se numeran cuando se mira su funcion.
fn etiquetar_cierres(n: mut P.Nodo, cuenta: mut usize) {
    var i = 0;
    while i < largo(n.hijos) {
        if igual(vista(n.hijos[i].clase), "cierre") {
            n.hijos[i].texto = $"#{cuenta}";
            cuenta = cuenta + 1;
        } else {
            etiquetar_cierres(n.hijos[i], cuenta);
        }
        i = i + 1;
    }
}

// Una clausura es su struct con lo capturado mas su funcion, que nace y se
// comprueba aqui, en mitad de quien la escribe, como en el original: por eso
// cada copia de una generica tiene las suyas.
fn cierre(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> str {
    let clave = $"{c.dueno}{n.texto}";
    if tiene(m.numeracion, vista(clave)) {
        let ya = obtener(m.numeracion, vista(clave)) sino 0;
        return $"Cierre_{ya}";
    }
    let numero = m.n_cierres + 1;
    m.n_cierres = numero;
    poner(m.numeracion, vista(clave), numero);
    let st = $"Cierre_{numero}";
    var nombres: lista<str> = [];
    var ts: lista<str> = [];
    var vistos: lista<str> = [];
    var mutables: lista<str> = [];
    for h en n.hijos {
        if igual(vista(h.clase), "captura") && largo(h.hijos) > 0 {
            anadir(mutables, copiar(h.texto));
        }
    }
    for h en n.hijos {
        if !igual(vista(h.clase), "captura") { continue; }
        let nombre = vista(h.texto);
        if esta_entre(vistos, nombre) {
            error(c, m, n.linea, $"`{nombre}` se captura dos veces");
            continue;
        }
        anadir(vistos, nuevo(nombre));
        let i = buscar_simbolo(c, nombre);
        if !existe(c, i) {
            error(c, m, n.linea, $"`{nombre}` no esta declarada, no se puede capturar");
            continue;
        }
        let t = copiar(c.simbolos[i].tipo);
        if presta_tipo(m, vista(t)) {
            var arreglo = $"Captura lo que necesites de `{nombre}`";
            if igual(vista(t), "view") || T.es_referencia(vista(t)) {
                arreglo = $"Captura un `str` con `copiar({nombre})`";
            }
            error(c, m, n.linea, $"`{nombre}` es `{t}`, un prestamo: una clausura captura por valor, y guardar un prestamo exigiria saber cuanto vive. {arreglo}");
            continue;
        }
        anadir(nombres, nuevo(nombre));
        anadir(ts, copiar(t));
        if posee_memoria(m, vista(t)) { mover(c, m, n.linea, i, false); }
        else { let _l = leer(c, m, n.linea, i); }
    }
    if largo(nombres) == 0 {
        anadir(nombres, nuevo("ss_vacio"));
        anadir(ts, nuevo("u8"));
    }
    poner(m.st_tipos, vista(st), ts);
    poner(m.st_nombres, vista(st), nombres);
    anadir(m.orden_structs, copiar(st));
    anadir(m.tipo_de_struct, copiar(st));
    let modifica = largo(mutables) > 0;
    if modifica { anadir(m.cierres_mut, copiar(st)); }
    let fn_nodo = nodo_de_cierre(n, numero, vistos, modifica);
    anadir(m.cierres, copiar(fn_nodo));
    anadir(m.orden_copias, $"ss_cierre_{numero}");
    anadir(m.cierres_mod, c.modulo);
    let de_cierre = $"ss_cierre_{numero}";
    var f = funcion_de(fn_nodo, vista(de_cierre), vista(c.archivo), c.modulo,
        numero - 1, false);
    f.de_cierre = true;
    let k = largo(m.funciones);
    poner(m.indice, vista(de_cierre), k);
    anadir(m.funciones, f);
    // Otra funcion entera: sus propios ambitos y su propio retorno.
    let simbolos = copiar(c.simbolos);
    let inicios = copiar(c.inicios);
    let retorno = copiar(c.retorno);
    let falible = c.falible;
    let dueno = copiar(c.dueno);
    let en_cierre = c.en_cierre;
    let capturas_mut = copiar(c.capturas_mut);
    let modificadas_antes = copiar(c.modificadas);
    c.simbolos = [];
    c.inicios = [];
    c.en_cierre = true;
    c.capturas_mut = copiar(mutables);
    c.modificadas = [];
    comprobar_funcion(c, m, tipos, k, fn_nodo, vista(de_cierre));
    let modificadas = copiar(c.modificadas);
    c.en_cierre = en_cierre;
    c.capturas_mut = capturas_mut;
    c.modificadas = modificadas_antes;
    c.simbolos = simbolos;
    c.inicios = inicios;
    c.retorno = retorno;
    c.falible = falible;
    c.dueno = dueno;
    for nombre en mutables {
        let escrito_n = G.escrito(vista(nombre));
        if !esta_entre(modificadas, vista(nombre)) && !empieza_con(vista(escrito_n), "_") {
            aviso(c, m, n.linea, $"`{nombre}` se captura con `mut` y nunca se modifica; puede ir sin `mut`");
        }
    }
    return st;
}

// ------------------------------------------------------------------
// Llamadas
// ------------------------------------------------------------------

fn llamada(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    desenvuelta: bool, destino: view) -> str {
    let escrito = vista(n.texto);
    let corto = I.sin_modulo(escrito);
    let fi = firma_interna(vista(corto));
    if fi.existe && !contiene(escrito, ".") {
        if fi.falible && !desenvuelta {
            error(c, m, n.linea, $"`{corto}` puede fallar: la llamada tiene que ir detras de `try`, o con `sino <valor>` para dar un valor cuando falle");
        }
        return interna(c, m, tipos, n, vista(corto), destino);
    }

    // Una variable con una clausura dentro se llama como su funcion, con el
    // entorno delante, prestado.
    let iv = buscar_simbolo(c, escrito);
    if existe(c, iv) {
        let tv = sin_prestamo(vista(c.simbolos[iv].tipo));
        let de_cierre = I.funcion_de_cierre(vista(tv));
        if largo(de_cierre) > 0 {
            var otra = P.rama("llamada", n.linea);
            otra.texto = copiar(de_cierre);
            anadir(otra.hijos, P.hoja("variable", escrito, n.linea));
            for h en n.hijos { anadir(otra.hijos, copiar(h)); }
            return llamada(c, m, tipos, otra, desenvuelta, destino);
        }
        if T.es_funcion(vista(c.simbolos[iv].tipo)) {
            return llamada_a_puntero(c, m, tipos, n, iv);
        }
    }

    let k = funcion_llamada(m, tipos, escrito);
    if k >= largo(m.funciones) {
        error(c, m, n.linea, $"`{escrito}` no es una funcion conocida");
        for h en n.hijos { let _t = comprobar_expresion(c, m, tipos, h, "", false); }
        return vacio();
    }
    var f = copiar(m.funciones[k]);
    // A quien se entrega lo que se mueve: la copia, si es una generica.
    var destinataria = copiar(f.nombre);
    if tiene_sueltos(f) {
        let inst = instanciar(c, m, tipos, n, k);
        if !inst.ok {
            for h en n.hijos { let _t = comprobar_expresion(c, m, tipos, h, "", false); }
            return vacio();
        }
        f.params = copiar(inst.params);
        f.retorno = copiar(inst.retorno);
        destinataria = copiar(inst.copia);
    }
    let nombre = vista(f.nombre);
    if f.falible && !desenvuelta {
        error(c, m, n.linea, $"`{nombre}` puede fallar: la llamada tiene que ir detras de `try`, o con `sino <valor>` para dar un valor cuando falle");
    }
    if largo(n.hijos) != largo(f.params) {
        let pide = largo(f.params);
        let dados = largo(n.hijos);
        error(c, m, n.linea, $"`{nombre}` espera {pide} argumento(s) y recibio {dados}");
    }
    // Dos prestamos de lo mismo solo conviven si ninguno modifica.
    var prestados_mut: mapa<str, str> = [];
    var prestados_lec: mapa<str, str> = [];
    var i = 0;
    while i < largo(n.hijos) && i < largo(f.params) {
        let arg = copiar(n.hijos[i]);
        let p = copiar(f.params[i]);
        i = i + 1;
        if prestado(p) {
            let base = variable_base(arg);
            let is = buscar_simbolo(c, vista(base));
            if largo(base) == 0 || !existe(c, is) {
                let t_arg = comprobar_expresion(c, m, tipos, arg, "", false);
                if largo(t_arg) > 0 && !encaja(vista(p.tipo), vista(t_arg)) {
                    error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `{p.tipo}` y recibio `{t_arg}`");
                } else if p.mutable {
                    error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `mut`: modificar algo recien hecho no le sirve a nadie, pasale una variable");
                }
                continue;
            }
            let tipo_arg = tipo_de_lugar(c, m, tipos, arg);
            if largo(tipo_arg) > 0 && !igual(vista(tipo_arg), vista(p.tipo)) {
                error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `{p.tipo}` y recibio `{tipo_arg}`");
            }
            var otro = nuevo(obtener(prestados_mut, vista(base)) sino "");
            if largo(otro) == 0 && p.mutable {
                otro = nuevo(obtener(prestados_lec, vista(base)) sino "");
            }
            if largo(otro) > 0 {
                var dos: lista<str> = [];
                anadir(dos, copiar(p.nombre));
                anadir(dos, copiar(otro));
                ordenar(dos);
                error(c, m, n.linea, $"`{base}` se presta dos veces en la misma llamada a `{nombre}` (como `{dos[0]}` y como `{dos[1]}`), y al menos uno de los dos puede modificarlo. v0 mira la variable entera, asi que rechaza esto aunque sean campos distintos");
            }
            if p.mutable {
                mutar(c, m, arg, arg.linea, is, false);
                // Quien lo recibe casi siempre lee antes de escribir.
                c.simbolos[is].leida = true;
                poner(prestados_mut, vista(base), copiar(p.nombre));
            } else {
                let _l = leer(c, m, arg.linea, is);
                poner(prestados_lec, vista(base), copiar(p.nombre));
            }
            continue;
        }
        // Una funcion de C mira la cadena, no se la queda.
        let mueve = posee_memoria(m, vista(p.tipo)) && !f.externa;
        if mueve && igual(vista(arg.clase), "variable") {
            let ia = buscar_simbolo(c, vista(arg.texto));
            if existe(c, ia) { c.simbolos[ia].movida_a = copiar(destinataria); }
        }
        let t = comprobar_expresion(c, m, tipos, arg, vista(p.tipo), mueve);
        // Una vista que se pasa tambien presta, aunque no tenga nombre:
        // `g(s, vista(s))` con `a: mut str` dejaria a `g` modificando por un
        // lado lo que lee por el otro. Es el fallo 2 de la especificacion.
        if presta_tipo(m, vista(p.tipo)) && !f.externa {
            for base en prestados_por(c, m, arg, vista(t)) {
                let otro = nuevo(obtener(prestados_mut, vista(base)) sino "");
                if largo(otro) > 0 {
                    var dos: lista<str> = [];
                    anadir(dos, copiar(p.nombre));
                    anadir(dos, copiar(otro));
                    ordenar(dos);
                    error(c, m, n.linea, $"`{base}` se presta dos veces en la misma llamada a `{nombre}` (como `{dos[0]}` y como `{dos[1]}`), y al menos uno de los dos puede modificarlo. v0 mira la variable entera, asi que rechaza esto aunque sean campos distintos");
                }
                if !tiene(prestados_lec, vista(base)) {
                    poner(prestados_lec, vista(base), copiar(p.nombre));
                }
            }
        }
        if igual(vista(p.tipo), "view") && igual(vista(t), "str") { continue; }
        if largo(t) > 0 && !encaja(vista(p.tipo), vista(t)) {
            if largo(I.funcion_de_cierre(vista(t))) > 0 && T.es_funcion(vista(p.tipo)) {
                error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `{p.tipo}`, un puntero a funcion, y recibio una clausura. Una clausura lleva dentro lo que capturo, asi que no cabe en un puntero: haz el parametro generico (`{p.nombre}: F`) y valdra para las dos");
            } else {
                error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `{p.tipo}` y recibio `{t}`");
            }
        }
    }
    if largo(f.retorno) > 0 {
        if f.cadena_c { return nuevo("str"); }
        return copiar(f.retorno);
    }
    return nuevo("()");
}

// Una variable que guarda una funcion se llama como cualquier otra.
fn llamada_a_puntero(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    iv: usize) -> str {
    let _l = leer(c, m, n.linea, iv);
    let tv = copiar(c.simbolos[iv].tipo);
    let nombre = vista(n.texto);
    let partes = T.partes_de_funcion(vista(tv));
    var params: lista<str> = [];
    var i = 0;
    while i + 1 < largo(partes) {
        anadir(params, copiar(partes[i]));
        i = i + 1;
    }
    if largo(n.hijos) != largo(params) {
        let pide = largo(params);
        let dados = largo(n.hijos);
        error(c, m, n.linea, $"`{nombre}` es `{tv}` y espera {pide} argumento(s), recibio {dados}");
    }
    // Los prestamos de una misma llamada, como en una funcion con nombre: la
    // firma del puntero dice lo mismo que la de ella.
    var prestados_mut: mapa<str, str> = [];
    var prestados_lec: mapa<str, str> = [];
    var k = 0;
    while k < largo(n.hijos) && k < largo(params) {
        let esperado = vista(params[k]);
        let presta = T.es_referencia(esperado);
        let dentro = sin_prestamo(esperado);
        let mueve = !presta && posee_memoria(m, vista(dentro));
        let t = comprobar_expresion(c, m, tipos, n.hijos[k], vista(dentro), mueve);
        let cual = $"el argumento {k + 1}";
        if presta {
            let base = variable_base(n.hijos[k]);
            let is = buscar_simbolo(c, vista(base));
            if largo(base) > 0 && existe(c, is) {
                let mutable = es_referencia_mutable(esperado);
                var otro = nuevo(obtener(prestados_mut, vista(base)) sino "");
                if largo(otro) == 0 && mutable {
                    otro = nuevo(obtener(prestados_lec, vista(base)) sino "");
                }
                if largo(otro) > 0 {
                    error(c, m, n.linea, $"`{base}` se presta dos veces en la misma llamada a `{nombre}` ({otro} y {cual}), y al menos uno de los dos puede modificarlo");
                }
                if mutable {
                    mutar(c, m, n.hijos[k], n.hijos[k].linea, is, false);
                    poner(prestados_mut, vista(base), copiar(cual));
                } else {
                    let _u = leer(c, m, n.hijos[k].linea, is);
                    if !tiene(prestados_lec, vista(base)) {
                        poner(prestados_lec, vista(base), copiar(cual));
                    }
                }
            }
        } else if presta_tipo(m, vista(dentro)) {
            for base en prestados_por(c, m, n.hijos[k], vista(t)) {
                let otro = nuevo(obtener(prestados_mut, vista(base)) sino "");
                if largo(otro) > 0 {
                    error(c, m, n.linea, $"`{base}` se presta dos veces en la misma llamada a `{nombre}` ({otro} y {cual}), y al menos uno de los dos puede modificarlo");
                }
                if !tiene(prestados_lec, vista(base)) {
                    poner(prestados_lec, vista(base), copiar(cual));
                }
            }
        }
        let limpio = sin_prestamo(vista(t));
        if largo(t) > 0 && !encaja(vista(dentro), vista(limpio)) {
            if !(igual(vista(dentro), "view") && igual(vista(limpio), "str")) {
                error(c, m, n.linea, $"`{nombre}` toma `{esperado}` ahi y recibio `{t}`");
            }
        }
        k = k + 1;
    }
    if largo(partes) == 0 { return vacio(); }
    return copiar(partes[largo(partes) - 1]);
}

// ------------------------------------------------------------------
// Las internas
// ------------------------------------------------------------------

fn evaluar_todos(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) {
    for h en n.hijos { let _t = comprobar_expresion(c, m, tipos, h, "", false); }
}

fn interna(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    nombre: view, destino: view) -> str {
    let fi = firma_interna(nombre);
    let dados = largo(n.hijos);

    if igual(nombre, "igual") || igual(nombre, "menor") {
        if dados != 2 {
            error(c, m, n.linea, $"`{nombre}` espera 2 argumentos y recibio {dados}");
            evaluar_todos(c, m, tipos, n);
            return nuevo("bool");
        }
        let a0 = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
        let ta = sin_prestamo(vista(a0));
        let a1 = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
        let tb = sin_prestamo(vista(a1));
        var validos = comparables();
        if igual(nombre, "igual") { validos = igualables(); }
        let cuales = con_comas(validos);
        if largo(ta) > 0 && !igual(vista(ta), literal()) && !esta_entre(validos, vista(ta)) {
            error(c, m, n.linea, $"`{nombre}` compara {cuales}, y recibio `{ta}`");
            return nuevo("bool");
        }
        if largo(tb) > 0 && !igual(vista(tb), literal()) && !esta_entre(validos, vista(tb)) {
            error(c, m, n.linea, $"`{nombre}` compara {cuales}, y recibio `{tb}`");
            return nuevo("bool");
        }
        let texto_a = igual(vista(ta), "str") || igual(vista(ta), "view");
        let texto_b = igual(vista(tb), "str") || igual(vista(tb), "view");
        if largo(ta) > 0 && largo(tb) > 0 && !(texto_a && texto_b) {
            var a = copiar(ta);
            var b = copiar(tb);
            if igual(vista(a), literal()) { a = nuevo("usize"); }
            if igual(vista(b), literal()) { b = nuevo("usize"); }
            if !igual(vista(a), vista(b)) {
                error(c, m, n.linea, $"`{nombre}` compara dos valores del mismo tipo, y recibio `{ta}` y `{tb}`");
            }
        }
        return nuevo("bool");
    }

    if igual(nombre, "raiz") || igual(nombre, "piso") || igual(nombre, "techo")
    || igual(nombre, "redondear") || igual(nombre, "absoluto") {
        if dados != 1 {
            error(c, m, n.linea, $"`{nombre}` espera 1 argumento y recibio {dados}");
            evaluar_todos(c, m, tipos, n);
            return vacio();
        }
        let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
        let t = sin_prestamo(vista(crudo));
        if igual(vista(t), literal_decimal()) { return nuevo("f64"); }
        if igual(nombre, "absoluto") {
            if igual(vista(t), literal()) { return nuevo("i64"); }
            if !es_decimal(vista(t)) && !es_con_signo(vista(t)) {
                error(c, m, n.linea, $"`absoluto` necesita un numero con signo, recibio `{t}`");
                return vacio();
            }
            return t;
        }
        if igual(vista(t), literal()) { return nuevo("f64"); }
        if !es_decimal(vista(t)) {
            error(c, m, n.linea, $"`{nombre}` trabaja sobre decimales, recibio `{t}`");
            return vacio();
        }
        return t;
    }

    if igual(nombre, "reservar") {
        if dados != 1 {
            error(c, m, n.linea, $"`reservar` espera 1 argumento (cuantos) y recibio {dados}");
            evaluar_todos(c, m, tipos, n);
            return vacio();
        }
        let t = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
        if largo(t) > 0 && !encaja("usize", vista(t)) {
            error(c, m, n.linea, $"`reservar` espera cuantos elementos, un `usize`, y recibio `{t}`");
        }
        if largo(destino) == 0 || !T.es_bloque(destino) {
            error(c, m, n.linea, "`reservar(n)` necesita saber de que: escribelo en la declaracion, `var b: bloque<str> = reservar(4);`");
            return vacio();
        }
        return nuevo(destino);
    }

    if igual(nombre, "redimensionar") {
        if dados != 2 {
            error(c, m, n.linea, $"`redimensionar` espera 2 argumentos y recibio {dados}");
            evaluar_todos(c, m, tipos, n);
            return nuevo("()");
        }
        let base = variable_base(n.hijos[0]);
        let is = buscar_simbolo(c, vista(base));
        let sitio = tipo_de_lugar(c, m, tipos, n.hijos[0]);
        let t_sitio = sin_prestamo(vista(sitio));
        if largo(base) == 0 || !existe(c, is) || !T.es_bloque(vista(t_sitio)) {
            error(c, m, n.linea, "`redimensionar` cambia el tamaño de un bloque, y necesita un sitio que lo sea: una variable, un campo o un elemento");
            let _t = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
            return nuevo("()");
        }
        let por_ref = T.es_referencia(vista(c.simbolos[is].tipo));
        mutar(c, m, n.hijos[0], n.hijos[0].linea, is, por_ref);
        anadir(c.simbolos[is].prestamos, nuevo("redimensionar"));
        let t = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
        soltar_prestamo(c, is, "redimensionar");
        if largo(t) > 0 && !encaja("usize", vista(t)) {
            error(c, m, n.linea, $"`redimensionar` espera el tamaño nuevo, un `usize`, y recibio `{t}`");
        }
        return nuevo("()");
    }

    if igual(nombre, "intercambiar") {
        if dados != 2 {
            error(c, m, n.linea, $"`intercambiar` espera 2 argumentos y recibio {dados}");
            evaluar_todos(c, m, tipos, n);
            return vacio();
        }
        let base = variable_base(n.hijos[0]);
        let is = buscar_simbolo(c, vista(base));
        if largo(base) == 0 || !existe(c, is) {
            error(c, m, n.linea, "`intercambiar` necesita un sitio: una variable, un campo o un elemento, no una expresion suelta");
            let _t = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
            return vacio();
        }
        let t = tipo_de_lugar(c, m, tipos, n.hijos[0]);
        if largo(t) > 0 && presta_tipo(m, vista(t)) {
            error(c, m, n.linea, $"`intercambiar` no cambia prestamos: `{t}` apunta a memoria de otro. Asigna con `=`");
        }
        let por_ref = T.es_referencia(vista(c.simbolos[is].tipo));
        mutar(c, m, n.hijos[0], n.hijos[0].linea, is, por_ref);
        anadir(c.simbolos[is].prestamos, nuevo("intercambiar"));
        var mueve = false;
        if largo(t) > 0 { mueve = posee_memoria(m, vista(t)); }
        let tv = comprobar_expresion(c, m, tipos, n.hijos[1], vista(t), mueve);
        soltar_prestamo(c, is, "intercambiar");
        if largo(t) > 0 && largo(tv) > 0 && !encaja(vista(t), vista(tv)) {
            error(c, m, n.linea, $"`intercambiar` pone y saca lo mismo: el sitio es `{t}` y el valor es `{tv}`");
        }
        return t;
    }

    if igual(nombre, "copiar") {
        if dados != 1 {
            error(c, m, n.linea, $"`copiar` espera 1 argumento y recibio {dados}");
            evaluar_todos(c, m, tipos, n);
            return vacio();
        }
        let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
        if largo(crudo) == 0 { return vacio(); }
        let t = sin_prestamo(vista(crudo));
        if igual(vista(t), "view") {
            error(c, m, n.linea, "una vista no es duenia de nada que copiar: si quieres el texto, `nuevo(v)` te da un `str`");
            return nuevo("str");
        }
        if igual(vista(t), literal()) { return nuevo("usize"); }
        if !almacenable(m, vista(t)) {
            error(c, m, n.linea, $"`copiar` no sabe copiar un `{t}`");
            return t;
        }
        return t;
    }

    if igual(nombre, "largo") {
        if dados != 1 {
            error(c, m, n.linea, $"`largo` espera 1 argumento y recibio {dados}");
            evaluar_todos(c, m, tipos, n);
            return nuevo("usize");
        }
        let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
        let t = sin_prestamo(vista(crudo));
        let x = vista(t);
        if largo(crudo) > 0 && !igual(x, "view") && !igual(x, "str") && !T.es_arreglo(x)
        && !T.es_lista(x) && !T.es_mapa(x) && !T.es_bloque(x) {
            error(c, m, n.linea, $"`largo` opera sobre texto, arreglos, listas o mapas, recibio `{t}`");
        }
        return nuevo("usize");
    }

    if igual(nombre, "anadir") {
        if dados != 2 {
            error(c, m, n.linea, $"`anadir` espera 2 argumentos y recibio {dados}");
            evaluar_todos(c, m, tipos, n);
            return nuevo("()");
        }
        let base = variable_base(n.hijos[0]);
        let is = buscar_simbolo(c, vista(base));
        var tipo_lista = vacio();
        let hay = largo(base) > 0 && existe(c, is);
        if hay { tipo_lista = tipo_de_lugar(c, m, tipos, n.hijos[0]); }
        if !hay {
            error(c, m, n.linea, "el primer argumento de `anadir` tiene que ser una variable, un campo o un elemento");
        } else if !T.es_lista(vista(tipo_lista)) {
            let visto = texto_o_none(vista(tipo_lista));
            error(c, m, n.linea, $"`anadir` opera sobre `lista<T>`, recibio `{visto}`");
        } else {
            let elem = elem_lista(vista(tipo_lista));
            let t = comprobar_expresion(c, m, tipos, n.hijos[1], vista(elem), posee_memoria(m, vista(elem)));
            if largo(t) > 0 && !encaja(vista(elem), vista(t)) {
                error(c, m, n.linea, $"la lista guarda `{elem}` y se intento agregar `{t}`");
            }
            mutar(c, m, n.hijos[0], n.hijos[0].linea, is, false);
            return nuevo("()");
        }
        let _t = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
        return nuevo("()");
    }

    if igual(nombre, "ordenar") {
        if dados != 1 {
            error(c, m, n.linea, $"`ordenar` espera 1 argumento y recibio {dados}");
            evaluar_todos(c, m, tipos, n);
            return nuevo("()");
        }
        let base = variable_base(n.hijos[0]);
        let is = buscar_simbolo(c, vista(base));
        let hay = largo(base) > 0 && existe(c, is);
        var t = vacio();
        if hay { t = tipo_de_lugar(c, m, tipos, n.hijos[0]); }
        if !hay {
            error(c, m, n.linea, "`ordenar` necesita una variable, un campo o un elemento");
        } else if !T.es_lista(vista(t)) {
            let visto = texto_o_none(vista(t));
            error(c, m, n.linea, $"`ordenar` opera sobre `lista<T>`, recibio `{visto}`");
        } else {
            let e = elem_lista(vista(t));
            let ords = ordenables();
            if !esta_entre(ords, vista(e)) {
                let cuales = con_comas(ords);
                error(c, m, n.linea, $"`{e}` no tiene un orden natural; `ordenar` funciona sobre {cuales}");
            } else {
                mutar(c, m, n.hijos[0], n.hijos[0].linea, is, false);
            }
        }
        return nuevo("()");
    }

    if igual(nombre, "poner") || igual(nombre, "obtener") || igual(nombre, "obtener_mut")
    || igual(nombre, "tiene") || igual(nombre, "claves") || igual(nombre, "quitar") {
        return interna_mapa(c, m, tipos, n, nombre);
    }

    if igual(nombre, "texto") {
        if dados != 1 {
            error(c, m, n.linea, $"`texto` espera 1 argumento y recibio {dados}");
            evaluar_todos(c, m, tipos, n);
            return nuevo("str");
        }
        let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
        let t = sin_prestamo(vista(crudo));
        let x = vista(t);
        if largo(t) > 0 && !es_tipo_entero(x) && !igual(x, literal()) && !igual(x, "bool")
        && !igual(x, "view") && !igual(x, "str") {
            error(c, m, n.linea, $"`texto` convierte escalares o texto, recibio `{t}`");
        }
        return nuevo("str");
    }

    if dados != largo(fi.params) {
        let pide = largo(fi.params);
        error(c, m, n.linea, $"`{nombre}` espera {pide} argumento(s) y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return copiar(fi.retorno);
    }

    // Paso 1: los argumentos, y los prestamos que duran lo que la llamada.
    var prestados: lista<str> = [];
    var i = 0;
    while i < dados {
        let esperado = vista(fi.params[i]);
        let arg = copiar(n.hijos[i]);
        let k = i + 1;
        i = i + 1;
        if igual(esperado, "@mut") { continue; }
        if igual(esperado, "@presta") {
            let base = variable_base(arg);
            let is = buscar_simbolo(c, vista(base));
            if largo(base) == 0 || !existe(c, is) {
                error(c, m, n.linea, $"`{nombre}` necesita una variable, un campo o un elemento, no una expresion suelta");
                continue;
            }
            let crudo = tipo_de_lugar(c, m, tipos, arg);
            let t_presta = sin_prestamo(vista(crudo));
            if !igual(vista(t_presta), "str") {
                error(c, m, n.linea, $"`{nombre}` presta de un `str`");
                continue;
            }
            let _l = leer(c, m, arg.linea, is);
            anadir(prestados, copiar(base));
            continue;
        }
        let t = comprobar_expresion(c, m, tipos, arg, "", false);
        if largo(t) > 0 && !igual(esperado, "@cualquiera") && !encaja(esperado, vista(t)) {
            let limpio = sin_prestamo(vista(t));
            if !(igual(esperado, "view") && igual(vista(limpio), "str")) {
                error(c, m, n.linea, $"el argumento {k} de `{nombre}` debe ser `{esperado}` y es `{t}`");
            }
        }
        if igual(esperado, "@cualquiera") && largo(t) > 0
        && (T.es_arreglo(vista(t)) || es_struct(m, vista(t))) {
            error(c, m, n.linea, $"`{nombre}` no sabe mostrar un `{t}`: muestra sus campos o elementos por separado");
        }
        if igual(esperado, "view") {
            // Todos los duenios posibles, no el primero: con
            // `if c { vista(a) } else { vista(b) }` puede ser cualquiera.
            var origenes: lista<str> = [];
            for o en origenes_de(c, m, arg) {
                if !igual(vista(o), "<temporal>") { anadir(origenes, copiar(o)); }
            }
            if largo(origenes) == 0 && igual(vista(arg.clase), "variable") && igual(vista(t), "str") {
                anadir(origenes, copiar(arg.texto));
            }
            for o en origenes { anadir(prestados, copiar(o)); }
        }
    }

    // Paso 2: los efectos, que ya ven los prestamos del paso 1. Esto es lo
    // que rechaza `empujar(s, vista(s))`.
    var j = 0;
    while j < dados {
        let k = j + 1;
        let esperado = vista(fi.params[j]);
        let arg = copiar(n.hijos[j]);
        j = j + 1;
        if !igual(esperado, "@mut") { continue; }
        let base = variable_base(arg);
        let is = buscar_simbolo(c, vista(base));
        if largo(base) == 0 || !existe(c, is) {
            error(c, m, n.linea, $"el argumento {k} de `{nombre}` tiene que ser una variable, un campo o un elemento");
            continue;
        }
        let crudo = tipo_de_lugar(c, m, tipos, arg);
        let t_lugar = sin_prestamo(vista(crudo));
        if !igual(vista(t_lugar), "str") {
            error(c, m, n.linea, $"`{nombre}` opera sobre `str`");
            continue;
        }
        if esta_entre(prestados, vista(base)) {
            error(c, m, n.linea, $"`{base}` se presta y se modifica en la misma llamada a `{nombre}`: al crecer, el buffer puede moverse y dejar la vista colgando");
            continue;
        }
        let por_ref = !igual(vista(arg.clase), "variable")
        || T.es_referencia(vista(c.simbolos[is].tipo));
        mutar(c, m, arg, arg.linea, is, por_ref);
    }
    return copiar(fi.retorno);
}

// `poner`, `obtener`, `tiene`, `claves`, `quitar` y `obtener_mut`.
fn interna_mapa(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    nombre: view) -> str {
    var esperados = 2;
    if igual(nombre, "poner") { esperados = 3; }
    if igual(nombre, "claves") { esperados = 1; }
    var si_falla = vacio();
    if igual(nombre, "poner") { si_falla = nuevo("()"); }
    if igual(nombre, "tiene") || igual(nombre, "quitar") { si_falla = nuevo("bool"); }
    let dados = largo(n.hijos);
    if dados != esperados {
        error(c, m, n.linea, $"`{nombre}` espera {esperados} argumento(s) y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return si_falla;
    }
    let base = variable_base(n.hijos[0]);
    let is = buscar_simbolo(c, vista(base));
    let hay = largo(base) > 0 && existe(c, is);
    var tipo_mapa = vacio();
    if hay { tipo_mapa = tipo_de_lugar(c, m, tipos, n.hijos[0]); }
    if !hay {
        error(c, m, n.linea, $"el primer argumento de `{nombre}` tiene que ser una variable, un campo o un elemento");
        var r = 1;
        while r < dados {
            let _t = comprobar_expresion(c, m, tipos, n.hijos[r], "", false);
            r = r + 1;
        }
        return si_falla;
    }
    if !T.es_mapa(vista(tipo_mapa)) {
        let visto = texto_o_none(vista(tipo_mapa));
        error(c, m, n.linea, $"`{nombre}` opera sobre `mapa<K, V>`, recibio `{visto}`");
        var r = 1;
        while r < dados {
            let _t = comprobar_expresion(c, m, tipos, n.hijos[r], "", false);
            r = r + 1;
        }
        return si_falla;
    }
    let partes = clave_y_valor(vista(tipo_mapa));
    let kt = copiar(partes[0]);
    let vt = copiar(partes[1]);
    let linea_m = n.hijos[0].linea;
    if igual(nombre, "claves") {
        let _l = leer(c, m, linea_m, is);
        return $"lista<{kt}>";
    }
    let tc = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    if largo(tc) > 0 && !encaja(vista(kt), vista(tc))
    && !(igual(vista(kt), "str") && igual(vista(tc), "view")) {
        error(c, m, n.linea, $"la clave del mapa es `{kt}` y se paso `{tc}`");
    }
    if igual(nombre, "tiene") {
        let _l = leer(c, m, linea_m, is);
        return nuevo("bool");
    }
    if igual(nombre, "obtener_mut") {
        if !es_compuesto(m, vista(vt)) {
            error(c, m, n.linea, $"`obtener_mut` presta para modificar algo que vive en el mapa; `{vt}` es un escalar, asi que usa `obtener` y vuelve a `poner`");
            return vt;
        }
        mutar(c, m, n.hijos[0], linea_m, is, false);
        return $"&mut {vt}";
    }
    if igual(nombre, "quitar") {
        mutar(c, m, n.hijos[0], linea_m, is, false);
        return nuevo("bool");
    }
    if igual(nombre, "obtener") {
        let _l = leer(c, m, linea_m, is);
        if !posee_memoria(m, vista(vt)) { return vt; }
        if igual(vista(vt), "str") { return nuevo("view"); }
        return $"&{vt}";
    }
    let tv = comprobar_expresion(c, m, tipos, n.hijos[2], vista(vt), posee_memoria(m, vista(vt)));
    if largo(tv) > 0 && !encaja(vista(vt), vista(tv)) {
        error(c, m, n.linea, $"el mapa guarda `{vt}` y se intento poner `{tv}`");
    }
    mutar(c, m, n.hijos[0], linea_m, is, false);
    return nuevo("()");
}

// ------------------------------------------------------------------
// Los tipos escritos: cada `Par<A, B>` tiene que ser un struct generico con
// ese numero de tipos
// ------------------------------------------------------------------

fn validar_tipo(c: mut Comprobacion, m: mut Mundo, linea: usize, t: view) {
    if !contiene(t, "<") && !contiene(t, "[") { return; }
    if empieza_con(t, "&mut ") { validar_tipo(c, m, linea, rebanar(t, 5, largo(t))); return; }
    if empieza_con(t, "&") { validar_tipo(c, m, linea, rebanar(t, 1, largo(t))); return; }
    if T.es_bloque(t) {
        let e = elem_bloque(t);
        validar_tipo(c, m, linea, vista(e));
        return;
    }
    if T.es_lista(t) {
        let e = elem_lista(t);
        validar_tipo(c, m, linea, vista(e));
        return;
    }
    if T.es_mapa(t) {
        for x en clave_y_valor(t) { validar_tipo(c, m, linea, vista(x)); }
        return;
    }
    if T.es_arreglo(t) {
        let e = elem_arreglo(t);
        validar_tipo(c, m, linea, vista(e));
        return;
    }
    if !termina_con(t, ">") || T.es_funcion(t) { return; }
    var i = 0;
    while i < largo(t) && byte(t, i) != 60 { i = i + 1; }
    let base = rebanar(t, 0, i);
    if largo(base) == 0 { return; }
    let primero = byte(base, 0);
    if !((primero >= 65 && primero <= 90) || (primero >= 97 && primero <= 122)) { return; }
    let args = T.partir_tipos(rebanar(t, i + 1, largo(t) - 1));
    for a en args { validar_tipo(c, m, linea, vista(a)); }
    if !tiene(m.st_params, base) {
        error(c, m, linea, $"`{base}` no es un struct generico");
        return;
    }
    let sueltos = I.lista_de(m.st_params, base) sino [];
    if largo(args) != largo(sueltos) {
        let pide = largo(sueltos);
        let dados = largo(args);
        error(c, m, linea, $"`{base}` toma {pide} tipo(s) y se le dieron {dados}");
        return;
    }
    registrar_aplicacion(m, t);
}

// Una copia de struct generico nace la primera vez que se nombra: se apunta
// y despues sus campos, que pueden pedir otras.
fn registrar_aplicacion(m: mut Mundo, t: view) {
    let nombre = I.nombre_resuelto(t);
    if esta_entre(m.orden_structs, vista(nombre)) { return; }
    anadir(m.orden_structs, nombre);
    anadir(m.tipo_de_struct, nuevo(t));
    for x en campos_tipos(m, t) { registrar_tipo(m, vista(x)); }
}

// Las copias que pide un tipo, sin errores: los de un tipo ya comprobado.
fn registrar_tipo(m: mut Mundo, t: view) {
    if !contiene(t, "<") && !contiene(t, "[") { return; }
    if empieza_con(t, "&mut ") { registrar_tipo(m, rebanar(t, 5, largo(t))); return; }
    if empieza_con(t, "&") { registrar_tipo(m, rebanar(t, 1, largo(t))); return; }
    if T.es_bloque(t) {
        let e = elem_bloque(t);
        registrar_tipo(m, vista(e));
        return;
    }
    if T.es_lista(t) {
        let e = elem_lista(t);
        registrar_tipo(m, vista(e));
        return;
    }
    if T.es_mapa(t) {
        for x en clave_y_valor(t) { registrar_tipo(m, vista(x)); }
        return;
    }
    if T.es_arreglo(t) {
        let e = elem_arreglo(t);
        registrar_tipo(m, vista(e));
        return;
    }
    if !es_struct_aplicado(m, t) { return; }
    for a en T.partir_tipos(T.entre_angulos(t)) { registrar_tipo(m, vista(a)); }
    registrar_aplicacion(m, t);
}

// Lo mismo en el cuerpo de una copia: sus declaraciones y clausuras.
fn registrar_en_nodo(m: mut Mundo, n: &P.Nodo) {
    let clase = vista(n.clase);
    if igual(clase, "declaracion") {
        var nombre = vacio();
        var escrito = vacio();
        let _mutable = partes_declaracion(vista(n.texto), nombre, escrito);
        if largo(escrito) > 0 { registrar_tipo(m, vista(escrito)); }
    }
    if igual(clase, "param") {
        let p = param_de(vista(n.texto));
        registrar_tipo(m, vista(p.tipo));
    }
    if igual(clase, "retorno_tipo") {
        let t = I.sin_alias_tipo(vista(n.texto));
        registrar_tipo(m, vista(t));
    }
    for h en n.hijos { registrar_en_nodo(m, h); }
}

// Los tipos escritos dentro de una funcion, en orden: parametros, retorno,
// y las declaraciones y clausuras de su cuerpo.
fn validar_en_funcion(c: mut Comprobacion, m: mut Mundo, d: &P.Nodo) {
    for h en d.hijos {
        if igual(vista(h.clase), "param") {
            let p = param_de(vista(h.texto));
            validar_tipo(c, m, d.linea, vista(p.tipo));
        }
    }
    for h en d.hijos {
        if igual(vista(h.clase), "retorno_tipo") {
            let t = I.sin_alias_tipo(vista(h.texto));
            validar_tipo(c, m, d.linea, vista(t));
        }
    }
    for h en d.hijos {
        if igual(vista(h.clase), "bloque") { validar_en_nodo(c, m, h); }
    }
}

fn validar_en_nodo(c: mut Comprobacion, m: mut Mundo, n: &P.Nodo) {
    if igual(vista(n.clase), "declaracion") {
        var nombre = vacio();
        var escrito = vacio();
        let _mutable = partes_declaracion(vista(n.texto), nombre, escrito);
        if largo(escrito) > 0 { validar_tipo(c, m, n.linea, vista(escrito)); }
    }
    if igual(vista(n.clase), "cierre") {
        // La clausura tiene sus tipos escritos donde esta: parametros,
        // retorno, y su cuerpo.
        for h en n.hijos {
            if igual(vista(h.clase), "param") {
                let p = param_de(vista(h.texto));
                validar_tipo(c, m, n.linea, vista(p.tipo));
            }
        }
        for h en n.hijos {
            if igual(vista(h.clase), "retorno_tipo") {
                let t = I.sin_alias_tipo(vista(h.texto));
                validar_tipo(c, m, n.linea, vista(t));
            }
        }
        for h en n.hijos {
            if igual(vista(h.clase), "bloque") { validar_en_nodo(c, m, h); }
        }
        return;
    }
    for h en n.hijos { validar_en_nodo(c, m, h); }
}

// ------------------------------------------------------------------
// Sentencias
// ------------------------------------------------------------------

fn comprobar_bloque(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) {
    // Un bloque anidado ya no es el nivel directo del bucle.
    let anterior = c.en_bucle_directo;
    c.en_bucle_directo = -1;
    abrir_ambito(c);
    if igual(vista(n.clase), "bloque") {
        for s en n.hijos { comprobar_sentencia(c, m, tipos, s); }
    } else {
        // `else if`: la rama es una sentencia suelta.
        comprobar_sentencia(c, m, tipos, n);
    }
    cerrar_ambito(c);
    c.en_bucle_directo = anterior;
}

fn cuerpo_de_bucle(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) {
    let anterior = c.en_bucle_directo;
    c.en_bucle_directo = c.en_bucle como i64;
    abrir_ambito(c);
    for s en n.hijos { comprobar_sentencia(c, m, tipos, s); }
    cerrar_ambito(c);
    c.en_bucle_directo = anterior;
    // Lo que sigue movido al cerrar la vuelta se moveria otra vez.
    let k = largo(c.movidas_en_bucle) - 1;
    let movidas = copiar(c.movidas_en_bucle[k]);
    var quedan: lista<lista<usize>> = [];
    var q = 0;
    while q < k {
        anadir(quedan, copiar(c.movidas_en_bucle[q]));
        q = q + 1;
    }
    c.movidas_en_bucle = quedan;
    var i = 0;
    while i + 1 < largo(movidas) {
        let s = movidas[i];
        let linea = movidas[i + 1];
        i = i + 2;
        if s < largo(c.simbolos) && c.simbolos[s].movida {
            let nombre = copiar(c.simbolos[s].nombre);
            error(c, m, linea, $"`{nombre}` se declaro fuera del bucle y se mueve aqui dentro, asi que la siguiente vuelta lo moveria otra vez. Declaralo dentro del bucle, o dale otro valor antes de cerrar la vuelta");
        }
    }
}

// `let x: T` -> nombre y tipo escrito (vacio si no lo lleva).
fn partes_declaracion(texto: view, nombre: mut str, tipo: mut str) -> bool {
    var i = 0;
    while i < largo(texto) && byte(texto, i) != 32 { i = i + 1; }
    let mutable = igual(rebanar(texto, 0, i), "var");
    let resto = recortar(rebanar(texto, i, largo(texto)));
    var j = 0;
    while j < largo(resto) && byte(resto, j) != 58 { j = j + 1; }
    nombre = nuevo(recortar(rebanar(resto, 0, j)));
    if j < largo(resto) {
        tipo = I.sin_alias_tipo(recortar(rebanar(resto, j + 1, largo(resto))));
    } else {
        tipo = vacio();
    }
    return mutable;
}

fn comprobar_mapa_valido(c: mut Comprobacion, m: &Mundo, linea: usize, t: view) {
    if !T.es_mapa(t) { return; }
    let ps = clave_y_valor(t);
    if largo(ps) != 2 { return; }
    let k = vista(ps[0]);
    let v = vista(ps[1]);
    if !igual(k, "str") {
        error(c, m, linea, $"en v0 la clave de un mapa tiene que ser `str`, y aqui es `{k}`");
    }
    if T.es_referencia(v) || T.es_referencia(k) {
        error(c, m, linea, "un mapa guarda valores, no prestamos: `&T` no puede ser ni clave ni valor");
    }
}

fn comprobar_sentencia(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo) {
    let clase = vista(s.clase);

    if igual(clase, "declaracion") {
        var nombre = vacio();
        var escrito = vacio();
        let mutable = partes_declaracion(vista(s.texto), nombre, escrito);
        var tipo = vacio();
        if largo(escrito) == 0 {
            let t = comprobar_expresion(c, m, tipos, s.hijos[0], "", true);
            if largo(t) == 0 { return; }
            tipo = copiar(t);
            if igual(vista(tipo), literal()) {
                comprobar_literal(c, m, s.hijos[0], "usize");
                tipo = nuevo("usize");
            }
            if !almacenable(m, vista(tipo)) {
                error(c, m, s.linea, $"no se puede deducir el tipo de `{nombre}`: escribelo con `: tipo`");
                return;
            }
        } else {
            tipo = copiar(escrito);
            comprobar_mapa_valido(c, m, s.linea, vista(tipo));
            if !almacenable(m, vista(tipo)) {
                if T.es_referencia(vista(tipo)) {
                    let dentro = T.apuntado(vista(tipo));
                    error(c, m, s.linea, $"`{tipo}` no tiene sentido: `{dentro}` es un escalar, y prestarlo no aporta nada sobre copiarlo");
                } else {
                    error(c, m, s.linea, $"`{tipo}` no es un tipo almacenable; las listas y los arreglos no pueden guardar `view`, y las listas tampoco arreglos fijos");
                }
            }
            let t = comprobar_expresion(c, m, tipos, s.hijos[0], vista(tipo), true);
            if largo(t) > 0 && !encaja(vista(tipo), vista(t)) {
                error(c, m, s.linea, $"`{nombre}` se declaro `{tipo}` pero el valor es `{t}`");
            }
        }
        let i = declarar_simbolo(c, m, s.linea, vista(nombre), vista(tipo), mutable);
        if presta_tipo(m, vista(tipo)) {
            c.simbolos[i].procedencia = procedencia_de(c, m, s.hijos[0]);
            c.simbolos[i].prestado = T.es_referencia(vista(tipo));
            apuntar(c, m, s.linea, i, s.hijos[0]);
        }
        return;
    }

    if igual(clase, "asignacion") {
        let lugar = copiar(s.hijos[0]);
        let base = variable_base(lugar);
        let i = buscar_simbolo(c, vista(base));
        if largo(base) == 0 || !existe(c, i) {
            if largo(base) > 0 {
                error(c, m, s.linea, $"`{base}` no esta declarada");
            } else {
                error(c, m, s.linea, "destino de asignacion invalido");
            }
            let _t = comprobar_expresion(c, m, tipos, s.hijos[1], "", false);
            return;
        }
        c.escribiendo = c.escribiendo + 1;
        let destino = tipo_de_lugar(c, m, tipos, lugar);
        c.escribiendo = c.escribiendo - 1;
        let tipo = comprobar_expresion(c, m, tipos, s.hijos[1], vista(destino), true);
        if escribe_en_captura(c, m, lugar) { return; }
        c.simbolos[i].mutada = true;
        let st = copiar(c.simbolos[i].tipo);
        if T.es_referencia(vista(st)) {
            if !es_referencia_mutable(vista(st)) {
                error_solo_lectura(c, m, s.linea, vista(base), vista(st));
            }
        } else if !c.simbolos[i].mutable {
            error_no_mutable(c, m, s.linea, i);
        }
        if largo(c.simbolos[i].prestamos) > 0 {
            let por = ocupada(c, i);
            error(c, m, s.linea, $"no se puede modificar `{base}`: {por}");
        }
        if largo(destino) > 0 && largo(tipo) > 0 && !encaja(vista(destino), vista(tipo)) {
            error(c, m, s.linea, $"el destino es `{destino}` y se le asigna un `{tipo}`");
        }
        // Una vista guardada en un campo: el struct de la raiz presta tambien
        // de ella. Si la raiz llego prestada, quien la presto no sabria de
        // donde presta ahora, salvo que sea un literal.
        if igual(vista(lugar.clase), "campo") && presta_tipo(m, vista(tipo)) {
            let de_raiz = copiar(c.simbolos[i].tipo);
            if c.simbolos[i].prestado || T.es_referencia(vista(de_raiz)) {
                if !igual(procedencia_de(c, m, s.hijos[1]), "estatico") {
                    error(c, m, s.linea, $"no se puede guardar un prestamo en `{base}`: llego prestada, y quien la presto no sabria de donde presta ahora. Guarda un literal, o devuelve el valor");
                }
            } else if es_prestado_st(m, vista(de_raiz)) {
                let nueva = procedencia_de(c, m, s.hijos[1]);
                let antes = copiar(c.simbolos[i].procedencia);
                if igual(vista(antes), "local") || igual(vista(nueva), "local") {
                    c.simbolos[i].procedencia = nuevo("local");
                } else if igual(vista(antes), "parametro") || igual(vista(nueva), "parametro") {
                    c.simbolos[i].procedencia = nuevo("parametro");
                }
                apuntar(c, m, s.linea, i, s.hijos[1]);
            }
        }

        // Lo que se habia sacado vuelve a estar, si se repone en el mismo
        // nivel en que vive la variable. Dentro de un `if`, el otro camino no
        // lo repuso.
        if c.en_condicional == c.simbolos[i].condicional_al_declarar
        && c.en_bucle == c.simbolos[i].bucle_al_declarar {
            if igual(vista(lugar.clase), "variable") {
                c.simbolos[i].sacados = [];
            } else {
                let camino = ruta_de_campo(lugar);
                if largo(camino) > 0 {
                    let ruta = despues_de_tab(vista(camino));
                    var quedan: lista<str> = [];
                    for x en c.simbolos[i].sacados {
                        let r = antes_de_tab(vista(x));
                        if !igual(vista(r), vista(ruta)) && !empieza_con(vista(r), $"{ruta}.") {
                            anadir(quedan, copiar(x));
                        }
                    }
                    c.simbolos[i].sacados = quedan;
                }
            }
        }
        if igual(vista(lugar.clase), "variable") {
            c.simbolos[i].movida = false;
            if c.en_bucle_directo == c.en_bucle como i64 {
                c.simbolos[i].reasignada_directo = true;
            }
            let ti = copiar(c.simbolos[i].tipo);
            if presta_tipo(m, vista(ti)) {
                // Lo peor de lo que tuvo y de lo que tiene ahora: si la
                // asignacion va en una rama, la otra puede no haberla hecho.
                let nueva = procedencia_de(c, m, s.hijos[1]);
                let antes = copiar(c.simbolos[i].procedencia);
                if igual(vista(antes), "local") || igual(vista(nueva), "local") {
                    c.simbolos[i].procedencia = nuevo("local");
                } else if igual(vista(antes), "parametro") || igual(vista(nueva), "parametro") {
                    c.simbolos[i].procedencia = nuevo("parametro");
                }
                apuntar(c, m, s.linea, i, s.hijos[1]);
            }
        }
        return;
    }

    if igual(clase, "si") {
        let t = comprobar_expresion(c, m, tipos, s.hijos[0], "", false);
        if largo(t) > 0 && !igual(vista(t), "bool") {
            error(c, m, s.linea, $"la condicion de `if` debe ser `bool`, es `{t}`");
        }
        c.en_condicional = c.en_condicional + 1;
        let antes = foto(c);
        comprobar_bloque(c, m, tipos, s.hijos[1]);
        let tras_e = foto(c);
        let sale_e = bloque_termina(s.hijos[1]);
        var tras_s = copiar(antes);
        var sale_s = false;
        if largo(s.hijos) > 2 {
            restaurar_foto(c, antes);
            comprobar_bloque(c, m, tipos, s.hijos[2]);
            tras_s = foto(c);
            sale_s = termina_rama(s.hijos[2]);
        }
        // Una rama que no continua no aporta a lo que sigue.
        var i = 0;
        while i < largo(c.simbolos) && 4 * i + 3 < largo(tras_e) {
            var mb = tras_e[4 * i];
            var lb = tras_e[4 * i + 1];
            var eb = tras_e[4 * i + 2];
            var rb = tras_e[4 * i + 3];
            if 4 * i + 3 < largo(tras_s) {
                mb = tras_s[4 * i];
                lb = tras_s[4 * i + 1];
                eb = tras_s[4 * i + 2];
                rb = tras_s[4 * i + 3];
            }
            let ma = tras_e[4 * i];
            let la = tras_e[4 * i + 1];
            let ea = tras_e[4 * i + 2];
            let ra = tras_e[4 * i + 3];
            if sale_e && !sale_s {
                c.simbolos[i].movida = mb == 1;
                c.simbolos[i].movida_en = lb;
                c.simbolos[i].entregada_en = eb;
                c.simbolos[i].reasignada_directo = rb == 1;
            } else if sale_s && !sale_e {
                c.simbolos[i].movida = ma == 1;
                c.simbolos[i].movida_en = la;
                c.simbolos[i].entregada_en = ea;
                c.simbolos[i].reasignada_directo = ra == 1;
            } else {
                c.simbolos[i].movida = ma == 1 || mb == 1;
                if ma == 1 { c.simbolos[i].movida_en = la; } else { c.simbolos[i].movida_en = lb; }
                if ea != 0 { c.simbolos[i].entregada_en = ea; } else { c.simbolos[i].entregada_en = eb; }
                c.simbolos[i].reasignada_directo = ra == 1 || rb == 1;
            }
            i = i + 1;
        }
        c.en_condicional = c.en_condicional - 1;
        return;
    }

    if igual(clase, "para") {
        let crudo = comprobar_expresion(c, m, tipos, s.hijos[0], "", false);
        let tipo = sin_prestamo(vista(crudo));
        var elem = vacio();
        var tipo_valor = vacio();
        var variable = vacio();
        var valor = vacio();
        let nombres = vista(s.texto);
        var coma = 0;
        while coma < largo(nombres) && byte(nombres, coma) != 44 { coma = coma + 1; }
        variable = nuevo(recortar(rebanar(nombres, 0, coma)));
        if coma < largo(nombres) { valor = nuevo(recortar(rebanar(nombres, coma + 1, largo(nombres)))); }
        if largo(tipo) > 0 && T.es_mapa(vista(tipo)) {
            let ps = clave_y_valor(vista(tipo));
            elem = copiar(ps[0]);
            tipo_valor = copiar(ps[1]);
        } else if largo(tipo) > 0 && (T.es_lista(vista(tipo)) || T.es_arreglo(vista(tipo))) {
            if T.es_lista(vista(tipo)) { elem = elem_lista(vista(tipo)); }
            else { elem = elem_arreglo(vista(tipo)); }
            if largo(valor) > 0 {
                error(c, m, s.linea, "los dos nombres de `for k, v en ...` son para un mapa; una lista solo da el elemento");
            }
        } else if largo(tipo) > 0 {
            error(c, m, s.linea, $"`for` recorre una `lista<T>`, un arreglo o un `mapa<K, V>`, y `{tipo}` no lo es");
        }
        // El bucle presta la coleccion mientras dura.
        let base = variable_base(s.hijos[0]);
        let d = buscar_simbolo(c, vista(base));
        let marca = $"<el for de la linea {s.linea}>";
        let hay_duenio = largo(base) > 0 && existe(c, d);
        if hay_duenio { anadir(c.simbolos[d].prestamos, copiar(marca)); }
        abrir_ambito(c);
        c.en_bucle = c.en_bucle + 1;
        let vacia: lista<usize> = [];
        anadir(c.movidas_en_bucle, vacia);
        c.en_condicional = c.en_condicional + 1;
        if largo(elem) > 0 {
            let i = declarar_simbolo(c, m, s.linea, vista(variable), vista(elem), false);
            c.simbolos[i].prestado = true;
            c.simbolos[i].leida = true;
        }
        if largo(tipo_valor) > 0 && largo(valor) > 0 {
            let j = declarar_simbolo(c, m, s.linea, vista(valor), vista(tipo_valor), false);
            c.simbolos[j].leida = true;
            if posee_memoria(m, vista(tipo_valor)) { c.simbolos[j].prestado = true; }
        }
        cuerpo_de_bucle(c, m, tipos, s.hijos[1]);
        c.en_condicional = c.en_condicional - 1;
        c.en_bucle = c.en_bucle - 1;
        cerrar_ambito(c);
        if hay_duenio && esta_entre(c.simbolos[d].prestamos, vista(marca)) {
            soltar_prestamo(c, d, vista(marca));
        }
        return;
    }

    if igual(clase, "romper") || igual(clase, "continuar") {
        if c.en_bucle == 0 {
            var palabra = nuevo("break");
            if igual(clase, "continuar") { palabra = nuevo("continue"); }
            error(c, m, s.linea, $"`{palabra}` solo tiene sentido dentro de un `for` o un `while`");
        }
        return;
    }

    if igual(clase, "mientras") {
        c.en_condicion_bucle = c.en_condicion_bucle + 1;
        let t = comprobar_expresion(c, m, tipos, s.hijos[0], "", false);
        c.en_condicion_bucle = c.en_condicion_bucle - 1;
        c.en_bucle = c.en_bucle + 1;
        let vacia: lista<usize> = [];
        anadir(c.movidas_en_bucle, vacia);
        if largo(t) > 0 && !igual(vista(t), "bool") {
            error(c, m, s.linea, $"la condicion de `while` debe ser `bool`, es `{t}`");
        }
        c.en_condicional = c.en_condicional + 1;
        cuerpo_de_bucle(c, m, tipos, s.hijos[1]);
        c.en_condicional = c.en_condicional - 1;
        c.en_bucle = c.en_bucle - 1;
        return;
    }

    if igual(clase, "retorno") {
        let r = copiar(c.retorno);
        if largo(s.hijos) == 0 {
            if largo(r) > 0 {
                error(c, m, s.linea, $"esta funcion devuelve `{r}` y el `return` esta vacio");
            }
            return;
        }
        if presta_tipo(m, vista(r)) {
            comprobar_vista_devuelta(c, m, s);
        }
        c.en_retorno = c.en_retorno + 1;
        var tipo = vacio();
        if igual(vista(s.hijos[0].clase), "variable") {
            tipo = variable(c, m, tipos, s.hijos[0], true, true);
        } else {
            tipo = comprobar_expresion(c, m, tipos, s.hijos[0], vista(r), true);
        }
        c.en_retorno = c.en_retorno - 1;
        if largo(r) == 0 {
            error(c, m, s.linea, "esta funcion no declara tipo de retorno");
        } else if largo(tipo) > 0 && !encaja(vista(r), vista(tipo)) {
            error(c, m, s.linea, $"esta funcion devuelve `{r}` y aqui se devuelve `{tipo}`");
        }
        return;
    }

    if igual(clase, "falla") {
        if !c.falible {
            error(c, m, s.linea, "esta funcion no esta declarada con `!`, asi que no puede fallar; ponle `!` despues del tipo de retorno");
        }
        return;
    }

    if igual(clase, "expresion") && largo(s.hijos) > 0 {
        let _t = comprobar_expresion(c, m, tipos, s.hijos[0], "", false);
        return;
    }
}

fn comprobar_vista_devuelta(c: mut Comprobacion, m: &Mundo, s: &P.Nodo) {
    let proc = procedencia_de(c, m, s.hijos[0]);
    if !igual(vista(proc), "local") { return; }
    let duenio = origen_de(c, m, s.hijos[0]);
    var de_quien = vacio();
    var extra = nuevo("esa memoria muere al cerrar la funcion");
    if largo(duenio) > 0 {
        de_quien = $" de `{duenio}`";
        extra = $"`{duenio}` muere al cerrar la funcion";
    }
    error(c, m, s.linea, $"no se puede devolver una vista{de_quien}: {extra}. Una vista que sale de la funcion tiene que venir de un parametro `view` o de un literal; si quieres entregar el texto, devuelve un `str` con `nuevo(...)`");
}

// ------------------------------------------------------------------
// Una funcion, y el programa entero
// ------------------------------------------------------------------

struct Programa {
    arboles: lista<P.Nodo>,
    modulos: lista<str>,
    contextos: lista<I.Contexto>,
    cierres: lista<P.Nodo>,
    cierres_mod: lista<usize>,
}

fn comprobar_funcion(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, k: usize,
    original: &P.Nodo, dueno: view) {
    var d = copiar(original);
    var cuenta: usize = 0;
    etiquetar_cierres(d, cuenta);
    c.dueno = nuevo(dueno);
    let historia_antes = copiar(c.historia);
    c.historia = [];
    let f = copiar(m.funciones[k]);
    let nombre = vista(f.nombre);
    c.retorno = copiar(f.retorno);
    c.falible = f.falible;
    if largo(f.retorno) > 0 && !almacenable(m, vista(f.retorno)) {
        error(c, m, f.linea, $"la funcion `{nombre}` devuelve el tipo `{f.retorno}`, que no se puede almacenar");
    }
    abrir_ambito(c);
    for p en f.params {
        if !almacenable(m, vista(p.tipo)) {
            error(c, m, f.linea, $"el parametro `{p.nombre}` usa el tipo `{p.tipo}`, que no se puede almacenar");
        }
        if prestado(p) && igual(vista(p.tipo), "view") {
            var marca = nuevo("&");
            if p.mutable { marca = nuevo("mut"); }
            error(c, m, f.linea, $"`{marca}` sobre `view` no tiene sentido: una vista ya es un prestamo. Quita el `{marca}`");
        }
        let i = declarar_simbolo(c, m, f.linea, vista(p.nombre), vista(p.tipo), p.mutable);
        c.simbolos[i].prestado = prestado(p);
        c.simbolos[i].es_param = true;
        let h = c.simbolos[i].historia;
        c.historia[h].es_param = true;
        if igual(vista(p.tipo), "view") || (!prestado(p) && es_prestado_st(m, vista(p.tipo))) {
            c.simbolos[i].procedencia = nuevo("parametro");
        }
    }
    var sale = false;
    for h en d.hijos {
        if igual(vista(h.clase), "bloque") {
            comprobar_bloque(c, m, tipos, h);
            sale = siempre_sale(h);
        }
    }
    cerrar_ambito(c);
    // Prometer un valor y no devolverlo deja al que llama leyendo basura.
    if largo(f.retorno) > 0 && !igual(vista(f.retorno), "()") && !igual(nombre, "main")
    && !sale {
        error(c, m, f.linea, $"`{nombre}` promete devolver `{f.retorno}` pero hay un camino que llega al final sin `return`");
    }
    avisar_sin_usar(c, m, f);
    anadir(c.informe, informe_de(m, f, c.historia));
    c.historia = historia_antes;
    c.retorno = vacio();
    c.falible = false;
}

// ------------------------------------------------------------------
// `--explicar`: lo que se infirio, dicho como el original
// ------------------------------------------------------------------

// Los caracteres de un texto: lo que mide Python al alinear columnas.
fn ancho_de(t: view) -> usize {
    var n = 0;
    var i = 0;
    while i < largo(t) {
        let b = byte(t, i);
        if b < 128 || b >= 192 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn a_la_izquierda(t: view, cuanto: usize) -> str {
    var r = nuevo(t);
    var n = ancho_de(t);
    while n < cuanto {
        empujar(r, " ");
        n = n + 1;
    }
    return r;
}

fn sin_espacio_final(t: view) -> str {
    var fin = largo(t);
    while fin > 0 && (byte(t, fin - 1) == 32 || byte(t, fin - 1) == 10) { fin = fin - 1; }
    return nuevo(rebanar(t, 0, fin));
}

// Un tipo como lo escribe el original. Los nombres que chocan con C ya
// llegan cambiados en el arbol, como alli.
fn tipo_informe(t: view) -> str { return I.nombre_resuelto(t); }

fn firma_legible(f: &Funcion) -> str {
    var partes = vacio();
    var i = 0;
    while i < largo(f.params) {
        if i > 0 { empujar(partes, ", "); }
        let t = tipo_informe(vista(f.params[i].tipo));
        let pn = vista(f.params[i].nombre);
        if f.params[i].mutable { let x = $"{pn}: mut {t}"; empujar(partes, vista(x)); }
        else if f.params[i].compartido { let x = $"{pn}: &{t}"; empujar(partes, vista(x)); }
        else { let x = $"{pn}: {t}"; empujar(partes, vista(x)); }
        i = i + 1;
    }
    var firma = $"fn {f.nombre}({partes})";
    if largo(f.retorno) > 0 && !igual(vista(f.retorno), "()") {
        let r = tipo_informe(vista(f.retorno));
        empujar(firma, " -> ");
        empujar(firma, vista(r));
    }
    if f.falible { empujar(firma, " !"); }
    return firma;
}

// Que es la variable.
fn papel_de(m: &Mundo, s: &Simbolo) -> str {
    if s.prestado {
        if s.mutable { return nuevo("prestado, modificable"); }
        return nuevo("prestado para leer");
    }
    if igual(vista(s.tipo), "view") { return nuevo("vista"); }
    if posee_memoria(m, vista(s.tipo)) {
        if s.es_param { return nuevo("DUEÑA (recibida)"); }
        return nuevo("DUEÑA");
    }
    return nuevo("valor");
}

// Que pasa con su memoria.
fn destino_de(m: &Mundo, s: &Simbolo) -> str {
    if igual(vista(s.tipo), "view") {
        var origen = vacio();
        if largo(s.origen) > 0 {
            let o = copiar(s.origen);
            origen = $" de `{o}`";
        }
        if igual(vista(s.procedencia), "estatico") {
            return nuevo("apunta a un literal: vive todo el programa");
        }
        if igual(vista(s.procedencia), "parametro") {
            if largo(origen) == 0 { origen = nuevo(" de un parametro"); }
            return $"presta{origen}: la memoria es de quien llama";
        }
        return $"presta{origen}: muere con el";
    }
    if s.prestado { return nuevo("no se libera aqui: es de quien llama"); }
    if !posee_memoria(m, vista(s.tipo)) { return vacio(); }
    if s.entregada_en > 0 {
        return $"se entrega en la linea {s.entregada_en} (return)";
    }
    if s.movida {
        var a = vacio();
        if largo(s.movida_a) > 0 {
            let destino_c = copiar(s.movida_a);
            a = $" a `{destino_c}`";
        }
        return $"se mueve{a} en la linea {s.movida_en}; lleva bandera por si el programa sale antes";
    }
    if T.es_arreglo(vista(s.tipo)) {
        let e = elem_arreglo(vista(s.tipo));
        if posee_memoria(m, vista(e)) {
            let n = largo_arreglo(vista(s.tipo));
            return $"se libera sola al cerrar su bloque, elemento por elemento ({n})";
        }
    }
    return nuevo("se libera sola al cerrar su bloque");
}

fn informe_de(m: &Mundo, f: &Funcion, historia: &lista<Simbolo>) -> str {
    let firma = firma_legible(f);
    var t = $"  {firma}\n";
    if f.falible && igual(vista(f.nombre), "main") {
        empujar(t, "      puede fallar: si falla, el programa imprime `error: <motivo>` y sale con codigo 1\n");
    } else if f.falible {
        empujar(t, "      puede fallar: quien la llame tiene que usar `try` o `sino`\n");
    }
    if largo(historia) == 0 {
        empujar(t, "      (sin variables)\n\n");
        return t;
    }
    var an = 0;
    var at = 0;
    var ap = 0;
    for s en historia {
        let nt = tipo_informe(vista(s.tipo));
        let pa = papel_de(m, s);
        let nc = copiar(s.nombre);
        if ancho_de(vista(nc)) > an { an = ancho_de(vista(nc)); }
        if ancho_de(vista(nt)) > at { at = ancho_de(vista(nt)); }
        if ancho_de(vista(pa)) > ap { ap = ancho_de(vista(pa)); }
    }
    var duenias = 0;
    var solas = 0;
    var entregadas = 0;
    var movidas = 0;
    for s en historia {
        var marca = nuevo("let");
        if s.mutable { marca = nuevo("var"); }
        if s.es_param { marca = nuevo("arg"); }
        let nt = tipo_informe(vista(s.tipo));
        let pa = papel_de(m, s);
        let de = destino_de(m, s);
        let nc = copiar(s.nombre);
        let c1 = a_la_izquierda(vista(nc), an);
        let c2 = a_la_izquierda(vista(nt), at);
        let c3 = a_la_izquierda(vista(pa), ap);
        let fila = $"      {marca} {c1}  {c2}  {c3}  {de}";
        empujar(t, sin_espacio_final(vista(fila)));
        empujar(t, "\n");
        if posee_memoria(m, vista(s.tipo)) && !s.prestado {
            duenias = duenias + 1;
            if !s.movida && s.entregada_en == 0 { solas = solas + 1; }
            if s.entregada_en > 0 { entregadas = entregadas + 1; }
            if s.movida { movidas = movidas + 1; }
        }
    }
    if duenias > 0 {
        var trozos: lista<str> = [];
        if solas > 0 {
            if solas > 1 { anadir(trozos, $"{solas} se liberan solas"); }
            else { anadir(trozos, $"{solas} se libera sola"); }
        }
        if entregadas > 0 {
            if entregadas > 1 { anadir(trozos, $"{entregadas} se entregan"); }
            else { anadir(trozos, $"{entregadas} se entrega"); }
        }
        if movidas > 0 {
            if movidas > 1 { anadir(trozos, $"{movidas} se mueven"); }
            else { anadir(trozos, $"{movidas} se mueve"); }
        }
        var junto = vacio();
        var i = 0;
        while i < largo(trozos) {
            if i > 0 { empujar(junto, ", "); }
            empujar(junto, vista(trozos[i]));
            i = i + 1;
        }
        let linea = $"      {duenias} valor(es) con memoria propia: {junto}\n";
        empujar(t, vista(linea));
    }
    empujar(t, "\n");
    return t;
}

// El informe entero: los structs, y cada funcion comprobada en su orden.
fn explicacion(m: &Mundo, informe: &lista<str>, archivo: view) -> str {
    var t = $"{archivo}\n\n";
    if largo(m.orden_structs) == 0 && largo(informe) == 0 {
        empujar(t, "  (nada que explicar)");
        return t;
    }
    var k = 0;
    while k < largo(m.orden_structs) {
        let nombre_c = copiar(m.orden_structs[k]);
        let nombre = vista(nombre_c);
        let aqui = vista(m.tipo_de_struct[k]);
        let posee = posee_memoria(m, aqui);
        empujar(t, "  struct ");
        empujar(t, nombre);
        if posee { empujar(t, "   es DUEÑO: contiene memoria que hay que liberar\n"); }
        else { empujar(t, "   solo datos: nada que liberar\n"); }
        let ns = campos_nombres(m, aqui);
        let ts = campos_tipos(m, aqui);
        var i = 0;
        while i < largo(ns) && i < largo(ts) {
            let tc = tipo_informe(vista(ts[i]));
            var marca = vacio();
            if posee_memoria(m, vista(ts[i])) { marca = nuevo("  <- duenio"); }
            let campo_c = copiar(ns[i]);
            let linea = $"      {campo_c}: {tc}{marca}\n";
            empujar(t, vista(linea));
            i = i + 1;
        }
        if posee {
            let linea = $"      el compilador genera `ss_drop_{nombre}` y lo llama donde haga falta\n";
            empujar(t, vista(linea));
        }
        empujar(t, "\n");
        k = k + 1;
    }
    for x en informe { empujar(t, vista(x)); }
    var limpio = sin_espacio_final(vista(t));
    empujar(limpio, "\n");
    return limpio;
}

// Un `_` delante silencia el aviso, como en Rust: dice que es a proposito.
fn avisar_sin_usar(c: mut Comprobacion, m: &Mundo, f: &Funcion) {
    let historia = copiar(c.historia);
    let nombre_f = vista(f.nombre);
    for s en historia {
        let n = vista(s.nombre);
        let escrito_n = G.escrito(n);
        if empieza_con(vista(escrito_n), "_") { continue; }
        if s.es_param {
            if !s.leida && !s.mutada {
                aviso(c, m, f.linea, $"el parametro `{n}` de `{nombre_f}` no se usa; si es a proposito llamalo `_{n}`");
            } else if s.mutable && !s.mutada {
                aviso(c, m, f.linea, $"`{n}` se recibe como `mut {s.tipo}` y nunca se modifica; podria ser `&{s.tipo}`");
            }
            continue;
        }
        if !s.leida && !s.mutada {
            aviso(c, m, s.linea_decl, $"`{n}` se declara y no se usa; si es a proposito llamala `_{n}`");
        } else if !s.leida {
            aviso(c, m, s.linea_decl, $"a `{n}` se le asignan valores que nunca se leen");
        } else if s.mutable && !s.mutada {
            aviso(c, m, s.linea_decl, $"`{n}` se declara `var` y nunca se modifica; puede ser `let`");
        }
    }
}

// Lo que va a un lado y otro del borde con C: numeros, `bool` y `str` de
// entrada; numeros, `bool`, `cadena_c` y nada de salida.
fn comprobar_externa(c: mut Comprobacion, m: &Mundo, f: &Funcion) {
    let nombre = vista(f.nombre);
    for p en f.params {
        let t = vista(p.tipo);
        if prestado(p) || T.es_referencia(t) {
            error(c, m, f.linea, $"`{nombre}` es de C: sus parametros no se prestan ni se mutan, se pasan por valor");
        } else if igual(t, "view") {
            error(c, m, f.linea, $"`{nombre}.{p.nombre}` es una `view`, y una vista puede apuntar a la mitad de una cadena: no acaba en `\\0` y C leeria de mas. Pasa un `str`, que si acaba, o haz `nuevo(v)` antes");
        } else if !es_numerico(t) && !igual(t, "bool") && !igual(t, "str") {
            error(c, m, f.linea, $"`{nombre}.{p.nombre}` es `{t}`, y eso no significa lo mismo en C. En el borde caben los numeros, `bool` y `str`; para lo demas, envuelvelo en una funcion de C tuya");
        }
    }
    var r = copiar(f.retorno);
    if largo(r) == 0 { r = nuevo("()"); }
    let rv = vista(r);
    if !es_numerico(rv) && !igual(rv, "bool") && !igual(rv, "cadena_c") && !igual(rv, "()") {
        if igual(rv, "str") {
            error(c, m, f.linea, $"`{nombre}` devuelve `str`, y un `str` es de Tcode: C no puede fabricar uno. Si devuelve un `char*` que no hay que liberar, dilo con `cadena_c` y Tcode lo copia");
        } else {
            error(c, m, f.linea, $"`{nombre}` devuelve `{r}`, y eso no significa lo mismo en C. En el borde caben los numeros, `bool`, `cadena_c` y nada");
        }
    }
}

// Los campos de un `struct`: nombres y tipos, sin el alias del modulo.
fn campo_de(texto: view, nombre: mut str, tipo: mut str) {
    var j = 0;
    while j < largo(texto) && byte(texto, j) != 58 { j = j + 1; }
    nombre = nuevo(recortar(rebanar(texto, 0, j)));
    tipo = I.sin_alias_tipo(recortar(rebanar(texto, j + 1, largo(texto))));
}

// El programa entero, con las clausuras ya numeradas: cada una es su nodo
// `fn ss_cierre_N` y el modulo donde se escribio. Devuelve los errores como
// `archivo:linea: mensaje`, en el mismo orden que el original.
// Lo que sale de comprobar: los errores, y si no los hay, las clausuras que
// nacieron y donde va cada una.
struct Revision {
    errores: lista<str>,
    avisos: lista<str>,
    // Lo que dice `--explicar`.
    explicacion: str,
    cierres: lista<P.Nodo>,
    cierres_mod: lista<usize>,
    numeracion: mapa<str, usize>,
    // Los campos sacados de su struct: `archivo\tlinea\tp.a.b`.
    sacados: lista<str>,
    // El tipo de cada expresion, por modulo, para el generador.
    anotados: lista<mapa<str, str>>,
    // Las copias y las clausuras, en el orden en que se escriben.
    orden_copias: lista<str>,
    // Las copias de structs genericos, en el orden en que nacen: tambien
    // las que se deducen de un literal, que no estan escritas en ningun sitio.
    structs_aplicados: lista<str>,
}

fn comprobar_programa(arboles: &lista<P.Nodo>, modulos: &lista<str>,
    contextos: &lista<I.Contexto>) -> Revision {
    var m = Mundo { funciones: [], indice: [], st_tipos: [], st_nombres: [],
        st_params: [], en_variantes: [], en_formas: [], bonitos: [],
        cierres: [], cierres_mod: [], n_cierres: 0, cierres_mut: [], numeracion: [],
        arboles: copiar(arboles), modulos: copiar(modulos),
        contextos: copiar(contextos), copias: [], orden_structs: [], tipo_de_struct: [],
        anotados: [], orden_copias: [] };
    for _a en arboles {
        let vacio_m: mapa<str, str> = [];
        anadir(m.anotados, vacio_m);
    }
    var c = estado("", 0);
    // Donde se definio cada struct y enum, para decir donde estaba el primero.
    var st_donde: mapa<str, str> = [];
    var en_donde: mapa<str, str> = [];

    // Primero se registra todo lo que hay.
    var k = 0;
    while k < largo(arboles) {
        let ruta = vista(modulos[k]);
        var j = 0;
        while j < largo(arboles[k].hijos) {
            let clase = vista(arboles[k].hijos[j].clase);
            let texto_d = vista(arboles[k].hijos[j].texto);
            if igual(clase, "fn") {
                let nombre = resolver_nombre(contextos[k], texto_d);
                if !igual(vista(nombre), texto_d) {
                    poner(m.bonitos, vista(nombre), nuevo(texto_d));
                }
                let f = funcion_de(arboles[k].hijos[j], vista(nombre), ruta, k, j, false);
                if !tiene(m.indice, vista(nombre)) {
                    poner(m.indice, vista(nombre), largo(m.funciones));
                }
                anadir(m.funciones, f);
            }
            if igual(clase, "externo") {
                for h en arboles[k].hijos[j].hijos {
                    if !igual(vista(h.clase), "fn") { continue; }
                    let f = funcion_de(h, vista(h.texto), ruta, k, j, true);
                    if !tiene(m.indice, vista(h.texto)) {
                        poner(m.indice, vista(h.texto), largo(m.funciones));
                    }
                    anadir(m.funciones, f);
                }
            }
            j = j + 1;
        }
        k = k + 1;
    }
    // Los enums, antes que los structs: un struct puede llevar uno.
    k = 0;
    while k < largo(arboles) {
        c.archivo = copiar(modulos[k]);
        for d en arboles[k].hijos {
            if !igual(vista(d.clase), "enum") { continue; }
            let nombre = vista(d.texto);
            if tiene(en_donde, nombre) {
                let donde = obtener(en_donde, nombre) sino "";
                error(c, m, d.linea, $"`{nombre}` ya esta definido en {donde}");
            }
            poner(en_donde, nombre, $"{modulos[k]}:{d.linea}");
            var formas: lista<str> = [];
            for v en d.hijos {
                if !igual(vista(v.clase), "variante") { continue; }
                anadir(formas, copiar(v.texto));
                var lleva: lista<str> = [];
                for x en v.hijos {
                    if igual(vista(x.clase), "lleva") { anadir(lleva, I.sin_alias_tipo(vista(x.texto))); }
                }
                poner(m.en_formas, $"{nombre}.{v.texto}", lleva);
            }
            poner(m.en_variantes, nombre, formas);
        }
        k = k + 1;
    }

    // Los structs.
    k = 0;
    while k < largo(arboles) {
        c.archivo = copiar(modulos[k]);
        for d en arboles[k].hijos {
            if !igual(vista(d.clase), "struct") { continue; }
            let nombre = vista(d.texto);
            if tiene(st_donde, nombre) {
                let donde = obtener(st_donde, nombre) sino "";
                error(c, m, d.linea, $"el struct `{nombre}` ya esta definido en {donde}");
            }
            poner(st_donde, nombre, $"{modulos[k]}:{d.linea}");
            var ns: lista<str> = [];
            var ts: lista<str> = [];
            var ps: lista<str> = [];
            for h en d.hijos {
                if igual(vista(h.clase), "tipo_param") { anadir(ps, copiar(h.texto)); }
                if igual(vista(h.clase), "campo_def") {
                    var cn = vacio();
                    var ct = vacio();
                    campo_de(vista(h.texto), cn, ct);
                    anadir(ns, cn);
                    anadir(ts, ct);
                }
            }
            poner(m.st_nombres, nombre, ns);
            poner(m.st_tipos, nombre, ts);
            if largo(ps) > 0 { poner(m.st_params, nombre, ps); }
            else if !esta_entre(m.orden_structs, nombre) {
                anadir(m.orden_structs, nuevo(nombre));
                anadir(m.tipo_de_struct, nuevo(nombre));
            }
        }
        k = k + 1;
    }
    k = 0;
    while k < largo(arboles) {
        c.archivo = copiar(modulos[k]);
        for d en arboles[k].hijos {
            if !igual(vista(d.clase), "struct") { continue; }
            var generico_r = false;
            for h en d.hijos {
                if igual(vista(h.clase), "tipo_param") { generico_r = true; }
            }
            if generico_r { continue; }
            for h en d.hijos {
                if !igual(vista(h.clase), "campo_def") { continue; }
                var cn = vacio();
                var ct = vacio();
                campo_de(vista(h.texto), cn, ct);
                validar_tipo(c, m, d.linea, vista(ct));
            }
        }
        k = k + 1;
    }
    k = 0;
    while k < largo(arboles) {
        c.archivo = copiar(modulos[k]);
        for d en arboles[k].hijos {
            if !igual(vista(d.clase), "struct") { continue; }
            var generico = false;
            for h en d.hijos {
                if igual(vista(h.clase), "tipo_param") { generico = true; }
            }
            if generico { continue; }
            let nombre = vista(d.texto);
            var vistos_c: lista<str> = [];
            var tipos_c: lista<str> = [];
            for h en d.hijos {
                if !igual(vista(h.clase), "campo_def") { continue; }
                var cn = vacio();
                var ct = vacio();
                campo_de(vista(h.texto), cn, ct);
                if esta_entre(vistos_c, vista(cn)) {
                    error(c, m, d.linea, $"`{nombre}` tiene dos campos llamados `{cn}`");
                }
                anadir(vistos_c, copiar(cn));
                anadir(tipos_c, copiar(ct));
                // Un campo `view` hace del struct uno que presta: se le trata
                // como a una vista, sin anotar vidas en el tipo.
                if !almacenable(m, vista(ct)) {
                    error(c, m, d.linea, $"`{nombre}.{cn}` usa el tipo `{ct}`, que no existe");
                }
            }
            var ciclo = false;
            for t en tipos_c {
                var vistos: lista<str> = [];
                if se_contiene(m, vista(t), nombre, vistos) { ciclo = true; }
            }
            if ciclo {
                error(c, m, d.linea, $"`{nombre}` se contiene a si mismo: no tiene un tamaño finito");
            }
        }
        k = k + 1;
    }

    // Lo que lleva cada forma. Va despues de los structs: una forma puede
    // llevar uno, y antes no existia.
    k = 0;
    while k < largo(arboles) {
        c.archivo = copiar(modulos[k]);
        for d en arboles[k].hijos {
            if !igual(vista(d.clase), "enum") { continue; }
            let nombre = vista(d.texto);
            for v en d.hijos {
                if !igual(vista(v.clase), "variante") { continue; }
                for x en v.hijos {
                    if !igual(vista(x.clase), "lleva") { continue; }
                    let t = I.sin_alias_tipo(vista(x.texto));
                    validar_tipo(c, m, d.linea, vista(t));
                    if !almacenable(m, vista(t)) {
                        error(c, m, d.linea, $"`{nombre}.{v.texto}` lleva un `{t}`, que no es un tipo");
                    } else if igual(vista(t), "view") {
                        error_enum_prestado(c, m, d.linea, nombre, vista(v.texto), vista(t));
                    }
                    var vistos: lista<str> = [];
                    if se_contiene(m, vista(t), nombre, vistos) {
                        error(c, m, d.linea, $"`{nombre}.{v.texto}` contiene un `{nombre}`: el tamaño no seria finito. Metelo en una `lista`, que guarda un puntero");
                    }
                    // Tampoco un struct que presta.
                    if es_prestado_st(m, vista(t)) {
                        error_enum_prestado(c, m, d.linea, nombre, vista(v.texto), vista(t));
                    }
                }
            }
        }
        k = k + 1;
    }

    // Los tipos escritos en cada funcion que no es generica.
    var e = 0;
    while e < largo(m.funciones) {
        if !m.funciones[e].de_cierre && !tiene_sueltos(m.funciones[e]) {
            c.archivo = copiar(m.funciones[e].archivo);
            let km = m.funciones[e].modulo;
            let kp = m.funciones[e].posicion;
            if m.funciones[e].externa {
                let f = copiar(m.funciones[e]);
                for p en f.params { validar_tipo(c, m, f.linea, vista(p.tipo)); }
                validar_tipo(c, m, f.linea, vista(f.retorno));
            } else {
                validar_en_funcion(c, m, arboles[km].hijos[kp]);
            }
        }
        e = e + 1;
    }

    // El borde con C.
    e = 0;
    while e < largo(m.funciones) {
        if m.funciones[e].externa {
            c.archivo = copiar(m.funciones[e].archivo);
            let f = copiar(m.funciones[e]);
            comprobar_externa(c, m, f);
        }
        e = e + 1;
    }

    // Nombres: ni de una interna, ni repetidos.
    var vistas: mapa<str, str> = [];
    e = 0;
    while e < largo(m.funciones) {
        if !m.funciones[e].de_cierre {
            c.archivo = copiar(m.funciones[e].archivo);
            let nombre = copiar(m.funciones[e].nombre);
            let linea = m.funciones[e].linea;
            if nombra_interna(vista(nombre)) {
                error(c, m, linea, $"`{nombre}` es una funcion interna del lenguaje: una funcion propia con ese nombre no se llamaria nunca. Ponle otro nombre");
            }
            if tiene(vistas, vista(nombre)) {
                let donde = obtener(vistas, vista(nombre)) sino "";
                error(c, m, linea, $"la funcion `{nombre}` ya esta definida en {donde}");
            } else {
                poner(vistas, vista(nombre), $"{m.funciones[e].archivo}:{linea}");
            }
        }
        e = e + 1;
    }

    // Y cada funcion, en orden. Las genericas se comprueban en sus copias,
    // que esta capa todavia no mira; las de C no tienen cuerpo.
    e = 0;
    while e < largo(m.funciones) {
        let f = copiar(m.funciones[e]);
        if !f.de_cierre && !f.externa && !tiene_sueltos(f) {
            c.archivo = copiar(f.archivo);
            c.modulo = f.modulo;
            let nodo = copiar(arboles[f.modulo].hijos[f.posicion]);
            comprobar_funcion(c, m, contextos[f.modulo], e, nodo, vista(f.nombre));
        }
        e = e + 1;
    }
    comprobar_restricciones(c, m);
    let principal = vista(modulos[largo(modulos) - 1]);
    var aplicados: lista<str> = [];
    for t en m.tipo_de_struct {
        if contiene(vista(t), "<") { anadir(aplicados, copiar(t)); }
    }
    return Revision { errores: copiar(c.errores), avisos: copiar(c.avisos),
        explicacion: explicacion(m, c.informe, principal),
        cierres: copiar(m.cierres),
        cierres_mod: copiar(m.cierres_mod), numeracion: copiar(m.numeracion),
        sacados: copiar(c.sacados), anotados: copiar(m.anotados),
        orden_copias: copiar(m.orden_copias), structs_aplicados: aplicados };
}
