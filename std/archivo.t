// std/archivo.t — leer archivos con memoria acotada.
//
// `leer_archivo` sigue siendo lo mas comodo cuando cabe entero. Estas
// funciones leen como mucho `tamano` bytes cada vez y permiten procesar un
// archivo grande sin reservar su tamaño completo.

// Recorre el archivo de principio a fin. Cada parte solo vive durante la
// llamada a `visitar`, así que la memoria usada no crece con el archivo.
fn por_partes<F>(ruta: view, tamano: usize, visitar: F) ! {
    if tamano == 0 { fail "el tamano de cada parte tiene que ser mayor que cero"; }
    var desde = 0;
    var seguir = true;
    while seguir {
        let parte = try leer_parte_archivo(ruta, desde, tamano);
        if largo(parte) == 0 {
            seguir = false;
        } else {
            visitar(vista(parte));
            desde = desde + largo(parte);
        }
    }
}

// La variante que conserva las partes. Es útil si se necesitan después; para
// memoria acotada usa `por_partes`.
fn partes_de_archivo(ruta: view, tamano: usize) -> list<str> ! {
    if tamano == 0 { fail "el tamano de cada parte tiene que ser mayor que cero"; }
    var salida: list<str> = [];
    var desde = 0;
    var seguir = true;
    while seguir {
        let parte = try leer_parte_archivo(ruta, desde, tamano);
        if largo(parte) == 0 {
            seguir = false;
        } else {
            desde = desde + largo(parte);
            anadir(salida, parte);
        }
    }
    return salida;
}
