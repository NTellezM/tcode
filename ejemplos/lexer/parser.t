// parser.t — el analisis sintactico de Tcode, escrito en Tcode.
//
// Descenso recursivo sobre los tokens que produce lib/lexico.t. Construye un
// arbol y lo imprime, o solo comprueba que el archivo sea sintacticamente
// valido.
//
//     ./parser archivo.t              imprime el arbol
//     ./parser archivo.t --callado    solo dice si es valido
//
// La pregunta que este programa responde: si las reglas de propiedad
// aguantan un arbol que se construye de abajo arriba, moviendo cada hijo
// dentro de su padre.

usar "lib/lexico.t";

struct Nodo {
    clase: str,
    texto: str,
    linea: usize,
    hijos: lista<Nodo>,
}

struct Estado {
    toks: lista<Token>,
    i: usize,
    // Nombres de struct, recogidos antes de analizar: hacen falta para saber
    // que `Punto { x: 1 }` es un literal y no el inicio de un bloque.
    structs: mapa<str, usize>,
}

// ------------------------------------------------------------------
// Construccion del arbol. Cada hijo se MUEVE dentro del padre: no hay
// copias, y el arbol entero se libera solo al salir del bloque.
// ------------------------------------------------------------------

fn hoja(clase: view, texto: view, linea: usize) -> Nodo {
    return Nodo { clase: nuevo(clase), texto: nuevo(texto), linea: linea,
                  hijos: [] };
}

fn rama(clase: view, linea: usize) -> Nodo {
    return Nodo { clase: nuevo(clase), texto: vacio(), linea: linea,
                  hijos: [] };
}

fn contar_nodos(n: &Nodo) -> usize {
    var total: usize = 1;
    for h en n.hijos { total = total + contar_nodos(h); }
    return total;
}

fn hondura(n: &Nodo) -> usize {
    var mayor: usize = 0;
    for h en n.hijos {
        let d: usize = hondura(h);
        if d > mayor { mayor = d; }
    }
    return mayor + 1;
}

fn mostrar(n: &Nodo, sangria: usize) {
    var i: usize = 0;
    while i < sangria { imprimir("  "); i = i + 1; }
    if largo(vista(n.texto)) > 0 {
        imprimir($"{n.clase} {n.texto}\n");
    } else {
        imprimir($"{n.clase}\n");
    }
    for h en n.hijos { mostrar(h, sangria + 1); }
}

// ------------------------------------------------------------------
// Lectura de tokens
// ------------------------------------------------------------------

fn tipo_en(e: &Estado, salto: usize) -> view {
    let j: usize = e.i + salto;
    if j >= largo(e.toks) { return "fin"; }
    return vista(e.toks[j].tipo);
}

fn valor_en(e: &Estado, salto: usize) -> view {
    let j: usize = e.i + salto;
    if j >= largo(e.toks) { return ""; }
    return vista(e.toks[j].valor);
}

fn linea_actual(e: &Estado) -> usize {
    if e.i >= largo(e.toks) { return 0; }
    return e.toks[e.i].linea;
}

fn es(e: &Estado, tipo: view, valor: view) -> bool {
    if !igual(tipo_en(e, 0), tipo) { return false; }
    if largo(valor) == 0 { return true; }
    return igual(valor_en(e, 0), valor);
}

fn avanzar(e: mut Estado) { e.i = e.i + 1; }

fn acepta(e: mut Estado, tipo: view, valor: view) -> bool {
    if es(e, tipo, valor) {
        avanzar(e);
        return true;
    }
    return false;
}

fn espera(e: mut Estado, tipo: view, valor: view) -> str ! {
    let v: str = nuevo(valor_en(e, 0));
    if !es(e, tipo, valor) {
        falla "no era el token que tocaba";
    }
    avanzar(e);
    return v;
}

// ------------------------------------------------------------------
// Tipos
// ------------------------------------------------------------------

