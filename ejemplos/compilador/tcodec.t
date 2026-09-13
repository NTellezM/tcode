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
usar "std/texto";
usar "std/lista";

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

// Lo que este hito todavia no sabe emitir: cada uno pide una seccion propia
// del archivo (typedefs, tablas, ayudantes), y sin ella el C no compila.
fn necesita_lo_que_falta(l: view) -> bool {
    if contiene(l, "ss_copia_") { return true; }
    if contiene(l, "ss_bloque_") { return true; }
    if contiene(l, "ss_arr_") || contiene(l, "ss_fn_") { return true; }
    if contiene(l, "ss_cierre_") || contiene(l, "ss_lang_cstr_") { return true; }
    if contiene(l, "ss_lang_leer_linea_") || contiene(l, "ss_lang_escribir_") {
        return true;
    }
    if contiene(l, "ss_lang_entrada_") || contiene(l, "ss_lang_variable_") {
        return true;
    }
    if contiene(l, "ss_lang_ahora_") || contiene(l, "ss_lang_monotono_") {
        return true;
    }
    if contiene(l, "ss_lang_azar_") || contiene(l, "ss_lang_sembrar_") {
        return true;
    }
    return contiene(l, "ss_lang_texto_decimal_");
}

// ------------------------------------------------------------------
// Rutas y modulos, como el cargador
// ------------------------------------------------------------------

// `a/./b/../c.t` -> `a/c.t`. Sin preguntar al sistema: hace falta que dos
// caminos al mismo archivo den la misma cadena, para no cargarlo dos veces.
fn normalizar(ruta: view) -> str {
    var partes: lista<str> = [];
    let absoluta = largo(ruta) > 0 && byte(ruta, 0) == 47;
    var desde = 0;
    var i = 0;
    while i <= largo(ruta) {
        if i == largo(ruta) || byte(ruta, i) == 47 {
            let trozo = rebanar(ruta, desde, i);
            if largo(trozo) > 0 && !igual(trozo, ".") {
                var atras = false;
                if igual(trozo, "..") && largo(partes) > 0 {
                    atras = !igual(vista(partes[largo(partes) - 1]), "..");
                }
                if atras { quitar_ultima(partes); }
                else { anadir(partes, nuevo(trozo)); }
            }
            desde = i + 1;
        }
        i = i + 1;
    }
    var r = vacio();
    if absoluta { empujar(r, "/"); }
    var primera = true;
    for x en partes {
        if !primera { empujar(r, "/"); }
        primera = false;
        empujar(r, vista(x));
    }
    return r;
}

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
        let prueba = leer_archivo(vista(c)) sino vacio();
        if largo(vista(prueba)) > 0 { return normalizar(vista(c)); }
    }
    falla "no encuentro un modulo que se usa";
}

// Los `usar` del principio de un archivo, en orden.
fn usar_de(fuente: view) -> lista<str> ! {
    let toks = try analizar(fuente);
    var salida: lista<str> = [];
    var i = 0;
    while i + 1 < largo(toks) {
        if !igual(vista(toks[i].valor), "usar") { break; }
        if !igual(vista(toks[i + 1].tipo), "cadena") { break; }
        anadir(salida, copiar(toks[i + 1].valor));
        i = i + 2;
        if i + 1 < largo(toks) && igual(vista(toks[i].valor), "como") {
            i = i + 2;
        }
        i = i + 1; // el `;`
    }
    return salida;
}

// Primero las dependencias, en el orden de los `usar`, y cada modulo una sola
// vez: el mismo recorrido que el cargador, que es el orden en que salen las
// funciones en el C.
fn visitar(ruta: view, raiz: view, hechos: mut lista<str>,
    pila: mut lista<str>) ! {
    if esta_en(pila, ruta) { falla "dependencia circular entre modulos"; }
    if esta_en(hechos, ruta) { return; }
    let fuente = try leer_archivo(ruta);
    anadir(pila, nuevo(ruta));
    let pedidos = try usar_de(vista(fuente));
    let dir = P.carpeta(ruta);
    for pedido en pedidos {
        let destino = try resolver(vista(pedido), vista(dir), raiz);
        try visitar(vista(destino), raiz, hechos, pila);
    }
    quitar_ultima(pila);
    anadir(hechos, nuevo(ruta));
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
        visitar_struct(vista(t), indice, tipos_de, listos, salida);
    }
    anadir(salida, nuevo(nombre));
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
}

