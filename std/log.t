// std/log.t — avisos con nivel y hora.
//
//     let l = log.con_nivel(1);        // 1 = enseña de INFO para arriba
//     log.informa(l, "arrancando");
//     log.error(l, "no se pudo abrir");
//
// Cuatro niveles, de menos a mas: 0 DEPURA, 1 INFO, 2 AVISO, 3 ERROR. Los
// ERROR van a la salida de error; los demas, a la normal. La marca es UTC,
// ISO 8601.

use "std/fecha" como fecha;

struct Log {
    minimo: i64,
}

// Un registro que enseña los avisos de `minimo` (0..3) para arriba.
fn con_nivel(minimo: i64) -> Log {
    return Log { minimo: minimo };
}

fn etiqueta(nivel: i64) -> view {
    if nivel <= 0 { return "DEPURA"; }
    if nivel == 1 { return "INFO"; }
    if nivel == 2 { return "AVISO"; }
    return "ERROR";
}

fn escribe(l: &Log, nivel: i64, mensaje: view) {
    if nivel < l.minimo { return; }
    let marca = fecha.formatear(fecha.ahora());
    if nivel >= 3 {
        imprimir_error($"{marca} [{etiqueta(nivel)}] {mensaje}\n");
    } else {
        imprimir($"{marca} [{etiqueta(nivel)}] {mensaje}\n");
    }
}

fn depura(l: &Log, mensaje: view) { escribe(l, 0, mensaje); }
fn informa(l: &Log, mensaje: view) { escribe(l, 1, mensaje); }
fn avisa(l: &Log, mensaje: view) { escribe(l, 2, mensaje); }
fn error(l: &Log, mensaje: view) { escribe(l, 3, mensaje); }
