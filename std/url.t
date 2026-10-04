// std/url.t — partir y rearmar direcciones de internet (RFC 3986).
//
//     let p = url.analizar("https://ejemplo.com/a/b?x=1#tope");
//     p.esquema     // "https"
//     p.host        // "ejemplo.com"
//     p.ruta        // "/a/b"
//     p.consulta    // "x=1"
//     p.fragmento   // "tope"
//
// `analizar` no copia trozos de la original: devuelve cada parte en un `str`
// con dueño, deja vacio lo que no venga y `puerto` en 0. No le hace ascos a
// nada: si no hay esquema, o no hay host, la parte que falte queda vacia.
//
// Lo que se mete dentro de una URL se escapa con `codificar_componente` y se
// deshace con `decodificar_componente`. `decodificar_formulario` es lo mismo
// pero convirtiendo el `+` en espacio: eso solo vale en el cuerpo de un
// formulario, donde el `+` significa espacio, no en una URL normal.

use "std/bytes";
use "std/caracter";
use "std/texto";
use "std/par";

// Las ocho partes de una URL. Las que no vengan, vacias; `puerto` en 0.
struct Partes {
    esquema: str,
    usuario: str,
    contrasena: str,
    host: str,
    puerto: u32,
    ruta: str,
    consulta: str,
    fragmento: str,
}

// ------------------------------------------------------------------
// Buscar dentro de la original
// ------------------------------------------------------------------

// La posicion del primer byte `b` en `v[desde..hasta]`, o `hasta` si no esta.
// El limite de arriba no es un adorno: lo que ya se recorto —la consulta, el
// fragmento— no se vuelve a mirar.
fn primer_byte(v: view, b: usize, desde: usize, hasta: usize) -> usize {
    var i = desde;
    while i < hasta {
        if byte(v, i) == b { return i; }
        i = i + 1;
    }
    return hasta;
}

// La posicion del ultimo byte `b` en `v[desde..hasta]`, o `hasta` si no esta.
fn ultimo_byte(v: view, b: usize, desde: usize, hasta: usize) -> usize {
    var i = hasta;
    while i > desde {
        i = i - 1;
        if byte(v, i) == b { return i; }
    }
    return hasta;
}

fn todo_digitos(v: view) -> bool {
    if largo(v) == 0 { return false; }
    var i = 0;
    while i < largo(v) {
        if !es_digito(byte(v, i)) { return false; }
        i = i + 1;
    }
    return true;
}

// ------------------------------------------------------------------
// Analizar
// ------------------------------------------------------------------

// Los bytes que puede llevar un esquema despues de la primera letra.
fn es_caracter_de_esquema(b: usize) -> bool {
    if b >= 65 && b <= 90 { return true; }  // A-Z
    if b >= 97 && b <= 122 { return true; } // a-z
    if b >= 48 && b <= 57 { return true; }  // 0-9
    return b == 43 || b == 45 || b == 46;   // + - .
}

// Donde acaba el esquema: el `:` que lo cierra, o `fin` si `v[0..fin]` no
// empieza por un esquema. Un `//` al principio no lo es, y por eso se mira la
// primera letra antes de nada.
fn fin_de_esquema(v: view, fin: usize) -> usize {
    if fin == 0 { return fin; }
    let b0 = byte(v, 0);
    let letra = (b0 >= 65 && b0 <= 90) || (b0 >= 97 && b0 <= 122);
    if !letra { return fin; }
    var i = 0;
    while i < fin {
        let b = byte(v, i);
        if b == 58 { return i; } // ':'
        if !es_caracter_de_esquema(b) { return fin; }
        i = i + 1;
    }
    return fin;
}

