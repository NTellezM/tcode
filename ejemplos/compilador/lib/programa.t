// lib/programa.t — lo que comparten los drivers del generador en Tcode.
//
// Preparar un archivo (sus firmas, las de los modulos que usa, los nombres
// que el cargador renombra) y generar una funcion entera. Lo usan
// `cuerpos.t`, que compara funcion a funcion, y `tcodec.t`, que escribe el
// programa entero.

use "generar.t" como G;
use "tipar.t" como I;
use "tipos.t" como T;
use "../../lexer/lib/lexico.t";
use "../../lexer/lib/sintaxis.t" como P;
use "std/texto";
use "std/lista";
use "../../lexer/lib/clase.t";

fn nombre_de(texto: view) -> str {
    var i = 0;
    while i < texto.largo() {
        if byte(texto, i) == 58 { return nuevo(rebanar(texto, 0, i)); }
        i = i + 1;
    }
    return nuevo(texto);
}

fn tras_dos_puntos(texto: view) -> str {
    var i = 0;
    while i + 1 < texto.largo() {
        if byte(texto, i) == 58 {
            if byte(texto, i + 1) == 32 {
                return nuevo(recortar(rebanar(texto, i + 2, texto.largo())));
            }
        }
        i = i + 1;
    }
    return vacio();
}

// El tipo de `nombre: tipo`, sin marca de prestamo y sin alias de modulo.
fn tipo_pelado(marcado: view) -> str {
    let t = tras_dos_puntos(marcado);
    if empieza_con(t, "mut ") {
        return T.sin_alias_tipo(rebanar(t, 4, t.largo()));
    }
    if T.es_referencia(t) { return T.sin_alias_tipo(T.apuntado(t)); }
    return T.sin_alias_tipo(t);
}

fn marca_de(marcado: view) -> str {
    let t = tras_dos_puntos(marcado);
    if empieza_con(t, "mut ") { return nuevo("mut "); }
    if T.es_referencia_mutable(t) { return nuevo("&mut "); }
    if T.es_referencia(t) { return nuevo("&"); }
    return vacio();
}

fn es_generica(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if h.clase == Clase.TipoParam { return true; }
    }
    return false;
}

fn recoger_firmas(n: &P.Nodo, c: mut I.Contexto) {
    // Los campos de cada struct: hacen falta para saber si un tipo posee
    // memoria, y de eso depende si el elemento de un `for` se presta o se
    // copia. Un struct de otro modulo se llama igual en C, asi que no lleva
    // alias.
    match n.clase {
        Clase.Struct -> {
            var suyos: list<str> = [];
            var como_se_llaman: list<str> = [];
            for h en n.hijos {
                if h.clase == Clase.CampoDef {
                    como_se_llaman.anadir(nombre_de(h.texto));
                    suyos.anadir(tipo_pelado(h.texto));
                }
            }
            poner(c.campos, vista(n.texto), T.leer_tipos(suyos));
            poner(c.nombres, vista(n.texto), como_se_llaman);
            var sueltos_st: list<str> = [];
            for h en n.hijos {
                if h.clase == Clase.TipoParam { sueltos_st.anadir(nuevo(h.texto)); }
            }
            if sueltos_st.largo() > 0 { poner(c.struct_params, vista(n.texto), sueltos_st); }
        }
        Clase.Enum -> {
            var cuales: list<str> = [];
            for h en n.hijos {
                if h.clase == Clase.Variante {
                    cuales.anadir(nuevo(h.texto));
                    var lleva: list<str> = [];
                    for x en h.hijos {
                        // Sin alias, como los nombres de los tipos:
                        // `Con(H.Nombre)` lleva un `Nombre`.
                        if x.clase == Clase.Lleva {
                            lleva.anadir(T.sin_alias_tipo(x.texto));
                        }
                    }
                    var clave = nuevo(n.texto);
                    clave.empujar(".");
                    clave.empujar(h.texto);
                    poner(c.formas, vista(clave), T.leer_tipos(lleva));
                }
            }
            poner(c.variantes, vista(n.texto), cuales);
        }
        Clase.Fn -> {
            var retorno = vacio();
            var es_de_c = false;
            var sueltos: list<str> = [];
            var tipos_param: list<str> = [];
            var marcados: list<str> = [];
            for h en n.hijos {
                if h.clase == Clase.RetornoTipo {
                    retorno = T.sin_alias_tipo(h.texto);
                }
                // Una firma de `externo` no tiene cuerpo, y `cadena_c` solo
                // existe en el borde: lo que ve Tcode es un `str` suyo.
                if h.clase == Clase.Externa { es_de_c = true; }
                if h.clase == Clase.TipoParam {
                    sueltos.anadir(nuevo(h.texto));
                }
                if h.clase == Clase.Param {
                    tipos_param.anadir(tipo_pelado(h.texto));
                    marcados.anadir(marca_de(h.texto));
                }
            }
            if es_de_c {
                // 2 si devuelve `cadena_c`: la llamada se queda una copia.
                if retorno == "cadena_c" {
                    poner(c.externas, vista(n.texto), 2);
                    retorno = nuevo("str");
                } else {
                    poner(c.externas, vista(n.texto), 1);
                }
                // Una funcion de C presta lo que recibe: no se queda con nada.
                var prestados: list<str> = [];
                for _m en marcados { prestados.anadir(nuevo("&")); }
                marcados = prestados;
            }
            // Si un modulo usado ya declaraba este nombre, el cargador de verdad
            // renombra los dos, y esta capa no sabe a que: no se emite la llamada.
            if tiene(c.retornos, n.texto) {
                poner(c.repetidas, vista(n.texto), 1);
            }
            poner(c.retornos, vista(n.texto), T.leer_tipo(retorno));
            poner(c.params, vista(n.texto), T.leer_tipos(tipos_param));
            poner(c.params_marcados, vista(n.texto), marcados);
            if sueltos.largo() > 0 { poner(c.tipo_params, vista(n.texto), sueltos); }
        }
        _ -> { }
    }
    for h en n.hijos { recoger_firmas(h, c); }
}

