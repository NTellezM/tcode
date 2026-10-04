// base64.t — codifica y decodifica base64 (RFC 4648), como `base64`.
//
//     ./base64 < datos          codifica, en lineas de 76 caracteres
//     ./base64 -d < texto       decodifica; los saltos de linea no cuentan
//
// Lee y escribe bytes: un cero en medio pasa igual que cualquier otro. La
// codificacion vive en `std/base64`; aqui solo queda el formato de fichero.

#importar "base64.t" como b64;

// El de fichero: lineas de 76, y un salto final.
fn envolver(v: view) -> str {
    var salida = vacio();
    var i = 0;
    while i < largo(v) {
        if i > 0 && i % 76 == 0 { empujar(salida, "\n"); }
        empujar_byte(salida, byte(v, i) como u8);
        i = i + 1;
    }
    if largo(salida) > 0 { empujar(salida, "\n"); }
    return salida;
}

fn main() -> usize ! {
    let entrada = try entrada_completa();
    if n_argumentos() > 1 && argumento(1) == "-d" {
        let datos = b64.decodificar(entrada) sino vacio();
        if largo(datos) == 0 && largo(entrada) > 0 {
            // Una entrada que solo son saltos de linea no es un error.
            var solo_saltos = true;
            var i = 0;
            while i < largo(entrada) {
                if byte(entrada, i) != 10 && byte(entrada, i) != 13 { solo_saltos = false; }
                i = i + 1;
            }
            if !solo_saltos {
                imprimir_error("base64: la entrada no es base64\n");
                return 1;
            }
        }
        imprimir(datos);
        return 0;
    }
    imprimir(envolver(b64.codificar(entrada)));
    return 0;
}
