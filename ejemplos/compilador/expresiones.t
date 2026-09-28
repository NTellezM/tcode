// expresiones.t — el C de cada expresion que se devuelve, dicho por Tcode.
//
// Segunda pieza del generador. Por cada `return <expr>;` de cada funcion,
// emite el C que le corresponde. Lo que esta capa todavia no sabe hacer sale
// como `?` y no se compara: la suite cuenta cuantas se cubren de verdad, que
// es mas honesto que hacer como que estan todas.
//
//     ./expresiones std/caracter.t

usar "lib/generar.t" como G;
usar "lib/tipar.t" como I;
usar "../lexer/lib/lexico.t";
usar "../lexer/lib/sintaxis.t" como P;
usar "std/texto";
usar "std/lista";
usar "../lexer/lib/clase.t";

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

fn tipo_pelado(marcado: view) -> str {
    let t = tras_dos_puntos(marcado);
    if empieza_con(t, "mut ") {
        return nuevo(rebanar(t, 4, t.largo()));
    }
    if empieza_con(t, "&mut ") {
        return nuevo(rebanar(t, 5, t.largo()));
    }
    if empieza_con(t, "&") {
        return nuevo(rebanar(t, 1, t.largo()));
    }
    return t;
}

// Solo la marca: `&`, `mut ` o nada.
fn marca_de(marcado: view) -> str {
    let t = tras_dos_puntos(marcado);
    if empieza_con(t, "mut ") { return nuevo("mut "); }
    if empieza_con(t, "&mut ") { return nuevo("&mut "); }
    if empieza_con(t, "&") { return nuevo("&"); }
    return vacio();
}

fn presta(marcado: view) -> bool {
    let t = tras_dos_puntos(marcado);
    if empieza_con(t, "mut ") { return true; }
    return empieza_con(t, "&");
}

fn es_generica(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if h.clase == Clase.TipoParam { return true; }
    }
    return false;
}

fn recoger_firmas(n: &P.Nodo, c: mut I.Contexto) {
    // Los campos de cada struct, con su tipo: un `0` en un campo `u64` es un
    // `u64`.
    if n.clase == Clase.Struct {
        var suyos: lista<str> = [];
        var como_se_llaman: lista<str> = [];
        for h en n.hijos {
            if h.clase == Clase.CampoDef {
                como_se_llaman.anadir(nombre_de(h.texto));
                suyos.anadir(tipo_pelado(h.texto));
            }
        }
        poner(c.campos, vista(n.texto), suyos);
        poner(c.nombres, vista(n.texto), como_se_llaman);
    }
    if n.clase == Clase.Fn {
        var retorno = vacio();
        var es_de_c = false;
        var sueltos: lista<str> = [];
        var tipos_param: lista<str> = [];
        var marcados: lista<str> = [];
        for h en n.hijos {
            match h.clase {
                Clase.RetornoTipo -> {
                    retorno = nuevo(h.texto);
                }
                // Una firma de `externo` no tiene cuerpo, y `cadena_c` solo
                // existe en el borde: lo que ve Tcode es un `str` suyo.
                Clase.Externa -> { es_de_c = true; }
                Clase.TipoParam -> {
                    sueltos.anadir(nuevo(h.texto));
                }
                Clase.Param -> {
                    tipos_param.anadir(tipo_pelado(h.texto));
                    marcados.anadir(marca_de(h.texto));
                }
                _ -> { }
            }
        }
        if es_de_c {
            poner(c.externas, vista(n.texto), 1);
            if retorno == "cadena_c" { retorno = nuevo("str"); }
            // Una funcion de C presta lo que recibe: no se queda con nada.
            var prestados: lista<str> = [];
            for _m en marcados { prestados.anadir(nuevo("&")); }
            marcados = prestados;
        }
        poner(c.retornos, vista(n.texto), retorno);
        poner(c.params, vista(n.texto), tipos_param);
        poner(c.params_marcados, vista(n.texto), marcados);
        if sueltos.largo() > 0 { poner(c.tipo_params, vista(n.texto), sueltos); }
    }
    for h en n.hijos { recoger_firmas(h, c); }
}

