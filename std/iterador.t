// std/iterador.t — recorridos que componen sin crear colecciones intermedias.
//
// `for` ya recorre listas, mapas y rangos. Estas funciones cubren lo que un
// bucle suele hacer alrededor: ejecutar, preguntar y acumular. Reciben una
// funcion o una clausura, de modo que el recorrido sigue siendo una sola
// pasada y una clausura puede llevar su estado consigo.

// Ejecuta `hacer` una vez por elemento, en orden.
fn para_cada<T, F>(xs: &lista<T>, hacer: F) {
    for x en xs { hacer(x); }
}

// Si todos los elementos cumplen. Como en logica, una lista vacia cumple.
fn todas<T, F>(xs: &lista<T>, cumple: F) -> bool {
    for x en xs {
        if !cumple(x) { return false; }
    }
    return true;
}

// Si cumple al menos uno. Una lista vacia no tiene ninguno.
fn alguna<T, F>(xs: &lista<T>, cumple: F) -> bool {
    for x en xs {
        if cumple(x) { return true; }
    }
    return false;
}

// El primero que cumple, copiado para que no escape un prestamo a la lista.
fn primera_que<T, F>(xs: &lista<T>, cumple: F) -> T ! {
    for x en xs {
        if cumple(x) { return copiar(x); }
    }
    falla "ningun elemento cumple";
}

// Reduce de izquierda a derecha. `combinar` recibe el acumulado por valor y
// el elemento prestado, y devuelve el acumulado de la vuelta siguiente.
fn plegar<T, A, F>(xs: &lista<T>, inicial: A, combinar: F) -> A {
    var acumulado = inicial;
    for x en xs { acumulado = combinar(acumulado, x); }
    return acumulado;
}

// Transforma sin cambiar el tipo. La variante entre tipos distintos necesita
// tipos asociados o parametros explicitos, que Tcode aun no tiene.
fn transformar<T, F>(xs: &lista<T>, convertir: F) -> lista<T> {
    var salida: lista<T> = [];
    for x en xs { anadir(salida, convertir(x)); }
    return salida;
}
