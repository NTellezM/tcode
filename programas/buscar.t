// buscar.t — las lineas que contienen un texto, como `LC_ALL=C grep -F`.
//
//     ./buscar [-n] [-v] [-i] texto [archivo]
//
// -n numera las lineas; -v da las que no lo contienen; -i no distingue
// mayusculas de minusculas en las letras ASCII. Sale con 0 si alguna linea
// salio y con 1 si ninguna, como `grep`.

usar "std/texto" como t;

fn main() -> usize ! {
    var numerar = false;
    var al_reves = false;
    var sin_caso = false;
    var sueltos: lista<str> = [];
    var k = 1;
    while k < n_argumentos() {
        let a = argumento(k);
        if a == "-n" {
            numerar = true;
        } else if a == "-v" {
            al_reves = true;
        } else if a == "-i" {
            sin_caso = true;
        } else {
            anadir(sueltos, nuevo(a));
        }
        k = k + 1;
    }
    if largo(sueltos) == 0 || largo(sueltos) > 2 {
        imprimir_error("uso: buscar [-n] [-v] [-i] texto [archivo]\n");
        return 2;
    }
    var texto = vacio();
    if largo(sueltos) == 2 {
        texto = try leer_archivo(sueltos[1]);
    } else {
        texto = try entrada_completa();
    }
    var aguja = copiar(sueltos[0]);
    if sin_caso { aguja = t.minusculas(aguja); }

    var salida = vacio();
    var salieron = 0;
    var numero = 0;
    var desde = 0;
    var i = 0;
    while desde < largo(texto) {
        // La linea va de `desde` hasta el siguiente salto, o hasta el final.
        i = desde;
        while i < largo(texto) && byte(texto, i) != 10 { i = i + 1; }
        let linea = rebanar(texto, desde, i);
        numero = numero + 1;
        var esta = false;
        if sin_caso {
            esta = t.contiene(t.minusculas(linea), aguja);
        } else {
            esta = t.contiene(linea, aguja);
        }
        if esta != al_reves {
            if numerar { empujar(salida, $"{numero}:"); }
            empujar(salida, linea);
            empujar(salida, "\n");
            salieron = salieron + 1;
        }
        desde = i + 1;
    }
    imprimir(salida);
    if salieron == 0 { return 1; }
    return 0;
}
