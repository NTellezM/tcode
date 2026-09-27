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
usar "../lexer/lib/clase.t";

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

// `nombre: mut lista<str>` da `lista<str>`: la marca se pasa aparte.
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

// `nombre: &Cosa` se queda en `nombre: &Cosa`; es lo que `prototipo`
// necesita para saber si va por puntero y como se llama.
fn marca_de(marcado: view) -> str {
    var i = 0;
    while i + 1 < marcado.largo() {
        if byte(marcado, i) == 58 {
            if byte(marcado, i + 1) == 32 {
                var s = nuevo(rebanar(marcado, 0, i + 2));
                s.empujar(recortar(rebanar(marcado, i + 2, marcado.largo())));
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
    if empieza_con(t, "mut ") { return nuevo("mut "); }
    if empieza_con(t, "&mut ") { return nuevo("&mut "); }
    if empieza_con(t, "&") { return nuevo("&"); }
    return vacio();
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t>\n");
        return 1;
    }

    let fuente = try leer_archivo(argumento(1));
    let tokens = try analizar(fuente);
    let nombres = P.structs_visibles(argumento(1), tokens);
    let formas = P.enums_visibles(argumento(1), tokens);
    var estado = P.estado_de(tokens, argumento(1), nombres, formas);
    var arbol = try P.programa(estado);
    // Lo que chocaria con C, renombrado como lo hace el cargador.
    var intocables: lista<str> = [nuevo("main")];
    G.externas_de(arbol, intocables);
    G.renombrar_para_c(arbol, G.nombres_de_c(), intocables);

    for d en arbol.hijos {
        if d.clase == Clase.Fn && !es_generica(d) {
            var tipos: lista<str> = [];
            var marcas: lista<str> = [];
            var retorno = vacio();
            var falible = false;
            for h en d.hijos {
                if h.clase == Clase.Param {
                    tipos.anadir(tipo_pelado(h.texto));
                    var m = nuevo(nombre_solo(h.texto));
                    m.empujar(": ");
                    m.empujar(solo_marca(h.texto));
                    marcas.anadir(m);
                }
                if h.clase == Clase.RetornoTipo {
                    retorno = nuevo(h.texto);
                }
                if h.clase == Clase.Falible { falible = true; }
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
    while i < marcado.largo() {
        if byte(marcado, i) == 58 { return nuevo(rebanar(marcado, 0, i)); }
        i = i + 1;
    }
    return nuevo(marcado);
}

fn es_generica(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if h.clase == Clase.TipoParam { return true; }
    }
    return false;
}
