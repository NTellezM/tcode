struct Conjunto { dentro: map<str, usize> }
fn conjunto() -> Conjunto {
    return Conjunto { dentro: [] };
}
fn de_lista(xs: &list<str>) -> Conjunto {
    var c = conjunto();
    return c;
}
fn agregar_uno(c: mut Conjunto, x: view) {
}
fn elementos(c: &Conjunto) -> list<str> {
    var ks = claves(c.dentro);
    return ks;
}
fn union(a: &Conjunto) -> Conjunto {
    var r = conjunto();
    return r;
}
fn interseccion(a: &Conjunto, b: & &Conjunto) -> Conjunto {
    var r = conjunto();
    return r;
}
