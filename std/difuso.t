// std/difuso.t — parecido entre textos: «¿querias decir este?».
//
//     let d = difuso.distancia("casa", "caza");      // 1
//     let p = difuso.parecido("camion", "camión");   // 100
//     difuso.sugerencia("--verion", ordenes)         // "--version"
//     difuso.contiene_aproximado("abrir el fichero", "fichero")
//
// Es la distancia de edicion de Levenshtein, pero contando CARACTERES y no
// bytes. Un `str` de Tcode guarda bytes: «camión» son siete bytes y seis
// caracteres, y una distancia que contara bytes diria que «camion» y «camión»
// se llevan dos, que es justo lo contrario de lo que quiere quien teclea mal
// una orden. Para eso esta `std/utf8`, que descodifica —`cuantos`, `siguiente`
// y `caracter_o`— y es lo que se usa aqui.
//
// ELECCIONES, que conviene saber
//
//   * Mayusculas: no cuentan. `parecido("Hola", "hola")` es 100. Quien busca
//     una orden teclea como le da la gana.
//   * Acentos: tampoco cuentan. `parecido("camion", "camión")` es 100, o sea
//     distancia 0. Se decide a proposito: «camión» y «camion» son la misma
//     palabra para quien busca, y en una lista de ordenes obligar a la tilde
//     seria una trampa. Se normaliza a minusculas y se quitan las tildes
//     antes de medir; la `ñ` se queda como `n`, que es lo mismo que hace
//     teclear medio mundo.
//   * El porcentaje mira al texto MAS LARGO de los dos. Asi «ab» y «abc»
//     valen 67 y no 50, y dos textos que no comparten nada valen 0. El 100 es
//     «iguales despues de normalizar» y el 0 es «no se parecen en nada».
//
// COSTE
//
// La distancia entre dos textos de `n` y `m` caracteres cuesta n * m, o sea
// cuadratica. Con nombres de orden, de fichero o de usuario no se nota: van
// de diez a treinta caracteres. Con parrafos enteros si se nota —comparar dos
// textos de mil caracteres son un millon de pasos, y una lista de mil
// candidatos son mil millones—, y `contiene_aproximado` recorre el texto
// entero, asi que es cuadratico tambien en lo largo que sea el parrafo.
//
// Si algun dia hace falta con textos largos, lo que hay que hacer es acotar
// antes: descartar candidatos por una medida barata —prefijos, un indice de
// palabras, un filtro de q-gramas— y medir la distancia solo con los pocos que
// pasen, o cortar la banda de la tabla a `2 * k + 1` diagonales cuando solo
// interese saber si la distancia baja de `k` (el truco de Ukkonen). Aqui no
// esta porque lo que se busca son ordenes y nombres, no parrafos.

use "std/utf8" como U;

// ---------------------------------------------------------------- normalizar

// La letra base de un caracter de Latin-1 (U+00C0..U+00FF), o el mismo
// caracter si ahi no hay una letra con acento. La `ñ` y la `ü` van aparte
// porque son letras propias y no una vocal con tilde.
fn sin_tilde_latina(c: u32) -> u32 {
    if c == 209 || c == 241 { return 110; } // Ñ ñ -> n
    if c == 220 || c == 252 { return 117; } // Ü ü -> u

    // Las vocales con acento, una por una y en su bloque: cuatro cada una, y
    // con el orden `À Á Â Ã Ä Å` / `È É Ê Ë` / `Ì Í Î Ï` / `Ò Ó Ô Õ Ö` /
    // `Ù Ú Û Ü`. Escribirlas todas juntas es lo que evita el error de contar
    // mal una tabla.
    if c >= 192 && c <= 197 { return 97; }
    if c >= 200 && c <= 203 { return 101; }
    if c >= 204 && c <= 207 { return 105; }
    if c >= 210 && c <= 214 { return 111; }
    if c >= 217 && c <= 220 { return 117; }

    if c == 198 { return 97; }  // Æ -> a
    if c == 199 { return 99; }  // Ç -> c
    if c == 208 { return 100; } // Ð -> d
    if c == 221 { return 121; } // Ý -> y
    if c == 222 { return 116; } // Þ -> t (la thorn, que suena a t)
    if c == 223 { return 115; } // ß -> s

    // Las minusculas del mismo bloque, con el mismo reparto.
    if c >= 224 && c <= 229 { return 97; }
    if c >= 232 && c <= 235 { return 101; }
    if c >= 236 && c <= 239 { return 105; }
    if c >= 242 && c <= 246 { return 111; }
    if c >= 249 && c <= 252 { return 117; }

    if c == 230 { return 97; }  // æ -> a
    if c == 231 { return 99; }  // ç -> c
    if c == 240 { return 100; } // ð -> d
    if c == 253 { return 121; } // ý -> y
    if c == 254 { return 116; } // þ -> t
    if c == 255 { return 121; } // ÿ -> y

    return c;
}

