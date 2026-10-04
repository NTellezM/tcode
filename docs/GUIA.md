# Tcode en 10 minutos

La vuelta corta: instala, escribe «hola, mundo», y entiende la única idea que
hay que entender — *por qué existe `view`*. Todo el código de aquí compila y
corre tal cual.

## 1. Instalar

```sh
./instalar.sh                      # deja tcode y tcodec en ~/.local
export PATH="$HOME/.local/bin:$PATH"
```

O, sin instalar, desde el repo: `./bin/tcode correr mi.t`.

## 2. Hola, mundo

```sh
tcode nuevo hola
cd hola
tcode correr main.t       # -> hola, mundo
```

`main.t` es esto:

```tcode
fn main() {
    imprimir("hola, mundo\n");
}
```

`tcode correr` compila y ejecuta de una. Eso es todo el ritual.

## 3. Funciones y tipos

```tcode
fn doblar(x: usize) -> usize {
    return x * 2;
}

fn main() {
    let nombre = nuevo("Tcode"); // let: no cambia
    var cuenta = 0;              // var: cambia
    cuenta = doblar(21);
    imprimir($"hola, {nombre}: {cuenta}\n");
}
```

Tipos de una palabra: `usize`, `i64`, `f64`, `bool`, `str`, `view`. La
interpolación es `$"…{expr}…"`.

## 4. Structs

```tcode
struct Punto {
    x: f64,
    y: f64,
}

fn distancia_cuadrada(a: &Punto, b: &Punto) -> f64 {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    return dx * dx + dy * dy;
}

fn main() {
    let a = Punto { x: 0.0, y: 0.0 };
    let b = Punto { x: 3.0, y: 4.0 };
    imprimir($"distancia al cuadrado: {distancia_cuadrada(a, b)}\n");
}
```

Dos cosas: un struct se construye `Punto { x: …, y: … }`, y el parámetro
`&Punto` **presta** — `a` y `b` se pasan sin copiar nada y sin un `&` en la
llamada (se presta solo). Eso lleva a la idea central.

## 5. `view` y `str`: la idea que hay que entender

- **`str` posee.** Es texto en el montículo, con su memoria propia.
- **`view` presta.** Es un dedo que apunta a texto que ya existe; no copia.

```tcode
fn saludar(nombre: view) {
    imprimir($"hola, {nombre}\n");
}

fn main() {
    let nombre = nuevo("Tcode"); // str: posee sus bytes
    saludar(nombre);             // se presta como view, sin copiar
}
```

Por qué importa:

1. **Sin copias.** Pasar un `str` a una función que solo lo mira, copiándolo
   entero, sería caro. Con `view` no se toca un byte.
2. **Sin liberaciones dobles ni uso de memoria liberada.** El compilador
   comprueba quién posee y quién presta. Un `view` no puede sobrevivir a lo
   que apunta; un enum **no** guarda un `view`, porque al mirarlo nadie sabría
   de quién presta.

El caso se ve mejor con un `main` mínimo, que además es la primera vez que
aparece un enum:

```tcode
enum Resultado {
    Bien(usize),
    Mal(str),
}

fn main() {
    let texto = nuevo("no hay");
    let r = Resultado.Mal(texto);
    match r {
        Resultado.Bien(n) -> { imprimir($"bien: {n}\n"); }
        Resultado.Mal(m) -> { imprimir($"mal: {m}\n"); }
    }
}
```

Ese `Mal` **posee** su texto, porque es un `str`. Si en su lugar pusieras un
`view`, el compilador lo rechaza con su motivo:

```
error: `R.Mal` lleva un `view`, que presta: un enum no guarda prestamos, porque
al mirarlo nadie sabria de quien presta. Usa `str`, o un struct con duenio
```

El compilador lo dice él solo, sin que haga falta deducirlo, y además te dice
qué poner en su lugar. Y fíjate en un detalle que sorprende:
`Resultado.Mal("no hay")` con la cadena literal **tampoco** compila, porque una
cadena literal es un `view`. Para llenar un campo que posee hace falta texto con
dueño, `nuevo("no hay")`.

## 6. Genéricos

