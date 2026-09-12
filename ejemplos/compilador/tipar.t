// tipar.t — el tipo de cada variable de cada funcion, dicho por Tcode.
//
// Recorre un `.t` con el parser de Tcode, va declarando lo que encuentra y
// dice de que tipo es cada cosa. La suite corre esto y el comprobador de
// Python sobre los mismos archivos y compara linea a linea.
//
//     ./tipar std/texto.t

usar "lib/tipar.t" como I;
usar "../lexer/lib/lexico.t";
usar "../lexer/lib/sintaxis.t" como P;
usar "std/texto";
usar "std/lista";

// De `nombre: &lista<str>` saca `nombre` y `lista<str>`: el prestamo se
// guarda aparte, igual que en el comprobador de Python.
fn nombre_de(texto: view) -> str {
    var i = 0;
    while i < largo(texto) {
        if byte(texto, i) == 58 { return nuevo(rebanar(texto, 0, i)); }
        i = i + 1;
    }
    return nuevo(texto);
}

// `P.Nodo` es `Nodo`: el nombre del modulo no forma parte del tipo.
fn sin_alias_de_modulo(t: view) -> str {
    var corte = 0;
    var visto = false;
    var i = 0;
    while i < largo(t) {
        let b = byte(t, i);
        if b == 46 && !visto { corte = i + 1; visto = true; }
        if b == 60 { break; }
        i = i + 1;
    }
    if !visto { return nuevo(t); }
    return nuevo(rebanar(t, corte, largo(t)));
}

fn tipo_desnudo(texto: view) -> str {
    var i = 0;
    while i + 1 < largo(texto) {
        if byte(texto, i) == 58 {
            if byte(texto, i + 1) == 32 {
                let t = recortar(rebanar(texto, i + 2, largo(texto)));
                if empieza_con(t, "mut ") {
                    return sin_alias_de_modulo(rebanar(t, 4, largo(t)));
                }
                if empieza_con(t, "&mut ") {
                    return sin_alias_de_modulo(rebanar(t, 5, largo(t)));
                }
                if empieza_con(t, "&") {
                    return sin_alias_de_modulo(rebanar(t, 1, largo(t)));
                }
                return sin_alias_de_modulo(t);
            }
        }
        i = i + 1;
    }
    return vacio();
}

// `let nombre` o `let nombre: tipo` -> el nombre.
fn nombre_declarado(texto: view) -> str {
    let sin_clave = tras_espacio(texto);
    return nombre_de(vista(sin_clave));
}

fn tras_espacio(texto: view) -> str {
    var i = 0;
    while i < largo(texto) {
        if byte(texto, i) == 32 {
            return nuevo(rebanar(texto, i + 1, largo(texto)));
        }
        i = i + 1;
    }
    return nuevo(texto);
}

fn recoger_declaraciones(n: &P.Nodo, c: mut I.Contexto) {
    if igual(vista(n.clase), "struct") {
        var tipos: lista<str> = [];
        var nombres: lista<str> = [];
        for h en n.hijos {
            if igual(vista(h.clase), "campo_def") {
                anadir(nombres, nombre_de(vista(h.texto)));
                anadir(tipos, tipo_desnudo(vista(h.texto)));
            }
        }
        poner(c.campos, vista(n.texto), tipos);
        poner(c.nombres, vista(n.texto), nombres);
    }
    if igual(vista(n.clase), "fn") {
        var retorno = vacio();
        var sueltos: lista<str> = [];
        var tipos_param: lista<str> = [];
        for h en n.hijos {
            if igual(vista(h.clase), "retorno_tipo") {
                retorno = nuevo(vista(h.texto));
            }
            if igual(vista(h.clase), "tipo_param") {
                anadir(sueltos, nuevo(vista(h.texto)));
            }
            if igual(vista(h.clase), "param") {
                anadir(tipos_param, tipo_desnudo(vista(h.texto)));
            }
        }
        poner(c.retornos, vista(n.texto), retorno);
        poner(c.params, vista(n.texto), tipos_param);
        if largo(sueltos) > 0 {
            poner(c.tipo_params, vista(n.texto), sueltos);
        }
    }
    for h en n.hijos { recoger_declaraciones(h, c); }
}

