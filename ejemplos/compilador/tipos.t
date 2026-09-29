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
usar "../lexer/lib/clase.t";

// De `nombre: &lista<str>` se queda con `&lista<str>`. El parser escribe
// `mut T` donde el comprobador dice `&mut T`, asi que se iguala aqui.
fn tras_dos_puntos(texto: view) -> str {
    var i = 0;
    while i + 1 < texto.largo() {
        if byte(texto, i) == 58 {
            if byte(texto, i + 1) == 32 {
                let t = recortar(rebanar(texto, i + 2, texto.largo()));
                if empieza_con(t, "mut ") {
                    var m = nuevo("&mut ");
                    m.empujar(rebanar(t, 4, t.largo()));
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
    if n.clase == Clase.Struct {
        var suyos: lista<str> = [];
        for h en n.hijos {
            if h.clase == Clase.CampoDef {
                let t = tras_dos_puntos(h.texto);
                tipos.anadir(copiar(t));
                suyos.anadir(t);
            }
        }
        poner(campos, vista(n.texto), suyos);
    }
    if n.clase == Clase.Param || n.clase == Clase.RetornoTipo {
        if n.clase == Clase.RetornoTipo {
            tipos.anadir(nuevo(n.texto));
        } else {
            tipos.anadir(tras_dos_puntos(n.texto));
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
    let tokens = try analizar(fuente);
    let nombres = P.structs_visibles(argumento(1), tokens);
    let formas = P.enums_visibles(argumento(1), tokens);
    var estado = P.estado_de(tokens, argumento(1), nombres, formas);
    let arbol = try P.programa(estado);

    var campos: mapa<str, lista<str>> = [];
    var tipos: lista<str> = [];
    recoger(arbol, campos, tipos);

    // En orden y sin repetir, para que la comparacion sea estable.
    var vistos: mapa<str, usize> = [];
    var unicos: lista<str> = [];
    for t en tipos {
        if !tiene(vistos, t) {
            poner(vistos, vista(t), 1);
            unicos.anadir(copiar(t));
        }
    }
    ordenar(unicos);

    for t en unicos {
        let duenio = posee_de(campos, vista(t));
        let existe = T.tipo_existe(campos, vista(t));
        imprimir($"{t}\t{duenio}\t{existe}\n");
        // Leido como arbol y vuelto a escribir, el tipo es el mismo texto; y
        // montado de nuevo con sus propias partes, tambien. Si no, la linea
        // de mas hace fallar la comparacion.
        let leido = T.leer_tipo(t);
        let vuelta = T.escribir_tipo(leido);
        if !igual(vuelta, t) { imprimir($"{t}\tida y vuelta\t{vuelta}\n"); }
        let montado = T.con_partes(t, T.partes(t));
        if !igual(montado, t) { imprimir($"{t}\tcon sus partes\t{montado}\n"); }
    }
    return 0;
}

// Aqui solo hay structs: sin genericas ni enums.
fn posee_de(campos: &mapa<str, lista<str>>, t: view) -> bool {
    var nada: mapa<str, lista<str>> = [];
    var vistos: mapa<str, usize> = [];
    return T.posee_en(t, campos, nada, nada, nada, vistos);
}