// La letra base de un caracter de Latin Extended-A (U+0100..U+017F), que es
// donde vive el resto del alfabeto con acento —el polaco, el checo, el
// turco—: cada letra ocupa dos codigos seguidos, la mayuscula y la minuscula,
// y por eso basta con mirar los pares que de verdad son una letra con signo.
// Las ligaduras (`ĳ`, `ŉ`, `ŧ` y compañia) no se tocan: no son una letra con
// tilde y decir que si seria inventarse el parecido.
fn sin_signo_extendida(c: u32) -> u32 {
    if c == 256 || c == 257 { return 97; }  // Ā ā
    if c == 258 || c == 259 { return 97; }  // Ă ă
    if c == 260 || c == 261 { return 97; }  // Ą ą
    if c == 262 || c == 263 { return 99; }  // Ć ć
    if c == 264 || c == 265 { return 99; }  // Ĉ ĉ
    if c == 266 || c == 267 { return 99; }  // Ċ ċ
    if c == 268 || c == 269 { return 99; }  // Č č
    if c == 270 || c == 271 { return 100; } // Ď ď
    if c == 272 || c == 273 { return 100; } // Đ đ
    if c == 274 || c == 275 { return 101; } // Ē ē
    if c == 276 || c == 277 { return 101; } // Ĕ ĕ
    if c == 278 || c == 279 { return 101; } // Ė ė
    if c == 280 || c == 281 { return 101; } // Ę ę
    if c == 282 || c == 283 { return 101; } // Ě ě
    if c == 284 || c == 285 { return 103; } // Ĝ ĝ
    if c == 286 || c == 287 { return 103; } // Ğ ğ
    if c == 288 || c == 289 { return 103; } // Ġ ġ
    if c == 290 || c == 291 { return 103; } // Ģ ģ
    if c == 292 || c == 293 { return 104; } // Ĥ ĥ
    if c == 296 || c == 297 { return 105; } // Ĩ ĩ
    if c == 298 || c == 299 { return 105; } // Ī ī
    if c == 300 || c == 301 { return 105; } // Ĭ ĭ
    if c == 302 || c == 303 { return 105; } // Į į
    if c == 304 { return 105; }             // İ
    if c == 305 { return 105; }             // ı (la i sin punto)
    if c == 306 || c == 307 { return 105; } // Ĳ ĳ
    if c == 308 || c == 309 { return 106; } // Ĵ ĵ
    if c == 310 || c == 311 { return 107; } // Ķ ķ
    if c == 313 || c == 314 { return 108; } // Ĺ ĺ
    if c == 315 || c == 316 { return 108; } // Ļ ļ
    if c == 317 || c == 318 { return 108; } // Ľ ľ
    if c == 321 || c == 322 { return 108; } // Ł ł
    if c == 323 || c == 324 { return 110; } // Ń ń
    if c == 325 || c == 326 { return 110; } // Ņ ņ
    if c == 327 || c == 328 { return 110; } // Ň ň
    if c == 331 || c == 332 { return 110; } // Ŋ ŋ
    if c == 333 || c == 334 { return 111; } // Ō ō
    if c == 335 || c == 336 { return 111; } // Ŏ ŏ
    if c == 337 || c == 338 { return 111; } // Ő ő
    if c == 339 { return 111; }             // Œ
    if c == 340 || c == 341 { return 114; } // Ŕ ŕ
    if c == 342 || c == 343 { return 114; } // Ŗ ŗ
    if c == 344 || c == 345 { return 114; } // Ř ř
    if c == 346 || c == 347 { return 115; } // Ś ś
    if c == 348 || c == 349 { return 115; } // Ŝ ŝ
    if c == 350 || c == 351 { return 115; } // Ş ş
    if c == 352 || c == 353 { return 115; } // Š š
    if c == 354 || c == 355 { return 116; } // Ţ ţ
    if c == 356 || c == 357 { return 116; } // Ť ť
    if c == 358 || c == 359 { return 116; } // Ŧ ŧ
    if c == 360 || c == 361 { return 117; } // Ũ ũ
    if c == 362 || c == 363 { return 117; } // Ū ū
    if c == 364 || c == 365 { return 117; } // Ŭ ŭ
    if c == 366 || c == 367 { return 117; } // Ů ů
    if c == 368 || c == 369 { return 117; } // Ű ű
    if c == 370 || c == 371 { return 117; } // Ų ų
    if c == 372 || c == 373 { return 119; } // Ŵ ŵ
    if c == 374 || c == 375 { return 121; } // Ŷ ŷ
    if c == 376 { return 121; }             // Ÿ
    if c == 377 || c == 378 { return 122; } // Ź ź
    if c == 379 || c == 380 { return 122; } // Ż ż
    if c == 381 || c == 382 { return 122; } // Ž ž
    return c;
}

