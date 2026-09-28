// tcodec.t — el archivo C entero, escrito por Tcode.
//
// El paso que separa "piezas que coinciden" de "un compilador": la cabecera,
// los modulos que el programa usa, sus structs, los tipos resultado, la
// aritmetica que hace falta, los prototipos y todas las funciones, `main`
// incluida, en el orden en que las escribe el generador de Python y con el
// mismo C. Lo que todavia no sabe escribir entero lo rechaza por la salida
// de error, sin escribir medio archivo.
//
// `std/` y `runtime/` estan donde diga `TCODE_RAIZ`; si no lo dice, los
// busca subiendo desde su propio ejecutable.
//
//     make tcodec
//     ./tcodec ejemplos/binario.t --mostrar-c > binario.c

usar "lib/programa.t" como F;
usar "lib/generar.t" como G;
usar "lib/tipar.t" como I;
usar "../lexer/lib/lexico.t";
usar "../lexer/lib/sintaxis.t" como P;
usar "lib/tipos.t" como T;
usar "lib/comprobar.t" como C;
usar "lib/formato.t" como FMT;
usar "std/texto";
usar "std/lista";
usar "../lexer/lib/clase.t";

// Lo que hace falta del sistema para construir el binario, escrito en C al
// lado: ejecutar el compilador de C, un temporal, y sustituir un archivo de
// una vez.
externo "lib/sistema_tcodec.c" {
    fn tcodec_pila_honda() -> i32;
    fn tcodec_ejecutar(orden: str) -> i32;
    fn tcodec_directorio_temporal() -> cadena_c;
    fn tcodec_ruta_real(ruta: str) -> cadena_c;
    fn tcodec_misma_ruta(a: str, b: str) -> i32;
    fn tcodec_es_archivo(ruta: str) -> i32;
    fn tcodec_temporal_junto(destino: str) -> cadena_c;
    fn tcodec_instalar(temporal: str, destino: str, ejecutable: i32) -> i32;
    fn tcodec_borrar(ruta: str);
    fn tcodec_raiz_instalada() -> cadena_c;
}

// Donde empieza `que` en `t` a partir de `desde`, o `largo(t)` si no esta.
fn buscar_desde(t: view, que: view, desde: usize) -> usize {
    if que.largo() == 0 {
        if desde <= t.largo() { return desde; }
        return t.largo();
    }
    // El primer byte descarta casi todas las posiciones sin cortar nada: se
    // busca en cada linea del C escrito, y cortar y comparar en cada byte era
    // lo que mas tardaba despues del lexer.
    let primero = byte(que, 0);
    var i = desde;
    while i + que.largo() <= t.largo() {
        if byte(t, i) == primero && igual(rebanar(t, i, i + que.largo()), que) { return i; }
        i = i + 1;
    }
    return t.largo();
}

// Lo que va entre `prefijo` y el `(` siguiente, en cada aparicion.
fn apuntar_tras(t: view, prefijo: view, salida: mut mapa<str, usize>) {
    var i = buscar_desde(t, prefijo, 0);
    while i < t.largo() {
        let desde = i + prefijo.largo();
        let hasta = buscar_desde(t, "(", desde);
        if hasta < t.largo() {
            poner(salida, rebanar(t, desde, hasta), 1);
        }
        i = buscar_desde(t, prefijo, desde);
    }
}

// La linea que instancia la aritmetica comprobada de un ancho.
fn fila_aritmetica(t: view) -> str {
    if t == "usize" { return nuevo("SS_LANG_ARIT_U(usize, size_t, SIZE_MAX)"); }
    if t == "u8" { return nuevo("SS_LANG_ARIT_U(u8, uint8_t, UINT8_MAX)"); }
    if t == "u16" { return nuevo("SS_LANG_ARIT_U(u16, uint16_t, UINT16_MAX)"); }
    if t == "u32" { return nuevo("SS_LANG_ARIT_U(u32, uint32_t, UINT32_MAX)"); }
    if t == "u64" { return nuevo("SS_LANG_ARIT_U(u64, uint64_t, UINT64_MAX)"); }
    if t == "i8" {
        return nuevo("SS_LANG_ARIT_I(i8, int8_t, uint8_t, INT8_MAX, INT8_MIN)");
    }
    if t == "i16" {
        return nuevo("SS_LANG_ARIT_I(i16, int16_t, uint16_t, INT16_MAX, INT16_MIN)");
    }
    if t == "i32" {
        return nuevo("SS_LANG_ARIT_I(i32, int32_t, uint32_t, INT32_MAX, INT32_MIN)");
    }
    return nuevo("SS_LANG_ARIT_I(i64, int64_t, uint64_t, INT64_MAX, INT64_MIN)");
}

fn maximo_entero(t: view) -> str {
    if t == "usize" { return nuevo("SIZE_MAX"); }
    if t == "u8" { return nuevo("UINT8_MAX"); }
    if t == "u16" { return nuevo("UINT16_MAX"); }
    if t == "u32" { return nuevo("UINT32_MAX"); }
    if t == "u64" { return nuevo("UINT64_MAX"); }
    if t == "i8" { return nuevo("INT8_MAX"); }
    if t == "i16" { return nuevo("INT16_MAX"); }
    if t == "i32" { return nuevo("INT32_MAX"); }
    return nuevo("INT64_MAX");
}

fn minimo_entero(t: view) -> str {
    if t == "i8" { return nuevo("INT8_MIN"); }
    if t == "i16" { return nuevo("INT16_MIN"); }
    if t == "i32" { return nuevo("INT32_MIN"); }
    return nuevo("INT64_MIN");
}

// Lo que este hito todavia no sabe emitir: cada uno pide una seccion propia
// del archivo (typedefs, tablas, ayudantes), y sin ella el C no compila.
// La linea sin lo que va entre comillas: un literal que diga `ss_lista_`
// no es un uso, y un compilador lleva muchos literales asi.
fn sin_cadenas(l: view) -> str {
    var r = vacio();
    var dentro = false;
    var desde = 0;
    var i = 0;
    while i < l.largo() {
        let c = byte(l, i);
        if dentro {
            if c == 92 {
                i = i + 2;
                continue;
            }
            if c == 34 {
                dentro = false;
                desde = i;
            }
        } else {
            if c == 34 {
                r.empujar(rebanar(l, desde, i + 1));
                dentro = true;
            }
        }
        i = i + 1;
    }
    if !dentro { r.empujar(rebanar(l, desde, l.largo())); }
    return r;
}

fn necesita_lo_que_falta(l: view) -> bool {
    let _l = l;
    return false;
}

// ------------------------------------------------------------------
// Rutas y modulos, como el cargador
// ------------------------------------------------------------------

fn quitar_ultima(xs: mut lista<str>) {
    var quedan: lista<str> = [];
    var i = 0;
    while i + 1 < xs.largo() {
        quedan.anadir(copiar(xs[i]));
        i = i + 1;
    }
    xs = quedan;
}

fn esta_en(xs: &lista<str>, x: view) -> bool {
    for y en xs {
        if igual(y, x) { return true; }
    }
    return false;
}

// Donde esta un modulo pedido. `std/` viene de la instalacion; lo demas es
// relativo al archivo que lo pide. La extension es opcional.
fn resolver(pedido: view, dir: view, raiz: view) -> str ! {
    var base = vacio();
    if empieza_con(pedido, "std/") {
        base.empujar(raiz);
        base.empujar("/std/");
        base.empujar(rebanar(pedido, 4, pedido.largo()));
    } else {
        if dir.largo() > 0 {
            base.empujar(dir);
            base.empujar("/");
        }
        base.empujar(pedido);
    }
    var candidatos: lista<str> = [];
    candidatos.anadir(copiar(base));
    if !termina_con(base, ".t") {
        var con_t = copiar(base);
        con_t.empujar(".t");
        candidatos.anadir(con_t);
    }
    for c en candidatos {
        if tcodec_es_archivo(copiar(c)) == 1 { return F.normalizar(c); }
    }
    // La primera, para que el error diga algo reconocible.
    return F.normalizar(candidatos[0]);
}

// Los `usar` del principio de un archivo, en orden.
fn usar_de(fuente: view) -> lista<str> ! {
    // Si no se puede leer, no pide nada: el error de verdad lo dice despues
    // `preparar`, con su archivo y su linea.
    let toks = analizar(fuente) sino [];
    var salida: lista<str> = [];
    var i = 0;
    while i + 1 < toks.largo() {
        if toks[i].valor != "usar" { break; }
        if toks[i + 1].tipo != "cadena" { break; }
        // `ruta\tlinea`: la linea es la del `usar`, para decir donde se pidio
        // un modulo que no esta.
        salida.anadir($"{toks[i + 1].valor}\t{toks[i].linea}");
        i = i + 2;
        if i + 1 < toks.largo() && toks[i].valor == "como" {
            i = i + 2;
        }
        i = i + 1; // el `;`
    }
    return salida;
}

// Los `usar` del principio con su alias: `ruta\talias\tlinea`, alias vacio
// si no lleva.
fn usar_con_alias(fuente: view) -> lista<str> ! {
    let toks = try analizar(fuente);
    var salida: lista<str> = [];
    var i = 0;
    while i + 1 < toks.largo() {
        if toks[i].valor != "usar" { break; }
        if toks[i + 1].tipo != "cadena" { break; }
        var junto = copiar(toks[i + 1].valor);
        junto.empujar("\t");
        let linea = toks[i].linea;
        i = i + 2;
        if i + 1 < toks.largo() && toks[i].valor == "como" {
            junto.empujar(toks[i + 1].valor);
            i = i + 2;
        }
        let pieza = $"\t{linea}";
        junto.empujar(pieza);
        salida.anadir(junto);
        i = i + 1; // el `;`
    }
    return salida;
}

// Si el archivo declara `fn main` fuera de toda llave. Se mira en los
// tokens, antes de analizar nada: el error es del `usar` que lo trae.
fn tiene_main(fuente: view) -> bool {
    let toks = analizar(fuente) sino [];
    var hondo = 0;
    var i = 0;
    while i < toks.largo() {
        let t = vista(toks[i].valor);
        let es_simbolo = toks[i].tipo == "simbolo";
        if es_simbolo && t == "{" {
            hondo = hondo + 1;
        } else if es_simbolo && t == "}" {
            if hondo > 0 { hondo = hondo - 1; }
        } else if hondo == 0 && t == "fn" && i + 1 < toks.largo()
        && toks[i + 1].valor == "main" {
            return true;
        }
        i = i + 1;
    }
    return false;
}

// Primero las dependencias, en el orden de los `usar`, y cada modulo una sola
// vez: el mismo recorrido que el cargador, que es el orden en que salen las
// funciones en el C. Si algo falla, `error` lo dice como el cargador de
// Python: un ciclo, o un modulo que no esta y quien lo pedia.
fn visitar(ruta: view, raiz: view, hechos: mut lista<str>,
    pila: mut lista<str>, error: mut str, quien: view, linea: usize) -> bool {
    if esta_en(pila, ruta) {
        var ciclo = vacio();
        var dentro = false;
        for p en pila {
            if igual(p, ruta) { dentro = true; }
            if dentro {
                ciclo.empujar(nombre_suelto(p));
                ciclo.empujar(" -> ");
            }
        }
        ciclo.empujar(nombre_suelto(ruta));
        error = $"dependencia circular entre modulos: {ciclo}";
        return false;
    }
    if esta_en(hechos, ruta) { return true; }
    if tcodec_es_archivo(nuevo(ruta)) == 0 {
        var de = vacio();
        if quien.largo() > 0 { de = $"{quien}:{linea}: "; }
        var pista = vacio();
        if empieza_con(ruta, "std/") || contiene(ruta, "/std/") {
            pista = nuevo("; los modulos de `std/` viven junto al compilador");
        }
        let suelto = nombre_suelto(ruta);
        let dicho = repr_texto(suelto);
        error = $"{de}no encuentro el modulo {dicho}{pista}";
        return false;
    }
    let fuente = leer_archivo(ruta) sino vacio();
    if quien.largo() > 0 && tiene_main(fuente) {
        error = $"{quien}:{linea}: `{ruta}` tiene `fn main`, y un modulo no puede tenerla: quitala, o compila `{ruta}` por su cuenta";
        return false;
    }
    pila.anadir(nuevo(ruta));
    let pedidos = usar_de(fuente) sino [];
    let dir = P.carpeta(ruta);
    for pedido en pedidos {
        let pedida = campo_pedido(pedido, 0);
        let texto_linea = campo_pedido(pedido, 1);
        let n = a_entero(texto_linea) sino 0;
        if contiene(pedida, "\0") {
            error = $"{ruta}:{n}: la ruta de un modulo no puede llevar un byte cero";
            return false;
        }
        let destino = resolver(pedida, dir, raiz) sino vacio();
        if !visitar(destino, raiz, hechos, pila, error, ruta, n) { return false; }
    }
    quitar_ultima(pila);
    hechos.anadir(nuevo(ruta));
    return true;
}

// ------------------------------------------------------------------
// Que ve cada archivo
// ------------------------------------------------------------------
//
// Cada archivo ve lo suyo y lo que trae cada `usar`, y nada mas. Como en el
// cargador de Python, un nombre que llega de dos sitios distintos es un
// error, y tambien usar algo de un modulo que este archivo no pidio aunque
// lo pida otro.

// Los modulos que declaran un nombre, en su orden.
fn declarantes(arboles: &lista<P.Nodo>, modulos: &lista<str>, nombre: view) -> lista<str> {
    var salida: lista<str> = [];
    var k = 0;
    while k < arboles.largo() {
        if esta_en(nombres_declarados(arboles[k]), nombre) { salida.anadir(copiar(modulos[k])); }
        k = k + 1;
    }
    return salida;
}

fn nombres_declarados(arbol: &P.Nodo) -> lista<str> {
    var salida: lista<str> = [];
    for d en arbol.hijos {
        let clase = d.clase;
        if clase == Clase.Fn || clase == Clase.Struct || clase == Clase.Enum {
            if !esta_en(salida, d.texto) { salida.anadir(copiar(d.texto)); }
        }
    }
    return salida;
}

// Los nombres que una funcion declara dentro: parametros, variables, los de
// un `for` y los que atrapa un `match`.
fn locales_de(n: &P.Nodo, salida: mut lista<str>) {
    let clase = n.clase;
    match clase {
        Clase.Param -> {
            var i = 0;
            while i < n.texto.largo() && byte(n.texto, i) != 58 { i = i + 1; }
            salida.anadir(nuevo(recortar(rebanar(n.texto, 0, i))));
        }
        Clase.Declaracion -> {
            let t = vista(n.texto);
            var i = 0;
            while i < t.largo() && byte(t, i) != 32 { i = i + 1; }
            var j = i + 1;
            while j < t.largo() && byte(t, j) != 58 { j = j + 1; }
            if i + 1 <= t.largo() { salida.anadir(nuevo(recortar(rebanar(t, i + 1, j)))); }
        }
        Clase.Para -> {
            let t = vista(n.texto);
            var i = 0;
            while i < t.largo() && byte(t, i) != 44 { i = i + 1; }
            salida.anadir(nuevo(recortar(rebanar(t, 0, i))));
            if i < t.largo() { salida.anadir(nuevo(recortar(rebanar(t, i + 1, t.largo())))); }
        }
        Clase.Atrapa -> { salida.anadir(copiar(n.texto)); }
        _ -> { }
    }
    for h en n.hijos { locales_de(h, salida); }
}

// El primer nombre que se usa sin haberlo pedido, en preorden: `nombre\tlinea`.
fn sin_pedir(n: &P.Nodo, visible: &mapa<str, str>, duenios: &mapa<str, str>,
    locales: &lista<str>) -> str {
    let clase = n.clase;
    var nombre = vacio();
    match clase {
        Clase.Llamada -> { nombre = copiar(n.texto); }
        Clase.LiteralStruct -> { nombre = copiar(n.texto); }
        Clase.EnumLit -> { nombre = I.antes_del_punto(n.texto); }
        _ -> { }
    }
    if nombre.largo() > 0 {
        let nv = vista(nombre);
        if !tiene(visible, nv) && tiene(duenios, nv) && !C.nombra_interna(nv)
        && !esta_en(locales, nv) {
            return $"{nombre}\t{n.linea}";
        }
    }
    for h en n.hijos {
        let dentro = sin_pedir(h, visible, duenios, locales);
        if dentro.largo() > 0 { return dentro; }
    }
    return vacio();
}

fn revisar_nombres(arboles: &lista<P.Nodo>, modulos: &lista<str>, raiz: view,
    error: mut str) -> bool {
    // Quien declara cada nombre, en el orden de los modulos.
    var duenios: mapa<str, str> = [];
    var cuantos: mapa<str, usize> = [];
    var k = 0;
    while k < arboles.largo() {
        for n en nombres_declarados(arboles[k]) {
            var junto = nuevo(obtener(duenios, n) sino "");
            if junto.largo() > 0 { junto.empujar(", "); }
            junto.empujar(modulos[k]);
            poner(duenios, vista(n), junto);
            let c = obtener(cuantos, n) sino 0;
            poner(cuantos, vista(n), c + 1);
        }
        k = k + 1;
    }
    k = 0;
    while k < arboles.largo() {
        // clave -> `modulo` que la trae; el valor interno es modulo+nombre,
        // salvo que el nombre lo declare uno solo.
        var visible: mapa<str, str> = [];
        for n en nombres_declarados(arboles[k]) {
            poner(visible, vista(n), copiar(modulos[k]));
        }
        let fuente = leer_archivo(modulos[k]) sino vacio();
        let pedidos = usar_con_alias(fuente) sino [];
        let dir = P.carpeta(modulos[k]);
        for pedido en pedidos {
            let ruta_p = campo_pedido(pedido, 0);
            let alias = campo_pedido(pedido, 1);
            let texto_linea = campo_pedido(pedido, 2);
            let destino = resolver(ruta_p, dir, raiz) sino vacio();
            var jm = 0;
            while jm < modulos.largo() && !igual(modulos[jm], destino) {
                jm = jm + 1;
            }
            if jm == modulos.largo() { continue; }
            for n en nombres_declarados(arboles[jm]) {
                var clave = copiar(n);
                if alias.largo() > 0 { clave = $"{alias}.{n}"; }
                if tiene(visible, clave) {
                    let previo = nuevo(obtener(visible, clave) sino "");
                    let varios = (obtener(cuantos, n) sino 0) > 1;
                    // Chocan si por dentro se llamarian distinto, y por dentro
                    // se llaman con el nombre del archivo delante: dos
                    // `x.t` en carpetas distintas no chocan aqui, como en el
                    // original.
                    let suyos = declarantes(arboles, modulos, n);
                    let pa = F.prefijo_unico(previo, suyos);
                    let pb = F.prefijo_unico(modulos[jm], suyos);
                    if varios && !igual(pa, pb) {
                        let dicho = G.legible_c(clave);
                        error = $"{modulos[k]}:{texto_linea}: `{dicho}` llega de dos sitios, {previo} y {modulos[jm]}. Dale un nombre a uno de los dos: `usar \"...\" como algo;` y luego `algo.{dicho}`";
                        return false;
                    }
                }
                poner(visible, vista(clave), copiar(modulos[jm]));
            }
        }
        // Y lo que se usa sin pedirlo.
        for d en arboles[k].hijos {
            if d.clase != Clase.Fn { continue; }
            var locales: lista<str> = [];
            locales_de(d, locales);
            for h en d.hijos {
                if h.clase != Clase.Bloque { continue; }
                let hallado = sin_pedir(h, visible, duenios, locales);
                if hallado.largo() > 0 {
                    let nombre = campo_pedido(hallado, 0);
                    let linea = campo_pedido(hallado, 1);
                    let donde = obtener(duenios, nombre) sino "";
                    let dicho = G.escrito(nombre);
                    error = $"{modulos[k]}:{linea}: `{dicho}` esta en {donde}, que este archivo no usa. Se veia porque lo usa otro modulo, pero cada archivo tiene que pedir lo suyo: añade `usar \"...\";`";
                    return false;
                }
            }
        }
        k = k + 1;
    }
    return true;
}

// ------------------------------------------------------------------
// Structs y resultados
// ------------------------------------------------------------------

// Un struct por valor necesita el tamanio del que lleva dentro: se definen
// en orden de dependencia, visitando antes lo que contiene cada uno.
fn visitar_struct(nombre: view, indice: &mapa<str, usize>,
    tipos_de: &lista<lista<str>>, listos: mut mapa<str, usize>,
    salida: mut lista<str>) {
    if tiene(listos, nombre) || !tiene(indice, nombre) { return; }
    poner(listos, nombre, 1);
    let k = obtener(indice, nombre) sino 0;
    for t en tipos_de[k] {
        // Un arreglo de structs necesita el tamaño del de dentro.
        var base = copiar(t);
        while T.es_arreglo(base) {
            let pa = T.partes_de_arreglo(base);
            if pa.largo() != 2 { break; }
            base = copiar(pa[0]);
        }
        visitar_struct(base, indice, tipos_de, listos, salida);
    }
    salida.anadir(nuevo(nombre));
}

