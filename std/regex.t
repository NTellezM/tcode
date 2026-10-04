// std/regex.t — expresiones regulares, al estilo de las de siempre.
//
//     let p = try regex.compilar("(\\d+)-(\\d+)");
//     regex.casamenta(p, "12-34")                 // true
//     regex.busca(p, "voy del 12-34 al 56")        // true
//     let r = try regex.buscar(p, "voy del 12-34")  // r.desde, r.hasta
//     let cs = try regex.capturas(p, "12-34")       // ["12-34", "12", "34"]
//     regex.reemplazar_todo(p, "12-34", "$2:$1")    // "34:12"
//     regex.partir(regex.compilar(", *") sino ..., "a, b")  // ["a", "b"]
//
// SINTAXIS QUE ENTIENDE
//
//     literales       `abc`
//     comodin         `.`   cualquier byte menos el salto de linea
//     cuantificadores `*`, `+`, `?`, los tres glotones
//     clases          `[a-z]`, `[^0-9]`, con `-` para rangos
//     anclas          `^` principio del texto, `$` final del texto
//     alternancia     `a|b`
//     grupos          `( ... )`, que capturan
//     escapes         `\d \D \w \W \s \S`, y `\.` `\*` `\\` y compañia para
//                     los metacaracteres; tambien `\n`, `\t` y `\r`
//
// SINTAXIS QUE NO ENTIENDE, A PROPOSITO
//
//     `{n,m}`             las llaves son literales
//     version perezosa    `*?`, `+?` y `??` fallan al compilar, con motivo
//     miradas adelante    `(?=...)` no existe: un `?` tras `(` es un error
//     modo multilinea     `^` y `$` solo valen en los extremos del texto
//     `\b`, `\A`, `\z`    no existen; una barra invertida ante una letra que
//                         no sea de las de arriba da esa letra como literal
//
// Se trabaja con BYTES, no con caracteres: el patron y el texto son `view` y
// cada posicion es un byte. Por eso `.` casa con un byte cualquiera de un
// caracter UTF-8 y no con el caracter entero, y por eso `\w` tiene por letra
// todo byte >= 128, que es lo mismo que hace `std/caracter.t`. Los rangos de
// las clases y los numeros de `$1` tambien son de bytes.
//
// EL TOPE DE PASOS
//
// Un motor de retroceso se cuelga con un patron como `(a+)+b` contra un texto
// largo de aes: hay tantas maneras de repartir las aes entre los dos `+` que
// los intentos crecen de forma exponencial. Este modulo lleva la cuenta de
// los pasos y corta. El tope es de un millon de pasos mas veinte por cada
// byte del texto: asi un patron lineal sobre un texto largo nunca se
// confunde con uno explosivo, y el caso malo se corta enseguida en vez de
// dejar el programa colgado. Ademas, una vuelta de `*` o de `+` que no
// consume nada —la de `(a*)*`, por ejemplo— se corta en cuanto se ve que no
// avanza: eso no gasta pasos ni cambia lo que el patron significa.
//
// Al agotarse, `buscar` y `capturas` fallan con "el patron es demasiado
// costoso para este texto". Las que no pueden fallar segun su firma
// (`casamenta`, `busca`, `reemplazar`, `reemplazar_todo`, `partir`) no
// tienen por donde dar ese motivo: se comportan como si no hubiera
// coincidencia, o cortan por donde iban. Para distinguir "no casa" de "es
// demasiado costoso" estan `buscar` y `capturas`.
//
// CHOQUES DE NOMBRES
//
// Los nombres de `std/` no llevan prefijo, y `partir` y `reemplazar` se
// llaman igual que los de `std/texto.t`. Un programa que use los dos modulos
// tiene que darle nombre a uno: `use "std/regex" como re;` y luego
// `re.partir(...)`. Ningun otro nombre de este modulo choca con `std/`.
//
// DOS DECISIONES QUE SE NOTAN
//
//     * `partir` no parte por una coincidencia vacia: un patron que casa con
//       la cadena vacia no trocea el texto por cada byte.
//     * `Rango` usa el intervalo `[desde, hasta)`, como `rebanar`: `hasta`
//       es el primero que ya no es de la coincidencia.

use "std/caracter" como c;

// ------------------------------------------------------------------
// El patron, ya compilado
// ------------------------------------------------------------------

