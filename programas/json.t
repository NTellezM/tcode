// json.t — valida y reformatea JSON de la entrada.
//
//     ./json < archivo.json      lo reformatea con dos espacios de sangria
//     ./json -c < archivo.json   compacto, en una linea
//
// Un JSON mal escrito falla con su linea. Es un ejercicio de texto intensivo,
// mapas y una generica recursiva: un `Valor` que se contiene a si mismo por
// una lista o un mapa, que es justo lo que las pruebas apenas tocan.

usar "std/caracter" como c;
usar "std/mapa" como m;

enum Valor {
    Nada,
    Cierto,
    Falso,
    Numero(str),
    Texto(str),
    Lista(lista<Valor>),
    Objeto(mapa<str, Valor>),
}

struct Lector {
    texto: str,
    pos: usize,
    linea: usize,
}

// El byte siguiente, o 0 si se acabo el texto.
fn mirar(l: &Lector) -> usize {
    if l.pos >= largo(l.texto) { return 0; }
    return byte(l.texto, l.pos);
}

fn tomar(l: mut Lector) -> usize {
    let b = mirar(l);
    if b == 10 { l.linea = l.linea + 1; }
    l.pos = l.pos + 1;
    return b;
}

fn espacios(l: mut Lector) {
    while c.es_blanco(mirar(l)) { let _b = tomar(l); }
}

// Lo que sale de `\x`, o 255 si el escape no vale.
fn escapado(codigo: usize) -> usize {
    if codigo == 34 { return 34; }  // "
    if codigo == 92 { return 92; }  // backslash
    if codigo == 47 { return 47; }  // /
    if codigo == 98 { return 8; }   // b
    if codigo == 102 { return 12; } // f
    if codigo == 110 { return 10; } // n
    if codigo == 114 { return 13; } // r
    if codigo == 116 { return 9; }  // t
    return 255;
}

fn digito_hex(b: usize) -> usize {
    if b >= 48 && b <= 57 { return b - 48; }
    if b >= 97 && b <= 102 { return b - 97 + 10; }
    if b >= 65 && b <= 70 { return b - 65 + 10; }
    return 255;
}

// Un `\uXXXX` a sus bytes UTF-8, en `salida`.
fn escapar_unicode(l: mut Lector, salida: mut str) ! {
    var valor = 0;
    var i = 0;
    while i < 4 {
        let d = digito_hex(tomar(l));
        if d == 255 { falla "un escape \\u sin cuatro digitos hex"; }
        valor = valor * 16 + d;
        i = i + 1;
    }
    if valor <= 127 {
        empujar_byte(salida, valor como u8);
    } else if valor <= 2047 {
        empujar_byte(salida, (192 + valor / 64) como u8);
        empujar_byte(salida, (128 + valor % 64) como u8);
    } else {
        empujar_byte(salida, (224 + valor / 4096) como u8);
        empujar_byte(salida, (128 + (valor / 64) % 64) como u8);
        empujar_byte(salida, (128 + valor % 64) como u8);
    }
}

// Una cadena JSON, con sus escapes, ya decodificados a bytes reales.
fn cadena(l: mut Lector) -> str ! {
    var salida = vacio();
    let _abre = tomar(l); // la comilla
    while true {
        let b = mirar(l);
        if b == 0 { falla "una cadena sin cerrar"; }
        if b == 34 { let _cierra = tomar(l); return salida; }
        if b == 92 {
            let _barra = tomar(l);
            let codigo = tomar(l);
            if codigo == 117 {
                try escapar_unicode(l, salida);
                continue;
            }
            let decodificado = escapado(codigo);
            if decodificado == 255 { falla "un escape desconocido"; }
            empujar_byte(salida, decodificado como u8);
            continue;
        }
        if b < 32 { falla "un byte de control suelto en la cadena"; }
        empujar_byte(salida, b como u8);
        let _b = tomar(l);
    }
    falla "una cadena sin cerrar";
}

// Un numero: se valida la forma y se guarda el texto tal cual.
fn numero(l: mut Lector) -> str ! {
    let desde = l.pos;
    if mirar(l) == 45 { let _menos = tomar(l); }
    if mirar(l) == 48 {
        let _cero = tomar(l);
    } else {
        if !c.es_digito(mirar(l)) { falla "un numero sin digitos"; }
        while c.es_digito(mirar(l)) { let _d = tomar(l); }
    }
    if mirar(l) == 46 {
        let _punto = tomar(l);
        if !c.es_digito(mirar(l)) { falla "un punto sin decimales"; }
        while c.es_digito(mirar(l)) { let _d = tomar(l); }
    }
    if mirar(l) == 101 || mirar(l) == 69 {
        let _e = tomar(l);
        if mirar(l) == 43 || mirar(l) == 45 { let _signo = tomar(l); }
        if !c.es_digito(mirar(l)) { falla "un exponente sin digitos"; }
        while c.es_digito(mirar(l)) { let _d = tomar(l); }
    }
    return nuevo(rebanar(l.texto, desde, l.pos));
}

