// ordenar.t — ordena lineas byte a byte, como `LC_ALL=C sort`.
//
//     ./ordenar [-r] [-u] [archivo]
//
// -r invierte el orden; -u deja una sola de cada linea repetida. Sin
// archivo, lee la entrada. Una ultima linea sin salto cuenta igual.

fn partir_lineas(v: view) -> list<str> {
    var salida: list<str> = [];
    var desde = 0;
    var i = 0;
    while i < largo(v) {
        if byte(v, i) == 10 {
            anadir(salida, nuevo(rebanar(v, desde, i)));
            desde = i + 1;
        }
        i = i + 1;
    }
    if desde < largo(v) { anadir(salida, nuevo(rebanar(v, desde, largo(v)))); }
    return salida;
}

fn main() -> usize ! {
    var invertir = false;
    var unicas = false;
    var ruta = vacio();
    var k = 1;
    while k < n_argumentos() {
        let a = argumento(k);
        if a == "-r" {
            invertir = true;
        } else if a == "-u" {
            unicas = true;
        } else if a == "-ru" || a == "-ur" {
            invertir = true;
            unicas = true;
        } else {
            ruta = nuevo(a);
        }
        k = k + 1;
    }
    var texto = vacio();
    if largo(ruta) > 0 {
        texto = try leer_archivo(ruta);
    } else {
        texto = try entrada_completa();
    }
    var ls = partir_lineas(texto);
    ordenar(ls);
    var salida = vacio();
    var i = 0;
    while i < largo(ls) {
        var j = i;
        if invertir { j = largo(ls) - 1 - i; }
        let repetida = unicas && i > 0 && igual(ls[j], ls[if invertir { j + 1 } else { j - 1 }]);
        if !repetida {
            empujar(salida, ls[j]);
            empujar(salida, "\n");
        }
        i = i + 1;
    }
    imprimir(salida);
    return 0;
}
