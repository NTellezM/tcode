// tipar.t — el tipo de cada variable de cada funcion, dicho por Tcode.
//
// Recorre un `.t` con el parser de Tcode, va declarando lo que encuentra y
// dice de que tipo es cada cosa. La suite corre esto y el comprobador de
// Python sobre los mismos archivos y compara linea a linea.
//
//     ./tipar std/texto.t

usar "lib/tipar.t" como I;
usar "lib/propiedad.t" como Q;
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

// `P.Nodo` es `Nodo`, y `lista<P.Nodo>` es `lista<Nodo>`: el nombre del
// modulo no forma parte del tipo, este donde este.
fn sin_alias_de_modulo(t: view) -> str {
    var salida = vacio();
    // Donde empieza el ultimo nombre escrito: si detras viene un punto, ese
    // nombre era el del modulo y se borra.
    var inicio_nombre = 0;
    var desde = 0;
    var i = 0;
    while i <= largo(t) {
        var corta = true;
        if i < largo(t) { corta = !de_nombre(byte(t, i)); }
        if corta {
            if i > desde {
                inicio_nombre = largo(vista(salida));
                empujar(salida, rebanar(t, desde, i));
            }
            if i < largo(t) {
                if byte(t, i) == 46 {
                    salida = nuevo(rebanar(vista(salida), 0, inicio_nombre));
                } else {
                    empujar(salida, rebanar(t, i, i + 1));
                }
            }
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
}

fn de_nombre(b: usize) -> bool {
    if b >= 97 && b <= 122 { return true; }
    if b >= 65 && b <= 90 { return true; }
    if b >= 48 && b <= 57 { return true; }
    return b == 95;
}

// Como `tipo_desnudo` pero conservando la marca: `&Cosa`, `mut lista<str>`.
// Sirve para saber si una llamada se queda con lo que le dan.
fn tipo_con_marca(texto: view) -> str {
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
                let tipo_campo = tipo_desnudo(vista(h.texto));
                anadir(tipos, I.sin_alias_tipo(vista(tipo_campo)));
            }
        }
        poner(c.campos, vista(n.texto), tipos);
        poner(c.nombres, vista(n.texto), nombres);
    }
    if igual(vista(n.clase), "enum") {
        var cuales: lista<str> = [];
        for h en n.hijos {
            if igual(vista(h.clase), "variante") {
                anadir(cuales, nuevo(vista(h.texto)));
                var lleva: lista<str> = [];
                for x en h.hijos {
                    if igual(vista(x.clase), "lleva") {
                        anadir(lleva, nuevo(vista(x.texto)));
                    }
                }
                var clave = nuevo(vista(n.texto));
                empujar(clave, ".");
                empujar(clave, vista(h.texto));
                poner(c.formas, vista(clave), lleva);
            }
        }
        poner(c.variantes, vista(n.texto), cuales);
    }
    if igual(vista(n.clase), "fn") {
        var retorno = vacio();
        var es_de_c = false;
        var sueltos: lista<str> = [];
        var tipos_param: lista<str> = [];
        var marcados: lista<str> = [];
        for h en n.hijos {
            if igual(vista(h.clase), "retorno_tipo") {
                retorno = I.sin_alias_tipo(vista(h.texto));
            }
            // Una firma de `externo` no tiene cuerpo, y `cadena_c` solo
            // existe en el borde: lo que ve Tcode es un `str` suyo.
            if igual(vista(h.clase), "externa") { es_de_c = true; }
            if igual(vista(h.clase), "tipo_param") {
                anadir(sueltos, nuevo(vista(h.texto)));
            }
            if igual(vista(h.clase), "param") {
                let tipo_param = tipo_desnudo(vista(h.texto));
                anadir(tipos_param, I.sin_alias_tipo(vista(tipo_param)));
                let con_marca = tipo_con_marca(vista(h.texto));
                anadir(marcados, I.sin_alias_tipo(vista(con_marca)));
            }
        }
        if es_de_c {
            poner(c.externas, vista(n.texto), 1);
            if igual(vista(retorno), "cadena_c") { retorno = nuevo("str"); }
            // Una funcion de C presta lo que recibe: no se queda con nada.
            var prestados: lista<str> = [];
            for _m en marcados { anadir(prestados, nuevo("&")); }
            marcados = prestados;
        }
        poner(c.retornos, vista(n.texto), retorno);
        poner(c.params, vista(n.texto), tipos_param);
        poner(c.params_marcados, vista(n.texto), marcados);
        if largo(sueltos) > 0 {
            poner(c.tipo_params, vista(n.texto), sueltos);
        }
    }
    for h en n.hijos { recoger_declaraciones(h, c); }
}

