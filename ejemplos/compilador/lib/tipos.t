// lib/tipos.t — la capa de tipos del comprobador, escrita en Tcode.
//
// Un tipo en Tcode viaja como cadena: `usize`, `lista<str>`,
// `mapa<str, Cosa>`, `bloque<T>`, `[usize; 4]`, `&Cosa`, `fn(&T, &T) -> bool`.
// Es como sale en los mensajes y en los nombres de C. Aqui se lee como arbol
// (`leer_tipo`, `Tipo`, `Forma`) y se vuelve a escribir (`escribir_tipo`), y el
// resto del compilador pregunta y construye tipos solo a traves de este modulo.
//
// Aqui estan las dos preguntas de las que cuelga el resto:
//
//     posee(t)        ¿un valor de este tipo es duenio de memoria?
//                     De eso depende si se libera, si se mueve o se copia.
//     tipo_existe(t)  ¿se puede guardar un valor de este tipo?
//
// El lexer y el parser de Tcode ya estan escritos en Tcode; esto es la capa
// siguiente. Se comprueba contra la de Python en cada ejecucion de la suite.

usar "std/texto";

// ------------------------------------------------------------------
// Leer la forma de un tipo
// ------------------------------------------------------------------

fn empieza(t: view, p: view) -> bool {
    return empieza_con(t, p);
}

// Lo que hay entre el primer `<` y el ultimo `>`.
fn entre_angulos(t: view) -> view {
    var desde = 0;
    while desde < t.largo() {
        if byte(t, desde) == 60 { break; }
        desde = desde + 1;
    }
    if desde >= t.largo() { return rebanar(t, 0, 0); }
    return rebanar(t, desde + 1, t.largo() - 1);
}

