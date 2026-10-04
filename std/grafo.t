// std/grafo.t — un grafo dirigido con pesos, para preguntar por relaciones:
// dependencias entre modulos, mapas de un juego, cualquier cosa que sea
// "esto lleva a aquello".
//
// Por dentro es un `map<str, list<Arista>>`: la clave es el nombre del nodo y
// el valor la lista de sus aristas de salida. Se guarda asi, y no como una
// lista de aristas sueltas, porque las preguntas de siempre —quienes son los
// vecinos de este nodo, a quien alcanza, por donde se llega antes— se
// contestan mirando un solo nodo, y en un mapa esa mirada es directa. Con las
// aristas sueltas habria que recorrer el grafo entero por cada pregunta. El
// precio es que el mapa es dueño de los nombres: cada arista guarda tambien
// el nombre de a donde va, y un nombre corto se repite una vez por arista.
//
// Todos los nodos estan en el mapa aunque no tengan aristas: `poner_nodo`
// deja la clave con la lista vacia y `poner_arista` da de alta los dos
// extremos. Asi `claves(g.aristas)` es la lista de nodos, `tiene` es
// `hay_nodo`, y no hay que distinguir "nodo suelto" de "nodo que no esta".
//
// Un nombre que no esta no revienta: las que preguntan (`hay_nodo`,
// `hay_arista`, `vecinos`, `alcanzables`) contestan que no, y las que
// prometen un camino (`camino_mas_corto`, `orden_topologico`) fallan con
// motivo, que es lo que se puede atrapar. Poner dos veces la misma arista
// reemplaza el peso, no apila aristas paralelas.
//
// El peso es `usize`: un peso negativo no se puede ni escribir, el
// compilador lo rechaza antes de generar nada, asi que Dijkstra no lleva una
// comprobacion en tiempo de ejecucion que nunca podria dispararse. Si
// hiciera falta un peso con signo, el sitio para cambiarlo es este tipo, no
// un `if` escondido en el camino.
//
// Los costes, con n nodos y a aristas, para saber que se esta comprando:
//
//     poner_nodo            O(1) casi siempre
//     poner_arista          O(grado), por buscar la arista repetida
//     hay_nodo              O(1);  hay_arista O(grado)
//     vecinos               O(grado log grado), por el orden
//     camino_mas_corto      O(n^2), eligiendo el mas cercano a mano
//     alcanzables           O(n + a), mas el orden
//     orden_topologico      O(n^2), por la misma eleccion a mano
//     componentes           O(n + a), con el camino aplanado
//
// Dijkstra y el orden topologico eligen el nodo a mano en vez de con un
// monticulo porque `std/prioridad` ordena numeros y aqui haria falta un par
// (distancia, nombre) que `menor` no sabe comparar. Con grafos de cientos de
// nodos la diferencia no se nota, y se paga en claridad.

use "std/lista";

// Una arista de salida: a donde va y lo que cuesta.
struct Arista {
    hasta: str,
    peso: usize,
}

// El grafo entero. Cada clave es un nodo, cada valor sus aristas de salida.
struct Grafo {
    aristas: map<str, list<Arista>>,
}

// ---------- construirlo ----------

fn nuevo_grafo() -> Grafo {
    return Grafo { aristas: [] };
}

// Da de alta un nodo sin aristas. Repetirlo no hace nada.
fn poner_nodo(g: mut Grafo, nombre: view) {
    if !tiene(g.aristas, nombre) {
        poner(g.aristas, nombre, []);
    }
}

// Da de alta los dos extremos y deja la arista puesta. Si esa arista ya
// estaba, le cambia el peso: una relacion no se apila dos veces.
fn poner_arista(g: mut Grafo, desde: view, hasta: view, peso: usize) {
    poner_nodo(g, desde);
    poner_nodo(g, hasta);
    // El unico fallo posible es que la clave no este, y acaba de quedar.
    let _cuantas = meter_arista(g, desde, Arista { hasta: nuevo(hasta), peso: peso }) sino 0;
}

// ---------- preguntar ----------

// Si el nodo esta en el grafo, tenga aristas o no.
fn hay_nodo(g: &Grafo, nombre: view) -> bool {
    return tiene(g.aristas, nombre);
}

// Si la arista esta, con cualquier peso.
fn hay_arista(g: &Grafo, desde: view, hasta: view) -> bool {
    if !tiene(g.aristas, desde) { return false; }
    for a en vecindario(g, desde) sino [] {
        if igual(a.hasta, hasta) { return true; }
    }
    return false;
}

// Los nombres de los vecinos de un nodo, en orden. Un nodo que no esta no
// tiene vecinos: lista vacia, no fallo. `hay_nodo` es la pregunta que lo
// distingue de un nodo suelto.
fn vecinos(g: &Grafo, nombre: view) -> list<str> {
    var salida: list<str> = [];
    for a en vecindario(g, nombre) sino [] {
        anadir(salida, nuevo(a.hasta));
    }
    ordenar(salida);
    return salida;
}

