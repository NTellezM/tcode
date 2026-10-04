// std/sha256.t — SHA-256 (FIPS 180-4), en Tcode puro.
//
//     use "std/sha256";
//
//     let d = resumen("abc");       // 32 bytes, en crudo
//     let h = resumen_hex("abc");   // 64 digitos hexadecimales
//     let m = hmac_sha256(clave, mensaje);   // en hexadecimal
//
//     var r = nuevo_resumen();      // por partes, sin juntar el texto
//     anadir_al_resumen(r, trozo_1);
//     anadir_al_resumen(r, trozo_2);
//     let h2 = terminar_resumen_hex(r);
//
//     let hf = sha256_de_fichero("grande.bin") sino nuevo("");
//
// Un `str` de Tcode guarda bytes, no texto, asi que el resumen son 32 bytes
// crudos dentro de un `str`: puede tener ceros y se copia tal cual.
//
// De donde salen las constantes, que no son magia:
//
//   * `K` son los 32 primeros bits de la parte fraccionaria de la raiz cubica
//     de los 64 primeros numeros primos: K[i] = parte_fraccionaria(raiz3(p_i))
//     * 2^32. Por ejemplo raiz3(2) = 1.2599210498..., su parte fraccionaria
//     por 2^32 es 0x428a2f98.
//
//   * `H_INICIAL` son los 32 primeros bits de la parte fraccionaria de la raiz
//     cuadrada de los 8 primeros primos: H[j] = parte_fraccionaria(raiz(p_j))
//     * 2^32. Por ejemplo raiz(2) = 1.4142135623..., que da 0x6a09e667.
//
use "std/bytes";

// Todo el algoritmo trabaja en `u32` y envuelve a proposito: la suma es modulo
// 2^32, asi que va con `+?` (envolvente explicita) y nunca con `+`, que en
// Tcode aborta si desborda. Las rotaciones son de 32 bits, y como el lenguaje
// no trae una operacion de girar, las hace `girar` con dos desplazamientos.

// ---------- las constantes de la especificacion ----------

// Los 64 primeros primos: 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, ... 311.
fn k_de_la_raiz_cubica() -> list<u32> {
    return [
        1116352408, 1899447441, 3049323471, 3921009573,
        961987163, 1508970993, 2453635748, 2870763221,
        3624381080, 310598401, 607225278, 1426881987,
        1925078388, 2162078206, 2614888103, 3248222580,
        3835390401, 4022224774, 264347078, 604807628,
        770255983, 1249150122, 1555081692, 1996064986,
        2554220882, 2821834349, 2952996808, 3210313671,
        3336571891, 3584528711, 113926993, 338241895,
        666307205, 773529912, 1294757372, 1396182291,
        1695183700, 1986661051, 2177026350, 2456956037,
        2730485921, 2820302411, 3259730800, 3345764771,
        3516065817, 3600352804, 4094571909, 275423344,
        430227734, 506948616, 659060556, 883997877,
        958139571, 1322822218, 1537002063, 1747873779,
        1955562222, 2024104815, 2227730452, 2361852424,
        2428436474, 2756734187, 3204031479, 3329325298
    ];
}

// Las raices cuadradas de 2, 3, 5, 7, 11, 13, 17 y 19.
fn h_inicial() -> list<u32> {
    return [
        1779033703, 3144134277, 1013904242, 2773480762,
        1359893119, 2600822924, 528734635, 1541459225
    ];
}

// ---------- lo que hace falta de la especificacion ----------

// La rotacion a la derecha en 32 bits. Tcode no trae una operacion de girar,
// asi que se hace con dos desplazamientos: lo que sale por la derecha entra
// por la izquierda. Con `n` a cero el desplazamiento de la izquierda seria 32,
// que no cabe en un `u32`, asi que ese caso se deja aparte.
fn girar(x: u32, n: u32) -> u32 {
    let bajo: u32 = x >> n;
    if n == 0 {
        // Girar cero no es girar: y ademas `x << 32` no cabe en un `u32`.
        return bajo;
    }
    // `<<` de un `u32` ya envuelve solo: los bits que salen por la izquierda
    // desaparecen, que es justo lo que se quiere al girar.
    let alto: u32 = x << (32 - n);
    return alto | bajo;
}