// La letra base de un caracter del bloque vietnamita (U+1EA0..U+1EFF), que va
// por grupos de tonos —la mayuscula, la minuscula y las variantes— y donde los
// grupos no miden todos lo mismo. Por eso van por rangos escritos y no por
// cuenta de bloques: contar de seis en seis deja fuera las letras del final de
// cada grupo, que es un error que no se ve hasta que alguien teclea «Việt».
//
// Al final del bloque quedan las letras `Ỻ` a `ỿ`, que no son vocales
// vietnamitas sino latinas raras: se devuelven tal cual.
fn sin_tono_vietnamita(c: u32) -> u32 {
    if c >= 7840 && c <= 7863 { return 97; }  // Ạ ạ Ả ả Ấ ấ ... Ặ ặ
    if c >= 7864 && c <= 7879 { return 101; } // Ẹ ẹ Ẻ ẻ Ẽ ẽ ... ệ
    if c >= 7880 && c <= 7883 { return 105; } // Ỉ ỉ Ị ị
    if c >= 7884 && c <= 7907 { return 111; } // Ọ ọ Ỏ ỏ ... ợ
    if c >= 7908 && c <= 7921 { return 117; } // Ụ ụ Ủ ủ ... ự
    if c >= 7922 && c <= 7929 { return 121; } // Ỳ ỳ Ỵ ỵ Ỷ ỷ Ỹ ỹ
    return c;
}

// Lo que se considera «el mismo» caracter al medir: minuscula y sin tilde.
//
// Se trabaja con el VALOR del caracter, no con el byte, asi que comparar dos
// valores basta y no hay que montar ningun texto normalizado por dentro. Es la
// diferencia entre que «camión» sean seis caracteres o siete bytes.
//
// Se cubren las cuatro zonas donde vive el alfabeto con acento —Latin-1, Latin
// Extended-A, el bloque vietnamita y las mayusculas ASCII— y nada mas: un
// ideograma o un emoji se quedan como son, que es lo que se quiere al medir
// distancias de nombres. Las letras raras de Latin Extended Additional (U+1E00
// a U+1E9F, como la `ḃ` o la `ṡ`) tampoco se tocan: van cada una por su lado.
fn normalizado(c: u32) -> u32 {
    if c < 128 {
        // Las mayusculas ASCII, que es lo que mas se teclea.
        if c >= 65 && c <= 90 { return c + 32; }
        return c;
    }
    if c <= 255 { return sin_tilde_latina(c); }
    if c <= 383 { return sin_signo_extendida(c); }
    if c >= 7840 && c <= 7935 { return sin_tono_vietnamita(c); }
    return c;
}

