// std/ini.t — leer y escribir INI (el formato de configuracion clasico).
//
//     let ini = ini.leer(texto);      // a map<str, map<str, str>>
//     let texto = ini.escribir(ini);  // de vuelta
//
// Una linea es `clave = valor`, una seccion es `[nombre]`, y `;` o `#`
// empiezan un comentario. La seccion sin nombre usa la clave vacia "".

use "std/texto";

fn leer(texto: view) -> map<str, map<str, str>> {
    var ini: map<str, map<str, str>> = [];
    var seccion = nuevo("");
    var dentro: map<str, str> = [];
    for linea en lineas(texto) {
        let r = recortar(linea);
        if largo(r) == 0 { continue; }
        let b = byte(r, 0);
        if b == 59 || b == 35 { continue; }
        if b == 91 {
            // Cierra la seccion anterior y abre una nueva.
            poner(ini, seccion, dentro);
            let fin = indice_de(r, "]") sino largo(r);
            seccion = nuevo(recortar(rebanar(r, 1, fin)));
            dentro = [];
        } else {
            let igual = indice_de(r, "=") sino largo(r);
            if igual < largo(r) {
                let clave = recortar(rebanar(r, 0, igual));
                let valor = recortar(rebanar(r, igual + 1, largo(r)));
                poner(dentro, nuevo(clave), nuevo(valor));
            }
        }
    }
    poner(ini, seccion, dentro);
    return ini;
}

fn escribir_claves(claves: &map<str, str>, salida: mut str) {
    for clave, valor en claves {
        empujar(salida, clave);
        empujar(salida, " = ");
        empujar(salida, valor);
        empujar(salida, "\n");
    }
}

fn escribir(ini: &map<str, map<str, str>>) -> str {
    var salida = vacio();
    // La seccion sin nombre va PRIMERO: sus claves son las de antes de
    // cualquier `[seccion]`, y si fueran despues caerian en la anterior.
    for seccion, claves en ini {
        if largo(seccion) == 0 { escribir_claves(claves, salida); }
    }
    for seccion, claves en ini {
        if largo(seccion) == 0 { continue; }
        empujar(salida, "[");
        empujar(salida, seccion);
        empujar(salida, "]\n");
        escribir_claves(claves, salida);
        empujar(salida, "\n");
    }
    return salida;
}

fn valor_en(dentro: &map<str, str>, clave: view) -> str ! {
    return nuevo(try obtener(dentro, clave));
}

// El valor de `clave` en `seccion`; falla si no esta. Una copia, para no
// depender de quien presta el mapa.
fn valor(ini: &map<str, map<str, str>>, seccion: view, clave: view) -> str ! {
    let dentro = try obtener(ini, seccion);
    return try valor_en(dentro, clave);
}

// El valor de `clave` en `seccion`, o `alterno` si no esta.
fn valor_o(ini: &map<str, map<str, str>>, seccion: view, clave: view,
    alterno: view) -> str {
    let v = valor(ini, seccion, clave) sino nuevo(alterno);
    return v;
}
