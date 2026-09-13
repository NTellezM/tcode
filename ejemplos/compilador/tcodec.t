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
    if contiene(l, "ss_mapa_") || contiene(l, "ss_copia_") { return true; }
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

// Lo que este hito no sabe escribir todavia: mapas, bloques y arreglos.
fn es_otra_coleccion(t: view) -> bool {
    return contiene(t, "mapa<") || contiene(t, "bloque<") || contiene(t, "[");
}

// Registra `t` si es una lista, la de dentro primero. Falso si es algo que
// este hito todavia no escribe.
fn mirar_tipo(t: view, listas: mut lista<str>, vistas: mut mapa<str, usize>) -> bool {
    if es_otra_coleccion(t) {
        // Un prestamo no registra nada, como en el original.
        return empieza_con(t, "&");
    }
    if !es_lista_t(t) { return true; }
    if tiene(vistas, t) { return true; }
    let dentro = interior_lista(t);
    if es_lista_t(vista(dentro)) {
        if !mirar_tipo(vista(dentro), listas, vistas) { return false; }
    }
    poner(vistas, t, 1);
    anadir(listas, nuevo(t));
    return true;
}

fn mirar_bloque(n: &P.Nodo, tipos: mut I.Contexto, listas: mut lista<str>,
    vistas: mut mapa<str, usize>) -> bool {
    I.abrir(tipos);
    var bien = true;
    for st en n.hijos {
        let clase = vista(st.clase);
        if igual(clase, "declaracion") && largo(st.hijos) == 1 {
            let nombre = G.nombre_declarado(vista(st.texto));
            var escrito = G.tipo_escrito(vista(st.texto));
            if largo(escrito) == 0 { escrito = I.tipo_de(tipos, st.hijos[0]); }
            let t = I.sin_alias_tipo(vista(escrito));
            if bien { bien = mirar_tipo(vista(t), listas, vistas); }
            I.declarar(tipos, vista(nombre), vista(t));
        }
        if igual(clase, "si") {
            var k = 1;
            while k < largo(st.hijos) {
                if bien { bien = mirar_bloque(st.hijos[k], tipos, listas, vistas); }
                k = k + 1;
            }
        }
        if igual(clase, "mientras") && largo(st.hijos) == 2 {
            if bien { bien = mirar_bloque(st.hijos[1], tipos, listas, vistas); }
        }
    }
    I.cerrar(tipos);
    return bien;
}

fn mirar_funcion(d: &P.Nodo, tipos: mut I.Contexto, listas: mut lista<str>,
    vistas: mut mapa<str, usize>) -> bool {
    let r = retorno_de(d);
    if !mirar_tipo(vista(r), listas, vistas) { return false; }
    I.abrir(tipos);
    var bien = true;
    for h en d.hijos {
        if igual(vista(h.clase), "param") {
            let pelado = F.tipo_pelado(vista(h.texto));
            let t = I.sin_alias_tipo(vista(pelado));
            if bien { bien = mirar_tipo(vista(t), listas, vistas); }
            let pn = F.nombre_de(vista(h.texto));
            I.declarar(tipos, vista(pn), vista(t));
        }
    }
    for h en d.hijos {
        if igual(vista(h.clase), "bloque") && bien {
            bien = mirar_bloque(h, tipos, listas, vistas);
        }
    }
    I.cerrar(tipos);
    return bien;
}

