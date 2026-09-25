// tcodec.t — el archivo C entero, escrito por Tcode.
//
// El paso que separa "piezas que coinciden" de "un compilador": la cabecera,
// los modulos que el programa usa, sus structs, los tipos resultado, la
// aritmetica que hace falta, los prototipos y todas las funciones, `main`
// incluida, en el orden en que las escribe el generador de Python y con el
// mismo C. Lo que todavia no sabe escribir entero lo rechaza por la salida
// de error, sin escribir medio archivo.
//
// Se ejecuta desde la raiz del repositorio: todavia no sabe preguntar por el
// directorio de trabajo, y las rutas de los `#line` son relativas a el.
//
//     TCODE_RAIZ=. ./tcodec ejemplos/binario.t > binario.c

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
}

// Donde empieza `que` en `t` a partir de `desde`, o `largo(t)` si no esta.
fn buscar_desde(t: view, que: view, desde: usize) -> usize {
    var i = desde;
    while i + largo(que) <= largo(t) {
        if igual(rebanar(t, i, i + largo(que)), que) { return i; }
        i = i + 1;
    }
    return largo(t);
}

// Lo que va entre `prefijo` y el `(` siguiente, en cada aparicion.
fn apuntar_tras(t: view, prefijo: view, salida: mut mapa<str, usize>) {
    var i = buscar_desde(t, prefijo, 0);
    while i < largo(t) {
        let desde = i + largo(prefijo);
        let hasta = buscar_desde(t, "(", desde);
        if hasta < largo(t) {
            poner(salida, rebanar(t, desde, hasta), 1);
        }
        i = buscar_desde(t, prefijo, desde);
    }
}

// La linea que instancia la aritmetica comprobada de un ancho.
fn fila_aritmetica(t: view) -> str {
    if igual(t, "usize") { return nuevo("SS_LANG_ARIT_U(usize, size_t, SIZE_MAX)"); }
    if igual(t, "u8") { return nuevo("SS_LANG_ARIT_U(u8, uint8_t, UINT8_MAX)"); }
    if igual(t, "u16") { return nuevo("SS_LANG_ARIT_U(u16, uint16_t, UINT16_MAX)"); }
    if igual(t, "u32") { return nuevo("SS_LANG_ARIT_U(u32, uint32_t, UINT32_MAX)"); }
    if igual(t, "u64") { return nuevo("SS_LANG_ARIT_U(u64, uint64_t, UINT64_MAX)"); }
    if igual(t, "i8") {
        return nuevo("SS_LANG_ARIT_I(i8, int8_t, uint8_t, INT8_MAX, INT8_MIN)");
    }
    if igual(t, "i16") {
        return nuevo("SS_LANG_ARIT_I(i16, int16_t, uint16_t, INT16_MAX, INT16_MIN)");
    }
    if igual(t, "i32") {
        return nuevo("SS_LANG_ARIT_I(i32, int32_t, uint32_t, INT32_MAX, INT32_MIN)");
    }
    return nuevo("SS_LANG_ARIT_I(i64, int64_t, uint64_t, INT64_MAX, INT64_MIN)");
}

fn maximo_entero(t: view) -> str {
    if igual(t, "usize") { return nuevo("SIZE_MAX"); }
    if igual(t, "u8") { return nuevo("UINT8_MAX"); }
    if igual(t, "u16") { return nuevo("UINT16_MAX"); }
    if igual(t, "u32") { return nuevo("UINT32_MAX"); }
    if igual(t, "u64") { return nuevo("UINT64_MAX"); }
    if igual(t, "i8") { return nuevo("INT8_MAX"); }
    if igual(t, "i16") { return nuevo("INT16_MAX"); }
    if igual(t, "i32") { return nuevo("INT32_MAX"); }
    return nuevo("INT64_MAX");
}

fn minimo_entero(t: view) -> str {
    if igual(t, "i8") { return nuevo("INT8_MIN"); }
    if igual(t, "i16") { return nuevo("INT16_MIN"); }
    if igual(t, "i32") { return nuevo("INT32_MIN"); }
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
    while i < largo(l) {
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
                empujar(r, rebanar(l, desde, i + 1));
                dentro = true;
            }
        }
        i = i + 1;
    }
    if !dentro { empujar(r, rebanar(l, desde, largo(l))); }
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
    while i + 1 < largo(xs) {
        anadir(quedan, copiar(xs[i]));
        i = i + 1;
    }
    xs = quedan;
}

fn esta_en(xs: &lista<str>, x: view) -> bool {
    for y en xs {
        if igual(vista(y), x) { return true; }
    }
    return false;
}

// Donde esta un modulo pedido. `std/` viene de la instalacion; lo demas es
// relativo al archivo que lo pide. La extension es opcional.
fn resolver(pedido: view, dir: view, raiz: view) -> str ! {
    var base = vacio();
    if empieza_con(pedido, "std/") {
        empujar(base, raiz);
        empujar(base, "/std/");
        empujar(base, rebanar(pedido, 4, largo(pedido)));
    } else {
        if largo(dir) > 0 {
            empujar(base, dir);
            empujar(base, "/");
        }
        empujar(base, pedido);
    }
    var candidatos: lista<str> = [];
    anadir(candidatos, copiar(base));
    if !termina_con(vista(base), ".t") {
        var con_t = copiar(base);
        empujar(con_t, ".t");
        anadir(candidatos, con_t);
    }
    for c en candidatos {
        if tcodec_es_archivo(copiar(c)) == 1 { return F.normalizar(vista(c)); }
    }
    // La primera, para que el error diga algo reconocible.
    return F.normalizar(vista(candidatos[0]));
}

// Los `usar` del principio de un archivo, en orden.
fn usar_de(fuente: view) -> lista<str> ! {
    // Si no se puede leer, no pide nada: el error de verdad lo dice despues
    // `preparar`, con su archivo y su linea.
    let toks = analizar(fuente) sino [];
    var salida: lista<str> = [];
    var i = 0;
    while i + 1 < largo(toks) {
        if !igual(vista(toks[i].valor), "usar") { break; }
        if !igual(vista(toks[i + 1].tipo), "cadena") { break; }
        // `ruta\tlinea`: la linea es la del `usar`, para decir donde se pidio
        // un modulo que no esta.
        anadir(salida, $"{toks[i + 1].valor}\t{toks[i].linea}");
        i = i + 2;
        if i + 1 < largo(toks) && igual(vista(toks[i].valor), "como") {
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
    while i + 1 < largo(toks) {
        if !igual(vista(toks[i].valor), "usar") { break; }
        if !igual(vista(toks[i + 1].tipo), "cadena") { break; }
        var junto = copiar(toks[i + 1].valor);
        empujar(junto, "\t");
        let linea = toks[i].linea;
        i = i + 2;
        if i + 1 < largo(toks) && igual(vista(toks[i].valor), "como") {
            empujar(junto, vista(toks[i + 1].valor));
            i = i + 2;
        }
        let pieza = $"\t{linea}";
        empujar(junto, vista(pieza));
        anadir(salida, junto);
        i = i + 1; // el `;`
    }
    return salida;
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
            if igual(vista(p), ruta) { dentro = true; }
            if dentro {
                empujar(ciclo, nombre_suelto(vista(p)));
                empujar(ciclo, " -> ");
            }
        }
        empujar(ciclo, nombre_suelto(ruta));
        error = $"dependencia circular entre modulos: {ciclo}";
        return false;
    }
    if esta_en(hechos, ruta) { return true; }
    if tcodec_es_archivo(nuevo(ruta)) == 0 {
        var de = vacio();
        if largo(quien) > 0 { de = $"{quien}:{linea}: "; }
        var pista = vacio();
        if empieza_con(ruta, "std/") || contiene(ruta, "/std/") {
            pista = nuevo("; los modulos de `std/` viven junto al compilador");
        }
        let suelto = nombre_suelto(ruta);
        let dicho = repr_texto(vista(suelto));
        error = $"{de}no encuentro el modulo {dicho}{pista}";
        return false;
    }
    let fuente = leer_archivo(ruta) sino vacio();
    anadir(pila, nuevo(ruta));
    let pedidos = usar_de(vista(fuente)) sino [];
    let dir = P.carpeta(ruta);
    for pedido en pedidos {
        let pedida = campo_pedido(vista(pedido), 0);
        let texto_linea = campo_pedido(vista(pedido), 1);
        let n = a_entero(vista(texto_linea)) sino 0;
        let destino = resolver(vista(pedida), vista(dir), raiz) sino vacio();
        if !visitar(vista(destino), raiz, hechos, pila, error, ruta, n) { return false; }
    }
    quitar_ultima(pila);
    anadir(hechos, nuevo(ruta));
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
    while k < largo(arboles) {
        if esta_en(nombres_declarados(arboles[k]), nombre) { anadir(salida, copiar(modulos[k])); }
        k = k + 1;
    }
    return salida;
}

fn nombres_declarados(arbol: &P.Nodo) -> lista<str> {
    var salida: lista<str> = [];
    for d en arbol.hijos {
        let clase = vista(d.clase);
        if igual(clase, "fn") || igual(clase, "struct") || igual(clase, "enum") {
            if !esta_en(salida, vista(d.texto)) { anadir(salida, copiar(d.texto)); }
        }
    }
    return salida;
}

// Los nombres que una funcion declara dentro: parametros, variables, los de
// un `for` y los que atrapa un `match`.
fn locales_de(n: &P.Nodo, salida: mut lista<str>) {
    let clase = vista(n.clase);
    if igual(clase, "param") {
        var i = 0;
        while i < largo(n.texto) && byte(vista(n.texto), i) != 58 { i = i + 1; }
        anadir(salida, nuevo(recortar(rebanar(vista(n.texto), 0, i))));
    }
    if igual(clase, "declaracion") {
        let t = vista(n.texto);
        var i = 0;
        while i < largo(t) && byte(t, i) != 32 { i = i + 1; }
        var j = i + 1;
        while j < largo(t) && byte(t, j) != 58 { j = j + 1; }
        if i + 1 <= largo(t) { anadir(salida, nuevo(recortar(rebanar(t, i + 1, j)))); }
    }
    if igual(clase, "para") {
        let t = vista(n.texto);
        var i = 0;
        while i < largo(t) && byte(t, i) != 44 { i = i + 1; }
        anadir(salida, nuevo(recortar(rebanar(t, 0, i))));
        if i < largo(t) { anadir(salida, nuevo(recortar(rebanar(t, i + 1, largo(t))))); }
    }
    if igual(clase, "atrapa") { anadir(salida, copiar(n.texto)); }
    for h en n.hijos { locales_de(h, salida); }
}

// El primer nombre que se usa sin haberlo pedido, en preorden: `nombre\tlinea`.
fn sin_pedir(n: &P.Nodo, visible: &mapa<str, str>, duenios: &mapa<str, str>,
    locales: &lista<str>) -> str {
    let clase = vista(n.clase);
    var nombre = vacio();
    if igual(clase, "llamada") { nombre = copiar(n.texto); }
    if igual(clase, "literal_struct") { nombre = copiar(n.texto); }
    if igual(clase, "enum_lit") { nombre = I.antes_del_punto(vista(n.texto)); }
    if largo(nombre) > 0 {
        let nv = vista(nombre);
        if !tiene(visible, nv) && tiene(duenios, nv) && !C.nombra_interna(nv)
        && !esta_en(locales, nv) {
            return $"{nombre}\t{n.linea}";
        }
    }
    for h en n.hijos {
        let dentro = sin_pedir(h, visible, duenios, locales);
        if largo(dentro) > 0 { return dentro; }
    }
    return vacio();
}