// Define en C el enum o struct `nombre`, y antes lo que lleve por valor.
fn definir_tipo_c(nombre: view, en_nombres: &lista<str>, en_variantes: &lista<lista<str>>,
    en_lleva: &lista<lista<str>>, st_indice: &mapa<str, usize>,
    st_campos: &lista<lista<str>>, st_tipos: &lista<lista<str>>,
    definidos: mut mapa<str, usize>, partes: mut lista<str>) {
    if tiene(definidos, nombre) { return; }
    var ie = 0;
    while ie < en_nombres.largo() && !igual(en_nombres[ie], nombre) { ie = ie + 1; }
    let es_enum = ie < en_nombres.largo();
    if !es_enum && !tiene(st_indice, nombre) { return; }
    poner(definidos, nombre, 1);
    var lleva: lista<str> = [];
    if es_enum {
        for x en en_lleva[ie] {
            for t en partir_tab(x) { lleva.anadir(copiar(t)); }
        }
    } else {
        let k = obtener(st_indice, nombre) sino 0;
        for t en st_tipos[k] { lleva.anadir(copiar(t)); }
    }
    for t en lleva {
        var base = copiar(t);
        while T.es_arreglo(base) {
            let pa = T.partes_de_arreglo(base);
            if pa.largo() != 2 { break; }
            base = copiar(pa[0]);
        }
        definir_tipo_c(vista(base), en_nombres, en_variantes, en_lleva, st_indice, st_campos,
            st_tipos, definidos, partes);
    }
    if es_enum {
        cuerpo_enum_c(ie, en_nombres, en_variantes, en_lleva, partes);
    } else {
        let k = obtener(st_indice, nombre) sino 0;
        partes.anadir($"struct {nombre}");
        partes.anadir(nuevo("{"));
        var j = 0;
        while j < st_campos[k].largo() {
            let tc = G.tipo_c(st_tipos[k][j]);
            partes.anadir($"    {tc} {st_campos[k][j]};");
            j = j + 1;
        }
        partes.anadir(nuevo("};"));
        partes.anadir(vacio());
    }
}

// Un enum en C: la etiqueta y, a su lado, una union con lo de cada forma.
fn cuerpo_enum_c(ie_s: usize, en_nombres: &lista<str>, en_variantes: &lista<lista<str>>,
    en_lleva: &lista<lista<str>>, partes: mut lista<str>) {
    let en_n = copiar(en_nombres[ie_s]);
    partes.anadir($"struct {en_n}");
    partes.anadir(nuevo("{"));
    partes.anadir(nuevo("    uint32_t etiqueta;"));
    var hay_datos = false;
    for ll en en_lleva[ie_s] {
        if ll.largo() > 0 { hay_datos = true; }
    }
    if hay_datos {
        partes.anadir(nuevo("    union"));
        partes.anadir(nuevo("    {"));
        var iv = 0;
        while iv < en_variantes[ie_s].largo() {
            let tipos_v = partir_tab(en_lleva[ie_s][iv]);
            if tipos_v.largo() > 0 {
                var campos_c = vacio();
                var q = 0;
                while q < tipos_v.largo() {
                    let tc = G.tipo_c(tipos_v[q]);
                    if q > 0 { campos_c.empujar(" "); }
                    let pieza = $"{tc} _{q};";
                    campos_c.empujar(pieza);
                    q = q + 1;
                }
                partes.anadir($"        struct {{ {campos_c} }} v_{en_variantes[ie_s][iv]};");
            }
            iv = iv + 1;
        }
        partes.anadir(nuevo("    } dato;"));
    }
    partes.anadir(nuevo("};"));
    partes.anadir(vacio());
}

// Si en algun sitio de `n` se llama a la interna `nombre`.
fn llama_a(n: &P.Nodo, nombre: view) -> bool {
    if n.clase == Clase.Llamada && igual(n.texto, nombre) {
        return true;
    }
    for h en n.hijos {
        if llama_a(h, nombre) { return true; }
    }
    return false;
}

// `leer_archivo` solo entra en el programa que lo usa.
// Escribir un archivo entero: la ruta sin ceros por medio, y un fallo al
// abrir, al escribir o al cerrar es un fallo, no un archivo a medias callado.
fn ayudante_escribir_archivo(salida: mut lista<str>) {
    let res = G.tipo_resultado("()");
    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static {res} ss_lang_escribir_archivo_(SafeView ruta, SafeView datos)");
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    if (ruta.len != 0 && memchr(ruta.ptr, 0, ruta.len) != NULL)"));
    salida.anadir($"        return ({res}){{ .motivo = \"la ruta contiene un byte cero\" }};");
    salida.anadir(vacio());
    salida.anadir(nuevo("    SafeString copia = ss_from_view(ruta);"));
    salida.anadir(nuevo("    if (!ss_ok(&copia))"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        ss_free(&copia);"));
    salida.anadir($"        return ({res}){{ .motivo = \"sin memoria para la ruta\" }};");
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    FILE* f = fopen(ss_cstr(&copia), \"wb\");"));
    salida.anadir(nuevo("    ss_free(&copia);"));
    salida.anadir(nuevo("    if (f == NULL)"));
    salida.anadir($"        return ({res}){{ .motivo = \"no se pudo abrir el archivo para escribir\" }};");
    salida.anadir(vacio());
    salida.anadir(nuevo("    bool fallo = false;"));
    salida.anadir(nuevo("    if (datos.len != 0)"));
    salida.anadir(nuevo("        fallo = fwrite(datos.ptr, 1, datos.len, f) != datos.len;"));
    salida.anadir(nuevo("    if (fclose(f) != 0) fallo = true;"));
    salida.anadir(nuevo("    if (fallo)"));
    salida.anadir($"        return ({res}){{ .motivo = \"fallo al escribir el archivo\" }};");
    salida.anadir($"    return ({res}){{ .motivo = NULL }};");
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());
}

// Las internas que pueden fallar necesitan su tipo resultado, y el original
// los apunta en el orden en que aparecen sus llamadas, entrando en cada
// clausura donde esta escrita.
fn resultados_de_internas(n: &P.Nodo, cierres: &Cierres, reg: mut Registro) {
    let clase = n.clase;
    if clase == Clase.Llamada {
        let nombre = vista(n.texto);
        if nombre == "leer_archivo" || nombre == "leer_parte_archivo"
        || nombre == "leer_linea"
        || nombre == "entrada_completa" || nombre == "variable_entorno" {
            registrar_resultado(reg, "str");
        }
        if nombre == "escribir_archivo" { registrar_resultado(reg, "()"); }
    }
    if clase == Clase.Cierre {
        let de_cierre = I.funcion_de_cierre(n.texto);
        if tiene(cierres.indice, de_cierre) {
            let k = obtener(cierres.indice, de_cierre) sino 0;
            resultados_de_internas(cierres.fns[k], cierres, reg);
        }
    }
    for h en n.hijos { resultados_de_internas(h, cierres, reg); }
}

fn ayudante_leer_archivo(salida: mut lista<str>) {
    let res = G.tipo_resultado("str");
    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static {res} ss_lang_leer_archivo_(SafeView ruta)");
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    if (ruta.len != 0 && memchr(ruta.ptr, 0, ruta.len) != NULL)"));
    salida.anadir($"        return ({res}){{ .motivo = \"la ruta contiene un byte cero\" }};");
    salida.anadir(nuevo("    SafeString nombre = ss_from_view(ruta);"));
    salida.anadir(nuevo("    if (!ss_ok(&nombre))"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        ss_free(&nombre);"));
    salida.anadir($"        return ({res}){{ .motivo = \"sin memoria para la ruta\" }};");
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    FILE* f = fopen(ss_cstr(&nombre), \"rb\");"));
    salida.anadir(nuevo("    ss_free(&nombre);"));
    salida.anadir(nuevo("    if (f == NULL)"));
    salida.anadir($"        return ({res}){{ .motivo = \"no se pudo abrir el archivo\" }};");
    salida.anadir(nuevo("    SafeString contenido = ss_new();"));
    salida.anadir(nuevo("    unsigned char bloque[8192];"));
    salida.anadir(nuevo("    size_t n;"));
    salida.anadir(nuevo("    while ((n = fread(bloque, 1, sizeof(bloque), f)) != 0)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        if (!ss_append_len(&contenido, (const char*) bloque, n))"));
    salida.anadir(nuevo("        {"));
    salida.anadir(nuevo("            fclose(f);"));
    salida.anadir(nuevo("            ss_free(&contenido);"));
    salida.anadir($"            return ({res}){{ .motivo = \"sin memoria al leer el archivo\" }};");
    salida.anadir(nuevo("        }"));
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    bool fallo_lectura = ferror(f) != 0;"));
    salida.anadir(nuevo("    if (fclose(f) != 0) fallo_lectura = true;"));
    salida.anadir(nuevo("    if (fallo_lectura)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        ss_free(&contenido);"));
    salida.anadir($"        return ({res}){{ .motivo = \"fallo al leer el archivo\" }};");
    salida.anadir(nuevo("    }"));
    salida.anadir($"    return ({res}){{ .motivo = NULL, .valor = contenido }};");
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());
}

fn ayudante_leer_parte_archivo(salida: mut lista<str>) {
    let res = G.tipo_resultado("str");
    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static {res} ss_lang_leer_parte_archivo_(SafeView ruta, size_t desde, size_t cuantos)");
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    if (cuantos == 0)"));
    salida.anadir($"        return ({res}){{ .motivo = \"el tamano de lectura tiene que ser mayor que cero\" }};");
    salida.anadir(nuevo("    if (desde > (size_t) LONG_MAX)"));
    salida.anadir($"        return ({res}){{ .motivo = \"la posicion del archivo es demasiado grande\" }};");
    salida.anadir(nuevo("    if (ruta.len != 0 && memchr(ruta.ptr, 0, ruta.len) != NULL)"));
    salida.anadir($"        return ({res}){{ .motivo = \"la ruta contiene un byte cero\" }};");
    salida.anadir(nuevo("    SafeString nombre = ss_from_view(ruta);"));
    salida.anadir(nuevo("    if (!ss_ok(&nombre))"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        ss_free(&nombre);"));
    salida.anadir($"        return ({res}){{ .motivo = \"sin memoria para la ruta\" }};");
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    FILE* f = fopen(ss_cstr(&nombre), \"rb\");"));
    salida.anadir(nuevo("    ss_free(&nombre);"));
    salida.anadir(nuevo("    if (f == NULL)"));
    salida.anadir($"        return ({res}){{ .motivo = \"no se pudo abrir el archivo\" }};");
    salida.anadir(nuevo("    if (fseek(f, (long) desde, SEEK_SET) != 0)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        fclose(f);"));
    salida.anadir($"        return ({res}){{ .motivo = \"no se pudo buscar la posicion del archivo\" }};");
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    SafeString contenido = ss_new();"));
    salida.anadir(nuevo("    unsigned char bloque[8192];"));
    salida.anadir(nuevo("    size_t quedan = cuantos;"));
    salida.anadir(nuevo("    while (quedan != 0)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        size_t pedido = quedan < sizeof(bloque) ? quedan : sizeof(bloque);"));
    salida.anadir(nuevo("        size_t n = fread(bloque, 1, pedido, f);"));
    salida.anadir(nuevo("        if (n != 0 && !ss_append_len(&contenido, (const char*) bloque, n))"));
    salida.anadir(nuevo("        {"));
    salida.anadir(nuevo("            fclose(f);"));
    salida.anadir(nuevo("            ss_free(&contenido);"));
    salida.anadir($"            return ({res}){{ .motivo = \"sin memoria al leer el archivo\" }};");
    salida.anadir(nuevo("        }"));
    salida.anadir(nuevo("        quedan -= n;"));
    salida.anadir(nuevo("        if (n < pedido) break;"));
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    bool fallo_lectura = ferror(f) != 0;"));
    salida.anadir(nuevo("    if (fclose(f) != 0) fallo_lectura = true;"));
    salida.anadir(nuevo("    if (fallo_lectura)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        ss_free(&contenido);"));
    salida.anadir($"        return ({res}){{ .motivo = \"fallo al leer el archivo\" }};");
    salida.anadir(nuevo("    }"));
    salida.anadir($"    return ({res}){{ .motivo = NULL, .valor = contenido }};");
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());
}

fn typedef_resultado(t: view) -> str {
    let nombre = G.tipo_resultado(t);
    if t.largo() == 0 || t == "()" {
        return $"typedef struct {{ const char* motivo; }} {nombre};";
    }
    let tc = G.tipo_c(t);
    return $"typedef struct {{ const char* motivo; {tc} valor; }} {nombre};";
}

fn es_falible(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if h.clase == Clase.Falible { return true; }
    }
    return false;
}

fn retorno_de(d: &P.Nodo) -> str {
    for h en d.hijos {
        if h.clase == Clase.RetornoTipo {
            return I.sin_alias_tipo(h.texto);
        }
    }
    return vacio();
}

fn tiene_tipo_param(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if h.clase == Clase.TipoParam { return true; }
    }
    return false;
}

fn rechazo(que: view) -> usize {
    imprimir_error($"tcodec: todavia no se escribir {que}\n");
    return 1;
}

// ------------------------------------------------------------------
// Listas
// ------------------------------------------------------------------
//
// Cada `lista<T>` concreta lleva su typedef y sus funciones propias: no hay
// `void*` ni tamanios pasados a mano. Los typedefs salen ordenados por
// nombre; las funciones, en el orden en que el original registro cada tipo,
// que es el de su recorrido previo: campos de struct, retorno, parametros y
// declaraciones, entrando en `if` y `while` pero no en `for` ni `match`.

// Lo que el recorrido previo registra, en el orden en que lo registra el
// original: cada coleccion concreta y cada tipo resultado. Un mapa registra
// al pasar la lista de sus claves y los resultados de `obtener`, asi que
// los tres van en el mismo recorrido y no en tres.
struct Registro {
    listas: lista<str>,
    mapas: lista<str>,
    resultados: lista<str>,
    vistos: mapa<str, usize>,
    res_vistos: mapa<str, usize>,
    // Cada `bloque<T>`, en el orden en que se registra: antes que lo que
    // lleva dentro, al reves que una lista.
    bloques: lista<str>,
    // Los envoltorios de arreglo van aparte: no son agregados sin nombre.
    arreglos: lista<str>,
    arr_vistos: mapa<str, usize>,
}

fn registro() -> Registro {
    return Registro { listas: [], mapas: [], resultados: [], vistos: [],
        res_vistos: [], arreglos: [], arr_vistos: [], bloques: [] };
}

fn registrar_resultado(reg: mut Registro, t: view) {
    var clave = I.nombre_resuelto(t);
    if t == "()" { clave = vacio(); }
    if tiene(reg.res_vistos, clave) { return; }
    poner(reg.res_vistos, vista(clave), 1);
    reg.resultados.anadir(clave);
}

// Tiene partes: se puede leer un campo o modificarlo en el sitio.
fn es_compuesto_t(t: view, structs: &mapa<str, usize>) -> bool {
    if t == "str" || T.es_bloque(t) { return true; }
    if T.es_lista(t) || T.es_mapa(t) { return true; }
    if T.es_arreglo(t) { return true; }
    return tiene(structs, t);
}

// Lo que devuelve `obtener` para un mapa cuyo valor es `v`.
fn tipo_obtener(v: view, global: &I.Contexto) -> str {
    if !I.posee_con_formas(global, v) { return nuevo(v); }
    if v == "str" { return nuevo("view"); }
    return T.hacer_prestado(v);
}

// Registra `t` si es una lista o un mapa, lo de dentro primero. Falso si
// es algo que este hito todavia no escribe.
fn mirar_tipo(t: view, reg: mut Registro, global: &I.Contexto,
    structs: &mapa<str, usize>) -> bool {
    if contiene(t, "<") {
        let resuelto = I.nombre_resuelto(t);
        if !igual(resuelto, t) {
            return mirar_tipo(resuelto, reg, global, structs);
        }
    }
    if T.es_arreglo(t) {
        let pa = T.partes_de_arreglo(t);
        if pa.largo() != 2 { return false; }
        if tiene(reg.arr_vistos, t) { return true; }
        // El typedef del elemento va antes que el envoltorio del arreglo:
        // tambien cuando el elemento es una lista, mapa o bloque.
        if !mirar_tipo(pa[0], reg, global, structs) { return false; }
        poner(reg.arr_vistos, t, 1);
        reg.arreglos.anadir(nuevo(t));
        return true;
    }
    if T.es_bloque(t) {
        if tiene(reg.vistos, t) { return true; }
        poner(reg.vistos, t, 1);
        reg.bloques.anadir(nuevo(t));
        let dentro_b = T.elemento(t);
        return mirar_tipo(dentro_b, reg, global, structs);
    }
    // Una lista o un mapa de bloques o arreglos registran lo de dentro al
    // registrarse, como cualquier otra lista o mapa.
    if T.lleva_bloque_o_arreglo(t) && !T.es_lista(t) && !T.es_mapa(t) {
        // Un prestamo no registra nada, como en el original.
        if T.es_referencia(t) { return true; }
        imprimir_error($"tcodec: el tipo `{t}`\n");
        return false;
    }
    if tiene(reg.vistos, t) { return true; }
    if T.es_lista(t) {
        let dentro = T.elemento(t);
        // Igual que el generador de referencia: lo que lleva dentro tiene que
        // registrarse antes, aunque sea un mapa o un bloque y no otra lista.
        if !mirar_tipo(dentro, reg, global, structs) { return false; }
        poner(reg.vistos, t, 1);
        reg.listas.anadir(nuevo(t));
        return true;
    }
    if !T.es_mapa(t) { return true; }
    let partes = T.partes(t);
    if partes.largo() != 2 { return false; }
    // El nombre en C de la clave y del valor, la lista que devuelve
    // `claves`, y los resultados de `obtener` y de `obtener_mut`.
    for x en partes {
        if T.es_lista(x) || T.es_mapa(x) || T.lleva_bloque_o_arreglo(x) {
            if !mirar_tipo(x, reg, global, structs) { return false; }
        }
    }
    let de_claves = T.hacer_lista(partes[0]);
    if !mirar_tipo(de_claves, reg, global, structs) { return false; }
    let obt = tipo_obtener(partes[1], global);
    registrar_resultado(reg, obt);
    if es_compuesto_t(partes[1], structs) {
        let con_mut = T.hacer_prestado_mut(partes[1]);
        registrar_resultado(reg, con_mut);
    }
    poner(reg.vistos, t, 1);
    reg.mapas.anadir(nuevo(t));
    return true;
}

fn mirar_bloque(n: &P.Nodo, tipos: mut I.Contexto, reg: mut Registro,
    global: &I.Contexto, structs: &mapa<str, usize>) -> bool {
    I.abrir(tipos);
    var bien = true;
    for st en n.hijos {
        let clase = st.clase;
        match clase {
            Clase.Declaracion -> {
                if st.hijos.largo() == 1 {
                    let nombre = G.nombre_declarado(st.texto);
                    var escrito = G.tipo_escrito(st.texto);
                    if escrito.largo() == 0 { escrito = I.tipo_de(tipos, st.hijos[0]); }
                    let t = I.sin_alias_tipo(escrito);
                    if bien { bien = mirar_tipo(t, reg, global, structs); }
                    I.declarar(tipos, nombre, t);
                }
            }
            Clase.Si -> {
                var k = 1;
                while k < st.hijos.largo() {
                    if bien {
                        bien = mirar_bloque(st.hijos[k], tipos, reg, global, structs);
                    }
                    k = k + 1;
                }
            }
            Clase.Mientras -> {
                if st.hijos.largo() == 2 {
                    if bien {
                        bien = mirar_bloque(st.hijos[1], tipos, reg, global, structs);
                    }
                }
            }
            _ -> { }
        }
    }
    I.cerrar(tipos);
    return bien;
}

fn mirar_funcion(d: &P.Nodo, tipos: mut I.Contexto, reg: mut Registro,
    global: &I.Contexto, structs: &mapa<str, usize>) -> bool {
    let r = retorno_de(d);
    if !mirar_tipo(r, reg, global, structs) { return false; }
    if es_falible(d) { registrar_resultado(reg, r); }
    I.abrir(tipos);
    var bien = true;
    for h en d.hijos {
        if h.clase == Clase.Param {
            let pelado = F.tipo_pelado(h.texto);
            let t = I.sin_alias_tipo(pelado);
            if bien { bien = mirar_tipo(t, reg, global, structs); }
            let pn = F.nombre_de(h.texto);
            I.declarar(tipos, pn, t);
        }
    }
    for h en d.hijos {
        if h.clase == Clase.Bloque && bien {
            bien = mirar_bloque(h, tipos, reg, global, structs);
        }
    }
    I.cerrar(tipos);
    return bien;
}

