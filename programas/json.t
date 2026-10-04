// json.t — valida y reformatea JSON de la entrada, sobre std/json y std/cli.
//
//     ./json < archivo.json      lo reformatea con dos espacios de sangria
//     ./json -c < archivo.json   compacto, en una linea
//
// Un JSON mal escrito falla. El parser vive en `std/json`, y las banderas
// las lee `std/cli`.

#importar "json.t" como json;
#importar "cli.t" como cli;

fn main() -> usize ! {
    let todo = try entrada_completa();
    let a = cli.leer();
    let compacto = cli.tiene_bandera(a, "c");
    let v = try json.leer(todo);
    if compacto {
        imprimir(json.escribir(v));
    } else {
        imprimir(json.escribir_con_sangria(v));
    }
    imprimir("\n");
    return 0;
}
