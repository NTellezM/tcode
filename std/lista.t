// std/lista.t — lo que se le pide a una lista y no viene de serie.
//
// `anadir`, `largo`, `ordenar` y la indexacion las pone el compilador. Aqui
// esta el resto, y casi todo es generico.
//
// Lo que el cuerpo necesita del elemento va escrito en la firma:
//
//     <T>               no necesita nada: solo cuenta o mueve posiciones
//     <T: numero>       necesita sumar, dividir o comparar de veras
//     <T: igualable>    necesita `igual`
//     <T: ordenable>    necesita `menor`
//
// Una restriccion es un conjunto de tipos con nombre, no una interfaz que
// haya que implementar: `usize` cumple `numero` sin que nadie escriba nada.

usar "std/numero";

// ---------- para cualquier lista ----------

fn esta_vacia<T>(xs: &lista<T>) -> bool {
    return largo(xs) == 0;
}

// La ultima posicion valida. Falla en vez de devolver un numero envuelto:
// `largo(xs) - 1` sobre una lista vacia aborta el programa.
fn ultima_posicion<T>(xs: &lista<T>) -> usize ! {
    if esta_vacia(xs) { falla "una lista vacia no tiene ultima posicion"; }
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

// ---------- hace falta poder comparar ----------

fn incluye<T: igualable>(xs: &lista<T>, aguja: &T) -> bool {
    for x en xs {
        if igual(x, aguja) { return true; }
    }
    return false;
}

fn posicion<T: igualable>(xs: &lista<T>, aguja: &T) -> usize ! {
    var i = 0;
    for x en xs {
        if igual(x, aguja) { return i; }
        i = i + 1;
    }
    falla "eso no esta en la lista";
}

fn maximo<T: ordenable>(xs: &lista<T>) -> T ! {
    if esta_vacia(xs) { falla "una lista vacia no tiene maximo"; }
    var m = copiar(xs[0]);
    for x en xs {
        if menor(m, x) { m = copiar(x); }
    }
    return m;
}

fn minimo<T: ordenable>(xs: &lista<T>) -> T ! {
    if esta_vacia(xs) { falla "una lista vacia no tiene minimo"; }
    var m = copiar(xs[0]);
    for x en xs {
        if menor(x, m) { m = copiar(x); }
    }
    return m;
}

// ---------- hace falta poder sumar ----------

// Sumar una lista vacia da cero, que es lo correcto. `var total: T = 0` es
// lo que lo permite: en la copia, `T` ya es un tipo concreto y el `0` cuadra
// con el.
fn suma<T: numero>(ns: &lista<T>) -> T {
    var total: T = 0;
    for n en ns { total = total + n; }
    return total;
}

fn media(ns: &lista<usize>) -> usize ! {
    if esta_vacia(ns) { falla "una lista vacia no tiene media"; }
    return try dividir(suma(ns), largo(ns));
}

// Da la vuelta a la lista en el sitio. Con numeros se puede: copiar uno no le
// quita nada a nadie, asi que se pueden intercambiar dos posiciones.
fn invertir<T: numero>(ns: mut lista<T>) {
    if esta_vacia(ns) { return; }
    var i = 0;
    var j = largo(ns) - 1;
    while i < j {
        let guardado = ns[i];
        ns[i] = ns[j];
        ns[j] = guardado;
        i = i + 1;
        j = j - 1;
    }
}
