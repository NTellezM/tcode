// std/cli.t — leer los argumentos del programa.
//
//     usar "std/cli" as cli;
//     let a = cli.leer();
//     if cli.tiene_bandera(a, "ayuda") { ... }   // --ayuda o -h
//     let salida = cli.opcion(a, "salida");      // --salida=archivo
//     for r en a.sueltos { ... }                 // los que no son banderas
//
// Convencion: `--nombre` y `-x` son banderas; `--nombre=valor` es una opcion;
// todo lo demas queda suelto, en orden. Sin ambiguedades: una bandera nunca
// se traga el argumento siguiente.

usar "std/texto" como t;
usar "std/mapa" como m;

struct Argumentos {
    banderas: mapa<str, bool>,
    opciones: mapa<str, str>,
    sueltos: lista<str>,
}

// La posicion del primer '=', o largo(v) si no hay.
fn posicion_de_igual(v: view) -> usize {
    var i = 0;
    while i < largo(v) {
        if byte(v, i) == 61 { return i; }
        i = i + 1;
    }
    return largo(v);
}

fn leer() -> Argumentos {
    var a = Argumentos { banderas: [], opciones: [], sueltos: [] };
    var k = 1;
    while k < n_argumentos() {
        let x = argumento(k);
        if t.empieza_con(x, "--") {
            let nombre = nuevo(rebanar(x, 2, largo(x)));
            let donde = posicion_de_igual(nombre);
            if donde < largo(nombre) {
                poner(a.opciones, nuevo(rebanar(nombre, 0, donde)),
                    nuevo(rebanar(nombre, donde + 1, largo(nombre))));
            } else {
                poner(a.banderas, nombre, true);
            }
        } else if t.empieza_con(x, "-") && largo(x) > 1 {
            poner(a.banderas, nuevo(rebanar(x, 1, largo(x))), true);
        } else {
            anadir(a.sueltos, nuevo(x));
        }
        k = k + 1;
    }
    return a;
}

// La bandera esta puesta (siempre vale true cuando esta).
fn tiene_bandera(a: &Argumentos, nombre: view) -> bool {
    return m.obtener_o(a.banderas, nombre, false);
}

// El valor de la opcion, o "" si no esta.
fn opcion(a: &Argumentos, nombre: view) -> str {
    let v = obtener(a.opciones, nombre) sino "";
    return nuevo(v);
}