// La etiqueta de un nodo del arbol que sale de leer el patron y la de una
// instruccion del programa van en el mismo `enum`: asi no hay dos listas de
// nombres parecidos, y `Principio` y `Final` valen para las dos cosas.
enum Forma {
    // nodos
    Vacio, Letra, Punto, Conjunto, Concat, Alterna,
    Estrella, Mas, Opcion, Grupo, Principio, Final,
    // instrucciones
    Byte, Cualquiera, Clase, Bifurca, Salta, Marca, Casa, Guarda_loop, Progreso,
}

// Una instruccion. `x` e `y` son lo que signifique cada una, y los saltos
// son RELATIVOS a la instruccion: el destino es `pc + 1 + x`. Relativos y no
// absolutos porque asi el programa se puede armar por trozos sin tener que
// reescribir los saltos que ya estaban.
struct Instr { op: Forma, x: i64, y: i64 }

// Un nodo del arbol. `a` y `b` son indices a otros nodos, y tambien guardan
// el byte de una letra o el numero de una clase.
struct Nodo { forma: Forma, a: usize, b: usize, grupo: usize }

// El patron compilado y todo lo que necesita quien lo casa.
struct Patron {
    programa: list<Instr>,
    clases: list<list<bool>>,
    grupos: usize, // cuantos grupos hay, contando el 0 (la coincidencia entera)
}

// Donde empieza y donde acaba una coincidencia. `hasta` es el primero que ya
// no es de la coincidencia: `rebanar(v, r.desde, r.hasta)` es lo que pillo.
struct Rango { desde: usize, hasta: usize }

// Lo que va leyendo el compilador mientras recorre el patron.
struct Compilador {
    p: view,
    i: usize,
    nodos: list<Nodo>,
    clases: list<list<bool>>,
    grupos: usize,
}

// ------------------------------------------------------------------
// Menudencias
// ------------------------------------------------------------------

// El centinela de "aqui no hay nada". Es el mayor `usize`, que no puede ser
// una posicion valida en un texto.
fn sin_sitio() -> usize {
    return 18446744073709551615;
}

fn es_nada(x: usize) -> bool {
    return x == 18446744073709551615;
}

// El codigo de las clases que trae la barra invertida, o 6 si no es ninguna.
fn codigo_predefinido(b: usize) -> usize {
    if b == 100 { return 0; } // d
    if b == 68 { return 1; }  // D
    if b == 119 { return 2; } // w
    if b == 87 { return 3; }  // W
    if b == 115 { return 4; } // s
    if b == 83 { return 5; }  // S
    return 6;
}

// El byte que representa un escape de los de siempre; cualquier otro se
// queda como estaba, que es lo que hace `\.` con el punto.
fn byte_literal(b: usize) -> usize {
    if b == 110 { return 10; } // n
    if b == 116 { return 9; }  // t
    if b == 114 { return 13; } // r
    return b;
}

fn marcar_uno(bits: mut list<bool>, b: usize) {
    bits[b] = true;
}

fn marcar_rango(bits: mut list<bool>, desde: usize, hasta: usize) {
    var k = desde;
    while k <= hasta {
        bits[k] = true;
        k = k + 1;
    }
}

// La vuelta de un mapa de bytes: lo que no estaba, queda.
fn negar(bits: mut list<bool>) {
    var k = 0;
    while k < 256 {
        bits[k] = !bits[k];
        k = k + 1;
    }
}

// Enciende en `destino` todo lo que este encendido en `origen`. Se llama
// `encender_de` y no `unir` porque `unir` ya es el de `std/texto.t`, y los
// nombres de `std/` no llevan prefijo.
fn encender_de(destino: mut list<bool>, origen: &list<bool>) {
    var k = 0;
    while k < 256 {
        if origen[k] { destino[k] = true; }
        k = k + 1;
    }
}

// Los 256 bytes, todos apagados.
fn bits_vacios() -> list<bool> {
    var bits: list<bool> = [];
    var k = 0;
    while k < 256 {
        anadir(bits, false);
        k = k + 1;
    }
    return bits;
}

// Las clases de una letra: digito, palabra y blanco. Se preguntan a
// `std/caracter.t` byte a byte, para que `\d`, `\w` y `\s` sean exactamente
// lo mismo que `es_digito`, `es_alfanumerico` y `es_blanco`. Los codigos 1,
// 3 y 5 son las negadas.
fn clase_predefinida(codigo: usize) -> list<bool> {
    var bits = bits_vacios();
    var k = 0;
    while k < 256 {
        var dentro = false;
        if codigo == 0 || codigo == 1 {
            dentro = c.es_digito(k);
        } else if codigo == 2 || codigo == 3 {
            dentro = c.es_alfanumerico(k);
        } else {
            dentro = c.es_blanco(k);
        }
        if dentro { bits[k] = true; }
        k = k + 1;
    }
    if codigo == 1 || codigo == 3 || codigo == 5 { negar(bits); }
    return bits;
}

