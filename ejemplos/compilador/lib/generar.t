// lib/generar.t — el C de cada tipo y de cada firma, escrito en Tcode.
//
// Sexta capa del compilador en su propio lenguaje, y la primera del
// generador. Aqui esta la cara que el C ve de un programa Tcode: como se
// llama cada tipo, y como queda la firma de cada funcion.
//
// La suite compara lo que sale de aqui con lo que emite el generador de
// Python, cadena por cadena, para cada funcion del repositorio.

usar "tipos.t" como T;
usar "tipar.t" como I;
usar "../../lexer/lib/sintaxis.t" como P;
usar "../../lexer/lib/lexico.t" como L;
usar "std/texto";
usar "std/lista";

// El nombre C de un tipo compuesto: `[usize; 3]` es `arr_usize_3`.
// Tiene que dar exactamente lo mismo que el generador de Python, porque de
// ahi salen los nombres de todas las funciones que este genera.
fn mangle(t: view) -> str {
    if T.es_referencia(t) {
        var s = nuevo("ref_");
        if empieza_con(t, "&mut ") { s = nuevo("refmut_"); }
        let dentro = T.apuntado(t);
        let m = mangle(dentro);
        empujar(s, vista(m));
        return s;
    }
    if T.es_arreglo(t) {
        let elem = T.elemento(t);
        var s = nuevo("arr_");
        let m = mangle(vista(elem));
        empujar(s, vista(m));
        empujar(s, "_");
        empujar(s, cuantos_de_arreglo(t));
        return s;
    }
    if T.es_bloque(t) {
        var s = nuevo("bloque_");
        let dentro = T.elemento(t);
        let m = mangle(vista(dentro));
        empujar(s, vista(m));
        return s;
    }
    if T.es_mapa(t) {
        let partes = T.partir_tipos(T.entre_angulos(t));
        if largo(partes) != 2 { return nuevo(t); }
        var s = nuevo("mapa_");
        let k = mangle(vista(partes[0]));
        let v = mangle(vista(partes[1]));
        empujar(s, vista(k));
        empujar(s, "_");
        empujar(s, vista(v));
        return s;
    }
    if T.es_lista(t) {
        var s = nuevo("lista_");
        let dentro = T.elemento(t);
        let m = mangle(vista(dentro));
        empujar(s, vista(m));
        return s;
    }
    if T.es_funcion(t) {
        let partes = T.partes_de_funcion(t);
        if largo(partes) == 0 { return nuevo(t); }
        var s = nuevo("fn_");
        var i = 0;
        while i + 1 < largo(partes) {
            if i > 0 { empujar(s, "_"); }
            let pieza = mangle(vista(partes[i]));
            empujar(s, vista(pieza));
            i = i + 1;
        }
        if largo(partes) == 1 { empujar(s, "nada"); }
        empujar(s, "_a_");
        let ultimo = mangle(vista(partes[largo(partes) - 1]));
        empujar(s, vista(ultimo));
        return s;
    }
    // `()` no es un nombre valido en C.
    if igual(t, "()") { return nuevo("nada"); }
    if I.es_aplicacion(t) { return I.nombre_resuelto(t); }
    // El alias del modulo —`P.Nodo`— es cosa de quien lee el archivo.
    return I.sin_modulo(t);
}

// El `4` de `[usize; 4]`.
fn cuantos_de_arreglo(t: view) -> str {
    // El `;` de fuera: el de `[[usize; 2]; 3]` es el que va antes del 3.
    var i = largo(t);
    while i > 0 {
        i = i - 1;
        if byte(t, i) == 59 {
            return nuevo(recortar(rebanar(t, i + 1, largo(t) - 1)));
        }
    }
    return nuevo("0");
}

// El tipo de C que le corresponde. Los compuestos van envueltos en un
// struct con nombre: en C un arreglo desnudo no se puede asignar ni
// devolver, y envolverlo le devuelve la semantica de valor que el lenguaje
// promete.
fn tipo_c(t: view) -> str {
    if igual(t, "str") { return nuevo("SafeString"); }
    if igual(t, "view") { return nuevo("SafeView"); }
    if igual(t, "bool") { return nuevo("bool"); }
    if igual(t, "usize") { return nuevo("size_t"); }
    if igual(t, "u8") { return nuevo("uint8_t"); }
    if igual(t, "u16") { return nuevo("uint16_t"); }
    if igual(t, "u32") { return nuevo("uint32_t"); }
    if igual(t, "u64") { return nuevo("uint64_t"); }
    if igual(t, "i8") { return nuevo("int8_t"); }
    if igual(t, "i16") { return nuevo("int16_t"); }
    if igual(t, "i32") { return nuevo("int32_t"); }
    if igual(t, "i64") { return nuevo("int64_t"); }
    if igual(t, "f32") { return nuevo("float"); }
    if igual(t, "f64") { return nuevo("double"); }
    if igual(t, "()") || largo(t) == 0 { return nuevo("void"); }

    if T.es_referencia(t) {
        // Un prestamo es un puntero. El de solo lectura sale `const`, asi
        // que el propio compilador de C impide escribir por el.
        let dentro = T.apuntado(t);
        var s = vacio();
        if !empieza_con(t, "&mut ") { empujar(s, "const "); }
        let base = tipo_c(dentro);
        empujar(s, vista(base));
        empujar(s, "*");
        return s;
    }
    if T.es_arreglo(t) || T.es_bloque(t) || T.es_mapa(t) || T.es_lista(t)
    || T.es_funcion(t) {
        var s = nuevo("ss_");
        let m = mangle(t);
        empujar(s, vista(m));
        return s;
    }
    // Un struct generico aplicado se llama en C como su copia.
    if I.es_aplicacion(t) { return I.nombre_resuelto(t); }
    // Un struct se llama igual en los dos lados. El alias con el que se
    // escribio —`P.Nodo`— es cosa de quien lee el archivo: en C no queda.
    return I.sin_modulo(t);
}

// El `T !` de Tcode es un struct: `motivo == NULL` significa que fue bien.
fn tipo_resultado(t: view) -> str {
    var s = nuevo("ss_res_");
    if largo(t) == 0 || igual(t, "()") {
        empujar(s, "unidad");
        return s;
    }
    let m = mangle(t);
    empujar(s, vista(m));
    return s;
}

// ------------------------------------------------------------------
// Nombres que no pueden ir tal cual a C
// ------------------------------------------------------------------

// Tcode no tiene las palabras de C, asi que `union`, `log` o `EOF` son
// nombres legales. Pero el C generado incluye `math.h`, `stdio.h` y
// compania, y ahi `log` ya es una funcion y `EOF` una macro. Esos nombres
// llevan `ss_id_` delante en todo el arbol a la vez, antes de comprobar
// nada, y los mensajes lo quitan. Es la regla de `tcode/nombres_c.py`, con
// la misma lista: lo que declaran las cabeceras incluidas en C17 estricto,
// las palabras de C, lo del runtime y los nombres reservados de C.
fn nombres_de_c() -> mapa<str, usize> {
    var m: mapa<str, usize> = [];
    apuntar_nombres_c(m, "BUFSIZ CLOCKS_PER_SEC DBL_DECIMAL_DIG DBL_DIG DBL_EPSILON DBL_HAS_SUBNORM");
    apuntar_nombres_c(m, "DBL_MANT_DIG DBL_MAX DBL_MAX_10_EXP DBL_MAX_EXP DBL_MIN DBL_MIN_10_EXP");
    apuntar_nombres_c(m, "DBL_MIN_EXP DBL_TRUE_MIN DECIMAL_DIG EOF EXIT_FAILURE EXIT_SUCCESS FILE");
    apuntar_nombres_c(m, "FILENAME_MAX FLT_DECIMAL_DIG FLT_DIG FLT_EPSILON FLT_EVAL_METHOD FLT_HAS_SUBNORM");
    apuntar_nombres_c(m, "FLT_MANT_DIG FLT_MAX FLT_MAX_10_EXP FLT_MAX_EXP FLT_MIN FLT_MIN_10_EXP");
    apuntar_nombres_c(m, "FLT_MIN_EXP FLT_RADIX FLT_ROUNDS FLT_TRUE_MIN FOPEN_MAX FP_ILOGB0 FP_ILOGBNAN");
    apuntar_nombres_c(m, "FP_INFINITE FP_NAN FP_NORMAL FP_SUBNORMAL FP_ZERO HUGE_VAL HUGE_VALF HUGE_VALL");
    apuntar_nombres_c(m, "INFINITY INT16_C INT16_MAX INT16_MIN INT32_C INT32_MAX INT32_MIN INT64_C");
    apuntar_nombres_c(m, "INT64_MAX INT64_MIN INT8_C INT8_MAX INT8_MIN INTMAX_C INTMAX_MAX INTMAX_MIN");
    apuntar_nombres_c(m, "INTPTR_MAX INTPTR_MIN INT_FAST16_MAX INT_FAST16_MIN INT_FAST32_MAX");
    apuntar_nombres_c(m, "INT_FAST32_MIN INT_FAST64_MAX INT_FAST64_MIN INT_FAST8_MAX INT_FAST8_MIN");
    apuntar_nombres_c(m, "INT_LEAST16_MAX INT_LEAST16_MIN INT_LEAST32_MAX INT_LEAST32_MIN INT_LEAST64_MAX");
    apuntar_nombres_c(m, "INT_LEAST64_MIN INT_LEAST8_MAX INT_LEAST8_MIN LDBL_DECIMAL_DIG LDBL_DIG");
    apuntar_nombres_c(m, "LDBL_EPSILON LDBL_HAS_SUBNORM LDBL_MANT_DIG LDBL_MAX LDBL_MAX_10_EXP");
    apuntar_nombres_c(m, "LDBL_MAX_EXP LDBL_MIN LDBL_MIN_10_EXP LDBL_MIN_EXP LDBL_TRUE_MIN L_tmpnam");
    apuntar_nombres_c(m, "MATH_ERREXCEPT MATH_ERRNO MB_CUR_MAX NAN NULL PTRDIFF_MAX PTRDIFF_MIN RAND_MAX");
    apuntar_nombres_c(m, "SAFESTR_H SEEK_CUR SEEK_END SEEK_SET SIG_ATOMIC_MAX SIG_ATOMIC_MIN SIZE_MAX");
    apuntar_nombres_c(m, "SafeFreeFn SafeReallocFn SafeString SafeStringList SafeView TIME_UTC TMP_MAX");
    apuntar_nombres_c(m, "UINT16_C UINT16_MAX UINT32_C UINT32_MAX UINT64_C UINT64_MAX UINT8_C UINT8_MAX");
    apuntar_nombres_c(m, "UINTMAX_C UINTMAX_MAX UINTPTR_MAX UINT_FAST16_MAX UINT_FAST32_MAX");
    apuntar_nombres_c(m, "UINT_FAST64_MAX UINT_FAST8_MAX UINT_LEAST16_MAX UINT_LEAST32_MAX");
    apuntar_nombres_c(m, "UINT_LEAST64_MAX UINT_LEAST8_MAX WCHAR_MAX WCHAR_MIN WINT_MAX WINT_MIN abort abs");
    apuntar_nombres_c(m, "acos acosf acosh acoshf acoshl acosl alignas aligned_alloc alignof argc argv");
    apuntar_nombres_c(m, "asctime asin asinf asinh asinhf asinhl asinl assert at_quick_exit atan atan2");
    apuntar_nombres_c(m, "atan2f atan2l atanf atanh atanhf atanhl atanl atexit atof atoi atol atoll auto");
    apuntar_nombres_c(m, "break bsearch calloc case cbrt cbrtf cbrtl ceil ceilf ceill char clearerr clock");
    apuntar_nombres_c(m, "clock_t complex const constexpr continue copysign copysignf copysignl cos cosf");
    apuntar_nombres_c(m, "cosh coshf coshl cosl ctime default difftime div div_t do double double_t else");
    apuntar_nombres_c(m, "enum erf erfc erfcf erfcl erff erfl errno exit exp exp2 exp2f exp2l expf expl");
    apuntar_nombres_c(m, "expm1 expm1f expm1l extern fabs fabsf fabsl fclose fdim fdimf fdiml feof ferror");
    apuntar_nombres_c(m, "fflush fgetc fgetpos fgets float float_t floor floorf floorl fma fmaf fmal fmax");
    apuntar_nombres_c(m, "fmaxf fmaxl fmin fminf fminl fmod fmodf fmodl fopen for fpclassify fpos_t");
    apuntar_nombres_c(m, "fprintf fputc fputs fread free freopen frexp frexpf frexpl fscanf fseek fsetpos");
    apuntar_nombres_c(m, "ftell fwrite generic getc getchar getenv gmtime goto hypot hypotf hypotl if");
    apuntar_nombres_c(m, "ilogb ilogbf ilogbl imaginary inline int int16_t int32_t int64_t int8_t");
    apuntar_nombres_c(m, "int_fast16_t int_fast32_t int_fast64_t int_fast8_t int_least16_t int_least32_t");
    apuntar_nombres_c(m, "int_least64_t int_least8_t intmax_t intptr_t isfinite isgreater isgreaterequal");
    apuntar_nombres_c(m, "isinf isless islessequal islessgreater isnan isnormal isunordered labs ldexp");
    apuntar_nombres_c(m, "ldexpf ldexpl ldiv ldiv_t lgamma lgammaf lgammal llabs lldiv lldiv_t llrint");
    apuntar_nombres_c(m, "llrintf llrintl llround llroundf llroundl localtime log log10 log10f log10l");
    apuntar_nombres_c(m, "log1p log1pf log1pl log2 log2f log2l logb logbf logbl logf logl long lrint");
    apuntar_nombres_c(m, "lrintf lrintl lround lroundf lroundl malloc math_errhandling max_align_t mblen");
    apuntar_nombres_c(m, "mbstowcs mbtowc memchr memcmp memcpy memmove memset mktime modf modff modfl nan");
    apuntar_nombres_c(m, "nanf nanl nearbyint nearbyintf nearbyintl nextafter nextafterf nextafterl");
    apuntar_nombres_c(m, "nexttoward nexttowardf nexttowardl noreturn nullptr offsetof perror pow powf");
    apuntar_nombres_c(m, "powl printf ptrdiff_t putc putchar puts qsort quick_exit rand realloc register");
    apuntar_nombres_c(m, "remainder remainderf remainderl remove remquo remquof remquol rename restrict");
    apuntar_nombres_c(m, "return rewind rint rintf rintl round roundf roundl scalbln scalblnf scalblnl");
    apuntar_nombres_c(m, "scalbn scalbnf scalbnl scanf setbuf setvbuf short signbit signed sin sinf sinh");
    apuntar_nombres_c(m, "sinhf sinhl sinl size_t sizeof snprintf sprintf sqrt sqrtf sqrtl srand sscanf");
    apuntar_nombres_c(m, "static static_assert stderr stdin stdout strcat strchr strcmp strcoll strcpy");
    apuntar_nombres_c(m, "strcspn strerror strftime strlen strncat strncmp strncpy strpbrk strrchr strspn");
    apuntar_nombres_c(m, "strstr strtod strtof strtok strtol strtold strtoll strtoul strtoull struct");
    apuntar_nombres_c(m, "strxfrm sv switch system tan tanf tanh tanhf tanhl tanl tgamma tgammaf tgammal");
    apuntar_nombres_c(m, "thread_local time time_t timespec timespec_get tm tmpfile tmpnam trunc truncf");
    apuntar_nombres_c(m, "truncl typedef typeof typeof_unqual uint16_t uint32_t uint64_t uint8_t");
    apuntar_nombres_c(m, "uint_fast16_t uint_fast32_t uint_fast64_t uint_fast8_t uint_least16_t");
    apuntar_nombres_c(m, "uint_least32_t uint_least64_t uint_least8_t uintmax_t uintptr_t ungetc union");
    apuntar_nombres_c(m, "unsigned va_arg va_copy va_end va_list va_start vfprintf vfscanf void volatile");
    apuntar_nombres_c(m, "vprintf vscanf vsnprintf vsprintf vsscanf wchar_t wcstombs wctomb while");
    return m;
}

fn apuntar_nombres_c(m: mut mapa<str, usize>, cuales: view) {
    for n en palabras(cuales) { poner(m, vista(n), 1); }
}

fn choca_con_c(n: view, de_c: &mapa<str, usize>) -> bool {
    if tiene(de_c, n) { return true; }
    // Reservados de C: `_Bool`, `__func__`, y todo lo que empiece asi.
    if largo(n) > 1 && byte(n, 0) == 95
    && (byte(n, 1) == 95 || (byte(n, 1) >= 65 && byte(n, 1) <= 90)) {
        return true;
    }
    // El runtime y lo que escribe el generador: `ss_free`, `SV_FMT`,
    // `ss_tmp1`, `SS_E_A`.
    if empieza_con(n, "ss_") || empieza_con(n, "sv_") || empieza_con(n, "SS_")
    || empieza_con(n, "SV_") {
        return true;
    }
    // El struct de una clausura.
    if !empieza_con(n, "Cierre_") || largo(n) == 7 { return false; }
    var i = 7;
    while i < largo(n) {
        if byte(n, i) < 48 || byte(n, i) > 57 { return false; }
        i = i + 1;
    }
    return true;
}

// El nombre que se escribio, sin el prefijo que le puso el cargador.
fn escrito(n: view) -> str {
    if empieza_con(n, "ss_id_") { return nuevo(rebanar(n, 6, largo(n))); }
    return nuevo(n);
}

fn empieza_nombre(c: usize) -> bool {
    return (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95;
}

// Un mensaje con los nombres como se escribieron.
fn legible_c(t: view) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(t) {
        if empieza_nombre(byte(t, i)) {
            var j = i;
            while j < largo(t) && I.es_de_nombre(byte(t, j)) { j = j + 1; }
            let e = escrito(rebanar(t, i, j));
            empujar(r, vista(e));
            i = j;
        } else {
            empujar(r, rebanar(t, i, i + 1));
            i = i + 1;
        }
    }
    return r;
}

fn nombre_para_c(n: view, de_c: &mapa<str, usize>, intocables: &lista<str>) -> str {
    if !choca_con_c(n, de_c) { return nuevo(n); }
    for x en intocables {
        if igual(vista(x), n) { return nuevo(n); }
    }
    return $"ss_id_{n}";
}

// Cada nombre de un texto del arbol, cambiado si choca. Uno seguido de `.`
// es el alias de un modulo, que no llega a C; con `solo_el_primero`, lo que
// hay detras del punto es la forma de un enum, que tampoco.
fn texto_para_c(t: view, de_c: &mapa<str, usize>, intocables: &lista<str>,
    solo_el_primero: bool) -> str {
    var r = vacio();
    var i = 0;
    var visto_punto = false;
    while i < largo(t) {
        let c = byte(t, i);
        if c == 46 { visto_punto = true; }
        if !empieza_nombre(c) {
            empujar(r, rebanar(t, i, i + 1));
            i = i + 1;
            continue;
        }
        var j = i;
        while j < largo(t) && I.es_de_nombre(byte(t, j)) { j = j + 1; }
        let n = rebanar(t, i, j);
        if (solo_el_primero && visto_punto) || (j < largo(t) && byte(t, j) == 46 && !solo_el_primero) {
            empujar(r, n);
        } else {
            let otro = nombre_para_c(n, de_c, intocables);
            empujar(r, vista(otro));
        }
        i = j;
    }
    return r;
}

// Los nombres de las funciones de un `externo`: son los de C, y no se tocan.
fn externas_de(arbol: &P.Nodo, salida: mut lista<str>) {
    for d en arbol.hijos {
        if !igual(vista(d.clase), "externo") { continue; }
        for f en d.hijos { anadir(salida, copiar(f.texto)); }
    }
}

// Todo el arbol con los nombres que chocan con C cambiados. Los literales,
// las rutas, los operadores y las formas de un enum no son nombres de C.
fn renombrar_para_c(n: mut P.Nodo, de_c: &mapa<str, usize>, intocables: &lista<str>) {
    let clase = copiar(n.clase);
    let cl = vista(clase);
    let fijo = igual(cl, "cadena") || igual(cl, "interpolada") || igual(cl, "entero")
    || igual(cl, "decimal") || igual(cl, "booleano") || igual(cl, "falla")
    || igual(cl, "usar") || igual(cl, "alias") || igual(cl, "externo") || igual(cl, "externa")
    || igual(cl, "variante") || igual(cl, "binaria") || igual(cl, "unaria");
    if !fijo {
        let forma = igual(cl, "enum_lit") || igual(cl, "brazo") || igual(cl, "patron");
        n.texto = texto_para_c(vista(n.texto), de_c, intocables, forma);
    }
    var i = 0;
    while i < largo(n.hijos) {
        renombrar_para_c(n.hijos[i], de_c, intocables);
        i = i + 1;
    }
}

// La firma en C de una funcion. `main` es el unico nombre que cambia: el de
// verdad lo pone el generador para poder recoger los argumentos.
fn prototipo(nombre: view, params: &lista<str>, marcas: &lista<str>,
    retorno: view, falible: bool) -> str {
    if igual(nombre, "main") && !falible {
        return nuevo("int main(int argc, char** argv)");
    }

    var salida = vacio();
    if falible {
        let r = tipo_resultado(retorno);
        empujar(salida, vista(r));
    } else {
        let r = tipo_c(retorno);
        empujar(salida, vista(r));
    }
    empujar(salida, " ");
    if igual(nombre, "main") { empujar(salida, "ss_main_"); }
    else { empujar(salida, nombre); }
    empujar(salida, "(");

    if largo(params) == 0 {
        empujar(salida, "void)");
        return salida;
    }

    var i = 0;
    while i < largo(params) {
        if i > 0 { empujar(salida, ", "); }
        empujar(salida, "SS_LANG_QUIZA_SIN_USAR ");
        let solo = marca_sola(vista(marcas[i]));
        let marca = vista(solo);
        let base = tipo_c(vista(params[i]));
        if empieza_con(marca, "&mut ") || empieza_con(marca, "mut ") {
            empujar(salida, base);
            empujar(salida, "* ");
        } else {
            if empieza_con(marca, "&") {
                empujar(salida, "const ");
                empujar(salida, base);
                empujar(salida, "* ");
            } else {
                empujar(salida, base);
                empujar(salida, " ");
            }
        }
        let pn = nombre_de_param(vista(marcas[i]));
        empujar(salida, vista(pn));
        i = i + 1;
    }
    empujar(salida, ")");
    return salida;
}

// Las marcas llegan como `nombre: &`, con el nombre delante para no tener
// que pasar dos listas. Esto saca la parte de detras.
fn marca_sola(marcado: view) -> str {
    var i = 0;
    while i + 1 < largo(marcado) {
        if byte(marcado, i) == 58 {
            if byte(marcado, i + 1) == 32 {
                return nuevo(rebanar(marcado, i + 2, largo(marcado)));
            }
        }
        i = i + 1;
    }
    return vacio();
}

fn nombre_de_param(marcado: view) -> str {
    var i = 0;
    while i < largo(marcado) {
        if byte(marcado, i) == 58 { return nuevo(rebanar(marcado, 0, i)); }
        i = i + 1;
    }
    return nuevo(marcado);
}

// ------------------------------------------------------------------
// Expresiones
// ------------------------------------------------------------------
//
// El C de una expresion. Solo las que no necesitan emitir lineas aparte:
// un temporal o una bandera hay que declararlos antes, y eso es del cuerpo,
// no de la expresion. Lo que no se sabe hacer sale como `?`, y la suite
// cuenta cuantas se cubren en vez de fingir que son todas.

struct Sitio {
    archivo: str,
    // nombre -> tipo, para elegir el ancho de la aritmetica comprobada
    tipos: mapa<str, str>,
    // nombres que en C son punteros: parametros prestados
    punteros: mapa<str, usize>,
    // nombres que se entregan por algun camino: su liberacion la decide una
    // bandera `ss_vivo_X` en vez de hacerse siempre
    pide_bandera: mapa<str, usize>,
    // lo que devuelve la funcion que se esta generando: `try` sale por ahi
    retorno: str,
    // los campos que el comprobador vio sacar de su struct:
    // `archivo\tlinea\tp.a.b`
    sacados: mapa<str, usize>,
}

// Que nombres son un puntero en el C generado: los parametros prestados, y
// tambien un local cuyo tipo es un prestamo. `let xs = try obtener(m, k)` da
// un `&lista<str>`, y eso en C es un puntero como cualquier otro.
fn es_puntero(s: &Sitio, tipos: &I.Contexto, nombre: view) -> bool {
    if tiene(s.punteros, nombre) { return true; }
    let t = I.buscar(tipos, nombre);
    return T.es_referencia(vista(t));
}

fn no_se() -> str { return nuevo("?"); }

fn es_desconocido(c: view) -> bool { return igual(c, "?"); }

fn sin_ceros_izquierda(valor: view) -> view {
    var i = 0;
    while i + 1 < largo(valor) && byte(valor, i) == 48 { i = i + 1; }
    return rebanar(valor, i, largo(valor));
}

fn limite_literal_entero(tipo: view, negativo: bool) -> str {
    if igual(tipo, "u8") { return nuevo("255"); }
    if igual(tipo, "u16") { return nuevo("65535"); }
    if igual(tipo, "u32") { return nuevo("4294967295"); }
    if igual(tipo, "u64") || igual(tipo, "usize") {
        return nuevo("18446744073709551615");
    }
    if igual(tipo, "i8") {
        return nuevo(if negativo { "128" } else { "127" });
    }
    if igual(tipo, "i16") {
        return nuevo(if negativo { "32768" } else { "32767" });
    }
    if igual(tipo, "i32") {
        return nuevo(if negativo { "2147483648" } else { "2147483647" });
    }
    if igual(tipo, "i64") {
        return nuevo(if negativo { "9223372036854775808" }
            else { "9223372036854775807" });
    }
    return vacio();
}

fn cabe_literal_entero(valor: view, tipo: view, negativo: bool) -> bool {
    let limite = limite_literal_entero(tipo, negativo);
    if largo(limite) == 0 { return true; }
    if negativo && !empieza_con(tipo, "i") { return false; }
    let limpio = sin_ceros_izquierda(valor);
    if largo(limpio) < largo(limite) { return true; }
    if largo(limpio) > largo(limite) { return false; }
    return igual(limpio, limite) || menor(limpio, limite);
}

