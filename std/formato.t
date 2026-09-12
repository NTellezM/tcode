// std/formato.t — poner numeros y tablas donde se puedan leer.

usar "std/texto";
usar "std/numero";
usar "std/lista";

// Un decimal con tantos decimales como se pidan, redondeando. `imprimir`
// usa `%g`, que sirve para mirar pero no para una tabla.
fn con_decimales(x: f64, cuantos: usize) -> str {
    var escala: f64 = 1;
    var i = 0;
    while i < cuantos { escala = escala * 10.0; i = i + 1; }

    let negativo = x < 0.0;
    let magnitud = absoluto(x);
    let entero_escalado = redondear(magnitud * escala) como u64;
    let entera = entero_escalado / (escala como u64);
    let resto = entero_escalado - entera * (escala como u64);

    var s = vacio();
    if negativo { empujar(s, "-"); }
    empujar(s, texto(entera como usize));
    if cuantos > 0 {
        empujar(s, ".");
        // Los ceros de delante que `texto` se come.
        let digitos = texto(resto como usize);
        var faltan = cuantos - menor_de(cuantos, largo(vista(digitos)));
        while faltan > 0 { empujar(s, "0"); faltan = faltan - 1; }
        empujar(s, digitos);
    }
    return s;
}

// Un numero con separador de millares: 1234567 -> 1.234.567
fn con_millares(n: usize) -> str {
    let d = texto(n);
    var s = vacio();
    var i = 0;
    while i < largo(vista(d)) {
        let quedan = largo(vista(d)) - i;
        if i > 0 && quedan % 3 == 0 { empujar(s, "."); }
        empujar(s, rebanar(vista(d), i, i + 1));
        i = i + 1;
    }
    return s;
}

// Una fila de tabla: cada celda rellenada al ancho que le toca.
fn fila(celdas: &lista<str>, anchos: &lista<usize>, sep: view) -> str {
    var s = vacio();
    var i = 0;
    for c en celdas {
        if i > 0 { empujar(s, sep); }
        let ancho = if i < largo(anchos) { anchos[i] } else { largo(vista(c)) };
        empujar(s, rellenar(vista(c), ancho));
        i = i + 1;
    }
    return nuevo(recortar(vista(s)));
}

// Los anchos que necesita cada columna para que todo cuadre.
fn anchos_de(filas: &lista<lista<str>>) -> lista<usize> {
    var anchos: lista<usize> = [];
    for f en filas {
        var i = 0;
        for c en f {
            while largo(anchos) <= i { anadir(anchos, 0); }
            if largo(vista(c)) > anchos[i] { anchos[i] = largo(vista(c)); }
            i = i + 1;
        }
    }
    return anchos;
}