// ------------------------------------------------------------------
// Leer el patron
// ------------------------------------------------------------------

fn nuevo_nodo(com: mut Compilador, forma: Forma, a: usize, b: usize, grupo: usize) -> usize {
    anadir(com.nodos, Nodo { forma: forma, a: a, b: b, grupo: grupo });
    return largo(com.nodos) - 1;
}

// Guarda un mapa de bytes como una clase mas y devuelve el nodo que la usa.
fn guardar_clase(com: mut Compilador, bits: list<bool>) -> usize {
    anadir(com.clases, bits);
    return nuevo_nodo(com, Forma.Clase, largo(com.clases) - 1, 0, 0);
}

// Si donde estamos empieza un atomo. `|` y `)` no empiezan ninguno: son los
// dos sitios donde se acaba una concatenacion.
fn empieza_atomo(com: &Compilador) -> bool {
    if com.i >= largo(com.p) { return false; }
    let b = byte(com.p, com.i);
    return b != 124 && b != 41;
}

// Una alternancia: concatenaciones separadas por `|`. Se emite un `Bifurca`
// por rama, menos por la ultima, y cada rama salta al final.
fn parsear_alternancia(com: mut Compilador) -> usize ! {
    var izq = try parsear_concatenacion(com);
    while com.i < largo(com.p) && byte(com.p, com.i) == 124 {
        com.i = com.i + 1;
        let der = try parsear_concatenacion(com);
        izq = nuevo_nodo(com, Forma.Alterna, izq, der, 0);
    }
    return izq;
}

// Una concatenacion: atomos repetidos, pegados por la izquierda. Sin nada
// delante es el nodo vacio, que casa con la cadena vacia: es lo que hace
// falta para `a|` o para un grupo `()`.
fn parsear_concatenacion(com: mut Compilador) -> usize ! {
    if !empieza_atomo(com) {
        return nuevo_nodo(com, Forma.Vacio, 0, 0, 0);
    }
    var izq = try parsear_repetido(com);
    while empieza_atomo(com) {
        let der = try parsear_repetido(com);
        izq = nuevo_nodo(com, Forma.Concat, izq, der, 0);
    }
    return izq;
}

// Un atomo con sus cuantificadores. Se admiten varios seguidos, que es lo
// que quiere `a**`; lo que no se admite es un `?` detras de un
// cuantificador, porque eso en otros lenguajes pide la version perezosa, que
// aqui no existe.
fn parsear_repetido(com: mut Compilador) -> usize ! {
    var n = try parsear_atomo(com);
    while com.i < largo(com.p) {
        let b = byte(com.p, com.i);
        if b == 42 || b == 43 || b == 63 {
            com.i = com.i + 1;
            // Un `?` pegado a un cuantificador es la version perezosa en
            // otros lenguajes. Aqui no la hay, y callarlo cambiaria lo que
            // el patron significa, asi que se dice y no se sigue.
            if com.i < largo(com.p) && byte(com.p, com.i) == 63 {
                fail "aqui no hay versiones perezosas (`*?`, `+?`, `??`): quita el `?`";
            }
            if b == 42 {
                n = nuevo_nodo(com, Forma.Estrella, n, 0, 0);
            } else if b == 43 {
                n = nuevo_nodo(com, Forma.Mas, n, 0, 0);
            } else {
                n = nuevo_nodo(com, Forma.Opcion, n, 0, 0);
            }
        } else {
            break;
        }
    }
    return n;
}

