// informe.t — el programa. Junta un modulo propio con la biblioteca.
//
// Reparte el trabajo en varios archivos, usa funciones que pueden fallar y
// no libera nada a mano. Es lo que hacia falta para escribir algo grande.

usar "lib/articulo.t";
usar "std/numero";
usar "std/texto";

fn main() -> usize ! {
    var inv = [
        crear("tornillos", 420),
        crear("tuercas", 310),
        crear("arandelas", 200),
        crear("remaches", 275)
    ];

    ajustar(inv[2], 25);

    var total = 0;
    var i = 0;
    while i < 4 {
        total = total + inv[i].unidades;
        i = i + 1;
    }

    let borde = repetir("=", 46);
    imprimir($"{borde}\n");

    i = 0;
    while i < 4 {
        imprimir($"{try linea(inv[i], total)}\n");
        i = i + 1;
    }

    imprimir($"{borde}\n");
    imprimir($"total {total}, media {try dividir(total, 4)}\n");

    // Un fallo que se sustituye en vez de propagarse.
    imprimir($"sobre cero: {porcentaje(10, 0) sino 0} (sustituido)\n");
}
