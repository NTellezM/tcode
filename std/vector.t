// std/vector.t — una lista dinamica escrita en Tcode.
//
// `lista<T>` la pone el compilador. Esto hace lo mismo sin que el compilador
// sepa nada: sobre `bloque<T>`, que es memoria reservada de una pieza con su
// tamaño al lado.
//
// Lo que lo hace posible es que un bloque nace a CEROS, y en Tcode todo tipo
// puesto a ceros es un valor valido y vacio: un `str` a ceros es el texto
// vacio, un struct a ceros tiene todos sus campos vacios. Asi no hay ranuras
// sin inicializar que temer, que es de donde salen los problemas al escribir
// un vector en C o el `unsafe` al escribirlo en Rust.

usar "std/numero";

struct Vector<T> {
    datos: bloque<T>,
    largo: usize,
}

fn cuantos<T>(v: &Vector < T >) -> usize { return v.largo; }

fn capacidad<T>(v: &Vector < T >) -> usize { return largo(v.datos); }

fn agregar<T>(v: mut Vector < T >, x: T) {
    if v.largo == largo(v.datos) {
        let crecido = if largo(v.datos) == 0 { 8 } else { largo(v.datos) * 2 };
        redimensionar(v.datos, crecido);
    }
    v.datos[v.largo] = x;
    v.largo = v.largo + 1;
}

// Saca el ultimo dejando un valor vacio en su sitio: nunca hay un hueco sin
// duenio, que es lo que el compilador no deja hacer de otra forma.
fn sacar<T>(v: mut Vector < T >, vacio_del_tipo: T) -> T ! {
    if v.largo == 0 { falla "el vector esta vacio"; }
    v.largo = v.largo - 1;
    return intercambiar(v.datos[v.largo], vacio_del_tipo);
}

fn copia_de<T>(v: &Vector < T >, i: usize) -> T ! {
    if i >= v.largo { falla "esa posicion no existe en el vector"; }
    return copiar(v.datos[i]);
}

// Le sobra memoria si se le quito mucho: la devuelve.
fn ajustar<T>(v: mut Vector < T >) {
    redimensionar(v.datos, v.largo);
}
