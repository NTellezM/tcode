// std/lista.t — lo que se le pide a una lista y no viene de serie.
//
// `anadir`, `largo`, `ordenar` y la indexacion las pone el compilador. Aqui
// esta el resto.
//
// Lo que sirve para cualquier elemento es generico: `largo_de`, `esta_vacia`.
// Lo que no, no lo es, y por una razon que se ve: `suma` necesita sumar,
// `incluye` necesita comparar, y `primeras` necesita copiar el elemento.
// `usize` se copia solo; un `str` hay que copiarlo a mano. Sin restricciones
// sobre `T` el compilador no puede saber cual de las dos cosas vale, asi que
// esas siguen siendo una por tipo. Es honesto: la generica que existe es la
// que de verdad no mira dentro del elemento.

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

// Las primeras `cuantas`, o todas si hay menos.
fn primeras(xs: &lista<str>, cuantas: usize) -> lista<str> {
    var salida: lista<str> = [];
    var i = 0;
    for x en xs {
        if i == cuantas { break; }
        anadir(salida, nuevo(vista(x)));
        i = i + 1;
    }
    return salida;
}

// Aqui hay que copiar, no dar la vuelta en el sitio: sacar un `str` de una
// lista dejaria un hueco sin duenio, y el compilador no lo permite.
fn invertida(xs: &lista<str>) -> lista<str> {
    var salida: lista<str> = [];
    var i = largo(xs);
    while i > 0 {
        i = i - 1;
        anadir(salida, nuevo(vista(xs[i])));
    }
    return salida;
}
