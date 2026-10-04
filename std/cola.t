// std/cola.t — una cola FIFO y una cola de doble extremo.
//
// Las dos van sobre una `list<T>` con un indice de cabeza: el frente es
// `datos[cabeza]`, y sacar por delante es avanzar `cabeza`, no `quitar(xs, 0)`
// —que no existe para listas y, de existir, moveria todos los elementos de
// detras—. Cuando la cabeza pasa de la mitad del largo se compacta una sola
// vez: los vivos se copian al principio y la cabeza vuelve a cero. Asi sacar
// por delante cuesta O(1) casi siempre y O(n) de vez en cuando, que es lo que
// hace util a este modulo frente a una lista desnuda.
//
// `Cola<T>` es FIFO: entra por detras y sale por delante. `Doble<T>` puede
// ademas meter y sacar por el otro extremo.
//
// Se construyen con el literal del struct, como `std/pila`: los tipos no se
// escriben en la llamada, se deducen de los argumentos, y `nueva_cola<T>()`
// no tiene ninguno del que deducir `T`. Las dos constructoras van abajo para
// que el nombre este donde se espera, pero en la practica se arranca con
//     var c: Cola<usize> = Cola { datos: [], cabeza: 0 };
//     var d: Doble<str> = Doble { datos: [], cabeza: 0 };

struct Cola<T> {
    datos: list<T>,
    cabeza: usize,
}

struct Doble<T> {
    datos: list<T>,
    cabeza: usize,
}

// ---------- Cola FIFO ----------

fn nueva_cola<T>() -> Cola<T> {
    return Cola { datos: [], cabeza: 0 };
}

// Vacia cuando la cabeza alcanzo al largo: lo de antes ya se saco y solo
// espera a que la compactacion lo suelte.
fn cola_vacia<T>(c: &Cola<T>) -> bool {
    return c.cabeza == largo(c.datos);
}

fn cuantos_en_cola<T>(c: &Cola<T>) -> usize {
    return largo(c.datos) - c.cabeza;
}

fn encolar<T>(c: mut Cola<T>, x: T) {
    anadir(c.datos, x);
}

// Deja los vivos al principio y reinicia la cabeza. Se copia en vez de mover
// porque de un elemento de lista no se saca su duenio sin dejar otro en su
// sitio, y de `T` no se sabe construir un valor vacio que sirva de relleno.
fn compactar_cola<T>(c: mut Cola<T>) {
    if c.cabeza == 0 { return; }
    var vivos: list<T> = [];
    var i = c.cabeza;
    while i < largo(c.datos) {
        anadir(vivos, copiar(c.datos[i]));
        i = i + 1;
    }
    c.datos = vivos;
    c.cabeza = 0;
}

// Saca el del frente. La copia se hace antes de compactar, asi que la
// compactacion no toca lo que se devuelve.
fn desencolar<T>(c: mut Cola<T>) -> T ! {
    if cola_vacia(c) { fail "la cola esta vacia"; }
    let x = copiar(c.datos[c.cabeza]);
    c.cabeza = c.cabeza + 1;
    if c.cabeza * 2 > largo(c.datos) { compactar_cola(c); }
    return x;
}

// Lo mira sin sacarlo: devuelve una copia y no mueve la cabeza.
fn frente<T>(c: &Cola<T>) -> T ! {
    if cola_vacia(c) { fail "la cola esta vacia"; }
    return copiar(c.datos[c.cabeza]);
}

// ---------- Cola de doble extremo ----------

fn nueva_doble<T>() -> Doble<T> {
    return Doble { datos: [], cabeza: 0 };
}

fn doble_vacia<T>(d: &Doble<T>) -> bool {
    return d.cabeza == largo(d.datos);
}

fn cuantos_en_doble<T>(d: &Doble<T>) -> usize {
    return largo(d.datos) - d.cabeza;
}

fn meter_detras<T>(d: mut Doble<T>, x: T) {
    anadir(d.datos, x);
}

// Delante solo hay sitio si la cabeza ya avanzo. Si no, `list<T>` no crece por
// delante y no queda mas que rehacer la lista con el nuevo al principio: eso
// cuesta O(n), pero el caso corriente —meter y sacar por delante alternando—
// reutiliza el hueco que deja la salida y sale O(1).
fn meter_delante<T>(d: mut Doble<T>, x: T) {
    if d.cabeza > 0 {
        d.cabeza = d.cabeza - 1;
        d.datos[d.cabeza] = x;
        return;
    }
    var rehecha: list<T> = [];
    anadir(rehecha, x);
    var i = 0;
    while i < largo(d.datos) {
        anadir(rehecha, copiar(d.datos[i]));
        i = i + 1;
    }
    d.datos = rehecha;
}

fn compactar_doble<T>(d: mut Doble<T>) {
    if d.cabeza == 0 { return; }
    var vivos: list<T> = [];
    var i = d.cabeza;
    while i < largo(d.datos) {
        anadir(vivos, copiar(d.datos[i]));
        i = i + 1;
    }
    d.datos = vivos;
    d.cabeza = 0;
}

fn sacar_delante<T>(d: mut Doble<T>) -> T ! {
    if doble_vacia(d) { fail "la cola doble esta vacia"; }
    let x = copiar(d.datos[d.cabeza]);
    d.cabeza = d.cabeza + 1;
    if d.cabeza * 2 > largo(d.datos) { compactar_doble(d); }
    return x;
}

// Sale por detras: se copia el ultimo y se recorta, que es la unica forma de
// soltar su duenio sin dejar un relleno en el sitio. La cabeza no se mueve,
// asi que este lado no ensucia nada del otro.
fn sacar_detras<T>(d: mut Doble<T>) -> T ! {
    if doble_vacia(d) { fail "la cola doble esta vacia"; }
    let pos = largo(d.datos) - 1;
    let x = copiar(d.datos[pos]);
    truncar(d.datos, pos);
    return x;
}

fn primero<T>(d: &Doble<T>) -> T ! {
    if doble_vacia(d) { fail "la cola doble esta vacia"; }
    return copiar(d.datos[d.cabeza]);
}

fn ultimo<T>(d: &Doble<T>) -> T ! {
    if doble_vacia(d) { fail "la cola doble esta vacia"; }
    return copiar(d.datos[largo(d.datos) - 1]);
}
