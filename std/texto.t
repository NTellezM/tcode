// std/texto.t — lo que en Python te dan los metodos de `str`.

usar "std/caracter";

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

// Como `palabras`, pero cortando por cualquier cosa que no sea letra ni
// digito: de "hola, mundo!" salen "hola" y "mundo", sin la puntuacion. Es lo
// que quiere un contador de palabras; `palabras` es lo que quiere quien parte
// una linea en campos.
fn terminos(v: view) -> lista<str> {
    var salida: lista<str> = [];
    var desde = 0;
    var i = 0;
    while i <= largo(v) {
        var corta = true;
        if i < largo(v) { corta = !es_alfanumerico(byte(v, i)); }
        if corta {
            if i > desde { anadir(salida, nuevo(rebanar(v, desde, i))); }
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

// Parte por un separador cualquiera, conservando los trozos vacios.
fn partir(v: view, sep: view) -> lista<str> ! {
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

// ------------------------------------------------------------------
// Recortar y comparar
// ------------------------------------------------------------------

// Quita los blancos de los dos extremos. Devuelve una VISTA del original:
// no copia nada, y por eso presta de lo que le pasaron.
fn recortar(v: view) -> view {
    var desde = 0;
    while desde < largo(v) && es_blanco(byte(v, desde)) {
        desde = desde + 1;
    }
    var hasta = largo(v);
    while hasta > desde && es_blanco(byte(v, hasta - 1)) {
        hasta = hasta - 1;
    }
    return rebanar(v, desde, hasta);
}

fn empieza_con(v: view, prefijo: view) -> bool {
    if largo(v) < largo(prefijo) { return false; }
    return igual(rebanar(v, 0, largo(prefijo)), prefijo);
}

fn termina_con(v: view, sufijo: view) -> bool {
    if largo(v) < largo(sufijo) { return false; }
    return igual(rebanar(v, largo(v) - largo(sufijo), largo(v)), sufijo);
}

// Donde empieza `aguja` dentro de `pajar`. Falla si no esta, para que no se
// pueda confundir "esta en la posicion 0" con "no esta".
fn indice_de(pajar: view, aguja: view) -> usize ! {
    if largo(aguja) == 0 { return 0; }
    if largo(aguja) > largo(pajar) { falla "no esta"; }
    var i = 0;
    while i + largo(aguja) <= largo(pajar) {
        if igual(rebanar(pajar, i, i + largo(aguja)), aguja) { return i; }
        i = i + 1;
    }
    falla "no esta";
}

fn contiene(pajar: view, aguja: view) -> bool {
    let donde = indice_de(pajar, aguja) sino 18446744073709551615;
    return donde != 18446744073709551615;
}

// ------------------------------------------------------------------
// Construir
// ------------------------------------------------------------------

fn repetir(v: view, veces: usize) -> str {
    var s = vacio();
    var i = 0;
    while i < veces {
        empujar(s, v);
        i = i + 1;
    }
    return s;
}

fn unir(trozos: &lista<str>, sep: view) -> str {
    var s = vacio();
    var primero = true;
    for t en trozos {
        if !primero { empujar(s, sep); }
        empujar(s, t);
        primero = false;
    }
    return s;
}

fn reemplazar(v: view, viejo: view, nuevo_texto: view) -> str ! {
    if largo(viejo) == 0 { falla "no se puede reemplazar la cadena vacia"; }
    var s = vacio();
    var i = 0;
    while i < largo(v) {
        var casa = false;
        if i + largo(viejo) <= largo(v) {
            casa = igual(rebanar(v, i, i + largo(viejo)), viejo);
        }
        if casa {
            empujar(s, nuevo_texto);
            i = i + largo(viejo);
        } else {
            empujar(s, rebanar(v, i, i + 1));
            i = i + 1;
        }
    }
    return s;
}

// Rellena con espacios a la derecha hasta `ancho`. Si ya es mas largo, lo
// deja como esta: recortar por sorpresa esconde datos.
fn rellenar(v: view, ancho: usize) -> str {
    var s = nuevo(v);
    if largo(v) < ancho {
        let hueco = repetir(" ", ancho - largo(v));
        empujar(s, hueco);
    }
    return s;
}

// Lo mismo, pero pegado a la derecha: para columnas de numeros.
fn alinear(v: view, ancho: usize) -> str {
    if largo(v) >= ancho { return nuevo(v); }
    var s = repetir(" ", ancho - largo(v));
    empujar(s, v);
    return s;
}