fn mayuscula(x: u32) -> u32 {
    return girar(x, 2) ^ girar(x, 13) ^ girar(x, 22);
}

fn minuscula(x: u32) -> u32 {
    return girar(x, 6) ^ girar(x, 11) ^ girar(x, 25);
}

// Sigma mayuscula 0 y 1 de la expansion del mensaje.
fn sigma_0(x: u32) -> u32 {
    return girar(x, 7) ^ girar(x, 18) ^ (x >> 3);
}

fn sigma_1(x: u32) -> u32 {
    return girar(x, 17) ^ girar(x, 19) ^ (x >> 10);
}

// La funcion de eleccion y la de mayoria, bit a bit.
fn elegir(x: u32, y: u32, z: u32) -> u32 {
    // El complemento de `x` a 32 bits: Tcode no niega un entero, `(!x)` es
    // para `bool`.
    return (x & y) ^ ((x ^ 4294967295) & z);
}

fn mayoria(x: u32, y: u32, z: u32) -> u32 {
    return (x & y) ^ (x & z) ^ (y & z);
}

// Las 64 palabras de un bloque, a partir de los 16 primeros enteros.
fn expandir(bloque: &list<u32>) -> list<u32> {
    var w: list<u32> = [];
    var i = 0;
    while i < 16 {
        anadir(w, bloque[i]);
        i = i + 1;
    }
    i = 16;
    while i < 64 {
        let s0 = sigma_0(w[i - 15]);
        let s1 = sigma_1(w[i - 2]);
        var n: u32 = w[i - 16];
        n = n +? s0;
        n = n +? w[i - 7];
        n = n +? s1;
        anadir(w, n);
        i = i + 1;
    }
    return w;
}

// Un bloque de 64 bytes, ya como 16 enteros de 32 bits en orden de red.
fn palabras_del_bloque(bloque: view) -> list<u32> {
    var palabras: list<u32> = [];
    var i = 0;
    while i < 16 {
        var n: u32 = 0;
        var k = 0;
        while k < 4 {
            n = (n << 8) | (byte(bloque, i * 4 + k) como u32);
            k = k + 1;
        }
        anadir(palabras, n);
        i = i + 1;
    }
    return palabras;
}