// Los typedefs de listas y mapas van juntos, ordenados por el tipo escrito,
// cada uno despues de los que lleva dentro.
fn poner_typedef(t: view, reg: &Registro, puestos: mut mapa<str, usize>,
    salida: mut lista<str>) {
    if tiene(puestos, t) || !tiene(reg.vistos, t) { return; }
    poner(puestos, t, 1);
    let tc = G.tipo_c(t);
    if T.es_bloque(t) {
        let dentro_b = T.elemento(t);
        poner_typedef(dentro_b, reg, puestos, salida);
        let te_b = G.tipo_c(dentro_b);
        salida.anadir($"typedef struct {{ {te_b}* e; size_t n; }} {tc};");
        return;
    }
    if T.es_lista(t) {
        let dentro = T.elemento(t);
        poner_typedef(dentro, reg, puestos, salida);
        let te = G.tipo_c(dentro);
        salida.anadir($"typedef struct {{ {te}* e; size_t length; size_t capacity; }} {tc};");
        return;
    }
    let partes = T.partes(t);
    for x en partes { poner_typedef(x, reg, puestos, salida); }
    let tk = G.tipo_c(partes[0]);
    let tv = G.tipo_c(partes[1]);
    salida.anadir($"typedef struct {{ {tk}* claves; {tv}* valores; size_t largo; size_t capacidad; }} {tc};");
}

fn ordenable(t: view) -> bool {
    if t == "str" || t == "bool" { return true; }
    if t == "usize" || t == "u8" || t == "u16" { return true; }
    if t == "u32" || t == "u64" || t == "i8" { return true; }
    if t == "i16" || t == "i32" || t == "i64" { return true; }
    return t == "f32" || t == "f64";
}