fn valor(l: mut Lector) -> Valor ! {
    espacios(l);
    let b = mirar(l);
    if b == 123 { return try objeto(l); }
    if b == 91 { return try arreglo(l); }
    if b == 34 { return Valor.Texto(try cadena(l)); }
    if b == 110 { return try literal(l, "null", Valor.Nada); }
    if b == 116 { return try literal(l, "true", Valor.Cierto); }
    if b == 102 { return try literal(l, "false", Valor.Falso); }
    if c.es_digito(b) || b == 45 {
        return Valor.Numero(try numero(l));
    }
    falla "aqui se esperaba un valor";
}

fn literal(l: mut Lector, palabra: view, v: Valor) -> Valor ! {
    var i = 0;
    while i < largo(palabra) {
        if tomar(l) != byte(palabra, i) { falla "un literal mal escrito"; }
        i = i + 1;
    }
    return v;
}

fn objeto(l: mut Lector) -> Valor ! {
    let _abre = tomar(l); // {
    var dentro: mapa<str, Valor> = [];
    espacios(l);
    if mirar(l) == 125 { let _cierra = tomar(l); return Valor.Objeto(dentro); }
    while true {
        espacios(l);
        if mirar(l) != 34 { falla "la clave de un objeto es una cadena"; }
        let clave = try cadena(l);
        espacios(l);
        if tomar(l) != 58 { falla "faltan los dos puntos"; }
        let v = try valor(l);
        poner(dentro, clave, v);
        espacios(l);
        let b = tomar(l);
        if b == 125 { return Valor.Objeto(dentro); }
        if b != 44 { falla "faltaba una coma o el cierre del objeto"; }
    }
    falla "un objeto sin cerrar";
}

fn arreglo(l: mut Lector) -> Valor ! {
    let _abre = tomar(l); // [
    var dentro: lista<Valor> = [];
    espacios(l);
    if mirar(l) == 93 { let _cierra = tomar(l); return Valor.Lista(dentro); }
    while true {
        let v = try valor(l);
        dentro.anadir(v);
        espacios(l);
        let b = tomar(l);
        if b == 93 { return Valor.Lista(dentro); }
        if b != 44 { falla "faltaba una coma o el cierre de la lista"; }
    }
    falla "una lista sin cerrar";
}

// ---------- escribir ----------

fn comillas(l: view, salida: mut str) {
    salida.empujar("\"");
    var i = 0;
    while i < largo(l) {
        let b = byte(l, i);
        if b == 34 { salida.empujar("\\\""); }
        else if b == 92 { salida.empujar("\\\\"); }
        else if b == 10 { salida.empujar("\\n"); }
        else if b == 9 { salida.empujar("\\t"); }
        else if b == 13 { salida.empujar("\\r"); }
        else if b < 32 { salida.empujar($"\\u00{b}"); }
        else { empujar_byte(salida, b como u8); }
        i = i + 1;
    }
    salida.empujar("\"");
}

fn sangrar(salida: mut str, hondo: usize, compacto: bool) {
    if compacto { return; }
    salida.empujar("\n");
    var i = 0;
    while i < hondo {
        salida.empujar("  ");
        i = i + 1;
    }
}

fn escribir(v: &Valor, salida: mut str, hondo: usize, compacto: bool) ! {
    match v {
        Valor.Nada -> { salida.empujar("null"); }
        Valor.Cierto -> { salida.empujar("true"); }
        Valor.Falso -> { salida.empujar("false"); }
        Valor.Numero(t) -> { salida.empujar(t); }
        Valor.Texto(t) -> { comillas(t, salida); }
        Valor.Lista(xs) -> {
            salida.empujar("[");
            var primero = true;
            for x en xs {
                if !primero { salida.empujar(","); }
                sangrar(salida, hondo + 1, compacto);
                try escribir(x, salida, hondo + 1, compacto);
                primero = false;
            }
            sangrar(salida, hondo, compacto);
            salida.empujar("]");
        }
        Valor.Objeto(dentro) -> {
            salida.empujar("{");
            var primero = true;
            for k, x en dentro {
                if !primero { salida.empujar(","); }
                sangrar(salida, hondo + 1, compacto);
                comillas(k, salida);
                if compacto { salida.empujar(":"); } else { salida.empujar(": "); }
                try escribir(x, salida, hondo + 1, compacto);
                primero = false;
            }
            sangrar(salida, hondo, compacto);
            salida.empujar("}");
        }
    }
}

fn main() -> usize ! {
    let todo = try entrada_completa();
    var l = Lector { texto: todo, pos: 0, linea: 1 };
    let compacto = n_argumentos() > 1 && argumento(1) == "-c";

    let raiz = try valor(l);
    espacios(l);
    if mirar(l) != 0 {
        imprimir_error($"json: linea {l.linea}: sobra texto despues del valor\n");
        return 1;
    }

    var salida = vacio();
    try escribir(raiz, salida, 0, compacto);
    imprimir(salida);
    imprimir("\n");
    return 0;
}
