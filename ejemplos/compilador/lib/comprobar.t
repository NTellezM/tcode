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

use "tipar.t" como I;
use "tipos.t" como T;
use "generar.t" como G;
use "../../lexer/lib/sintaxis.t" como P;
use "std/texto";
use "std/lista";
use "../../lexer/lib/clase.t";

// ------------------------------------------------------------------
// Los tipos basicos, como en el original
// ------------------------------------------------------------------

// Un numero escrito todavia no tiene ancho, y uno con punto tampoco.
fn literal() -> view { return "{entero}"; }
fn literal_decimal() -> view { return "{decimal}"; }
fn unidad() -> view { return "()"; }

// Los marcadores de un literal sin fijar, ya como `Tipo`: `{entero}` y
// `{decimal}` no pasan por `leer_tipo`, asi que se preguntan por el nombre.
fn es_literal_entero(t: &T.Tipo) -> bool {
    return igual(t.nombre, literal());
}
fn es_literal_decimal_t(t: &T.Tipo) -> bool {
    return igual(t.nombre, literal_decimal());
}
// Un texto de tipo (real o marcador) leido a `Tipo`.
fn tipo_de_escrito(v: view) -> T.Tipo {
    if igual(v, literal()) || igual(v, literal_decimal()) { return T.marcador(v); }
    return T.leer_tipo(v);
}

fn es_sin_signo(t: view) -> bool {
    return t == "u8" || t == "u16" || t == "u32"
    || t == "u64" || t == "usize";
}

fn es_con_signo(t: view) -> bool {
    return t == "i8" || t == "i16" || t == "i32"
    || t == "i64";
}

fn es_tipo_entero(t: view) -> bool { return es_sin_signo(t) || es_con_signo(t); }

fn es_decimal(t: view) -> bool { return t == "f32" || t == "f64"; }

fn es_numerico(t: view) -> bool { return es_tipo_entero(t) || es_decimal(t); }

fn sin_prestamo(t: view) -> str { return T.apuntado_si(t); }

// Lo que no posee nada detras: se puede sacar de un prestamo.
fn es_copiable(t: view) -> bool {
    return es_numerico(t) || t == "bool" || t == "view"
    || igual(t, literal()) || igual(t, literal_decimal()) || igual(t, unidad())
    || T.es_funcion(t);
}