// -------------------------------------------------------------- la distancia

// El menor de tres numeros, con nombre para que la tabla se lea.
fn menor_de_tres(a: usize, b: usize, c: usize) -> usize {
    var m = a;
    if b < m { m = b; }
    if c < m { m = c; }
    return m;
}

// La distancia de edicion de Levenshtein entre dos textos, contando
// CARACTERES y no bytes, y sin distinguir mayusculas ni tildes.
//
// Es el numero minimo de caracteres que hay que borrar, meter o cambiar para
// pasar de uno al otro. Si uno esta vacio, es el largo del otro: no hay nada
// que comparar y ninguna edicion se puede ahorrar.
//
// POR QUE DOS FILAS Y NO LA MATRIZ ENTERA
//
// La tabla de la distancia tiene `(n + 1) * (m + 1)` casillas, y para rellenar
// la fila `i` solo hace falta la fila `i - 1`: lo de mas arriba ya no se
// vuelve a mirar. Guardar la matriz entera cuesta n * m `usize` —ocho bytes
// cada uno— y solo sirve para reconstruir el camino de las ediciones, que
// aqui no se pide. Con dos filas el coste en memoria es `2 * (m + 1)`, que no
// crece con el texto: medir dos textos de mil caracteres pasa de ocho megas a
// dieciseis kilobytes.
//
// El precio de no guardar el camino es que no se puede decir QUE ediciones
// hacen falta, solo cuantas. Para decir «querias decir este» eso es
// exactamente lo que se necesita.
fn distancia(a: view, b: view) -> usize {
    // Un texto vacio no tiene caracteres que emparejar: la distancia es el
    // numero de caracteres del otro, y asi no se monta ninguna fila de mas.
    if largo(a) == 0 { return U.cuantos(b); }
    if largo(b) == 0 { return U.cuantos(a); }

    // La fila que se guarda dos veces es la del texto corto, y tenerla corta
    // es tener la memoria mas pequeña. Si `b` es mas largo se recorre `b` por
    // filas y `a` por columnas, sin copiar ni dar la vuelta a nada: la
    // distancia es simetrica y da igual cual sea cual.
    let largo_a = U.cuantos(a);
    let largo_b = U.cuantos(b);
    if largo_a >= largo_b { return distancia_con(a, largo_a, b, largo_b); }
    return distancia_con(b, largo_b, a, largo_a);
}

// La distancia entre el texto de las filas, de `largo_filas` caracteres, y el
// de las columnas, de `largo_columnas`. Los largos se pasan ya contados para no
// recorrer los textos dos veces, y el texto corto es el de las columnas: es el
// que se guarda dos veces en memoria.
fn distancia_con(filas: view, largo_filas: usize, columnas_texto: view, largo_columnas: usize) -> usize {
    // La fila de partida: pasar de nada a los primeros `k` caracteres de la
    // columna cuesta `k` inserciones. Es la distancia de la cadena vacia.
    var previa: list<usize> = [];
    var k = 0;
    while k <= largo_columnas {
        anadir(previa, k);
        k = k + 1;
    }

    var fila: list<usize> = [];
    var i = 0;
    var pa = 0;
    while i < largo_filas {
        let ca = normalizado(U.caracter_o(filas, pa, U.reemplazo()));
        pa = U.siguiente(filas, pa);

        // La primera columna es pasar de los primeros `i + 1` caracteres de la
        // fila a nada: `i + 1` borrados.
        anadir(fila, i + 1);

        var j = 0;
        var pb = 0;
        while j < largo_columnas {
            let cb = normalizado(U.caracter_o(columnas_texto, pb, U.reemplazo()));
            pb = U.siguiente(columnas_texto, pb);

            var coste = 1;
            if ca == cb { coste = 0; }

            // Borrar de la fila, meter en la fila, o cambiar: la casilla de
            // arriba, la de la izquierda y la diagonal.
            anadir(fila, menor_de_tres(previa[j] + coste, fila[j] + 1, previa[j + 1] + 1));
            j = j + 1;
        }

        // La fila que acaba de nacer es la previa de la siguiente vuelta. Se
        // intercambian las dos, sin copiar: `previa` pasa a ser `fila` y al
        // reves, y la que sobra se vacia y se reescribe entera.
        let usada = previa;
        previa = fila;
        fila = usada;
        truncar(fila, 0);

        i = i + 1;
    }

    return previa[largo_columnas];
}

