// std/cuenta.t — lo que en Python te da `collections.Counter`.

use "std/texto";

fn contar(cosas: &list<str>) -> map<str, usize> {
    var m: map<str, usize> = [];
    for x en cosas {
        let previo = obtener(m, x) sino 0;
        poner(m, x, previo + 1);
    }
    return m;
}

// Las `cuantas` claves con mas cuenta, de mayor a menor. Seleccion directa:
// con pocas es mas barato que ordenar el vocabulario entero.
fn mayores(m: &map<str, usize>, cuantas: usize) -> list<str> {
    var salida: list<str> = [];
    var tope = 0;
    var primera = true;

    var puestas = 0;
    while puestas < cuantas {
        var mejor = 0;
        var ganadora = vacio();
        for clave, veces en m {
            var cabe = true;
            if !primera { cabe = veces < tope; }
            if veces > mejor && cabe {
                mejor = veces;
                ganadora = nuevo(clave);
            }
        }
        if mejor == 0 { return salida; }
        anadir(salida, ganadora);
        tope = mejor;
        primera = false;
        puestas = puestas + 1;
    }
    return salida;
}
