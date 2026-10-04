// std/pila.t — una pila LIFO.
//
//     var p: pila.Pila<usize> = pila.Pila { datos: [], tope: 0 };
//     pila.apilar(p, 1);
//     let x = pila.desapilar(p, 0) sino 0;
//
// Por debajo es una `lista<T>` y un tope. Los huecos de lo ya sacado se
// reutilizan, asi que no crece sin freno al llenar y vaciar.
//
// No hay `nueva`: `T` no se deduce sin argumentos, asi que se construye con el
// literal del struct, igual que `std/vector`.

struct Pila<T> {
    datos: list<T>,
    tope: usize,
}

fn cuantos<T>(p: &Pila<T>) -> usize {
    return p.tope;
}

fn vacia<T>(p: &Pila<T>) -> bool {
    return p.tope == 0;
}

fn apilar<T>(p: mut Pila<T>, x: T) {
    if p.tope < largo(p.datos) {
        p.datos[p.tope] = x;
    } else {
        anadir(p.datos, x);
    }
    p.tope = p.tope + 1;
}

// Saca el de arriba. `vacio_t` es lo que deja en su hueco, para no dejar un
// hueco sin duenio.
fn desapilar<T>(p: mut Pila<T>, vacio_t: T) -> T ! {
    if p.tope == 0 { fail "la pila esta vacia"; }
    p.tope = p.tope - 1;
    return intercambiar(p.datos[p.tope], vacio_t);
}

// El de arriba, sin sacarlo: una copia.
fn cima<T>(p: &Pila<T>) -> T ! {
    if p.tope == 0 { fail "la pila esta vacia"; }
    return copiar(p.datos[p.tope - 1]);
}