fn poner_typedef_lista(t: view, vistas: &mapa<str, usize>,
    puestos: mut mapa<str, usize>, salida: mut lista<str>) {
    if tiene(puestos, t) || !tiene(vistas, t) { return; }
    poner(puestos, t, 1);
    let dentro = interior_lista(t);
    poner_typedef_lista(vista(dentro), vistas, puestos, salida);
    let te = G.tipo_c(vista(dentro));
    let tc = G.tipo_c(t);
    anadir(salida, $"typedef struct {{ {te}* e; size_t length; size_t capacity; }} {tc};");
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
    for m en modulos {
        var tipos = I.contexto();
        let arbol = try F.preparar(vista(m), tipos);
        F.recoger_firmas(arbol, global);
        for d en arbol.hijos {
            let clase = vista(d.clase);
            if igual(clase, "usar") || igual(clase, "alias") { continue; }
            if igual(clase, "fn") {
                if F.es_generica(d) { return rechazo("genericas"); }
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
                        if es_otra_coleccion(vista(t)) || (contiene(vista(t), "<")
                            && !es_lista_t(vista(t))) {
                            return rechazo("mapas, bloques ni arreglos en un struct");
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

    // Las listas, con el mismo recorrido que el original: en orden de
    // declaracion, campos de struct y funciones entremezclados.
    var listas: lista<str> = [];
    var vistas: mapa<str, usize> = [];
    var im = 0;
    while im < largo(arboles) {
        for d en arboles[im].hijos {
            if igual(vista(d.clase), "struct") {
                for h en d.hijos {
                    if igual(vista(h.clase), "campo_def") {
                        let tp = F.tipo_pelado(vista(h.texto));
                        let t = I.sin_alias_tipo(vista(tp));
                        if !mirar_tipo(vista(t), listas, vistas) {
                            return rechazo("mapas, bloques ni arreglos");
                        }
                    }
                }
            }
            if igual(vista(d.clase), "fn") {
                if !mirar_funcion(d, contextos[im], listas, vistas) {
                    return rechazo("mapas, bloques ni arreglos");
                }
            }
        }
        im = im + 1;
    }

    // Los tipos resultado, en el orden en que el original los registra: el
    // de declaracion, recorriendo los modulos en orden.
    var resultados: lista<str> = [];
    var ya: mapa<str, usize> = [];
    for arbol en arboles {
        for d en arbol.hijos {
            if igual(vista(d.clase), "fn") && es_falible(d) {
                var r = retorno_de(d);
                if igual(vista(r), "()") { r = vacio(); }
                if !tiene(ya, vista(r)) {
                    poner(ya, vista(r), 1);
                    anadir(resultados, r);
                }
            }
        }
    }
    // Las internas falibles registran el suyo despues, al recorrer todo.
    var usa_leer_archivo = false;
    for arbol en arboles {
        if llama_a(arbol, "leer_archivo") { usa_leer_archivo = true; }
    }
    if usa_leer_archivo && !tiene(ya, "str") {
        poner(ya, "str", 1);
        anadir(resultados, nuevo("str"));
    }

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
    for x en listas { anadir(ordenadas, copiar(x)); }
    ordenar(ordenadas);
    var puestos: mapa<str, usize> = [];
    for x en ordenadas { poner_typedef_lista(vista(x), vistas, puestos, partes); }
    if largo(listas) > 0 { anadir(partes, vacio()); }
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
    for r en resultados { anadir(partes, typedef_resultado(vista(r))); }
    if largo(resultados) > 0 { anadir(partes, vacio()); }
    if usa_leer_archivo { ayudante_leer_archivo(partes); }
    for x en listas { funcion_push(vista(x), partes); }
    for x en listas { funcion_ordenar(vista(x), partes); }

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
            if !igual(vista(d.clase), "fn") { continue; }
            let lineas = F.generar_funcion(d, contextos[i], vista(modulos[i]), cta);
            if largo(lineas) == 0 {
                imprimir_error($"tcodec: no se escribir `{d.texto}` entera\n");
                return 1;
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
                    return 1;
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
        }
        i = i + 1;
    }

    // Toda lista que aparezca en un cuerpo tiene que tener su typedef: si el
    // recorrido no la registro, el C no compilaria. Mejor no escribirlo.
    var usadas: mapa<str, usize> = [];
    for l en cuerpos { apuntar_nombres(vista(l), "ss_lista_", usadas); }
    var registradas: mapa<str, usize> = [];
    for x en listas {
        let nombre_c = G.tipo_c(vista(x));
        poner(registradas, vista(nombre_c), 1);
    }
    for u en claves(usadas) {
        if !tiene(registradas, vista(u)) {
            imprimir_error($"tcodec: `{u}` se usa y el recorrido no la registro\n");
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
