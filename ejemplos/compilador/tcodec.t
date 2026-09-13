// tcodec.t — el archivo C entero, escrito por Tcode.
//
// El paso que separa "piezas que coinciden" de "un compilador": la cabecera,
// la aritmetica que el programa usa, los prototipos y todas las funciones,
// `main` incluida, en el orden en que las escribe el generador de Python y
// con el mismo C. Lo que todavia no sabe escribir entero lo rechaza por la
// salida de error, sin escribir medio archivo.
//
//     TCODE_RAIZ=. ./tcodec ejemplos/hola.t > hola.c

usar "lib/programa.t" como F;
usar "lib/generar.t" como G;
usar "lib/tipar.t" como I;
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
    if contiene(l, "ss_res_") || contiene(l, "ss_lista_") { return true; }
    if contiene(l, "ss_mapa_") || contiene(l, "ss_push_") { return true; }
    if contiene(l, "ss_copia_") || contiene(l, "ss_drop_") { return true; }
    if contiene(l, "ss_ordenar_") || contiene(l, "ss_bloque_") { return true; }
    if contiene(l, "ss_arr_") || contiene(l, "ss_fn_") { return true; }
    if contiene(l, "ss_cierre_") || contiene(l, "ss_lang_cstr_") { return true; }
    if contiene(l, "ss_lang_leer_") || contiene(l, "ss_lang_escribir_") {
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

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t>\n");
        return 2;
    }
    let ruta = argumento(1);
    var tipos = I.contexto();
    let arbol = try F.preparar(ruta, tipos);

    // Este hito escribe programas de un solo archivo, sin tipos propios.
    for d en arbol.hijos {
        let clase = vista(d.clase);
        if !igual(clase, "fn") {
            imprimir_error($"tcodec: todavia no se escribir `{clase}`\n");
            return 1;
        }
        if F.es_generica(d) {
            imprimir_error("tcodec: todavia no se escribir genericas\n");
            return 1;
        }
    }

    var protos: lista<str> = [];
    var cuerpos: lista<str> = [];
    var anchos: mapa<str, usize> = [];
    var decimales: mapa<str, usize> = [];
    var conversiones: mapa<str, usize> = [];
    for d en arbol.hijos {
        let lineas = F.generar_funcion(d, tipos, ruta);
        if largo(lineas) == 0 {
            imprimir_error($"tcodec: no se escribir `{d.texto}` entera\n");
            return 1;
        }
        if !igual(vista(d.texto), "main") {
            var p = copiar(lineas[1]);
            empujar(p, ";");
            anadir(protos, p);
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

    // Solo los anchos que el programa usa, y en el mismo orden que el
    // original: el de los nombres.
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
    // `f64_de_usize`: el destino y el origen, ordenados por ese orden.
    var cs: lista<str> = [];
    for c en claves(conversiones) {
        let corte = buscar_desde(vista(c), "_de_", 0);
        if corte < largo(vista(c)) {
            let destino = rebanar(vista(c), 0, corte);
            let origen = rebanar(vista(c), corte + 4, largo(vista(c)));
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

    let raiz = variable_entorno("TCODE_RAIZ") sino nuevo(".");
    let cabecera = try leer_archivo($"{raiz}/runtime/cabecera.inc");

    // El mismo orden que el original: la cabecera, la aritmetica, el hueco
    // de los copiadores (vacio, pero su linea en blanco va siempre), los
    // prototipos, y cada funcion con su linea en blanco detras.
    var partes: lista<str> = [];
    anadir(partes, cabecera);
    for a en arit { anadir(partes, copiar(a)); }
    anadir(partes, vacio());
    for p en protos { anadir(partes, copiar(p)); }
    anadir(partes, vacio());
    for l en cuerpos { anadir(partes, copiar(l)); }

    var todo = vacio();
    var primero = true;
    for x en partes {
        if !primero { empujar(todo, "\n"); }
        primero = false;
        empujar(todo, vista(x));
    }
    imprimir(todo);
    return 0;
}