// Un valor de tipo `dado` sirve donde se pide `esperado`.
fn encaja(esperado: view, dado: view) -> bool {
    if igual(esperado, dado) { return true; }
    // Un `buffer` es un `str` que ademas C puede escribir: se le da un `str`.
    if igual(esperado, "buffer") && igual(dado, "str") { return true; }
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

// `a`, `b` y `c` -> "`a`, `b` y `c`".
fn lista_legible(nombres: &list<str>) -> str {
    var r = vacio();
    var i = 0;
    while i < nombres.largo() {
        if i > 0 {
            if i + 1 == nombres.largo() { r.empujar(" y "); } else { r.empujar(", "); }
        }
        r.empujar("`");
        r.empujar(nombres[i]);
        r.empujar("`");
        i = i + 1;
    }
    return r;
}

// "`a`, `b`, `c`": todos con coma, como `", ".join` del original.
fn con_comas(nombres: &list<str>) -> str {
    var r = vacio();
    var i = 0;
    while i < nombres.largo() {
        if i > 0 { r.empujar(", "); }
        r.empujar("`");
        r.empujar(nombres[i]);
        r.empujar("`");
        i = i + 1;
    }
    return r;
}

fn numericos() -> list<str> {
    var r: list<str> = [];
    r.anadir(nuevo("u8")); r.anadir(nuevo("u16")); r.anadir(nuevo("u32"));
    r.anadir(nuevo("u64")); r.anadir(nuevo("usize")); r.anadir(nuevo("i8"));
    r.anadir(nuevo("i16")); r.anadir(nuevo("i32")); r.anadir(nuevo("i64"));
    r.anadir(nuevo("f32")); r.anadir(nuevo("f64"));
    return r;
}

fn igualables() -> list<str> {
    var r = numericos();
    r.anadir(nuevo("bool")); r.anadir(nuevo("str")); r.anadir(nuevo("view"));
    ordenar(r);
    return r;
}

fn comparables() -> list<str> {
    var r = numericos();
    r.anadir(nuevo("str")); r.anadir(nuevo("view"));
    ordenar(r);
    return r;
}

fn ordenables() -> list<str> {
    var r = numericos();
    r.anadir(nuevo("bool")); r.anadir(nuevo("str"));
    ordenar(r);
    return r;
}

fn restriccion_admite(r: view) -> list<str> {
    var s: list<str> = [];
    if r == "numero" { s = numericos(); }
    if r == "entero" {
        for t en numericos() {
            if es_tipo_entero(t) { s.anadir(copiar(t)); }
        }
    }
    if r == "decimal" { s.anadir(nuevo("f32")); s.anadir(nuevo("f64")); }
    if r == "igualable" { s = igualables(); }
    if r == "ordenable" { s = comparables(); }
    if r == "texto" { s.anadir(nuevo("str")); s.anadir(nuevo("view")); }
    ordenar(s);
    return s;
}

fn esta_entre(xs: &list<str>, x: view) -> bool {
    for y en xs {
        if igual(y, x) { return true; }
    }
    return false;
}

// ------------------------------------------------------------------
// Las internas
// ------------------------------------------------------------------

struct Interna {
    existe: bool,
    params: list<str>,
    retorno: str,
    falible: bool,
}

fn firma_interna(nombre: view) -> Interna {
    var ps: list<str> = [];
    var r = vacio();
    var fal = false;
    var existe = true;
    if nombre == "vacio" { r = nuevo("str"); }
    else if nombre == "nuevo" { ps.anadir(nuevo("view")); r = nuevo("str"); }
    else if nombre == "vista" { ps.anadir(nuevo("@presta")); r = nuevo("view"); }
    else if nombre == "empujar" {
        ps.anadir(nuevo("@mut")); ps.anadir(nuevo("view")); r = nuevo("()");
    }
    else if nombre == "empujar_byte" {
        ps.anadir(nuevo("@mut")); ps.anadir(nuevo("u8")); r = nuevo("()");
    }
    else if nombre == "largo" { ps.anadir(nuevo("@dimensionable")); r = nuevo("usize"); }
    else if nombre == "igual" || nombre == "menor" {
        ps.anadir(nuevo("@comparable")); ps.anadir(nuevo("@comparable"));
        r = nuevo("bool");
    }
    else if nombre == "rebanar" {
        ps.anadir(nuevo("view")); ps.anadir(nuevo("usize")); ps.anadir(nuevo("usize"));
        r = nuevo("view");
    }
    else if nombre == "imprimir" || nombre == "imprimir_error" {
        ps.anadir(nuevo("@cualquiera")); r = nuevo("()");
    }
    else if nombre == "anadir" {
        ps.anadir(nuevo("@lista_mut")); ps.anadir(nuevo("@elemento")); r = nuevo("()");
    }
    else if nombre == "truncar" {
        ps.anadir(nuevo("@lista_mut")); ps.anadir(nuevo("usize")); r = nuevo("()");
    }
    else if nombre == "texto" { ps.anadir(nuevo("@escalar")); r = nuevo("str"); }
    else if nombre == "copiar" { ps.anadir(nuevo("@copiable")); }
    else if nombre == "intercambiar" {
        ps.anadir(nuevo("@lugar_mut")); ps.anadir(nuevo("@valor_igual"));
    }
    else if nombre == "reservar" { ps.anadir(nuevo("usize")); }
    else if nombre == "redimensionar" {
        ps.anadir(nuevo("@bloque_mut")); ps.anadir(nuevo("usize")); r = nuevo("()");
    }
    else if nombre == "raiz" || nombre == "piso" || nombre == "techo"
    || nombre == "redondear" {
        ps.anadir(nuevo("@decimal"));
    }
    else if nombre == "absoluto" { ps.anadir(nuevo("@con_signo")); }
    else if nombre == "byte" {
        ps.anadir(nuevo("view")); ps.anadir(nuevo("usize")); r = nuevo("usize");
    }
    else if nombre == "n_argumentos" { r = nuevo("usize"); }
    else if nombre == "argumento" { ps.anadir(nuevo("usize")); r = nuevo("view"); }
    else if nombre == "leer_archivo" {
        ps.anadir(nuevo("view")); r = nuevo("str"); fal = true;
    }
    else if nombre == "leer_parte_archivo" {
        ps.anadir(nuevo("view")); ps.anadir(nuevo("usize"));
        ps.anadir(nuevo("usize")); r = nuevo("str"); fal = true;
    }
    else if nombre == "escribir_archivo" {
        ps.anadir(nuevo("view")); ps.anadir(nuevo("view")); r = nuevo("()"); fal = true;
    }
    else if nombre == "leer_linea" || nombre == "entrada_completa" {
        r = nuevo("str"); fal = true;
    }
    else if nombre == "variable_entorno" {
        ps.anadir(nuevo("view")); r = nuevo("str"); fal = true;
    }
    else if nombre == "ahora_ms" || nombre == "monotono_ms" { r = nuevo("i64"); }
    else if nombre == "azar" { ps.anadir(nuevo("usize")); r = nuevo("usize"); }
    else if nombre == "sembrar" { ps.anadir(nuevo("u64")); r = nuevo("()"); }
    else if nombre == "ordenar" { ps.anadir(nuevo("@lista_mut")); r = nuevo("()"); }
    else if nombre == "poner" {
        ps.anadir(nuevo("@mapa_mut")); ps.anadir(nuevo("@clave"));
        ps.anadir(nuevo("@valor")); r = nuevo("()");
    }
    else if nombre == "obtener" {
        ps.anadir(nuevo("@mapa")); ps.anadir(nuevo("@clave")); fal = true;
    }
    else if nombre == "tiene" {
        ps.anadir(nuevo("@mapa")); ps.anadir(nuevo("@clave")); r = nuevo("bool");
    }
    else if nombre == "claves" { ps.anadir(nuevo("@mapa")); }
    else if nombre == "quitar" {
        ps.anadir(nuevo("@mapa_mut")); ps.anadir(nuevo("@clave")); r = nuevo("bool");
    }
    else if nombre == "obtener_mut" {
        ps.anadir(nuevo("@mapa_mut")); ps.anadir(nuevo("@clave")); fal = true;
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
    params: list<Param>,
    // Vacio si no dice que devuelve.
    retorno: str,
    falible: bool,
    externa: bool,
    // De C, y devuelve `cadena_c`: por dentro es un `str`.
    cadena_c: bool,
    tipo_params: list<str>,
    // `T=numero`, en el orden en que se escribieron.
    restricciones: list<str>,
    // Donde esta su arbol: el modulo y la posicion, o la clausura.
    modulo: usize,
    posicion: usize,
    de_cierre: bool,
}

struct Mundo {
    funciones: list<Funcion>,
    indice: map<str, usize>,
    // Structs concretos y plantillas: tipos y nombres de sus campos.
    st_tipos: map<str, list<T.Tipo>>,
    st_nombres: map<str, list<str>>,
    // Struct generico -> sus parametros de tipo.
    st_params: map<str, list<str>>,
    // Enum -> sus formas; `Enum.Forma` -> lo que lleva.
    en_variantes: map<str, list<str>>,
    en_formas: map<str, list<T.Tipo>>,
    // Nombre por dentro -> el que se escribio, para los mensajes.
    bonitos: map<str, str>,
    // Las funciones de las clausuras, que nacen al comprobarlas: la N-1 es
    // `ss_cierre_N`, escrita en el modulo `cierres_mod[N-1]`.
    cierres: list<P.Nodo>,
    cierres_mod: list<usize>,
    n_cierres: usize,
    // Los structs de las clausuras que modifican lo que capturaron:
    // llamarlas las modifica.
    cierres_mut: list<str>,
    // `dueno#k` -> N: la k-esima clausura del cuerpo de `dueno` (una
    // funcion, `plantilla|T1|T2` para la copia de una generica, o
    // `ss_cierre_M`) es `Cierre_N`.
    numeracion: map<str, usize>,
    // Lo que hace falta para comprobar la copia de una generica: el arbol de
    // cada modulo y como se ven los nombres desde el.
    arboles: list<P.Nodo>,
    modulos: list<str>,
    contextos: list<I.Contexto>,
    // Las copias ya creadas: `plantilla|T1|T2`.
    copias: list<str>,
    // Los structs en el orden en que existen para el original: los escritos,
    // y despues cada copia de un generico y cada clausura segun nacen, con
    // el nombre que les da el original (`Par__str_usize`) y su tipo aqui.
    orden_structs: list<str>,
    tipo_de_struct: list<str>,
    // El tipo de cada expresion, por modulo: `dueno#id` -> tipo, con los
    // numeros escritos ya decididos por su contexto. El generador lo lee de
    // aqui en vez de deducirlo otra vez.
    anotados: list<map<str, T.Tipo>>,
    // Los nodos que el comprobador leyo en vez de mover, por `dueno#id`. Vive
    // aqui y no en `Comprobacion` porque `probar_juego` copia `Comprobacion`
    // entera una vez por candidato de instanciacion generica, y con la lista
    // ya completa: tenerla alli salia cuadratico.
    lecturas: list<str>,
    // El complemento: los nodos que el comprobador MOVIO en vez de leer, por
    // `dueno#id`, y con la misma clave. Es el canal por el que viaja la
    // decision de mover para que el generador no la rederive por forma.
    movidas: list<str>,
    // El tercer valor de la misma decision: los nodos que el comprobador paso
    // PRESTADOS —la rama `prestado(p)`, un `&T` o un `mut T`—, por `dueno#id`
    // y con la misma clave. Ni se leen ni se mueven: se prestan, y el
    // generador tiene que saberlo para pedir la direccion en vez del valor sin
    // volver a deducirlo por la forma ni por la firma.
    prestamos: list<str>,
    // Las copias de genericas y las clausuras, en el orden en que nacen: una
    // clausura al verla, una copia despues de comprobar su cuerpo. Es el
    // orden en que el generador las escribe.
    orden_copias: list<str>,
}

fn param_de(texto: view) -> Param {
    var corte = 0;
    while corte < texto.largo() && byte(texto, corte) != 58 { corte = corte + 1; }
    let nombre = recortar(rebanar(texto, 0, corte));
    var resto = recortar(rebanar(texto, corte + 1, texto.largo()));
    var mutable = false;
    var compartido = false;
    if empieza_con(resto, "mut ") {
        mutable = true;
        resto = recortar(rebanar(resto, 4, resto.largo()));
    } else if T.es_referencia_mutable(resto) {
        mutable = true;
        resto = recortar(T.apuntado(resto));
    } else if T.es_referencia(resto) {
        compartido = true;
        resto = recortar(T.apuntado(resto));
    }
    return Param { nombre: nuevo(nombre), tipo: T.sin_alias_tipo(resto),
        mutable: mutable, compartido: compartido };
}

fn prestado(p: &Param) -> bool { return p.mutable || p.compartido; }

// Lo que dice la firma de un nodo `fn`.
fn funcion_de(d: &P.Nodo, nombre: view, archivo: view, modulo: usize,
    posicion: usize, externa: bool) -> Funcion {
    var ps: list<Param> = [];
    var ret = vacio();
    var fal = false;
    var tps: list<str> = [];
    var rs: list<str> = [];
    for h en d.hijos {
        let clase = h.clase;
        match clase {
            Clase.Param -> { ps.anadir(param_de(h.texto)); }
            Clase.RetornoTipo -> { ret = T.sin_alias_tipo(h.texto); }
            Clase.Falible -> { fal = true; }
            Clase.TipoParam -> { tps.anadir(copiar(h.texto)); }
            Clase.Restriccion -> {
                if tps.largo() > 0 {
                    let tp = vista(tps[tps.largo() - 1]);
                    rs.anadir($"{tp}={h.texto}");
                }
            }
            _ -> { }
        }
    }
    var cadena = false;
    if externa && ret == "cadena_c" { cadena = true; }
    return Funcion { nombre: nuevo(nombre), archivo: nuevo(archivo), linea: d.linea,
        params: ps, retorno: ret, falible: fal, externa: externa, cadena_c: cadena,
        tipo_params: tps, restricciones: rs, modulo: modulo, posicion: posicion,
        de_cierre: false };
}

fn tiene_sueltos(f: &Funcion) -> bool { return f.tipo_params.largo() > 0; }

fn buscar_funcion(m: &Mundo, nombre: view) -> usize ! {
    if !tiene(m.indice, nombre) { fail "no es una funcion"; }
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
    if !T.es_aplicacion(t) { return false; }
    let base = T.base_de_aplicacion(t);
    return tiene(m.st_params, base);
}

fn es_struct(m: &Mundo, t: view) -> bool {
    if es_struct_aplicado(m, t) { return true; }
    return tiene(m.st_tipos, t) && !tiene(m.st_params, t);
}

fn es_enum(m: &Mundo, t: view) -> bool { return tiene(m.en_variantes, t); }

// Si ninguna forma del enum lleva nada: sus valores son solo la etiqueta.
fn enum_sin_datos(m: &Mundo, t: view) -> bool {
    let vs = I.lista_de(m.en_variantes, t) sino [];
    for v en vs {
        if formas_de(m, t, v).largo() > 0 { return false; }
    }
    return true;
}

// `==` compara lo que no tiene partes: numeros, `bool`, textos y enums que
// son solo su etiqueta. Con partes habria que decidir que es ser iguales, y
// eso lo escribe quien compara. `""` si `t` se compara.
fn por_que_no_se_compara(m: &Mundo, t: view) -> str {
    if es_enum(m, t) && !enum_sin_datos(m, t) {
        return $"`==` compara enums sin datos, y alguna forma de `{t}` lleva algo: miralo con `match`";
    }
    if es_struct(m, t) || T.es_lista(t) || T.es_mapa(t) || T.es_arreglo(t) || T.es_bloque(t) {
        return $"`==` no compara `{t}`, que tiene partes: compara las que te importen";
    }
    return vacio();
}

// Lo que `imprimir` y `{}` saben escribir: numeros, `bool` y texto, o un
// prestamo de uno de ellos.
fn se_muestra(t: view) -> bool {
    let limpio = sin_prestamo(t);
    return es_numerico(limpio) || limpio == "bool" || limpio == "str" || limpio == "view"
    || igual(limpio, literal()) || igual(limpio, literal_decimal());
}

// Que hacer con un valor que `imprimir` no sabe escribir.
fn como_mostrar(m: &Mundo, t: view) -> str {
    let limpio = sin_prestamo(t);
    if es_enum(m, limpio) { return nuevo("escribe el nombre de cada forma con un `match`"); }
    if es_struct(m, limpio) || T.es_lista(limpio) || T.es_mapa(limpio) || T.es_arreglo(limpio)
    || T.es_bloque(limpio) {
        return nuevo("muestra sus campos o elementos por separado");
    }
    return nuevo("muestra un numero, un `bool` o un texto");
}

// Los campos de un struct, con los tipos de una aplicacion ya puestos.
fn campos_tipos(m: &Mundo, t: view) -> list<str> {
    var salida: list<str> = [];
    if es_struct_aplicado(m, t) {
        let base = T.base_de_aplicacion(t);
        let sueltos = I.lista_de(m.st_params, vista(base)) sino [];
        let dados = T.partes(t);
        if dados.largo() != sueltos.largo() { return salida; }
        var lig: map<str, str> = [];
        var i = 0;
        while i < sueltos.largo() {
            poner(lig, vista(sueltos[i]), copiar(dados[i]));
            i = i + 1;
        }
        let crudos = T.tipos_de_mapa(m.st_tipos, vista(base)) sino [];
        for x en crudos { salida.anadir(T.escribir_tipo(T.sustituir_tipo(x, lig))); }
        return salida;
    }
    return T.escribir_de_mapa_tipos(m.st_tipos, t) sino [];
}

fn campos_nombres(m: &Mundo, t: view) -> list<str> {
    if es_struct_aplicado(m, t) {
        let base = T.base_de_aplicacion(t);
        return I.lista_de(m.st_nombres, vista(base)) sino [];
    }
    return I.lista_de(m.st_nombres, t) sino [];
}

fn campo_tipo(m: &Mundo, t: view, campo: view) -> str {
    let ns = campos_nombres(m, t);
    let ts = campos_tipos(m, t);
    var i = 0;
    while i < ns.largo() && i < ts.largo() {
        if igual(ns[i], campo) { return copiar(ts[i]); }
        i = i + 1;
    }
    return vacio();
}

fn formas_de(m: &Mundo, en_t: view, forma: view) -> list<str> {
    let clave = $"{en_t}.{forma}";
    return T.escribir_de_mapa_tipos(m.en_formas, vista(clave)) sino [];
}

fn tiene_forma(m: &Mundo, en_t: view, forma: view) -> bool {
    let vs = I.lista_de(m.en_variantes, en_t) sino [];
    return esta_entre(vs, forma);
}

// Un valor de este tipo es duenio de memoria del heap: la regla de
// `tipos.t`, con lo que este mundo sabe de structs, genericas y enums.
fn posee_memoria(m: &Mundo, t: view) -> bool {
    var vistos: map<str, usize> = [];
    return T.posee_en(T.leer_tipo(t), m.st_tipos, m.st_params, m.en_variantes, m.en_formas, vistos);
}

// Tiene partes: se puede mirar o modificar por dentro.
fn es_compuesto(m: &Mundo, t: view) -> bool {
    return t == "str" || T.es_bloque(t) || T.es_lista(t) || T.es_mapa(t)
    || T.es_arreglo(t) || es_struct(m, t) || es_enum(m, t);
}

// Se puede guardar un valor de este tipo.
fn almacenable(m: &Mundo, t: view) -> bool {
    if T.es_referencia(t) { return almacenable(m, T.apuntado(t)); }
    if T.es_funcion(t) {
        let partes = T.partes_de_funcion(t);
        if partes.largo() == 0 { return false; }
        var i = 0;
        while i + 1 < partes.largo() {
            if !almacenable(m, partes[i]) { return false; }
            i = i + 1;
        }
        let r = vista(partes[partes.largo() - 1]);
        return r == "()" || almacenable(m, r);
    }
    if es_numerico(t) || t == "str" || t == "view" || t == "bool" {
        return true;
    }
    if es_struct(m, t) || es_enum(m, t) { return true; }
    if T.es_arreglo(t) {
        // Un arreglo tampoco guarda vistas ni prestamos: cada elemento se
        // puede reasignar por un indice que no se conoce al compilar, y no
        // habria forma de saber de quien presta cada uno.
        let e = T.elemento(t);
        return e != "view" && !T.es_referencia(e)
        && !es_prestado_st(m, e) && almacenable(m, e);
    }
    if T.es_mapa(t) {
        let ps = T.partes(t);
        if ps.largo() != 2 { return false; }
        // Un mapa tampoco guarda vistas ni prestamos: nadie sabria cuanto
        // viven.
        return almacenable(m, ps[0]) && almacenable(m, ps[1])
        && ps[0] != "view" && !T.es_referencia(ps[0])
        && !es_prestado_st(m, ps[0])
        && ps[1] != "view" && !T.es_referencia(ps[1])
        && !es_prestado_st(m, ps[1]);
    }
    if T.es_bloque(t) {
        let e = T.elemento(t);
        return e != "view" && !T.es_referencia(e) && !T.es_arreglo(e)
        && !es_prestado_st(m, e) && almacenable(m, e);
    }
    if T.es_lista(t) {
        // Guardar un prestamo pediria expresar cuanto vive lo que apunta.
        let e = T.elemento(t);
        return e != "view" && !T.es_referencia(e) && !T.es_arreglo(e)
        && !es_prestado_st(m, e) && almacenable(m, e);
    }
    return false;
}

// Un struct que presta: lleva una `view`, o un struct que presta. Se trata
// como una vista: apunta a memoria de otro.
fn es_prestado_st(m: &Mundo, t: view) -> bool {
    var vistos: list<str> = [];
    return presta_st(m, t, vistos);
}

fn presta_st(m: &Mundo, t: view, vistos: mut list<str>) -> bool {
    if !es_struct(m, t) || esta_entre(vistos, t) { return false; }
    vistos.anadir(nuevo(t));
    for ct en campos_tipos(m, t) {
        if ct == "view" || presta_st(m, ct, vistos) { return true; }
    }
    return false;
}

// Si un valor de este tipo apunta a memoria de otro.
fn presta_tipo(m: &Mundo, t: view) -> bool {
    return t == "view" || T.es_referencia(t) || es_prestado_st(m, t);
}

// Si el tipo lleva una `view` dentro, a cualquier hondura: el `dato: T` de
// un `Caja<view>`, el `list<Rama<view>>` de un `Arbol<view>`, o la propia
// `view`. `presta_tipo` no basta: se para en las listas, y por dentro de una
// lista tambien hay una vista. Los `vistos` cortan los structs que se
// contienen a si mismos.
fn lleva_vista(m: &Mundo, t: view) -> bool {
    var vistos: list<str> = [];
    return lleva_vista_en(m, t, vistos);
}

fn lleva_vista_en(m: &Mundo, t: view, vistos: mut list<str>) -> bool {
    if t == "view" { return true; }
    if esta_entre(vistos, t) { return false; }
    vistos.anadir(nuevo(t));
    if es_struct(m, t) {
        for ct en campos_tipos(m, t) {
            if lleva_vista_en(m, ct, vistos) { return true; }
        }
        return false;
    }
    for x en T.partes(t) {
        if lleva_vista_en(m, x, vistos) { return true; }
    }
    return false;
}

fn error_enum_prestado(c: mut Comprobacion, m: &Mundo, linea: usize, en_n: view, forma: view,
    t: view) {
    error(c, m, linea, $"`{en_n}.{forma}` lleva un `{t}`, que presta: un enum no guarda prestamos, porque al mirarlo nadie sabria de quien presta. Usa `str`, o un struct con duenio");
}

// Un struct o enum que se contiene a si mismo por valor.
fn se_contiene(m: &Mundo, t: view, buscado: view, vistos: mut list<str>) -> bool {
    if igual(t, buscado) { return true; }
    if T.es_arreglo(t) {
        let e = T.elemento(t);
        return se_contiene(m, e, buscado, vistos);
    }
    if T.es_mapa(t) || T.es_lista(t) { return false; }
    if esta_entre(vistos, t) { return false; }
    if es_enum(m, t) {
        vistos.anadir(nuevo(t));
        let vs = I.lista_de(m.en_variantes, t) sino [];
        for v en vs {
            for x en formas_de(m, t, v) {
                if se_contiene(m, x, buscado, vistos) { return true; }
            }
        }
        return false;
    }
    if !es_struct(m, t) { return false; }
    vistos.anadir(nuevo(t));
    for x en campos_tipos(m, t) {
        if se_contiene(m, x, buscado, vistos) { return true; }
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
    sacados: list<str>,
    // Las vistas vivas que prestan de esta variable, y las reservas.
    prestamos: list<str>,
    // Si es una vista: de quien presta, y de donde sale su memoria. En
    // `origenes`, todos los duenios de los que puede venir, el primero
    // delante.
    origen: str,
    origenes: list<str>,
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
    // El bloque donde se declaro, por su numero: una vista no se menciona mas
    // alla de el. 0 si no se sabe.
    bloque_decl: usize,
}

struct Comprobacion {
    archivo: str,
    modulo: usize,
    // Todos los simbolos vivos, de fuera hacia dentro; `inicios` dice donde
    // empieza cada ambito.
    simbolos: list<Simbolo>,
    inicios: list<usize>,
    errores: list<str>,
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
    movidas_en_bucle: list<list<usize>>,
    en_retorno: usize,
    // Las copias de genericas que se estan comprobando, de fuera hacia
    // dentro: `al usar `f` con T = str, desde archivo:linea`.
    instanciando: list<str>,
    // De quien es el cuerpo que se esta mirando, para numerar sus clausuras.
    dueno: str,
    // Los avisos: no impiden compilar.
    avisos: list<str>,
    // Cada simbolo que ha declarado la funcion en curso, con su estado final:
    // al cerrar su bloque se guarda aqui como quedo.
    historia: list<Simbolo>,
    // Lo que `--explicar` dice de cada funcion comprobada, en orden.
    informe: list<str>,
    // La clausura que se esta comprobando, si hay una: lo que capturo con
    // `mut` y lo que de eso ha modificado de verdad.
    en_cierre: bool,
    capturas_mut: list<str>,
    modificadas: list<str>,
    // La plantilla de cada copia de generica que se esta comprobando, a la
    // par que `instanciando`.
    plantillas: list<usize>,
    // Dentro de la guarda de un brazo: ahi no se mueve nada, porque se
    // evalua aunque el brazo no llegue a casar.
    en_guarda: usize,
    // Mirando el objeto de un `p.x` (no es usar `p` entera), y escribiendo
    // en un campo (no es leerlo).
    por_campo: usize,
    escribiendo: usize,
    // Los campos sacados de su struct en todo el programa, para el
    // generador: `archivo\tlinea\tp.a.b`.
    sacados: list<str>,
    // Las cuentas de numeros escritos que esperan su tipo, en el orden en
    // que se comprobaron, con el dueño de cada una; y las ya hechas, por su
    // clave anotada.
    escritas: list<P.Nodo>,
    escritas_duenos: list<str>,
    contadas: map<str, usize>,
    // Las sentencias que se estan comprobando, de fuera adentro, hasta
    // `hondura`; las de la funcion en curso empiezan en `base`. De cada una:
    // su clase, lo que menciona, lo que mencionan las que la siguen en su
    // bloque, y el bloque. Dicen si una vista se vuelve a usar.
    hondura: usize,
    base: usize,
    cadena_clases: list<str>,
    cadena_propias: list<map<str, usize>>,
    cadena_despues: list<map<str, usize>>,
    cadena_bloques: list<usize>,
}

fn estado(archivo: view, modulo: usize) -> Comprobacion {
    return Comprobacion { archivo: nuevo(archivo), modulo: modulo, simbolos: [],
        inicios: [], errores: [], retorno: vacio(), falible: false,
        en_condicional: 0, en_condicion_bucle: 0, en_bucle: 0,
        en_bucle_directo: 0, movidas_en_bucle: [], en_retorno: 0, instanciando: [],
        dueno: vacio(), avisos: [], historia: [], informe: [], en_cierre: false,
        capturas_mut: [], modificadas: [], plantillas: [], en_guarda: 0,
        por_campo: 0, escribiendo: 0, sacados: [], escritas: [],
        escritas_duenos: [], contadas: [], hondura: 0, base: 0, cadena_clases: [],
        cadena_propias: [], cadena_despues: [], cadena_bloques: [] };
}

// Lo que el mensaje dice en vez de los nombres que puso el compilador: una
// copia de struct generico se llama como su plantilla, una clausura es una
// clausura, y una funcion renombrada, como se escribio.
fn legible(m: &Mundo, mensaje: view) -> str {
    var r = vacio();
    var i = 0;
    while i < mensaje.largo() {
        let c = byte(mensaje, i);
        if T.es_de_nombre(c) && (i == 0 || !T.es_de_nombre(byte(mensaje, i - 1))) {
            var j = i;
            while j < mensaje.largo() && T.es_de_nombre(byte(mensaje, j)) { j = j + 1; }
            let palabra = rebanar(mensaje, i, j);
            let resto = rebanar(mensaje, j, mensaje.largo());
            if j < mensaje.largo() && byte(mensaje, j) == 60 && tiene(m.st_params, palabra)
            && !empieza_con(resto, "<...>") {
                // `Par<i64, usize>` -> `Par`: se salta lo que va entre angulos.
                let dicho = G.escrito(palabra);
                r.empujar(dicho);
                var hondo = 0;
                var k = j;
                while k < mensaje.largo() {
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
            let de_fn = como_struct.largo() > 0
            && largo(I.funcion_de_cierre(como_struct)) > 0;
            if de_fn || (empieza_con(palabra, "Cierre_")
                && largo(I.funcion_de_cierre(palabra)) > 0) {
                r.empujar("clausura");
                i = j;
                continue;
            }
            // Lo que choca con C lleva `ss_id_` delante: se dice como se
            // escribio.
            if tiene(m.bonitos, palabra) {
                let dicho = G.escrito(obtener(m.bonitos, palabra) sino "");
                r.empujar(dicho);
                i = j;
                continue;
            }
            let dicho = G.escrito(palabra);
            r.empujar(dicho);
            i = j;
            continue;
        }
        r.empujar(rebanar(mensaje, i, i + 1));
        i = i + 1;
    }
    return r;
}

fn error(c: mut Comprobacion, m: &Mundo, linea: usize, mensaje: view) {
    let claro = legible(m, mensaje);
    var todo = $"{c.archivo}:{linea}: {claro}";
    // Un error dentro de una generica no se entiende sin saber con que tipos
    // se la uso, ni desde donde: de dentro hacia fuera.
    var i = c.instanciando.largo();
    while i > 0 {
        i = i - 1;
        todo.empujar("\n  ");
        todo.empujar(c.instanciando[i]);
    }
    c.errores.anadir(todo);
}

// Un aviso no impide compilar. Dentro de una generica es el mismo por cada
// juego de tipos: se dice una vez.
fn aviso(c: mut Comprobacion, m: &Mundo, linea: usize, mensaje: view) {
    let claro = legible(m, mensaje);
    let todo = $"{c.archivo}:{linea}: {claro}";
    if c.instanciando.largo() > 0 && esta_entre(c.avisos, todo) { return; }
    c.avisos.anadir(todo);
}

fn abrir_ambito(c: mut Comprobacion) { c.inicios.anadir(c.simbolos.largo()); }

// Buscar de dentro hacia fuera. `largo(simbolos)` si no esta.
fn buscar_simbolo(c: &Comprobacion, nombre: view) -> usize {
    var i = c.simbolos.largo();
    while i > 0 {
        i = i - 1;
        if igual(c.simbolos[i].nombre, nombre) { return i; }
    }
    return c.simbolos.largo();
}

fn existe(c: &Comprobacion, i: usize) -> bool { return i < c.simbolos.largo(); }

fn soltar_prestamo(c: mut Comprobacion, i: usize, quien: view) {
    var quedan: list<str> = [];
    var quitado = false;
    for p en c.simbolos[i].prestamos {
        if !quitado && igual(p, quien) { quitado = true; continue; }
        quedan.anadir(copiar(p));
    }
    c.simbolos[i].prestamos = quedan;
}

// Al cerrar un ambito mueren sus vistas, y con ellas los prestamos que
// tenian sobre variables de fuera.
fn cerrar_ambito(c: mut Comprobacion) {
    if c.inicios.largo() == 0 { return; }
    let desde = c.inicios[c.inicios.largo() - 1];
    var muertos: list<Simbolo> = [];
    var vivos: list<Simbolo> = [];
    var i = 0;
    while i < c.simbolos.largo() {
        if i < desde { vivos.anadir(copiar(c.simbolos[i])); }
        else { muertos.anadir(copiar(c.simbolos[i])); }
        i = i + 1;
    }
    c.simbolos = vivos;
    for s en muertos {
        if s.historia < c.historia.largo() { c.historia[s.historia] = copiar(s); }
    }
    var otros: list<usize> = [];
    var k = 0;
    while k + 1 < c.inicios.largo() {
        otros.anadir(c.inicios[k]);
        k = k + 1;
    }
    c.inicios = otros;
    // Solo lo que presta tiene duenios apuntados.
    for s en muertos {
        if s.origenes.largo() > 0 {
            for o en s.origenes {
                let d = buscar_simbolo(c, o);
                if existe(c, d) && esta_entre(c.simbolos[d].prestamos, s.nombre) {
                    soltar_prestamo(c, d, s.nombre);
                }
            }
        }
    }
}

// Tapar una variable de fuera es un error, como declarar dos veces la misma.
fn declarar_simbolo(c: mut Comprobacion, m: &Mundo, linea: usize, nombre: view, tipo: view,
    mutable: bool) -> usize {
    var desde = 0;
    if c.inicios.largo() > 0 { desde = c.inicios[c.inicios.largo() - 1]; }
    var en_este = false;
    var fuera = false;
    var i = 0;
    while i < c.simbolos.largo() {
        if igual(c.simbolos[i].nombre, nombre) {
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
        es_param: false, historia: c.historia.largo(), movida_a: vacio(),
        bloque_decl: bloque_en_curso(c) };
    c.historia.anadir(copiar(nuevo_s));
    c.simbolos.anadir(nuevo_s);
    return c.simbolos.largo() - 1;
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
    if c.simbolos[i].sacados.largo() == 0 || c.por_campo > 0 { return false; }
    let n = copiar(c.simbolos[i].nombre);
    let primero = copiar(c.simbolos[i].sacados[0]);
    let ruta = antes_de_tab(primero);
    let cuando = despues_de_tab(primero);
    error(c, m, linea, $"`{n}` esta a medio mover: `{n}.{ruta}` se saco en la linea {cuando}. Dale otro valor antes de usarla entera, o usa solo sus otros campos");
    return true;
}

fn antes_de_tab(t: view) -> str {
    var i = 0;
    while i < t.largo() && byte(t, i) != 9 { i = i + 1; }
    return nuevo(rebanar(t, 0, i));
}

fn despues_de_tab(t: view) -> str {
    var i = 0;
    while i < t.largo() && byte(t, i) != 9 { i = i + 1; }
    if i >= t.largo() { return vacio(); }
    return nuevo(rebanar(t, i + 1, t.largo()));
}

fn es_reserva(n: view) -> bool {
    return n == "intercambiar" || n == "redimensionar" || n == "truncar";
}

// Por que no se puede tocar: prestamos vivos, o una reserva.
fn ocupada(vivos: &list<str>) -> str {
    var prestamos: list<str> = [];
    var reservas: list<str> = [];
    for p en vivos {
        if es_reserva(p) { reservas.anadir(copiar(p)); }
        else { prestamos.anadir(copiar(p)); }
    }
    if prestamos.largo() > 0 {
        let l = lista_legible(prestamos);
        return $"esta prestada por {l}";
    }
    let n = vista(reservas[0]);
    if n == "intercambiar" {
        return nuevo("esta reservada por `intercambiar` mientras se calcula el reemplazo");
    }
    if n == "truncar" {
        return nuevo("esta reservada por `truncar` mientras se calcula el recorte");
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
        if c.movidas_en_bucle.largo() > 0 {
            let k = c.movidas_en_bucle.largo() - 1;
            c.movidas_en_bucle[k].anadir(i);
            c.movidas_en_bucle[k].anadir(linea);
        }
    }
    let vivos = prestamos_vivos(c, i);
    if vivos.largo() > 0 {
        let n = copiar(c.simbolos[i].nombre);
        let por = ocupada(vivos);
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
    let de_tipo = sin_prestamo(c.simbolos[i].tipo);
    if esta_entre(m.cierres_mut, de_tipo) {
        // Lo que se modifica es la clausura: se la llama, y guarda lo que
        // capturo con `mut`.
        var arreglo = nuevo("declarala con `var`");
        if c.simbolos[i].es_param {
            arreglo = nuevo("recibela con `mut` delante del tipo");
            // En una generica, el tipo que se escribio: `f: mut F`.
            if c.plantillas.largo() > 0 {
                let k = c.plantillas[c.plantillas.largo() - 1];
                for p en m.funciones[k].params {
                    if igual(p.nombre, n) {
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
    while (x.clase == Clase.Campo || x.clase == Clase.Indice)
    && x.hijos.largo() > 0 {
        if x.clase == Clase.Campo && x.hijos[0].clase == Clase.Variable
        && x.hijos[0].texto == "_ss_entorno" {
            campo = copiar(x.texto);
        }
        let dentro = copiar(x.hijos[0]);
        x = dentro;
    }
    if campo.largo() == 0 { return false; }
    if esta_entre(c.capturas_mut, campo) {
        if !esta_entre(c.modificadas, campo) { c.modificadas.anadir(copiar(campo)); }
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
    let por_campo = lugar.clase == Clase.Campo;
    if por_campo { c.por_campo = c.por_campo + 1; }
    let a_medias = a_medio_mover(c, m, linea, i);
    if por_campo { c.por_campo = c.por_campo - 1; }
    if a_medias { return; }
    let t = copiar(c.simbolos[i].tipo);
    let n = copiar(c.simbolos[i].nombre);
    if por_referencia && T.es_referencia(t) {
        if !T.es_referencia_mutable(t) {
            error_solo_lectura(c, m, linea, n, t);
        } else {
            let vivos_r = prestamos_vivos(c, i);
            if vivos_r.largo() > 0 {
                let por = ocupada(vivos_r);
                error(c, m, linea, $"no se puede modificar `{n}`: {por}");
            }
        }
        return;
    }
    if !c.simbolos[i].mutable {
        error_no_mutable(c, m, linea, i);
        return;
    }
    let vivos = prestamos_vivos(c, i);
    if vivos.largo() > 0 {
        let por = ocupada(vivos);
        error(c, m, linea, $"no se puede modificar `{n}`: {por}");
    }
}

// ------------------------------------------------------------------
// Caminos que se excluyen: fotos del estado de los movimientos
// ------------------------------------------------------------------

// Cuatro numeros por simbolo vivo: movida, en que linea, entregada, y si se
// le dio otro valor al nivel directo del bucle.
fn foto(c: &Comprobacion) -> list<usize> {
    var f: list<usize> = [];
    for s en c.simbolos {
        if s.movida { f.anadir(1); } else { f.anadir(0); }
        f.anadir(s.movida_en);
        f.anadir(s.entregada_en);
        if s.reasignada_directo { f.anadir(1); } else { f.anadir(0); }
    }
    return f;
}

fn restaurar_foto(c: mut Comprobacion, f: &list<usize>) {
    var i = 0;
    while i < c.simbolos.largo() && 4 * i + 3 < f.largo() {
        c.simbolos[i].movida = f[4 * i] == 1;
        c.simbolos[i].movida_en = f[4 * i + 1];
        c.simbolos[i].entregada_en = f[4 * i + 2];
        c.simbolos[i].reasignada_directo = f[4 * i + 3] == 1;
        i = i + 1;
    }
}

// Lo que sobrevive a dos caminos: movido en uno cuenta como movido.
fn juntar_ramas(c: mut Comprobacion, a: &list<usize>, b: &list<usize>) {
    var i = 0;
    while i < c.simbolos.largo() && 4 * i + 3 < a.largo() {
        var mb = a[4 * i];
        var lb = a[4 * i + 1];
        var eb = a[4 * i + 2];
        var rb = a[4 * i + 3];
        if 4 * i + 3 < b.largo() {
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

// El bloque no continua: sale por `return`, `fail`, `break` o `continue`.
fn bloque_termina(n: &P.Nodo) -> bool {
    if n.hijos.largo() == 0 { return false; }
    let ultima = n.hijos[n.hijos.largo() - 1].clase;
    return ultima == Clase.Retorno || ultima == Clase.Falla
    || ultima == Clase.Romper || ultima == Clase.Continuar;
}

// Todos los caminos de este bloque salen de la funcion.
fn siempre_sale(n: &P.Nodo) -> bool {
    if n.hijos.largo() == 0 { return false; }
    let k = n.hijos.largo() - 1;
    let clase = n.hijos[k].clase;
    if clase == Clase.Retorno || clase == Clase.Falla { return true; }
    if clase == Clase.Si && n.hijos[k].hijos.largo() == 3 {
        return siempre_sale(n.hijos[k].hijos[1]) && siempre_sale_rama(n.hijos[k].hijos[2]);
    }
    if clase == Clase.Expresion && n.hijos[k].hijos.largo() == 1 {
        return match_siempre_sale(n.hijos[k].hijos[0]);
    }
    return false;
}

// Un `match` exhaustivo tambien sale si cada brazo es un bloque que sale.
// Los brazos que dan una expresion llevan un `Retorno` interno, pero ese es
// el valor del brazo, no un `return` de la funcion.
fn match_siempre_sale(n: &P.Nodo) -> bool {
    if n.clase != Clase.Match || n.hijos.largo() <= 1 { return false; }
    var i = 1;
    while i < n.hijos.largo() {
        if n.hijos[i].hijos.largo() == 0 { return false; }
        let k = n.hijos[i].hijos.largo() - 1;
        if n.hijos[i].hijos[k].clase != Clase.Bloque
        || !siempre_sale(n.hijos[i].hijos[k]) { return false; }
        i = i + 1;
    }
    return true;
}

// La rama `else` puede ser un bloque o, en `else if`, otra sentencia.
fn siempre_sale_rama(n: &P.Nodo) -> bool {
    if n.clase == Clase.Bloque { return siempre_sale(n); }
    var b = P.rama(Clase.Bloque, n.linea);
    b.hijos.anadir(copiar(n));
    return siempre_sale(b);
}

fn termina_rama(n: &P.Nodo) -> bool {
    if n.clase == Clase.Bloque { return bloque_termina(n); }
    let clase = n.clase;
    return clase == Clase.Retorno || clase == Clase.Falla
    || clase == Clase.Romper || clase == Clase.Continuar;
}

// La variable en la raiz de `x`, `p.a.b` o `v[i][j]`.
fn variable_base(n: &P.Nodo) -> str {
    let clase = n.clase;
    if clase == Clase.Variable { return copiar(n.texto); }
    if (clase == Clase.Campo || clase == Clase.Indice) && n.hijos.largo() > 0 {
        return variable_base(n.hijos[0]);
    }
    return vacio();
}

// Lo que presta un sitio, como camino: `p.a.b`. Un indice no se sigue
// —`v[i]` y `v[j]` pueden ser el mismo elemento—, asi que `v[i].x` presta
// todo `v`.
fn camino_de(n: &P.Nodo) -> str {
    var cortado = false;
    return camino_y_corte(n, cortado);
}

fn camino_y_corte(n: &P.Nodo, cortado: mut bool) -> str {
    let clase = n.clase;
    if clase == Clase.Variable { return copiar(n.texto); }
    if n.hijos.largo() == 0 { return vacio(); }
    if clase != Clase.Campo && clase != Clase.Indice { return vacio(); }
    let dentro = camino_y_corte(n.hijos[0], cortado);
    if dentro.largo() == 0 { return dentro; }
    if clase == Clase.Indice {
        cortado = true;
        return dentro;
    }
    if cortado { return dentro; }
    return $"{dentro}.{n.texto}";
}

// Si dos caminos pueden ser la misma memoria: `p.a` y `p.a.b` si, uno
// contiene al otro; `p.a` y `p.b` no.
fn solapan(a: view, b: view) -> bool {
    if igual(a, b) { return true; }
    return empieza_con(b, $"{a}.") || empieza_con(a, $"{b}.");
}

// Lo que dejan prestado los argumentos de una llamada, como caminos. Dos
// prestamos de lo mismo solo conviven si ninguno modifica: si no, el callee
// tendria dos nombres para la misma memoria.
struct Prestamos {
    caminos: list<str>,
    quienes: list<str>,
    mutables: list<bool>,
}

fn prestamos() -> Prestamos {
    return Prestamos { caminos: [], quienes: [], mutables: [] };
}

// El prestamo anterior que no convive con este: lo que se presta dos veces y
// quien lo presto, o nada. Primero uno que modifica.
fn choque_prestamo(p: &Prestamos, camino: view, mutable: bool) -> list<str> {
    var salida: list<str> = [];
    var vuelta = 0;
    while vuelta < 2 {
        var k = 0;
        while k < p.caminos.largo() {
            let modifica = p.mutables[k];
            let toca = if vuelta == 0 { modifica } else { mutable && !modifica };
            if toca && solapan(camino, p.caminos[k]) {
                if camino.largo() <= p.caminos[k].largo() { salida.anadir(nuevo(camino)); }
                else { salida.anadir(copiar(p.caminos[k])); }
                salida.anadir(copiar(p.quienes[k]));
                return salida;
            }
            k = k + 1;
        }
        vuelta = vuelta + 1;
    }
    return salida;
}

fn apuntar_prestamo(p: mut Prestamos, camino: view, quien: view, mutable: bool) {
    p.caminos.anadir(nuevo(camino));
    p.quienes.anadir(nuevo(quien));
    p.mutables.anadir(mutable);
}

// ------------------------------------------------------------------
// De donde sale la memoria de una vista
// ------------------------------------------------------------------

fn procedencia_de(c: &Comprobacion, m: &Mundo, n: &P.Nodo) -> str {
    let clase = n.clase;
    match clase {
        Clase.Try -> {
            if n.hijos.largo() > 0 { return procedencia_de(c, m, n.hijos[0]); }
        }
        Clase.Sino -> {
            if n.hijos.largo() == 2 {
                let a = procedencia_de(c, m, n.hijos[0]);
                let b = procedencia_de(c, m, n.hijos[1]);
                if a == "local" || b == "local" { return nuevo("local"); }
                if a == "parametro" || b == "parametro" {
                    return nuevo("parametro");
                }
                return nuevo("estatico");
            }
        }
        Clase.Cadena -> { return nuevo("estatico"); }
        Clase.Variable -> {
            let i = buscar_simbolo(c, n.texto);
            if !existe(c, i) { return nuevo("local"); }
            if c.simbolos[i].tipo == "view" || es_prestado_st(m, c.simbolos[i].tipo) {
                if c.simbolos[i].procedencia.largo() > 0 { return copiar(c.simbolos[i].procedencia); }
                return nuevo("local");
            }
            return nuevo("local");
        }
        Clase.LiteralStruct -> {
            // Lo peor de lo que prestan sus campos.
            let st = I.sin_modulo(n.texto);
            var peor = nuevo("estatico");
            for h en n.hijos {
                if h.hijos.largo() == 0 { continue; }
                if !presta_tipo(m, tipo_del_campo(m, st, h.texto)) { continue; }
                let p = procedencia_de(c, m, h.hijos[0]);
                if p == "local" { return nuevo("local"); }
                if p == "parametro" { peor = nuevo("parametro"); }
            }
            return peor;
        }
        Clase.Campo -> {
            let raiz = variable_base(n);
            let i = buscar_simbolo(c, raiz);
            if raiz.largo() > 0 && existe(c, i) {
                let t = copiar(c.simbolos[i].tipo);
                // Un campo de lo que llego prestado es parte de lo prestado:
                // da igual que el campo en si no preste. La memoria es de
                // quien presto la raiz.
                if c.simbolos[i].prestado || T.es_referencia(t) { return nuevo("parametro"); }
                let tc = tipo_simple(c, m, n);
                if presta_tipo(m, tc) && es_prestado_st(m, t) {
                    if c.simbolos[i].procedencia.largo() > 0 { return copiar(c.simbolos[i].procedencia); }
                    return nuevo("local");
                }
            }
            return nuevo("local");
        }
        Clase.Indice -> {
            let raiz = variable_base(n);
            let i = buscar_simbolo(c, raiz);
            if raiz.largo() > 0 && existe(c, i) {
                let t = copiar(c.simbolos[i].tipo);
                if c.simbolos[i].prestado || T.es_referencia(t) { return nuevo("parametro"); }
            }
            return nuevo("local");
        }
        Clase.Llamada -> {
            let nombre = resolver_nombre(c_tipos_vacio(), n.texto);
            let nn = vista(nombre);
            if nn == "argumento" { return nuevo("estatico"); }
            if (nn == "vista" || nn == "obtener" || nn == "obtener_mut")
            && n.hijos.largo() > 0 {
                let base = variable_base(n.hijos[0]);
                let i = buscar_simbolo(c, base);
                if base.largo() > 0 && existe(c, i) {
                    if c.simbolos[i].procedencia.largo() > 0 {
                        return copiar(c.simbolos[i].procedencia);
                    }
                    // Prestado, pero no todo lo prestado viene del que llama:
                    // la variable de un `for` presta de su coleccion, que puede
                    // ser un temporal. Solo un parametro presta de fuera.
                    if c.simbolos[i].prestado && c.simbolos[i].es_param {
                        return nuevo("parametro");
                    }
                }
                return nuevo("local");
            }
            if nn == "nuevo" || nn == "vacio" { return nuevo("local"); }
            if nn == "rebanar" {
                if n.hijos.largo() > 0 { return procedencia_de(c, m, n.hijos[0]); }
                return nuevo("local");
            }
            if nn == "copiar" && n.hijos.largo() == 1 {
                let tc = tipo_simple(c, m, n.hijos[0]);
                if presta_tipo(m, tc) { return procedencia_de(c, m, n.hijos[0]); }
            }
            let k = buscar_funcion(m, nn) sino m.funciones.largo();
            if k >= m.funciones.largo() || tiene_sueltos(m.funciones[k]) { return nuevo("local"); }
            let ret = copiar(m.funciones[k].retorno);
            if !presta_tipo(m, ret) || T.es_referencia(ret) { return nuevo("local"); }
            var peor = nuevo("estatico");
            var i = 0;
            while i < n.hijos.largo() && i < m.funciones[k].params.largo() {
                var p = vacio();
                let pt = vista(m.funciones[k].params[i].tipo);
                if pt == "view" {
                    let visto = prestado_como_vista(c, m, n.hijos[i]);
                    p = procedencia_de(c, m, visto);
                } else if !prestado(m.funciones[k].params[i]) && es_prestado_st(m, pt) {
                    p = procedencia_de(c, m, n.hijos[i]);
                } else if prestado(m.funciones[k].params[i]) {
                    let base = variable_base(n.hijos[i]);
                    let j = buscar_simbolo(c, base);
                    if base.largo() > 0 && existe(c, j) && c.simbolos[j].prestado {
                        p = nuevo("parametro");
                    } else {
                        p = nuevo("local");
                    }
                }
                if p == "local" { return nuevo("local"); }
                if p == "parametro" { peor = nuevo("parametro"); }
                i = i + 1;
            }
            return peor;
        }
        _ -> { }
    }
    return nuevo("local");
}

// Lo que se pasa donde se pide una vista, como lo mira el prestamo: un
// `str` con nombre se presta solo, y es como si llevara `vista(...)` escrito.
// Sin esto, `f(p.nombre)` con `p` prestado pareceria un temporal, y
// `f(vista(p.nombre))` no.
fn prestado_como_vista(c: &Comprobacion, m: &Mundo, arg: &P.Nodo) -> P.Nodo {
    if P.es_lugar(arg) {
        let t = tipo_del_sitio(c, m, arg);
        let limpio = sin_prestamo(t);
        if limpio == "str" {
            var v = P.rama(Clase.Llamada, arg.linea);
            v.texto.empujar("vista");
            v.hijos.anadir(copiar(arg));
            return v;
        }
    }
    return copiar(arg);
}

// El tipo de una variable, un campo o un elemento, a cualquier hondura:
// `xs[0].nombre`. `""` si no se sabe.
fn tipo_del_sitio(c: &Comprobacion, m: &Mundo, n: &P.Nodo) -> str {
    let clase = n.clase;
    if clase == Clase.Indice && n.hijos.largo() > 0 {
        let base = tipo_del_sitio(c, m, n.hijos[0]);
        if T.es_lista(base) || T.es_arreglo(base) {
            return T.elemento(base);
        }
        return vacio();
    }
    if clase == Clase.Campo && n.hijos.largo() > 0 {
        let base = tipo_del_sitio(c, m, n.hijos[0]);
        if base.largo() == 0 || !es_struct(m, base) { return vacio(); }
        return tipo_del_campo(m, base, n.texto);
    }
    return tipo_simple(c, m, n);
}

// Un contexto sin nada: para resolver nombres que no dependen del modulo.
fn c_tipos_vacio() -> I.Contexto { return I.contexto(); }

// De que variable duenia sale una vista, si sale de alguna: la primera de
// las posibles.
fn origen_de(c: &Comprobacion, m: &Mundo, n: &P.Nodo) -> str {
    for o en origenes_de(c, m, n) {
        if o != "<temporal>" { return copiar(o); }
    }
    return vacio();
}

fn juntar_origenes(salida: mut list<str>, de: &list<str>) {
    for x en de {
        if x.largo() > 0 && !esta_entre(salida, x) { salida.anadir(copiar(x)); }
    }
}

// Todas las variables duenias de las que puede venir una vista, en orden y
// sin repetir. `<temporal>` si puede venir de un valor sin nombre, recien
// hecho, que se libera al acabar la sentencia: una vista suya no se guarda.
fn origenes_de(c: &Comprobacion, m: &Mundo, n: &P.Nodo) -> list<str> {
    var salida: list<str> = [];
    let clase = n.clase;
    match clase {
        Clase.Try -> {
            if n.hijos.largo() > 0 { return origenes_de(c, m, n.hijos[0]); }
        }
        Clase.Sino -> {
            if n.hijos.largo() == 2 {
                juntar_origenes(salida, origenes_de(c, m, n.hijos[0]));
                juntar_origenes(salida, origenes_de(c, m, n.hijos[1]));
                return salida;
            }
        }
        Clase.Llamada -> {
            let nombre = I.sin_modulo(n.texto);
            let nn = vista(nombre);
            if nn == "vista" && n.hijos.largo() > 0 {
                let base = variable_base(n.hijos[0]);
                if base.largo() > 0 { salida.anadir(base); }
                return salida;
            }
            if nn == "rebanar" && n.hijos.largo() > 0 { return origenes_de(c, m, n.hijos[0]); }
            if (nn == "obtener" || nn == "obtener_mut") && n.hijos.largo() > 0 {
                let base = variable_base(n.hijos[0]);
                if base.largo() > 0 { salida.anadir(base); } else { salida.anadir(nuevo("<temporal>")); }
                return salida;
            }
            if nn == "copiar" && n.hijos.largo() == 1 {
                // La copia de algo que presta presta de lo mismo. El tipo va
                // aparte: dentro del `&&` se calcularia siempre.
                let tc = tipo_simple(c, m, n.hijos[0]);
                if presta_tipo(m, tc) { return origenes_de(c, m, n.hijos[0]); }
            }
            // Una funcion que devuelve `view` solo puede devolver algo derivado
            // de lo que le prestaron. No se sabe de cual, asi que de todos.
            let k = funcion_vista(c, m, n.texto);
            if k < m.funciones.largo() {
                let ret = vista(m.funciones[k].retorno);
                if ret.largo() > 0 && !T.es_referencia(ret)
                && (presta_tipo(m, ret) || lleva_suelto(ret, m.funciones[k].tipo_params)) {
                    juntar_origenes(salida, origenes_de_args(c, m, n, 0, k));
                }
                return salida;
            }
            let iv = buscar_simbolo(c, n.texto);
            if existe(c, iv) {
                // Una clausura: el entorno va delante, prestado, y lo demas como
                // en su funcion.
                let tv = sin_prestamo(c.simbolos[iv].tipo);
                let de_cierre = I.funcion_de_cierre(tv);
                let kc = buscar_funcion(m, de_cierre) sino m.funciones.largo();
                if de_cierre.largo() > 0 && kc < m.funciones.largo() {
                    let ret = vista(m.funciones[kc].retorno);
                    if presta_tipo(m, ret) && !T.es_referencia(ret) {
                        var entorno: list<str> = [];
                        entorno.anadir(copiar(n.texto));
                        juntar_origenes(salida, entorno);
                        juntar_origenes(salida, origenes_de_args(c, m, n, 1, kc));
                    }
                } else if T.es_funcion(c.simbolos[iv].tipo) {
                    // Un puntero a funcion: su tipo dice lo mismo que la firma.
                    juntar_origenes(salida, origenes_de_puntero(c, m, n, c.simbolos[iv].tipo));
                }
            }
            return salida;
        }
        Clase.SiExpr -> {
            if n.hijos.largo() == 3 {
                // Puede ser cualquiera de las dos ramas.
                juntar_origenes(salida, origenes_de(c, m, n.hijos[1]));
                juntar_origenes(salida, origenes_de(c, m, n.hijos[2]));
                return salida;
            }
        }
        Clase.Match -> {
            if n.hijos.largo() > 0 {
                // Lo que da cada brazo; y si da algo que atrapo el patron, el valor
                // mirado: lo atrapado es un prestamo suyo.
                var mirado: list<str> = [];
                var visto = false;
                var k = 1;
                while k < n.hijos.largo() {
                    for h en n.hijos[k].hijos {
                        if h.clase != Clase.Retorno || h.hijos.largo() != 1 { continue; }
                        juntar_origenes(salida, origenes_de(c, m, h.hijos[0]));
                        var atrapados: list<str> = [];
                        atrapados_de(n.hijos[k], atrapados);
                        if atrapados.largo() > 0 && menciona(h.hijos[0], atrapados) {
                            if !visto {
                                mirado = origenes_mirado(c, m, n.hijos[0]);
                                if mirado.largo() == 0 { mirado.anadir(nuevo("<temporal>")); }
                                visto = true;
                            }
                            juntar_origenes(salida, mirado);
                        }
                    }
                    k = k + 1;
                }
                return salida;
            }
        }
        Clase.Variable -> {
            let i = buscar_simbolo(c, n.texto);
            if existe(c, i) && (c.simbolos[i].tipo == "view"
                || es_prestado_st(m, c.simbolos[i].tipo)) {
                return copiar(c.simbolos[i].origenes);
            }
            if existe(c, i) && c.simbolos[i].tipo == "str" {
                salida.anadir(copiar(n.texto));
            }
        }
        Clase.LiteralStruct -> {
            // Un struct que presta, de lo que prestan sus campos.
            let st = I.sin_modulo(n.texto);
            for h en n.hijos {
                if h.hijos.largo() == 0 { continue; }
                if !presta_tipo(m, tipo_del_campo(m, st, h.texto)) { continue; }
                var de = origenes_de(c, m, h.hijos[0]);
                if de.largo() == 0 && h.hijos[0].clase != Clase.Variable
                && es_local(procedencia_de(c, m, h.hijos[0])) {
                    de.anadir(nuevo("<temporal>"));
                }
                juntar_origenes(salida, de);
            }
            return salida;
        }
        _ -> {
            if clase == Clase.Campo || clase == Clase.Indice {
                // Un sitio dentro de una variable: presta de ella. Si es la vista de
                // un struct que presta, de lo mismo que el. Si la variable llego
                // prestada, la memoria es de quien llama.
                let raiz = variable_base(n);
                let i = buscar_simbolo(c, raiz);
                if raiz.largo() == 0 || !existe(c, i) { return salida; }
                let t = copiar(c.simbolos[i].tipo);
                if c.simbolos[i].prestado || T.es_referencia(t) { return salida; }
                let tc = tipo_simple(c, m, n);
                if es_prestado_st(m, t) && presta_tipo(m, tc) {
                    return copiar(c.simbolos[i].origenes);
                }
                salida.anadir(copiar(raiz));
            }
        }
    }
    return salida;
}

// La funcion de un nombre como la ve el modulo que se comprueba. Sin su
// contexto, por el nombre sin modulo.
fn funcion_vista(c: &Comprobacion, m: &Mundo, escrito: view) -> usize {
    if c.modulo < m.contextos.largo() {
        return funcion_llamada(m, m.contextos[c.modulo], escrito);
    }
    let corto = I.sin_modulo(escrito);
    return buscar_funcion(m, corto) sino m.funciones.largo();
}

// Si el tipo `t` nombra alguno de los parametros de tipo `sueltos`.
fn lleva_suelto(t: view, sueltos: &list<str>) -> bool {
    var i = 0;
    while i < t.largo() {
        if T.es_de_nombre(byte(t, i)) {
            var j = i;
            while j < t.largo() && T.es_de_nombre(byte(t, j)) { j = j + 1; }
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
    k: usize) -> list<str> {
    var salida: list<str> = [];
    var i = desde;
    while i < m.funciones[k].params.largo() && i - desde < n.hijos.largo() {
        let pt = vista(m.funciones[k].params[i].tipo);
        var arg = copiar(n.hijos[i - desde]);
        if pt == "view" { arg = prestado_como_vista(c, m, n.hijos[i - desde]); }
        let del_arg = tipo_simple(c, m, arg);
        let suelto = lleva_suelto(pt, m.funciones[k].tipo_params)
        && del_arg != "str";
        if pt == "view"
        || (!prestado(m.funciones[k].params[i]) && (es_prestado_st(m, pt) || suelto)) {
            var de_arg = origenes_de(c, m, arg);
            if !suelto && de_arg.largo() == 0 && arg.clase != Clase.Variable
            && es_local(procedencia_de(c, m, arg)) {
                // Un `str` recien hecho donde se pide una vista.
                de_arg.anadir(nuevo("<temporal>"));
            }
            juntar_origenes(salida, de_arg);
        } else if prestado(m.funciones[k].params[i]) {
            let base = variable_base(arg);
            var de_arg: list<str> = [];
            if base.largo() > 0 { de_arg.anadir(copiar(base)); } else { de_arg.anadir(nuevo("<temporal>")); }
            juntar_origenes(salida, de_arg);
            // Si lo prestado presta a su vez, tambien de lo suyo.
            let j = buscar_simbolo(c, base);
            if base.largo() > 0 && existe(c, j) && es_prestado_st(m, c.simbolos[j].tipo) {
                juntar_origenes(salida, c.simbolos[j].origenes);
            }
        }
        i = i + 1;
    }
    return salida;
}

// Lo que presta el resultado de llamar a una variable que guarda una funcion:
// su tipo dice lo mismo que una firma.
fn origenes_de_puntero(c: &Comprobacion, m: &Mundo, n: &P.Nodo, tipo: view) -> list<str> {
    var salida: list<str> = [];
    let partes = T.partes_de_funcion(tipo);
    if partes.largo() == 0 { return salida; }
    if !presta_tipo(m, partes[partes.largo() - 1]) { return salida; }
    var i = 0;
    while i + 1 < partes.largo() && i < n.hijos.largo() {
        let pt = vista(partes[i]);
        if T.es_referencia(pt) {
            let base = variable_base(n.hijos[i]);
            var de_arg: list<str> = [];
            if base.largo() > 0 { de_arg.anadir(copiar(base)); } else { de_arg.anadir(nuevo("<temporal>")); }
            juntar_origenes(salida, de_arg);
            let j = buscar_simbolo(c, base);
            if base.largo() > 0 && existe(c, j) && presta_tipo(m, c.simbolos[j].tipo) {
                juntar_origenes(salida, c.simbolos[j].origenes);
            }
        } else if presta_tipo(m, pt) {
            var de_arg = origenes_de(c, m, n.hijos[i]);
            if de_arg.largo() == 0 && n.hijos[i].clase != Clase.Variable
            && es_local(procedencia_de(c, m, n.hijos[i])) {
                de_arg.anadir(nuevo("<temporal>"));
            }
            juntar_origenes(salida, de_arg);
        }
        i = i + 1;
    }
    return salida;
}

// De que variables es lo que atrapa un patron: de la del valor mirado, y si
// esa es un prestamo, tambien de lo que presta.
fn origenes_mirado(c: &Comprobacion, m: &Mundo, valor: &P.Nodo) -> list<str> {
    var salida: list<str> = [];
    let base = variable_base(valor);
    let i = buscar_simbolo(c, base);
    if base.largo() == 0 || !existe(c, i) { return salida; }
    salida.anadir(copiar(base));
    if presta_tipo(m, c.simbolos[i].tipo) {
        juntar_origenes(salida, c.simbolos[i].origenes);
    }
    return salida;
}

// Los nombres que atrapa el patron de un brazo, a cualquier hondura.
fn atrapados_de(b: &P.Nodo, salida: mut list<str>) {
    for h en b.hijos {
        if h.clase == Clase.Atrapa && h.texto != "_" {
            salida.anadir(copiar(h.texto));
        } else if h.clase == Clase.Patron {
            atrapados_de(h, salida);
        }
    }
}

// Si en `n` se lee alguna de estas variables.
fn menciona(n: &P.Nodo, nombres: &list<str>) -> bool {
    if n.clase == Clase.Variable && esta_entre(nombres, n.texto) { return true; }
    for h en n.hijos {
        if menciona(h, nombres) { return true; }
    }
    return false;
}

// Las variables que un argumento deja prestadas mientras dura la llamada,
// cuando va a un sitio que presta (`view`, un struct que presta). Un `str`
// suelto donde se pide `view` se presta entero; una vista con nombre ya
// tiene sus prestamos apuntados en sus duenios.
fn prestados_por(c: &Comprobacion, m: &Mundo, arg: &P.Nodo, t: view) -> list<str> {
    var salida: list<str> = [];
    let clase = arg.clase;
    if clase == Clase.Variable {
        let i = buscar_simbolo(c, arg.texto);
        if existe(c, i) {
            let limpio = sin_prestamo(c.simbolos[i].tipo);
            if limpio == "str" { salida.anadir(copiar(arg.texto)); }
        }
        return salida;
    }
    let limpio = sin_prestamo(t);
    if limpio == "str" && (clase == Clase.Campo || clase == Clase.Indice) {
        let camino = camino_de(arg);
        if camino.largo() > 0 { salida.anadir(camino); }
        return salida;
    }
    // `vista(p.a)` presta solo `p.a`. `vista` solo mira un `str`: lo demas
    // ya es un error.
    if clase == Clase.Llamada && arg.texto == "vista" && arg.hijos.largo() == 1
    && (arg.hijos[0].clase == Clase.Campo || arg.hijos[0].clase == Clase.Indice) {
        let camino = camino_de(arg.hijos[0]);
        if camino.largo() > 0 { salida.anadir(camino); }
        return salida;
    }
    for o en origenes_de(c, m, arg) {
        if o != "<temporal>" { salida.anadir(copiar(o)); }
    }
    return salida;
}

// El tipo de un campo de un struct, o vacio.
fn tipo_del_campo(m: &Mundo, st: view, campo_n: view) -> str {
    let ns = campos_nombres(m, st);
    let ts = campos_tipos(m, st);
    var i = 0;
    while i < ns.largo() && i < ts.largo() {
        if igual(ns[i], campo_n) { return copiar(ts[i]); }
        i = i + 1;
    }
    return vacio();
}

// El tipo de una variable o de un campo, sin comprobar nada.
fn tipo_simple(c: &Comprobacion, m: &Mundo, n: &P.Nodo) -> str {
    if n.clase == Clase.Variable {
        let i = buscar_simbolo(c, n.texto);
        if existe(c, i) { return sin_prestamo(c.simbolos[i].tipo); }
        return vacio();
    }
    if n.clase == Clase.Campo && n.hijos.largo() > 0 {
        let base = tipo_simple(c, m, n.hijos[0]);
        if base.largo() == 0 || !es_struct(m, base) { return vacio(); }
        return tipo_del_campo(m, base, n.texto);
    }
    return vacio();
}

fn es_local(procedencia: str) -> bool { return procedencia == "local"; }

// En que bloque esta declarado el simbolo `i`: 0 es el de fuera.
fn nivel_de_simbolo(c: &Comprobacion, i: usize) -> usize {
    var n = 0;
    var k = 0;
    while k < c.inicios.largo() {
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
    apuntar_a(c, m, linea, i, nuevos);
}

// `let x: &T = l[i];`: un prestamo de un sitio que ya existe —una variable,
// un campo, un elemento—, no de lo que da una llamada. Solo de lo que tiene
// partes: un escalar se copia, y pedirlo prestado sigue siendo el error de
// siempre. Un `&T` que ya se tiene se copia como cualquier otro valor.
fn presta_un_sitio(c: &Comprobacion, m: &Mundo, escrito: view, valor: &P.Nodo) -> bool {
    if !T.es_referencia(escrito) { return false; }
    let cl = valor.clase;
    if cl != Clase.Variable && cl != Clase.Campo && cl != Clase.Indice { return false; }
    if !es_compuesto(m, T.apuntado(escrito)) { return false; }
    if cl == Clase.Variable {
        let iv = buscar_simbolo(c, valor.texto);
        if existe(c, iv) && T.es_referencia(c.simbolos[iv].tipo) { return false; }
    }
    return true;
}

// `x` apunta al sitio sin copiarlo. Mientras se use, la variable de la que
// sale queda prestada entera —de un elemento no se sigue el indice, como en
// una llamada—: no se mueve ni se modifica, salvo a traves de `x` si es
// `&mut`.
fn prestar_sitio(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo,
    nombre: view, escrito: view, mutable: bool) {
    let valor: &P.Nodo = s.hijos[0];
    let t = comprobar_expresion(c, m, tipos, valor, "", false);
    let base = variable_base(valor);
    let ib = buscar_simbolo(c, base);
    let quiere = T.apuntado(escrito);
    let dado = sin_prestamo(T.escribir_tipo(t));
    if T.conocido(t) && !igual(dado, quiere) {
        error(c, m, s.linea, $"`{nombre}` se declaro `{escrito}` pero el valor es `{dado}`");
    }
    if base.largo() > 0 && existe(c, ib) && T.es_referencia_mutable(escrito) {
        let por_puntero = T.es_referencia(c.simbolos[ib].tipo);
        mutar(c, m, valor, s.linea, ib, por_puntero);
    }
    let i = declarar_simbolo(c, m, s.linea, nombre, escrito, mutable);
    c.simbolos[i].prestado = true;
    c.simbolos[i].procedencia = nuevo("local");
    if base.largo() == 0 || !existe(c, ib) { return; }
    // Presta de la variable, y si ella misma presta, de lo suyo.
    var origenes: list<str> = [nuevo(base)];
    if presta_tipo(m, c.simbolos[ib].tipo) {
        for o en c.simbolos[ib].origenes {
            if !esta_entre(origenes, o) { origenes.anadir(copiar(o)); }
        }
    }
    apuntar_a(c, m, s.linea, i, origenes);
}

// La vista del simbolo `i` pasa a apuntar a `nuevos`: cada duenio queda
// prestado mientras ella viva, y tiene que vivir al menos lo mismo.
fn apuntar_a(c: mut Comprobacion, m: &Mundo, linea: usize, i: usize, nuevos: &list<str>) {
    let nombre = copiar(c.simbolos[i].nombre);
    if esta_entre(nuevos, "<temporal>") {
        error(c, m, linea, $"`{nombre}` apuntaria a un valor temporal, que se libera al acabar esta sentencia: guarda ese valor en una variable y presta de ella");
    }
    let suyo = nivel_de_simbolo(c, i);
    for o en nuevos {
        if o == "<temporal>" || esta_entre(c.simbolos[i].origenes, o) { continue; }
        let d = buscar_simbolo(c, o);
        if !existe(c, d) { continue; }
        if nivel_de_simbolo(c, d) > suyo {
            error(c, m, linea, $"`{nombre}` vive mas que `{o}`: `{o}` muere al cerrar su bloque y `{nombre}` seguiria apuntando a ella. Declara `{o}` fuera del bloque, o haz de `{nombre}` un `str` con `nuevo(...)`");
            continue;
        }
        c.simbolos[i].origenes.anadir(copiar(o));
        c.simbolos[d].prestamos.anadir(copiar(nombre));
    }
    if c.simbolos[i].origen.largo() == 0 && c.simbolos[i].origenes.largo() > 0 {
        c.simbolos[i].origen = copiar(c.simbolos[i].origenes[0]);
    }
}

// ------------------------------------------------------------------
// Literales que no caben
// ------------------------------------------------------------------

fn comprobar_literal(c: mut Comprobacion, m: &Mundo, n: &P.Nodo, destino: view) {
    let clase = n.clase;
    if clase == Clase.Binaria && n.hijos.largo() == 2 {
        let op_b = vista(n.texto);
        // Los numeros escritos son decimales aqui, y con decimales no hay
        // resto ni bits.
        if es_decimal(destino) && largo(I.literal_de(n)) > 0
        && (op_b == "%" || op_b == "&" || op_b == "|"
            || op_b == "^" || op_b == "<<" || op_b == ">>") {
            if op_b == "%" {
                error(c, m, n.linea, "`%` es el resto de una division entera; con decimales no tiene un significado unico");
            } else {
                error(c, m, n.linea, $"`{op_b}` trabaja sobre los bits de un entero, recibio `{destino}` y `{destino}`");
            }
            return;
        }
        comprobar_literal(c, m, n.hijos[0], destino);
        let op = vista(n.texto);
        if op == "<<" || op == ">>" {
            comprobar_literal(c, m, n.hijos[1], "usize");
        } else {
            comprobar_literal(c, m, n.hijos[1], destino);
        }
        return;
    }
    // Cada rama que sea un numero escrito tiene que caber.
    if clase == Clase.SiExpr && n.hijos.largo() == 3 {
        comprobar_literal(c, m, n.hijos[1], destino);
        comprobar_literal(c, m, n.hijos[2], destino);
        return;
    }
    var negativo = false;
    var lit = copiar(n);
    if clase == Clase.Unaria && n.texto == "-" && n.hijos.largo() == 1 {
        let hc = n.hijos[0].clase;
        if hc == Clase.Entero || hc == Clase.Decimal {
            negativo = true;
            lit = copiar(n.hijos[0]);
        }
    }
    var signo = vacio();
    if negativo { signo = nuevo("-"); }
    if lit.clase == Clase.Entero {
        let valor = G.sin_ceros_izquierda(lit.texto);
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
    if lit.clase == Clase.Decimal && es_decimal(destino) {
        if !G.cabe_literal_decimal(lit.texto, destino) {
            error(c, m, n.linea, $"el literal `{signo}{lit.texto}` no cabe en `{destino}` como numero finito");
        }
    }
}

// ------------------------------------------------------------------
// Genericas: que tipos pone cada llamada
// ------------------------------------------------------------------

fn es_param_de_tipo(sueltos: &list<str>, t: view) -> bool { return esta_entre(sueltos, t); }

// `list<T>` contra `list<str>` liga `T` a `str`. Falso si contradice lo que
// ya estaba ligado.
fn unificar_tipo(patron: view, dado: view, sueltos: &list<str>,
    lig: mut map<str, str>) -> bool {
    if patron.largo() == 0 || dado.largo() == 0 { return true; }
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
    if T.es_referencia_mutable(patron) {
        return T.es_referencia_mutable(dado)
        && unificar_tipo(T.apuntado(patron), T.apuntado(dado),
            sueltos, lig);
    }
    if T.es_referencia(patron) {
        return T.es_referencia(dado)
        && unificar_tipo(T.apuntado(patron), T.apuntado(dado),
            sueltos, lig);
    }
    if T.es_lista(patron) && T.es_lista(dado) {
        let a = T.elemento(patron);
        let b = T.elemento(dado);
        return unificar_tipo(a, b, sueltos, lig);
    }
    if T.es_mapa(patron) && T.es_mapa(dado) {
        let a = T.partes(patron);
        let b = T.partes(dado);
        if a.largo() != 2 || b.largo() != 2 { return false; }
        return unificar_tipo(a[0], b[0], sueltos, lig)
        && unificar_tipo(a[1], b[1], sueltos, lig);
    }
    if T.es_arreglo(patron) && T.es_arreglo(dado) {
        let na = T.cuantos_del_arreglo(patron);
        let nb = T.cuantos_del_arreglo(dado);
        let ea = T.elemento(patron);
        let eb = T.elemento(dado);
        return igual(na, nb) && unificar_tipo(ea, eb, sueltos, lig);
    }
    // `Par<A, B>` contra `Par<usize, str>`.
    if T.es_aplicacion(patron) && T.es_aplicacion(dado) {
        let ba = T.base_de_aplicacion(patron);
        let bb = T.base_de_aplicacion(dado);
        if !igual(ba, bb) { return false; }
        let xs = T.partes(patron);
        let ys = T.partes(dado);
        if xs.largo() != ys.largo() { return false; }
        var i = 0;
        while i < xs.largo() {
            if !unificar_tipo(xs[i], ys[i], sueltos, lig) { return false; }
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
    while i < f.params.largo() {
        if i > 0 { t.empujar(", "); }
        if f.params[i].mutable { t.empujar("&mut "); }
        else if f.params[i].compartido { t.empujar("&"); }
        t.empujar(f.params[i].tipo);
        i = i + 1;
    }
    t.empujar(")");
    if f.retorno.largo() > 0 && f.retorno != "()" {
        t.empujar(" -> ");
        t.empujar(f.retorno);
    }
    return t;
}

// La funcion de un nombre tal como lo ve este modulo.
fn funcion_llamada(m: &Mundo, tipos: &I.Contexto, nombre: view) -> usize {
    let dentro = resolver_nombre(tipos, nombre);
    return buscar_funcion(m, dentro) sino m.funciones.largo();
}

fn tipo_probable(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let clase = n.clase;
    match clase {
        Clase.Variable -> {
            let i = buscar_simbolo(c, n.texto);
            if existe(c, i) { return T.leer_tipo(c.simbolos[i].tipo); }
            let k = funcion_llamada(m, tipos, n.texto);
            if k < m.funciones.largo() && !tiene_sueltos(m.funciones[k]) && !m.funciones[k].falible {
                return tipo_de_escrito(firma_de(m.funciones[k]));
            }
            return T.ninguno();
        }
        Clase.Cierre -> { return cierre(c, m, tipos, n); }
        Clase.Cadena -> { return T.leer_tipo("view"); }
        Clase.Entero -> { return T.leer_tipo("usize"); }
        Clase.Decimal -> { return T.leer_tipo("f64"); }
        Clase.Booleano -> { return T.leer_tipo("bool"); }
        Clase.Interpolada -> { return T.leer_tipo("str"); }
        Clase.LiteralStruct -> { return tipo_de_escrito(I.sin_modulo(n.texto)); }
        Clase.Unaria -> {
            if n.hijos.largo() > 0 {
                if n.texto == "!" { return T.leer_tipo("bool"); }
                if n.texto == "-" && I.literal_de(n.hijos[0]) == "entero" {
                    return T.leer_tipo("i64");
                }
                let t = tipo_probable(c, m, tipos, n.hijos[0]);
                if es_literal_entero(t) { return T.leer_tipo("i64"); }
                return t;
            }
        }
        Clase.Conversion -> {
            let destino = vista(n.texto);
            if empieza_con(destino, "?") { return tipo_de_escrito(rebanar(destino, 1, destino.largo())); }
            return tipo_de_escrito(destino);
        }
        // Una rama que es un numero escrito toma el tipo de la otra.
        Clase.SiExpr -> {
            if n.hijos.largo() == 3 {
                let lit_a = I.literal_de(n.hijos[1]);
                let lit_b = I.literal_de(n.hijos[2]);
                if lit_a.largo() > 0 && lit_b.largo() == 0 {
                    return tipo_probable(c, m, tipos, n.hijos[2]);
                }
                if lit_a.largo() > 0 {
                    if lit_a == "decimal" || lit_b == "decimal" { return T.leer_tipo("f64"); }
                    return T.leer_tipo("usize");
                }
                return tipo_probable(c, m, tipos, n.hijos[1]);
            }
        }
        Clase.Binaria -> {
            if n.hijos.largo() == 2 {
                let op = vista(n.texto);
                if op == "&&" || op == "||" || op == "==" || op == "!="
                || op == "<" || op == "<=" || op == ">" || op == ">=" {
                    return T.leer_tipo("bool");
                }
                // Un numero escrito no decide nada por su cuenta: toma el tipo del
                // otro lado.
                let lit_i = I.literal_de(n.hijos[0]);
                let lit_d = I.literal_de(n.hijos[1]);
                if lit_i.largo() > 0 && lit_d.largo() > 0 {
                    if lit_i == "decimal" || lit_d == "decimal" { return T.leer_tipo("f64"); }
                    return T.leer_tipo("usize");
                }
                if lit_i.largo() > 0 { return tipo_probable(c, m, tipos, n.hijos[1]); }
                let a = tipo_probable(c, m, tipos, n.hijos[0]);
                let b = tipo_probable(c, m, tipos, n.hijos[1]);
                if !T.conocido(a) || es_literal_entero(a) {
                    if es_literal_entero(b) { return T.leer_tipo("usize"); }
                    return b;
                }
                return a;
            }
        }
        Clase.Llamada -> {
            let nombre = I.sin_modulo(n.texto);
            // Las que devuelven el tipo de lo que reciben, como al comprobar.
            if (nombre == "absoluto" || nombre == "raiz" || nombre == "piso"
                || nombre == "techo" || nombre == "redondear") && n.hijos.largo() == 1 {
                let lit = I.literal_de(n.hijos[0]);
                if lit.largo() > 0 {
                    if lit == "entero" && nombre == "absoluto" { return T.leer_tipo("i64"); }
                    return T.leer_tipo("f64");
                }
                let t_a = tipo_probable(c, m, tipos, n.hijos[0]);
                return tipo_de_escrito(T.apuntado_si(T.escribir_tipo(t_a)));
            }
            let fi = firma_interna(nombre);
            if fi.existe { return tipo_de_escrito(fi.retorno); }
            let k = funcion_llamada(m, tipos, n.texto);
            if k >= m.funciones.largo() { return T.ninguno(); }
            if !tiene_sueltos(m.funciones[k]) { return tipo_de_escrito(m.funciones[k].retorno); }
            // Para saber que devuelve hay que elegir la copia, en silencio.
            let antes = c.errores.largo();
            let inst = instanciar(c, m, tipos, n, k);
            if !inst.ok || c.errores.largo() > antes {
                truncar_errores(c, antes);
                return T.ninguno();
            }
            return tipo_de_escrito(inst.retorno);
        }
        _ -> {
            if (clase == Clase.Try || clase == Clase.Sino) && n.hijos.largo() > 0 {
                return tipo_probable(c, m, tipos, n.hijos[0]);
            }
            if clase == Clase.Campo || clase == Clase.Indice {
                return tipo_de_lugar(c, m, tipos, n);
            }
        }
    }
    return T.ninguno();
}

fn truncar_errores(c: mut Comprobacion, cuantos: usize) {
    var quedan: list<str> = [];
    var i = 0;
    while i < cuantos && i < c.errores.largo() {
        quedan.anadir(copiar(c.errores[i]));
        i = i + 1;
    }
    c.errores = quedan;
}

// Una generica con los tipos que pone una llamada.
struct Instancia {
    ok: bool,
    params: list<Param>,
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
    var lig: map<str, str> = [];
    let fallo = Instancia { ok: false, params: [], retorno: vacio(), ligadas: vacio(),
        clave: vacio(), copia: vacio() };
    if n.hijos.largo() == f.params.largo() {
        var i = 0;
        while i < f.params.largo() {
            var dado = tipo_probable(c, m, tipos, n.hijos[i]);
            if T.es_referencia(T.escribir_tipo(dado)) { dado = tipo_de_escrito(T.apuntado(T.escribir_tipo(dado))); }
            var antes: map<str, str> = [];
            for x en claves(lig) {
                if x == "\t" { continue; }
                let v = obtener(lig, x) sino "";
                poner(antes, vista(x), nuevo(v));
            }
            let pt = vista(f.params[i].tipo);
            if !unificar_tipo(pt, T.escribir_tipo(dado), sueltos, lig) {
                var choca = vacio();
                for tp en sueltos {
                    if choca.largo() == 0 && tiene(antes, tp) && contiene(pt, tp) {
                        choca = copiar(tp);
                    }
                }
                let pn = vista(f.params[i].nombre);
                if choca.largo() > 0 {
                    let ya = obtener(antes, choca) sino "";
                    error(c, m, n.linea, $"`{choca}` en `{nombre}` ya quedo en `{ya}` por un argumento anterior, y `{pn}` pide `{T.escribir_tipo(dado)}`. Un mismo parametro de tipo es un solo tipo en toda la llamada");
                } else {
                    let visto = texto_o_none(T.escribir_tipo(dado));
                    error(c, m, n.linea, $"`{pn}` de `{nombre}` es `{pt}` y recibio `{visto}`");
                }
                return fallo;
            }
            i = i + 1;
        }
    }
    var faltan: list<str> = [];
    for tp en sueltos {
        if !tiene(lig, tp) { faltan.anadir(copiar(tp)); }
    }
    if faltan.largo() > 0 {
        let cuales = con_comas(faltan);
        error(c, m, n.linea, $"no se puede deducir {cuales} en la llamada a `{nombre}`: los argumentos no lo dicen. Guarda el argumento en una variable con su tipo escrito y pasa esa");
        return fallo;
    }
    for r en f.restricciones {
        var corte = 0;
        while corte < r.largo() && byte(r, corte) != 61 { corte = corte + 1; }
        let tp = rebanar(r, 0, corte);
        let cual = rebanar(r, corte + 1, r.largo());
        let validos = restriccion_admite(cual);
        let puesto = obtener(lig, tp) sino "";
        if puesto.largo() > 0 && !esta_entre(validos, puesto) {
            let lista_v = con_comas(validos);
            error(c, m, n.linea, $"`{nombre}` pide que `{tp}` sea `{cual}`, y aqui `{tp}` es `{puesto}`. `{cual}` son: {lista_v}");
            return fallo;
        }
    }
    var ps: list<Param> = [];
    for p en f.params {
        anadir(ps, Param { nombre: copiar(p.nombre), tipo: T.sustituir(p.tipo, lig),
                mutable: p.mutable, compartido: p.compartido });
    }
    var ligadas = vacio();
    let orden = obtener(lig, "\t") sino "";
    var desde = 0;
    var i = 0;
    while i < orden.largo() {
        if byte(orden, i) == 9 {
            let tp = rebanar(orden, desde, i);
            let puesto = obtener(lig, tp) sino "";
            if ligadas.largo() > 0 { ligadas.empujar(", "); }
            let pieza = $"{tp} = {puesto}";
            ligadas.empujar(pieza);
            desde = i + 1;
        }
        i = i + 1;
    }
    var clave = copiar(f.nombre);
    var copia = copiar(f.nombre);
    copia.empujar("__");
    var primero_t = true;
    for tp en sueltos {
        clave.empujar("|");
        clave.empujar(obtener(lig, tp) sino "");
        let puesto = nuevo(obtener(lig, tp) sino "");
        let resuelto = I.nombre_resuelto(puesto);
        if !primero_t { copia.empujar("_"); }
        primero_t = false;
        copia.empujar(T.sanear(resuelto));
    }
    let hecha = esta_entre(m.copias, clave);
    let inst = Instancia { ok: true, params: ps, retorno: T.sustituir(f.retorno, lig),
        ligadas: ligadas, clave: copiar(clave), copia: copiar(copia) };
    if !hecha {
        m.copias.anadir(copiar(clave));
        comprobar_copia(c, m, n, k, inst, lig, false);
        m.orden_copias.anadir(copiar(inst.copia));
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
    let total = m.funciones.largo();
    var e = 0;
    while e < total {
        let f = copiar(m.funciones[e]);
        let k = e;
        e = e + 1;
        if f.de_cierre || f.externa || !tiene_sueltos(f) || f.restricciones.largo() == 0 {
            continue;
        }
        var restr: map<str, str> = [];
        for r en f.restricciones {
            var corte = 0;
            while corte < r.largo() && byte(r, corte) != 61 { corte = corte + 1; }
            poner(restr, rebanar(r, 0, corte), nuevo(rebanar(r, corte + 1, r.largo())));
        }
        let prefijo = $"{f.nombre}|";
        var probadas: list<str> = [];
        var bases: list<list<str>> = [];
        for cl en m.copias {
            if empieza_con(cl, prefijo) {
                probadas.anadir(copiar(cl));
                bases.anadir(partir_por_barra(rebanar(cl, prefijo.largo(), cl.largo())));
            }
        }
        if bases.largo() == 0 {
            var todos = true;
            for tp en f.tipo_params {
                if !tiene(restr, tp) { todos = false; }
            }
            if todos {
                let ninguna: list<str> = [];
                bases.anadir(ninguna);
            }
        }
        for base en bases {
            var opciones: list<list<str>> = [];
            var i = 0;
            var alguna_vacia = false;
            while i < f.tipo_params.largo() {
                let tp = vista(f.tipo_params[i]);
                if tiene(restr, tp) {
                    let cual = obtener(restr, tp) sino "";
                    opciones.anadir(restriccion_admite(cual));
                } else {
                    var una: list<str> = [];
                    if i < base.largo() { una.anadir(copiar(base[i])); }
                    if una.largo() == 0 { alguna_vacia = true; }
                    opciones.anadir(una);
                }
                i = i + 1;
            }
            if alguna_vacia || opciones.largo() == 0 { continue; }
            // Todas las combinaciones, la ultima posicion la que mas cambia.
            var cuenta: list<usize> = [];
            for _o en opciones { cuenta.anadir(0); }
            var sigue = true;
            while sigue {
                var juego: list<str> = [];
                var clave = copiar(f.nombre);
                var j = 0;
                while j < opciones.largo() {
                    let t = copiar(opciones[j][cuenta[j]]);
                    clave.empujar("|");
                    clave.empujar(t);
                    juego.anadir(t);
                    j = j + 1;
                }
                if !esta_entre(probadas, clave) {
                    probadas.anadir(copiar(clave));
                    if firma_valida(m, f, juego) { probar_juego(c, m, k, juego); }
                }
                // La siguiente.
                var p = opciones.largo();
                sigue = false;
                while p > 0 && !sigue {
                    p = p - 1;
                    if cuenta[p] + 1 < opciones[p].largo() {
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

fn partir_por_barra(t: view) -> list<str> {
    var salida: list<str> = [];
    var desde = 0;
    var i = 0;
    while i <= t.largo() {
        if i == t.largo() || byte(t, i) == 124 {
            salida.anadir(nuevo(rebanar(t, desde, i)));
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

// Las ligaduras de `f` para un juego de tipos, en el orden de la plantilla.
fn ligaduras_de_juego(f: &Funcion, juego: &list<str>) -> map<str, str> {
    var lig: map<str, str> = [];
    var orden = vacio();
    var i = 0;
    while i < f.tipo_params.largo() && i < juego.largo() {
        poner(lig, vista(f.tipo_params[i]), copiar(juego[i]));
        orden.empujar(f.tipo_params[i]);
        orden.empujar("\t");
        i = i + 1;
    }
    poner(lig, "\t", orden);
    return lig;
}

// Si con estos tipos la firma tiene sentido. Un `T = view` sobre un
// `&list<T>` no lo tiene: nadie podria llamarla asi, y el cuerpo no tiene
// que valer para lo que no se puede escribir. Tampoco lo tiene un tipo que
// lleve una `view` dentro por culpa de `T` —un `Caja<view>`, un
// `Arbol<view>`—: ahi el cuerpo recibe algo que no es suyo y `copiar` no
// vale, asi que no se le puede exigir que compile para esa instanciacion.
// Un `view` escrito a mano, sin `T` de por medio, no invalida el juego.
fn firma_valida(m: &Mundo, f: &Funcion, juego: &list<str>) -> bool {
    let lig = ligaduras_de_juego(f, juego);
    for p en f.params {
        let t = T.sustituir(p.tipo, lig);
        if !almacenable(m, t) || (prestado(p) && t == "view") { return false; }
        if !igual(p.tipo, t) && lleva_vista(m, t) { return false; }
    }
    let r = T.sustituir(f.retorno, lig);
    if r.largo() > 0 && !igual(f.retorno, r) && lleva_vista(m, r) { return false; }
    return r.largo() == 0 || r == "()" || almacenable(m, r);
}

// Comprueba la copia de `k` para este juego sin quedarsela: lo que cambie
// al hacerla se deshace, y solo quedan los errores.
fn probar_juego(c: mut Comprobacion, m: mut Mundo, k: usize, juego: &list<str>) {
    let f = copiar(m.funciones[k]);
    let lig = ligaduras_de_juego(f, juego);
    var ps: list<Param> = [];
    for p en f.params {
        anadir(ps, Param { nombre: copiar(p.nombre), tipo: T.sustituir(p.tipo, lig),
                mutable: p.mutable, compartido: p.compartido });
    }
    var ligadas = vacio();
    var clave = copiar(f.nombre);
    var copia = copiar(f.nombre);
    copia.empujar("__");
    var i = 0;
    while i < f.tipo_params.largo() && i < juego.largo() {
        if i > 0 {
            ligadas.empujar(", ");
            copia.empujar("_");
        }
        ligadas.empujar($"{f.tipo_params[i]} = {juego[i]}");
        clave.empujar("|");
        clave.empujar(juego[i]);
        let resuelto = I.nombre_resuelto(juego[i]);
        copia.empujar(T.sanear(resuelto));
        i = i + 1;
    }
    let inst = Instancia { ok: true, params: ps, retorno: T.sustituir(f.retorno, lig),
        ligadas: ligadas, clave: copiar(clave), copia: copia };
    let c_antes = copiar(c);
    // Los mapas no se pueden recortar: se copian. Las listas solo se anaden
    // al comprobar, asi que basta recordar su largo y truncarlas.
    let indice_antes = copiar(m.indice);
    let st_tipos_antes = copiar(m.st_tipos);
    let st_nombres_antes = copiar(m.st_nombres);
    let st_params_antes = copiar(m.st_params);
    let en_variantes_antes = copiar(m.en_variantes);
    let en_formas_antes = copiar(m.en_formas);
    let bonitos_antes = copiar(m.bonitos);
    let numeracion_antes = copiar(m.numeracion);
    let n_cierres_antes = m.n_cierres;
    let n_funciones = m.funciones.largo();
    let n_copias = m.copias.largo();
    let n_orden_copias = m.orden_copias.largo();
    let n_orden_structs = m.orden_structs.largo();
    let n_tipo_de_struct = m.tipo_de_struct.largo();
    let n_cierres = m.cierres.largo();
    let n_cierres_mod = m.cierres_mod.largo();
    let n_cierres_mut = m.cierres_mut.largo();
    let antes = c.errores.largo();
    m.copias.anadir(copiar(clave));
    let nodo = copiar(m.arboles[f.modulo].hijos[f.posicion]);
    let archivo_antes = copiar(c.archivo);
    c.archivo = copiar(f.archivo);
    comprobar_copia(c, m, nodo, k, inst, lig, true);
    var nuevos: list<str> = [];
    var q = antes;
    while q < c.errores.largo() {
        nuevos.anadir(copiar(c.errores[q]));
        q = q + 1;
    }
    c = c_antes;
    c.archivo = archivo_antes;
    truncar(m.funciones, n_funciones);
    m.indice = copiar(indice_antes);
    m.st_tipos = copiar(st_tipos_antes);
    m.st_nombres = copiar(st_nombres_antes);
    m.st_params = copiar(st_params_antes);
    m.en_variantes = copiar(en_variantes_antes);
    m.en_formas = copiar(en_formas_antes);
    m.bonitos = copiar(bonitos_antes);
    truncar(m.cierres, n_cierres);
    truncar(m.cierres_mod, n_cierres_mod);
    m.n_cierres = n_cierres_antes;
    truncar(m.cierres_mut, n_cierres_mut);
    m.numeracion = copiar(numeracion_antes);
    truncar(m.copias, n_copias);
    truncar(m.orden_copias, n_orden_copias);
    truncar(m.orden_structs, n_orden_structs);
    truncar(m.tipo_de_struct, n_tipo_de_struct);
    for x en nuevos {
        if !esta_entre(c.errores, x) { c.errores.anadir(copiar(x)); }
    }
}

// Los tipos puestos en el arbol de una copia: en los parametros, el
// retorno, las declaraciones y las conversiones.
fn sustituir_en_arbol(n: mut P.Nodo, lig: &map<str, str>) {
    let clase = n.clase;
    if clase == Clase.Param || clase == Clase.Declaracion {
        let t = copiar(n.texto);
        var j = 0;
        while j < t.largo() && byte(t, j) != 58 { j = j + 1; }
        if j < t.largo() {
            let tipo = T.sustituir(rebanar(t, j + 1, t.largo()), lig);
            n.texto = $"{rebanar(vista(t), 0, j + 1)}{tipo}";
        }
    } else if clase == Clase.RetornoTipo || clase == Clase.Conversion {
        let t = copiar(n.texto);
        n.texto = T.sustituir(t, lig);
    }
    var i = 0;
    while i < n.hijos.largo() {
        sustituir_en_arbol(n.hijos[i], lig);
        i = i + 1;
    }
}

// El cuerpo de una generica se comprueba con los tipos puestos, en mitad de
// quien la llama, como otra funcion entera.
fn comprobar_copia(c: mut Comprobacion, m: mut Mundo, n: &P.Nodo, k: usize,
    inst: &Instancia, lig: &map<str, str>, sin_llamada: bool) {
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
    registrar_tipo(m, f.retorno);
    for p en copiar(f.params) { registrar_tipo(m, p.tipo); }
    for h en nodo.hijos {
        if h.clase == Clase.Bloque { registrar_en_nodo(m, h); }
    }
    let kc = m.funciones.largo();
    m.funciones.anadir(f);
    let tipos = copiar(m.contextos[modulo]);
    let simbolos = copiar(c.simbolos);
    let inicios = copiar(c.inicios);
    let retorno = copiar(c.retorno);
    let falible = c.falible;
    let archivo = copiar(c.archivo);
    let nombre = copiar(m.funciones[k].nombre);
    let ligadas = legible(m, inst.ligadas);
    if sin_llamada {
        c.instanciando.anadir($"al comprobar `{nombre}` con {ligadas}: la restriccion lo admite, asi que el cuerpo tiene que valer tambien asi");
    } else {
        c.instanciando.anadir($"al usar `{nombre}` con {ligadas}, desde {archivo}:{n.linea}");
    }
    c.plantillas.anadir(k);
    let dueno = copiar(c.dueno);
    let modulo_antes = c.modulo;
    c.simbolos = [];
    c.inicios = [];
    c.archivo = copiar(m.modulos[modulo]);
    c.modulo = modulo;
    comprobar_funcion(c, m, tipos, kc, nodo, inst.clave);
    c.dueno = dueno;
    c.modulo = modulo_antes;
    var quedan: list<str> = [];
    var q = 0;
    while q + 1 < c.instanciando.largo() {
        quedan.anadir(copiar(c.instanciando[q]));
        q = q + 1;
    }
    c.instanciando = quedan;
    var otras: list<usize> = [];
    var q2 = 0;
    while q2 + 1 < c.plantillas.largo() {
        otras.anadir(c.plantillas[q2]);
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
    if t.largo() == 0 { return nuevo("None"); }
    return nuevo(t);
}

// Escribir en `x` no es leer `x`: la variable suelta se resuelve sin usarla.
fn tipo_de_lugar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    if n.clase == Clase.Variable {
        let i = buscar_simbolo(c, n.texto);
        if existe(c, i) { return T.leer_tipo(c.simbolos[i].tipo); }
        return T.ninguno();
    }
    return comprobar_expresion(c, m, tipos, n, "", false);
}

// ------------------------------------------------------------------
// Expresiones
// ------------------------------------------------------------------

// El tipo de `n`, comprobandola. Queda anotado para el generador, que lo lee
// en vez de deducirlo otra vez por su cuenta, que es como se equivocaba.
fn comprobar_expresion(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    destino: view, mover_variables: bool) -> T.Tipo {
    let t = comprobar_expresion_sin_anotar(c, m, tipos, n, destino, mover_variables);
    anotar(c, m, n, t);
    let destino_p = sin_prestamo(destino);
    if (es_literal_entero(t) || es_literal_decimal_t(t))
    && es_numerico(destino_p) {
        fijar_literal(c, m, n, destino_p);
    } else if es_literal_entero(t) && n.clase != Clase.Entero && n.id > 0 {
        // Una cuenta que todavia no sabe su tipo: se lo dira quien la use, o
        // al acabar la sentencia sera `usize`.
        c.escritas.anadir(copiar(n));
        c.escritas_duenos.anadir(copiar(c.dueno));
    }
    return t;
}

fn clave_anotada(c: &Comprobacion, n: &P.Nodo) -> str {
    return $"{c.dueno}#{n.id}";
}

fn anotar(c: &Comprobacion, m: mut Mundo, n: &P.Nodo, t: &T.Tipo) {
    if n.id == 0 || c.modulo >= m.anotados.largo() { return; }
    let clave = clave_anotada(c, n);
    poner(m.anotados[c.modulo], vista(clave), copiar(t));
}

// Aqui el comprobador decidio que un sitio se lee y no se mueve: se graba por
// `dueno#id` —la clave de los anotados— para que el generador lo consulte en
// vez de deducirlo por su cuenta.
fn grabar_lectura(c: &Comprobacion, m: mut Mundo, n: &P.Nodo) {
    if n.id == 0 { return; }
    m.lecturas.anadir(clave_anotada(c, n));
}

// La otra cara: aqui el comprobador decidio mover, y se graba en el mismo
// canal y con la misma clave. Quien lo consuma sabe asi, nodo a nodo, si lo
// que hay es una entrega o una lectura, sin volver a mirar la forma.
fn grabar_movimiento(c: &Comprobacion, m: mut Mundo, n: &P.Nodo) {
    if n.id == 0 { return; }
    m.movidas.anadir(clave_anotada(c, n));
}

// Y el tercer valor: aqui el comprobador decidio PRESTAR —`&T` o `mut T`—, que
// no es leer ni mover. Se graba en el mismo canal y con la misma clave, para
// que quien lo consuma pida la direccion en vez del valor sin rehacer la
// decision por la forma ni por la firma.
fn grabar_prestamo(c: &Comprobacion, m: mut Mundo, n: &P.Nodo) {
    if n.id == 0 { return; }
    m.prestamos.anadir(clave_anotada(c, n));
}

// El prestamo de un argumento. Por su nodo cuando el programa lo escribio; y
// cuando lo sintetizo el compilador —el entorno de una clausura, que no tiene
// nodo propio— bajo el id de la llamada, con una marca que lo distingue de
// cuando esa misma llamada es, a su vez, argumento prestado de otra. La marca
// es la misma que consulta el generador.
fn grabar_prestamo_de(c: &Comprobacion, m: mut Mundo, arg: &P.Nodo,
    llamada: &P.Nodo) {
    if arg.id != 0 {
        grabar_prestamo(c, m, arg);
        return;
    }
    if llamada.id == 0 { return; }
    var clave = clave_anotada(c, llamada);
    clave.empujar("#entorno");
    m.prestamos.anadir(clave);
}

// Un numero escrito ya sabe su tipo: se lo dice el otro lado de la operacion,
// o el sitio donde va. Se anota en el y en todo lo que es numero escrito por
// debajo; un desplazamiento cuenta en `usize`.
// Y si es una cuenta de enteros, se hace ya.
fn fijar_literal(c: mut Comprobacion, m: mut Mundo, n: &P.Nodo, tipo: view) {
    if c.modulo >= m.anotados.largo() { return; }
    var antes = nuevo(literal());
    if n.id > 0 {
        let clave = clave_anotada(c, n);
        antes = T.escribir_de_mapa(m.anotados[c.modulo], clave) sino T.escribir_tipo(T.marcador(literal()));
    }
    fijar_literal_sin_contar(c, m, n, tipo);
    if igual(antes, literal()) && es_tipo_entero(tipo)
    && I.literal_de(n) == "entero" && n.id > 0 {
        contar_escrita(c, m, n, tipo);
    }
}

fn fijar_literal_sin_contar(c: &Comprobacion, m: mut Mundo, n: &P.Nodo, tipo: view) {
    if c.modulo >= m.anotados.largo() { return; }
    if n.id > 0 {
        let clave = clave_anotada(c, n);
        let actual = T.escribir_de_mapa(m.anotados[c.modulo], clave) sino T.escribir_tipo(T.marcador(literal()));
        if !igual(actual, literal()) && !igual(actual, literal_decimal()) { return; }
    }
    if largo(I.literal_de(n)) == 0 { return; }
    anotar(c, m, n, tipo_de_escrito(tipo));
    let clase = n.clase;
    if clase == Clase.Binaria && n.hijos.largo() == 2 {
        fijar_literal_sin_contar(c, m, n.hijos[0], tipo);
        if n.texto == "<<" || n.texto == ">>" {
            fijar_literal_sin_contar(c, m, n.hijos[1], "usize");
        } else {
            fijar_literal_sin_contar(c, m, n.hijos[1], tipo);
        }
    } else if clase == Clase.Unaria && n.hijos.largo() == 1 {
        fijar_literal_sin_contar(c, m, n.hijos[0], tipo);
    } else if clase == Clase.SiExpr && n.hijos.largo() == 3 {
        fijar_literal_sin_contar(c, m, n.hijos[1], tipo);
        fijar_literal_sin_contar(c, m, n.hijos[2], tipo);
    }
}

// ------------------------------------------------------------------
// Cuentas de numeros escritos, hechas al compilar
// ------------------------------------------------------------------
//
// `let x: u8 = 200 + 100;` no es un programa que aborte: es un programa mal
// escrito. Una cuenta hecha solo de numeros escritos se hace aqui, en el tipo
// que le toca, y lo que en marcha pararia el programa —desbordarse, dividir
// por cero, desplazar el ancho o mas— para aqui, con su linea.
//
// Sin enteros de mas de 64 bits, un valor es su signo y su magnitud: cabe
// todo `u64` y todo `i64`, y cada operacion mira si se sale antes de salirse.

struct Escrito {
    // False si depende de algo que solo se sabe en marcha: la condicion de
    // un `if`.
    sabido: bool,
    negativo: bool,
    magnitud: u64,
    // La cuenta ya paro, con su error dicho: no se sigue.
    parada: bool,
}

fn escrito_sin_saber() -> Escrito {
    return Escrito { sabido: false, negativo: false, magnitud: 0, parada: false };
}

fn escrito_parado() -> Escrito {
    return Escrito { sabido: false, negativo: false, magnitud: 0, parada: true };
}

fn valor_sabido(negativo: bool, magnitud: u64) -> Escrito {
    // El cero no tiene signo.
    return Escrito { sabido: true, negativo: negativo && magnitud > 0,
        magnitud: magnitud, parada: false };
}

fn texto_escrito(v: &Escrito) -> str {
    if v.negativo { return $"-{v.magnitud}"; }
    return $"{v.magnitud}";
}

fn bits_de_entero(t: view) -> u64 {
    if t == "u8" || t == "i8" { return 8; }
    if t == "u16" || t == "i16" { return 16; }
    if t == "u32" || t == "i32" { return 32; }
    return 64;
}

fn con_signo(t: view) -> bool { return empieza_con(t, "i"); }

// Si el valor cabe en el tipo.
fn cabe_escrito(v: &Escrito, t: view) -> bool {
    let bits = bits_de_entero(t);
    if !con_signo(t) {
        if v.negativo { return false; }
        if bits == 64 { return true; }
        return v.magnitud <= (1 << bits) - 1;
    }
    let mitad: u64 = 1 << (bits - 1);
    if v.negativo { return v.magnitud <= mitad; }
    return v.magnitud < mitad;
}

// Los bits del valor en complemento a dos, sobre 64.
fn patron_escrito(v: &Escrito) -> u64 {
    if v.negativo { return 0 -? v.magnitud; }
    return v.magnitud;
}

// Los bits de abajo de un patron, leidos como un `t`.
fn desde_patron(p: u64, t: view) -> Escrito {
    let bits = bits_de_entero(t);
    var q = p;
    if bits < 64 { q = p & ((1 << bits) - 1); }
    if con_signo(t) && ((q >> (bits - 1)) & 1) == 1 {
        if bits == 64 { return valor_sabido(true, 0 -? q); }
        return valor_sabido(true, (1 << bits) - q);
    }
    return valor_sabido(false, q);
}

fn sumar_escritos(a: &Escrito, b: &Escrito) -> Escrito {
    if a.negativo == b.negativo {
        let r = a.magnitud +? b.magnitud;
        // Se salio de 64 bits: de cualquier tipo.
        if r < a.magnitud { return escrito_sin_saber(); }
        return valor_sabido(a.negativo, r);
    }
    if a.magnitud >= b.magnitud { return valor_sabido(a.negativo, a.magnitud - b.magnitud); }
    return valor_sabido(b.negativo, b.magnitud - a.magnitud);
}

fn cuenta_parada(c: mut Comprobacion, m: &Mundo, n: &P.Nodo, que: view) -> Escrito {
    error(c, m, n.linea, $"{que}: es una cuenta de numeros escritos, y se hace al compilar");
    return escrito_parado();
}

fn contar_escrita(c: mut Comprobacion, m: mut Mundo, n: &P.Nodo, tipo: view) {
    let _v = valor_escrito(c, m, n, tipo);
}

// Las cuentas de la sentencia que nadie tipo: son `usize`. De fuera adentro,
// que la de fuera hace tambien las suyas.
fn contar_pendientes(c: mut Comprobacion, m: mut Mundo, desde: usize) {
    var k = c.escritas.largo();
    while k > desde {
        k = k - 1;
        let dueno_antes = copiar(c.dueno);
        c.dueno = copiar(c.escritas_duenos[k]);
        let n = copiar(c.escritas[k]);
        let clave = clave_anotada(c, n);
        var actual = nuevo(literal());
        if c.modulo < m.anotados.largo() {
            actual = T.escribir_de_mapa(m.anotados[c.modulo], clave) sino T.escribir_tipo(T.marcador(literal()));
        }
        if igual(actual, literal()) { contar_escrita(c, m, n, "usize"); }
        c.dueno = dueno_antes;
    }
    if c.escritas.largo() == desde { return; }
    var quedan: list<P.Nodo> = [];
    var quedan_d: list<str> = [];
    var j = 0;
    while j < desde {
        quedan.anadir(copiar(c.escritas[j]));
        quedan_d.anadir(copiar(c.escritas_duenos[j]));
        j = j + 1;
    }
    c.escritas = quedan;
    c.escritas_duenos = quedan_d;
}

// El valor de la cuenta. Cada nodo se cuenta una vez.
fn valor_escrito(c: mut Comprobacion, m: mut Mundo, n: &P.Nodo, tipo: view) -> Escrito {
    let clave = clave_anotada(c, n);
    if tiene(c.contadas, clave) { return escrito_sin_saber(); }
    poner(c.contadas, vista(clave), 1);
    let clase = n.clase;
    if clase == Clase.Entero {
        // Uno que no cabe ya tiene su error.
        let digitos = G.sin_ceros_izquierda(vista(n.texto));
        if !G.cabe_literal_entero(digitos, tipo, false) { return escrito_sin_saber(); }
        var v: u64 = 0;
        var i = 0;
        while i < digitos.largo() {
            v = v * 10 + (byte(digitos, i) - 48) como u64;
            i = i + 1;
        }
        return valor_sabido(false, v);
    }
    if clase == Clase.SiExpr && n.hijos.largo() == 3 {
        let a = valor_escrito(c, m, n.hijos[1], tipo);
        if a.parada { return a; }
        let b = valor_escrito(c, m, n.hijos[2], tipo);
        if b.parada { return b; }
        return escrito_sin_saber();
    }
    if clase != Clase.Binaria || n.hijos.largo() != 2 { return escrito_sin_saber(); }
    let op = vista(n.texto);
    let desplaza = op == "<<" || op == ">>";
    let a = valor_escrito(c, m, n.hijos[0], tipo);
    if a.parada { return a; }
    let b = valor_escrito(c, m, n.hijos[1], if desplaza { "usize" } else { tipo });
    if b.parada { return b; }
    if !a.sabido || !b.sabido { return escrito_sin_saber(); }
    let ta = texto_escrito(a);
    let tb = texto_escrito(b);
    let cuenta = $"`{ta} {op} {tb}`";

    if op == "+?" || op == "-?" || op == "*?" {
        let pa = patron_escrito(a);
        let pb = patron_escrito(b);
        var r: u64 = 0;
        if op == "+?" { r = pa +? pb; }
        else if op == "-?" { r = pa -? pb; }
        else { r = pa *? pb; }
        return desde_patron(r, tipo);
    }
    if op == "+" || op == "-" || op == "*" {
        var r = escrito_sin_saber();
        if op == "+" { r = sumar_escritos(a, b); }
        else if op == "-" {
            let menos_b = valor_sabido(!b.negativo, b.magnitud);
            r = sumar_escritos(a, menos_b);
        } else {
            let tope: u64 = 18446744073709551615;
            if a.magnitud == 0 || b.magnitud <= tope / a.magnitud {
                r = valor_sabido(a.negativo != b.negativo, a.magnitud * b.magnitud);
            }
        }
        if !r.sabido || !cabe_escrito(r, tipo) {
            return cuenta_parada(c, m, n, $"{cuenta} no cabe en `{tipo}`");
        }
        return r;
    }
    if op == "/" || op == "%" {
        if b.magnitud == 0 {
            return cuenta_parada(c, m, n, $"{cuenta} divide por cero");
        }
        // Como C: el cociente se trunca hacia cero, y el resto lleva el signo
        // de lo dividido. `MIN / -1` se sale del tipo; `MIN % -1` es 0.
        if op == "%" { return valor_sabido(a.negativo, a.magnitud % b.magnitud); }
        let q = valor_sabido(a.negativo != b.negativo, a.magnitud / b.magnitud);
        if !cabe_escrito(q, tipo) {
            return cuenta_parada(c, m, n, $"{cuenta} no cabe en `{tipo}`");
        }
        return q;
    }
    if op == "&" || op == "|" || op == "^" {
        let pa = patron_escrito(a);
        let pb = patron_escrito(b);
        var r: u64 = 0;
        if op == "&" { r = pa & pb; }
        else if op == "|" { r = pa | pb; }
        else { r = pa ^ pb; }
        return desde_patron(r, tipo);
    }
    if desplaza {
        let bits = bits_de_entero(tipo);
        if b.magnitud >= bits {
            return cuenta_parada(c, m, n, $"{cuenta} desplaza un `{tipo}` {tb} bits, y tiene {bits}");
        }
        if op == "<<" { return desde_patron(patron_escrito(a) << b.magnitud, tipo); }
        if !a.negativo {
            let r = a.magnitud >> b.magnitud;
            return valor_sabido(false, r);
        }
        // Un negativo rellena con unos: redondea hacia abajo.
        let p = (patron_escrito(a) como? i64) >> b.magnitud;
        return desde_patron(p como? u64, tipo);
    }
    return escrito_sin_saber();
}

fn comprobar_expresion_sin_anotar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto,
    n: &P.Nodo, destino: view, mover_variables: bool) -> T.Tipo {
    if es_numerico(destino) { comprobar_literal(c, m, n, destino); }
    let clase = n.clase;
    match clase {
        Clase.Entero -> { return T.marcador(literal()); }
        Clase.Decimal -> { return T.marcador(literal_decimal()); }
        Clase.Cadena -> { return T.leer_tipo("view"); }
        Clase.Booleano -> { return T.leer_tipo("bool"); }
        Clase.Expresion -> {
            if n.hijos.largo() == 1 {
                return comprobar_expresion(c, m, tipos, n.hijos[0], destino, mover_variables);
            }
        }
        Clase.Interpolada -> {
            for x en n.hijos {
                let t = comprobar_expresion(c, m, tipos, x, "", false);
                if !T.conocido(t) { continue; }
                if !se_muestra(T.escribir_tipo(t)) {
                    let limpio = sin_prestamo(T.escribir_tipo(t));
                    let pista = if es_enum(m, limpio) { $": {como_mostrar(m, T.escribir_tipo(t))}" } else { vacio() };
                    error(c, m, n.linea, $"dentro de `{{}}` va un escalar o texto, y `{T.escribir_tipo(t)}` no lo es{pista}");
                }
            }
            return T.leer_tipo("str");
        }
        Clase.Variable -> {
            return variable(c, m, tipos, n, mover_variables, false);
        }
        Clase.Unaria -> { return unaria(c, m, tipos, n, destino); }
        Clase.Cierre -> { return cierre(c, m, tipos, n); }
        Clase.SiExpr -> { return si_expr(c, m, tipos, n, destino, mover_variables); }
        Clase.EnumLit -> { return enum_lit(c, m, tipos, n); }
        Clase.Match -> { return comprobar_match(c, m, tipos, n, destino, mover_variables); }
        Clase.Conversion -> { return comprobar_conversion(c, m, tipos, n); }
        Clase.Try -> {
            if !c.falible {
                error(c, m, n.linea, "`try` deja subir la falla al que llamo, pero esta funcion no esta declarada con `!`");
            }
            if c.en_condicion_bucle > 0 {
                error(c, m, n.linea, "`try` no puede ir en la condicion de un `while`: se evaluaria una sola vez");
            }
            return desenvolver(c, m, tipos, n, n.hijos[0], "try");
        }
        Clase.Sino -> {
            if c.en_condicion_bucle > 0 {
                error(c, m, n.linea, "`sino` no puede ir en la condicion de un `while`: se evaluaria una sola vez");
            }
            let t = desenvolver(c, m, tipos, n, n.hijos[0], "sino");
            let alt = comprobar_expresion(c, m, tipos, n.hijos[1], T.escribir_tipo(t), true);
            if T.conocido(t) && T.es_referencia(T.escribir_tipo(t)) {
                error(c, m, n.linea, $"`sino` no vale aqui: la llamada devuelve un prestamo (`{T.escribir_tipo(t)}`) y no hay nada que prestar cuando falla. Usa `try`, o pregunta antes con `tiene(...)`");
            } else if T.conocido(t) && T.conocido(alt) && !encaja(T.escribir_tipo(t), T.escribir_tipo(alt)) {
                error(c, m, n.linea, $"la llamada da `{T.escribir_tipo(t)}` y el valor de despues de `sino` es `{T.escribir_tipo(alt)}`");
            }
            return t;
        }
        Clase.Campo -> { return campo(c, m, tipos, n, mover_variables); }
        Clase.Indice -> { return indice(c, m, tipos, n, mover_variables); }
        Clase.LiteralStruct -> { return literal_struct(c, m, tipos, n, destino); }
        Clase.LiteralLista -> { return literal_arreglo(c, m, tipos, n, destino); }
        Clase.Binaria -> { return binaria(c, m, tipos, n); }
        Clase.Llamada -> { return llamada(c, m, tipos, n, false, destino); }
        Clase.Rango -> { return rango(c, m, tipos, n); }
        _ -> { }
    }
    return T.ninguno();
}

// `a..b`, lo que recorre un `for`: los dos extremos son el mismo entero, y
// un numero escrito toma el tipo del otro, o `usize` si los dos lo son.
fn rango(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    if n.hijos.largo() != 2 { return T.ninguno(); }
    let crudo_a = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let crudo_b = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    if !T.conocido(crudo_a) || !T.conocido(crudo_b) { return T.ninguno(); }
    var a = sin_prestamo(T.escribir_tipo(crudo_a));
    var b = sin_prestamo(T.escribir_tipo(crudo_b));
    if igual(a, literal()) && igual(b, literal()) {
        a = nuevo("usize");
        b = nuevo("usize");
    }
    if igual(a, literal()) && es_tipo_entero(b) { a = copiar(b); }
    if igual(b, literal()) && es_tipo_entero(a) { b = copiar(a); }
    if !es_tipo_entero(a) || !es_tipo_entero(b) {
        let de = extremo_dicho(T.escribir_tipo(crudo_a));
        let a_ = extremo_dicho(T.escribir_tipo(crudo_b));
        error(c, m, n.linea, $"un rango va de un entero a otro, y este va de {de} a {a_}");
        return T.ninguno();
    }
    if !igual(a, b) {
        error(c, m, n.linea, $"los dos extremos de un rango son del mismo tipo, y aqui son `{a}` y `{b}`");
        return T.ninguno();
    }
    comprobar_literal(c, m, n.hijos[0], a);
    fijar_literal(c, m, n.hijos[0], a);
    comprobar_literal(c, m, n.hijos[1], a);
    fijar_literal(c, m, n.hijos[1], a);
    return tipo_de_escrito(T.hacer_rango(a));
}

// Un extremo de rango en un mensaje: su tipo, o que es un numero escrito.
fn extremo_dicho(t: view) -> str {
    if igual(t, literal()) { return nuevo("un entero escrito"); }
    if igual(t, literal_decimal()) { return nuevo("un decimal escrito"); }
    return $"`{t}`";
}

fn variable(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    mover_variables: bool, directo: bool) -> T.Tipo {
    let nombre = vista(n.texto);
    let i = buscar_simbolo(c, nombre);
    if !existe(c, i) {
        // El nombre de una funcion sin parentesis es un valor: su puntero.
        let k = funcion_llamada(m, tipos, nombre);
        if k < m.funciones.largo() && !tiene_sueltos(m.funciones[k]) {
            if m.funciones[k].falible {
                error(c, m, n.linea, $"`{nombre}` puede fallar, y una funcion que se pasa como valor no puede: quitale el `!` o envuelvela");
                return T.ninguno();
            }
            return tipo_de_escrito(firma_de(m.funciones[k]));
        }
        if k < m.funciones.largo() {
            error(c, m, n.linea, $"`{nombre}` es generica: hay una funcion por cada juego de tipos, y aqui no se sabe cual. Envuelvela en una funcion normal");
            return T.ninguno();
        }
        error(c, m, n.linea, $"`{nombre}` no esta declarada");
        return T.ninguno();
    }
    let t = copiar(c.simbolos[i].tipo);
    if mover_variables && posee_memoria(m, t) {
        mover(c, m, n.linea, i, directo);
        // El `return x` tambien entrega, pero no por un camino: sale de la
        // funcion entera, y de esa bandera ya se ocupa `retorno_c`. Se graba
        // lo que se entrega y sigue vivo, que es lo que hay que apagar.
        if !directo { grabar_movimiento(c, m, n); }
    } else {
        let _leida = leer(c, m, n.linea, i);
        // Aqui el comprobador decidio que este nodo se lee y no se mueve. Se
        // graba por `dueno#id` —la clave de los anotados— para que el
        // generador lo consulte en vez de deducirlo por su cuenta.
        grabar_lectura(c, m, n);
    }
    return tipo_de_escrito(t);
}

fn unaria(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    destino: view) -> T.Tipo {
    let t = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let op = vista(n.texto);
    if op == "~" {
        if es_literal_entero(t) {
            fijar_literal(c, m, n.hijos[0], "usize");
            return tipo_de_escrito("usize");
        }
        if T.conocido(t) && !es_tipo_entero(T.escribir_tipo(t)) {
            error(c, m, n.linea, $"`~` da la vuelta a los bits de un entero, recibio `{T.escribir_tipo(t)}`");
        }
        return t;
    }
    if op == "!" {
        if T.conocido(t) && t.nombre != "bool" {
            error(c, m, n.linea, $"`!` necesita un `bool`, recibio `{T.escribir_tipo(t)}`");
        }
        return tipo_de_escrito("bool");
    }
    if es_literal_entero(t) {
        // Un `-3` suelto ya lo dice `comprobar_literal`: no cabe. Una cuenta,
        // `-(3 + 4)`, no la mira nadie mas.
        if es_sin_signo(destino) && n.hijos[0].clase != Clase.Entero {
            error(c, m, n.linea, $"`{destino}` no tiene signo: no se puede negar");
        }
        if es_numerico(destino) {
            fijar_literal(c, m, n.hijos[0], destino);
            return tipo_de_escrito(destino);
        }
        comprobar_literal(c, m, n, "i64");
        fijar_literal(c, m, n.hijos[0], "i64");
        return tipo_de_escrito("i64");
    }
    if es_literal_decimal_t(t) { return t; }
    if es_decimal(T.escribir_tipo(t)) { return t; }
    if T.conocido(t) && !es_tipo_entero(T.escribir_tipo(t)) {
        error(c, m, n.linea, $"`-` necesita un entero, recibio `{T.escribir_tipo(t)}`");
    }
    if es_sin_signo(T.escribir_tipo(t)) {
        error(c, m, n.linea, $"`{T.escribir_tipo(t)}` no tiene signo: no se puede negar");
    }
    return t;
}

fn si_expr(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    destino: view, mover_variables: bool) -> T.Tipo {
    let tc = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    if T.conocido(tc) && tc.nombre != "bool" {
        error(c, m, n.linea, $"la condicion de un `if` tiene que ser `bool`, y es `{T.escribir_tipo(tc)}`");
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
    let tb_p = T.apuntado_si(T.escribir_tipo(tb));
    let ta_p = T.apuntado_si(T.escribir_tipo(ta));
    if (es_literal_entero(ta) || es_literal_decimal_t(ta))
    && es_numerico(tb_p) {
        comprobar_literal(c, m, n.hijos[1], tb_p);
        fijar_literal(c, m, n.hijos[1], tb_p);
    } else if (es_literal_entero(tb) || es_literal_decimal_t(tb))
    && es_numerico(ta_p) {
        comprobar_literal(c, m, n.hijos[2], ta_p);
        fijar_literal(c, m, n.hijos[2], ta_p);
    } else if es_literal_entero(ta) && es_literal_decimal_t(tb) {
        fijar_literal(c, m, n.hijos[1], literal_decimal());
        return tb;
    } else if es_literal_entero(tb) && es_literal_decimal_t(ta) {
        fijar_literal(c, m, n.hijos[2], literal_decimal());
        return ta;
    }
    if T.conocido(ta) && T.conocido(tb) && !encaja(T.escribir_tipo(ta), T.escribir_tipo(tb))
    && !encaja(T.escribir_tipo(tb), T.escribir_tipo(ta)) {
        error(c, m, n.linea, $"las dos ramas de un `if` tienen que dar el mismo tipo, y dan `{T.escribir_tipo(ta)}` y `{T.escribir_tipo(tb)}`");
    }
    if !T.conocido(ta) || es_literal_entero(ta) || es_literal_decimal_t(ta) {
        if T.conocido(tb) { return tb; }
        return ta;
    }
    return ta;
}

fn cuantos_valores(n: usize) -> str {
    if n == 1 { return nuevo("1 valor"); }
    return $"{n} valores";
}

fn enum_lit(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let crudo = I.antes_del_punto(n.texto);
    let en_t = I.sin_modulo(crudo);
    let forma = I.tras_el_punto(n.texto);
    if !es_enum(m, en_t) {
        error(c, m, n.linea, $"`{en_t}` no es un enum");
        return T.ninguno();
    }
    if !tiene_forma(m, en_t, forma) {
        let cuales = formas_legibles(m, en_t);
        error(c, m, n.linea, $"`{en_t}` no tiene la forma `{forma}`; tiene {cuales}");
        return T.ninguno();
    }
    let lleva = formas_de(m, en_t, forma);
    if n.hijos.largo() != lleva.largo() {
        let cuantos = cuantos_valores(lleva.largo());
        let dados = n.hijos.largo();
        error(c, m, n.linea, $"`{en_t}.{forma}` lleva {cuantos}, y se le dieron {dados}");
        return T.ninguno();
    }
    var i = 0;
    while i < lleva.largo() {
        let t = vista(lleva[i]);
        let ta = comprobar_expresion(c, m, tipos, n.hijos[i], t, posee_memoria(m, t));
        if T.conocido(ta) && !encaja(t, T.escribir_tipo(ta)) {
            error(c, m, n.linea, $"`{en_t}.{forma}` lleva un `{t}` y se le dio un `{T.escribir_tipo(ta)}`");
        }
        i = i + 1;
    }
    return tipo_de_escrito(en_t);
}

fn formas_legibles(m: &Mundo, en_t: view) -> str {
    let vs = I.lista_de(m.en_variantes, en_t) sino [];
    var todas: list<str> = [];
    for v en vs { todas.anadir($"{en_t}.{v}"); }
    return con_comas(todas);
}

fn comprobar_conversion(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let dado = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let t = sin_prestamo(T.escribir_tipo(dado));
    // `300 como u8` es una cuenta de numeros escritos: lo que en marcha
    // pararia el programa es un error aqui, como `let x: u8 = 256;`. Se
    // cuenta antes de fijarle el tipo, que tambien la contaria.
    let destino_t = T.sin_alias_tipo(vista(n.texto));
    // `-300` es un `i64`: se cuenta lo de dentro y se le cambia el signo.
    let x: &P.Nodo = n.hijos[0];
    let negada = x.clase == Clase.Unaria && x.texto == "-" && x.hijos.largo() == 1
    && I.literal_de(x.hijos[0]) == "entero";
    if (igual(t, literal()) || negada) && es_tipo_entero(destino_t) {
        var v = escrito_sin_saber();
        if negada {
            // Al tiparla como `i64` ya se conto, y sus errores ya se dieron:
            // se cuenta otra vez aparte, sin repetirlos.
            let contadas_antes = copiar(c.contadas);
            let errores_antes = c.errores.largo();
            c.contadas = [];
            let dentro = valor_escrito(c, m, x.hijos[0], "i64");
            c.contadas = contadas_antes;
            if c.errores.largo() > errores_antes {
                var quedan: list<str> = [];
                var k = 0;
                while k < errores_antes {
                    quedan.anadir(copiar(c.errores[k]));
                    k = k + 1;
                }
                c.errores = quedan;
            }
            if dentro.sabido { v = valor_sabido(!dentro.negativo, dentro.magnitud); }
        } else {
            v = valor_escrito(c, m, x, "usize");
        }
        if v.sabido && !cabe_escrito(v, destino_t) {
            let tv = texto_escrito(v);
            let _p = cuenta_parada(c, m, n, $"`{tv} como {destino_t}` no cabe en `{destino_t}`");
        }
    }
    // Un numero escrito sin nada al lado sale de su tipo de siempre.
    if igual(t, literal()) { fijar_literal(c, m, n.hijos[0], "usize"); }
    else if igual(t, literal_decimal()) { fijar_literal(c, m, n.hijos[0], "f64"); }
    var a = copiar(n.texto);
    var envolviendo = false;
    if empieza_con(a, "?") {
        envolviendo = true;
        a = nuevo(rebanar(a, 1, a.largo()));
    }
    a = T.sin_alias_tipo(a);
    if !es_numerico(a) {
        error(c, m, n.linea, $"`como` convierte entre numeros, y `{a}` no es uno");
    } else if t.largo() > 0 && !igual(t, literal()) && !igual(t, literal_decimal())
    && !es_numerico(t) {
        error(c, m, n.linea, $"`como` convierte entre numeros, y `{t}` no es uno");
    } else if envolviendo && es_tipo_entero(a)
    && (es_decimal(t) || igual(t, literal_decimal())) {
        error(c, m, n.linea, $"`como?` de un decimal a `{a}` no tiene sentido: di que quieres con la parte decimal —`piso`, `techo` o `redondear` de `std/numero`— y luego `como {a}`");
    } else if igual(t, a) {
        aviso(c, m, n.linea, $"`como {a}` sobre algo que ya es `{a}`: no hace nada");
    }
    return tipo_de_escrito(a);
}

// Lo que sigue a `try` o `sino` tiene que poder fallar.
fn desenvolver(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, nodo: &P.Nodo,
    dentro: &P.Nodo, palabra: view) -> T.Tipo {
    var falible = false;
    if dentro.clase == Clase.Llamada {
        let k = funcion_llamada(m, tipos, dentro.texto);
        if k < m.funciones.largo() && m.funciones[k].falible { falible = true; }
        let nombre = I.sin_modulo(dentro.texto);
        let fi = firma_interna(nombre);
        if fi.existe && fi.falible { falible = true; }
    }
    if !falible {
        error(c, m, nodo.linea, $"`{palabra}` va delante de una llamada a una funcion declarada con `!`");
        let _t = comprobar_expresion(c, m, tipos, dentro, "", false);
        return T.ninguno();
    }
    return llamada(c, m, tipos, dentro, true, "");
}

// `p.a.b` -> `p\ta.b`: la cadena de campos desde una variable. Vacio si
// por medio hay un indice, una llamada u otra cosa.
fn ruta_de_campo(n: &P.Nodo) -> str {
    var nombres: list<str> = [];
    var x = copiar(n);
    while x.clase == Clase.Campo && x.hijos.largo() > 0 {
        nombres.anadir(copiar(x.texto));
        let dentro = copiar(x.hijos[0]);
        x = dentro;
    }
    if x.clase != Clase.Variable || nombres.largo() == 0 { return vacio(); }
    var r = copiar(x.texto);
    r.empujar("\t");
    var k = nombres.largo();
    while k > 0 {
        k = k - 1;
        r.empujar(nombres[k]);
        if k > 0 { r.empujar("."); }
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
    if c.simbolos[i].prestado || T.es_referencia(t) || t == "view" {
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
    let vivos = prestamos_vivos(c, i);
    if vivos.largo() > 0 {
        let por = ocupada(vivos);
        error(c, m, n.linea, $"no se puede sacar `{nombre}`: {por}");
        return;
    }
    c.simbolos[i].sacados.anadir($"{ruta}\t{n.linea}");
    // El generador reconoce el nodo por su `id`, no por su linea: otro
    // `p.c` en la misma linea —el destino de `p.c = p.c;`, o una lectura
    // despues de reponerlo— no es este, y no se saca.
    c.sacados.anadir($"{c.archivo}\t{n.id}\t{nombre}");
}

fn campo(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    mover_variables: bool) -> T.Tipo {
    let camino = ruta_de_campo(n);
    let raiz = antes_de_tab(camino);
    let ruta = despues_de_tab(camino);
    var ir = c.simbolos.largo();
    if camino.largo() > 0 { ir = buscar_simbolo(c, raiz); }
    // Lo ya sacado no se usa; el error se da una vez y se sigue.
    var ya_sacado = false;
    if c.por_campo == 0 && c.escribiendo == 0 && existe(c, ir) {
        for sacado en copiar(c.simbolos[ir].sacados) {
            if ya_sacado { break; }
            let r = antes_de_tab(sacado);
            let cuando = despues_de_tab(sacado);
            if igual(ruta, r) || empieza_con(ruta, $"{r}.") {
                error(c, m, n.linea, $"`{raiz}.{r}` ya se saco en la linea {cuando} y aqui se usa otra vez");
                ya_sacado = true;
            } else if empieza_con(r, $"{ruta}.") {
                error(c, m, n.linea, $"`{raiz}.{ruta}` esta a medio mover: `{raiz}.{r}` se saco en la linea {cuando}");
                ya_sacado = true;
            }
        }
    }
    let oc = n.hijos[0].clase;
    let encadenado = oc == Clase.Variable || oc == Clase.Campo;
    if encadenado { c.por_campo = c.por_campo + 1; }
    let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    if encadenado { c.por_campo = c.por_campo - 1; }
    if !T.conocido(crudo) { return T.ninguno(); }
    let base = sin_prestamo(T.escribir_tipo(crudo));
    if !es_struct(m, base) {
        error(c, m, n.linea, $"`{base}` no es un struct, no tiene campos");
        return T.ninguno();
    }
    let nombre = vista(n.texto);
    let ns = campos_nombres(m, base);
    let ts = campos_tipos(m, base);
    var i = 0;
    while i < ns.largo() && i < ts.largo() {
        if igual(ns[i], nombre) {
            if mover_variables && posee_memoria(m, ts[i]) && c.por_campo == 0
            && !ya_sacado {
                sacar_campo(c, m, n, base, raiz, ruta, ir);
            } else {
                // Aqui el campo se lee: se graba por `dueno#id` como en
                // `variable()`, para que el generador lo preste en vez de
                // bajarlo a un temporal con duenio.
                grabar_lectura(c, m, n);
            }
            return tipo_de_escrito(copiar(ts[i]));
        }
        i = i + 1;
    }
    error(c, m, n.linea, $"`{base}` no tiene un campo `{nombre}`");
    return T.ninguno();
}

fn indice(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    mover_variables: bool) -> T.Tipo {
    let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let ti = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    if T.conocido(ti) && !encaja("usize", T.escribir_tipo(ti)) {
        error(c, m, n.linea, $"un indice tiene que ser `usize`, es `{T.escribir_tipo(ti)}`");
    }
    if !T.conocido(crudo) { return T.ninguno(); }
    let base = sin_prestamo(T.escribir_tipo(crudo));
    let b = vista(base);
    if !T.es_arreglo(b) && !T.es_lista(b) && !T.es_bloque(b) {
        error(c, m, n.linea, $"`{base}` no es un arreglo, no se puede indexar");
        return T.ninguno();
    }
    var elem = vacio();
    if T.es_arreglo(b) { elem = T.elemento(b); }
    else if T.es_bloque(b) { elem = T.elemento(b); }
    else { elem = T.elemento(b); }
    if mover_variables && posee_memoria(m, elem) {
        var que = nuevo("un arreglo");
        if T.es_bloque(b) { que = nuevo("un bloque"); }
        else if T.es_lista(b) { que = nuevo("una lista"); }
        error(c, m, n.linea, $"no se puede sacar un elemento de {que} y dejar el hueco sin duenio. Si solo quieres leerlo, prestalo: `let x: &{elem} = ...`; si lo necesitas tuyo, `copiar(...)`; si quieres sacarlo, di que dejas en su sitio: `intercambiar(...)`");
    } else {
        // Aqui el elemento se lee: se graba por `dueno#id`, como el campo y
        // la variable, para que el generador lo preste.
        grabar_lectura(c, m, n);
    }
    return tipo_de_escrito(elem);
}

// `Par { a: 7, b: nuevo("x") }` no dice sus tipos: salen de donde va, o de
// lo que hay en los campos.
fn tipo_de_literal_generico(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto,
    n: &P.Nodo, base: view, destino: view) -> T.Tipo {
    let sueltos = I.lista_de(m.st_params, base) sino [];
    if destino.largo() > 0 && T.es_aplicacion(destino) {
        let bd = T.base_de_aplicacion(destino);
        let args = T.partes(destino);
        if igual(bd, base) && args.largo() == sueltos.largo() {
            registrar_tipo(m, destino);
            return tipo_de_escrito(destino);
        }
    }
    var lig: map<str, str> = [];
    let ns = I.lista_de(m.st_nombres, base) sino [];
    let ts = T.tipos_de_mapa(m.st_tipos, base) sino [];
    for h en n.hijos {
        var k = 0;
        while k < ns.largo() && !igual(ns[k], h.texto) { k = k + 1; }
        if k >= ns.largo() || k >= ts.largo() || h.hijos.largo() == 0 { continue; }
        var dado = tipo_probable(c, m, tipos, h.hijos[0]);
        if es_literal_entero(dado) { dado = T.leer_tipo("usize"); }
        if T.es_referencia(T.escribir_tipo(dado)) { dado = tipo_de_escrito(T.apuntado(T.escribir_tipo(dado))); }
        let _u = unificar_tipo(T.escribir_tipo(ts[k]), T.escribir_tipo(dado), sueltos, lig);
    }
    var faltan: list<str> = [];
    for tp en sueltos {
        if !tiene(lig, tp) { faltan.anadir(copiar(tp)); }
    }
    if faltan.largo() > 0 {
        let cuales = con_comas(faltan);
        error(c, m, n.linea, $"no se puede deducir {cuales} en `{base} {{ ... }}`: ni los campos ni el sitio donde va lo dicen. Escribe el tipo en la declaracion: `let x: {base}<...> = ...`");
        return T.ninguno();
    }
    var t = nuevo(base);
    t.empujar("<");
    var i = 0;
    while i < sueltos.largo() {
        if i > 0 { t.empujar(", "); }
        let puesto = obtener(lig, sueltos[i]) sino "";
        t.empujar(puesto);
        i = i + 1;
    }
    t.empujar(">");
    registrar_tipo(m, t);
    return tipo_de_escrito(t);
}

fn literal_struct(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    destino: view) -> T.Tipo {
    var tipo = I.sin_modulo(n.texto);
    if tiene(m.st_params, tipo) {
        let resuelto = tipo_de_literal_generico(c, m, tipos, n, tipo, destino);
        if !T.conocido(resuelto) {
            for h en n.hijos {
                if h.hijos.largo() > 0 { let _t = comprobar_expresion(c, m, tipos, h.hijos[0], "", false); }
            }
            return T.ninguno();
        }
        tipo = T.escribir_tipo(resuelto);
    }
    if !es_struct(m, tipo) {
        error(c, m, n.linea, $"`{tipo}` no es un struct conocido");
        for h en n.hijos {
            if h.hijos.largo() > 0 { let _t = comprobar_expresion(c, m, tipos, h.hijos[0], "", false); }
        }
        return T.ninguno();
    }
    var dados: list<str> = [];
    for h en n.hijos {
        let nombre = vista(h.texto);
        let def = campo_tipo(m, tipo, nombre);
        var mueve = false;
        if def.largo() > 0 { mueve = posee_memoria(m, def); }
        var t = T.ninguno();
        if h.hijos.largo() > 0 { t = comprobar_expresion(c, m, tipos, h.hijos[0], def, mueve); }
        if def.largo() == 0 {
            error(c, m, n.linea, $"`{tipo}` no tiene un campo `{nombre}`");
            continue;
        }
        if esta_entre(dados, nombre) {
            error(c, m, n.linea, $"el campo `{nombre}` se da dos veces");
        }
        dados.anadir(nuevo(nombre));
        if T.conocido(t) && !encaja(def, T.escribir_tipo(t)) {
            error(c, m, n.linea, $"`{tipo}.{nombre}` es `{def}` y recibio `{T.escribir_tipo(t)}`");
        }
    }
    var faltan: list<str> = [];
    for x en campos_nombres(m, tipo) {
        if !esta_entre(dados, x) { faltan.anadir(copiar(x)); }
    }
    if faltan.largo() > 0 {
        let cuales = con_comas(faltan);
        error(c, m, n.linea, $"a `{tipo}` le faltan campos: {cuales}");
    }
    return tipo_de_escrito(tipo);
}

fn literal_arreglo(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    esperado: view) -> T.Tipo {
    if esperado.largo() > 0 && T.es_mapa(esperado) {
        if n.hijos.largo() > 0 {
            error(c, m, n.linea, "un mapa se llena con `poner`; el unico literal que admite es `[]`");
        }
        return tipo_de_escrito(esperado);
    }
    let es_lista_esperada = esperado.largo() > 0 && T.es_lista(esperado);
    if n.hijos.largo() == 0 && !es_lista_esperada {
        if esperado.largo() == 0 {
            error(c, m, n.linea, "`[]` vacio no dice si es una lista, un arreglo o un mapa: escribe el tipo, como `let xs: list<usize> = [];`");
        } else {
            error(c, m, n.linea, "un arreglo tiene que tener al menos un elemento");
        }
        return T.ninguno();
    }
    var elem_esperado = vacio();
    if es_lista_esperada {
        elem_esperado = T.elemento(esperado);
    } else if esperado.largo() > 0 && T.es_arreglo(esperado) {
        elem_esperado = T.elemento(esperado);
        let cuantos = T.cuantos_del_arreglo(esperado);
        let hay = texto(n.hijos.largo());
        if !igual(cuantos, hay) {
            error(c, m, n.linea, $"el tipo dice {cuantos} elemento(s) y el literal tiene {hay}");
        }
    }
    var tipos_e: list<T.Tipo> = [];
    var mueve = false;
    if elem_esperado.largo() > 0 { mueve = posee_memoria(m, elem_esperado); }
    for x en n.hijos {
        tipos_e.anadir(comprobar_expresion(c, m, tipos, x, elem_esperado, mueve));
    }
    if elem_esperado.largo() > 0 {
        var i = 0;
        while i < tipos_e.largo() {
            let t = T.escribir_tipo(tipos_e[i]);
            if t.largo() > 0 && !encaja(elem_esperado, t) {
                let k = i + 1;
                error(c, m, n.linea, $"el elemento {k} deberia ser `{elem_esperado}` y es `{t}`");
            }
            i = i + 1;
        }
        if es_lista_esperada { return tipo_de_escrito(esperado); }
        let hay = n.hijos.largo();
        return tipo_de_escrito(T.hacer_arreglo(elem_esperado, $"{hay}"));
    }
    var conocidos: list<str> = [];
    for t en tipos_e {
        if T.conocido(t) { conocidos.anadir(T.escribir_tipo(t)); }
    }
    if conocidos.largo() == 0 { return T.ninguno(); }
    var elem = copiar(conocidos[0]);
    for t en conocidos {
        if !igual(t, literal()) { elem = copiar(t); break; }
    }
    var i = 0;
    while i < tipos_e.largo() {
        let t = T.escribir_tipo(tipos_e[i]);
        if t.largo() > 0 && !encaja(elem, t) {
            let k = i + 1;
            error(c, m, n.linea, $"los elementos de un arreglo tienen que ser del mismo tipo: el 1 es `{elem}` y el {k} es `{t}`");
        }
        i = i + 1;
    }
    let final = concreto(elem);
    let hay = n.hijos.largo();
    return tipo_de_escrito(T.hacer_arreglo(final, $"{hay}"));
}

// Un texto: con duenio o prestado.
fn es_texto(t: view) -> bool {
    return t == "str" || t == "view";
}

fn binaria(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let op = vista(n.texto);
    let crudo_i = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    var crudo_d = T.ninguno();
    let logico = op == "&&" || op == "||";
    if logico {
        c.en_condicional = c.en_condicional + 1;
        crudo_d = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
        c.en_condicional = c.en_condicional - 1;
    } else {
        crudo_d = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    }
    if logico {
        if T.conocido(crudo_i) && crudo_i.nombre != "bool" {
            error(c, m, n.linea, $"`{op}` necesita `bool`, el lado izquierdo es `{T.escribir_tipo(crudo_i)}`");
        }
        if T.conocido(crudo_d) && crudo_d.nombre != "bool" {
            error(c, m, n.linea, $"`{op}` necesita `bool`, el lado derecho es `{T.escribir_tipo(crudo_d)}`");
        }
        return tipo_de_escrito("bool");
    }
    if !T.conocido(crudo_i) || !T.conocido(crudo_d) { return T.ninguno(); }
    var ti = sin_prestamo(T.escribir_tipo(crudo_i));
    var td = sin_prestamo(T.escribir_tipo(crudo_d));
    let li = igual(ti, literal()) || igual(ti, literal_decimal());
    let ld = igual(td, literal()) || igual(td, literal_decimal());
    let desplaza = op == "<<" || op == ">>";
    if li && es_numerico(td) {
        comprobar_literal(c, m, n.hijos[0], td);
        fijar_literal(c, m, n.hijos[0], td);
        ti = copiar(td);
    } else if ld && es_numerico(ti) {
        comprobar_literal(c, m, n.hijos[1], ti);
        if desplaza { fijar_literal(c, m, n.hijos[1], "usize"); }
        else { fijar_literal(c, m, n.hijos[1], ti); }
        td = copiar(ti);
    }
    if igual(ti, literal()) && igual(td, literal_decimal()) {
        fijar_literal(c, m, n.hijos[0], literal_decimal());
        ti = copiar(td);
    } else if igual(td, literal()) && igual(ti, literal_decimal()) {
        fijar_literal(c, m, n.hijos[1], literal_decimal());
        td = copiar(ti);
    }
    // Cuanto se desplaza llega siempre como `usize`. Un negativo no cabe: se
    // mira aqui —y no solo en el plegado de literales— para coger tambien el
    // caso en que un `como` envuelve al desplazamiento y deja el negativo
    // llegar al generador.
    if desplaza && es_numerico(td) {
        fijar_literal(c, m, n.hijos[1], "usize");
        comprobar_literal(c, m, n.hijos[1], "usize");
    }
    let a = vista(ti);
    let b = vista(td);
    if op == "==" || op == "!=" {
        // Dos textos se comparan por lo que dicen, sea cual sea su forma: el
        // generador lo escribe como `igual(a, b)`.
        if es_texto(a) && es_texto(b) { return tipo_de_escrito("bool"); }
        if !igual(a, b) {
            error(c, m, n.linea, $"no se pueden comparar `{ti}` y `{td}`");
        } else {
            let porque = por_que_no_se_compara(m, a);
            if porque.largo() > 0 { error(c, m, n.linea, porque); }
        }
        if es_decimal(a) {
            aviso(c, m, n.linea, $"`{op}` entre decimales compara bit a bit: `0.1 + 0.2` no es `0.3`. Si querias 'aproximadamente', usa `cerca(a, b, tolerancia)` de `std/numero`");
        }
        return tipo_de_escrito("bool");
    }
    if op == "<" || op == "<=" || op == ">" || op == ">=" {
        if !igual(a, literal()) && !igual(a, literal_decimal())
        && (!es_numerico(a) || !es_numerico(b)) {
            error(c, m, n.linea, $"`{op}` necesita enteros, recibio `{ti}` y `{td}`");
        } else if !igual(a, b) {
            error(c, m, n.linea, $"`{ti}` y `{td}` no se mezclan sin conversion explicita");
        }
        return tipo_de_escrito("bool");
    }
    if op == "&" || op == "|" || op == "^" || op == "<<" || op == ">>" {
        if igual(a, literal()) && igual(b, literal()) { return tipo_de_escrito(nuevo(literal())); }
        if !es_tipo_entero(a) || !es_tipo_entero(b) {
            error(c, m, n.linea, $"`{op}` trabaja sobre los bits de un entero, recibio `{ti}` y `{td}`");
            return T.ninguno();
        }
        if op == "<<" || op == ">>" { return tipo_de_escrito(a); }
        if !igual(a, b) {
            error(c, m, n.linea, $"`{ti}` y `{td}` no se mezclan sin conversion explicita");
        }
        return tipo_de_escrito(a);
    }
    // aritmetica
    if op == "/?" && !igual(a, literal_decimal()) && !igual(b, literal_decimal())
    && !es_decimal(a) && !es_decimal(b) {
        // Entre enteros no hay IEEE que pedir: dividir por cero o `MIN / -1`
        // no tienen un resultado al que volver.
        error(c, m, n.linea, "`/?` es la division IEEE de los decimales; entre enteros no hay vuelta que dar. Usa `/`, que se detiene al dividir por cero");
        return T.ninguno();
    }
    let lit_a = igual(a, literal()) || igual(a, literal_decimal());
    let lit_b = igual(b, literal()) || igual(b, literal_decimal());
    if lit_a && lit_b {
        if igual(a, literal_decimal()) || igual(b, literal_decimal()) {
            return tipo_de_escrito(nuevo(literal_decimal()));
        }
        return tipo_de_escrito(nuevo(literal()));
    }
    if op == "%" && (es_decimal(a) || es_decimal(b)) {
        error(c, m, n.linea, "`%` es el resto de una division entera; con decimales no tiene un significado unico");
        return T.ninguno();
    }
    if !es_numerico(a) || !es_numerico(b) {
        error(c, m, n.linea, $"`{op}` necesita enteros, recibio `{ti}` y `{td}`");
        return T.ninguno();
    }
    if !igual(a, b) {
        error(c, m, n.linea, $"`{ti}` y `{td}` no se mezclan sin conversion explicita");
    }
    return tipo_de_escrito(a);
}

// `match`: exhaustivo, lo que atrapa se presta, y cada brazo es un camino.
fn comprobar_match(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    destino: view, mover_variables: bool) -> T.Tipo {
    let tv = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    if !T.conocido(tv) { return T.ninguno(); }
    let base = sin_prestamo(T.escribir_tipo(tv));
    if !es_enum(m, base) {
        error(c, m, n.linea, $"`match` mira las formas de un enum, y `{T.escribir_tipo(tv)}` no es uno");
        return T.ninguno();
    }
    let antes = foto(c);
    var fotos: list<list<usize>> = [];
    // Las formas con un brazo que vale para todas ellas, y las que tienen
    // alguno, aunque sea con condiciones.
    var vistas: list<str> = [];
    var con_brazo: list<str> = [];
    var comun = vacio();
    var escritos: list<P.Nodo> = [];
    var hay_comodin = false;
    var k = 1;
    while k < n.hijos.largo() {
        let b: &P.Nodo = n.hijos[k];
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
            if h.clase == Clase.Guarda { guarda = h_i como i64; }
            h_i = h_i + 1;
        }
        // Un brazo con guarda, o con algo que no sea un nombre en alguna
        // posicion, puede no casar: no cubre su forma el solo.
        var condicionado = guarda >= 0;
        for p en posiciones {
            if p.clase != Clase.Atrapa { condicionado = true; }
        }
        var forma = vacio();
        if b.texto.largo() == 0 {
            if posiciones.largo() > 0 { error(c, m, n.linea, "el brazo `_` no atrapa nada"); }
            if guarda < 0 { hay_comodin = true; }
        } else {
            forma = I.tras_el_punto(b.texto);
            if !tiene_forma(m, base, forma) {
                let cuales = formas_legibles(m, base);
                error(c, m, n.linea, $"`{base}` no tiene la forma `{forma}`; tiene {cuales}");
                continue;
            }
            if esta_entre(vistas, forma) {
                error(c, m, n.linea, $"`{base}.{forma}` se mira dos veces; el segundo brazo no se ejecuta nunca");
            }
            if !esta_entre(con_brazo, forma) { con_brazo.anadir(copiar(forma)); }
            if !condicionado { vistas.anadir(copiar(forma)); }
            if !patron_valido(c, m, n.linea, base, forma, posiciones) { continue; }
        }
        abrir_ambito(c);
        c.en_condicional = c.en_condicional + 1;
        if forma.largo() > 0 {
            let mirado = origenes_mirado(c, m, n.hijos[0]);
            declarar_patron(c, m, n.linea, base, forma, posiciones, mirado);
        }
        if guarda >= 0 {
            let g: &P.Nodo = b.hijos[guarda como usize];
            c.en_guarda = c.en_guarda + 1;
            let tg = comprobar_expresion(c, m, tipos, g.hijos[0], "", false);
            c.en_guarda = c.en_guarda - 1;
            if T.conocido(tg) && tg.nombre != "bool" {
                error(c, m, n.linea, $"la guarda de un brazo tiene que ser `bool`, es `{T.escribir_tipo(tg)}`");
            }
        }
        var t = T.ninguno();
        var es_expresion = false;
        for h en b.hijos {
            if h.clase == Clase.Retorno { es_expresion = true; }
        }
        for h en b.hijos {
            let hc = h.clase;
            if hc == Clase.Retorno && h.hijos.largo() > 0 {
                t = comprobar_expresion(c, m, tipos, h.hijos[0], destino, mover_variables);
                if es_literal_entero(t) || es_literal_decimal_t(t) {
                    escritos.anadir(copiar(h.hijos[0]));
                }
            } else if hc == Clase.Bloque {
                comprobar_sentencias(c, m, tipos, h);
            }
        }
        c.en_condicional = c.en_condicional - 1;
        cerrar_ambito(c);
        fotos.anadir(foto(c));
        if es_expresion && T.conocido(t) && !es_literal_entero(t)
        && !es_literal_decimal_t(t) {
            if comun.largo() == 0 {
                comun = T.escribir_tipo(t);
            } else if !encaja(T.escribir_tipo(t), comun) && !encaja(comun, T.escribir_tipo(t)) {
                error(c, m, n.linea, $"los brazos de un `match` tienen que dar el mismo tipo, y dan `{comun}` y `{T.escribir_tipo(t)}`");
            }
        }
    }
    if fotos.largo() > 0 {
        var juntas = copiar(fotos[0]);
        var j = 1;
        while j < fotos.largo() {
            juntar_ramas(c, juntas, fotos[j]);
            juntas = foto(c);
            j = j + 1;
        }
    }
    if !hay_comodin {
        var faltan: list<str> = [];
        var a_medias: list<str> = [];
        for v en I.lista_de(m.en_variantes, vista(base)) sino [] {
            if !esta_entre(con_brazo, v) {
                faltan.anadir($"{base}.{v}");
            } else if !esta_entre(vistas, v) {
                a_medias.anadir($"{base}.{v}");
            }
        }
        if faltan.largo() > 0 {
            let cuales = con_comas(faltan);
            error(c, m, n.linea, $"al `match` le faltan formas: {cuales}. Ponlas, o pon un brazo `_` para lo que quede; si no, el dia que anadas una variante este sitio se quedaria callado");
        } else if a_medias.largo() > 0 {
            let cuales = con_comas(a_medias);
            error(c, m, n.linea, $"al `match` le pueden quedar casos de {cuales} sin mirar: sus brazos tienen guarda o un patron que puede no casar. Pon uno que valga para todos, o un brazo `_`");
        }
    }
    // Un brazo que es un numero escrito toma el tipo de los demas, y tiene que
    // caber en el.
    let comun_p = sin_prestamo(comun);
    if es_numerico(comun_p) {
        for v en escritos {
            comprobar_literal(c, m, v, comun_p);
            fijar_literal(c, m, v, comun_p);
        }
    }
    return tipo_de_escrito(comun);
}

// Lo que va en cada posicion de un patron, en orden: hojas `atrapa` y ramas
// `patron` y `literal`.
fn posiciones_de(b: &P.Nodo) -> list<P.Nodo> {
    var salida: list<P.Nodo> = [];
    for h en b.hijos {
        let hc = h.clase;
        if hc == Clase.Atrapa || hc == Clase.Patron || hc == Clase.Literal {
            salida.anadir(copiar(h));
        }
    }
    return salida;
}

// Si lo que va en cada posicion de `base.forma(...)` encaja con lo que lleva
// la forma: el numero, las formas anidadas y los literales.
fn patron_valido(c: mut Comprobacion, m: &Mundo, linea: usize, base: view, forma: view,
    posiciones: &list<P.Nodo>) -> bool {
    let lleva = formas_de(m, base, forma);
    if posiciones.largo() != lleva.largo() {
        let cuantos = cuantos_valores(lleva.largo());
        let atrapados = posiciones.largo();
        error(c, m, linea, $"`{base}.{forma}` lleva {cuantos}, y el patron atrapa {atrapados}");
        return false;
    }
    var i = 0;
    while i < posiciones.largo() {
        let t = copiar(lleva[i]);
        let p = copiar(posiciones[i]);
        i = i + 1;
        let pc = p.clase;
        if pc == Clase.Atrapa { continue; }
        if pc == Clase.Patron {
            let quien = I.sin_modulo(I.antes_del_punto(p.texto));
            let cual = I.tras_el_punto(p.texto);
            if !es_enum(m, t) || !igual(quien, t) {
                error(c, m, linea, $"`{base}.{forma}` lleva un `{t}` en la posicion {i}, y el patron pone `{p.texto}`");
                return false;
            }
            if !tiene_forma(m, t, cual) {
                let cuales = formas_legibles(m, t);
                error(c, m, linea, $"`{t}` no tiene la forma `{cual}`; tiene {cuales}");
                return false;
            }
            if !patron_valido(c, m, linea, t, cual, posiciones_de(p)) { return false; }
            continue;
        }
        let lit: &P.Nodo = p.hijos[0];
        let lc = lit.clase;
        var numero = lc == Clase.Entero;
        if lc == Clase.Unaria && lit.texto == "-" && lit.hijos.largo() > 0 {
            numero = lit.hijos[0].clase == Clase.Entero;
        }
        if numero && es_tipo_entero(t) {
            comprobar_literal(c, m, lit, t);
        } else if !((lc == Clase.Cadena && t == "str")
            || (lc == Clase.Booleano && t == "bool")) {
            error(c, m, linea, $"`{base}.{forma}` lleva un `{t}` en la posicion {i}, y el literal del patron no es uno");
            return false;
        }
    }
    return true;
}

// Lo que atrapa el patron, prestado: un `match` mira, no desmonta. Un `str`
// prestado es una `view`, y lo demas con duenio un `&T`.
fn declarar_patron(c: mut Comprobacion, m: &Mundo, linea: usize, base: view, forma: view,
    posiciones: &list<P.Nodo>, mirado: &list<str>) {
    let lleva = formas_de(m, base, forma);
    var i = 0;
    while i < posiciones.largo() && i < lleva.largo() {
        let t = copiar(lleva[i]);
        let p = copiar(posiciones[i]);
        i = i + 1;
        if p.clase == Clase.Patron {
            let cual = I.tras_el_punto(p.texto);
            declarar_patron(c, m, linea, t, cual, posiciones_de(p), mirado);
        } else if p.clase == Clase.Atrapa && p.texto != "_" {
            var tp = copiar(t);
            if posee_memoria(m, t) {
                if t == "str" { tp = nuevo("view"); } else { tp = T.hacer_prestado(t); }
            }
            let si = declarar_simbolo(c, m, linea, p.texto, tp, false);
            if !igual(tp, t) {
                // Lo atrapado apunta dentro del valor mirado: mientras viva,
                // ese valor no se mueve ni se modifica.
                for o en mirado {
                    let d = buscar_simbolo(c, o);
                    if !existe(c, d) || esta_entre(c.simbolos[si].origenes, o) { continue; }
                    c.simbolos[si].origenes.anadir(copiar(o));
                    c.simbolos[d].prestamos.anadir(copiar(p.texto));
                }
                if c.simbolos[si].origenes.largo() > 0 {
                    c.simbolos[si].origen = copiar(c.simbolos[si].origenes[0]);
                }
            }
        }
    }
}

// Una clausura es su struct con lo capturado mas su funcion, que se
// comprueba aqui, en mitad de quien la escribe, como en el original.
// Dentro del cuerpo, un nombre capturado es un campo del entorno.
fn renombrar_capturas(n: mut P.Nodo, nombres: &list<str>, linea: usize) {
    var i = 0;
    while i < n.hijos.largo() {
        if n.hijos[i].clase == Clase.Variable
        && esta_entre(nombres, n.hijos[i].texto) {
            var campo_e = P.rama(Clase.Campo, n.hijos[i].linea);
            campo_e.texto = copiar(n.hijos[i].texto);
            campo_e.hijos.anadir(P.hoja(Clase.Variable, "_ss_entorno", linea));
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
fn nodo_de_cierre(n: &P.Nodo, numero: usize, capturadas: &list<str>,
    modifica: bool) -> P.Nodo {
    var f = P.rama(Clase.Fn, n.linea);
    f.texto = $"ss_cierre_{numero}";
    var entorno = P.rama(Clase.Param, n.linea);
    entorno.texto = $"_ss_entorno: &Cierre_{numero}";
    if modifica { entorno.texto = $"_ss_entorno: mut Cierre_{numero}"; }
    f.hijos.anadir(entorno);
    for h en n.hijos {
        if h.clase == Clase.Captura { continue; }
        var x = copiar(h);
        if x.clase == Clase.Bloque { renombrar_capturas(x, capturadas, n.linea); }
        f.hijos.anadir(x);
    }
    return f;
}

// Las clausuras de un cuerpo, numeradas `#0`, `#1`... en preorden. Las de
// dentro de otra son de la otra: se numeran cuando se mira su funcion.
fn etiquetar_cierres(n: mut P.Nodo, cuenta: mut usize) {
    var i = 0;
    while i < n.hijos.largo() {
        if n.hijos[i].clase == Clase.Cierre {
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
fn cierre(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let clave = $"{c.dueno}{n.texto}";
    if tiene(m.numeracion, clave) {
        let ya = obtener(m.numeracion, clave) sino 0;
        return tipo_de_escrito($"Cierre_{ya}");
    }
    let numero = m.n_cierres + 1;
    m.n_cierres = numero;
    poner(m.numeracion, vista(clave), numero);
    let st = $"Cierre_{numero}";
    var nombres: list<str> = [];
    var ts: list<str> = [];
    var vistos: list<str> = [];
    var mutables: list<str> = [];
    for h en n.hijos {
        if h.clase == Clase.Captura && h.hijos.largo() > 0 {
            mutables.anadir(copiar(h.texto));
        }
    }
    for h en n.hijos {
        if h.clase != Clase.Captura { continue; }
        let nombre = vista(h.texto);
        if esta_entre(vistos, nombre) {
            error(c, m, n.linea, $"`{nombre}` se captura dos veces");
            continue;
        }
        vistos.anadir(nuevo(nombre));
        let i = buscar_simbolo(c, nombre);
        if !existe(c, i) {
            error(c, m, n.linea, $"`{nombre}` no esta declarada, no se puede capturar");
            continue;
        }
        let t = copiar(c.simbolos[i].tipo);
        if presta_tipo(m, t) {
            var arreglo = $"Captura lo que necesites de `{nombre}`";
            if t == "view" || T.es_referencia(t) {
                arreglo = $"Captura un `str` con `copiar({nombre})`";
            }
            error(c, m, n.linea, $"`{nombre}` es `{t}`, un prestamo: una clausura captura por valor, y guardar un prestamo exigiria saber cuanto vive. {arreglo}");
            continue;
        }
        nombres.anadir(nuevo(nombre));
        ts.anadir(copiar(t));
        if posee_memoria(m, t) { mover(c, m, n.linea, i, false); }
        else { let _l = leer(c, m, n.linea, i); }
    }
    if nombres.largo() == 0 {
        nombres.anadir(nuevo("ss_vacio"));
        ts.anadir(nuevo("u8"));
    }
    poner(m.st_tipos, vista(st), T.leer_tipos(ts));
    poner(m.st_nombres, vista(st), nombres);
    m.orden_structs.anadir(copiar(st));
    m.tipo_de_struct.anadir(copiar(st));
    let modifica = mutables.largo() > 0;
    if modifica { m.cierres_mut.anadir(copiar(st)); }
    let fn_nodo = nodo_de_cierre(n, numero, vistos, modifica);
    m.cierres.anadir(copiar(fn_nodo));
    m.orden_copias.anadir($"ss_cierre_{numero}");
    m.cierres_mod.anadir(c.modulo);
    let de_cierre = $"ss_cierre_{numero}";
    var f = funcion_de(fn_nodo, vista(de_cierre), vista(c.archivo), c.modulo,
        numero - 1, false);
    f.de_cierre = true;
    let k = m.funciones.largo();
    poner(m.indice, vista(de_cierre), k);
    m.funciones.anadir(f);
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
    comprobar_funcion(c, m, tipos, k, fn_nodo, de_cierre);
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
        let escrito_n = G.escrito(nombre);
        if !esta_entre(modificadas, nombre) && !empieza_con(escrito_n, "_") {
            aviso(c, m, n.linea, $"`{nombre}` se captura con `mut` y nunca se modifica; puede ir sin `mut`");
        }
    }
    return tipo_de_escrito(st);
}

// ------------------------------------------------------------------
// Llamadas
// ------------------------------------------------------------------

fn llamada(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    desenvuelta: bool, destino: view) -> T.Tipo {
    let escrito = vista(n.texto);
    let corto = I.sin_modulo(escrito);
    let fi = firma_interna(corto);
    if fi.existe && !contiene(escrito, ".") {
        if fi.falible && !desenvuelta {
            error(c, m, n.linea, $"`{corto}` puede fallar: la llamada tiene que ir detras de `try`, o con `sino <valor>` para dar un valor cuando falle");
        }
        return interna(c, m, tipos, n, corto, destino);
    }

    // Una variable con una clausura dentro se llama como su funcion, con el
    // entorno delante, prestado.
    let iv = buscar_simbolo(c, escrito);
    if existe(c, iv) {
        let tv = sin_prestamo(c.simbolos[iv].tipo);
        let de_cierre = I.funcion_de_cierre(tv);
        if de_cierre.largo() > 0 {
            var otra = P.rama(Clase.Llamada, n.linea);
            // El entorno lo pone el compilador, no el programa: no tiene id
            // propio. Su prestamo —el parametro 0 de `ss_cierre_N`— viaja bajo
            // el id de esta llamada, que es la que el generador reconstruye.
            otra.id = n.id;
            otra.texto = copiar(de_cierre);
            otra.hijos.anadir(P.hoja(Clase.Variable, escrito, n.linea));
            for h en n.hijos { otra.hijos.anadir(copiar(h)); }
            return llamada(c, m, tipos, otra, desenvuelta, destino);
        }
        if T.es_funcion(c.simbolos[iv].tipo) {
            return llamada_a_puntero(c, m, tipos, n, iv);
        }
    }

    let k = funcion_llamada(m, tipos, escrito);
    if k >= m.funciones.largo() {
        error(c, m, n.linea, $"`{escrito}` no es una funcion conocida");
        for h en n.hijos { let _t = comprobar_expresion(c, m, tipos, h, "", false); }
        return T.ninguno();
    }
    var f = copiar(m.funciones[k]);
    // A quien se entrega lo que se mueve: la copia, si es una generica.
    var destinataria = copiar(f.nombre);
    if tiene_sueltos(f) {
        let inst = instanciar(c, m, tipos, n, k);
        if !inst.ok {
            for h en n.hijos { let _t = comprobar_expresion(c, m, tipos, h, "", false); }
            return T.ninguno();
        }
        f.params = copiar(inst.params);
        f.retorno = copiar(inst.retorno);
        destinataria = copiar(inst.copia);
    }
    let nombre = vista(f.nombre);
    if f.falible && !desenvuelta {
        error(c, m, n.linea, $"`{nombre}` puede fallar: la llamada tiene que ir detras de `try`, o con `sino <valor>` para dar un valor cuando falle");
    }
    if n.hijos.largo() != f.params.largo() {
        let pide = f.params.largo();
        let dados = n.hijos.largo();
        error(c, m, n.linea, $"`{nombre}` espera {pide} argumento(s) y recibio {dados}");
    }
    // Dos prestamos de lo mismo solo conviven si ninguno modifica. Dos campos
    // distintos no son lo mismo: `g(p.a, p.b)` vale.
    var hechos = prestamos();
    var i = 0;
    while i < n.hijos.largo() && i < f.params.largo() {
        let arg: &P.Nodo = n.hijos[i];
        let p: &Param = f.params[i];
        i = i + 1;
        if prestado(p) {
            // Lo que se pasa a un parametro que presta no se lee ni se mueve:
            // se presta. Queda grabado para que el generador pida la direccion
            // porque este canal lo dice, y no porque la firma tenga un `&`. Un
            // argumento sintetizado —el entorno de una clausura— no tiene id:
            // se graba bajo el id de la llamada.
            grabar_prestamo_de(c, m, arg, n);
            let base = variable_base(arg);
            let is = buscar_simbolo(c, base);
            if base.largo() == 0 || !existe(c, is) {
                let t_arg = comprobar_expresion(c, m, tipos, arg, "", false);
                if T.conocido(t_arg) && !encaja(p.tipo, T.escribir_tipo(t_arg)) {
                    error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `{p.tipo}` y recibio `{T.escribir_tipo(t_arg)}`");
                } else if p.mutable {
                    error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `mut`: modificar algo recien hecho no le sirve a nadie, pasale una variable");
                }
                continue;
            }
            let tipo_arg = tipo_de_lugar(c, m, tipos, arg);
            // Un prestamo que ya se tiene —lo que da `obtener`, lo que
            // atrapa un `match`— se pasa tal cual: es el mismo puntero.
            let ya_prestado = T.conocido(tipo_arg) && T.es_referencia(T.escribir_tipo(tipo_arg))
            && igual(T.apuntado(T.escribir_tipo(tipo_arg)), p.tipo);
            if T.conocido(tipo_arg) && !igual(T.escribir_tipo(tipo_arg), p.tipo) && !ya_prestado {
                error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `{p.tipo}` y recibio `{T.escribir_tipo(tipo_arg)}`");
            }
            let camino = camino_de(arg);
            let choque = choque_prestamo(hechos, camino, p.mutable);
            if choque.largo() == 2 {
                var dos: list<str> = [];
                dos.anadir(copiar(p.nombre));
                dos.anadir(copiar(choque[1]));
                ordenar(dos);
                error(c, m, n.linea, $"`{choque[0]}` se presta dos veces en la misma llamada a `{nombre}` (como `{dos[0]}` y como `{dos[1]}`), y al menos uno de los dos puede modificarlo");
            }
            apuntar_prestamo(hechos, camino, p.nombre, p.mutable);
            if p.mutable {
                let por_puntero = T.es_referencia(c.simbolos[is].tipo);
                mutar(c, m, arg, arg.linea, is, por_puntero);
                // Quien lo recibe casi siempre lee antes de escribir.
                c.simbolos[is].leida = true;
            } else {
                let _l = leer(c, m, arg.linea, is);
            }
            continue;
        }
        // Un `buffer` es una salida: C va a escribir ahi. Pide una variable
        // —y `var`, porque se modifica— y la llamada cuenta como modificarla.
        if igual(p.tipo, "buffer") {
            let base = variable_base(arg);
            let is = buscar_simbolo(c, base);
            if base.largo() == 0 || !existe(c, is) {
                let t_arg = comprobar_expresion(c, m, tipos, arg, "str", false);
                if T.conocido(t_arg) && !encaja("str", T.escribir_tipo(t_arg)) {
                    error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `buffer` y recibio `{T.escribir_tipo(t_arg)}`");
                } else {
                    error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `buffer`: C va a escribir ahi, pasale una variable");
                }
                continue;
            }
            let tipo_arg = tipo_de_lugar(c, m, tipos, arg);
            if T.conocido(tipo_arg) && !igual(T.escribir_tipo(tipo_arg), "str") {
                error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `buffer` y recibio `{T.escribir_tipo(tipo_arg)}`");
                continue;
            }
            let por_puntero = T.es_referencia(c.simbolos[is].tipo);
            mutar(c, m, arg, arg.linea, is, por_puntero);
            c.simbolos[is].leida = true;
            continue;
        }
        // Una funcion de C mira la cadena, no se la queda.
        let mueve = posee_memoria(m, p.tipo) && !f.externa;
        if mueve && arg.clase == Clase.Variable {
            let ia = buscar_simbolo(c, arg.texto);
            if existe(c, ia) { c.simbolos[ia].movida_a = copiar(destinataria); }
        }
        // Un `buffer` no es un tipo de valor: por dentro es un `str`, y asi se
        // comprueba el argumento. El `const` se lo quita el generador.
        var esperado = copiar(p.tipo);
        if igual(esperado, "buffer") { esperado = nuevo("str"); }
        let t = comprobar_expresion(c, m, tipos, arg, esperado, mueve);
        // Una vista que se pasa tambien presta, aunque no tenga nombre:
        // `g(s, vista(s))` con `a: mut str` dejaria a `g` modificando por un
        // lado lo que lee por el otro. Es el fallo 2 de la especificacion.
        if presta_tipo(m, p.tipo) && !f.externa {
            for camino en prestados_por(c, m, arg, T.escribir_tipo(t)) {
                let choque = choque_prestamo(hechos, camino, false);
                if choque.largo() == 2 {
                    var dos: list<str> = [];
                    dos.anadir(copiar(p.nombre));
                    dos.anadir(copiar(choque[1]));
                    ordenar(dos);
                    error(c, m, n.linea, $"`{choque[0]}` se presta dos veces en la misma llamada a `{nombre}` (como `{dos[0]}` y como `{dos[1]}`), y al menos uno de los dos puede modificarlo");
                }
                apuntar_prestamo(hechos, camino, p.nombre, false);
            }
        }
        if p.tipo == "view" && t.nombre == "str" { continue; }
        if T.conocido(t) && !encaja(p.tipo, T.escribir_tipo(t)) {
            if largo(I.funcion_de_cierre(T.escribir_tipo(t))) > 0 && T.es_funcion(p.tipo) {
                error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `{p.tipo}`, un puntero a funcion, y recibio una clausura. Una clausura lleva dentro lo que capturo, asi que no cabe en un puntero: haz el parametro generico (`{p.nombre}: F`) y valdra para las dos");
            } else {
                error(c, m, n.linea, $"`{p.nombre}` de `{nombre}` es `{p.tipo}` y recibio `{T.escribir_tipo(t)}`");
            }
        }
    }
    if f.retorno.largo() > 0 {
        if f.cadena_c { return tipo_de_escrito("str"); }
        return tipo_de_escrito(copiar(f.retorno));
    }
    return tipo_de_escrito(nuevo("()"));
}

// Una variable que guarda una funcion se llama como cualquier otra.
fn llamada_a_puntero(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    iv: usize) -> T.Tipo {
    let _l = leer(c, m, n.linea, iv);
    let tv = copiar(c.simbolos[iv].tipo);
    let nombre = vista(n.texto);
    let partes = T.partes_de_funcion(tv);
    var params: list<str> = [];
    var i = 0;
    while i + 1 < partes.largo() {
        params.anadir(copiar(partes[i]));
        i = i + 1;
    }
    if n.hijos.largo() != params.largo() {
        let pide = params.largo();
        let dados = n.hijos.largo();
        error(c, m, n.linea, $"`{nombre}` es `{tv}` y espera {pide} argumento(s), recibio {dados}");
    }
    // Los prestamos de una misma llamada, como en una funcion con nombre: la
    // firma del puntero dice lo mismo que la de ella.
    var hechos = prestamos();
    var k = 0;
    while k < n.hijos.largo() && k < params.largo() {
        let esperado = vista(params[k]);
        let presta = T.es_referencia(esperado);
        let dentro = sin_prestamo(esperado);
        let mueve = !presta && posee_memoria(m, dentro);
        let t = comprobar_expresion(c, m, tipos, n.hijos[k], dentro, mueve);
        let cual = $"el argumento {k + 1}";
        if presta {
            // La firma del puntero presta igual que la de una funcion con
            // nombre: el argumento queda grabado como prestado, la misma
            // decision y el mismo canal.
            grabar_prestamo_de(c, m, n.hijos[k], n);
            let base = variable_base(n.hijos[k]);
            let is = buscar_simbolo(c, base);
            if base.largo() > 0 && existe(c, is) {
                let mutable = T.es_referencia_mutable(esperado);
                let camino = camino_de(n.hijos[k]);
                let choque = choque_prestamo(hechos, camino, mutable);
                if choque.largo() == 2 {
                    error(c, m, n.linea, $"`{choque[0]}` se presta dos veces en la misma llamada a `{nombre}` ({choque[1]} y {cual}), y al menos uno de los dos puede modificarlo");
                }
                apuntar_prestamo(hechos, camino, cual, mutable);
                if mutable {
                    mutar(c, m, n.hijos[k], n.hijos[k].linea, is, false);
                } else {
                    let _u = leer(c, m, n.hijos[k].linea, is);
                }
            }
        } else if presta_tipo(m, dentro) {
            for camino en prestados_por(c, m, n.hijos[k], T.escribir_tipo(t)) {
                let choque = choque_prestamo(hechos, camino, false);
                if choque.largo() == 2 {
                    error(c, m, n.linea, $"`{choque[0]}` se presta dos veces en la misma llamada a `{nombre}` ({choque[1]} y {cual}), y al menos uno de los dos puede modificarlo");
                }
                apuntar_prestamo(hechos, camino, cual, false);
            }
        }
        let limpio = sin_prestamo(T.escribir_tipo(t));
        if T.conocido(t) && !encaja(dentro, limpio) {
            if !(dentro == "view" && limpio == "str") {
                error(c, m, n.linea, $"`{nombre}` toma `{esperado}` ahi y recibio `{T.escribir_tipo(t)}`");
            }
        }
        k = k + 1;
    }
    if partes.largo() == 0 { return T.ninguno(); }
    return tipo_de_escrito(copiar(partes[partes.largo() - 1]));
}

// ------------------------------------------------------------------
// Las internas
// ------------------------------------------------------------------

fn evaluar_todos(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) {
    for h en n.hijos { let _t = comprobar_expresion(c, m, tipos, h, "", false); }
}

fn interna(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    nombre: view, destino: view) -> T.Tipo {
    let fi = firma_interna(nombre);
    let dados = n.hijos.largo();

    if nombre == "igual" || nombre == "menor" { return interna_comparar(c, m, tipos, n, nombre); }

    if nombre == "raiz" || nombre == "piso" || nombre == "techo"
    || nombre == "redondear" || nombre == "absoluto" { return interna_numeros(c, m, tipos, n, nombre); }

    if nombre == "reservar" { return interna_reservar(c, m, tipos, n, destino); }

    if nombre == "redimensionar" { return interna_redimensionar(c, m, tipos, n); }

    if nombre == "intercambiar" { return interna_intercambiar(c, m, tipos, n); }

    if nombre == "copiar" { return interna_copiar(c, m, tipos, n); }

    if nombre == "largo" { return interna_largo(c, m, tipos, n); }

    if nombre == "anadir" { return interna_anadir(c, m, tipos, n); }

    if nombre == "truncar" { return interna_truncar(c, m, tipos, n); }

    if nombre == "ordenar" { return interna_ordenar(c, m, tipos, n); }

    if nombre == "poner" || nombre == "obtener" || nombre == "obtener_mut"
    || nombre == "tiene" || nombre == "claves" || nombre == "quitar" {
        return interna_mapa(c, m, tipos, n, nombre);
    }

    if nombre == "texto" { return interna_texto(c, m, tipos, n); }

    if dados != fi.params.largo() {
        let pide = fi.params.largo();
        error(c, m, n.linea, $"`{nombre}` espera {pide} argumento(s) y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return tipo_de_escrito(copiar(fi.retorno));
    }

    // Paso 1: los argumentos, y los prestamos que duran lo que la llamada.
    var prestados: list<str> = [];
    var i = 0;
    while i < dados {
        let esperado = vista(fi.params[i]);
        let arg: &P.Nodo = n.hijos[i];
        let k = i + 1;
        i = i + 1;
        if esperado == "@mut" { continue; }
        if esperado == "@presta" {
            let base = variable_base(arg);
            let is = buscar_simbolo(c, base);
            if base.largo() == 0 || !existe(c, is) {
                error(c, m, n.linea, $"`{nombre}` necesita una variable, un campo o un elemento, no una expresion suelta");
                continue;
            }
            let crudo = tipo_de_lugar(c, m, tipos, arg);
            let t_presta = sin_prestamo(T.escribir_tipo(crudo));
            if t_presta != "str" {
                error(c, m, n.linea, $"`{nombre}` presta de un `str`");
                continue;
            }
            let _l = leer(c, m, arg.linea, is);
            prestados.anadir(copiar(base));
            continue;
        }
        let t = comprobar_expresion(c, m, tipos, arg, "", false);
        if T.conocido(t) && esperado != "@cualquiera" && !encaja(esperado, T.escribir_tipo(t)) {
            let limpio = sin_prestamo(T.escribir_tipo(t));
            if !(esperado == "view" && limpio == "str") {
                error(c, m, n.linea, $"el argumento {k} de `{nombre}` debe ser `{esperado}` y es `{T.escribir_tipo(t)}`");
            }
        }
        if esperado == "@cualquiera" && T.conocido(t) && !se_muestra(T.escribir_tipo(t)) {
            error(c, m, n.linea, $"`{nombre}` no sabe mostrar un `{T.escribir_tipo(t)}`: {como_mostrar(m, T.escribir_tipo(t))}");
        }
        if esperado == "view" {
            // Todos los duenios posibles, no el primero: con
            // `if c { vista(a) } else { vista(b) }` puede ser cualquiera.
            var origenes: list<str> = [];
            for o en origenes_de(c, m, arg) {
                if o != "<temporal>" { origenes.anadir(copiar(o)); }
            }
            if origenes.largo() == 0 && arg.clase == Clase.Variable && t.nombre == "str" {
                origenes.anadir(copiar(arg.texto));
            }
            for o en origenes { prestados.anadir(copiar(o)); }
        }
    }

    // Paso 2: los efectos, que ya ven los prestamos del paso 1. Esto es lo
    // que rechaza `empujar(s, vista(s))`.
    var j = 0;
    while j < dados {
        let k = j + 1;
        let esperado = vista(fi.params[j]);
        let arg: &P.Nodo = n.hijos[j];
        j = j + 1;
        if esperado != "@mut" { continue; }
        let base = variable_base(arg);
        let is = buscar_simbolo(c, base);
        if base.largo() == 0 || !existe(c, is) {
            error(c, m, n.linea, $"el argumento {k} de `{nombre}` tiene que ser una variable, un campo o un elemento");
            continue;
        }
        let crudo = tipo_de_lugar(c, m, tipos, arg);
        let t_lugar = sin_prestamo(T.escribir_tipo(crudo));
        if t_lugar != "str" {
            error(c, m, n.linea, $"`{nombre}` opera sobre `str`");
            continue;
        }
        if esta_entre(prestados, base) {
            error(c, m, n.linea, $"`{base}` se presta y se modifica en la misma llamada a `{nombre}`: al crecer, el buffer puede moverse y dejar la vista colgando");
            continue;
        }
        let por_ref = arg.clase != Clase.Variable
        || T.es_referencia(c.simbolos[is].tipo);
        mutar(c, m, arg, arg.linea, is, por_ref);
    }
    return tipo_de_escrito(copiar(fi.retorno));
}
fn interna_comparar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto,
    n: &P.Nodo, nombre: view) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 2 {
        error(c, m, n.linea, $"`{nombre}` espera 2 argumentos y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return tipo_de_escrito("bool");
    }
    let a0 = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let ta = sin_prestamo(T.escribir_tipo(a0));
    let a1 = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    let tb = sin_prestamo(T.escribir_tipo(a1));
    var validos = comparables();
    if nombre == "igual" { validos = igualables(); }
    let cuales = con_comas(validos);
    if ta.largo() > 0 && !igual(ta, literal()) && !esta_entre(validos, ta) {
        error(c, m, n.linea, $"`{nombre}` compara {cuales}, y recibio `{ta}`");
        return tipo_de_escrito("bool");
    }
    if tb.largo() > 0 && !igual(tb, literal()) && !esta_entre(validos, tb) {
        error(c, m, n.linea, $"`{nombre}` compara {cuales}, y recibio `{tb}`");
        return tipo_de_escrito("bool");
    }
    let texto_a = ta == "str" || ta == "view";
    let texto_b = tb == "str" || tb == "view";
    if ta.largo() > 0 && tb.largo() > 0 && !(texto_a && texto_b) {
        var a = copiar(ta);
        var b = copiar(tb);
        if igual(a, literal()) { a = nuevo("usize"); }
        if igual(b, literal()) { b = nuevo("usize"); }
        if !igual(a, b) {
            error(c, m, n.linea, $"`{nombre}` compara dos valores del mismo tipo, y recibio `{ta}` y `{tb}`");
        }
    }
    return tipo_de_escrito("bool");
}

fn interna_numeros(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto,
    n: &P.Nodo, nombre: view) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 1 {
        error(c, m, n.linea, $"`{nombre}` espera 1 argumento y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return T.ninguno();
    }
    let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let t = sin_prestamo(T.escribir_tipo(crudo));
    if igual(t, literal_decimal()) { return tipo_de_escrito("f64"); }
    if nombre == "absoluto" {
        if igual(t, literal()) { return tipo_de_escrito("i64"); }
        if !es_decimal(t) && !es_con_signo(t) {
            error(c, m, n.linea, $"`absoluto` necesita un numero con signo, recibio `{t}`");
            return T.ninguno();
        }
        return tipo_de_escrito(t);
    }
    if igual(t, literal()) { return tipo_de_escrito("f64"); }
    if !es_decimal(t) {
        error(c, m, n.linea, $"`{nombre}` trabaja sobre decimales, recibio `{t}`");
        return T.ninguno();
    }
    return tipo_de_escrito(t);
}

fn interna_reservar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto,
    n: &P.Nodo, destino: view) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 1 {
        error(c, m, n.linea, $"`reservar` espera 1 argumento (cuantos) y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return T.ninguno();
    }
    let t = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    if T.conocido(t) && !encaja("usize", T.escribir_tipo(t)) {
        error(c, m, n.linea, $"`reservar` espera cuantos elementos, un `usize`, y recibio `{T.escribir_tipo(t)}`");
    }
    if destino.largo() == 0 || !T.es_bloque(destino) {
        error(c, m, n.linea, "`reservar(n)` necesita saber de que: escribelo en la declaracion, `var b: bloque<str> = reservar(4);`");
        return T.ninguno();
    }
    return tipo_de_escrito(destino);
}

fn interna_redimensionar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 2 {
        error(c, m, n.linea, $"`redimensionar` espera 2 argumentos y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return tipo_de_escrito(nuevo("()"));
    }
    let base = variable_base(n.hijos[0]);
    let is = buscar_simbolo(c, base);
    let sitio = tipo_de_lugar(c, m, tipos, n.hijos[0]);
    let t_sitio = sin_prestamo(T.escribir_tipo(sitio));
    if base.largo() == 0 || !existe(c, is) || !T.es_bloque(t_sitio) {
        error(c, m, n.linea, "`redimensionar` cambia el tamaño de un bloque, y necesita un sitio que lo sea: una variable, un campo o un elemento");
        let _t = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
        return tipo_de_escrito(nuevo("()"));
    }
    let por_ref = T.es_referencia(c.simbolos[is].tipo);
    mutar(c, m, n.hijos[0], n.hijos[0].linea, is, por_ref);
    c.simbolos[is].prestamos.anadir(nuevo("redimensionar"));
    let t = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    soltar_prestamo(c, is, "redimensionar");
    if T.conocido(t) && !encaja("usize", T.escribir_tipo(t)) {
        error(c, m, n.linea, $"`redimensionar` espera el tamaño nuevo, un `usize`, y recibio `{T.escribir_tipo(t)}`");
    }
    return tipo_de_escrito(nuevo("()"));
}

fn interna_intercambiar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 2 {
        error(c, m, n.linea, $"`intercambiar` espera 2 argumentos y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return T.ninguno();
    }
    let base = variable_base(n.hijos[0]);
    let is = buscar_simbolo(c, base);
    if base.largo() == 0 || !existe(c, is) {
        error(c, m, n.linea, "`intercambiar` necesita un sitio: una variable, un campo o un elemento, no una expresion suelta");
        let _t = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
        return T.ninguno();
    }
    let t = tipo_de_lugar(c, m, tipos, n.hijos[0]);
    if T.conocido(t) && presta_tipo(m, T.escribir_tipo(t)) {
        error(c, m, n.linea, $"`intercambiar` no cambia prestamos: `{T.escribir_tipo(t)}` apunta a memoria de otro. Asigna con `=`");
    }
    let por_ref = T.es_referencia(c.simbolos[is].tipo);
    mutar(c, m, n.hijos[0], n.hijos[0].linea, is, por_ref);
    c.simbolos[is].prestamos.anadir(nuevo("intercambiar"));
    var mueve = false;
    if T.conocido(t) { mueve = posee_memoria(m, T.escribir_tipo(t)); }
    let tv = comprobar_expresion(c, m, tipos, n.hijos[1], T.escribir_tipo(t), mueve);
    soltar_prestamo(c, is, "intercambiar");
    if T.conocido(t) && T.conocido(tv) && !encaja(T.escribir_tipo(t), T.escribir_tipo(tv)) {
        error(c, m, n.linea, $"`intercambiar` pone y saca lo mismo: el sitio es `{T.escribir_tipo(t)}` y el valor es `{T.escribir_tipo(tv)}`");
    }
    return t;
}

fn interna_copiar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 1 {
        error(c, m, n.linea, $"`copiar` espera 1 argumento y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return T.ninguno();
    }
    let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    if !T.conocido(crudo) { return T.ninguno(); }
    let t = sin_prestamo(T.escribir_tipo(crudo));
    if t == "view" {
        error(c, m, n.linea, "una vista no es duenia de nada que copiar: si quieres el texto, `nuevo(v)` te da un `str`");
        return tipo_de_escrito("str");
    }
    if igual(t, literal()) { return tipo_de_escrito("usize"); }
    if !almacenable(m, t) {
        error(c, m, n.linea, $"`copiar` no sabe copiar un `{t}`");
        return tipo_de_escrito(t);
    }
    return tipo_de_escrito(t);
}

fn interna_largo(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 1 {
        error(c, m, n.linea, $"`largo` espera 1 argumento y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return tipo_de_escrito("usize");
    }
    let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let t = sin_prestamo(T.escribir_tipo(crudo));
    let x = vista(t);
    if T.conocido(crudo) && x != "view" && x != "str" && !T.es_arreglo(x)
    && !T.es_lista(x) && !T.es_mapa(x) && !T.es_bloque(x) {
        error(c, m, n.linea, $"`largo` opera sobre texto, arreglos, listas o mapas, recibio `{t}`");
    }
    return tipo_de_escrito("usize");
}

fn interna_anadir(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 2 {
        error(c, m, n.linea, $"`anadir` espera 2 argumentos y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return tipo_de_escrito(nuevo("()"));
    }
    let base = variable_base(n.hijos[0]);
    let is = buscar_simbolo(c, base);
    var tipo_lista = vacio();
    let hay = base.largo() > 0 && existe(c, is);
    if hay { tipo_lista = sin_prestamo(T.escribir_tipo(tipo_de_lugar(c, m, tipos, n.hijos[0]))); }
    if !hay {
        error(c, m, n.linea, "el primer argumento de `anadir` tiene que ser una variable, un campo o un elemento");
    } else if !T.es_lista(tipo_lista) {
        let visto = texto_o_none(tipo_lista);
        error(c, m, n.linea, $"`anadir` opera sobre `list<T>`, recibio `{visto}`");
    } else {
        let elem = T.elemento(tipo_lista);
        let t = comprobar_expresion(c, m, tipos, n.hijos[1], elem, posee_memoria(m, elem));
        if T.conocido(t) && !encaja(elem, T.escribir_tipo(t)) {
            error(c, m, n.linea, $"la lista guarda `{elem}` y se intento agregar `{T.escribir_tipo(t)}`");
        }
        // Por un `&mut list<T>` —de `obtener_mut`, o un parametro— se
        // modifica; por un `&` no, y el error lo dice.
        mutar(c, m, n.hijos[0], n.hijos[0].linea, is,
            T.es_referencia(c.simbolos[is].tipo));
        return tipo_de_escrito(nuevo("()"));
    }
    let _t = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    return tipo_de_escrito(nuevo("()"));
}

fn interna_truncar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 2 {
        error(c, m, n.linea, $"`truncar` espera 2 argumentos y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return tipo_de_escrito(nuevo("()"));
    }
    let base = variable_base(n.hijos[0]);
    let is = buscar_simbolo(c, base);
    var tipo_lista = vacio();
    let hay = base.largo() > 0 && existe(c, is);
    if hay { tipo_lista = sin_prestamo(T.escribir_tipo(tipo_de_lugar(c, m, tipos, n.hijos[0]))); }
    if !hay {
        error(c, m, n.linea, "el primer argumento de `truncar` tiene que ser una variable, un campo o un elemento");
    } else if !T.es_lista(tipo_lista) {
        let visto = texto_o_none(tipo_lista);
        error(c, m, n.linea, $"`truncar` opera sobre `list<T>`, recibio `{visto}`");
    } else {
        // Como `anadir`: por un `&mut list<T>` se recorta; por un `&` no.
        mutar(c, m, n.hijos[0], n.hijos[0].linea, is,
            T.es_referencia(c.simbolos[is].tipo));
        c.simbolos[is].prestamos.anadir(nuevo("truncar"));
        let t = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
        soltar_prestamo(c, is, "truncar");
        if T.conocido(t) && !encaja("usize", T.escribir_tipo(t)) {
            error(c, m, n.linea, $"`truncar` espera el nuevo largo, un `usize`, y recibio `{T.escribir_tipo(t)}`");
        }
        return tipo_de_escrito(nuevo("()"));
    }
    let _t = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    return tipo_de_escrito(nuevo("()"));
}

fn interna_ordenar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 1 {
        error(c, m, n.linea, $"`ordenar` espera 1 argumento y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return tipo_de_escrito(nuevo("()"));
    }
    let base = variable_base(n.hijos[0]);
    let is = buscar_simbolo(c, base);
    let hay = base.largo() > 0 && existe(c, is);
    var t = vacio();
    if hay { t = sin_prestamo(T.escribir_tipo(tipo_de_lugar(c, m, tipos, n.hijos[0]))); }
    if !hay {
        error(c, m, n.linea, "`ordenar` necesita una variable, un campo o un elemento");
    } else if !T.es_lista(t) {
        let visto = texto_o_none(t);
        error(c, m, n.linea, $"`ordenar` opera sobre `list<T>`, recibio `{visto}`");
    } else {
        let e = T.elemento(t);
        let ords = ordenables();
        if !esta_entre(ords, e) {
            let cuales = con_comas(ords);
            error(c, m, n.linea, $"`{e}` no tiene un orden natural; `ordenar` funciona sobre {cuales}");
        } else {
            mutar(c, m, n.hijos[0], n.hijos[0].linea, is,
                T.es_referencia(c.simbolos[is].tipo));
        }
    }
    return tipo_de_escrito(nuevo("()"));
}

fn interna_texto(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) -> T.Tipo {
    let dados = n.hijos.largo();
    if dados != 1 {
        error(c, m, n.linea, $"`texto` espera 1 argumento y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return tipo_de_escrito("str");
    }
    let crudo = comprobar_expresion(c, m, tipos, n.hijos[0], "", false);
    let t = sin_prestamo(T.escribir_tipo(crudo));
    let x = vista(t);
    if t.largo() > 0 && !es_tipo_entero(x) && !igual(x, literal()) && x != "bool"
    && x != "view" && x != "str" {
        error(c, m, n.linea, $"`texto` convierte escalares o texto, recibio `{t}`");
    }
    return tipo_de_escrito("str");
}

// `poner`, `obtener`, `tiene`, `claves`, `quitar` y `obtener_mut`.
fn interna_mapa(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo,
    nombre: view) -> T.Tipo {
    var esperados = 2;
    if nombre == "poner" { esperados = 3; }
    if nombre == "claves" { esperados = 1; }
    var si_falla = vacio();
    if nombre == "poner" { si_falla = nuevo("()"); }
    if nombre == "tiene" || nombre == "quitar" { si_falla = nuevo("bool"); }
    let dados = n.hijos.largo();
    if dados != esperados {
        error(c, m, n.linea, $"`{nombre}` espera {esperados} argumento(s) y recibio {dados}");
        evaluar_todos(c, m, tipos, n);
        return tipo_de_escrito(si_falla);
    }
    let base = variable_base(n.hijos[0]);
    let is = buscar_simbolo(c, base);
    let hay = base.largo() > 0 && existe(c, is);
    var tipo_mapa = T.ninguno();
    if hay { tipo_mapa = tipo_de_lugar(c, m, tipos, n.hijos[0]); }
    if !hay {
        error(c, m, n.linea, $"el primer argumento de `{nombre}` tiene que ser una variable, un campo o un elemento");
        var r = 1;
        while r < dados {
            let _t = comprobar_expresion(c, m, tipos, n.hijos[r], "", false);
            r = r + 1;
        }
        return tipo_de_escrito(si_falla);
    }
    if !T.es_mapa(T.escribir_tipo(tipo_mapa)) {
        let visto = texto_o_none(T.escribir_tipo(tipo_mapa));
        error(c, m, n.linea, $"`{nombre}` opera sobre `map<K, V>`, recibio `{visto}`");
        var r = 1;
        while r < dados {
            let _t = comprobar_expresion(c, m, tipos, n.hijos[r], "", false);
            r = r + 1;
        }
        return tipo_de_escrito(si_falla);
    }
    let partes = T.partes(T.escribir_tipo(tipo_mapa));
    let kt = copiar(partes[0]);
    let vt = copiar(partes[1]);
    let linea_m = n.hijos[0].linea;
    if nombre == "claves" {
        let _l = leer(c, m, linea_m, is);
        return tipo_de_escrito(T.hacer_lista(kt));
    }
    let tc = comprobar_expresion(c, m, tipos, n.hijos[1], "", false);
    if T.conocido(tc) && !encaja(kt, T.escribir_tipo(tc))
    && !(kt == "str" && tc.nombre == "view") {
        error(c, m, n.linea, $"la clave del mapa es `{kt}` y se paso `{T.escribir_tipo(tc)}`");
    }
    if nombre == "tiene" {
        let _l = leer(c, m, linea_m, is);
        return tipo_de_escrito("bool");
    }
    if nombre == "obtener_mut" {
        if !es_compuesto(m, vt) {
            error(c, m, n.linea, $"`obtener_mut` presta para modificar algo que vive en el mapa; `{vt}` es un escalar, asi que usa `obtener` y vuelve a `poner`");
            return tipo_de_escrito(vt);
        }
        mutar(c, m, n.hijos[0], linea_m, is, false);
        return tipo_de_escrito(T.hacer_prestado_mut(vt));
    }
    if nombre == "quitar" {
        mutar(c, m, n.hijos[0], linea_m, is, false);
        return tipo_de_escrito("bool");
    }
    if nombre == "obtener" {
        let _l = leer(c, m, linea_m, is);
        if !posee_memoria(m, vt) { return tipo_de_escrito(vt); }
        if vt == "str" { return tipo_de_escrito("view"); }
        return tipo_de_escrito(T.hacer_prestado(vt));
    }
    let tv = comprobar_expresion(c, m, tipos, n.hijos[2], vt, posee_memoria(m, vt));
    if T.conocido(tv) && !encaja(vt, T.escribir_tipo(tv)) {
        error(c, m, n.linea, $"el mapa guarda `{vt}` y se intento poner `{T.escribir_tipo(tv)}`");
    }
    mutar(c, m, n.hijos[0], linea_m, is, false);
    return tipo_de_escrito(nuevo("()"));
}

// ------------------------------------------------------------------
// Los tipos escritos: cada `Par<A, B>` tiene que ser un struct generico con
// ese numero de tipos
// ------------------------------------------------------------------

// Lo prestado, las listas, los bloques, los mapas y los arreglos: los tipos
// que llevan otros dentro y no son la aplicacion de un generico.
fn lleva_partes(t: view) -> bool {
    return T.es_referencia(t) || T.es_bloque(t) || T.es_lista(t) || T.es_mapa(t)
    || T.es_arreglo(t);
}

fn validar_tipo(c: mut Comprobacion, m: mut Mundo, linea: usize, t: view) {
    if !contiene(t, "<") && !contiene(t, "[") { return; }
    // Lo que lleva tipos dentro vale si valen sus partes, en orden.
    if lleva_partes(t) {
        for x en T.partes(t) { validar_tipo(c, m, linea, x); }
        return;
    }
    if !termina_con(t, ">") || T.es_funcion(t) { return; }
    let base = T.base(t);
    if base.largo() == 0 { return; }
    let primero = byte(base, 0);
    if !((primero >= 65 && primero <= 90) || (primero >= 97 && primero <= 122)) { return; }
    let args = T.partes(t);
    for a en args { validar_tipo(c, m, linea, a); }
    if !tiene(m.st_params, base) {
        error(c, m, linea, $"`{base}` no es un struct generico");
        return;
    }
    let sueltos = I.lista_de(m.st_params, base) sino [];
    if args.largo() != sueltos.largo() {
        let pide = sueltos.largo();
        let dados = args.largo();
        error(c, m, linea, $"`{base}` toma {pide} tipo(s) y se le dieron {dados}");
        return;
    }
    registrar_aplicacion(m, t);
}

// Una copia de struct generico nace la primera vez que se nombra: se apunta
// y despues sus campos, que pueden pedir otras.
fn registrar_aplicacion(m: mut Mundo, t: view) {
    let nombre = I.nombre_resuelto(t);
    if esta_entre(m.orden_structs, nombre) { return; }
    m.orden_structs.anadir(nombre);
    m.tipo_de_struct.anadir(nuevo(t));
    for x en campos_tipos(m, t) { registrar_tipo(m, x); }
}

// Las copias que pide un tipo, sin errores: los de un tipo ya comprobado.
fn registrar_tipo(m: mut Mundo, t: view) {
    if !contiene(t, "<") && !contiene(t, "[") { return; }
    if lleva_partes(t) {
        for x en T.partes(t) { registrar_tipo(m, x); }
        return;
    }
    if !es_struct_aplicado(m, t) { return; }
    for a en T.partes(t) { registrar_tipo(m, a); }
    registrar_aplicacion(m, t);
}

// Lo mismo en el cuerpo de una copia: sus declaraciones y clausuras.
fn registrar_en_nodo(m: mut Mundo, n: &P.Nodo) {
    let clase = n.clase;
    match clase {
        Clase.Declaracion -> {
            var nombre = vacio();
            var escrito = vacio();
            let _mutable = partes_declaracion(n.texto, nombre, escrito);
            if escrito.largo() > 0 { registrar_tipo(m, escrito); }
        }
        Clase.Param -> {
            let p = param_de(n.texto);
            registrar_tipo(m, p.tipo);
        }
        Clase.RetornoTipo -> {
            let t = T.sin_alias_tipo(n.texto);
            registrar_tipo(m, t);
        }
        _ -> { }
    }
    for h en n.hijos { registrar_en_nodo(m, h); }
}

// Los tipos escritos dentro de una funcion, en orden: parametros, retorno,
// y las declaraciones y clausuras de su cuerpo.
fn validar_en_funcion(c: mut Comprobacion, m: mut Mundo, d: &P.Nodo) {
    for h en d.hijos {
        if h.clase == Clase.Param {
            let p = param_de(h.texto);
            validar_tipo(c, m, d.linea, p.tipo);
        }
    }
    for h en d.hijos {
        if h.clase == Clase.RetornoTipo {
            let t = T.sin_alias_tipo(h.texto);
            validar_tipo(c, m, d.linea, t);
        }
    }
    for h en d.hijos {
        if h.clase == Clase.Bloque { validar_en_nodo(c, m, h); }
    }
}

fn validar_en_nodo(c: mut Comprobacion, m: mut Mundo, n: &P.Nodo) {
    if n.clase == Clase.Declaracion {
        var nombre = vacio();
        var escrito = vacio();
        let _mutable = partes_declaracion(n.texto, nombre, escrito);
        if escrito.largo() > 0 { validar_tipo(c, m, n.linea, escrito); }
    }
    if n.clase == Clase.Cierre {
        // La clausura tiene sus tipos escritos donde esta: parametros,
        // retorno, y su cuerpo.
        for h en n.hijos {
            if h.clase == Clase.Param {
                let p = param_de(h.texto);
                validar_tipo(c, m, n.linea, p.tipo);
            }
        }
        for h en n.hijos {
            if h.clase == Clase.RetornoTipo {
                let t = T.sin_alias_tipo(h.texto);
                validar_tipo(c, m, n.linea, t);
            }
        }
        for h en n.hijos {
            if h.clase == Clase.Bloque { validar_en_nodo(c, m, h); }
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
    if n.clase == Clase.Bloque {
        comprobar_sentencias(c, m, tipos, n);
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
    comprobar_sentencias(c, m, tipos, n);
    cerrar_ambito(c);
    c.en_bucle_directo = anterior;
    cerrar_movidas_de_bucle(c, m);
}

// Lo que sigue movido al cerrar la vuelta se moveria otra vez. Vale igual
// para el cuerpo y para la condicion: las dos corren en cada vuelta.
fn cerrar_movidas_de_bucle(c: mut Comprobacion, m: &Mundo) {
    let k = c.movidas_en_bucle.largo() - 1;
    let movidas = copiar(c.movidas_en_bucle[k]);
    var quedan: list<list<usize>> = [];
    var q = 0;
    while q < k {
        quedan.anadir(copiar(c.movidas_en_bucle[q]));
        q = q + 1;
    }
    c.movidas_en_bucle = quedan;
    var i = 0;
    while i + 1 < movidas.largo() {
        let s = movidas[i];
        let linea = movidas[i + 1];
        i = i + 2;
        if s < c.simbolos.largo() && c.simbolos[s].movida {
            let nombre = copiar(c.simbolos[s].nombre);
            error(c, m, linea, $"`{nombre}` se declaro fuera del bucle y se mueve aqui dentro, asi que la siguiente vuelta lo moveria otra vez. Declaralo dentro del bucle, o dale otro valor antes de cerrar la vuelta");
        }
    }
}

// `let x: T` -> nombre y tipo escrito (vacio si no lo lleva).
fn partes_declaracion(texto: view, nombre: mut str, tipo: mut str) -> bool {
    var i = 0;
    while i < texto.largo() && byte(texto, i) != 32 { i = i + 1; }
    let mutable = rebanar(texto, 0, i) == "var";
    let resto = recortar(rebanar(texto, i, texto.largo()));
    var j = 0;
    while j < resto.largo() && byte(resto, j) != 58 { j = j + 1; }
    nombre = nuevo(recortar(rebanar(resto, 0, j)));
    if j < resto.largo() {
        tipo = T.sin_alias_tipo(recortar(rebanar(resto, j + 1, resto.largo())));
    } else {
        tipo = vacio();
    }
    return mutable;
}

fn comprobar_mapa_valido(c: mut Comprobacion, m: &Mundo, linea: usize, t: view) {
    if !T.es_mapa(t) { return; }
    let ps = T.partes(t);
    if ps.largo() != 2 { return; }
    let k = vista(ps[0]);
    let v = vista(ps[1]);
    if k != "str" {
        error(c, m, linea, $"la clave de un mapa tiene que ser `str`, y aqui es `{k}`");
    }
    if T.es_referencia(v) || T.es_referencia(k) {
        error(c, m, linea, "un mapa guarda valores, no prestamos: `&T` no puede ser ni clave ni valor");
    }
}

// Una sentencia suelta, sin nada detras: la rama de un `else if`.
fn comprobar_sentencia(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo) {
    let nada: map<str, usize> = [];
    comprobar_sentencia_en(c, m, tipos, s, nada, s.id);
}

// Las sentencias de un bloque, cada una sabiendo que nombres mencionan las
// que la siguen.
fn comprobar_sentencias(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, n: &P.Nodo) {
    let despues = despues_de_cada(n);
    var k = 0;
    while k < n.hijos.largo() {
        comprobar_sentencia_en(c, m, tipos, n.hijos[k], despues[k], n.id);
        k = k + 1;
    }
}

fn comprobar_sentencia_en(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo,
    despues: &map<str, usize>, bloque: usize) {
    let desde = c.escritas.largo();
    var clase = nuevo("otra");
    if s.clase == Clase.Si { clase = nuevo("si"); }
    if s.clase == Clase.Mientras || s.clase == Clase.Para {
        clase = nuevo("bucle");
    }
    var propias: map<str, usize> = [];
    mencionados_en(s, propias);
    let k = c.hondura;
    if k < c.cadena_clases.largo() {
        c.cadena_clases[k] = clase;
        c.cadena_propias[k] = propias;
        c.cadena_despues[k] = copiar(despues);
        c.cadena_bloques[k] = bloque;
    } else {
        c.cadena_clases.anadir(clase);
        c.cadena_propias.anadir(propias);
        c.cadena_despues.anadir(copiar(despues));
        c.cadena_bloques.anadir(bloque);
    }
    c.hondura = k + 1;
    comprobar_sentencia_sin_contar(c, m, tipos, s);
    c.hondura = k;
    contar_pendientes(c, m, desde);
}

// Los nombres de variable que aparecen en `n`, a cualquier hondura.
fn mencionados_en(n: &P.Nodo, salida: mut map<str, usize>) {
    if n.clase == Clase.Variable { poner(salida, vista(n.texto), 1); }
    for h en n.hijos { mencionados_en(h, salida); }
}

// Por cada sentencia del bloque, los nombres que mencionan las que la siguen.
fn despues_de_cada(n: &P.Nodo) -> list<map<str, usize>> {
    var al_reves: list<map<str, usize>> = [];
    var vistos: map<str, usize> = [];
    var k = n.hijos.largo();
    while k > 0 {
        k = k - 1;
        al_reves.anadir(copiar(vistos));
        mencionados_en(n.hijos[k], vistos);
    }
    var salida: list<map<str, usize>> = [];
    var j = al_reves.largo();
    while j > 0 {
        j = j - 1;
        salida.anadir(copiar(al_reves[j]));
    }
    return salida;
}

// El bloque de la sentencia en curso, o 0.
fn bloque_en_curso(c: &Comprobacion) -> usize {
    if c.hondura == 0 || c.hondura <= c.base { return 0; }
    return c.cadena_bloques[c.hondura - 1];
}

// Si la vista `nombre` se vuelve a usar desde aqui. Un prestamo dura hasta
// el ultimo uso de quien presta, no hasta el final de su bloque:
//
//     let v = vista(s);
//     imprimir(v);        // ultimo uso de `v`
//     empujar(s, "!");    // bien: nadie mira ya a `s`
//
// Se usa si se menciona en la sentencia en curso, en las que la siguen en su
// bloque o en los de fuera hasta donde se declaro, o en cualquier parte de un
// bucle que la envuelva: la vuelta siguiente vuelve a empezar. Ante la duda,
// vive.
fn vive_despues(c: &Comprobacion, nombre: view) -> bool {
    let i = buscar_simbolo(c, nombre);
    var tope = 0;
    if existe(c, i) { tope = c.simbolos[i].bloque_decl; }
    var j = c.hondura;
    while j > c.base {
        j = j - 1;
        // De un `if` que envuelve a la sentencia en curso solo corre la rama
        // en la que se esta; de lo demas, todo cuenta.
        let en_curso = j + 1 == c.hondura;
        if (en_curso || c.cadena_clases[j] != "si")
        && tiene(c.cadena_propias[j], nombre) {
            return true;
        }
        if tiene(c.cadena_despues[j], nombre) { return true; }
        if tope > 0 && c.cadena_bloques[j] == tope { return false; }
    }
    return false;
}

// Los prestamos de `i` que siguen vivos aqui. Los de un `for` y las reservas
// de `intercambiar` y `redimensionar` viven hasta que acaban; los de una
// vista, hasta su ultimo uso.
fn prestamos_vivos(c: &Comprobacion, i: usize) -> list<str> {
    var salida: list<str> = [];
    for p en c.simbolos[i].prestamos {
        if es_reserva(p) || empieza_con(p, "<") || vive_despues(c, p) {
            salida.anadir(copiar(p));
        }
    }
    return salida;
}

fn comprobar_sentencia_sin_contar(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto,
    s: &P.Nodo) {
    let clase = s.clase;

    match clase {
        Clase.Declaracion -> { sentencia_declaracion(c, m, tipos, s); return; }
        Clase.Asignacion -> { sentencia_asignacion(c, m, tipos, s); return; }
        Clase.Si -> { sentencia_si(c, m, tipos, s); return; }
        Clase.Para -> { sentencia_para(c, m, tipos, s); return; }
        Clase.Mientras -> { sentencia_mientras(c, m, tipos, s); return; }
        Clase.Retorno -> { sentencia_retorno(c, m, tipos, s); return; }
        Clase.Falla -> { sentencia_falla(c, m, s); return; }
        Clase.Expresion -> { sentencia_expresion(c, m, tipos, s); return; }
        _ -> { sentencia_otra(c, m, s); return; }
    }
}
fn sentencia_declaracion(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo) {
    var nombre = vacio();
    var escrito = vacio();
    let mutable = partes_declaracion(s.texto, nombre, escrito);
    var tipo = vacio();
    if escrito.largo() == 0 {
        let t = comprobar_expresion(c, m, tipos, s.hijos[0], "", true);
        if !T.conocido(t) { return; }
        tipo = T.escribir_tipo(t);
        if igual(tipo, literal()) {
            comprobar_literal(c, m, s.hijos[0], "usize");
            tipo = nuevo("usize");
        }
        if !almacenable(m, tipo) {
            error(c, m, s.linea, $"no se puede deducir el tipo de `{nombre}`: escribelo con `: tipo`");
            return;
        }
    } else if presta_un_sitio(c, m, escrito, s.hijos[0]) {
        prestar_sitio(c, m, tipos, s, nombre, escrito, mutable);
        return;
    } else {
        tipo = copiar(escrito);
        comprobar_mapa_valido(c, m, s.linea, tipo);
        if !almacenable(m, tipo) {
            if T.es_referencia(tipo) {
                let dentro = T.apuntado(tipo);
                error(c, m, s.linea, $"`{tipo}` no tiene sentido: `{dentro}` es un escalar, y prestarlo no aporta nada sobre copiarlo");
            } else {
                error(c, m, s.linea, $"`{tipo}` no es un tipo almacenable; las listas y los arreglos no pueden guardar `view` ni prestamos `&T`, y las listas tampoco arreglos fijos");
            }
        }
        let t = comprobar_expresion(c, m, tipos, s.hijos[0], tipo, true);
        if T.conocido(t) && !encaja(tipo, T.escribir_tipo(t)) {
            error(c, m, s.linea, $"`{nombre}` se declaro `{tipo}` pero el valor es `{T.escribir_tipo(t)}`");
        }
    }
    let i = declarar_simbolo(c, m, s.linea, nombre, tipo, mutable);
    if presta_tipo(m, tipo) {
        c.simbolos[i].procedencia = procedencia_de(c, m, s.hijos[0]);
        c.simbolos[i].prestado = T.es_referencia(tipo);
        apuntar(c, m, s.linea, i, s.hijos[0]);
    }
    return;
}

fn sentencia_asignacion(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo) {
    let lugar: &P.Nodo = s.hijos[0];
    let base = variable_base(lugar);
    let i = buscar_simbolo(c, base);
    if base.largo() == 0 || !existe(c, i) {
        if base.largo() > 0 {
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
    let tipo = comprobar_expresion(c, m, tipos, s.hijos[1], T.escribir_tipo(destino), true);
    if escribe_en_captura(c, m, lugar) { return; }
    c.simbolos[i].mutada = true;
    let st = copiar(c.simbolos[i].tipo);
    if T.es_referencia(st) {
        if !T.es_referencia_mutable(st) {
            error_solo_lectura(c, m, s.linea, base, st);
        }
    } else if !c.simbolos[i].mutable {
        error_no_mutable(c, m, s.linea, i);
    }
    let vivos = prestamos_vivos(c, i);
    if vivos.largo() > 0 {
        let por = ocupada(vivos);
        error(c, m, s.linea, $"no se puede modificar `{base}`: {por}");
    }
    if T.conocido(destino) && T.conocido(tipo) && !encaja(T.escribir_tipo(destino), T.escribir_tipo(tipo)) {
        error(c, m, s.linea, $"el destino es `{T.escribir_tipo(destino)}` y se le asigna un `{T.escribir_tipo(tipo)}`");
    }
    // Una vista guardada en un campo: el struct de la raiz presta tambien
    // de ella. Si la raiz llego prestada, quien la presto no sabria de
    // donde presta ahora, salvo que sea un literal.
    if lugar.clase == Clase.Campo && presta_tipo(m, T.escribir_tipo(tipo)) {
        let de_raiz = copiar(c.simbolos[i].tipo);
        if c.simbolos[i].prestado || T.es_referencia(de_raiz) {
            if procedencia_de(c, m, s.hijos[1]) != "estatico" {
                error(c, m, s.linea, $"no se puede guardar un prestamo en `{base}`: llego prestada, y quien la presto no sabria de donde presta ahora. Guarda un literal, o devuelve el valor");
            }
        } else if es_prestado_st(m, de_raiz) {
            let nueva = procedencia_de(c, m, s.hijos[1]);
            let antes = copiar(c.simbolos[i].procedencia);
            if antes == "local" || nueva == "local" {
                c.simbolos[i].procedencia = nuevo("local");
            } else if antes == "parametro" || nueva == "parametro" {
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
        if lugar.clase == Clase.Variable {
            c.simbolos[i].sacados = [];
        } else {
            let camino = ruta_de_campo(lugar);
            if camino.largo() > 0 {
                let ruta = despues_de_tab(camino);
                var quedan: list<str> = [];
                for x en c.simbolos[i].sacados {
                    let r = antes_de_tab(x);
                    if !igual(r, ruta) && !empieza_con(r, $"{ruta}.") {
                        quedan.anadir(copiar(x));
                    }
                }
                c.simbolos[i].sacados = quedan;
            }
        }
    }
    if lugar.clase == Clase.Variable {
        c.simbolos[i].movida = false;
        if c.en_bucle_directo == c.en_bucle como i64 {
            c.simbolos[i].reasignada_directo = true;
        }
        let ti = copiar(c.simbolos[i].tipo);
        if presta_tipo(m, ti) {
            // Lo peor de lo que tuvo y de lo que tiene ahora: si la
            // asignacion va en una rama, la otra puede no haberla hecho.
            let nueva = procedencia_de(c, m, s.hijos[1]);
            let antes = copiar(c.simbolos[i].procedencia);
            if antes == "local" || nueva == "local" {
                c.simbolos[i].procedencia = nuevo("local");
            } else if antes == "parametro" || nueva == "parametro" {
                c.simbolos[i].procedencia = nuevo("parametro");
            }
            apuntar(c, m, s.linea, i, s.hijos[1]);
        }
    }
    return;
}

fn sentencia_si(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo) {
    let t = comprobar_expresion(c, m, tipos, s.hijos[0], "", false);
    if T.conocido(t) && t.nombre != "bool" {
        error(c, m, s.linea, $"la condicion de `if` debe ser `bool`, es `{T.escribir_tipo(t)}`");
    }
    c.en_condicional = c.en_condicional + 1;
    let antes = foto(c);
    comprobar_bloque(c, m, tipos, s.hijos[1]);
    let tras_e = foto(c);
    let sale_e = bloque_termina(s.hijos[1]);
    var tras_s = copiar(antes);
    var sale_s = false;
    if s.hijos.largo() > 2 {
        restaurar_foto(c, antes);
        comprobar_bloque(c, m, tipos, s.hijos[2]);
        tras_s = foto(c);
        sale_s = termina_rama(s.hijos[2]);
    }
    // Una rama que no continua no aporta a lo que sigue.
    var i = 0;
    while i < c.simbolos.largo() && 4 * i + 3 < tras_e.largo() {
        var mb = tras_e[4 * i];
        var lb = tras_e[4 * i + 1];
        var eb = tras_e[4 * i + 2];
        var rb = tras_e[4 * i + 3];
        if 4 * i + 3 < tras_s.largo() {
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

fn sentencia_para(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo) {
    let crudo = comprobar_expresion(c, m, tipos, s.hijos[0], "", false);
    let tipo = sin_prestamo(T.escribir_tipo(crudo));
    var elem = vacio();
    var tipo_valor = vacio();
    var variable = vacio();
    var valor = vacio();
    let nombres = vista(s.texto);
    var coma = 0;
    while coma < nombres.largo() && byte(nombres, coma) != 44 { coma = coma + 1; }
    variable = nuevo(recortar(rebanar(nombres, 0, coma)));
    if coma < nombres.largo() { valor = nuevo(recortar(rebanar(nombres, coma + 1, nombres.largo()))); }
    let es_rango = tipo.largo() > 0 && T.es_rango(tipo);
    if es_rango {
        elem = T.elemento(tipo);
        if valor.largo() > 0 {
            error(c, m, s.linea, "un rango da un numero en cada vuelta: `for i en a..b`, con un solo nombre");
        }
    } else if tipo.largo() > 0 && T.es_mapa(tipo) {
        let ps = T.partes(tipo);
        elem = copiar(ps[0]);
        tipo_valor = copiar(ps[1]);
    } else if tipo.largo() > 0 && (T.es_lista(tipo) || T.es_arreglo(tipo)) {
        if T.es_lista(tipo) { elem = T.elemento(tipo); }
        else { elem = T.elemento(tipo); }
        if valor.largo() > 0 {
            error(c, m, s.linea, "los dos nombres de `for k, v en ...` son para un mapa; una lista solo da el elemento");
        }
    } else if tipo.largo() > 0 {
        error(c, m, s.linea, $"`for` recorre una `list<T>`, un arreglo o un `map<K, V>`, y `{tipo}` no lo es");
    }
    // El bucle presta la coleccion mientras dura.
    let base = variable_base(s.hijos[0]);
    let d = buscar_simbolo(c, base);
    let marca = $"<el for de la linea {s.linea}>";
    let hay_duenio = base.largo() > 0 && existe(c, d);
    if hay_duenio { c.simbolos[d].prestamos.anadir(copiar(marca)); }
    abrir_ambito(c);
    c.en_bucle = c.en_bucle + 1;
    let vacia: list<usize> = [];
    c.movidas_en_bucle.anadir(vacia);
    c.en_condicional = c.en_condicional + 1;
    if elem.largo() > 0 {
        let i = declarar_simbolo(c, m, s.linea, variable, elem, false);
        // El numero de un rango es suyo; el elemento de una coleccion se
        // presta de ella. Y presta de donde preste la coleccion: de un
        // parametro si es campo suyo, del propio bucle si es un temporal.
        c.simbolos[i].prestado = !es_rango;
        c.simbolos[i].procedencia = procedencia_de(c, m, s.hijos[0]);
        c.simbolos[i].leida = true;
    }
    if tipo_valor.largo() > 0 && valor.largo() > 0 {
        let j = declarar_simbolo(c, m, s.linea, valor, tipo_valor, false);
        c.simbolos[j].leida = true;
        if posee_memoria(m, tipo_valor) {
            c.simbolos[j].prestado = true;
            c.simbolos[j].procedencia = procedencia_de(c, m, s.hijos[0]);
        }
    }
    cuerpo_de_bucle(c, m, tipos, s.hijos[1]);
    c.en_condicional = c.en_condicional - 1;
    c.en_bucle = c.en_bucle - 1;
    cerrar_ambito(c);
    if hay_duenio && esta_entre(c.simbolos[d].prestamos, marca) {
        soltar_prestamo(c, d, marca);
    }
    return;
}

fn sentencia_mientras(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo) {
    // La condicion corre en cada vuelta, igual que el cuerpo: se comprueba al
    // mismo nivel de bucle y sus movimientos entran en la misma lista, que
    // `cuerpo_de_bucle` revisa al cerrar la vuelta. Si no, `while usa(p)`
    // movia `p` en cada vuelta y nadie lo veia.
    c.en_condicion_bucle = c.en_condicion_bucle + 1;
    c.en_bucle = c.en_bucle + 1;
    let vacia: list<usize> = [];
    c.movidas_en_bucle.anadir(vacia);
    let t = comprobar_expresion(c, m, tipos, s.hijos[0], "", false);
    c.en_condicion_bucle = c.en_condicion_bucle - 1;
    if T.conocido(t) && t.nombre != "bool" {
        error(c, m, s.linea, $"la condicion de `while` debe ser `bool`, es `{T.escribir_tipo(t)}`");
    }
    c.en_condicional = c.en_condicional + 1;
    cuerpo_de_bucle(c, m, tipos, s.hijos[1]);
    c.en_condicional = c.en_condicional - 1;
    c.en_bucle = c.en_bucle - 1;
    return;
}

fn sentencia_retorno(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo) {
    let r = copiar(c.retorno);
    if s.hijos.largo() == 0 {
        if r.largo() > 0 {
            error(c, m, s.linea, $"esta funcion devuelve `{r}` y el `return` esta vacio");
        }
        return;
    }
    if presta_tipo(m, r) {
        comprobar_vista_devuelta(c, m, s);
    }
    c.en_retorno = c.en_retorno + 1;
    var tipo = T.ninguno();
    if s.hijos[0].clase == Clase.Variable {
        tipo = variable(c, m, tipos, s.hijos[0], true, true);
    } else {
        tipo = comprobar_expresion(c, m, tipos, s.hijos[0], r, true);
    }
    c.en_retorno = c.en_retorno - 1;
    if r.largo() == 0 {
        error(c, m, s.linea, "esta funcion no declara tipo de retorno");
    } else if T.conocido(tipo) && !encaja(r, T.escribir_tipo(tipo)) {
        error(c, m, s.linea, $"esta funcion devuelve `{r}` y aqui se devuelve `{T.escribir_tipo(tipo)}`");
    }
    return;
}

fn sentencia_falla(c: mut Comprobacion, m: &Mundo, s: &P.Nodo) {
    if !c.falible {
        error(c, m, s.linea, "esta funcion no esta declarada con `!`, asi que no puede fallar; ponle `!` despues del tipo de retorno");
    }
    return;
}

fn sentencia_expresion(c: mut Comprobacion, m: mut Mundo, tipos: &I.Contexto, s: &P.Nodo) {
    if s.hijos.largo() > 0 {
        let _t = comprobar_expresion(c, m, tipos, s.hijos[0], "", false);
        return;
    }
}

fn sentencia_otra(c: mut Comprobacion, m: &Mundo, s: &P.Nodo) {
    let clase = s.clase;
    if clase == Clase.Romper || clase == Clase.Continuar {
        if c.en_bucle == 0 {
            var palabra = nuevo("break");
            if clase == Clase.Continuar { palabra = nuevo("continue"); }
            error(c, m, s.linea, $"`{palabra}` solo tiene sentido dentro de un `for` o un `while`");
        }
        return;
    }
}

fn comprobar_vista_devuelta(c: mut Comprobacion, m: &Mundo, s: &P.Nodo) {
    let proc = procedencia_de(c, m, s.hijos[0]);
    if proc != "local" { return; }
    let duenio = origen_de(c, m, s.hijos[0]);
    var de_quien = vacio();
    var extra = nuevo("esa memoria muere al cerrar la funcion");
    if duenio.largo() > 0 {
        de_quien = $" de `{duenio}`";
        extra = $"`{duenio}` muere al cerrar la funcion";
    }
    error(c, m, s.linea, $"no se puede devolver una vista{de_quien}: {extra}. Una vista que sale de la funcion tiene que venir de un parametro `view` o de un literal; si quieres entregar el texto, devuelve un `str` con `nuevo(...)`");
}

// ------------------------------------------------------------------
// Una funcion, y el programa entero
// ------------------------------------------------------------------

struct Programa {
    arboles: list<P.Nodo>,
    modulos: list<str>,
    contextos: list<I.Contexto>,
    cierres: list<P.Nodo>,
    cierres_mod: list<usize>,
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
    if f.retorno.largo() > 0 && !almacenable(m, f.retorno) {
        error(c, m, f.linea, $"la funcion `{nombre}` devuelve el tipo `{f.retorno}`, que no se puede almacenar");
    }
    abrir_ambito(c);
    for p en f.params {
        if !almacenable(m, p.tipo) {
            error(c, m, f.linea, $"el parametro `{p.nombre}` usa el tipo `{p.tipo}`, que no se puede almacenar");
        }
        if prestado(p) && p.tipo == "view" {
            var marca = nuevo("&");
            if p.mutable { marca = nuevo("mut"); }
            error(c, m, f.linea, $"`{marca}` sobre `view` no tiene sentido: una vista ya es un prestamo. Quita el `{marca}`");
        }
        let i = declarar_simbolo(c, m, f.linea, p.nombre, p.tipo, p.mutable);
        c.simbolos[i].prestado = prestado(p);
        c.simbolos[i].es_param = true;
        let h = c.simbolos[i].historia;
        c.historia[h].es_param = true;
        if p.tipo == "view" || (!prestado(p) && es_prestado_st(m, p.tipo)) {
            c.simbolos[i].procedencia = nuevo("parametro");
        }
    }
    var sale = false;
    // Una copia de generica o una clausura se comprueban desde dentro de una
    // sentencia de otra funcion: sus sentencias no son las de esta.
    let base_antes = c.base;
    c.base = c.hondura;
    for h en d.hijos {
        if h.clase == Clase.Bloque {
            comprobar_bloque(c, m, tipos, h);
            sale = siempre_sale(h);
        }
    }
    c.base = base_antes;
    cerrar_ambito(c);
    // Prometer un valor y no devolverlo deja al que llama leyendo basura.
    if f.retorno.largo() > 0 && f.retorno != "()" && nombre != "main"
    && !sale {
        error(c, m, f.linea, $"`{nombre}` promete devolver `{f.retorno}` pero hay un camino que llega al final sin `return`");
    }
    avisar_sin_usar(c, m, f);
    c.informe.anadir(informe_de(m, f, c.historia));
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
    while i < t.largo() {
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
        r.empujar(" ");
        n = n + 1;
    }
    return r;
}

fn sin_espacio_final(t: view) -> str {
    var fin = t.largo();
    while fin > 0 && (byte(t, fin - 1) == 32 || byte(t, fin - 1) == 10) { fin = fin - 1; }
    return nuevo(rebanar(t, 0, fin));
}

// Un tipo como lo escribe el original. Los nombres que chocan con C ya
// llegan cambiados en el arbol, como alli.
fn tipo_informe(t: view) -> str { return I.nombre_resuelto(t); }

fn firma_legible(f: &Funcion) -> str {
    var partes = vacio();
    var i = 0;
    while i < f.params.largo() {
        if i > 0 { partes.empujar(", "); }
        let t = tipo_informe(f.params[i].tipo);
        let pn = vista(f.params[i].nombre);
        if f.params[i].mutable { let x = $"{pn}: mut {t}"; partes.empujar(x); }
        else if f.params[i].compartido { let x = $"{pn}: &{t}"; partes.empujar(x); }
        else { let x = $"{pn}: {t}"; partes.empujar(x); }
        i = i + 1;
    }
    var firma = $"fn {f.nombre}({partes})";
    if f.retorno.largo() > 0 && f.retorno != "()" {
        let r = tipo_informe(f.retorno);
        firma.empujar(" -> ");
        firma.empujar(r);
    }
    if f.falible { firma.empujar(" !"); }
    return firma;
}

// Que es la variable.
fn papel_de(m: &Mundo, s: &Simbolo) -> str {
    if s.prestado {
        if s.mutable { return nuevo("prestado, modificable"); }
        return nuevo("prestado para leer");
    }
    if s.tipo == "view" { return nuevo("vista"); }
    if posee_memoria(m, s.tipo) {
        if s.es_param { return nuevo("DUEÑA (recibida)"); }
        return nuevo("DUEÑA");
    }
    return nuevo("valor");
}

// Que pasa con su memoria.
fn destino_de(m: &Mundo, s: &Simbolo) -> str {
    if s.tipo == "view" {
        var origen = vacio();
        if s.origen.largo() > 0 {
            let o = copiar(s.origen);
            origen = $" de `{o}`";
        }
        if s.procedencia == "estatico" {
            return nuevo("apunta a un literal: vive todo el programa");
        }
        if s.procedencia == "parametro" {
            if origen.largo() == 0 { origen = nuevo(" de un parametro"); }
            return $"presta{origen}: la memoria es de quien llama";
        }
        return $"presta{origen}: muere con el";
    }
    if s.prestado { return nuevo("no se libera aqui: es de quien llama"); }
    if !posee_memoria(m, s.tipo) { return vacio(); }
    if s.entregada_en > 0 {
        return $"se entrega en la linea {s.entregada_en} (return)";
    }
    if s.movida {
        var a = vacio();
        if s.movida_a.largo() > 0 {
            let destino_c = copiar(s.movida_a);
            a = $" a `{destino_c}`";
        }
        return $"se mueve{a} en la linea {s.movida_en}; lleva bandera por si el programa sale antes";
    }
    if T.es_arreglo(s.tipo) {
        let e = T.elemento(s.tipo);
        if posee_memoria(m, e) {
            let n = T.cuantos_del_arreglo(s.tipo);
            return $"se libera sola al cerrar su bloque, elemento por elemento ({n})";
        }
    }
    return nuevo("se libera sola al cerrar su bloque");
}

fn informe_de(m: &Mundo, f: &Funcion, historia: &list<Simbolo>) -> str {
    let firma = firma_legible(f);
    var t = $"  {firma}\n";
    if f.falible && f.nombre == "main" {
        t.empujar("      puede fallar: si falla, el programa imprime `error: <motivo>` y sale con codigo 1\n");
    } else if f.falible {
        t.empujar("      puede fallar: quien la llame tiene que usar `try` o `sino`\n");
    }
    if historia.largo() == 0 {
        t.empujar("      (sin variables)\n\n");
        return t;
    }
    var an = 0;
    var at = 0;
    var ap = 0;
    for s en historia {
        let nt = tipo_informe(s.tipo);
        let pa = papel_de(m, s);
        let nc = copiar(s.nombre);
        if ancho_de(nc) > an { an = ancho_de(nc); }
        if ancho_de(nt) > at { at = ancho_de(nt); }
        if ancho_de(pa) > ap { ap = ancho_de(pa); }
    }
    var duenias = 0;
    var solas = 0;
    var entregadas = 0;
    var movidas = 0;
    for s en historia {
        var marca = nuevo("let");
        if s.mutable { marca = nuevo("var"); }
        if s.es_param { marca = nuevo("arg"); }
        let nt = tipo_informe(s.tipo);
        let pa = papel_de(m, s);
        let de = destino_de(m, s);
        let nc = copiar(s.nombre);
        let c1 = a_la_izquierda(nc, an);
        let c2 = a_la_izquierda(nt, at);
        let c3 = a_la_izquierda(pa, ap);
        let fila = $"      {marca} {c1}  {c2}  {c3}  {de}";
        t.empujar(sin_espacio_final(fila));
        t.empujar("\n");
        if posee_memoria(m, s.tipo) && !s.prestado {
            duenias = duenias + 1;
            if !s.movida && s.entregada_en == 0 { solas = solas + 1; }
            if s.entregada_en > 0 { entregadas = entregadas + 1; }
            if s.movida { movidas = movidas + 1; }
        }
    }
    if duenias > 0 {
        var trozos: list<str> = [];
        if solas > 0 {
            if solas > 1 { trozos.anadir($"{solas} se liberan solas"); }
            else { trozos.anadir($"{solas} se libera sola"); }
        }
        if entregadas > 0 {
            if entregadas > 1 { trozos.anadir($"{entregadas} se entregan"); }
            else { trozos.anadir($"{entregadas} se entrega"); }
        }
        if movidas > 0 {
            if movidas > 1 { trozos.anadir($"{movidas} se mueven"); }
            else { trozos.anadir($"{movidas} se mueve"); }
        }
        var junto = vacio();
        var i = 0;
        while i < trozos.largo() {
            if i > 0 { junto.empujar(", "); }
            junto.empujar(trozos[i]);
            i = i + 1;
        }
        let linea = $"      {duenias} valor(es) con memoria propia: {junto}\n";
        t.empujar(linea);
    }
    t.empujar("\n");
    return t;
}

// El informe entero: los structs, y cada funcion comprobada en su orden.
fn explicacion(m: &Mundo, informe: &list<str>, archivo: view) -> str {
    var t = $"{archivo}\n\n";
    if m.orden_structs.largo() == 0 && informe.largo() == 0 {
        t.empujar("  (nada que explicar)");
        return t;
    }
    var k = 0;
    while k < m.orden_structs.largo() {
        let nombre_c = copiar(m.orden_structs[k]);
        let nombre = vista(nombre_c);
        let aqui = vista(m.tipo_de_struct[k]);
        let posee = posee_memoria(m, aqui);
        t.empujar("  struct ");
        t.empujar(nombre);
        if posee { t.empujar("   es DUEÑO: contiene memoria que hay que liberar\n"); }
        else { t.empujar("   solo datos: nada que liberar\n"); }
        let ns = campos_nombres(m, aqui);
        let ts = campos_tipos(m, aqui);
        var i = 0;
        while i < ns.largo() && i < ts.largo() {
            let tc = tipo_informe(ts[i]);
            var marca = vacio();
            if posee_memoria(m, ts[i]) { marca = nuevo("  <- duenio"); }
            let campo_c = copiar(ns[i]);
            let linea = $"      {campo_c}: {tc}{marca}\n";
            t.empujar(linea);
            i = i + 1;
        }
        if posee {
            let linea = $"      el compilador genera `ss_drop_{nombre}` y lo llama donde haga falta\n";
            t.empujar(linea);
        }
        t.empujar("\n");
        k = k + 1;
    }
    for x en informe { t.empujar(x); }
    var limpio = sin_espacio_final(t);
    limpio.empujar("\n");
    return limpio;
}

// Un `_` delante silencia el aviso, como en Rust: dice que es a proposito.
fn avisar_sin_usar(c: mut Comprobacion, m: &Mundo, f: &Funcion) {
    let historia = copiar(c.historia);
    let nombre_f = vista(f.nombre);
    for s en historia {
        let n = vista(s.nombre);
        let escrito_n = G.escrito(n);
        if empieza_con(escrito_n, "_") { continue; }
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

// Lo que va a un lado y otro del borde con C: numeros, `bool`, `str` y
// `buffer` de entrada; numeros, `bool`, `cadena_c` y nada de salida. Un
// `buffer` es un `str` del que C ademas puede escribir, y solo vale ahi.
fn comprobar_externa(c: mut Comprobacion, m: &Mundo, f: &Funcion) {
    let nombre = vista(f.nombre);
    for p en f.params {
        let t = vista(p.tipo);
        if prestado(p) || T.es_referencia(t) {
            error(c, m, f.linea, $"`{nombre}` es de C: sus parametros no se prestan ni se mutan, se pasan por valor");
        } else if t == "view" {
            error(c, m, f.linea, $"`{nombre}.{p.nombre}` es una `view`, y una vista puede apuntar a la mitad de una cadena: no acaba en `\\0` y C leeria de mas. Pasa un `str`, que si acaba, o haz `nuevo(v)` antes");
        } else if !es_numerico(t) && t != "bool" && t != "str" && t != "buffer" {
            error(c, m, f.linea, $"`{nombre}.{p.nombre}` es `{t}`, y eso no significa lo mismo en C. En el borde caben los numeros, `bool`, `str` y `buffer`; para lo demas, envuelvelo en una funcion de C tuya");
        }
    }
    var r = copiar(f.retorno);
    if r.largo() == 0 { r = nuevo("()"); }
    let rv = vista(r);
    if !es_numerico(rv) && rv != "bool" && rv != "cadena_c" && rv != "()" {
        if rv == "str" {
            error(c, m, f.linea, $"`{nombre}` devuelve `str`, y un `str` es de Tcode: C no puede fabricar uno. Si devuelve un `char*` que no hay que liberar, dilo con `cadena_c` y Tcode lo copia");
        } else {
            error(c, m, f.linea, $"`{nombre}` devuelve `{r}`, y eso no significa lo mismo en C. En el borde caben los numeros, `bool`, `cadena_c` y nada");
        }
    }
}

// Los campos de un `struct`: nombres y tipos, sin el alias del modulo.
fn campo_de(texto: view, nombre: mut str, tipo: mut str) {
    var j = 0;
    while j < texto.largo() && byte(texto, j) != 58 { j = j + 1; }
    nombre = nuevo(recortar(rebanar(texto, 0, j)));
    tipo = T.sin_alias_tipo(recortar(rebanar(texto, j + 1, texto.largo())));
}

// El programa entero, con las clausuras ya numeradas: cada una es su nodo
// `fn ss_cierre_N` y el modulo donde se escribio. Devuelve los errores como
// `archivo:linea: mensaje`, en el mismo orden que el original.
// Lo que sale de comprobar: los errores, y si no los hay, las clausuras que
// nacieron y donde va cada una.
struct Revision {
    errores: list<str>,
    avisos: list<str>,
    // Lo que dice `--explicar`.
    explicacion: str,
    cierres: list<P.Nodo>,
    cierres_mod: list<usize>,
    numeracion: map<str, usize>,
    // Los campos sacados de su struct: `archivo\tlinea\tp.a.b`.
    sacados: list<str>,
    // Los nodos que el comprobador leyo en vez de mover: `dueno#id`, el
    // mismo canal por el que viaja la decision hasta el generador.
    lecturas: list<str>,
    // Y los que movio en vez de leer: el mismo canal, la otra cara.
    movidas: list<str>,
    // Y los que presto: el mismo canal, el tercer valor. `&T`/`mut T`, que ni
    // se leen ni se mueven.
    prestamos: list<str>,
    // El tipo de cada expresion, por modulo, para el generador.
    anotados: list<map<str, T.Tipo>>,
    // Las copias y las clausuras, en el orden en que se escriben.
    orden_copias: list<str>,
    // Las copias de structs genericos, en el orden en que nacen: tambien
    // las que se deducen de un literal, que no estan escritas en ningun sitio.
    structs_aplicados: list<str>,
    // Todos los structs con su nombre de C —declarados, copias y los de las
    // clausuras— en el orden en que nacen, que es el orden en que se escriben.
    orden_structs: list<str>,
}

fn comprobar_programa(arboles: &list<P.Nodo>, modulos: &list<str>,
    contextos: &list<I.Contexto>) -> Revision {
    var m = Mundo { funciones: [], indice: [], st_tipos: [], st_nombres: [],
        st_params: [], en_variantes: [], en_formas: [], bonitos: [],
        cierres: [], cierres_mod: [], n_cierres: 0, cierres_mut: [], numeracion: [],
        arboles: copiar(arboles), modulos: copiar(modulos),
        contextos: copiar(contextos), copias: [], orden_structs: [], tipo_de_struct: [],
        anotados: [], orden_copias: [], lecturas: [], movidas: [], prestamos: [] };
    for _a en arboles {
        let vacio_m: map<str, T.Tipo> = [];
        m.anotados.anadir(vacio_m);
    }
    var c = estado("", 0);

    registrar_funciones(m, arboles, modulos, contextos);
    registrar_enums(c, m, arboles, modulos);

    registrar_structs(c, m, arboles, modulos);
    validar_tipos_de_campos(c, m, arboles, modulos);
    validar_campos(c, m, arboles, modulos);

    validar_formas(c, m, arboles, modulos);

    validar_tipos_de_funciones(c, m, arboles);

    comprobar_borde_c(c, m);

    comprobar_nombres(c, m);

    comprobar_cada_funcion(c, m, arboles, contextos);
    comprobar_restricciones(c, m);
    let principal = vista(modulos[modulos.largo() - 1]);
    var aplicados: list<str> = [];
    for t en m.tipo_de_struct {
        if contiene(t, "<") { aplicados.anadir(copiar(t)); }
    }
    return Revision { errores: copiar(c.errores), avisos: copiar(c.avisos),
        explicacion: explicacion(m, c.informe, principal),
        cierres: copiar(m.cierres),
        cierres_mod: copiar(m.cierres_mod), numeracion: copiar(m.numeracion),
        sacados: copiar(c.sacados), lecturas: copiar(m.lecturas),
        movidas: copiar(m.movidas),
        prestamos: copiar(m.prestamos),
        anotados: copiar(m.anotados),
        orden_copias: copiar(m.orden_copias), structs_aplicados: aplicados,
        orden_structs: copiar(m.orden_structs) };
}
fn registrar_funciones(m: mut Mundo, arboles: &list<P.Nodo>, modulos: &list<str>,
    contextos: &list<I.Contexto>) {
    // Primero se registra todo lo que hay.
    var k = 0;
    while k < arboles.largo() {
        let ruta = vista(modulos[k]);
        var j = 0;
        while j < arboles[k].hijos.largo() {
            let clase = arboles[k].hijos[j].clase;
            let texto_d = vista(arboles[k].hijos[j].texto);
            if clase == Clase.Fn {
                let nombre = resolver_nombre(contextos[k], texto_d);
                if !igual(nombre, texto_d) {
                    poner(m.bonitos, vista(nombre), nuevo(texto_d));
                }
                let f = funcion_de(arboles[k].hijos[j], nombre, ruta, k, j, false);
                if !tiene(m.indice, nombre) {
                    poner(m.indice, vista(nombre), m.funciones.largo());
                }
                m.funciones.anadir(f);
            }
            if clase == Clase.Externo {
                for h en arboles[k].hijos[j].hijos {
                    if h.clase != Clase.Fn { continue; }
                    let f = funcion_de(h, h.texto, ruta, k, j, true);
                    if !tiene(m.indice, h.texto) {
                        poner(m.indice, vista(h.texto), m.funciones.largo());
                    }
                    m.funciones.anadir(f);
                }
            }
            j = j + 1;
        }
        k = k + 1;
    }
}

fn registrar_enums(c: mut Comprobacion, m: mut Mundo, arboles: &list<P.Nodo>, modulos: &list<str>) {
    // Los enums, antes que los structs: un struct puede llevar uno.
    var en_donde: map<str, str> = [];
    var k = 0;
    while k < arboles.largo() {
        c.archivo = copiar(modulos[k]);
        for d en arboles[k].hijos {
            if d.clase != Clase.Enum { continue; }
            let nombre = vista(d.texto);
            if tiene(en_donde, nombre) {
                let donde = obtener(en_donde, nombre) sino "";
                error(c, m, d.linea, $"`{nombre}` ya esta definido en {donde}");
            }
            poner(en_donde, nombre, $"{modulos[k]}:{d.linea}");
            var formas: list<str> = [];
            for v en d.hijos {
                if v.clase != Clase.Variante { continue; }
                formas.anadir(copiar(v.texto));
                var lleva: list<str> = [];
                for x en v.hijos {
                    if x.clase == Clase.Lleva { lleva.anadir(T.sin_alias_tipo(x.texto)); }
                }
                poner(m.en_formas, $"{nombre}.{v.texto}", T.leer_tipos(lleva));
            }
            poner(m.en_variantes, nombre, formas);
        }
        k = k + 1;
    }
}

fn registrar_structs(c: mut Comprobacion, m: mut Mundo, arboles: &list<P.Nodo>, modulos: &list<str>) {
    // Los structs.
    var st_donde: map<str, str> = [];
    var k = 0;
    while k < arboles.largo() {
        c.archivo = copiar(modulos[k]);
        for d en arboles[k].hijos {
            if d.clase != Clase.Struct { continue; }
            let nombre = vista(d.texto);
            if tiene(st_donde, nombre) {
                let donde = obtener(st_donde, nombre) sino "";
                error(c, m, d.linea, $"el struct `{nombre}` ya esta definido en {donde}");
            }
            poner(st_donde, nombre, $"{modulos[k]}:{d.linea}");
            var ns: list<str> = [];
            var ts: list<str> = [];
            var ps: list<str> = [];
            for h en d.hijos {
                if h.clase == Clase.TipoParam { ps.anadir(copiar(h.texto)); }
                if h.clase == Clase.CampoDef {
                    var cn = vacio();
                    var ct = vacio();
                    campo_de(h.texto, cn, ct);
                    ns.anadir(cn);
                    ts.anadir(ct);
                }
            }
            poner(m.st_nombres, nombre, ns);
            poner(m.st_tipos, nombre, T.leer_tipos(ts));
            if ps.largo() > 0 { poner(m.st_params, nombre, ps); }
            else if !esta_entre(m.orden_structs, nombre) {
                m.orden_structs.anadir(nuevo(nombre));
                m.tipo_de_struct.anadir(nuevo(nombre));
            }
        }
        k = k + 1;
    }
}

fn validar_tipos_de_campos(c: mut Comprobacion, m: mut Mundo, arboles: &list<P.Nodo>, modulos: &list<str>) {
    var k = 0;
    while k < arboles.largo() {
        c.archivo = copiar(modulos[k]);
        for d en arboles[k].hijos {
            if d.clase != Clase.Struct { continue; }
            var generico_r = false;
            for h en d.hijos {
                if h.clase == Clase.TipoParam { generico_r = true; }
            }
            if generico_r { continue; }
            for h en d.hijos {
                if h.clase != Clase.CampoDef { continue; }
                var cn = vacio();
                var ct = vacio();
                campo_de(h.texto, cn, ct);
                validar_tipo(c, m, d.linea, ct);
            }
        }
        k = k + 1;
    }
}

fn validar_campos(c: mut Comprobacion, m: &Mundo, arboles: &list<P.Nodo>, modulos: &list<str>) {
    var k = 0;
    while k < arboles.largo() {
        c.archivo = copiar(modulos[k]);
        for d en arboles[k].hijos {
            if d.clase != Clase.Struct { continue; }
            var generico = false;
            for h en d.hijos {
                if h.clase == Clase.TipoParam { generico = true; }
            }
            if generico { continue; }
            let nombre = vista(d.texto);
            var vistos_c: list<str> = [];
            var tipos_c: list<str> = [];
            for h en d.hijos {
                if h.clase != Clase.CampoDef { continue; }
                var cn = vacio();
                var ct = vacio();
                campo_de(h.texto, cn, ct);
                if esta_entre(vistos_c, cn) {
                    error(c, m, d.linea, $"`{nombre}` tiene dos campos llamados `{cn}`");
                }
                vistos_c.anadir(copiar(cn));
                tipos_c.anadir(copiar(ct));
                // Un campo `view` hace del struct uno que presta: se le trata
                // como a una vista, sin anotar vidas en el tipo.
                if !almacenable(m, ct) {
                    error(c, m, d.linea, $"`{nombre}.{cn}` usa el tipo `{ct}`, que no existe");
                }
                // Un `&T` guardado no dice de quien presta ni cuanto vive: el
                // struct no lo sigue, y en C quedaba el valor copiado sin
                // dueno (dos liberaciones). Prestar un campo es `view`.
                if T.es_referencia(ct) {
                    error(c, m, d.linea, $"`{nombre}.{cn}` es `{ct}`, un prestamo: un campo no guarda `&T`, porque nadie sabria cuanto vive. Si el struct presta de lo que le pongan, el campo es `view`; si el campo es suyo, quita el `&`");
                }
            }
            var ciclo = false;
            for t en tipos_c {
                var vistos: list<str> = [];
                if se_contiene(m, t, nombre, vistos) { ciclo = true; }
            }
            if ciclo {
                error(c, m, d.linea, $"`{nombre}` se contiene a si mismo: no tiene un tamaño finito");
            }
        }
        k = k + 1;
    }
}

fn validar_formas(c: mut Comprobacion, m: mut Mundo, arboles: &list<P.Nodo>, modulos: &list<str>) {
    // Lo que lleva cada forma. Va despues de los structs: una forma puede
    // llevar uno, y antes no existia.
    var k = 0;
    while k < arboles.largo() {
        c.archivo = copiar(modulos[k]);
        for d en arboles[k].hijos {
            if d.clase != Clase.Enum { continue; }
            let nombre = vista(d.texto);
            for v en d.hijos {
                if v.clase != Clase.Variante { continue; }
                for x en v.hijos {
                    if x.clase != Clase.Lleva { continue; }
                    let t = T.sin_alias_tipo(x.texto);
                    validar_tipo(c, m, d.linea, t);
                    if !almacenable(m, t) {
                        error(c, m, d.linea, $"`{nombre}.{v.texto}` lleva un `{t}`, que no es un tipo");
                    } else if t == "view" || T.es_referencia(t) {
                        error_enum_prestado(c, m, d.linea, nombre, v.texto, t);
                    }
                    var vistos: list<str> = [];
                    if se_contiene(m, t, nombre, vistos) {
                        error(c, m, d.linea, $"`{nombre}.{v.texto}` contiene un `{nombre}`: el tamaño no seria finito. Metelo en una `list`, que guarda un puntero");
                    }
                    // Tampoco un struct que presta.
                    if es_prestado_st(m, t) {
                        error_enum_prestado(c, m, d.linea, nombre, v.texto, t);
                    }
                }
            }
        }
        k = k + 1;
    }
}

fn validar_tipos_de_funciones(c: mut Comprobacion, m: mut Mundo, arboles: &list<P.Nodo>) {
    // Los tipos escritos en cada funcion que no es generica.
    var e = 0;
    while e < m.funciones.largo() {
        if !m.funciones[e].de_cierre && !tiene_sueltos(m.funciones[e]) {
            c.archivo = copiar(m.funciones[e].archivo);
            let km = m.funciones[e].modulo;
            let kp = m.funciones[e].posicion;
            if m.funciones[e].externa {
                let f = copiar(m.funciones[e]);
                for p en f.params { validar_tipo(c, m, f.linea, p.tipo); }
                validar_tipo(c, m, f.linea, f.retorno);
            } else {
                validar_en_funcion(c, m, arboles[km].hijos[kp]);
            }
        }
        e = e + 1;
    }
}

fn comprobar_borde_c(c: mut Comprobacion, m: &Mundo) {
    // El borde con C.
    var e = 0;
    while e < m.funciones.largo() {
        if m.funciones[e].externa {
            c.archivo = copiar(m.funciones[e].archivo);
            let f: &Funcion = m.funciones[e];
            comprobar_externa(c, m, f);
        }
        e = e + 1;
    }
}

fn comprobar_nombres(c: mut Comprobacion, m: &Mundo) {
    // Nombres: ni de una interna, ni repetidos.
    var vistas: map<str, str> = [];
    var e = 0;
    while e < m.funciones.largo() {
        if !m.funciones[e].de_cierre {
            c.archivo = copiar(m.funciones[e].archivo);
            let nombre = copiar(m.funciones[e].nombre);
            let linea = m.funciones[e].linea;
            if nombra_interna(nombre) {
                error(c, m, linea, $"`{nombre}` es una funcion interna del lenguaje: una funcion propia con ese nombre no se llamaria nunca. Ponle otro nombre");
            }
            if tiene(vistas, nombre) {
                let donde = obtener(vistas, nombre) sino "";
                error(c, m, linea, $"la funcion `{nombre}` ya esta definida en {donde}");
            } else {
                poner(vistas, vista(nombre), $"{m.funciones[e].archivo}:{linea}");
            }
        }
        e = e + 1;
    }
}

fn comprobar_cada_funcion(c: mut Comprobacion, m: mut Mundo, arboles: &list<P.Nodo>,
    contextos: &list<I.Contexto>) {
    // Y cada funcion, en orden. Las genericas se comprueban en sus copias,
    // que esta capa todavia no mira; las de C no tienen cuerpo.
    var e = 0;
    while e < m.funciones.largo() {
        let f = copiar(m.funciones[e]);
        if !f.de_cierre && !f.externa && !tiene_sueltos(f) {
            c.archivo = copiar(f.archivo);
            c.modulo = f.modulo;
            let nodo = copiar(arboles[f.modulo].hijos[f.posicion]);
            comprobar_funcion(c, m, contextos[f.modulo], e, nodo, f.nombre);
        }
        e = e + 1;
    }
}