// Un atomo suelto.
fn parsear_atomo(com: mut Compilador) -> usize ! {
    let b = byte(com.p, com.i);
    if b == 40 {
        com.i = com.i + 1;
        let cual = com.grupos;
        com.grupos = com.grupos + 1;
        let dentro = try parsear_alternancia(com);
        if com.i >= largo(com.p) || byte(com.p, com.i) != 41 {
            fail "un `(` sin cerrar";
        }
        com.i = com.i + 1;
        return nuevo_nodo(com, Forma.Grupo, dentro, 0, cual);
    }
    if b == 91 {
        return try parsear_clase(com);
    }
    if b == 46 {
        com.i = com.i + 1;
        return nuevo_nodo(com, Forma.Punto, 0, 0, 0);
    }
    if b == 94 {
        com.i = com.i + 1;
        return nuevo_nodo(com, Forma.Principio, 0, 0, 0);
    }
    if b == 36 {
        com.i = com.i + 1;
        return nuevo_nodo(com, Forma.Final, 0, 0, 0);
    }
    if b == 92 {
        return try parsear_escape(com);
    }
    if b == 42 { fail "un `*` sin nada delante"; }
    if b == 43 { fail "un `+` sin nada delante"; }
    if b == 63 { fail "un `?` sin nada delante"; }
    com.i = com.i + 1;
    return nuevo_nodo(com, Forma.Letra, b, 0, 0);
}

// Un escape suelto, fuera de una clase.
fn parsear_escape(com: mut Compilador) -> usize ! {
    com.i = com.i + 1;
    if com.i >= largo(com.p) {
        fail "el patron acaba en una barra invertida";
    }
    let b = byte(com.p, com.i);
    com.i = com.i + 1;
    let cod = codigo_predefinido(b);
    if cod < 6 {
        let bits = clase_predefinida(cod);
        return guardar_clase(com, bits);
    }
    return nuevo_nodo(com, Forma.Letra, byte_literal(b), 0, 0);
}

// Una clase `[...]`. El `]` es literal si es lo primero, como en POSIX, y el
// `-` es literal si esta al principio o al final.
fn parsear_clase(com: mut Compilador) -> usize ! {
    com.i = com.i + 1;
    var bits = bits_vacios();
    var negada = false;
    if com.i < largo(com.p) && byte(com.p, com.i) == 94 {
        negada = true;
        com.i = com.i + 1;
    }
    var primero = true;
    while true {
        if com.i >= largo(com.p) {
            fail "un `[` sin cerrar";
        }
        let b = byte(com.p, com.i);
        if b == 93 && !primero {
            break;
        }
        primero = false;
        var bajo = 0;
        var suelto = true;
        if b == 92 {
            com.i = com.i + 1;
            if com.i >= largo(com.p) {
                fail "el patron acaba en una barra invertida";
            }
            let e = byte(com.p, com.i);
            com.i = com.i + 1;
            let cod = codigo_predefinido(e);
            if cod < 6 {
                let mapa = clase_predefinida(cod);
                encender_de(bits, mapa);
                suelto = false;
            } else {
                bajo = byte_literal(e);
            }
        } else {
            bajo = b;
            com.i = com.i + 1;
        }
        if suelto {
            if com.i + 1 < largo(com.p)
            && byte(com.p, com.i) == 45
            && byte(com.p, com.i + 1) != 93 {
                com.i = com.i + 1;
                var alto = 0;
                if byte(com.p, com.i) == 92 {
                    com.i = com.i + 1;
                    if com.i >= largo(com.p) {
                        fail "el patron acaba en una barra invertida";
                    }
                    alto = byte_literal(byte(com.p, com.i));
                    com.i = com.i + 1;
                } else {
                    alto = byte(com.p, com.i);
                    com.i = com.i + 1;
                }
                if alto < bajo {
                    fail "un rango al reves dentro de `[...]`";
                }
                marcar_rango(bits, bajo, alto);
            } else {
                marcar_uno(bits, bajo);
            }
        }
    }
    com.i = com.i + 1; // el `]`
    if negada { negar(bits); }
    return guardar_clase(com, bits);
}

// ------------------------------------------------------------------
// De arbol a programa
// ------------------------------------------------------------------

