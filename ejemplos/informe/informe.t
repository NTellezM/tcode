// informe.t — el programa. Junta los dos modulos.
//
// Reparte el trabajo en tres archivos, usa una funcion que puede fallar y
// no libera nada a mano. Es lo que hacia falta para escribir algo grande.

usar "lib/texto.t";
usar "lib/calculo.t";

struct Articulo {
    nombre: str,
    unidades: usize,
}

// `&Articulo` lo presta para leer: no lo copia ni lo saca del arreglo.
fn linea(a: &Articulo, total: usize) -> str ! {
    let pct: usize = try porcentaje(a.unidades, total);

    var s: str = vacio();
    let nombre: str = rellenar(vista(a.nombre), 12);
    empujar(s, vista(nombre));

    let barra: str = repetir("#", try dividir(pct, 4));
    empujar(s, vista(barra));

    let hueco: str = repetir(" ", 26 - largo(vista(barra)));
    empujar(s, vista(hueco));
    return s;
}

// `mut Articulo` lo presta para modificarlo en el sitio.
fn ajustar(a: mut Articulo, extra: usize) {
    a.unidades = a.unidades + extra;
}

fn main() -> usize ! {
    var inv: [Articulo; 4] = [
        Articulo { nombre: nuevo("tornillos"), unidades: 420 },
        Articulo { nombre: nuevo("tuercas"),   unidades: 310 },
        Articulo { nombre: nuevo("arandelas"), unidades: 200 },
        Articulo { nombre: nuevo("remaches"),  unidades: 275 }
    ];

    ajustar(inv[2], 25);

    var total: usize = 0;
    var i: usize = 0;
    while i < 4 {
        total = total + inv[i].unidades;
        i = i + 1;
    }

    let borde: str = repetir("=", 46);
    imprimir(borde); imprimir("\n");

    i = 0;
    while i < 4 {
        let l: str = try linea(inv[i], total);
        imprimir(l);
        imprimir(inv[i].unidades);
        imprimir(" (");
        imprimir(try porcentaje(inv[i].unidades, total));
        imprimir("%)\n");
        i = i + 1;
    }

    imprimir(borde); imprimir("\n");
    imprimir("total ");   imprimir(total);
    imprimir(", media "); imprimir(try media(total, 4));
    imprimir("\n");

    // Un fallo que se sustituye en vez de propagarse.
    imprimir("sobre cero: ");
    imprimir(porcentaje(10, 0) sino 0);
    imprimir(" (sustituido)\n");
    return 0;
}