// Las firmas de otro modulo se apuntan dos veces: con su nombre a secas y
// con el alias que le puso quien lo usa (`I.tipo_de`), porque asi es como se
// escribe la llamada. Si el nombre a secas lo trae mas de un modulo, el
// cargador de verdad lo renombra y esta capa no sabe a que: se marca como
// repetido para no emitir una llamada al que no es.
fn recoger_de_modulo(m: &P.Usado, c: mut I.Contexto) {
    var suyas = I.contexto();
    recoger_firmas(m.arbol, suyas);
    // Los tipos de otro modulo se llaman igual en C: van tal cual.
    for st en claves(suyas.campos) {
        let cs = T.tipos_de_mapa(suyas.campos, vista(st)) sino [];
        poner(c.campos, vista(st), cs);
        let ns = I.lista_de(suyas.nombres, vista(st)) sino [];
        poner(c.nombres, vista(st), ns);
        if tiene(suyas.struct_params, st) {
            let sp = I.lista_de(suyas.struct_params, vista(st)) sino [];
            poner(c.struct_params, vista(st), sp);
        }
    }
    for en_ en claves(suyas.variantes) {
        let vs = I.lista_de(suyas.variantes, vista(en_)) sino [];
        for v en vs {
            var clave = nuevo(en_);
            clave.empujar(".");
            clave.empujar(v);
            let lleva = T.tipos_de_mapa(suyas.formas, vista(clave)) sino [];
            poner(c.formas, vista(clave), lleva);
        }
        poner(c.variantes, vista(en_), vs);
    }
    for nombre en claves(suyas.retornos) {
        if tiene(c.retornos, nombre) {
            poner(c.repetidas, vista(nombre), 1);
        }
        copiar_firma(suyas, c, nombre, nombre);
        if m.alias.largo() > 0 {
            var con_alias = copiar(m.alias);
            con_alias.empujar(".");
            con_alias.empujar(nombre);
            copiar_firma(suyas, c, nombre, con_alias);
        }
    }
}

fn copiar_firma(de: &I.Contexto, a: mut I.Contexto, suyo: view, como: view) {
    poner(a.retornos, como, T.tipo_de_mapa(de.retornos, suyo) sino T.ninguno());
    let ps = T.tipos_de_mapa(de.params, suyo) sino [];
    poner(a.params, como, ps);
    let ms = I.lista_de(de.params_marcados, suyo) sino [];
    poner(a.params_marcados, como, ms);
    if tiene(de.tipo_params, suyo) {
        let tp = I.lista_de(de.tipo_params, suyo) sino [];
        poner(a.tipo_params, como, tp);
    }
    if tiene(de.externas, suyo) {
        let marca_e = obtener(de.externas, suyo) sino 1;
        poner(a.externas, como, marca_e);
    }
}