// ---------- recorrerlo ----------

// Todo lo que se alcanza desde `desde` siguiendo aristas, en orden. El punto
// de partida no sale por serlo: solo sale si un ciclo vuelve a el, que es
// cuando de verdad se alcanza.
fn alcanzables(g: &Grafo, desde: view) -> list<str> {
    var vistos: map<str, usize> = [];
    var salida: list<str> = [];
    var pendientes: list<str> = [nuevo(desde)];
    var i = 0;
    while i < largo(pendientes) {
        let actual = nuevo(pendientes[i]);
        i = i + 1;
        for a en vecindario(g, vista(actual)) sino [] {
            if !tiene(vistos, a.hasta) {
                poner(vistos, a.hasta, 1);
                anadir(salida, nuevo(a.hasta));
                anadir(pendientes, nuevo(a.hasta));
            }
        }
    }
    ordenar(salida);
    return salida;
}

// ---------- camino mas corto ----------

// El camino de menos peso de `desde` a `hasta`, con los dos extremos dentro.
// Es Dijkstra eligiendo a mano el mas cercano que quede; con el peso no
// negativo que garantiza `usize`, asentar ese nodo es definitivo.
//
// Si `hasta` no se alcanza, sale una lista vacia: no hay camino, que es una
// respuesta. Si `desde` o `hasta` no son nodos del grafo, falla: eso no es un
// camino que falte, es preguntar por algo que no esta. Con dos caminos que
// pesan lo mismo devuelve uno, siempre el mismo: entre los empatados manda el
// nombre menor.
fn camino_mas_corto(g: &Grafo, desde: view, hasta: view) -> list<str> ! {
    if !tiene(g.aristas, desde) { fail "no hay nodo con ese nombre"; }
    if !tiene(g.aristas, hasta) { fail "no hay nodo con ese nombre"; }

    // Lo mas barato que se conoce de cada nodo, de donde se llego, y lo que
    // ya esta asentado.
    var distancia: map<str, usize> = [];
    var previo: map<str, str> = [];
    var asentado: map<str, usize> = [];
    poner(distancia, desde, 0);

    while true {
        // El no asentado con menos distancia. Los que no estan en
        // `distancia` todavia no se alcanzan y no son candidatos: por eso
        // agotarlos no es un fallo, es que no queda nada que mirar.
        //
        // Entre dos con la misma distancia gana el nombre menor, para que el
        // camino no dependa del orden interno de la tabla: con dos rutas que
        // pesan lo mismo, hay que devolver una, y mejor que sea siempre la
        // misma.
        var mejor = 0;
        var hay = false;
        var actual = vacio();
        for nombre, d en distancia {
            if tiene(asentado, nombre) { continue; }
            if !hay || d < mejor || (d == mejor && menor(nombre, vista(actual))) {
                mejor = d;
                hay = true;
                actual = nuevo(nombre);
            }
        }
        if !hay { break; }
        if igual(vista(actual), hasta) { break; }

        poner(asentado, vista(actual), 1);
        let xs = try vecindario(g, vista(actual));
        for a en xs {
            let alt = mejor + a.peso;
            let conocido = obtener(distancia, a.hasta) sino 18446744073709551615;
            if alt < conocido {
                poner(distancia, a.hasta, alt);
                poner(previo, a.hasta, nuevo(actual));
            }
        }
    }

    if !tiene(distancia, hasta) { return []; }
    return try reconstruir(previo, desde, hasta);
}

// Desanda `previo` desde `hasta` hasta `desde`. Lo lleno Dijkstra: cada nodo
// con distancia tiene predecesor, y las distancias bajan al seguirlo, asi
// que el recorrido acaba en `desde`. El `try` no se espera alcanzar nunca;
// esta para que un fallo se vea en vez de dar vueltas sin fin.
fn reconstruir(previo: &map<str, str>, desde: view, hasta: view) -> list<str> ! {
    var al_reves: list<str> = [nuevo(hasta)];
    var actual = nuevo(hasta);
    while !igual(vista(actual), desde) {
        let p = try obtener(previo, vista(actual));
        actual = nuevo(p);
        anadir(al_reves, nuevo(actual));
    }
    return invertida(al_reves);
}

// ---------- orden topologico ----------

