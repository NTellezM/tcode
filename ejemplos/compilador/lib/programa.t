// lib/programa.t — lo que comparten los drivers del generador en Tcode.
//
// Preparar un archivo (sus firmas, las de los modulos que usa, los nombres
// que el cargador renombra) y generar una funcion entera. Lo usan
// `cuerpos.t`, que compara funcion a funcion, y `tcodec.t`, que escribe el
// programa entero.

usar "generar.t" como G;
usar "tipar.t" como I;
usar "tipos.t" como T;
usar "../../lexer/lib/lexico.t";
usar "../../lexer/lib/sintaxis.t" como P;
usar "std/texto";
usar "std/lista";

fn nombre_de(texto: view) -> str {
    var i = 0;
    while i < largo(texto) {
        if byte(texto, i) == 58 { return nuevo(rebanar(texto, 0, i)); }
        i = i + 1;
    }
    return nuevo(texto);
}

fn tras_dos_puntos(texto: view) -> str {
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

fn tipo_pelado(marcado: view) -> str {
    let t = tras_dos_puntos(marcado);
    if empieza_con(vista(t), "mut ") {
        return nuevo(rebanar(vista(t), 4, largo(vista(t))));
    }
    if empieza_con(vista(t), "&mut ") {
        return nuevo(rebanar(vista(t), 5, largo(vista(t))));
    }
    if empieza_con(vista(t), "&") {
        return nuevo(rebanar(vista(t), 1, largo(vista(t))));
    }
    return t;
}

fn marca_de(marcado: view) -> str {
    let t = tras_dos_puntos(marcado);
    if empieza_con(vista(t), "mut ") { return nuevo("mut "); }
    if empieza_con(vista(t), "&mut ") { return nuevo("&mut "); }
    if empieza_con(vista(t), "&") { return nuevo("&"); }
    return vacio();
}

fn es_generica(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if igual(vista(h.clase), "tipo_param") { return true; }
    }
    return false;
}

