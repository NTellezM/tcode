// std/lista.t — lo que se le pide a una lista y no viene de serie.
//
// `anadir`, `largo`, `ordenar` y la indexacion las pone el compilador. Aqui
// esta el resto.
//
// Es generico lo que no necesita saber nada del elemento (`esta_vacia`) y lo
// que solo necesita copiarlo (`primeras`, `invertida`), porque `copiar` vale
// para cualquier tipo. Lo que hace falta sumar o comparar sigue siendo una
// funcion por tipo: `suma` necesita `+` e `incluye` necesita `igual`, y
// todavia no hay forma de exigirselos a `T`.

usar "std/numero";

// ---------- para cualquier lista ----------

fn esta_vacia<T>(xs: &lista<T>) -> bool {
    return largo(xs) == 0;
}

// La ultima posicion valida. Falla en vez de devolver un numero envuelto:
// `largo(xs) - 1` sobre una lista vacia aborta el programa.
fn ultima_posicion<T>(xs: &lista<T>) -> usize ! {
    if largo(xs) == 0 { falla "una lista vacia no tiene ultima posicion"; }
    return largo(xs) - 1;
}

// Las primeras `cuantas`, o todas si hay menos.
fn primeras<T>(xs: &lista<T>, cuantas: usize) -> lista<T> {
    var salida: lista<T> = [];
    var i = 0;
    for x en xs {
        if i == cuantas { break; }
        anadir(salida, copiar(x));
        i = i + 1;
    }
    return salida;
}

// Copia al reves, no da la vuelta en el sitio: sacar un elemento duenio de
// una lista dejaria un hueco sin duenio, y el compilador no lo permite.
fn invertida<T>(xs: &lista<T>) -> lista<T> {
    var salida: lista<T> = [];
    var i = largo(xs);
    while i > 0 {
        i = i - 1;
        anadir(salida, copiar(xs[i]));
    }
    return salida;
}

// ---------- listas de numeros ----------

fn suma(ns: &lista<usize>) -> usize {
    var total = 0;
    for n en ns { total = total + n; }
    return total;
}

fn maximo(ns: &lista<usize>) -> usize ! {
    if esta_vacia(ns) { falla "una lista vacia no tiene maximo"; }
    var m = ns[0];
    for n en ns { if n > m { m = n; } }
    return m;
}

fn minimo(ns: &lista<usize>) -> usize ! {
    if esta_vacia(ns) { falla "una lista vacia no tiene minimo"; }
    var m = ns[0];
    for n en ns { if n < m { m = n; } }
    return m;
}

fn media(ns: &lista<usize>) -> usize ! {
    if esta_vacia(ns) { falla "una lista vacia no tiene media"; }
    return try dividir(suma(ns), largo(ns));
}

// Da la vuelta a la lista en el sitio. Con numeros se puede: copiar un
// `usize` no le quita nada a nadie.
fn invertir(ns: mut lista<usize>) {
    var j = ultima_posicion(ns) sino 0;
    if esta_vacia(ns) { return; }
    var i = 0;
    while i < j {
        let guardado = ns[i];
        ns[i] = ns[j];
        ns[j] = guardado;
        i = i + 1;
        j = j - 1;
    }
}

// ---------- listas de texto ----------

fn incluye(xs: &lista<str>, aguja: view) -> bool {
    for x en xs {
        if igual(vista(x), aguja) { return true; }
    }
    return false;
}

fn posicion(xs: &lista<str>, aguja: view) -> usize ! {
    var i = 0;
    for x en xs {
        if igual(vista(x), aguja) { return i; }
        i = i + 1;
    }
    falla "eso no esta en la lista";
}


