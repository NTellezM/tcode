// std/prueba.t — comprobar cosas desde Tcode.
//
// Sin esto, un programa en Tcode no puede decir si hizo lo que debia mas que
// imprimiendo y mirando. Aqui hay lo minimo: afirmaciones que cuentan, y un
// resumen al final que sirve como codigo de salida.
//
//     var p = pruebas();
//     afirmar_igual_texto(p, "junta", unir(xs, ","), "a,b");
//     afirmar(p, "no esta vacia", largo(xs) > 0);
//     return terminar(p);

usar "std/texto";

struct Pruebas {
    hechas: usize,
    fallos: lista<str>,
}

fn pruebas() -> Pruebas {
    return Pruebas { hechas: 0, fallos: [] };
}

fn afirmar(p: mut Pruebas, que: view, cierto: bool) {
    p.hechas = p.hechas + 1;
    if !cierto {
        anadir(p.fallos, nuevo(que));
    }
}

fn afirmar_igual_texto(p: mut Pruebas, que: view, dado: view, esperado: view) {
    p.hechas = p.hechas + 1;
    if !igual(dado, esperado) {
        anadir(p.fallos, $"{que}: se esperaba \"{esperado}\" y hubo \"{dado}\"");
    }
}

fn afirmar_igual_numero(p: mut Pruebas, que: view, dado: usize, esperado: usize) {
    p.hechas = p.hechas + 1;
    if dado != esperado {
        anadir(p.fallos, $"{que}: se esperaba {esperado} y hubo {dado}");
    }
}

// Devuelve lo que tiene que devolver `main`: cero si todo fue bien.
fn terminar(p: &Pruebas) -> usize {
    if largo(p.fallos) == 0 {
        imprimir($"{p.hechas} comprobaciones, todo bien\n");
        return 0;
    }
    for f en p.fallos { imprimir_error($"  falla: {f}\n"); }
    imprimir_error($"{largo(p.fallos)} de {p.hechas} comprobaciones fallaron\n");
    return 1;
}
