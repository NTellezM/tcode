// firmas.t — la firma en C de cada funcion, dicha por Tcode.
//
// Primera pieza del generador escrita en su propio lenguaje. La suite la
// compara con lo que emite el generador de Python, cadena por cadena, para
// cada funcion del repositorio.
//
//     ./firmas std/texto.t

usar "lib/generar.t" como G;
usar "../lexer/lib/lexico.t";
usar "../lexer/lib/sintaxis.t" como P;
usar "std/texto";
usar "std/lista";

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

// `nombre: mut lista<str>` da `lista<str>`: la marca se pasa aparte.
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

// `nombre: &Cosa` se queda en `nombre: &Cosa`; es lo que `prototipo`
// necesita para saber si va por puntero y como se llama.
fn marca_de(marcado: view) -> str {
    var i = 0;
    while i + 1 < largo(marcado) {
        if byte(marcado, i) == 58 {
            if byte(marcado, i + 1) == 32 {
                var s = nuevo(rebanar(marcado, 0, i + 2));
                empujar(s, recortar(rebanar(marcado, i + 2, largo(marcado))));
                return s;
            }
        }
        i = i + 1;
    }
    return nuevo(marcado);
}

// La marca sin el nombre delante, para saber si presta.
fn solo_marca(marcado: view) -> str {
    let t = tras_dos_puntos(marcado);
    if empieza_con(vista(t), "mut ") { return nuevo("mut "); }
    if empieza_con(vista(t), "&mut ") { return nuevo("&mut "); }
    if empieza_con(vista(t), "&") { return nuevo("&"); }
    return vacio();
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t>\n");
        return 1;
    }

    let fuente = try leer_archivo(argumento(1));
    let tokens = try analizar(vista(fuente));
    let nombres = P.structs_visibles(argumento(1), tokens);
    let formas = P.enums_visibles(argumento(1), tokens);
    var estado = P.estado_de(tokens, argumento(1), nombres, formas);
    let arbol = try P.programa(estado);

    for d en arbol.hijos {
        if igual(vista(d.clase), "fn") && !es_generica(d) {
            var tipos: lista<str> = [];
            var marcas: lista<str> = [];
            var retorno = vacio();
            var falible = false;
            for h en d.hijos {
                if igual(vista(h.clase), "param") {
                    anadir(tipos, tipo_pelado(vista(h.texto)));
                    var m = nuevo(nombre_solo(vista(h.texto)));
                    empujar(m, ": ");
                    empujar(m, solo_marca(vista(h.texto)));
                    anadir(marcas, m);
                }
                if igual(vista(h.clase), "retorno_tipo") {
                    retorno = nuevo(vista(h.texto));
                }
                if igual(vista(h.clase), "falible") { falible = true; }
            }
            let firma = G.prototipo(vista(d.texto), tipos, marcas,
                vista(retorno), falible);
            imprimir($"{firma}\n");
        }
    }
    return 0;
}

fn nombre_solo(marcado: view) -> str {
    var i = 0;
    while i < largo(marcado) {
        if byte(marcado, i) == 58 { return nuevo(rebanar(marcado, 0, i)); }
        i = i + 1;
    }
    return nuevo(marcado);
}

fn es_generica(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if igual(vista(h.clase), "tipo_param") { return true; }
    }
    return false;
}
