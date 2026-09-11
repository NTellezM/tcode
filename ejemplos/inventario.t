// inventario.t — structs, arreglos y propiedad recursiva.
//
// `Articulo` posee un `str`. Un `[Articulo; 4]` posee cuatro. El compilador
// genera la liberacion de los cuatro, en orden, sin que aparezca un solo
// `ss_free` en este archivo.

usar "std/texto";

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
        let marcas = repetir("#", inv[i].unidades / 50);
        imprimir($"{inv[i].nombre}\t pasillo {inv[i].pasillo}  {marcas} {inv[i].unidades}\n");
        i = i + 1;
    }

    let r = resumir(inv);
    imprimir($"\ntotal {r.total}, mayor {r.mayor}, lleno: {r.lleno}\n");
}
