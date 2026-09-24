// lib/propiedad.t — que le pasa a cada valor con duenio, escrito en Tcode.
//
// Quinta capa del compilador en su propio lenguaje. Las anteriores dicen que
// hay y de que tipo es; esta dice lo unico que de verdad separa a Tcode de C:
// quien es duenio de que memoria, y donde deja de serlo.
//
// Cada variable acaba en una de estas:
//
//     prestado   llego prestada: no se libera aqui, es de quien llama
//     presta     es una vista: no posee nada
//     nada       su tipo no tiene memoria detras
//     entrega:N  se devuelve en la linea N
//     mueve:N    pasa a ser de otro en la linea N
//     libera     se libera sola al cerrar su bloque
//
// Es la misma lista que el comprobador de Python sabe decir con `--explicar`,
// y la suite compara las dos sobre el codigo real del repositorio.

usar "tipar.t" como I;
usar "tipos.t" como T;
usar "../../lexer/lib/sintaxis.t" como P;
usar "std/texto";
usar "std/lista";

struct Hecho {
    funcion: str,
    nombre: str,
    destino: str,
}

// Lo que se sabe de una variable mientras se recorre su funcion.
struct Vigilada {
    nombre: str,
    tipo: str,
    prestado: bool,
    // Donde se declaro. Con dos del mismo nombre en bloques distintos, la
    // que manda en una linea es la ultima declarada antes de ella.
    declarada_en: usize,
    // 0 mientras no le pase nada.
    entregada_en: usize,
    movida_en: usize,
}

// Estado de las variables que ya eran visibles al entrar en una rama. Las
// declaradas dentro de ella no se fotografian: su destino pertenece a esa
// rama aunque esta termine y no alcance la continuacion.
struct Foto {
    indices: lista<usize>,
    movidas: lista<usize>,
    entregadas: lista<usize>,
}

fn vigilar(nombre: view, tipo: view, prestado: bool,
    declarada_en: usize) -> Vigilada {
    return Vigilada { nombre: nuevo(nombre), tipo: nuevo(tipo),
        prestado: prestado, declarada_en: declarada_en,
        entregada_en: 0, movida_en: 0 };
}

// El destino de una variable, una vez recorrida su funcion.
fn destino_de(c: &I.Contexto, v: &Vigilada) -> str {
    if igual(vista(v.tipo), "view") { return nuevo("presta"); }
    // `prestado` conserva el origen, no se deduce solo del tipo. Por ejemplo,
    // un patron de `match` puede exponer un `&lista<T>` sin que el informe lo
    // cuente como una variable recibida en prestamo.
    if v.prestado { return nuevo("prestado"); }
    if !tiene_duenio(c, vista(v.tipo)) { return nuevo("nada"); }
    if v.entregada_en > 0 {
        var s = nuevo("entrega:");
        empujar(s, texto(v.entregada_en));
        return s;
    }
    if v.movida_en > 0 {
        var s = nuevo("mueve:");
        empujar(s, texto(v.movida_en));
        return s;
    }
    return nuevo("libera");
}

fn tiene_duenio(c: &I.Contexto, t: view) -> bool {
    // No basta mirar campos de structs: un enum puede llevar un `str`, una
    // lista o cualquier otro dueño. `posee_con_formas` recorre ambas clases
    // y también sus aplicaciones genéricas.
    return I.posee_con_formas(c, t);
}

// ------------------------------------------------------------------
// Quien se queda con que
// ------------------------------------------------------------------

// El nombre de la variable si la expresion es exactamente una variable.
// Mover es entregar la variable entera: `f(x)` la mueve, `f(x.campo)` no.
fn variable_suelta(n: &P.Nodo) -> str {
    if igual(vista(n.clase), "variable") { return nuevo(vista(n.texto)); }
    if igual(vista(n.clase), "expresion") {
        if largo(n.hijos) == 1 { return variable_suelta(n.hijos[0]); }
    }
    return vacio();
}

// El tipo de una variable segun lo que se esta vigilando. El ambito del
// comprobador ya se cerro cuando llega este recorrido.
fn tipo_vigilado(vs: &lista<Vigilada>, nombre: view, linea: usize) -> str {
    let i = cual(vs, nombre, linea) sino largo(vs);
    if i >= largo(vs) { return vacio(); }
    return copiar(vs[i].tipo);
}

// Con dos variables del mismo nombre en bloques distintos, la que manda es
// la ultima declarada antes de esta linea: es la que tapa a la otra.
fn cual(vs: &lista<Vigilada>, nombre: view, linea: usize) -> usize ! {
    var i = largo(vs);
    while i > 0 {
        i = i - 1;
        if igual(vista(vs[i].nombre), nombre) {
            if vs[i].declarada_en <= linea { return i; }
        }
    }
    falla "no esta vigilada";
}

