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
//
// Todo eso es texto: no necesita backend y vale igual para una terminal que
// para un archivo. El teclado —`modo_crudo`, `modo_normal`, `leer_tecla`— es
// otra cosa: ahi hay que hablar con el terminal, y quien sabe de eso es
// `stty`.

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

// --------------------------------------------------------------- el teclado
//
// Un juego no quiere esperar a Enter ni ver su tecla escrita en la pantalla.
// Eso es lo que apaga `modo_crudo`, y `modo_normal` lo devuelve como estaba.
//
// Quien sabe de esto es `stty`: desde el borde de `externo` solo pasan
// numeros, `bool` y texto, y `tcgetattr` y `tcsetattr` piden un `struct
// termios` que no cabe. Poner y quitar el modo crudo son dos procesos en
// toda la partida, y no se notan.
//
// En crudo, Ctrl-C no mata el proceso: el terminal lo manda como una tecla.
// `leer_tecla` la reconoce, deja el terminal en modo normal y la devuelve
// como "ctrl-c", asi que un programa que se limite a salir al verla no deja
// el terminal roto. Aun asi hay que llamar a `modo_normal` antes de
// terminar: una salida por las bravas —un `fail`, un cierre forzado— no pasa
// por aqui y deja el terminal sin eco; en la shell, `stty sane` lo arregla.

externo "unistd.h" {
    // Si la entrada es un terminal. Sin mirarlo antes, `stty` se queja en
    // cada programa que lea de una tuberia.
    fn isatty(fd: i32) -> i32;
}

externo "stdlib.h" {
    fn system(orden: str) -> i32;
}

externo "stdio.h" {
    // Un byte de la entrada, o -1 al acabarse. Es lo unico que deja leer el
    // borde: `read` pide un puntero al sitio donde escribir, y eso no cabe.
    fn getchar() -> i32;
}

// Si la entrada es un terminal de verdad: lo que hay que mirar antes de
// tocar nada. Una tuberia o un archivo no tienen modo crudo ni teclas.
fn es_terminal() -> bool {
    return isatty(0) != 0;
}

// Pone el terminal en crudo: sin eco, sin esperar a Enter y sin que Ctrl-C
// mate el proceso. Dice si lo pudo poner; en una tuberia no hace nada y dice
// que no.
//
// No se usa `stty raw` porque `raw` apaga tambien el procesado de la salida,
// y entonces un "\n" deja de volver a la primera columna y el dibujo se
// descuadra. Se apagan solo las cuatro cosas que estorban: `-icanon` —la
// linea, que es lo que obliga a pulsar Enter—, `-echo` —el eco—, `-isig`
// —las senales, que es por lo que Ctrl-C llega como byte— y `-ixon` —el pare
// y siga de Ctrl-S—.
fn modo_crudo() -> bool {
    if !es_terminal() { return false; }
    return system(nuevo("stty -icanon -echo -isig -ixon min 1 time 0")) == 0;
}

// Lo devuelve a como estaba: deshace exactamente lo que puso `modo_crudo`.
// Llamarlo dos veces, o sin haber puesto nunca el modo crudo, no hace dano.
fn modo_normal() -> bool {
    if !es_terminal() { return false; }
    return system(nuevo("stty icanon echo isig ixon min 1 time 0")) == 0;
}

// Un byte de la entrada, o -1 si se acabo.
fn leer_byte() -> i64 {
    return getchar() como i64;
}

// Cuantos bytes anuncia el primero de un caracter UTF-8. Es la tabla de
// `std/utf8`, pero mirada desde el primer byte solo: los demas todavia no
// han llegado, y `bytes_de` no dice nada hasta que estan todos. Un byte que
// no empieza ningun caracter anuncia uno.
fn bytes_anunciados(primero: i64) -> usize {
    if primero >= 194 && primero <= 223 { return 2; }
    if primero >= 224 && primero <= 239 { return 3; }
    if primero >= 240 && primero <= 244 { return 4; }
    return 1;
}

// El byte ya leido, con los que le siguen si empieza un caracter UTF-8: una
// tecla no es medio caracter.
fn caracter_de(primero: i64) -> str {
    var s = vacio();
    empujar_byte(s, primero como u8);
    var faltan = bytes_anunciados(primero) - 1;
    while faltan > 0 {
        let c = leer_byte();
        if c < 0 { break; }
        empujar_byte(s, c como u8);
        faltan = faltan - 1;
    }
    return s;
}

// El nombre de las teclas que llegan como un byte por debajo de 32: Ctrl y
// compania.
fn nombre_de_control(b: i64) -> str {
    if b == 0 { return nuevo("ctrl-arroba"); }
    if b >= 1 && b <= 26 {
        var s = nuevo("ctrl-");
        empujar_byte(s, (b + 96) como u8);
        return s;
    }
    if b == 28 { return nuevo("ctrl-barra"); }
    if b == 29 { return nuevo("ctrl-]"); }
    if b == 30 { return nuevo("ctrl-^"); }
    if b == 31 { return nuevo("ctrl-_"); }
    return vacio();
}

