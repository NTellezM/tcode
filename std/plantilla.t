// std/plantilla.t — rellenar una plantilla con `{clave}`.
//
//     plantilla.rellenar("hola, {nombre}", datos)   // "hola, Ana"
//
// `datos` es un `mapa<str, str>`. Una clave que no esta se rellena con nada.
// Las llaves se escapan doblandolas: `{{` y `}}`.

fn rellenar(patron: view, datos: &map<str, str>) -> str {
    var salida = vacio();
    var i = 0;
    while i < largo(patron) {
        let b = byte(patron, i);
        if b == 123 && i + 1 < largo(patron) && byte(patron, i + 1) == 123 {
            empujar(salida, "{"); i = i + 2; continue;
        }
        if b == 125 && i + 1 < largo(patron) && byte(patron, i + 1) == 125 {
            empujar(salida, "}"); i = i + 2; continue;
        }
        if b == 123 {
            var j = i + 1;
            while j < largo(patron) && byte(patron, j) != 125 { j = j + 1; }
            let clave = rebanar(patron, i + 1, j);
            let v = obtener(datos, clave) sino "";
            empujar(salida, v);
            i = j + 1;
            continue;
        }
        empujar_byte(salida, b como u8);
        i = i + 1;
    }
    return salida;
}