// Parte por las comas de fuera: `str, lista<usize>` da dos trozos.
fn partir_tipos(dentro: view) -> lista<str> {
    var salida: lista<str> = [];
    var hondura = 0;
    var desde = 0;
    var i = 0;
    while i <= dentro.largo() {
        var corta = false;
        if i == dentro.largo() {
            corta = true;
        } else {
            let b = byte(dentro, i);
            // Un tipo funcion lleva comas dentro de sus parentesis, y la `>`
            // de su `->` no cierra ningun angulo.
            let flecha = b == 62 && i > 0 && byte(dentro, i - 1) == 45;
            if b == 60 || b == 91 || b == 40 { hondura = hondura + 1; }
            if (b == 62 && !flecha) || b == 93 || b == 41 { hondura = hondura - 1; }
            if b == 44 && hondura == 0 { corta = true; }
        }
        if corta {
            let trozo = recortar(rebanar(dentro, desde, i));
            if trozo.largo() > 0 { salida.anadir(nuevo(trozo)); }
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

fn es_lista(t: view) -> bool { return forma_de(t) == Forma.Lista; }

fn es_bloque(t: view) -> bool { return forma_de(t) == Forma.Bloque; }

fn es_mapa(t: view) -> bool { return forma_de(t) == Forma.Mapa; }

// Lo que recorre `for i en a..b`: los enteros de `a` a `b`, sin `b`.
fn es_rango(t: view) -> bool { return forma_de(t) == Forma.Rango; }

fn es_funcion(t: view) -> bool {
    return empieza(t, "fn(");
}

fn es_arreglo(t: view) -> bool {
    return empieza(t, "[");
}

fn es_referencia(t: view) -> bool {
    return empieza(t, "&");
}

fn apuntado(t: view) -> view {
    if forma_de(t) == Forma.PrestaMut { return rebanar(t, 5, t.largo()); }
    return rebanar(t, 1, t.largo());
}

// `fn(usize, str) -> bool` da ["usize", "str", "bool"]: los argumentos y,
// al final, lo que devuelve. Sin flecha, el retorno es `()`.
fn partes_de_funcion(t: view) -> lista<str> {
    var hondura = 0;
    var cierre = 0;
    var i = 0;
    while i < t.largo() {
        let b = byte(t, i);
        if b == 40 { hondura = hondura + 1; }
        if b == 41 {
            hondura = hondura - 1;
            if hondura == 0 { cierre = i; break; }
        }
        i = i + 1;
    }
    var salida: lista<str> = [];
    if cierre == 0 { return salida; }
    let dentro = rebanar(t, 3, cierre);
    if largo(recortar(dentro)) > 0 {
        for x en partir_tipos(dentro) { salida.anadir(copiar(x)); }
    }
    let resto = recortar(rebanar(t, cierre + 1, t.largo()));
    if empieza_con(resto, "->") {
        salida.anadir(nuevo(recortar(rebanar(resto, 2, resto.largo()))));
    } else {
        salida.anadir(nuevo("()"));
    }
    return salida;
}

// Quita el prestamo si lo hay: `&Cosa` -> `Cosa`, `usize` -> `usize`.
fn apuntado_si(t: view) -> str {
    let forma = forma_de(t);
    if forma == Forma.Presta || forma == Forma.PrestaMut {
        return nuevo(apuntado(t));
    }
    return nuevo(t);
}

fn elemento(t: view) -> str {
    if es_arreglo(t) {
        // `[usize; 4]`: lo que va antes del `;` de fuera. El de
        // `[[usize; 2]; 3]` es `[usize; 2]`, no `[usize`.
        var hondura = 0;
        var i = 1;
        while i + 1 < t.largo() {
            let b = byte(t, i);
            if b == 91 || b == 60 { hondura = hondura + 1; }
            if (b == 93 || b == 62) && hondura > 0 { hondura = hondura - 1; }
            if b == 59 && hondura == 0 { return nuevo(rebanar(t, 1, i)); }
            i = i + 1;
        }
        return nuevo(rebanar(t, 1, t.largo() - 1));
    }
    return nuevo(entre_angulos(t));
}

// El valor de un mapa: el segundo de los dos que van entre angulos.
fn valor_de_mapa(t: view) -> str ! {
    let leido = leer_tipo(t);
    if leido.forma != Forma.Mapa || leido.args.largo() != 2 {
        falla "un mapa lleva clave y valor";
    }
    return escribir_tipo(leido.args[1]);
}

// ------------------------------------------------------------------
// El tipo como arbol
// ------------------------------------------------------------------
//
// La cadena es como viaja un tipo entre las capas y como sale en los
// mensajes. Para mirar dentro de el se lee una vez como arbol, y lo que se
// construye se escribe desde el arbol: asi solo hay un sitio que sabe como
// se escribe cada forma.

// De que forma es un tipo. `Nombre` es todo lo que desde aqui no tiene
// partes: los escalares, `str`, `view`, `()`, un struct, un enum, un
// parametro de tipo, y la aplicacion de un struct generico, que lleva sus
// argumentos (`Par<str, usize>`).
enum Forma {
    Nombre,
    Lista,
    Bloque,
    Mapa,
    Rango,
    Arreglo,
    Presta,
    PrestaMut,
    Funcion,
}

struct Tipo {
    forma: Forma,
    // El de un `Nombre`; vacio en lo demas.
    nombre: str,
    // Lo de dentro, en orden: el elemento; la clave y el valor; lo apuntado;
    // los argumentos de una aplicacion; los parametros de una funcion y, si
    // devuelve algo, su retorno al final.
    args: lista<Tipo>,
    // Cuantos lleva un arreglo, como se escribio.
    cuantos: str,
    devuelve: bool,
}

fn nuevo_tipo(forma: Forma, nombre: view) -> Tipo {
    return Tipo { forma: forma, nombre: nuevo(nombre), args: [], cuantos: vacio(),
        devuelve: false };
}

fn con_uno(forma: Forma, dentro: view) -> Tipo {
    var t = nuevo_tipo(forma, "");
    t.args.anadir(leer_tipo(dentro));
    return t;
}

fn con_varios(forma: Forma, nombre: view, dentro: view) -> Tipo {
    var t = nuevo_tipo(forma, nombre);
    for x en partir_tipos(dentro) { t.args.anadir(leer_tipo(x)); }
    return t;
}

// Un tipo que no se sabe. `tipo_de` lo devuelve cuando no conoce el tipo de
// una expresion, y quien lo lee pregunta `conocido` antes de mirarlo. Es un
// `Nombre` con el nombre vacio, que es justo lo que da `leer_tipo("")`.
fn ninguno() -> Tipo {
    return nuevo_tipo(Forma.Nombre, "");
}

// Un marcador que no es un tipo de verdad: el comprobador guarda `{entero}` y
// `{decimal}` para las expresiones numericas aun sin fijar. Vive en los mapas
// de tipos, asi que se monta a mano (no pasa por `leer_tipo`).
fn marcador(s: view) -> Tipo {
    return nuevo_tipo(Forma.Nombre, s);
}

fn conocido(t: &Tipo) -> bool {
    return t.forma != Forma.Nombre || t.nombre.largo() > 0;
}

// El `Tipo` que guarda un mapa bajo `clave`, ya con duenio: `obtener` presta
// y `sino` no puede devolver un prestamo, asi que se copia. Los lectores de
// los mapas de tipos lo usan en vez de `obtener ... sino`.
fn tipo_de_mapa(m: &mapa<str, Tipo>, clave: view) -> Tipo ! {
    return copiar(try obtener(m, clave));
}

// La lista de `Tipo` que guarda un mapa bajo `clave`, con duenio: la pareja
// de `tipo_de_mapa` para los campos que llevan varios tipos.
fn tipos_de_mapa(m: &mapa<str, lista<Tipo>>, clave: view) -> lista<Tipo> ! {
    return copiar(try obtener(m, clave));
}

// Una lista de textos de tipo, leidos a sus `Tipo`. La usan los que guardan
// una firma recien leida: el texto entra, la estructura se guarda.
fn leer_tipos(escritos: &lista<str>) -> lista<Tipo> {
    var salida: lista<Tipo> = [];
    for e en escritos { salida.anadir(leer_tipo(e)); }
    return salida;
}

// El camino inverso: la lista de `Tipo`, escrita a texto. La usan los que
// aun hablan en `str` con el generador de C.
fn escribir_tipos(tipos: &lista<Tipo>) -> lista<str> {
    var salida: lista<str> = [];
    for t en tipos { salida.anadir(escribir_tipo(t)); }
    return salida;
}

// La forma de un tipo escrito, sin leer lo de dentro. Es lo unico que
// preguntan `posee` y `tipo_existe` antes de bajar, y no reserva nada: leer
// el arbol entero para eso era la mayor parte de lo que se leian tipos.
fn forma_de(t: view) -> Forma {
    if empieza(t, "&mut ") { return Forma.PrestaMut; }
    if empieza(t, "&") { return Forma.Presta; }
    if empieza(t, "[") && termina_con(t, "]") && contiene(t, ";") { return Forma.Arreglo; }
    if empieza(t, "fn(") {
        if partes_de_funcion(t).largo() == 0 { return Forma.Nombre; }
        return Forma.Funcion;
    }
    if empieza(t, "lista<") && termina_con(t, ">") { return Forma.Lista; }
    if empieza(t, "bloque<") && termina_con(t, ">") { return Forma.Bloque; }
    if empieza(t, "rango<") && termina_con(t, ">") { return Forma.Rango; }
    if empieza(t, "mapa<") && termina_con(t, ">") { return Forma.Mapa; }
    return Forma.Nombre;
}

// El arbol de un tipo escrito. Lo que no tiene una forma conocida es un
// `Nombre` con el texto tal cual, asi que leer y escribir siempre vuelve a
// dar lo mismo.
fn leer_tipo(t: view) -> Tipo {
    let forma = forma_de(t);
    match forma {
        Forma.PrestaMut -> { return con_uno(forma, rebanar(t, 5, t.largo())); }
        Forma.Presta -> { return con_uno(forma, rebanar(t, 1, t.largo())); }
        Forma.Arreglo -> {
            var a = con_uno(forma, elemento(t));
            a.cuantos = cuantos_del_arreglo(t);
            return a;
        }
        Forma.Funcion -> {
            let partes = partes_de_funcion(t);
            var f = nuevo_tipo(forma, "");
            f.devuelve = tiene_flecha(t);
            var i = 0;
            while i < partes.largo() {
                // Sin flecha, `partes_de_funcion` pone un `()` al final que no
                // esta escrito.
                if i + 1 < partes.largo() || f.devuelve { f.args.anadir(leer_tipo(partes[i])); }
                i = i + 1;
            }
            return f;
        }
        Forma.Lista -> { return con_uno(forma, entre_angulos(t)); }
        Forma.Bloque -> { return con_uno(forma, entre_angulos(t)); }
        Forma.Rango -> { return con_uno(forma, entre_angulos(t)); }
        Forma.Mapa -> { return con_varios(forma, "", entre_angulos(t)); }
        Forma.Nombre -> { }
    }
    // Un nombre, o la aplicacion de un struct generico: `Par<str, usize>`.
    let abre = primer_angulo(t);
    if abre > 0 && termina_con(t, ">") {
        return con_varios(forma, rebanar(t, 0, abre), entre_angulos(t));
    }
    return nuevo_tipo(forma, t);
}

fn primer_angulo(t: view) -> usize {
    var i = 0;
    while i < t.largo() {
        if byte(t, i) == 60 { return i; }
        i = i + 1;
    }
    return 0;
}

// Si detras del `)` de una funcion hay un `->`.
fn tiene_flecha(t: view) -> bool {
    var hondura = 0;
    var i = 0;
    while i < t.largo() {
        let b = byte(t, i);
        if b == 40 { hondura = hondura + 1; }
        if b == 41 {
            hondura = hondura - 1;
            if hondura == 0 {
                return empieza_con(recortar(rebanar(t, i + 1, t.largo())), "->");
            }
        }
        i = i + 1;
    }
    return false;
}

fn escritos(ts: &lista<Tipo>, desde: usize, hasta: usize) -> str {
    var s = vacio();
    var i = desde;
    while i < hasta {
        if i > desde { s.empujar(", "); }
        s.empujar(escribir_tipo(ts[i]));
        i = i + 1;
    }
    return s;
}

// El tipo escrito, como lo escribe el resto del compilador.
fn escribir_tipo(t: &Tipo) -> str {
    let n = t.args.largo();
    match t.forma {
        Forma.Nombre -> {
            if n == 0 { return copiar(t.nombre); }
            return $"{t.nombre}<{escritos(t.args, 0, n)}>";
        }
        Forma.Lista -> { return $"lista<{escritos(t.args, 0, n)}>"; }
        Forma.Bloque -> { return $"bloque<{escritos(t.args, 0, n)}>"; }
        Forma.Mapa -> { return $"mapa<{escritos(t.args, 0, n)}>"; }
        Forma.Rango -> { return $"rango<{escritos(t.args, 0, n)}>"; }
        Forma.Arreglo -> { return $"[{escritos(t.args, 0, n)}; {t.cuantos}]"; }
        Forma.Presta -> { return $"&{escritos(t.args, 0, n)}"; }
        Forma.PrestaMut -> { return $"&mut {escritos(t.args, 0, n)}"; }
        Forma.Funcion -> {
            if !t.devuelve { return $"fn({escritos(t.args, 0, n)})"; }
            if n == 0 { return nuevo("fn()"); }
            return $"fn({escritos(t.args, 0, n - 1)}) -> {escribir_tipo(t.args[n - 1])}";
        }
    }
    return vacio();
}

// Lo que un tipo lleva dentro, cada parte escrita: el elemento de una lista,
// la clave y el valor de un mapa, lo apuntado, los argumentos de una
// aplicacion, los parametros y el retorno de una funcion.
fn partes(t: view) -> lista<str> {
    var salida: lista<str> = [];
    let a = leer_tipo(t);
    for x en a.args { salida.anadir(escribir_tipo(x)); }
    return salida;
}

// El mismo tipo con sus partes cambiadas por `nuevas`, en el orden de
// `partes`. Es como se reescribe un tipo a cualquier hondura sin partir
// cadenas: se cambia cada parte y se vuelve a montar.
fn con_partes(t: view, nuevas: &lista<str>) -> str {
    var a = leer_tipo(t);
    if nuevas.largo() != a.args.largo() { return nuevo(t); }
    var hechas: lista<Tipo> = [];
    for x en nuevas { hechas.anadir(leer_tipo(x)); }
    a.args = hechas;
    return escribir_tipo(a);
}

// El nombre de una aplicacion, sin sus argumentos: `Par<str, usize>` ->
// `Par`. Vacio si no es un nombre.
fn base(t: view) -> str {
    let a = leer_tipo(t);
    if a.forma != Forma.Nombre { return vacio(); }
    return copiar(a.nombre);
}

// `[T; N]` -> [T, N]; vacia si no es un arreglo.
fn partes_de_arreglo(t: view) -> lista<str> {
    var salida: lista<str> = [];
    let a = leer_tipo(t);
    if a.forma != Forma.Arreglo || a.args.largo() != 1 { return salida; }
    salida.anadir(escribir_tipo(a.args[0]));
    salida.anadir(copiar(a.cuantos));
    return salida;
}

// Cuantos arreglos hay en el tipo, a cualquier hondura: `[[u8; 2]; 3]`
// lleva dos. Ordena los typedef de los arreglos: los de dentro, antes.
fn arreglos_dentro(t: view) -> usize {
    return arreglos_en(leer_tipo(t));
}

fn arreglos_en(t: &Tipo) -> usize {
    var n = 0;
    if t.forma == Forma.Arreglo { n = 1; }
    for x en t.args { n = n + arreglos_en(x); }
    return n;
}

// Si en algun sitio del tipo hay un bloque o un arreglo.
fn lleva_bloque_o_arreglo(t: view) -> bool {
    return lleva_bloque_o_arreglo_en(leer_tipo(t));
}

fn lleva_bloque_o_arreglo_en(t: &Tipo) -> bool {
    if t.forma == Forma.Bloque || t.forma == Forma.Arreglo { return true; }
    for x en t.args {
        if lleva_bloque_o_arreglo_en(x) { return true; }
    }
    return false;
}

fn hacer_lista(e: view) -> str { return $"lista<{e}>"; }
fn hacer_rango(e: view) -> str { return $"rango<{e}>"; }
fn hacer_arreglo(e: view, n: view) -> str { return $"[{e}; {n}]"; }
fn hacer_prestado(t: view) -> str { return $"&{t}"; }
fn hacer_prestado_mut(t: view) -> str { return $"&mut {t}"; }

fn es_referencia_mutable(t: view) -> bool { return forma_de(t) == Forma.PrestaMut; }

// `[T; N]` -> `N`, como se escribio.
fn cuantos_del_arreglo(t: view) -> str {
    var i = t.largo();
    while i > 0 && byte(t, i - 1) != 32 { i = i - 1; }
    if t.largo() == 0 { return vacio(); }
    return nuevo(rebanar(t, i, t.largo() - 1));
}

// Un nombre de C: lo que no sea letra o cifra, cambiado por `_`, sin
// repetirlo ni dejarlo en los bordes.
fn sanear(t: view) -> str {
    var r = vacio();
    var pendiente = false;
    var i = 0;
    while i < t.largo() {
        let c = byte(t, i);
        let bueno = (c >= 97 && c <= 122) || (c >= 65 && c <= 90)
        || (c >= 48 && c <= 57);
        if bueno {
            if pendiente && r.largo() > 0 { r.empujar("_"); }
            pendiente = false;
            r.empujar(rebanar(t, i, i + 1));
        } else {
            pendiente = true;
        }
        i = i + 1;
    }
    return r;
}

// Como se llama la copia de un struct generico: `Par<str, usize>` es
// `Par__str_usize`. `args` son los argumentos ya con sus propias copias.
fn nombre_de_copia(base: view, args: &lista<str>) -> str {
    var r = nuevo(base);
    r.empujar("__");
    var i = 0;
    while i < args.largo() {
        if i > 0 { r.empujar("_"); }
        r.empujar(sanear(args[i]));
        i = i + 1;
    }
    return r;
}

// ------------------------------------------------------------------
// Las dos preguntas
// ------------------------------------------------------------------

fn escalar(t: view) -> bool {
    if t == "usize" || t == "bool" || t == "view" { return true; }
    if t == "u8" || t == "u16" || t == "u32" || t == "u64" {
        return true;
    }
    if t == "i8" || t == "i16" || t == "i32" || t == "i64" {
        return true;
    }
    return t == "f32" || t == "f64" || t == "()";
}

// Si un valor de tipo `t` es dueno de memoria del heap. Es la unica regla
// del compilador para esa pregunta: la usan el comprobador, el que tipa y el
// generador, cada uno con lo que sabe de los tipos con nombre.
//
// - `campos`: struct -> los tipos de sus campos, tambien de las plantillas.
// - `parametros`: struct generico -> sus parametros de tipo.
// - `variantes`: enum -> sus formas.
// - `formas`: `Enum.Forma` -> lo que lleva.
//
// Un tipo de otro modulo se escribe `Q.Nombre`, pero se apunta por su
// nombre. `vistos` corta la recursion: un `Nodo` con un campo `lista<Nodo>`
// se contiene a si mismo de forma finita, y preguntarle dos veces no aporta.
fn posee_en(t: &Tipo, campos: &mapa<str, lista<Tipo>>, parametros: &mapa<str, lista<str>>,
    variantes: &mapa<str, lista<str>>, formas: &mapa<str, lista<Tipo>>,
    vistos: mut mapa<str, usize>) -> bool {
    return posee_desde(t, campos, parametros, variantes, formas, vistos) sino false;
}

// Falible solo para leer los mapas sin copiar; cada `obtener` va detras de
// su `tiene`, asi que no falla.
fn posee_desde(t: &Tipo, campos: &mapa<str, lista<Tipo>>, parametros: &mapa<str, lista<str>>,
    variantes: &mapa<str, lista<str>>, formas: &mapa<str, lista<Tipo>>,
    vistos: mut mapa<str, usize>) -> bool ! {
    match t.forma {
        // Lo prestado es de otro; una funcion y un rango no guardan nada.
        Forma.Presta -> { return false; }
        Forma.PrestaMut -> { return false; }
        Forma.Funcion -> { return false; }
        Forma.Rango -> { return false; }
        Forma.Lista -> { return true; }
        Forma.Bloque -> { return true; }
        Forma.Mapa -> { return true; }
        Forma.Arreglo -> {
            return try posee_desde(t.args[0], campos, parametros, variantes, formas, vistos);
        }
        Forma.Nombre -> { }
    }
    if t.nombre == "str" { return true; }
    if escalar(t.nombre) { return false; }

    // Un struct generico aplicado posee si posee alguno de sus campos, con
    // los tipos ya puestos.
    if t.forma == Forma.Nombre && t.args.largo() > 0 {
        let base = sin_alias_tipo(t.nombre);
        if !tiene(parametros, base) || !tiene(campos, base) { return false; }
        let sueltos = try obtener(parametros, base);
        if t.args.largo() != sueltos.largo() { return false; }
        var ligaduras: mapa<str, str> = [];
        var i = 0;
        while i < sueltos.largo() {
            poner(ligaduras, vista(sueltos[i]), escribir_tipo(t.args[i]));
            i = i + 1;
        }
        let crudos = try obtener(campos, base);
        for x en crudos {
            let puesto = sustituir_tipo(x, ligaduras);
            if try posee_desde(puesto, campos, parametros, variantes, formas, vistos) { return true; }
        }
        return false;
    }

    let nombre = sin_alias_tipo(t.nombre);
    if tiene(vistos, nombre) { return false; }
    poner(vistos, vista(nombre), 1);
    // Un enum posee si alguna de sus formas lleva algo que posee: en tiempo
    // de ejecucion solo hay una, pero cual sea no se sabe aqui.
    if tiene(variantes, nombre) {
        let cuales = try obtener(variantes, nombre);
        for v en cuales {
            let clave = $"{nombre}.{v}";
            if !tiene(formas, clave) { continue; }
            let lleva = try obtener(formas, clave);
            for x en lleva {
                if try posee_desde(x, campos, parametros, variantes, formas, vistos) { return true; }
            }
        }
        return false;
    }
    // Una plantilla sin aplicar no es un tipo: no guarda nada.
    if tiene(parametros, nombre) || !tiene(campos, nombre) { return false; }
    let suyos = try obtener(campos, nombre);
    for x en suyos {
        if try posee_desde(x, campos, parametros, variantes, formas, vistos) { return true; }
    }
    return false;
}

// `Par<str, usize>`: un struct generico aplicado a sus tipos. `lista<...>`,
// `mapa<...>`, `bloque<...>` y `fn(...)` no, que esos los pone el lenguaje.
fn es_aplicacion(t: view) -> bool {
    if t.largo() == 0 || !termina_con(t, ">") { return false; }
    var i = 0;
    while i < t.largo() && byte(t, i) != 60 {
        if !es_de_nombre(byte(t, i)) && byte(t, i) != 46 { return false; }
        i = i + 1;
    }
    if i == 0 || i == t.largo() { return false; }
    let base = rebanar(t, 0, i);
    if base == "lista" || base == "mapa" || base == "bloque" {
        return false;
    }
    let primero = byte(t, 0);
    return (primero >= 65 && primero <= 90) || (primero >= 97 && primero <= 122);
}

// El struct generico de una aplicacion, sin alias: `t.Par<A, B>` -> `Par`.
fn base_de_aplicacion(t: view) -> str {
    var i = 0;
    while i < t.largo() && byte(t, i) != 60 { i = i + 1; }
    return sin_alias_tipo(rebanar(t, 0, i));
}

// Cambia cada nombre de `t` que este en `ligaduras` por lo suyo: los
// parametros de una plantilla por los tipos de una aplicacion.
fn sustituir(t: view, ligaduras: &mapa<str, str>) -> str {
    var salida = vacio();
    var desde = 0;
    var i = 0;
    while i <= t.largo() {
        var corta = true;
        if i < t.largo() { corta = !es_de_nombre(byte(t, i)); }
        if corta {
            if i > desde {
                let pieza = rebanar(t, desde, i);
                if tiene(ligaduras, pieza) {
                    salida.empujar(obtener(ligaduras, pieza) sino "");
                } else {
                    salida.empujar(pieza);
                }
            }
            if i < t.largo() { salida.empujar(rebanar(t, i, i + 1)); }
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

// Cambia cada nombre de `t` que este en `ligaduras` por lo suyo, sobre el
// arbol: los parametros de una plantilla por los tipos de una aplicacion.
// Es la pareja estructurada de `sustituir`; las ligaduras siguen en str
// porque las lee quien las escribe en C.
fn sustituir_tipo(t: &Tipo, ligaduras: &mapa<str, str>) -> Tipo {
    if t.forma == Forma.Nombre && t.args.largo() == 0 {
        if tiene(ligaduras, t.nombre) {
            return leer_tipo(obtener(ligaduras, t.nombre) sino "");
        }
        return copiar(t);
    }
    var salida = copiar(t);
    var i = 0;
    while i < salida.args.largo() {
        salida.args[i] = sustituir_tipo(salida.args[i], ligaduras);
        i = i + 1;
    }
    return salida;
}

// `lista<P.Nodo>` -> `lista<Nodo>`: el alias de un modulo es de quien lo
// escribe, y los tipos se apuntan por su nombre.
fn sin_alias_tipo(t: view) -> str {
    var r = vacio();
    var i = 0;
    while i < t.largo() {
        if es_de_nombre(byte(t, i)) {
            var j = i;
            while j < t.largo() && es_de_nombre(byte(t, j)) { j = j + 1; }
            if j < t.largo() && byte(t, j) == 46 {
                i = j + 1; // `P.` fuera
                continue;
            }
            r.empujar(rebanar(t, i, j));
            i = j;
            continue;
        }
        r.empujar(rebanar(t, i, i + 1));
        i = i + 1;
    }
    return r;
}

fn es_de_nombre(b: usize) -> bool {
    if b >= 97 && b <= 122 { return true; }
    if b >= 65 && b <= 90 { return true; }
    if b >= 48 && b <= 57 { return true; }
    return b == 95;
}

fn tipo_existe(campos: &mapa<str, lista<str>>, t: view) -> bool {
    match forma_de(t) {
        Forma.Presta -> { return tipo_existe(campos, apuntado(t)); }
        Forma.PrestaMut -> { return tipo_existe(campos, apuntado(t)); }
        Forma.Funcion -> { return true; }
        Forma.Arreglo -> {
            let dentro = elemento(t);
            return tipo_existe(campos, dentro);
        }
        Forma.Mapa -> {
            let ps = partes(t);
            if ps.largo() != 2 { return false; }
            return tipo_existe(campos, ps[0]) && tipo_existe(campos, ps[1]);
        }
        Forma.Lista -> { return coleccion_existe(campos, t); }
        Forma.Bloque -> { return coleccion_existe(campos, t); }
        // Un rango solo existe en la cabecera de un `for`.
        Forma.Rango -> { return tiene(campos, t); }
        Forma.Nombre -> { }
    }
    if t == "str" || escalar(t) { return true; }
    return tiene(campos, t);
}

// Guardar vistas o arreglos fijos en una coleccion exigiria expresar su vida
// util o su tamaño, y v0 no los lleva en el tipo.
fn coleccion_existe(campos: &mapa<str, lista<str>>, t: view) -> bool {
    let dentro = elemento(t);
    if dentro == "view" { return false; }
    if es_arreglo(dentro) { return false; }
    return tipo_existe(campos, dentro);
}
