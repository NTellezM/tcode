// std/arbol.t — un arbol binario de busqueda, generico y ordenado.
//
//     var a: Arbol<usize> = Arbol { ramas: [], raiz: 0, cuantas: 0, libres: [] };
//     meter_en_arbol(a, 5);
//     if esta_en_arbol(a, 5) { imprimir("esta\n"); }
//     let de_menor_a_mayor = en_orden(a);
//
// Es un arbol de verdad, no una lista disfrazada. Cada `Rama<T>` guarda su
// dato y los enlaces a sus dos hijos, y buscar, meter o sacar bajan por UNA
// sola rama, descartando en cada paso el subarbol que no puede contener el
// dato. Recorrer una lista entera costaria O(n) por operacion; aqui cuesta
// O(altura): logaritmico si el arbol esta equilibrado, que es lo que sale con
// datos al azar o con claves de muchos bits, y lineal en el peor caso, cuando
// llegan ya ordenados y el arbol degenera en escalera. Esa es la diferencia
// con guardar la lista ordenada: alli buscar es logaritmico pero meter es
// O(n) porque hay que desplazar medio vector.
//
// Los nodos viven en una `list<Rama<T>>` y los hijos se nombran por su
// posicion. No es capricho: un struct no se contiene por valor —no tendria
// tamano finito— y una `view` no se puede guardar en una lista, asi que no
// hay punteros que dar. El enlace guardado es `posicion + 1`, de modo que `0`
// significa «no hay hijo» sin reservar ninguna ranura de relleno y sin
// inventarse un `T` vacio, que de un generico no se sabe construir. Las
// posiciones que deja libres un `sacar` se apuntan en `libres` y se
// reutilizan: sacar y volver a meter no hace crecer el arbol. El dato de una
// rama suelta no se suelta hasta que su ranura se reutiliza o se libera el
// arbol entero: de un elemento de una lista no se saca su duenio sin dejar
// otro en su sitio, y aqui no hay otro `T` que dejar.
//
// El orden lo pone `menor`, con la misma restriccion `ordenable` que usa
// `std/lista`, y nada mas: para los tipos que no la cumplen, el compilador lo
// dice al llamar.
//
//     meter_en_arbol     O(altura)
//     esta_en_arbol      O(altura)
//     sacar_del_arbol    O(altura)
//     minimo/maximo      O(altura)
//     en_orden           O(n)
//     cuantos_en_arbol   O(1)
//     altura_del_arbol   O(n)
//
// `nuevo_arbol` no se puede llamar: una funcion generica sin argumentos no
// tiene de donde deducir `T`, y los tipos no se escriben en la llamada
// (`nuevo_arbol<usize>()` no existe), asi que ni la anotacion delante lo
// salva. Se arranca con el literal del struct, igual que en `std/cola`,
// `std/pila` y `std/prioridad`. La funcion se deja abajo porque es el nombre
// que uno busca, pero el camino es el literal.

struct Rama<T> {
    dato: T,
    izquierda: usize,
    derecha: usize,
}

struct Arbol<T> {
    ramas: list<Rama<T>>,
    raiz: usize,
    cuantas: usize,
    libres: list<usize>,
}

// Un arbol vacio. No se puede llamar —ver la cabecera—: se escribe el literal
// `Arbol { ramas: [], raiz: 0, cuantas: 0, libres: [] }` con su tipo delante.
fn nuevo_arbol<T>() -> Arbol<T> {
    return Arbol { ramas: [], raiz: 0, cuantas: 0, libres: [] };
}

// ---------- ramas ----------

// Una ranura nueva con su dato dentro, reutilizando la ultima que quedo libre
// si la hay. El dato viejo de una ranura reutilizada se libera al pisarlo.
fn nueva_rama_en_arbol<T>(a: mut Arbol<T>, x: T, izquierda: usize, derecha: usize) -> usize {
    let rama = Rama { dato: x, izquierda: izquierda, derecha: derecha };
    if largo(a.libres) > 0 {
        let pos = a.libres[largo(a.libres) - 1];
        truncar(a.libres, largo(a.libres) - 1);
        a.ramas[pos] = rama;
        return pos + 1;
    }
    anadir(a.ramas, rama);
    return largo(a.ramas);
}

