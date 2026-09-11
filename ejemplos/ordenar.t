// ordenar.t — las palabras distintas de un archivo, en orden alfabetico.
//
// El bucle de veinte lineas que partia el texto byte a byte esta ahora en
// `terminos`, y el recorte de las ocho primeras en `primeras`. Lo que queda
// es el programa.
//
//     ./ordenar README.md

usar "std/texto";
usar "std/lista";
usar "std/cuenta";

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo>\n");
        return 1;
    }

    let contenido = try leer_archivo(argumento(1));
    let repetidas = terminos(vista(contenido));
    let distintas = contar(repetidas);
    var vocabulario = claves(distintas);
    ordenar(vocabulario);

    imprimir($"{largo(vocabulario)} palabras distintas, las 8 primeras en orden:\n");
    for palabra en primeras(vocabulario, 8) {
        imprimir($"  {palabra}\n");
    }
}