// La compresion: mezcla el bloque en las ocho palabras de estado.
fn comprimir(estado: mut list<u32>, bloque: view) {
    let k = k_de_la_raiz_cubica();
    let w = expandir(palabras_del_bloque(bloque));
    var a: u32 = estado[0];
    var b: u32 = estado[1];
    var c: u32 = estado[2];
    var d: u32 = estado[3];
    var e: u32 = estado[4];
    var f: u32 = estado[5];
    var g: u32 = estado[6];
    var h: u32 = estado[7];
    var i = 0;
    while i < 64 {
        let t1a = h +? minuscula(e);
        let t1b = t1a +? elegir(e, f, g);
        let t1c = t1b +? k[i];
        let t1 = t1c +? w[i];
        let t2 = mayuscula(a) +? mayoria(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d +? t1;
        d = c;
        c = b;
        b = a;
        a = t1 +? t2;
        i = i + 1;
    }
    estado[0] = a +? estado[0];
    estado[1] = b +? estado[1];
    estado[2] = c +? estado[2];
    estado[3] = d +? estado[3];
    estado[4] = e +? estado[4];
    estado[5] = f +? estado[5];
    estado[6] = g +? estado[6];
    estado[7] = h +? estado[7];
}

// ---------- el resumen, de una vez ----------

// Los 32 bytes del resumen, en crudo.
fn resumen(v: view) -> str {
    var r = nuevo_resumen();
    anadir_al_resumen(r, v);
    return terminar_resumen(r);
}

// Los 32 bytes, en 64 digitos hexadecimales minusculos.
fn resumen_hex(v: view) -> str {
    var r = nuevo_resumen();
    anadir_al_resumen(r, v);
    return terminar_resumen_hex(r);
}

// ---------- el resumen, por partes ----------

// El estado de un resumen a medias: las ocho palabras, lo que sobra del ultimo
// bloque y cuantos bytes han entrado en total (para la longitud del final).
struct Resumen {
    estado: list<u32>,
    pendiente: str,
    total: u64,
}

// Un resumen recien empezado, con los valores iniciales de la especificacion.
fn nuevo_resumen() -> Resumen {
    return Resumen { estado: h_inicial(), pendiente: vacio(), total: 0 };
}

// Un bloque entero esta listo para comprimir.
fn esta_lleno(pendiente: view) -> bool {
    return largo(pendiente) >= 64;
}

// El resumen de lo que se le haya dado al `Resumen`, en crudo. Es de solo
// lectura: el original se queda como estaba, asi que se le pueden seguir
// anadiendo trozos despues.
fn terminar_resumen(r: &Resumen) -> str {
    // Se copia el pendiente porque el relleno hay que anadirlo sin tocar el
    // original.
    var cola = nuevo(r.pendiente);
    let bytes_del_mensaje = r.total;
    empujar_byte(cola, 128); // el 1 de relleno, y siete ceros
    while largo(cola) % 64 != 56 {
        empujar_byte(cola, 0);
    }
    var i = 8;
    while i > 0 {
        i = i - 1;
        empujar_byte(cola, (((bytes_del_mensaje * 8) >> (i * 8)) & 255) como u8);
    }
    // El estado se copia para no modificar el `Resumen` prestado.
    var estado: list<u32> = [];
    var j = 0;
    while j < 8 {
        anadir(estado, r.estado[j]);
        j = j + 1;
    }
    var desde = 0;
    while desde < largo(cola) {
        comprimir(estado, rebanar(cola, desde, desde + 64));
        desde = desde + 64;
    }
    var salida = vacio();
    j = 0;
    while j < 8 {
        poner_u32(salida, estado[j]);
        j = j + 1;
    }
    return salida;
}

fn terminar_resumen_hex(r: &Resumen) -> str {
    let crudo = terminar_resumen(r);
    return a_hex(vista(crudo));
}

// Anade un trozo de mensaje al resumen. Los trozos pueden ser de cualquier
// tamaño: lo que no llene un bloque se guarda para la proxima vez.
fn anadir_al_resumen(r: mut Resumen, v: view) {
    var i = 0;
    while i < largo(v) {
        empujar_byte(r.pendiente, byte(v, i) como u8);
        if esta_lleno(r.pendiente) {
            comprimir(r.estado, vista(r.pendiente));
            r.pendiente = vacio();
        }
        i = i + 1;
    }
    r.total = r.total + (largo(v) como u64);
}

// ---------- HMAC (RFC 2104) ----------

// El HMAC-SHA256 en hexadecimal. La clave se acorta con su propio resumen si
// pasa de 64 bytes, como manda la especificacion, y si no se rellena con ceros.
fn hmac_sha256(clave: view, mensaje: view) -> str {
    var k = vacio();
    if largo(clave) > 64 {
        k = resumen(clave);
    } else {
        k = nuevo(clave);
    }
    while largo(k) < 64 {
        empujar_byte(k, 0);
    }
    var interna = vacio();
    var i = 0;
    while i < 64 {
        empujar_byte(interna, (byte(k, i) ^ 54) como u8); // 0x36
        i = i + 1;
    }
    empujar(interna, mensaje);
    let intermedio = resumen(vista(interna));
    var externa = vacio();
    i = 0;
    while i < 64 {
        empujar_byte(externa, (byte(k, i) ^ 92) como u8); // 0x5c
        i = i + 1;
    }
    empujar(externa, vista(intermedio));
    return resumen_hex(vista(externa));
}

// ---------- un fichero, por partes ----------

// El SHA-256 de un fichero, leido por trozos para no cargarlo entero. El
// tamaño de cada trozo es multiplo de 64: asi cada trozo cierra bloques y el
// ultimo es el unico que puede quedar a medias.
fn sha256_de_fichero(ruta: view) -> str ! {
    var r = nuevo_resumen();
    var desde = 0;
    var seguir = true;
    while seguir {
        let parte = try leer_parte_archivo(ruta, desde, 65536);
        if largo(parte) == 0 {
            seguir = false;
        } else {
            anadir_al_resumen(r, vista(parte));
            desde = desde + largo(parte);
        }
    }
    return terminar_resumen_hex(r);
}
