// texto.t — una libreria de texto escrita en safestr.
//
// Ninguna funcion de aqui puede tener las cuatro clases de fallo que
// encontramos auditando la libreria en C: el compilador las rechaza.

fn repetir(patron: view, veces: usize) -> str {
    var s = vacio();
    var i = 0;
    while i < veces {
        empujar(s, patron);
        i = i + 1;
    }
    return s;
}

fn unir(a: view, b: view, sep: view) -> str {
    var s = nuevo(a);
    empujar(s, sep);
    empujar(s, b);
    return s;
}

fn empieza_con(texto: view, prefijo: view) -> bool {
    let n = largo(prefijo);
    if largo(texto) < n {
        return false;
    }
    return igual(rebanar(texto, 0, n), prefijo);
}

fn termina_con(texto: view, sufijo: view) -> bool {
    let n = largo(sufijo);
    let m = largo(texto);
    if m < n {
        return false;
    }
    return igual(rebanar(texto, m - n, m), sufijo);
}

// Estas dos devuelven una vista atada a su parametro: no reservan un solo
// byte. El compilador comprueba que el texto al que apuntan sobrevive a la
// llamada, y mantiene vivo el prestamo en quien llama.
fn sin_prefijo(v: view, n: usize) -> view {
    if largo(v) < n {
        return v;
    }
    return rebanar(v, n, largo(v));
}

fn primera_mitad(v: view) -> view {
    return rebanar(v, 0, largo(v) / 2);
}

// `mut str` es prestamo mutable: la funcion modifica el string del que llama,
// sin tomar posesion de el.
fn agregar_separador(s: mut str) {
    empujar(s, " | ");
}

fn marco(titulo: view) -> str {
    let borde = repetir("=", largo(titulo) + 4);
    var s = vacio();
    empujar(s, borde);
    empujar(s, "\n| ");
    empujar(s, titulo);
    empujar(s, " |\n");
    empujar(s, borde);
    empujar(s, "\n");
    return s;
}

fn main() -> usize {
    let cabecera = marco("safestr");
    imprimir(cabecera);

    let saludo = unir("hola", "mundo", ", ");
    imprimir(saludo);
    imprimir("\n");

    var linea = nuevo("campo1");
    agregar_separador(linea);
    empujar(linea, "campo2");
    agregar_separador(linea);
    empujar(linea, "campo3");
    imprimir(linea);
    imprimir("\n");

    imprimir(empieza_con(saludo, "hola"));
    imprimir(" ");
    imprimir(termina_con(saludo, "mundo"));
    imprimir("\n");

    let ruta = nuevo("PRE:documento.txt");
    imprimir(sin_prefijo(ruta, 4));
    imprimir("  ");
    imprimir(primera_mitad(ruta));
    imprimir("\n");

    let barras = repetir("-*", 10);
    imprimir(barras);
    imprimir("\n");
}