fn tipo(e: mut Estado) -> str ! {
    if es(e, "palabra", "lista") {
        avanzar(e);
        try espera(e, "simbolo", "<");
        let dentro: str = try tipo(e);
        try espera(e, "simbolo", ">");
        var t: str = nuevo("lista<");
        empujar(t, vista(dentro));
        empujar(t, ">");
        return t;
    }
    if es(e, "palabra", "mapa") {
        avanzar(e);
        try espera(e, "simbolo", "<");
        let k: str = try tipo(e);
        try espera(e, "simbolo", ",");
        let v: str = try tipo(e);
        try espera(e, "simbolo", ">");
        var t: str = nuevo("mapa<");
        empujar(t, vista(k));
        empujar(t, ", ");
        empujar(t, vista(v));
        empujar(t, ">");
        return t;
    }
    if es(e, "simbolo", "[") {
        avanzar(e);
        let dentro: str = try tipo(e);
        try espera(e, "simbolo", ";");
        let n: str = try espera(e, "entero", "");
        try espera(e, "simbolo", "]");
        var t: str = nuevo("[");
        empujar(t, vista(dentro));
        empujar(t, "; ");
        empujar(t, vista(n));
        empujar(t, "]");
        return t;
    }
    if es(e, "palabra", "") || es(e, "ident", "") {
        let v: str = nuevo(valor_en(e, 0));
        avanzar(e);
        return v;
    }
    falla "se esperaba un tipo";
}

// ------------------------------------------------------------------
// Expresiones, de menor a mayor precedencia
// ------------------------------------------------------------------

fn primario(e: mut Estado) -> Nodo ! {
    let l: usize = linea_actual(e);

    if es(e, "entero", "") {
        let v: str = try espera(e, "entero", "");
        return hoja("entero", vista(v), l);
    }
    if es(e, "cadena", "") {
        let v: str = try espera(e, "cadena", "");
        return hoja("cadena", vista(v), l);
    }
    if es(e, "interpolada", "") {
        let v: str = try espera(e, "interpolada", "");
        return hoja("interpolada", vista(v), l);
    }
    if es(e, "palabra", "true") || es(e, "palabra", "false") {
        let v: str = nuevo(valor_en(e, 0));
        avanzar(e);
        return hoja("booleano", vista(v), l);
    }
    if acepta(e, "simbolo", "(") {
        let dentro: Nodo = try expresion(e);
        try espera(e, "simbolo", ")");
        return dentro;
    }
    if acepta(e, "simbolo", "[") {
        var n: Nodo = rama("literal_lista", l);
        if !es(e, "simbolo", "]") {
            var mas: bool = true;
            while mas {
                let x: Nodo = try expresion(e);
                anadir(n.hijos, x);
                mas = acepta(e, "simbolo", ",");
            }
        }
        try espera(e, "simbolo", "]");
        return n;
    }
    if es(e, "ident", "") {
        let nombre: str = try espera(e, "ident", "");

        if acepta(e, "simbolo", "(") {
            var n: Nodo = rama("llamada", l);
            empujar(n.texto, vista(nombre));
            if !es(e, "simbolo", ")") {
                var mas: bool = true;
                while mas {
                    let x: Nodo = try expresion(e);
                    anadir(n.hijos, x);
                    mas = acepta(e, "simbolo", ",");
                }
            }
            try espera(e, "simbolo", ")");
            return n;
        }

        if es(e, "simbolo", "{") && tiene(e.structs, vista(nombre)) {
            avanzar(e);
            var n: Nodo = rama("literal_struct", l);
            empujar(n.texto, vista(nombre));
            while !es(e, "simbolo", "}") {
                let campo: str = try espera(e, "ident", "");
                try espera(e, "simbolo", ":");
                var c: Nodo = rama("campo", l);
                empujar(c.texto, vista(campo));
                let x: Nodo = try expresion(e);
                anadir(c.hijos, x);
                anadir(n.hijos, c);
                if !acepta(e, "simbolo", ",") { break; }
            }
            try espera(e, "simbolo", "}");
            return n;
        }

        return hoja("variable", vista(nombre), l);
    }

    falla "se esperaba una expresion";
}

