// lexer.t — imprime los tokens de un archivo de Tcode.
//
//     ./lexer archivo.t            un token por linea
//     ./lexer archivo.t --contar   cuantos hay de cada clase

usar "lib/lexico.t";

// ------------------------------------------------------------------
// Programa
// ------------------------------------------------------------------

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t> [--contar]\n");
        return 1;
    }

    let ruta = argumento(1);
    let fuente = try leer_archivo(ruta);
    let tokens = try analizar(fuente);

    var solo_contar = false;
    if n_argumentos() > 2 { solo_contar = igual(argumento(2), "--contar"); }

    if solo_contar {
        var por_tipo: mapa<str, usize> = [];
        for t en tokens {
            let cuantos = obtener(por_tipo, t.tipo) sino 0;
            poner(por_tipo, t.tipo, cuantos + 1);
        }
        imprimir($"{ruta}: {largo(tokens)} tokens\n");

        var nombres = claves(por_tipo);
        ordenar(nombres);
        for nombre en nombres {
            let cuantos = obtener(por_tipo, nombre) sino 0;
            imprimir($"  {nombre}  {cuantos}\n");
        }
        return 0;
    }

    for t en tokens {
        imprimir($"{t.linea}\t{t.tipo}\t{t.valor}\n");
    }
}