// Las secuencias que acaban en una letra —flechas, Inicio, Fin, F1 a F4—, o
// el texto vacio si esa letra no dice nada.
fn por_letra(c: i64) -> str {
    if c == 65 { return nuevo("arriba"); }          // A
    if c == 66 { return nuevo("abajo"); }           // B
    if c == 67 { return nuevo("derecha"); }         // C
    if c == 68 { return nuevo("izquierda"); }       // D
    if c == 70 { return nuevo("fin"); }             // F
    if c == 72 { return nuevo("inicio"); }          // H
    if c == 90 { return nuevo("tabulador_atras"); } // Z, Mayus+Tabulador
    if c == 80 { return nuevo("f1"); }              // P a S, que solo manda ESC O
    if c == 81 { return nuevo("f2"); }
    if c == 82 { return nuevo("f3"); }
    if c == 83 { return nuevo("f4"); }
    return vacio();
}

// Las que llevan un numero antes de la tilde: `ESC [ 3 ~` es Suprimir.
fn por_numero(n: usize) -> str {
    if n == 1 || n == 7 { return nuevo("inicio"); }
    if n == 2 { return nuevo("insertar"); }
    if n == 3 { return nuevo("suprimir"); }
    if n == 4 || n == 8 { return nuevo("fin"); }
    if n == 5 { return nuevo("pagina_arriba"); }
    if n == 6 { return nuevo("pagina_abajo"); }
    if n >= 11 && n <= 15 {
        let k = n - 10;
        return $"f{k}";
    }
    if n >= 17 && n <= 21 {
        let k = n - 11;
        return $"f{k}";
    }
    if n == 23 { return nuevo("f11"); }
    if n == 24 { return nuevo("f12"); }
    return vacio();
}

// Lo que viene detras de un `ESC [` o un `ESC O`. Lo que no se conoce —una
// secuencia con modificadores, como Mayus+flecha, o una tecla que este
// modulo no sabe nombrar— se consume entero y deja el texto vacio.
fn secuencia() -> str {
    let c = leer_byte();
    if c < 0 { return nuevo("escape"); }
    if c < 48 || c > 57 { return por_letra(c); }
    var n = 0;
    var d = c;
    while d >= 48 && d <= 57 {
        n = n * 10 + ((d - 48) como usize);
        d = leer_byte();
    }
    if d == 126 { return por_numero(n); }
    // Un `;` trae modificadores: se tira lo que queda hasta la letra final.
    while d >= 0 && d != 126 && (d < 64 || d > 126) { d = leer_byte(); }
    return vacio();
}

// Lo que sigue a un ESC. El terminal manda una flecha de un golpe —`ESC [ A`
// es un solo `write`—, asi que las letras que faltan ya estan ahi cuando se
// piden. Un ESC suelto no se puede distinguir de un principio de secuencia
// sin un `select` con su tiempo de espera, que el borde no deja usar: por eso
// dos ESC seguidos son la tecla Escape, y un ESC con otra cosa detras es esa
// tecla con Alt.
fn tras_escape() -> str {
    let c = leer_byte();
    if c < 0 || c == 27 { return nuevo("escape"); }
    if c == 91 || c == 79 { return secuencia(); }
    return $"alt-{caracter_de(c)}";
}

// Una tecla, ya traducida, y espera a que la haya.
//
//     flechas     "arriba", "abajo", "izquierda", "derecha"
//     edicion     "inicio", "fin", "insertar", "suprimir", "retroceso"
//     paginas     "pagina_arriba", "pagina_abajo"
//     teclas      "enter", "tabulador", "tabulador_atras", "escape", "f1".."f12"
//     control     "ctrl-a".."ctrl-z" y sus vecinas; "ctrl-c" es una tecla
//     texto       el caracter tal cual y entero: "a", "3", " "
//     con Alt     "alt-a"
//     sin entrada "fin_de_entrada", cuando la entrada se cerro
//
// Dos ESC seguidos son la tecla Escape: un ESC suelto no se distingue del
// principio de una flecha sin un `select` que el borde no deja usar, y
// esperar a ver si llega algo mas dejaria el juego colgado al pulsar Escape.
// Una secuencia que no se conoce —Mayus+flecha, por ejemplo— devuelve el
// texto vacio, que es lo que hay que ignorar.
//
// Necesita `modo_crudo`: sin el, el terminal espera a Enter y va soltando
// las teclas de la linea una a una. Con la entrada cerrada devuelve
// "fin_de_entrada" y no espera, asi que un bucle que no lo mire girara sin
// parar.
fn leer_tecla() -> str {
    let c = leer_byte();
    if c < 0 { return nuevo("fin_de_entrada"); }
    if c == 27 { return tras_escape(); }
    if c == 10 || c == 13 { return nuevo("enter"); }
    if c == 9 { return nuevo("tabulador"); }
    if c == 127 || c == 8 { return nuevo("retroceso"); }
    if c == 3 {
        // Ctrl-C en crudo es una tecla y no una senal. El terminal se deja
        // como estaba antes de devolverla: asi un programa que se limite a
        // salir al verla no lo deja roto.
        modo_normal();
        return nuevo("ctrl-c");
    }
    if c < 32 { return nombre_de_control(c); }
    return caracter_de(c);
}
