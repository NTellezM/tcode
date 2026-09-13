// sistema.t — lo que el programa le pide a la maquina.
//
// Todo esto podria hacerse con un bloque `externo`, y saldria peor: lo que
// devuelven `leer_linea` o `variable_entorno` es memoria, y la memoria en
// Tcode tiene dueno. Un `char*` prestado de C no lo tiene, y habria que
// copiarlo a mano cada vez. Por eso estas son internas y no una biblioteca.
//
// Cada una decide algo que C decidio al reves:
//
//   - `leer_linea` crece lo que haga falta. `fgets` corta y deja el resto
//     para la vuelta siguiente, que es peor que fallar porque parece que
//     funciona; el `bufio.Scanner` de Go deja de leer a los 64 KB y no lo
//     dice. Aqui no hay linea demasiado larga.
//   - El fin de la entrada es un FALLO, no una cadena vacia: una linea en
//     blanco no es lo mismo que no haber nada. Es la diferencia entre el
//     `input()` de Python (que levanta `EOFError`) y leer un `""` y no
//     saber cual de las dos cosas paso.
//   - `variable_entorno` distingue "no esta" de "esta vacia". `getenv` no
//     puede: las dos dan algo falso. Go necesito `LookupEnv` aparte para
//     esto, y Rust un `Result`.
//   - Hay DOS relojes, y el nombre dice cual es cual. Medir una duracion con
//     el de pared es el error clasico —salta con el NTP y con el cambio de
//     hora—, y el `clock()` de C mide tiempo de CPU aunque medio mundo lo
//     use para lo otro.
//   - `azar` no tiene el sesgo de `rand() % n`: si el tope no divide al
//     rango, los primeros valores saldrian mas veces. Se descarta el
//     sobrante, como en Rust y en Go.

usar "std/texto";
usar "std/lista";

fn main() -> usize ! {
    // ---- el entorno ----
    let ruta = variable_entorno("PATH") sino nuevo("(no esta)");
    imprimir($"PATH ocupa {largo(vista(ruta))} bytes\n");

    let inventada = variable_entorno("ESTO_NO_EXISTE_12345") sino
    nuevo("(no esta, y se sabe)");
    imprimir($"la inventada: {inventada}\n");

    // ---- los dos relojes ----
    // El de pared para decir CUANDO; el monotono para decir CUANTO.
    let empiezo = monotono_ms();
    var vueltas = 0;
    while vueltas < 200000 {
        vueltas = vueltas + 1;
    }
    let tardo = monotono_ms() -? empiezo;
    imprimir($"contar hasta {vueltas} tardo {tardo >= 0} (ms >= 0)\n");
    imprimir($"el reloj de pared va: {ahora_ms() > 1700000000000}\n");

    // ---- azar, y repetible ----
    // Con semilla puesta sale siempre lo mismo, que es lo que hace falta
    // para que una prueba sirva de algo. Sin ponerla, el reloj la elige.
    sembrar(7);
    var tirada: lista<usize> = [];
    var i = 0;
    while i < 6 {
        anadir(tirada, azar(6) + 1);
        i = i + 1;
    }
    imprimir("seis dados con semilla 7:");
    for d en tirada {
        imprimir($" {d}");
    }
    imprimir("\n");

    // ---- la entrada ----
    // Sin nada por la entrada, `leer_linea` falla, y eso es una respuesta.
    var lineas = 0;
    var bytes = 0;
    var sigo = true;
    while sigo {
        let linea = leer_linea() sino nuevo("");
        if largo(vista(linea)) == 0 {
            // Puede ser una linea en blanco o el fin; se distingue mirando
            // otra vez, que es justo lo que el fallo permite hacer.
            sigo = false;
        } else {
            lineas = lineas + 1;
            bytes = bytes + largo(vista(linea));
        }
    }
    imprimir($"lei {lineas} lineas, {bytes} bytes sin contar los saltos\n");
    return 0;
}
