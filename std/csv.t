// std/csv.t — leer y escribir CSV (lo esencial de RFC 4180).
//
//     let filas = csv.leer(texto);     // a lista<lista<str>>
//     let texto = csv.escribir(filas); // de vuelta, con comillas si hacen falta
//
// Un campo lleva comillas cuando tiene coma, comillas o un salto de linea;
// dentro, una comilla se escribe como dos. Texto intensivo puro: es el tipo
// de biblioteca que ejercita las listas y los prestamos sin tocar nada mas.

fn leer(texto: view) -> lista<lista<str>> {
    var filas: lista<lista<str>> = [];
    var fila: lista<str> = [];
    var campo = vacio();
    var en_comillas = false;
    var i = 0;
    while i < largo(texto) {
        let b = byte(texto, i);
        if en_comillas {
            // Dos comillas seguidas dentro de comillas son una comilla.
            if b == 34 {
                if i + 1 < largo(texto) && byte(texto, i + 1) == 34 {
                    empujar_byte(campo, 34);
                    i = i + 1;
                } else {
                    en_comillas = false;
                }
            } else {
                empujar_byte(campo, b como u8);
            }
            i = i + 1;
            continue;
        }
        if b == 34 {
            en_comillas = true;
        } else if b == 44 {
            anadir(fila, campo);
            campo = vacio();
        } else if b == 10 {
            anadir(fila, campo);
            campo = vacio();
            anadir(filas, fila);
            fila = [];
        } else if b == 13 {
            // El `\r` del CRLF: se ignora fuera de comillas.
        } else {
            empujar_byte(campo, b como u8);
        }
        i = i + 1;
    }
    // La ultima fila, si no termino en salto.
    if largo(campo) > 0 || largo(fila) > 0 {
        anadir(fila, campo);
        anadir(filas, fila);
    }
    return filas;
}

fn escribir(filas: &lista<lista<str>>) -> str {
    var salida = vacio();
    var primera_fila = true;
    for fila en filas {
        if !primera_fila { empujar(salida, "\n"); }
        primera_fila = false;
        var primer_campo = true;
        for campo en fila {
            if !primer_campo { empujar(salida, ","); }
            primer_campo = false;
            escribir_campo(campo, salida);
        }
    }
    return salida;
}

fn escribir_campo(campo: view, salida: mut str) {
    // Comilla solo cuando hace falta: coma (44), comilla (34), LF (10) o CR (13).
    var necesita = false;
    var i = 0;
    while i < largo(campo) {
        let b = byte(campo, i);
        if b == 44 || b == 34 || b == 10 || b == 13 { necesita = true; }
        i = i + 1;
    }
    if !necesita {
        empujar(salida, campo);
        return;
    }
    empujar(salida, "\"");
    i = 0;
    while i < largo(campo) {
        let b = byte(campo, i);
        if b == 34 { empujar(salida, "\"\""); }
        else { empujar_byte(salida, b como u8); }
        i = i + 1;
    }
    empujar(salida, "\"");
}