// Compara el texto decimal sin convertirlo primero a `f64`: precisamente hay
// que decidir si esa conversion produciria infinito. Se normaliza a
// `cifras * 10^orden` y se compara con el punto en que C redondea a infinito.
fn cabe_literal_decimal(valor: view, tipo: view) -> bool {
    var fin_mantisa = largo(valor);
    var punto = largo(valor);
    var i = 0;
    while i < largo(valor) {
        let c = byte(valor, i);
        if c == 46 { punto = i; }
        if c == 101 || c == 69 { fin_mantisa = i; break; }
        i = i + 1;
    }
    let antes = if punto < fin_mantisa { punto } else { fin_mantisa };

    var cifras = vacio();
    var ceros = 0;
    var empezo = false;
    i = 0;
    while i < fin_mantisa {
        let c = byte(valor, i);
        if c != 46 {
            if !empezo && c == 48 { ceros = ceros + 1; }
            else {
                empezo = true;
                empujar_byte(cifras, c como u8);
            }
        }
        i = i + 1;
    }
    if !empezo { return true; }

    var orden: i64 = (antes como i64) - (ceros como i64) - 1;
    if fin_mantisa < largo(valor) {
        i = fin_mantisa + 1;
        var exp_negativo = false;
        if i < largo(valor) && (byte(valor, i) == 43 || byte(valor, i) == 45) {
            exp_negativo = byte(valor, i) == 45;
            i = i + 1;
        }
        var exp: i64 = 0;
        while i < largo(valor) {
            if exp > 1000 { return exp_negativo; }
            exp = exp * 10 + ((byte(valor, i) - 48) como i64);
            i = i + 1;
        }
        if exp > 1000 { return exp_negativo; }
        if exp_negativo { orden = orden - exp; }
        else { orden = orden + exp; }
    }

    let max_orden: i64 = if igual(tipo, "f32") { 38 } else { 308 };
    if orden < max_orden { return true; }
    if orden > max_orden { return false; }
    // El umbral es el maximo mas media unidad de su ultima cifra: ahi C ya
    // redondea a infinito (el empate va al par, que es infinito). Por debajo,
    // `3.4028235e38` redondea al maximo de `f32` y vale.
    var umbral = nuevo("340282356779733661637539395458142568448");
    if igual(tipo, "f64") {
        umbral = nuevo("179769313486231580793728971405303415079934132710037826936173");
        empujar(umbral, "778980444968292764750946649017977587207096330286416692887910");
        empujar(umbral, "946555547851940402630657488671505820681908902000708383676273");
        empujar(umbral, "854845817711531764475730270069855571366959622842914819860834");
        empujar(umbral, "936475292719074168444365510704342711559699508093042880177904");
        empujar(umbral, "174497792");
    }
    i = 0;
    while i < largo(vista(umbral)) {
        let dado = if i < largo(cifras) { byte(vista(cifras), i) } else { 48 };
        let tope = byte(vista(umbral), i);
        if dado < tope { return true; }
        if dado > tope { return false; }
        i = i + 1;
    }
    // Igual al umbral, o mayor por las cifras que siguen: infinito.
    return false;
}

fn literal_entero(texto: view, esperado: view) -> str {
    // `010` es diez, no el ocho octal que leeria C.
    let valor = sin_ceros_izquierda(texto);
    if igual(esperado, "f64") || igual(esperado, "f32") {
        if !entero_exacto_en(valor, esperado) { return no_se(); }
        var s = nuevo(valor);
        empujar(s, ".0");
        if igual(esperado, "f32") { empujar(s, "f"); }
        return s;
    }
    if es_entero(esperado) && !cabe_literal_entero(valor, esperado, false) {
        return no_se();
    }
    // Sin sufijo, un literal por encima de 2^63-1 no cabe en el tipo que C le
    // asigna por defecto y el compilador avisa.
    var s = nuevo("(");
    if es_entero(esperado) {
        let tc = tipo_c(esperado);
        empujar(s, vista(tc));
    } else { empujar(s, "size_t"); }
    empujar(s, ")");
    var numero = nuevo(valor);
    if mayor_que(valor, "9223372036854775807") { empujar(numero, "ULL"); }
    // El ancho de `size_t` es el del destino: por encima de 2^32 - 1 el C
    // comprueba al compilar que el literal cabe.
    if igual(vista(s), "(size_t)") && mayor_que(valor, "4294967295") {
        return $"SS_LANG_USIZE_LIT({numero})";
    }
    empujar(s, vista(numero));
    return s;
}

// Un entero escrito donde va un decimal tiene que caber exacto en la mantisa:
// sin contar los ceros binarios del final, no puede tener mas bits que ella.
fn entero_exacto_en(valor: view, tipo: view) -> bool {
    var v: u64 = 0;
    var i = 0;
    while i < largo(valor) {
        v = v * 10 + ((byte(valor, i) - 48) como u64);
        i = i + 1;
    }
    if v == 0 { return true; }
    while v % 2 == 0 { v = v / 2; }
    var bits: usize = 0;
    while v != 0 {
        bits = bits + 1;
        v = v / 2;
    }
    let mantisa: usize = if igual(tipo, "f32") { 24 } else { 53 };
    return bits <= mantisa;
}

fn mayor_que(valor: view, tope: view) -> bool {
    if largo(valor) > largo(tope) { return true; }
    if largo(valor) < largo(tope) { return false; }
    return menor(tope, valor);
}

// El tipo de un nombre segun lo que se sabe aqui.
fn tipo_de_nombre(s: &Sitio, nombre: view) -> str {
    if !tiene(s.tipos, nombre) { return vacio(); }
    return nuevo(obtener(s.tipos, nombre) sino "");
}

// La aritmetica comprobada tiene una familia por ancho, y el nombre lo elige
// el tipo de los operandos.
fn familia(op: view) -> str {
    if igual(op, "+") { return nuevo("suma"); }
    if igual(op, "-") { return nuevo("resta"); }
    if igual(op, "*") { return nuevo("mul"); }
    return vacio();
}

fn expresion_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, esperado: view, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);

    if igual(clase, "entero") { return literal_entero(vista(n.texto), esperado); }
    if igual(clase, "booleano") { return nuevo(vista(n.texto)); }

    // Una cadena escrita es una vista de si misma: no reserva nada, y vive
    // lo que vive el programa.
    if igual(clase, "cadena") { return como_vista(b, s, n, tipos); }

    if igual(clase, "expresion") {
        if largo(n.hijos) == 1 {
            return expresion_c(b, s, n.hijos[0], esperado, tipos);
        }
        return no_se();
    }

    if igual(clase, "variable") {
        let nombre = vista(n.texto);
        if es_puntero(s, tipos, nombre) {
            var v = nuevo("(*");
            empujar(v, nombre);
            empujar(v, ")");
            return v;
        }
        // El nombre de una funcion como valor: el puntero, que en C se
        // escribe igual que ella.
        if largo(I.buscar(tipos, nombre)) == 0
        && largo(I.firma_de_funcion(tipos, nombre)) > 0 {
            if tiene(tipos.repetidas, nombre) { return no_se(); }
            var en_c = I.sin_modulo(nombre);
            if tiene(tipos.renombradas, nombre) {
                en_c = nuevo(obtener(tipos.renombradas, nombre) sino "");
            }
            return en_c;
        }
        return nuevo(nombre);
    }

    if igual(clase, "cierre") { return cierre_c(b, s, n, tipos); }

    if igual(clase, "llamada") {
        // `reservar(n)` no dice de que: lo dice donde va.
        if igual(vista(n.texto), "reservar") { return reservar_c(b, s, n, esperado, tipos); }
        return llamada_c(b, s, n, tipos);
    }

    if igual(clase, "conversion") { return conversion_c(b, s, n, tipos); }

    if igual(clase, "literal_struct") {
        return literal_struct_c(b, s, n, esperado, tipos);
    }

    // `Json.Numero(42)`: la etiqueta de la forma y, en su hueco de la union,
    // lo que lleve. La variante se queda con lo que recibe.
    if igual(clase, "enum_lit") {
        let en_t = I.antes_del_punto(vista(n.texto));
        let cual = I.tras_el_punto(vista(n.texto));
        // Con el alias de un modulo delante no se sabe como quedo el nombre.
        if contiene(vista(cual), ".") { return no_se(); }
        let lleva = I.lista_de(tipos.formas, vista(n.texto)) sino [];
        if largo(lleva) != largo(n.hijos) { return no_se(); }
        let etq = etiqueta(vista(en_t), vista(cual));
        var r = $"({en_t}){{ .etiqueta = {etq}";
        var previos: lista<str> = [];
        abrir_marco(b);
        var i = 0;
        for h en n.hijos {
            let valor = expresion_c(b, s, h, vista(lleva[i]), tipos);
            if es_desconocido(vista(valor)) {
                let _m = cerrar_marco(b);
                return no_se();
            }
            reclamar(b, vista(valor));
            agregar_argumento_marcado(b, h, vista(valor), vista(lleva[i]), false,
                false, largo(n.hijos) > 1);
            i = i + 1;
        }
        let marco_v = cerrar_marco(b);
        i = 0;
        for p_v en marco_v.entradas {
            let pieza = $", .dato.v_{cual}._{i} = ";
            empujar(r, vista(pieza));
            if largo(p_v.tmp) > 0 {
                anadir(previos, $"{p_v.tmp} = {p_v.valor}");
                empujar(r, vista(p_v.tmp));
            } else {
                empujar(r, vista(p_v.valor));
            }
            i = i + 1;
        }
        empujar(r, " }");
        if largo(previos) > 0 {
            b.ultima_linea = 0;
            marcar(b, s, n.linea);
        }
        return envolver_llamada_ordenada(r, previos);
    }

    if igual(clase, "interpolada") { return interpolada_c(b, s, n, tipos); }

    if igual(clase, "si_expr") { return si_expr_c(b, s, n, esperado, tipos); }

    if igual(clase, "try") { return try_c(b, s, n, tipos); }
    if igual(clase, "sino") { return sino_c(b, s, n, tipos); }

    // Un `match` dentro de una expresion: su `switch` va delante, en lineas
    // propias, y la expresion lee el temporal donde deja el valor. Lo que
    // atrapan los brazos se declara en copias del sitio y de los tipos: al
    // cerrar el `match` ya no se ve. Un brazo que pida salir de la funcion
    // no se sabe hacer desde aqui, y la funcion entera se descarta.
    if igual(clase, "match") {
        var s_m = copiar(s);
        var t_m = copiar(tipos);
        return match_valor(b, s_m, n, t_m, vista(s.retorno), false);
    }

    // Un decimal va tal cual se escribio, con sufijo si el destino es de
    // 32 bits: `2.5` en un `f32` sin la `f` seria un `double` recortado.
    if igual(clase, "decimal") {
        if (igual(esperado, "f32") || igual(esperado, "f64"))
        && !cabe_literal_decimal(vista(n.texto), esperado) {
            return no_se();
        }
        var r = nuevo(vista(n.texto));
        if !contiene(vista(n.texto), ".") && !contiene(vista(n.texto), "e")
        && !contiene(vista(n.texto), "E") {
            empujar(r, ".0");
        }
        if igual(esperado, "f32") { empujar(r, "f"); }
        return r;
    }

    // `[a, b]` donde se espera una lista: nace vacia y se van metiendo.
    if igual(clase, "literal_lista") && T.es_lista(esperado) {
        let elem = T.elemento(esperado);
        let tmp = nuevo_temporal(b);
        var l = nuevo(tipo_c(esperado));
        empujar(l, " ");
        empujar(l, vista(tmp));
        empujar(l, " = { .e = NULL, .length = 0, .capacity = 0 };");
        emitir(b, vista(l));
        for x en n.hijos {
            let valor = expresion_c(b, s, x, vista(elem), tipos);
            if es_desconocido(vista(valor)) { return no_se(); }
            reclamar(b, vista(valor));
            var mete = nuevo("ss_push_");
            empujar(mete, mangle(esperado));
            empujar(mete, "(&");
            empujar(mete, vista(tmp));
            empujar(mete, ", ");
            empujar(mete, vista(valor));
            empujar(mete, ", \"");
            empujar(mete, vista(s.archivo));
            empujar(mete, "\", ");
            empujar(mete, texto(n.linea));
            empujar(mete, ");");
            emitir(b, vista(mete));
        }
        return copiar(tmp);
    }

    // `[a, b, c]` de tamaño fijo: un literal compuesto de C, de una vez.
    if igual(clase, "literal_lista") && !T.es_mapa(esperado) && largo(n.hijos) > 0 {
        var t = nuevo(esperado);
        if !T.es_arreglo(esperado) { t = I.tipo_de(tipos, n); }
        if !T.es_arreglo(vista(t)) { return no_se(); }
        let elem = T.elemento(vista(t));
        var piezas = vacio();
        var previos: lista<str> = [];
        abrir_marco(b);
        for x en n.hijos {
            let valor = expresion_c(b, s, x, vista(elem), tipos);
            if es_desconocido(vista(valor)) {
                let _m = cerrar_marco(b);
                return no_se();
            }
            reclamar(b, vista(valor));
            agregar_argumento_marcado(b, x, vista(valor), vista(elem), false, false,
                largo(n.hijos) > 1);
        }
        let marco_e = cerrar_marco(b);
        escribir_argumentos(marco_e, piezas, previos, ", ");
        apuntar_arreglo(b, vista(t));
        let tc = tipo_c(vista(t));
        let literal = $"({tc}){{{{ {piezas} }}}}";
        if largo(previos) > 0 {
            b.ultima_linea = 0;
            marcar(b, s, n.linea);
        }
        return envolver_llamada_ordenada(literal, previos);
    }

    // `[]` donde se espera un mapa: la tabla no nace hasta el primer
    // `poner`, que es donde el coste se ve.
    if igual(clase, "literal_lista") {
        if largo(n.hijos) != 0 { return no_se(); }
        if !T.es_mapa(esperado) { return no_se(); }
        var r = nuevo("(");
        empujar(r, tipo_c(esperado));
        empujar(r, "){ .claves = NULL, .valores = NULL, .largo = 0, ");
        empujar(r, ".capacidad = 0 }");
        return r;
    }

    if igual(clase, "campo") {
        // `sitio_c` ya devuelve el valor, no el puntero: un prestamo sale
        // como `(*x)`, asi que aqui siempre es un punto.
        let base = sitio_c(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(base)) { return no_se(); }
        var r = copiar(base);
        empujar(r, ".");
        empujar(r, vista(n.texto));
        let ruta = ruta_de_campo_c(n);
        if largo(ruta) > 0 && tiene(s.sacados, $"{s.archivo}\t{n.linea}\t{ruta}") {
            // Sacar un campo: se copia y su sitio queda a ceros, que es un
            // valor valido y al liberar el struct no suelta nada.
            let t = I.tipo_de(tipos, n);
            let tc = tipo_c(vista(t));
            let tmp = nuevo_temporal(b);
            emitir(b, $"{tc} {tmp};");
            return $"({tmp} = {r}, {r} = ({tc}){{0}}, {tmp})";
        }
        return r;
    }

    if igual(clase, "indice") {
        return indice_c(b, s, n, tipos);
    }

    if igual(clase, "binaria") {
        return binaria_c(b, s, n, esperado, tipos);
    }

    if igual(clase, "unaria") {
        let op = vista(n.texto);
        if largo(n.hijos) != 1 { return no_se(); }
        // `~` lleva molde para que el resultado no se ensanche por el camino.
        if igual(op, "~") {
            var t = I.tipo_de(tipos, n.hijos[0]);
            if !es_entero(vista(t)) { t = nuevo(esperado); }
            if !es_entero(vista(t)) { return no_se(); }
            let dentro = expresion_c(b, s, n.hijos[0], vista(t), tipos);
            if es_desconocido(vista(dentro)) { return no_se(); }
            let tc = tipo_c(vista(t));
            if empieza_con(vista(t), "i") {
                let ut = $"uint{rebanar(vista(t), 1, largo(vista(t)))}_t";
                return $"ss_lang_env_{t}(({ut}) ~({ut}) ({dentro}))";
            }
            return $"(({tc}) ~{dentro})";
        }
        if igual(op, "-") {
            var t = I.tipo_de(tipos, n.hijos[0]);
            if es_entero(esperado) || igual(esperado, "f32") || igual(esperado, "f64") {
                t = nuevo(esperado);
            } else {
                if igual(I.literal_de(n.hijos[0]), "entero") { t = nuevo("i64"); }
            }
            if empieza_con(vista(t), "i")
            && igual(vista(n.hijos[0].clase), "entero") {
                let valor = sin_ceros_izquierda(vista(n.hijos[0].texto));
                if !cabe_literal_entero(valor, vista(t), true) { return no_se(); }
                if (igual(vista(t), "i8") && igual(valor, "128"))
                || (igual(vista(t), "i16") && igual(valor, "32768"))
                || (igual(vista(t), "i32") && igual(valor, "2147483648"))
                || (igual(vista(t), "i64") && igual(valor, "9223372036854775808")) {
                    return $"INT{rebanar(vista(t), 1, largo(vista(t)))}_MIN";
                }
                return $"(({tipo_c(vista(t))})-{valor})";
            }
            if es_entero(vista(t)) && !empieza_con(vista(t), "i")
            && igual(vista(n.hijos[0].clase), "entero") {
                return no_se();
            }
            let dentro = expresion_c(b, s, n.hijos[0], vista(t), tipos);
            if es_desconocido(vista(dentro)) { return no_se(); }
            if empieza_con(vista(t), "i") {
                return $"ss_lang_neg_{t}({dentro}, \"{s.archivo}\", {n.linea})";
            }
            return $"(-{dentro})";
        }
        let dentro = expresion_c(b, s, n.hijos[0], esperado, tipos);
        if es_desconocido(vista(dentro)) { return no_se(); }
        var v = nuevo("(");
        empujar(v, op);
        empujar(v, vista(dentro));
        empujar(v, ")");
        return v;
    }

    return no_se();
}

// `$"van {n} de {total}"`. Se baja a un `str` que se va llenando: cada
// trozo se agrega tal cual y cada hueco pasa por la misma conversion que
// `imprimir`. No hay formato en tiempo de ejecucion ni un `printf` con
// cadena variable: el tipo de cada hueco se sabe al compilar, y por eso no
// existe aqui el fallo clasico de `%d` con un puntero.
fn interpolada_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo,
    tipos: &I.Contexto) -> str {
    let tmp = nuevo_temporal(b);
    var abre = nuevo("SafeString ");
    empujar(abre, vista(tmp));
    empujar(abre, " = ss_new();");
    emitir(b, vista(abre));
    apuntar_temporal(b, vista(tmp), "str");

    let crudo = vista(n.texto);
    var trozo = vacio();
    var cual = 0;
    var i = 0;
    while i < largo(crudo) {
        let c = byte(crudo, i);
        // Un escape va entero al trozo, que se descifra despues: `\{` es
        // una llave escrita, y la barra de `\\` no deja la siguiente suelta.
        if c == 92 && i + 1 < largo(crudo) {
            empujar(trozo, rebanar(crudo, i, i + 2));
            i = i + 2;
            continue;
        }
        // `{{` y `}}` son una llave escrita, no un hueco.
        if c == 123 && i + 1 < largo(crudo) && byte(crudo, i + 1) == 123 {
            empujar(trozo, "{");
            i = i + 2;
            continue;
        }
        if c == 125 && i + 1 < largo(crudo) && byte(crudo, i + 1) == 125 {
            empujar(trozo, "}");
            i = i + 2;
            continue;
        }
        if c != 123 {
            empujar(trozo, rebanar(crudo, i, i + 1));
            i = i + 1;
            continue;
        }

        if largo(trozo) > 0 {
            agregar_trozo(b, s, vista(tmp), vista(trozo), n.linea);
            trozo = vacio();
        }
        if cual >= largo(n.hijos) { return no_se(); }
        let dado = hueco_c(b, s, n.hijos[cual], tipos);
        if es_desconocido(vista(dado)) { return no_se(); }
        agregar_vista(b, s, vista(tmp), vista(dado), n.linea);
        cual = cual + 1;

        // Saltar hasta la llave que cierra, contando las de dentro y
        // saltando las cadenas del hueco, que sus llaves no son suyas.
        i = L.cierre_de_hueco(crudo, i + 1) + 1;
    }
    if largo(trozo) > 0 {
        agregar_trozo(b, s, vista(tmp), vista(trozo), n.linea);
    }
    return copiar(tmp);
}

// El texto de un hueco, ya como vista. Un `str` o una `view` se prestan; lo
// demas se convierte a texto en un temporal.
fn hueco_c(b: mut Cuerpo, s: &Sitio, x: &P.Nodo, tipos: &I.Contexto) -> str {
    let t = I.tipo_de(tipos, x);
    if igual(vista(t), "str") || igual(vista(t), "view") {
        return como_vista(b, s, x, tipos);
    }
    let valor = expresion_c(b, s, x, vista(t), tipos);
    if es_desconocido(vista(valor)) { return no_se(); }
    let convertido = texto_de(s, vista(valor), vista(t), x.linea);
    if es_desconocido(vista(convertido)) { return no_se(); }
    let pieza = nuevo_temporal(b);
    var l = nuevo("SafeString ");
    empujar(l, vista(pieza));
    empujar(l, " = ");
    empujar(l, vista(convertido));
    empujar(l, ";");
    emitir(b, vista(l));
    apuntar_temporal(b, vista(pieza), "str");
    var r = nuevo("ss_view(&");
    empujar(r, vista(pieza));
    empujar(r, ")");
    return r;
}

// El `str` que representa un valor. Las mismas reglas que `texto`.
fn texto_de(s: &Sitio, valor: view, t: view, linea: usize) -> str {
    var r = vacio();
    if igual(t, "usize") {
        r = nuevo("ss_lang_texto_usize_(");
        empujar(r, valor);
    } else {
        if igual(t, "f32") || igual(t, "f64") {
            r = nuevo("ss_lang_texto_view_(sv(ss_lang_texto_decimal_(");
            empujar(r, valor);
            empujar(r, "))");
        } else {
            if igual(t, "bool") {
                r = nuevo("ss_lang_texto_view_((");
                empujar(r, valor);
                empujar(r, ") ? sv(\"true\") : sv(\"false\")");
            } else {
                if es_entero(t) {
                    // Un ancho fijo se ensancha al mayor de su signo: hay
                    // una conversion por signo, no una por ancho.
                    if empieza_con(t, "u") {
                        r = nuevo("ss_lang_texto_usize_((size_t) ");
                    } else {
                        r = nuevo("ss_lang_texto_i64_((int64_t) ");
                    }
                    empujar(r, valor);
                } else {
                    return no_se();
                }
            }
        }
    }
    empujar(r, ", \"");
    empujar(r, vista(s.archivo));
    empujar(r, "\", ");
    empujar(r, texto(linea));
    empujar(r, ")");
    return r;
}

fn agregar_trozo(b: mut Cuerpo, s: &Sitio, donde: view, t: view,
    linea: usize) {
    let escrito = literal_c(t);
    var v = nuevo("sv_len(");
    empujar(v, vista(escrito));
    empujar(v, ", ");
    empujar(v, texto(cuantos_bytes(t)));
    empujar(v, ")");
    agregar_vista(b, s, donde, vista(v), linea);
}

fn agregar_vista(b: mut Cuerpo, s: &Sitio, donde: view, que: view,
    linea: usize) {
    var l = nuevo("ss_lang_agregar_texto_(&");
    empujar(l, donde);
    empujar(l, ", ");
    empujar(l, que);
    empujar(l, ", \"");
    empujar(l, vista(s.archivo));
    empujar(l, "\", ");
    empujar(l, texto(linea));
    empujar(l, ");");
    emitir(b, vista(l));
}

// `Punto { x: 1, y: 2 }`. El struct se queda con lo que le pongan: un campo
// con duenio recibe el valor, no una copia, y desde ahi lo suelta el.
fn literal_struct_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, esperado: view,
    tipos: &I.Contexto) -> str {
    // `Par { ... }` sin sus tipos, donde se espera un `Par<str, usize>`: es
    // ese, como deduce el comprobador.
    var escrito_s = nuevo(vista(n.texto));
    if !contiene(vista(escrito_s), "<") && I.es_aplicacion(esperado) {
        let base_e = I.base_de_aplicacion(esperado);
        let corto_e = I.sin_modulo(vista(escrito_s));
        if igual(vista(base_e), vista(corto_e)) { escrito_s = nuevo(esperado); }
    }
    // Sin tipos escritos ni esperados, los que dedujo el comprobador.
    if !contiene(vista(escrito_s), "<") {
        let dicho = I.tipo_de(tipos, n);
        if I.es_aplicacion(vista(dicho)) { escrito_s = dicho; }
    }
    let escrito = vista(escrito_s);
    var r = nuevo("(");
    // En C no queda el alias del modulo: `P.Nodo` es `Nodo`.
    empujar(r, tipo_c(escrito));
    empujar(r, "){ ");
    var previos: lista<str> = [];
    abrir_marco(b);
    for h en n.hijos {
        if !igual(vista(h.clase), "campo") || largo(h.hijos) != 1 {
            let _m = cerrar_marco(b);
            return no_se();
        }
        let suyo = I.tipo_de_campo(tipos, escrito, vista(h.texto));
        let valor = expresion_c(b, s, h.hijos[0], vista(suyo), tipos);
        if es_desconocido(vista(valor)) {
            let _m = cerrar_marco(b);
            return no_se();
        }
        reclamar(b, vista(valor)); // el struct se lo queda
        agregar_argumento_marcado(b, h.hijos[0], vista(valor), vista(suyo), false,
            false, largo(n.hijos) > 1);
    }
    let marco_c = cerrar_marco(b);
    var k_c = 0;
    for p_c en marco_c.entradas {
        if k_c > 0 { empujar(r, ", "); }
        empujar(r, ".");
        empujar(r, vista(n.hijos[k_c].texto));
        empujar(r, " = ");
        if largo(p_c.tmp) > 0 {
            anadir(previos, $"{p_c.tmp} = {p_c.valor}");
            empujar(r, vista(p_c.tmp));
        } else {
            empujar(r, vista(p_c.valor));
        }
        k_c = k_c + 1;
    }
    empujar(r, " }");
    if largo(previos) > 0 {
        b.ultima_linea = 0;
        marcar(b, s, n.linea);
    }
    return envolver_llamada_ordenada(r, previos);
}