// `ejemplos/compilador/tipar.t` -> `tipar`. Lo mismo que hace el cargador:
// el nombre del archivo sin extension, y lo que no sea letra, cifra o `_`
// pasa a ser `_`.
fn prefijo_de(ruta: view) -> str {
    var desde = 0;
    var i = 0;
    while i < ruta.largo() {
        if byte(ruta, i) == 47 { desde = i + 1; }
        i = i + 1;
    }
    var hasta = ruta.largo();
    var j = ruta.largo();
    while j > desde {
        j = j - 1;
        if byte(ruta, j) == 46 {
            hasta = j;
            break;
        }
    }
    var r = vacio();
    var k = desde;
    while k < hasta {
        let c = byte(ruta, k);
        if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57)
        || c == 95 {
            r.empujar(rebanar(ruta, k, k + 1));
        } else {
            r.empujar("_");
        }
        k = k + 1;
    }
    return r;
}

// `a/./b/../c.t` -> `a/c.t`. Sin preguntar al sistema: hace falta que dos
// caminos al mismo archivo den la misma cadena, para no cargarlo dos veces.
fn normalizar(ruta: view) -> str {
    var partes: list<str> = [];
    let absoluta = ruta.largo() > 0 && byte(ruta, 0) == 47;
    var desde = 0;
    var i = 0;
    while i <= ruta.largo() {
        if i == ruta.largo() || byte(ruta, i) == 47 {
            let trozo = rebanar(ruta, desde, i);
            if trozo.largo() > 0 && trozo != "." {
                var atras = false;
                if trozo == ".." && partes.largo() > 0 {
                    atras = partes[partes.largo() - 1] != "..";
                }
                if atras { partes = sin_la_ultima(partes); }
                else { partes.anadir(nuevo(trozo)); }
            }
            desde = i + 1;
        }
        i = i + 1;
    }
    var r = vacio();
    if absoluta { r.empujar("/"); }
    var primera = true;
    for x en partes {
        if !primera { r.empujar("/"); }
        primera = false;
        r.empujar(x);
    }
    return r;
}

fn sin_la_ultima(xs: &list<str>) -> list<str> {
    var quedan: list<str> = [];
    var i = 0;
    while i + 1 < xs.largo() {
        quedan.anadir(copiar(xs[i]));
        i = i + 1;
    }
    return quedan;
}

// El prefijo con el que se renombra lo que choca entre modulos. Basta el
// nombre del archivo, salvo que otro de los que declaran ese mismo nombre se
// llame igual (`x.t` y `lib/x.t`): entonces va la ruta entera, como en el
// cargador. `modulos` son solo los que declaran el nombre.
fn prefijo_unico(ruta: view, modulos: &list<str>) -> str {
    let base = prefijo_de(ruta);
    var iguales = 0;
    for m en modulos {
        let otra = prefijo_de(m);
        if igual(otra, base) { iguales = iguales + 1; }
    }
    if iguales <= 1 { return base; }
    // La ruta sin extension; `.oculto` no tiene, el punto es del nombre.
    var hasta = ruta.largo();
    var i = ruta.largo();
    while i > 0 {
        i = i - 1;
        let b = byte(ruta, i);
        if b == 47 { break; }
        if b == 46 {
            if i > 0 && byte(ruta, i - 1) != 47 { hasta = i; }
            break;
        }
    }
    var r = vacio();
    var k = 0;
    while k < hasta {
        let b = byte(ruta, k);
        k = k + 1;
        // Un caracter de UTF-8 es un solo `_`, no uno por byte.
        if b >= 128 && b < 192 { continue; }
        if T.es_de_nombre(b) { empujar_byte(r, b como u8); } else { r.empujar("_"); }
    }
    var desde = 0;
    var fin = r.largo();
    while desde < fin && byte(r, desde) == 95 { desde = desde + 1; }
    while fin > desde && byte(r, fin - 1) == 95 { fin = fin - 1; }
    return nuevo(rebanar(r, desde, fin));
}