// Vuelca un nodo y lo que cuelga de el. Los saltos son relativos, asi que
// cada nodo se puede emitir sin saber donde acaba el programa.
fn emitir(nodos: &list<Nodo>, n: usize, prog: mut list<Instr>) {
    let x: &Nodo = nodos[n];
    if x.forma == Forma.Vacio {
        return;
    }
    if x.forma == Forma.Letra {
        anadir(prog, Instr { op: Forma.Byte, x: x.a como i64, y: 0 });
        return;
    }
    if x.forma == Forma.Punto {
        anadir(prog, Instr { op: Forma.Cualquiera, x: 0, y: 0 });
        return;
    }
    if x.forma == Forma.Clase {
        anadir(prog, Instr { op: Forma.Clase, x: x.a como i64, y: 0 });
        return;
    }
    if x.forma == Forma.Principio {
        anadir(prog, Instr { op: Forma.Principio, x: 0, y: 0 });
        return;
    }
    if x.forma == Forma.Final {
        anadir(prog, Instr { op: Forma.Final, x: 0, y: 0 });
        return;
    }
    if x.forma == Forma.Concat {
        emitir(nodos, x.a, prog);
        emitir(nodos, x.b, prog);
        return;
    }
    if x.forma == Forma.Alterna {
        let s = largo(prog);
        anadir(prog, Instr { op: Forma.Bifurca, x: 0, y: 0 });
        emitir(nodos, x.a, prog);
        let j = largo(prog);
        anadir(prog, Instr { op: Forma.Salta, x: 0, y: 0 });
        emitir(nodos, x.b, prog);
        let fin = largo(prog);
        prog[s].y = (j como i64) - (s como i64);
        prog[j].x = (fin como i64) - (j como i64) - 1;
        return;
    }
    if x.forma == Forma.Estrella {
        //     Bifurca  (cuerpo, salida)
        //   g: Guarda_loop          <- donde iba la posicion al empezar la vuelta
        //     <cuerpo>
        //   p: Progreso  (salida si no avanzo)
        //   j: Salta g
        // fin:
        let s = largo(prog);
        anadir(prog, Instr { op: Forma.Bifurca, x: 0, y: 0 });
        let g = largo(prog);
        anadir(prog, Instr { op: Forma.Guarda_loop, x: g como i64, y: 0 });
        emitir(nodos, x.a, prog);
        let p = largo(prog);
        anadir(prog, Instr { op: Forma.Progreso, x: g como i64, y: 0 });
        let j = largo(prog);
        anadir(prog, Instr { op: Forma.Salta, x: 0, y: 0 });
        let fin = largo(prog);
        prog[s].y = (fin como i64) - (s como i64) - 1;
        prog[p].y = (fin como i64) - (p como i64) - 1;
        prog[j].x = (s como i64) - (j como i64) - 1;
        return;
    }
    if x.forma == Forma.Mas {
        //   s: Guarda_loop
        //     <cuerpo>
        //   p: Progreso  (salida si no avanzo)
        //   b: Bifurca   (otra vuelta, salida)
        // fin:
        let s = largo(prog);
        anadir(prog, Instr { op: Forma.Guarda_loop, x: s como i64, y: 0 });
        emitir(nodos, x.a, prog);
        let p = largo(prog);
        anadir(prog, Instr { op: Forma.Progreso, x: s como i64, y: 0 });
        let b = largo(prog);
        anadir(prog, Instr { op: Forma.Bifurca, x: 0, y: 0 });
        let fin = largo(prog);
        prog[p].y = (fin como i64) - (p como i64) - 1;
        prog[b].x = (s como i64) - (b como i64) - 1;
        return;
    }
    if x.forma == Forma.Opcion {
        let s = largo(prog);
        anadir(prog, Instr { op: Forma.Bifurca, x: 0, y: 0 });
        emitir(nodos, x.a, prog);
        let fin = largo(prog);
        prog[s].y = (fin como i64) - (s como i64) - 1;
        return;
    }
    // Solo queda un grupo.
    anadir(prog, Instr { op: Forma.Marca, x: (2 * x.grupo) como i64, y: 0 });
    emitir(nodos, x.a, prog);
    anadir(prog, Instr { op: Forma.Marca, x: (2 * x.grupo + 1) como i64, y: 0 });
}

fn compilar(patron: view) -> Patron ! {
    // El grupo 0 es la coincidencia entera; los del usuario empiezan en el 1.
    var com = Compilador { p: patron, i: 0, nodos: [], clases: [], grupos: 1 };
    let raiz = try parsear_alternancia(com);
    if com.i < largo(com.p) {
        fail "un `)` sin su `(`";
    }
    var prog: list<Instr> = [];
    anadir(prog, Instr { op: Forma.Marca, x: 0, y: 0 });
    emitir(com.nodos, raiz, prog);
    anadir(prog, Instr { op: Forma.Marca, x: 1, y: 0 });
    anadir(prog, Instr { op: Forma.Casa, x: 0, y: 0 });
    return Patron { programa: prog, clases: com.clases, grupos: com.grupos };
}

// ------------------------------------------------------------------
// El motor
// ------------------------------------------------------------------

