// tipos.t — la capa de tipos del comprobador, corriendo sobre codigo real.
//
// Lee un `.t`, lo analiza con el parser de Tcode, saca todos los tipos que
// aparecen y responde las dos preguntas de las que cuelga el comprobador.
// La suite corre esto y el equivalente en Python sobre los mismos archivos,
// y compara linea a linea.
//
//     ./tipos std/lista.t

usar "lib/tipos.t" como T;
usar "../lexer/lib/lexico.t";
usar "../lexer/lib/sintaxis.t" como P;
usar "std/texto";
usar "std/lista";

// De `nombre: &lista<str>` se queda con `&lista<str>`. El parser escribe
// `mut T` donde el comprobador dice `&mut T`, asi que se iguala aqui.
fn tras_dos_puntos(texto: view) -> str {
    var i = 0;
    while i + 1 < largo(texto) {
        if byte(texto, i) == 58 {
            if byte(texto, i + 1) == 32 {
                let t = recortar(rebanar(texto, i + 2, largo(texto)));
                if empieza_con(t, "mut ") {
                    var m = nuevo("&mut ");
                    empujar(m, rebanar(t, 4, largo(t)));
                    return m;
                }
                return nuevo(t);
            }
        }
        i = i + 1;
    }
    return nuevo(texto);
}

fn recoger(n: &P.Nodo, campos: mut mapa<str, lista<str>>,
           tipos: mut lista<str>) {
    if igual(vista(n.clase), "struct") {
        var suyos: lista<str> = [];
        for h en n.hijos {
            if igual(vista(h.clase), "campo_def") {
                let t = tras_dos_puntos(vista(h.texto));
                anadir(tipos, copiar(t));
                anadir(suyos, t);
            }
        }
        poner(campos, vista(n.texto), suyos);
    }
    if igual(vista(n.clase), "param") || igual(vista(n.clase), "retorno_tipo") {
        if igual(vista(n.clase), "retorno_tipo") {
            anadir(tipos, nuevo(vista(n.texto)));
        } else {
            anadir(tipos, tras_dos_puntos(vista(n.texto)));
        }
    }
    for h en n.hijos { recoger(h, campos, tipos); }
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t>\n");
        return 1;
    }

    let fuente = try leer_archivo(argumento(1));
    let tokens = try analizar(vista(fuente));
    let nombres = P.structs_visibles(argumento(1), tokens);
    let sin_alias: mapa<str, usize> = [];
    var estado = P.Estado { toks: tokens, i: 0, alias: sin_alias,
                            structs: nombres };
    let arbol = try P.programa(estado);

    var campos: mapa<str, lista<str>> = [];
    var tipos: lista<str> = [];
    recoger(arbol, campos, tipos);

    // En orden y sin repetir, para que la comparacion sea estable.
    var vistos: mapa<str, usize> = [];
    var unicos: lista<str> = [];
    for t en tipos {
        if !tiene(vistos, vista(t)) {
            poner(vistos, vista(t), 1);
            anadir(unicos, copiar(t));
        }
    }
    ordenar(unicos);

    for t en unicos {
        let duenio = posee_de(campos, vista(t));
        let existe = T.tipo_existe(campos, vista(t));
        imprimir($"{t}\t{duenio}\t{existe}\n");
    }
    return 0;
}

// `posee` es falible porque mira dentro de los structs; aqui un tipo que no
// se reconoce simplemente no posee nada.
fn posee_de(campos: &mapa<str, lista<str>>, t: view) -> bool {
    var visitados: mapa<str, usize> = [];
    return T.posee(campos, t, visitados) sino false;
}
