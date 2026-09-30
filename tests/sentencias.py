"""
Programas que mueven un valor con duenio por algunos caminos y por otros
no, dentro de bucles, `match` con guardas, `continue` y `break`.

Prueba P14: el generador de C lleva una bandera `ss_vivo_x` para las
variables que se mueven en algun camino pero no en todos, y libera segun
el camino que se tomo. Si la lleva mal, ASan ve un doble free (libera lo
que ya se movio) o una fuga (no libera lo que seguia siendo nuestro).

Los casos son validos por construccion: compilan, corren, y lo unico que
se comprueba es que ASan y UBSan no vean nada.

Los textos son largos a proposito: una cadena corta no mueve el buffer
al crecer, y un uso tras liberar pasaria desapercibido incluso para ASan.

Se recorren con `for i en [0, 1, 2, 3, 4]`, no con un rango `0..5`:
los rangos son azucar de `tcodec`, y estos casos los compila Python.

Los casos con `continue` dentro de un `match` no usan despues la variable
movida: el comprobador no modela que `continue` sale del camino, y la
rechaza. Queda anotado como limite.
"""

CASOS = [
    ("if + continue mueve a un lado", '''fn consumir(x: str) -> usize { return largo(x); }

fn main() -> usize {
    var total: usize = 0;
    for i en [0, 1, 2, 3, 4] {
        var x = nuevo("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        if i == 2 {
            imprimir(consumir(x));
            continue;
        }
        total = total + largo(x);
    }
    imprimir(total);
    return 0;
}
'''),
    ("match + continue mueve en un brazo", '''fn consumir(x: str) -> usize { return largo(x); }

enum Clave { A, B }

fn main() -> usize {
    var total: usize = 0;
    for i en [0, 1, 2, 3, 4] {
        var x = nuevo("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        let k = if i % 2 == 0 { Clave.A } else { Clave.B };
        match k {
            Clave.A -> {
                imprimir(consumir(x));
                continue;
            }
            Clave.B -> { }
        }
        total = total + 1;
    }
    imprimir(total);
    return 0;
}
'''),
    ("match con guarda que puede no casar", '''fn consumir(x: str) -> usize { return largo(x); }

enum Clave { A, B }

fn main() -> usize {
    var total: usize = 0;
    for i en [0, 1, 2, 3, 4] {
        var x = nuevo("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        let k = Clave.A;
        match k {
            Clave.A if i == 2 -> {
                imprimir(consumir(x));
                continue;
            }
            Clave.A -> { }
            Clave.B -> { }
        }
        total = total + 1;
    }
    imprimir(total);
    return 0;
}
'''),
    ("break dentro de un bucle anidado", '''fn consumir(x: str) -> usize { return largo(x); }

fn main() -> usize {
    var total: usize = 0;
    for i en [0, 1, 2] {
        var x = nuevo("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        for j en [0, 1, 2] {
            if j == 1 {
                imprimir(consumir(x));
                break;
            }
            total = total + largo(x);
        }
    }
    imprimir(total);
    return 0;
}
'''),
    ("if/else if con continue y break", '''fn consumir(x: str) -> usize { return largo(x); }

fn main() -> usize {
    var total: usize = 0;
    for i en [0, 1, 2, 3, 4] {
        var x = nuevo("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        if i == 2 {
            imprimir(consumir(x));
            continue;
        } else if i == 4 {
            imprimir(consumir(x));
            break;
        }
        total = total + largo(x);
    }
    imprimir(total);
    return 0;
}
'''),
]
