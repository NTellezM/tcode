// cuerpos.t — la funcion entera en C, escrita por Tcode.
//
// Tercera pieza del generador, y la que de verdad cuenta: la firma, el
// cuerpo, y los `ss_free` puestos solos donde tocan. Una funcion que esta
// capa no sabe hacer entera no se emite a medias: se descarta, porque media
// funcion generada no dice nada.
//
//     ./cuerpos std/caracter.t

usar "lib/programa.t" como F;
usar "lib/tipar.t" como I;
usar "../lexer/lib/lexico.t";
usar "../lexer/lib/sintaxis.t" como P;
usar "std/texto";
usar "std/lista";

fn main() -> usize ! {
    if n_argumentos() < 2 {
        imprimir_error($"uso: {argumento(0)} <archivo.t>\n");
        return 1;
    }

    let ruta = argumento(1);
    var tipos = I.contexto();
    let arbol = try F.preparar(ruta, tipos);
    for d en arbol.hijos {
        if igual(vista(d.clase), "fn") && !F.es_generica(d)
        && !igual(vista(d.texto), "main") {
            // Cada funcion de cero: el oraculo renumera los contadores.
            var cta = F.cuenta_nueva();
            let lineas = F.generar_funcion(d, tipos, ruta, cta);
            if largo(lineas) > 0 {
                // Un separador a principio de linea, para que quien compare
                // sepa donde empieza cada funcion.
                imprimir($"@@ {d.texto}\n");
                for l en lineas { imprimir($"{l}\n"); }
            }
        }
    }
    return 0;
}