// Todo lo que hace falta para correr un programa sobre un texto. La pila es
// la de sitios a los que volver si lo que se probe no sale; `undo` guarda
// que ranura de captura tenia que valor antes de tocarla, para poder
// deshacer al retroceder. Las dos pilas tienen un tope logico (`cuantas_*`)
// para poder reutilizar el hueco en vez de ir soltando y pidiendo memoria.
struct Motor {
    caps: list<usize>,
    pasos: usize,
    tope: usize,
    pila_pc: list<usize>,
    pila_sp: list<usize>,
    pila_marca: list<usize>,
    undo_slot: list<usize>,
    undo_val: list<usize>,
    loop_sp: list<usize>,
    cuantas_pila: usize,
    cuantas_undo: usize,
    estado: usize, // 0 nada, 1 hay, 2 se paso el tope
}

fn motor(p: &Patron, v: view) -> Motor {
    var caps: list<usize> = [];
    var k = 0;
    while k < 2 * p.grupos {
        anadir(caps, sin_sitio());
        k = k + 1;
    }
    return Motor {
        caps: caps,
        pasos: 0,
        // Un millon de pasos, y veinte mas por cada byte del texto.
        tope: 1000000 + 20 * largo(v),
        pila_pc: [], pila_sp: [], pila_marca: [],
        undo_slot: [], undo_val: [],
        loop_sp: [],
        cuantas_pila: 0, cuantas_undo: 0, estado: 0,
    };
}

// Aparta un sitio al que volver: la instruccion alternativa, la posicion del
// texto, y hasta donde llegaba el monton de deshaceres.
fn apilar_punto(m: mut Motor, pc: usize, sp: usize) {
    if m.cuantas_pila < largo(m.pila_pc) {
        m.pila_pc[m.cuantas_pila] = pc;
        m.pila_sp[m.cuantas_pila] = sp;
        m.pila_marca[m.cuantas_pila] = m.cuantas_undo;
    } else {
        anadir(m.pila_pc, pc);
        anadir(m.pila_sp, sp);
        anadir(m.pila_marca, m.cuantas_undo);
    }
    m.cuantas_pila = m.cuantas_pila + 1;
}

// Apunta lo que habia en una ranura de captura y la deja en `sp`.
fn guardar_posicion(m: mut Motor, ranura: usize, sp: usize) {
    if m.cuantas_undo < largo(m.undo_slot) {
        m.undo_slot[m.cuantas_undo] = ranura;
        m.undo_val[m.cuantas_undo] = m.caps[ranura];
    } else {
        anadir(m.undo_slot, ranura);
        anadir(m.undo_val, m.caps[ranura]);
    }
    m.cuantas_undo = m.cuantas_undo + 1;
    m.caps[ranura] = sp;
}

// Devuelve las capturas a como estaban antes de los ultimos `hasta` apuntes.
fn deshacer(m: mut Motor, hasta: usize) {
    while m.cuantas_undo > hasta {
        m.cuantas_undo = m.cuantas_undo - 1;
        let ranura = m.undo_slot[m.cuantas_undo];
        m.caps[ranura] = m.undo_val[m.cuantas_undo];
    }
}

// La posicion donde empezaba la vuelta de un `*` o un `+`. La ranura es la
// posicion de la instruccion `Guarda_loop`, que es distinta para cada bucle
// aunque esten uno dentro de otro.
fn dejar_marca_loop(m: mut Motor, ranura: usize, sp: usize) {
    while largo(m.loop_sp) <= ranura {
        anadir(m.loop_sp, 0);
    }
    m.loop_sp[ranura] = sp;
}

fn marca_loop(m: &Motor, ranura: usize) -> usize {
    if ranura >= largo(m.loop_sp) { return 0; }
    return m.loop_sp[ranura];
}