fn soltar_rama_en_arbol<T>(a: mut Arbol<T>, enlace: usize) {
    anadir(a.libres, enlace - 1);
}

// El enlace de la rama menor del subarbol que cuelga de `desde`, bajando
// siempre por la izquierda. `0` si el subarbol esta vacio.
fn enlace_minimo_en_arbol<T>(a: &Arbol<T>, desde: usize) -> usize {
    var enlace = desde;
    while enlace != 0 && a.ramas[enlace - 1].izquierda != 0 {
        enlace = a.ramas[enlace - 1].izquierda;
    }
    return enlace;
}

fn enlace_maximo_en_arbol<T>(a: &Arbol<T>, desde: usize) -> usize {
    var enlace = desde;
    while enlace != 0 && a.ramas[enlace - 1].derecha != 0 {
        enlace = a.ramas[enlace - 1].derecha;
    }
    return enlace;
}

// ---------- meter ----------

// Mete `x` en su sitio si no estaba. Si ya estaba no hace nada: el arbol es un
// conjunto ordenado, no un monton con repetidos, y por eso buscar siempre
// encuentra lo mismo.
fn meter_en_arbol<T: ordenable>(a: mut Arbol<T>, x: T) {
    if a.raiz == 0 {
        a.raiz = nueva_rama_en_arbol(a, x, 0, 0);
        a.cuantas = a.cuantas + 1;
        return;
    }
    // Primero se busca el hueco —solo comparaciones— y solo despues se mete.
    // Asi `x` se mueve una vez, y no dentro de un bucle donde el compilador no
    // sabria si sigue siendo suyo.
    var enlace = a.raiz;
    var padre = 0;
    var por_la_izquierda = false;
    var ya_estaba = false;
    while enlace != 0 {
        let p = enlace - 1;
        if menor(x, a.ramas[p].dato) {
            padre = enlace;
            por_la_izquierda = true;
            enlace = a.ramas[p].izquierda;
        } else if menor(a.ramas[p].dato, x) {
            padre = enlace;
            por_la_izquierda = false;
            enlace = a.ramas[p].derecha;
        } else {
            ya_estaba = true;
            enlace = 0;
        }
    }
    if ya_estaba { return; }
    let nueva = nueva_rama_en_arbol(a, x, 0, 0);
    if por_la_izquierda {
        a.ramas[padre - 1].izquierda = nueva;
    } else {
        a.ramas[padre - 1].derecha = nueva;
    }
    a.cuantas = a.cuantas + 1;
}

// ---------- buscar ----------

fn esta_en_arbol<T: ordenable>(a: &Arbol<T>, x: &T) -> bool {
    var enlace = a.raiz;
    while enlace != 0 {
        let p = enlace - 1;
        if menor(x, a.ramas[p].dato) {
            enlace = a.ramas[p].izquierda;
        } else if menor(a.ramas[p].dato, x) {
            enlace = a.ramas[p].derecha;
        } else {
            return true;
        }
    }
    return false;
}

// ---------- sacar ----------