// Lo que el generador cuenta para el archivo entero y no por funcion: los
// temporales, los indices de bucle y la ultima linea marcada siguen contando
// de una funcion a la siguiente, tambien entre modulos. Quien compara
// funcion a funcion empieza cada una de cero; quien escribe el archivo
// entero pasa la misma de una a otra.
struct Cuenta {
    temporal: usize,
    bucle: usize,
    // Las etiquetas de `goto`: se numeran en todo el archivo.
    etiquetas: usize,
    // Los campos que el comprobador vio sacar de su struct:
    // `archivo\tid del nodo\tp.a.b`.
    sacados: map<str, usize>,
    // Los nodos que el comprobador leyo en vez de mover: `dueno#id`, con el
    // dueno de la funcion que se escribe.
    lecturas: map<str, usize>,
    ultima_linea: usize,
    // Las copias de genericas que han pedido las funciones escritas.
    instancias: list<str>,
    // Los tipos que han pedido copiador, en el orden en que se pidieron.
    copias: list<str>,
    // Los arreglos que solo nombra un literal en algun cuerpo.
    arreglos: list<str>,
    // La funcion que se escribe, con el nombre que le da el comprobador: es
    // la clave de los tipos que dejo anotados. Vacio, no hay anotaciones y
    // los tipos se deducen.
    dueno: str,
    // Si la ultima funcion no se pudo escribir entera, el error que lo dice:
    // donde, y que no se supo escribir.
    fallo: str,
}

fn cuenta_nueva() -> Cuenta {
    return Cuenta { temporal: 0, bucle: 0, etiquetas: 0, sacados: [], lecturas: [],
        ultima_linea: 0,
        instancias: [],
        copias: [], arreglos: [], dueno: vacio(), fallo: vacio() };
}

// Lee y analiza un archivo, y deja en `tipos` todo lo que hace falta saber
// para generarlo: sus firmas, las de los modulos que usa y los nombres que
// el cargador renombra. Devuelve el arbol.
fn preparar(ruta: view, tipos: mut I.Contexto) -> P.Nodo ! {
    var error = vacio();
    let ninguno: map<str, usize> = [];
    var leidos = P.leidos();
    return try preparar_con_error(ruta, tipos, error, ninguno, ninguno, leidos, true);
}

// Lo mismo, y si el archivo no se puede leer como Tcode, `error` dice por que
// con las palabras del lexer y el parser de Python.
// `previos_st` y `previos_en` son los structs y enums de los modulos ya
// leidos: el cargador de Python se los da al parser, y con ellos `Caja { .. }`
// es un literal aunque `Caja` venga de un modulo que este no usa. En
// `leidos` va lo que ya se leyo de otros archivos en esta compilacion.
// Los tipos se escriben como los ve quien los escribe —`Q.Caja`,
// `list<H.Nombre>`, `Q.Sobre.Con`—, pero en el compilador se apuntan por su
// nombre: el alias de un modulo solo dice de donde viene, y dos modulos no
// declaran el mismo tipo. Se quita una vez, al leer —despues de mirar que
// cada archivo pide lo que usa, que eso si depende de como se escribio—, en
// cada sitio donde el arbol guarda un tipo, y ninguna capa de despues vuelve
// a ver un alias en un tipo. Las firmas que se recogen al leer ya se guardan
// sin el. Las llamadas lo conservan: dos modulos si pueden declarar la misma
// funcion, y `Q.hecho` dice cual.
fn quitar_alias_de_tipos(n: mut P.Nodo) {
    let cl = n.clase;
    if cl == Clase.CampoDef || cl == Clase.Param || cl == Clase.Declaracion {
        n.texto = tipo_sin_alias_tras_nombre(n.texto);
    } else if cl == Clase.RetornoTipo || cl == Clase.Lleva || cl == Clase.Conversion
    || cl == Clase.LiteralStruct {
        if contiene(n.texto, ".") { n.texto = T.sin_alias_tipo(n.texto); }
    } else if cl == Clase.EnumLit || cl == Clase.Brazo || cl == Clase.Patron {
        n.texto = forma_sin_alias(n.texto);
    }
    var i = 0;
    while i < n.hijos.largo() {
        quitar_alias_de_tipos(n.hijos[i]);
        i = i + 1;
    }
}

// `x: &Q.Caja` -> `x: &Caja`; `let w` se queda como esta.
fn tipo_sin_alias_tras_nombre(texto: view) -> str {
    let corte = indice_de(texto, ": ") sino texto.largo();
    if corte == texto.largo() { return nuevo(texto); }
    var r = nuevo(rebanar(texto, 0, corte + 2));
    r.empujar(T.sin_alias_tipo(rebanar(texto, corte + 2, texto.largo())));
    return r;
}

