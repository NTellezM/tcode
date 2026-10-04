// std/terminal.t — mover el cursor y dibujar en una terminal.
//
// Los codigos de escape son texto, asi que esto es TCode puro y no necesita
// backend. Quien lo use decide si su salida va a una terminal de verdad o a
// un archivo; si va a un archivo los codigos se ven como basura, y para eso
// estan `sin_codigos` y `ancho_visible`, que miden lo que se ve y no lo que
// se escribe.
//
// `std/color` pone colores; esto pone lo demas: donde esta el cursor, que se
// borra, una barra de avance y un marco.

use "std/utf8" como U;

// --------------------------------------------------------------- el cursor

fn escape(codigo: view) -> str {
    return $"\x1b[{codigo}";
}

// Sube `n` lineas sin cambiar de columna.
fn subir(n: usize) -> str { return escape($"{n}A"); }

// Baja `n` lineas sin cambiar de columna.
fn bajar(n: usize) -> str { return escape($"{n}B"); }

fn derecha(n: usize) -> str { return escape($"{n}C"); }

fn izquierda(n: usize) -> str { return escape($"{n}D"); }

// Se pone en la columna `n` de la linea en la que este.
fn a_columna(n: usize) -> str { return escape($"{n}G"); }

// Al principio de la linea, para reescribirla: es lo que hace falta para una
// barra de avance que se repinta en su sitio.
fn a_inicio_de_linea() -> str { return escape("G"); }

fn borrar_linea() -> str { return escape("2K"); }

// Borra desde el cursor hasta el final de la pantalla.
fn borrar_hasta_el_final() -> str { return escape("0J"); }

fn borrar_pantalla() -> str { return escape("2J"); }

fn ocultar_cursor() -> str { return escape("?25l"); }

fn mostrar_cursor() -> str { return escape("?25h"); }

fn guardar_cursor() -> str { return escape("s"); }

fn volver_al_cursor() -> str { return escape("u"); }

// ------------------------------------------------------------- lo que se ve

// El byte termina una secuencia de escape.
fn fin_de_escape(b: usize) -> bool {
    return b >= 64 && b <= 126;
}

// El texto sin sus codigos de escape: lo que de verdad se lee.
fn sin_codigos(v: view) -> str {
    var s = vacio();
    var i = 0;
    while i < largo(v) {
        // Toda secuencia de estas empieza por ESC [ y acaba en una letra.
        if byte(v, i) == 27 && i + 1 < largo(v) && byte(v, i + 1) == 91 {
            i = i + 2;
            while i < largo(v) && !fin_de_escape(byte(v, i)) { i = i + 1; }
            if i < largo(v) { i = i + 1; }
        } else {
            empujar_byte(s, byte(v, i) como u8);
            i = i + 1;
        }
    }
    return s;
}

// Lo que ocupa el texto en pantalla: ni los codigos de escape ni los bytes
// cuentan, solo los caracteres y su ancho. Es lo que hay que usar para
// alinear algo que lleva color.
fn ancho_visible(v: view) -> usize {
    return U.ancho(sin_codigos(v));
}

// ------------------------------------------------------------ lo que avanza

// Una barra de avance de `ancho` huecos: `[####......]  40%`.
fn barra(hechos: usize, total: usize, ancho: usize) -> str {
    var llenos = 0;
    if total > 0 { llenos = hechos * ancho / total; }
    if llenos > ancho { llenos = ancho; }
    var s = vacio();
    s.empujar("[");
    var i = 0;
    while i < llenos {
        s.empujar("#");
        i = i + 1;
    }
    while i < ancho {
        s.empujar(".");
        i = i + 1;
    }
    s.empujar("] ");
    var tanto = 0;
    if total > 0 { tanto = hechos * 100 / total; }
    if tanto > 100 { tanto = 100; }
    s.empujar($"{tanto}%");
    return s;
}

// Un cuadro que gira, para decir que algo sigue vivo: se le pasa un contador
// que sube y devuelve el que toca.
fn giro(paso: usize) -> str {
    let cuadros: list<str> = [nuevo("|"), nuevo("/"), nuevo("-"), nuevo("\\")];
    return copiar(cuadros[paso % 4]);
}

// --------------------------------------------------------------- el marco

// Encierra unas lineas en una caja, alineadas por lo que se ve: asi una linea
// con color no descoloca el borde.
fn marco(lineas: &list<str>) -> list<str> {
    var ancho = 0;
    for l en lineas {
        let w = ancho_visible(l);
        if w > ancho { ancho = w; }
    }
    var borde = vacio();
    borde.empujar("+");
    var i = 0;
    while i < ancho + 2 {
        borde.empujar("-");
        i = i + 1;
    }
    borde.empujar("+");
    var salida: list<str> = [];
    salida.anadir(copiar(borde));
    for l en lineas {
        var fila = vacio();
        fila.empujar("| ");
        fila.empujar(l);
        var hueco = ancho - ancho_visible(l);
        while hueco > 0 {
            fila.empujar(" ");
            hueco = hueco - 1;
        }
        fila.empujar(" |");
        salida.anadir(fila);
    }
    salida.anadir(borde);
    return salida;
}