// Los `return` de una funcion, en orden.
fn retornos_de(n: &P.Nodo, fuera: mut lista<usize>, nodos: mut lista<P.Nodo>) {
    if n.clase == Clase.Retorno {
        if n.hijos.largo() > 0 {
            fuera.anadir(n.linea);
            nodos.anadir(copiar(n.hijos[0]));
        }
    }
    for h en n.hijos { retornos_de(h, fuera, nodos); }
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t>\n");
        return 1;
    }

    let ruta = argumento(1);
    let fuente = try leer_archivo(ruta);
    let tokens = try analizar(fuente);
    let nombres = P.structs_visibles(ruta, tokens);
    let formas = P.enums_visibles(ruta, tokens);
    let enums_vistos = claves(formas);
    var estado = P.estado_de(tokens, ruta, nombres, formas);
    var arbol = try P.programa(estado);
    // Lo que chocaria con C, renombrado como lo hace el cargador.
    var intocables: lista<str> = [nuevo("main")];
    G.externas_de(arbol, intocables);
    G.renombrar_para_c(arbol, G.nombres_de_c(), intocables);

    var tipos = I.contexto();
    recoger_firmas(arbol, tipos);
    // Los enums que se ven desde aqui, tambien los de otro modulo: de sus
    // formas basta saber que es un enum, que se compara por su etiqueta.
    for en_ en enums_vistos {
        if !tiene(tipos.variantes, en_) {
            let sin_formas: lista<str> = [];
            poner(tipos.variantes, en_, sin_formas);
        }
    }

    for d en arbol.hijos {
        if d.clase == Clase.Fn && !es_generica(d) {
            var puntos: mapa<str, usize> = [];
            var de_tipo: mapa<str, str> = [];
            I.abrir(tipos);
            for h en d.hijos {
                if h.clase == Clase.Param {
                    let pn = nombre_de(h.texto);
                    let pt = tipo_pelado(h.texto);
                    poner(de_tipo, vista(pn), copiar(pt));
                    I.declarar(tipos, pn, pt);
                    if presta(h.texto) {
                        let m = marca_de(h.texto);
                        if m == "&" { poner(puntos, vista(pn), 2); }
                        else { poner(puntos, vista(pn), 1); }
                    }
                }
            }
            // Esta capa mira expresiones sueltas, no caminos: sin caminos
            // no hay nada que una bandera pueda decidir.
            let sin_banderas: mapa<str, usize> = [];
            var lo_que_devuelve = vacio();
            for h en d.hijos {
                if h.clase == Clase.RetornoTipo {
                    lo_que_devuelve = nuevo(h.texto);
                }
            }
            let sitio = G.Sitio { archivo: nuevo(ruta), tipos: de_tipo,
                punteros: puntos, pide_bandera: sin_banderas,
                retorno: lo_que_devuelve, sacados: [] };

            var lineas: lista<usize> = [];
            var nodos: lista<P.Nodo> = [];
            for h en d.hijos {
                if h.clase == Clase.Bloque {
                    retornos_de(h, lineas, nodos);
                }
            }
            var esperado = vacio();
            for h en d.hijos {
                if h.clase == Clase.RetornoTipo {
                    esperado = nuevo(h.texto);
                }
            }
            var k = 0;
            while k < nodos.largo() {
                // Una expresion puede necesitar lineas propias —`byte`
                // guarda la vista en un temporal antes de indexarla—, y esta
                // capa compara solo la expresion. Las lineas se generan
                // igual, en un cuerpo que se tira: lo que importa es que el
                // contador de temporales avance como en el original.
                var hueco = G.cuerpo();
                let c = G.expresion_c(hueco, sitio, nodos[k],
                    vista(esperado), tipos);
                imprimir($"{d.texto}\t{lineas[k]}\t{c}\n");
                k = k + 1;
            }
            I.cerrar(tipos);
        }
    }
    return 0;
}
