// inventario.t — structs, arreglos y propiedad recursiva.
//
// `Articulo` posee un `str`. Un `[Articulo; 4]` posee cuatro. El compilador
// genera la liberacion de los cuatro, en orden, sin que aparezca un solo
// `ss_free` en este archivo.

struct Articulo {
    nombre: str,
    pasillo: usize,
    unidades: usize,
}

struct Resumen {
    total: usize,
    mayor: usize,
    lleno: bool,
}

fn crear(nombre: view, pasillo: usize, unidades: usize) -> Articulo {
    return Articulo {
        nombre: nuevo(nombre),
        pasillo: pasillo,
        unidades: unidades,
    };
}

fn resumir(inv: [Articulo; 4]) -> Resumen {
    var total = 0;
    var mayor = 0;
    for a en inv {
        total = total + a.unidades;
        if a.unidades > mayor {
            mayor = a.unidades;
        }
    }
    return Resumen { total: total, mayor: mayor, lleno: total > 1000 };
}

fn barra(n: usize) -> str {
    var s = vacio();
    var i = 0;
    while i < n {
        empujar(s, "#");
        i = i + 1;
    }
    return s;
}

fn main() -> usize {
    var inv = [
        crear("tornillos",  1, 420),
        crear("tuercas",    1, 310),
        crear("arandelas",  2, 150),
        crear("remaches",   3, 275)
    ];

    // Se puede escribir dentro de un arreglo de structs, a cualquier hondura.
    inv[2].unidades = inv[2].unidades + 50;

    var i = 0;
    while i < 4 {
        imprimir(inv[i].nombre);
        imprimir("\t pasillo ");
        imprimir(inv[i].pasillo);
        imprimir("  ");
        let b = barra(inv[i].unidades / 50);
        imprimir(b);
        imprimir(" ");
        imprimir(inv[i].unidades);
        imprimir("\n");
        i = i + 1;
    }

    let r = resumir(inv);
    imprimir("\ntotal ");
    imprimir(r.total);
    imprimir(", mayor ");
    imprimir(r.mayor);
    imprimir(", lleno: ");
    imprimir(r.lleno);
    imprimir("\n");
}
