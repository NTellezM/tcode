// std/json.t — leer y escribir JSON.
//
//   let v = json.leer(texto) sino { ... }      // parsea a un `Valor`
//   let s = json.escribir(v);                   // compacto, en una linea
//   let p = json.escribir_con_sangria(v);       // con dos espacios
//
// `Valor` es un arbol que se contiene a si mismo por una lista o un mapa, asi
// que un JSON vale lo que quepa: nada, un numero, una cadena, una lista, o un
// objeto de claves a valores.

use "std/caracter" como c;
use "std/mapa" como m;

enum Valor {
    Nada,
    Cierto,
    Falso,
    Numero(str),
    Texto(str),
    Lista(list<Valor>),
    Objeto(map<str, Valor>),
}

struct Lector {
    texto: str,
    pos: usize,
    linea: usize,
}

// ---------- leer ----------

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

fn escapar_unicode(l: mut Lector, salida: mut str) ! {
    var valor = 0;
    var i = 0;
    while i < 4 {
        let d = digito_hex(tomar(l));
        if d == 255 { fail "un escape \\u sin cuatro digitos hex"; }
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

fn cadena(l: mut Lector) -> str ! {
    var salida = vacio();
    let _abre = tomar(l); // la comilla
    while true {
        let b = mirar(l);
        if b == 0 { fail "una cadena sin cerrar"; }
        if b == 34 { let _cierra = tomar(l); return salida; }
        if b == 92 {
            let _barra = tomar(l);
            let codigo = tomar(l);
            if codigo == 117 {
                try escapar_unicode(l, salida);
                continue;
            }
            let decodificado = escapado(codigo);
            if decodificado == 255 { fail "un escape desconocido"; }
            empujar_byte(salida, decodificado como u8);
            continue;
        }
        if b < 32 { fail "un byte de control suelto en la cadena"; }
        empujar_byte(salida, b como u8);
        let _b = tomar(l);
    }
    fail "una cadena sin cerrar";
}

fn numero(l: mut Lector) -> str ! {
    let desde = l.pos;
    if mirar(l) == 45 { let _menos = tomar(l); }
    if mirar(l) == 48 {
        let _cero = tomar(l);
    } else {
        if !c.es_digito(mirar(l)) { fail "un numero sin digitos"; }
        while c.es_digito(mirar(l)) { let _d = tomar(l); }
    }
    if mirar(l) == 46 {
        let _punto = tomar(l);
        if !c.es_digito(mirar(l)) { fail "un punto sin decimales"; }
        while c.es_digito(mirar(l)) { let _d = tomar(l); }
    }
    if mirar(l) == 101 || mirar(l) == 69 {
        let _e = tomar(l);
        if mirar(l) == 43 || mirar(l) == 45 { let _signo = tomar(l); }
        if !c.es_digito(mirar(l)) { fail "un exponente sin digitos"; }
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
    fail "aqui se esperaba un valor";
}

fn literal(l: mut Lector, palabra: view, v: Valor) -> Valor ! {
    var i = 0;
    while i < largo(palabra) {
        if tomar(l) != byte(palabra, i) { fail "un literal mal escrito"; }
        i = i + 1;
    }
    return v;
}

fn objeto(l: mut Lector) -> Valor ! {
    let _abre = tomar(l); // {
    var dentro: map<str, Valor> = [];
    espacios(l);
    if mirar(l) == 125 { let _cierra = tomar(l); return Valor.Objeto(dentro); }
    while true {
        espacios(l);
        if mirar(l) != 34 { fail "la clave de un objeto es una cadena"; }
        let clave = try cadena(l);
        espacios(l);
        if tomar(l) != 58 { fail "faltan los dos puntos"; }
        let v = try valor(l);
        poner(dentro, clave, v);
        espacios(l);
        let b = tomar(l);
        if b == 125 { return Valor.Objeto(dentro); }
        if b != 44 { fail "faltaba una coma o el cierre del objeto"; }
    }
    fail "un objeto sin cerrar";
}

fn arreglo(l: mut Lector) -> Valor ! {
    let _abre = tomar(l); // [
    var dentro: list<Valor> = [];
    espacios(l);
    if mirar(l) == 93 { let _cierra = tomar(l); return Valor.Lista(dentro); }
    while true {
        let v = try valor(l);
        anadir(dentro, v);
        espacios(l);
        let b = tomar(l);
        if b == 93 { return Valor.Lista(dentro); }
        if b != 44 { fail "faltaba una coma o el cierre de la lista"; }
    }
    fail "una lista sin cerrar";
}

// ---------- escribir ----------

fn comillas(l: view, salida: mut str) {
    empujar(salida, "\"");
    var i = 0;
    while i < largo(l) {
        let b = byte(l, i);
        if b == 34 { empujar(salida, "\\\""); }
        else if b == 92 { empujar(salida, "\\\\"); }
        else if b == 10 { empujar(salida, "\\n"); }
        else if b == 9 { empujar(salida, "\\t"); }
        else if b == 13 { empujar(salida, "\\r"); }
        else if b < 32 { empujar(salida, $"\\u00{b}"); }
        else { empujar_byte(salida, b como u8); }
        i = i + 1;
    }
    empujar(salida, "\"");
}

fn sangrar(salida: mut str, hondo: usize, compacto: bool) {
    if compacto { return; }
    empujar(salida, "\n");
    var i = 0;
    while i < hondo {
        empujar(salida, "  ");
        i = i + 1;
    }
}

fn escribir_dentro(v: &Valor, salida: mut str, hondo: usize, compacto: bool) {
    match v {
        Valor.Nada -> { empujar(salida, "null"); }
        Valor.Cierto -> { empujar(salida, "true"); }
        Valor.Falso -> { empujar(salida, "false"); }
        Valor.Numero(t) -> { empujar(salida, t); }
        Valor.Texto(t) -> { comillas(t, salida); }
        Valor.Lista(xs) -> {
            empujar(salida, "[");
            var primero = true;
            for x en xs {
                if !primero { empujar(salida, ","); }
                sangrar(salida, hondo + 1, compacto);
                escribir_dentro(x, salida, hondo + 1, compacto);
                primero = false;
            }
            sangrar(salida, hondo, compacto);
            empujar(salida, "]");
        }
        Valor.Objeto(dentro) -> {
            empujar(salida, "{");
            var primero = true;
            for k, x en dentro {
                if !primero { empujar(salida, ","); }
                sangrar(salida, hondo + 1, compacto);
                comillas(k, salida);
                if compacto { empujar(salida, ":"); } else { empujar(salida, ": "); }
                escribir_dentro(x, salida, hondo + 1, compacto);
                primero = false;
            }
            sangrar(salida, hondo, compacto);
            empujar(salida, "}");
        }
    }
}

// ---------- la api ----------

// Todo el texto es un unico valor JSON. Si sobra algo despues, falla.
fn leer(texto: view) -> Valor ! {
    var l = Lector { texto: nuevo(texto), pos: 0, linea: 1 };
    let v = try valor(l);
    espacios(l);
    if mirar(l) != 0 {
        fail "sobra texto despues del valor";
    }
    return v;
}

fn escribir(v: &Valor) -> str {
    var salida = vacio();
    escribir_dentro(v, salida, 0, true);
    return salida;
}

fn escribir_con_sangria(v: &Valor) -> str {
    var salida = vacio();
    escribir_dentro(v, salida, 0, false);
    return salida;
}
