// lib/sintaxis.t — el analisis sintactico de Tcode, escrito en Tcode.
//
// Lo usan `parser.t`, que imprime el arbol, y `compilador/tipos.t`, que se
// apoya en el para responder preguntas sobre los tipos que aparecen.

usar "std/texto";
usar "lexico.t";

struct Nodo {
    clase: str,
    texto: str,
    linea: usize,
    hijos: lista<Nodo>,
}

struct Estado {
    toks: lista<Token>,
    i: usize,
    // Los alias de `usar ... como x`: `x.algo` es un nombre, no el campo
    // `algo` de una variable `x`.
    alias: mapa<str, usize>,
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
    var total = 1;
    for h en n.hijos { total = total + contar_nodos(h); }
    return total;
}

fn hondura(n: &Nodo) -> usize {
    var mayor = 0;
    for h en n.hijos {
        let d = hondura(h);
        if d > mayor { mayor = d; }
    }
    return mayor + 1;
}

fn mostrar(n: &Nodo, sangria: usize) {
    var i = 0;
    while i < sangria { imprimir("  "); i = i + 1; }
    if largo(n.texto) > 0 {
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
    let j = e.i + salto;
    if j >= largo(e.toks) { return "fin"; }
    return vista(e.toks[j].tipo);
}

fn valor_en(e: &Estado, salto: usize) -> view {
    let j = e.i + salto;
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
    // `lista<lista<str>>` acaba en dos `>` pegados, que el lexer lee como el
    // desplazamiento `>>`. Donde se espera cerrar un tipo, se parte en dos.
    if igual(valor, ">") {
        if es(e, "simbolo", ">>") {
            e.toks[e.i].valor = nuevo(">");
            return nuevo(">");
        }
    }
    let v = nuevo(valor_en(e, 0));
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
    // `&T` y `&mut T` como tipo. Fuera de la posicion de parametro aparecen
    // dentro de un tipo de funcion: `fn(&T, &T) -> bool`.
    if acepta(e, "simbolo", "&") {
        var t = nuevo("&");
        if acepta(e, "palabra", "mut") { empujar(t, "mut "); }
        let dentro = try tipo(e);
        empujar(t, dentro);
        return t;
    }
    // `bloque<T>`: no es palabra reservada, se reconoce por el `<`.
    if es(e, "ident", "bloque") {
        if igual(valor_en(e, 1), "<") {
            avanzar(e);
            try espera(e, "simbolo", "<");
            let dentro = try tipo(e);
            try espera(e, "simbolo", ">");
            var t = nuevo("bloque<");
            empujar(t, dentro);
            empujar(t, ">");
            return t;
        }
    }
    if es(e, "palabra", "lista") {
        avanzar(e);
        try espera(e, "simbolo", "<");
        let dentro = try tipo(e);
        try espera(e, "simbolo", ">");
        var t = nuevo("lista<");
        empujar(t, dentro);
        empujar(t, ">");
        return t;
    }
    if es(e, "palabra", "mapa") {
        avanzar(e);
        try espera(e, "simbolo", "<");
        let k = try tipo(e);
        try espera(e, "simbolo", ",");
        let v = try tipo(e);
        try espera(e, "simbolo", ">");
        var t = nuevo("mapa<");
        empujar(t, k);
        empujar(t, ", ");
        empujar(t, v);
        empujar(t, ">");
        return t;
    }
    // `fn(usize, usize) -> bool`: el tipo de una funcion usada como valor.
    if es(e, "palabra", "fn") {
        avanzar(e);
        try espera(e, "simbolo", "(");
        var t = nuevo("fn(");
        if !es(e, "simbolo", ")") {
            var mas_p = true;
            while mas_p {
                let a = try tipo(e);
                empujar(t, a);
                mas_p = acepta(e, "simbolo", ",");
                if mas_p { empujar(t, ", "); }
            }
        }
        try espera(e, "simbolo", ")");
        empujar(t, ")");
        if acepta(e, "simbolo", "->") {
            let r = try tipo(e);
            empujar(t, " -> ");
            empujar(t, r);
        }
        return t;
    }

    if es(e, "simbolo", "[") {
        avanzar(e);
        let dentro = try tipo(e);
        try espera(e, "simbolo", ";");
        let n = try espera(e, "entero", "");
        try espera(e, "simbolo", "]");
        var t = nuevo("[");
        empujar(t, dentro);
        empujar(t, "; ");
        empujar(t, n);
        empujar(t, "]");
        return t;
    }
    if es(e, "palabra", "") || es(e, "ident", "") {
        var v = nuevo(valor_en(e, 0));
        avanzar(e);
        // `t.Caja`: un tipo que llega con nombre de modulo.
        if tiene(e.alias, vista(v)) {
            if es(e, "simbolo", ".") {
                avanzar(e);
                let miembro = try espera(e, "ident", "");
                empujar(v, ".");
                empujar(v, miembro);
            }
        }
        // `Par<usize, str>`: un struct generico aplicado a sus tipos.
        if acepta(e, "simbolo", "<") {
            empujar(v, "<");
            var mas_arg = true;
            while mas_arg {
                let a = try tipo(e);
                empujar(v, a);
                mas_arg = acepta(e, "simbolo", ",");
                if mas_arg { empujar(v, ", "); }
            }
            try espera(e, "simbolo", ">");
            empujar(v, ">");
        }
        return v;
    }
    falla "se esperaba un tipo";
}

// ------------------------------------------------------------------
// Expresiones, de menor a mayor precedencia
// ------------------------------------------------------------------

fn primario(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);

    if es(e, "entero", "") {
        let v = try espera(e, "entero", "");
        return hoja("entero", v, l);
    }
    if es(e, "cadena", "") {
        let v = try espera(e, "cadena", "");
        return hoja("cadena", v, l);
    }
    if es(e, "interpolada", "") {
        let v = try espera(e, "interpolada", "");
        return hoja("interpolada", v, l);
    }
    if es(e, "palabra", "true") || es(e, "palabra", "false") {
        let v = nuevo(valor_en(e, 0));
        avanzar(e);
        return hoja("booleano", v, l);
    }
    if acepta(e, "simbolo", "(") {
        let dentro = try expresion(e);
        try espera(e, "simbolo", ")");
        return dentro;
    }
    if acepta(e, "simbolo", "[") {
        var n = rama("literal_lista", l);
        if !es(e, "simbolo", "]") {
            var mas = true;
            while mas {
                let x = try expresion(e);
                anadir(n.hijos, x);
                mas = acepta(e, "simbolo", ",");
            }
        }
        try espera(e, "simbolo", "]");
        return n;
    }
    // `fn[a, b](x: usize) -> bool { ... }`: una clausura.
    if es(e, "palabra", "fn") {
        avanzar(e);
        var n = rama("cierre", l);
        if acepta(e, "simbolo", "[") {
            if !es(e, "simbolo", "]") {
                var mas_c = true;
                while mas_c {
                    let cap = try espera(e, "ident", "");
                    anadir(n.hijos, hoja("captura", cap, l));
                    mas_c = acepta(e, "simbolo", ",");
                }
            }
            try espera(e, "simbolo", "]");
        }
        try espera(e, "simbolo", "(");
        if !es(e, "simbolo", ")") {
            var mas_p = true;
            while mas_p {
                let pn = try espera(e, "ident", "");
                try espera(e, "simbolo", ":");
                var marca = vacio();
                if acepta(e, "palabra", "mut") { marca = nuevo("mut "); }
                else { if acepta(e, "simbolo", "&") { marca = nuevo("&"); } }
                let t = try tipo(e);
                var pp = rama("param", l);
                empujar(pp.texto, pn);
                empujar(pp.texto, ": ");
                empujar(pp.texto, marca);
                empujar(pp.texto, t);
                anadir(n.hijos, pp);
                mas_p = acepta(e, "simbolo", ",");
            }
        }
        try espera(e, "simbolo", ")");
        if acepta(e, "simbolo", "->") {
            let t = try tipo(e);
            var r = rama("retorno_tipo", l);
            empujar(r.texto, t);
            anadir(n.hijos, r);
        }
        if acepta(e, "simbolo", "!") {
            anadir(n.hijos, hoja("falible", "", l));
        }
        let cuerpo = try bloque(e);
        anadir(n.hijos, cuerpo);
        return n;
    }

    // `if c { a } else { b }` como valor: cada rama es una expresion suelta.
    if es(e, "palabra", "if") {
        avanzar(e);
        var n = rama("si_expr", l);
        let c = try expresion(e);
        anadir(n.hijos, c);
        try espera(e, "simbolo", "{");
        let a = try expresion(e);
        anadir(n.hijos, a);
        try espera(e, "simbolo", "}");
        try espera(e, "palabra", "else");
        try espera(e, "simbolo", "{");
        let b = try expresion(e);
        anadir(n.hijos, b);
        try espera(e, "simbolo", "}");
        return n;
    }

    if es(e, "decimal", "") {
        let v = try espera(e, "decimal", "");
        return hoja("decimal", v, l);
    }

    if es(e, "ident", "") {
        var nombre = try espera(e, "ident", "");

        // `txt.palabras(v)`: nombre calificado por el modulo de donde viene.
        if tiene(e.alias, vista(nombre)) {
            if acepta(e, "simbolo", ".") {
                let miembro = try espera(e, "ident", "");
                empujar(nombre, ".");
                empujar(nombre, miembro);
            }
        }

        if acepta(e, "simbolo", "(") {
            var n = rama("llamada", l);
            empujar(n.texto, nombre);
            if !es(e, "simbolo", ")") {
                var mas = true;
                while mas {
                    let x = try expresion(e);
                    anadir(n.hijos, x);
                    mas = acepta(e, "simbolo", ",");
                }
            }
            try espera(e, "simbolo", ")");
            return n;
        }

        if es(e, "simbolo", "{") && (tiene(e.structs, nombre)
            || contiene(vista(nombre), ".")) {
            avanzar(e);
            var n = rama("literal_struct", l);
            empujar(n.texto, nombre);
            while !es(e, "simbolo", "}") {
                let campo = try espera(e, "ident", "");
                try espera(e, "simbolo", ":");
                var c = rama("campo", l);
                empujar(c.texto, campo);
                let x = try expresion(e);
                anadir(c.hijos, x);
                anadir(n.hijos, c);
                if !acepta(e, "simbolo", ",") { break; }
            }
            try espera(e, "simbolo", "}");
            return n;
        }

        return hoja("variable", nombre, l);
    }

    falla "se esperaba una expresion";
}