// Parte una URL en sus trozos. Acepta lo que le echen: sin esquema, sin host,
// con usuario y contrasena, con puerto, con IPv6 entre corchetes.
fn analizar(v: view) -> Partes {
    var fin = largo(v);

    // El fragmento es lo que va tras el primer `#`.
    let almohadilla = primer_byte(v, 35, 0, fin);
    var fragmento: view = "";
    if almohadilla < fin {
        fragmento = rebanar(v, almohadilla + 1, fin);
        fin = almohadilla;
    }

    // La consulta es lo que va tras el primer `?`, ya sin el fragmento.
    let interrogacion = primer_byte(v, 63, 0, fin);
    var consulta: view = "";
    if interrogacion < fin {
        consulta = rebanar(v, interrogacion + 1, fin);
        fin = interrogacion;
    }

    // El esquema, si hay un `:` antes de cualquier `/`.
    let dos_puntos = fin_de_esquema(v, fin);
    var esquema: view = "";
    var inicio = 0;
    if dos_puntos < fin {
        esquema = rebanar(v, 0, dos_puntos);
        inicio = dos_puntos + 1;
    }

    var usuario: view = "";
    var contrasena: view = "";
    var host: view = "";
    var puerto: u32 = 0;
    var ruta: view = "";

    // Sin `//` no hay autoridad: todo lo que queda es ruta.
    if inicio + 2 <= fin && byte(v, inicio) == 47 && byte(v, inicio + 1) == 47 {
        let ini_autoridad = inicio + 2;
        let barra = primer_byte(v, 47, ini_autoridad, fin);
        ruta = rebanar(v, barra, fin);

        // El usuario va antes de la ultima `@`; puede traer contrasena.
        let arroba = ultimo_byte(v, 64, ini_autoridad, barra);
        var ini_host = ini_autoridad;
        if arroba < barra {
            let colon = primer_byte(v, 58, ini_autoridad, arroba);
            if colon < arroba {
                usuario = rebanar(v, ini_autoridad, colon);
                contrasena = rebanar(v, colon + 1, arroba);
            } else {
                usuario = rebanar(v, ini_autoridad, arroba);
            }
            ini_host = arroba + 1;
        }

        // El host, con su puerto detras. Un host entre corchetes es una
        // direccion IPv6 y puede llevar `:` dentro.
        var ini_puerto = barra;
        if ini_host < barra && byte(v, ini_host) == 91 {      // '['
            let cierre = primer_byte(v, 93, ini_host, barra); // ']'
            if cierre < barra { ini_puerto = cierre + 1; }
        } else {
            ini_puerto = ultimo_byte(v, 58, ini_host, barra); // ':'
        }
        if ini_puerto < barra && byte(v, ini_puerto) == 58 {
            let cifras = rebanar(v, ini_puerto + 1, barra);
            if todo_digitos(cifras) {
                host = rebanar(v, ini_host, ini_puerto);
                let n = a_entero(cifras) sino 0;
                puerto = n como u32;
            } else {
                host = rebanar(v, ini_host, barra);
            }
        } else {
            host = rebanar(v, ini_host, barra);
        }
    } else {
        ruta = rebanar(v, inicio, fin);
    }

    return Partes {
        esquema: nuevo(esquema),
        usuario: nuevo(usuario),
        contrasena: nuevo(contrasena),
        host: nuevo(host),
        puerto: puerto,
        ruta: nuevo(ruta),
        consulta: nuevo(consulta),
        fragmento: nuevo(fragmento),
    };
}

// ------------------------------------------------------------------
// Escapar y desescapar
// ------------------------------------------------------------------

// Los unicos bytes que pueden ir sueltos: `A-Z a-z 0-9 - . _ ~`.
fn es_seguro(b: usize) -> bool {
    if b >= 65 && b <= 90 { return true; }            // A-Z
    if b >= 97 && b <= 122 { return true; }           // a-z
    if b >= 48 && b <= 57 { return true; }            // 0-9
    return b == 45 || b == 46 || b == 95 || b == 126; // - . _ ~
}

// Percent-encoding: lo que no sea seguro va a `%XX`, con las cifras en
// mayusculas. El `a_hex` de std/bytes da minusculas, asi que se sube.
fn codificar_componente(v: view) -> str {
    var salida = vacio();
    var i = 0;
    while i < largo(v) {
        let b = byte(v, i);
        if es_seguro(b) {
            empujar_byte(salida, b como u8);
        } else {
            empujar(salida, "%");
            empujar(salida, mayusculas(a_hex(rebanar(v, i, i + 1))));
        }
        i = i + 1;
    }
    return salida;
}

fn es_digito_hex(b: usize) -> bool {
    if b >= 48 && b <= 57 { return true; } // 0-9
    if b >= 65 && b <= 70 { return true; } // A-F
    return b >= 97 && b <= 102;            // a-f
}