fn postfijo(e: mut Estado) -> Nodo ! {
    var n: Nodo = try primario(e);
    var sigue: bool = true;
    while sigue {
        let l: usize = linea_actual(e);
        if acepta(e, "simbolo", ".") {
            let campo: str = try espera(e, "ident", "");
            var p: Nodo = rama("campo", l);
            empujar(p.texto, vista(campo));
            anadir(p.hijos, n);
            n = p;
        } else {
            if acepta(e, "simbolo", "[") {
                let idx: Nodo = try expresion(e);
                try espera(e, "simbolo", "]");
                var p: Nodo = rama("indice", l);
                anadir(p.hijos, n);
                anadir(p.hijos, idx);
                n = p;
            } else {
                sigue = false;
            }
        }
    }
    return n;
}

fn unario(e: mut Estado) -> Nodo ! {
    let l: usize = linea_actual(e);
    if es(e, "palabra", "try") {
        avanzar(e);
        var n: Nodo = rama("try", l);
        let dentro: Nodo = try unario(e);
        anadir(n.hijos, dentro);
        return n;
    }
    if es(e, "simbolo", "!") || es(e, "simbolo", "-") {
        let op: str = nuevo(valor_en(e, 0));
        avanzar(e);
        var n: Nodo = rama("unaria", l);
        empujar(n.texto, vista(op));
        let dentro: Nodo = try unario(e);
        anadir(n.hijos, dentro);
        return n;
    }
    return try postfijo(e);
}

// Un nivel de precedencia: `sub` a la izquierda, y mientras el simbolo
// actual este en `ops`, se junta. `ops` viene como texto separado por
// espacios; comparar asi evita repetir la misma funcion seis veces.
fn en_lista(ops: view, sep: usize, cual: view) -> bool {
    var desde: usize = 0;
    var i: usize = 0;
    while i <= largo(ops) {
        var corta: bool = true;
        if i < largo(ops) { corta = byte(ops, i) == sep; }
        if corta {
            if igual(rebanar(ops, desde, i), cual) { return true; }
            desde = i + 1;
        }
        i = i + 1;
    }
    return false;
}

fn nivel(e: mut Estado, ops: view, grado: usize) -> Nodo ! {
    var izq: Nodo = try siguiente_nivel(e, grado);
    var sigue: bool = true;
    while sigue {
        if !es(e, "simbolo", "") || !en_lista(ops, 32, valor_en(e, 0)) {
            sigue = false;
        } else {
            let l: usize = linea_actual(e);
            let op: str = nuevo(valor_en(e, 0));
            avanzar(e);
            let der: Nodo = try siguiente_nivel(e, grado);
            var n: Nodo = rama("binaria", l);
            empujar(n.texto, vista(op));
            anadir(n.hijos, izq);
            anadir(n.hijos, der);
            izq = n;
        }
    }
    return izq;
}

fn siguiente_nivel(e: mut Estado, grado: usize) -> Nodo ! {
    if grado == 0 { return try nivel(e, "&& ||", 1); }
    if grado == 1 { return try nivel(e, "== !=", 2); }
    if grado == 2 { return try nivel(e, "< <= > >=", 3); }
    if grado == 3 { return try nivel(e, "+ - +? -?", 4); }
    if grado == 4 { return try nivel(e, "* / % *?", 5); }
    return try unario(e);
}

fn expresion(e: mut Estado) -> Nodo ! {
    let n: Nodo = try siguiente_nivel(e, 0);
    if es(e, "palabra", "sino") {
        let l: usize = linea_actual(e);
        avanzar(e);
        let alt: Nodo = try siguiente_nivel(e, 0);
        var s: Nodo = rama("sino", l);
        anadir(s.hijos, n);
        anadir(s.hijos, alt);
        return s;
    }
    return n;
}

// ------------------------------------------------------------------
// Sentencias
// ------------------------------------------------------------------

fn bloque(e: mut Estado) -> Nodo ! {
    let l: usize = linea_actual(e);
    try espera(e, "simbolo", "{");
    var n: Nodo = rama("bloque", l);
    while !es(e, "simbolo", "}") {
        if igual(tipo_en(e, 0), "fin") { falla "bloque sin cerrar"; }
        let st: Nodo = try sentencia(e);
        anadir(n.hijos, st);
    }
    try espera(e, "simbolo", "}");
    return n;
}