fn recoger_firmas(n: &P.Nodo, c: mut I.Contexto) {
    // Los campos de cada struct: hacen falta para saber si un tipo posee
    // memoria, y de eso depende si el elemento de un `for` se presta o se
    // copia. Un struct de otro modulo se llama igual en C, asi que no lleva
    // alias.
    if igual(vista(n.clase), "struct") {
        var suyos: lista<str> = [];
        var como_se_llaman: lista<str> = [];
        for h en n.hijos {
            if igual(vista(h.clase), "campo_def") {
                anadir(como_se_llaman, nombre_de(vista(h.texto)));
                anadir(suyos, tipo_pelado(vista(h.texto)));
            }
        }
        poner(c.campos, vista(n.texto), suyos);
        poner(c.nombres, vista(n.texto), como_se_llaman);
        var sueltos_st: lista<str> = [];
        for h en n.hijos {
            if igual(vista(h.clase), "tipo_param") { anadir(sueltos_st, nuevo(vista(h.texto))); }
        }
        if largo(sueltos_st) > 0 { poner(c.struct_params, vista(n.texto), sueltos_st); }
    }
    if igual(vista(n.clase), "enum") {
        var cuales: lista<str> = [];
        for h en n.hijos {
            if igual(vista(h.clase), "variante") {
                anadir(cuales, nuevo(vista(h.texto)));
                var lleva: lista<str> = [];
                for x en h.hijos {
                    if igual(vista(x.clase), "lleva") {
                        anadir(lleva, nuevo(vista(x.texto)));
                    }
                }
                var clave = nuevo(vista(n.texto));
                empujar(clave, ".");
                empujar(clave, vista(h.texto));
                poner(c.formas, vista(clave), lleva);
            }
        }
        poner(c.variantes, vista(n.texto), cuales);
    }
    if igual(vista(n.clase), "fn") {
        var retorno = vacio();
        var es_de_c = false;
        var sueltos: lista<str> = [];
        var tipos_param: lista<str> = [];
        var marcados: lista<str> = [];
        for h en n.hijos {
            if igual(vista(h.clase), "retorno_tipo") {
                retorno = nuevo(vista(h.texto));
            }
            // Una firma de `externo` no tiene cuerpo, y `cadena_c` solo
            // existe en el borde: lo que ve Tcode es un `str` suyo.
            if igual(vista(h.clase), "externa") { es_de_c = true; }
            if igual(vista(h.clase), "tipo_param") {
                anadir(sueltos, nuevo(vista(h.texto)));
            }
            if igual(vista(h.clase), "param") {
                anadir(tipos_param, tipo_pelado(vista(h.texto)));
                anadir(marcados, marca_de(vista(h.texto)));
            }
        }
        if es_de_c {
            // 2 si devuelve `cadena_c`: la llamada se queda una copia.
            if igual(vista(retorno), "cadena_c") {
                poner(c.externas, vista(n.texto), 2);
                retorno = nuevo("str");
            } else {
                poner(c.externas, vista(n.texto), 1);
            }
            // Una funcion de C presta lo que recibe: no se queda con nada.
            var prestados: lista<str> = [];
            for _m en marcados { anadir(prestados, nuevo("&")); }
            marcados = prestados;
        }
        // Si un modulo usado ya declaraba este nombre, el cargador de verdad
        // renombra los dos, y esta capa no sabe a que: no se emite la llamada.
        if tiene(c.retornos, vista(n.texto)) {
            poner(c.repetidas, vista(n.texto), 1);
        }
        poner(c.retornos, vista(n.texto), retorno);
        poner(c.params, vista(n.texto), tipos_param);
        poner(c.params_marcados, vista(n.texto), marcados);
        if largo(sueltos) > 0 { poner(c.tipo_params, vista(n.texto), sueltos); }
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
        let cs = I.lista_de(suyas.campos, vista(st)) sino [];
        poner(c.campos, vista(st), cs);
        let ns = I.lista_de(suyas.nombres, vista(st)) sino [];
        poner(c.nombres, vista(st), ns);
        if tiene(suyas.struct_params, vista(st)) {
            let sp = I.lista_de(suyas.struct_params, vista(st)) sino [];
            poner(c.struct_params, vista(st), sp);
        }
    }
    for en_ en claves(suyas.variantes) {
        let vs = I.lista_de(suyas.variantes, vista(en_)) sino [];
        for v en vs {
            var clave = nuevo(vista(en_));
            empujar(clave, ".");
            empujar(clave, vista(v));
            let lleva = I.lista_de(suyas.formas, vista(clave)) sino [];
            poner(c.formas, vista(clave), lleva);
        }
        poner(c.variantes, vista(en_), vs);
    }
    for nombre en claves(suyas.retornos) {
        if tiene(c.retornos, vista(nombre)) {
            poner(c.repetidas, vista(nombre), 1);
        }
        copiar_firma(suyas, c, vista(nombre), vista(nombre));
        if largo(m.alias) > 0 {
            var con_alias = copiar(m.alias);
            empujar(con_alias, ".");
            empujar(con_alias, vista(nombre));
            copiar_firma(suyas, c, vista(nombre), vista(con_alias));
        }
    }
}

fn copiar_firma(de: &I.Contexto, a: mut I.Contexto, suyo: view, como: view) {
    poner(a.retornos, como, nuevo(obtener(de.retornos, suyo) sino ""));
    let ps = I.lista_de(de.params, suyo) sino [];
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
    while i < largo(ruta) {
        if byte(ruta, i) == 47 { desde = i + 1; }
        i = i + 1;
    }
    var hasta = largo(ruta);
    var j = largo(ruta);
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
            empujar(r, rebanar(ruta, k, k + 1));
        } else {
            empujar(r, "_");
        }
        k = k + 1;
    }
    return r;
}

// `a/./b/../c.t` -> `a/c.t`. Sin preguntar al sistema: hace falta que dos
// caminos al mismo archivo den la misma cadena, para no cargarlo dos veces.
fn normalizar(ruta: view) -> str {
    var partes: lista<str> = [];
    let absoluta = largo(ruta) > 0 && byte(ruta, 0) == 47;
    var desde = 0;
    var i = 0;
    while i <= largo(ruta) {
        if i == largo(ruta) || byte(ruta, i) == 47 {
            let trozo = rebanar(ruta, desde, i);
            if largo(trozo) > 0 && !igual(trozo, ".") {
                var atras = false;
                if igual(trozo, "..") && largo(partes) > 0 {
                    atras = !igual(vista(partes[largo(partes) - 1]), "..");
                }
                if atras { partes = sin_la_ultima(partes); }
                else { anadir(partes, nuevo(trozo)); }
            }
            desde = i + 1;
        }
        i = i + 1;
    }
    var r = vacio();
    if absoluta { empujar(r, "/"); }
    var primera = true;
    for x en partes {
        if !primera { empujar(r, "/"); }
        primera = false;
        empujar(r, vista(x));
    }
    return r;
}

