// wc.t — lineas, palabras y bytes, como `wc` sin opciones.
//
//     ./wc archivo...      una fila por archivo, y el total si son varios
//     ./wc < archivo       de la entrada
//
// Una palabra es lo que hay entre blancos (espacio, \t, \n, \v, \f, \r)
// con al menos un caracter imprimible, byte a byte, como `wc` de GNU con
// LC_ALL=C: un byte que no se imprime —un cero, uno no ASCII— ni separa
// palabras ni empieza una. Las columnas salen separadas por un espacio: el
// ancho de `wc` depende del sistema, los numeros no.

usar "std/caracter" como c;

struct Cuenta {
    lineas: usize,
    palabras: usize,
    bytes: usize,
}

fn contar(v: view) -> Cuenta {
    var r = Cuenta { lineas: 0, palabras: 0, bytes: largo(v) };
    var dentro = false;
    var i = 0;
    while i < largo(v) {
        let b = byte(v, i);
        if b == 10 { r.lineas = r.lineas + 1; }
        if c.es_blanco(b) || b == 11 || b == 12 {
            dentro = false;
        } else if b >= 33 && b <= 126 && !dentro {
            r.palabras = r.palabras + 1;
            dentro = true;
        }
        i = i + 1;
    }
    return r;
}

fn fila(r: &Cuenta, nombre: view) -> str {
    if largo(nombre) == 0 { return $"{r.lineas} {r.palabras} {r.bytes}\n"; }
    return $"{r.lineas} {r.palabras} {r.bytes} {nombre}\n";
}

// Cuenta un archivo, lo imprime y lo suma al total. Si no se puede leer,
// falla y el total no cambia.
fn uno(ruta: view, total: mut Cuenta) -> bool ! {
    let contenido = try leer_archivo(ruta);
    let r = contar(contenido);
    imprimir(fila(r, ruta));
    total.lineas = total.lineas + r.lineas;
    total.palabras = total.palabras + r.palabras;
    total.bytes = total.bytes + r.bytes;
    return true;
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        let todo = try entrada_completa();
        imprimir(fila(contar(todo), ""));
        return 0;
    }
    var total = Cuenta { lineas: 0, palabras: 0, bytes: 0 };
    var fallos = 0;
    var k = 1;
    while k < n_argumentos() {
        let ruta = argumento(k);
        if !(uno(ruta, total) sino false) {
            imprimir_error($"wc: {ruta}: no se pudo leer\n");
            fallos = fallos + 1;
        }
        k = k + 1;
    }
    if n_argumentos() > 2 { imprimir(fila(total, "total")); }
    if fallos > 0 { return 1; }
    return 0;
}