// Un orden en el que cada nodo va antes que sus dependientes: si hay una
// arista de `a` a `b`, `a` sale antes que `b`. Entre los que quedan libres
// elige el nombre menor, para que el orden no dependa del orden interno de
// la tabla.
//
// Si hay un ciclo no hay orden posible y falla: un ciclo no da "un orden
// incompleto", da que el orden no existe.
fn orden_topologico(g: &Grafo) -> list<str> ! {
    // Cuantas aristas entran en cada nodo.
    var entrantes: map<str, usize> = [];
    for nombre, _ en g.aristas {
        poner(entrantes, nombre, 0);
    }
    for nombre, _ en g.aristas {
        for a en vecindario(g, nombre) sino [] {
            let antes = obtener(entrantes, a.hasta) sino 0;
            poner(entrantes, a.hasta, antes + 1);
        }
    }

    var puestos: map<str, usize> = [];
    var orden: list<str> = [];
    while largo(orden) < largo(g.aristas) {
        var elegido = vacio();
        var hay = false;
        for nombre, cuantas en entrantes {
            if tiene(puestos, nombre) { continue; }
            if cuantas == 0 && (!hay || menor(nombre, vista(elegido))) {
                elegido = nuevo(nombre);
                hay = true;
            }
        }
        if !hay { fail "el grafo tiene un ciclo: no hay orden topologico"; }

        poner(puestos, vista(elegido), 1);
        anadir(orden, nuevo(elegido));
        for a en vecindario(g, vista(elegido)) sino [] {
            let antes = obtener(entrantes, a.hasta) sino 0;
            if antes > 0 { poner(entrantes, a.hasta, antes - 1); }
        }
    }
    return orden;
}

// ---------- componentes ----------

// Los grupos de nodos conectados entre si, mirando las aristas como si no
// tuvieran direccion. Dentro de cada grupo los nombres van en orden, y los
// grupos salen en el orden del primer nodo que los abre, asi que el
// resultado no depende de la tabla.
//
// Por dentro es union con el camino aplanado sobre las posiciones de los
// nodos: cada arista junta los grupos de sus dos extremos, y al final cada
// posicion busca su raiz. Asi no hay que construir el grafo sin direccion
// entero solo para recorrerlo.
fn componentes(g: &Grafo) -> list<list<str>> {
    var nombres = claves(g.aristas);
    ordenar(nombres);
    let total = largo(nombres);

    var indice: map<str, usize> = [];
    var padre: list<usize> = [];
    for i en 0..total {
        poner(indice, vista(nombres[i]), i);
        anadir(padre, i);
    }

    for i en 0..total {
        for a en vecindario(g, vista(nombres[i])) sino [] {
            let j = obtener(indice, a.hasta) sino i;
            juntar_grupos(padre, i, j);
        }
    }

    // `total` es "sin grupo todavia": cada raiz abre el suyo la primera vez
    // que aparece, y los demas se le cuelgan.
    var grupo_de: list<usize> = [];
    for _i en 0..total {
        anadir(grupo_de, total);
    }
    var salida: list<list<str>> = [];
    for i en 0..total {
        let r = raiz_de(padre, i);
        if grupo_de[r] == total {
            grupo_de[r] = largo(salida);
            anadir(salida, []);
        }
        anadir(salida[grupo_de[r]], nuevo(nombres[i]));
    }
    return salida;
}

// ---------- por dentro ----------

// El vecindario de un nodo, copiado. Falla si el nodo no esta; quien no
// falla hacia fuera lo atrapa con `sino []` y se queda sin vecinos.
//
// Se copia porque `obtener` sobre una lista presta el valor que vive en la
// tabla, y un prestamo no tiene un valor de recambio que darle a `sino`. La
// copia se paga una vez por nodo expandido, no una por arista mirada.
fn vecindario(g: &Grafo, nombre: view) -> list<Arista> ! {
    if !tiene(g.aristas, nombre) { fail "no existe un nodo con ese nombre"; }
    return copiar(try obtener(g.aristas, nombre));
}

// Mete la arista en el nodo, reemplazando el peso si ya habia una igual, y
// devuelve cuantas aristas quedan.
//
// `poner_arista` no puede fallar hacia fuera —acaba de dar de alta el nodo,
// asi que la clave esta— pero `obtener_mut` si falla, y un `sino` necesita
// un valor que usar. El que sobra es la cuenta.
fn meter_arista(g: mut Grafo, desde: view, a: Arista) -> usize ! {
    let xs = try obtener_mut(g.aristas, desde);
    var i = 0;
    while i < largo(xs) {
        if igual(xs[i].hasta, a.hasta) {
            xs[i].peso = a.peso;
            return largo(xs);
        }
        i = i + 1;
    }
    anadir(xs, a);
    return largo(xs);
}

// La raiz del grupo de `i`, aplanando de paso los caminos que se recorren
// para no tener que volver a recorrerlos.
fn raiz_de(padre: mut list<usize>, i: usize) -> usize {
    var r = i;
    while padre[r] != r {
        r = padre[r];
    }
    var k = i;
    while padre[k] != r {
        let siguiente = padre[k];
        padre[k] = r;
        k = siguiente;
    }
    return r;
}

// Junta los grupos de `a` y `b`, si no estaban ya juntos.
fn juntar_grupos(padre: mut list<usize>, a: usize, b: usize) {
    let ra = raiz_de(padre, a);
    let rb = raiz_de(padre, b);
    if ra != rb { padre[rb] = ra; }
}
