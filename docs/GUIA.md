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
    let nombre = nuevo("Tcode");        // let: no cambia
    var cuenta = 0;                      // var: cambia
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
    let nombre = nuevo("Tcode");   // str: posee sus bytes
    saludar(nombre);               // se presta como view, sin copiar
}
```

Por qué importa:

1. **Sin copias.** Pasar un `str` a una función que solo lo mira, copiándolo
   entero, sería caro. Con `view` no se toca un byte.
2. **Sin liberaciones dobles ni uso de memoria liberada.** El compilador
   comprueba quién posee y quién presta. Un `view` no puede sobrevivir a lo
   que apunta; un enum **no** guarda un `view`, porque al mirarlo nadie sabría
   de quién presta:

```tcode
enum Resultado {
    Bien(usize),
    Mal(str),      // posee, por eso sí se permite; `Mal(view)` no compila
}
```

Ese rechazo es el compilador cuidándote: en C ese «préstamo guardado» es un
puntero colgante esperando a explotar. Aquí ni compila.

## 6. Genéricos

La misma función, para lo que sea:

```tcode
fn esta_vacia<T>(xs: &lista<T>) -> bool {
    return largo(xs) == 0;
}

fn main() {
    var xs: lista<usize> = [];
    xs.anadir(1);
    imprimir($"vacia: {esta_vacia(xs)}\n");   // false
}
```

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
    if b == 0 { falla "division por cero"; }
    return a / b;
}

fn main() {
    let x = dividir(10, 2) sino 999;    // 5
    let y = dividir(10, 0) sino 0;      // 0, sin reventar
}
```

El `!` dice «esto puede fallar». `sino valor` da un respaldo si falla; `try`
deja subir el fallo al que llama (y solo se puede usar dentro de otra función
`!`). Es el patrón de error del lenguaje: explícito, sin excepciones escondidas.

## Dónde seguir

- **`docs/ESPECIFICACION.md`** — la referencia completa (tipos, reglas de
  préstamo, restricciones).
- **`std/`** — la biblioteca estándar: `texto`, `mapa`, `lista`, `caracter`,
  `bytes`, `numero`, `par`, `iterador`… Es corta y se lee entera en una tarde.
- **`programas/`** — programas reales y pequeños: `wc`, `calc`, `base64`,
  `buscar`, `ordenar`, `json`. Son el mejor curso avanzado.
- **`tests/lenguaje/`** — las propiedades que definen el comportamiento.

Y si algo te rechaza, lee el error: el compilador dice *qué* y *en qué línea*,
y suele explicar *por qué*. Ese cuidado es el idioma del proyecto.
