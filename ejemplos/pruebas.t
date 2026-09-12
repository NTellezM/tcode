// pruebas.t — la biblioteca estandar probandose a si misma, en Tcode.
//
// Ni el compilador ni Python intervienen aqui: es un programa de Tcode que
// comprueba otros programas de Tcode y sale con cero si todo cuadra. La
// suite lo corre como un ejemplo mas.
//
//     ./pruebas

usar "std/prueba";
usar "std/texto";
usar "std/lista";
usar "std/numero";
usar "std/mapa";
usar "std/conjunto";
usar "std/formato";
usar "std/bytes";
usar "std/vector";
usar "std/par";

fn corto(x: &str) -> bool { return largo(x) < 5; }

fn main() -> usize ! {
    var p = pruebas();

    // ---- texto ----
    afirmar_igual_texto(p, "partir y unir",
        unir(try partir("a,b,,c", ","), "-"), "a-b--c");
    afirmar_igual_texto(p, "recortar", recortar("  hola  "), "hola");
    afirmar_igual_texto(p, "minusculas", minusculas("HoLa"), "hola");
    afirmar_igual_texto(p, "reemplazar",
        try reemplazar("uno dos uno", "uno", "tres"), "tres dos tres");
    afirmar_igual_texto(p, "terminos sin puntuacion",
        unir(terminos("hola, mundo!"), "|"), "hola|mundo");
    afirmar(p, "empieza y termina",
        empieza_con("camion", "cam") && termina_con("camion", "ion"));
    afirmar_igual_numero(p, "a_entero", try a_entero("1204"), 1204);
    afirmar_igual_texto(p, "rellenar", rellenar("ab", 5), "ab   ");
    afirmar_igual_texto(p, "alinear", alinear("7", 4), "   7");

    // ---- lista ----
    var ns: lista<usize> = [];
    anadir(ns, 5); anadir(ns, 1); anadir(ns, 9);
    afirmar_igual_numero(p, "suma", suma(ns), 15);
    afirmar_igual_numero(p, "maximo", try maximo(ns), 9);
    afirmar_igual_numero(p, "minimo", try minimo(ns), 1);
    afirmar_igual_numero(p, "media", try media(ns), 5);
    afirmar_igual_numero(p, "ultima posicion", try ultima_posicion(ns), 2);

    var ts: lista<str> = [];
    anadir(ts, nuevo("pera")); anadir(ts, nuevo("aguacate"));
    anadir(ts, nuevo("uva"));
    afirmar_igual_texto(p, "invertida", unir(invertida(ts), ","),
        "uva,aguacate,pera");
    afirmar_igual_texto(p, "primeras", unir(primeras(ts, 2), ","),
        "pera,aguacate");
    afirmar_igual_texto(p, "filtradas con clausura",
        unir(filtradas(ts, fn(x: &str) -> bool { return largo(x) < 5; }), ","),
        "pera,uva");
    afirmar_igual_numero(p, "cuantas cumplen",
        cuantas_cumplen(ts, corto), 2);
    afirmar_igual_texto(p, "ordenadas por largo",
        unir(ordenadas_por(ts, fn(a: &str, b: &str) -> bool {
            return largo(a) < largo(b);
        }), ","), "uva,pera,aguacate");
    afirmar_igual_texto(p, "aplanar",
        unir(aplanar(dos_listas()), ","), "a,b,c");

    // ---- numero ----
    afirmar_igual_numero(p, "porcentaje", try porcentaje(1, 8), 12);
    afirmar_igual_numero(p, "acotar", acotar(99, 0, 10), 10);
    afirmar(p, "cerca", cerca(0.1 + 0.2, 0.3, 0.000001));
    afirmar(p, "dividir entre cero falla", (dividir(1, 0) sino 999) == 999);

    // ---- mapa y conjunto ----
    var m: mapa<str, usize> = [];
    acumular(m, "a", 2); acumular(m, "a", 3); acumular(m, "b", 1);
    afirmar_igual_numero(p, "acumular", obtener_o(m, "a", 0), 5);
    afirmar_igual_texto(p, "claves ordenadas", unir(claves_ordenadas(m), ","),
        "a,b");

    let c1 = de_lista(palabras("uno dos tres"));
    let c2 = de_lista(palabras("dos tres cuatro"));
    afirmar_igual_texto(p, "interseccion",
        unir(elementos(interseccion(c1, c2)), ","), "dos,tres");
    afirmar_igual_texto(p, "diferencia",
        unir(elementos(diferencia(c1, c2)), ","), "uno");
    afirmar_igual_numero(p, "union", cuantos_hay(union(c1, c2)), 4);

    // ---- formato ----
    afirmar_igual_texto(p, "con decimales", con_decimales(3.14159, 2), "3.14");
    afirmar_igual_texto(p, "millares", con_millares(1234567), "1.234.567");

    // ---- bytes ----
    var buf = vacio();
    poner_u32(buf, 3735928559);
    afirmar_igual_texto(p, "a_hex", a_hex(vista(buf)), "deadbeef");
    afirmar_igual_numero(p, "leer_u32", try leer_u32(vista(buf), 0) como usize,
        3735928559);
    afirmar_igual_numero(p, "de_hex", largo(try de_hex("deadbeef")), 4);

    // ---- vector, escrito en Tcode sobre bloque<T> ----
    var v: Vector<str> = Vector { datos: reservar(0), largo: 0 };
    agregar(v, nuevo("x")); agregar(v, nuevo("y"));
    afirmar_igual_numero(p, "vector cuenta", cuantos(v), 2);
    afirmar_igual_texto(p, "vector saca", try sacar(v, vacio()), "y");
    afirmar_igual_numero(p, "vector encoge", cuantos(v), 1);

    // ---- par ----
    let dos = par(nuevo("clave"), 9);
    afirmar_igual_numero(p, "par segundo", dos.segundo, 9);
    afirmar_igual_texto(p, "par volteado", volteado(dos).segundo, "clave");

    return terminar(p);
}

fn dos_listas() -> lista<lista<str>> {
    var a: lista<str> = [];
    anadir(a, nuevo("a"));
    var b: lista<str> = [];
    anadir(b, nuevo("b")); anadir(b, nuevo("c"));
    var todas: lista<lista<str>> = [];
    anadir(todas, a); anadir(todas, b);
    return todas;
}
