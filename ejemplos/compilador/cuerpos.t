// cuerpos.t — la funcion entera en C, escrita por Tcode.
//
// Tercera pieza del generador, y la que de verdad cuenta: la firma, el
// cuerpo, y los `ss_free` puestos solos donde tocan. Una funcion que esta
// capa no sabe hacer entera no se emite a medias: se descarta, porque media
// funcion generada no dice nada.
//
//     ./cuerpos std/caracter.t

usar "lib/generar.t" como G;
usar "lib/tipar.t" como I;
usar "../lexer/lib/lexico.t";
usar "../lexer/lib/sintaxis.t" como P;
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
            poner(c.externas, vista(n.texto), 1);
            if igual(vista(retorno), "cadena_c") { retorno = nuevo("str"); }
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
    if tiene(de.externas, suyo) { poner(a.externas, como, 1); }
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

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t>\n");
        return 1;
    }

    let ruta = argumento(1);
    let fuente = try leer_archivo(ruta);
    let tokens = try analizar(vista(fuente));
    let nombres = P.structs_visibles(ruta, tokens);
    let formas = P.enums_visibles(ruta, tokens);
    var tipos = I.contexto();
    // Lo que traen los modulos que este archivo usa, antes de nada: sin
    // esto, una llamada a `empieza_con` de `std/texto` no se sabe que
    // devuelve, y la funcion entera se descarta. Va aqui porque los tokens
    // pasan a ser del `Estado` en cuanto se construye.
    for m en P.modulos_usados(ruta, tokens) {
        recoger_de_modulo(m, tipos);
    }

    let sin_alias: mapa<str, usize> = [];
    var estado = P.Estado { toks: tokens, i: 0, alias: sin_alias,
        structs: nombres, enums: formas };
    let arbol = try P.programa(estado);

    // Y las suyas, que mandan sobre las de fuera.
    recoger_firmas(arbol, tipos);
    // Un nombre propio que tambien trae un modulo usado no es ambiguo: desde
    // aqui es el propio. El cargador lo renombra con el nombre de este
    // archivo delante, y asi se llama en C.
    let base = prefijo_de(ruta);
    for d en arbol.hijos {
        if igual(vista(d.clase), "fn") && tiene(tipos.repetidas, vista(d.texto)) {
            var otro = copiar(base);
            empujar(otro, "__");
            empujar(otro, vista(d.texto));
            poner(tipos.renombradas, vista(d.texto), otro);
            quitar(tipos.repetidas, vista(d.texto));
        }
    }

    for d en arbol.hijos {
        if igual(vista(d.clase), "fn") && !es_generica(d) {
            emitir_funcion(d, tipos, ruta);
        }
    }
    return 0;
}

fn emitir_funcion(d: &P.Nodo, tipos: mut I.Contexto, ruta: view) {
    var puntos: mapa<str, usize> = [];
    var de_tipo: mapa<str, str> = [];
    var tipos_param: lista<str> = [];
    var marcas: lista<str> = [];
    var retorno = vacio();
    var falible = false;

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
            if largo(m) > 0 { poner(puntos, vista(pn), 1); }
        }
        if igual(vista(h.clase), "retorno_tipo") {
            retorno = nuevo(vista(h.texto));
        }
        if igual(vista(h.clase), "falible") { falible = true; }
    }

    // `main` lleva envoltorio propio: recoge los argumentos, y si es
    // falible ademas informa del motivo al salir. Otra capa.
    if igual(vista(d.texto), "main") {
        I.cerrar(tipos);
        return;
    }

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

    // El `for` presta el elemento que recorre: mientras dura, el nombre es
    // un puntero mas del sitio.
    var sitio = G.Sitio { archivo: nuevo(ruta), tipos: de_tipo,
        punteros: puntos, pide_bandera: banderas,
        retorno: copiar(retorno) };
    var b = G.cuerpo();
    // La directiva de la funcion la pone el que imprime, antes de la firma;
    // aqui solo hay que saber que ya esta puesta, para no repetirla si la
    // primera sentencia esta en la misma linea.
    b.ultima_linea = d.linea;
    G.abrir_bloque(b);
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
                }
            }
        }
    }
    I.cerrar(tipos);
    if !bien {
        imprimir_error($"!! {d.texto}\t{b.fallo_linea}\t{b.fallo_clase}\n");
        return;
    }

    // Una funcion renombrada por el cargador se declara con su nombre de C:
    // es el mismo que usan las llamadas.
    var nombre_c = nuevo(vista(d.texto));
    if tiene(tipos.renombradas, vista(d.texto)) {
        nombre_c = nuevo(obtener(tipos.renombradas, vista(d.texto)) sino "");
    }
    let firma = G.prototipo(vista(nombre_c), tipos_param, marcas,
        vista(retorno), falible);
    // Un separador para que quien compare sepa donde empieza cada funcion.
    imprimir($"@@ {d.texto}\n");
    imprimir($"#line {d.linea} \"{ruta}\"\n");
    imprimir($"{firma}\n{{\n");
    for l en b.lineas { imprimir($"{l}\n"); }
    imprimir("}\n");
}