// `Q.Sobre.Con` -> `Sobre.Con`: con alias, una forma tiene tres partes.
fn forma_sin_alias(texto: view) -> str {
    var puntos = 0;
    var primero = texto.largo();
    var i = 0;
    while i < texto.largo() {
        if byte(texto, i) == 46 {
            if puntos == 0 { primero = i; }
            puntos = puntos + 1;
        }
        i = i + 1;
    }
    if puntos < 2 { return nuevo(texto); }
    return nuevo(rebanar(texto, primero + 1, texto.largo()));
}

fn preparar_con_error(ruta: view, tipos: mut I.Contexto, error: mut str,
    previos_st: &map<str, usize>, previos_en: &map<str, usize>,
    leidos: mut P.Leidos, transitivo: bool) -> P.Nodo ! {
    let fuente = try leer_archivo(ruta);
    let tokens = try tokens_de(fuente, ruta, error);
    var nombres = P.visibles_con(ruta, tokens, "struct", leidos);
    var formas = P.visibles_con(ruta, tokens, "enum", leidos);
    for x en claves(previos_st) { poner(nombres, vista(x), 1); }
    for x en claves(previos_en) { poner(formas, vista(x), 1); }
    // Lo que traen los modulos, antes de nada: los tokens pasan a ser del
    // `Estado` en cuanto se construye.
    var usados = P.modulos_usados_con(ruta, tokens, leidos);
    // Para manglear: las herramientas quieren ver tambien lo que llega de
    // segunda mano, como el cargador completo. La carga de firmas —`usados`—
    // sigue siendo la directa.
    var extra: list<P.Usado> = [];
    if transitivo { extra = P.modulos_usados_transitivos(ruta, tokens, leidos); }

    var estado = P.estado_de(tokens, ruta, nombres, formas);
    var arbol = P.programa(estado) sino P.rama(Clase.Vacio, 0);
    if estado.error.largo() > 0 || arbol.clase == Clase.Vacio {
        error = copiar(estado.error);
        fail "sintaxis";
    }

    // Lo que chocaria con C se renombra antes que nada, en este arbol y en
    // los de lo que usa, como hace el cargador. Salvo `main` y lo que
    // declara un `externo`: es el nombre de la funcion de C.
    let de_c = G.nombres_de_c();
    var intocables: list<str> = [nuevo("main")];
    G.externas_de(arbol, intocables);
    for u en usados { G.externas_de(u.arbol, intocables); }
    G.renombrar_para_c(arbol, de_c, intocables);
    var k = 0;
    while k < usados.largo() {
        G.renombrar_para_c(usados[k].arbol, de_c, intocables);
        k = k + 1;
    }
    for m en usados {
        recoger_de_modulo(m, tipos);
    }

    // Y las suyas, que mandan sobre las de fuera.
    recoger_firmas(arbol, tipos);
    // Un nombre propio que tambien trae un modulo usado no es ambiguo: desde
    // aqui es el propio. El cargador lo renombra con el nombre de este
    // archivo delante, y asi se llama en C.
    for d en arbol.hijos {
        if d.clase == Clase.Fn {
            var suyos: list<str> = [normalizar(ruta)];
            if transitivo {
                for u en extra {
                    if declara_fn(u.arbol, d.texto) { suyos.anadir(normalizar(u.ruta)); }
                }
            } else {
                for u en usados {
                    if declara_fn(u.arbol, d.texto) { suyos.anadir(normalizar(u.ruta)); }
                }
            }
            if suyos.largo() > 1 {
                var otro = prefijo_unico(ruta, suyos);
                otro.empujar("__");
                otro.empujar(d.texto);
                poner(tipos.renombradas, vista(d.texto), otro);
                quitar(tipos.repetidas, d.texto);
            }
        }
    }
    vistas_implicitas(arbol, tipos);
    return arbol;
}

fn declara_fn(arbol: &P.Nodo, nombre: view) -> bool {
    for d en arbol.hijos {
        if d.clase == Clase.Fn && igual(d.texto, nombre) { return true; }
    }
    return false;
}