// `x como u32`. Convertir de verdad comprueba que el valor cabe: si no
// cabe, el programa para donde esta. `como?` es la otra: pedir a proposito
// que se quede con los bits de abajo, que es lo que C hace siempre y sin
// avisar. Las dos se escriben distinto porque son dos intenciones distintas.
fn conversion_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo,
    tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 1 { return no_se(); }
    let escrito = vista(n.texto);
    var envolviendo = false;
    var destino = nuevo(escrito);
    if empieza_con(escrito, "?") {
        envolviendo = true;
        destino = nuevo(rebanar(escrito, 1, largo(escrito)));
    }
    let suyo = I.tipo_de(tipos, n.hijos[0]);
    var origen = T.apuntado_si(vista(suyo));
    if !es_aritmetico(vista(origen)) { origen = nuevo("usize"); }
    let valor = expresion_c(b, s, n.hijos[0], vista(origen), tipos);
    if es_desconocido(vista(valor)) { return no_se(); }
    if igual(vista(origen), vista(destino)) { return valor; }

    if envolviendo {
        var r = nuevo("((");
        empujar(r, tipo_c(vista(destino)));
        empujar(r, ") ");
        empujar(r, vista(valor));
        empujar(r, ")");
        return r;
    }
    var r = nuevo("ss_lang_conv_");
    empujar(r, vista(destino));
    empujar(r, "_de_");
    empujar(r, vista(origen));
    empujar(r, "(");
    empujar(r, vista(valor));
    empujar(r, ", \"");
    empujar(r, vista(s.archivo));
    empujar(r, "\", ");
    empujar(r, texto(n.linea));
    empujar(r, ")");
    return r;
}

fn es_aritmetico(t: view) -> bool {
    if igual(t, "f32") || igual(t, "f64") { return true; }
    return es_entero(t);
}

// Un sitio del que tomar campos o elementos. Una llamada no es un sitio:
// `hacer()[1]` tendria que guardar lo que devuelve antes de indexarlo, o la
// llamada se evaluaria una vez por cada vez que aparece en el C —dos: el
// elemento y el largo— y lo que devuelve no lo liberaria nadie.
fn sitio_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);
    if igual(clase, "variable") || igual(clase, "campo")
    || igual(clase, "indice") {
        return expresion_c(b, s, n, "", tipos);
    }
    // Una llamada no es un sitio: `claves(m).length` la evaluaria una vez
    // por cada aparicion en el C, y lo que devuelve no lo soltaria nadie. Se
    // guarda en un temporal, que se suelta al acabar la sentencia.
    var t = I.tipo_de(tipos, n);
    if largo(t) == 0 { t = nuevo("usize"); }
    let tmp = nuevo_temporal(b);
    let valor = expresion_c(b, s, n, vista(t), tipos);
    if es_desconocido(vista(valor)) { return no_se(); }
    reclamar(b, vista(valor));
    let tc = tipo_c(vista(t));
    emitir(b, $"{tc} {tmp} = {valor};");
    if I.posee_con_formas(tipos, vista(t)) {
        apuntar_temporal(b, vista(tmp), vista(t));
    }
    return tmp;
}

fn sitio_solo_lectura(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> bool {
    let clase = vista(n.clase);
    if igual(clase, "variable") {
        if tiene(s.punteros, vista(n.texto)) {
            let marca = obtener(s.punteros, vista(n.texto)) sino 0;
            if marca == 2 { return true; }
        }
        let t = I.tipo_de(tipos, n);
        return T.es_referencia(vista(t)) && !empieza_con(vista(t), "&mut ");
    }
    if (igual(clase, "campo") || igual(clase, "indice")) && largo(n.hijos) > 0 {
        return sitio_solo_lectura(s, n.hijos[0], tipos);
    }
    return false;
}

// Indexar comprueba el limite: es la comprobacion que C no hace y por la que
// existe medio Tcode. Va en el C, no en el comprobador, porque el indice se
// sabe al correr.
fn indice_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 2 { return no_se(); }
    let suyo = I.tipo_de(tipos, n.hijos[0]);
    let base = T.apuntado_si(vista(suyo));
    let sitio = sitio_c(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(sitio)) { return no_se(); }
    let idx = expresion_c(b, s, n.hijos[1], "usize", tipos);
    if es_desconocido(vista(idx)) { return no_se(); }

    // La direccion del contenedor se evalua una sola vez, aun cuando `sitio`
    // sea otro indice con efectos. La coma secuencia esa evaluacion y el [0]
    // final deja un sitio asignable en C.
    let ptr = nuevo_temporal(b);
    let tc = tipo_c(vista(base));
    if sitio_solo_lectura(s, n.hijos[0], tipos) {
        emitir(b, $"const {tc}* {ptr};");
    } else {
        emitir(b, $"{tc}* {ptr};");
    }

    var cuantos = vacio();
    if T.es_lista(vista(base)) {
        cuantos = $"{ptr}->length";
    } else {
        if T.es_bloque(vista(base)) {
            cuantos = $"{ptr}->n";
        } else {
            if T.es_arreglo(vista(base)) {
                cuantos = cuantos_de_arreglo(vista(base));
            } else {
                return no_se();
            }
        }
    }

    var r = $"(({ptr} = &({sitio}), &{ptr}->e[ss_lang_indice_(";
    empujar(r, vista(idx));
    empujar(r, ", ");
    empujar(r, vista(cuantos));
    empujar(r, ", \"");
    empujar(r, vista(s.archivo));
    empujar(r, "\", ");
    empujar(r, texto(n.linea));
    empujar(r, ")])[0])");
    return r;
}

fn binaria_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, esperado: view, tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 2 { return no_se(); }
    let op = vista(n.texto);

    // Lo logico conserva el cortocircuito de C: el lado derecho solo se
    // evalua si el izquierdo no decide ya el resultado.
    if igual(op, "&&") || igual(op, "||") {
        return junta(b, s, n, "bool", op, tipos);
    }

    let t = I.tipo_cuenta(tipos, n, esperado);
    if largo(t) == 0 { return no_se(); }

    // Para todo lo demas, C no promete izquierda antes que derecha. Se
    // declaran dos temporales sin inicializarlos y las asignaciones quedan
    // dentro de la expresion: asi un `&&` o `||` exterior sigue pudiendo
    // omitirla por completo.
    var t_der = copiar(t);
    if igual(op, "<<") || igual(op, ">>") { t_der = nuevo("usize"); }
    let valor_izq_0 = expresion_c(b, s, n.hijos[0], vista(t), tipos);
    // El izquierdo queda pendiente mientras se calcula el derecho: si este
    // deja sentencias, aquel corre antes.
    let tc_pendiente = tipo_c(vista(t));
    abrir_marco(b);
    apuntar_pendiente(b, operando(n.hijos[0], vista(valor_izq_0), vista(tc_pendiente)));
    let valor_der = expresion_c(b, s, n.hijos[1], vista(t_der), tipos);
    let marco_izq = cerrar_marco(b);
    let valor_izq = copiar(marco_izq.entradas[0].valor);
    if es_desconocido(vista(valor_izq)) || es_desconocido(vista(valor_der)) {
        return no_se();
    }
    let tmp_izq = nuevo_temporal(b);
    let tmp_der = nuevo_temporal(b);
    let tc_izq = tipo_c(vista(t));
    let tc_der = tipo_c(vista(t_der));
    emitir(b, $"{tc_izq} {tmp_izq};");
    emitir(b, $"{tc_der} {tmp_der};");
    // Los temporales son infraestructura del C. La operacion que viene
    // despues sigue perteneciendo a la linea original para el depurador.
    b.ultima_linea = 0;
    marcar(b, s, n.linea);
    var resultado = vacio();

    // Los decimales no desbordan: se van a infinito o a NaN, callando. En
    // Tcode eso para el programa donde aparece, asi que cada operacion pasa
    // por una comprobacion de que el resultado sigue siendo un numero. El
    // que quiera lo de IEEE lo pide con `+?`, `-?`, `*?` o `/?`.
    if igual(vista(t), "f32") || igual(vista(t), "f64") {
        if empieza_con(op, "+?") || empieza_con(op, "-?")
        || empieza_con(op, "*?") || empieza_con(op, "/?") {
            resultado = $"({tmp_izq} {rebanar(op, 0, 1)} {tmp_der})";
        } else {
            if igual(op, "+") || igual(op, "-") || igual(op, "*")
            || igual(op, "/") {
                resultado = $"ss_lang_fin_{t}(({tmp_izq} {op} {tmp_der}), \"{op}\", \"Si lo querias, escribe `{op}?`.\", \"{s.archivo}\", {n.linea})";
            } else {
                resultado = $"({tmp_izq} {op} {tmp_der})";
            }
        }
    }

    // El desplazamiento tiene dos tipos: lo que se mueve y cuanto se mueve.
    // Y se comprueba, porque en C desplazar mas que el ancho es indefinido.
    if largo(resultado) == 0 && (igual(op, "<<") || igual(op, ">>")) {
        var sentido = nuevo("der");
        if igual(op, "<<") { sentido = nuevo("izq"); }
        resultado = $"ss_lang_desp_{sentido}_{t}({tmp_izq}, {tmp_der}, \"{s.archivo}\", {n.linea})";
    }

    // Bits, y aritmetica envolvente pedida a proposito. El molde deja claro
    // que el resultado no se ensancha por el camino: en C, `u8 & u8` da un
    // `int`.
    // La envolvente se opera en `uint64_t`, donde C define la vuelta: con
    // signo, `INT64_MAX + 1` es comportamiento indefinido.
    if largo(resultado) == 0
    && (igual(op, "+?") || igual(op, "-?") || igual(op, "*?")) {
        let tc = tipo_c(vista(t));
        let signo = rebanar(op, 0, 1);
        let bits = $"((uint64_t) ({tmp_izq}) {signo} (uint64_t) ({tmp_der}))";
        if empieza_con(vista(t), "i") {
            let ut = $"uint{rebanar(vista(t), 1, largo(vista(t)))}_t";
            resultado = $"ss_lang_env_{t}(({ut}) {bits})";
        } else {
            resultado = $"(({tc}) {bits})";
        }
    }
    if largo(resultado) == 0
    && (igual(op, "&") || igual(op, "|") || igual(op, "^")) {
        let tc = tipo_c(vista(t));
        if empieza_con(vista(t), "i") {
            let ut = $"uint{rebanar(vista(t), 1, largo(vista(t)))}_t";
            resultado = $"ss_lang_env_{t}(({ut}) (({ut}) ({tmp_izq}) {op} ({ut}) ({tmp_der})))";
        } else {
            resultado = $"(({tc}) ({tmp_izq} {op} {tmp_der}))";
        }
    }

    let fam = familia(op);
    if largo(resultado) == 0 && largo(fam) > 0 {
        resultado = $"ss_lang_{fam}_{t}({tmp_izq}, {tmp_der}, \"{s.archivo}\", {n.linea})";
    }

    if largo(resultado) == 0 && (igual(op, "/") || igual(op, "%")) {
        if empieza_con(vista(t), "i") {
            var nombre = nuevo("div");
            if igual(op, "%") { nombre = nuevo("mod"); }
            resultado = $"ss_lang_{nombre}_{t}({tmp_izq}, {tmp_der}, \"{s.archivo}\", {n.linea})";
        } else {
            var macro = nuevo("SS_LANG_DIV");
            if igual(op, "%") { macro = nuevo("SS_LANG_MOD"); }
            resultado = $"{macro}({tmp_izq}, {tmp_der}, \"{s.archivo}\", {n.linea})";
        }
    }

    if largo(resultado) == 0
    && (igual(op, "==") || igual(op, "!=") || igual(op, "<")
        || igual(op, "<=") || igual(op, ">") || igual(op, ">=")) {
        resultado = $"({tmp_izq} {op} {tmp_der})";
    }
    if largo(resultado) == 0 { return no_se(); }
    return $"(({tmp_izq} = {valor_izq}, {tmp_der} = {valor_der}, {resultado}))";
}

// `(izq OP der)`, que es como salen los operadores que C ya tiene.
fn junta(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, esperado: view, op: view,
    tipos: &I.Contexto) -> str {
    let izq = expresion_c(b, s, n.hijos[0], esperado, tipos);
    let marca = largo(b.lineas);
    let base = largo(b.temporales);
    // Lo que el lado derecho deje se mueve dentro de un `if`: lo de fuera no
    // se puede adelantar ahi, correria solo a veces. Se adelanta despues, al
    // escribir `bool vale = izq`.
    poner_barrera(b);
    let der = expresion_c(b, s, n.hijos[1], esperado, tipos);
    let _barrera = cerrar_marco(b);
    if es_desconocido(vista(izq)) || es_desconocido(vista(der)) {
        return no_se();
    }
    var hace_algo = false;
    var k = marca;
    while k < largo(b.lineas) {
        let x = vista(b.lineas[k]);
        if (contiene(x, "=") || contiene(x, "(")) && !empieza_con(x, "#") { hace_algo = true; }
        k = k + 1;
    }
    if hace_algo {
        // El lado derecho dejo lineas que hacen algo —un `str` recien hecho
        // que se presta, por ejemplo—, y delante de la sentencia se harian
        // siempre. Van dentro de un `if`, y lo que dejaron se suelta ahi
        // mismo: el resultado ya es un `bool`.
        var nuevas: lista<str> = [];
        k = marca;
        while k < largo(b.lineas) {
            anadir(nuevas, copiar(b.lineas[k]));
            k = k + 1;
        }
        recortar_lineas(b, marca);
        var suyos: lista<str> = [];
        var quedan: lista<str> = [];
        k = 0;
        while k < largo(b.temporales) {
            if k < base { anadir(quedan, copiar(b.temporales[k])); }
            else { anadir(suyos, copiar(b.temporales[k])); }
            k = k + 1;
        }
        b.temporales = quedan;
        let vale = nuevo_temporal(b);
        emitir(b, $"bool {vale} = {izq};");
        if igual(op, "&&") { emitir(b, $"if ({vale})"); } else { emitir(b, $"if (!{vale})"); }
        emitir(b, "{");
        for x en nuevas {
            // Una directiva va pegada al margen.
            if largo(x) == 0 || empieza_con(vista(x), "#") { anadir(b.lineas, copiar(x)); }
            else { anadir(b.lineas, $"    {x}"); }
        }
        b.sangria = b.sangria + 1;
        emitir(b, $"{vale} = {der};");
        for entrada en suyos {
            let nt = antes_de_dos_puntos(vista(entrada));
            let tt = despues_de_dos_puntos(vista(entrada));
            liberacion(b, tipos, vista(nt), vista(tt));
        }
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        return vale;
    }
    var v = nuevo("(");
    empujar(v, vista(izq));
    empujar(v, " ");
    empujar(v, op);
    empujar(v, " ");
    empujar(v, vista(der));
    empujar(v, ")");
    return v;
}

// El tipo con el que operar los dos lados: el del primero que se sepa.
fn es_entero(t: view) -> bool {
    if igual(t, "usize") || igual(t, "i64") { return true; }
    if igual(t, "u8") || igual(t, "u16") || igual(t, "u32") { return true; }
    if igual(t, "u64") || igual(t, "i8") || igual(t, "i16") { return true; }
    return igual(t, "i32");
}

// Solo las llamadas a funciones del programa: las internas tienen cada una
// su forma, y eso es otra capa.
// Las internas que no necesitan emitir nada aparte: se bajan a una llamada
// del runtime y ya. `byte` no esta porque necesita guardar la vista en un
// temporal antes de indexarla.
fn interna_pura(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let nombre = vista(n.texto);

    if igual(nombre, "vacio") { return nuevo("ss_new()"); }

    if igual(nombre, "n_argumentos") { return nuevo("ss_lang_n_argumentos_()"); }

    if igual(nombre, "redimensionar") {
        if largo(n.hijos) != 2 { return no_se(); }
        let crudo = I.tipo_de(tipos, n.hijos[0]);
        let t = T.apuntado_si(vista(crudo));
        if !T.es_bloque(vista(t)) { return no_se(); }
        let dir = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(dir)) { return no_se(); }
        let ptr = nuevo_temporal(b);
        let tc = tipo_c(vista(t));
        emitir(b, $"{tc}* {ptr} = {dir};");
        let cuantos = expresion_c(b, s, n.hijos[1], "usize", tipos);
        if es_desconocido(vista(cuantos)) { return no_se(); }
        let m = mangle(vista(t));
        return $"ss_lang_bloque_cambiar_{m}({ptr}, {cuantos}, \"{s.archivo}\", {n.linea})";
    }

    // Se saca primero y se pone despues: si el valor nuevo viniera del mismo
    // sitio, hacerlo al reves lo perderia. Nunca queda un hueco sin duenio.
    if igual(nombre, "intercambiar") {
        if largo(n.hijos) != 2 { return no_se(); }
        var t = I.tipo_de(tipos, n.hijos[0]);
        if largo(t) == 0 { t = nuevo("usize"); }
        // El destino puede hacer trabajo al calcularse. Su direccion se
        // guarda para leer y escribir exactamente el mismo sitio.
        let direccion = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(direccion)) { return no_se(); }
        let tc = tipo_c(vista(t));
        let ptr = nuevo_temporal(b);
        emitir(b, $"{tc}* {ptr} = {direccion};");
        let valor = expresion_c(b, s, n.hijos[1], vista(t), tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        reclamar(b, vista(valor));
        let tmp = nuevo_temporal(b);
        emitir(b, $"{tc} {tmp} = *{ptr};");
        emitir(b, $"*{ptr} = {valor};");
        return tmp;
    }

    if igual(nombre, "argumento") {
        if largo(n.hijos) != 1 { return no_se(); }
        let i = expresion_c(b, s, n.hijos[0], "usize", tipos);
        if es_desconocido(vista(i)) { return no_se(); }
        var r = nuevo("ss_lang_argumento_(");
        empujar(r, vista(i));
        empujar(r, ", \"");
        empujar(r, vista(s.archivo));
        empujar(r, "\", ");
        empujar(r, texto(n.linea));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "largo") {
        if largo(n.hijos) != 1 { return no_se(); }
        // `let p: &mut bloque<usize> = ...` se mide por lo que apunta.
        let suyo = I.tipo_de(tipos, n.hijos[0]);
        let sobre = T.apuntado_si(vista(suyo));
        if T.es_mapa(vista(sobre)) {
            let donde = sitio_c(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(donde)) { return no_se(); }
            var r = nuevo("(");
            empujar(r, vista(donde));
            empujar(r, ".largo)");
            return r;
        }
        if T.es_lista(vista(sobre)) {
            let donde = sitio_c(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(donde)) { return no_se(); }
            var r = nuevo("(");
            empujar(r, vista(donde));
            empujar(r, ".length)");
            return r;
        }
        if T.es_bloque(vista(sobre)) {
            let donde = sitio_c(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(donde)) { return no_se(); }
            return $"({donde}.n)";
        }
        let v = como_vista(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(v)) { return no_se(); }
        var r = nuevo("sv_len_of(");
        empujar(r, vista(v));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "nuevo") {
        if largo(n.hijos) != 1 { return no_se(); }
        let v = como_vista(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(v)) { return no_se(); }
        var r = nuevo("ss_from_view(");
        empujar(r, vista(v));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "vista") {
        if largo(n.hijos) != 1 { return no_se(); }
        let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(donde)) { return no_se(); }
        var r = nuevo("ss_view(");
        empujar(r, vista(donde));
        empujar(r, ")");
        return r;
    }

    if igual(nombre, "igual") || igual(nombre, "menor") {
        if largo(n.hijos) != 2 { return no_se(); }
        let crudo = I.tipo_de(tipos, n.hijos[0]);
        let ta = T.apuntado_si(vista(crudo));
        let es_texto = igual(vista(ta), "str") || igual(vista(ta), "view");
        var uno = vacio();
        var dos = vacio();
        var tc = vacio();
        if es_texto { tc = nuevo("SafeView"); } else { tc = tipo_c(vista(ta)); }
        abrir_marco(b);
        if es_texto { uno = como_vista(b, s, n.hijos[0], tipos); }
        else { uno = expresion_c(b, s, n.hijos[0], vista(ta), tipos); }
        apuntar_pendiente(b, operando(n.hijos[0], vista(uno), vista(tc)));
        if es_texto { dos = como_vista(b, s, n.hijos[1], tipos); }
        else { dos = expresion_c(b, s, n.hijos[1], vista(ta), tipos); }
        let marco_u = cerrar_marco(b);
        uno = copiar(marco_u.entradas[0].valor);
        if es_desconocido(vista(uno)) || es_desconocido(vista(dos)) {
            return no_se();
        }
        let tmp_uno = nuevo_temporal(b);
        let tmp_dos = nuevo_temporal(b);
        emitir(b, $"{tc} {tmp_uno};");
        emitir(b, $"{tc} {tmp_dos};");
        var comparacion = vacio();
        if es_texto {
            comparacion = nuevo("sv_equals(");
            if igual(nombre, "menor") { comparacion = nuevo("(sv_cmp("); }
            empujar(comparacion, vista(tmp_uno));
            empujar(comparacion, ", ");
            empujar(comparacion, vista(tmp_dos));
            if igual(nombre, "menor") { empujar(comparacion, ") < 0)"); }
            else { empujar(comparacion, ")"); }
        } else {
            var op = nuevo("<");
            if igual(nombre, "igual") { op = nuevo("=="); }
            comparacion = $"({tmp_uno} {op} {tmp_dos})";
        }
        var r = $"(({tmp_uno} = {uno}, {tmp_dos} = {dos}, ";
        empujar(r, vista(comparacion));
        empujar(r, "))");
        return r;
    }

    // `byte(v, i)` no cabe en una sola expresion de C: hay que guardar la
    // vista en un temporal y luego indexarla, porque si no se calcularia dos
    // veces —una para el elemento y otra para el largo— y `byte(f(), 0)`
    // llamaria a `f` dos veces. Es la primera interna que necesita emitir
    // una linea propia, y por eso esta capa recibe el cuerpo.
    if igual(nombre, "byte") {
        if largo(n.hijos) != 2 { return no_se(); }
        let v = como_vista(b, s, n.hijos[0], tipos);
        let i = expresion_c(b, s, n.hijos[1], "usize", tipos);
        if es_desconocido(vista(v)) || es_desconocido(vista(i)) {
            return no_se();
        }
        let tmp = nuevo_temporal(b);
        var l = nuevo("SafeView ");
        empujar(l, vista(tmp));
        empujar(l, " = ");
        empujar(l, vista(v));
        empujar(l, ";");
        emitir(b, vista(l));

        var r = nuevo("((size_t)(unsigned char)");
        empujar(r, vista(tmp));
        empujar(r, ".ptr[ss_lang_indice_(");
        empujar(r, vista(i));
        empujar(r, ", ");
        empujar(r, vista(tmp));
        empujar(r, ".len, \"");
        empujar(r, vista(s.archivo));
        empujar(r, "\", ");
        empujar(r, texto(n.linea));
        empujar(r, ")])");
        return r;
    }

    // Los mapas. El nombre de cada operacion lleva dentro el tipo del mapa,
    // porque cada uno tiene su propia tabla generada: no hay una funcion
    // generica que reciba tamanios y punteros a void.
    if igual(nombre, "poner") || igual(nombre, "obtener")
    || igual(nombre, "obtener_mut") || igual(nombre, "tiene")
    || igual(nombre, "claves") || igual(nombre, "quitar") {
        if largo(n.hijos) == 0 { return no_se(); }
        let suyo = I.tipo_de(tipos, n.hijos[0]);
        let tm = T.apuntado_si(vista(suyo));
        if !T.es_mapa(vista(tm)) { return no_se(); }
        let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(donde)) { return no_se(); }

        var r = nuevo("ss_mapa_");
        empujar(r, nombre);
        empujar(r, "_");
        empujar(r, mangle(vista(tm)));
        empujar(r, "(");
        empujar(r, vista(donde));

        if igual(nombre, "claves") {
            if largo(n.hijos) != 1 { return no_se(); }
            empujar(r, ", \"");
            empujar(r, vista(s.archivo));
            empujar(r, "\", ");
            empujar(r, texto(n.linea));
            empujar(r, ")");
            return r;
        }

        if largo(n.hijos) < 2 { return no_se(); }
        if igual(nombre, "poner") {
            if largo(n.hijos) != 3 { return no_se(); }
            let ptr = nuevo_temporal(b);
            let tc = tipo_c(vista(tm));
            emitir(b, $"{tc}* {ptr} = {donde};");
            let clave_p = como_vista(b, s, n.hijos[1], tipos);
            if es_desconocido(vista(clave_p)) { return no_se(); }
            let tv = T.valor_de_mapa(vista(tm)) sino vacio();
            if largo(vista(tv)) == 0 { return no_se(); }
            let valor = expresion_c(b, s, n.hijos[2], vista(tv), tipos);
            if es_desconocido(vista(valor)) { return no_se(); }
            reclamar(b, vista(valor)); // el mapa se lo queda
            b.ultima_linea = 0;
            marcar(b, s, n.linea);
            return $"ss_mapa_poner_{mangle(vista(tm))}({ptr}, {clave_p}, {valor}, \"{s.archivo}\", {n.linea})";
        }
        let clave = como_vista(b, s, n.hijos[1], tipos);
        if es_desconocido(vista(clave)) { return no_se(); }
        var previos: lista<str> = [];
        var llamada = nuevo("ss_mapa_");
        empujar(llamada, nombre);
        empujar(llamada, "_");
        empujar(llamada, mangle(vista(tm)));
        empujar(llamada, "(");
        let mutable = igual(nombre, "obtener_mut") || igual(nombre, "quitar");
        agregar_argumento_ordenado(b, llamada, previos, vista(donde),
            vista(tm), true, mutable, true);
        empujar(llamada, ", ");
        agregar_argumento_ordenado(b, llamada, previos, vista(clave),
            "view", false, false, true);
        empujar(llamada, ")");
        b.ultima_linea = 0;
        marcar(b, s, n.linea);
        return envolver_llamada_ordenada(llamada, previos);
    }

    // `copiar(x)`: una copia independiente, hasta el fondo. Cada tipo lleva
    // su copiador generado, espejo exacto de su liberacion.
    if igual(nombre, "copiar") {
        if largo(n.hijos) != 1 { return no_se(); }
        let crudo = I.tipo_de(tipos, n.hijos[0]);
        let t = T.apuntado_si(vista(crudo));
        if largo(vista(t)) == 0 { return no_se(); }
        if !I.posee_con_formas(tipos, vista(t)) {
            // Un escalar se copia solo.
            return expresion_c(b, s, n.hijos[0], vista(t), tipos);
        }
        var donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(donde)) && T.es_referencia(vista(crudo)) {
            // Llega prestado, y en C eso ya es la direccion.
            donde = expresion_c(b, s, n.hijos[0], vista(crudo), tipos);
        }
        if es_desconocido(vista(donde)) { return no_se(); }
        if igual(vista(t), "str") {
            var r = nuevo("ss_clone(");
            empujar(r, vista(donde));
            empujar(r, ")");
            return r;
        }
        // El copiador se escribe aparte, al final: se apunta que hace falta.
        anadir(b.copias, I.sin_alias_tipo(vista(t)));
        var r = nuevo("ss_copia_");
        empujar(r, mangle(vista(t)));
        empujar(r, "(");
        empujar(r, vista(donde));
        empujar(r, ")");
        return r;
    }

    // `imprimir` va a la salida; `imprimir_error`, al diagnostico. Separarlos
    // es lo que permite encauzar la salida de una herramienta sin que se le
    // cuelen los mensajes de uso. El formato sale del tipo, que se sabe al
    // compilar: no hay `%d` con un puntero que valga.
    if igual(nombre, "imprimir") || igual(nombre, "imprimir_error") {
        if largo(n.hijos) != 1 { return no_se(); }
        var r = nuevo("printf(");
        if igual(nombre, "imprimir_error") { r = nuevo("fprintf(stderr, "); }
        let t = I.tipo_de(tipos, n.hijos[0]);
        let clase = vista(n.hijos[0].clase);
        // El texto va con `fwrite`, por su largo: un `str` guarda bytes y
        // puede llevar ceros, que `%s` y `%.*s` tomarian por el final.
        var salida = nuevo("stdout");
        if igual(nombre, "imprimir_error") { salida = nuevo("stderr"); }
        if igual(vista(t), "str") && (igual(clase, "variable")
            || igual(clase, "campo") || igual(clase, "indice")) {
            let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(donde)) { return no_se(); }
            return $"ss_lang_escribir_({salida}, ss_view({donde}))";
        }
        if igual(vista(t), "str") || igual(vista(t), "view") {
            let v = como_vista(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(v)) { return no_se(); }
            let tmp = nuevo_temporal(b);
            emitir(b, $"SafeView {tmp} = {v};");
            b.ultima_linea = 0;
            marcar(b, s, n.hijos[0].linea);
            return $"ss_lang_escribir_({salida}, {tmp})";
        }
        let valor = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        if igual(vista(t), "usize") {
            empujar(r, "\"%zu\", ");
        } else {
            if igual(vista(t), "f32") || igual(vista(t), "f64") {
                empujar(r, "\"%s\", ss_lang_texto_decimal_(");
                empujar(r, vista(valor));
                empujar(r, "))");
                return r;
            }
            if igual(vista(t), "bool") {
                empujar(r, "\"%s\", (");
                empujar(r, vista(valor));
                empujar(r, ") ? \"true\" : \"false\")");
                return r;
            }
            if !es_entero(vista(t)) { return no_se(); }
            // Un ancho fijo se ensancha al mayor para imprimirlo: un formato
            // por signo y no nueve.
            if empieza_con(vista(t), "u") {
                empujar(r, "\"%llu\", (unsigned long long)");
            } else {
                empujar(r, "\"%lld\", (long long)");
            }
        }
        empujar(r, vista(valor));
        empujar(r, ")");
        return r;
    }

    // `texto(x)`: el `str` que representa un valor, con las mismas reglas
    // que un hueco de una cadena interpolada.
    if igual(nombre, "texto") {
        if largo(n.hijos) != 1 { return no_se(); }
        let t = I.tipo_de(tipos, n.hijos[0]);
        if igual(vista(t), "str") || igual(vista(t), "view") {
            let v = como_vista(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(v)) { return no_se(); }
            var r = nuevo("ss_lang_texto_view_(");
            empujar(r, vista(v));
            empujar(r, ", \"");
            empujar(r, vista(s.archivo));
            empujar(r, "\", ");
            empujar(r, texto(n.linea));
            empujar(r, ")");
            return r;
        }
        let valor = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        return texto_de(s, vista(valor), vista(t), n.linea);
    }

    // `raiz`, `piso`, `techo`, `redondear` y `absoluto`. Sobre un decimal
    // pasan por la comprobacion de finitud: `raiz` de un negativo da NaN, y
    // eso para donde aparece como cualquier otro NaN. Sobre un entero con
    // signo, `absoluto` del minimo no cabe en el tipo: es el unico caso.
    if igual(nombre, "raiz") || igual(nombre, "piso") || igual(nombre, "techo")
    || igual(nombre, "redondear") || igual(nombre, "absoluto") {
        if largo(n.hijos) != 1 { return no_se(); }
        let crudo = I.tipo_de(tipos, n.hijos[0]);
        var t = T.apuntado_si(vista(crudo));
        if !es_aritmetico(vista(t)) { t = nuevo("f64"); }
        let valor = expresion_c(b, s, n.hijos[0], vista(t), tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        if igual(vista(t), "f32") || igual(vista(t), "f64") {
            var fn_c = nuevo("fabs");
            if igual(nombre, "raiz") { fn_c = nuevo("sqrt"); }
            if igual(nombre, "piso") { fn_c = nuevo("floor"); }
            if igual(nombre, "techo") { fn_c = nuevo("ceil"); }
            if igual(nombre, "redondear") { fn_c = nuevo("round"); }
            var r = nuevo("ss_lang_fin_");
            empujar(r, vista(t));
            empujar(r, "(");
            empujar(r, vista(fn_c));
            if igual(vista(t), "f32") { empujar(r, "f"); }
            empujar(r, "(");
            empujar(r, vista(valor));
            empujar(r, "), \"");
            empujar(r, nombre);
            empujar(r, "\", \"");
            if igual(nombre, "raiz") {
                empujar(r, "Comprueba el signo antes: la raiz de un negativo ");
                empujar(r, "no es un numero.");
            } else {
                empujar(r, "Comprueba el valor antes de operar con el.");
            }
            empujar(r, "\", \"");
            empujar(r, vista(s.archivo));
            empujar(r, "\", ");
            empujar(r, texto(n.linea));
            empujar(r, ")");
            return r;
        }
        if !igual(nombre, "absoluto") { return no_se(); }
        var r = nuevo("ss_lang_abs_");
        empujar(r, vista(t));
        empujar(r, "(");
        empujar(r, vista(valor));
        empujar(r, ", \"");
        empujar(r, vista(s.archivo));
        empujar(r, "\", ");
        empujar(r, texto(n.linea));
        empujar(r, ")");
        return r;
    }

    // `ordenar(xs)`: cada tipo de lista lleva su propia ordenacion generada.
    if igual(nombre, "ordenar") {
        if largo(n.hijos) != 1 { return no_se(); }
        let crudo = I.tipo_de(tipos, n.hijos[0]);
        let t = T.apuntado_si(vista(crudo));
        if !T.es_lista(vista(t)) { return no_se(); }
        let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(donde)) { return no_se(); }
        var r = nuevo("ss_ordenar_");
        empujar(r, mangle(vista(t)));
        empujar(r, "(");
        empujar(r, vista(donde));
        empujar(r, ")");
        return r;
    }

    // `empujar_byte(s, b)`: un byte crudo, no texto. Es lo que permite
    // construir un buffer binario y no solo leerlo.
    if igual(nombre, "empujar_byte") {
        if largo(n.hijos) != 2 { return no_se(); }
        let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(donde)) { return no_se(); }
        let ptr = nuevo_temporal(b);
        emitir(b, $"SafeString* {ptr} = {donde};");
        let valor = expresion_c(b, s, n.hijos[1], "u8", tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        var r = nuevo("ss_lang_empujar_byte_(");
        empujar(r, vista(ptr));
        empujar(r, ", ");
        empujar(r, vista(valor));
        empujar(r, ", \"");
        empujar(r, vista(s.archivo));
        empujar(r, "\", ");
        empujar(r, texto(n.linea));
        empujar(r, ")");
        b.ultima_linea = 0;
        marcar(b, s, n.linea);
        return r;
    }

    if igual(nombre, "rebanar") {
        if largo(n.hijos) != 3 { return no_se(); }
        abrir_marco(b);
        let v_0 = como_vista(b, s, n.hijos[0], tipos);
        apuntar_pendiente(b, operando(n.hijos[0], vista(v_0), "SafeView"));
        let desde_0 = expresion_c(b, s, n.hijos[1], "usize", tipos);
        apuntar_pendiente(b, operando(n.hijos[1], vista(desde_0), "size_t"));
        let hasta = expresion_c(b, s, n.hijos[2], "usize", tipos);
        let marco_r = cerrar_marco(b);
        let v = copiar(marco_r.entradas[0].valor);
        let desde = copiar(marco_r.entradas[1].valor);
        if es_desconocido(vista(v)) || es_desconocido(vista(desde))
        || es_desconocido(vista(hasta)) {
            return no_se();
        }
        var r = nuevo("ss_lang_rebanar_(");
        var previos: lista<str> = [];
        agregar_argumento_ordenado(b, r, previos, vista(v), "view",
            false, false, true);
        empujar(r, ", ");
        agregar_argumento_ordenado(b, r, previos, vista(desde), "usize",
            false, false, true);
        empujar(r, ", ");
        agregar_argumento_ordenado(b, r, previos, vista(hasta), "usize",
            false, false, true);
        empujar(r, ", \"");
        empujar(r, vista(s.archivo));
        empujar(r, "\", ");
        empujar(r, texto(n.linea));
        empujar(r, ")");
        b.ultima_linea = 0;
        marcar(b, s, n.linea);
        return envolver_llamada_ordenada(r, previos);
    }

    return no_se();
}

