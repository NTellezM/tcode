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
        punteros: puntos, pide_bandera: banderas };
    var b = G.cuerpo();
    // La directiva de la funcion la pone el que imprime, antes de la firma;
    // aqui solo hay que saber que ya esta puesta, para no repetirla si la
    // primera sentencia esta en la misma linea.
    b.ultima_linea = d.linea;
    G.abrir_bloque(b);
    // Un parametro con duenio es de la funcion: se libera al salir.
    var k = 0;
    while k < largo(tipos_param) {
        if igual(vista(tipos_param[k]), "str") {
            if largo(G.marca_sola(vista(marcas[k]))) == 0 {
                G.anotar_duenio(b, G.nombre_de_param(vista(marcas[k])),
                    "str");
            }
        }
        k = k + 1;
    }
    // Las banderas de los parametros abren el cuerpo, en orden de firma.
    var q = 0;
    while q < largo(tipos_param) {
        if igual(vista(tipos_param[q]), "str") {
            if largo(G.marca_sola(vista(marcas[q]))) == 0 {
                let pn = G.nombre_de_param(vista(marcas[q]));
                if tiene(sitio.pide_bandera, vista(pn)) {
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
                }
            }
            if bien && !G.termina_saliendo(h) {
                G.liberar_todo(b, sitio, "");
                if falible {
                    // Una falible que llega al final salio bien.
                    G.emitir_final_bien(b, vista(retorno));
                }
            }
        }
    }
    I.cerrar(tipos);
    if !bien { return; }

    let firma = G.prototipo(vista(d.texto), tipos_param, marcas,
        vista(retorno), falible);
    // Un separador para que quien compare sepa donde empieza cada funcion.
    imprimir($"@@ {d.texto}\n");
    imprimir($"#line {d.linea} \"{ruta}\"\n");
    imprimir($"{firma}\n{{\n");
    for l en b.lineas { imprimir($"{l}\n"); }
    imprimir("}\n");
}