fn sentencia(e: mut Estado) -> Nodo ! {
    let l: usize = linea_actual(e);

    if es(e, "palabra", "let") || es(e, "palabra", "var") {
        let clave: str = nuevo(valor_en(e, 0));
        avanzar(e);
        let nombre: str = try espera(e, "ident", "");
        try espera(e, "simbolo", ":");
        let t: str = try tipo(e);
        try espera(e, "simbolo", "=");
        var n: Nodo = rama("declaracion", l);
        empujar(n.texto, vista(clave));
        empujar(n.texto, " ");
        empujar(n.texto, vista(nombre));
        empujar(n.texto, ": ");
        empujar(n.texto, vista(t));
        let v: Nodo = try expresion(e);
        anadir(n.hijos, v);
        try espera(e, "simbolo", ";");
        return n;
    }

    if es(e, "palabra", "if") {
        avanzar(e);
        var n: Nodo = rama("si", l);
        let cond: Nodo = try expresion(e);
        anadir(n.hijos, cond);
        let entonces: Nodo = try bloque(e);
        anadir(n.hijos, entonces);
        if acepta(e, "palabra", "else") {
            if es(e, "simbolo", "{") {
                let sino_b: Nodo = try bloque(e);
                anadir(n.hijos, sino_b);
            } else {
                let sino_s: Nodo = try sentencia(e);
                anadir(n.hijos, sino_s);
            }
        }
        return n;
    }

    if es(e, "palabra", "while") {
        avanzar(e);
        var n: Nodo = rama("mientras", l);
        let cond: Nodo = try expresion(e);
        anadir(n.hijos, cond);
        let cuerpo: Nodo = try bloque(e);
        anadir(n.hijos, cuerpo);
        return n;
    }

    if es(e, "palabra", "for") {
        avanzar(e);
        var n: Nodo = rama("para", l);
        let uno: str = try espera(e, "ident", "");
        empujar(n.texto, vista(uno));
        if acepta(e, "simbolo", ",") {
            let dos: str = try espera(e, "ident", "");
            empujar(n.texto, ", ");
            empujar(n.texto, vista(dos));
        }
        try espera(e, "palabra", "en");
        let coleccion: Nodo = try expresion(e);
        anadir(n.hijos, coleccion);
        let cuerpo: Nodo = try bloque(e);
        anadir(n.hijos, cuerpo);
        return n;
    }

    if es(e, "palabra", "return") {
        avanzar(e);
        var n: Nodo = rama("retorno", l);
        if !es(e, "simbolo", ";") {
            let v: Nodo = try expresion(e);
            anadir(n.hijos, v);
        }
        try espera(e, "simbolo", ";");
        return n;
    }

    if es(e, "palabra", "falla") {
        avanzar(e);
        let motivo: str = try espera(e, "cadena", "");
        try espera(e, "simbolo", ";");
        return hoja("falla", vista(motivo), l);
    }

    if es(e, "palabra", "break") {
        avanzar(e);
        try espera(e, "simbolo", ";");
        return hoja("romper", "", l);
    }

    if es(e, "palabra", "continue") {
        avanzar(e);
        try espera(e, "simbolo", ";");
        return hoja("continuar", "", l);
    }

    // asignacion o expresion suelta
    let izq: Nodo = try expresion(e);
    if acepta(e, "simbolo", "=") {
        var n: Nodo = rama("asignacion", l);
        let der: Nodo = try expresion(e);
        anadir(n.hijos, izq);
        anadir(n.hijos, der);
        try espera(e, "simbolo", ";");
        return n;
    }
    try espera(e, "simbolo", ";");
    var n: Nodo = rama("expresion", l);
    anadir(n.hijos, izq);
    return n;
}

// ------------------------------------------------------------------
// Declaraciones de alto nivel
// ------------------------------------------------------------------