// La direccion de un sitio con nombre: `&x`, `&p.campo`, `&v.e[i]`. Prestar
// algo recien hecho pediria un temporal del que tomar la direccion, y ese
// temporal habria que soltarlo al acabar la sentencia: otra capa.
fn direccion_del_sitio(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);
    if igual(clase, "variable") {
        // Un `&T` ya ES la direccion: pedirsela otra vez sobra.
        if es_puntero(s, tipos, vista(n.texto)) {
            return nuevo(vista(n.texto));
        }
        var r = nuevo("&");
        empujar(r, vista(n.texto));
        return r;
    }
    if igual(clase, "campo") || igual(clase, "indice") {
        let donde = expresion_c(b, s, n, "", tipos);
        if es_desconocido(vista(donde)) { return no_se(); }
        var r = nuevo("&");
        empujar(r, vista(donde));
        return r;
    }
    return no_se();
}

// `ss_view(&x)`, o `ss_view(x)` si `x` ya es un puntero.
fn direccion_de(s: &Sitio, nombre: view, envoltura: view) -> str {
    var r = nuevo(envoltura);
    if !tiene(s.punteros, nombre) { empujar(r, "&"); }
    empujar(r, nombre);
    empujar(r, ")");
    return r;
}

// Un argumento donde se pide una vista: un `view` va tal cual, un `str` se
// presta, y un literal es su propia vista.
fn como_vista(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    if igual(vista(n.clase), "cadena") {
        var r = nuevo("sv_len(");
        empujar(r, literal_c(vista(n.texto)));
        empujar(r, ", ");
        empujar(r, texto(cuantos_bytes(vista(n.texto))));
        empujar(r, ")");
        return r;
    }
    let t = I.tipo_de(tipos, n);
    if igual(vista(t), "str") {
        let clase = vista(n.clase);
        if igual(clase, "variable") || igual(clase, "campo")
        || igual(clase, "indice") {
            let donde = direccion_del_sitio(b, s, n, tipos);
            if es_desconocido(vista(donde)) { return no_se(); }
            var r = nuevo("ss_view(");
            empujar(r, vista(donde));
            empujar(r, ")");
            return r;
        }
        // Un `str` recien hecho no tiene sitio del que tomar la direccion:
        // se guarda en un temporal, que se suelta al acabar la sentencia.
        let tmp = nuevo_temporal(b);
        let valor = expresion_c(b, s, n, "str", tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        reclamar(b, vista(valor));
        var l = nuevo("SafeString ");
        empujar(l, vista(tmp));
        empujar(l, " = ");
        empujar(l, vista(valor));
        empujar(l, ";");
        emitir(b, vista(l));
        apuntar_temporal(b, vista(tmp), "str");
        var r = nuevo("ss_view(&");
        empujar(r, vista(tmp));
        empujar(r, ")");
        return r;
    }
    if igual(vista(t), "view") { return expresion_c(b, s, n, "view", tipos); }
    return no_se();
}

// Un literal de C con los mismos BYTES, escapado. Lo que no sea imprimible
// va en octal: asi un byte crudo no depende de como lo lea el compilador de
// C ni de en que juego de caracteres este el archivo. Un `?` detras de otro
// va escapado: en C17 `??=` es un trigrafo, y C lo cambiaria por `#` antes
// de leer la cadena, con el largo de antes al lado.
fn literal_c(crudo: view) -> str {
    let bytes = P.desescapar(crudo);
    let t = vista(bytes);
    var r = nuevo("\"");
    var i = 0;
    while i < largo(t) {
        let c = byte(t, i);
        if c == 63 && i > 0 && byte(t, i - 1) == 63 { empujar(r, "\\?"); }
        else if c == 92 { empujar(r, "\\\\"); }
        else {
            if c == 34 { empujar(r, "\\\""); }
            else {
                if c == 10 { empujar(r, "\\n"); }
                else {
                    if c == 9 { empujar(r, "\\t"); }
                    else {
                        if c >= 32 && c < 127 {
                            empujar(r, rebanar(t, i, i + 1));
                        } else {
                            let oct = en_octal(c);
                            empujar(r, "\\");
                            empujar(r, vista(oct));
                        }
                    }
                }
            }
        }
        i = i + 1;
    }
    empujar(r, "\"");
    return r;
}

// Tres digitos siempre: `\1` seguido de un `2` seria `\12`, otro byte.
fn en_octal(c: usize) -> str {
    var r = vacio();
    var d = 0;
    while d < 3 {
        let peso = potencia_ocho(2 - d);
        let cifra = (c / peso) % 8;
        empujar(r, texto(cifra));
        d = d + 1;
    }
    return r;
}

fn potencia_ocho(n: usize) -> usize {
    if n == 0 { return 1; }
    if n == 1 { return 8; }
    return 64;
}

fn cuantos_bytes(crudo: view) -> usize {
    let t = P.desescapar(crudo);
    return largo(vista(t));
}

// Una llamada a C: la misma que escribiria un programa en C, sin nada que
// traducir salvo la cadena, que pasa a `const char*` comprobando que no
// lleve un cero en medio. Lo que devuelve `cadena_c` sigue siendo de C:
// Tcode se queda una copia, que ya se suelta sola.
// Un bloque nuevo, a ceros. El tipo sale de donde se pone.
fn reservar_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, esperado: view,
    tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 1 { return no_se(); }
    var t = nuevo(esperado);
    if !T.es_bloque(esperado) { t = I.tipo_de(tipos, n); }
    if !T.es_bloque(vista(t)) { t = nuevo("bloque<usize>"); }
    let cuantos = expresion_c(b, s, n.hijos[0], "usize", tipos);
    if es_desconocido(vista(cuantos)) { return no_se(); }
    let m = mangle(vista(t));
    return $"ss_lang_bloque_nuevo_{m}({cuantos}, \"{s.archivo}\", {n.linea})";
}

fn llamada_externa_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let nombre = vista(n.texto);
    let firmados = I.lista_de(tipos.params, nombre) sino [];
    if largo(firmados) != largo(n.hijos) { return no_se(); }
    var v = I.sin_modulo(nombre);
    empujar(v, "(");
    var previos: lista<str> = [];
    let secuenciar = largo(n.hijos) > 1;
    abrir_marco(b);
    var i = 0;
    for h en n.hijos {
        var arg = vacio();
        var tc = vacio();
        if igual(vista(firmados[i]), "str") {
            let sitio = sitio_c(b, s, h, tipos);
            if es_desconocido(vista(sitio)) {
                let _m = cerrar_marco(b);
                return no_se();
            }
            arg = $"ss_lang_cstr_(&{sitio}, \"{s.archivo}\", {n.linea})";
            tc = nuevo("const char*");
        } else {
            arg = expresion_c(b, s, h, vista(firmados[i]), tipos);
            if es_desconocido(vista(arg)) {
                let _m = cerrar_marco(b);
                return no_se();
            }
            tc = tipo_c(vista(firmados[i]));
        }
        var p_arg = operando(h, vista(arg), vista(tc));
        if secuenciar {
            let tmp = nuevo_temporal(b);
            emitir(b, $"{tc} {tmp};");
            p_arg.tmp = tmp;
        }
        apuntar_pendiente(b, p_arg);
        i = i + 1;
    }
    let marco_args = cerrar_marco(b);
    escribir_argumentos(marco_args, v, previos, ", ");
    empujar(v, ")");
    if largo(previos) > 0 {
        var orden = nuevo("((");
        var primero = true;
        for p en previos {
            if !primero { empujar(orden, ", "); }
            primero = false;
            empujar(orden, vista(p));
        }
        empujar(orden, ", ");
        empujar(orden, vista(v));
        empujar(orden, "))");
        v = orden;
    }
    let marca = obtener(tipos.externas, nombre) sino 1;
    if marca == 2 {
        let tmp = nuevo_temporal(b);
        emitir(b, $"SafeString {tmp} = ss_from({v});");
        apuntar_temporal(b, vista(tmp), "str");
        return tmp;
    }
    return v;
}

fn agregar_argumento_ordenado(b: mut Cuerpo, llamada: mut str,
    previos: mut lista<str>, arg: view, tipo: view, presta: bool,
    mutable: bool, secuenciar: bool) {
    if !secuenciar {
        empujar(llamada, arg);
        return;
    }
    let tmp = nuevo_temporal(b);
    var d = vacio();
    if presta && !mutable { empujar(d, "const "); }
    empujar(d, tipo_c(tipo));
    if presta { empujar(d, "*"); }
    empujar(d, " ");
    empujar(d, vista(tmp));
    empujar(d, ";");
    emitir(b, vista(d));
    anadir(previos, $"{tmp} = {arg}");
    empujar(llamada, vista(tmp));
}

// Como `agregar_argumento_ordenado`, pero el argumento queda pendiente en el
// marco abierto: se escribe al cerrarlo, con `escribir_argumentos`, cuando ya
// se sabe si hubo que adelantarlo.
fn agregar_argumento_marcado(b: mut Cuerpo, nodo: &P.Nodo, arg: view, tipo: view,
    presta: bool, mutable: bool, secuenciar: bool) {
    var tc_op = vacio();
    if !presta { tc_op = tipo_c(tipo); }
    var p = operando(nodo, arg, vista(tc_op));
    if secuenciar {
        let tmp = nuevo_temporal(b);
        var d = vacio();
        if presta && !mutable { empujar(d, "const "); }
        empujar(d, tipo_c(tipo));
        if presta { empujar(d, "*"); }
        empujar(d, " ");
        empujar(d, vista(tmp));
        empujar(d, ";");
        emitir(b, vista(d));
        p.tmp = tmp;
    }
    apuntar_pendiente(b, p);
}

// Los argumentos de un marco ya cerrado, en orden: cada uno en su temporal si
// la llamada los guarda, o tal cual. `antes` va delante de cada uno menos el
// primero.
fn escribir_argumentos(marco: &Marco, llamada: mut str, previos: mut lista<str>,
    antes: view) {
    var primero = true;
    for p en marco.entradas {
        if !primero { empujar(llamada, antes); }
        primero = false;
        if largo(p.tmp) > 0 {
            anadir(previos, $"{p.tmp} = {p.valor}");
            empujar(llamada, vista(p.tmp));
        } else {
            empujar(llamada, vista(p.valor));
        }
    }
}

fn envolver_llamada_ordenada(llamada: str, previos: &lista<str>) -> str {
    if largo(previos) == 0 { return llamada; }
    var orden = nuevo("((");
    var primero = true;
    for p en previos {
        if !primero { empujar(orden, ", "); }
        primero = false;
        empujar(orden, vista(p));
    }
    empujar(orden, ", ");
    empujar(orden, vista(llamada));
    empujar(orden, "))");
    return orden;
}

// Una llamada a un valor: una variable que guarda una clausura se llama como
// su funcion con el entorno delante, prestado; una que guarda un puntero a
// funcion, con la firma que dice su tipo. Vacio si el valor no es ninguna
// de las dos cosas: entonces es una llamada normal.
// Una clausura escrita en el sitio es su struct: lo capturado, por valor.
// Pide su funcion a quien escribe el programa, con el tipo de cada captura,
// que es lo que llevara el struct.
fn cierre_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let st = vista(n.texto);
    let de_cierre = I.funcion_de_cierre(st);
    if largo(de_cierre) == 0 { return no_se(); }
    var pedido = nuevo("\t");
    empujar(pedido, vista(de_cierre));
    var piezas = vacio();
    for h en n.hijos {
        if !igual(vista(h.clase), "captura") { continue; }
        let nombre = vista(h.texto);
        let t = I.buscar(tipos, nombre);
        if largo(t) == 0 { return no_se(); }
        // Un prestamo no se captura: el comprobador ya lo rechazo.
        if T.es_referencia(vista(t)) || igual(vista(t), "view") { return no_se(); }
        // Capturar lo que tiene duenio es moverlo al struct: la bandera la
        // apaga la sentencia, aqui basta con que exista.
        if I.posee_con_formas(tipos, vista(t)) && !es_puntero(s, tipos, nombre)
        && !lleva_bandera(b, s, nombre) {
            return no_se();
        }
        let valor = expresion_c(b, s, P.hoja("variable", nombre, n.linea),
            vista(t), tipos);
        if es_desconocido(vista(valor)) { return no_se(); }
        if largo(piezas) > 0 { empujar(piezas, ", "); }
        let pieza = $".{nombre} = {valor}";
        empujar(piezas, vista(pieza));
        let sin_alias = I.sin_alias_tipo(vista(t));
        let campo = $"\t{nombre}={sin_alias}";
        empujar(pedido, vista(campo));
    }
    if largo(piezas) == 0 { piezas = nuevo(".ss_vacio = 0"); }
    anadir(b.instancias, pedido);
    return $"({st}){{ {piezas} }}";
}

fn llamada_a_valor(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto,
    local: view) -> str {
    let t = T.apuntado_si(local);
    let de_cierre = I.funcion_de_cierre(vista(t));
    if largo(de_cierre) > 0 {
        var otra = P.rama("llamada", n.linea);
        otra.texto = copiar(de_cierre);
        anadir(otra.hijos, P.hoja("variable", vista(n.texto), n.linea));
        for h en n.hijos { anadir(otra.hijos, copiar(h)); }
        return llamada_c(b, s, otra, tipos);
    }
    if !T.es_funcion(vista(t)) { return vacio(); }
    if es_puntero(s, tipos, vista(n.texto)) { return no_se(); }
    let partes = T.partes_de_funcion(vista(t));
    if largo(partes) == 0 { return no_se(); }
    var firmados: lista<str> = [];
    var marcados: lista<str> = [];
    var i = 0;
    while i + 1 < largo(partes) {
        let p = vista(partes[i]);
        anadir(firmados, T.apuntado_si(p));
        if empieza_con(p, "&mut ") { anadir(marcados, nuevo("mut ")); }
        else {
            if T.es_referencia(p) { anadir(marcados, nuevo("&")); }
            else { anadir(marcados, vacio()); }
        }
        i = i + 1;
    }
    return llamada_con_firma(b, s, n, tipos, vista(n.texto), firmados, marcados, "");
}