// Una funcion entera en C, linea a linea: su `#line`, la firma, el cuerpo y,
// si es `main` falible, el envoltorio que informa del fallo al salir. Vacia
// si esta capa no la sabe generar entera: media funcion no vale nada, y la
// razon va por la salida de error.
fn generar_funcion(d: &P.Nodo, tipos: mut I.Contexto, ruta: view,
    cta: mut Cuenta) -> list<str> {
    let ninguna: list<str> = [];
    var puntos: map<str, usize> = [];
    var de_tipo: map<str, str> = [];
    var tipos_param: list<str> = [];
    var marcas: list<str> = [];
    var retorno = vacio();
    var falible = false;

    tipos.dueno = copiar(cta.dueno);
    I.abrir(tipos);
    for h en d.hijos {
        match h.clase {
            Clase.Param -> {
                let pn = nombre_de(h.texto);
                let pt = tipo_pelado(h.texto);
                let m = marca_de(h.texto);
                poner(de_tipo, vista(pn), copiar(pt));
                I.declarar(tipos, pn, pt);
                tipos_param.anadir(copiar(pt));
                var junto = copiar(pn);
                junto.empujar(": ");
                junto.empujar(m);
                marcas.anadir(junto);
                if m.largo() > 0 {
                    if m == "&" { poner(puntos, vista(pn), 2); }
                    else { poner(puntos, vista(pn), 1); }
                }
            }
            Clase.RetornoTipo -> {
                retorno = nuevo(h.texto);
            }
            Clase.Falible -> { falible = true; }
            _ -> { }
        }
    }
    let es_main = d.texto == "main";

    // Quien se entrega por algun camino lleva bandera. Se decide antes de
    // emitir nada, porque la bandera nace pegada a la declaracion.
    var movidas: list<str> = [];
    for h en d.hijos {
        if h.clase == Clase.Bloque {
            G.movidas_hondo(puntos, h, tipos, movidas);
        }
    }
    var banderas: map<str, usize> = [];
    for nm en movidas { poner(banderas, vista(nm), 1); }

    var sitio = G.Sitio { archivo: nuevo(ruta), tipos: de_tipo,
        punteros: puntos, pide_bandera: banderas,
        retorno: copiar(retorno), sacados: copiar(cta.sacados),
        lecturas: copiar(cta.lecturas) };
    var b = G.cuerpo();
    b.temporal = cta.temporal;
    b.bucle = cta.bucle;
    b.etiquetas = cta.etiquetas;
    // La directiva de la funcion va antes de la firma; aqui solo hay que
    // saber que ya esta puesta, para no repetirla si la primera sentencia
    // esta en la misma linea.
    b.ultima_linea = d.linea;
    G.abrir_bloque(b);
    // `main` recoge los argumentos antes que nada. La falible no: lo hace
    // su envoltorio.
    if es_main && !falible {
        G.emitir(b, "ss_lang_argc_ = argc;");
        G.emitir(b, "ss_lang_argv_ = argv;");
    }
    // Un parametro con duenio es de la funcion: se libera al salir. Da igual
    // que sea un `str`, una lista, un struct o un arreglo de structs: lo que
    // cuenta es que posea y que no llegue prestado.
    var k = 0;
    while k < tipos_param.largo() {
        if I.posee_con_formas(tipos, tipos_param[k]) {
            if largo(G.marca_sola(marcas[k])) == 0 {
                let pn = G.nombre_de_param(marcas[k]);
                // Un parametro se apunta con la linea 0.
                let clave = G.clave_de(pn, 0);
                G.anotar_duenio(b, pn, tipos_param[k], clave);
            }
        }
        k = k + 1;
    }
    // Las banderas de los parametros abren el cuerpo, en orden de firma.
    var q = 0;
    while q < tipos_param.largo() {
        if I.posee_con_formas(tipos, tipos_param[q]) {
            if largo(G.marca_sola(marcas[q])) == 0 {
                let pn = G.nombre_de_param(marcas[q]);
                let clave = G.clave_de(pn, 0);
                if tiene(sitio.pide_bandera, clave) {
                    G.nace_bandera(b, pn);
                }
            }
        }
        q = q + 1;
    }

    var bien = true;
    for h en d.hijos {
        if h.clase == Clase.Bloque {
            for st en h.hijos {
                if bien {
                    bien = G.sentencia_c(b, sitio, st, tipos, vista(retorno),
                        falible);
                    if !bien { G.apuntar_fallo(b, st); }
                }
            }
            if bien && !G.termina_saliendo(h) {
                G.liberar_todo(b, sitio, tipos, "");
                if falible {
                    // Una falible que llega al final salio bien.
                    G.emitir_final_bien(b, retorno);
                } else {
                    if es_main { G.emitir(b, "return 0;"); }
                }
            }
        }
    }
    I.cerrar(tipos);
    if !bien {
        var donde = nuevo(ruta);
        if b.fallo_linea > 0 { donde = $"{ruta}:{b.fallo_linea}"; }
        cta.fallo = $"error: {donde}: tcodec no sabe escribir esta {b.fallo_clase} de `{d.texto}`. Es un fallo del compilador, no de tu programa";
        return ninguna;
    }

    // Una funcion renombrada por el cargador se declara con su nombre de C:
    // es el mismo que usan las llamadas.
    var nombre_c = nuevo(d.texto);
    if tiene(tipos.renombradas, d.texto) {
        nombre_c = nuevo(obtener(tipos.renombradas, d.texto) sino "");
    }
    var salida: list<str> = [];
    // La directiva de la funcion, salvo que la ultima marcada ya fuera esa.
    if cta.ultima_linea != d.linea {
        salida.anadir($"#line {d.linea} \"{ruta}\"");
    }
    anadir(salida, G.prototipo(vista(nombre_c), tipos_param, marcas,
            vista(retorno), falible));
    salida.anadir(nuevo("{"));
    for l en b.lineas { salida.anadir(copiar(l)); }
    salida.anadir(nuevo("}"));

    // `main` falible: un envoltorio que informa y devuelve un codigo distinto
    // de cero, para que el fallo no se pierda al salir del programa.
    if es_main && falible {
        let res = G.tipo_resultado(retorno);
        salida.anadir(vacio());
        salida.anadir(nuevo("int main(int argc, char** argv)"));
        salida.anadir(nuevo("{"));
        salida.anadir(nuevo("    ss_lang_argc_ = argc;"));
        salida.anadir(nuevo("    ss_lang_argv_ = argv;"));
        salida.anadir($"    {res} r = ss_main_();");
        salida.anadir(nuevo("    if (r.motivo != NULL)"));
        salida.anadir(nuevo("    {"));
        salida.anadir(nuevo("        fprintf(stderr, \"error: %s\\n\", r.motivo);"));
        salida.anadir(nuevo("        return 1;"));
        salida.anadir(nuevo("    }"));
        if retorno.largo() == 0 || retorno == "()" {
            salida.anadir(nuevo("    return 0;"));
        } else {
            salida.anadir(nuevo("    return (int) r.valor;"));
        }
        salida.anadir(nuevo("}"));
    }
    cta.temporal = b.temporal;
    cta.bucle = b.bucle;
    cta.etiquetas = b.etiquetas;
    cta.ultima_linea = b.ultima_linea;
    for x en b.instancias { cta.instancias.anadir(copiar(x)); }
    for x en b.copias { cta.copias.anadir(copiar(x)); }
    for x en b.arreglos { cta.arreglos.anadir(copiar(x)); }
    return salida;
}