La misma función, para lo que sea:

```tcode
fn esta_vacia<T>(xs: &list<T>) -> bool {
    return largo(xs) == 0;
}

fn main() {
    var xs: list<usize> = [];
    xs.anadir(1);
    imprimir($"vacia: {esta_vacia(xs)}\n");
}
```

Y sale `vacia: false`. `largo` es una interna, así que este bloque no necesita
ningún `#importar`.

`<T>` es un parámetro de tipo. Hay restricciones cuando se necesitan:
`fn primero<T: igualable>(…)`.

## 7. Enums y `match`

```tcode
enum Resultado {
    Bien(usize),
    Mal(str),
}

fn main() {
    let r = Resultado.Bien(42);
    match r {
        Resultado.Bien(n) -> { imprimir($"bien: {n}\n"); }
        Resultado.Mal(m) -> { imprimir($"mal: {m}\n"); }
    }
}
```

Las variantes llevan valores, y `match` los abre. `match` es exhaustivo: el
compilador te obliga a cubrir todas las variantes (o poner `_`).

## 8. Fallos: `!`, `try` y `sino`

```tcode
fn dividir(a: usize, b: usize) -> usize ! {
    if b == 0 { fail "division por cero"; }
    return a / b;
}

fn main() {
    let x = dividir(10, 2) sino 999; // 5
    let y = dividir(10, 0) sino 0;   // 0, sin reventar
    imprimir($"x = {x}, y = {y}\n");
}
```

```
$ ./fallos
x = 5, y = 0
```

Este bloque tampoco necesita `#importar`: `imprimir` es interna.

El `!` dice «esto puede fallar». `sino valor` da un respaldo si falla; `try`
deja subir el fallo al que llama (y solo se puede usar dentro de otra función
`!`). Es el patrón de error del lenguaje: explícito, sin excepciones escondidas.

## 9. Ejercicios

Cinco programas de dificultad creciente, del «hola con entrada» al «cambio con
validación». Todo lo que aparece aquí compila y corre tal cual, y se puede
probar sin instalar nada:

```sh
./bin/tcode correr mi.t
```

### 9.1 Saludo con entrada

El más corto: preguntar y contestar. En C esto es `get_string` y `printf`; aquí
es `leer_linea` y una cadena interpolada.

```tcode
fn main() {
    imprimir("Input: ");
    let nombre = leer_linea() sino nuevo("");
    imprimir($"hola, {nombre}\n");
}
```

```
$ printf 'Tcode\n' | ./saludo
Input: hola, Tcode
```

Sin un solo `#importar`, porque no hace falta. Cuatro cosas de esas cuatro
líneas:

- El prompt se imprime **antes** y sin salto, así que la respuesta sale en la
  misma línea. `imprimir` no añade nada por su cuenta.
- `imprimir`, `leer_linea` y `largo` son **internas** del lenguaje, no viven en
  `std/`. Este programa no importa nada y funciona; en cuanto uses una función
  de verdad de la biblioteca (`recortar`, `a_entero`, `es_blanco`) tendrás que
  pedir su fichero, porque en Tcode cada archivo pide lo suyo: que otro módulo
  ya lo haya importado no te lo presta.
- `sino nuevo("")` convierte el fallo en una cadena vacía. Sin el `sino`, el
  fallo se propaga y `main` tendría que declararse `fn main() !`.
- **Quita el salto de línea.** A diferencia de `fgets`, aquí no queda un `\n`
  colgando al final, así que no hay que recortarlo para comparar ni imprimir.

### 9.2 Imprimir el nombre letra a letra

El clásico bucle `for (int i = 0, n = strlen(name); i < n; i++)`. En Tcode el
recorrido y el `strlen` vienen juntos:

```tcode
fn imprimir_letra_a_letra(texto: view) {
    for i en 0..largo(texto) {
        imprimir(rebanar(texto, i, i + 1));
    }
}

fn main() {
    imprimir("Input: ");
    let nombre = leer_linea() sino nuevo("");

    if largo(nombre) == 0 {
        imprimir("\n");
    } else {
        imprimir_letra_a_letra(nombre);
        imprimir("\n");
    }
}
```