fn marcar_movida(vs: mut lista<Vigilada>, nombre: view, linea: usize) {
    if largo(nombre) == 0 { return; }
    let i = cual(vs, nombre, linea) sino largo(vs);
    if i >= largo(vs) { return; }
    if vs[i].movida_en == 0 && vs[i].entregada_en == 0 {
        vs[i].movida_en = linea;
    }
}

fn marcar_entregada(vs: mut lista<Vigilada>, nombre: view, linea: usize) {
    if largo(nombre) == 0 { return; }
    let i = cual(vs, nombre, linea) sino largo(vs);
    if i >= largo(vs) { return; }
    vs[i].entregada_en = linea;
}

fn fotografiar(vs: &lista<Vigilada>, antes_de: usize) -> Foto {
    var indices: lista<usize> = [];
    var movidas: lista<usize> = [];
    var entregadas: lista<usize> = [];
    var i = 0;
    while i < largo(vs) {
        if vs[i].declarada_en < antes_de {
            anadir(indices, i);
            anadir(movidas, vs[i].movida_en);
            anadir(entregadas, vs[i].entregada_en);
        }
        i = i + 1;
    }
    return Foto { indices: indices, movidas: movidas,
        entregadas: entregadas };
}

fn restaurar(vs: mut lista<Vigilada>, f: &Foto) {
    var i = 0;
    while i < largo(f.indices) {
        let k = f.indices[i];
        vs[k].movida_en = f.movidas[i];
        vs[k].entregada_en = f.entregadas[i];
        i = i + 1;
    }
}

// `return`, `falla`, `break` y `continue` hacen que este bloque no llegue al
// codigo posterior. Es la misma definicion directa que usa el comprobador de
// Python al juntar las dos ramas de un `if`.
fn termina(n: &P.Nodo) -> bool {
    if !igual(vista(n.clase), "bloque") || largo(n.hijos) == 0 {
        return false;
    }
    let clase = vista(n.hijos[largo(n.hijos) - 1].clase);
    return igual(clase, "retorno") || igual(clase, "falla")
    || igual(clase, "romper") || igual(clase, "continuar");
}

fn unir_ramas(vs: mut lista<Vigilada>, a: &Foto, b: &Foto,
    sale_a: bool, sale_b: bool) {
    var i = 0;
    while i < largo(a.indices) {
        let k = a.indices[i];
        if sale_a && !sale_b {
            vs[k].movida_en = b.movidas[i];
            vs[k].entregada_en = b.entregadas[i];
        } else {
            if sale_b && !sale_a {
                vs[k].movida_en = a.movidas[i];
                vs[k].entregada_en = a.entregadas[i];
            } else {
                if a.movidas[i] > 0 { vs[k].movida_en = a.movidas[i]; }
                else { vs[k].movida_en = b.movidas[i]; }
                if a.entregadas[i] > 0 {
                    vs[k].entregada_en = a.entregadas[i];
                } else {
                    vs[k].entregada_en = b.entregadas[i];
                }
            }
        }
        i = i + 1;
    }
}

// Si el parametro numero `i` de `fn` se queda con lo que le den.
fn se_lo_queda(c: &I.Contexto, fn_: view, i: usize) -> bool {
    if !tiene(c.params_marcados, fn_) { return false; }
    let marcados = I.lista_de(c.params_marcados, fn_) sino [];
    if i >= largo(marcados) { return false; }
    let m = vista(marcados[i]);
    // Un prestamo no se queda con nada.
    if empieza_con(m, "&") || empieza_con(m, "mut ") { return false; }
    // En una generica, `a: A` se queda con lo que le den si eso posee, y eso
    // depende del argumento: lo mira quien llama, con el tipo de lo que pasa.
    if tiene(c.tipo_params, fn_) {
        let sueltos = I.lista_de(c.tipo_params, fn_) sino [];
        var cualquiera: mapa<str, str> = [];
        for tp en sueltos { poner(cualquiera, vista(tp), nuevo("str")); }
        let puesto = I.sustituir(m, cualquiera);
        if !igual(vista(puesto), m) { return true; }
    }
    return tiene_duenio(c, m);
}

// ------------------------------------------------------------------
// Recorrer un cuerpo buscando quien entrega y quien mueve
// ------------------------------------------------------------------