fn sin_la_ultima(xs: &lista<str>) -> lista<str> {
    var quedan: lista<str> = [];
    var i = 0;
    while i + 1 < largo(xs) {
        anadir(quedan, copiar(xs[i]));
        i = i + 1;
    }
    return quedan;
}

// El prefijo con el que se renombra lo que choca entre modulos. Basta el
// nombre del archivo, salvo que otro de los que declaran ese mismo nombre se
// llame igual (`x.t` y `lib/x.t`): entonces va la ruta entera, como en el
// cargador. `modulos` son solo los que declaran el nombre.
fn prefijo_unico(ruta: view, modulos: &lista<str>) -> str {
    let base = prefijo_de(ruta);
    var iguales = 0;
    for m en modulos {
        let otra = prefijo_de(vista(m));
        if igual(vista(otra), vista(base)) { iguales = iguales + 1; }
    }
    if iguales <= 1 { return base; }
    // La ruta sin extension; `.oculto` no tiene, el punto es del nombre.
    var hasta = largo(ruta);
    var i = largo(ruta);
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
        if I.es_de_nombre(b) { empujar_byte(r, b como u8); } else { empujar(r, "_"); }
    }
    var desde = 0;
    var fin = largo(r);
    while desde < fin && byte(vista(r), desde) == 95 { desde = desde + 1; }
    while fin > desde && byte(vista(r), fin - 1) == 95 { fin = fin - 1; }
    return nuevo(rebanar(vista(r), desde, fin));
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
    // `archivo\tlinea\tp.a.b`.
    sacados: mapa<str, usize>,
    ultima_linea: usize,
    // Las copias de genericas que han pedido las funciones escritas.
    instancias: lista<str>,
    // Los tipos que han pedido copiador, en el orden en que se pidieron.
    copias: lista<str>,
    // Los arreglos que solo nombra un literal en algun cuerpo.
    arreglos: lista<str>,
    // La funcion que se escribe, con el nombre que le da el comprobador: es
    // la clave de los tipos que dejo anotados. Vacio, no hay anotaciones y
    // los tipos se deducen.
    dueno: str,
}

fn cuenta_nueva() -> Cuenta {
    return Cuenta { temporal: 0, bucle: 0, etiquetas: 0, sacados: [], ultima_linea: 0,
        instancias: [],
        copias: [], arreglos: [], dueno: vacio() };
}

// Lee y analiza un archivo, y deja en `tipos` todo lo que hace falta saber
// para generarlo: sus firmas, las de los modulos que usa y los nombres que
// el cargador renombra. Devuelve el arbol.
fn preparar(ruta: view, tipos: mut I.Contexto) -> P.Nodo ! {
    var error = vacio();
    let ninguno: mapa<str, usize> = [];
    var leidos = P.leidos();
    return try preparar_con_error(ruta, tipos, error, ninguno, ninguno, leidos);
}

// Lo mismo, y si el archivo no se puede leer como Tcode, `error` dice por que
// con las palabras del lexer y el parser de Python.
// `previos_st` y `previos_en` son los structs y enums de los modulos ya
// leidos: el cargador de Python se los da al parser, y con ellos `Caja { .. }`
// es un literal aunque `Caja` venga de un modulo que este no usa. En
// `leidos` va lo que ya se leyo de otros archivos en esta compilacion.
fn preparar_con_error(ruta: view, tipos: mut I.Contexto, error: mut str,
    previos_st: &mapa<str, usize>, previos_en: &mapa<str, usize>,
    leidos: mut P.Leidos) -> P.Nodo ! {
    let fuente = try leer_archivo(ruta);
    let tokens = try tokens_de(vista(fuente), ruta, error);
    var nombres = P.visibles_con(ruta, tokens, "struct", leidos);
    var formas = P.visibles_con(ruta, tokens, "enum", leidos);
    for x en claves(previos_st) { poner(nombres, vista(x), 1); }
    for x en claves(previos_en) { poner(formas, vista(x), 1); }
    // Lo que traen los modulos, antes de nada: los tokens pasan a ser del
    // `Estado` en cuanto se construye.
    var usados = P.modulos_usados_con(ruta, tokens, leidos);

    var estado = P.estado_de(tokens, ruta, nombres, formas);
    var arbol = P.programa(estado) sino P.rama("vacio", 0);
    if largo(estado.error) > 0 || igual(vista(arbol.clase), "vacio") {
        error = copiar(estado.error);
        falla "sintaxis";
    }

    // Lo que chocaria con C se renombra antes que nada, en este arbol y en
    // los de lo que usa, como hace el cargador. Salvo `main` y lo que
    // declara un `externo`: es el nombre de la funcion de C.
    let de_c = G.nombres_de_c();
    var intocables: lista<str> = [nuevo("main")];
    G.externas_de(arbol, intocables);
    for u en usados { G.externas_de(u.arbol, intocables); }
    G.renombrar_para_c(arbol, de_c, intocables);
    var k = 0;
    while k < largo(usados) {
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
        if igual(vista(d.clase), "fn") && tiene(tipos.repetidas, vista(d.texto)) {
            var suyos: lista<str> = [normalizar(ruta)];
            for u en usados {
                if declara_fn(u.arbol, vista(d.texto)) { anadir(suyos, normalizar(vista(u.ruta))); }
            }
            var otro = prefijo_unico(ruta, suyos);
            empujar(otro, "__");
            empujar(otro, vista(d.texto));
            poner(tipos.renombradas, vista(d.texto), otro);
            quitar(tipos.repetidas, vista(d.texto));
        }
    }
    vistas_implicitas(arbol, tipos);
    return arbol;
}