// ------------------------------------------------------------------
// Vistas implicitas
// ------------------------------------------------------------------

// Donde se pide una vista y se da un `str` con nombre —una variable, un
// campo, un elemento—, el `str` se presta solo, como en los argumentos:
// `let v: view = s;`, `v = s;` con `v` vista, y `return s;` en una funcion
// que devuelve `view` son `vista(s)`. Se escribe aqui, en el arbol, antes
// que nada: el comprobador y el generador ven el `vista(s)` de siempre, con
// sus prestamos y sus vidas. Un `str` sin nombre —`nuevo("x")`— no se
// presta, que moriria al acabar la sentencia, y su error es el de siempre.
fn vistas_implicitas(arbol: mut P.Nodo, tipos: mut I.Contexto) {
    var cambio = false;
    var i = 0;
    while i < arbol.hijos.largo() {
        if arbol.hijos[i].clase == Clase.Fn {
            vistas_en_funcion(arbol.hijos[i], tipos, cambio);
        }
        i = i + 1;
    }
    // Los nodos nuevos tambien llevan numero.
    if cambio {
        var cuenta: usize = 0;
        P.numerar(arbol, cuenta);
    }
}

fn vistas_en_funcion(f: mut P.Nodo, tipos: mut I.Contexto, cambio: mut bool) {
    I.abrir(tipos);
    var retorno = vacio();
    for h en f.hijos {
        if h.clase == Clase.Param {
            let pn = nombre_de(h.texto);
            let pt = tipo_pelado(h.texto);
            I.declarar(tipos, pn, pt);
        }
        if h.clase == Clase.RetornoTipo {
            retorno = T.sin_alias_tipo(h.texto);
        }
    }
    var i = 0;
    while i < f.hijos.largo() {
        if f.hijos[i].clase == Clase.Bloque {
            vistas_en_bloque(f.hijos[i], tipos, retorno, cambio);
        }
        i = i + 1;
    }
    I.cerrar(tipos);
}