fn mirar(c: &I.Contexto, n: &P.Nodo, vs: mut lista<Vigilada>) {
    let clase = vista(n.clase);

    if igual(clase, "si") && largo(n.hijos) >= 2 {
        // La condicion siempre se evalua. A partir de ahi, cada rama parte de
        // la misma foto y solo aporta estado si puede alcanzar la continuacion.
        mirar(c, n.hijos[0], vs);
        let antes = fotografiar(vs, n.linea);

        mirar(c, n.hijos[1], vs);
        let tras_entonces = fotografiar(vs, n.linea);
        let entonces_sale = termina(n.hijos[1]);

        restaurar(vs, antes);
        var sino_sale = false;
        if largo(n.hijos) > 2 {
            mirar(c, n.hijos[2], vs);
            sino_sale = termina(n.hijos[2]);
        }
        let tras_sino = fotografiar(vs, n.linea);
        unir_ramas(vs, tras_entonces, tras_sino, entonces_sale, sino_sale);
        return;
    }

    if igual(clase, "retorno") {
        // `return x;` entrega `x` entero. Cualquier otra cosa que se
        // devuelva no entrega una variable, la calcula.
        if largo(n.hijos) > 0 {
            let quien = variable_suelta(n.hijos[0]);
            marcar_entregada(vs, vista(quien), n.linea);
        }
        for h en n.hijos { mirar(c, h, vs); }
        return;
    }

    if igual(clase, "llamada") {
        mirar_llamada(c, n, vs);
        return;
    }

    if igual(clase, "literal_struct") {
        // Un campo con duenio se queda con lo que le pongan.
        var i = 0;
        for h en n.hijos {
            // Cada hijo es un `campo` con su valor dentro.
            for x en h.hijos {
                let quien = variable_suelta(x);
                if largo(quien) > 0 {
                    let t = tipo_vigilado(vs, vista(quien), x.linea);
                    if tiene_duenio(c, vista(t)) {
                        // En la linea del valor, no en la del literal: un literal
                        // de struct suele ocupar varias lineas.
                        marcar_movida(vs, vista(quien), x.linea);
                    }
                }
                mirar(c, x, vs);
            }
            i = i + 1;
        }
        return;
    }

    if igual(clase, "enum_lit") {
        // Una variante se queda con cada valor con dueño que lleva, igual que
        // un struct se queda con sus campos. El sitio es el del argumento:
        // la construcción puede estar repartida en varias líneas.
        for h en n.hijos {
            let quien = variable_suelta(h);
            if largo(quien) > 0 {
                let t = tipo_vigilado(vs, vista(quien), h.linea);
                if tiene_duenio(c, vista(t)) {
                    marcar_movida(vs, vista(quien), h.linea);
                }
            }
            mirar(c, h, vs);
        }
        return;
    }

    if igual(clase, "asignacion") {
        // `a = b` con `b` con duenio: `b` pasa a ser de `a`.
        if largo(n.hijos) > 1 {
            let quien = variable_suelta(n.hijos[1]);
            if largo(quien) > 0 {
                let t = tipo_vigilado(vs, vista(quien), n.linea);
                if tiene_duenio(c, vista(t)) {
                    marcar_movida(vs, vista(quien), n.linea);
                }
            }
        }
        for h en n.hijos { mirar(c, h, vs); }
        return;
    }

    if igual(clase, "declaracion") {
        // `let a = b` es lo mismo: `b` pasa a ser de `a`.
        if largo(n.hijos) > 0 {
            let quien = variable_suelta(n.hijos[0]);
            if largo(quien) > 0 {
                let t = tipo_vigilado(vs, vista(quien), n.linea);
                if tiene_duenio(c, vista(t)) {
                    marcar_movida(vs, vista(quien), n.linea);
                }
            }
        }
        for h en n.hijos { mirar(c, h, vs); }
        return;
    }

    for h en n.hijos { mirar(c, h, vs); }
}

fn mirar_llamada(c: &I.Contexto, n: &P.Nodo, vs: mut lista<Vigilada>) {
    let nombre = vista(n.texto);

    // Las internas que se quedan con un valor: el segundo argumento de
    // `anadir`, el tercero de `poner`.
    var se_queda_en = 99;
    if igual(nombre, "anadir") { se_queda_en = 1; }
    if igual(nombre, "poner") { se_queda_en = 2; }
    if igual(nombre, "intercambiar") { se_queda_en = 1; }

    var i = 0;
    for h en n.hijos {
        var lo_toma = false;
        if i == se_queda_en {
            lo_toma = true;
        } else {
            lo_toma = se_lo_queda(c, nombre, i);
        }
        if lo_toma {
            let quien = variable_suelta(h);
            if largo(quien) > 0 {
                let t = tipo_vigilado(vs, vista(quien), h.linea);
                if tiene_duenio(c, vista(t)) {
                    // En la linea del argumento, no en la de la llamada: una
                    // llamada puede ocupar varias lineas.
                    marcar_movida(vs, vista(quien), h.linea);
                }
            }
        }
        mirar(c, h, vs);
        i = i + 1;
    }
}
