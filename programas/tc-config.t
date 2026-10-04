// tc-config.t — lee un config TOML: consulta una clave o lo vuelca a JSON.
//
//     ./tc-config config.toml                      todo, en JSON
//     ./tc-config config.toml --clave=server.host  solo esa clave
//
// Junta las bibliotecas: `cli` para los argumentos, `toml` para leer, `json`
// para escribir. Sale con 2 si faltan argumentos, y con 1 si la clave no esta.

#importar "cli.t" como cli;
#importar "toml.t" como toml;
#importar "json.t" como json;

fn a_json(v: &toml.ValorToml) -> json.Valor {
    match v {
        toml.ValorToml.Texto(s) -> { return json.Valor.Texto(nuevo(s)); }
        toml.ValorToml.Entero(n) -> { return json.Valor.Numero($"{n}"); }
        toml.ValorToml.Decimal(x) -> { return json.Valor.Numero($"{x}"); }
        toml.ValorToml.Cierto -> { return json.Valor.Cierto; }
        toml.ValorToml.Falso -> { return json.Valor.Falso; }
        toml.ValorToml.Lista(xs) -> {
            var salida: list<json.Valor> = [];
            for x en xs { anadir(salida, a_json(x)); }
            return json.Valor.Lista(salida);
        }
    }
    return json.Valor.Nada;
}

fn a_objeto(t: &map<str, toml.ValorToml>) -> json.Valor {
    var m: map<str, json.Valor> = [];
    for k, v en t {
        poner(m, nuevo(k), a_json(v));
    }
    return json.Valor.Objeto(m);
}

fn main() -> usize ! {
    let a = cli.leer();
    if largo(a.sueltos) == 0 {
        imprimir_error("uso: tc-config <archivo.toml> [--clave=a.b]\n");
        return 2;
    }
    let ruta = vista(a.sueltos[0]);
    let texto = try leer_archivo(ruta);
    let t = try toml.leer(texto);
    let clave = cli.opcion(a, "clave");
    if largo(clave) > 0 {
        if !toml.tiene_clave(t, clave) {
            imprimir_error($"tc-config: no esta la clave `{clave}`\n");
            return 1;
        }
        let v = toml.crudo_de(t, clave) sino toml.ValorToml.Texto(vacio());
        imprimir(json.escribir(a_json(v)));
        imprimir("\n");
        return 0;
    }
    imprimir(json.escribir_con_sangria(a_objeto(t)));
    imprimir("\n");
    return 0;
}