// Corre el programa desde `inicio`. Devuelve donde acabo la coincidencia, o
// el centinela. Deja en `m.estado` si hay, si no hay o si se paso el tope.
fn correr(m: mut Motor, p: &Patron, v: view, inicio: usize, exige_fin: bool) -> usize {
    m.cuantas_pila = 0;
    m.cuantas_undo = 0;
    m.estado = 0;
    var k = 0;
    while k < largo(m.caps) {
        m.caps[k] = sin_sitio();
        k = k + 1;
    }
    var pc = 0;
    var sp = inicio;
    while true {
        m.pasos = m.pasos + 1;
        if m.pasos > m.tope {
            m.estado = 2;
            return sin_sitio();
        }
        let ins: &Instr = p.programa[pc];
        var atras = false;
        if ins.op == Forma.Byte {
            if sp < largo(v) && byte(v, sp) == ins.x como usize {
                sp = sp + 1;
                pc = pc + 1;
            } else {
                atras = true;
            }
        } else if ins.op == Forma.Cualquiera {
            if sp < largo(v) && byte(v, sp) != 10 {
                sp = sp + 1;
                pc = pc + 1;
            } else {
                atras = true;
            }
        } else if ins.op == Forma.Clase {
            if sp < largo(v) && p.clases[ins.x como usize][byte(v, sp)] {
                sp = sp + 1;
                pc = pc + 1;
            } else {
                atras = true;
            }
        } else if ins.op == Forma.Bifurca {
            apilar_punto(m, (pc como i64 + 1 + ins.y) como usize, sp);
            pc = (pc como i64 + 1 + ins.x) como usize;
        } else if ins.op == Forma.Salta {
            pc = (pc como i64 + 1 + ins.x) como usize;
        } else if ins.op == Forma.Marca {
            guardar_posicion(m, ins.x como usize, sp);
            pc = pc + 1;
        } else if ins.op == Forma.Guarda_loop {
            dejar_marca_loop(m, ins.x como usize, sp);
            pc = pc + 1;
        } else if ins.op == Forma.Progreso {
            // Si la vuelta no consumio nada, se sale del bucle en vez de
            // dar vueltas sobre el mismo sitio para siempre.
            if sp == marca_loop(m, ins.x como usize) {
                pc = (pc como i64 + 1 + ins.y) como usize;
            } else {
                pc = pc + 1;
            }
        } else if ins.op == Forma.Principio {
            if sp == 0 {
                pc = pc + 1;
            } else {
                atras = true;
            }
        } else if ins.op == Forma.Final {
            if sp == largo(v) {
                pc = pc + 1;
            } else {
                atras = true;
            }
        } else {
            // Casa: solo vale si no se exige llegar al final, o si se llego.
            if exige_fin && sp != largo(v) {
                atras = true;
            } else {
                m.estado = 1;
                return sp;
            }
        }
        if atras {
            if m.cuantas_pila == 0 {
                m.estado = 0;
                return sin_sitio();
            }
            m.cuantas_pila = m.cuantas_pila - 1;
            pc = m.pila_pc[m.cuantas_pila];
            sp = m.pila_sp[m.cuantas_pila];
            let marca = m.pila_marca[m.cuantas_pila];
            deshacer(m, marca);
        }
    }
    return sin_sitio();
}

// Prueba a casar desde cada posicion, de la primera a la ultima. El tope de
// pasos es para toda la busqueda, no para cada intento: asi un patron que se
// desborda se corta aunque haya mucho texto.
fn buscar_en(m: mut Motor, p: &Patron, v: view, desde: usize, exige_fin: bool) -> Rango {
    m.pasos = 0;
    var inicio = desde;
    while inicio <= largo(v) {
        let fin = correr(m, p, v, inicio, exige_fin);
        if m.estado == 1 {
            return Rango { desde: inicio, hasta: fin };
        }
        if m.estado == 2 {
            break;
        }
        inicio = inicio + 1;
    }
    return Rango { desde: sin_sitio(), hasta: sin_sitio() };
}

// ------------------------------------------------------------------
// Lo que se le pide a un patron
// ------------------------------------------------------------------

// El texto ENTERO casa con el patron. Si el patron puede acabar antes, se
// sigue probando hasta que una de las maneras llegue al final.
fn casamenta(p: &Patron, v: view) -> bool {
    var m = motor(p, v);
    let fin = correr(m, p, v, 0, true);
    if m.estado != 1 { return false; }
    return fin == largo(v);
}

// Casa en algun sitio.
fn busca(p: &Patron, v: view) -> bool {
    var m = motor(p, v);
    let r = buscar_en(m, p, v, 0, false);
    return !es_nada(r.desde);
}

// Donde empieza y donde acaba la primera coincidencia. Falla si no hay.
fn buscar(p: &Patron, v: view) -> Rango ! {
    var m = motor(p, v);
    let r = buscar_en(m, p, v, 0, false);
    if m.estado == 2 {
        fail "el patron es demasiado costoso para este texto";
    }
    if es_nada(r.desde) {
        fail "no hay ninguna coincidencia";
    }
    return r;
}

