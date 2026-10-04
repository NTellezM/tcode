// std/prioridad.t — una cola de prioridad: un monticulo binario de minimos.
//
//     var p: prioridad.Prioridad<usize> = prioridad.Prioridad { datos: [] };
//     prioridad.meter_con_prioridad(p, 5);
//     prioridad.meter_con_prioridad(p, 1);
//     let x = prioridad.sacar_el_primero(p) sino 0;    // 1
//
// El mas pequeño esta siempre arriba, en la posicion 0. Por debajo es una
// `list<T>` y ya esta: no hay arbol de nodos ni memoria reservada aparte.
// Un monticulo es un arbol completo metido en una lista, y el hijo `k` de la
// posicion `i` vive en `2*i + 1` y `2*i + 2`, asi que el padre de `i` es
// `(i - 1) / 2`. Con eso, subir y bajar es aritmetica de indices.
//
// El coste es la razon de que exista este modulo:
//
//     meter_con_prioridad     O(log n)
//     sacar_el_primero        O(log n)
//     ver_el_primero          O(1)
//     prioridad_vacia         O(1)
//     cuantos_en_prioridad    O(1)
//
// Guardar la lista ordenada daria el primero en O(1) pero meter en O(n), y
// buscar el minimo cada vez daria meter en O(1) pero sacarlo en O(n). El
// monticulo paga logaritmo en los dos lados, que es lo que se le pide a una
// cola de prioridad. `ver_el_primero` y las dos cuentas son constantes: el
// minimo ya esta en la posicion 0 y el largo lo lleva la lista.
//
// No hay `nueva_prioridad`: una funcion que solo crea el contenedor no tiene
// ningun argumento del que deducir `T`, y aqui los tipos no se escriben en la
// llamada (`f<usize>()` no existe), asi que no habria forma de llamarla. Se
// construye con el literal del struct, igual que `std/pila` y `std/vector`.
//
// El elemento es un numero: `menor` lo ordena y moverlo de ranura en ranura
// no deja a nadie sin su memoria. `T: ordenable` seria mas ancho de puertas
// afuera y no se puede cumplir por dentro: obliga a comprobar el cuerpo
// tambien con `T = view`, y una vista no se puede copiar ni guardar en una
// lista. Los textos se quedan fuera por eso, y el compilador lo dice si se
// intentan.

struct Prioridad<T> {
    datos: list<T>,
}

fn prioridad_vacia<T: numero>(p: &Prioridad<T>) -> bool {
    return largo(p.datos) == 0;
}

fn cuantos_en_prioridad<T: numero>(p: &Prioridad<T>) -> usize {
    return largo(p.datos);
}

// Mete `x` al final y lo sube mientras sea menor que su padre.
//
// Sube por el hueco: el que llega se lleva aparte, los padres que estorban
// bajan una posicion y el que llega cae donde le toca. Asi hay una copia por
// nivel y no tres.
fn meter_con_prioridad<T: numero>(p: mut Prioridad<T>, x: T) {
    anadir(p.datos, x);
    sube_hueco(p, largo(p.datos) - 1);
}

// El mas pequeño, sin sacarlo: una copia, y la cola se queda como estaba.
fn ver_el_primero<T: numero>(p: &Prioridad<T>) -> T ! {
    if largo(p.datos) == 0 { fail "la cola de prioridad esta vacia"; }
    return copiar(p.datos[0]);
}

// Saca el mas pequeño.
//
// El ultimo pasa arriba y se baja mientras sea mayor que alguno de sus hijos,
// cambiandolo por el menor de los dos. El que estaba arriba se guarda aparte y
// su ranura se recorta: no queda ningun hueco sin duenio, que es lo que el
// compilador no deja hacer de otra forma.
fn sacar_el_primero<T: numero>(p: mut Prioridad<T>) -> T ! {
    if largo(p.datos) == 0 { fail "la cola de prioridad esta vacia"; }

    // Con uno solo no hay nada que reordenar.
    if largo(p.datos) == 1 {
        let unico: T = copiar(p.datos[0]);
        truncar(p.datos, 0);
        return unico;
    }

    // La raiz se guarda, el ultimo sube a su sitio y la ultima ranura se
    // recorta antes de reordenar, para que el monticulo sea el de verdad.
    let minimo: T = copiar(p.datos[0]);
    p.datos[0] = copiar(p.datos[largo(p.datos) - 1]);
    truncar(p.datos, largo(p.datos) - 1);

    if largo(p.datos) > 0 {
        baja_hueco(p, 0);
    }

    return minimo;
}

// ---------- el monticulo por dentro ----------

// Sube el de la posicion `i` mientras sea menor que su padre.
fn sube_hueco<T: numero>(p: mut Prioridad<T>, i: usize) {
    var hueco: bloque<T> = reservar(1);
    let _recien = intercambiar(hueco[0], p.datos[i]);

    var donde = i;
    while donde > 0 {
        let padre = (donde - 1) / 2;
        if !menor(hueco[0], p.datos[padre]) { break; }
        p.datos[donde] = copiar(p.datos[padre]);
        donde = padre;
    }

    p.datos[donde] = copiar(hueco[0]);
}

// Baja el de la posicion `i` mientras sea mayor que alguno de sus hijos,
// cambiandolo por el menor de los dos.
fn baja_hueco<T: numero>(p: mut Prioridad<T>, i: usize) {
    var donde = i;
    while true {
        let izquierdo = 2 * donde + 1;
        if izquierdo >= largo(p.datos) { return; }

        var menor_hijo = izquierdo;
        let derecho = izquierdo + 1;
        if derecho < largo(p.datos) {
            if menor(p.datos[derecho], p.datos[izquierdo]) { menor_hijo = derecho; }
        }

        if !menor(p.datos[menor_hijo], p.datos[donde]) { return; }

        let encima: T = copiar(p.datos[donde]);
        p.datos[donde] = copiar(p.datos[menor_hijo]);
        p.datos[menor_hijo] = encima;
        donde = menor_hijo;
    }
}
