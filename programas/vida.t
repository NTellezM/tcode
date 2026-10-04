// vida.t — el juego de la vida de Conway, con los bordes muertos.
//
//     ./vida rejilla.txt generaciones
//
// La rejilla es un rectangulo de `.` (muerta) y `#` (viva), una fila por
// linea. Imprime la rejilla tras las generaciones pedidas.

use "std/texto" como t;

struct Rejilla {
    ancho: usize,
    alto: usize,
    celdas: list<bool>,
}

fn leer(texto: view) -> Rejilla ! {
    let filas = t.lineas(texto);
    if largo(filas) == 0 { fail "la rejilla esta vacia"; }
    let ancho = largo(filas[0]);
    var celdas: list<bool> = [];
    for f en filas {
        if largo(f) != ancho { fail "las filas no miden lo mismo"; }
        var i = 0;
        while i < ancho {
            let b = byte(f, i);
            if b == 35 {
                anadir(celdas, true);
            } else if b == 46 {
                anadir(celdas, false);
            } else {
                fail "una celda que no es `.` ni `#`";
            }
            i = i + 1;
        }
    }
    return Rejilla { ancho: ancho, alto: largo(filas), celdas: celdas };
}

fn viva(r: &Rejilla, x: usize, y: usize) -> bool {
    return r.celdas[y * r.ancho + x];
}

fn vecinas(r: &Rejilla, x: usize, y: usize) -> usize {
    var n = 0;
    var dy = 0;
    while dy < 3 {
        var dx = 0;
        while dx < 3 {
            // `x + dx - 1` sin bajar de cero: el borde se salta.
            if (dx != 1 || dy != 1) && x + dx >= 1 && y + dy >= 1
            && x + dx - 1 < r.ancho && y + dy - 1 < r.alto {
                if viva(r, x + dx - 1, y + dy - 1) { n = n + 1; }
            }
            dx = dx + 1;
        }
        dy = dy + 1;
    }
    return n;
}

fn siguiente(r: &Rejilla) -> Rejilla {
    var celdas: list<bool> = [];
    var y = 0;
    while y < r.alto {
        var x = 0;
        while x < r.ancho {
            let n = vecinas(r, x, y);
            anadir(celdas, n == 3 || n == 2 && viva(r, x, y));
            x = x + 1;
        }
        y = y + 1;
    }
    return Rejilla { ancho: r.ancho, alto: r.alto, celdas: celdas };
}

fn dibujar(r: &Rejilla) -> str {
    var salida = vacio();
    var y = 0;
    while y < r.alto {
        var x = 0;
        while x < r.ancho {
            if viva(r, x, y) { empujar(salida, "#"); } else { empujar(salida, "."); }
            x = x + 1;
        }
        empujar(salida, "\n");
        y = y + 1;
    }
    return salida;
}

fn main() -> usize ! {
    if n_argumentos() != 3 {
        imprimir_error("uso: vida rejilla.txt generaciones\n");
        return 2;
    }
    let texto = try leer_archivo(argumento(1));
    let generaciones = try t.a_entero(argumento(2));
    var r = try leer(texto);
    var g = 0;
    while g < generaciones {
        r = siguiente(r);
        g = g + 1;
    }
    imprimir(dibujar(r));
    return 0;
}
