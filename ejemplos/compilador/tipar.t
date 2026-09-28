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
usar "../lexer/lib/clase.t";

// De `nombre: &lista<str>` saca `nombre` y `lista<str>`: el prestamo se
// guarda aparte, igual que en el comprobador de Python.
fn nombre_de(texto: view) -> str {
    var i = 0;
    while i < texto.largo() {
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
    while i <= t.largo() {
        var corta = true;
        if i < t.largo() { corta = !de_nombre(byte(t, i)); }
        if corta {
            if i > desde {
                inicio_nombre = salida.largo();
                salida.empujar(rebanar(t, desde, i));
            }
            if i < t.largo() {
                if byte(t, i) == 46 {
                    salida = nuevo(rebanar(salida, 0, inicio_nombre));
                } else {
                    salida.empujar(rebanar(t, i, i + 1));
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
    while i + 1 < texto.largo() {
        if byte(texto, i) == 58 {
            if byte(texto, i + 1) == 32 {
                return nuevo(recortar(rebanar(texto, i + 2, texto.largo())));
            }
        }
        i = i + 1;
    }
    return vacio();
}

fn tipo_desnudo(texto: view) -> str {
    var i = 0;
    while i + 1 < texto.largo() {
        if byte(texto, i) == 58 {
            if byte(texto, i + 1) == 32 {
                let t = recortar(rebanar(texto, i + 2, texto.largo()));
                if empieza_con(t, "mut ") {
                    return sin_alias_de_modulo(rebanar(t, 4, t.largo()));
                }
                if empieza_con(t, "&mut ") {
                    return sin_alias_de_modulo(rebanar(t, 5, t.largo()));
                }
                if empieza_con(t, "&") {
                    return sin_alias_de_modulo(rebanar(t, 1, t.largo()));
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
    return nombre_de(sin_clave);
}

fn tras_espacio(texto: view) -> str {
    var i = 0;
    while i < texto.largo() {
        if byte(texto, i) == 32 {
            return nuevo(rebanar(texto, i + 1, texto.largo()));
        }
        i = i + 1;
    }
    return nuevo(texto);
}

fn recoger_declaraciones(n: &P.Nodo, c: mut I.Contexto) {
    match n.clase {
        Clase.Struct -> {
            var tipos: lista<str> = [];
            var nombres: lista<str> = [];
            for h en n.hijos {
                if h.clase == Clase.CampoDef {
                    nombres.anadir(nombre_de(h.texto));
                    let tipo_campo = tipo_desnudo(h.texto);
                    tipos.anadir(I.sin_alias_tipo(tipo_campo));
                }
            }
            poner(c.campos, vista(n.texto), tipos);
            poner(c.nombres, vista(n.texto), nombres);
            // Un struct generico: sus parametros, para leer `Par<str, usize>`.
            var sueltos: lista<str> = [];
            for h en n.hijos {
                if h.clase == Clase.TipoParam { sueltos.anadir(nuevo(h.texto)); }
            }
            if sueltos.largo() > 0 { poner(c.struct_params, vista(n.texto), sueltos); }
        }
        Clase.Enum -> {
            var cuales: lista<str> = [];
            for h en n.hijos {
                if h.clase == Clase.Variante {
                    cuales.anadir(nuevo(h.texto));
                    var lleva: lista<str> = [];
                    for x en h.hijos {
                        if x.clase == Clase.Lleva {
                            lleva.anadir(nuevo(x.texto));
                        }
                    }
                    var clave = nuevo(n.texto);
                    clave.empujar(".");
                    clave.empujar(h.texto);
                    poner(c.formas, vista(clave), lleva);
                }
            }
            poner(c.variantes, vista(n.texto), cuales);
        }
        Clase.Fn -> {
            var retorno = vacio();
            var es_de_c = false;
            var sueltos: lista<str> = [];
            var tipos_param: lista<str> = [];
            var marcados: lista<str> = [];
            for h en n.hijos {
                if h.clase == Clase.RetornoTipo {
                    retorno = I.sin_alias_tipo(h.texto);
                }
                // Una firma de `externo` no tiene cuerpo, y `cadena_c` solo
                // existe en el borde: lo que ve Tcode es un `str` suyo.
                if h.clase == Clase.Externa { es_de_c = true; }
                if h.clase == Clase.TipoParam {
                    sueltos.anadir(nuevo(h.texto));
                }
                if h.clase == Clase.Param {
                    let tipo_param = tipo_desnudo(h.texto);
                    tipos_param.anadir(I.sin_alias_tipo(tipo_param));
                    let con_marca = tipo_con_marca(h.texto);
                    marcados.anadir(I.sin_alias_tipo(con_marca));
                }
            }
            if es_de_c {
                poner(c.externas, vista(n.texto), 1);
                if retorno == "cadena_c" { retorno = nuevo("str"); }
                // Una funcion de C presta lo que recibe: no se queda con nada.
                var prestados: lista<str> = [];
                for _m en marcados { prestados.anadir(nuevo("&")); }
                marcados = prestados;
            }
            poner(c.retornos, vista(n.texto), retorno);
            poner(c.params, vista(n.texto), tipos_param);
            poner(c.params_marcados, vista(n.texto), marcados);
            if sueltos.largo() > 0 {
                poner(c.tipo_params, vista(n.texto), sueltos);
            }
        }
        _ -> { }
    }
    for h en n.hijos { recoger_declaraciones(h, c); }
}

// Recorre un cuerpo declarando lo que vaya apareciendo, y va apuntando cada
// variable con su tipo en el orden en que se declara.
fn recorrer(n: &P.Nodo, c: mut I.Contexto, quien: view, salida: mut lista<str>,
    lineas: mut lista<usize>) {
    let clase = n.clase;

    match clase {
        Clase.Declaracion -> {
            // Primero el valor, que se lee en el ambito de antes.
            var tipo = vacio();
            let escrito = tipo_desnudo(n.texto);
            if escrito.largo() > 0 {
                tipo = escrito;
            } else {
                if n.hijos.largo() > 0 { tipo = I.tipo_de(c, n.hijos[0]); }
            }
            for h en n.hijos { recorrer(h, c, quien, salida, lineas); }
            let nombre = nombre_declarado(n.texto);
            I.declarar(c, nombre, tipo);
            salida.anadir($"{quien}\t{nombre}\t{tipo}");
            // Cada fila lleva su linea, en la misma posicion: la propiedad las
            // empareja por el indice. Sin esta, un `for` posterior dejaba su
            // linea en el hueco de la declaracion, y la variable parecia
            // declarada despues de usarse.
            lineas.anadir(n.linea);
            return;
        }
        Clase.Para -> {
            // `for x en xs`: la variable toma el tipo del elemento.
            if n.hijos.largo() > 0 {
                let sobre = I.tipo_de(c, n.hijos[0]);
                let base = elemento_de(sobre);
                I.abrir(c);
                let partes = try_partir(n.texto);
                let uno = copiar(partes[0]);
                I.declarar(c, uno, base);
                salida.anadir($"{quien}\t{uno}\t{base}");
                lineas.anadir(n.linea);
                if partes.largo() > 1 {
                    // `for clave, valor en mapa`: la segunda es el valor.
                    let dos = copiar(partes[1]);
                    let tv = valor_de(sobre);
                    I.declarar(c, dos, tv);
                    salida.anadir($"{quien}\t{dos}\t{tv}");
                    lineas.anadir(n.linea);
                }
                var k = 1;
                while k < n.hijos.largo() {
                    recorrer(n.hijos[k], c, quien, salida, lineas);
                    k = k + 1;
                }
                I.cerrar(c);
            }
            return;
        }
        Clase.Match -> {
            // Lo que atrapa cada patron vive solo dentro de su brazo, y se
            // presta: `Json.Texto(s)` da una `view`, no un `str` que soltar.
            for h en n.hijos {
                if h.clase != Clase.Brazo { continue; }
                I.abrir(c);
                atrapar(h, c, quien, salida, lineas);
                for x en h.hijos {
                    let xc = x.clase;
                    if xc != Clase.Atrapa && xc != Clase.Patron && xc != Clase.Literal {
                        recorrer(x, c, quien, salida, lineas);
                    }
                }
                I.cerrar(c);
            }
            return;
        }
        Clase.Bloque -> {
            I.abrir(c);
            for h en n.hijos { recorrer(h, c, quien, salida, lineas); }
            I.cerrar(c);
            return;
        }
        _ -> { }
    }

    for h en n.hijos { recorrer(h, c, quien, salida, lineas); }
}

// El tipo de lo que sale al recorrer una coleccion.
// Una generica no se comprueba tal cual: el comprobador de Python trabaja
// sobre una copia por cada juego de tipos, asi que no hay nada que comparar.
fn es_generica(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if h.clase == Clase.TipoParam { return true; }
    }
    return false;
}

// Donde empiezan las lineas de esta funcion dentro de `salida`.
fn primera_de(salida: &lista<str>, quien: view) -> usize {
    var i = 0;
    while i < salida.largo() {
        if empieza_con(salida[i], quien) { return i; }
        i = i + 1;
    }
    return salida.largo();
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
    // Una referencia declarada normalmente (`let x = obtener(...)`) queda
    // prestada. La que introduce un patron de `match`, en cambio, es solo la
    // vista tipada que el patron expone y Python no la marca como recibida.
    // La linea forma parte de la clave para no confundir nombres repetidos.
    var atrapadas: mapa<str, usize> = [];
    recoger_atrapadas(d, atrapadas);
    var prestados: mapa<str, usize> = [];
    for h en d.hijos {
        if h.clase == Clase.Param {
            let marca = tipo_con_marca(h.texto);
            if empieza_con(marca, "&") || empieza_con(marca, "mut ") {
                let pn = nombre_de(h.texto);
                poner(prestados, vista(pn), 1);
            }
        }
    }

    var vs: lista<Q.Vigilada> = [];
    var mias: lista<usize> = [];
    var i = desde;
    while i < salida.largo() {
        let partes = partir_por_tab(salida[i]);
        if partes.largo() == 3 {
            if igual(partes[0], quien) {
                let nom = copiar(partes[1]);
                let tip = copiar(partes[2]);
                // Prestada si llego como parametro prestado, o si es la
                // variable de un `for`: recorrer es mirar lo que hay, no
                // sacarlo, y eso vale igual para un numero que para un
                // `str`. Que el elemento tenga duenio o no cambia como se
                // pasa, no de quien es.
                var donde = 0;
                if i < lineas.largo() { donde = lineas[i]; }
                var prestada = tiene(prestados, nom);
                let clave = $"{nom}\t{donde}";
                let es_ref = empieza_con(tip, "&")
                || empieza_con(tip, "mut ");
                if es_ref && !tiene(atrapadas, clave) {
                    prestada = true;
                }
                if tiene(de_bucle, clave) { prestada = true; }
                if tiene(valores_de_bucle, clave)
                && Q.tiene_duenio(c, vista(tip)) {
                    prestada = true;
                }
                vs.anadir(Q.vigilar(nom, tip, prestada, donde));
                mias.anadir(i);
            }
        }
        i = i + 1;
    }

    for h en d.hijos {
        if h.clase == Clase.Bloque { Q.mirar(c, h, vs); }
    }

    var k = 0;
    while k < mias.largo() {
        let dest = Q.destino_de(c, vs[k]);
        var nueva = copiar(salida[mias[k]]);
        nueva.empujar("\t");
        nueva.empujar(dest);
        salida[mias[k]] = nueva;
        k = k + 1;
    }
}

// Lo que atrapa un patron, tambien dentro de una forma anidada: `n` es el
// brazo o la rama `patron`, con la forma en su texto. `_` no atrapa nada.
fn atrapar(n: &P.Nodo, c: mut I.Contexto, quien: view, salida: mut lista<str>,
    lineas: mut lista<usize>) {
    let lleva = I.lista_de(c.formas, vista(n.texto)) sino [];
    var k = 0;
    for x en n.hijos {
        let xc = x.clase;
        if xc != Clase.Atrapa && xc != Clase.Patron && xc != Clase.Literal { continue; }
        if xc == Clase.Patron {
            atrapar(x, c, quien, salida, lineas);
        } else if xc == Clase.Atrapa && x.texto != "_" {
            var t = vacio();
            if k < lleva.largo() { t = I.tipo_atrapado(c, lleva[k]); }
            I.declarar(c, x.texto, t);
            salida.anadir($"{quien}\t{x.texto}\t{t}");
            lineas.anadir(x.linea);
        }
        k = k + 1;
    }
}

// Variables que nacen al desarmar visualmente una variante. El `match` no
// mueve esos valores fuera del enum: solo les da nombre dentro del brazo.
fn recoger_atrapadas(n: &P.Nodo, salida: mut mapa<str, usize>) {
    if n.clase == Clase.Atrapa && n.texto != "_" {
        poner(salida, $"{n.texto}\t{n.linea}", 1);
    }
    for h en n.hijos { recoger_atrapadas(h, salida); }
}

// Las declaraciones que introduce un `for`, identificadas por nombre y
// linea. Usar solo el nombre convertia tambien en prestada cualquier variable
// homonima de otro bloque. El primero —el elemento o la clave— se presta
// siempre; el segundo —el valor de un mapa— llega por copia si es escalar, y
// prestado si tiene duenio.
fn recoger_bucles(n: &P.Nodo, primeros: mut mapa<str, usize>,
    segundos: mut mapa<str, usize>) {
    if n.clase == Clase.Para {
        let partes = try_partir(n.texto);
        var i = 0;
        for parte en partes {
            let clave = $"{parte}\t{n.linea}";
            if i == 0 { poner(primeros, vista(clave), 1); }
            else { poner(segundos, vista(clave), 1); }
            i = i + 1;
        }
    }
    for h en n.hijos { recoger_bucles(h, primeros, segundos); }
}

fn ya_esta(vs: &lista<Q.Vigilada>, nombre: view) -> bool {
    for v en vs {
        if igual(v.nombre, nombre) { return true; }
    }
    return false;
}

fn destino_para(c: &I.Contexto, vs: &lista<Q.Vigilada>, nombre: view) -> str {
    for v en vs {
        if igual(v.nombre, nombre) { return Q.destino_de(c, v); }
    }
    return nuevo("nada");
}

fn partir_por_tab(l: view) -> lista<str> {
    var salida: lista<str> = [];
    var desde = 0;
    var i = 0;
    while i <= l.largo() {
        var corta = false;
        if i == l.largo() { corta = true; }
        else { corta = byte(l, i) == 9; }
        if corta {
            salida.anadir(nuevo(rebanar(l, desde, i)));
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
    while i <= texto.largo() {
        var corta = false;
        if i == texto.largo() { corta = true; }
        else { corta = byte(texto, i) == 44; }
        if corta {
            let t = recortar(rebanar(texto, desde, i));
            if t.largo() > 0 { salida.anadir(nuevo(t)); }
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
        if partes.largo() == 2 { return copiar(partes[1]); }
    }
    return vacio();
}

fn elemento_de(crudo: view) -> str {
    // Recorrer algo prestado es recorrer lo que presta.
    let sin = quitar_prestamo(crudo);
    return elemento_de_bruto(sin);
}

fn quitar_prestamo(t: view) -> str {
    if empieza_con(t, "&mut ") { return nuevo(rebanar(t, 5, t.largo())); }
    if empieza_con(t, "&") { return nuevo(rebanar(t, 1, t.largo())); }
    return nuevo(t);
}

fn elemento_de_bruto(t: view) -> str {
    if empieza_con(t, "mapa<") {
        let partes = partir_angulos(t);
        if partes.largo() == 2 { return copiar(partes[0]); }
        return vacio();
    }
    if empieza_con(t, "lista<") || empieza_con(t, "bloque<") {
        return dentro_angulos(t);
    }
    if empieza_con(t, "[") {
        var i = 1;
        while i < t.largo() {
            if byte(t, i) == 59 { return nuevo(rebanar(t, 1, i)); }
            i = i + 1;
        }
    }
    return vacio();
}

fn dentro_angulos(t: view) -> str {
    var desde = 0;
    while desde < t.largo() {
        if byte(t, desde) == 60 { break; }
        desde = desde + 1;
    }
    if desde >= t.largo() { return vacio(); }
    return nuevo(rebanar(t, desde + 1, t.largo() - 1));
}

fn partir_angulos(t: view) -> lista<str> {
    let dentro = dentro_angulos(t);
    var salida: lista<str> = [];
    var hondura = 0;
    var desde = 0;
    var i = 0;
    while i <= dentro.largo() {
        var corta = false;
        if i == dentro.largo() {
            corta = true;
        } else {
            let b = byte(dentro, i);
            if b == 60 || b == 91 { hondura = hondura + 1; }
            if b == 62 || b == 93 { hondura = hondura - 1; }
            if b == 44 && hondura == 0 { corta = true; }
        }
        if corta {
            let trozo = recortar(rebanar(dentro, desde, i));
            if trozo.largo() > 0 { salida.anadir(nuevo(trozo)); }
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
    while i + 1 < toks.largo() {
        if toks[i].valor == "usar" {
            if toks[i + 1].tipo == "cadena" {
                let pedido = nuevo(toks[i + 1].valor);
                var candidatos: lista<str> = [];
                var junto = nuevo(dir);
                if junto.largo() > 0 { junto.empujar("/"); }
                junto.empujar(pedido);
                candidatos.anadir(copiar(junto));
                junto.empujar(".t");
                candidatos.anadir(junto);
                candidatos.anadir(copiar(pedido));
                var suelto = copiar(pedido);
                suelto.empujar(".t");
                candidatos.anadir(suelto);

                for cand en candidatos {
                    let texto = leer_archivo(cand) sino vacio();
                    if texto.largo() > 0 {
                        mirar_modulo(cand, texto, c);
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
    if toks.largo() == 0 { return; }
    let nombres = P.structs_visibles(ruta, toks);
    let formas = P.enums_visibles(ruta, toks);
    var e = P.estado_de(toks, ruta, nombres, formas);
    let arbol = programa_o_vacio(e);
    recoger_declaraciones(arbol, c);
    // Y lo que ese modulo trae a su vez, una vuelta mas.
    recoger_de_usados(ruta, e.toks, c);
}

fn programa_o_vacio(e: mut P.Estado) -> P.Nodo {
    return P.programa(e) sino P.hoja(Clase.Programa, "", 0);
}

fn carpeta(ruta: view) -> str {
    var corte = 0;
    var i = 0;
    while i < ruta.largo() {
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
        con_propiedad = argumento(2) == "--propiedad";
    }

    let fuente = try leer_archivo(argumento(1));
    let tokens = try analizar(fuente);
    let nombres = P.structs_visibles(argumento(1), tokens);
    let formas = P.enums_visibles(argumento(1), tokens);
    var estado = P.estado_de(tokens, argumento(1), nombres, formas);
    let arbol = try P.programa(estado);

    var c = I.contexto();
    recoger_de_usados(argumento(1), estado.toks, c);
    recoger_declaraciones(arbol, c);

    var salida: lista<str> = [];
    var lineas: lista<usize> = [];
    for d en arbol.hijos {
        if d.clase == Clase.Fn && !es_generica(d) {
            I.abrir(c);
            let quien = nuevo(d.texto);
            for h en d.hijos {
                if h.clase == Clase.Param {
                    let pn = nombre_de(h.texto);
                    let pt = tipo_desnudo(h.texto);
                    I.declarar(c, pn, pt);
                    salida.anadir($"{quien}\t{pn}\t{pt}");
                    lineas.anadir(d.linea);
                }
            }
            for h en d.hijos {
                if h.clase == Clase.Bloque {
                    recorrer(h, c, quien, salida, lineas);
                }
            }
            if con_propiedad {
                anotar_propiedad(c, d, vista(quien), salida, lineas,
                    primera_de(salida, quien));
            }
            I.cerrar(c);
        }
    }

    // El tipo se dice como el comprobador: `Par<str, usize>` es
    // `Par__str_usize`. Solo al escribir, que la propiedad lee el escrito.
    for l en salida {
        let partes = partir_por_tab(l);
        var fila = vacio();
        var k = 0;
        while k < partes.largo() {
            if k > 0 { fila.empujar("\t"); }
            if k == 2 {
                let r = I.nombre_resuelto(partes[k]);
                fila.empujar(r);
            } else {
                fila.empujar(partes[k]);
            }
            k = k + 1;
        }
        imprimir($"{fila}\n");
    }
    return 0;
}
