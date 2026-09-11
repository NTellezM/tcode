// texto.t — lo que sigue siendo tuyo cuando la biblioteca ya esta escrita.
//
// `repetir`, `unir`, `empieza_con` y `termina_con` estaban aqui copiadas.
// Ahora vienen de `std/texto`, y lo que queda es lo que este archivo de
// verdad ensena: vistas que no reservan memoria, y prestamos mutables.

usar "std/texto";

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
    return $"{borde}\n| {titulo} |\n{borde}\n";
}

fn main() -> usize ! {
    imprimir(marco("safestr"));

    var partes: lista<str> = [];
    anadir(partes, nuevo("hola"));
    anadir(partes, nuevo("mundo"));
    let saludo = unir(partes, ", ");
    imprimir($"{saludo}\n");

    var linea = nuevo("campo1");
    agregar_separador(linea);
    empujar(linea, "campo2");
    agregar_separador(linea);
    empujar(linea, "campo3");
    imprimir($"{linea}\n");

    imprimir($"{empieza_con(saludo, "hola")} {termina_con(saludo, "mundo")}\n");

    let ruta = nuevo("PRE:documento.txt");
    imprimir($"{sin_prefijo(ruta, 4)}  {primera_mitad(ruta)}\n");

    imprimir($"{repetir("-*", 10)}\n");
}