fn declara_fn(arbol: &P.Nodo, nombre: view) -> bool {
    for d en arbol.hijos {
        if igual(vista(d.clase), "fn") && igual(vista(d.texto), nombre) { return true; }
    }
    return false;
}

// Una funcion entera en C, linea a linea: su `#line`, la firma, el cuerpo y,
// si es `main` falible, el envoltorio que informa del fallo al salir. Vacia
// si esta capa no la sabe generar entera: media funcion no vale nada, y la
// razon va por la salida de error.
fn generar_funcion(d: &P.Nodo, tipos: mut I.Contexto, ruta: view,
    cta: mut Cuenta) -> lista<str> {
    let ninguna: lista<str> = [];
    var puntos: mapa<str, usize> = [];
    var de_tipo: mapa<str, str> = [];
    var tipos_param: lista<str> = [];
    var marcas: lista<str> = [];
    var retorno = vacio();
    var falible = false;

    tipos.dueno = copiar(cta.dueno);
    I.abrir(tipos);
    for h en d.hijos {
        if igual(vista(h.clase), "param") {
            let pn = nombre_de(vista(h.texto));
            let pt = tipo_pelado(vista(h.texto));
            let m = marca_de(vista(h.texto));
            poner(de_tipo, vista(pn), copiar(pt));
            I.declarar(tipos, vista(pn), vista(pt));
            anadir(tipos_param, copiar(pt));
            var junto = copiar(pn);
            empujar(junto, ": ");
            empujar(junto, vista(m));
            anadir(marcas, junto);
            if largo(m) > 0 {
                if igual(vista(m), "&") { poner(puntos, vista(pn), 2); }
                else { poner(puntos, vista(pn), 1); }
            }
        }
        if igual(vista(h.clase), "retorno_tipo") {
            retorno = nuevo(vista(h.texto));
        }
        if igual(vista(h.clase), "falible") { falible = true; }
    }
    let es_main = igual(vista(d.texto), "main");

    // Quien se entrega por algun camino lleva bandera. Se decide antes de
    // emitir nada, porque la bandera nace pegada a la declaracion.
    var movidas: lista<str> = [];
    for h en d.hijos {
        if igual(vista(h.clase), "bloque") {
            G.movidas_hondo(puntos, h, tipos, movidas);
        }
    }
    var banderas: mapa<str, usize> = [];
    for nm en movidas { poner(banderas, vista(nm), 1); }

    var sitio = G.Sitio { archivo: nuevo(ruta), tipos: de_tipo,
        punteros: puntos, pide_bandera: banderas,
        retorno: copiar(retorno), sacados: copiar(cta.sacados) };
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
    while k < largo(tipos_param) {
        if I.posee_con_formas(tipos, vista(tipos_param[k])) {
            if largo(G.marca_sola(vista(marcas[k]))) == 0 {
                let pn = G.nombre_de_param(vista(marcas[k]));
                // Un parametro se apunta con la linea 0.
                let clave = G.clave_de(vista(pn), 0);
                G.anotar_duenio(b, vista(pn), vista(tipos_param[k]), vista(clave));
            }
        }
        k = k + 1;
    }
    // Las banderas de los parametros abren el cuerpo, en orden de firma.
    var q = 0;
    while q < largo(tipos_param) {
        if I.posee_con_formas(tipos, vista(tipos_param[q])) {
            if largo(G.marca_sola(vista(marcas[q]))) == 0 {
                let pn = G.nombre_de_param(vista(marcas[q]));
                let clave = G.clave_de(vista(pn), 0);
                if tiene(sitio.pide_bandera, vista(clave)) {
                    G.nace_bandera(b, vista(pn));
                }
            }
        }
        q = q + 1;
    }

    var bien = true;
    for h en d.hijos {
        if igual(vista(h.clase), "bloque") {
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
                    G.emitir_final_bien(b, vista(retorno));
                } else {
                    if es_main { G.emitir(b, "return 0;"); }
                }
            }
        }
    }
    I.cerrar(tipos);
    if !bien {
        imprimir_error($"!! {d.texto}\t{b.fallo_linea}\t{b.fallo_clase}\n");
        return ninguna;
    }

    // Una funcion renombrada por el cargador se declara con su nombre de C:
    // es el mismo que usan las llamadas.
    var nombre_c = nuevo(vista(d.texto));
    if tiene(tipos.renombradas, vista(d.texto)) {
        nombre_c = nuevo(obtener(tipos.renombradas, vista(d.texto)) sino "");
    }
    var salida: lista<str> = [];
    // La directiva de la funcion, salvo que la ultima marcada ya fuera esa.
    if cta.ultima_linea != d.linea {
        anadir(salida, $"#line {d.linea} \"{ruta}\"");
    }
    anadir(salida, G.prototipo(vista(nombre_c), tipos_param, marcas,
            vista(retorno), falible));
    anadir(salida, nuevo("{"));
    for l en b.lineas { anadir(salida, copiar(l)); }
    anadir(salida, nuevo("}"));

    // `main` falible: un envoltorio que informa y devuelve un codigo distinto
    // de cero, para que el fallo no se pierda al salir del programa.
    if es_main && falible {
        let res = G.tipo_resultado(vista(retorno));
        anadir(salida, vacio());
        anadir(salida, nuevo("int main(int argc, char** argv)"));
        anadir(salida, nuevo("{"));
        anadir(salida, nuevo("    ss_lang_argc_ = argc;"));
        anadir(salida, nuevo("    ss_lang_argv_ = argv;"));
        anadir(salida, $"    {res} r = ss_main_();");
        anadir(salida, nuevo("    if (r.motivo != NULL)"));
        anadir(salida, nuevo("    {"));
        anadir(salida, nuevo("        fprintf(stderr, \"error: %s\\n\", r.motivo);"));
        anadir(salida, nuevo("        return 1;"));
        anadir(salida, nuevo("    }"));
        if largo(vista(retorno)) == 0 || igual(vista(retorno), "()") {
            anadir(salida, nuevo("    return 0;"));
        } else {
            anadir(salida, nuevo("    return (int) r.valor;"));
        }
        anadir(salida, nuevo("}"));
    }
    cta.temporal = b.temporal;
    cta.bucle = b.bucle;
    cta.etiquetas = b.etiquetas;
    cta.ultima_linea = b.ultima_linea;
    for x en b.instancias { anadir(cta.instancias, copiar(x)); }
    for x en b.copias { anadir(cta.copias, copiar(x)); }
    for x en b.arreglos { anadir(cta.arreglos, copiar(x)); }
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
    while i < largo(arbol.hijos) {
        if igual(vista(arbol.hijos[i].clase), "fn") {
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
        if igual(vista(h.clase), "param") {
            let pn = nombre_de(vista(h.texto));
            let pt = tipo_pelado(vista(h.texto));
            I.declarar(tipos, vista(pn), vista(pt));
        }
        if igual(vista(h.clase), "retorno_tipo") {
            retorno = I.sin_alias_tipo(vista(h.texto));
        }
    }
    var i = 0;
    while i < largo(f.hijos) {
        if igual(vista(f.hijos[i].clase), "bloque") {
            vistas_en_bloque(f.hijos[i], tipos, vista(retorno), cambio);
        }
        i = i + 1;
    }
    I.cerrar(tipos);
}