// -------------------------------------------------------------- el porcentaje

// Cuanto se parecen, de 0 a 100. El 100 es «iguales» —tras quitar mayusculas
// y tildes— y el 0 es «no se parecen en nada».
//
// La cuenta es `100 * (1 - distancia / largo_del_mas_largo)`, y por eso el
// divisor es el mas largo y no el mas corto: asi dos textos que no comparten
// ni un caracter dan 0 de verdad, y no un numero que parezca un aprobado. Y
// asi «ab» contra «abc» vale 67, que es lo que se espera de dos de tres.
fn parecido(a: view, b: view) -> usize {
    let la = U.cuantos(a);
    let lb = U.cuantos(b);
    if la == 0 && lb == 0 { return 100; }
    var mayor = la;
    if lb > mayor { mayor = lb; }
    let d = distancia(a, b);
    if d >= mayor { return 0; }
    return (100 * (mayor - d)) / mayor;
}

// --------------------------------------------------------------- los mejores

// El minimo de parecido que se le pide a `sugerencia`. Con 60, «camion» y
// «camino» —parecido 83— pasan, y «casa» y «perro» —parecido 0— no. Esta
// escogido para una lista de ordenes: por debajo de 60 lo que sale es mas
// ruido que ayuda, y quien llama puede mirar los porcentajes por su cuenta si
// quiere el umbral a su gusto.
fn parecido_minimo() -> usize { return 60; }

// Con cuanto parecido basta para decir que la aguja aparece en el texto. Es
// mas bajo que el de `sugerencia`: dentro de un texto largo, una palabra bien
// escrita rodeada de otras no tiene por que sacar un 60 sobre la ventana que
// le toca.
fn parecido_minimo_en_texto() -> usize { return 50; }

// Los `tope` candidatos mas cercanos a `aguja`, de mas a menos, sin repetir y
// sin los que no se parezcan en nada.
//
// Repetir un candidato no cuenta dos veces: si el mismo texto esta dos veces
// en la lista, sale una. Y si hay menos candidatos que `tope`, salen todos los
// que pasen del minimo.
//
// COSTE: por cada uno de los `tope` puestos se mira la lista entera, asi que
// es `tope * candidatos` distancias de cuadraticas. Para una lista de ordenes
// es lo que hay; para una lista enorme lo que toca es no pedir muchos.
fn mas_parecidos(aguja: view, candidatos: &list<str>, tope: usize) -> list<str> {
    var salida: list<str> = [];

    // Se recuerda cual ya salio, para no repetirlo. Son posiciones, que son
    // numeros: moverlas no deja a nadie sin su memoria.
    var usados: list<usize> = [];
    var i = 0;
    while i < largo(candidatos) {
        anadir(usados, 0);
        i = i + 1;
    }

    while largo(salida) < tope {
        var elegido = 18446744073709551615;
        var mejor = 0;

        var k = 0;
        while k < largo(candidatos) {
            if usados[k] == 0 {
                let p = parecido(aguja, candidatos[k]);
                if p >= parecido_minimo()
                && (elegido == 18446744073709551615 || p > mejor) {
                    elegido = k;
                    mejor = p;
                }
            }
            k = k + 1;
        }

        // Sin ninguno que llegue al minimo, se acabo: no se rellena con
        // candidatos que no se parecen en nada.
        if elegido == 18446744073709551615 { break; }

        usados[elegido] = 1;
        anadir(salida, copiar(candidatos[elegido]));
    }

    return salida;
}