// El cuerpo comun de las dos funciones de al reves. `mas_espacio` decide si
// el `+` se lee como un espacio, que es lo que hace un formulario.
fn desescapar(v: view, mas_espacio: bool) -> str ! {
    var salida = vacio();
    var i = 0;
    while i < largo(v) {
        let b = byte(v, i);
        if b == 37 { // '%'
            // Las dos cifras, antes de cortar nada: un `%` a medias y un `%`
            // con una letra que no toca son el mismo error.
            if i + 3 > largo(v)
            || !es_digito_hex(byte(v, i + 1))
            || !es_digito_hex(byte(v, i + 2)) {
                fail "un % tiene que ir seguido de dos cifras hexadecimales";
            }
            let par = try de_hex(rebanar(v, i + 1, i + 3));
            empujar_byte(salida, byte(par, 0) como u8);
            i = i + 3;
        } else if b == 43 && mas_espacio { // '+'
            empujar_byte(salida, 32);
            i = i + 1;
        } else {
            empujar_byte(salida, b como u8);
            i = i + 1;
        }
    }
    return salida;
}

// Al reves del percent-encoding. Falla si un `%` no lleva detras dos cifras
// hexadecimales: adivinar lo que quiso decir el que lo escribio es peor que
// decirlo.
fn decodificar_componente(v: view) -> str ! {
    return try desescapar(v, false);
}

// Como el anterior, pero con el `+` por espacio: es lo que vale dentro del
// cuerpo de un formulario (`application/x-www-form-urlencoded`).
fn decodificar_formulario(v: view) -> str ! {
    return try desescapar(v, true);
}

// ------------------------------------------------------------------
// Consultas
// ------------------------------------------------------------------

// La posicion del primer `=` en `v`, o `largo(v)` si no hay.
fn posicion_de_igual(v: view) -> usize {
    return primer_byte(v, 61, 0, largo(v));
}

// Los pares `nombre=valor` de una consulta, sin tocar el texto: lo que viene
// escapado se queda escapado. Los trozos vacios se saltan, para que
// `a=1&&b=2` y `a=1&b=2` den lo mismo, y un nombre sin `=` sale con valor
// vacio.
fn parametros(consulta: view) -> list<Par<str, str>> {
    var salida: list<Par<str, str>> = [];
    let trozos = partir(consulta, "&") sino [];
    for t en trozos {
        if largo(t) == 0 { continue; }
        let igual = posicion_de_igual(t);
        if igual < largo(t) {
            anadir(salida, par(nuevo(rebanar(t, 0, igual)),
                    nuevo(rebanar(t, igual + 1, largo(t)))));
        } else {
            anadir(salida, par(nuevo(t), vacio()));
        }
    }
    return salida;
}

// El valor de `nombre` en la consulta, ya desescapado. Falla si el parametro
// no esta: no hay valor por defecto sensato. Los nombres se comparan tambien
// desescapados, para que `a%20b` encuentre lo que puso `a b`.
fn valor_de(consulta: view, nombre: view) -> str ! {
    let buscado = try decodificar_formulario(nombre);
    let lista = parametros(consulta);
    for p en lista {
        let clave = decodificar_formulario(p.primero) sino nuevo(p.primero);
        if igual(clave, buscado) {
            return try decodificar_formulario(p.segundo);
        }
    }
    fail "la consulta no trae ese parametro";
}

// ------------------------------------------------------------------
// Rearmar
// ------------------------------------------------------------------

// Vuelve a juntar las partes. Si `host` esta vacio no pone `//`, que es lo
// que deja intacta una ruta suelta o un `mailto:`.
fn construir(p: &Partes) -> str {
    var s = vacio();
    if largo(p.esquema) > 0 {
        empujar(s, p.esquema);
        empujar(s, ":");
    }
    if largo(p.host) > 0 {
        empujar(s, "//");
        if largo(p.usuario) > 0 || largo(p.contrasena) > 0 {
            empujar(s, p.usuario);
            if largo(p.contrasena) > 0 {
                empujar(s, ":");
                empujar(s, p.contrasena);
            }
            empujar(s, "@");
        }
        empujar(s, p.host);
        if p.puerto != 0 {
            empujar(s, ":");
            empujar(s, texto(p.puerto));
        }
    }
    empujar(s, p.ruta);
    if largo(p.consulta) > 0 {
        empujar(s, "?");
        empujar(s, p.consulta);
    }
    if largo(p.fragmento) > 0 {
        empujar(s, "#");
        empujar(s, p.fragmento);
    }
    return s;
}