fn vistas_en_bloque(b: mut P.Nodo, tipos: mut I.Contexto, retorno: view,
    cambio: mut bool) {
    I.abrir(tipos);
    var i = 0;
    while i < largo(b.hijos) {
        vistas_en_sentencia(b.hijos[i], tipos, retorno, cambio);
        i = i + 1;
    }
    I.cerrar(tipos);
}

// Una sentencia: lo que presta ella, lo de sus bloques, y lo que declara,
// que se ve desde la siguiente.
fn vistas_en_sentencia(st: mut P.Nodo, tipos: mut I.Contexto, retorno: view,
    cambio: mut bool) {
    let clase = copiar(st.clase);
    let es_declaracion = igual(vista(clase), "declaracion") && largo(st.hijos) == 1;
    if es_declaracion {
        let escrito = G.tipo_escrito(vista(st.texto));
        let t = I.sin_alias_tipo(vista(escrito));
        if igual(vista(t), "view") { prestar_si_str(st.hijos[0], tipos, cambio); }
    }
    if igual(vista(clase), "asignacion") && largo(st.hijos) == 2 {
        let destino = I.tipo_de(tipos, st.hijos[0]);
        if igual(vista(destino), "view") { prestar_si_str(st.hijos[1], tipos, cambio); }
    }
    if igual(vista(clase), "retorno") && largo(st.hijos) == 1 && igual(retorno, "view") {
        prestar_si_str(st.hijos[0], tipos, cambio);
    }
    // Un `for` declara su variable para el cuerpo.
    let es_para = igual(vista(clase), "para") && largo(st.hijos) == 2;
    if es_para {
        I.abrir(tipos);
        declarar_de_para(st, tipos);
    }
    var k = 0;
    while k < largo(st.hijos) {
        vistas_en_hijo(st.hijos[k], tipos, retorno, cambio);
        k = k + 1;
    }
    if es_para { I.cerrar(tipos); }
    if es_declaracion {
        let nombre = G.nombre_declarado(vista(st.texto));
        var tipo = G.tipo_escrito(vista(st.texto));
        if largo(tipo) == 0 { tipo = I.tipo_de(tipos, st.hijos[0]); }
        I.declarar(tipos, vista(nombre), vista(tipo));
    }
}

