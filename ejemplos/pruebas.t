// pruebas.t — la biblioteca estandar probandose a si misma, en Tcode.
//
// Ni el compilador ni Python intervienen aqui: es un programa de Tcode que
// comprueba otros programas de Tcode y sale con cero si todo cuadra. La
// suite lo corre como un ejemplo mas.
//
//     ./pruebas

#importar "prueba.t";
#importar "texto.t";
#importar "lista.t";
#importar "numero.t";
#importar "mapa.t";
#importar "conjunto.t";
#importar "formato.t";
#importar "bytes.t";
#importar "vector.t";
#importar "par.t";
#importar "iterador.t";

fn corto(x: &str) -> bool { return largo(x) < 5; }

fn positivo(n: &usize) -> bool { return n > 0; }

fn main() -> usize ! {
    var p = pruebas();

    // ---- texto ----
    afirmar_igual_texto(p, "partir y unir",
        unir(try partir("a,b,,c", ","), "-"), "a-b--c");
    afirmar_igual_texto(p, "recortar", recortar("  hola  "), "hola");
    afirmar_igual_texto(p, "minusculas", minusculas("HoLa"), "hola");
    afirmar_igual_texto(p, "mayusculas", mayusculas("HoLa"), "HOLA");
    afirmar_igual_texto(p, "lineas",
        unir(lineas("una\x0d\n\ndos\n"), "|"), "una||dos");
    afirmar_igual_numero(p, "apariciones", try apariciones("aaaa", "aa"), 2);
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
    var ns: list<usize> = [];
    anadir(ns, 5); anadir(ns, 1); anadir(ns, 9);
    afirmar_igual_numero(p, "suma", suma(ns), 15);
    afirmar_igual_numero(p, "maximo", try maximo(ns), 9);
    afirmar_igual_numero(p, "minimo", try minimo(ns), 1);
    afirmar_igual_numero(p, "media", try media(ns), 5);
    afirmar_igual_numero(p, "ultima posicion", try ultima_posicion(ns), 2);

    var ts: list<str> = [];
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

    // ---- iteradores de una pasada ----
    afirmar(p, "todas", todas(ns, positivo));
    afirmar(p, "alguna", alguna(ns, fn(n: &usize) -> bool { return n == 9; }));
    afirmar_igual_numero(p, "primera que",
        try primera_que(ns, fn(n: &usize) -> bool { return n > 5; }), 9);
    afirmar_igual_numero(p, "plegar",
        plegar(ns, 10, fn(total: usize, n: &usize) -> usize {
                return total + n;
            }), 25);
    let dobles = transformar(ns, fn(n: &usize) -> usize { return n * 2; });
    afirmar_igual_numero(p, "transformar", suma(dobles), 30);

    // ---- numero ----
    afirmar_igual_numero(p, "porcentaje", try porcentaje(1, 8), 12);
    afirmar_igual_numero(p, "acotar", acotar(99, 0, 10), 10);
    afirmar(p, "cerca", cerca(0.1 + 0.2, 0.3, 0.000001));
    afirmar(p, "dividir entre cero fail", (dividir(1, 0) sino 999) == 999);

    // ---- mapa y conjunto ----
    var m: map<str, usize> = [];
    acumular(m, "a", 2); acumular(m, "a", 3); acumular(m, "b", 1);
    afirmar_igual_numero(p, "acumular", obtener_o(m, "a", 0), 5);
    afirmar_igual_texto(p, "claves ordenadas", unir(claves_ordenadas(m), ","),
        "a,b");
    let valores_m: list<usize> = try valores_ordenados(m);
    afirmar_igual_numero(p, "valores ordenados", suma(valores_m), 6);
    var otro: map<str, usize> = [];
    poner(otro, "a", 8); poner(otro, "c", 2); try actualizar(m, otro);
    afirmar_igual_numero(p, "actualizar", obtener_o(m, "a", 0), 8);

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
    afirmar_igual_texto(p, "vector a lista", unir(a_lista(v), ","), "x");

    // ---- par ----
    let dos = par(nuevo("clave"), 9);
    afirmar_igual_numero(p, "par segundo", dos.segundo, 9);
    afirmar_igual_texto(p, "par volteado", volteado(dos).segundo, "clave");

    return terminar(p);
}

fn dos_listas() -> list<list<str>> {
    var a: list<str> = [];
    anadir(a, nuevo("a"));
    var b: list<str> = [];
    anadir(b, nuevo("b")); anadir(b, nuevo("c"));
    var todas: list<list<str>> = [];
    anadir(todas, a); anadir(todas, b);
    return todas;
}