fn funcion_push(t: view, salida: mut lista<str>) {
    let dentro = T.elemento(t);
    let te = G.tipo_c(dentro);
    let tc = G.tipo_c(t);
    let m = G.mangle(t);
    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static void ss_push_{m}({tc}* p, {te} valor,");
    salida.anadir(nuevo("        const char* archivo, int linea)"));
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    if (p->length == p->capacity)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        if (p->length == SIZE_MAX)"));
    salida.anadir(nuevo("            ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir(nuevo("        size_t nueva = p->capacity == 0 ? 8 : p->capacity;"));
    salida.anadir(nuevo("        if (nueva < p->length + 1)"));
    salida.anadir(nuevo("        {"));
    salida.anadir(nuevo("            nueva = nueva > SIZE_MAX / 2 ? SIZE_MAX : nueva * 2;"));
    salida.anadir(nuevo("            if (nueva < p->length + 1) nueva = p->length + 1;"));
    salida.anadir(nuevo("        }"));
    salida.anadir(nuevo("        if (nueva > SIZE_MAX / sizeof(*p->e))"));
    salida.anadir(nuevo("            ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir(nuevo("        void* memoria = realloc(p->e, nueva * sizeof(*p->e));"));
    salida.anadir(nuevo("        if (memoria == NULL) ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir($"        p->e = ({te}*) memoria;");
    salida.anadir(nuevo("        p->capacity = nueva;"));
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    p->e[p->length++] = valor;"));
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());
}

fn funcion_ordenar(t: view, salida: mut lista<str>) {
    let dentro = T.elemento(t);
    if !ordenable(dentro) { return; }
    let te = G.tipo_c(dentro);
    let tc = G.tipo_c(t);
    let m = G.mangle(t);
    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static int ss_cmp_{m}(const void* a, const void* b)");
    salida.anadir(nuevo("{"));
    if dentro == "str" {
        salida.anadir(nuevo("    return ss_cmp((const SafeString*) a, (const SafeString*) b);"));
    } else {
        salida.anadir($"    {te} x = *(const {te}*) a;");
        salida.anadir($"    {te} y = *(const {te}*) b;");
        salida.anadir(nuevo("    return (x > y) - (x < y);"));
    }
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());
    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static void ss_ordenar_{m}({tc}* p)");
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    if (p->length > 1)"));
    salida.anadir($"        qsort(p->e, p->length, sizeof(*p->e), ss_cmp_{m});");
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());
}

// Las lineas que sueltan `donde`, con la misma cuenta que el resto: una
// lista dentro de un valor gasta indice de bucle.
fn lineas_liberacion(global: &I.Contexto, donde: view, tipo: view,
    sangria: usize, cta: mut F.Cuenta, salida: mut lista<str>) {
    var b = G.cuerpo();
    b.temporal = cta.temporal;
    b.bucle = cta.bucle;
    b.etiquetas = cta.etiquetas;
    b.sangria = sangria;
    G.liberacion(b, global, donde, tipo);
    for l en b.lineas { salida.anadir(copiar(l)); }
    cta.temporal = b.temporal;
    cta.bucle = b.bucle;
    cta.etiquetas = b.etiquetas;
}

// Un juego de funciones por cada `mapa<K, V>` concreto: tabla de
// direccionamiento abierto con sondeo lineal, y borrado sin lapidas.
fn funcion_mapa(t: view, global: &I.Contexto, structs: &mapa<str, usize>,
    cta: mut F.Cuenta, salida: mut lista<str>) {
    let partes = T.partes(t);
    let k = copiar(partes[0]);
    let v = copiar(partes[1]);
    let m = G.mangle(t);
    let nombre = G.tipo_c(t);
    let tc_k = G.tipo_c(k);
    let tc_v = G.tipo_c(v);
    let de_claves = T.hacer_lista(k);
    let lista_k = G.tipo_c(de_claves);
    let m_claves = G.mangle(de_claves);
    let obt = tipo_obtener(v, global);
    let res_v = G.tipo_resultado(obt);
    let posee = I.posee_con_formas(global, v);

    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static size_t ss_mapa_sitio_{m}(const {nombre}* p, SafeView clave)");
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    /* La capacidad es potencia de dos, asi que el resto es"));
    salida.anadir(nuevo("       una mascara. Sondeo lineal: bueno con la cache y sin"));
    salida.anadir(nuevo("       lapidas, porque en v0 no se borra. */"));
    salida.anadir(nuevo("    size_t mascara = p->capacidad - 1;"));
    salida.anadir(nuevo("    size_t i = (size_t) sv_hash(clave) & mascara;"));
    salida.anadir(nuevo("    while (p->claves[i].data != NULL)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        if (sv_equals(ss_view(&p->claves[i]), clave)) return i;"));
    salida.anadir(nuevo("        i = (i + 1) & mascara;"));
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    return i;   /* celda libre: aqui iria */"));
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());

    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static void ss_mapa_crecer_{m}({nombre}* p, const char* archivo, int linea)");
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    size_t nueva = p->capacidad == 0 ? 16 : p->capacidad * 2;"));
    salida.anadir(nuevo("    if (nueva < p->capacidad) ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir($"    if (nueva > SIZE_MAX / sizeof({tc_k})");
    salida.anadir($"        || nueva > SIZE_MAX / sizeof({tc_v}))");
    salida.anadir(nuevo("        ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir(vacio());
    salida.anadir($"    {nombre} nuevo;");
    salida.anadir($"    nuevo.claves = ({tc_k}*) calloc(nueva, sizeof({tc_k}));");
    if posee {
        salida.anadir($"    nuevo.valores = ({tc_v}*) calloc(nueva, sizeof({tc_v}));");
    } else {
        salida.anadir($"    nuevo.valores = ({tc_v}*) malloc(nueva * sizeof({tc_v}));");
    }
    salida.anadir(nuevo("    if (nuevo.claves == NULL || nuevo.valores == NULL)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        free(nuevo.claves); free(nuevo.valores);"));
    salida.anadir(nuevo("        ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    nuevo.largo = p->largo;"));
    salida.anadir(nuevo("    nuevo.capacidad = nueva;"));
    salida.anadir(vacio());
    salida.anadir(nuevo("    /* Se reubican las claves tal cual: nadie copia texto. */"));
    salida.anadir(nuevo("    for (size_t i = 0; i < p->capacidad; i++)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        if (p->claves[i].data == NULL) continue;"));
    salida.anadir($"        size_t j = ss_mapa_sitio_{m}(&nuevo, ss_view(&p->claves[i]));");
    salida.anadir(nuevo("        nuevo.claves[j] = p->claves[i];"));
    salida.anadir(nuevo("        nuevo.valores[j] = p->valores[i];"));
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    free(p->claves); free(p->valores);"));
    salida.anadir(nuevo("    *p = nuevo;"));
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());

    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static void ss_mapa_poner_{m}({nombre}* p, SafeView clave, {tc_v} valor,");
    salida.anadir(nuevo("        const char* archivo, int linea)"));
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    /* Se crece al 70% de ocupacion: por encima, el sondeo"));
    salida.anadir(nuevo("       lineal empieza a formar cadenas largas. */"));
    salida.anadir(nuevo("    if (p->capacidad == 0 || (p->largo + 1) * 10 >= p->capacidad * 7)"));
    salida.anadir($"        ss_mapa_crecer_{m}(p, archivo, linea);");
    salida.anadir(vacio());
    salida.anadir($"    size_t i = ss_mapa_sitio_{m}(p, clave);");
    salida.anadir(nuevo("    if (p->claves[i].data != NULL)"));
    salida.anadir(nuevo("    {"));
    if posee {
        salida.anadir(nuevo("        /* el valor viejo era nuestro */"));
        lineas_liberacion(global, "p->valores[i]", v, 2, cta, salida);
    }
    salida.anadir(nuevo("        p->valores[i] = valor;   /* ya estaba: se reemplaza */"));
    salida.anadir(nuevo("        return;"));
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    p->claves[i] = ss_from_view(clave);"));
    salida.anadir(nuevo("    if (!ss_ok(&p->claves[i])) ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir(nuevo("    p->valores[i] = valor;"));
    salida.anadir(nuevo("    p->largo++;"));
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());

    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static bool ss_mapa_tiene_{m}(const {nombre}* p, SafeView clave)");
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    if (p->capacidad == 0) return false;"));
    salida.anadir($"    return p->claves[ss_mapa_sitio_{m}(p, clave)].data != NULL;");
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());

    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static {res_v} ss_mapa_obtener_{m}(const {nombre}* p, SafeView clave)");
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    if (p->capacidad == 0)"));
    salida.anadir($"        return ({res_v}){{ .motivo = \"la clave no esta en el mapa\" }};");
    salida.anadir($"    size_t i = ss_mapa_sitio_{m}(p, clave);");
    salida.anadir(nuevo("    if (p->claves[i].data == NULL)"));
    salida.anadir($"        return ({res_v}){{ .motivo = \"la clave no esta en el mapa\" }};");
    if v == "str" {
        salida.anadir($"    return ({res_v}){{ .motivo = NULL, .valor = ss_view(&p->valores[i]) }};");
    } else {
        if posee {
            salida.anadir($"    return ({res_v}){{ .motivo = NULL, .valor = &p->valores[i] }};");
        } else {
            salida.anadir($"    return ({res_v}){{ .motivo = NULL, .valor = p->valores[i] }};");
        }
    }
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());

    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static {lista_k} ss_mapa_claves_{m}(const {nombre}* p,");
    salida.anadir(nuevo("        const char* archivo, int linea)"));
    salida.anadir(nuevo("{"));
    salida.anadir($"    {lista_k} salida = {{ NULL, 0, 0 }};");
    salida.anadir(nuevo("    for (size_t i = 0; i < p->capacidad; i++)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        if (p->claves[i].data == NULL) continue;"));
    salida.anadir($"        {tc_k} copia = ss_clone(&p->claves[i]);");
    salida.anadir(nuevo("        if (!ss_ok(&copia)) ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir($"        ss_push_{m_claves}(&salida, copia, archivo, linea);");
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    return salida;"));
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());

    if es_compuesto_t(v, structs) {
        let con_mut = T.hacer_prestado_mut(v);
        let rm = G.tipo_resultado(con_mut);
        salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
        salida.anadir($"static {rm} ss_mapa_obtener_mut_{m}({nombre}* p, SafeView clave)");
        salida.anadir(nuevo("{"));
        salida.anadir(nuevo("    if (p->capacidad == 0)"));
        salida.anadir($"        return ({rm}){{ .motivo = \"la clave no esta en el mapa\" }};");
        salida.anadir($"    size_t i = ss_mapa_sitio_{m}(p, clave);");
        salida.anadir(nuevo("    if (p->claves[i].data == NULL)"));
        salida.anadir($"        return ({rm}){{ .motivo = \"la clave no esta en el mapa\" }};");
        salida.anadir($"    return ({rm}){{ .motivo = NULL, .valor = &p->valores[i] }};");
        salida.anadir(nuevo("}"));
        salida.anadir(vacio());
    }

    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static bool ss_mapa_quitar_{m}({nombre}* p, SafeView clave)");
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    if (p->capacidad == 0) return false;"));
    salida.anadir(nuevo("    size_t mascara = p->capacidad - 1;"));
    salida.anadir($"    size_t i = ss_mapa_sitio_{m}(p, clave);");
    salida.anadir(nuevo("    if (p->claves[i].data == NULL) return false;"));
    salida.anadir(vacio());
    salida.anadir(nuevo("    ss_free(&p->claves[i]);"));
    salida.anadir(nuevo("    p->claves[i] = ss_new();"));
    if posee {
        lineas_liberacion(global, "p->valores[i]", v, 1, cta, salida);
        salida.anadir($"    memset(&p->valores[i], 0, sizeof({tc_v}));");
    }
    salida.anadir(nuevo("    p->largo--;"));
    salida.anadir(vacio());
    salida.anadir(nuevo("    /* Sin lapidas: se cierra el hueco arrastrando hacia atras"));
    salida.anadir(nuevo("       las entradas del mismo grupo que quedarian inalcanzables."));
    salida.anadir(nuevo("       Es lo que permite que la busqueda pueda parar en la"));
    salida.anadir(nuevo("       primera celda libre. */"));
    salida.anadir(nuevo("    size_t j = i;"));
    salida.anadir(nuevo("    for (;;)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        j = (j + 1) & mascara;"));
    salida.anadir(nuevo("        if (p->claves[j].data == NULL) break;"));
    salida.anadir(nuevo("        size_t k = (size_t) sv_hash(ss_view(&p->claves[j])) & mascara;"));
    salida.anadir(nuevo("        bool mover = (i <= j) ? (k <= i || k > j)"));
    salida.anadir(nuevo("                              : (k <= i && k > j);"));
    salida.anadir(nuevo("        if (mover)"));
    salida.anadir(nuevo("        {"));
    salida.anadir(nuevo("            p->claves[i] = p->claves[j];"));
    salida.anadir(nuevo("            p->valores[i] = p->valores[j];"));
    salida.anadir(nuevo("            p->claves[j] = ss_new();"));
    salida.anadir(nuevo("            i = j;"));
    salida.anadir(nuevo("        }"));
    salida.anadir(nuevo("    }"));
    salida.anadir(nuevo("    return true;"));
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());

    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static void ss_mapa_libre_{m}({nombre}* p)");
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    for (size_t i = 0; i < p->capacidad; i++)"));
    salida.anadir(nuevo("        if (p->claves[i].data != NULL)"));
    salida.anadir(nuevo("        {"));
    salida.anadir(nuevo("            ss_free(&p->claves[i]);"));
    if posee {
        lineas_liberacion(global, "p->valores[i]", v, 3, cta, salida);
    }
    salida.anadir(nuevo("        }"));
    salida.anadir(nuevo("    free(p->claves); free(p->valores);"));
    salida.anadir(nuevo("    p->claves = NULL; p->valores = NULL;"));
    salida.anadir(nuevo("    p->largo = 0; p->capacidad = 0;"));
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());
}

fn funcion_bloque(t: view, global: &I.Contexto, cta: mut F.Cuenta,
    salida: mut lista<str>) {
    let elem = T.elemento(t);
    let te = G.tipo_c(elem);
    let nombre = G.tipo_c(t);
    let m = G.mangle(t);
    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static {nombre} ss_lang_bloque_nuevo_{m}(size_t n,");
    salida.anadir(nuevo("        const char* archivo, int linea)"));
    salida.anadir(nuevo("{"));
    salida.anadir($"    {nombre} b = {{ NULL, 0 }};");
    salida.anadir(nuevo("    if (n == 0) return b;"));
    salida.anadir($"    if (n > SIZE_MAX / sizeof({te}))");
    salida.anadir(nuevo("        ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir($"    b.e = ({te}*) calloc(n, sizeof({te}));");
    salida.anadir(nuevo("    if (b.e == NULL) ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir(nuevo("    b.n = n;"));
    salida.anadir(nuevo("    return b;"));
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());
    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static void ss_lang_bloque_cambiar_{m}({nombre}* p, size_t n,");
    salida.anadir(nuevo("        const char* archivo, int linea)"));
    salida.anadir(nuevo("{"));
    salida.anadir(nuevo("    if (n == p->n) return;"));
    if I.posee_con_formas(global, elem) {
        salida.anadir(nuevo("    if (n < p->n)"));
        salida.anadir(nuevo("        for (size_t i = n; i < p->n; i++)"));
        salida.anadir(nuevo("        {"));
        lineas_liberacion(global, "p->e[i]", elem, 3, cta, salida);
        salida.anadir(nuevo("        }"));
    }
    salida.anadir(nuevo("    if (n == 0)"));
    salida.anadir(nuevo("    {"));
    salida.anadir(nuevo("        free(p->e); p->e = NULL; p->n = 0; return;"));
    salida.anadir(nuevo("    }"));
    salida.anadir($"    if (n > SIZE_MAX / sizeof({te}))");
    salida.anadir(nuevo("        ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir($"    void* memoria = realloc(p->e, n * sizeof({te}));");
    salida.anadir(nuevo("    if (memoria == NULL) ss_lang_sin_memoria_(archivo, linea);"));
    salida.anadir($"    p->e = ({te}*) memoria;");
    salida.anadir(nuevo("    /* Lo nuevo nace a ceros, que en Tcode es un valor valido. */"));
    salida.anadir(nuevo("    if (n > p->n)"));
    salida.anadir($"        memset(p->e + p->n, 0, (n - p->n) * sizeof({te}));");
    salida.anadir(nuevo("    p->n = n;"));
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());
}

// El tipo de mapa al que se refiere un nombre de C: `ss_mapa_poner_mapa_x`
// y `ss_mapa_x` hablan del mismo.
fn tipo_de_nombre_mapa(u: view) -> str {
    let resto = rebanar(u, 8, u.largo());
    if empieza_con(resto, "obtener_mut_") { return $"ss_{rebanar(resto, 12, largo(resto))}"; }
    if empieza_con(resto, "obtener_") { return $"ss_{rebanar(resto, 8, largo(resto))}"; }
    if empieza_con(resto, "sitio_") || empieza_con(resto, "poner_")
    || empieza_con(resto, "tiene_") || empieza_con(resto, "libre_") {
        return $"ss_{rebanar(resto, 6, largo(resto))}";
    }
    if empieza_con(resto, "crecer_") || empieza_con(resto, "claves_")
    || empieza_con(resto, "quitar_") {
        return $"ss_{rebanar(resto, 7, largo(resto))}";
    }
    return nuevo(u);
}

// Los nombres de C que empiezan por `prefijo`: `ss_lista_str` en una linea.
fn apuntar_nombres(t: view, prefijo: view, salida: mut mapa<str, usize>) {
    var i = buscar_desde(t, prefijo, 0);
    while i < t.largo() {
        var j = i + prefijo.largo();
        while j < t.largo() && I.es_de_nombre(byte(t, j)) { j = j + 1; }
        // Solo al principio de un nombre: `posicion__` esta dentro de
        // `ultima_posicion__usize`, y esa es otra copia.
        if i == 0 || !I.es_de_nombre(byte(t, i - 1)) {
            poner(salida, rebanar(t, i, j), 1);
        }
        i = buscar_desde(t, prefijo, j);
    }
}

// ------------------------------------------------------------------
// El archivo
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Copiadores
// ------------------------------------------------------------------
//
// `copiar` de algo con memoria detras llama a un copiador generado, uno por
// tipo, espejo de su liberador. Se descubren al escribir las funciones y
// salen despues de la aritmetica, de dentro hacia fuera.

// `a\tb` -> [a, b]; la cadena vacia no lleva nada.
fn partir_tab(t: view) -> lista<str> {
    var salida: lista<str> = [];
    if t.largo() == 0 { return salida; }
    var desde = 0;
    var i = 0;
    while i <= t.largo() {
        if i == t.largo() || byte(t, i) == 9 {
            salida.anadir(nuevo(rebanar(t, desde, i)));
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

fn hondura_tipo(t: view) -> usize {
    var n = 0;
    var i = 0;
    while i < t.largo() {
        let b = byte(t, i);
        if b == 60 || b == 91 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

// Apunta el copiador de `t` y el de lo que lleve dentro, en ese orden.
fn necesita_copiador(t: view, global: &I.Contexto, st_indice: &mapa<str, usize>,
    st_tipos: &lista<lista<str>>, vistos: mut mapa<str, usize>,
    salida: mut lista<str>) {
    if t == "str" || !I.posee_con_formas(global, t) || tiene(vistos, t) {
        return;
    }
    poner(vistos, t, 1);
    salida.anadir(nuevo(t));
    if T.es_bloque(t) {
        let dentro_b = T.elemento(t);
        necesita_copiador(dentro_b, global, st_indice, st_tipos, vistos, salida);
        return;
    }
    if T.es_lista(t) {
        let dentro = T.elemento(t);
        necesita_copiador(dentro, global, st_indice, st_tipos, vistos, salida);
        return;
    }
    if T.es_mapa(t) {
        let partes = T.partes(t);
        if partes.largo() == 2 {
            necesita_copiador(vista(partes[1]), global, st_indice, st_tipos,
                vistos, salida);
        }
        return;
    }
    if T.es_arreglo(t) {
        let pa = T.partes_de_arreglo(t);
        if pa.largo() == 2 {
            necesita_copiador(pa[0], global, st_indice, st_tipos, vistos, salida);
        }
        return;
    }
    if tiene(st_indice, t) {
        let k = obtener(st_indice, t) sino 0;
        for c en st_tipos[k] {
            necesita_copiador(c, global, st_indice, st_tipos, vistos, salida);
        }
    }
    if tiene(global.variantes, t) {
        // Lo que llevan sus formas, en orden.
        for v en I.lista_de(global.variantes, t) sino [] {
            for x en I.lista_de(global.formas, $"{t}.{v}") sino [] {
                necesita_copiador(x, global, st_indice, st_tipos, vistos, salida);
            }
        }
    }
}

fn copia_de(donde: view, t: view, global: &I.Contexto) -> str {
    if !I.posee_con_formas(global, t) { return nuevo(donde); }
    if t == "str" { return $"ss_clone(&{donde})"; }
    let m = G.mangle(t);
    return $"ss_copia_{m}(&{donde})";
}

// Falso si el tipo es de los que este hito todavia no copia.
fn cuerpo_copiador(t: view, global: &I.Contexto, st_indice: &mapa<str, usize>,
    st_campos: &lista<lista<str>>, st_tipos: &lista<lista<str>>,
    en_indice: &mapa<str, usize>, en_variantes: &lista<lista<str>>,
    en_lleva: &lista<lista<str>>, salida: mut lista<str>) -> bool {
    let tc = G.tipo_c(t);
    let m = G.mangle(t);
    // Un enum se copia entero y luego se duplica lo que lleve con dueno la
    // forma que tenga.
    if tiene(en_indice, t) {
        let ke = obtener(en_indice, t) sino 0;
        salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
        salida.anadir($"static {tc} ss_copia_{m}(const {tc}* p)");
        salida.anadir(nuevo("{"));
        salida.anadir($"    {tc} r = *p;");
        var hay: lista<usize> = [];
        var iv = 0;
        while iv < en_variantes[ke].largo() {
            let tipos_v = partir_tab(en_lleva[ke][iv]);
            var alguna = false;
            for tt en tipos_v {
                if I.posee_con_formas(global, tt) { alguna = true; }
            }
            if alguna { hay.anadir(iv); }
            iv = iv + 1;
        }
        if hay.largo() > 0 {
            salida.anadir(nuevo("    switch (p->etiqueta)"));
            salida.anadir(nuevo("    {"));
            for cual en hay {
                let vn = copiar(en_variantes[ke][cual]);
                let etq = G.etiqueta(t, vn);
                salida.anadir($"    case {etq}:");
                let tipos_v = partir_tab(en_lleva[ke][cual]);
                var q = 0;
                while q < tipos_v.largo() {
                    if I.posee_con_formas(global, tipos_v[q]) {
                        let origen = $"p->dato.v_{vn}._{q}";
                        let cp = copia_de(vista(origen), vista(tipos_v[q]), global);
                        salida.anadir($"        r.dato.v_{vn}._{q} = {cp};");
                    }
                    q = q + 1;
                }
                salida.anadir(nuevo("        break;"));
            }
            salida.anadir(nuevo("    default: break;"));
            salida.anadir(nuevo("    }"));
        }
        salida.anadir(nuevo("    return r;"));
        salida.anadir(nuevo("}"));
        salida.anadir(vacio());
        return true;
    }
    if T.es_bloque(t) {
        let elem_b = T.elemento(t);
        let te_b = G.tipo_c(elem_b);
        let cp_b = copia_de("p->e[i]", vista(elem_b), global);
        salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
        salida.anadir($"static {tc} ss_copia_{m}(const {tc}* p)");
        salida.anadir(nuevo("{"));
        salida.anadir($"    {tc} r = {{ NULL, 0 }};");
        salida.anadir(nuevo("    if (p->n == 0) return r;"));
        salida.anadir($"    r.e = ({te_b}*) calloc(p->n, sizeof({te_b}));");
        salida.anadir(nuevo("    if (r.e == NULL) ss_lang_sin_memoria_(__FILE__, __LINE__);"));
        salida.anadir(nuevo("    r.n = p->n;"));
        salida.anadir(nuevo("    for (size_t i = 0; i < p->n; i++)"));
        salida.anadir($"        r.e[i] = {cp_b};");
        salida.anadir(nuevo("    return r;"));
        salida.anadir(nuevo("}"));
        salida.anadir(vacio());
        return true;
    }
    if T.es_lista(t) {
        let elem = T.elemento(t);
        let te = G.tipo_c(elem);
        let cp = copia_de("p->e[i]", vista(elem), global);
        salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
        salida.anadir($"static {tc} ss_copia_{m}(const {tc}* p)");
        salida.anadir(nuevo("{"));
        salida.anadir($"    {tc} r = {{ NULL, 0, 0 }};");
        salida.anadir(nuevo("    if (p->length == 0) return r;"));
        salida.anadir($"    r.e = ({te}*) calloc(p->length, sizeof({te}));");
        salida.anadir(nuevo("    if (r.e == NULL) ss_lang_sin_memoria_(__FILE__, __LINE__);"));
        salida.anadir(nuevo("    r.capacity = p->length;"));
        salida.anadir(nuevo("    for (size_t i = 0; i < p->length; i++)"));
        salida.anadir($"        r.e[i] = {cp};");
        salida.anadir(nuevo("    r.length = p->length;"));
        salida.anadir(nuevo("    return r;"));
        salida.anadir(nuevo("}"));
        salida.anadir(vacio());
        return true;
    }
    if T.es_mapa(t) {
        let partes = T.partes(t);
        if partes.largo() != 2 { return false; }
        let tck = G.tipo_c(partes[0]);
        let tcv = G.tipo_c(partes[1]);
        let cp = copia_de("p->valores[i]", vista(partes[1]), global);
        salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
        salida.anadir($"static {tc} ss_copia_{m}(const {tc}* p)");
        salida.anadir(nuevo("{"));
        salida.anadir($"    {tc} r = {{ NULL, NULL, 0, 0 }};");
        salida.anadir(nuevo("    if (p->capacidad == 0) return r;"));
        salida.anadir($"    r.claves = ({tck}*) calloc(p->capacidad, sizeof({tck}));");
        salida.anadir($"    r.valores = ({tcv}*) calloc(p->capacidad, sizeof({tcv}));");
        salida.anadir(nuevo("    if (r.claves == NULL || r.valores == NULL)"));
        salida.anadir(nuevo("        ss_lang_sin_memoria_(__FILE__, __LINE__);"));
        salida.anadir(nuevo("    r.capacidad = p->capacidad;"));
        salida.anadir(nuevo("    r.largo = p->largo;"));
        salida.anadir(nuevo("    for (size_t i = 0; i < p->capacidad; i++)"));
        salida.anadir(nuevo("    {"));
        salida.anadir(nuevo("        if (p->claves[i].data == NULL) continue;"));
        salida.anadir(nuevo("        r.claves[i] = ss_clone(&p->claves[i]);"));
        salida.anadir($"        r.valores[i] = {cp};");
        salida.anadir(nuevo("    }"));
        salida.anadir(nuevo("    return r;"));
        salida.anadir(nuevo("}"));
        salida.anadir(vacio());
        return true;
    }
    if T.es_arreglo(t) {
        let pa = T.partes_de_arreglo(t);
        if pa.largo() != 2 { return false; }
        let cp = copia_de("p->e[i]", vista(pa[0]), global);
        salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
        salida.anadir($"static {tc} ss_copia_{m}(const {tc}* p)");
        salida.anadir(nuevo("{"));
        salida.anadir($"    {tc} r;");
        salida.anadir($"    for (size_t i = 0; i < {pa[1]}; i++)");
        salida.anadir($"        r.e[i] = {cp};");
        salida.anadir(nuevo("    return r;"));
        salida.anadir(nuevo("}"));
        salida.anadir(vacio());
        return true;
    }
    if !tiene(st_indice, t) { return false; }
    let k = obtener(st_indice, t) sino 0;
    salida.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
    salida.anadir($"static {tc} ss_copia_{m}(const {tc}* p)");
    salida.anadir(nuevo("{"));
    salida.anadir($"    {tc} r;");
    var j = 0;
    while j < st_campos[k].largo() {
        let donde = $"p->{st_campos[k][j]}";
        let cp = copia_de(vista(donde), vista(st_tipos[k][j]), global);
        salida.anadir($"    r.{st_campos[k][j]} = {cp};");
        j = j + 1;
    }
    salida.anadir(nuevo("    return r;"));
    salida.anadir(nuevo("}"));
    salida.anadir(vacio());
    return true;
}

// ------------------------------------------------------------------
// Structs genericos
// ------------------------------------------------------------------
//
// Cada `Par<str, usize>` escrito es una copia, `Par__str_usize`, que se
// escribe como un struct mas. El tipado en Tcode trabaja con el tipo escrito;
// aqui se crean las copias en el orden en que las crea el comprobador de
// Python: primero los campos de los structs, despues los tipos escritos en
// cada funcion, y los de cada generica al instanciarla.

// Los structs desde `desde`, en el orden de `orden`; los que no estan en el,
// detras y como estaban.
fn ordenar_como_comprobador(desde: usize, orden: &lista<str>,
    st_nombres: mut lista<str>, st_indice: mut mapa<str, usize>,
    st_campos: mut lista<lista<str>>, st_tipos: mut lista<lista<str>>) {
    var puesto: mapa<str, usize> = [];
    var k = 0;
    while k < orden.largo() {
        if !tiene(puesto, orden[k]) { poner(puesto, vista(orden[k]), k); }
        k = k + 1;
    }
    // Una insercion estable: son pocos.
    var cual: lista<usize> = [];
    var i = desde;
    while i < st_nombres.largo() {
        cual.anadir(i);
        i = i + 1;
    }
    let fuera = orden.largo();
    var a = 1;
    while a < cual.largo() {
        var b = a;
        while b > 0 {
            let pb = obtener(puesto, st_nombres[cual[b]]) sino fuera;
            let pa = obtener(puesto, st_nombres[cual[b - 1]]) sino fuera;
            if pa <= pb { break; }
            let t = cual[b];
            cual[b] = cual[b - 1];
            cual[b - 1] = t;
            b = b - 1;
        }
        a = a + 1;
    }
    var nombres: lista<str> = [];
    var campos: lista<lista<str>> = [];
    var tipos: lista<lista<str>> = [];
    var j = 0;
    while j < desde {
        nombres.anadir(copiar(st_nombres[j]));
        campos.anadir(copiar(st_campos[j]));
        tipos.anadir(copiar(st_tipos[j]));
        j = j + 1;
    }
    for c en cual {
        poner(st_indice, vista(st_nombres[c]), nombres.largo());
        nombres.anadir(copiar(st_nombres[c]));
        campos.anadir(copiar(st_campos[c]));
        tipos.anadir(copiar(st_tipos[c]));
    }
    st_nombres = nombres;
    st_campos = campos;
    st_tipos = tipos;
}

// Como `resolver_tipo` del comprobador: el tipo con cada aplicacion cambiada
// por su copia, creando la copia la primera vez. Una copia se apunta despues
// de resolver sus campos, asi que las que pide un campo van antes.
fn resolver_reg(t: view, plantillas_st: &mapa<str, usize>,
    p_params: &lista<lista<str>>, p_campos: &lista<lista<str>>,
    p_tipos: &lista<lista<str>>, en_curso: mut mapa<str, usize>,
    st_nombres: mut lista<str>, st_indice: mut mapa<str, usize>,
    st_campos: mut lista<lista<str>>, st_tipos: mut lista<lista<str>>,
    global: mut I.Contexto) -> str {
    if !contiene(t, "<") && !contiene(t, "[") { return nuevo(t); }
    // Lo que lleva tipos dentro se resuelve parte a parte y se vuelve a
    // montar, en orden: la clave de un mapa antes que su valor.
    if T.es_referencia(t) || T.es_lista(t) || T.es_bloque(t) || T.es_mapa(t)
    || T.es_arreglo(t) {
        var nuevas: lista<str> = [];
        for parte en T.partes(t) {
            let resuelta = resolver_reg(parte, plantillas_st, p_params, p_campos, p_tipos,
                en_curso, st_nombres, st_indice, st_campos, st_tipos, global);
            nuevas.anadir(resuelta);
        }
        return T.con_partes(t, nuevas);
    }
    if !I.es_aplicacion(t) { return nuevo(t); }
    let base = I.base_de_aplicacion(t);
    if !tiene(plantillas_st, base) { return nuevo(t); }
    let kp = obtener(plantillas_st, base) sino 0;
    let dados = T.partes(t);
    if dados.largo() != p_params[kp].largo() { return nuevo(t); }
    var ligaduras: mapa<str, str> = [];
    var resueltos: lista<str> = [];
    var i = 0;
    while i < dados.largo() {
        let d = resolver_reg(dados[i], plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
        poner(ligaduras, vista(p_params[kp][i]), copiar(d));
        resueltos.anadir(d);
        i = i + 1;
    }
    let nombre = T.nombre_de_copia(base, resueltos);
    if tiene(st_indice, nombre) || tiene(en_curso, nombre) { return nombre; }
    poner(en_curso, vista(nombre), 1);
    var tipos_c: lista<str> = [];
    let crudos = copiar(p_tipos[kp]);
    for x en crudos {
        let puesto = I.sustituir(x, ligaduras);
        anadir(tipos_c, resolver_reg(vista(puesto), plantillas_st, p_params, p_campos, p_tipos, en_curso,
                st_nombres, st_indice, st_campos, st_tipos, global));
    }
    poner(st_indice, vista(nombre), st_nombres.largo());
    st_nombres.anadir(copiar(nombre));
    st_campos.anadir(copiar(p_campos[kp]));
    poner(global.campos, vista(nombre), copiar(tipos_c));
    poner(global.nombres, vista(nombre), copiar(p_campos[kp]));
    st_tipos.anadir(tipos_c);
    return nombre;
}

// Los tipos escritos en una funcion, en el orden en que los resuelve el
// comprobador: parametros, retorno y cuerpo.
fn resolver_en_nodo(n: &P.Nodo, plantillas_st: &mapa<str, usize>,
    p_params: &lista<lista<str>>, p_campos: &lista<lista<str>>,
    p_tipos: &lista<lista<str>>, en_curso: mut mapa<str, usize>,
    st_nombres: mut lista<str>, st_indice: mut mapa<str, usize>,
    st_campos: mut lista<lista<str>>, st_tipos: mut lista<lista<str>>,
    global: mut I.Contexto) {
    let clase = n.clase;
    if clase == Clase.Param {
        let tp = F.tipo_pelado(n.texto);
        let t = I.sin_alias_tipo(tp);
        let _r = resolver_reg(vista(t), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
    }
    if clase == Clase.RetornoTipo || clase == Clase.LiteralStruct {
        let t = I.sin_alias_tipo(n.texto);
        let _r = resolver_reg(vista(t), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
    }
    if clase == Clase.Declaracion {
        let escrito = G.tipo_escrito(n.texto);
        if escrito.largo() > 0 {
            let t = I.sin_alias_tipo(escrito);
            let _r = resolver_reg(vista(t), plantillas_st, p_params, p_campos, p_tipos, en_curso,
                st_nombres, st_indice, st_campos, st_tipos, global);
        }
    }
    for h en n.hijos { resolver_en_nodo(h, plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global); }
}

// Una copia de generica resuelve primero su retorno, luego sus parametros y
// luego el cuerpo.
fn resolver_instancia(d: &P.Nodo, plantillas_st: &mapa<str, usize>,
    p_params: &lista<lista<str>>, p_campos: &lista<lista<str>>,
    p_tipos: &lista<lista<str>>, en_curso: mut mapa<str, usize>,
    st_nombres: mut lista<str>, st_indice: mut mapa<str, usize>,
    st_campos: mut lista<lista<str>>, st_tipos: mut lista<lista<str>>,
    global: mut I.Contexto) {
    for h en d.hijos {
        if h.clase == Clase.RetornoTipo { resolver_en_nodo(h, plantillas_st, p_params, p_campos, p_tipos, en_curso,
                st_nombres, st_indice, st_campos, st_tipos, global); }
    }
    for h en d.hijos {
        if h.clase == Clase.Param { resolver_en_nodo(h, plantillas_st, p_params, p_campos, p_tipos, en_curso,
                st_nombres, st_indice, st_campos, st_tipos, global); }
    }
    for h en d.hijos {
        if h.clase == Clase.Bloque { resolver_en_nodo(h, plantillas_st, p_params, p_campos, p_tipos, en_curso,
                st_nombres, st_indice, st_campos, st_tipos, global); }
    }
}

// ------------------------------------------------------------------
// Externo
// ------------------------------------------------------------------

// La firma en C de una funcion que escribio otro: un `str` entra como
// `const char*`, y `cadena_c` sale como tal.
fn prototipo_externo(nombre: view, tipos_p: &lista<str>, nombres_p: &lista<str>,
    retorno: view) -> str {
    var tc = G.tipo_c(retorno);
    if retorno == "cadena_c" { tc = nuevo("const char*"); }
    if tipos_p.largo() == 0 { return $"{tc} {nombre}(void)"; }
    var partes = vacio();
    var i = 0;
    while i < tipos_p.largo() {
        var t = G.tipo_c(tipos_p[i]);
        if tipos_p[i] == "str" { t = nuevo("const char*"); }
        if i > 0 { partes.empujar(", "); }
        let pieza = $"{t} {nombres_p[i]}";
        partes.empujar(pieza);
        i = i + 1;
    }
    return $"{tc} {nombre}({partes})";
}

// Cada linea de un texto, sin el salto final.
fn anadir_lineas(texto_c: view, salida: mut lista<str>) {
    var fin = texto_c.largo();
    if fin > 0 && byte(texto_c, fin - 1) == 10 { fin = fin - 1; }
    var desde = 0;
    var i = 0;
    while i <= fin {
        if i == fin || byte(texto_c, i) == 10 {
            salida.anadir(nuevo(rebanar(texto_c, desde, i)));
            desde = i + 1;
        }
        i = i + 1;
    }
}

// ------------------------------------------------------------------
// Clausuras
// ------------------------------------------------------------------
//
// El original convierte cada clausura en un struct con lo capturado y una
// funcion que lo recibe, y las numera segun las va comprobando. Aqui se hace
// antes de nada, recorriendo las funciones en el mismo orden: en el arbol
// queda solo `Cierre_N` con sus capturas, y su cuerpo pasa a `ss_cierre_N`.

// Cada clausura de un cuerpo, en preorden y sin entrar en otras, pasa a ser
// el `Cierre_N` que le dio el comprobador: queda su nombre y sus capturas,
// y su cuerpo es la funcion `ss_cierre_N`.
fn numerar_cierres(n: mut P.Nodo, dueno: view, numeracion: &mapa<str, usize>,
    cuenta: mut usize) {
    var i = 0;
    while i < n.hijos.largo() {
        if n.hijos[i].clase == Clase.Cierre {
            let clave = $"{dueno}#{cuenta}";
            cuenta = cuenta + 1;
            if tiene(numeracion, clave) {
                let numero = obtener(numeracion, clave) sino 0;
                var queda = P.rama(Clase.Cierre, n.hijos[i].linea);
                queda.texto = $"Cierre_{numero}";
                for h en n.hijos[i].hijos {
                    if h.clase == Clase.Captura { queda.hijos.anadir(copiar(h)); }
                }
                n.hijos[i] = queda;
            }
        } else {
            numerar_cierres(n.hijos[i], dueno, numeracion, cuenta);
        }
        i = i + 1;
    }
}

fn tiene_cierre(n: &P.Nodo) -> bool {
    if n.clase == Clase.Cierre { return true; }
    for h en n.hijos {
        if tiene_cierre(h) { return true; }
    }
    return false;
}

// Lo que lleva el struct de una clausura, en orden, sacado de su pedido
// `\tss_cierre_N\tnombre=tipo...`. Sin capturas lleva un byte: un struct
// vacio no es C valido.
fn campos_de_cierre(p: view, nombres: mut lista<str>, tipos: mut lista<str>) {
    var k = 2;
    var pieza = campo_pedido(p, k);
    while pieza.largo() > 0 {
        let corte = buscar_desde(pieza, "=", 0);
        nombres.anadir(nuevo(rebanar(pieza, 0, corte)));
        tipos.anadir(nuevo(rebanar(pieza, corte + 1, pieza.largo())));
        k = k + 1;
        pieza = campo_pedido(p, k);
    }
    if nombres.largo() == 0 {
        nombres.anadir(nuevo("ss_vacio"));
        tipos.anadir(nuevo("u8"));
    }
}

// `ss_cierre_3` -> `Cierre_3`.
fn struct_de_cierre(en_c: view) -> str {
    return $"Cierre_{rebanar(en_c, 10, largo(en_c))}";
}

// Los tipos funcion que puede nombrar el C: las firmas del programa y los
// tipos de los parametros y retornos de cada funcion escrita, con los que
// lleven dentro.
fn apuntar_tipo_funcion(t: view, salida: mut lista<str>) {
    if !T.es_funcion(t) || esta_en(salida, t) { return; }
    salida.anadir(nuevo(t));
    for x en T.partes_de_funcion(t) {
        let dentro = T.apuntado_si(x);
        apuntar_tipo_funcion(dentro, salida);
    }
}

fn tipos_funcion_de(d: &P.Nodo, salida: mut lista<str>) {
    for h en d.hijos {
        if h.clase == Clase.Param {
            let tp = F.tipo_pelado(h.texto);
            apuntar_tipo_funcion(tp, salida);
        }
        if h.clase == Clase.RetornoTipo {
            apuntar_tipo_funcion(h.texto, salida);
        }
    }
}

// `nombre` aparece en `l` como palabra entera: `ss_fn_x_a_y` no es
// `ss_fn_x_a_y_z`.
fn contiene_nombre(l: view, nombre: view) -> bool {
    var i = buscar_desde(l, nombre, 0);
    while i < l.largo() {
        let fin = i + nombre.largo();
        let antes_ok = i == 0 || !es_de_nombre_c(byte(l, i - 1));
        let despues_ok = fin >= l.largo() || !es_de_nombre_c(byte(l, fin));
        if antes_ok && despues_ok { return true; }
        i = buscar_desde(l, nombre, i + 1);
    }
    return false;
}

fn es_de_nombre_c(c: usize) -> bool {
    return (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57)
    || c == 95;
}

// ------------------------------------------------------------------
// Genericas
// ------------------------------------------------------------------
//
// Una generica no se escribe: se escriben las copias que pide cada llamada,
// con los tipos puestos, detras de todo lo demas. El original crea cada copia
// al comprobar la llamada y comprueba su cuerpo antes de apuntarla, asi que
// las que pide una copia salen antes que ella. Aqui se descubren igual:
// escribiendo cada funcion una vez en borrador y siguiendo lo que piden sus
// llamadas.

// Un campo de un pedido `plantilla\tnombre_c\tT=tipo...`.
fn campo_pedido(p: view, cual: usize) -> str {
    var k = 0;
    var desde = 0;
    var i = 0;
    while i <= p.largo() {
        if i == p.largo() || byte(p, i) == 9 {
            if k == cual { return nuevo(rebanar(p, desde, i)); }
            k = k + 1;
            desde = i + 1;
        }
        i = i + 1;
    }
    return vacio();
}

fn ligaduras_de(p: view) -> mapa<str, str> {
    var salida: mapa<str, str> = [];
    var k = 2;
    var pieza = campo_pedido(p, k);
    while pieza.largo() > 0 {
        let corte = buscar_desde(pieza, "=", 0);
        let tp = nuevo(rebanar(pieza, 0, corte));
        let puesto = nuevo(rebanar(pieza, corte + 1, pieza.largo()));
        poner(salida, vista(tp), puesto);
        k = k + 1;
        pieza = campo_pedido(p, k);
    }
    return salida;
}

// Los nodos cuyo texto lleva tipos escritos.
fn lleva_tipo(clase: Clase) -> bool {
    if clase == Clase.Param || clase == Clase.RetornoTipo { return true; }
    if clase == Clase.Declaracion || clase == Clase.Conversion { return true; }
    return clase == Clase.LiteralStruct || clase == Clase.Cierre;
}

fn copiar_sustituido(n: &P.Nodo, lig: &mapa<str, str>) -> P.Nodo {
    var r = P.rama(n.clase, n.linea);
    // El mismo numero: es por el que el comprobador dejo anotado su tipo.
    r.id = n.id;
    if lleva_tipo(n.clase) {
        r.texto = I.sustituir(n.texto, lig);
    } else {
        r.texto = copiar(n.texto);
    }
    for h en n.hijos {
        if h.clase == Clase.TipoParam { continue; }
        r.hijos.anadir(copiar_sustituido(h, lig));
    }
    return r;
}

// La copia de una generica con los tipos de un pedido.
fn nodo_instancia(p: view, arboles: &lista<P.Nodo>,
    plantillas: &mapa<str, usize>, numeracion: &mapa<str, usize>) -> P.Nodo {
    let plantilla = campo_pedido(p, 0);
    let en_c = campo_pedido(p, 1);
    let lig = ligaduras_de(p);
    let im = obtener(plantillas, plantilla) sino 0;
    var r = P.rama(Clase.Vacio, 0);
    for d en arboles[im].hijos {
        if d.clase == Clase.Fn && igual(d.texto, plantilla) {
            r = copiar_sustituido(d, lig);
            r.texto = copiar(en_c);
            break;
        }
    }
    // Las clausuras de esta copia son suyas.
    let dueno = dueno_de_pedido(p);
    var cuenta: usize = 0;
    numerar_cierres(r, dueno, numeracion, cuenta);
    return r;
}

// Como llama el comprobador a una copia: `plantilla|T1|T2`. Es de quien son
// sus clausuras y la clave de los tipos que dejo anotados en ella.
fn dueno_de_pedido(p: view) -> str {
    var dueno = campo_pedido(p, 0);
    var k = 2;
    var pieza = campo_pedido(p, k);
    while pieza.largo() > 0 {
        let corte = buscar_desde(pieza, "=", 0);
        dueno.empujar("|");
        dueno.empujar(rebanar(pieza, corte + 1, pieza.largo()));
        k = k + 1;
        pieza = campo_pedido(p, k);
    }
    return dueno;
}

// El orden de las copias por su puesto, sin mover las que empatan:
// insercion, que son pocas.
fn orden_por_puesto(puestos: &lista<usize>) -> lista<usize> {
    var orden: lista<usize> = [];
    var i = 0;
    while i < puestos.largo() {
        orden.anadir(i);
        var j = i;
        while j > 0 && puestos[orden[j - 1]] > puestos[orden[j]] {
            let antes = orden[j - 1];
            orden[j - 1] = orden[j];
            orden[j] = antes;
            j = j - 1;
        }
        i = i + 1;
    }
    return orden;
}

// Como llama el comprobador a una funcion del programa.
fn dueno_de_funcion(d: &P.Nodo, tipos: &I.Contexto) -> str {
    if tiene(tipos.renombradas, d.texto) {
        return nuevo(obtener(tipos.renombradas, d.texto) sino "");
    }
    return copiar(d.texto);
}

// Las funciones de las clausuras, el modulo de cada una y el indice de cada
// nombre en C.
struct Cierres {
    fns: lista<P.Nodo>,
    modulo: lista<usize>,
    indice: mapa<str, usize>,
    // `dueno#k` -> N, como lo decidio el comprobador.
    numeracion: mapa<str, usize>,
    // Los campos que el comprobador vio sacar de su struct.
    sacados: mapa<str, usize>,
}

// Escribe en borrador cada copia pedida que no se haya visto, primero las
// que pide ella, y la apunta en `orden` al terminar.
fn descubrir(pedidos: &lista<str>, arboles: &lista<P.Nodo>,
    contextos: mut lista<I.Contexto>, modulos: &lista<str>,
    plantillas: &mapa<str, usize>, vistos: mut mapa<str, usize>,
    orden: mut lista<str>, creados: mut lista<str>, cierres: &Cierres,
    global: mut I.Contexto) -> bool {
    for p en pedidos {
        let en_c = campo_pedido(p, 1);
        if tiene(vistos, en_c) { continue; }
        poner(vistos, vista(en_c), 1);
        creados.anadir(copiar(p));
        let plantilla = campo_pedido(p, 0);
        if plantilla.largo() == 0 {
            // Una clausura: su struct existe desde que se crea, y su funcion
            // se apunta antes de comprobar su cuerpo, al reves que una copia.
            if !tiene(cierres.indice, en_c) {
                imprimir_error($"tcodec: `{en_c}` no es una clausura conocida\n");
                return false;
            }
            let k = obtener(cierres.indice, en_c) sino 0;
            var cn: lista<str> = [];
            var ct: lista<str> = [];
            campos_de_cierre(p, cn, ct);
            let st = struct_de_cierre(en_c);
            poner(global.campos, vista(st), copiar(ct));
            poner(global.nombres, vista(st), copiar(cn));
            var kc = 0;
            while kc < contextos.largo() {
                poner(contextos[kc].campos, vista(st), copiar(ct));
                poner(contextos[kc].nombres, vista(st), copiar(cn));
                kc = kc + 1;
            }
            orden.anadir(copiar(p));
            let de = cierres.modulo[k];
            var borrador_c = F.cuenta_nueva();
            borrador_c.sacados = copiar(cierres.sacados);
            borrador_c.dueno = copiar(cierres.fns[k].texto);
            let lineas_c = F.generar_funcion(cierres.fns[k], contextos[de],
                vista(modulos[de]), borrador_c);
            if lineas_c.largo() == 0 {
                imprimir_error($"tcodec: no se escribir la clausura `{en_c}`\n");
                return false;
            }
            if !descubrir(borrador_c.instancias, arboles, contextos, modulos,
                plantillas, vistos, orden, creados, cierres, global) {
                return false;
            }
            continue;
        }
        if !tiene(plantillas, plantilla) {
            imprimir_error($"tcodec: `{plantilla}` no es una generica conocida\n");
            return false;
        }
        let de = obtener(plantillas, plantilla) sino 0;
        let copia = nodo_instancia(p, arboles, plantillas, cierres.numeracion);
        var borrador = F.cuenta_nueva();
        borrador.sacados = copiar(cierres.sacados);
        borrador.dueno = dueno_de_pedido(p);
        let lineas = F.generar_funcion(copia, contextos[de], modulos[de], borrador);
        if lineas.largo() == 0 {
            imprimir_error($"tcodec: no se escribir la copia `{en_c}`\n");
            return false;
        }
        if !descubrir(borrador.instancias, arboles, contextos, modulos, plantillas,
            vistos, orden, creados, cierres, global) {
            return false;
        }
        orden.anadir(copiar(p));
    }
    return true;
}

// Una funcion al archivo: su prototipo, su cuerpo y lo que su cuerpo pide
// de la aritmetica. Falso si no la sabe escribir entera.
fn emitir_funcion(d: &P.Nodo, tipos: mut I.Contexto, ruta: view,
    cta: mut F.Cuenta, protos: mut lista<str>, cuerpos: mut lista<str>,
    anchos: mut mapa<str, usize>, decimales: mut mapa<str, usize>,
    conversiones: mut mapa<str, usize>) -> bool {
    let lineas = F.generar_funcion(d, tipos, ruta, cta);
    if lineas.largo() == 0 {
        imprimir_error($"tcodec: no se escribir `{d.texto}` entera\n");
        return false;
    }
    if d.texto != "main" {
        for l en lineas {
            if !empieza_con(l, "#line") {
                var p = copiar(l);
                p.empujar(";");
                protos.anadir(p);
                break;
            }
        }
    }
    for l en lineas {
        let limpia = sin_cadenas(l);
        if necesita_lo_que_falta(limpia) {
            imprimir_error($"tcodec: `{d.texto}` necesita algo que falta: {l}\n");
            return false;
        }
        apuntar_tras(limpia, "ss_lang_suma_", anchos);
        apuntar_tras(limpia, "ss_lang_resta_", anchos);
        apuntar_tras(limpia, "ss_lang_mul_", anchos);
        apuntar_tras(limpia, "ss_lang_abs_", anchos);
        apuntar_tras(limpia, "ss_lang_neg_", anchos);
        apuntar_tras(limpia, "ss_lang_div_", anchos);
        apuntar_tras(limpia, "ss_lang_mod_", anchos);
        apuntar_tras(limpia, "ss_lang_desp_izq_", anchos);
        apuntar_tras(limpia, "ss_lang_desp_der_", anchos);
        apuntar_tras(limpia, "ss_lang_env_", anchos);
        apuntar_tras(limpia, "ss_lang_fin_", decimales);
        apuntar_tras(limpia, "ss_lang_conv_", conversiones);
        cuerpos.anadir(copiar(l));
    }
    cuerpos.anadir(vacio());
    return true;
}

// ------------------------------------------------------------------
// Del C al binario, como `tcode`
// ------------------------------------------------------------------

// Un argumento para la shell, entre comillas simples: nada de dentro se
// interpreta.
fn para_la_shell(t: view) -> str {
    var r = nuevo("'");
    var i = 0;
    while i < t.largo() {
        if byte(t, i) == 39 { r.empujar("'\\''"); }
        else { r.empujar(rebanar(t, i, i + 1)); }
        i = i + 1;
    }
    r.empujar("'");
    return r;
}

// `a/b/c.t` -> `a/b/c`: sin la extension, si la hay en el ultimo trozo.
fn sin_extension(ruta: view) -> str {
    var punto = ruta.largo();
    var i = ruta.largo();
    while i > 0 {
        i = i - 1;
        let b = byte(ruta, i);
        if b == 47 { break; }
        if b == 46 {
            punto = i;
            break;
        }
    }
    // `.oculto` no tiene extension: el punto es parte del nombre.
    if punto < ruta.largo() && punto > 0 && byte(ruta, punto - 1) == 47 {
        return nuevo(ruta);
    }
    if punto == 0 { return nuevo(ruta); }
    return nuevo(rebanar(ruta, 0, punto));
}

fn extension(ruta: view) -> str {
    let sin = sin_extension(ruta);
    return nuevo(rebanar(ruta, sin.largo(), ruta.largo()));
}

fn nombre_suelto(ruta: view) -> str {
    var i = ruta.largo();
    while i > 0 {
        if byte(ruta, i - 1) == 47 { break; }
        i = i - 1;
    }
    return nuevo(rebanar(ruta, i, ruta.largo()));
}

fn directorio_de(ruta: view) -> str {
    var i = ruta.largo();
    while i > 0 {
        if byte(ruta, i - 1) == 47 { return nuevo(rebanar(ruta, 0, i - 1)); }
        i = i - 1;
    }
    return vacio();
}

// `escribir_archivo` no da valor: esto da `true` si fue bien, para poder
// decir que hacer si no con `sino false`.
fn escribir(ruta: view, contenido: view) -> bool ! {
    try escribir_archivo(ruta, contenido);
    return true;
}

// Lo escribe entero en un temporal al lado y solo entonces sustituye el
// destino, siguiendo enlaces y con sus permisos.
fn escribir_de_una_vez(ruta: view, contenido: view, ejecutable: bool) -> bool {
    let destino = tcodec_ruta_real(nuevo(ruta));
    if destino.largo() == 0 { return false; }
    let temporal = tcodec_temporal_junto(copiar(destino));
    if temporal.largo() == 0 { return false; }
    let bien = escribir(vista(temporal), contenido) sino false;
    if !bien {
        tcodec_borrar(copiar(temporal));
        return false;
    }
    var bandera: i32 = 0;
    if ejecutable { bandera = 1; }
    if tcodec_instalar(copiar(temporal), copiar(destino), bandera) != 0 {
        tcodec_borrar(copiar(temporal));
        return false;
    }
    return true;
}

fn construir(todo: view, fuente: view, salida: view, modo: view, nivel: view,
    cc: view, raiz: view, ext_cabeceras: &lista<str>, ext_modulos: &lista<str>) -> usize {
    var base = nuevo(salida);
    if base.largo() == 0 { base = sin_extension(fuente); }

    // Con --emitir-c el C es el producto, y va junto al fuente. Un `.c` que
    // no escribio Tcode no se pisa.
    if modo == "emitir" {
        let ruta_c = $"{base}.c";
        if tcodec_es_archivo(copiar(ruta_c)) == 1 {
            let previo = leer_archivo(ruta_c) sino vacio();
            let marca = "/* Generado por el compilador de Tcode. No editar a mano. */";
            var principio = vista(previo);
            if principio.largo() > 200 { principio = rebanar(principio, 0, 200); }
            if !contiene(principio, marca) {
                imprimir_error($"tcodec: {ruta_c} ya existe y no lo genero tcode, asi que no lo piso. Usa -o para elegir otro nombre.\n");
                return 2;
            }
        }
        if !escribir_de_una_vez(ruta_c, todo, false) {
            imprimir_error($"tcodec: no se pudo escribir `{ruta_c}`\n");
            return 2;
        }
        imprimir($"{ruta_c}\n");
        return 0;
    }

    // `-o fuente.t` y un fuente sin extension harian que el compilador de C
    // pisara el programa original.
    if tcodec_misma_ruta(copiar(base), nuevo(fuente)) == 1 {
        imprimir_error($"tcodec: la salida `{base}` es el propio archivo fuente; elige otro nombre con `-o`.\n");
        return 2;
    }
    let ext = extension(base);
    if ext == ".t" {
        imprimir_error($"tcodec: la salida `{base}` parece un fuente `.t`; elige otro nombre para no sobrescribir codigo.\n");
        return 2;
    }
    if !contiene(todo, "int main(") {
        imprimir_error($"tcodec: {fuente} no tiene `fn main`, asi que no es un programa. Si es un modulo, compila el archivo que lo usa; si no, anade `fn main() -> usize {{ ... }}`.\n");
        return 1;
    }

    // Un `externo "algo.c"` no se incluye: se compila y se enlaza junto al
    // programa.
    var acompanan: lista<str> = [];
    var faltan: lista<str> = [];
    var k = 0;
    while k < ext_cabeceras.largo() {
        let cab = vista(ext_cabeceras[k]);
        if termina_con(cab, ".c") {
            let dir = directorio_de(ext_modulos[k]);
            var junto = nuevo(cab);
            if dir.largo() > 0 { junto = $"{dir}/{cab}"; }
            if !esta_en(acompanan, junto) && !esta_en(faltan, junto) {
                if tcodec_es_archivo(copiar(junto)) == 1 { acompanan.anadir(junto); }
                else { faltan.anadir(junto); }
            }
        }
        k = k + 1;
    }
    if faltan.largo() > 0 {
        for x en faltan {
            imprimir_error($"tcodec: `externo` pide `{x}` y ese archivo no esta.\n");
        }
        return 2;
    }

    let tmp = tcodec_directorio_temporal();
    if tmp.largo() == 0 {
        imprimir_error("tcodec: no se pudo crear un directorio temporal\n");
        return 2;
    }
    let nombre_c = nombre_suelto(base);
    let ruta_c = $"{tmp}/{nombre_c}.c";
    let ruta_err = $"{tmp}/cc.err";
    let bien = escribir(vista(ruta_c), todo) sino false;
    if !bien {
        imprimir_error($"tcodec: no se pudo escribir `{ruta_c}`\n");
        tcodec_borrar(copiar(tmp));
        return 2;
    }

    // El enlazador trabaja sobre un vecino temporal: solo un resultado
    // completo sustituye al binario anterior.
    let destino_bin = tcodec_ruta_real(copiar(base));
    var salida_tmp = vacio();
    if destino_bin.largo() > 0 { salida_tmp = tcodec_temporal_junto(copiar(destino_bin)); }
    if salida_tmp.largo() == 0 {
        imprimir_error($"tcodec: no se pudo preparar la salida `{base}`\n");
        tcodec_borrar(copiar(ruta_c));
        tcodec_borrar(copiar(tmp));
        return 2;
    }

    var orden = para_la_shell(cc);
    let piezas_fijas = $" -std=c17 -O{nivel} -Wall -Wextra ";
    orden.empujar(piezas_fijas);
    let incluir = $"-I{raiz}/runtime";
    orden.empujar(para_la_shell(incluir));
    orden.empujar(" ");
    orden.empujar(para_la_shell(ruta_c));
    orden.empujar(" ");
    let safestr = $"{raiz}/runtime/safestr.c";
    orden.empujar(para_la_shell(safestr));
    for x en acompanan {
        orden.empujar(" ");
        orden.empujar(para_la_shell(x));
    }
    orden.empujar(" -o ");
    orden.empujar(para_la_shell(salida_tmp));
    // `raiz`, `piso` y compania viven en libm.
    orden.empujar(" -lm 2> ");
    orden.empujar(para_la_shell(ruta_err));

    let rc = tcodec_ejecutar(orden);
    let dijo = leer_archivo(ruta_err) sino vacio();
    tcodec_borrar(copiar(ruta_c));
    tcodec_borrar(copiar(ruta_err));
    tcodec_borrar(copiar(tmp));
    if rc != 0 {
        tcodec_borrar(copiar(salida_tmp));
        if ext_cabeceras.largo() > 0 {
            imprimir_error("tcodec: el C generado no compilo. Con bloques `externo` de por medio, lo mas probable es que una firma no coincida con la de C.\n");
        } else {
            imprimir_error("tcodec: el C generado no compilo. Es un fallo del compilador, no de tu programa.\n");
        }
        imprimir_error($"{dijo}\n");
        return 1;
    }
    if largo(recortar(dijo)) > 0 { imprimir_error($"{dijo}\n"); }
    if tcodec_instalar(copiar(salida_tmp), copiar(destino_bin), 1) != 0 {
        tcodec_borrar(copiar(salida_tmp));
        imprimir_error($"tcodec: no se pudo instalar la salida `{base}`\n");
        return 2;
    }
    imprimir($"{base}\n");
    return 0;
}

struct Opciones {
    fuente: str,
    salida: str,
    nivel: str,
    cc: str,
    modo: str,
    sin_avisos: bool,
    escribir: bool,
    avisos_como_errores: bool,
    terminar: bool,
    codigo: usize,
}

fn leer_opciones() -> Opciones {
    var o = Opciones { fuente: vacio(), salida: vacio(), nivel: nuevo("2"),
        cc: variable_entorno("CC") sino nuevo("cc"), modo: nuevo("binario"),
        sin_avisos: false, escribir: false, avisos_como_errores: false,
        terminar: false, codigo: 0 };
    var ia = 1;
    while ia < n_argumentos() {
        let a = argumento(ia);
        ia = ia + 1;
        if a == "-o" || a == "--cc" {
            if ia >= n_argumentos() {
                imprimir_error($"tcodec: `{a}` necesita un valor detras\n");
                o.terminar = true;
                o.codigo = 2;
                return o;
            }
            if a == "-o" { o.salida = nuevo(argumento(ia)); }
            else { o.cc = nuevo(argumento(ia)); }
            ia = ia + 1;
        } else if empieza_con(a, "-O") {
            o.nivel = nuevo(rebanar(a, 2, a.largo()));
            if o.nivel.largo() == 0 && ia < n_argumentos() {
                o.nivel = nuevo(argumento(ia));
                ia = ia + 1;
            }
            let nv = vista(o.nivel);
            if nv != "0" && nv != "1" && nv != "2" && nv != "3" && nv != "s" {
                imprimir_error("tcodec: -O acepta 0, 1, 2, 3 o s\n");
                o.terminar = true;
                o.codigo = 2;
                return o;
            }
        } else if a == "--emitir-c" {
            o.modo = nuevo("emitir");
        } else if a == "--mostrar-c" {
            o.modo = nuevo("mostrar");
        } else if a == "--solo-comprobar" {
            o.modo = nuevo("comprobar");
        } else if a == "--explicar" {
            o.modo = nuevo("explicar");
        } else if a == "--formatear" {
            o.modo = nuevo("formatear");
        } else if a == "--escribir" {
            o.escribir = true;
        } else if a == "--sin-avisos" {
            o.sin_avisos = true;
        } else if a == "--avisos-como-errores" {
            o.avisos_como_errores = true;
        } else if a == "--version" {
            imprimir("tcodec 0.1.0\n");
            o.terminar = true;
            return o;
        } else if empieza_con(a, "-") {
            imprimir_error($"tcodec: no conozco la opcion `{a}`\n");
            o.terminar = true;
            o.codigo = 2;
            return o;
        } else if o.fuente.largo() > 0 {
            imprimir_error("tcodec: un archivo cada vez\n");
            o.terminar = true;
            o.codigo = 2;
            return o;
        } else {
            o.fuente = nuevo(a);
        }
    }
    if o.fuente.largo() == 0 {
        imprimir_error($"uso: {argumento(0)} <archivo.t> [-o salida] [-O0..3] [--cc cc] [--emitir-c] [--mostrar-c] [--solo-comprobar] [--sin-avisos] [--avisos-como-errores] [--formatear [--escribir]] [--explicar]\n");
        o.terminar = true;
        o.codigo = 2;
    } else if tcodec_es_archivo(copiar(o.fuente)) == 0 {
        imprimir_error($"tcodec: no encuentro {o.fuente}\n");
        o.terminar = true;
        o.codigo = 2;
    }
    return o;
}

fn formatear_archivo(fuente: view, escribir_en_su_sitio: bool) -> usize {
    let original = leer_archivo(fuente) sino vacio();
    var error_f = vacio();
    let salida_f = FMT.formatear(original, fuente, error_f) sino vacio();
    if error_f.largo() > 0 {
        imprimir_error($"error: {error_f}\n");
        return 1;
    }
    if !escribir_en_su_sitio {
        imprimir(salida_f);
        return 0;
    }
    if !igual(salida_f, original) {
        if !escribir_de_una_vez(fuente, salida_f, false) {
            imprimir_error($"tcodec: no se pudo escribir `{fuente}`\n");
            return 2;
        }
        imprimir($"formateado {fuente}\n");
    }
    return 0;
}

// Las instancias de aritmetica y conversion que realmente aparecen en los
// cuerpos. Mantener esta fase aparte deja visible que su orden depende solo de
// los nombres apuntados durante la generacion.
fn aritmetica_usada(anchos: &mapa<str, usize>, decimales: &mapa<str, usize>,
    conversiones: &mapa<str, usize>) -> lista<str> {
    var arit: lista<str> = [];
    var ws = claves(anchos);
    ordenar(ws);
    for w en ws { arit.anadir(fila_aritmetica(w)); }
    var fs = claves(decimales);
    ordenar(fs);
    for f en fs {
        let tc = G.tipo_c(f);
        arit.anadir($"SS_LANG_ARIT_F({f}, {tc})");
    }
    var cs: lista<str> = [];
    for cv en claves(conversiones) {
        let corte = buscar_desde(cv, "_de_", 0);
        if corte < cv.largo() {
            let destino = rebanar(cv, 0, corte);
            let origen = rebanar(cv, corte + 4, cv.largo());
            cs.anadir($"{destino}\t{origen}");
        }
    }
    ordenar(cs);
    for par en cs {
        let corte = buscar_desde(par, "\t", 0);
        let destino = rebanar(par, 0, corte);
        let origen = rebanar(par, corte + 1, par.largo());
        let td = G.tipo_c(destino);
        let to = G.tipo_c(origen);
        var macro = nuevo("SS_LANG_CONV");
        var extra = vacio();
        if empieza_con(origen, "f") {
            if destino == "usize" || empieza_con(destino, "u") {
                macro = nuevo("SS_LANG_CONV_F_U");
            } else {
                if empieza_con(destino, "i") { macro = nuevo("SS_LANG_CONV_F_I"); }
            }
        } else {
            if destino == "f32" || destino == "f64" {
                if origen == "usize" || empieza_con(origen, "u") {
                    macro = nuevo("SS_LANG_CONV_U_F");
                } else {
                    if empieza_con(origen, "i") { macro = nuevo("SS_LANG_CONV_I_F"); }
                }
                if destino == "f32" { extra = nuevo("FLT_MANT_DIG, "); }
                else { extra = nuevo("DBL_MANT_DIG, "); }
            } else {
                let origen_entero = origen == "usize"
                || empieza_con(origen, "u") || empieza_con(origen, "i");
                let destino_entero = destino == "usize"
                || empieza_con(destino, "u") || empieza_con(destino, "i");
                if origen_entero && destino_entero {
                    let ou = origen == "usize" || empieza_con(origen, "u");
                    let du = destino == "usize" || empieza_con(destino, "u");
                    var os = nuevo("I");
                    if ou { os = nuevo("U"); }
                    var ds = nuevo("I");
                    if du { ds = nuevo("U"); }
                    macro = $"SS_LANG_CONV_{os}_{ds}";
                    if du || ou { extra = $"{maximo_entero(destino)}, "; }
                    else {
                        extra = $"{minimo_entero(destino)}, {maximo_entero(destino)}, ";
                    }
                }
            }
        }
        if origen == "f64" && destino == "f32" {
            macro = nuevo("SS_LANG_CONV_F_F");
            extra = nuevo("FLT_MAX, ");
        }
        arit.anadir($"{macro}({destino}, {td}, {extra}{origen}, {to})");
    }
    if arit.largo() > 0 { arit.anadir(vacio()); }
    return arit;
}

// Los typedef de tipos funcion, en el primer lugar en que el C los nombra.
fn tipos_funcion_usados(global: &I.Contexto, arboles: &lista<P.Nodo>,
    instancias: &lista<P.Nodo>, protos: &lista<str>,
    limpios: &lista<str>) -> lista<str> {
    var candidatos: lista<str> = [];
    for fk en claves(global.retornos) {
        let firma = I.firma_de_funcion(global, fk);
        apuntar_tipo_funcion(firma, candidatos);
    }
    var k_tf = 0;
    while k_tf < arboles.largo() {
        for d en arboles[k_tf].hijos {
            if d.clase == Clase.Fn && !F.es_generica(d) {
                tipos_funcion_de(d, candidatos);
            }
        }
        k_tf = k_tf + 1;
    }
    for d en instancias { tipos_funcion_de(d, candidatos); }
    var nombres_fn: lista<str> = [];
    for t en candidatos { nombres_fn.anadir(G.tipo_c(t)); }
    var tipos_fn: lista<str> = [];
    var puestos_fn: mapa<str, usize> = [];
    var mirar_fn: lista<str> = [];
    for l en protos { mirar_fn.anadir(sin_cadenas(l)); }
    for l en limpios { mirar_fn.anadir(copiar(l)); }
    for l en mirar_fn {
        if !contiene(l, "ss_fn_") { continue; }
        var k_c = 0;
        while k_c < candidatos.largo() {
            let nc = vista(nombres_fn[k_c]);
            if !tiene(puestos_fn, nc) && contiene_nombre(l, nc) {
                poner(puestos_fn, nc, 1);
                let partes_f = T.partes_de_funcion(candidatos[k_c]);
                var firma_c = vacio();
                var q = 0;
                while q + 1 < partes_f.largo() {
                    if q > 0 { firma_c.empujar(", "); }
                    let pc = G.tipo_c(partes_f[q]);
                    firma_c.empujar(pc);
                    q = q + 1;
                }
                if firma_c.largo() == 0 { firma_c = nuevo("void"); }
                let rc = G.tipo_c(partes_f[partes_f.largo() - 1]);
                tipos_fn.anadir($"typedef {rc} (*{nc})({firma_c});");
            }
            k_c = k_c + 1;
        }
    }
    if tipos_fn.largo() > 0 { tipos_fn.anadir(vacio()); }
    return tipos_fn;
}

// Ensambla las secciones ya generadas sin decidir nada sobre su contenido.
fn ensamblar_c(raiz: view, ext_cabeceras: &lista<str>, ext_protos: &lista<str>,
    partes: &lista<str>, envoltorios: &lista<str>,
    tipos_fn: &lista<str>, arit: &lista<str>,
    bloque_copias: &lista<str>, protos: &lista<str>,
    cuerpos: &lista<str>) -> str ! {
    let cabecera = try leer_archivo($"{raiz}/runtime/cabecera.inc");
    var todas: lista<str> = [];
    todas.anadir(cabecera);
    var incluidas: lista<str> = [];
    for h en ext_cabeceras {
        if termina_con(h, ".c") || esta_en(incluidas, h) { continue; }
        incluidas.anadir(copiar(h));
    }
    if incluidas.largo() > 0 {
        todas.anadir(nuevo("/* de los bloques `externo` */"));
        for h en incluidas {
            if contiene(h, "/") || empieza_con(h, ".") {
                todas.anadir($"#include \"{h}\"");
            } else {
                todas.anadir($"#include <{h}>");
            }
        }
        todas.anadir(vacio());
    }
    if ext_protos.largo() > 0 {
        let cstr = try leer_archivo($"{raiz}/runtime/cstr.inc");
        anadir_lineas(cstr, todas);
        todas.anadir(vacio());
    }
    for x en partes { todas.anadir(copiar(x)); }
    for x en envoltorios { todas.anadir(copiar(x)); }
    for x en tipos_fn { todas.anadir(copiar(x)); }
    for a en arit { todas.anadir(copiar(a)); }
    for x en bloque_copias { todas.anadir(copiar(x)); }
    for p en protos { todas.anadir(copiar(p)); }
    var k_ext = 0;
    while k_ext < ext_protos.largo() {
        if termina_con(ext_cabeceras[k_ext], ".c") {
            todas.anadir($"{ext_protos[k_ext]};");
        }
        k_ext = k_ext + 1;
    }
    todas.anadir(vacio());
    for l en cuerpos { todas.anadir(copiar(l)); }

    var todo = vacio();
    var primero = true;
    for x en todas {
        if !primero { todo.empujar("\n"); }
        primero = false;
        todo.empujar(x);
    }
    return todo;
}

struct UsosGenerados {
    ok: bool,
    limpios: lista<str>,
    envoltorios: lista<str>,
}

// Comprueba que cada nombre compuesto usado por los cuerpos tenga la
// declaracion que el recorrido previo debio registrar. Los arreglos que solo
// aparecen en literales se completan aqui, igual que antes.
fn revisar_usos_generados(cuerpos: &lista<str>, reg: &Registro, cta: &F.Cuenta,
    plantillas: &mapa<str, usize>,
    vistas_inst: &mapa<str, usize>) -> UsosGenerados {
    var limpios: lista<str> = [];
    for l en cuerpos { limpios.anadir(sin_cadenas(l)); }
    var registradas: mapa<str, usize> = [];

    var usadas: mapa<str, usize> = [];
    for l en limpios { apuntar_nombres(l, "ss_lista_", usadas); }
    for x en reg.listas {
        let nombre_c = G.tipo_c(x);
        poner(registradas, vista(nombre_c), 1);
    }
    for u en claves(usadas) {
        if !tiene(registradas, u) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no la registro\n");
            return UsosGenerados { ok: false, limpios: [], envoltorios: [] };
        }
    }

    var usados_b: mapa<str, usize> = [];
    for l en limpios { apuntar_nombres(l, "ss_bloque_", usados_b); }
    for x en reg.bloques {
        let nombre_c = G.tipo_c(x);
        poner(registradas, vista(nombre_c), 1);
    }
    for u en claves(usados_b) {
        if !tiene(registradas, u) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no lo registro\n");
            return UsosGenerados { ok: false, limpios: [], envoltorios: [] };
        }
    }

    var tardios: lista<str> = [];
    for t en cta.arreglos {
        if !tiene(reg.arr_vistos, t) && !esta_en(tardios, t) {
            tardios.anadir(copiar(t));
        }
    }
    var envoltorios: lista<str> = [];
    var hondo = 0;
    var quedan = tardios.largo();
    while quedan > 0 {
        for t en tardios {
            if T.arreglos_dentro(t) == hondo {
                let pa = T.partes_de_arreglo(t);
                let te = G.tipo_c(pa[0]);
                let tc = G.tipo_c(t);
                envoltorios.anadir($"typedef struct {{ {te} e[{pa[1]}]; }} {tc};");
                quedan = quedan - 1;
            }
        }
        hondo = hondo + 1;
    }
    if envoltorios.largo() > 0 { envoltorios.anadir(vacio()); }
    var usados_a: mapa<str, usize> = [];
    for l en limpios { apuntar_nombres(l, "ss_arr_", usados_a); }
    for x en reg.arreglos {
        let nombre_c = G.tipo_c(x);
        poner(registradas, vista(nombre_c), 1);
    }
    for x en tardios {
        let nombre_c = G.tipo_c(x);
        poner(registradas, vista(nombre_c), 1);
    }
    for u en claves(usados_a) {
        if !tiene(registradas, u) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no lo registro\n");
            return UsosGenerados { ok: false, limpios: [], envoltorios: [] };
        }
    }

    var usados_m: mapa<str, usize> = [];
    var usados_r: mapa<str, usize> = [];
    for l en limpios {
        apuntar_nombres(l, "ss_mapa_", usados_m);
        apuntar_nombres(l, "ss_res_", usados_r);
    }
    for x en reg.mapas {
        let nombre_c = G.tipo_c(x);
        poner(registradas, vista(nombre_c), 1);
    }
    for x en reg.resultados {
        let nombre_c = G.tipo_resultado(x);
        poner(registradas, vista(nombre_c), 1);
    }
    for u en claves(usados_m) {
        let tipo = tipo_de_nombre_mapa(u);
        if !tiene(registradas, tipo) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no lo registro\n");
            return UsosGenerados { ok: false, limpios: [], envoltorios: [] };
        }
    }
    for u en claves(usados_r) {
        if !tiene(registradas, u) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no lo registro\n");
            return UsosGenerados { ok: false, limpios: [], envoltorios: [] };
        }
    }

    for g en claves(plantillas) {
        var usadas_g: mapa<str, usize> = [];
        let prefijo = $"{g}__";
        for l en limpios { apuntar_nombres(l, prefijo, usadas_g); }
        for u en claves(usadas_g) {
            if !tiene(vistas_inst, u) {
                imprimir_error($"tcodec: la copia `{u}` se usa y no se escribio\n");
                return UsosGenerados { ok: false, limpios: [], envoltorios: [] };
            }
        }
    }
    return UsosGenerados { ok: true, limpios: limpios, envoltorios: envoltorios };
}

struct CopiadoresGenerados {
    ok: bool,
    lineas: lista<str>,
}

fn generar_copiadores(cta: &F.Cuenta, global: &I.Contexto,
    st_indice: &mapa<str, usize>, st_campos: &lista<lista<str>>,
    st_tipos: &lista<lista<str>>, en_indice: &mapa<str, usize>,
    en_variantes: &lista<lista<str>>, en_lleva: &lista<lista<str>>,
    limpios: &lista<str>) -> CopiadoresGenerados {
    var apuntados: lista<str> = [];
    var vistos: mapa<str, usize> = [];
    for t en cta.copias {
        let tr = I.nombre_resuelto(t);
        necesita_copiador(tr, global, st_indice, st_tipos, vistos, apuntados);
    }
    var copiadores: lista<str> = [];
    var hondo = 0;
    var quedan = apuntados.largo();
    while quedan > 0 {
        for t en apuntados {
            if hondura_tipo(t) == hondo {
                copiadores.anadir(copiar(t));
                quedan = quedan - 1;
            }
        }
        hondo = hondo + 1;
    }
    var lineas: lista<str> = [];
    var nombres: mapa<str, usize> = [];
    for t en copiadores {
        let tc = G.tipo_c(t);
        let m = G.mangle(t);
        lineas.anadir($"static {tc} ss_copia_{m}(const {tc}* p);");
        let nc = $"ss_copia_{m}";
        poner(nombres, vista(nc), 1);
    }
    lineas.anadir(vacio());
    for t en copiadores {
        if !cuerpo_copiador(vista(t), global, st_indice, st_campos, st_tipos,
            en_indice, en_variantes, en_lleva, lineas) {
            let _r = rechazo("copiar bloques");
            return CopiadoresGenerados { ok: false, lineas: [] };
        }
    }
    var usados: mapa<str, usize> = [];
    for l en limpios { apuntar_nombres(l, "ss_copia_", usados); }
    for u en claves(usados) {
        if !tiene(nombres, u) {
            imprimir_error($"tcodec: `{u}` se usa y no se apunto\n");
            return CopiadoresGenerados { ok: false, lineas: [] };
        }
    }
    return CopiadoresGenerados { ok: true, lineas: lineas };
}

struct FuncionesGeneradas {
    ok: bool,
    protos: lista<str>,
    cuerpos: lista<str>,
    anchos: mapa<str, usize>,
    decimales: mapa<str, usize>,
    conversiones: mapa<str, usize>,
}

fn generar_funciones(arboles: &lista<P.Nodo>, contextos: mut lista<I.Contexto>,
    modulos: &lista<str>, instancias: &lista<P.Nodo>,
    modulo_de: &lista<usize>, duenos_inst: &lista<str>,
    orden_inst: &lista<str>, orden_copias_revision: &lista<str>,
    cta: mut F.Cuenta) -> FuncionesGeneradas {
    var protos: lista<str> = [];
    var cuerpos: lista<str> = [];
    var anchos: mapa<str, usize> = [];
    var decimales: mapa<str, usize> = [];
    var conversiones: mapa<str, usize> = [];
    var i = 0;
    while i < arboles.largo() {
        // El original compara archivo y linea a la vez para no repetir un
        // `#line`: al cambiar de modulo nunca coincide.
        cta.ultima_linea = 0;
        for d en arboles[i].hijos {
            if d.clase != Clase.Fn || F.es_generica(d) { continue; }
            cta.dueno = dueno_de_funcion(d, contextos[i]);
            if !emitir_funcion(d, contextos[i], vista(modulos[i]), cta, protos,
                cuerpos, anchos, decimales, conversiones) {
                return FuncionesGeneradas { ok: false, protos: [], cuerpos: [],
                    anchos: [], decimales: [], conversiones: [] };
            }
        }
        i = i + 1;
    }

    // Las copias van detras de todo, `main` incluida, en el orden en que las
    // hizo el comprobador; las que no hizo, detras, como se descubrieron.
    var puesto_de: mapa<str, usize> = [];
    var k_orden = 0;
    while k_orden < orden_copias_revision.largo() {
        if !tiene(puesto_de, orden_copias_revision[k_orden]) {
            poner(puesto_de, vista(orden_copias_revision[k_orden]), k_orden);
        }
        k_orden = k_orden + 1;
    }
    var puestos_copias: lista<usize> = [];
    for p en orden_inst {
        let en_c_o = campo_pedido(p, 1);
        anadir(puestos_copias,
            obtener(puesto_de, en_c_o) sino orden_copias_revision.largo());
    }
    let orden_copias = orden_por_puesto(puestos_copias);
    var ultima_ruta = copiar(modulos[modulos.largo() - 1]);
    for k_o en orden_copias {
        let de = modulo_de[k_o];
        if !igual(modulos[de], ultima_ruta) { cta.ultima_linea = 0; }
        ultima_ruta = copiar(modulos[de]);
        cta.dueno = copiar(duenos_inst[k_o]);
        if !emitir_funcion(instancias[k_o], contextos[de], vista(modulos[de]),
            cta, protos, cuerpos, anchos, decimales, conversiones) {
            return FuncionesGeneradas { ok: false, protos: [], cuerpos: [],
                anchos: [], decimales: [], conversiones: [] };
        }
    }
    return FuncionesGeneradas { ok: true, protos: protos, cuerpos: cuerpos,
        anchos: anchos, decimales: decimales, conversiones: conversiones };
}

struct SoporteGenerado {
    partes: lista<str>,
    cta: F.Cuenta,
}

struct StructsLeidos {
    nombres: lista<str>,
    campos: lista<lista<str>>,
    tipos: lista<lista<str>>,
    indice: mapa<str, usize>,
}

struct StructsGenericos {
    indice: mapa<str, usize>,
    params: lista<lista<str>>,
    campos: lista<lista<str>>,
    tipos: lista<lista<str>>,
}

struct EnumsLeidos {
    nombres: lista<str>,
    indice: mapa<str, usize>,
    variantes: lista<lista<str>>,
    lleva: lista<lista<str>>,
}

struct ExternosLeidos {
    cabeceras: lista<str>,
    modulos: lista<str>,
    protos: lista<str>,
}

struct ProgramaLeido {
    ok: bool,
    modulos: lista<str>,
    global: I.Contexto,
    arboles: lista<P.Nodo>,
    contextos: lista<I.Contexto>,
    structs: StructsLeidos,
    genericos: StructsGenericos,
    enums: EnumsLeidos,
    externos: ExternosLeidos,
    plantillas: mapa<str, usize>,
}

fn programa_no_leido() -> ProgramaLeido {
    return ProgramaLeido { ok: false, modulos: [], global: I.contexto(),
        arboles: [], contextos: [],
        structs: StructsLeidos { nombres: [], campos: [], tipos: [], indice: [] },
        genericos: StructsGenericos { indice: [], params: [], campos: [], tipos: [] },
        enums: EnumsLeidos { nombres: [], indice: [], variantes: [], lleva: [] },
        externos: ExternosLeidos { cabeceras: [], modulos: [], protos: [] },
        plantillas: [] };
}

fn ajustar_contextos(arboles: &lista<P.Nodo>, modulos: &lista<str>, raiz: view,
    global: &I.Contexto, plantillas: &mapa<str, usize>,
    contextos: mut lista<I.Contexto>) -> bool ! {
    var error_nombres = vacio();
    if !revisar_nombres(arboles, modulos, raiz, error_nombres) {
        imprimir_error($"error: {error_nombres}\n");
        return false;
    }
    for g en claves(plantillas) {
        if tiene(global.repetidas, g) {
            let _r = rechazo("una generica repetida entre modulos");
            return false;
        }
    }
    var mr = 0;
    while mr < arboles.largo() {
        for d en arboles[mr].hijos {
            if d.clase == Clase.Fn && tiene(global.repetidas, d.texto) {
                let suyos = declarantes(arboles, modulos, d.texto);
                let base = F.prefijo_unico(modulos[mr], suyos);
                let otro = $"{base}__{d.texto}";
                poner(contextos[mr].renombradas, vista(d.texto), otro);
                quitar(contextos[mr].repetidas, d.texto);
            }
        }
        let fuente_m = try leer_archivo(modulos[mr]);
        let pedidos_m = try usar_con_alias(fuente_m);
        let dir_m = P.carpeta(modulos[mr]);
        for pedido en pedidos_m {
            let ruta_p = campo_pedido(pedido, 0);
            let alias_p = campo_pedido(pedido, 1);
            let destino = try resolver(ruta_p, dir_m, raiz);
            var jm = 0;
            while jm < modulos.largo() && !igual(modulos[jm], destino) {
                jm = jm + 1;
            }
            if jm == modulos.largo() {
                let _r = rechazo("un modulo que no se cargo");
                return false;
            }
            for d en arboles[jm].hijos {
                if d.clase != Clase.Fn || !tiene(global.repetidas, d.texto) {
                    continue;
                }
                var clave = copiar(d.texto);
                if alias_p.largo() > 0 { clave = $"{alias_p}.{d.texto}"; }
                let suyos = declarantes(arboles, modulos, d.texto);
                let base_d = F.prefijo_unico(destino, suyos);
                let otro = $"{base_d}__{d.texto}";
                poner(contextos[mr].renombradas, vista(clave), otro);
                quitar(contextos[mr].repetidas, clave);
            }
        }
        mr = mr + 1;
    }

    // Cada archivo necesita conocer los tipos de todo el programa.
    var k_ctx = 0;
    while k_ctx < contextos.largo() {
        for st en claves(global.campos) {
            if tiene(contextos[k_ctx].campos, st) { continue; }
            let cs_g = I.lista_de(global.campos, vista(st)) sino [];
            poner(contextos[k_ctx].campos, vista(st), cs_g);
            let ns_g = I.lista_de(global.nombres, vista(st)) sino [];
            poner(contextos[k_ctx].nombres, vista(st), ns_g);
        }
        for sp en claves(global.struct_params) {
            if tiene(contextos[k_ctx].struct_params, sp) { continue; }
            let ps_g = I.lista_de(global.struct_params, vista(sp)) sino [];
            poner(contextos[k_ctx].struct_params, vista(sp), ps_g);
        }
        for en_g en claves(global.variantes) {
            if tiene(contextos[k_ctx].variantes, en_g) { continue; }
            let vs_g = I.lista_de(global.variantes, vista(en_g)) sino [];
            poner(contextos[k_ctx].variantes, vista(en_g), vs_g);
        }
        for fk en claves(global.formas) {
            if tiene(contextos[k_ctx].formas, fk) { continue; }
            let fs_g = I.lista_de(global.formas, vista(fk)) sino [];
            poner(contextos[k_ctx].formas, vista(fk), fs_g);
        }
        k_ctx = k_ctx + 1;
    }
    return true;
}

fn leer_programa(fuente: view, raiz: view) -> ProgramaLeido ! {
    let principal = F.normalizar(fuente);
    var modulos: lista<str> = [];
    var pila: lista<str> = [];
    var error_carga = vacio();
    if !visitar(principal, raiz, modulos, pila, error_carga, "", 0) {
        imprimir_error($"error: {error_carga}\n");
        return programa_no_leido();
    }

    var global = I.contexto();
    var arboles: lista<P.Nodo> = [];
    var contextos: lista<I.Contexto> = [];
    var st_nombres: lista<str> = [];
    var st_campos: lista<lista<str>> = [];
    var st_tipos: lista<lista<str>> = [];
    var st_indice: mapa<str, usize> = [];
    var stp_nombres: lista<str> = [];
    var stp_indice: mapa<str, usize> = [];
    var stp_params: lista<lista<str>> = [];
    var stp_campos: lista<lista<str>> = [];
    var stp_tipos: lista<lista<str>> = [];
    var ext_cabeceras: lista<str> = [];
    var ext_modulos: lista<str> = [];
    var ext_protos: lista<str> = [];
    var en_nombres: lista<str> = [];
    var en_indice: mapa<str, usize> = [];
    var en_variantes: lista<lista<str>> = [];
    var en_lleva: lista<lista<str>> = [];
    var plantillas: mapa<str, usize> = [];
    var previos_st: mapa<str, usize> = [];
    var previos_en: mapa<str, usize> = [];
    var leidos = P.leidos_en(raiz);
    for m en modulos {
        var tipos = I.contexto();
        var error_m = vacio();
        let arbol = F.preparar_con_error(vista(m), tipos, error_m, previos_st,
            previos_en, leidos) sino P.rama(Clase.Vacio, 0);
        if error_m.largo() > 0 {
            imprimir_error($"error: {error_m}\n");
            return programa_no_leido();
        }
        if arbol.clase == Clase.Vacio {
            imprimir_error($"tcodec: no se pudo leer `{m}`\n");
            return programa_no_leido();
        }
        for d en arbol.hijos {
            if d.clase == Clase.Struct || d.clase == Clase.Enum {
                poner(previos_st, vista(d.texto), 1);
            }
            if d.clase == Clase.Enum { poner(previos_en, vista(d.texto), 1); }
        }
        F.recoger_firmas(arbol, global);
        for d en arbol.hijos {
            let clase = d.clase;
            match clase {
                Clase.Fn -> {
                    if F.es_generica(d) {
                        poner(plantillas, vista(d.texto), arboles.largo());
                        continue;
                    }
                    if d.texto == "main" && !igual(m, principal) {
                        let _r = rechazo("un `main` en un modulo");
                        return programa_no_leido();
                    }
                    continue;
                }
                Clase.Struct -> {
                    if tiene_tipo_param(d) {
                        if tiene(stp_indice, d.texto) {
                            let _r = rechazo("un struct generico repetido entre modulos");
                            return programa_no_leido();
                        }
                        var tps: lista<str> = [];
                        var cs: lista<str> = [];
                        var ts: lista<str> = [];
                        for h en d.hijos {
                            if h.clase == Clase.TipoParam { tps.anadir(nuevo(h.texto)); }
                            if h.clase == Clase.CampoDef {
                                cs.anadir(F.nombre_de(h.texto));
                                let tp = F.tipo_pelado(h.texto);
                                ts.anadir(I.sin_alias_tipo(tp));
                            }
                        }
                        poner(stp_indice, vista(d.texto), stp_nombres.largo());
                        stp_nombres.anadir(nuevo(d.texto));
                        stp_params.anadir(tps);
                        stp_campos.anadir(cs);
                        stp_tipos.anadir(ts);
                        continue;
                    }
                    if tiene(st_indice, d.texto) {
                        let _r = rechazo("un struct repetido entre modulos");
                        return programa_no_leido();
                    }
                    var campos: lista<str> = [];
                    var tipos_campo: lista<str> = [];
                    for h en d.hijos {
                        if h.clase == Clase.CampoDef {
                            let tp = F.tipo_pelado(h.texto);
                            campos.anadir(F.nombre_de(h.texto));
                            tipos_campo.anadir(I.sin_alias_tipo(tp));
                        }
                    }
                    poner(st_indice, vista(d.texto), st_nombres.largo());
                    st_nombres.anadir(nuevo(d.texto));
                    st_campos.anadir(campos);
                    st_tipos.anadir(tipos_campo);
                    continue;
                }
                Clase.Externo -> {
                    for f en d.hijos {
                        if f.clase != Clase.Fn { continue; }
                        var ps: lista<str> = [];
                        var pn: lista<str> = [];
                        var ret = vacio();
                        for h en f.hijos {
                            if h.clase == Clase.Param {
                                let tp = F.tipo_pelado(h.texto);
                                ps.anadir(I.sin_alias_tipo(tp));
                                pn.anadir(F.nombre_de(h.texto));
                            }
                            if h.clase == Clase.RetornoTipo { ret = nuevo(h.texto); }
                        }
                        ext_cabeceras.anadir(nuevo(d.texto));
                        ext_modulos.anadir(copiar(m));
                        ext_protos.anadir(prototipo_externo(f.texto, ps, pn, ret));
                    }
                    continue;
                }
                Clase.Enum -> {
                    if tiene(en_indice, d.texto) || tiene(st_indice, d.texto) {
                        let _r = rechazo("un enum repetido entre modulos");
                        return programa_no_leido();
                    }
                    var vs: lista<str> = [];
                    var ls: lista<str> = [];
                    for h en d.hijos {
                        if h.clase != Clase.Variante { continue; }
                        vs.anadir(nuevo(h.texto));
                        var junto = vacio();
                        var primero_t = true;
                        for x en h.hijos {
                            if x.clase != Clase.Lleva { continue; }
                            let t = I.sin_alias_tipo(x.texto);
                            if T.lleva_bloque_o_arreglo(t) {
                                let _r = rechazo("bloques o arreglos en un enum");
                                return programa_no_leido();
                            }
                            if !primero_t { junto.empujar("\t"); }
                            primero_t = false;
                            junto.empujar(t);
                        }
                        ls.anadir(junto);
                    }
                    poner(en_indice, vista(d.texto), en_nombres.largo());
                    en_nombres.anadir(nuevo(d.texto));
                    en_variantes.anadir(vs);
                    en_lleva.anadir(ls);
                    continue;
                }
                _ -> {
                    if clase == Clase.Usar || clase == Clase.Alias { continue; }
                }
            }
            let _r = rechazo($"`{nombre_de_clase(clase)}`");
            return programa_no_leido();
        }
        arboles.anadir(arbol);
        contextos.anadir(tipos);
    }
    if !(try ajustar_contextos(arboles, modulos, raiz, global, plantillas, contextos)) {
        return programa_no_leido();
    }
    let structs = StructsLeidos { nombres: st_nombres, campos: st_campos,
        tipos: st_tipos, indice: st_indice };
    let genericos = StructsGenericos { indice: stp_indice, params: stp_params,
        campos: stp_campos, tipos: stp_tipos };
    let enums = EnumsLeidos { nombres: en_nombres, indice: en_indice,
        variantes: en_variantes, lleva: en_lleva };
    let externos = ExternosLeidos { cabeceras: ext_cabeceras,
        modulos: ext_modulos, protos: ext_protos };
    return ProgramaLeido { ok: true, modulos: modulos, global: global,
        arboles: arboles, contextos: contextos, structs: structs,
        genericos: genericos, enums: enums, externos: externos,
        plantillas: plantillas };
}

fn preparar_cierres(revision: &C.Revision, arboles: mut lista<P.Nodo>,
    contextos: mut lista<I.Contexto>, global: mut I.Contexto) -> Cierres {
    var sacados: mapa<str, usize> = [];
    for x en revision.sacados { poner(sacados, vista(x), 1); }
    var cierres = Cierres { fns: copiar(revision.cierres),
        modulo: copiar(revision.cierres_mod), indice: [],
        numeracion: copiar(revision.numeracion), sacados: sacados };
    var m_c = 0;
    while m_c < arboles.largo() {
        var k_d = 0;
        while k_d < arboles[m_c].hijos.largo() {
            if arboles[m_c].hijos[k_d].clase == Clase.Fn
            && !F.es_generica(arboles[m_c].hijos[k_d]) {
                var dueno = copiar(arboles[m_c].hijos[k_d].texto);
                if tiene(contextos[m_c].renombradas, dueno) {
                    dueno = nuevo(obtener(contextos[m_c].renombradas, dueno) sino "");
                }
                var cuenta: usize = 0;
                numerar_cierres(arboles[m_c].hijos[k_d], vista(dueno),
                    cierres.numeracion, cuenta);
            }
            k_d = k_d + 1;
        }
        m_c = m_c + 1;
    }
    let numeracion = copiar(cierres.numeracion);
    var k_cf = 0;
    while k_cf < cierres.fns.largo() {
        let dueno_c = copiar(cierres.fns[k_cf].texto);
        var cuenta_c: usize = 0;
        numerar_cierres(cierres.fns[k_cf], dueno_c, numeracion, cuenta_c);
        poner(cierres.indice, vista(dueno_c), k_cf);
        F.recoger_firmas(cierres.fns[k_cf], global);
        var k_cx = 0;
        while k_cx < contextos.largo() {
            F.recoger_firmas(cierres.fns[k_cf], contextos[k_cx]);
            k_cx = k_cx + 1;
        }
        k_cf = k_cf + 1;
    }
    return cierres;
}

struct InstanciasPreparadas {
    ok: bool,
    con_partes: mapa<str, usize>,
    vistas: mapa<str, usize>,
    orden: lista<str>,
    nodos: lista<P.Nodo>,
    modulos: lista<usize>,
    duenos: lista<str>,
    n_concretos: usize,
}

fn preparar_instancias(revision: &C.Revision, arboles: &lista<P.Nodo>,
    contextos: mut lista<I.Contexto>, modulos: &lista<str>,
    global: mut I.Contexto, cierres: &Cierres,
    plantillas: &mapa<str, usize>, stp_indice: &mapa<str, usize>,
    stp_params: &lista<lista<str>>, stp_campos: &lista<lista<str>>,
    stp_tipos: &lista<lista<str>>, st_nombres: mut lista<str>,
    st_indice: mut mapa<str, usize>, st_campos: mut lista<lista<str>>,
    st_tipos: mut lista<lista<str>>, en_nombres: &lista<str>) -> InstanciasPreparadas {
    // Primero se concretan los tipos de los structs declarados y los escritos
    // en funciones no genericas.
    var en_curso_st: mapa<str, usize> = [];
    let n_concretos = st_nombres.largo();
    var k_st = 0;
    while k_st < n_concretos {
        var nuevos_t: lista<str> = [];
        let viejos_t = copiar(st_tipos[k_st]);
        for vt en viejos_t {
            anadir(nuevos_t, resolver_reg(vista(vt), stp_indice, stp_params,
                    stp_campos, stp_tipos, en_curso_st, st_nombres, st_indice,
                    st_campos, st_tipos, global));
        }
        let nombre_st = copiar(st_nombres[k_st]);
        poner(global.campos, vista(nombre_st), copiar(nuevos_t));
        st_tipos[k_st] = nuevos_t;
        k_st = k_st + 1;
    }
    var k_fn = 0;
    while k_fn < arboles.largo() {
        for d en arboles[k_fn].hijos {
            if d.clase == Clase.Fn && !F.es_generica(d) {
                resolver_en_nodo(d, stp_indice, stp_params, stp_campos,
                    stp_tipos, en_curso_st, st_nombres, st_indice, st_campos,
                    st_tipos, global);
            }
        }
        k_fn = k_fn + 1;
    }

    var con_partes: mapa<str, usize> = [];
    for n en st_nombres { poner(con_partes, vista(n), 1); }
    for n en en_nombres { poner(con_partes, vista(n), 1); }

    // Las copias se descubren antes del recorrido de tipos: sus firmas
    // tambien cuentan y su orden tiene que ser el del compilador original.
    var vistas: mapa<str, usize> = [];
    var orden: lista<str> = [];
    var creados: lista<str> = [];
    var k_desc = 0;
    while k_desc < arboles.largo() {
        for d en arboles[k_desc].hijos {
            if d.clase != Clase.Fn || F.es_generica(d) { continue; }
            var borrador = F.cuenta_nueva();
            borrador.sacados = copiar(cierres.sacados);
            borrador.dueno = dueno_de_funcion(d, contextos[k_desc]);
            let escritas = F.generar_funcion(d, contextos[k_desc],
                vista(modulos[k_desc]), borrador);
            if escritas.largo() == 0 { continue; }
            if !descubrir(borrador.instancias, arboles, contextos, modulos,
                plantillas, vistas, orden, creados, cierres, global) {
                return InstanciasPreparadas { ok: false, con_partes: [],
                    vistas: [], orden: [], nodos: [], modulos: [], duenos: [],
                    n_concretos: 0 };
            }
        }
        k_desc = k_desc + 1;
    }
    for p en creados {
        if largo(campo_pedido(p, 0)) == 0 {
            let en_c_c = campo_pedido(p, 1);
            let st_c = struct_de_cierre(en_c_c);
            var cn: lista<str> = [];
            var ct: lista<str> = [];
            campos_de_cierre(p, cn, ct);
            poner(st_indice, vista(st_c), st_nombres.largo());
            st_nombres.anadir(copiar(st_c));
            st_campos.anadir(cn);
            st_tipos.anadir(ct);
            continue;
        }
        let copia_r = nodo_instancia(p, arboles, plantillas, cierres.numeracion);
        resolver_instancia(copia_r, stp_indice, stp_params, stp_campos,
            stp_tipos, en_curso_st, st_nombres, st_indice, st_campos,
            st_tipos, global);
    }
    for t_ap en revision.structs_aplicados {
        let _r = resolver_reg(vista(t_ap), stp_indice, stp_params, stp_campos,
            stp_tipos, en_curso_st, st_nombres, st_indice, st_campos,
            st_tipos, global);
    }
    ordenar_como_comprobador(n_concretos, revision.orden_structs, st_nombres,
        st_indice, st_campos, st_tipos);
    for n en st_nombres { poner(con_partes, vista(n), 1); }

    var nodos: lista<P.Nodo> = [];
    var modulos_i: lista<usize> = [];
    var duenos: lista<str> = [];
    for p en orden {
        if largo(campo_pedido(p, 0)) == 0 {
            let en_c_i = campo_pedido(p, 1);
            let k_ci = obtener(cierres.indice, en_c_i) sino 0;
            nodos.anadir(copiar(cierres.fns[k_ci]));
            modulos_i.anadir(cierres.modulo[k_ci]);
            duenos.anadir(copiar(cierres.fns[k_ci].texto));
            continue;
        }
        nodos.anadir(nodo_instancia(p, arboles, plantillas, cierres.numeracion));
        duenos.anadir(dueno_de_pedido(p));
        let plantilla = campo_pedido(p, 0);
        modulos_i.anadir(obtener(plantillas, plantilla) sino 0);
    }
    return InstanciasPreparadas { ok: true, con_partes: con_partes,
        vistas: vistas, orden: orden, nodos: nodos, modulos: modulos_i,
        duenos: duenos, n_concretos: n_concretos };
}

fn generar_soporte(raiz: view, arboles: &lista<P.Nodo>, global: &I.Contexto,
    cierres: &Cierres, reg: mut Registro, con_partes: &mapa<str, usize>,
    st_nombres: &lista<str>, st_indice: &mapa<str, usize>,
    st_campos: &lista<lista<str>>, st_tipos: &lista<lista<str>>,
    en_nombres: &lista<str>, en_variantes: &lista<lista<str>>,
    en_lleva: &lista<lista<str>>) -> SoporteGenerado ! {
    // Las internas falibles registran su resultado despues de recorrer todo.
    var usa_leer_archivo = false;
    var usa_leer_parte_archivo = false;
    var usa_escribir_archivo = false;
    var da_texto = false;
    var usa_sistema: mapa<str, usize> = [];
    for arbol en arboles {
        if llama_a(arbol, "leer_archivo") { usa_leer_archivo = true; }
        if llama_a(arbol, "leer_parte_archivo") { usa_leer_parte_archivo = true; }
        if llama_a(arbol, "escribir_archivo") { usa_escribir_archivo = true; }
        if llama_a(arbol, "leer_linea") {
            da_texto = true;
            poner(usa_sistema, "leer_linea", 1);
        }
        if llama_a(arbol, "entrada_completa") {
            da_texto = true;
            poner(usa_sistema, "entrada_completa", 1);
        }
        if llama_a(arbol, "variable_entorno") {
            da_texto = true;
            poner(usa_sistema, "variable_entorno", 1);
        }
        if llama_a(arbol, "ahora_ms") { poner(usa_sistema, "ahora_ms", 1); }
        if llama_a(arbol, "monotono_ms") { poner(usa_sistema, "monotono_ms", 1); }
        if llama_a(arbol, "azar") || llama_a(arbol, "sembrar") {
            poner(usa_sistema, "semilla", 1);
        }
    }
    for arbol en arboles { resultados_de_internas(arbol, cierres, reg); }
    let _t = da_texto;

    // Los structs en orden de dependencia, y quien de ellos posee.
    var listos: mapa<str, usize> = [];
    var orden: lista<str> = [];
    for n en st_nombres { visitar_struct(n, st_indice, st_tipos, listos, orden); }
    var cta = F.cuenta_nueva();
    cta.sacados = copiar(cierres.sacados);

    var partes: lista<str> = [];
    for n en st_nombres { partes.anadir($"typedef struct {n} {n};"); }
    if st_nombres.largo() > 0 { partes.anadir(vacio()); }
    // Cada enum con la etiqueta de cada forma: la 0 es la primera.
    var ie_t = 0;
    while ie_t < en_nombres.largo() {
        partes.anadir($"typedef struct {en_nombres[ie_t]} {en_nombres[ie_t]};");
        var iv_t = 0;
        while iv_t < en_variantes[ie_t].largo() {
            let etq = G.etiqueta(en_nombres[ie_t], en_variantes[ie_t][iv_t]);
            partes.anadir($"#define {etq} {iv_t}");
            iv_t = iv_t + 1;
        }
        ie_t = ie_t + 1;
    }
    if en_nombres.largo() > 0 { partes.anadir(vacio()); }
    var ordenadas: lista<str> = [];
    for x en reg.bloques { ordenadas.anadir(copiar(x)); }
    for x en reg.listas { ordenadas.anadir(copiar(x)); }
    for x en reg.mapas { ordenadas.anadir(copiar(x)); }
    ordenar(ordenadas);
    var puestos: mapa<str, usize> = [];
    for x en ordenadas { poner_typedef(x, reg, puestos, partes); }
    if ordenadas.largo() > 0 { partes.anadir(vacio()); }
    // Los enums, y detras los structs en orden de dependencia. Cada uno
    // necesita el tamanio de lo que lleva por valor, asi que va despues.
    var definidos: mapa<str, usize> = [];
    for en_n en en_nombres {
        definir_tipo_c(vista(en_n), en_nombres, en_variantes, en_lleva,
            st_indice, st_campos, st_tipos, definidos, partes);
    }
    for n en orden {
        definir_tipo_c(vista(n), en_nombres, en_variantes, en_lleva,
            st_indice, st_campos, st_tipos, definidos, partes);
    }
    var alguno_posee = false;
    for n en orden {
        if I.posee_con_formas(global, n) {
            partes.anadir($"static void ss_drop_{n}({n}* p);");
            alguno_posee = true;
        }
    }
    for n en en_nombres {
        if I.posee_con_formas(global, n) {
            partes.anadir($"static void ss_drop_{n}({n}* p);");
            alguno_posee = true;
        }
    }
    if alguno_posee { partes.anadir(vacio()); }

    // Los envoltorios de arreglo, de dentro hacia fuera.
    var arr_orden: lista<str> = [];
    var hondo_a = 0;
    var quedan_a = reg.arreglos.largo();
    while quedan_a > 0 {
        for t en reg.arreglos {
            if T.arreglos_dentro(t) == hondo_a {
                arr_orden.anadir(copiar(t));
                quedan_a = quedan_a - 1;
            }
        }
        hondo_a = hondo_a + 1;
    }
    for t en arr_orden {
        let pa = T.partes_de_arreglo(t);
        let te = G.tipo_c(pa[0]);
        let tc = G.tipo_c(t);
        partes.anadir($"typedef struct {{ {te} e[{pa[1]}]; }} {tc};");
    }
    if reg.arreglos.largo() > 0 { partes.anadir(vacio()); }
    for r en reg.resultados { partes.anadir(typedef_resultado(r)); }
    if reg.resultados.largo() > 0 { partes.anadir(vacio()); }

    // Las internas que hablan con el sistema, en un orden fijo.
    let res_texto = G.tipo_resultado("str");
    var internas_orden: lista<str> = [];
    internas_orden.anadir(nuevo("ahora_ms"));
    internas_orden.anadir(nuevo("monotono_ms"));
    internas_orden.anadir(nuevo("semilla"));
    internas_orden.anadir(nuevo("leer_linea"));
    internas_orden.anadir(nuevo("entrada_completa"));
    internas_orden.anadir(nuevo("variable_entorno"));
    if usa_escribir_archivo { ayudante_escribir_archivo(partes); }
    for interna en internas_orden {
        if !tiene(usa_sistema, interna) { continue; }
        let crudo = try leer_archivo($"{raiz}/runtime/sistema/{interna}.inc");
        let hecho = try reemplazar(crudo, "@RES_STR@", res_texto);
        var desde = 0;
        var k_l = 0;
        let cuerpo_c = rebanar(hecho, 0, hecho.largo() - 1);
        while k_l <= cuerpo_c.largo() {
            if k_l == cuerpo_c.largo() || byte(cuerpo_c, k_l) == 10 {
                partes.anadir(nuevo(rebanar(cuerpo_c, desde, k_l)));
                desde = k_l + 1;
            }
            k_l = k_l + 1;
        }
        partes.anadir(vacio());
    }
    if usa_leer_archivo { ayudante_leer_archivo(partes); }
    if usa_leer_parte_archivo { ayudante_leer_parte_archivo(partes); }
    for x en reg.bloques { funcion_bloque(x, global, cta, partes); }
    for x en reg.listas { funcion_push(x, partes); }
    for x en reg.listas { funcion_ordenar(x, partes); }
    for x en reg.mapas { funcion_mapa(x, global, con_partes, cta, partes); }

    // Liberadores de structs, antes que las funciones y en la misma cuenta.
    for n en orden {
        if !I.posee_con_formas(global, n) { continue; }
        let k = obtener(st_indice, n) sino 0;
        var b = G.cuerpo();
        b.temporal = cta.temporal;
        b.bucle = cta.bucle;
        b.etiquetas = cta.etiquetas;
        var j = 0;
        while j < st_campos[k].largo() {
            let donde = $"p->{st_campos[k][j]}";
            G.liberacion(b, global, donde, st_tipos[k][j]);
            j = j + 1;
        }
        partes.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
        partes.anadir($"static void ss_drop_{n}({n}* p)");
        partes.anadir(nuevo("{"));
        for l en b.lineas { partes.anadir(copiar(l)); }
        partes.anadir(nuevo("}"));
        partes.anadir(vacio());
        cta.temporal = b.temporal;
        cta.bucle = b.bucle;
        cta.etiquetas = b.etiquetas;
    }

    // Liberadores de enums: solo las formas que llevan algo con duenio.
    var ie_d = 0;
    while ie_d < en_nombres.largo() {
        let en_n = copiar(en_nombres[ie_d]);
        if I.posee_con_formas(global, en_n) {
            partes.anadir(nuevo("SS_LANG_QUIZA_SIN_USAR"));
            partes.anadir($"static void ss_drop_{en_n}({en_n}* p)");
            partes.anadir(nuevo("{"));
            partes.anadir(nuevo("    switch (p->etiqueta)"));
            partes.anadir(nuevo("    {"));
            var iv = 0;
            while iv < en_variantes[ie_d].largo() {
                let tipos_v = partir_tab(en_lleva[ie_d][iv]);
                var alguna = false;
                for tt en tipos_v {
                    if I.posee_con_formas(global, tt) { alguna = true; }
                }
                if alguna {
                    let etq = G.etiqueta(en_n, en_variantes[ie_d][iv]);
                    partes.anadir($"    case {etq}:");
                    partes.anadir(nuevo("    {"));
                    var q = 0;
                    while q < tipos_v.largo() {
                        if I.posee_con_formas(global, tipos_v[q]) {
                            let donde = $"p->dato.v_{en_variantes[ie_d][iv]}._{q}";
                            lineas_liberacion(global, vista(donde), vista(tipos_v[q]),
                                2, cta, partes);
                        }
                        q = q + 1;
                    }
                    partes.anadir(nuevo("        break;"));
                    partes.anadir(nuevo("    }"));
                }
                iv = iv + 1;
            }
            partes.anadir(nuevo("    default: break;"));
            partes.anadir(nuevo("    }"));
            partes.anadir(nuevo("}"));
            partes.anadir(vacio());
        }
        ie_d = ie_d + 1;
    }
    return SoporteGenerado { partes: partes, cta: cta };
}

fn main() -> usize ! {
    // Antes que nada, pila de sobra: el analisis es recursivo.
    let _pila = tcodec_pila_honda();
    let opciones = leer_opciones();
    if opciones.terminar { return opciones.codigo; }
    if opciones.modo == "formatear" {
        return formatear_archivo(opciones.fuente, opciones.escribir);
    }
    let fuente = copiar(opciones.fuente);
    let salida = copiar(opciones.salida);
    let nivel = copiar(opciones.nivel);
    let cc = copiar(opciones.cc);
    let modo = copiar(opciones.modo);
    let sin_avisos = opciones.sin_avisos;
    let avisos_como_errores = opciones.avisos_como_errores;

    var raiz = variable_entorno("TCODE_RAIZ") sino tcodec_raiz_instalada();
    if raiz.largo() == 0 { raiz = nuevo("."); }
    let leido = try leer_programa(fuente, raiz);
    if !leido.ok { return 1; }
    let modulos = copiar(leido.modulos);
    var global = copiar(leido.global);
    var arboles = copiar(leido.arboles);
    var contextos = copiar(leido.contextos);
    var st_nombres = copiar(leido.structs.nombres);
    var st_campos = copiar(leido.structs.campos);
    var st_tipos = copiar(leido.structs.tipos);
    var st_indice = copiar(leido.structs.indice);
    let stp_indice = copiar(leido.genericos.indice);
    let stp_params = copiar(leido.genericos.params);
    let stp_campos = copiar(leido.genericos.campos);
    let stp_tipos = copiar(leido.genericos.tipos);
    let ext_cabeceras = copiar(leido.externos.cabeceras);
    let ext_modulos = copiar(leido.externos.modulos);
    let ext_protos = copiar(leido.externos.protos);
    let en_nombres = copiar(leido.enums.nombres);
    let en_indice = copiar(leido.enums.indice);
    let en_variantes = copiar(leido.enums.variantes);
    let en_lleva = copiar(leido.enums.lleva);
    let plantillas = copiar(leido.plantillas);

    // El programa tiene que valer antes de escribir nada: mismas reglas y
    // mismos mensajes que el comprobador de Python.
    let revision = C.comprobar_programa(arboles, modulos, contextos);
    // El tipo de cada expresion, tal como lo dejo el comprobador: el
    // generador lo lee en vez de deducirlo.
    var k_anot = 0;
    while k_anot < contextos.largo() && k_anot < revision.anotados.largo() {
        contextos[k_anot].anotados = copiar(revision.anotados[k_anot]);
        k_anot = k_anot + 1;
    }
    if revision.errores.largo() > 0 {
        for e en revision.errores { imprimir_error($"error: {e}\n"); }
        let n = revision.errores.largo();
        if n == 1 { imprimir_error("\n1 error. No se genero nada.\n"); }
        else { imprimir_error($"\n{n} errores. No se genero nada.\n"); }
        return 1;
    }
    // Un aviso no impide compilar, salvo que se pida.
    let n_avisos = revision.avisos.largo();
    if n_avisos > 0 && !sin_avisos {
        for a en revision.avisos { imprimir_error($"aviso: {a}\n"); }
        if avisos_como_errores {
            if n_avisos == 1 {
                imprimir_error("\n1 aviso tratado como error. No se genero nada.\n");
            } else {
                imprimir_error($"\n{n_avisos} avisos tratados como error. No se genero nada.\n");
            }
            return 1;
        }
    }
    // Lo que se infirio: quien es duenio de que, quien presta a quien, y donde
    // se libera cada cosa.
    if modo == "explicar" {
        let texto_e = vista(revision.explicacion);
        var salto = 0;
        while salto < texto_e.largo() && byte(texto_e, salto) != 10 { salto = salto + 1; }
        imprimir($"{fuente}{rebanar(texto_e, salto, largo(texto_e))}\n");
        return 0;
    }
    if modo == "comprobar" {
        if n_avisos == 0 { imprimir($"{fuente}: sin errores\n"); }
        else if n_avisos == 1 { imprimir($"{fuente}: sin errores, 1 aviso\n"); }
        else { imprimir($"{fuente}: sin errores, {n_avisos} avisos\n"); }
        return 0;
    }

    // Las clausuras conservan la numeracion y el modulo que les dio el
    // comprobador, incluso dentro de las copias genericas.
    let cierres = preparar_cierres(revision, arboles, contextos, global);

    let preparadas = preparar_instancias(revision, arboles, contextos, modulos,
        global, cierres, plantillas, stp_indice, stp_params, stp_campos,
        stp_tipos, st_nombres, st_indice, st_campos, st_tipos, en_nombres);
    if !preparadas.ok { return 1; }
    let con_partes = copiar(preparadas.con_partes);
    let vistas_inst = copiar(preparadas.vistas);
    let orden_inst = copiar(preparadas.orden);
    let instancias = copiar(preparadas.nodos);
    let modulo_de = copiar(preparadas.modulos);
    let duenos_inst = copiar(preparadas.duenos);
    let n_concretos = preparadas.n_concretos;

    // Las listas, con el mismo recorrido que el original: en orden de
    // declaracion, campos de struct y funciones entremezclados.
    var reg = registro();
    var im = 0;
    while im < arboles.largo() {
        for d en arboles[im].hijos {
            if d.clase == Clase.Struct && !tiene_tipo_param(d) {
                for h en d.hijos {
                    if h.clase == Clase.CampoDef {
                        let tp = F.tipo_pelado(h.texto);
                        let t = I.sin_alias_tipo(tp);
                        if !mirar_tipo(t, reg, global, con_partes) {
                            return rechazo("mapas, bloques ni arreglos");
                        }
                    }
                }
            }
            if d.clase == Clase.Enum {
                // Lo que lleva una forma tambien: `Lista(lista<Json>)` pedia
                // su lista y nadie la declaraba si el programa no la
                // escribia en otro sitio.
                for v en d.hijos {
                    if v.clase != Clase.Variante { continue; }
                    for x en v.hijos {
                        if x.clase != Clase.Lleva { continue; }
                        let t = I.sin_alias_tipo(x.texto);
                        if !mirar_tipo(t, reg, global, con_partes) {
                            return rechazo("mapas, bloques ni arreglos");
                        }
                    }
                }
            }
            if d.clase == Clase.Fn && !F.es_generica(d) {
                if !mirar_funcion(d, contextos[im], reg, global, con_partes) {
                    return rechazo("mapas, bloques ni arreglos");
                }
            }
        }
        im = im + 1;
    }
    // Las copias de structs genericos van detras de lo declarado.
    var k_ist = n_concretos;
    while k_ist < st_nombres.largo() {
        let tipos_ist = copiar(st_tipos[k_ist]);
        for tt en tipos_ist {
            if !mirar_tipo(tt, reg, global, con_partes) {
                return rechazo("mapas, bloques ni arreglos");
            }
        }
        k_ist = k_ist + 1;
    }
    var k_mira = 0;
    while k_mira < instancias.largo() {
        if !mirar_funcion(instancias[k_mira], contextos[modulo_de[k_mira]], reg,
            global, con_partes) {
            return rechazo("mapas, bloques ni arreglos");
        }
        k_mira = k_mira + 1;
    }

    let soporte = try generar_soporte(raiz, arboles, global, cierres, reg,
        con_partes, st_nombres, st_indice, st_campos, st_tipos, en_nombres,
        en_variantes, en_lleva);
    let partes = copiar(soporte.partes);
    var cta = copiar(soporte.cta);

    let funciones = generar_funciones(arboles, contextos, modulos, instancias,
        modulo_de, duenos_inst, orden_inst, revision.orden_copias, cta);
    if !funciones.ok { return 1; }
    let protos = copiar(funciones.protos);
    let cuerpos = copiar(funciones.cuerpos);
    let anchos = copiar(funciones.anchos);
    let decimales = copiar(funciones.decimales);
    let conversiones = copiar(funciones.conversiones);

    let usos = revisar_usos_generados(cuerpos, reg, cta, plantillas, vistas_inst);
    if !usos.ok { return 1; }
    let limpios = copiar(usos.limpios);
    let envoltorios = copiar(usos.envoltorios);

    let copias_c = generar_copiadores(cta, global, st_indice, st_campos, st_tipos,
        en_indice, en_variantes, en_lleva, limpios);
    if !copias_c.ok { return 1; }
    let bloque_copias = copiar(copias_c.lineas);

    let arit = aritmetica_usada(anchos, decimales, conversiones);
    let tipos_fn = tipos_funcion_usados(global, arboles, instancias, protos, limpios);
    let todo = try ensamblar_c(raiz, ext_cabeceras, ext_protos, partes,
        envoltorios, tipos_fn, arit, bloque_copias, protos, cuerpos);
    if modo == "mostrar" {
        imprimir(todo);
        return 0;
    }
    return construir(todo, vista(fuente), vista(salida), vista(modo), vista(nivel),
        vista(cc), vista(raiz), ext_cabeceras, ext_modulos);
}