Este tampoco importa nada: `largo`, `rebanar` y `leer_linea` son internas.

```
$ printf 'hola\n' | ./nombre
Input: hola

$ printf '' | ./nombre
Input: 
```

- `largo(texto)` es `strlen`, y `0..largo(texto)` es el `for` entero: no hay
  que declarar `n` aparte ni acordarse de la condición.
- `rebanar(texto, i, i + 1)` es el `name[i]` que se **imprime**. Para comparar
  con una letra usarías `byte(texto, i)`, que da el número del byte (0–255);
  un trozo de texto que se escribe, en cambio, es una vista.
- La función recibe `view`, así que **presta**: el `nombre` de `main` no se
  copia, y `imprimir_letra_a_letra(nombre)` se pasa sin `&` ni `vista(...)`.
- `if largo(nombre) == 0` cubre el fin de la entrada. En C, `strlen(NULL)`
  revienta; aquí la cadena vacía significa «no había nada» y se imprime solo el
  salto.

### 9.3 Una pirámide

Dibujar una pirámide de `#` alineada a la derecha. La gracia está en que una
fila se pinta con dos bucles, y en que el hueco y el ladrillo son **el mismo
problema al revés**: los huecos bajan, los ladrillos suben.

```tcode
#importar "texto.t";

// Una fila: primero los huecos y luego los ladrillos.
fn print_row(spaces: usize, bricks: usize) {
    for _i en 0..spaces { imprimir(" "); }
    for _i en 0..bricks { imprimir("#"); }
    imprimir("\n");
}

// Pide la altura y la deja en `n`.
//
//   0  hay altura
//   1  la linea estaba mal escrita, o no llega a 1: se vuelve a pedir
//   2  la linea estaba vacia, o se acabo la entrada: el atajo de abajo las
//      junta (ver 9.4)
//
// El 2 para el bucle, como en el `do ... while (n < 1)`.
fn leer_altura(n: mut usize) -> i64 {
    imprimir("Height: ");
    let linea = leer_linea() sino nuevo("");
    if largo(linea) == 0 { return 2; }
    let v = a_entero(recortar(linea)) sino 0;
    if v < 1 || v > 1000 { return 1; }
    n = v;
    return 0;
}

fn main() {
    var n: usize = 0;
    var estado: i64 = 1;
    while estado == 1 {
        estado = leer_altura(n);
    }

    for i en 0..n {
        print_row(n - i - 1, i + 1);
    }
}
```

```
$ printf '3\n' | ./mario
Height:   #
 ##
###
```

- `n - i - 1` y `i + 1`: en la fila `i` los huecos son los que faltan para
  llegar a `n`, y los ladrillos son `i + 1`. Con la primera fila (`i = 0`) el
  número de huecos es el mayor de todos, así que la resta nunca se pasa de
  cero — y esa comprobación existe: restarle a un `usize` por debajo de cero
  **detiene el programa** en vez de dar la vuelta al número, como haría un
  `unsigned` de C.
- `_i` con guion bajo es una variable que no se usa, para callar el aviso.
- `leer_altura` escribe en su parámetro y por eso es `n: mut usize`; el
  compilador pone el `&` en la llamada. Y como recibe un `usize`, **no hay
  números negativos que validar**: `-1` ni siquiera es un valor de ese tipo, lo
  rechaza `a_entero`.
- Los tres estados (0 bien, 1 mal escrita, 2 fin de entrada) son el patrón de
  validación que se repite en el ejercicio siguiente.

### 9.4 El cambio, en monedas

El más completo: pedir centavos hasta que sean válidos y desglosarlos en
monedas de 25, 10, 5 y 1. Esta es la versión de la guía, con **una** función
para las monedas en vez de cuatro copiadas — que es justo lo que Tcode quiere
que hagas con una función que recibe el valor:

```tcode
#importar "texto.t";

// Cuantas monedas de `valor` caben en `centavos`, restadas una a una.
fn contar_monedas(centavos: i64, valor: i64) -> i64 {
    var resto = centavos;
    var cuantas: i64 = 0;
    while resto >= valor {
        resto = resto - valor;
        cuantas = cuantas + 1;
    }
    return cuantas;
}

// Pide los centavos y los deja en `centavos`.
//
//   0  hay cantidad
//   1  la linea estaba mal escrita: se vuelve a pedir
//   2  la linea estaba vacia, o se acabo la entrada: el atajo de abajo las
//      junta
fn leer_centavos(centavos: mut i64) -> i64 {
    imprimir("Change owed: ");
    let linea = leer_linea() sino nuevo("");
    if largo(linea) == 0 { return 2; }
    let n = a_entero(recortar(linea)) sino 18446744073709551615;
    if n > 9223372036854775807 { return 1; }
    centavos = n como i64;
    return 0;
}

fn main() {
    var centavos: i64 = 0;
    var estado: i64 = 1;
    while estado == 1 {
        estado = leer_centavos(centavos);
    }

    let cuartos = contar_monedas(centavos, 25);
    centavos = centavos - cuartos * 25;
    let dieces = contar_monedas(centavos, 10);
    centavos = centavos - dieces * 10;
    let cincos = contar_monedas(centavos, 5);
    centavos = centavos - cincos * 5;
    let sueltos = contar_monedas(centavos, 1);
    centavos = centavos - sueltos;

    let total = cuartos + dieces + cincos + sueltos;
    imprimir($"quarters {cuartos}, dimes {dieces}, nickels {cincos}, pennies {sueltos}\n");
    imprimir($"{total} total\n");
}
```

```
$ printf '41\n' | ./cambio
Change owed: quarters 1, dimes 1, nickels 1, pennies 1
4 total

$ printf 'hola\n30\n' | ./cambio      # la primera no vale, la segunda si
Change owed: Change owed: quarters 1, dimes 0, nickels 1, pennies 0
2 total

$ printf '' | ./cambio                # fin de entrada: ni se cuelga ni aborta
Change owed: quarters 0, dimes 0, nickels 0, pennies 0
0 total
```

Este ejercicio es el que más reglas del lenguaje toca de golpe:

- **El fin de la entrada y la línea en blanco se juntan con este `sino`.**
  `leer_linea` falla al acabarse la entrada, y `sino nuevo("")` convierte ese
  fallo en la misma cadena vacía que deja un `Enter` a secas. Por eso, **con
  este atajo**, una línea vacía **para** el bucle: si en su lugar volviera a
  pedir, el fin de la entrada sería un bucle infinito pidiendo una línea que ya
  no existe. Pero el runtime **sí los distingue**: el fallo es un fallo y la
  línea en blanco es una cadena vacía con éxito. Con `try`, o con otro `sino`
  que no sea `nuevo("")` —por ejemplo `sino nuevo("<FALLO>")`—, se separan:
  `printf 'a\n\nb\n' | ./programa` da `[a] [] [b] [<FALLO>]` (el valor, la
  línea en blanco, el valor siguiente y el fallo), y una línea en blanco puede
  volver a preguntar mientras el fin de la entrada para.
- **`a_entero` ya lo comprueba todo.** Devuelve `usize` y falla si el texto no
  es un número o si es negativo, así que el `sino 18446744073709551615` cubre
  de una vez «no es número» y «es negativo». El número que sigue es el centinela
  que se compara después.
- **El techo antes de convertir.** `n > 9223372036854775807` corta lo que no
  cabe en `i64`, para que `n como i64` no le dé la vuelta al número.
- **No existe `-=`.** Se escribe `centavos = centavos - cuartos * 25;`. `+=` y
  `-=` no están en el lenguaje, y el error que sale es «se esperaba una
  expresion».
- **`var` en el parámetro, `let` para lo que no cambia.** El parámetro de una
  `fn` es inmutable por defecto; para escribir en él hay que declararlo `mut`.
  Por eso `leer_centavos` devuelve un estado y escribe los centavos por el
  parámetro, en vez de devolver dos cosas.
- **Un `while` de validación puede no dar ni una vuelta**, así que una función
  que promete devolver algo tiene que salir por `return` o `fail` por todos los
  caminos. De ahí el `return 1;` inalcanzable al final de muchas funciones: es
  para el compilador, no para el programa.