// Los argumentos de una llamada, ya elegida la funcion: `en_c` es como se
// llama en C, `firmados` el tipo de cada parametro y `marcados` su marca de
// prestamo. `pedido`, si no esta vacio, es la copia de generica que hace falta.
fn llamada_con_firma(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto,
    en_c: view, firmados: &lista<str>, marcados: &lista<str>,
    pedido: view) -> str {
    var v = nuevo(en_c);
    empujar(v, "(");
    var previos: lista<str> = [];
    let secuenciar = largo(n.hijos) > 1;
    // Cada argumento queda pendiente mientras se calculan los de despues: si
    // uno de ellos deja sentencias, los de antes corren antes.
    abrir_marco(b);
    var i = 0;
    for h en n.hijos {
        var esperado = vacio();
        if i < largo(firmados) { esperado = copiar(firmados[i]); }

        // Un parametro prestado recibe la direccion, no el valor. Si lo que
        // se le pasa ya es un puntero, se pasa tal cual.
        var presta_el = false;
        var presta_mut = false;
        if i < largo(marcados) {
            let m = vista(marcados[i]);
            presta_el = empieza_con(m, "&") || empieza_con(m, "mut ");
            presta_mut = empieza_con(m, "mut ");
        }
        if presta_el {
            let clase_h = vista(h.clase);
            if igual(clase_h, "variable") || igual(clase_h, "campo")
            || igual(clase_h, "indice") {
                let dir = direccion_del_sitio(b, s, h, tipos);
                if es_desconocido(vista(dir)) {
                    let _m = cerrar_marco(b);
                    return no_se();
                }
                agregar_argumento_marcado(b, h, vista(dir), vista(esperado), true,
                    presta_mut, secuenciar);
                i = i + 1;
                continue;
            }
            // Prestar algo recien hecho: se guarda en un temporal para poder
            // tomarle la direccion, y se suelta al acabar la sentencia como
            // cualquier otro valor descartado.
            if largo(esperado) == 0 {
                let _m = cerrar_marco(b);
                return no_se();
            }
            let tmp = nuevo_temporal(b);
            let valor = expresion_c(b, s, h, vista(esperado), tipos);
            if es_desconocido(vista(valor)) {
                let _m = cerrar_marco(b);
                return no_se();
            }
            reclamar(b, vista(valor));
            let tc = tipo_c(vista(esperado));
            emitir(b, $"{tc} {tmp} = {valor};");
            if I.posee_con_formas(tipos, vista(esperado)) {
                apuntar_temporal(b, vista(tmp), vista(esperado));
            }
            var dir = nuevo("&");
            empujar(dir, vista(tmp));
            agregar_argumento_marcado(b, h, vista(dir), vista(esperado), true,
                presta_mut, secuenciar);
            i = i + 1;
            continue;
        }

        // Donde se pide una vista, un `str` se lee prestandolo: escribir
        // `vista(s)` no le aportaria nada al compilador.
        if igual(vista(esperado), "view") {
            let suyo = I.tipo_de(tipos, h);
            if igual(vista(suyo), "str") {
                let arg = como_vista(b, s, h, tipos);
                if es_desconocido(vista(arg)) {
                    let _m = cerrar_marco(b);
                    return no_se();
                }
                agregar_argumento_marcado(b, h, vista(arg), "view", false, false,
                    secuenciar);
                i = i + 1;
                continue;
            }
        }

        // Pasar una variable con duenio a algo que se la queda es moverla.
        // La bandera la apaga la sentencia; aqui basta con que exista.
        if !presta_el && entrega_variable(s, h, tipos) {
            if !lleva_bandera(b, s, vista(h.texto)) {
                let _m = cerrar_marco(b);
                return no_se();
            }
        }
        let arg = expresion_c(b, s, h, vista(esperado), tipos);
        if es_desconocido(vista(arg)) || (secuenciar && largo(esperado) == 0) {
            let _m = cerrar_marco(b);
            return no_se();
        }
        // La funcion se lo queda: si venia de un temporal de la sentencia,
        // deja de soltarse ahi.
        if largo(esperado) > 0 && I.posee_con_formas(tipos, vista(esperado)) {
            reclamar(b, vista(arg));
        }
        agregar_argumento_marcado(b, h, vista(arg), vista(esperado), false, false,
            secuenciar);
        i = i + 1;
    }
    let marco_args = cerrar_marco(b);
    escribir_argumentos(marco_args, v, previos, ", ");
    // Despues de los argumentos: una generica que se llama dentro de otro
    // argumento se crea antes, como en el original.
    if largo(pedido) > 0 { anadir(b.instancias, nuevo(pedido)); }
    empujar(v, ")");
    if largo(previos) > 0 {
        var orden = nuevo("((");
        var primero = true;
        for p en previos {
            if !primero { empujar(orden, ", "); }
            primero = false;
            empujar(orden, vista(p));
        }
        empujar(orden, ", ");
        empujar(orden, vista(v));
        empujar(orden, "))");
        return orden;
    }
    return v;
}

fn llamada_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let nombre = vista(n.texto);
    // Una variable con una clausura o una funcion dentro se llama a traves
    // de su valor. Cualquier otra no cambia nada: es la funcion del nombre.
    let local = I.buscar(tipos, nombre);
    if largo(local) > 0 {
        let por_valor = llamada_a_valor(b, s, n, tipos, vista(local));
        if largo(por_valor) > 0 { return por_valor; }
    }
    let pura = interna_pura(b, s, n, tipos);
    if !es_desconocido(vista(pura)) { return pura; }
    if igual(nombre, "leer_archivo") || igual(nombre, "escribir_archivo")
    || igual(nombre, "leer_linea")
    || igual(nombre, "entrada_completa") || igual(nombre, "variable_entorno")
    || igual(nombre, "ahora_ms") || igual(nombre, "monotono_ms")
    || igual(nombre, "sembrar") || igual(nombre, "azar") {
        return interna_del_sistema(b, s, n, tipos);
    }
    if es_interna(nombre) { return no_se(); }
    if !tiene(tipos.retornos, nombre) { return no_se(); }
    // Una llamada a C pide convertir el `str` a `const char*` comprobando el
    // cero de en medio. Esta capa todavia no lo hace, asi que no la emite.
    if tiene(tipos.externas, nombre) { return llamada_externa_c(b, s, n, tipos); }
    if tiene(tipos.repetidas, nombre) { return no_se(); }

    var firmados = I.lista_de(tipos.params, nombre) sino [];
    let marcados = I.lista_de(tipos.params_marcados, nombre) sino [];
    // En C no queda el alias del modulo: `I.tipo_de` se llama `tipo_de`.
    var en_c = I.sin_modulo(nombre);
    // Un nombre propio que tambien traia un modulo: el cargador le pone el
    // nombre del archivo delante. Llamado con el alias del modulo seria el
    // otro, y ese no se sabe como quedo: no se emite.
    if tiene(tipos.renombradas, nombre) {
        en_c = nuevo(obtener(tipos.renombradas, nombre) sino "");
    }
    if contiene(nombre, ".") && tiene(tipos.renombradas, vista(en_c)) {
        return no_se();
    }

    // Una generica: se eligen los tipos mirando los argumentos, igual que el
    // comprobador, y se llama a la copia con ese juego de tipos. El nombre
    // de la copia lleva los tipos dentro, saneados para que sean C.
    var pedido = vacio();
    if tiene(tipos.tipo_params, nombre) {
        let sueltos = I.lista_de(tipos.tipo_params, nombre) sino [];
        var ligaduras: mapa<str, str> = [];
        var k = 0;
        while k < largo(firmados) && k < largo(n.hijos) {
            let dado = I.tipo_de(tipos, n.hijos[k]);
            let limpio = T.apuntado_si(vista(dado));
            I.unificar(vista(firmados[k]), vista(limpio), sueltos, ligaduras);
            k = k + 1;
        }
        empujar(en_c, "__");
        var primero = true;
        for tp en sueltos {
            if !tiene(ligaduras, vista(tp)) { return no_se(); }
            let ligado = nuevo(obtener(ligaduras, vista(tp)) sino "");
            if !primero { empujar(en_c, "_"); }
            primero = false;
            let ligado_c = I.nombre_resuelto(vista(ligado));
            let limpio = sanear(vista(ligado_c));
            empujar(en_c, vista(limpio));
        }
        // Lo que hace falta para escribir la copia: de que plantilla sale,
        // como se llama y que tipo va en cada parametro. Sin el alias del
        // modulo: la copia se escribe en el modulo de la plantilla.
        pedido = I.sin_modulo(nombre);
        empujar(pedido, "\t");
        empujar(pedido, vista(en_c));
        for tp en sueltos {
            let ligado = obtener(ligaduras, vista(tp)) sino "";
            let sin_alias = I.sin_alias_tipo(ligado);
            empujar(pedido, "\t");
            empujar(pedido, vista(tp));
            empujar(pedido, "=");
            empujar(pedido, vista(sin_alias));
        }
        var puestos: lista<str> = [];
        for f en firmados { anadir(puestos, I.sustituir(vista(f), ligaduras)); }
        firmados = puestos;
    }
    return llamada_con_firma(b, s, n, tipos, vista(en_c), firmados, marcados,
        vista(pedido));
}