fn registro() -> Registro {
    return Registro { listas: [], mapas: [], resultados: [], vistos: [],
        res_vistos: [] };
}

fn registrar_resultado(reg: mut Registro, t: view) {
    var clave = nuevo(t);
    if igual(t, "()") { clave = vacio(); }
    if tiene(reg.res_vistos, vista(clave)) { return; }
    poner(reg.res_vistos, vista(clave), 1);
    anadir(reg.resultados, clave);
}

// Tiene partes: se puede leer un campo o modificarlo en el sitio.
fn es_compuesto_t(t: view, structs: &mapa<str, usize>) -> bool {
    if igual(t, "str") || es_lista_t(t) || es_mapa_t(t) { return true; }
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
    if es_bloque_o_arreglo(t) {
        // Un prestamo no registra nada, como en el original.
        return empieza_con(t, "&");
    }
    if tiene(reg.vistos, t) { return true; }
    if es_lista_t(t) {
        // Una lista de mapas registraria el mapa al pedir su nombre en C,
        // fuera del recorrido, y ese orden no se reproduce aqui.
        if contiene(t, "mapa<") { return false; }
        let dentro = interior_lista(t);
        if es_lista_t(vista(dentro)) {
            if !mirar_tipo(vista(dentro), reg, global, structs) { return false; }
        }
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
    b.sangria = sangria;
    G.liberacion(b, global, donde, tipo);
    for l en b.lineas { anadir(salida, copiar(l)); }
    cta.temporal = b.temporal;
    cta.bucle = b.bucle;
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
        poner(salida, rebanar(t, i, j), 1);
        i = buscar_desde(t, prefijo, j);
    }
}

// ------------------------------------------------------------------
// El archivo
// ------------------------------------------------------------------

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
    plantillas: &mapa<str, usize>) -> P.Nodo {
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
    return r;
}