### 9.5 Contar palabras y letras

Dos contadores sobre la misma línea. El de palabras es el interesante: hay que
acordarse de si veníamos dentro de una palabra, porque los blancos seguidos
cuentan como un solo corte.

```tcode
#importar "texto.t";
#importar "caracter.t";

fn contar_palabras(texto: view) -> usize {
    var suma = 0;
    var dentro = false;
    for i en 0..largo(texto) {
        if !es_blanco(byte(texto, i)) {
            dentro = true;
        } else if dentro {
            suma = suma + 1;
            dentro = false;
        }
    }
    if dentro { suma = suma + 1; }
    return suma;
}

fn contar_letras(texto: view) -> usize {
    var suma = 0;
    for i en 0..largo(texto) {
        if es_letra(byte(texto, i)) { suma = suma + 1; }
    }
    return suma;
}

fn main() {
    imprimir("Text: ");
    let texto = leer_linea() sino nuevo("");
    imprimir($"palabras {contar_palabras(texto)}, letras {contar_letras(texto)}\n");
}
```

```
$ printf 'Hola, mundo. Adios.\n' | ./contador
Text: palabras 3, letras 14

$ printf '' | ./contador
Text: palabras 0, letras 0
```

- `byte(texto, i)` es el equivalente de `name[i]` cuando quieres **preguntar**
  por el carácter, no imprimirlo: da un número, y `es_blanco` y `es_letra` (de
  `std/caracter.t`) lo entienden.
- Aquí sí hay que separar los dos contadores en dos funciones, porque cada uno
  tiene su estado. `contar_palabras` no puede saber nada de `contar_letras`, y
  ambas reciben `view` para no copiar el texto.
- El contador de palabras es el ejemplo de manual de estado que sobrevive
  dentro de una función: `dentro` empieza en `false`, se enciende con la
  primera letra y se apaga al primer blanco, sumando solo en ese apagado. El
  `if dentro` de después es para la última palabra, que no tiene blanco detrás.

### Lo que se repite

Estos cinco programas usan un puñado de piezas una y otra vez. Merece la pena
reconocerlas:

| pieza | para qué |
|---|---|
| `leer_linea() sino nuevo("")` | leer una línea sin que el fin de entrada reviente |
| `largo(x) == 0` | «no había nada»: fin de entrada o línea en blanco |
| `a_entero(recortar(x)) sino …` | convertir y validar de una vez |
| `fn f(x: mut T) -> i64` | devolver un estado y escribir el valor por el parámetro |
| `while estado == 1 { … }` | validar en bucle hasta que la entrada sirva |
| `for i en 0..largo(v)` | recorrer texto sin `strlen` ni índice que mantener |
| `byte(v, i)` / `rebanar(v, i, i+1)` | preguntar por el carácter / imprimirlo |

Y las tres trampas que se cobran un intento cada una: no hay `+=` ni `-=`, un
`let` no se puede reasignar (usa `var`), y el parámetro de una función es
inmutable salvo que lo declares `mut`. Con los importes, la regla es la misma
que con todo lo demás: cada bloque pide lo que usa. `imprimir`, `leer_linea`,
`largo` y `nuevo` son internas y no piden nada; `recortar`, `a_entero`,
`es_blanco` y `es_letra` viven en `std/` y su fichero se importa, aunque otro
módulo ya lo haya importado por su cuenta.

## Dónde seguir

- **`docs/ESPECIFICACION.md`** — la referencia completa (tipos, reglas de
  préstamo, restricciones).
- **`std/`** — la biblioteca estándar: `texto`, `lista`, `mapa`, `caracter`,
  `bytes`, `numero`, `par`, `iterador`… Es corta y se lee entera en una tarde.
- **`programas/`** — programas reales y pequeños: `wc`, `calc`, `base64`,
  `buscar`, `ordenar`, `json`. Son el mejor curso avanzado.
- **`tests/lenguaje/`** — las propiedades que definen el comportamiento.

Y si algo te rechaza, lee el error: el compilador dice *qué* y *en qué línea*,
y suele explicar *por qué*. Ese cuidado es el idioma del proyecto.
