// Las palabras mas frecuentes de un archivo.
//
//     ./frecuencia README.md

usar "../std/cuenta.t";

fn main() -> usize ! {
    let texto = try leer_archivo(argumento(1));
    let cuenta = contar(palabras(minusculas(texto)));

    for palabra en mayores(cuenta, 5) {
        imprimir($"{obtener(cuenta, palabra) sino 0}  {palabra}\n");
    }
}