// Si la expresion entrega una variable entera que tiene duenio: eso es un
// movimiento, y un movimiento pide bandera.
fn entrega_variable(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> bool {
    return entrega_suelta(s.punteros, n, tipos);
}

// Lo mismo sin el `Sitio`: la pasada que decide las banderas corre antes de
// que el `Sitio` exista, porque el `Sitio` las lleva dentro.
fn entrega_suelta(punteros: &mapa<str, usize>, n: &P.Nodo,
    tipos: &I.Contexto) -> bool {
    if !igual(vista(n.clase), "variable") { return false; }
    if tiene(punteros, vista(n.texto)) { return false; }
    let t = I.tipo_de(tipos, n);
    // Un struct que posee se mueve igual que un `str`: si solo se miraran
    // las colecciones, pasar un `Nodo` a quien se lo queda no pediria
    // bandera y se soltaria dos veces.
    return I.posee_con_formas(tipos, vista(t));
}

// ------------------------------------------------------------------
// Banderas de propiedad
// ------------------------------------------------------------------
//
// Una variable con duenio puede entregarse por unos caminos y no por otros:
//
//     var s = nuevo("hola");
//     if c { guardar(s); }    // por aqui se la llevan
//     // y aqui hay que soltarla, pero solo si no se la llevaron
//
// C no sabe cual de los dos caminos se tomo, asi que se le dice con un
// `bool ss_vivo_s`. Rust hace justo esto desde 1.12, y por lo mismo. C++ lo
// evita cobrando siempre: lo movido queda vacio pero valido y su destructor
// corre igual, uno por cada objeto movido. Go y Swift lo mandan al tiempo de
// ejecucion, recolector o cuentas de referencias. Zig no lo resuelve: lo
// escribe el programador con `defer`, y a veces se equivoca.
//
// Tcode cobra lo que Rust —un `bool` en la pila que el compilador de C borra
// en cuanto puede demostrar que sobra— y no pide escribir nada.

// Si el parametro `i` de `nombre` presta en vez de quedarse con el valor.
fn presta_argumento(tipos: &I.Contexto, nombre: view, i: usize) -> bool {
    // `anadir(xs, v)` y `poner(m, k, v)` prestan la coleccion y se quedan
    // con lo demas. Las otras internas cubiertas toman vistas o escalares.
    if igual(nombre, "anadir") { return i == 0; }
    // `intercambiar(sitio, v)` presta el sitio y se queda con `v`.
    if igual(nombre, "intercambiar") { return i == 0; }
    // La clave se copia dentro de la tabla: se presta. Solo el valor se
    // queda en el mapa.
    if igual(nombre, "poner") { return i < 2; }
    if es_interna(nombre) { return true; }
    // Un parametro `view` mira el texto, no se lo queda.
    let firmados = I.lista_de(tipos.params, nombre) sino [];
    if i < largo(firmados) {
        if igual(vista(firmados[i]), "view") { return true; }
    }
    let marcados = I.lista_de(tipos.params_marcados, nombre) sino [];
    if i >= largo(marcados) { return true; }
    let m = vista(marcados[i]);
    return empieza_con(m, "&") || empieza_con(m, "mut ");
}

fn apuntar_movida(salida: mut lista<str>, nombre: view) {
    for x en salida {
        if igual(vista(x), nombre) { return; }
    }
    anadir(salida, nuevo(nombre));
}

// Los nombres que este nodo entrega. Sin entrar en los bloques de dentro:
// cada sentencia apaga las suyas, donde toca.
fn movidas_en(punteros: &mapa<str, usize>, n: &P.Nodo, tipos: &I.Contexto,
    salida: mut lista<str>) {
    let clase = vista(n.clase);
    if igual(clase, "bloque") { return; }

    // La alternativa de un `sino` solo corre si la llamada falla: lo que
    // entrega lo apaga esa rama, no la sentencia entera.
    if igual(clase, "sino") && largo(n.hijos) == 2 {
        movidas_en(punteros, n.hijos[0], tipos, salida);
        return;
    }

    // `let y = x;` y `y = x;` mueven tanto como pasarla a una funcion.
    if igual(clase, "declaracion") && largo(n.hijos) == 1 {
        if entrega_suelta(punteros, n.hijos[0], tipos) {
            apuntar_movida(salida, vista(n.hijos[0].texto));
        }
    }
    if igual(clase, "asignacion") && largo(n.hijos) == 2 {
        if entrega_suelta(punteros, n.hijos[1], tipos) {
            apuntar_movida(salida, vista(n.hijos[1].texto));
        }
    }

    if igual(clase, "enum_lit") {
        for h en n.hijos {
            if entrega_suelta(punteros, h, tipos) {
                apuntar_movida(salida, vista(h.texto));
            }
        }
    }

    if igual(clase, "literal_struct") {
        for h en n.hijos {
            for x en h.hijos {
                if entrega_suelta(punteros, x, tipos) {
                    apuntar_movida(salida, vista(x.texto));
                }
            }
        }
    }

    // Capturar por valor lo que tiene duenio es entregarlo al struct de la
    // clausura, igual que meterlo en un literal.
    if igual(clase, "cierre") {
        for h en n.hijos {
            if !igual(vista(h.clase), "captura") { continue; }
            let v = P.hoja("variable", vista(h.texto), n.linea);
            if entrega_suelta(punteros, v, tipos) {
                apuntar_movida(salida, vista(h.texto));
            }
        }
    }

    if igual(clase, "llamada") {
        var i = 0;
        for h en n.hijos {
            if !presta_argumento(tipos, vista(n.texto), i) {
                if entrega_suelta(punteros, h, tipos) {
                    apuntar_movida(salida, vista(h.texto));
                }
            }
            i = i + 1;
        }
    }

    for h en n.hijos { movidas_en(punteros, h, tipos, salida); }
}

// Lo que entrega la alternativa de un `sino`, que se apaga dentro de su rama.
fn movidas_de_alternativa(punteros: &mapa<str, usize>, n: &P.Nodo,
    tipos: &I.Contexto, salida: mut lista<str>) {
    if entrega_suelta(punteros, n, tipos) {
        apuntar_movida(salida, vista(n.texto));
    }
    movidas_en(punteros, n, tipos, salida);
}

// Lo que se entrega solo por un camino dentro de la sentencia: las
// alternativas de sus `sino`. Tambien pide bandera, aunque no lo apague la
// sentencia.
fn movidas_por_caminos(punteros: &mapa<str, usize>, n: &P.Nodo,
    tipos: &I.Contexto, salida: mut lista<str>) {
    if igual(vista(n.clase), "bloque") { return; }
    if igual(vista(n.clase), "sino") && largo(n.hijos) == 2 {
        movidas_de_alternativa(punteros, n.hijos[1], tipos, salida);
    }
    for h en n.hijos { movidas_por_caminos(punteros, h, tipos, salida); }
}

// Lo mismo entrando en los bloques de dentro: es la pasada que decide quien
// lleva bandera. Declara los locales segun los va encontrando, porque para
// saber si una variable se entrega hay que saber primero que tiene duenio, y
// eso lo dice su tipo. Devolver una variable no cuenta: ahi ya no queda
// nadie a quien mentirle.
fn movidas_hondo(punteros: &mapa<str, usize>, bloque: &P.Nodo,
    tipos: mut I.Contexto, salida: mut lista<str>) {
    let ninguna: lista<str> = [];
    movidas_hondo_en(punteros, bloque, tipos, salida, ninguna);
}

// `visibles` son las declaraciones que se ven desde aqui, como
// `nombre@linea`. Cada bloque trabaja sobre su propia copia: lo que se
// declara dentro no se ve fuera, y asi no hace falta deshacer nada.
fn movidas_hondo_en(punteros: &mapa<str, usize>, bloque: &P.Nodo,
    tipos: mut I.Contexto, salida: mut lista<str>, visibles: &lista<str>) {
    var mias: lista<str> = [];
    for x en visibles { anadir(mias, copiar(x)); }
    I.abrir(tipos);
    for st en bloque.hijos {
        // Lo que entrega esta sentencia se mira ANTES de declarar lo que
        // declara: `let y = x;` entrega la `x` de fuera.
        var salen: lista<str> = [];
        movidas_en(punteros, st, tipos, salen);
        movidas_por_caminos(punteros, st, tipos, salen);
        for nm en salen {
            let k = visible_en(mias, vista(nm));
            apuntar_movida(salida, vista(k));
        }
        if igual(vista(st.clase), "declaracion") && largo(st.hijos) == 1 {
            let nombre = nombre_declarado(vista(st.texto));
            var tipo = tipo_escrito(vista(st.texto));
            if largo(tipo) == 0 { tipo = I.tipo_de(tipos, st.hijos[0]); }
            I.declarar(tipos, vista(nombre), vista(tipo));
            anadir(mias, clave_de(vista(nombre), st.linea));
        }
        // Un `for` declara su variable para el cuerpo. Sin ella, lo que se
        // calcula a partir de ella —`var p = copiar(l)`— no tiene tipo, y no
        // se sabria que `p` posee ni que se entrega.
        let es_para = igual(vista(st.clase), "para") && largo(st.hijos) == 2;
        if es_para {
            I.abrir(tipos);
            let suyo = I.tipo_de(tipos, st.hijos[0]);
            let sobre = T.apuntado_si(vista(suyo));
            let uno = primer_nombre(vista(st.texto));
            let dos = segundo_nombre(vista(st.texto));
            if T.es_mapa(vista(sobre)) {
                let partes = T.partir_tipos(T.entre_angulos(vista(sobre)));
                if largo(partes) == 2 {
                    I.declarar(tipos, vista(uno), vista(partes[0]));
                    if largo(dos) > 0 {
                        I.declarar(tipos, vista(dos), vista(partes[1]));
                    }
                }
            } else {
                let elem = T.elemento(vista(sobre));
                I.declarar(tipos, vista(uno), vista(elem));
            }
        }
        for h en st.hijos {
            if igual(vista(h.clase), "bloque") {
                movidas_hondo_en(punteros, h, tipos, salida, mias);
            }
        }
        if es_para { I.cerrar(tipos); }
    }
    I.cerrar(tipos);
}

fn visible_en(visibles: &lista<str>, nombre: view) -> str {
    var i = largo(visibles);
    while i > 0 {
        i = i - 1;
        let n = antes_de_arroba(vista(visibles[i]));
        if igual(vista(n), nombre) { return copiar(visibles[i]); }
    }
    return clave_de(nombre, 0);
}

// Las que hablan con el sistema y pueden fallar. No llevan argumentos que
// convertir, asi que su C es el nombre y ya.
fn interna_del_sistema(b: mut Cuerpo, s: &Sitio, n: &P.Nodo,
    tipos: &I.Contexto) -> str {
    let nombre = vista(n.texto);
    if igual(nombre, "leer_archivo") {
        if largo(n.hijos) != 1 { return no_se(); }
        let ruta = como_vista(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(ruta)) { return no_se(); }
        var r = nuevo("ss_lang_leer_archivo_(");
        empujar(r, vista(ruta));
        empujar(r, ")");
        return r;
    }
    // La ruta y luego los datos, cada uno una sola vez.
    if igual(nombre, "escribir_archivo") {
        if largo(n.hijos) != 2 { return no_se(); }
        abrir_marco(b);
        let ruta_0 = como_vista(b, s, n.hijos[0], tipos);
        apuntar_pendiente(b, operando(n.hijos[0], vista(ruta_0), "SafeView"));
        let datos = como_vista(b, s, n.hijos[1], tipos);
        let marco_a = cerrar_marco(b);
        let ruta = copiar(marco_a.entradas[0].valor);
        if es_desconocido(vista(ruta)) || es_desconocido(vista(datos)) { return no_se(); }
        var r = nuevo("ss_lang_escribir_archivo_(");
        var previos: lista<str> = [];
        agregar_argumento_ordenado(b, r, previos, vista(ruta), "view",
            false, false, true);
        empujar(r, ", ");
        agregar_argumento_ordenado(b, r, previos, vista(datos), "view",
            false, false, true);
        empujar(r, ")");
        b.ultima_linea = 0;
        marcar(b, s, n.linea);
        return envolver_llamada_ordenada(r, previos);
    }
    if igual(nombre, "variable_entorno") {
        if largo(n.hijos) != 1 { return no_se(); }
        let v = como_vista(b, s, n.hijos[0], tipos);
        if es_desconocido(vista(v)) { return no_se(); }
        return $"ss_lang_variable_entorno_({v})";
    }
    if igual(nombre, "sembrar") {
        if largo(n.hijos) != 1 { return no_se(); }
        let x = expresion_c(b, s, n.hijos[0], "u64", tipos);
        if es_desconocido(vista(x)) { return no_se(); }
        return $"ss_lang_sembrar_({x})";
    }
    if igual(nombre, "azar") {
        if largo(n.hijos) != 1 { return no_se(); }
        let x = expresion_c(b, s, n.hijos[0], "usize", tipos);
        if es_desconocido(vista(x)) { return no_se(); }
        return $"ss_lang_azar_({x}, \"{s.archivo}\", {n.linea})";
    }
    if largo(n.hijos) != 0 { return no_se(); }
    var r = nuevo("ss_lang_");
    empujar(r, nombre);
    empujar(r, "_()");
    return r;
}

fn es_interna(nombre: view) -> bool {
    if igual(nombre, "byte") { return true; }
    if igual(nombre, "largo") || igual(nombre, "nuevo") { return true; }
    if igual(nombre, "vacio") || igual(nombre, "vista") { return true; }
    if igual(nombre, "rebanar") || igual(nombre, "igual") { return true; }
    if igual(nombre, "menor") { return true; }
    if igual(nombre, "imprimir") || igual(nombre, "empujar") { return true; }
    if igual(nombre, "anadir") || igual(nombre, "poner") { return true; }
    if igual(nombre, "obtener") || igual(nombre, "tiene") { return true; }
    if igual(nombre, "claves") || igual(nombre, "quitar") { return true; }
    if igual(nombre, "texto") || igual(nombre, "copiar") { return true; }
    if igual(nombre, "ordenar") || igual(nombre, "reservar") { return true; }
    if igual(nombre, "redimensionar") || igual(nombre, "intercambiar") { return true; }
    return false;
}

// ------------------------------------------------------------------
// Sentencias, y la liberacion automatica
// ------------------------------------------------------------------
//
// Aqui esta lo que hace que Tcode sea Tcode: nadie escribe un `ss_free`, y
// al cerrar un bloque se devuelve lo que nacio dentro, en orden inverso al
// que se declaro. En una funcion, lo que se devuelve no se libera.
//
// Se cubre el subconjunto sin banderas: funciones donde ningun valor se
// mueve a otro sitio. Una bandera hace falta cuando un valor se entrega solo
// por algunos caminos, y eso es la parte dificil, no esta.

struct Cuerpo {
    lineas: lista<str>,
    // Lo declarado en cada bloque abierto: `nombre: tipo`, del mas de fuera
    // al mas de dentro.
    bloques: lista<lista<str>>,
    // La misma forma que `bloques`, con `nombre@linea` de cada declaracion.
    // Las banderas se deciden por declaracion y no por nombre: tres `r` en
    // tres bloques son tres variables, y que una se entregue no dice nada
    // de las otras dos.
    claves: lista<lista<str>>,
    sangria: usize,
    temporal: usize,
    // La ultima posicion marcada con `#line`, para no repetirla.
    ultima_linea: usize,
    // Cuantos bucles se han abierto: cada uno lleva su propio indice.
    bucle: usize,
    // Lo que nace a mitad de una sentencia y no tiene nombre: el `str` que
    // devuelve `tipo_c(t)` dentro de `empujar(s, tipo_c(t))`. Vive hasta el
    // final de la sentencia, y se suelta ahi. Van como `nombre: tipo`, igual
    // que los bloques.
    temporales: lista<str>,
    // Los temporales de las sentencias que envuelven a la actual, de fuera
    // hacia dentro. Una salida temprana tiene que soltarlos todos: la
    // limpieza de fin de cada una se emite despues y no se alcanza.
    fuera: lista<lista<str>>,
    // Cuantos bloques habia abiertos al empezar el bucle mas de dentro.
    // Salir de un bucle salta el cierre de los bloques de dentro, asi que
    // hay que soltarlos a mano; los de fuera siguen vivos.
    bucles: lista<usize>,
    // Cuantas listas de `fuera` habia al abrir cada bucle: `break` y
    // `continue` sueltan solo las de las sentencias de dentro del bucle.
    bucles_t: lista<usize>,
    // La primera sentencia que esta capa no supo hacer, y de que clase era.
    // No cambia nada de lo que se emite: sirve para poder decir que falta
    // sin tener que adivinarlo contando nodos.
    fallo_linea: usize,
    fallo_clase: str,
    // Las copias de genericas que piden las llamadas, en el orden en que se
    // terminan de escribir: `plantilla\tnombre_c\tT=tipo...`.
    instancias: lista<str>,
    // Los tipos que se copian con un copiador generado, en orden.
    copias: lista<str>,
    // Los arreglos que nombra un literal sin declararse en ningun sitio:
    // `for x en [1, 2]`. Su typedef llega tarde, detras de los demas.
    arreglos: lista<str>,
    // Las etiquetas de `goto` puestas en todo el archivo, los `switch`
    // abiertos, y cuantos habia al abrir cada bucle: un `break` dentro de un
    // `switch` saldria del `switch`, asi que sale con `goto` a una etiqueta
    // detras del bucle. Esa etiqueta, si hizo falta, en `etiquetas_bucle`.
    etiquetas: usize,
    en_switch: usize,
    switch_en_bucle: lista<usize>,
    etiquetas_bucle: lista<str>,
    // Lo ya calculado de una expresion que todavia no corrio: cada marco es
    // una operacion o una llamada a medio escribir.
    por_correr: lista<Marco>,
}

// Un operando ya calculado que todavia no corrio: su C, su tipo en C, si no
// hace falta adelantarlo, y el temporal donde lo guarda la llamada, si lo
// guarda.
struct Pendiente {
    valor: str,
    tipo_c: str,
    fijo: bool,
    tmp: str,
}

// Una barrera corta: lo de fuera no se adelanta dentro de ella.
struct Marco {
    barrera: bool,
    entradas: lista<Pendiente>,
}

// Lo apunta el sitio mas hondo, y solo la primera vez: si un `if` falla
// porque falla algo de dentro, lo que interesa es lo de dentro.
fn apuntar_fallo(b: mut Cuerpo, n: &P.Nodo) {
    if b.fallo_linea != 0 { return; }
    b.fallo_linea = n.linea;
    b.fallo_clase = nuevo(vista(n.clase));
}

fn nombre_de_indice(n: usize) -> str {
    var s = nuevo("ss_k");
    empujar(s, texto(n));
    return s;
}

fn nombre_de_bucle(n: usize) -> str {
    var s = nuevo("ss_i");
    empujar(s, texto(n));
    return s;
}

// Un arreglo que pide typedef, con los arreglos que lleva dentro delante.
fn apuntar_arreglo(b: mut Cuerpo, t: view) {
    if !T.es_arreglo(t) { return; }
    let dentro = T.elemento(t);
    apuntar_arreglo(b, vista(dentro));
    for x en b.arreglos {
        if igual(vista(x), t) { return; }
    }
    anadir(b.arreglos, nuevo(t));
}

fn cuerpo() -> Cuerpo {
    return Cuerpo { lineas: [], bloques: [], claves: [], sangria: 1, temporal: 0,
        ultima_linea: 0, bucle: 0, bucles: [], temporales: [], fuera: [], bucles_t: [],
        fallo_linea: 0, fallo_clase: vacio(), instancias: [], copias: [], arreglos: [],
        etiquetas: 0, en_switch: 0, switch_en_bucle: [], etiquetas_bucle: [], por_correr: [] };
}

fn sangrar(b: &Cuerpo) -> str {
    var s = vacio();
    var i = 0;
    while i < b.sangria {
        empujar(s, "    ");
        i = i + 1;
    }
    return s;
}

fn emitir(b: mut Cuerpo, texto_linea: view) {
    if largo(texto_linea) > 0 && hace_algo(texto_linea) { adelantar(b); }
    var l = sangrar(b);
    empujar(l, texto_linea);
    anadir(b.lineas, l);
}

// Los operandos ya calculados que todavia no corrieron se calculan aqui, en
// temporales, antes de la sentencia que viene: esa sentencia es de un
// operando que va despues, y la evaluacion va de izquierda a derecha. Sin
// esto, `f() + (if c { g() } else { 0 })` llamaba a `g` antes que a `f`.
fn adelantar(b: mut Cuerpo) {
    var inicio = 0;
    var i = largo(b.por_correr);
    while i > 0 {
        if b.por_correr[i - 1].barrera {
            inicio = i;
            break;
        }
        i = i - 1;
    }
    var k = inicio;
    while k < largo(b.por_correr) {
        var j = 0;
        while j < largo(b.por_correr[k].entradas) {
            if !b.por_correr[k].entradas[j].fijo {
                let tmp = nuevo_temporal(b);
                let tc = copiar(b.por_correr[k].entradas[j].tipo_c);
                let valor = copiar(b.por_correr[k].entradas[j].valor);
                var l = sangrar(b);
                empujar(l, $"{tc} {tmp} = {valor};");
                anadir(b.lineas, l);
                b.por_correr[k].entradas[j].valor = tmp;
                b.por_correr[k].entradas[j].fijo = true;
            }
            j = j + 1;
        }
        k = k + 1;
    }
}

// Lo que se puede llamar sin que se note cuando: no escribe, no para, no
// cambia nada que se vea. Reservar memoria solo para si no queda.
fn es_puro_c(nombre: view) -> bool {
    if igual(nombre, "sizeof") || igual(nombre, "sv") || igual(nombre, "sv_len") { return true; }
    if igual(nombre, "sv_len_of") || igual(nombre, "ss_view") { return true; }
    if igual(nombre, "sv_equals") || igual(nombre, "sv_cmp") { return true; }
    if igual(nombre, "ss_new") || igual(nombre, "ss_from") || igual(nombre, "ss_from_view") {
        return true;
    }
    if igual(nombre, "ss_clone") { return true; }
    return igual(nombre, "SS_LANG_USIZE_LIT");
}

fn empieza_nombre_c(c: usize) -> bool {
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
}

fn sigue_nombre_c(c: usize) -> bool {
    return empieza_nombre_c(c) || (c >= 48 && c <= 57);
}

// Si correr esta linea antes que un operando ya calculado se puede notar:
// abre un `if`, un bucle o un `switch` —lo que va dentro correria solo a
// veces—, o llama a algo que escribe, para o cambia algo. Copiar un valor o
// tomar una vista no.
fn hace_algo(linea: view) -> bool {
    var i = 0;
    while i < largo(linea) && (byte(linea, i) == 32 || byte(linea, i) == 9) { i = i + 1; }
    if i >= largo(linea) || byte(linea, i) == 35 { return false; }
    // Una palabra de control al principio.
    var fin = i;
    while fin < largo(linea) && sigue_nombre_c(byte(linea, fin)) { fin = fin + 1; }
    let primera = rebanar(linea, i, fin);
    if igual(primera, "if") || igual(primera, "while") || igual(primera, "for")
    || igual(primera, "switch") || igual(primera, "do") || igual(primera, "else")
    || igual(primera, "goto") || igual(primera, "return") {
        return true;
    }
    // Cada nombre seguido de `(`.
    while i < largo(linea) {
        if !empieza_nombre_c(byte(linea, i)) {
            i = i + 1;
            continue;
        }
        var j = i;
        while j < largo(linea) && sigue_nombre_c(byte(linea, j)) { j = j + 1; }
        var k = j;
        while k < largo(linea) && (byte(linea, k) == 32 || byte(linea, k) == 9) { k = k + 1; }
        if k < largo(linea) && byte(linea, k) == 40 {
            if !es_puro_c(rebanar(linea, i, j)) { return true; }
            i = k + 1;
        } else {
            i = j;
        }
    }
    return false;
}

// Un numero, un texto o un booleano escritos: calcularlos antes o despues da
// igual.
fn es_constante(n: &P.Nodo) -> bool {
    let clase = vista(n.clase);
    if igual(clase, "unaria") && igual(vista(n.texto), "-") && largo(n.hijos) == 1 {
        let hc = vista(n.hijos[0].clase);
        return igual(hc, "entero") || igual(hc, "decimal");
    }
    return igual(clase, "entero") || igual(clase, "decimal") || igual(clase, "booleano")
    || igual(clase, "cadena");
}

// La entrada de un marco para un operando ya calculado. No hace falta
// adelantar un numero escrito, ni una direccion, que es lo que llega sin
// tipo: el sitio no cambia. Un valor con duenio se adelanta tambien: pasa al
// temporal, y de ahi a quien se lo queda.
fn operando(n: &P.Nodo, valor: view, tipo_c_op: view) -> Pendiente {
    let fijo = largo(tipo_c_op) == 0 || es_constante(n);
    return Pendiente { valor: nuevo(valor), tipo_c: nuevo(tipo_c_op), fijo: fijo,
        tmp: vacio() };
}

fn abrir_marco(b: mut Cuerpo) {
    anadir(b.por_correr, Marco { barrera: false, entradas: [] });
}

fn poner_barrera(b: mut Cuerpo) {
    anadir(b.por_correr, Marco { barrera: true, entradas: [] });
}

fn apuntar_pendiente(b: mut Cuerpo, p: Pendiente) {
    let k = largo(b.por_correr);
    if k > 0 { anadir(b.por_correr[k - 1].entradas, p); }
}

fn cerrar_marco(b: mut Cuerpo) -> Marco {
    var quedan: lista<Marco> = [];
    var ultimo = Marco { barrera: false, entradas: [] };
    var i = 0;
    let n = largo(b.por_correr);
    while i < n {
        if i + 1 < n {
            anadir(quedan, intercambiar(b.por_correr[i], Marco { barrera: false, entradas: [] }));
        } else {
            ultimo = intercambiar(b.por_correr[i], Marco { barrera: false, entradas: [] });
        }
        i = i + 1;
    }
    b.por_correr = quedan;
    return ultimo;
}

fn emitir_crudo(b: mut Cuerpo, texto_linea: view) {
    anadir(b.lineas, nuevo(texto_linea));
}

// `#line`: le dice al compilador de C de que linea de Tcode viene lo que
// sigue. Va pegada al margen, que una directiva sangrada no es directiva.
fn marcar(b: mut Cuerpo, s: &Sitio, linea: usize) {
    if linea == 0 || linea == b.ultima_linea { return; }
    b.ultima_linea = linea;
    var l = nuevo("#line ");
    empujar(l, texto(linea));
    empujar(l, " \"");
    empujar(l, vista(s.archivo));
    empujar(l, "\"");
    emitir_crudo(b, vista(l));
}

fn nuevo_temporal(b: mut Cuerpo) -> str {
    b.temporal = b.temporal + 1;
    var s = nuevo("ss_tmp");
    empujar(s, texto(b.temporal));
    return s;
}

fn abrir_bloque(b: mut Cuerpo) {
    let vacio_bloque: lista<str> = [];
    anadir(b.bloques, vacio_bloque);
    let vacias: lista<str> = [];
    anadir(b.claves, vacias);
}

// `clave` es `nombre@linea` de la declaracion: la bandera se busca por ella.
fn anotar_duenio(b: mut Cuerpo, nombre: view, tipo: view, clave: view) {
    if largo(b.bloques) == 0 { abrir_bloque(b); }
    var junto = nuevo(nombre);
    empujar(junto, ": ");
    empujar(junto, tipo);
    let ultimo = largo(b.bloques) - 1;
    anadir(b.bloques[ultimo], junto);
    anadir(b.claves[ultimo], nuevo(clave));
}

fn clave_de(nombre: view, linea: usize) -> str {
    var k = nuevo(nombre);
    empujar(k, "@");
    empujar(k, texto(linea));
    return k;
}

fn antes_de_arroba(t: view) -> str {
    var i = largo(t);
    while i > 0 {
        i = i - 1;
        if byte(t, i) == 64 { return nuevo(rebanar(t, 0, i)); }
    }
    return nuevo(t);
}

// La declaracion visible de un nombre, de dentro hacia fuera. Si no la hay,
// es un parametro: esos se apuntan con la linea 0.
fn clave_visible(b: &Cuerpo, nombre: view) -> str {
    var i = largo(b.bloques);
    while i > 0 {
        i = i - 1;
        var j = largo(b.bloques[i]);
        while j > 0 {
            j = j - 1;
            let n = antes_de_dos_puntos(vista(b.bloques[i][j]));
            if igual(vista(n), nombre) { return copiar(b.claves[i][j]); }
        }
    }
    return clave_de(nombre, 0);
}

fn lleva_bandera(b: &Cuerpo, s: &Sitio, nombre: view) -> bool {
    let k = clave_visible(b, nombre);
    return tiene(s.pide_bandera, vista(k));
}

// Suelta lo del bloque de dentro, en orden inverso, y lo quita de la pila.
fn cerrar_bloque(b: mut Cuerpo, s: &Sitio, tipos: &I.Contexto) {
    if largo(b.bloques) == 0 { return; }
    let ultimo = largo(b.bloques) - 1;
    liberar_uno(b, s, tipos, ultimo, "");
    quitar_ultimo_bloque(b);
}

// Deja el cuerpo como estaba en `hasta` lineas. Lo usa el `while` cuya
// condicion hay que rehacer dentro del bucle.
fn recortar_lineas(b: mut Cuerpo, hasta: usize) {
    var quedan: lista<str> = [];
    var i = 0;
    while i < hasta {
        anadir(quedan, copiar(b.lineas[i]));
        i = i + 1;
    }
    b.lineas = quedan;
}

// Un temporal de sentencia: nace aqui y se suelta al acabar la sentencia,
// salvo que alguien se quede con el.
fn apuntar_temporal(b: mut Cuerpo, nombre: view, tipo: view) {
    var junto = nuevo(nombre);
    empujar(junto, ": ");
    empujar(junto, tipo);
    anadir(b.temporales, junto);
}

// Quien se queda con un temporal lo dice, y deja de soltarse aqui.
fn reclamar(b: mut Cuerpo, valor: view) {
    var quedan: lista<str> = [];
    for t en b.temporales {
        let n = antes_de_dos_puntos(vista(t));
        if !igual(vista(n), valor) { anadir(quedan, copiar(t)); }
    }
    b.temporales = quedan;
}

fn soltar_temporales(b: mut Cuerpo, tipos: &I.Contexto) {
    var i = 0;
    while i < largo(b.temporales) {
        let entrada = copiar(b.temporales[i]);
        let n = antes_de_dos_puntos(vista(entrada));
        let t = despues_de_dos_puntos(vista(entrada));
        liberacion(b, tipos, vista(n), vista(t));
        i = i + 1;
    }
}

// Lo que ya se solto al salir no se suelta otra vez.
fn olvidar_temporales(b: mut Cuerpo) {
    let vacia: lista<str> = [];
    b.temporales = vacia;
}

fn nueva_etiqueta(b: mut Cuerpo, que: view) -> str {
    b.etiquetas = b.etiquetas + 1;
    return $"ss_fin_{que}{b.etiquetas}";
}

fn abrir_bucle_saltos(b: mut Cuerpo) {
    anadir(b.switch_en_bucle, b.en_switch);
    anadir(b.etiquetas_bucle, vacio());
}

// Detras del bucle, la etiqueta a la que salta un `break` que iba dentro de
// un `switch`, si lo hubo.
fn cerrar_bucle_saltos(b: mut Cuerpo) {
    if largo(b.etiquetas_bucle) == 0 { return; }
    let etiqueta = copiar(b.etiquetas_bucle[largo(b.etiquetas_bucle) - 1]);
    var quedan: lista<usize> = [];
    var quedan_e: lista<str> = [];
    var i = 0;
    while i + 1 < largo(b.etiquetas_bucle) {
        anadir(quedan, b.switch_en_bucle[i]);
        anadir(quedan_e, copiar(b.etiquetas_bucle[i]));
        i = i + 1;
    }
    b.switch_en_bucle = quedan;
    b.etiquetas_bucle = quedan_e;
    if largo(etiqueta) > 0 { emitir(b, $"{etiqueta}: ;"); }
}

fn quitar_ultimo_bucle(b: mut Cuerpo) {
    if largo(b.bucles) == 0 { return; }
    var quedan: lista<usize> = [];
    var i = 0;
    while i + 1 < largo(b.bucles) {
        anadir(quedan, b.bucles[i]);
        i = i + 1;
    }
    b.bucles = quedan;
    var quedan_t: lista<usize> = [];
    var j = 0;
    while j + 1 < largo(b.bucles_t) {
        anadir(quedan_t, b.bucles_t[j]);
        j = j + 1;
    }
    b.bucles_t = quedan_t;
}

fn quitar_ultimo_bloque(b: mut Cuerpo) {
    var quedan: lista<lista<str>> = [];
    var sus_claves: lista<lista<str>> = [];
    var i = 0;
    while i + 1 < largo(b.bloques) {
        var copia: lista<str> = [];
        for x en b.bloques[i] { anadir(copia, copiar(x)); }
        anadir(quedan, copia);
        var ks: lista<str> = [];
        for x en b.claves[i] { anadir(ks, copiar(x)); }
        anadir(sus_claves, ks);
        i = i + 1;
    }
    b.bloques = quedan;
    b.claves = sus_claves;
}

// Todo lo vivo, de dentro hacia fuera: es lo que hace falta antes de un
// `return`, donde no se cierra un bloque sino todos.
fn liberar_todo(b: mut Cuerpo, s: &Sitio, tipos: &I.Contexto,
    excepto: view) {
    // Los de la sentencia en curso primero: `return $"{rellenar(v, 8)}"`
    // dejaria el `str` de `rellenar` sin soltar, porque la limpieza de fin
    // de sentencia se emite DESPUES del `return` y no se ejecuta nunca.
    soltar_temporales(b, tipos);
    // Y los de las sentencias que la envuelven: en `if largo(claves(m)) > 0
    // { return 1; }` la lista de `claves` es de la condicion del `if`, no del
    // `return`, y sin esto se escapaba por ese camino.
    soltar_fuera_desde(b, tipos, 0);
    var i = largo(b.bloques);
    while i > 0 {
        i = i - 1;
        liberar_uno(b, s, tipos, i, excepto);
    }
}

// Las listas de `fuera` desde `desde`, de dentro hacia fuera. Se sueltan
// sin quitarlas: el camino que no sale tiene que soltarlas igual al acabar
// cada sentencia.
fn soltar_fuera_desde(b: mut Cuerpo, tipos: &I.Contexto, desde: usize) {
    var k = largo(b.fuera);
    while k > desde {
        k = k - 1;
        let copia = copiar(b.fuera[k]);
        for entrada en copia {
            let n = antes_de_dos_puntos(vista(entrada));
            let t = despues_de_dos_puntos(vista(entrada));
            liberacion(b, tipos, vista(n), vista(t));
        }
    }
}

fn quitar_ultima_fuera(b: mut Cuerpo) {
    if largo(b.fuera) == 0 { return; }
    var quedan: lista<lista<str>> = [];
    var i = 0;
    while i + 1 < largo(b.fuera) {
        anadir(quedan, copiar(b.fuera[i]));
        i = i + 1;
    }
    b.fuera = quedan;
}

fn liberar_uno(b: mut Cuerpo, s: &Sitio, tipos: &I.Contexto,
    cual: usize, excepto: view) {
    var j = largo(b.bloques[cual]);
    while j > 0 {
        j = j - 1;
        let entrada = copiar(b.bloques[cual][j]);
        let nombre = antes_de_dos_puntos(vista(entrada));
        if igual(vista(nombre), excepto) { continue; }
        let tipo = despues_de_dos_puntos(vista(entrada));
        // Si se entrega por algun camino, quien decide es la bandera: aqui
        // no se sabe por cual se vino.
        if tiene(s.pide_bandera, vista(b.claves[cual][j])) {
            var g = nuevo("if (ss_vivo_");
            empujar(g, vista(nombre));
            empujar(g, ")");
            emitir(b, vista(g));
            emitir(b, "{");
            b.sangria = b.sangria + 1;
            liberacion(b, tipos, vista(nombre), vista(tipo));
            b.sangria = b.sangria - 1;
            emitir(b, "}");
            continue;
        }
        liberacion(b, tipos, vista(nombre), vista(tipo));
    }
}

// `bool ss_vivo_x = true;` justo detras de la declaracion de `x`.
fn nace_bandera(b: mut Cuerpo, nombre: view) {
    var l = nuevo("bool ss_vivo_");
    empujar(l, nombre);
    empujar(l, " = true;");
    emitir(b, vista(l));
}

// `ss_vivo_x = false;` por cada una que se entrego en el camino que acaba.
fn apagar(b: mut Cuerpo, nombres: &lista<str>) {
    for nm en nombres {
        var l = nuevo("ss_vivo_");
        empujar(l, vista(nm));
        empujar(l, " = false;");
        emitir(b, vista(l));
    }
}

// Lo que hay que soltar, dentro del subconjunto que esta capa emite.
// `T.posee` sabe mas —structs, arreglos— pero pide los campos de todos los
// structs y puede fallar; aqui no hace falta tanto.
fn tiene_duenio(t: view) -> bool {
    if igual(t, "str") { return true; }
    return T.es_lista(t) || T.es_mapa(t) || T.es_bloque(t);
}

fn liberacion(b: mut Cuerpo, tipos: &I.Contexto, nombre: view,
    tipo: view) {
    if igual(tipo, "str") {
        var l = nuevo("ss_free(&");
        empujar(l, nombre);
        empujar(l, ");");
        emitir(b, vista(l));
        return;
    }
    // Una lista suelta su memoria y se queda vacia. Si sus elementos tienen
    // duenio, cada uno se suelta antes: la lista era su unica duenia.
    // Un arreglo no tiene memoria propia que devolver: vive entero donde se
    // declaro. Lo que haya que soltar son sus elementos, si poseen, uno a uno.
    if T.es_arreglo(tipo) {
        let elem = T.elemento(tipo);
        if !I.posee_con_formas(tipos, vista(elem)) { return; }
        b.bucle = b.bucle + 1;
        let i = nombre_de_bucle(b.bucle);
        let cuantos = cuantos_de_arreglo(tipo);
        var f = nuevo("for (size_t ");
        empujar(f, vista(i));
        empujar(f, " = 0; ");
        empujar(f, vista(i));
        empujar(f, " < ");
        empujar(f, vista(cuantos));
        empujar(f, "; ");
        empujar(f, vista(i));
        empujar(f, "++)");
        emitir(b, vista(f));
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        var dentro = nuevo(nombre);
        empujar(dentro, ".e[");
        empujar(dentro, vista(i));
        empujar(dentro, "]");
        liberacion(b, tipos, vista(dentro), vista(elem));
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        return;
    }

    // Un mapa suelta su tabla, sus claves y sus valores de una vez: lleva
    // su propio liberador generado, como cada tipo de mapa lleva el suyo.
    if T.es_mapa(tipo) {
        var l = nuevo("ss_mapa_libre_");
        empujar(l, mangle(tipo));
        empujar(l, "(&");
        empujar(l, nombre);
        empujar(l, ");");
        emitir(b, vista(l));
        return;
    }

    // Un bloque suelta sus elementos, si poseen, y luego su memoria.
    if T.es_bloque(tipo) {
        let elem_b = T.elemento(tipo);
        if I.posee_con_formas(tipos, vista(elem_b)) {
            b.bucle = b.bucle + 1;
            let i_b = nombre_de_bucle(b.bucle);
            emitir(b, $"for (size_t {i_b} = 0; {i_b} < {nombre}.n; {i_b}++)");
            emitir(b, "{");
            b.sangria = b.sangria + 1;
            let dentro_b = $"{nombre}.e[{i_b}]";
            liberacion(b, tipos, vista(dentro_b), vista(elem_b));
            b.sangria = b.sangria - 1;
            emitir(b, "}");
        }
        emitir(b, $"free({nombre}.e);");
        emitir(b, $"{nombre}.e = NULL;");
        emitir(b, $"{nombre}.n = 0;");
        return;
    }

    if T.es_lista(tipo) {
        let elem = T.elemento(tipo);
        if I.posee_con_formas(tipos, vista(elem)) {
            b.bucle = b.bucle + 1;
            let i = nombre_de_bucle(b.bucle);
            var f = nuevo("for (size_t ");
            empujar(f, vista(i));
            empujar(f, " = 0; ");
            empujar(f, vista(i));
            empujar(f, " < ");
            empujar(f, nombre);
            empujar(f, ".length; ");
            empujar(f, vista(i));
            empujar(f, "++)");
            emitir(b, vista(f));
            emitir(b, "{");
            b.sangria = b.sangria + 1;
            var dentro = nuevo(nombre);
            empujar(dentro, ".e[");
            empujar(dentro, vista(i));
            empujar(dentro, "]");
            liberacion(b, tipos, vista(dentro), vista(elem));
            b.sangria = b.sangria - 1;
            emitir(b, "}");
        }
        var l = nuevo("free(");
        empujar(l, nombre);
        empujar(l, ".e);");
        emitir(b, vista(l));
        var a = nuevo(nombre);
        empujar(a, ".e = NULL;");
        emitir(b, vista(a));
        var c = nuevo(nombre);
        empujar(c, ".length = 0;");
        emitir(b, vista(c));
        var d = nuevo(nombre);
        empujar(d, ".capacity = 0;");
        emitir(b, vista(d));
        return;
    }

    // Un struct que posee lleva su liberador generado, que suelta sus campos
    // en orden. El nombre no lleva el alias del modulo: en C no queda.
    if I.posee_con_formas(tipos, tipo) {
        var corto = I.sin_modulo(tipo);
        if I.es_aplicacion(tipo) { corto = I.nombre_resuelto(tipo); }
        var l = nuevo("ss_drop_");
        empujar(l, vista(corto));
        empujar(l, "(&");
        empujar(l, nombre);
        empujar(l, ");");
        emitir(b, vista(l));
    }
}

fn antes_de_dos_puntos(t: view) -> str {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 58 { return nuevo(rebanar(t, 0, i)); }
        i = i + 1;
    }
    return nuevo(t);
}

fn despues_de_dos_puntos(t: view) -> str {
    var i = 0;
    while i + 1 < largo(t) {
        if byte(t, i) == 58 {
            return nuevo(rebanar(t, i + 2, largo(t)));
        }
        i = i + 1;
    }
    return vacio();
}

// Una sentencia. Devuelve false si esta capa no la sabe hacer: entonces la
// funcion entera se descarta, porque media funcion generada no vale nada.
// Lo que esta sentencia entrego, apagado aqui mismo: el camino se acaba.
fn apagar_las_de(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) {
    var salen: lista<str> = [];
    movidas_en(s.punteros, n, tipos, salen);
    var vivas: lista<str> = [];
    for nm en salen {
        if lleva_bandera(b, s, vista(nm)) { anadir(vivas, copiar(nm)); }
    }
    apagar(b, vivas);
}

fn primer_nombre(t: view) -> str {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 44 { return nuevo(recortar(rebanar(t, 0, i))); }
        i = i + 1;
    }
    return nuevo(recortar(t));
}

fn segundo_nombre(t: view) -> str {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 44 {
            return nuevo(recortar(rebanar(t, i + 1, largo(t))));
        }
        i = i + 1;
    }
    return vacio();
}

// `for k, v en m` lleva dos nombres separados por coma.
fn lleva_coma(t: view) -> bool {
    var i = 0;
    while i < largo(t) {
        if byte(t, i) == 44 { return true; }
        i = i + 1;
    }
    return false;
}

