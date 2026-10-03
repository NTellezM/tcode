// std/tabla.t — tablas de texto alineadas.
//
//     imprimir(tabla.dibujar(cabecera, filas));
//
// La cabecera es opcional (una lista vacia la omite). Cada columna se rellena
// al ancho de su celda mas larga, y hay una linea de guiones bajo la
// cabecera. Se apoya en `std/formato`, que ya calcula los anchos.

usar "std/formato" como f;

// Una linea de `veces` guiones, para separar la cabecera.
fn guiones(veces: usize) -> str {
    var s = vacio();
    var i = 0;
    while i < veces { empujar(s, "-"); i = i + 1; }
    return s;
}

// La tabla entera, con la cabecera delante si la hay.
fn dibujar(cabecera: &lista<str>, filas: &lista<lista<str>>) -> str {
    var todas: lista<lista<str>> = [];
    if largo(cabecera) > 0 { anadir(todas, copiar(cabecera)); }
    for f_ en filas { anadir(todas, copiar(f_)); }
    let anchos = f.anchos_de(todas);
    var salida = vacio();
    if largo(cabecera) > 0 {
        empujar(salida, f.fila(cabecera, anchos, "  "));
        empujar(salida, "\n");
        var i = 0;
        while i < largo(anchos) {
            if i > 0 { empujar(salida, "  "); }
            empujar(salida, guiones(anchos[i]));
            i = i + 1;
        }
        empujar(salida, "\n");
    }
    for f_ en filas {
        empujar(salida, f.fila(f_, anchos, "  "));
        empujar(salida, "\n");
    }
    return salida;
}
