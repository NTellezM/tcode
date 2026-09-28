// calc.t — evalua expresiones enteras, una por linea, en `i64`.
//
//     ./calc < cuentas
//
//     expr   := termino (("+" | "-") termino)*
//     termino:= factor (("*" | "/" | "%") factor)*
//     factor := "-" factor | "(" expr ")" | numero
//
// De izquierda a derecha, como en C: `/` trunca hacia cero y `%` lleva el
// signo del dividendo. Es aritmetica comprobada de Tcode: si una cuenta se
// sale de `i64`, o se divide por cero, el programa para en esa linea, con
// lo que ya habia impreso. Una linea que no es una expresion dice `error`.

struct Lector {
    texto: str,
    pos: usize,
}

fn saltar_blancos(l: mut Lector) {
    while l.pos < largo(l.texto) && (byte(l.texto, l.pos) == 32 || byte(l.texto, l.pos) == 9) {
        l.pos = l.pos + 1;
    }
}

// El siguiente byte sin blancos, o 0 al final.
fn mirar(l: mut Lector) -> usize {
    saltar_blancos(l);
    if l.pos >= largo(l.texto) { return 0; }
    return byte(l.texto, l.pos);
}

fn factor(l: mut Lector) -> i64 ! {
    let b = mirar(l);
    if b == 45 {
        l.pos = l.pos + 1;
        let v = try factor(l);
        return -v;
    }
    if b == 40 {
        l.pos = l.pos + 1;
        let v = try expr(l);
        if mirar(l) != 41 { falla "falta )"; }
        l.pos = l.pos + 1;
        return v;
    }
    if b < 48 || b > 57 { falla "se esperaba un numero"; }
    var v: i64 = 0;
    while l.pos < largo(l.texto) && byte(l.texto, l.pos) >= 48 && byte(l.texto, l.pos) <= 57 {
        let d = (byte(l.texto, l.pos) - 48) como i64;
        v = v * 10 + d;
        l.pos = l.pos + 1;
    }
    return v;
}

fn termino(l: mut Lector) -> i64 ! {
    var v = try factor(l);
    while true {
        let b = mirar(l);
        if b != 42 && b != 47 && b != 37 { break; }
        l.pos = l.pos + 1;
        let w = try factor(l);
        if b == 42 {
            v = v * w;
        } else if b == 47 {
            v = v / w;
        } else {
            v = v % w;
        }
    }
    return v;
}

fn expr(l: mut Lector) -> i64 ! {
    var v = try termino(l);
    while true {
        let b = mirar(l);
        if b != 43 && b != 45 { break; }
        l.pos = l.pos + 1;
        let w = try termino(l);
        if b == 43 { v = v + w; } else { v = v - w; }
    }
    return v;
}

fn linea_entera(texto: view) -> i64 ! {
    var l = Lector { texto: nuevo(texto), pos: 0 };
    let v = try expr(l);
    if mirar(l) != 0 { falla "sobra algo"; }
    return v;
}

// La cuenta de una linea como texto, o `error`.
fn resultado(texto: view) -> str ! {
    let v = try linea_entera(texto);
    return texto(v);
}

fn main() -> usize ! {
    let entrada = try entrada_completa();
    var desde = 0;
    var i = 0;
    while desde < largo(entrada) {
        i = desde;
        while i < largo(entrada) && byte(entrada, i) != 10 { i = i + 1; }
        let linea = rebanar(entrada, desde, i);
        let dice = resultado(linea) sino nuevo("error");
        imprimir($"{dice}\n");
        desde = i + 1;
    }
    return 0;
}