fn mueve_algo(s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> bool {
    var salen: lista<str> = [];
    movidas_en(s.punteros, n, tipos, salen);
    movidas_por_caminos(s.punteros, n, tipos, salen);
    return largo(salen) > 0;
}

// Cada sentencia tiene sus propios temporales, y al acabar se sueltan. Los
// de fuera se guardan y se devuelven: una sentencia puede llevar otras
// dentro, y las de dentro no heredan lo que quedo a medias fuera.
fn sentencia_c(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo,
    tipos: mut I.Contexto, retorno: view, falible: bool) -> bool {
    var antes: lista<str> = [];
    for t en b.temporales { anadir(antes, copiar(t)); }
    var de_fuera: lista<str> = [];
    for t en antes { anadir(de_fuera, copiar(t)); }
    anadir(b.fuera, de_fuera);
    let vacia: lista<str> = [];
    b.temporales = vacia;

    let bien = una_sentencia(b, s, n, tipos, retorno, falible);
    if bien { soltar_temporales(b, tipos); }
    b.temporales = antes;
    quitar_ultima_fuera(b);
    return bien;
}

fn una_sentencia(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo,
    tipos: mut I.Contexto, retorno: view, falible: bool) -> bool {
    let clase = vista(n.clase);
    marcar(b, s, n.linea);

    if igual(clase, "declaracion") {
        if largo(n.hijos) != 1 { return false; }
        let nombre = nombre_declarado(vista(n.texto));
        var tipo = tipo_escrito(vista(n.texto));
        if largo(tipo) == 0 { tipo = I.tipo_de(tipos, n.hijos[0]); }
        if largo(tipo) == 0 { return false; }

        var valor = vacio();
        let cual = vista(n.hijos[0].clase);

        if igual(cual, "try") {
            // `try f(...)`: se guarda el resultado, y si trae motivo se sale
            // por el mismo camino sin tocar lo que ya esta vivo.
            if !falible { return false; }
            valor = try_c(b, s, n.hijos[0], tipos);
        } else if igual(cual, "match") {
            // Sus brazos pueden llevar sentencias: se genera desde aqui,
            // donde el sitio se puede modificar, como en `return`.
            valor = match_valor(b, s, n.hijos[0], tipos, retorno, falible);
        } else {
            valor = expresion_c(b, s, n.hijos[0], vista(tipo), tipos);
        }
        if es_desconocido(vista(valor)) { return false; }
        // La variable se queda con el temporal: deja de soltarse al acabar
        // la sentencia, porque ahora tiene duenio con nombre.
        reclamar(b, vista(valor));

        var l = nuevo("SS_LANG_QUIZA_SIN_USAR ");
        empujar(l, tipo_c(vista(tipo)));
        empujar(l, " ");
        empujar(l, vista(nombre));
        empujar(l, " = ");
        empujar(l, vista(valor));
        empujar(l, ";");
        emitir(b, vista(l));

        I.declarar(tipos, vista(nombre), vista(tipo));
        if I.posee_con_formas(tipos, vista(tipo)) {
            let clave = clave_de(vista(nombre), n.linea);
            anotar_duenio(b, vista(nombre), vista(tipo), vista(clave));
            if tiene(s.pide_bandera, vista(clave)) {
                nace_bandera(b, vista(nombre));
            }
        }
        apagar_las_de(b, s, n, tipos);
        return true;
    }

    if igual(clase, "expresion") {
        if largo(n.hijos) != 1 { return false; }
        if anadir_c(b, s, n.hijos[0], tipos) {
            apagar_las_de(b, s, n, tipos);
            return true;
        }
        if empujar_c(b, s, n.hijos[0], tipos) {
            apagar_las_de(b, s, n, tipos);
            return true;
        }
        // `poner(m, k, v)` devuelve algo que casi nadie mira: como sentencia
        // se escribe la llamada y se tira el valor, como en C.
        if igual(vista(n.hijos[0].clase), "llamada")
        && igual(vista(n.hijos[0].texto), "poner") {
            let hecha = interna_pura(b, s, n.hijos[0], tipos);
            if es_desconocido(vista(hecha)) { return false; }
            var l = copiar(hecha);
            empujar(l, ";");
            emitir(b, vista(l));
            apagar_las_de(b, s, n, tipos);
            return true;
        }
        // Un `match` suelto mira y hace: el `switch` va tal cual, sin
        // temporal donde dejar nada.
        if igual(vista(n.hijos[0].clase), "match") {
            if !match_c(b, s, n.hijos[0], tipos, retorno, falible, "") {
                return false;
            }
            apagar_las_de(b, s, n, tipos);
            return true;
        }
        // Cualquier otra expresion suelta. Descarta su valor, y si ese valor
        // tenia duenio, este es el sitio donde se devuelve: `try espera(...)`
        // como sentencia tira el `str` que devuelve, y nadie mas lo iba a
        // soltar.
        let hecha = expresion_c(b, s, n.hijos[0], "", tipos);
        if es_desconocido(vista(hecha)) { return false; }
        descartar_c(b, tipos, vista(hecha), n.hijos[0]);
        apagar_las_de(b, s, n, tipos);
        return true;
    }

    if igual(clase, "falla") {
        // Salir por el camino malo: se suelta todo y se devuelve el motivo.
        if !falible { return false; }
        liberar_todo(b, s, tipos, "");
        var l = nuevo("return (");
        empujar(l, tipo_resultado(retorno));
        empujar(l, "){ .motivo = ");
        empujar(l, literal_c(vista(n.texto)));
        empujar(l, " };");
        emitir(b, vista(l));
        olvidar_temporales(b);
        return true;
    }

    if igual(clase, "retorno") {
        if largo(n.hijos) == 0 {
            liberar_todo(b, s, tipos, "");
            if falible {
                var l = nuevo("return (");
                empujar(l, tipo_resultado(retorno));
                empujar(l, "){ .motivo = NULL };");
                emitir(b, vista(l));
                olvidar_temporales(b);
                return true;
            }
            emitir(b, "return;");
            olvidar_temporales(b);
            return true;
        }
        // Devolver una variable entera no necesita temporal: no hay nada
        // que calcular, y liberar lo demas no la toca.
        if igual(vista(n.hijos[0].clase), "variable") {
            let quien = vista(n.hijos[0].texto);
            // Si lleva bandera porque se entrega por otro camino, al
            // devolverla tambien se entrega: se apaga antes de salir, o la
            // liberacion la veria encendida.
            if lleva_bandera(b, s, quien) {
                var apaga = nuevo("ss_vivo_");
                empujar(apaga, quien);
                empujar(apaga, " = false;");
                emitir(b, vista(apaga));
            }
            liberar_todo(b, s, tipos, quien);
            let c = expresion_c(b, s, n.hijos[0], retorno, tipos);
            var r = nuevo("return ");
            if falible {
                empujar(r, "(");
                empujar(r, tipo_resultado(retorno));
                empujar(r, "){ .motivo = NULL, .valor = ");
                empujar(r, vista(c));
                empujar(r, " };");
            } else {
                empujar(r, vista(c));
                empujar(r, ";");
            }
            emitir(b, vista(r));
            olvidar_temporales(b);
            return true;
        }

        // Un `match` que da valor puede llevar brazos con sentencias, y eso
        // solo se genera desde aqui, donde el sitio se puede modificar.
        var valor = vacio();
        if igual(vista(n.hijos[0].clase), "match") {
            valor = match_valor(b, s, n.hijos[0], tipos, retorno, falible);
        } else {
            valor = expresion_c(b, s, n.hijos[0], retorno, tipos);
        }
        if es_desconocido(vista(valor)) { return false; }
        // Lo que se devuelve no se suelta: se entrega.
        reclamar(b, vista(valor));
        // El valor se guarda antes de soltar nada: puede leer justo lo que
        // se va a liberar.
        let tmp = nuevo_temporal(b);
        var l = nuevo(tipo_c(retorno));
        empujar(l, " ");
        empujar(l, vista(tmp));
        empujar(l, " = ");
        empujar(l, vista(valor));
        empujar(l, ";");
        emitir(b, vista(l));
        // Antes de liberar, y no despues: lo que se apague detras de un
        // `return` no se ejecuta nunca, y la liberacion veria la bandera
        // encendida todavia.
        apagar_las_de(b, s, n, tipos);
        // Lo que se entrega no se libera.
        var entregada = vacio();
        if igual(vista(n.hijos[0].clase), "variable") {
            entregada = nuevo(vista(n.hijos[0].texto));
        }
        liberar_todo(b, s, tipos, vista(entregada));
        var r = nuevo("return ");
        if falible {
            // En una falible lo que se devuelve va envuelto: `motivo` a
            // NULL dice que fue bien.
            empujar(r, "(");
            empujar(r, tipo_resultado(retorno));
            empujar(r, "){ .motivo = NULL, .valor = ");
            empujar(r, vista(tmp));
            empujar(r, " };");
        } else {
            empujar(r, vista(tmp));
            empujar(r, ";");
        }
        emitir(b, vista(r));
        olvidar_temporales(b);
        return true;
    }

    if igual(clase, "si") {
        if largo(n.hijos) < 2 { return false; }
        if mueve_algo(s, n.hijos[0], tipos) { return false; }
        let cond = expresion_c(b, s, n.hijos[0], "bool", tipos);
        if es_desconocido(vista(cond)) { return false; }
        var l = nuevo("if (");
        empujar(l, vista(cond));
        empujar(l, ")");
        emitir(b, vista(l));
        if !bloque_c(b, s, n.hijos[1], tipos, retorno, falible) {
            return false;
        }
        if largo(n.hijos) > 2 {
            emitir(b, "else");
            if !bloque_c(b, s, n.hijos[2], tipos, retorno, falible) {
                return false;
            }
        }
        return true;
    }

    if igual(clase, "mientras") {
        if largo(n.hijos) != 2 { return false; }
        if mueve_algo(s, n.hijos[0], tipos) { return false; }

        // Casi toda condicion sale entera en una expresion de C y va donde
        // va. Pero alguna necesita lineas propias —`byte` guarda la vista en
        // un temporal antes de indexarla— y esas lineas tienen que correr en
        // CADA vuelta: dejarlas fuera del bucle seria mirar, en la segunda,
        // algo calculado antes de que el cuerpo lo cambiara.
        let marca = largo(b.lineas);
        let temporal_antes = b.temporal;
        let bucle_antes = b.bucle;
        var temporales_antes: lista<str> = [];
        for t en b.temporales { anadir(temporales_antes, copiar(t)); }
        let cond = expresion_c(b, s, n.hijos[0], "bool", tipos);
        if es_desconocido(vista(cond)) { return false; }
        if largo(b.lineas) == marca {
            var l = nuevo("while (");
            empujar(l, vista(cond));
            empujar(l, ")");
            emitir(b, vista(l));
            anadir(b.bucles, largo(b.bloques));
            anadir(b.bucles_t, largo(b.fuera));
            abrir_bucle_saltos(b);
            let salio = bloque_c(b, s, n.hijos[1], tipos, retorno, falible);
            quitar_ultimo_bucle(b);
            cerrar_bucle_saltos(b);
            return salio;
        }

        // Dejo lineas: se deshace y se rehace dentro.
        recortar_lineas(b, marca);
        b.temporal = temporal_antes;
        b.bucle = bucle_antes;
        b.temporales = temporales_antes;
        emitir(b, "while (true)");
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        abrir_bloque(b);
        anadir(b.bucles, largo(b.bloques) - 1);
        anadir(b.bucles_t, largo(b.fuera));
        abrir_bucle_saltos(b);
        I.abrir(tipos);
        let base = largo(b.temporales);
        var dentro = expresion_c(b, s, n.hijos[0], "bool", tipos);
        if es_desconocido(vista(dentro)) { return false; }
        // Si la condicion dejo temporales con duenio, se sueltan en cada
        // vuelta, antes de decidir: dejarlos para el final de la sentencia
        // los liberaria fuera del bucle, donde ya no existen, y se escaparia
        // uno por vuelta.
        if largo(b.temporales) > base {
            let vale = nuevo_temporal(b);
            var cap = nuevo("bool ");
            empujar(cap, vista(vale));
            empujar(cap, " = ");
            empujar(cap, vista(dentro));
            empujar(cap, ";");
            emitir(b, vista(cap));
            var k = base;
            while k < largo(b.temporales) {
                let entrada = copiar(b.temporales[k]);
                let nt = antes_de_dos_puntos(vista(entrada));
                let tt = despues_de_dos_puntos(vista(entrada));
                liberacion(b, tipos, vista(nt), vista(tt));
                k = k + 1;
            }
            var quedan: lista<str> = [];
            var q = 0;
            while q < base {
                anadir(quedan, copiar(b.temporales[q]));
                q = q + 1;
            }
            b.temporales = quedan;
            dentro = copiar(vale);
        }
        var g = nuevo("if (!(");
        empujar(g, vista(dentro));
        empujar(g, "))");
        emitir(b, vista(g));
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        emitir(b, "break;");
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        var bien = true;
        for st en n.hijos[1].hijos {
            if bien {
                bien = sentencia_c(b, s, st, tipos, retorno, falible);
                if !bien { apuntar_fallo(b, st); }
            }
        }
        if bien && !termina_saliendo(n.hijos[1]) { cerrar_bloque(b, s, tipos); }
        else { quitar_ultimo_bloque(b); }
        quitar_ultimo_bucle(b);
        I.cerrar(tipos);
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        cerrar_bucle_saltos(b);
        return bien;
    }

    if igual(clase, "asignacion") {
        if largo(n.hijos) != 2 { return false; }
        let a_que = vista(n.hijos[0].clase);
        if !igual(a_que, "variable") && !igual(a_que, "campo")
        && !igual(a_que, "indice") {
            return false;
        }
        // Solo una variable entera lleva bandera: un campo se apunta por su
        // struct, y eso es otra capa.
        var nombre = vacio();
        if igual(a_que, "variable") { nombre = nuevo(vista(n.hijos[0].texto)); }
        let tipo = I.tipo_de(tipos, n.hijos[0]);
        if largo(tipo) == 0 { return false; }
        // Se fija primero el sitio. Ademas de coincidir con el generador de
        // Python, esto evita que el valor cambie un indice o la coleccion de
        // la izquierda antes de que sepamos donde se escribira.
        let destino = expresion_c(b, s, n.hijos[0], vista(tipo), tipos);
        if es_desconocido(vista(destino)) { return false; }
        var valor = vacio();
        if igual(vista(n.hijos[1].clase), "match") {
            valor = match_valor(b, s, n.hijos[1], tipos, retorno, falible);
        } else {
            valor = expresion_c(b, s, n.hijos[1], vista(tipo), tipos);
        }
        if es_desconocido(vista(valor)) { return false; }
        reclamar(b, vista(valor));

        // Asignar a algo con duenio pide soltar lo viejo. `liberacion` ya sabe
        // soltar cualquier cosa que posea: `str`, listas, mapas y structs.
        if I.posee_con_formas(tipos, vista(tipo)) {
            // El valor se guarda antes de soltar lo viejo, porque en C lo
            // que cuenta no es donde se calculo la expresion sino donde
            // queda escrita: `s = nuevo(rebanar(vista(s), 0, 6))` leeria
            // `s` despues de haberlo soltado.
            let tmp = nuevo_temporal(b);
            var g = nuevo(tipo_c(vista(tipo)));
            empujar(g, " ");
            empujar(g, vista(tmp));
            empujar(g, " = ");
            empujar(g, vista(valor));
            empujar(g, ";");
            emitir(b, vista(g));

            if lleva_bandera(b, s, vista(nombre)) {
                // Si ya se lo llevaron, aqui no hay nada que devolver:
                // soltarlo seria soltarlo dos veces.
                var w = nuevo("if (ss_vivo_");
                empujar(w, vista(nombre));
                empujar(w, ")");
                emitir(b, vista(w));
                emitir(b, "{");
                b.sangria = b.sangria + 1;
                liberacion(b, tipos, vista(destino), vista(tipo));
                b.sangria = b.sangria - 1;
                emitir(b, "}");
                var a = copiar(destino);
                empujar(a, " = ");
                empujar(a, vista(tmp));
                empujar(a, ";");
                emitir(b, vista(a));
                var enciende = nuevo("ss_vivo_");
                empujar(enciende, vista(nombre));
                empujar(enciende, " = true;");
                emitir(b, vista(enciende));
                apagar_las_de(b, s, n, tipos);
                return true;
            }
            liberacion(b, tipos, vista(destino), vista(tipo));
            var a = copiar(destino);
            empujar(a, " = ");
            empujar(a, vista(tmp));
            empujar(a, ";");
            emitir(b, vista(a));
            apagar_las_de(b, s, n, tipos);
            return true;
        }

        var l = copiar(destino);
        empujar(l, " = ");
        empujar(l, vista(valor));
        empujar(l, ";");
        emitir(b, vista(l));
        apagar_las_de(b, s, n, tipos);
        return true;
    }

    if igual(clase, "para") {
        if largo(n.hijos) != 2 { return false; }
        // `for x en ...` o, sobre un mapa, `for clave, valor en m`.
        let uno = primer_nombre(vista(n.texto));
        let dos = segundo_nombre(vista(n.texto));
        // Un sitio con nombre: variable, campo o elemento. `for x en f(...)`
        // no, que se calcula una sola vez y eso pide un temporal que soltar
        // al final.
        let que = vista(n.hijos[0].clase);
        let suyo = I.tipo_de(tipos, n.hijos[0]);
        let sobre = T.apuntado_si(vista(suyo));
        let es_mapa_ = T.es_mapa(vista(sobre));
        let es_arreglo_ = T.es_arreglo(vista(sobre));
        if !T.es_lista(vista(sobre)) && !es_mapa_ && !es_arreglo_ { return false; }
        if largo(dos) > 0 && !es_mapa_ { return false; }
        var lugar = vacio();
        if igual(que, "variable") || igual(que, "campo") || igual(que, "indice") {
            lugar = sitio_c(b, s, n.hijos[0], tipos);
        } else {
            // `for x en f(...)`: la coleccion se calcula UNA vez. Dejar la
            // llamada en la condicion la repetiria en cada vuelta, y cada
            // vuelta filtraria una copia.
            let tmp = nuevo_temporal(b);
            let valor = expresion_c(b, s, n.hijos[0], vista(sobre), tipos);
            if es_desconocido(vista(valor)) { return false; }
            reclamar(b, vista(valor));
            var l = nuevo(tipo_c(vista(sobre)));
            empujar(l, " ");
            empujar(l, vista(tmp));
            empujar(l, " = ");
            empujar(l, vista(valor));
            empujar(l, ";");
            emitir(b, vista(l));
            apuntar_temporal(b, vista(tmp), vista(sobre));
            lugar = copiar(tmp);
        }
        if es_desconocido(vista(lugar)) { return false; }

        b.bucle = b.bucle + 1;
        let i = nombre_de_indice(b.bucle);
        var f = nuevo("for (size_t ");
        empujar(f, vista(i));
        empujar(f, " = 0; ");
        empujar(f, vista(i));
        empujar(f, " < ");
        if es_arreglo_ {
            let cuantos = cuantos_de_arreglo(vista(sobre));
            empujar(f, vista(cuantos));
            empujar(f, "; ");
        } else {
            empujar(f, vista(lugar));
            // Una tabla se recorre por sus celdas, y se saltan las vacias.
            if es_mapa_ { empujar(f, ".capacidad; "); }
            else { empujar(f, ".length; "); }
        }
        empujar(f, vista(i));
        empujar(f, "++)");
        emitir(b, vista(f));
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        if es_mapa_ {
            var salta = nuevo("if (");
            empujar(salta, vista(lugar));
            empujar(salta, ".claves[");
            empujar(salta, vista(i));
            empujar(salta, "].data == NULL) continue;");
            emitir(b, vista(salta));
        }
        abrir_bloque(b);
        anadir(b.bucles, largo(b.bloques) - 1);
        anadir(b.bucles_t, largo(b.fuera));
        abrir_bucle_saltos(b);
        I.abrir(tipos);

        // El elemento se presta, no se copia: un `str` copiado tendria dos
        // duenios. Los escalares van por valor, que no hay nada que duplicar.
        // Sobre un mapa lo que se recorre son las claves, y nadie copia una:
        // se presta la que ya esta en la tabla.
        var elem = T.elemento(vista(sobre));
        if es_mapa_ {
            let partes = T.partir_tipos(T.entre_angulos(vista(sobre)));
            if largo(partes) != 2 { return false; }
            elem = copiar(partes[0]);
        }
        let quien = vista(uno);
        let elem_posee = I.posee_con_formas(tipos, vista(elem));
        var acceso = copiar(lugar);
        if es_mapa_ { empujar(acceso, ".claves["); }
        else { empujar(acceso, ".e["); }
        empujar(acceso, vista(i));
        empujar(acceso, "]");
        var d = nuevo("SS_LANG_QUIZA_SIN_USAR ");
        let presta = elem_posee;
        if presta {
            empujar(d, "const ");
            empujar(d, tipo_c(vista(elem)));
            empujar(d, "* ");
            empujar(d, quien);
            empujar(d, " = &");
        } else {
            empujar(d, tipo_c(vista(elem)));
            empujar(d, " ");
            empujar(d, quien);
            empujar(d, " = ");
        }
        empujar(d, vista(acceso));
        empujar(d, ";");
        emitir(b, vista(d));
        I.declarar(tipos, quien, vista(elem));
        if largo(dos) > 0 {
            // El valor va tal cual: un escalar se copia solo.
            let tv = T.valor_de_mapa(vista(sobre)) sino vacio();
            if largo(tv) == 0 { return false; }
            var dv = nuevo("SS_LANG_QUIZA_SIN_USAR ");
            empujar(dv, tipo_c(vista(tv)));
            empujar(dv, " ");
            empujar(dv, vista(dos));
            empujar(dv, " = ");
            empujar(dv, vista(lugar));
            empujar(dv, ".valores[");
            empujar(dv, vista(i));
            empujar(dv, "];");
            emitir(b, vista(dv));
            I.declarar(tipos, vista(dos), vista(tv));
        }
        let ya_era = tiene(s.punteros, quien);
        if presta { poner(s.punteros, quien, 2); }

        var bien = true;
        for st en n.hijos[1].hijos {
            if bien {
                bien = sentencia_c(b, s, st, tipos, retorno, falible);
                if !bien { apuntar_fallo(b, st); }
            }
        }
        if bien && !termina_saliendo(n.hijos[1]) { cerrar_bloque(b, s, tipos); }
        else { quitar_ultimo_bloque(b); }

        if presta && !ya_era { quitar(s.punteros, quien); }
        quitar_ultimo_bucle(b);
        I.cerrar(tipos);
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        cerrar_bucle_saltos(b);
        // `for c en filtradas(xs, f)` entrega `f` al calcular la coleccion.
        if bien { apagar_las_de(b, s, n, tipos); }
        return bien;
    }

    if igual(clase, "romper") || igual(clase, "continuar") {
        // Los temporales de las sentencias de dentro del bucle —la condicion
        // de un `if` que contiene el `break`— no llegan a su limpieza de fin.
        // Los del propio bucle si: siguen haciendo falta.
        soltar_temporales(b, tipos);
        if largo(b.bucles_t) > 0 {
            soltar_fuera_desde(b, tipos, b.bucles_t[largo(b.bucles_t) - 1] + 1);
        }
        // Lo que nacio dentro del bucle no lo cierra nadie si se sale por
        // aqui: se suelta ahora, de dentro hacia fuera.
        var desde = 0;
        if largo(b.bucles) > 0 { desde = b.bucles[largo(b.bucles) - 1]; }
        var i = largo(b.bloques);
        while i > desde {
            i = i - 1;
            liberar_uno(b, s, tipos, i, "");
        }
        if igual(clase, "romper") && largo(b.switch_en_bucle) > 0
        && b.en_switch > b.switch_en_bucle[largo(b.switch_en_bucle) - 1] {
            // Un `break` de C aqui saldria del `switch` del `match`.
            let k = largo(b.etiquetas_bucle) - 1;
            if largo(b.etiquetas_bucle[k]) == 0 {
                let et = nueva_etiqueta(b, "bucle");
                b.etiquetas_bucle[k] = et;
            }
            let destino = copiar(b.etiquetas_bucle[k]);
            emitir(b, $"goto {destino};");
            return true;
        }
        if igual(clase, "romper") { emitir(b, "break;"); }
        else { emitir(b, "continue;"); }
        return true;
    }

    return false;
}

fn bloque_c(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo, tipos: mut I.Contexto,
    retorno: view, falible: bool) -> bool {
    emitir(b, "{");
    b.sangria = b.sangria + 1;
    abrir_bloque(b);
    I.abrir(tipos);
    var bien = true;
    for h en n.hijos {
        if bien {
            bien = sentencia_c(b, s, h, tipos, retorno, falible);
            if !bien { apuntar_fallo(b, h); }
        }
    }
    if bien && !termina_saliendo(n) { cerrar_bloque(b, s, tipos); }
    else { quitar_ultimo_bloque(b); }
    I.cerrar(tipos);
    b.sangria = b.sangria - 1;
    emitir(b, "}");
    return bien;
}

// Un bloque que acaba en `return` no cierra nada: ya se solto todo alli.
fn termina_saliendo(n: &P.Nodo) -> bool {
    if largo(n.hijos) == 0 { return false; }
    let ultimo = largo(n.hijos) - 1;
    let c = vista(n.hijos[ultimo].clase);
    return igual(c, "retorno") || igual(c, "romper") || igual(c, "continuar");
}

fn nombre_declarado(texto: view) -> str {
    var desde = 0;
    var i = 0;
    while i < largo(texto) {
        if byte(texto, i) == 32 { desde = i + 1; break; }
        i = i + 1;
    }
    var j = desde;
    while j < largo(texto) {
        if byte(texto, j) == 58 { return nuevo(rebanar(texto, desde, j)); }
        j = j + 1;
    }
    return nuevo(rebanar(texto, desde, largo(texto)));
}

fn tipo_escrito(texto: view) -> str {
    var i = 0;
    while i + 1 < largo(texto) {
        if byte(texto, i) == 58 {
            if byte(texto, i + 1) == 32 {
                return nuevo(recortar(rebanar(texto, i + 2, largo(texto))));
            }
        }
        i = i + 1;
    }
    return vacio();
}

// `try f(...)`: deja el resultado en un temporal, sale si trae motivo, y
// devuelve el C que lee el valor.
// Lo que da una llamada que puede fallar cuando sale bien. Una del programa
// lo dice su firma; una interna como `obtener` sale del tipo del mapa.
fn tipo_si_va_bien(n: &P.Nodo, tipos: &I.Contexto) -> str {
    let llamado = vista(n.texto);
    if tiene(tipos.retornos, llamado) {
        // El retorno escrito de una generica puede ser `T`; el tipo de esta
        // llamada ya contiene las ligaduras deducidas de sus argumentos.
        if tiene(tipos.tipo_params, llamado) { return I.tipo_de(tipos, n); }
        return nuevo(obtener(tipos.retornos, llamado) sino "");
    }
    // Escribir sale bien o no, sin valor.
    if igual(llamado, "escribir_archivo") { return nuevo("()"); }
    if igual(llamado, "obtener") || igual(llamado, "obtener_mut")
    || igual(llamado, "leer_archivo")
    || igual(llamado, "leer_linea") || igual(llamado, "entrada_completa")
    || igual(llamado, "variable_entorno") {
        return I.tipo_de(tipos, n);
    }
    return vacio();
}

fn try_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    let retorno = vista(s.retorno);
    if largo(n.hijos) != 1 { return no_se(); }
    if !igual(vista(n.hijos[0].clase), "llamada") { return no_se(); }
    let suyo = tipo_si_va_bien(n.hijos[0], tipos);
    // Vacio puede ser "no la conozco" o "no devuelve nada": solo lo segundo
    // vale, y lo dice que este en las firmas.
    if largo(vista(suyo)) == 0
    && !tiene(tipos.retornos, vista(n.hijos[0].texto)) {
        return no_se();
    }

    // El temporal se reserva antes de generar la llamada, como el original:
    // la llamada puede reservar los suyos, y el orden decide los numeros.
    let tmp = nuevo_temporal(b);
    let c = llamada_c(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(c)) { return no_se(); }

    var l = nuevo(tipo_resultado(vista(suyo)));
    empujar(l, " ");
    empujar(l, vista(tmp));
    empujar(l, " = ");
    empujar(l, vista(c));
    empujar(l, ";");
    emitir(b, vista(l));

    var cond = nuevo("if (");
    empujar(cond, vista(tmp));
    empujar(cond, ".motivo != NULL)");
    emitir(b, vista(cond));
    emitir(b, "{");
    b.sangria = b.sangria + 1;
    liberar_todo(b, s, tipos, "");
    var sale = nuevo("return (");
    empujar(sale, tipo_resultado(retorno));
    empujar(sale, "){ .motivo = ");
    empujar(sale, vista(tmp));
    empujar(sale, ".motivo };");
    emitir(b, vista(sale));
    b.sangria = b.sangria - 1;
    emitir(b, "}");

    // Sin valor no hay nada que leer: el trabajo ya esta emitido.
    if largo(vista(suyo)) == 0 || igual(vista(suyo), "()") { return vacio(); }
    var leer = copiar(tmp);
    empujar(leer, ".valor");
    return leer;
}