fn declaracion(e: mut Estado) -> Nodo ! {
    let l: usize = linea_actual(e);

    if es(e, "palabra", "struct") {
        avanzar(e);
        let nombre: str = try espera(e, "ident", "");
        try espera(e, "simbolo", "{");
        var n: Nodo = rama("struct", l);
        empujar(n.texto, vista(nombre));
        while !es(e, "simbolo", "}") {
            let campo: str = try espera(e, "ident", "");
            try espera(e, "simbolo", ":");
            let t: str = try tipo(e);
            var c: Nodo = rama("campo_def", linea_actual(e));
            empujar(c.texto, vista(campo));
            empujar(c.texto, ": ");
            empujar(c.texto, vista(t));
            anadir(n.hijos, c);
            if !acepta(e, "simbolo", ",") { break; }
        }
        try espera(e, "simbolo", "}");
        return n;
    }

    try espera(e, "palabra", "fn");
    let nombre: str = try espera(e, "ident", "");
    try espera(e, "simbolo", "(");
    var n: Nodo = rama("fn", l);
    empujar(n.texto, vista(nombre));

    if !es(e, "simbolo", ")") {
        var mas: bool = true;
        while mas {
            let pn: str = try espera(e, "ident", "");
            try espera(e, "simbolo", ":");
            var marca: str = vacio();
            if acepta(e, "palabra", "mut") { marca = nuevo("mut "); }
            else { if acepta(e, "simbolo", "&") { marca = nuevo("&"); } }
            let t: str = try tipo(e);
            var p: Nodo = rama("param", l);
            empujar(p.texto, vista(pn));
            empujar(p.texto, ": ");
            empujar(p.texto, vista(marca));
            empujar(p.texto, vista(t));
            anadir(n.hijos, p);
            mas = acepta(e, "simbolo", ",");
        }
    }
    try espera(e, "simbolo", ")");

    if acepta(e, "simbolo", "->") {
        let t: str = try tipo(e);
        var r: Nodo = rama("retorno_tipo", l);
        empujar(r.texto, vista(t));
        anadir(n.hijos, r);
    }
    if acepta(e, "simbolo", "!") {
        anadir(n.hijos, hoja("falible", "", l));
    }

    let cuerpo: Nodo = try bloque(e);
    anadir(n.hijos, cuerpo);
    return n;
}

fn recoger_structs(toks: &lista<Token>) -> mapa<str, usize> {
    var m: mapa<str, usize> = [];
    var i: usize = 0;
    while i + 1 < largo(toks) {
        if igual(vista(toks[i].valor), "struct") {
            if igual(vista(toks[i + 1].tipo), "ident") {
                poner(m, vista(toks[i + 1].valor), 1);
            }
        }
        i = i + 1;
    }
    return m;
}

fn programa(e: mut Estado) -> Nodo ! {
    var raiz: Nodo = rama("programa", 1);
    while acepta(e, "palabra", "usar") {
        let ruta: str = try espera(e, "cadena", "");
        try espera(e, "simbolo", ";");
        anadir(raiz.hijos, hoja("usar", vista(ruta), linea_actual(e)));
    }
    while !igual(tipo_en(e, 0), "fin") {
        let d: Nodo = try declaracion(e);
        anadir(raiz.hijos, d);
    }
    return raiz;
}

// ------------------------------------------------------------------
// Programa
// ------------------------------------------------------------------

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t> [--callado]\n");
        return 1;
    }

    let ruta: view = argumento(1);
    let fuente: str = try leer_archivo(ruta);
    let tokens: lista<Token> = try analizar(vista(fuente));

    // Los structs se recogen ANTES de mover los tokens dentro del estado:
    // despues del movimiento ya no serian nuestros. El compilador lo dice.
    let nombres: mapa<str, usize> = recoger_structs(tokens);
    var e: Estado = Estado { toks: tokens, i: 0, structs: nombres };
    let arbol: Nodo = try programa(e);


    var callado: bool = false;
    if n_argumentos() > 2 { callado = igual(argumento(2), "--callado"); }

    if callado {
        imprimir($"{ruta}: {contar_nodos(arbol)} nodos, hondura {hondura(arbol)}\n");
        return 0;
    }
    mostrar(arbol, 0);
    return 0;
}
