// json.t — un valor que es una cosa O otra, y el compilador obliga a mirar
// cual.
//
// Es el caso por el que existen los tipos suma. Sin ellos hay que fingirlos
// con una etiqueta de texto y un puñado de campos que solo valen a veces:
//
//     struct Json { clase: str, numero: i64, texto: str, hijos: lista<Json> }
//
// y entonces `clase` puede decir "numero" mientras alguien lee `texto`,
// nadie avisa de que falta tratar una clase nueva, y un "numro" mal escrito
// compila igual de bien. Este archivo no puede tener ninguno de esos fallos.
//
// Como lo hacen los demas:
//
//   - C: `enum` son enteros con nombre; la union se monta a mano y nadie
//     comprueba que la etiqueta y el campo leido concuerden.
//   - Go: no tiene. Se usa una interfaz y un `type switch`, sin
//     exhaustividad: anadir un caso no rompe nada, solo lo deja mal.
//   - C++: `std::variant` y `std::visit`, verboso y con errores ilegibles.
//   - Rust, Swift, Zig y los ML: como aqui, y con exhaustividad.
//
// Lo que Tcode hace distinto:
//
//   - La etiqueta 0 es la PRIMERA variante, siempre. Un enum puesto a ceros
//     es un valor valido, asi que cabe en la memoria que entrega `reservar`
//     sin que exista un `unsafe` ni un `MaybeUninit`.
//   - Un `match` MIRA, no desmonta: lo que atrapa el patron se presta. Rust
//     deja sacar el valor de dentro y a cambio tiene que llevar la cuenta de
//     un enum medio movido, con `ref`, `&` y modos de ligadura. Aqui quien
//     quiera quedarse con lo de dentro escribe `copiar(...)`, que es la
//     misma regla explicita del resto del lenguaje.

usar "std/texto";
usar "std/lista";

enum Json {
    Nulo,
    Verdad(bool),
    Numero(i64),
    Texto(str),
    Lista(lista<Json>),
}

fn escribir(v: &Json) -> str {
    return match v {
        Json.Nulo -> nuevo("null"),
        Json.Verdad(b) -> nuevo(if b { "true" } else { "false" }),
        Json.Numero(n) -> texto(n),
        Json.Texto(s) -> {
            // Sin escapes: aqui lo que se ensena es el enum, no JSON.
            var r = nuevo("\"");
            empujar(r, s);
            empujar(r, "\"");
            return r;
        }
        Json.Lista(xs) -> {
            var r = nuevo("[");
            var primero = true;
            for x en xs {
                if !primero { empujar(r, ","); }
                primero = false;
                let dentro = escribir(x);
                empujar(r, vista(dentro));
            }
            empujar(r, "]");
            return r;
        }
    };
}

// Cuantos valores hay contando los de dentro. Un `match` suelto no da
// valor: mira y hace.
fn cuantos(v: &Json) -> usize {
    var n = 1;
    match v {
        Json.Lista(xs) -> {
            for x en xs {
                n = n + cuantos(x);
            }
        }
        _ -> { }
    }
    return n;
}

fn main() {
    var xs: lista<Json> = [];
    anadir(xs, Json.Numero(42));
    anadir(xs, Json.Texto(nuevo("hola")));
    anadir(xs, Json.Verdad(true));
    anadir(xs, Json.Nulo);

    var dentro: lista<Json> = [];
    anadir(dentro, Json.Numero(1));
    anadir(dentro, Json.Numero(2));
    anadir(xs, Json.Lista(dentro));

    let doc = Json.Lista(xs);
    imprimir($"{escribir(doc)}\n");
    imprimir($"{cuantos(doc)} valores\n");
}
