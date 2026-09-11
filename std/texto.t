// std/texto.t — lo que en Python te dan los metodos de `str`.

fn es_blanco(b: usize) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13;
}

fn minusculas(v: view) -> str {
    var salida = vacio();
    var i = 0;
    while i < largo(v) {
        let b = byte(v, i);
        if b >= 65 && b <= 90 {
            // Se reconstruye el byte desplazado a partir de una tabla, porque
            // el lenguaje trabaja con vistas y no con bytes sueltos.
            let alfabeto = "abcdefghijklmnopqrstuvwxyz";
            empujar(salida, rebanar(alfabeto, b - 65, b - 64));
        } else {
            empujar(salida, rebanar(v, i, i + 1));
        }
        i = i + 1;
    }
    return salida;
}

// Parte por espacios, saltos y tabuladores, descartando los vacios.
fn palabras(v: view) -> lista<str> {
    var salida: lista<str> = [];
    var desde = 0;
    var i = 0;
    while i <= largo(v) {
        var corta = true;
        if i < largo(v) { corta = es_blanco(byte(v, i)); }
        if corta {
            if i > desde { anadir(salida, nuevo(rebanar(v, desde, i))); }
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

// Parte por un separador cualquiera, conservando los trozos vacios.
fn dividir(v: view, sep: view) -> lista<str> ! {
    if largo(sep) == 0 { falla "el separador no puede estar vacio"; }
    var salida: lista<str> = [];
    var desde = 0;
    var i = 0;
    while i + largo(sep) <= largo(v) {
        if igual(rebanar(v, i, i + largo(sep)), sep) {
            anadir(salida, nuevo(rebanar(v, desde, i)));
            i = i + largo(sep);
            desde = i;
        } else {
            i = i + 1;
        }
    }
    anadir(salida, nuevo(rebanar(v, desde, largo(v))));
    return salida;
}

fn a_entero(v: view) -> usize ! {
    if largo(v) == 0 { falla "no hay numero que leer"; }
    var n = 0;
    var i = 0;
    while i < largo(v) {
        let b = byte(v, i);
        if b < 48 || b > 57 { falla "eso no es un numero"; }
        n = n * 10 + (b - 48);
        i = i + 1;
    }
    return n;
}
