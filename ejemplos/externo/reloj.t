// reloj.t — la puerta a C, y por que es la unica.
//
// Tcode compila a C17, asi que llamar a una funcion de C no cuesta nada:
// es la misma llamada que escribiria un programa en C, sin envoltorio y sin
// nada que traducir. Eso ya es mejor que cgo (que cambia de pila y cuesta
// unos 100 ns) y que ctypes (que lo resuelve al correr).
//
// Lo interesante no es eso, sino que el borde sigue siendo seguro:
//
//   - Un bloque `externo` se ve desde lejos y dice de donde sale cada cosa.
//     No hay `unsafe` por llamada como en Rust, porque no hace falta: desde
//     Tcode no se puede escribir una llamada que rompa la memoria.
//   - En el borde solo caben los tipos que significan EXACTAMENTE lo mismo
//     a los dos lados: numeros, `bool` y `str`. Una `lista`, un `mapa` o un
//     struct no; para eso se envuelve en C, como en `sistema.c`.
//   - Un `str` entra como `const char*` porque el runtime garantiza el `\0`
//     final. Una `view` NO: puede apuntar a la mitad de una cadena. Es la
//     comprobacion que Rust deja en manos de `CString::new` y que aqui hace
//     el compilador.
//   - Y si un `str` lleva un cero EN MEDIO, el programa para en la linea
//     donde se entrega, en vez de pasarle a C una cadena cortada. No es un
//     fallo de memoria; es una verdad a medias, y se trata como el
//     desbordamiento o el NaN.
//
// Lo que Tcode NO puede prometer: que la funcion de C haga lo que dice. Si
// `sqrt` corrompiera la memoria, la corrompe. Por eso la puerta es una, se
// declara, y su nombre esta escrito aqui.

usar "std/texto";

externo "math.h" {
    fn sqrt(x: f64) -> f64;
    fn pow(base: f64, exponente: f64) -> f64;
}

externo "stdlib.h" {
    // Devuelve un `char*` que sigue siendo de C: `cadena_c` dice justo eso,
    // y Tcode se queda una copia que ya se libera sola.
    fn getenv(nombre: str) -> cadena_c;
}

// Un `.c` no se incluye: se compila y se enlaza junto al programa.
externo "sistema.c" {
    fn ahora_segundos() -> i64;
    fn al_azar(tope: i64) -> i64;
    fn sembrar(semilla: i64);
}

fn main() {
    imprimir($"raiz de 2      {sqrt(2.0)}\n");
    imprimir($"2 elevado a 10 {pow(2.0, 10.0)}\n");

    let clave = nuevo("PATH");
    let valor = getenv(clave);
    imprimir($"PATH tiene     {largo(vista(valor))} bytes\n");

    // Semilla fija: el ejemplo tiene que dar siempre lo mismo.
    sembrar(1);
    var suma: i64 = 0;
    var i: i64 = 0;
    while i < 5 {
        suma = suma +? al_azar(100);
        i = i + 1;
    }
    imprimir($"cinco al azar  suman {suma}\n");
    imprimir($"el reloj anda  {ahora_segundos() > 1700000000}\n");
}