// Saca `x` y devuelve si estaba. Si no estaba no toca nada.
//
// El caso dificil es la rama con dos hijos: quitarla dejaria dos subarboles
// que no se pueden colgar de un solo enlace. El sucesor —la rama menor de su
// subarbol derecho, que por ser la menor no tiene hijo izquierdo— es el que
// sigue a `x` en orden, asi que ocupa su sitio.
//
// En vez de copiar el dato del sucesor al sitio del que se va —una copia de
// `T` y dos datos vivos hasta que se pise la ranura— se lleva la rama entera:
// se desengancha de su padre y se le cuelgan los dos hijos del que se va. El
// dato no se copia ni una vez, y el arbol de valores queda igual.
fn sacar_del_arbol<T: ordenable>(a: mut Arbol<T>, x: &T) -> bool {
    var enlace = a.raiz;
    var padre = 0;
    var por_la_izquierda = false;
    var encontrado = false;
    while enlace != 0 && !encontrado {
        let p = enlace - 1;
        if menor(x, a.ramas[p].dato) {
            padre = enlace;
            por_la_izquierda = true;
            enlace = a.ramas[p].izquierda;
        } else if menor(a.ramas[p].dato, x) {
            padre = enlace;
            por_la_izquierda = false;
            enlace = a.ramas[p].derecha;
        } else {
            encontrado = true;
        }
    }
    if !encontrado { return false; }

    let p = enlace - 1;
    let izquierda = a.ramas[p].izquierda;
    let derecha = a.ramas[p].derecha;
    var sustituto = 0;
    if izquierda == 0 {
        sustituto = derecha;
    } else if derecha == 0 {
        sustituto = izquierda;
    } else {
        var padre_sucesor = enlace;
        var sucesor = derecha;
        while a.ramas[sucesor - 1].izquierda != 0 {
            padre_sucesor = sucesor;
            sucesor = a.ramas[sucesor - 1].izquierda;
        }
        let q = sucesor - 1;
        if sucesor == derecha {
            // El sucesor ya colgaba de donde cuelga el que se va: solo hereda
            // el hijo izquierdo, que no tenia.
            a.ramas[q].izquierda = izquierda;
        } else {
            // Su padre se queda con el hijo derecho del sucesor, que es lo
            // unico que el sucesor tenia por debajo.
            a.ramas[padre_sucesor - 1].izquierda = a.ramas[q].derecha;
            a.ramas[q].izquierda = izquierda;
            a.ramas[q].derecha = derecha;
        }
        sustituto = sucesor;
    }

    if padre == 0 {
        a.raiz = sustituto;
    } else if por_la_izquierda {
        a.ramas[padre - 1].izquierda = sustituto;
    } else {
        a.ramas[padre - 1].derecha = sustituto;
    }
    soltar_rama_en_arbol(a, enlace);
    a.cuantas = a.cuantas - 1;
    return true;
}

// ---------- medir y recorrer ----------

fn cuantos_en_arbol<T>(a: &Arbol<T>) -> usize {
    return a.cuantas;
}

// La altura en ramas: un arbol vacio mide 0 y uno de una sola rama mide 1.
fn altura_del_arbol<T>(a: &Arbol<T>) -> usize {
    return altura_desde(a, a.raiz);
}

fn altura_desde<T>(a: &Arbol<T>, enlace: usize) -> usize {
    if enlace == 0 { return 0; }
    let p = enlace - 1;
    let h_izquierda = altura_desde(a, a.ramas[p].izquierda);
    let h_derecha = altura_desde(a, a.ramas[p].derecha);
    if h_izquierda > h_derecha { return h_izquierda + 1; }
    return h_derecha + 1;
}

// Los datos de menor a mayor: recorrer en orden es visitar el subarbol
// izquierdo, luego la rama, luego el derecho.
fn en_orden<T>(a: &Arbol<T>) -> list<T> {
    var salida: list<T> = [];
    en_orden_desde(a, a.raiz, salida);
    return salida;
}

fn en_orden_desde<T>(a: &Arbol<T>, enlace: usize, salida: mut list<T>) {
    if enlace == 0 { return; }
    let p = enlace - 1;
    en_orden_desde(a, a.ramas[p].izquierda, salida);
    anadir(salida, copiar(a.ramas[p].dato));
    en_orden_desde(a, a.ramas[p].derecha, salida);
}

// El menor y el mayor son las ramas que se alcanzan bajando siempre por un
// lado: el de mas a la izquierda y el de mas a la derecha. Falla en vez de
// devolver algo inventado, como `minimo` y `maximo` de `std/lista`.
fn minimo_del_arbol<T: ordenable>(a: &Arbol<T>) -> T ! {
    if a.raiz == 0 { fail "un arbol vacio no tiene minimo"; }
    let enlace = enlace_minimo_en_arbol(a, a.raiz);
    return copiar(a.ramas[enlace - 1].dato);
}

fn maximo_del_arbol<T: ordenable>(a: &Arbol<T>) -> T ! {
    if a.raiz == 0 { fail "un arbol vacio no tiene maximo"; }
    let enlace = enlace_maximo_en_arbol(a, a.raiz);
    return copiar(a.ramas[enlace - 1].dato);
}