fn vistas_en_bloque(b: mut P.Nodo, tipos: mut I.Contexto, retorno: view,
    cambio: mut bool) {
    I.abrir(tipos);
    var i = 0;
    while i < b.hijos.largo() {
        vistas_en_sentencia(b.hijos[i], tipos, retorno, cambio);
        i = i + 1;
    }
    I.cerrar(tipos);
}

// Una sentencia: lo que presta ella, lo de sus bloques, y lo que declara,
// que se ve desde la siguiente.
fn vistas_en_sentencia(st: mut P.Nodo, tipos: mut I.Contexto, retorno: view,
    cambio: mut bool) {
    let clase = st.clase;
    let es_declaracion = clase == Clase.Declaracion && st.hijos.largo() == 1;
    if es_declaracion {
        let escrito = G.tipo_escrito(st.texto);
        let t = T.sin_alias_tipo(escrito);
        if t == "view" { prestar_si_str(st.hijos[0], tipos, cambio); }
    }
    if clase == Clase.Asignacion && st.hijos.largo() == 2 {
        let destino = I.tipo_de(tipos, st.hijos[0]);
        if destino.nombre == "view" { prestar_si_str(st.hijos[1], tipos, cambio); }
    }
    if clase == Clase.Retorno && st.hijos.largo() == 1 && retorno == "view" {
        prestar_si_str(st.hijos[0], tipos, cambio);
    }
    // Un `for` declara su variable para el cuerpo.
    let es_para = clase == Clase.Para && st.hijos.largo() == 2;
    if es_para {
        I.abrir(tipos);
        declarar_de_para(st, tipos);
    }
    var k = 0;
    while k < st.hijos.largo() {
        vistas_en_hijo(st.hijos[k], tipos, retorno, cambio);
        k = k + 1;
    }
    if es_para { I.cerrar(tipos); }
    if es_declaracion {
        let nombre = G.nombre_declarado(st.texto);
        var tipo = G.tipo_escrito(st.texto);
        if tipo.largo() == 0 { tipo = T.escribir_tipo(I.tipo_de(tipos, st.hijos[0])); }
        I.declarar(tipos, nombre, tipo);
    }
}

// Lo que cuelga de una sentencia: sus bloques se miran como bloques, y en
// una expresion se buscan los que lleve, como los brazos de un `match`. El
// `return` que es el valor de un brazo no es de la funcion, y tampoco el de
// una clausura: esos no se tocan.
fn vistas_en_hijo(h: mut P.Nodo, tipos: mut I.Contexto, retorno: view,
    cambio: mut bool) {
    let clase = h.clase;
    if clase == Clase.Bloque {
        vistas_en_bloque(h, tipos, retorno, cambio);
        return;
    }
    if clase == Clase.Cierre { return; }
    var k = 0;
    while k < h.hijos.largo() {
        vistas_en_hijo(h.hijos[k], tipos, retorno, cambio);
        k = k + 1;
    }
}

fn declarar_de_para(st: &P.Nodo, tipos: mut I.Contexto) {
    let suyo = I.tipo_de(tipos, st.hijos[0]);
    let sobre = T.apuntado_si(T.escribir_tipo(suyo));
    let uno = G.primer_nombre(st.texto);
    let dos = G.segundo_nombre(st.texto);
    if T.es_rango(sobre) {
        I.declarar(tipos, uno, T.elemento(sobre));
    } else if T.es_mapa(sobre) {
        let partes = T.partes(sobre);
        if partes.largo() == 2 {
            I.declarar(tipos, uno, partes[0]);
            if dos.largo() > 0 { I.declarar(tipos, dos, partes[1]); }
        }
    } else {
        let elem = T.elemento(sobre);
        I.declarar(tipos, uno, elem);
    }
}

// Si `n` es un `str` con nombre, pasa a ser `vista(n)`.
fn prestar_si_str(n: mut P.Nodo, tipos: &I.Contexto, cambio: mut bool) {
    if !P.es_lugar(n) { return; }
    let t = I.tipo_de(tipos, n);
    let sin = T.apuntado_si(T.escribir_tipo(t));
    if sin != "str" { return; }
    var envuelto = P.rama(Clase.Llamada, n.linea);
    envuelto.texto.empujar("vista");
    envuelto.hijos.anadir(copiar(n));
    n = envuelto;
    cambio = true;
}
