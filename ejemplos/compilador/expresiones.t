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

// Solo la marca: `&`, `mut ` o nada.
fn marca_de(marcado: view) -> str {
    let t = tras_dos_puntos(marcado);
    if empieza_con(vista(t), "mut ") { return nuevo("mut "); }
    if empieza_con(vista(t), "&mut ") { return nuevo("&mut "); }
    if empieza_con(vista(t), "&") { return nuevo("&"); }
    return vacio();
}

fn presta(marcado: view) -> bool {
    let t = tras_dos_puntos(marcado);
    if empieza_con(vista(t), "mut ") { return true; }
    return empieza_con(vista(t), "&");
}

fn es_generica(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if igual(vista(h.clase), "tipo_param") { return true; }
    }
    return false;
}

fn recoger_firmas(n: &P.Nodo, c: mut I.Contexto) {
    if igual(vista(n.clase), "fn") {
        var retorno = vacio();
        var sueltos: lista<str> = [];
        var tipos_param: lista<str> = [];
        var marcados: lista<str> = [];
        for h en n.hijos {
            if igual(vista(h.clase), "retorno_tipo") {
                retorno = nuevo(vista(h.texto));
            }
            if igual(vista(h.clase), "tipo_param") {
                anadir(sueltos, nuevo(vista(h.texto)));
            }
            if igual(vista(h.clase), "param") {
                anadir(tipos_param, tipo_pelado(vista(h.texto)));
                anadir(marcados, marca_de(vista(h.texto)));
            }
        }
        poner(c.retornos, vista(n.texto), retorno);
        poner(c.params, vista(n.texto), tipos_param);
        poner(c.params_marcados, vista(n.texto), marcados);
        if largo(sueltos) > 0 { poner(c.tipo_params, vista(n.texto), sueltos); }
    }
    for h en n.hijos { recoger_firmas(h, c); }
}

// Los `return` de una funcion, en orden.
fn retornos_de(n: &P.Nodo, fuera: mut lista<usize>, nodos: mut lista<P.Nodo>) {
    if igual(vista(n.clase), "retorno") {
        if largo(n.hijos) > 0 {
            anadir(fuera, n.linea);
            anadir(nodos, copiar(n.hijos[0]));
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
    let tokens = try analizar(vista(fuente));
    let nombres = P.structs_visibles(ruta, tokens);
    let sin_alias: mapa<str, usize> = [];
    var estado = P.Estado { toks: tokens, i: 0, alias: sin_alias,
        structs: nombres };
    let arbol = try P.programa(estado);

    var tipos = I.contexto();
    recoger_firmas(arbol, tipos);

    for d en arbol.hijos {
        if igual(vista(d.clase), "fn") && !es_generica(d) {
            var puntos: mapa<str, usize> = [];
            var de_tipo: mapa<str, str> = [];
            I.abrir(tipos);
            for h en d.hijos {
                if igual(vista(h.clase), "param") {
                    let pn = nombre_de(vista(h.texto));
                    let pt = tipo_pelado(vista(h.texto));
                    poner(de_tipo, vista(pn), copiar(pt));
                    I.declarar(tipos, vista(pn), vista(pt));
                    if presta(vista(h.texto)) { poner(puntos, vista(pn), 1); }
                }
            }
            let sitio = G.Sitio { archivo: nuevo(ruta), tipos: de_tipo,
                punteros: puntos };

            var lineas: lista<usize> = [];
            var nodos: lista<P.Nodo> = [];
            for h en d.hijos {
                if igual(vista(h.clase), "bloque") {
                    retornos_de(h, lineas, nodos);
                }
            }
            var esperado = vacio();
            for h en d.hijos {
                if igual(vista(h.clase), "retorno_tipo") {
                    esperado = nuevo(vista(h.texto));
                }
            }
            var k = 0;
            while k < largo(nodos) {
                let c = G.expresion_c(sitio, nodos[k], vista(esperado), tipos);
                imprimir($"{d.texto}\t{lineas[k]}\t{c}\n");
                k = k + 1;
            }
            I.cerrar(tipos);
        }
    }
    return 0;
}