// Lo que cuelga de una sentencia: sus bloques se miran como bloques, y en
// una expresion se buscan los que lleve, como los brazos de un `match`. El
// `return` que es el valor de un brazo no es de la funcion, y tampoco el de
// una clausura: esos no se tocan.
fn vistas_en_hijo(h: mut P.Nodo, tipos: mut I.Contexto, retorno: view,
    cambio: mut bool) {
    let clase = copiar(h.clase);
    if igual(vista(clase), "bloque") {
        vistas_en_bloque(h, tipos, retorno, cambio);
        return;
    }
    if igual(vista(clase), "cierre") { return; }
    var k = 0;
    while k < largo(h.hijos) {
        vistas_en_hijo(h.hijos[k], tipos, retorno, cambio);
        k = k + 1;
    }
}

fn declarar_de_para(st: &P.Nodo, tipos: mut I.Contexto) {
    let suyo = I.tipo_de(tipos, st.hijos[0]);
    let sobre = T.apuntado_si(vista(suyo));
    let uno = G.primer_nombre(vista(st.texto));
    let dos = G.segundo_nombre(vista(st.texto));
    if T.es_rango(vista(sobre)) {
        I.declarar(tipos, vista(uno), T.entre_angulos(vista(sobre)));
    } else if T.es_mapa(vista(sobre)) {
        let partes = T.partir_tipos(T.entre_angulos(vista(sobre)));
        if largo(partes) == 2 {
            I.declarar(tipos, vista(uno), vista(partes[0]));
            if largo(dos) > 0 { I.declarar(tipos, vista(dos), vista(partes[1])); }
        }
    } else {
        let elem = T.elemento(vista(sobre));
        I.declarar(tipos, vista(uno), vista(elem));
    }
}

// Si `n` es un `str` con nombre, pasa a ser `vista(n)`.
fn prestar_si_str(n: mut P.Nodo, tipos: &I.Contexto, cambio: mut bool) {
    if !P.es_lugar(n) { return; }
    let t = I.tipo_de(tipos, n);
    let sin = T.apuntado_si(vista(t));
    if !igual(vista(sin), "str") { return; }
    var envuelto = P.rama("llamada", n.linea);
    empujar(envuelto.texto, "vista");
    anadir(envuelto.hijos, copiar(n));
    n = envuelto;
    cambio = true;
}