// Recorre un cuerpo declarando lo que vaya apareciendo, y va apuntando cada
// variable con su tipo en el orden en que se declara.
fn recorrer(n: &P.Nodo, c: mut I.Contexto, quien: view, salida: mut lista<str>) {
    let clase = vista(n.clase);

    if igual(clase, "declaracion") {
        // Primero el valor, que se lee en el ambito de antes.
        var tipo = vacio();
        let escrito = tipo_desnudo(vista(n.texto));
        if largo(escrito) > 0 {
            tipo = escrito;
        } else {
            if largo(n.hijos) > 0 { tipo = I.tipo_de(c, n.hijos[0]); }
        }
        for h en n.hijos { recorrer(h, c, quien, salida); }
        let nombre = nombre_declarado(vista(n.texto));
        I.declarar(c, vista(nombre), vista(tipo));
        anadir(salida, $"{quien}\t{nombre}\t{tipo}");
        return;
    }

    if igual(clase, "para") {
        // `for x en xs`: la variable toma el tipo del elemento.
        if largo(n.hijos) > 0 {
            let sobre = I.tipo_de(c, n.hijos[0]);
            let base = elemento_de(vista(sobre));
            I.abrir(c);
            let partes = try_partir(vista(n.texto));
            let uno = copiar(partes[0]);
            I.declarar(c, vista(uno), vista(base));
            anadir(salida, $"{quien}\t{uno}\t{base}");
            if largo(partes) > 1 {
                // `for clave, valor en mapa`: la segunda es el valor.
                let dos = copiar(partes[1]);
                let tv = valor_de(vista(sobre));
                I.declarar(c, vista(dos), vista(tv));
                anadir(salida, $"{quien}\t{dos}\t{tv}");
            }
            var k = 1;
            while k < largo(n.hijos) {
                recorrer(n.hijos[k], c, quien, salida);
                k = k + 1;
            }
            I.cerrar(c);
        }
        return;
    }

    if igual(clase, "bloque") {
        I.abrir(c);
        for h en n.hijos { recorrer(h, c, quien, salida); }
        I.cerrar(c);
        return;
    }

    for h en n.hijos { recorrer(h, c, quien, salida); }
}

// El tipo de lo que sale al recorrer una coleccion.
// Una generica no se comprueba tal cual: el comprobador de Python trabaja
// sobre una copia por cada juego de tipos, asi que no hay nada que comparar.
fn es_generica(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if igual(vista(h.clase), "tipo_param") { return true; }
    }
    return false;
}

