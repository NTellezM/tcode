// std/conjunto.t — un conjunto de textos.
//
// Por dentro es un `mapa<str, usize>` donde el valor no importa. Se separa
// porque la intencion se lee: `tiene(vistos, x)` dice si ya paso, y
// `poner(vistos, x, 1)` no dice nada del `1`.

usar "std/lista";

struct Conjunto { dentro: mapa<str, usize> }

fn conjunto() -> Conjunto {
    return Conjunto { dentro: [] };
}

fn de_lista(xs: &lista<str>) -> Conjunto {
    var c = conjunto();
    for x en xs { agregar_uno(c, vista(x)); }
    return c;
}

fn agregar_uno(c: mut Conjunto, x: view) {
    poner(c.dentro, x, 1);
}

fn contiene_a(c: &Conjunto, x: view) -> bool {
    return tiene(c.dentro, x);
}

fn quitar_uno(c: mut Conjunto, x: view) -> bool {
    return quitar(c.dentro, x);
}

fn cuantos_hay(c: &Conjunto) -> usize {
    return largo(c.dentro);
}

// En orden, para que la salida sea estable.
fn elementos(c: &Conjunto) -> lista<str> {
    var ks = claves(c.dentro);
    ordenar(ks);
    return ks;
}

fn union(a: &Conjunto, b: &Conjunto) -> Conjunto {
    var r = conjunto();
    for x en claves(a.dentro) { agregar_uno(r, vista(x)); }
    for x en claves(b.dentro) { agregar_uno(r, vista(x)); }
    return r;
}

fn interseccion(a: &Conjunto, b: &Conjunto) -> Conjunto {
    var r = conjunto();
    for x en claves(a.dentro) {
        if tiene(b.dentro, vista(x)) { agregar_uno(r, vista(x)); }
    }
    return r;
}

// Lo que esta en `a` y no en `b`.
fn diferencia(a: &Conjunto, b: &Conjunto) -> Conjunto {
    var r = conjunto();
    for x en claves(a.dentro) {
        if !tiene(b.dentro, vista(x)) { agregar_uno(r, vista(x)); }
    }
    return r;
}