fn revisar_nombres(arboles: &lista<P.Nodo>, modulos: &lista<str>, raiz: view,
    error: mut str) -> bool {
    // Quien declara cada nombre, en el orden de los modulos.
    var duenios: mapa<str, str> = [];
    var cuantos: mapa<str, usize> = [];
    var k = 0;
    while k < largo(arboles) {
        for n en nombres_declarados(arboles[k]) {
            var junto = nuevo(obtener(duenios, vista(n)) sino "");
            if largo(junto) > 0 { empujar(junto, ", "); }
            empujar(junto, vista(modulos[k]));
            poner(duenios, vista(n), junto);
            let c = obtener(cuantos, vista(n)) sino 0;
            poner(cuantos, vista(n), c + 1);
        }
        k = k + 1;
    }
    k = 0;
    while k < largo(arboles) {
        // clave -> `modulo` que la trae; el valor interno es modulo+nombre,
        // salvo que el nombre lo declare uno solo.
        var visible: mapa<str, str> = [];
        for n en nombres_declarados(arboles[k]) {
            poner(visible, vista(n), copiar(modulos[k]));
        }
        let fuente = leer_archivo(vista(modulos[k])) sino vacio();
        let pedidos = usar_con_alias(vista(fuente)) sino [];
        let dir = P.carpeta(vista(modulos[k]));
        for pedido en pedidos {
            let ruta_p = campo_pedido(vista(pedido), 0);
            let alias = campo_pedido(vista(pedido), 1);
            let texto_linea = campo_pedido(vista(pedido), 2);
            let destino = resolver(vista(ruta_p), vista(dir), raiz) sino vacio();
            var jm = 0;
            while jm < largo(modulos) && !igual(vista(modulos[jm]), vista(destino)) {
                jm = jm + 1;
            }
            if jm == largo(modulos) { continue; }
            for n en nombres_declarados(arboles[jm]) {
                var clave = copiar(n);
                if largo(alias) > 0 { clave = $"{alias}.{n}"; }
                if tiene(visible, vista(clave)) {
                    let previo = nuevo(obtener(visible, vista(clave)) sino "");
                    let varios = (obtener(cuantos, vista(n)) sino 0) > 1;
                    // Chocan si por dentro se llamarian distinto, y por dentro
                    // se llaman con el nombre del archivo delante: dos
                    // `x.t` en carpetas distintas no chocan aqui, como en el
                    // original.
                    let suyos = declarantes(arboles, modulos, vista(n));
                    let pa = F.prefijo_unico(vista(previo), suyos);
                    let pb = F.prefijo_unico(vista(modulos[jm]), suyos);
                    if varios && !igual(vista(pa), vista(pb)) {
                        let dicho = G.legible_c(vista(clave));
                        error = $"{modulos[k]}:{texto_linea}: `{dicho}` llega de dos sitios, {previo} y {modulos[jm]}. Dale un nombre a uno de los dos: `usar \"...\" como algo;` y luego `algo.{dicho}`";
                        return false;
                    }
                }
                poner(visible, vista(clave), copiar(modulos[jm]));
            }
        }
        // Y lo que se usa sin pedirlo.
        for d en arboles[k].hijos {
            if !igual(vista(d.clase), "fn") { continue; }
            var locales: lista<str> = [];
            locales_de(d, locales);
            for h en d.hijos {
                if !igual(vista(h.clase), "bloque") { continue; }
                let hallado = sin_pedir(h, visible, duenios, locales);
                if largo(hallado) > 0 {
                    let nombre = campo_pedido(vista(hallado), 0);
                    let linea = campo_pedido(vista(hallado), 1);
                    let donde = obtener(duenios, vista(nombre)) sino "";
                    let dicho = G.escrito(vista(nombre));
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
        while empieza_con(vista(base), "[") {
            let pa = partes_arreglo(vista(base));
            if largo(pa) != 2 { break; }
            base = copiar(pa[0]);
        }
        visitar_struct(vista(base), indice, tipos_de, listos, salida);
    }
    anadir(salida, nuevo(nombre));
}

// Define en C el enum o struct `nombre`, y antes lo que lleve por valor.
fn definir_tipo_c(nombre: view, en_nombres: &lista<str>, en_variantes: &lista<lista<str>>,
    en_lleva: &lista<lista<str>>, st_indice: &mapa<str, usize>,
    st_campos: &lista<lista<str>>, st_tipos: &lista<lista<str>>,
    definidos: mut mapa<str, usize>, partes: mut lista<str>) {
    if tiene(definidos, nombre) { return; }
    var ie = 0;
    while ie < largo(en_nombres) && !igual(vista(en_nombres[ie]), nombre) { ie = ie + 1; }
    let es_enum = ie < largo(en_nombres);
    if !es_enum && !tiene(st_indice, nombre) { return; }
    poner(definidos, nombre, 1);
    var lleva: lista<str> = [];
    if es_enum {
        for x en en_lleva[ie] {
            for t en partir_tab(vista(x)) { anadir(lleva, copiar(t)); }
        }
    } else {
        let k = obtener(st_indice, nombre) sino 0;
        for t en st_tipos[k] { anadir(lleva, copiar(t)); }
    }
    for t en lleva {
        var base = copiar(t);
        while empieza_con(vista(base), "[") {
            let pa = partes_arreglo(vista(base));
            if largo(pa) != 2 { break; }
            base = copiar(pa[0]);
        }
        definir_tipo_c(vista(base), en_nombres, en_variantes, en_lleva, st_indice, st_campos,
            st_tipos, definidos, partes);
    }
    if es_enum {
        cuerpo_enum_c(ie, en_nombres, en_variantes, en_lleva, partes);
    } else {
        let k = obtener(st_indice, nombre) sino 0;
        anadir(partes, $"struct {nombre}");
        anadir(partes, nuevo("{"));
        var j = 0;
        while j < largo(st_campos[k]) {
            let tc = G.tipo_c(vista(st_tipos[k][j]));
            anadir(partes, $"    {tc} {st_campos[k][j]};");
            j = j + 1;
        }
        anadir(partes, nuevo("};"));
        anadir(partes, vacio());
    }
}

// Un enum en C: la etiqueta y, a su lado, una union con lo de cada forma.
fn cuerpo_enum_c(ie_s: usize, en_nombres: &lista<str>, en_variantes: &lista<lista<str>>,
    en_lleva: &lista<lista<str>>, partes: mut lista<str>) {
    let en_n = copiar(en_nombres[ie_s]);
    anadir(partes, $"struct {en_n}");
    anadir(partes, nuevo("{"));
    anadir(partes, nuevo("    uint32_t etiqueta;"));
    var hay_datos = false;
    for ll en en_lleva[ie_s] {
        if largo(ll) > 0 { hay_datos = true; }
    }
    if hay_datos {
        anadir(partes, nuevo("    union"));
        anadir(partes, nuevo("    {"));
        var iv = 0;
        while iv < largo(en_variantes[ie_s]) {
            let tipos_v = partir_tab(vista(en_lleva[ie_s][iv]));
            if largo(tipos_v) > 0 {
                var campos_c = vacio();
                var q = 0;
                while q < largo(tipos_v) {
                    let tc = G.tipo_c(vista(tipos_v[q]));
                    if q > 0 { empujar(campos_c, " "); }
                    let pieza = $"{tc} _{q};";
                    empujar(campos_c, vista(pieza));
                    q = q + 1;
                }
                anadir(partes, $"        struct {{ {campos_c} }} v_{en_variantes[ie_s][iv]};");
            }
            iv = iv + 1;
        }
        anadir(partes, nuevo("    } dato;"));
    }
    anadir(partes, nuevo("};"));
    anadir(partes, vacio());
}

// Si en algun sitio de `n` se llama a la interna `nombre`.
fn llama_a(n: &P.Nodo, nombre: view) -> bool {
    if igual(vista(n.clase), "llamada") && igual(vista(n.texto), nombre) {
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
    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static {res} ss_lang_escribir_archivo_(SafeView ruta, SafeView datos)");
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    if (ruta.len != 0 && memchr(ruta.ptr, 0, ruta.len) != NULL)"));
    anadir(salida, $"        return ({res}){{ .motivo = \"la ruta contiene un byte cero\" }};");
    anadir(salida, vacio());
    anadir(salida, nuevo("    SafeString copia = ss_from_view(ruta);"));
    anadir(salida, nuevo("    if (!ss_ok(&copia))"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        ss_free(&copia);"));
    anadir(salida, $"        return ({res}){{ .motivo = \"sin memoria para la ruta\" }};");
    anadir(salida, nuevo("    }"));
    anadir(salida, nuevo("    FILE* f = fopen(ss_cstr(&copia), \"wb\");"));
    anadir(salida, nuevo("    ss_free(&copia);"));
    anadir(salida, nuevo("    if (f == NULL)"));
    anadir(salida, $"        return ({res}){{ .motivo = \"no se pudo abrir el archivo para escribir\" }};");
    anadir(salida, vacio());
    anadir(salida, nuevo("    bool fallo = false;"));
    anadir(salida, nuevo("    if (datos.len != 0)"));
    anadir(salida, nuevo("        fallo = fwrite(datos.ptr, 1, datos.len, f) != datos.len;"));
    anadir(salida, nuevo("    if (fclose(f) != 0) fallo = true;"));
    anadir(salida, nuevo("    if (fallo)"));
    anadir(salida, $"        return ({res}){{ .motivo = \"fallo al escribir el archivo\" }};");
    anadir(salida, $"    return ({res}){{ .motivo = NULL }};");
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());
}

// Las internas que pueden fallar necesitan su tipo resultado, y el original
// los apunta en el orden en que aparecen sus llamadas, entrando en cada
// clausura donde esta escrita.
fn resultados_de_internas(n: &P.Nodo, cierres: &Cierres, reg: mut Registro) {
    let clase = vista(n.clase);
    if igual(clase, "llamada") {
        let nombre = vista(n.texto);
        if igual(nombre, "leer_archivo") || igual(nombre, "leer_linea")
        || igual(nombre, "entrada_completa") || igual(nombre, "variable_entorno") {
            registrar_resultado(reg, "str");
        }
        if igual(nombre, "escribir_archivo") { registrar_resultado(reg, "()"); }
    }
    if igual(clase, "cierre") {
        let de_cierre = I.funcion_de_cierre(vista(n.texto));
        if tiene(cierres.indice, vista(de_cierre)) {
            let k = obtener(cierres.indice, vista(de_cierre)) sino 0;
            resultados_de_internas(cierres.fns[k], cierres, reg);
        }
    }
    for h en n.hijos { resultados_de_internas(h, cierres, reg); }
}

fn ayudante_leer_archivo(salida: mut lista<str>) {
    let res = G.tipo_resultado("str");
    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static {res} ss_lang_leer_archivo_(SafeView ruta)");
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    if (ruta.len != 0 && memchr(ruta.ptr, 0, ruta.len) != NULL)"));
    anadir(salida, $"        return ({res}){{ .motivo = \"la ruta contiene un byte cero\" }};");
    anadir(salida, nuevo("    SafeString nombre = ss_from_view(ruta);"));
    anadir(salida, nuevo("    if (!ss_ok(&nombre))"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        ss_free(&nombre);"));
    anadir(salida, $"        return ({res}){{ .motivo = \"sin memoria para la ruta\" }};");
    anadir(salida, nuevo("    }"));
    anadir(salida, nuevo("    FILE* f = fopen(ss_cstr(&nombre), \"rb\");"));
    anadir(salida, nuevo("    ss_free(&nombre);"));
    anadir(salida, nuevo("    if (f == NULL)"));
    anadir(salida, $"        return ({res}){{ .motivo = \"no se pudo abrir el archivo\" }};");
    anadir(salida, nuevo("    SafeString contenido = ss_new();"));
    anadir(salida, nuevo("    unsigned char bloque[8192];"));
    anadir(salida, nuevo("    size_t n;"));
    anadir(salida, nuevo("    while ((n = fread(bloque, 1, sizeof(bloque), f)) != 0)"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        if (!ss_append_len(&contenido, (const char*) bloque, n))"));
    anadir(salida, nuevo("        {"));
    anadir(salida, nuevo("            fclose(f);"));
    anadir(salida, nuevo("            ss_free(&contenido);"));
    anadir(salida, $"            return ({res}){{ .motivo = \"sin memoria al leer el archivo\" }};");
    anadir(salida, nuevo("        }"));
    anadir(salida, nuevo("    }"));
    anadir(salida, nuevo("    bool fallo_lectura = ferror(f) != 0;"));
    anadir(salida, nuevo("    if (fclose(f) != 0) fallo_lectura = true;"));
    anadir(salida, nuevo("    if (fallo_lectura)"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        ss_free(&contenido);"));
    anadir(salida, $"        return ({res}){{ .motivo = \"fallo al leer el archivo\" }};");
    anadir(salida, nuevo("    }"));
    anadir(salida, $"    return ({res}){{ .motivo = NULL, .valor = contenido }};");
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());
}

fn typedef_resultado(t: view) -> str {
    let nombre = G.tipo_resultado(t);
    if largo(t) == 0 || igual(t, "()") {
        return $"typedef struct {{ const char* motivo; }} {nombre};";
    }
    let tc = G.tipo_c(t);
    return $"typedef struct {{ const char* motivo; {tc} valor; }} {nombre};";
}

fn es_falible(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if igual(vista(h.clase), "falible") { return true; }
    }
    return false;
}

fn retorno_de(d: &P.Nodo) -> str {
    for h en d.hijos {
        if igual(vista(h.clase), "retorno_tipo") {
            return I.sin_alias_tipo(vista(h.texto));
        }
    }
    return vacio();
}

fn tiene_tipo_param(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if igual(vista(h.clase), "tipo_param") { return true; }
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

fn es_lista_t(t: view) -> bool { return empieza_con(t, "lista<"); }

fn interior_lista(t: view) -> str {
    return nuevo(rebanar(t, 6, largo(t) - 1));
}

// Bloques y arreglos: este hito todavia no los escribe.
fn es_bloque_o_arreglo(t: view) -> bool {
    return contiene(t, "bloque<") || contiene(t, "[");
}

fn es_mapa_t(t: view) -> bool { return empieza_con(t, "mapa<"); }

// La clave y el valor de un `mapa<K, V>`, cortando por la coma de fuera.
fn partes_mapa(t: view) -> lista<str> {
    var salida: lista<str> = [];
    let dentro = rebanar(t, 5, largo(t) - 1);
    var hondura = 0;
    var i = 0;
    while i < largo(dentro) {
        let b = byte(dentro, i);
        if b == 60 || b == 91 || b == 40 { hondura = hondura + 1; }
        if (b == 62 || b == 93 || b == 41) && hondura > 0 { hondura = hondura - 1; }
        if b == 44 && hondura == 0 {
            anadir(salida, nuevo(rebanar(dentro, 0, i)));
            var j = i + 1;
            while j < largo(dentro) && byte(dentro, j) == 32 { j = j + 1; }
            anadir(salida, nuevo(rebanar(dentro, j, largo(dentro))));
            return salida;
        }
        i = i + 1;
    }
    return salida;
}

// `[T; N]` -> [T, N], cortando por el `;` de fuera.
fn partes_arreglo(t: view) -> lista<str> {
    var salida: lista<str> = [];
    if largo(t) < 2 || !empieza_con(t, "[") { return salida; }
    let dentro = rebanar(t, 1, largo(t) - 1);
    var hondura = 0;
    var corte = largo(dentro);
    var i = 0;
    while i < largo(dentro) {
        let b = byte(dentro, i);
        if b == 91 || b == 60 { hondura = hondura + 1; }
        if (b == 93 || b == 62) && hondura > 0 { hondura = hondura - 1; }
        if b == 59 && hondura == 0 { corte = i; }
        i = i + 1;
    }
    if corte == largo(dentro) { return salida; }
    anadir(salida, nuevo(rebanar(dentro, 0, corte)));
    var j = corte + 1;
    while j < largo(dentro) && byte(dentro, j) == 32 { j = j + 1; }
    anadir(salida, nuevo(rebanar(dentro, j, largo(dentro))));
    return salida;
}

fn cuantos_corchetes(t: view) -> usize {
    var n = 0;
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 91 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

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
    if igual(t, "()") { clave = vacio(); }
    if tiene(reg.res_vistos, vista(clave)) { return; }
    poner(reg.res_vistos, vista(clave), 1);
    anadir(reg.resultados, clave);
}

// Tiene partes: se puede leer un campo o modificarlo en el sitio.
fn es_compuesto_t(t: view, structs: &mapa<str, usize>) -> bool {
    if igual(t, "str") || empieza_con(t, "bloque<") { return true; }
    if es_lista_t(t) || es_mapa_t(t) { return true; }
    if empieza_con(t, "[") { return true; }
    return tiene(structs, t);
}

// Lo que devuelve `obtener` para un mapa cuyo valor es `v`.
fn tipo_obtener(v: view, global: &I.Contexto) -> str {
    if !I.posee_con_formas(global, v) { return nuevo(v); }
    if igual(v, "str") { return nuevo("view"); }
    return $"&{v}";
}

// Registra `t` si es una lista o un mapa, lo de dentro primero. Falso si
// es algo que este hito todavia no escribe.
fn mirar_tipo(t: view, reg: mut Registro, global: &I.Contexto,
    structs: &mapa<str, usize>) -> bool {
    if contiene(t, "<") {
        let resuelto = I.nombre_resuelto(t);
        if !igual(vista(resuelto), t) {
            return mirar_tipo(vista(resuelto), reg, global, structs);
        }
    }
    if empieza_con(t, "[") {
        let pa = partes_arreglo(t);
        if largo(pa) != 2 { return false; }
        if tiene(reg.arr_vistos, t) { return true; }
        // El typedef del elemento va antes que el envoltorio del arreglo:
        // tambien cuando el elemento es una lista, mapa o bloque.
        if !mirar_tipo(vista(pa[0]), reg, global, structs) { return false; }
        poner(reg.arr_vistos, t, 1);
        anadir(reg.arreglos, nuevo(t));
        return true;
    }
    if empieza_con(t, "bloque<") {
        if tiene(reg.vistos, t) { return true; }
        poner(reg.vistos, t, 1);
        anadir(reg.bloques, nuevo(t));
        let dentro_b = nuevo(rebanar(t, 7, largo(t) - 1));
        return mirar_tipo(vista(dentro_b), reg, global, structs);
    }
    if es_bloque_o_arreglo(t) {
        // Un prestamo no registra nada, como en el original.
        if empieza_con(t, "&") { return true; }
        imprimir_error($"tcodec: el tipo `{t}`\n");
        return false;
    }
    if tiene(reg.vistos, t) { return true; }
    if es_lista_t(t) {
        let dentro = interior_lista(t);
        // Igual que el generador de referencia: lo que lleva dentro tiene que
        // registrarse antes, aunque sea un mapa o un bloque y no otra lista.
        if !mirar_tipo(vista(dentro), reg, global, structs) { return false; }
        poner(reg.vistos, t, 1);
        anadir(reg.listas, nuevo(t));
        return true;
    }
    if !es_mapa_t(t) { return true; }
    let partes = partes_mapa(t);
    if largo(partes) != 2 { return false; }
    // El nombre en C de la clave y del valor, la lista que devuelve
    // `claves`, y los resultados de `obtener` y de `obtener_mut`.
    for x en partes {
        if es_lista_t(vista(x)) || es_mapa_t(vista(x)) {
            if !mirar_tipo(vista(x), reg, global, structs) { return false; }
        }
    }
    let de_claves = $"lista<{partes[0]}>";
    if !mirar_tipo(vista(de_claves), reg, global, structs) { return false; }
    let obt = tipo_obtener(vista(partes[1]), global);
    registrar_resultado(reg, vista(obt));
    if es_compuesto_t(vista(partes[1]), structs) {
        let con_mut = $"&mut {partes[1]}";
        registrar_resultado(reg, vista(con_mut));
    }
    poner(reg.vistos, t, 1);
    anadir(reg.mapas, nuevo(t));
    return true;
}

fn mirar_bloque(n: &P.Nodo, tipos: mut I.Contexto, reg: mut Registro,
    global: &I.Contexto, structs: &mapa<str, usize>) -> bool {
    I.abrir(tipos);
    var bien = true;
    for st en n.hijos {
        let clase = vista(st.clase);
        if igual(clase, "declaracion") && largo(st.hijos) == 1 {
            let nombre = G.nombre_declarado(vista(st.texto));
            var escrito = G.tipo_escrito(vista(st.texto));
            if largo(escrito) == 0 { escrito = I.tipo_de(tipos, st.hijos[0]); }
            let t = I.sin_alias_tipo(vista(escrito));
            if bien { bien = mirar_tipo(vista(t), reg, global, structs); }
            I.declarar(tipos, vista(nombre), vista(t));
        }
        if igual(clase, "si") {
            var k = 1;
            while k < largo(st.hijos) {
                if bien {
                    bien = mirar_bloque(st.hijos[k], tipos, reg, global, structs);
                }
                k = k + 1;
            }
        }
        if igual(clase, "mientras") && largo(st.hijos) == 2 {
            if bien {
                bien = mirar_bloque(st.hijos[1], tipos, reg, global, structs);
            }
        }
    }
    I.cerrar(tipos);
    return bien;
}

fn mirar_funcion(d: &P.Nodo, tipos: mut I.Contexto, reg: mut Registro,
    global: &I.Contexto, structs: &mapa<str, usize>) -> bool {
    let r = retorno_de(d);
    if !mirar_tipo(vista(r), reg, global, structs) { return false; }
    if es_falible(d) { registrar_resultado(reg, vista(r)); }
    I.abrir(tipos);
    var bien = true;
    for h en d.hijos {
        if igual(vista(h.clase), "param") {
            let pelado = F.tipo_pelado(vista(h.texto));
            let t = I.sin_alias_tipo(vista(pelado));
            if bien { bien = mirar_tipo(vista(t), reg, global, structs); }
            let pn = F.nombre_de(vista(h.texto));
            I.declarar(tipos, vista(pn), vista(t));
        }
    }
    for h en d.hijos {
        if igual(vista(h.clase), "bloque") && bien {
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
    if empieza_con(t, "bloque<") {
        let dentro_b = nuevo(rebanar(t, 7, largo(t) - 1));
        poner_typedef(vista(dentro_b), reg, puestos, salida);
        let te_b = G.tipo_c(vista(dentro_b));
        anadir(salida, $"typedef struct {{ {te_b}* e; size_t n; }} {tc};");
        return;
    }
    if es_lista_t(t) {
        let dentro = interior_lista(t);
        poner_typedef(vista(dentro), reg, puestos, salida);
        let te = G.tipo_c(vista(dentro));
        anadir(salida, $"typedef struct {{ {te}* e; size_t length; size_t capacity; }} {tc};");
        return;
    }
    let partes = partes_mapa(t);
    for x en partes { poner_typedef(vista(x), reg, puestos, salida); }
    let tk = G.tipo_c(vista(partes[0]));
    let tv = G.tipo_c(vista(partes[1]));
    anadir(salida, $"typedef struct {{ {tk}* claves; {tv}* valores; size_t largo; size_t capacidad; }} {tc};");
}

fn ordenable(t: view) -> bool {
    if igual(t, "str") || igual(t, "bool") { return true; }
    if igual(t, "usize") || igual(t, "u8") || igual(t, "u16") { return true; }
    if igual(t, "u32") || igual(t, "u64") || igual(t, "i8") { return true; }
    if igual(t, "i16") || igual(t, "i32") || igual(t, "i64") { return true; }
    return igual(t, "f32") || igual(t, "f64");
}

fn funcion_push(t: view, salida: mut lista<str>) {
    let dentro = interior_lista(t);
    let te = G.tipo_c(vista(dentro));
    let tc = G.tipo_c(t);
    let m = G.mangle(t);
    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static void ss_push_{m}({tc}* p, {te} valor,");
    anadir(salida, nuevo("        const char* archivo, int linea)"));
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    if (p->length == p->capacity)"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        if (p->length == SIZE_MAX)"));
    anadir(salida, nuevo("            ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, nuevo("        size_t nueva = p->capacity == 0 ? 8 : p->capacity;"));
    anadir(salida, nuevo("        if (nueva < p->length + 1)"));
    anadir(salida, nuevo("        {"));
    anadir(salida, nuevo("            nueva = nueva > SIZE_MAX / 2 ? SIZE_MAX : nueva * 2;"));
    anadir(salida, nuevo("            if (nueva < p->length + 1) nueva = p->length + 1;"));
    anadir(salida, nuevo("        }"));
    anadir(salida, nuevo("        if (nueva > SIZE_MAX / sizeof(*p->e))"));
    anadir(salida, nuevo("            ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, nuevo("        void* memoria = realloc(p->e, nueva * sizeof(*p->e));"));
    anadir(salida, nuevo("        if (memoria == NULL) ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, $"        p->e = ({te}*) memoria;");
    anadir(salida, nuevo("        p->capacity = nueva;"));
    anadir(salida, nuevo("    }"));
    anadir(salida, nuevo("    p->e[p->length++] = valor;"));
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());
}

fn funcion_ordenar(t: view, salida: mut lista<str>) {
    let dentro = interior_lista(t);
    if !ordenable(vista(dentro)) { return; }
    let te = G.tipo_c(vista(dentro));
    let tc = G.tipo_c(t);
    let m = G.mangle(t);
    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static int ss_cmp_{m}(const void* a, const void* b)");
    anadir(salida, nuevo("{"));
    if igual(vista(dentro), "str") {
        anadir(salida, nuevo("    return ss_cmp((const SafeString*) a, (const SafeString*) b);"));
    } else {
        anadir(salida, $"    {te} x = *(const {te}*) a;");
        anadir(salida, $"    {te} y = *(const {te}*) b;");
        anadir(salida, nuevo("    return (x > y) - (x < y);"));
    }
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());
    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static void ss_ordenar_{m}({tc}* p)");
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    if (p->length > 1)"));
    anadir(salida, $"        qsort(p->e, p->length, sizeof(*p->e), ss_cmp_{m});");
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());
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
    for l en b.lineas { anadir(salida, copiar(l)); }
    cta.temporal = b.temporal;
    cta.bucle = b.bucle;
    cta.etiquetas = b.etiquetas;
}

// Un juego de funciones por cada `mapa<K, V>` concreto: tabla de
// direccionamiento abierto con sondeo lineal, y borrado sin lapidas.
fn funcion_mapa(t: view, global: &I.Contexto, structs: &mapa<str, usize>,
    cta: mut F.Cuenta, salida: mut lista<str>) {
    let partes = partes_mapa(t);
    let k = copiar(partes[0]);
    let v = copiar(partes[1]);
    let m = G.mangle(t);
    let nombre = G.tipo_c(t);
    let tc_k = G.tipo_c(vista(k));
    let tc_v = G.tipo_c(vista(v));
    let de_claves = $"lista<{k}>";
    let lista_k = G.tipo_c(vista(de_claves));
    let m_claves = G.mangle(vista(de_claves));
    let obt = tipo_obtener(vista(v), global);
    let res_v = G.tipo_resultado(vista(obt));
    let posee = I.posee_con_formas(global, vista(v));

    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static size_t ss_mapa_sitio_{m}(const {nombre}* p, SafeView clave)");
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    /* La capacidad es potencia de dos, asi que el resto es"));
    anadir(salida, nuevo("       una mascara. Sondeo lineal: bueno con la cache y sin"));
    anadir(salida, nuevo("       lapidas, porque en v0 no se borra. */"));
    anadir(salida, nuevo("    size_t mascara = p->capacidad - 1;"));
    anadir(salida, nuevo("    size_t i = (size_t) sv_hash(clave) & mascara;"));
    anadir(salida, nuevo("    while (p->claves[i].data != NULL)"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        if (sv_equals(ss_view(&p->claves[i]), clave)) return i;"));
    anadir(salida, nuevo("        i = (i + 1) & mascara;"));
    anadir(salida, nuevo("    }"));
    anadir(salida, nuevo("    return i;   /* celda libre: aqui iria */"));
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());

    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static void ss_mapa_crecer_{m}({nombre}* p, const char* archivo, int linea)");
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    size_t nueva = p->capacidad == 0 ? 16 : p->capacidad * 2;"));
    anadir(salida, nuevo("    if (nueva < p->capacidad) ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, $"    if (nueva > SIZE_MAX / sizeof({tc_k})");
    anadir(salida, $"        || nueva > SIZE_MAX / sizeof({tc_v}))");
    anadir(salida, nuevo("        ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, vacio());
    anadir(salida, $"    {nombre} nuevo;");
    anadir(salida, $"    nuevo.claves = ({tc_k}*) calloc(nueva, sizeof({tc_k}));");
    if posee {
        anadir(salida, $"    nuevo.valores = ({tc_v}*) calloc(nueva, sizeof({tc_v}));");
    } else {
        anadir(salida, $"    nuevo.valores = ({tc_v}*) malloc(nueva * sizeof({tc_v}));");
    }
    anadir(salida, nuevo("    if (nuevo.claves == NULL || nuevo.valores == NULL)"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        free(nuevo.claves); free(nuevo.valores);"));
    anadir(salida, nuevo("        ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, nuevo("    }"));
    anadir(salida, nuevo("    nuevo.largo = p->largo;"));
    anadir(salida, nuevo("    nuevo.capacidad = nueva;"));
    anadir(salida, vacio());
    anadir(salida, nuevo("    /* Se reubican las claves tal cual: nadie copia texto. */"));
    anadir(salida, nuevo("    for (size_t i = 0; i < p->capacidad; i++)"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        if (p->claves[i].data == NULL) continue;"));
    anadir(salida, $"        size_t j = ss_mapa_sitio_{m}(&nuevo, ss_view(&p->claves[i]));");
    anadir(salida, nuevo("        nuevo.claves[j] = p->claves[i];"));
    anadir(salida, nuevo("        nuevo.valores[j] = p->valores[i];"));
    anadir(salida, nuevo("    }"));
    anadir(salida, nuevo("    free(p->claves); free(p->valores);"));
    anadir(salida, nuevo("    *p = nuevo;"));
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());

    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static void ss_mapa_poner_{m}({nombre}* p, SafeView clave, {tc_v} valor,");
    anadir(salida, nuevo("        const char* archivo, int linea)"));
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    /* Se crece al 70% de ocupacion: por encima, el sondeo"));
    anadir(salida, nuevo("       lineal empieza a formar cadenas largas. */"));
    anadir(salida, nuevo("    if (p->capacidad == 0 || (p->largo + 1) * 10 >= p->capacidad * 7)"));
    anadir(salida, $"        ss_mapa_crecer_{m}(p, archivo, linea);");
    anadir(salida, vacio());
    anadir(salida, $"    size_t i = ss_mapa_sitio_{m}(p, clave);");
    anadir(salida, nuevo("    if (p->claves[i].data != NULL)"));
    anadir(salida, nuevo("    {"));
    if posee {
        anadir(salida, nuevo("        /* el valor viejo era nuestro */"));
        lineas_liberacion(global, "p->valores[i]", vista(v), 2, cta, salida);
    }
    anadir(salida, nuevo("        p->valores[i] = valor;   /* ya estaba: se reemplaza */"));
    anadir(salida, nuevo("        return;"));
    anadir(salida, nuevo("    }"));
    anadir(salida, nuevo("    p->claves[i] = ss_from_view(clave);"));
    anadir(salida, nuevo("    if (!ss_ok(&p->claves[i])) ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, nuevo("    p->valores[i] = valor;"));
    anadir(salida, nuevo("    p->largo++;"));
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());

    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static bool ss_mapa_tiene_{m}(const {nombre}* p, SafeView clave)");
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    if (p->capacidad == 0) return false;"));
    anadir(salida, $"    return p->claves[ss_mapa_sitio_{m}(p, clave)].data != NULL;");
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());

    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static {res_v} ss_mapa_obtener_{m}(const {nombre}* p, SafeView clave)");
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    if (p->capacidad == 0)"));
    anadir(salida, $"        return ({res_v}){{ .motivo = \"la clave no esta en el mapa\" }};");
    anadir(salida, $"    size_t i = ss_mapa_sitio_{m}(p, clave);");
    anadir(salida, nuevo("    if (p->claves[i].data == NULL)"));
    anadir(salida, $"        return ({res_v}){{ .motivo = \"la clave no esta en el mapa\" }};");
    if igual(vista(v), "str") {
        anadir(salida, $"    return ({res_v}){{ .motivo = NULL, .valor = ss_view(&p->valores[i]) }};");
    } else {
        if posee {
            anadir(salida, $"    return ({res_v}){{ .motivo = NULL, .valor = &p->valores[i] }};");
        } else {
            anadir(salida, $"    return ({res_v}){{ .motivo = NULL, .valor = p->valores[i] }};");
        }
    }
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());

    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static {lista_k} ss_mapa_claves_{m}(const {nombre}* p,");
    anadir(salida, nuevo("        const char* archivo, int linea)"));
    anadir(salida, nuevo("{"));
    anadir(salida, $"    {lista_k} salida = {{ NULL, 0, 0 }};");
    anadir(salida, nuevo("    for (size_t i = 0; i < p->capacidad; i++)"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        if (p->claves[i].data == NULL) continue;"));
    anadir(salida, $"        {tc_k} copia = ss_clone(&p->claves[i]);");
    anadir(salida, nuevo("        if (!ss_ok(&copia)) ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, $"        ss_push_{m_claves}(&salida, copia, archivo, linea);");
    anadir(salida, nuevo("    }"));
    anadir(salida, nuevo("    return salida;"));
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());

    if es_compuesto_t(vista(v), structs) {
        let con_mut = $"&mut {v}";
        let rm = G.tipo_resultado(vista(con_mut));
        anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
        anadir(salida, $"static {rm} ss_mapa_obtener_mut_{m}({nombre}* p, SafeView clave)");
        anadir(salida, nuevo("{"));
        anadir(salida, nuevo("    if (p->capacidad == 0)"));
        anadir(salida, $"        return ({rm}){{ .motivo = \"la clave no esta en el mapa\" }};");
        anadir(salida, $"    size_t i = ss_mapa_sitio_{m}(p, clave);");
        anadir(salida, nuevo("    if (p->claves[i].data == NULL)"));
        anadir(salida, $"        return ({rm}){{ .motivo = \"la clave no esta en el mapa\" }};");
        anadir(salida, $"    return ({rm}){{ .motivo = NULL, .valor = &p->valores[i] }};");
        anadir(salida, nuevo("}"));
        anadir(salida, vacio());
    }

    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static bool ss_mapa_quitar_{m}({nombre}* p, SafeView clave)");
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    if (p->capacidad == 0) return false;"));
    anadir(salida, nuevo("    size_t mascara = p->capacidad - 1;"));
    anadir(salida, $"    size_t i = ss_mapa_sitio_{m}(p, clave);");
    anadir(salida, nuevo("    if (p->claves[i].data == NULL) return false;"));
    anadir(salida, vacio());
    anadir(salida, nuevo("    ss_free(&p->claves[i]);"));
    anadir(salida, nuevo("    p->claves[i] = ss_new();"));
    if posee {
        lineas_liberacion(global, "p->valores[i]", vista(v), 1, cta, salida);
        anadir(salida, $"    memset(&p->valores[i], 0, sizeof({tc_v}));");
    }
    anadir(salida, nuevo("    p->largo--;"));
    anadir(salida, vacio());
    anadir(salida, nuevo("    /* Sin lapidas: se cierra el hueco arrastrando hacia atras"));
    anadir(salida, nuevo("       las entradas del mismo grupo que quedarian inalcanzables."));
    anadir(salida, nuevo("       Es lo que permite que la busqueda pueda parar en la"));
    anadir(salida, nuevo("       primera celda libre. */"));
    anadir(salida, nuevo("    size_t j = i;"));
    anadir(salida, nuevo("    for (;;)"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        j = (j + 1) & mascara;"));
    anadir(salida, nuevo("        if (p->claves[j].data == NULL) break;"));
    anadir(salida, nuevo("        size_t k = (size_t) sv_hash(ss_view(&p->claves[j])) & mascara;"));
    anadir(salida, nuevo("        bool mover = (i <= j) ? (k <= i || k > j)"));
    anadir(salida, nuevo("                              : (k <= i && k > j);"));
    anadir(salida, nuevo("        if (mover)"));
    anadir(salida, nuevo("        {"));
    anadir(salida, nuevo("            p->claves[i] = p->claves[j];"));
    anadir(salida, nuevo("            p->valores[i] = p->valores[j];"));
    anadir(salida, nuevo("            p->claves[j] = ss_new();"));
    anadir(salida, nuevo("            i = j;"));
    anadir(salida, nuevo("        }"));
    anadir(salida, nuevo("    }"));
    anadir(salida, nuevo("    return true;"));
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());

    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static void ss_mapa_libre_{m}({nombre}* p)");
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    for (size_t i = 0; i < p->capacidad; i++)"));
    anadir(salida, nuevo("        if (p->claves[i].data != NULL)"));
    anadir(salida, nuevo("        {"));
    anadir(salida, nuevo("            ss_free(&p->claves[i]);"));
    if posee {
        lineas_liberacion(global, "p->valores[i]", vista(v), 3, cta, salida);
    }
    anadir(salida, nuevo("        }"));
    anadir(salida, nuevo("    free(p->claves); free(p->valores);"));
    anadir(salida, nuevo("    p->claves = NULL; p->valores = NULL;"));
    anadir(salida, nuevo("    p->largo = 0; p->capacidad = 0;"));
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());
}

fn funcion_bloque(t: view, global: &I.Contexto, cta: mut F.Cuenta,
    salida: mut lista<str>) {
    let elem = nuevo(rebanar(t, 7, largo(t) - 1));
    let te = G.tipo_c(vista(elem));
    let nombre = G.tipo_c(t);
    let m = G.mangle(t);
    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static {nombre} ss_lang_bloque_nuevo_{m}(size_t n,");
    anadir(salida, nuevo("        const char* archivo, int linea)"));
    anadir(salida, nuevo("{"));
    anadir(salida, $"    {nombre} b = {{ NULL, 0 }};");
    anadir(salida, nuevo("    if (n == 0) return b;"));
    anadir(salida, $"    if (n > SIZE_MAX / sizeof({te}))");
    anadir(salida, nuevo("        ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, $"    b.e = ({te}*) calloc(n, sizeof({te}));");
    anadir(salida, nuevo("    if (b.e == NULL) ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, nuevo("    b.n = n;"));
    anadir(salida, nuevo("    return b;"));
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());
    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static void ss_lang_bloque_cambiar_{m}({nombre}* p, size_t n,");
    anadir(salida, nuevo("        const char* archivo, int linea)"));
    anadir(salida, nuevo("{"));
    anadir(salida, nuevo("    if (n == p->n) return;"));
    if I.posee_con_formas(global, vista(elem)) {
        anadir(salida, nuevo("    if (n < p->n)"));
        anadir(salida, nuevo("        for (size_t i = n; i < p->n; i++)"));
        anadir(salida, nuevo("        {"));
        lineas_liberacion(global, "p->e[i]", vista(elem), 3, cta, salida);
        anadir(salida, nuevo("        }"));
    }
    anadir(salida, nuevo("    if (n == 0)"));
    anadir(salida, nuevo("    {"));
    anadir(salida, nuevo("        free(p->e); p->e = NULL; p->n = 0; return;"));
    anadir(salida, nuevo("    }"));
    anadir(salida, $"    if (n > SIZE_MAX / sizeof({te}))");
    anadir(salida, nuevo("        ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, $"    void* memoria = realloc(p->e, n * sizeof({te}));");
    anadir(salida, nuevo("    if (memoria == NULL) ss_lang_sin_memoria_(archivo, linea);"));
    anadir(salida, $"    p->e = ({te}*) memoria;");
    anadir(salida, nuevo("    /* Lo nuevo nace a ceros, que en Tcode es un valor valido. */"));
    anadir(salida, nuevo("    if (n > p->n)"));
    anadir(salida, $"        memset(p->e + p->n, 0, (n - p->n) * sizeof({te}));");
    anadir(salida, nuevo("    p->n = n;"));
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());
}

// El tipo de mapa al que se refiere un nombre de C: `ss_mapa_poner_mapa_x`
// y `ss_mapa_x` hablan del mismo.
fn tipo_de_nombre_mapa(u: view) -> str {
    let resto = rebanar(u, 8, largo(u));
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
    while i < largo(t) {
        var j = i + largo(prefijo);
        while j < largo(t) && I.es_de_nombre(byte(t, j)) { j = j + 1; }
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
    if largo(t) == 0 { return salida; }
    var desde = 0;
    var i = 0;
    while i <= largo(t) {
        if i == largo(t) || byte(t, i) == 9 {
            anadir(salida, nuevo(rebanar(t, desde, i)));
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

fn hondura_tipo(t: view) -> usize {
    var n = 0;
    var i = 0;
    while i < largo(t) {
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
    if igual(t, "str") || !I.posee_con_formas(global, t) || tiene(vistos, t) {
        return;
    }
    poner(vistos, t, 1);
    anadir(salida, nuevo(t));
    if empieza_con(t, "bloque<") {
        let dentro_b = nuevo(rebanar(t, 7, largo(t) - 1));
        necesita_copiador(vista(dentro_b), global, st_indice, st_tipos, vistos, salida);
        return;
    }
    if es_lista_t(t) {
        let dentro = interior_lista(t);
        necesita_copiador(vista(dentro), global, st_indice, st_tipos, vistos, salida);
        return;
    }
    if es_mapa_t(t) {
        let partes = partes_mapa(t);
        if largo(partes) == 2 {
            necesita_copiador(vista(partes[1]), global, st_indice, st_tipos,
                vistos, salida);
        }
        return;
    }
    if empieza_con(t, "[") {
        let pa = partes_arreglo(t);
        if largo(pa) == 2 {
            necesita_copiador(vista(pa[0]), global, st_indice, st_tipos, vistos, salida);
        }
        return;
    }
    if tiene(st_indice, t) {
        let k = obtener(st_indice, t) sino 0;
        for c en st_tipos[k] {
            necesita_copiador(vista(c), global, st_indice, st_tipos, vistos, salida);
        }
    }
    if tiene(global.variantes, t) {
        // Lo que llevan sus formas, en orden.
        for v en I.lista_de(global.variantes, t) sino [] {
            for x en I.lista_de(global.formas, $"{t}.{v}") sino [] {
                necesita_copiador(vista(x), global, st_indice, st_tipos, vistos, salida);
            }
        }
    }
}

fn copia_de(donde: view, t: view, global: &I.Contexto) -> str {
    if !I.posee_con_formas(global, t) { return nuevo(donde); }
    if igual(t, "str") { return $"ss_clone(&{donde})"; }
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
        anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
        anadir(salida, $"static {tc} ss_copia_{m}(const {tc}* p)");
        anadir(salida, nuevo("{"));
        anadir(salida, $"    {tc} r = *p;");
        var hay: lista<usize> = [];
        var iv = 0;
        while iv < largo(en_variantes[ke]) {
            let tipos_v = partir_tab(vista(en_lleva[ke][iv]));
            var alguna = false;
            for tt en tipos_v {
                if I.posee_con_formas(global, vista(tt)) { alguna = true; }
            }
            if alguna { anadir(hay, iv); }
            iv = iv + 1;
        }
        if largo(hay) > 0 {
            anadir(salida, nuevo("    switch (p->etiqueta)"));
            anadir(salida, nuevo("    {"));
            for cual en hay {
                let vn = copiar(en_variantes[ke][cual]);
                let etq = G.etiqueta(t, vista(vn));
                anadir(salida, $"    case {etq}:");
                let tipos_v = partir_tab(vista(en_lleva[ke][cual]));
                var q = 0;
                while q < largo(tipos_v) {
                    if I.posee_con_formas(global, vista(tipos_v[q])) {
                        let origen = $"p->dato.v_{vn}._{q}";
                        let cp = copia_de(vista(origen), vista(tipos_v[q]), global);
                        anadir(salida, $"        r.dato.v_{vn}._{q} = {cp};");
                    }
                    q = q + 1;
                }
                anadir(salida, nuevo("        break;"));
            }
            anadir(salida, nuevo("    default: break;"));
            anadir(salida, nuevo("    }"));
        }
        anadir(salida, nuevo("    return r;"));
        anadir(salida, nuevo("}"));
        anadir(salida, vacio());
        return true;
    }
    if empieza_con(t, "bloque<") {
        let elem_b = nuevo(rebanar(t, 7, largo(t) - 1));
        let te_b = G.tipo_c(vista(elem_b));
        let cp_b = copia_de("p->e[i]", vista(elem_b), global);
        anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
        anadir(salida, $"static {tc} ss_copia_{m}(const {tc}* p)");
        anadir(salida, nuevo("{"));
        anadir(salida, $"    {tc} r = {{ NULL, 0 }};");
        anadir(salida, nuevo("    if (p->n == 0) return r;"));
        anadir(salida, $"    r.e = ({te_b}*) calloc(p->n, sizeof({te_b}));");
        anadir(salida, nuevo("    if (r.e == NULL) ss_lang_sin_memoria_(__FILE__, __LINE__);"));
        anadir(salida, nuevo("    r.n = p->n;"));
        anadir(salida, nuevo("    for (size_t i = 0; i < p->n; i++)"));
        anadir(salida, $"        r.e[i] = {cp_b};");
        anadir(salida, nuevo("    return r;"));
        anadir(salida, nuevo("}"));
        anadir(salida, vacio());
        return true;
    }
    if es_lista_t(t) {
        let elem = interior_lista(t);
        let te = G.tipo_c(vista(elem));
        let cp = copia_de("p->e[i]", vista(elem), global);
        anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
        anadir(salida, $"static {tc} ss_copia_{m}(const {tc}* p)");
        anadir(salida, nuevo("{"));
        anadir(salida, $"    {tc} r = {{ NULL, 0, 0 }};");
        anadir(salida, nuevo("    if (p->length == 0) return r;"));
        anadir(salida, $"    r.e = ({te}*) calloc(p->length, sizeof({te}));");
        anadir(salida, nuevo("    if (r.e == NULL) ss_lang_sin_memoria_(__FILE__, __LINE__);"));
        anadir(salida, nuevo("    r.capacity = p->length;"));
        anadir(salida, nuevo("    for (size_t i = 0; i < p->length; i++)"));
        anadir(salida, $"        r.e[i] = {cp};");
        anadir(salida, nuevo("    r.length = p->length;"));
        anadir(salida, nuevo("    return r;"));
        anadir(salida, nuevo("}"));
        anadir(salida, vacio());
        return true;
    }
    if es_mapa_t(t) {
        let partes = partes_mapa(t);
        if largo(partes) != 2 { return false; }
        let tck = G.tipo_c(vista(partes[0]));
        let tcv = G.tipo_c(vista(partes[1]));
        let cp = copia_de("p->valores[i]", vista(partes[1]), global);
        anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
        anadir(salida, $"static {tc} ss_copia_{m}(const {tc}* p)");
        anadir(salida, nuevo("{"));
        anadir(salida, $"    {tc} r = {{ NULL, NULL, 0, 0 }};");
        anadir(salida, nuevo("    if (p->capacidad == 0) return r;"));
        anadir(salida, $"    r.claves = ({tck}*) calloc(p->capacidad, sizeof({tck}));");
        anadir(salida, $"    r.valores = ({tcv}*) calloc(p->capacidad, sizeof({tcv}));");
        anadir(salida, nuevo("    if (r.claves == NULL || r.valores == NULL)"));
        anadir(salida, nuevo("        ss_lang_sin_memoria_(__FILE__, __LINE__);"));
        anadir(salida, nuevo("    r.capacidad = p->capacidad;"));
        anadir(salida, nuevo("    r.largo = p->largo;"));
        anadir(salida, nuevo("    for (size_t i = 0; i < p->capacidad; i++)"));
        anadir(salida, nuevo("    {"));
        anadir(salida, nuevo("        if (p->claves[i].data == NULL) continue;"));
        anadir(salida, nuevo("        r.claves[i] = ss_clone(&p->claves[i]);"));
        anadir(salida, $"        r.valores[i] = {cp};");
        anadir(salida, nuevo("    }"));
        anadir(salida, nuevo("    return r;"));
        anadir(salida, nuevo("}"));
        anadir(salida, vacio());
        return true;
    }
    if empieza_con(t, "[") {
        let pa = partes_arreglo(t);
        if largo(pa) != 2 { return false; }
        let cp = copia_de("p->e[i]", vista(pa[0]), global);
        anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
        anadir(salida, $"static {tc} ss_copia_{m}(const {tc}* p)");
        anadir(salida, nuevo("{"));
        anadir(salida, $"    {tc} r;");
        anadir(salida, $"    for (size_t i = 0; i < {pa[1]}; i++)");
        anadir(salida, $"        r.e[i] = {cp};");
        anadir(salida, nuevo("    return r;"));
        anadir(salida, nuevo("}"));
        anadir(salida, vacio());
        return true;
    }
    if !tiene(st_indice, t) { return false; }
    let k = obtener(st_indice, t) sino 0;
    anadir(salida, nuevo("SS_LANG_QUIZA_SIN_USAR"));
    anadir(salida, $"static {tc} ss_copia_{m}(const {tc}* p)");
    anadir(salida, nuevo("{"));
    anadir(salida, $"    {tc} r;");
    var j = 0;
    while j < largo(st_campos[k]) {
        let donde = $"p->{st_campos[k][j]}";
        let cp = copia_de(vista(donde), vista(st_tipos[k][j]), global);
        anadir(salida, $"    r.{st_campos[k][j]} = {cp};");
        j = j + 1;
    }
    anadir(salida, nuevo("    return r;"));
    anadir(salida, nuevo("}"));
    anadir(salida, vacio());
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

// Lo de dentro de `Base<a, b>`, cortado por las comas de fuera.
fn partir_args(t: view) -> lista<str> {
    var salida: lista<str> = [];
    var ini = 0;
    while ini < largo(t) && byte(t, ini) != 60 { ini = ini + 1; }
    if ini + 1 >= largo(t) { return salida; }
    let dentro = rebanar(t, ini + 1, largo(t) - 1);
    var hondura = 0;
    var desde = 0;
    var i = 0;
    while i <= largo(dentro) {
        var corta = i == largo(dentro);
        if !corta {
            let b = byte(dentro, i);
            if b == 60 || b == 91 || b == 40 { hondura = hondura + 1; }
            if (b == 62 || b == 93 || b == 41) && hondura > 0 { hondura = hondura - 1; }
            corta = b == 44 && hondura == 0;
        }
        if corta {
            var j = desde;
            while j < i && byte(dentro, j) == 32 { j = j + 1; }
            anadir(salida, nuevo(rebanar(dentro, j, i)));
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
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
    if empieza_con(t, "&mut ") {
        let d = resolver_reg(rebanar(t, 5, largo(t)), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
        return $"&mut {d}";
    }
    if empieza_con(t, "&") {
        let d = resolver_reg(rebanar(t, 1, largo(t)), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
        return $"&{d}";
    }
    if es_lista_t(t) {
        let e = interior_lista(t);
        let d = resolver_reg(vista(e), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
        return $"lista<{d}>";
    }
    if empieza_con(t, "bloque<") {
        let e = nuevo(rebanar(t, 7, largo(t) - 1));
        let d = resolver_reg(vista(e), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
        return $"bloque<{d}>";
    }
    if es_mapa_t(t) {
        let partes = partes_mapa(t);
        if largo(partes) != 2 { return nuevo(t); }
        let k = resolver_reg(vista(partes[0]), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
        let v = resolver_reg(vista(partes[1]), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
        return $"mapa<{k}, {v}>";
    }
    if empieza_con(t, "[") {
        let pa = partes_arreglo(t);
        if largo(pa) != 2 { return nuevo(t); }
        let d = resolver_reg(vista(pa[0]), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
        return $"[{d}; {pa[1]}]";
    }
    if !I.es_aplicacion(t) { return nuevo(t); }
    let base = I.base_de_aplicacion(t);
    if !tiene(plantillas_st, vista(base)) { return nuevo(t); }
    let kp = obtener(plantillas_st, vista(base)) sino 0;
    let dados = partir_args(t);
    if largo(dados) != largo(p_params[kp]) { return nuevo(t); }
    var ligaduras: mapa<str, str> = [];
    var nombre = copiar(base);
    empujar(nombre, "__");
    var i = 0;
    while i < largo(dados) {
        let d = resolver_reg(vista(dados[i]), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
        if i > 0 { empujar(nombre, "_"); }
        let limpio = G.sanear(vista(d));
        empujar(nombre, vista(limpio));
        poner(ligaduras, vista(p_params[kp][i]), d);
        i = i + 1;
    }
    if tiene(st_indice, vista(nombre)) || tiene(en_curso, vista(nombre)) { return nombre; }
    poner(en_curso, vista(nombre), 1);
    var tipos_c: lista<str> = [];
    let crudos = copiar(p_tipos[kp]);
    for x en crudos {
        let puesto = I.sustituir(vista(x), ligaduras);
        anadir(tipos_c, resolver_reg(vista(puesto), plantillas_st, p_params, p_campos, p_tipos, en_curso,
                st_nombres, st_indice, st_campos, st_tipos, global));
    }
    poner(st_indice, vista(nombre), largo(st_nombres));
    anadir(st_nombres, copiar(nombre));
    anadir(st_campos, copiar(p_campos[kp]));
    poner(global.campos, vista(nombre), copiar(tipos_c));
    poner(global.nombres, vista(nombre), copiar(p_campos[kp]));
    anadir(st_tipos, tipos_c);
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
    let clase = vista(n.clase);
    if igual(clase, "param") {
        let tp = F.tipo_pelado(vista(n.texto));
        let t = I.sin_alias_tipo(vista(tp));
        let _r = resolver_reg(vista(t), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
    }
    if igual(clase, "retorno_tipo") || igual(clase, "literal_struct") {
        let t = I.sin_alias_tipo(vista(n.texto));
        let _r = resolver_reg(vista(t), plantillas_st, p_params, p_campos, p_tipos, en_curso,
            st_nombres, st_indice, st_campos, st_tipos, global);
    }
    if igual(clase, "declaracion") {
        let escrito = G.tipo_escrito(vista(n.texto));
        if largo(escrito) > 0 {
            let t = I.sin_alias_tipo(vista(escrito));
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
        if igual(vista(h.clase), "retorno_tipo") { resolver_en_nodo(h, plantillas_st, p_params, p_campos, p_tipos, en_curso,
                st_nombres, st_indice, st_campos, st_tipos, global); }
    }
    for h en d.hijos {
        if igual(vista(h.clase), "param") { resolver_en_nodo(h, plantillas_st, p_params, p_campos, p_tipos, en_curso,
                st_nombres, st_indice, st_campos, st_tipos, global); }
    }
    for h en d.hijos {
        if igual(vista(h.clase), "bloque") { resolver_en_nodo(h, plantillas_st, p_params, p_campos, p_tipos, en_curso,
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
    if igual(retorno, "cadena_c") { tc = nuevo("const char*"); }
    if largo(tipos_p) == 0 { return $"{tc} {nombre}(void)"; }
    var partes = vacio();
    var i = 0;
    while i < largo(tipos_p) {
        var t = G.tipo_c(vista(tipos_p[i]));
        if igual(vista(tipos_p[i]), "str") { t = nuevo("const char*"); }
        if i > 0 { empujar(partes, ", "); }
        let pieza = $"{t} {nombres_p[i]}";
        empujar(partes, vista(pieza));
        i = i + 1;
    }
    return $"{tc} {nombre}({partes})";
}

// Cada linea de un texto, sin el salto final.
fn anadir_lineas(texto_c: view, salida: mut lista<str>) {
    var fin = largo(texto_c);
    if fin > 0 && byte(texto_c, fin - 1) == 10 { fin = fin - 1; }
    var desde = 0;
    var i = 0;
    while i <= fin {
        if i == fin || byte(texto_c, i) == 10 {
            anadir(salida, nuevo(rebanar(texto_c, desde, i)));
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
    while i < largo(n.hijos) {
        if igual(vista(n.hijos[i].clase), "cierre") {
            let clave = $"{dueno}#{cuenta}";
            cuenta = cuenta + 1;
            if tiene(numeracion, vista(clave)) {
                let numero = obtener(numeracion, vista(clave)) sino 0;
                var queda = P.rama("cierre", n.hijos[i].linea);
                queda.texto = $"Cierre_{numero}";
                for h en n.hijos[i].hijos {
                    if igual(vista(h.clase), "captura") { anadir(queda.hijos, copiar(h)); }
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
    if igual(vista(n.clase), "cierre") { return true; }
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
    while largo(pieza) > 0 {
        let corte = buscar_desde(vista(pieza), "=", 0);
        anadir(nombres, nuevo(rebanar(vista(pieza), 0, corte)));
        anadir(tipos, nuevo(rebanar(vista(pieza), corte + 1, largo(vista(pieza)))));
        k = k + 1;
        pieza = campo_pedido(p, k);
    }
    if largo(nombres) == 0 {
        anadir(nombres, nuevo("ss_vacio"));
        anadir(tipos, nuevo("u8"));
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
    anadir(salida, nuevo(t));
    for x en T.partes_de_funcion(t) {
        let dentro = T.apuntado_si(vista(x));
        apuntar_tipo_funcion(vista(dentro), salida);
    }
}

fn tipos_funcion_de(d: &P.Nodo, salida: mut lista<str>) {
    for h en d.hijos {
        if igual(vista(h.clase), "param") {
            let tp = F.tipo_pelado(vista(h.texto));
            apuntar_tipo_funcion(vista(tp), salida);
        }
        if igual(vista(h.clase), "retorno_tipo") {
            apuntar_tipo_funcion(vista(h.texto), salida);
        }
    }
}

// `nombre` aparece en `l` como palabra entera: `ss_fn_x_a_y` no es
// `ss_fn_x_a_y_z`.
fn contiene_nombre(l: view, nombre: view) -> bool {
    var i = buscar_desde(l, nombre, 0);
    while i < largo(l) {
        let fin = i + largo(nombre);
        let antes_ok = i == 0 || !es_de_nombre_c(byte(l, i - 1));
        let despues_ok = fin >= largo(l) || !es_de_nombre_c(byte(l, fin));
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
    while i <= largo(p) {
        if i == largo(p) || byte(p, i) == 9 {
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
    while largo(pieza) > 0 {
        let corte = buscar_desde(vista(pieza), "=", 0);
        let tp = nuevo(rebanar(vista(pieza), 0, corte));
        let puesto = nuevo(rebanar(vista(pieza), corte + 1, largo(vista(pieza))));
        poner(salida, vista(tp), puesto);
        k = k + 1;
        pieza = campo_pedido(p, k);
    }
    return salida;
}

// Los nodos cuyo texto lleva tipos escritos.
fn lleva_tipo(clase: view) -> bool {
    if igual(clase, "param") || igual(clase, "retorno_tipo") { return true; }
    if igual(clase, "declaracion") || igual(clase, "conversion") { return true; }
    return igual(clase, "literal_struct") || igual(clase, "cierre");
}

fn copiar_sustituido(n: &P.Nodo, lig: &mapa<str, str>) -> P.Nodo {
    var r = P.rama(vista(n.clase), n.linea);
    if lleva_tipo(vista(n.clase)) {
        r.texto = I.sustituir(vista(n.texto), lig);
    } else {
        r.texto = copiar(n.texto);
    }
    for h en n.hijos {
        if igual(vista(h.clase), "tipo_param") { continue; }
        anadir(r.hijos, copiar_sustituido(h, lig));
    }
    return r;
}

// La copia de una generica con los tipos de un pedido.
fn nodo_instancia(p: view, arboles: &lista<P.Nodo>,
    plantillas: &mapa<str, usize>, numeracion: &mapa<str, usize>) -> P.Nodo {
    let plantilla = campo_pedido(p, 0);
    let en_c = campo_pedido(p, 1);
    let lig = ligaduras_de(p);
    let im = obtener(plantillas, vista(plantilla)) sino 0;
    var r = P.rama("vacio", 0);
    for d en arboles[im].hijos {
        if igual(vista(d.clase), "fn") && igual(vista(d.texto), vista(plantilla)) {
            r = copiar_sustituido(d, lig);
            r.texto = copiar(en_c);
            break;
        }
    }
    // Las clausuras de esta copia son suyas: `plantilla|T1|T2`, como las
    // llama el comprobador.
    var dueno = copiar(plantilla);
    var k = 2;
    var pieza = campo_pedido(p, k);
    while largo(pieza) > 0 {
        let corte = buscar_desde(vista(pieza), "=", 0);
        empujar(dueno, "|");
        empujar(dueno, rebanar(vista(pieza), corte + 1, largo(pieza)));
        k = k + 1;
        pieza = campo_pedido(p, k);
    }
    var cuenta: usize = 0;
    numerar_cierres(r, vista(dueno), numeracion, cuenta);
    return r;
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
        let en_c = campo_pedido(vista(p), 1);
        if tiene(vistos, vista(en_c)) { continue; }
        poner(vistos, vista(en_c), 1);
        anadir(creados, copiar(p));
        let plantilla = campo_pedido(vista(p), 0);
        if largo(plantilla) == 0 {
            // Una clausura: su struct existe desde que se crea, y su funcion
            // se apunta antes de comprobar su cuerpo, al reves que una copia.
            if !tiene(cierres.indice, vista(en_c)) {
                imprimir_error($"tcodec: `{en_c}` no es una clausura conocida\n");
                return false;
            }
            let k = obtener(cierres.indice, vista(en_c)) sino 0;
            var cn: lista<str> = [];
            var ct: lista<str> = [];
            campos_de_cierre(vista(p), cn, ct);
            let st = struct_de_cierre(vista(en_c));
            poner(global.campos, vista(st), copiar(ct));
            poner(global.nombres, vista(st), copiar(cn));
            var kc = 0;
            while kc < largo(contextos) {
                poner(contextos[kc].campos, vista(st), copiar(ct));
                poner(contextos[kc].nombres, vista(st), copiar(cn));
                kc = kc + 1;
            }
            anadir(orden, copiar(p));
            let de = cierres.modulo[k];
            var borrador_c = F.cuenta_nueva();
            borrador_c.sacados = copiar(cierres.sacados);
            let lineas_c = F.generar_funcion(cierres.fns[k], contextos[de],
                vista(modulos[de]), borrador_c);
            if largo(lineas_c) == 0 {
                imprimir_error($"tcodec: no se escribir la clausura `{en_c}`\n");
                return false;
            }
            if !descubrir(borrador_c.instancias, arboles, contextos, modulos,
                plantillas, vistos, orden, creados, cierres, global) {
                return false;
            }
            continue;
        }
        if !tiene(plantillas, vista(plantilla)) {
            imprimir_error($"tcodec: `{plantilla}` no es una generica conocida\n");
            return false;
        }
        let de = obtener(plantillas, vista(plantilla)) sino 0;
        let copia = nodo_instancia(vista(p), arboles, plantillas, cierres.numeracion);
        var borrador = F.cuenta_nueva();
        borrador.sacados = copiar(cierres.sacados);
        let lineas = F.generar_funcion(copia, contextos[de], vista(modulos[de]), borrador);
        if largo(lineas) == 0 {
            imprimir_error($"tcodec: no se escribir la copia `{en_c}`\n");
            return false;
        }
        if !descubrir(borrador.instancias, arboles, contextos, modulos, plantillas,
            vistos, orden, creados, cierres, global) {
            return false;
        }
        anadir(orden, copiar(p));
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
    if largo(lineas) == 0 {
        imprimir_error($"tcodec: no se escribir `{d.texto}` entera\n");
        return false;
    }
    if !igual(vista(d.texto), "main") {
        for l en lineas {
            if !empieza_con(vista(l), "#line") {
                var p = copiar(l);
                empujar(p, ";");
                anadir(protos, p);
                break;
            }
        }
    }
    for l en lineas {
        let limpia = sin_cadenas(vista(l));
        if necesita_lo_que_falta(vista(limpia)) {
            imprimir_error($"tcodec: `{d.texto}` necesita algo que falta: {l}\n");
            return false;
        }
        apuntar_tras(vista(limpia), "ss_lang_suma_", anchos);
        apuntar_tras(vista(limpia), "ss_lang_resta_", anchos);
        apuntar_tras(vista(limpia), "ss_lang_mul_", anchos);
        apuntar_tras(vista(limpia), "ss_lang_abs_", anchos);
        apuntar_tras(vista(limpia), "ss_lang_neg_", anchos);
        apuntar_tras(vista(limpia), "ss_lang_div_", anchos);
        apuntar_tras(vista(limpia), "ss_lang_mod_", anchos);
        apuntar_tras(vista(limpia), "ss_lang_desp_izq_", anchos);
        apuntar_tras(vista(limpia), "ss_lang_desp_der_", anchos);
        apuntar_tras(vista(limpia), "ss_lang_env_", anchos);
        apuntar_tras(vista(limpia), "ss_lang_fin_", decimales);
        apuntar_tras(vista(limpia), "ss_lang_conv_", conversiones);
        anadir(cuerpos, copiar(l));
    }
    anadir(cuerpos, vacio());
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
    while i < largo(t) {
        if byte(t, i) == 39 { empujar(r, "'\\''"); }
        else { empujar(r, rebanar(t, i, i + 1)); }
        i = i + 1;
    }
    empujar(r, "'");
    return r;
}

// `a/b/c.t` -> `a/b/c`: sin la extension, si la hay en el ultimo trozo.
fn sin_extension(ruta: view) -> str {
    var punto = largo(ruta);
    var i = largo(ruta);
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
    if punto < largo(ruta) && punto > 0 && byte(ruta, punto - 1) == 47 {
        return nuevo(ruta);
    }
    if punto == 0 { return nuevo(ruta); }
    return nuevo(rebanar(ruta, 0, punto));
}

fn extension(ruta: view) -> str {
    let sin = sin_extension(ruta);
    return nuevo(rebanar(ruta, largo(sin), largo(ruta)));
}

fn nombre_suelto(ruta: view) -> str {
    var i = largo(ruta);
    while i > 0 {
        if byte(ruta, i - 1) == 47 { break; }
        i = i - 1;
    }
    return nuevo(rebanar(ruta, i, largo(ruta)));
}

fn directorio_de(ruta: view) -> str {
    var i = largo(ruta);
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
    if largo(destino) == 0 { return false; }
    let temporal = tcodec_temporal_junto(copiar(destino));
    if largo(temporal) == 0 { return false; }
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
    if largo(base) == 0 { base = sin_extension(fuente); }

    // Con --emitir-c el C es el producto, y va junto al fuente. Un `.c` que
    // no escribio Tcode no se pisa.
    if igual(modo, "emitir") {
        let ruta_c = $"{base}.c";
        if tcodec_es_archivo(copiar(ruta_c)) == 1 {
            let previo = leer_archivo(vista(ruta_c)) sino vacio();
            let marca = "/* Generado por el compilador de Tcode. No editar a mano. */";
            var principio = vista(previo);
            if largo(principio) > 200 { principio = rebanar(principio, 0, 200); }
            if !contiene(principio, marca) {
                imprimir_error($"tcodec: {ruta_c} ya existe y no lo genero tcode, asi que no lo piso. Usa -o para elegir otro nombre.\n");
                return 2;
            }
        }
        if !escribir_de_una_vez(vista(ruta_c), todo, false) {
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
    let ext = extension(vista(base));
    if igual(vista(ext), ".t") {
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
    while k < largo(ext_cabeceras) {
        let cab = vista(ext_cabeceras[k]);
        if termina_con(cab, ".c") {
            let dir = directorio_de(vista(ext_modulos[k]));
            var junto = nuevo(cab);
            if largo(dir) > 0 { junto = $"{dir}/{cab}"; }
            if !esta_en(acompanan, vista(junto)) && !esta_en(faltan, vista(junto)) {
                if tcodec_es_archivo(copiar(junto)) == 1 { anadir(acompanan, junto); }
                else { anadir(faltan, junto); }
            }
        }
        k = k + 1;
    }
    if largo(faltan) > 0 {
        for x en faltan {
            imprimir_error($"tcodec: `externo` pide `{x}` y ese archivo no esta.\n");
        }
        return 2;
    }

    let tmp = tcodec_directorio_temporal();
    if largo(tmp) == 0 {
        imprimir_error("tcodec: no se pudo crear un directorio temporal\n");
        return 2;
    }
    let nombre_c = nombre_suelto(vista(base));
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
    if largo(destino_bin) > 0 { salida_tmp = tcodec_temporal_junto(copiar(destino_bin)); }
    if largo(salida_tmp) == 0 {
        imprimir_error($"tcodec: no se pudo preparar la salida `{base}`\n");
        tcodec_borrar(copiar(ruta_c));
        tcodec_borrar(copiar(tmp));
        return 2;
    }

    var orden = para_la_shell(cc);
    let piezas_fijas = $" -std=c17 -O{nivel} -Wall -Wextra ";
    empujar(orden, vista(piezas_fijas));
    let incluir = $"-I{raiz}/runtime";
    empujar(orden, para_la_shell(vista(incluir)));
    empujar(orden, " ");
    empujar(orden, para_la_shell(vista(ruta_c)));
    empujar(orden, " ");
    let safestr = $"{raiz}/runtime/safestr.c";
    empujar(orden, para_la_shell(vista(safestr)));
    for x en acompanan {
        empujar(orden, " ");
        empujar(orden, para_la_shell(vista(x)));
    }
    empujar(orden, " -o ");
    empujar(orden, para_la_shell(vista(salida_tmp)));
    // `raiz`, `piso` y compania viven en libm.
    empujar(orden, " -lm 2> ");
    empujar(orden, para_la_shell(vista(ruta_err)));

    let rc = tcodec_ejecutar(orden);
    let dijo = leer_archivo(vista(ruta_err)) sino vacio();
    tcodec_borrar(copiar(ruta_c));
    tcodec_borrar(copiar(ruta_err));
    tcodec_borrar(copiar(tmp));
    if rc != 0 {
        tcodec_borrar(copiar(salida_tmp));
        if largo(ext_cabeceras) > 0 {
            imprimir_error("tcodec: el C generado no compilo. Con bloques `externo` de por medio, lo mas probable es que una firma no coincida con la de C.\n");
        } else {
            imprimir_error("tcodec: el C generado no compilo. Es un fallo del compilador, no de tu programa.\n");
        }
        imprimir_error($"{dijo}\n");
        return 1;
    }
    if largo(recortar(vista(dijo))) > 0 { imprimir_error($"{dijo}\n"); }
    if tcodec_instalar(copiar(salida_tmp), copiar(destino_bin), 1) != 0 {
        tcodec_borrar(copiar(salida_tmp));
        imprimir_error($"tcodec: no se pudo instalar la salida `{base}`\n");
        return 2;
    }
    imprimir($"{base}\n");
    return 0;
}

fn main() -> usize ! {
    // Antes que nada, pila de sobra: el analisis es recursivo.
    let _pila = tcodec_pila_honda();
    // Las mismas opciones que `tcode`, y una mas para ver el C sin escribir
    // ningun archivo, que es lo que usan la suite y el punto fijo.
    var fuente = vacio();
    var salida = vacio();
    var nivel = nuevo("2");
    var cc = variable_entorno("CC") sino nuevo("cc");
    var modo = nuevo("binario");
    var sin_avisos = false;
    var escribir_en_su_sitio = false;
    var avisos_como_errores = false;
    var ia = 1;
    while ia < n_argumentos() {
        let a = argumento(ia);
        ia = ia + 1;
        if igual(a, "-o") || igual(a, "--cc") {
            if ia >= n_argumentos() {
                imprimir_error($"tcodec: `{a}` necesita un valor detras\n");
                return 2;
            }
            if igual(a, "-o") { salida = nuevo(argumento(ia)); }
            else { cc = nuevo(argumento(ia)); }
            ia = ia + 1;
        } else if empieza_con(a, "-O") {
            nivel = nuevo(rebanar(a, 2, largo(a)));
            if largo(nivel) == 0 && ia < n_argumentos() {
                nivel = nuevo(argumento(ia));
                ia = ia + 1;
            }
            let nv = vista(nivel);
            if !igual(nv, "0") && !igual(nv, "1") && !igual(nv, "2") && !igual(nv, "3")
            && !igual(nv, "s") {
                imprimir_error("tcodec: -O acepta 0, 1, 2, 3 o s\n");
                return 2;
            }
        } else if igual(a, "--emitir-c") {
            modo = nuevo("emitir");
        } else if igual(a, "--mostrar-c") {
            modo = nuevo("mostrar");
        } else if igual(a, "--solo-comprobar") {
            modo = nuevo("comprobar");
        } else if igual(a, "--explicar") {
            modo = nuevo("explicar");
        } else if igual(a, "--formatear") {
            modo = nuevo("formatear");
        } else if igual(a, "--escribir") {
            escribir_en_su_sitio = true;
        } else if igual(a, "--sin-avisos") {
            sin_avisos = true;
        } else if igual(a, "--avisos-como-errores") {
            avisos_como_errores = true;
        } else if empieza_con(a, "-") {
            imprimir_error($"tcodec: no conozco la opcion `{a}`\n");
            return 2;
        } else if largo(fuente) > 0 {
            imprimir_error("tcodec: un archivo cada vez\n");
            return 2;
        } else {
            fuente = nuevo(a);
        }
    }
    if largo(fuente) == 0 {
        imprimir_error($"uso: {argumento(0)} <archivo.t> [-o salida] [-O0..3] [--cc cc] [--emitir-c] [--mostrar-c] [--solo-comprobar] [--sin-avisos] [--avisos-como-errores] [--formatear [--escribir]] [--explicar]\n");
        return 2;
    }
    if tcodec_es_archivo(copiar(fuente)) == 0 {
        imprimir_error($"tcodec: no encuentro {fuente}\n");
        return 2;
    }
    // Un estilo y es este: sin opciones, como `gofmt`.
    if igual(vista(modo), "formatear") {
        let original = leer_archivo(vista(fuente)) sino vacio();
        var error_f = vacio();
        let salida_f = FMT.formatear(vista(original), vista(fuente), error_f) sino vacio();
        if largo(error_f) > 0 {
            imprimir_error($"error: {error_f}\n");
            return 1;
        }
        if !escribir_en_su_sitio {
            imprimir(salida_f);
            return 0;
        }
        if !igual(vista(salida_f), vista(original)) {
            if !escribir_de_una_vez(vista(fuente), vista(salida_f), false) {
                imprimir_error($"tcodec: no se pudo escribir `{fuente}`\n");
                return 2;
            }
            imprimir($"formateado {fuente}\n");
        }
        return 0;
    }

    let raiz = variable_entorno("TCODE_RAIZ") sino nuevo(".");
    let principal = F.normalizar(vista(fuente));
    var modulos: lista<str> = [];
    var pila: lista<str> = [];
    var error_carga = vacio();
    if !visitar(vista(principal), vista(raiz), modulos, pila, error_carga, "", 0) {
        imprimir_error($"error: {error_carga}\n");
        return 1;
    }

    // Pase 1: cada modulo con su propio contexto —los nombres se resuelven
    // por archivo, como en el cargador—, y uno de todo el programa para saber
    // que struct posee memoria y que nombre se repite entre modulos.
    var global = I.contexto();
    var arboles: lista<P.Nodo> = [];
    var contextos: lista<I.Contexto> = [];
    var st_nombres: lista<str> = [];
    var st_campos: lista<lista<str>> = [];
    var st_tipos: lista<lista<str>> = [];
    var st_indice: mapa<str, usize> = [];
    // Los structs genericos: sus parametros de tipo, y sus campos escritos.
    var stp_nombres: lista<str> = [];
    var stp_indice: mapa<str, usize> = [];
    var stp_params: lista<lista<str>> = [];
    var stp_campos: lista<lista<str>> = [];
    var stp_tipos: lista<lista<str>> = [];
    // Las funciones de los bloques `externo`: de que cabecera salen y su
    // prototipo en C.
    var ext_cabeceras: lista<str> = [];
    // El modulo de cada una: un `externo "algo.c"` va junto al archivo que
    // lo pide, y se compila y se enlaza con el programa.
    var ext_modulos: lista<str> = [];
    var ext_protos: lista<str> = [];
    // Los enums: cada variante, y lo que lleva cada una como `T1\tT2`.
    var en_nombres: lista<str> = [];
    var en_indice: mapa<str, usize> = [];
    var en_variantes: lista<lista<str>> = [];
    var en_lleva: lista<lista<str>> = [];
    // Cada generica, con el indice del modulo que la declara.
    var plantillas: mapa<str, usize> = [];
    var previos_st: mapa<str, usize> = [];
    var previos_en: mapa<str, usize> = [];
    for m en modulos {
        var tipos = I.contexto();
        var error_m = vacio();
        let arbol = F.preparar_con_error(vista(m), tipos, error_m, previos_st, previos_en)
        sino P.rama("vacio", 0);
        if largo(error_m) > 0 {
            // Como el cargador de Python: el primer error y nada mas.
            imprimir_error($"error: {error_m}\n");
            return 1;
        }
        if igual(vista(arbol.clase), "vacio") {
            imprimir_error($"tcodec: no se pudo leer `{m}`\n");
            return 1;
        }
        // Lo que este declara lo ven los siguientes al leerse, como en el
        // cargador: un enum tambien es un nombre de tipo.
        for d en arbol.hijos {
            if igual(vista(d.clase), "struct") || igual(vista(d.clase), "enum") {
                poner(previos_st, vista(d.texto), 1);
            }
            if igual(vista(d.clase), "enum") { poner(previos_en, vista(d.texto), 1); }
        }
        F.recoger_firmas(arbol, global);
        for d en arbol.hijos {
            let clase = vista(d.clase);
            if igual(clase, "usar") || igual(clase, "alias") { continue; }
            if igual(clase, "fn") {
                if F.es_generica(d) {
                    poner(plantillas, vista(d.texto), largo(arboles));
                    continue;
                }
                if igual(vista(d.texto), "main") && !igual(vista(m), vista(principal)) {
                    return rechazo("un `main` en un modulo");
                }
                continue;
            }
            if igual(clase, "struct") {
                if tiene_tipo_param(d) {
                    if tiene(stp_indice, vista(d.texto)) {
                        return rechazo("un struct generico repetido entre modulos");
                    }
                    var tps: lista<str> = [];
                    var cs: lista<str> = [];
                    var ts: lista<str> = [];
                    for h en d.hijos {
                        if igual(vista(h.clase), "tipo_param") { anadir(tps, nuevo(vista(h.texto))); }
                        if igual(vista(h.clase), "campo_def") {
                            anadir(cs, F.nombre_de(vista(h.texto)));
                            let tp = F.tipo_pelado(vista(h.texto));
                            anadir(ts, I.sin_alias_tipo(vista(tp)));
                        }
                    }
                    poner(stp_indice, vista(d.texto), largo(stp_nombres));
                    anadir(stp_nombres, nuevo(vista(d.texto)));
                    anadir(stp_params, tps);
                    anadir(stp_campos, cs);
                    anadir(stp_tipos, ts);
                    continue;
                }
                if tiene(st_indice, vista(d.texto)) {
                    return rechazo("un struct repetido entre modulos");
                }
                var campos: lista<str> = [];
                var tipos_campo: lista<str> = [];
                for h en d.hijos {
                    if igual(vista(h.clase), "campo_def") {
                        let tp = F.tipo_pelado(vista(h.texto));
                        let t = I.sin_alias_tipo(vista(tp));
                        anadir(campos, F.nombre_de(vista(h.texto)));
                        anadir(tipos_campo, t);
                    }
                }
                poner(st_indice, vista(d.texto), largo(st_nombres));
                anadir(st_nombres, nuevo(vista(d.texto)));
                anadir(st_campos, campos);
                anadir(st_tipos, tipos_campo);
                continue;
            }
            if igual(clase, "externo") {
                for f en d.hijos {
                    if !igual(vista(f.clase), "fn") { continue; }
                    var ps: lista<str> = [];
                    var pn: lista<str> = [];
                    var ret = vacio();
                    for h en f.hijos {
                        if igual(vista(h.clase), "param") {
                            let tp = F.tipo_pelado(vista(h.texto));
                            anadir(ps, I.sin_alias_tipo(vista(tp)));
                            anadir(pn, F.nombre_de(vista(h.texto)));
                        }
                        if igual(vista(h.clase), "retorno_tipo") {
                            ret = nuevo(vista(h.texto));
                        }
                    }
                    anadir(ext_cabeceras, nuevo(vista(d.texto)));
                    anadir(ext_modulos, copiar(m));
                    anadir(ext_protos, prototipo_externo(vista(f.texto), ps, pn, vista(ret)));
                }
                continue;
            }
            if igual(clase, "enum") {
                if tiene(en_indice, vista(d.texto)) || tiene(st_indice, vista(d.texto)) {
                    return rechazo("un enum repetido entre modulos");
                }
                var vs: lista<str> = [];
                var ls: lista<str> = [];
                for h en d.hijos {
                    if !igual(vista(h.clase), "variante") { continue; }
                    anadir(vs, nuevo(vista(h.texto)));
                    var junto = vacio();
                    var primero_t = true;
                    for x en h.hijos {
                        if !igual(vista(x.clase), "lleva") { continue; }
                        let t = I.sin_alias_tipo(vista(x.texto));
                        if es_bloque_o_arreglo(vista(t)) {
                            return rechazo("bloques o arreglos en un enum");
                        }
                        if !primero_t { empujar(junto, "\t"); }
                        primero_t = false;
                        empujar(junto, vista(t));
                    }
                    anadir(ls, junto);
                }
                poner(en_indice, vista(d.texto), largo(en_nombres));
                anadir(en_nombres, nuevo(vista(d.texto)));
                anadir(en_variantes, vs);
                anadir(en_lleva, ls);
                continue;
            }
            return rechazo($"`{clase}`");
        }
        anadir(arboles, arbol);
        anadir(contextos, tipos);
    }
    // Lo que ve cada archivo, con los modulos ya leidos todos.
    var error_nombres = vacio();
    if !revisar_nombres(arboles, modulos, vista(raiz), error_nombres) {
        imprimir_error($"error: {error_nombres}\n");
        return 1;
    }

    // Un nombre de funcion que declaran dos modulos se llama en C con el del
    // archivo delante, en los dos: `celsius__nombre`. Cada archivo lo ve con
    // el nombre o el alias con que lo pide, como en el cargador.
    for g en claves(plantillas) {
        if tiene(global.repetidas, vista(g)) {
            return rechazo("una generica repetida entre modulos");
        }
    }
    var mr = 0;
    while mr < largo(arboles) {
        for d en arboles[mr].hijos {
            if igual(vista(d.clase), "fn") && tiene(global.repetidas, vista(d.texto)) {
                let suyos = declarantes(arboles, modulos, vista(d.texto));
                let base = F.prefijo_unico(vista(modulos[mr]), suyos);
                let otro = $"{base}__{d.texto}";
                poner(contextos[mr].renombradas, vista(d.texto), otro);
                quitar(contextos[mr].repetidas, vista(d.texto));
            }
        }
        let fuente_m = try leer_archivo(vista(modulos[mr]));
        let pedidos_m = try usar_con_alias(vista(fuente_m));
        let dir_m = P.carpeta(vista(modulos[mr]));
        for pedido en pedidos_m {
            let ruta_p = campo_pedido(vista(pedido), 0);
            let alias_p = campo_pedido(vista(pedido), 1);
            let destino = try resolver(vista(ruta_p), vista(dir_m), vista(raiz));
            var jm = 0;
            while jm < largo(modulos) && !igual(vista(modulos[jm]), vista(destino)) {
                jm = jm + 1;
            }
            if jm == largo(modulos) { return rechazo("un modulo que no se cargo"); }
            for d en arboles[jm].hijos {
                if !igual(vista(d.clase), "fn") { continue; }
                if !tiene(global.repetidas, vista(d.texto)) { continue; }
                var clave = copiar(d.texto);
                if largo(alias_p) > 0 { clave = $"{alias_p}.{d.texto}"; }
                let suyos = declarantes(arboles, modulos, vista(d.texto));
                let base_d = F.prefijo_unico(vista(destino), suyos);
                let otro = $"{base_d}__{d.texto}";
                poner(contextos[mr].renombradas, vista(clave), otro);
                quitar(contextos[mr].repetidas, vista(clave));
            }
        }
        mr = mr + 1;
    }

    // Los tipos son de todo el programa: una copia de `par` se escribe en el
    // modulo de `std/par`, y ahi tiene que saberse que un `Caja<str>` de
    // quien la llama posee memoria. El comprobador de Python los ve todos.
    var k_ctx = 0;
    while k_ctx < largo(contextos) {
        for st en claves(global.campos) {
            if tiene(contextos[k_ctx].campos, vista(st)) { continue; }
            let cs_g = I.lista_de(global.campos, vista(st)) sino [];
            poner(contextos[k_ctx].campos, vista(st), cs_g);
            let ns_g = I.lista_de(global.nombres, vista(st)) sino [];
            poner(contextos[k_ctx].nombres, vista(st), ns_g);
        }
        for sp en claves(global.struct_params) {
            if tiene(contextos[k_ctx].struct_params, vista(sp)) { continue; }
            let ps_g = I.lista_de(global.struct_params, vista(sp)) sino [];
            poner(contextos[k_ctx].struct_params, vista(sp), ps_g);
        }
        for en_g en claves(global.variantes) {
            if tiene(contextos[k_ctx].variantes, vista(en_g)) { continue; }
            let vs_g = I.lista_de(global.variantes, vista(en_g)) sino [];
            poner(contextos[k_ctx].variantes, vista(en_g), vs_g);
        }
        for fk en claves(global.formas) {
            if tiene(contextos[k_ctx].formas, vista(fk)) { continue; }
            let fs_g = I.lista_de(global.formas, vista(fk)) sino [];
            poner(contextos[k_ctx].formas, vista(fk), fs_g);
        }
        k_ctx = k_ctx + 1;
    }

    // El programa tiene que valer antes de escribir nada: mismas reglas y
    // mismos mensajes que el comprobador de Python.
    let revision = C.comprobar_programa(arboles, modulos, contextos);
    if largo(revision.errores) > 0 {
        for e en revision.errores { imprimir_error($"error: {e}\n"); }
        let n = largo(revision.errores);
        if n == 1 { imprimir_error("\n1 error. No se genero nada.\n"); }
        else { imprimir_error($"\n{n} errores. No se genero nada.\n"); }
        return 1;
    }
    // Un aviso no impide compilar, salvo que se pida.
    let n_avisos = largo(revision.avisos);
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
    if igual(vista(modo), "explicar") {
        let texto_e = vista(revision.explicacion);
        var salto = 0;
        while salto < largo(texto_e) && byte(texto_e, salto) != 10 { salto = salto + 1; }
        imprimir($"{fuente}{rebanar(texto_e, salto, largo(texto_e))}\n");
        return 0;
    }
    if igual(vista(modo), "comprobar") {
        if n_avisos == 0 { imprimir($"{fuente}: sin errores\n"); }
        else if n_avisos == 1 { imprimir($"{fuente}: sin errores, 1 aviso\n"); }
        else { imprimir($"{fuente}: sin errores, {n_avisos} avisos\n"); }
        return 0;
    }

    // Las clausuras nacieron al comprobar, en el orden del original y una por
    // copia en las genericas. Cada cuerpo lleva ahora el `Cierre_N` que le
    // toca en cada sitio, y su funcion se ve desde todos los modulos: una
    // copia de `filtradas` en std/lista llama a la clausura de quien la pidio.
    var sacados: mapa<str, usize> = [];
    for x en revision.sacados { poner(sacados, vista(x), 1); }
    var cierres = Cierres { fns: copiar(revision.cierres),
        modulo: copiar(revision.cierres_mod), indice: [],
        numeracion: copiar(revision.numeracion), sacados: sacados };
    var m_c = 0;
    while m_c < largo(arboles) {
        var k_d = 0;
        while k_d < largo(arboles[m_c].hijos) {
            if igual(vista(arboles[m_c].hijos[k_d].clase), "fn")
            && !F.es_generica(arboles[m_c].hijos[k_d]) {
                var dueno = copiar(arboles[m_c].hijos[k_d].texto);
                if tiene(contextos[m_c].renombradas, vista(dueno)) {
                    dueno = nuevo(obtener(contextos[m_c].renombradas, vista(dueno)) sino "");
                }
                var cuenta: usize = 0;
                numerar_cierres(arboles[m_c].hijos[k_d], vista(dueno), cierres.numeracion,
                    cuenta);
            }
            k_d = k_d + 1;
        }
        m_c = m_c + 1;
    }
    let numeracion = copiar(cierres.numeracion);
    var k_cf = 0;
    while k_cf < largo(cierres.fns) {
        let dueno_c = copiar(cierres.fns[k_cf].texto);
        var cuenta_c: usize = 0;
        numerar_cierres(cierres.fns[k_cf], vista(dueno_c), numeracion, cuenta_c);
        poner(cierres.indice, vista(dueno_c), k_cf);
        F.recoger_firmas(cierres.fns[k_cf], global);
        var k_cx = 0;
        while k_cx < largo(contextos) {
            F.recoger_firmas(cierres.fns[k_cf], contextos[k_cx]);
            k_cx = k_cx + 1;
        }
        k_cf = k_cf + 1;
    }

    // Las copias de los structs genericos: primero las que piden los campos
    // de los structs, luego las de los tipos escritos en cada funcion.
    var en_curso_st: mapa<str, usize> = [];
    let n_concretos = largo(st_nombres);
    var k_st = 0;
    while k_st < n_concretos {
        var nuevos_t: lista<str> = [];
        let viejos_t = copiar(st_tipos[k_st]);
        for vt en viejos_t {
            anadir(nuevos_t, resolver_reg(vista(vt), stp_indice, stp_params, stp_campos, stp_tipos, en_curso_st,
                    st_nombres, st_indice, st_campos, st_tipos, global));
        }
        let nombre_st = copiar(st_nombres[k_st]);
        poner(global.campos, vista(nombre_st), copiar(nuevos_t));
        st_tipos[k_st] = nuevos_t;
        k_st = k_st + 1;
    }
    var k_fn = 0;
    while k_fn < largo(arboles) {
        for d en arboles[k_fn].hijos {
            if igual(vista(d.clase), "fn") && !F.es_generica(d) {
                resolver_en_nodo(d, stp_indice, stp_params, stp_campos, stp_tipos, en_curso_st,
                    st_nombres, st_indice, st_campos, st_tipos, global);
            }
        }
        k_fn = k_fn + 1;
    }

    // Lo que tiene partes, para `obtener_mut`: structs y enums.
    var con_partes: mapa<str, usize> = [];
    for n en st_nombres { poner(con_partes, vista(n), 1); }
    for n en en_nombres { poner(con_partes, vista(n), 1); }

    // Las copias de las genericas, en el orden en que las crea el original.
    // Se descubren antes del recorrido de tipos porque el original ya las
    // tiene cuando registra: sus firmas tambien cuentan.
    var vistas_inst: mapa<str, usize> = [];
    var orden_inst: lista<str> = [];
    var creados_inst: lista<str> = [];
    var k_desc = 0;
    while k_desc < largo(arboles) {
        for d en arboles[k_desc].hijos {
            if !igual(vista(d.clase), "fn") || F.es_generica(d) { continue; }
            var borrador = F.cuenta_nueva();
            borrador.sacados = copiar(cierres.sacados);
            let escritas = F.generar_funcion(d, contextos[k_desc],
                vista(modulos[k_desc]), borrador);
            // Si no se sabe escribir, lo dira la pasada de verdad.
            if largo(escritas) == 0 { continue; }
            if !descubrir(borrador.instancias, arboles, contextos, modulos,
                plantillas, vistas_inst, orden_inst, creados_inst, cierres, global) {
                return 1;
            }
        }
        k_desc = k_desc + 1;
    }
    // Cada copia resuelve sus tipos al crearse, antes de su cuerpo. El struct
    // de una clausura tambien nace ahi, entre las copias.
    for p en creados_inst {
        if largo(campo_pedido(vista(p), 0)) == 0 {
            let en_c_c = campo_pedido(vista(p), 1);
            let st_c = struct_de_cierre(vista(en_c_c));
            var cn: lista<str> = [];
            var ct: lista<str> = [];
            campos_de_cierre(vista(p), cn, ct);
            poner(st_indice, vista(st_c), largo(st_nombres));
            anadir(st_nombres, copiar(st_c));
            anadir(st_campos, cn);
            anadir(st_tipos, ct);
            continue;
        }
        let copia_r = nodo_instancia(vista(p), arboles, plantillas, cierres.numeracion);
        resolver_instancia(copia_r, stp_indice, stp_params, stp_campos, stp_tipos, en_curso_st,
            st_nombres, st_indice, st_campos, st_tipos, global);
    }
    for n en st_nombres { poner(con_partes, vista(n), 1); }

    var instancias: lista<P.Nodo> = [];
    var modulo_de: lista<usize> = [];
    for p en orden_inst {
        if largo(campo_pedido(vista(p), 0)) == 0 {
            let en_c_i = campo_pedido(vista(p), 1);
            let k_ci = obtener(cierres.indice, vista(en_c_i)) sino 0;
            anadir(instancias, copiar(cierres.fns[k_ci]));
            anadir(modulo_de, cierres.modulo[k_ci]);
            continue;
        }
        anadir(instancias, nodo_instancia(vista(p), arboles, plantillas, cierres.numeracion));
        let plantilla = campo_pedido(vista(p), 0);
        anadir(modulo_de, obtener(plantillas, vista(plantilla)) sino 0);
    }

    // Las listas, con el mismo recorrido que el original: en orden de
    // declaracion, campos de struct y funciones entremezclados.
    var reg = registro();
    var im = 0;
    while im < largo(arboles) {
        for d en arboles[im].hijos {
            if igual(vista(d.clase), "struct") && !tiene_tipo_param(d) {
                for h en d.hijos {
                    if igual(vista(h.clase), "campo_def") {
                        let tp = F.tipo_pelado(vista(h.texto));
                        let t = I.sin_alias_tipo(vista(tp));
                        if !mirar_tipo(vista(t), reg, global, con_partes) {
                            return rechazo("mapas, bloques ni arreglos");
                        }
                    }
                }
            }
            if igual(vista(d.clase), "fn") && !F.es_generica(d) {
                if !mirar_funcion(d, contextos[im], reg, global, con_partes) {
                    return rechazo("mapas, bloques ni arreglos");
                }
            }
        }
        im = im + 1;
    }
    // Las copias de structs genericos van detras de lo declarado.
    var k_ist = n_concretos;
    while k_ist < largo(st_nombres) {
        let tipos_ist = copiar(st_tipos[k_ist]);
        for tt en tipos_ist {
            if !mirar_tipo(vista(tt), reg, global, con_partes) {
                return rechazo("mapas, bloques ni arreglos");
            }
        }
        k_ist = k_ist + 1;
    }
    var k_mira = 0;
    while k_mira < largo(instancias) {
        if !mirar_funcion(instancias[k_mira], contextos[modulo_de[k_mira]], reg,
            global, con_partes) {
            return rechazo("mapas, bloques ni arreglos");
        }
        k_mira = k_mira + 1;
    }

    // Las internas falibles registran el suyo despues, al recorrer todo.
    var usa_leer_archivo = false;
    var usa_escribir_archivo = false;
    var da_texto = false;
    var usa_sistema: mapa<str, usize> = [];
    for arbol en arboles {
        if llama_a(arbol, "leer_archivo") { usa_leer_archivo = true; }
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
    for n en st_nombres {
        visitar_struct(vista(n), st_indice, st_tipos, listos, orden);
    }
    var cta = F.cuenta_nueva();
    cta.sacados = copiar(cierres.sacados);

    var partes: lista<str> = [];
    for n en st_nombres { anadir(partes, $"typedef struct {n} {n};"); }
    if largo(st_nombres) > 0 { anadir(partes, vacio()); }
    // Cada enum con la etiqueta de cada forma: la 0 es la primera.
    var ie_t = 0;
    while ie_t < largo(en_nombres) {
        anadir(partes, $"typedef struct {en_nombres[ie_t]} {en_nombres[ie_t]};");
        var iv_t = 0;
        while iv_t < largo(en_variantes[ie_t]) {
            let etq = G.etiqueta(vista(en_nombres[ie_t]), vista(en_variantes[ie_t][iv_t]));
            anadir(partes, $"#define {etq} {iv_t}");
            iv_t = iv_t + 1;
        }
        ie_t = ie_t + 1;
    }
    if largo(en_nombres) > 0 { anadir(partes, vacio()); }
    var ordenadas: lista<str> = [];
    for x en reg.bloques { anadir(ordenadas, copiar(x)); }
    for x en reg.listas { anadir(ordenadas, copiar(x)); }
    for x en reg.mapas { anadir(ordenadas, copiar(x)); }
    ordenar(ordenadas);
    var puestos: mapa<str, usize> = [];
    for x en ordenadas { poner_typedef(vista(x), reg, puestos, partes); }
    if largo(ordenadas) > 0 { anadir(partes, vacio()); }
    // Los enums, y detras los structs en orden de dependencia. Pero cada
    // uno necesita el tamaño de lo que lleva por valor, asi que antes va lo
    // suyo: un enum que lleva un struct, u otro enum escrito mas abajo, lo
    // encuentra ya definido.
    var definidos: mapa<str, usize> = [];
    for en_n en en_nombres {
        definir_tipo_c(vista(en_n), en_nombres, en_variantes, en_lleva, st_indice, st_campos,
            st_tipos, definidos, partes);
    }
    for n en orden {
        definir_tipo_c(vista(n), en_nombres, en_variantes, en_lleva, st_indice, st_campos,
            st_tipos, definidos, partes);
    }
    var alguno_posee = false;
    for n en orden {
        if I.posee_con_formas(global, vista(n)) {
            anadir(partes, $"static void ss_drop_{n}({n}* p);");
            alguno_posee = true;
        }
    }
    for n en en_nombres {
        if I.posee_con_formas(global, vista(n)) {
            anadir(partes, $"static void ss_drop_{n}({n}* p);");
            alguno_posee = true;
        }
    }
    if alguno_posee { anadir(partes, vacio()); }
    // Los envoltorios de arreglo, de dentro hacia fuera.
    var arr_orden: lista<str> = [];
    var hondo_a = 0;
    var quedan_a = largo(reg.arreglos);
    while quedan_a > 0 {
        for t en reg.arreglos {
            if cuantos_corchetes(vista(t)) == hondo_a {
                anadir(arr_orden, copiar(t));
                quedan_a = quedan_a - 1;
            }
        }
        hondo_a = hondo_a + 1;
    }
    for t en arr_orden {
        let pa = partes_arreglo(vista(t));
        let te = G.tipo_c(vista(pa[0]));
        let tc = G.tipo_c(vista(t));
        anadir(partes, $"typedef struct {{ {te} e[{pa[1]}]; }} {tc};");
    }
    if largo(reg.arreglos) > 0 { anadir(partes, vacio()); }
    for r en reg.resultados { anadir(partes, typedef_resultado(vista(r))); }
    if largo(reg.resultados) > 0 { anadir(partes, vacio()); }
    // Las internas que hablan con el sistema, en un orden fijo: el monotono
    // cae en el de pared, y el azar sin semilla usa el reloj. Su C vive en
    // `runtime/sistema`, el mismo que lee el original.
    let res_texto = G.tipo_resultado("str");
    var internas_orden: lista<str> = [];
    anadir(internas_orden, nuevo("ahora_ms"));
    anadir(internas_orden, nuevo("monotono_ms"));
    anadir(internas_orden, nuevo("semilla"));
    anadir(internas_orden, nuevo("leer_linea"));
    anadir(internas_orden, nuevo("entrada_completa"));
    anadir(internas_orden, nuevo("variable_entorno"));
    if usa_escribir_archivo { ayudante_escribir_archivo(partes); }
    for interna en internas_orden {
        if !tiene(usa_sistema, vista(interna)) { continue; }
        let crudo = try leer_archivo($"{raiz}/runtime/sistema/{interna}.inc");
        let hecho = try reemplazar(vista(crudo), "@RES_STR@", vista(res_texto));
        var desde = 0;
        var k_l = 0;
        // Sin el salto final: cada linea va a su sitio, y la blanca de detras
        // la pone el separador.
        let cuerpo_c = rebanar(vista(hecho), 0, largo(vista(hecho)) - 1);
        while k_l <= largo(cuerpo_c) {
            if k_l == largo(cuerpo_c) || byte(cuerpo_c, k_l) == 10 {
                anadir(partes, nuevo(rebanar(cuerpo_c, desde, k_l)));
                desde = k_l + 1;
            }
            k_l = k_l + 1;
        }
        anadir(partes, vacio());
    }
    if usa_leer_archivo { ayudante_leer_archivo(partes); }
    // Los bloques: reservar y cambiar de tamaño, a ceros, y al encoger se
    // suelta lo que se queda fuera.
    for x en reg.bloques { funcion_bloque(vista(x), global, cta, partes); }
    for x en reg.listas { funcion_push(vista(x), partes); }
    for x en reg.listas { funcion_ordenar(vista(x), partes); }
    // Los mapas gastan cuenta si sus valores poseen: van antes que los
    // liberadores de los structs, como en el original.
    for x en reg.mapas { funcion_mapa(vista(x), global, con_partes, cta, partes); }

    // Los liberadores van antes que las funciones tambien en la cuenta: un
    // campo que sea una lista gasta indice de bucle.
    for n en orden {
        if !I.posee_con_formas(global, vista(n)) { continue; }
        let k = obtener(st_indice, vista(n)) sino 0;
        var b = G.cuerpo();
        b.temporal = cta.temporal;
        b.bucle = cta.bucle;
        b.etiquetas = cta.etiquetas;
        var j = 0;
        while j < largo(st_campos[k]) {
            let donde = $"p->{st_campos[k][j]}";
            G.liberacion(b, global, vista(donde), vista(st_tipos[k][j]));
            j = j + 1;
        }
        anadir(partes, nuevo("SS_LANG_QUIZA_SIN_USAR"));
        anadir(partes, $"static void ss_drop_{n}({n}* p)");
        anadir(partes, nuevo("{"));
        for l en b.lineas { anadir(partes, copiar(l)); }
        anadir(partes, nuevo("}"));
        anadir(partes, vacio());
        cta.temporal = b.temporal;
        cta.bucle = b.bucle;
        cta.etiquetas = b.etiquetas;
    }

    // Los liberadores de los enums: se mira la etiqueta y se suelta lo que
    // lleve esa forma. Las formas que no llevan nada con dueno no salen.
    var ie_d = 0;
    while ie_d < largo(en_nombres) {
        let en_n = copiar(en_nombres[ie_d]);
        if I.posee_con_formas(global, vista(en_n)) {
            anadir(partes, nuevo("SS_LANG_QUIZA_SIN_USAR"));
            anadir(partes, $"static void ss_drop_{en_n}({en_n}* p)");
            anadir(partes, nuevo("{"));
            anadir(partes, nuevo("    switch (p->etiqueta)"));
            anadir(partes, nuevo("    {"));
            var iv = 0;
            while iv < largo(en_variantes[ie_d]) {
                let tipos_v = partir_tab(vista(en_lleva[ie_d][iv]));
                var alguna = false;
                for tt en tipos_v {
                    if I.posee_con_formas(global, vista(tt)) { alguna = true; }
                }
                if alguna {
                    let etq = G.etiqueta(vista(en_n), vista(en_variantes[ie_d][iv]));
                    anadir(partes, $"    case {etq}:");
                    anadir(partes, nuevo("    {"));
                    var q = 0;
                    while q < largo(tipos_v) {
                        if I.posee_con_formas(global, vista(tipos_v[q])) {
                            let donde = $"p->dato.v_{en_variantes[ie_d][iv]}._{q}";
                            lineas_liberacion(global, vista(donde), vista(tipos_v[q]), 2,
                                cta, partes);
                        }
                        q = q + 1;
                    }
                    anadir(partes, nuevo("        break;"));
                    anadir(partes, nuevo("    }"));
                }
                iv = iv + 1;
            }
            anadir(partes, nuevo("    default: break;"));
            anadir(partes, nuevo("    }"));
            anadir(partes, nuevo("}"));
            anadir(partes, vacio());
        }
        ie_d = ie_d + 1;
    }

    // Las funciones de todos los modulos, en orden, con la misma cuenta.
    var protos: lista<str> = [];
    var cuerpos: lista<str> = [];
    var anchos: mapa<str, usize> = [];
    var decimales: mapa<str, usize> = [];
    var conversiones: mapa<str, usize> = [];
    var i = 0;
    while i < largo(arboles) {
        // El original compara archivo y linea a la vez para no repetir un
        // `#line`: al cambiar de modulo nunca coincide.
        cta.ultima_linea = 0;
        for d en arboles[i].hijos {
            if !igual(vista(d.clase), "fn") || F.es_generica(d) { continue; }
            if !emitir_funcion(d, contextos[i], vista(modulos[i]), cta, protos,
                cuerpos, anchos, decimales, conversiones) {
                return 1;
            }
        }
        i = i + 1;
    }
    // Las copias van detras de todo, `main` incluida.
    var ultima_ruta = copiar(modulos[largo(modulos) - 1]);
    var k_emite = 0;
    while k_emite < largo(instancias) {
        let de = modulo_de[k_emite];
        if !igual(vista(modulos[de]), vista(ultima_ruta)) { cta.ultima_linea = 0; }
        ultima_ruta = copiar(modulos[de]);
        if !emitir_funcion(instancias[k_emite], contextos[de], vista(modulos[de]),
            cta, protos, cuerpos, anchos, decimales, conversiones) {
            return 1;
        }
        k_emite = k_emite + 1;
    }

    // Toda lista que aparezca en un cuerpo tiene que tener su typedef: si el
    // recorrido no la registro, el C no compilaria. Mejor no escribirlo.
    var usadas: mapa<str, usize> = [];
    // Lo que se busca en los cuerpos, sin sus literales.
    var limpios: lista<str> = [];
    for l en cuerpos { anadir(limpios, sin_cadenas(vista(l))); }
    for l en limpios { apuntar_nombres(vista(l), "ss_lista_", usadas); }
    var registradas: mapa<str, usize> = [];
    for x en reg.listas {
        let nombre_c = G.tipo_c(vista(x));
        poner(registradas, vista(nombre_c), 1);
    }
    for u en claves(usadas) {
        if !tiene(registradas, vista(u)) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no la registro\n");
            return 1;
        }
    }

    // Y con los bloques.
    var usados_b: mapa<str, usize> = [];
    for l en limpios { apuntar_nombres(vista(l), "ss_bloque_", usados_b); }
    for x en reg.bloques {
        let nombre_c = G.tipo_c(vista(x));
        poner(registradas, vista(nombre_c), 1);
    }
    for u en claves(usados_b) {
        if !tiene(registradas, vista(u)) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no lo registro\n");
            return 1;
        }
    }

    // Y con los arreglos.
    var usados_a: mapa<str, usize> = [];
    for l en limpios { apuntar_nombres(vista(l), "ss_arr_", usados_a); }
    for x en reg.arreglos {
        let nombre_c = G.tipo_c(vista(x));
        poner(registradas, vista(nombre_c), 1);
    }
    for u en claves(usados_a) {
        if !tiene(registradas, vista(u)) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no lo registro\n");
            return 1;
        }
    }

    // Lo mismo con los mapas y los tipos resultado.
    var usados_m: mapa<str, usize> = [];
    var usados_r: mapa<str, usize> = [];
    for l en limpios {
        apuntar_nombres(vista(l), "ss_mapa_", usados_m);
        apuntar_nombres(vista(l), "ss_res_", usados_r);
    }
    for x en reg.mapas {
        let nombre_c = G.tipo_c(vista(x));
        poner(registradas, vista(nombre_c), 1);
    }
    for x en reg.resultados {
        let nombre_c = G.tipo_resultado(vista(x));
        poner(registradas, vista(nombre_c), 1);
    }
    for u en claves(usados_m) {
        let tipo = tipo_de_nombre_mapa(vista(u));
        if !tiene(registradas, vista(tipo)) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no lo registro\n");
            return 1;
        }
    }
    for u en claves(usados_r) {
        if !tiene(registradas, vista(u)) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no lo registro\n");
            return 1;
        }
    }

    // Y toda copia de generica que se llame tiene que haberse escrito.
    for g en claves(plantillas) {
        var usadas_g: mapa<str, usize> = [];
        let prefijo = $"{g}__";
        for l en limpios { apuntar_nombres(vista(l), vista(prefijo), usadas_g); }
        for u en claves(usadas_g) {
            if !tiene(vistas_inst, vista(u)) {
                imprimir_error($"tcodec: la copia `{u}` se usa y no se escribio\n");
                return 1;
            }
        }
    }

    // Los copiadores, en el orden en que el original los apunta, y de dentro
    // hacia fuera: el de `lista<Cosa>` llama al de `Cosa`.
    var apuntados: lista<str> = [];
    var vistos_c: mapa<str, usize> = [];
    for t en cta.copias {
        let tr = I.nombre_resuelto(vista(t));
        necesita_copiador(vista(tr), global, st_indice, st_tipos, vistos_c, apuntados);
    }
    var copiadores: lista<str> = [];
    var hondo = 0;
    var quedan = largo(apuntados);
    while quedan > 0 {
        for t en apuntados {
            if hondura_tipo(vista(t)) == hondo {
                anadir(copiadores, copiar(t));
                quedan = quedan - 1;
            }
        }
        hondo = hondo + 1;
    }
    var bloque_copias: lista<str> = [];
    var nombres_copia: mapa<str, usize> = [];
    for t en copiadores {
        let tc = G.tipo_c(vista(t));
        let m = G.mangle(vista(t));
        anadir(bloque_copias, $"static {tc} ss_copia_{m}(const {tc}* p);");
        let nc = $"ss_copia_{m}";
        poner(nombres_copia, vista(nc), 1);
    }
    anadir(bloque_copias, vacio());
    for t en copiadores {
        if !cuerpo_copiador(vista(t), global, st_indice, st_campos, st_tipos,
            en_indice, en_variantes, en_lleva, bloque_copias) {
            return rechazo("copiar bloques");
        }
    }
    var usados_c: mapa<str, usize> = [];
    for l en limpios { apuntar_nombres(vista(l), "ss_copia_", usados_c); }
    for u en claves(usados_c) {
        if !tiene(nombres_copia, vista(u)) {
            imprimir_error($"tcodec: `{u}` se usa y no se apunto\n");
            return 1;
        }
    }

    // Solo los anchos que el programa usa, en el orden de sus nombres.
    var arit: lista<str> = [];
    var ws = claves(anchos);
    ordenar(ws);
    for w en ws { anadir(arit, fila_aritmetica(vista(w))); }
    var fs = claves(decimales);
    ordenar(fs);
    for f en fs {
        let tc = G.tipo_c(vista(f));
        anadir(arit, $"SS_LANG_ARIT_F({f}, {tc})");
    }
    var cs: lista<str> = [];
    for cv en claves(conversiones) {
        let corte = buscar_desde(vista(cv), "_de_", 0);
        if corte < largo(vista(cv)) {
            let destino = rebanar(vista(cv), 0, corte);
            let origen = rebanar(vista(cv), corte + 4, largo(vista(cv)));
            anadir(cs, $"{destino}\t{origen}");
        }
    }
    ordenar(cs);
    for par en cs {
        let corte = buscar_desde(vista(par), "\t", 0);
        let destino = rebanar(vista(par), 0, corte);
        let origen = rebanar(vista(par), corte + 1, largo(vista(par)));
        let td = G.tipo_c(destino);
        let to = G.tipo_c(origen);
        var macro = nuevo("SS_LANG_CONV");
        var extra = vacio();
        if empieza_con(origen, "f") {
            if igual(destino, "usize") || empieza_con(destino, "u") {
                macro = nuevo("SS_LANG_CONV_F_U");
            } else {
                if empieza_con(destino, "i") {
                    macro = nuevo("SS_LANG_CONV_F_I");
                }
            }
        } else {
            if igual(destino, "f32") || igual(destino, "f64") {
                if igual(origen, "usize") || empieza_con(origen, "u") {
                    macro = nuevo("SS_LANG_CONV_U_F");
                } else {
                    if empieza_con(origen, "i") {
                        macro = nuevo("SS_LANG_CONV_I_F");
                    }
                }
                if igual(destino, "f32") {
                    extra = nuevo("FLT_MANT_DIG, ");
                } else {
                    extra = nuevo("DBL_MANT_DIG, ");
                }
            } else {
                let origen_entero = igual(origen, "usize")
                || empieza_con(origen, "u") || empieza_con(origen, "i");
                let destino_entero = igual(destino, "usize")
                || empieza_con(destino, "u") || empieza_con(destino, "i");
                if origen_entero && destino_entero {
                    let ou = igual(origen, "usize") || empieza_con(origen, "u");
                    let du = igual(destino, "usize") || empieza_con(destino, "u");
                    var os = nuevo("I");
                    if ou { os = nuevo("U"); }
                    var ds = nuevo("I");
                    if du { ds = nuevo("U"); }
                    macro = $"SS_LANG_CONV_{os}_{ds}";
                    if du || ou {
                        extra = $"{maximo_entero(destino)}, ";
                    } else {
                        extra = $"{minimo_entero(destino)}, {maximo_entero(destino)}, ";
                    }
                }
            }
        }
        if igual(origen, "f64") && igual(destino, "f32") {
            macro = nuevo("SS_LANG_CONV_F_F");
            extra = nuevo("FLT_MAX, ");
        }
        anadir(arit, $"{macro}({destino}, {td}, {extra}{origen}, {to})");
    }
    if largo(arit) > 0 { anadir(arit, vacio()); }

    // Los tipos funcion que nombra el C, cada uno con su typedef, en el orden
    // en que aparecen. Van justo antes de la aritmetica, como en el original.
    var candidatos: lista<str> = [];
    for fk en claves(global.retornos) {
        let firma = I.firma_de_funcion(global, vista(fk));
        apuntar_tipo_funcion(vista(firma), candidatos);
    }
    var k_tf = 0;
    while k_tf < largo(arboles) {
        for d en arboles[k_tf].hijos {
            if igual(vista(d.clase), "fn") && !F.es_generica(d) {
                tipos_funcion_de(d, candidatos);
            }
        }
        k_tf = k_tf + 1;
    }
    for d en instancias { tipos_funcion_de(d, candidatos); }
    var nombres_fn: lista<str> = [];
    for t en candidatos { anadir(nombres_fn, G.tipo_c(vista(t))); }
    var tipos_fn: lista<str> = [];
    var puestos_fn: mapa<str, usize> = [];
    var mirar_fn: lista<str> = [];
    for l en protos { anadir(mirar_fn, sin_cadenas(vista(l))); }
    for l en limpios { anadir(mirar_fn, copiar(l)); }
    for l en mirar_fn {
        if !contiene(vista(l), "ss_fn_") { continue; }
        var k_c = 0;
        while k_c < largo(candidatos) {
            let nc = vista(nombres_fn[k_c]);
            if !tiene(puestos_fn, nc) && contiene_nombre(vista(l), nc) {
                poner(puestos_fn, nc, 1);
                let partes_f = T.partes_de_funcion(vista(candidatos[k_c]));
                var firma_c = vacio();
                var q = 0;
                while q + 1 < largo(partes_f) {
                    if q > 0 { empujar(firma_c, ", "); }
                    let pc = G.tipo_c(vista(partes_f[q]));
                    empujar(firma_c, vista(pc));
                    q = q + 1;
                }
                if largo(firma_c) == 0 { firma_c = nuevo("void"); }
                let rc = G.tipo_c(vista(partes_f[largo(partes_f) - 1]));
                anadir(tipos_fn, $"typedef {rc} (*{nc})({firma_c});");
            }
            k_c = k_c + 1;
        }
    }
    if largo(tipos_fn) > 0 { anadir(tipos_fn, vacio()); }

    let cabecera = try leer_archivo($"{raiz}/runtime/cabecera.inc");

    // El mismo orden que el original: cabecera, structs y resultados,
    // liberadores, la aritmetica, el hueco de los copiadores (su linea en
    // blanco va siempre), los prototipos, y cada funcion con su linea en
    // blanco detras.
    var todas: lista<str> = [];
    anadir(todas, cabecera);
    // Las cabeceras que piden los `externo`, cada una una vez. Un `.c` no se
    // incluye: se compila aparte y se enlaza.
    var incluidas: lista<str> = [];
    for h en ext_cabeceras {
        if termina_con(vista(h), ".c") || esta_en(incluidas, vista(h)) { continue; }
        anadir(incluidas, copiar(h));
    }
    if largo(incluidas) > 0 {
        anadir(todas, nuevo("/* de los bloques `externo` */"));
        for h en incluidas {
            if contiene(vista(h), "/") || empieza_con(vista(h), ".") {
                anadir(todas, $"#include \"{h}\"");
            } else {
                anadir(todas, $"#include <{h}>");
            }
        }
        anadir(todas, vacio());
    }
    if largo(ext_protos) > 0 {
        let cstr = try leer_archivo($"{raiz}/runtime/cstr.inc");
        anadir_lineas(vista(cstr), todas);
        anadir(todas, vacio());
    }
    for x en partes { anadir(todas, copiar(x)); }
    for x en tipos_fn { anadir(todas, copiar(x)); }
    for a en arit { anadir(todas, copiar(a)); }
    for x en bloque_copias { anadir(todas, copiar(x)); }
    for p en protos { anadir(todas, copiar(p)); }
    // Una externa con cabecera ya trae su firma; la de un `.c` la pone Tcode.
    var k_ext = 0;
    while k_ext < largo(ext_protos) {
        if termina_con(vista(ext_cabeceras[k_ext]), ".c") {
            anadir(todas, $"{ext_protos[k_ext]};");
        }
        k_ext = k_ext + 1;
    }
    anadir(todas, vacio());
    for l en cuerpos { anadir(todas, copiar(l)); }

    var todo = vacio();
    var primero = true;
    for x en todas {
        if !primero { empujar(todo, "\n"); }
        primero = false;
        empujar(todo, vista(x));
    }
    if igual(vista(modo), "mostrar") {
        imprimir(todo);
        return 0;
    }
    return construir(todo, vista(fuente), vista(salida), vista(modo), vista(nivel),
        vista(cc), vista(raiz), ext_cabeceras, ext_modulos);
}