fn postfijo(e: mut Estado) -> Nodo ! {
    var n = try primario(e);
    var sigue = true;
    while sigue {
        let l = linea_actual(e);
        if acepta(e, "simbolo", ".") {
            let campo = try espera(e, "ident", "");
            var p = rama("campo", l);
            empujar(p.texto, campo);
            anadir(p.hijos, n);
            n = p;
        } else {
            if acepta(e, "simbolo", "[") {
                let idx = try expresion(e);
                try espera(e, "simbolo", "]");
                var p = rama("indice", l);
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
    let l = linea_actual(e);
    if es(e, "palabra", "try") {
        avanzar(e);
        var n = rama("try", l);
        let dentro = try unario(e);
        anadir(n.hijos, dentro);
        return n;
    }
    if es(e, "simbolo", "!") || es(e, "simbolo", "-") || es(e, "simbolo", "~") {
        let op = nuevo(valor_en(e, 0));
        avanzar(e);
        var n = rama("unaria", l);
        empujar(n.texto, op);
        let dentro = try unario(e);
        anadir(n.hijos, dentro);
        return n;
    }
    return try postfijo(e);
}

// Un nivel de precedencia: `sub` a la izquierda, y mientras el simbolo
// actual este en `ops`, se junta. `ops` viene como texto separado por
// espacios; comparar asi evita repetir la misma funcion seis veces.
fn en_lista(ops: view, sep: usize, cual: view) -> bool {
    var desde = 0;
    var i = 0;
    while i <= largo(ops) {
        var corta = true;
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
    var izq = try siguiente_nivel(e, grado);
    var sigue = true;
    while sigue {
        if !es(e, "simbolo", "") || !en_lista(ops, 32, valor_en(e, 0)) {
            sigue = false;
        } else {
            let l = linea_actual(e);
            let op = nuevo(valor_en(e, 0));
            avanzar(e);
            let der = try siguiente_nivel(e, grado);
            var n = rama("binaria", l);
            empujar(n.texto, op);
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
    // Los bits atan MAS que las comparaciones, no menos: `a & b == c` es
    // `(a & b) == c`, no lo que hace C.
    if grado == 3 { return try nivel(e, "|", 4); }
    if grado == 4 { return try nivel(e, "^", 5); }
    if grado == 5 { return try nivel(e, "&", 6); }
    if grado == 6 { return try nivel(e, "<< >>", 7); }
    if grado == 7 { return try nivel(e, "+ - +? -?", 8); }
    if grado == 8 { return try nivel(e, "* / % *? /?", 9); }
    return try conversion(e);
}

// `x como u8`, `x como? u8`: ata mas que cualquier binario.
fn conversion(e: mut Estado) -> Nodo ! {
    var izq = try unario(e);
    var sigue = true;
    while sigue {
        if !igual(valor_en(e, 0), "como") {
            sigue = false;
        } else {
            let l = linea_actual(e);
            avanzar(e);
            var n = rama("conversion", l);
            if acepta(e, "simbolo", "?") { empujar(n.texto, "?"); }
            let t = try tipo(e);
            empujar(n.texto, t);
            anadir(n.hijos, izq);
            izq = n;
        }
    }
    return izq;
}

fn expresion(e: mut Estado) -> Nodo ! {
    let n = try siguiente_nivel(e, 0);
    if es(e, "palabra", "sino") {
        let l = linea_actual(e);
        avanzar(e);
        let alt = try siguiente_nivel(e, 0);
        var s = rama("sino", l);
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
    let l = linea_actual(e);
    try espera(e, "simbolo", "{");
    var n = rama("bloque", l);
    while !es(e, "simbolo", "}") {
        if igual(tipo_en(e, 0), "fin") { falla "bloque sin cerrar"; }
        let st = try sentencia(e);
        anadir(n.hijos, st);
    }
    try espera(e, "simbolo", "}");
    return n;
}

fn sentencia(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);

    if es(e, "palabra", "let") || es(e, "palabra", "var") {
        let clave = nuevo(valor_en(e, 0));
        avanzar(e);
        let nombre = try espera(e, "ident", "");
        // El tipo es opcional: casi siempre se deduce del valor.
        var t = vacio();
        if acepta(e, "simbolo", ":") {
            let escrito = try tipo(e);
            t = nuevo(escrito);
        }
        try espera(e, "simbolo", "=");
        var n = rama("declaracion", l);
        empujar(n.texto, clave);
        empujar(n.texto, " ");
        empujar(n.texto, nombre);
        if largo(t) > 0 {
            empujar(n.texto, ": ");
            empujar(n.texto, t);
        }
        let v = try expresion(e);
        anadir(n.hijos, v);
        try espera(e, "simbolo", ";");
        return n;
    }

    if es(e, "palabra", "if") {
        avanzar(e);
        var n = rama("si", l);
        let cond = try expresion(e);
        anadir(n.hijos, cond);
        let entonces = try bloque(e);
        anadir(n.hijos, entonces);
        if acepta(e, "palabra", "else") {
            if es(e, "simbolo", "{") {
                let sino_b = try bloque(e);
                anadir(n.hijos, sino_b);
            } else {
                let sino_s = try sentencia(e);
                anadir(n.hijos, sino_s);
            }
        }
        return n;
    }

    if es(e, "palabra", "while") {
        avanzar(e);
        var n = rama("mientras", l);
        let cond = try expresion(e);
        anadir(n.hijos, cond);
        let cuerpo = try bloque(e);
        anadir(n.hijos, cuerpo);
        return n;
    }

    if es(e, "palabra", "for") {
        avanzar(e);
        var n = rama("para", l);
        let uno = try espera(e, "ident", "");
        empujar(n.texto, uno);
        if acepta(e, "simbolo", ",") {
            let dos = try espera(e, "ident", "");
            empujar(n.texto, ", ");
            empujar(n.texto, dos);
        }
        try espera(e, "palabra", "en");
        let coleccion = try expresion(e);
        anadir(n.hijos, coleccion);
        let cuerpo = try bloque(e);
        anadir(n.hijos, cuerpo);
        return n;
    }

    if es(e, "palabra", "return") {
        avanzar(e);
        var n = rama("retorno", l);
        if !es(e, "simbolo", ";") {
            let v = try expresion(e);
            anadir(n.hijos, v);
        }
        try espera(e, "simbolo", ";");
        return n;
    }

    if es(e, "palabra", "falla") {
        avanzar(e);
        let motivo = try espera(e, "cadena", "");
        try espera(e, "simbolo", ";");
        return hoja("falla", motivo, l);
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
    let izq = try expresion(e);
    if acepta(e, "simbolo", "=") {
        var n = rama("asignacion", l);
        let der = try expresion(e);
        anadir(n.hijos, izq);
        anadir(n.hijos, der);
        try espera(e, "simbolo", ";");
        return n;
    }
    try espera(e, "simbolo", ";");
    var n = rama("expresion", l);
    anadir(n.hijos, izq);
    return n;
}

// ------------------------------------------------------------------
// Declaraciones de alto nivel
// ------------------------------------------------------------------

fn declaracion(e: mut Estado) -> Nodo ! {
    let l = linea_actual(e);

    if es(e, "palabra", "struct") {
        avanzar(e);
        let nombre = try espera(e, "ident", "");
        var n = rama("struct", l);
        empujar(n.texto, nombre);
        // `struct Par<A, B>`: igual que en una funcion.
        if acepta(e, "simbolo", "<") {
            var mas_tp = true;
            while mas_tp {
                let tp = try espera(e, "ident", "");
                anadir(n.hijos, hoja("tipo_param", tp, l));
                mas_tp = acepta(e, "simbolo", ",");
            }
            try espera(e, "simbolo", ">");
        }
        try espera(e, "simbolo", "{");
        while !es(e, "simbolo", "}") {
            let campo = try espera(e, "ident", "");
            try espera(e, "simbolo", ":");
            let t = try tipo(e);
            var c = rama("campo_def", linea_actual(e));
            empujar(c.texto, campo);
            empujar(c.texto, ": ");
            empujar(c.texto, t);
            anadir(n.hijos, c);
            if !acepta(e, "simbolo", ",") { break; }
        }
        try espera(e, "simbolo", "}");
        return n;
    }

    try espera(e, "palabra", "fn");
    let nombre = try espera(e, "ident", "");
    var n = rama("fn", l);
    empujar(n.texto, nombre);

    // `fn primeras<T>(...)`: parametros de tipo. Dentro de la firma y del
    // cuerpo, `T` es un tipo mas, y `tipo` ya acepta cualquier nombre.
    if acepta(e, "simbolo", "<") {
        var mas_tipos = true;
        while mas_tipos {
            let tp = try espera(e, "ident", "");
            anadir(n.hijos, hoja("tipo_param", tp, l));
            // `<T: numero>`: la restriccion es un nombre, nada mas.
            if acepta(e, "simbolo", ":") {
                let r = try espera(e, "ident", "");
                anadir(n.hijos, hoja("restriccion", r, l));
            }
            mas_tipos = acepta(e, "simbolo", ",");
        }
        try espera(e, "simbolo", ">");
    }

    try espera(e, "simbolo", "(");

    if !es(e, "simbolo", ")") {
        var mas = true;
        while mas {
            let pn = try espera(e, "ident", "");
            try espera(e, "simbolo", ":");
            var marca = vacio();
            if acepta(e, "palabra", "mut") { marca = nuevo("mut "); }
            else { if acepta(e, "simbolo", "&") { marca = nuevo("&"); } }
            let t = try tipo(e);
            var p = rama("param", l);
            empujar(p.texto, pn);
            empujar(p.texto, ": ");
            empujar(p.texto, marca);
            empujar(p.texto, t);
            anadir(n.hijos, p);
            mas = acepta(e, "simbolo", ",");
        }
    }
    try espera(e, "simbolo", ")");

    if acepta(e, "simbolo", "->") {
        let t = try tipo(e);
        var r = rama("retorno_tipo", l);
        empujar(r.texto, t);
        anadir(n.hijos, r);
    }
    if acepta(e, "simbolo", "!") {
        anadir(n.hijos, hoja("falible", "", l));
    }

    let cuerpo = try bloque(e);
    anadir(n.hijos, cuerpo);
    return n;
}

fn recoger_structs(toks: &lista<Token>) -> mapa<str, usize> {
    var m: mapa<str, usize> = [];
    var i = 0;
    while i + 1 < largo(toks) {
        if igual(toks[i].valor, "struct") {
            if igual(toks[i + 1].tipo, "ident") {
                poner(m, toks[i + 1].valor, 1);
            }
        }
        i = i + 1;
    }
    return m;
}

// El directorio de una ruta, sin la barra final. `a/b/c.t` -> `a/b`.
fn carpeta(ruta: view) -> str {
    var corte = 0;
    var i = 0;
    while i < largo(ruta) {
        if byte(ruta, i) == 47 { corte = i; }
        i = i + 1;
    }
    return nuevo(rebanar(ruta, 0, corte));
}

// Los structs que ve un archivo: los suyos y los de lo que trae con `usar`.
//
// El parser de Python los recibe del cargador de modulos; aqui se leen las
// dependencias directamente. Con una vuelta basta: un struct que llega de
// tercera mano no se usa como literal sin nombrarlo antes.
fn structs_visibles(ruta: view, toks: &lista<Token>) -> mapa<str, usize> {
    var m = recoger_structs(toks);
    let dir = carpeta(ruta);

    var i = 0;
    while i + 1 < largo(toks) {
        if igual(toks[i].valor, "usar") {
            if igual(toks[i + 1].tipo, "cadena") {
                let pedido = nuevo(toks[i + 1].valor);
                var candidatos: lista<str> = [];
                // Junto al archivo que lo pide, y desde donde se ejecuta.
                var junto = nuevo(vista(dir));
                if largo(junto) > 0 { empujar(junto, "/"); }
                empujar(junto, vista(pedido));
                anadir(candidatos, copiar(junto));
                empujar(junto, ".t");
                anadir(candidatos, junto);
                anadir(candidatos, copiar(pedido));
                var suelto = copiar(pedido);
                empujar(suelto, ".t");
                anadir(candidatos, suelto);

                for c en candidatos {
                    let texto = leer_archivo(vista(c)) sino vacio();
                    if largo(texto) > 0 {
                        let otros = analizar(vista(texto)) sino [];
                        for nombre en recoger_structs(otros) {
                            poner(m, vista(nombre), 1);
                        }
                        break;
                    }
                }
            }
        }
        i = i + 1;
    }
    return m;
}

fn programa(e: mut Estado) -> Nodo ! {
    var raiz = rama("programa", 1);
    while acepta(e, "palabra", "usar") {
        let ruta = try espera(e, "cadena", "");
        // `usar "x" como a;`: `como` no es palabra reservada, es un ident.
        if igual(valor_en(e, 0), "como") {
            avanzar(e);
            let a = try espera(e, "ident", "");
            anadir(raiz.hijos, hoja("alias", a, linea_actual(e)));
            poner(e.alias, a, 1);
        }
        try espera(e, "simbolo", ";");
        anadir(raiz.hijos, hoja("usar", ruta, linea_actual(e)));
    }
    while !igual(tipo_en(e, 0), "fin") {
        let d = try declaracion(e);
        anadir(raiz.hijos, d);
    }
    return raiz;
}

// ------------------------------------------------------------------
// Programa
// ------------------------------------------------------------------
