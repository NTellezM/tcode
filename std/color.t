// std/color.t — colores y estilos ANSI para la terminal.
//
//     imprimir($"{color.rojo("error")} y {color.verde("bien")}\n");
//     imprimir(color.negrita("titulo"));
//
// Los codigos son los de ANSI: `ESC[32m ... ESC[0m`. No se pregunta si la
// salida es una terminal —no hay forma de saberlo desde aqui—; el que llama
// decide si los usa (por ejemplo, si `--color` o si no es una tuberia).

// El texto entre el codigo y el reset.
fn pintar(codigo: view, texto: view) -> str {
    var s = vacio();
    empujar_byte(s, 27); // ESC
    empujar(s, "[");
    empujar(s, codigo);
    empujar(s, "m");
    empujar(s, texto);
    empujar_byte(s, 27);
    empujar(s, "[0m");
    return s;
}

fn negrita(texto: view) -> str { return pintar("1", texto); }
fn tenue(texto: view) -> str { return pintar("2", texto); }
fn subrayado(texto: view) -> str { return pintar("4", texto); }
fn invertido(texto: view) -> str { return pintar("7", texto); }

fn negro(texto: view) -> str { return pintar("30", texto); }
fn rojo(texto: view) -> str { return pintar("31", texto); }
fn verde(texto: view) -> str { return pintar("32", texto); }
fn amarillo(texto: view) -> str { return pintar("33", texto); }
fn azul(texto: view) -> str { return pintar("34", texto); }
fn magenta(texto: view) -> str { return pintar("35", texto); }
fn cian(texto: view) -> str { return pintar("36", texto); }
fn blanco(texto: view) -> str { return pintar("37", texto); }

// Los 8 bits de color: 256 colores por numero.
fn color_256(n: usize, texto: view) -> str {
    return pintar($"38;5;{n}", texto);
}