// `f(x) sino otra_cosa`: si falla, el valor de al lado. Es la unica forma
// de que un fallo no se propague, y por eso se escribe: en Tcode no hay
// forma callada de ignorar uno.
fn sino_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 2 { return no_se(); }
    if !igual(vista(n.hijos[0].clase), "llamada") { return no_se(); }
    let suyo = tipo_si_va_bien(n.hijos[0], tipos);
    if largo(vista(suyo)) == 0 { return no_se(); }

    // El temporal se reserva antes de generar la llamada, como el original:
    // la llamada puede reservar los suyos, y el orden decide los numeros.
    let tmp = nuevo_temporal(b);
    let c = llamada_c(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(c)) { return no_se(); }

    var l = nuevo(tipo_resultado(vista(suyo)));
    empujar(l, " ");
    empujar(l, vista(tmp));
    empujar(l, " = ");
    empujar(l, vista(c));
    empujar(l, ";");
    emitir(b, vista(l));

    let elegido = nuevo_temporal(b);
    var d = nuevo(tipo_c(vista(suyo)));
    empujar(d, " ");
    empujar(d, vista(elegido));
    empujar(d, ";");
    emitir(b, vista(d));

    var cond = nuevo("if (");
    empujar(cond, vista(tmp));
    empujar(cond, ".motivo != NULL)");
    emitir(b, vista(cond));
    emitir(b, "{");
    b.sangria = b.sangria + 1;
    let alt = expresion_c(b, s, n.hijos[1], vista(suyo), tipos);
    if es_desconocido(vista(alt)) { return no_se(); }
    var pone = copiar(elegido);
    empujar(pone, " = ");
    empujar(pone, vista(alt));
    empujar(pone, ";");
    emitir(b, vista(pone));
    // Lo que entrega la alternativa solo se entrega por esta rama.
    var salen: lista<str> = [];
    movidas_de_alternativa(s.punteros, n.hijos[1], tipos, salen);
    var vivas: lista<str> = [];
    for nm en salen {
        if lleva_bandera(b, s, vista(nm)) { anadir(vivas, copiar(nm)); }
    }
    apagar(b, vivas);
    b.sangria = b.sangria - 1;
    emitir(b, "}");
    emitir(b, "else");
    emitir(b, "{");
    b.sangria = b.sangria + 1;
    var otro = copiar(elegido);
    empujar(otro, " = ");
    empujar(otro, vista(tmp));
    empujar(otro, ".valor;");
    emitir(b, vista(otro));
    b.sangria = b.sangria - 1;
    emitir(b, "}");
    return elegido;
}

// `anadir(xs, v)`: la lista se queda con el valor.
fn anadir_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> bool {
    if !igual(vista(n.clase), "llamada") { return false; }
    if !igual(vista(n.texto), "anadir") { return false; }
    if largo(n.hijos) != 2 { return false; }
    let suya = I.tipo_de(tipos, n.hijos[0]);
    let sobre = T.apuntado_si(vista(suya));
    if !T.es_lista(vista(sobre)) { return false; }
    let elem = T.elemento(vista(sobre));
    // Meter una variable con duenio en una lista la mueve: la lista se la
    // queda y desde aqui la suelta ella.
    if entrega_variable(s, n.hijos[1], tipos) {
        if !lleva_bandera(b, s, vista(n.hijos[1].texto)) { return false; }
    }
    let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(donde)) { return false; }
    let ptr = nuevo_temporal(b);
    let tc = tipo_c(vista(sobre));
    emitir(b, $"{tc}* {ptr} = {donde};");
    let valor = expresion_c(b, s, n.hijos[1], vista(elem), tipos);
    if es_desconocido(vista(valor)) { return false; }
    reclamar(b, vista(valor)); // la lista se lo queda

    var l = nuevo("ss_push_");
    empujar(l, mangle(vista(sobre)));
    empujar(l, "(");
    empujar(l, vista(ptr));
    empujar(l, ", ");
    empujar(l, vista(valor));
    empujar(l, ", \"");
    empujar(l, vista(s.archivo));
    empujar(l, "\", ");
    empujar(l, texto(n.linea));
    empujar(l, ")");
    b.ultima_linea = 0;
    marcar(b, s, n.linea);
    empujar(l, ";");
    emitir(b, vista(l));
    return true;
}

// `if c { a } else { b }` como valor. Se baja a una variable y un `if`, no
// al `?:` de C: cada rama puede necesitar emitir lineas propias, y dentro
// de `?:` no caben.
fn si_expr_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, esperado: view,
    tipos: &I.Contexto) -> str {
    if largo(n.hijos) != 3 { return no_se(); }
    var t = I.tipo_de(tipos, n);
    // Sin lo que anoto el comprobador, dos ramas que son numeros escritos
    // toman el tipo que se espera del `if`, como las habria anotado el.
    if largo(I.tipo_anotado(tipos, n)) == 0 && largo(I.literal_de(n)) > 0
    && es_aritmetico(esperado) {
        t = nuevo(esperado);
    }
    if largo(t) == 0 { t = nuevo("usize"); }
    let tmp = nuevo_temporal(b);
    var d = nuevo(tipo_c(vista(t)));
    empujar(d, " ");
    empujar(d, vista(tmp));
    empujar(d, ";");
    emitir(b, vista(d));
    let cond = expresion_c(b, s, n.hijos[0], "bool", tipos);
    if es_desconocido(vista(cond)) { return no_se(); }
    var l = nuevo("if (");
    empujar(l, vista(cond));
    empujar(l, ")");
    emitir(b, vista(l));
    var k = 1;
    while k < 3 {
        if k == 2 { emitir(b, "else"); }
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        let rama_c = expresion_c(b, s, n.hijos[k], vista(t), tipos);
        if es_desconocido(vista(rama_c)) { return no_se(); }
        var pone = copiar(tmp);
        empujar(pone, " = ");
        empujar(pone, vista(rama_c));
        empujar(pone, ";");
        emitir(b, vista(pone));
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        k = k + 1;
    }
    if I.posee_con_formas(tipos, vista(t)) {
        apuntar_temporal(b, vista(tmp), vista(t));
    }
    return copiar(tmp);
}

// `SS_FIGURA_CIRCULO`: el nombre en C de una forma.
fn etiqueta(enum_: view, variante: view) -> str {
    let a = mayusculas(enum_);
    let v = mayusculas(variante);
    var r = nuevo("SS_");
    empujar(r, vista(a));
    empujar(r, "_");
    empujar(r, vista(v));
    return r;
}

fn mayusculas(t: view) -> str {
    var r = vacio();
    var i = 0;
    while i < largo(t) {
        let c = byte(t, i);
        if c >= 97 && c <= 122 { empujar_byte(r, (c - 32) como ? u8); }
        else { empujar(r, rebanar(t, i, i + 1)); }
        i = i + 1;
    }
    return r;
}

// `p.a.b`, si es una cadena de campos desde una variable; vacio si no.
fn ruta_de_campo_c(n: &P.Nodo) -> str {
    var nombres: lista<str> = [];
    var x = copiar(n);
    while igual(vista(x.clase), "campo") && largo(x.hijos) > 0 {
        anadir(nombres, copiar(x.texto));
        let dentro = copiar(x.hijos[0]);
        x = dentro;
    }
    if !igual(vista(x.clase), "variable") || largo(nombres) == 0 { return vacio(); }
    var r = copiar(x.texto);
    var k = largo(nombres);
    while k > 0 {
        k = k - 1;
        empujar(r, ".");
        empujar(r, vista(nombres[k]));
    }
    return r;
}

// El `switch` de un `match` suelto. Cada brazo es un bloque propio: lo que
// nazca dentro se suelta al salir. Lo que atrapa el patron se presta
// siempre —un `match` mira, no desmonta—, asi que un `str` se ve como
// `view` y lo demas con duenio como un puntero.
// `destino` es la variable de C donde dejar el valor si el `match` da uno,
// o vacio si es suelto.
// Un `match` con guardas, literales o formas anidadas no cabe en un
// `switch`: un brazo que no casa deja paso al siguiente. Ese va como una
// fila de `if`, y el brazo que casa salta al final.
fn match_c(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo, tipos: mut I.Contexto,
    retorno: view, falible: bool, destino: view) -> bool {
    if largo(n.hijos) < 2 { return false; }
    let crudo = I.tipo_de(tipos, n.hijos[0]);
    let apuntado = T.apuntado_si(vista(crudo));
    let base = I.sin_modulo(vista(apuntado));
    if !tiene(tipos.variantes, vista(base)) { return false; }
    let sitio = sitio_c(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(sitio)) { return false; }
    var k = 1;
    while k < largo(n.hijos) {
        if !igual(vista(n.hijos[k].clase), "brazo") { return false; }
        k = k + 1;
    }
    if match_condicionado(n) {
        return match_condiciones(b, s, n, tipos, retorno, falible, destino, vista(base),
            vista(sitio));
    }

    emitir(b, $"switch ({sitio}.etiqueta)");
    emitir(b, "{");
    b.en_switch = b.en_switch + 1;
    var todos = true;
    k = 1;
    while k < largo(n.hijos) {
        let brazo = copiar(n.hijos[k]);
        let variante = I.tras_el_punto(vista(brazo.texto));
        if largo(vista(brazo.texto)) == 0 {
            todos = false;
            emitir(b, "default:");
        } else {
            let et = etiqueta(vista(base), vista(variante));
            emitir(b, $"case {et}:");
        }
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        abrir_bloque(b);
        I.abrir(tipos);
        if largo(vista(brazo.texto)) > 0 {
            if !atrapar_c(b, tipos, vista(base), vista(variante), posiciones_patron_c(brazo),
                vista(sitio)) {
                return false;
            }
        }
        if !cuerpo_brazo_c(b, s, brazo, tipos, retorno, falible, destino) { return false; }
        emitir(b, "break;");
        I.cerrar(tipos);
        b.sangria = b.sangria - 1;
        emitir(b, "}");
        k = k + 1;
    }
    b.en_switch = b.en_switch - 1;
    // Un `match` es exhaustivo, asi que este `default` no se alcanza nunca.
    // Esta para que el compilador de C no tenga que adivinarlo.
    if todos { emitir(b, "default: break;"); }
    emitir(b, "}");
    return true;
}

// Si algun brazo tiene guarda, o algo que no sea un nombre en una posicion.
fn match_condicionado(n: &P.Nodo) -> bool {
    var k = 1;
    while k < largo(n.hijos) {
        for h en n.hijos[k].hijos {
            let hc = vista(h.clase);
            if igual(hc, "guarda") || igual(hc, "patron") || igual(hc, "literal") {
                return true;
            }
        }
        k = k + 1;
    }
    return false;
}

// Un `if` por brazo, en orden: la forma, lo que pidan sus posiciones y,
// dentro, la guarda. El que casa hace lo suyo y salta al final.
fn match_condiciones(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo, tipos: mut I.Contexto,
    retorno: view, falible: bool, destino: view, base: view, sitio: view) -> bool {
    let fin = nueva_etiqueta(b, "match");
    var k = 1;
    while k < largo(n.hijos) {
        let brazo = copiar(n.hijos[k]);
        k = k + 1;
        let variante = I.tras_el_punto(vista(brazo.texto));
        let con_forma = largo(vista(brazo.texto)) > 0;
        var conds: lista<str> = [];
        if con_forma {
            let et = etiqueta(base, vista(variante));
            anadir(conds, $"{sitio}.etiqueta == {et}");
            if !condiciones_patron_c(b, s, tipos, base, vista(variante), posiciones_patron_c(brazo),
                sitio, conds) {
                return false;
            }
        }
        if largo(conds) > 0 {
            var todas = vacio();
            var i = 0;
            while i < largo(conds) {
                if i > 0 { empujar(todas, " && "); }
                empujar(todas, vista(conds[i]));
                i = i + 1;
            }
            emitir(b, $"if ({todas})");
        }
        emitir(b, "{");
        b.sangria = b.sangria + 1;
        abrir_bloque(b);
        I.abrir(tipos);
        if con_forma {
            if !atrapar_c(b, tipos, base, vista(variante), posiciones_patron_c(brazo), sitio) {
                return false;
            }
        }
        var guarda: i64 = -1;
        var h_i = 0;
        for h en brazo.hijos {
            if igual(vista(h.clase), "guarda") { guarda = h_i como i64; }
            h_i = h_i + 1;
        }
        if guarda < 0 {
            if !cuerpo_brazo_c(b, s, brazo, tipos, retorno, falible, destino) { return false; }
            emitir(b, $"goto {fin};");
        } else {
            // La guarda, con sus temporales soltados en el acto: el brazo
            // puede no casar, y entonces no llega a su final.
            let g = copiar(brazo.hijos[guarda como usize]);
            var antes: lista<str> = [];
            for x en b.temporales { anadir(antes, copiar(x)); }
            olvidar_temporales(b);
            let cond = expresion_c(b, s, g.hijos[0], "bool", tipos);
            if es_desconocido(vista(cond)) { return false; }
            let vale = nuevo_temporal(b);
            emitir(b, $"bool {vale} = {cond};");
            soltar_temporales(b, tipos);
            b.temporales = antes;
            emitir(b, $"if ({vale})");
            emitir(b, "{");
            b.sangria = b.sangria + 1;
            abrir_bloque(b);
            I.abrir(tipos);
            if !cuerpo_brazo_c(b, s, brazo, tipos, retorno, falible, destino) { return false; }
            emitir(b, $"goto {fin};");
            I.cerrar(tipos);
            b.sangria = b.sangria - 1;
            emitir(b, "}");
            quitar_ultimo_bloque(b);
        }
        I.cerrar(tipos);
        b.sangria = b.sangria - 1;
        emitir(b, "}");
    }
    emitir(b, $"{fin}: ;");
    return true;
}

// Lo que tiene que cumplir lo de dentro para que el patron case: la forma
// de lo anidado y el valor de cada literal.
fn condiciones_patron_c(b: mut Cuerpo, s: mut Sitio, tipos: mut I.Contexto, base: view,
    variante: view, posiciones: &lista<P.Nodo>, sitio: view, conds: mut lista<str>) -> bool {
    let lleva = I.lista_de(tipos.formas, $"{base}.{variante}") sino [];
    var i = 0;
    while i < largo(posiciones) {
        if i >= largo(lleva) { return false; }
        let t = copiar(lleva[i]);
        let p = copiar(posiciones[i]);
        let dentro = $"{sitio}.dato.v_{variante}._{i}";
        i = i + 1;
        if igual(vista(p.clase), "patron") {
            let otro = I.sin_modulo(vista(t));
            let cual = I.tras_el_punto(vista(p.texto));
            let et = etiqueta(vista(otro), vista(cual));
            anadir(conds, $"{dentro}.etiqueta == {et}");
            if !condiciones_patron_c(b, s, tipos, vista(otro), vista(cual), posiciones_patron_c(p),
                vista(dentro), conds) {
                return false;
            }
        } else if igual(vista(p.clase), "literal") {
            if igual(vista(t), "str") {
                let lit = expresion_c(b, s, p.hijos[0], "view", tipos);
                if es_desconocido(vista(lit)) { return false; }
                anadir(conds, $"sv_equals(ss_view(&{dentro}), {lit})");
            } else {
                let lit = expresion_c(b, s, p.hijos[0], vista(t), tipos);
                if es_desconocido(vista(lit)) { return false; }
                anadir(conds, $"{dentro} == {lit}");
            }
        }
    }
    return true;
}

// Lo que atrapa el patron, prestado: un `str` como `view`, lo demas con
// duenio como puntero, y los escalares por valor.
fn atrapar_c(b: mut Cuerpo, tipos: mut I.Contexto, base: view, variante: view,
    posiciones: &lista<P.Nodo>, sitio: view) -> bool {
    let lleva = I.lista_de(tipos.formas, $"{base}.{variante}") sino [];
    var i = 0;
    while i < largo(posiciones) {
        if i >= largo(lleva) { return false; }
        let t = copiar(lleva[i]);
        let h = copiar(posiciones[i]);
        let dentro = $"{sitio}.dato.v_{variante}._{i}";
        i = i + 1;
        if igual(vista(h.clase), "patron") {
            let otro = I.sin_modulo(vista(t));
            let cual = I.tras_el_punto(vista(h.texto));
            if !atrapar_c(b, tipos, vista(otro), vista(cual), posiciones_patron_c(h), vista(dentro)) {
                return false;
            }
            continue;
        }
        if !igual(vista(h.clase), "atrapa") || igual(vista(h.texto), "_") { continue; }
        if igual(vista(t), "str") {
            emitir(b, $"SS_LANG_QUIZA_SIN_USAR SafeView {h.texto} = ss_view(&{dentro});");
            I.declarar(tipos, vista(h.texto), "view");
        } else if I.posee_con_formas(tipos, vista(t)) {
            let tc = tipo_c(vista(t));
            emitir(b, $"SS_LANG_QUIZA_SIN_USAR const {tc}* {h.texto} = &{dentro};");
            I.declarar(tipos, vista(h.texto), $"&{t}");
        } else {
            let tc = tipo_c(vista(t));
            emitir(b, $"SS_LANG_QUIZA_SIN_USAR {tc} {h.texto} = {dentro};");
            I.declarar(tipos, vista(h.texto), vista(t));
        }
    }
    return true;
}

// Lo que hace el brazo: dejar su valor en `destino`, o sus sentencias. Y
// soltar lo que haya nacido dentro.
// Una expresion cuyo valor no se guarda: se hace, y lo que da se tira. Si
// ese valor tenia duenio, este es el sitio donde se devuelve: `try
// espera(...)` como sentencia tira el `str` que devuelve, y nadie mas lo iba
// a soltar.
fn descartar_c(b: mut Cuerpo, tipos: &I.Contexto, hecha: view, n: &P.Nodo) {
    let x = vista(n.clase);
    let t = tipo_suelto(n, tipos);
    if largo(hecha) > 0 && largo(vista(t)) > 0 && !igual(vista(t), "()")
    && I.posee_con_formas(tipos, vista(t)) {
        reclamar(b, hecha);
        var suelto = nuevo(hecha);
        // `liberacion` toma la direccion de lo que suelta, y el resultado de
        // una llamada no tiene direccion: `f();` a secas daria
        // `ss_free(&f())`, que ni siquiera es C. Se guarda antes.
        if !es_identificador(hecha) {
            let tmp = nuevo_temporal(b);
            var g = nuevo(tipo_c(vista(t)));
            empujar(g, " ");
            empujar(g, vista(tmp));
            empujar(g, " = ");
            empujar(g, hecha);
            empujar(g, ";");
            emitir(b, vista(g));
            suelto = copiar(tmp);
        }
        liberacion(b, tipos, vista(suelto), vista(t));
        return;
    }
    // `try f();` y `f() sino x;` ya emitieron todo su trabajo: lo que
    // devuelven es el valor, y como sentencia no haria nada. Lo que no es una
    // llamada, como el `0` de un brazo, se tira con `(void)`, que es como C
    // dice que es a proposito.
    if largo(hecha) > 0 && !igual(x, "try") && !igual(x, "sino") {
        if igual(x, "llamada") {
            var l = nuevo(hecha);
            empujar(l, ";");
            emitir(b, vista(l));
        } else {
            emitir(b, $"(void) ({hecha});");
        }
    }
}

fn cuerpo_brazo_c(b: mut Cuerpo, s: mut Sitio, brazo: &P.Nodo, tipos: mut I.Contexto,
    retorno: view, falible: bool, destino: view) -> bool {
    for h en brazo.hijos {
        let que = vista(h.clase);
        if igual(que, "bloque") {
            var bien = true;
            for st en h.hijos {
                if bien {
                    bien = sentencia_c(b, s, st, tipos, retorno, falible);
                    if !bien { apuntar_fallo(b, st); }
                }
            }
            if !bien { return false; }
            if termina_saliendo(h) { quitar_ultimo_bloque(b); }
            else { cerrar_bloque(b, s, tipos); }
        }
        // Un brazo que da un valor: se deja en el destino. Sus temporales
        // son suyos y se sueltan aqui, antes de salir del brazo, igual que
        // los de una sentencia.
        if igual(que, "retorno") {
            if largo(h.hijos) != 1 { return false; }
            marcar(b, s, h.linea);
            var antes: lista<str> = [];
            for x en b.temporales { anadir(antes, copiar(x)); }
            olvidar_temporales(b);
            let tv = I.tipo_de(tipos, h.hijos[0]);
            let valor = expresion_c(b, s, h.hijos[0], vista(tv), tipos);
            if es_desconocido(vista(valor)) { return false; }
            if largo(destino) > 0 {
                reclamar(b, vista(valor));
                emitir(b, $"{destino} = {valor};");
            } else {
                // Un `match` suelto: el brazo hace, y lo que da se tira.
                descartar_c(b, tipos, vista(valor), h.hijos[0]);
            }
            soltar_temporales(b, tipos);
            b.temporales = antes;
            cerrar_bloque(b, s, tipos);
        }
    }
    return true;
}

// Lo que va en cada posicion de un patron, en orden.
fn posiciones_patron_c(b: &P.Nodo) -> lista<P.Nodo> {
    var salida: lista<P.Nodo> = [];
    for h en b.hijos {
        let hc = vista(h.clase);
        if igual(hc, "atrapa") || igual(hc, "patron") || igual(hc, "literal") {
            anadir(salida, copiar(h));
        }
    }
    return salida;
}

// El `match` usado como valor: un temporal a ceros y el `switch` encima. A
// ceros porque en Tcode todo valor a ceros es valido, asi que el compilador
// de C no tiene de que quejarse aunque no sepa que el `switch` lo cubre todo.
fn match_valor(b: mut Cuerpo, s: mut Sitio, n: &P.Nodo, tipos: mut I.Contexto,
    retorno: view, falible: bool) -> str {
    var t = I.tipo_de(tipos, n);
    if largo(t) == 0 { t = nuevo("usize"); }
    let tmp = nuevo_temporal(b);
    var d = nuevo(tipo_c(vista(t)));
    empujar(d, " ");
    empujar(d, vista(tmp));
    empujar(d, " = {0};");
    emitir(b, vista(d));
    if I.posee_con_formas(tipos, vista(t)) {
        apuntar_temporal(b, vista(tmp), vista(t));
    }
    if !match_c(b, s, n, tipos, retorno, falible, vista(tmp)) { return no_se(); }
    return copiar(tmp);
}

// Un tipo hecho nombre de C: cada racha de lo que no sea letra o cifra pasa
// a ser un `_`, y sin `_` en los bordes. `lista<str>` da `lista_str`.
fn sanear(t: view) -> str {
    var r = vacio();
    var pendiente = false;
    var i = 0;
    while i < largo(t) {
        let c = byte(t, i);
        let bueno = (c >= 97 && c <= 122) || (c >= 65 && c <= 90)
        || (c >= 48 && c <= 57);
        if bueno {
            if pendiente && largo(r) > 0 { empujar(r, "_"); }
            pendiente = false;
            empujar(r, rebanar(t, i, i + 1));
        } else {
            pendiente = true;
        }
        i = i + 1;
    }
    return r;
}

// De que tipo es lo que da una expresion suelta. Una llamada del programa
// lo dice su firma; un `try` o un `sino`, lo que da cuando va bien.
fn tipo_suelto(n: &P.Nodo, tipos: &I.Contexto) -> str {
    let clase = vista(n.clase);
    if (igual(clase, "try") || igual(clase, "sino")) && largo(n.hijos) > 0 {
        return tipo_si_va_bien(n.hijos[0], tipos);
    }
    if igual(clase, "llamada") && tiene(tipos.retornos, vista(n.texto)) {
        return nuevo(obtener(tipos.retornos, vista(n.texto)) sino "");
    }
    return I.tipo_de(tipos, n);
}

fn es_identificador(v: view) -> bool {
    if largo(v) == 0 { return false; }
    var i = 0;
    while i < largo(v) {
        let c = byte(v, i);
        let letra = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95;
        let cifra = c >= 48 && c <= 57;
        if !letra && !(cifra && i > 0) { return false; }
        i = i + 1;
    }
    return true;
}

// `empujar(s, v)`: pegar texto al final de un `str`. No mueve nada, porque
// lo que se pega se copia: la vista de origen sigue siendo de quien era.
fn empujar_c(b: mut Cuerpo, s: &Sitio, n: &P.Nodo, tipos: &I.Contexto) -> bool {
    if !igual(vista(n.clase), "llamada") { return false; }
    if !igual(vista(n.texto), "empujar") { return false; }
    if largo(n.hijos) != 2 { return false; }
    let donde = direccion_del_sitio(b, s, n.hijos[0], tipos);
    if es_desconocido(vista(donde)) { return false; }
    let ptr = nuevo_temporal(b);
    emitir(b, $"SafeString* {ptr} = {donde};");
    let que = como_vista(b, s, n.hijos[1], tipos);
    if es_desconocido(vista(que)) { return false; }
    var l = nuevo("ss_append_view(");
    empujar(l, vista(ptr));
    empujar(l, ", ");
    empujar(l, vista(que));
    empujar(l, ");");
    b.ultima_linea = 0;
    marcar(b, s, n.linea);
    emitir(b, vista(l));
    return true;
}

// Lo que cierra una funcion falible que llega al final sin fallar.
fn emitir_final_bien(b: mut Cuerpo, retorno: view) {
    var l = nuevo("return (");
    empujar(l, tipo_resultado(retorno));
    empujar(l, "){ .motivo = NULL };");
    emitir(b, vista(l));
}
