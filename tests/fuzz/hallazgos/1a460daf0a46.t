
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
        var mejor = 0;
        var hay = false;
        var actual = vacio();
        for nombre, d en distancia {
            if tiene(asentado, nombre) { continue; }
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
// posicion busca su raiz. Asi no hay que construir el grafo sin direccion
// entero solo para recorrerlo.
fn componentes(g: &Grafo) -> list<list<str>> {
    var nombres = claves(g.aristas);
    ordenar(nombres);
    let total = largo(nombres);

    var indice: map<str, usize> = [];
    var padre: list<usize> = [];
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
    }
    return salida;
}

// ---------- por dentro ----------
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
             largo(xs);
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
    return r;
}

// Junta los grupos de `a` y `b`, si no estaban ya juntos.
fn juntar_grupos(padre: mut list<usize>, a: usize, b: usize) {
    let ra = raiz_de(padre, a);
    let rb = raiz_de(padre, b);
    if ra != rb { padre[rb] = ra; }
}