// Lo que pillaron los grupos de la primera coincidencia. El grupo 0 es la
// coincidencia entera, y un grupo que no participo sale vacio.
fn capturas(p: &Patron, v: view) -> list<str> ! {
    var m = motor(p, v);
    let r = buscar_en(m, p, v, 0, false);
    if m.estado == 2 {
        fail "el patron es demasiado costoso para este texto";
    }
    if es_nada(r.desde) {
        fail "no hay ninguna coincidencia";
    }
    var salida: list<str> = [];
    var g = 0;
    while g < p.grupos {
        let a = m.caps[2 * g];
        let b = m.caps[2 * g + 1];
        if es_nada(a) || es_nada(b) || b < a {
            anadir(salida, vacio());
        } else {
            anadir(salida, nuevo(rebanar(v, a, b)));
        }
        g = g + 1;
    }
    return salida;
}

// Copia `con` en `salida`, cambiando `$1`..`$9` por lo que pillo ese grupo y
// `$$` por un solo `$`. Un grupo que no participo se sustituye por nada. El
// `$0` es la coincidencia entera.
fn sustituir(m: &Motor, v: view, con: view, salida: mut str) {
    var i = 0;
    while i < largo(con) {
        let b = byte(con, i);
        var pegado = false;
        if b == 36 && i + 1 < largo(con) {
            let d = byte(con, i + 1);
            if d == 36 {
                empujar(salida, "$");
                i = i + 2;
                pegado = true;
            } else if d >= 48 && d <= 57 {
                let g = d - 48;
                if 2 * g + 1 < largo(m.caps) {
                    let a = m.caps[2 * g];
                    let z = m.caps[2 * g + 1];
                    if !es_nada(a) && !es_nada(z) && z >= a {
                        empujar(salida, rebanar(v, a, z));
                    }
                }
                i = i + 2;
                pegado = true;
            }
        }
        if !pegado {
            empujar_byte(salida, b como u8);
            i = i + 1;
        }
    }
}

// La primera, con sus `$1` y todo.
fn reemplazar(p: &Patron, v: view, con: view) -> str {
    var m = motor(p, v);
    let r = buscar_en(m, p, v, 0, false);
    if es_nada(r.desde) { return nuevo(v); }
    var salida = vacio();
    empujar(salida, rebanar(v, 0, r.desde));
    sustituir(m, v, con, salida);
    empujar(salida, rebanar(v, r.hasta, largo(v)));
    return salida;
}

// Todas. Una coincidencia vacia no se repite en el mismo sitio: se copia el
// byte y se sigue un paso mas alla, que es lo que hace falta para que
// `reemplazar_todo` de `x*` termine.
fn reemplazar_todo(p: &Patron, v: view, con: view) -> str {
    var salida = vacio();
    var m = motor(p, v);
    var desde = 0;
    var pos = 0;
    while pos <= largo(v) {
        let r = buscar_en(m, p, v, pos, false);
        if es_nada(r.desde) { break; }
        empujar(salida, rebanar(v, desde, r.desde));
        sustituir(m, v, con, salida);
        if r.desde == r.hasta {
            if r.hasta >= largo(v) {
                desde = largo(v);
                break;
            }
            empujar(salida, rebanar(v, r.hasta, r.hasta + 1));
            desde = r.hasta + 1;
            pos = r.hasta + 1;
        } else {
            desde = r.hasta;
            pos = r.hasta;
        }
    }
    empujar(salida, rebanar(v, desde, largo(v)));
    return salida;
}

// El texto troceado por donde casa el patron, conservando los trozos vacios.
// Una coincidencia vacia no parte nada: si no, un patron que casa con nada
// trocearia el texto por cada byte.
fn partir(p: &Patron, v: view) -> list<str> {
    var salida: list<str> = [];
    var m = motor(p, v);
    var desde = 0;
    var pos = 0;
    while pos <= largo(v) {
        let r = buscar_en(m, p, v, pos, false);
        if es_nada(r.desde) { break; }
        if r.desde == r.hasta {
            if r.hasta >= largo(v) { break; }
            pos = r.hasta + 1;
        } else {
            anadir(salida, nuevo(rebanar(v, desde, r.desde)));
            desde = r.hasta;
            pos = r.hasta;
        }
    }
    anadir(salida, nuevo(rebanar(v, desde, largo(v))));
    return salida;
}
