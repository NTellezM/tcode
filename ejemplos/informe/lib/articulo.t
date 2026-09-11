// lib/articulo.t — lo que es de este programa y de ningun otro.
//
// Aqui no hay utilidades genericas: `repetir`, `rellenar`, `dividir` y
// `porcentaje` vienen de `std`. Un modulo propio es para el dominio.

usar "std/texto";
usar "std/numero";

struct Articulo {
    nombre: str,
    unidades: usize,
}

fn crear(nombre: view, unidades: usize) -> Articulo {
    return Articulo { nombre: nuevo(nombre), unidades: unidades };
}

// `&Articulo` lo presta para leer: no lo copia ni lo saca del arreglo.
fn linea(a: &Articulo, total: usize) -> str ! {
    let pct = try porcentaje(a.unidades, total);
    let barra = repetir("#", try dividir(pct, 4));
    return $"{rellenar(a.nombre, 12)}{rellenar(barra, 26)}{a.unidades} ({pct}%)";
}

// `mut Articulo` lo presta para modificarlo en el sitio.
fn ajustar(a: mut Articulo, extra: usize) {
    a.unidades = a.unidades + extra;
}