// Recorre un cuerpo declarando lo que vaya apareciendo, y va apuntando cada
// variable con su tipo en el orden en que se declara.
fn recorrer(n: &P.Nodo, c: mut I.Contexto, quien: view, salida: mut lista<str>,
    lineas: mut lista<usize>) {
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
        for h en n.hijos { recorrer(h, c, quien, salida, lineas); }
        let nombre = nombre_declarado(vista(n.texto));
        I.declarar(c, vista(nombre), vista(tipo));
        anadir(salida, $"{quien}\t{nombre}\t{tipo}");
        // Cada fila lleva su linea, en la misma posicion: la propiedad las
        // empareja por el indice. Sin esta, un `for` posterior dejaba su
        // linea en el hueco de la declaracion, y la variable parecia
        // declarada despues de usarse.
        anadir(lineas, n.linea);
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
            anadir(lineas, n.linea);
            if largo(partes) > 1 {
                // `for clave, valor en mapa`: la segunda es el valor.
                let dos = copiar(partes[1]);
                let tv = valor_de(vista(sobre));
                I.declarar(c, vista(dos), vista(tv));
                anadir(salida, $"{quien}\t{dos}\t{tv}");
                anadir(lineas, n.linea);
            }
            var k = 1;
            while k < largo(n.hijos) {
                recorrer(n.hijos[k], c, quien, salida, lineas);
                k = k + 1;
            }
            I.cerrar(c);
        }
        return;
    }

    if igual(clase, "match") {
        // Lo que atrapa cada patron vive solo dentro de su brazo, y se
        // presta: `Json.Texto(s)` da una `view`, no un `str` que soltar.
        for h en n.hijos {
            if !igual(vista(h.clase), "brazo") { continue; }
            I.abrir(c);
            let lleva = I.lista_de(c.formas, vista(h.texto)) sino [];
            var k = 0;
            for x en h.hijos {
                if igual(vista(x.clase), "atrapa") {
                    var t = vacio();
                    if k < largo(lleva) {
                        t = I.tipo_atrapado(c, vista(lleva[k]));
                    }
                    I.declarar(c, vista(x.texto), vista(t));
                    anadir(salida, $"{quien}\t{x.texto}\t{t}");
                    anadir(lineas, x.linea);
                    k = k + 1;
                }
            }
            for x en h.hijos {
                if !igual(vista(x.clase), "atrapa") {
                    recorrer(x, c, quien, salida, lineas);
                }
            }
            I.cerrar(c);
        }
        return;
    }

    if igual(clase, "bloque") {
        I.abrir(c);
        for h en n.hijos { recorrer(h, c, quien, salida, lineas); }
        I.cerrar(c);
        return;
    }

    for h en n.hijos { recorrer(h, c, quien, salida, lineas); }
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

// Donde empiezan las lineas de esta funcion dentro de `salida`.
fn primera_de(salida: &lista<str>, quien: view) -> usize {
    var i = 0;
    while i < largo(salida) {
        if empieza_con(vista(salida[i]), quien) { return i; }
        i = i + 1;
    }
    return largo(salida);
}

// Recorre la funcion otra vez, ahora buscando quien entrega y quien mueve, y
// le pega a cada linea ya escrita su destino.
fn anotar_propiedad(c: &I.Contexto, d: &P.Nodo, quien: view,
    salida: mut lista<str>, lineas: &lista<usize>, desde: usize) {
    // Una por cada linea ya escrita, en el mismo orden. Asi dos variables
    // con el mismo nombre en bloques distintos siguen siendo dos: juntarlas
    // por el nombre daria el destino de una a la otra.
    var de_bucle: mapa<str, usize> = [];
    var valores_de_bucle: mapa<str, usize> = [];
    recoger_bucles(d, de_bucle, valores_de_bucle);
    var prestados: mapa<str, usize> = [];
    for h en d.hijos {
        if igual(vista(h.clase), "param") {
            let marca = tipo_con_marca(vista(h.texto));
            if empieza_con(vista(marca), "&") || empieza_con(vista(marca), "mut ") {
                let pn = nombre_de(vista(h.texto));
                poner(prestados, vista(pn), 1);
            }
        }
    }

    var vs: lista<Q.Vigilada> = [];
    var mias: lista<usize> = [];
    var i = desde;
    while i < largo(salida) {
        let partes = partir_por_tab(vista(salida[i]));
        if largo(partes) == 3 {
            if igual(vista(partes[0]), quien) {
                let nom = copiar(partes[1]);
                let tip = copiar(partes[2]);
                // Prestada si llego como parametro prestado, o si es la
                // variable de un `for`: recorrer es mirar lo que hay, no
                // sacarlo, y eso vale igual para un numero que para un
                // `str`. Que el elemento tenga duenio o no cambia como se
                // pasa, no de quien es.
                var prestada = tiene(prestados, vista(nom));
                if tiene(de_bucle, vista(nom)) { prestada = true; }
                if tiene(valores_de_bucle, vista(nom))
                && Q.tiene_duenio(c, vista(tip)) {
                    prestada = true;
                }
                var donde = 0;
                if i < largo(lineas) { donde = lineas[i]; }
                anadir(vs, Q.vigilar(vista(nom), vista(tip), prestada, donde));
                anadir(mias, i);
            }
        }
        i = i + 1;
    }

    for h en d.hijos {
        if igual(vista(h.clase), "bloque") { Q.mirar(c, h, vs); }
    }

    var k = 0;
    while k < largo(mias) {
        let dest = Q.destino_de(c, vs[k]);
        var nueva = copiar(salida[mias[k]]);
        empujar(nueva, "\t");
        empujar(nueva, vista(dest));
        salida[mias[k]] = nueva;
        k = k + 1;
    }
}