// El candidato que mas se parece, y falla si ninguno llega al minimo. El
// umbral es el de `parecido_minimo`.
//
// Se llama con un texto que no esta en la lista:
//
//     let cerca = difuso.sugerencia(lo_que_tecleo, ordenes) sino vacio();
//
// El motivo dice solo que no hay nada lo bastante parecido, sin la aguja ni el
// porcentaje: en este lenguaje el motivo de un `fail` es una cadena ESCRITA,
// no un texto construido, asi que no se puede armar con lo que se midio. Quien
// quiera el detalle —que candidato quedo mas cerca y con cuanto— lo tiene en
// `parecido` y en `mas_parecidos`, que no fallan.
fn sugerencia(aguja: view, candidatos: &list<str>) -> str ! {
    if largo(candidatos) == 0 { fail "no hay ninguna lista de la que sacar una sugerencia"; }

    var mejor = 0;
    var donde = 0;
    var hay = false;
    var i = 0;
    while i < largo(candidatos) {
        let p = parecido(aguja, candidatos[i]);
        if p > mejor {
            mejor = p;
            donde = i;
            hay = true;
        }
        i = i + 1;
    }

    if !hay || mejor < parecido_minimo() {
        fail "ningun candidato se parece lo bastante a la aguja";
    }

    return nuevo(candidatos[donde]);
}

// --------------------------------------------------- buscar dentro del texto

// El parecido del trozo de `texto` que va del caracter `desde` al `hasta` con
// la aguja. Es la cuenta que necesitan las funciones de abajo, y por eso esta
// aparte: no tiene por que repetirse la tabla en cada sitio.
fn mejor_en_ventana(aguja: view, texto: view, desde: usize, hasta: usize) -> usize {
    let trozo = U.trozo(texto, desde, hasta);
    let la = U.cuantos(aguja);
    let lt = U.cuantos(trozo);
    if la == 0 { return 100; }
    let d = distancia(aguja, trozo);
    if d >= lt { return 0; }
    // El divisor es el trozo, que es el texto que de verdad se lee.
    return (100 * (lt - d)) / lt;
}

// Si `aguja` aparece en `texto` salvo por errores de tecleo, sin distinguir
// mayusculas ni tildes.
//
// Se prueban todas las ventanas del texto cuyo largo se acerca al de la aguja
// —de dos tercios al doble, que es donde cabe un par de letras cambiadas— y
// basta con que una llegue al 50 de parecido. Mirar solo ventanas del largo
// exacto no vale: con una letra de mas o de menos, la aguja ya no encaja con
// ninguna.
//
// COSTE: cuadratico en el largo del texto, como `distancia`. Es para buscar
// una palabra en una linea, no un parrafo en un libro.
fn contiene_aproximado(texto: view, aguja: view) -> bool {
    let la = U.cuantos(aguja);
    let lt = U.cuantos(texto);
    if la == 0 { return true; }
    if lt == 0 { return false; }

    // Mas larga que el texto no cabe ni con todo borrado.
    if la > lt + la / 2 { return false; }

    // Un texto corto se prueba entero, que es mas barato que ir ventana a
    // ventana y no depende de que los largos cuadren.
    if lt <= la + la / 2 {
        return mejor_en_ventana(aguja, texto, 0, lt) >= parecido_minimo_en_texto();
    }

    var desde = 0;
    while desde + la / 2 <= lt {
        var hasta = desde + la;
        if hasta > lt { hasta = lt; }
        if mejor_en_ventana(aguja, texto, desde, hasta) >= parecido_minimo_en_texto() {
            return true;
        }
        desde = desde + 1;
    }
    return false;
}
