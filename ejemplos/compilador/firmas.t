// firmas.t — la firma en C de cada funcion, dicha por Tcode.
//
// Primera pieza del generador escrita en su propio lenguaje. La suite la
// compara con lo que emite el generador de Python, cadena por cadena, para
// cada funcion del repositorio.
//
//     ./firmas std/texto.t

use "lib/generar.t" como G;
use "lib/programa.t" como F;
use "lib/tipar.t" como I;
use "../lexer/lib/lexico.t";
use "../lexer/lib/sintaxis.t" como P;
use "std/texto";
use "std/lista";
use "../lexer/lib/clase.t";

fn tras_dos_puntos(texto: view) -> str {
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

// `nombre: mut lista<str>` da `lista<str>`: la marca se pasa aparte.
fn tipo_pelado(marcado: view) -> str {
    let t = tras_dos_puntos(marcado);
    if empieza_con(t, "mut ") {
        return nuevo(rebanar(t, 4, t.largo()));
    }
    if empieza_con(t, "&mut ") {
        return nuevo(rebanar(t, 5, t.largo()));
    }
    if empieza_con(t, "&") {
        return nuevo(rebanar(t, 1, t.largo()));
    }
    return t;
}

// `nombre: &Cosa` se queda en `nombre: &Cosa`; es lo que `prototipo`
// necesita para saber si va por puntero y como se llama.
fn marca_de(marcado: view) -> str {
    var i = 0;
    while i + 1 < marcado.largo() {
        if byte(marcado, i) == 58 {
            if byte(marcado, i + 1) == 32 {
                var s = nuevo(rebanar(marcado, 0, i + 2));
                s.empujar(recortar(rebanar(marcado, i + 2, marcado.largo())));
                return s;
            }
        }
        i = i + 1;
    }
    return nuevo(marcado);
}

// La marca sin el nombre delante, para saber si presta.
fn solo_marca(marcado: view) -> str {
    let t = tras_dos_puntos(marcado);
    if empieza_con(t, "mut ") { return nuevo("mut "); }
    if empieza_con(t, "&mut ") { return nuevo("&mut "); }
    if empieza_con(t, "&") { return nuevo("&"); }
    return vacio();
}

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t>\n");
        return 1;
    }

    var contexto = I.contexto();
    let arbol = try F.preparar(argumento(1), contexto);

    for d en arbol.hijos {
        if d.clase == Clase.Fn && !es_generica(d) {
            var tipos: list<str> = [];
            var marcas: list<str> = [];
            var retorno = vacio();
            var falible = false;
            for h en d.hijos {
                match h.clase {
                    Clase.Param -> {
                        tipos.anadir(tipo_pelado(h.texto));
                        var m = nuevo(nombre_solo(h.texto));
                        m.empujar(": ");
                        m.empujar(solo_marca(h.texto));
                        marcas.anadir(m);
                    }
                    Clase.RetornoTipo -> {
                        retorno = nuevo(h.texto);
                    }
                    Clase.Falible -> { falible = true; }
                    _ -> { }
                }
            }
            var nombre_c = copiar(d.texto);
            if tiene(contexto.renombradas, d.texto) {
                nombre_c = nuevo(obtener(contexto.renombradas, d.texto) sino "");
            }
            let firma = G.prototipo(vista(nombre_c), tipos, marcas,
                vista(retorno), falible);
            imprimir($"{firma}\n");
        }
    }
    return 0;
}

fn nombre_solo(marcado: view) -> str {
    var i = 0;
    while i < marcado.largo() {
        if byte(marcado, i) == 58 { return nuevo(rebanar(marcado, 0, i)); }
        i = i + 1;
    }
    return nuevo(marcado);
}

fn es_generica(d: &P.Nodo) -> bool {
    for h en d.hijos {
        if h.clase == Clase.TipoParam { return true; }
    }
    return false;
}