// Los nombres que declara un `for`, y en que sitio. El primero —el elemento
// o la clave— se presta siempre: recorrer es mirar lo que hay. El segundo
// —el valor de un mapa— llega por copia si es un escalar, y prestado si
// tiene duenio, igual que cualquier otro valor.
fn recoger_bucles(n: &P.Nodo, primeros: mut mapa<str, usize>,
    segundos: mut mapa<str, usize>) {
    if igual(vista(n.clase), "para") {
        let partes = try_partir(vista(n.texto));
        var i = 0;
        for parte en partes {
            if i == 0 { poner(primeros, vista(parte), 1); }
            else { poner(segundos, vista(parte), 1); }
            i = i + 1;
        }
    }
    for h en n.hijos { recoger_bucles(h, primeros, segundos); }
}

fn ya_esta(vs: &lista<Q.Vigilada>, nombre: view) -> bool {
    for v en vs {
        if igual(vista(v.nombre), nombre) { return true; }
    }
    return false;
}

fn destino_para(c: &I.Contexto, vs: &lista<Q.Vigilada>, nombre: view) -> str {
    for v en vs {
        if igual(vista(v.nombre), nombre) { return Q.destino_de(c, v); }
    }
    return nuevo("nada");
}

fn partir_por_tab(l: view) -> lista<str> {
    var salida: lista<str> = [];
    var desde = 0;
    var i = 0;
    while i <= largo(l) {
        var corta = false;
        if i == largo(l) { corta = true; }
        else { corta = byte(l, i) == 9; }
        if corta {
            anadir(salida, nuevo(rebanar(l, desde, i)));
            desde = i + 1;
        }
        i = i + 1;
    }
    return salida;
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
    let formas = P.enums_visibles(ruta, toks);
    let sin_alias: mapa<str, usize> = [];
    var e = P.Estado { toks: toks, i: 0, alias: sin_alias, structs: nombres, enums: formas };
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

    // Con `--propiedad` dice ademas que le pasa a cada valor con duenio.
    var con_propiedad = false;
    if n_argumentos() > 2 {
        con_propiedad = igual(argumento(2), "--propiedad");
    }

    let fuente = try leer_archivo(argumento(1));
    let tokens = try analizar(vista(fuente));
    let nombres = P.structs_visibles(argumento(1), tokens);
    let formas = P.enums_visibles(argumento(1), tokens);
    let sin_alias: mapa<str, usize> = [];
    var estado = P.Estado { toks: tokens, i: 0, alias: sin_alias,
        structs: nombres, enums: formas };
    let arbol = try P.programa(estado);

    var c = I.contexto();
    recoger_de_usados(argumento(1), estado.toks, c);
    recoger_declaraciones(arbol, c);

    var salida: lista<str> = [];
    var lineas: lista<usize> = [];
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
                    anadir(lineas, d.linea);
                }
            }
            for h en d.hijos {
                if igual(vista(h.clase), "bloque") {
                    recorrer(h, c, vista(quien), salida, lineas);
                }
            }
            if con_propiedad {
                anotar_propiedad(c, d, vista(quien), salida, lineas,
                    primera_de(salida, vista(quien)));
            }
            I.cerrar(c);
        }
    }

    for l en salida { imprimir($"{l}\n"); }
    return 0;
}
