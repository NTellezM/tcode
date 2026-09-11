// lib/texto.t — utilidades de texto. No sabe nada del informe.

fn repetir(patron: view, veces: usize) -> str {
    var s = vacio();
    var i = 0;
    while i < veces {
        empujar(s, patron);
        i = i + 1;
    }
    return s;
}

fn rellenar(v: view, ancho: usize) -> str {
    var s = nuevo(v);
    let n = largo(v);
    if n < ancho {
        let hueco = repetir(" ", ancho - n);
        empujar(s, hueco);
    }
    return s;
}