// Escribe en borrador cada copia pedida que no se haya visto, primero las
// que pide ella, y la apunta en `orden` al terminar.
fn descubrir(pedidos: &lista<str>, arboles: &lista<P.Nodo>,
    contextos: mut lista<I.Contexto>, modulos: &lista<str>,
    plantillas: &mapa<str, usize>, vistos: mut mapa<str, usize>,
    orden: mut lista<str>) -> bool {
    for p en pedidos {
        let en_c = campo_pedido(vista(p), 1);
        if tiene(vistos, vista(en_c)) { continue; }
        poner(vistos, vista(en_c), 1);
        let plantilla = campo_pedido(vista(p), 0);
        if !tiene(plantillas, vista(plantilla)) {
            imprimir_error($"tcodec: `{plantilla}` no es una generica conocida\n");
            return false;
        }
        let de = obtener(plantillas, vista(plantilla)) sino 0;
        let copia = nodo_instancia(vista(p), arboles, plantillas);
        var borrador = F.cuenta_nueva();
        let lineas = F.generar_funcion(copia, contextos[de], vista(modulos[de]), borrador);
        if largo(lineas) == 0 {
            imprimir_error($"tcodec: no se escribir la copia `{en_c}`\n");
            return false;
        }
        if !descubrir(borrador.instancias, arboles, contextos, modulos, plantillas,
            vistos, orden) {
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
        if necesita_lo_que_falta(vista(l)) {
            imprimir_error($"tcodec: `{d.texto}` necesita algo que falta\n");
            return false;
        }
        apuntar_tras(vista(l), "ss_lang_suma_", anchos);
        apuntar_tras(vista(l), "ss_lang_resta_", anchos);
        apuntar_tras(vista(l), "ss_lang_mul_", anchos);
        apuntar_tras(vista(l), "ss_lang_abs_", anchos);
        apuntar_tras(vista(l), "ss_lang_desp_izq_", anchos);
        apuntar_tras(vista(l), "ss_lang_desp_der_", anchos);
        apuntar_tras(vista(l), "ss_lang_fin_", decimales);
        apuntar_tras(vista(l), "ss_lang_conv_", conversiones);
        anadir(cuerpos, copiar(l));
    }
    anadir(cuerpos, vacio());
    return true;
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t>\n");
        return 2;
    }
    let raiz = variable_entorno("TCODE_RAIZ") sino nuevo(".");
    let principal = normalizar(argumento(1));
    var modulos: lista<str> = [];
    var pila: lista<str> = [];
    try visitar(vista(principal), vista(raiz), modulos, pila);

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
    // Cada generica, con el indice del modulo que la declara.
    var plantillas: mapa<str, usize> = [];
    for m en modulos {
        var tipos = I.contexto();
        let arbol = try F.preparar(vista(m), tipos);
        F.recoger_firmas(arbol, global);
        for d en arbol.hijos {
            let clase = vista(d.clase);
            if igual(clase, "usar") || igual(clase, "alias") { continue; }
            if igual(clase, "fn") {
                if F.es_generica(d) {
                    poner(plantillas, vista(d.texto), largo(arboles));
                    continue;
                }
                if G.choca_con_c(vista(d.texto)) {
                    return rechazo("nombres que chocan con C");
                }
                if igual(vista(d.texto), "main") && !igual(vista(m), vista(principal)) {
                    return rechazo("un `main` en un modulo");
                }
                continue;
            }
            if igual(clase, "struct") {
                if tiene_tipo_param(d) { return rechazo("structs genericos"); }
                if tiene(st_indice, vista(d.texto)) {
                    return rechazo("un struct repetido entre modulos");
                }
                var campos: lista<str> = [];
                var tipos_campo: lista<str> = [];
                for h en d.hijos {
                    if igual(vista(h.clase), "campo_def") {
                        let tp = F.tipo_pelado(vista(h.texto));
                        let t = I.sin_alias_tipo(vista(tp));
                        if es_bloque_o_arreglo(vista(t)) || (contiene(vista(t), "<")
                            && !es_lista_t(vista(t)) && !es_mapa_t(vista(t))) {
                            return rechazo("bloques, arreglos o genericos en un struct");
                        }
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
            return rechazo($"`{clase}`");
        }
        anadir(arboles, arbol);
        anadir(contextos, tipos);
    }
    if largo(claves(global.repetidas)) > 0 {
        return rechazo("nombres repetidos entre modulos");
    }

    // Las copias de las genericas, en el orden en que las crea el original.
    // Se descubren antes del recorrido de tipos porque el original ya las
    // tiene cuando registra: sus firmas tambien cuentan.
    var vistas_inst: mapa<str, usize> = [];
    var orden_inst: lista<str> = [];
    var k_desc = 0;
    while k_desc < largo(arboles) {
        for d en arboles[k_desc].hijos {
            if !igual(vista(d.clase), "fn") || F.es_generica(d) { continue; }
            var borrador = F.cuenta_nueva();
            let escritas = F.generar_funcion(d, contextos[k_desc],
                vista(modulos[k_desc]), borrador);
            // Si no se sabe escribir, lo dira la pasada de verdad.
            if largo(escritas) == 0 { continue; }
            if !descubrir(borrador.instancias, arboles, contextos, modulos,
                plantillas, vistas_inst, orden_inst) {
                return 1;
            }
        }
        k_desc = k_desc + 1;
    }
    var instancias: lista<P.Nodo> = [];
    var modulo_de: lista<usize> = [];
    for p en orden_inst {
        anadir(instancias, nodo_instancia(vista(p), arboles, plantillas));
        let plantilla = campo_pedido(vista(p), 0);
        anadir(modulo_de, obtener(plantillas, vista(plantilla)) sino 0);
    }

    // Las listas, con el mismo recorrido que el original: en orden de
    // declaracion, campos de struct y funciones entremezclados.
    var reg = registro();
    var im = 0;
    while im < largo(arboles) {
        for d en arboles[im].hijos {
            if igual(vista(d.clase), "struct") {
                for h en d.hijos {
                    if igual(vista(h.clase), "campo_def") {
                        let tp = F.tipo_pelado(vista(h.texto));
                        let t = I.sin_alias_tipo(vista(tp));
                        if !mirar_tipo(vista(t), reg, global, st_indice) {
                            return rechazo("mapas, bloques ni arreglos");
                        }
                    }
                }
            }
            if igual(vista(d.clase), "fn") && !F.es_generica(d) {
                if !mirar_funcion(d, contextos[im], reg, global, st_indice) {
                    return rechazo("mapas, bloques ni arreglos");
                }
            }
        }
        im = im + 1;
    }
    var k_mira = 0;
    while k_mira < largo(instancias) {
        if !mirar_funcion(instancias[k_mira], contextos[modulo_de[k_mira]], reg,
            global, st_indice) {
            return rechazo("mapas, bloques ni arreglos");
        }
        k_mira = k_mira + 1;
    }

    // Las internas falibles registran el suyo despues, al recorrer todo.
    var usa_leer_archivo = false;
    for arbol en arboles {
        if llama_a(arbol, "leer_archivo") { usa_leer_archivo = true; }
    }
    if usa_leer_archivo { registrar_resultado(reg, "str"); }

    // Los structs en orden de dependencia, y quien de ellos posee.
    var listos: mapa<str, usize> = [];
    var orden: lista<str> = [];
    for n en st_nombres {
        visitar_struct(vista(n), st_indice, st_tipos, listos, orden);
    }
    var cta = F.cuenta_nueva();

    var partes: lista<str> = [];
    for n en st_nombres { anadir(partes, $"typedef struct {n} {n};"); }
    if largo(st_nombres) > 0 { anadir(partes, vacio()); }
    var ordenadas: lista<str> = [];
    for x en reg.listas { anadir(ordenadas, copiar(x)); }
    for x en reg.mapas { anadir(ordenadas, copiar(x)); }
    ordenar(ordenadas);
    var puestos: mapa<str, usize> = [];
    for x en ordenadas { poner_typedef(vista(x), reg, puestos, partes); }
    if largo(ordenadas) > 0 { anadir(partes, vacio()); }
    for n en orden {
        let k = obtener(st_indice, vista(n)) sino 0;
        anadir(partes, $"struct {n}");
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
    var alguno_posee = false;
    for n en orden {
        if I.posee_con_formas(global, vista(n)) {
            anadir(partes, $"static void ss_drop_{n}({n}* p);");
            alguno_posee = true;
        }
    }
    if alguno_posee { anadir(partes, vacio()); }
    for r en reg.resultados { anadir(partes, typedef_resultado(vista(r))); }
    if largo(reg.resultados) > 0 { anadir(partes, vacio()); }
    if usa_leer_archivo { ayudante_leer_archivo(partes); }
    for x en reg.listas { funcion_push(vista(x), partes); }
    for x en reg.listas { funcion_ordenar(vista(x), partes); }
    // Los mapas gastan cuenta si sus valores poseen: van antes que los
    // liberadores de los structs, como en el original.
    for x en reg.mapas { funcion_mapa(vista(x), global, st_indice, cta, partes); }

    // Los liberadores van antes que las funciones tambien en la cuenta: un
    // campo que sea una lista gasta indice de bucle.
    for n en orden {
        if !I.posee_con_formas(global, vista(n)) { continue; }
        let k = obtener(st_indice, vista(n)) sino 0;
        var b = G.cuerpo();
        b.temporal = cta.temporal;
        b.bucle = cta.bucle;
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
    for l en cuerpos { apuntar_nombres(vista(l), "ss_lista_", usadas); }
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

    // Lo mismo con los mapas y los tipos resultado.
    var usados_m: mapa<str, usize> = [];
    var usados_r: mapa<str, usize> = [];
    for l en cuerpos {
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
        for l en cuerpos { apuntar_nombres(vista(l), vista(prefijo), usadas_g); }
        for u en claves(usadas_g) {
            if !tiene(vistas_inst, vista(u)) {
                imprimir_error($"tcodec: la copia `{u}` se usa y no se escribio\n");
                return 1;
            }
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
        anadir(arit, $"SS_LANG_CONV({destino}, {td}, {origen}, {to})");
    }
    if largo(arit) > 0 { anadir(arit, vacio()); }

    let cabecera = try leer_archivo($"{raiz}/runtime/cabecera.inc");

    // El mismo orden que el original: cabecera, structs y resultados,
    // liberadores, la aritmetica, el hueco de los copiadores (su linea en
    // blanco va siempre), los prototipos, y cada funcion con su linea en
    // blanco detras.
    var todas: lista<str> = [];
    anadir(todas, cabecera);
    for x en partes { anadir(todas, copiar(x)); }
    for a en arit { anadir(todas, copiar(a)); }
    anadir(todas, vacio());
    for p en protos { anadir(todas, copiar(p)); }
    anadir(todas, vacio());
    for l en cuerpos { anadir(todas, copiar(l)); }

    var todo = vacio();
    var primero = true;
    for x en todas {
        if !primero { empujar(todo, "\n"); }
        primero = false;
        empujar(todo, vista(x));
    }
    imprimir(todo);
    return 0;
}
