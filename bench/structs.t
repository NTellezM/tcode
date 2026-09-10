// Structs prestados: mide si la indireccion del `&` cuesta algo.
struct Punto { x: usize, y: usize }

fn dist2(a: &Punto, b: &Punto) -> usize {
    var dx: usize = 0;
    if a.x > b.x { dx = a.x - b.x; } else { dx = b.x - a.x; }
    var dy: usize = 0;
    if a.y > b.y { dy = a.y - b.y; } else { dy = b.y - a.y; }
    return dx * dx + dy * dy;
}

fn main() -> usize {
    var p: Punto = Punto { x: 0, y: 0 };
    var q: Punto = Punto { x: 3, y: 4 };
    var acc: usize = 0;
    var i: usize = 0;
    while i < 100000000 {
        p.x = i % 1000;
        q.y = i % 977;
        acc = acc + dist2(p, q) % 1024;
        i = i + 1;
    }
    imprimir(acc);
    imprimir("\n");
    return 0;
}