fn try_partir(texto: view) -> lista<str> {
    var salida: lista<str> = [];
    var desde = 0;
    var i = 0;
    while i <= largo(texto) {
        var corta = false;
        if i == largo(texto) { corta = true; }
        else { corta = byte(texto, i) == 44; }
        if corta {
            let t = recortar(rebanar(texto, desde, i));
            if largo(t) > 0 { anadir(salida, nuevo(t)); }
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

// El tipo del valor de un mapa, para `for clave, valor en m`.
fn valor_de(t: view) -> str {
    if empieza_con(t, "mapa<") {
        let partes = partir_angulos(t);
        if largo(partes) == 2 { return copiar(partes[1]); }
    }
    return vacio();
}

fn elemento_de(crudo: view) -> str {
    // Recorrer algo prestado es recorrer lo que presta.
    let sin = quitar_prestamo(crudo);
    return elemento_de_bruto(vista(sin));
}

fn quitar_prestamo(t: view) -> str {
    if empieza_con(t, "&mut ") { return nuevo(rebanar(t, 5, largo(t))); }
    if empieza_con(t, "&") { return nuevo(rebanar(t, 1, largo(t))); }
    return nuevo(t);
}

fn elemento_de_bruto(t: view) -> str {
    if empieza_con(t, "mapa<") {
        let partes = partir_angulos(t);
        if largo(partes) == 2 { return copiar(partes[0]); }
        return vacio();
    }
    if empieza_con(t, "lista<") || empieza_con(t, "bloque<") {
        return dentro_angulos(t);
    }
    if empieza_con(t, "[") {
        var i = 1;
        while i < largo(t) {
            if byte(t, i) == 59 { return nuevo(rebanar(t, 1, i)); }
            i = i + 1;
        }
    }
    return vacio();
}

fn dentro_angulos(t: view) -> str {
    var desde = 0;
    while desde < largo(t) {
        if byte(t, desde) == 60 { break; }
        desde = desde + 1;
    }
    if desde >= largo(t) { return vacio(); }
    return nuevo(rebanar(t, desde + 1, largo(t) - 1));
}

fn partir_angulos(t: view) -> lista<str> {
    let dentro = dentro_angulos(t);
    var salida: lista<str> = [];
    var hondura = 0;
    var desde = 0;
    var i = 0;
    while i <= largo(vista(dentro)) {
        var corta = false;
        if i == largo(vista(dentro)) {
            corta = true;
        } else {
            let b = byte(vista(dentro), i);
            if b == 60 || b == 91 { hondura = hondura + 1; }
            if b == 62 || b == 93 { hondura = hondura - 1; }
            if b == 44 && hondura == 0 { corta = true; }
        }
        if corta {
            let trozo = recortar(rebanar(vista(dentro), desde, i));
            if largo(trozo) > 0 { anadir(salida, nuevo(trozo)); }
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

// Lo que declaran los modulos que trae un `usar`. El comprobador de Python
// lo recibe del cargador; aqui se leen las dependencias directas, igual que
// hace el parser con los nombres de struct.
fn recoger_de_usados(ruta: view, toks: &lista<Token>, c: mut I.Contexto) {
    let dir = carpeta(ruta);
    var i = 0;
    while i + 1 < largo(toks) {
        if igual(toks[i].valor, "usar") {
            if igual(toks[i + 1].tipo, "cadena") {
                let pedido = nuevo(toks[i + 1].valor);
                var candidatos: lista<str> = [];
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

                for cand en candidatos {
                    let texto = leer_archivo(vista(cand)) sino vacio();
                    if largo(texto) > 0 {
                        mirar_modulo(vista(cand), vista(texto), c);
                        break;
                    }
                }
            }
        }
        i = i + 1;
    }
}

fn mirar_modulo(ruta: view, texto: view, c: mut I.Contexto) {
    let toks = analizar(texto) sino [];
    if largo(toks) == 0 { return; }
    let nombres = P.structs_visibles(ruta, toks);
    let sin_alias: mapa<str, usize> = [];
    var e = P.Estado { toks: toks, i: 0, alias: sin_alias, structs: nombres };
    let arbol = programa_o_vacio(e);
    recoger_declaraciones(arbol, c);
    // Y lo que ese modulo trae a su vez, una vuelta mas.
    recoger_de_usados(ruta, e.toks, c);
}

fn programa_o_vacio(e: mut P.Estado) -> P.Nodo {
    return P.programa(e) sino P.hoja("programa", "", 0);
}

fn carpeta(ruta: view) -> str {
    var corte = 0;
    var i = 0;
    while i < largo(ruta) {
        if byte(ruta, i) == 47 { corte = i; }
        i = i + 1;
    }
    return nuevo(rebanar(ruta, 0, corte));
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t>\n");
        return 1;
    }

    let fuente = try leer_archivo(argumento(1));
    let tokens = try analizar(vista(fuente));
    let nombres = P.structs_visibles(argumento(1), tokens);
    let sin_alias: mapa<str, usize> = [];
    var estado = P.Estado { toks: tokens, i: 0, alias: sin_alias,
        structs: nombres };
    let arbol = try P.programa(estado);

    var c = I.contexto();
    recoger_de_usados(argumento(1), estado.toks, c);
    recoger_declaraciones(arbol, c);

    var salida: lista<str> = [];
    for d en arbol.hijos {
        if igual(vista(d.clase), "fn") && !es_generica(d) {
            I.abrir(c);
            let quien = nuevo(vista(d.texto));
            for h en d.hijos {
                if igual(vista(h.clase), "param") {
                    let pn = nombre_de(vista(h.texto));
                    let pt = tipo_desnudo(vista(h.texto));
                    I.declarar(c, vista(pn), vista(pt));
                    anadir(salida, $"{quien}\t{pn}\t{pt}");
                }
            }
            for h en d.hijos {
                if igual(vista(h.clase), "bloque") {
                    recorrer(h, c, vista(quien), salida);
                }
            }
            I.cerrar(c);
        }
    }

    for l en salida { imprimir($"{l}\n"); }
    return 0;
}
