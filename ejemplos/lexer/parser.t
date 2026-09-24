// parser.t — el analisis sintactico de Tcode, corriendo sobre codigo real.
//
// El analisis vive en `lib/sintaxis.t`; esto es solo el programa que lo
// pone a andar y cuenta lo que sale.
//
//     ./parser std/lista.t --callado

usar "lib/lexico.t";
usar "lib/sintaxis.t";
usar "std/texto";

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t> [--callado]\n");
        return 1;
    }

    let ruta = argumento(1);
    let fuente = try leer_archivo(ruta);
    let tokens = try analizar(fuente);

    // Los structs se recogen ANTES de mover los tokens dentro del estado:
    // despues del movimiento ya no serian nuestros. El compilador lo dice.
    let nombres = structs_visibles(ruta, tokens);
    let formas = enums_visibles(ruta, tokens);
    var e = estado_de(tokens, ruta, nombres, formas);
    let arbol = try programa(e);

    var callado = false;
    if n_argumentos() > 2 { callado = igual(argumento(2), "--callado"); }

    if callado {
        imprimir($"{ruta}: {contar_nodos(arbol)} nodos, hondura {hondura(arbol)}\n");
        return 0;
    }
    mostrar(arbol, 0);
}
