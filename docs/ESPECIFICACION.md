# Tcode — especificación del lenguaje, v0

## Por qué existe

Tcode salió de auditar **safestr**, una librería de cadenas en C.
Auditándola encontramos cuatro fallos
de seguridad de memoria **en código escrito con cuidado poco común**:
invariantes documentadas, aliasing resuelto a mano, comprobaciones de
desbordamiento por todos lados. Aun así:

| # | Fallo | Clase |
|---|---|---|
| 1 | `ss_reserve` con `n` enorme → bloque de 15 bytes, `capacity` de 2⁶⁴ | desbordamiento de entero → escritura fuera del heap |
| 2 | `ss_appendf(&s, "%s", ss_cstr(&s))` | use-after-free por aliasing a través de un `realloc` |
| 3 | `ss_setf(&s, "[%s]", ss_cstr(&s))` → `"[]"` | resultado silenciosamente incorrecto |
| 4 | `sv_to_long("-9223372036854775808")` | desbordamiento con signo (UB) |

La conclusión no es "hay que escribir mejor C". Es que **esas cuatro clases
no deberían ser expresables**. Ese es el único motivo por el que Tcode
existe.

## Tesis

Un lenguaje de sistemas pequeño donde los cuatro fallos de arriba son
**errores de compilación**, y que compila a C portable.

No aspira a reemplazar a Rust. Aspira a ser lo que un programador de C puede
adoptar en una tarde, porque el resultado es C legible que se enlaza con lo
que ya tiene.

## Las cuatro reglas

### 1. Propiedad y préstamos (mata el fallo 2 y el contrato de `SafeView`)

Un `str` es dueño de su memoria. Un `view` la toma prestada.

Mientras exista un `view` derivado de un `str`, ese `str` **no se puede
mutar ni mover**. Los préstamos terminan al cerrar el bloque donde se
declararon.

```tcode
var s: str = nuevo("hola");
let v: view = vista(s);
empujar(s, " mundo");   // error: `s` está prestado por `v`
```

Esto es exactamente el caso 2 de la tabla, y también el "CONTRATO DE VIDA
ÚTIL" que safestr documentaba y pedía respetar con criterio.

#### Vidas útiles: una vista no sobrevive a lo que presta

La regla anterior vale dentro de una función. Cruzar un `return` necesita
saber **de dónde sale** la memoria a la que apunta la vista:

| Procedencia | ¿Puede salir de la función? |
|---|---|
| un literal | sí: vive lo que dura el programa |
| un parámetro `view` | sí: la memoria es de quien llama |
| un `str` local, o un parámetro `str` por valor | **no**: muere al cerrar |

Se infiere sola, sin anotaciones, atravesando `rebanar` y las llamadas a
otras funciones:

```tcode
fn primero(v: view) -> view { return rebanar(v, 0, 1); }   // ok
fn estatica()      -> view { return "constante"; }         // ok

fn colgante() -> view {
    var s: str = nuevo("hola");
    return vista(s);      // error: `s` muere al cerrar la funcion
}
```

Y el préstamo sigue vivo en quien llama, aunque haya pasado por medio una
función:

```tcode
var s: str = nuevo("hola");
let p: view = primero(vista(s));
empujar(s, "x");          // error: `s` esta prestada por `p`
```

Ante la duda, la inferencia rechaza. Prefiere negarse a un programa correcto
antes que aceptar uno colgante.

Lo que **no** admite v0: devolver una vista de un parámetro `mut str`.
Sería sólido, pero exige seguir el préstamo del que llama a través de la
mutación, y eso todavía no está.

### 2. Aritmética comprobada por defecto (mata los fallos 1 y 4)

`+`, `-` y `*` sobre enteros comprueban desbordamiento. Al desbordar, el
programa aborta con el archivo y la línea. No hay comportamiento indefinido.

Para optar por no comprobar, hay que escribirlo:

```tcode
let a: usize = x *? y;   // multiplicación envolvente, explícita
```

### 3. Sin conversiones implícitas (mata el fallo 4 por otra vía)

No existe la conversión silenciosa entre anchos ni entre signos. `i64` y
`usize` no se mezclan sin decirlo.

### La complejidad vive en una capa, no en la superficie

Las reglas de arriba las comprueba el compilador. Lo que **escribes** no tiene
por qué repetirlas:

```tcode
fn main() {
    let saludo = nuevo("hola, ");
    empujar(saludo, "mundo");
    imprimir(saludo);
}
```

Ahí hay propiedad, un préstamo y una liberación automática, y no se menciona
ninguna. Tres cosas lo hacen posible:

**El tipo se deduce del valor.** `let n = 42;` en vez de `let n: usize = 42;`.
Se escribe sólo cuando dice algo que el valor no dice: `let xs: lista<usize> =
[];`, donde `[]` no revela si es lista, arreglo o mapa. Al quitar las
redundantes de los once ejemplos quedaron **3 de 55**.

**Un `str` se presta solo donde se pide una vista.** `largo(s)` en vez de
`largo(vista(s))`, `empujar(s, t)` en vez de `empujar(s, vista(t))`. El
préstamo ocurre igual y el comprobador lo vigila igual; lo que se ahorra es
deletrearlo. De 56 `vista()` escritas a mano quedaron 5, y las cinco son
vistas con nombre que sí quieren serlo.

**`fn main()` sin ceremonia.** Sin `-> usize`, sin `return 0`. Se declara el
tipo de retorno sólo si el programa devuelve otra cosa.

La regla que decide qué se queda: **puedes bajar a la capa de abajo cuando la
necesitas, y no antes.** `vista(s)` sigue existiendo para cuando quieras
controlar exactamente dónde empieza el préstamo; el tipo escrito sigue
existiendo para cuando el valor no baste. Lo que se quitó no fue capacidad,
fue repetición.

Los tipos de una **firma** no se quitan. Ahí no son ceremonia: son el
contrato, y son donde un error sale con un mensaje bueno en vez de aparecer
tres funciones más allá.

### Prometer un valor obliga a devolverlo

Una función que declara tipo de retorno tiene que salir por `return` o `falla`
en **todos** los caminos. Un `while` no cuenta: puede no dar ni una vuelta.

```
error: `g` promete devolver `usize` pero hay un camino que llega al final
sin `return`
```

`main` es la excepción: si no dice otra cosa, sale con cero.

### 4. Sin valores no inicializados

Toda variable se inicializa en su declaración. `let` es inmutable; `var` es
mutable. La inmutabilidad es lo normal.

### 5. Tipos compuestos: propiedad recursiva y límites comprobados

Un `struct` es dueño de lo que sus campos poseen; un arreglo, de lo que
poseen sus elementos. La liberación se genera sola, en orden y a cualquier
hondura:

```tcode
struct Articulo { nombre: str, unidades: usize }

var inv: [Articulo; 4] = [ crear("tornillos", 420), ... ];
inv[2].unidades = inv[2].unidades + 50;
```

Cuatro `str` vivos ahí dentro, y ni un `ss_free` en el archivo. El compilador
emite `ss_drop_Articulo` y el bucle que lo aplica a los cuatro elementos.

**Todo índice se comprueba.** Salirse no lee memoria ajena: detiene el
programa diciendo dónde.

```
inventario.t:4: indice 3 fuera de rango (el arreglo tiene 3 elementos)
```

Los arreglos se generan envueltos en un struct de C. Un arreglo desnudo de C
no se puede asignar, ni pasar por valor, ni devolver: se degrada a puntero.
El envoltorio le devuelve la semántica de valor que el lenguaje promete.

Lo que v0 **no** admite, y lo dice:

- **Campos `view`.** Es el muro real: una vista dentro de un struct exige que
  la vida útil forme parte del tipo, como `struct Foo<'a>` en Rust. Un campo
  `view` da error y sugiere `str`.
- **Movimientos parciales.** Sacar un `str` de un campo o de un elemento
  dejaría el struct a medio mover o un hueco en el arreglo. Hay que mover el
  contenedor entero.
- **Recursión directa por valor.** `struct Nodo { hijo: Nodo }` no tiene tamaño
  finito y da error; la recursión mediante `lista<Nodo>` sí está permitida.

#### Listas dinámicas

`lista<T>` es una colección dueña cuyo largo se decide en ejecución:

```tcode
var numeros: lista<usize> = [];
var nombres: lista<str> = [nuevo("Ana"), nuevo("Beto")];
anadir(numeros, 10);
anadir(nombres, nuevo("Cielo"));
imprimir(nombres[2]);
```

El buffer crece de forma amortizada. `anadir` exige una lista `var`, mueve el
elemento si éste posee memoria y conserva el tipo concreto también en el C
generado. Al cerrar el bloque se liberan primero los elementos dueños y luego
el buffer. La indexación usa la misma comprobación que los arreglos fijos.

Una lista introduce indirección, por lo que permite estructuras recursivas de
tamaño finito (`struct Nodo { hijos: lista<Nodo> }`). v0 no permite guardar
`view` en listas —necesitaría vidas útiles en el tipo— ni usar un arreglo fijo
como elemento de lista.

### 6. Préstamos: `&T` para leer, `mut T` para modificar

Pasar un valor por nombre lo **mueve**. Para dejárselo a una función sin
entregárselo, se presta:

```tcode
fn describir(a: &Articulo) -> str { ... }        // presta para leer
fn reponer(a: mut Articulo, cuantas: usize) { }  // presta para modificar
```

En C salen como `const Articulo*` y `Articulo*`. El `const` no es adorno: lo
hace cumplir también el compilador de C.

Se puede prestar una variable, un campo o un elemento, así que `inv[i]` deja
de tener que desmontarse en campos sueltos.

Lo que se presta no se puede mover: la función no es su dueña.

```
error: `p` llego prestado: esta funcion no es su duenia y no puede
entregarlo. Pasa una copia, o recibelo por valor
```

Y lo prestado sólo para leer no se modifica, con un mensaje que dice el
arreglo verdadero en vez de sugerir `var`:

```
error: `p` llego prestado solo para leer (`&`): para modificarlo, recibelo
como `mut P`
```

**Dos préstamos de lo mismo sólo conviven si ninguno modifica.** Si no, el
callee tendría dos nombres para la misma memoria y podría escribir por uno
mientras lee por el otro:

```
error: `p` se presta dos veces en la misma llamada a `g` (como `a` y como
`b`), y al menos uno de los dos puede modificarlo
```

v0 mira la variable entera, así que rechaza prestar dos campos distintos del
mismo struct aunque no se solapen. Es conservador a propósito, y el mensaje
lo dice.

### 7. Módulos: un archivo es un módulo

```tcode
usar "lib/texto.t";
usar "lib/calculo.t";
```

Las rutas son relativas al archivo que las escribe. Cada módulo se carga una
sola vez aunque lo pidan varios, y las dependencias circulares se detectan y
se explican:

```
error: dependencia circular entre modulos: a.t -> b.t -> a.t
```

`usar "std/texto"` busca en la biblioteca que viene con el compilador, no
junto al programa. La extensión `.t` es opcional: se escribe el nombre del
módulo, no el del archivo.

### Espacios de nombres

Los nombres se resuelven **por archivo**: cada uno ve lo que él mismo
importa, y nada más. Dos módulos pueden declarar `contar` sin estorbarse.

```tcode
usar "lib/celsius.t" como c;
usar "lib/fahrenheit.t" como f;

imprimir(c.nombre());        // "Celsius"
imprimir(f.nombre());        // "Fahrenheit"
```

`usar` a secas trae los nombres tal cual. Sólo choca si **un mismo archivo**
trae dos iguales de forma llana, y entonces el error dice de dónde vienen los
dos y cómo arreglarlo:

```
error: app.t:2: `contar` llega de dos sitios, uno.t y dos.t. Dale un nombre
                a uno de los dos: `usar "..." como algo;` y luego
                `algo.contar`
```

Vale también para los tipos: `t.Caja`, `t.Par<usize, str>`.

`como` **no es palabra reservada**: sólo significa eso detrás de una ruta de
`usar`, así que sigue valiendo como nombre de variable.

#### Qué se tomó de dónde

| lenguaje | cómo lo hace | qué nos llevamos |
|---|---|---|
| **Python** | `import m as x`, resolución por archivo | el modelo entero: cada archivo ve lo suyo |
| **Rust** | `use a::b as c` | la grafía del renombrado |
| **Go** | obliga a calificar siempre: `pkg.F()` | lo que **no** copiamos: calificar cuando no hace falta es ruido |
| **C++** | `using namespace`, ADL | el contraejemplo: nombres que aparecen sin que nadie los pida |

Y un detalle propio: **el renombrado interno sólo ocurre cuando un nombre lo
declara más de un módulo.** Mientras `palabras` sea de uno solo, en el C
generado se sigue llamando `palabras`. Eso importa porque el C generado es
para leerlo: ensuciar todos los nombres para resolver un choque que casi
nunca pasa sale caro y no compra nada.

### 8. Fallos: no se pueden ignorar

Una función que puede fallar lo declara con `!` después del tipo de retorno,
y sale con `falla`:

```tcode
fn dividir(a: usize, b: usize) -> usize ! {
    if b == 0 {
        falla "division por cero";
    }
    return a / b;
}
```

Quien la llama tiene que decir qué hace con el fallo. No hay una tercera
opción, y olvidarse es un error de compilación:

| | |
|---|---|
| `try f(..)` | el fallo sube al que llamó; sólo dentro de otra función `!` |
| `f(..) sino valor` | si falla, se usa `valor` |

```
error: `porcentaje` puede fallar: la llamada tiene que ir detras de `try`,
o con `sino <valor>` para dar un valor cuando falle
```

`main` también puede declararse `!`. Si termina en fallo, el programa
imprime `error: <motivo>` por la salida de error y devuelve un código
distinto de cero, para que no se pierda al salir.

**Un fallo libera lo que ya se había reservado.** Es la parte que cuesta
hacer bien a mano en C, y es donde estaba el problema: una variable que un
`return` posterior entrega no está movida todavía en el `falla` de antes. El
compilador lleva una bandera en tiempo de ejecución para las variables que se
mueven en algún camino, y libera según el camino que se tomó de verdad.

**La regla es una sola, y vale para toda construcción presente y futura:**

> `return x` entrega `x` ahí mismo y no vuelve, así que no hace falta
> bandera. **Cualquier otro movimiento** puede no llegar a ocurrir —la
> alternativa de un `sino`, un argumento en una expresión que se evalúa a
> medias— y entonces la variable sigue siendo nuestra por el otro camino, y
> lleva bandera.

Ante la duda, bandera. Cuesta un `bool` que el compilador de C elimina en
cuanto puede demostrar que sobra: en `hola.t` no se genera ninguna.

Del lado del generador, quien abre un camino de ejecución lo hace con un
`with camino():` que apaga dentro de esa rama lo que se haya entregado en
ella. Se hizo así a propósito: una construcción nueva no puede olvidarse del
apagado porque no hay nada que recordar. Es la diferencia entre una regla y
una costumbre — y esa diferencia costó tres fugas (`falla`, `try` y `sino`),
cada una encontrada corriendo, no leyendo.

Lo que v0 no admite: `try` y `sino` en la condición de un `while` (se
evaluaría una sola vez), y el motivo es un literal, no un texto construido.

### 9. Entrada de archivos y texto construido

`leer_archivo(ruta) -> str !` lee el archivo completo en modo binario. Es
falible, así que exige `try` o `sino`; distingue apertura, lectura y falta de
memoria sin dejar buffers ni descriptores abiertos. Los bytes cero se
conservan. `byte(texto, i)` devuelve un valor entre 0 y 255 y comprueba el
índice.

`texto(x) -> str` materializa `usize`, `i64`, `bool`, `view` o `str`. Es la
pieza mínima para construir mensajes sin introducir todavía interpolación ni
un sistema de formatos.

### Avisos

Un aviso no impide compilar; señala algo que probablemente no era lo que se
quería. Un `_` delante del nombre lo silencia, y de paso le dice a quien lea
el código que es a propósito.

- variable declarada y nunca usada
- valores que se asignan y nunca se leen
- `var` que nunca se modifica: puede ser `let`
- parámetro que no se usa
- parámetro `mut T` que nunca se modifica: podría ser `&T`

`--avisos-como-errores` los convierte en errores; `--sin-avisos` los calla.

### Ver lo que el compilador infirió

El análisis de propiedad y préstamos normalmente sólo se ve cuando falla.
`tcode programa.t --explicar` lo muestra cuando sale bien: por variable, si
es dueña o prestada, dónde se mueve, dónde se libera, y de dónde sale cada
vista. Es el mismo modelo que produce los errores, escrito en positivo.

## Gramática v0

```
programa   := usar* (struct | enum | externo | funcion)*
usar       := "usar" cadena ";"
struct     := "struct" ident "{" (ident ":" tipo ",")* "}"
enum       := "enum" ident "{" (variante ",")* "}"
variante   := ident ("(" tipo ("," tipo)* ")")?
externo    := "externo" cadena "{" firma* "}"
firma      := "fn" ident "(" params? ")" ("->" tipo)? ";"
funcion    := "fn" ident "(" params? ")" ("->" tipo)? "!"? bloque
params     := param ("," param)*
param      := ident ":" ("mut" | "&")? tipo
tipo       := "str" | "view" | "usize" | "i64" | "bool"
            | "lista" "<" tipo ">"
            | IDENT_STRUCT | "[" tipo ";" entero "]"
bloque     := "{" sentencia* "}"

sentencia  := "let" ident ":" tipo "=" expr ";"
            | "for" ident ("," ident)? "en" expr bloque
            | "break" ";" | "continue" ";"
            | "var" ident ":" tipo "=" expr ";"
            | lugar "=" expr ";"
            | "if" expr bloque ("else" bloque)?
            | "while" expr bloque
            | "return" expr? ";"
            | "falla" cadena ";"
            | match
            | expr ";"

match      := "match" expr "{" brazo* "}"
brazo      := patron "->" (expr "," | bloque ","?)
patron     := "_" | ident "." ident ("(" ident ("," ident)* ")")?

expr       := o ("sino" o)?
o          := y ("||" y)*
y          := igualdad ("&&" igualdad)*
igualdad   := comparacion (("==" | "!=") comparacion)*
comparacion:= suma (("<" | "<=" | ">" | ">=") suma)*
suma       := producto (("+" | "-" | "+?" | "-?") producto)*
producto   := unario (("*" | "/" | "%" | "*?") unario)*
unario     := "try" unario | ("!" | "-") unario | postfijo
postfijo   := primario ("." ident | "[" expr "]")*
lugar      := ident ("." ident | "[" expr "]")*
primario   := entero | cadena | interpolada | "true" | "false" | ident
            | ident "(" args? ")" | "(" expr ")" | match
            | IDENT_ENUM "." ident ("(" args? ")")?
            | IDENT_STRUCT "{" (ident ":" expr ",")* "}"
            | "[" (expr ",")* "]"
```

## Funciones internas (v0)

Cada una es una operación de la librería de C, con la regla de préstamo que
le corresponde.

| safestr | C generado | efecto sobre préstamos |
|---|---|---|
| `nuevo(cadena) -> str` | `ss_from` | crea un dueño |
| `vacio() -> str` | `ss_new` | crea un dueño |
| `vista(s: str) -> view` | `ss_view` | **presta** `s` |
| `empujar(s: mut str, x)` | `ss_append` / `ss_append_view` | **muta** `s` |
| `largo(x) -> usize` | `ss_len` / `sv_len_of` | solo lee |
| `igual(a: view, b: view) -> bool` | `sv_equals` | solo lee |
| `rebanar(v: view, a, b) -> view` | `sv_slice` | hereda el préstamo de `v` |
| `imprimir(x)` | `printf` | solo lee |
| `anadir(xs: mut lista<T>, x: T)` | `realloc` + asignación comprobada | **muta** `xs`, mueve `x` si es dueño |
| `leer_archivo(ruta: view) -> str !` | `fopen` / `fread` / `fclose` | crea un dueño; el fallo es explícito |
| `byte(texto: view, i) -> usize` | acceso con límite comprobado | solo lee |
| `texto(x) -> str` | `ss_appendf` / copia | crea un dueño |

### 10. Mapas y argumentos

`mapa<K, V>` es una tabla hash dueña de sus claves:

```tcode
var cuenta: mapa<str, usize> = [];
poner(cuenta, "hola", 1);
let n: usize = obtener(cuenta, "hola") sino 0;
```

| operación | qué hace |
|---|---|
| `poner(m: mut mapa<K,V>, clave, valor)` | inserta o reemplaza; el mapa **copia** la clave |
| `obtener(m, clave) -> V !` | falible: una clave ausente no es un caso especial, es un fallo |
| `tiene(m, clave) -> bool` | sin construir el valor |
| `claves(m) -> lista<K>` | copias, para poder recorrerlo |
| `largo(m) -> usize` | cuántas entradas |

Por dentro es direccionamiento abierto con sondeo lineal y capacidad
potencia de dos, que crece al 70% de ocupación. En v0 no hay borrado, así que
tampoco lápidas: una celda con clave vacía corta la búsqueda.

Que `obtener` sea falible no es celo: es la misma decisión que en
`leer_archivo`. Una clave que no está no es un valor, y devolver un cero
disfrazado es exactamente cómo se cuelan los errores.

**Los dos límites de v0, dichos donde se declara el mapa:**

- **La clave tiene que ser `str`.** Se consulta con un `view`, sin copiar.
- **El valor es un escalar o un `str`.** Para un escalar, `obtener` devuelve
  una copia; para un `str`, **devuelve una vista prestada del texto que ya
  vive dentro de la tabla**, así que no se saca al dueño ni se copia nada:

  ```tcode
  var cfg: mapa<str, str> = [];
  poner(cfg, "host", nuevo("localhost"));
  let h: view = obtener(cfg, "host") sino "(sin valor)";
  ```

  Esa vista presta del mapa, así que modificarlo mientras viva es un error:

  ```
  error: no se puede modificar `cfg`: esta prestada por `h`
  ```

  Y no puede salir de la función, por la misma regla que cualquier vista de
  algo local.

  Para un struct, `obtener` devuelve un **`&V`**: un préstamo de solo
  lectura del valor que está en la tabla.

  ```tcode
  struct Simbolo { tipo: str, mutable: bool, usos: usize }

  var tabla: mapa<str, Simbolo> = [];
  poner(tabla, "n", Simbolo { tipo: nuevo("usize"), mutable: false, usos: 3 });
  let s: &Simbolo = try obtener(tabla, "n");
  imprimir($"{s.tipo} usado {s.usos} veces");
  ```

  `sino` no vale aquí, y el error lo dice: si la clave no está, no hay nada
  que prestar. O se usa `try`, o se pregunta antes con `tiene`.

### Argumentos de la línea de órdenes

```tcode
if n_argumentos() < 2 {
    imprimir("uso: "); imprimir(argumento(0)); imprimir(" <archivo>\n");
    return 1;
}
let ruta: view = argumento(1);
```

`argumento(0)` es el nombre del programa, como en C. Devuelve `view` y no
reserva nada: `argv` vive tanto como el proceso, así que esa vista nunca
cuelga —el compilador lo sabe y la trata como estática—. El índice se
comprueba.

### 11. Salida, escritura y orden

`imprimir` va al resultado; `imprimir_error` al diagnóstico. Separarlos no es
cosmético: es lo que permite encauzar una herramienta sin que se le cuelen
los mensajes de uso.

```tcode
imprimir_error("uso: "); imprimir_error(argumento(0));
```

`escribir_archivo(ruta, datos) !` escribe en binario, conserva los bytes cero
y es falible como su gemela de lectura.

Para el orden hay dos piezas:

| | |
|---|---|
| `menor(a: view, b: view) -> bool` | orden lexicográfico sobre texto |
| `ordenar(xs: mut lista<T>)` | ordena en el sitio |

`ordenar` sólo funciona sobre `usize`, `i64`, `bool` y `str`, que son los
tipos con un orden evidente. **Un struct no lo tiene**: cuál de sus campos
manda es una decisión del programa, no del lenguaje, y el compilador lo dice
en vez de inventarse uno.

### Borrado en los mapas

`quitar(m: mut mapa<K,V>, clave) -> bool` devuelve si había algo que quitar,
para poder distinguir *lo borré* de *no estaba* sin consultar antes.

Por dentro cierra el hueco arrastrando hacia atrás las entradas del mismo
grupo que quedarían inalcanzables, en vez de dejar una lápida. Es lo que
permite que la búsqueda siga pudiendo parar en la primera celda libre.

### 12. Recorridos

```tcode
for x en xs {
    if x == 7 { continue; }
    if x > 20 { break; }
    imprimir(x);
}
```

Recorre una `lista<T>`, un arreglo o un `mapa<K, V>`. Sobre un mapa se
pueden pedir los dos:

```tcode
for clave, veces en cuenta {
    imprimir(clave); imprimir(": "); imprimir(veces); imprimir("\n");
}
```

**Recorrer un mapa no copia nada.** `claves(m)` existe todavía y sirve
cuando hace falta ordenar, pero clona el vocabulario entero; el recorrido
directo presta las claves que ya están en la tabla:

```c
if (m.claves[ss_k1].data == NULL) continue;
const SafeString* k = &m.claves[ss_k1];
size_t v = m.valores[ss_k1];
```

Con 120.000 palabras la diferencia es real: 0,05 s y 20 MB recorriendo
directo contra 0,08 s y 24 MB pasando por `claves`. Con vocabularios
pequeños no se nota, y decirlo importa tanto como el número.

**El elemento llega prestado, no copiado.** Un `str` copiado tendría dos
dueños, así que dentro del bucle la variable es de sólo lectura: no se mueve
ni se modifica. Los escalares van por valor porque no hay nada que duplicar.
En el C generado se ve tal cual:

```c
const SafeString* n = &ns.e[ss_k2];
```

**Y el bucle presta la colección mientras dura.** Modificarla por dentro
movería los elementos bajo los pies del recorrido:

```
error: no se puede modificar `xs`: esta prestada por `<el for de la linea 4>`
```

Eso es la invalidación de iteradores —el fallo clásico de `vector` en C++ y
de `map` en Go— dicho antes de compilar, sin coste en ejecución.

`break` y `continue` liberan lo reservado en la vuelta antes de saltar, que
es lo que en C hay que recordar a mano:

```c
if ((sv_len_of(ss_view(n)) > (size_t)4))
{
    ss_free(&etiqueta);
    break;
}
```

Sobre los nombres: `for`, `break` y `continue` se reconocen en cualquier
lenguaje y leerlos en inglés no cuesta nada; `en` se eligió en español
porque ahí `in` no aportaba nada a quien escribe el resto en español.

### 13. Cadenas interpoladas

```tcode
let aviso: str = $"linea {n}: `{palabra}` aparece {veces} veces";
imprimir($"[{i}]");
```

El `$` delante distingue una cadena interpolada de una normal, así que los
literales de siempre siguen siendo literales. Dentro de `{}` cabe **cualquier
expresión** del lenguaje, y se analiza con las reglas de siempre: `{n + 1}`,
`{obtener(m, k) sino ""}`, `{a.campo}`. Para escribir una llave, `{{` y `}}`.

No hay formato en tiempo de ejecución. Cada hueco se convierte con las
mismas reglas que `imprimir`, y como el tipo se conoce al compilar, el C que
sale es una secuencia de `ss_append_view` — no un `printf` con cadena
variable. Un `{}` sobre una lista o un struct es un error de compilación, no
un `?` en la salida.

## Autoanálisis

El **frontend de Tcode, escrito en Tcode**: 884 líneas entre
`ejemplos/lexer/lib/lexico.t` (léxico), `lexer.t` y `parser.t` (sintaxis).

Sobre los doce `.t` del repositorio —incluidos ellos mismos— producen 9.099
tokens idénticos a los del compilador y 4.592 nodos, aceptando y rechazando
exactamente los mismos archivos. No es una demostración: está en la suite y
se comprueba en cada ejecución.

Escribir el parser sacó cuatro fallos del lenguaje que ningún ejemplo pequeño
había tocado, y que están corregidos:

- Una vista derivada de un parámetro prestado se trataba como local, así que
  no podía salir de la función aunque la memoria fuera de quien llamó.
- Los nombres de struct no cruzaban de un módulo a otro.
- Mover dentro de un `if` estaba prohibido, y el plegado de un parser es
  exactamente eso.
- Las dos ramas de un `if` compartían el estado de movimientos, como si se
  ejecutaran las dos.

Y dos del generador: la asignación liberaba el valor viejo aunque ya se
hubiera movido —doble `free`— y una sentencia que descartaba un valor dueño
lo filtraba.

### 14. `&T`: préstamos como tipo

`&T` no es solo una marca de parámetro: es un tipo. Un valor `&T` apunta a
algo que vive en otro sitio y es de solo lectura.

```tcode
let s: &Simbolo = try obtener(tabla, "n");
imprimir(s.tipo);          // se leen sus campos
```

Las reglas son las de cualquier préstamo, y se comprueban igual:

- Mientras viva, lo prestado no se puede modificar ni mover.
- No puede salir de la función si presta de algo local.
- No se puede mover: no es suyo.
- Un mapa guarda valores, no préstamos: `mapa<str, &T>` es un error.

En C sale como `const T*`, así que el propio compilador de C también
impide escribir a través de él.

### `&mut T`: préstamos que sí escriben

`obtener_mut(m, clave) -> &mut V !` presta para modificar lo que ya está
guardado, sin sacarlo ni reemplazarlo:

```tcode
let s: &mut Simbolo = try obtener_mut(tabla, "n");
s.usos = s.usos + 1;
empujar(s.tipo, ".");
```

En C es un `T*` sin `const`. Las reglas son las que ya tenía el lenguaje, sin
añadir ninguna:

```
error: no se puede modificar `tabla`: esta prestada por `s`
```

Eso rechaza `poner` y `quitar` mientras el préstamo viva —importante, porque
un `poner` puede disparar el rehash y mover el valor bajo los pies del
puntero— y también un segundo `obtener_mut`.

`mut T`, `&T` y `&mut T` en la posición de un parámetro son la misma idea:
`x: mut T` y `x: &mut T` prestan para modificar, `x: &T` presta para leer.

Se presta lo que tiene partes. Un escalar se copia y ya está, así que
`&usize` da error y lo dice.

**Qué se comprueba y qué no.** Tcode garantiza seguridad de memoria, no
acceso exclusivo: recorrer un mapa mientras existe un `&mut` suyo está
permitido, porque leer no reubica nada. Lo que sí se impide es todo lo que
puede mover la memoria bajo un préstamo vivo.

## La biblioteca estándar

`std/` es Tcode escrito en Tcode. Nada de lo que hay ahí necesita el
compilador: son funciones normales, con las mismas reglas de propiedad que
cualquier otra.

| módulo | qué trae |
|---|---|
| `std/caracter` | `es_blanco`, `es_digito`, `es_letra`, `es_alfanumerico`, `es_minuscula`, `es_mayuscula` |
| `std/texto` | `palabras`, `terminos`, `partir`, `unir`, `recortar`, `rellenar`, `alinear`, `minusculas`, `repetir`, `reemplazar`, `empieza_con`, `termina_con`, `contiene`, `indice_de`, `a_entero` |
| `std/lista` | `suma`, `maximo`, `minimo`, `media`, `invertir` sobre `lista<usize>`; `incluye`, `posicion`, `primeras`, `invertida` sobre `lista<str>` |
| `std/numero` | `dividir`, `resto`, `porcentaje`, `menor_de`, `mayor_de`, `acotar` |
| `std/cuenta` | `contar` y `mayores` — lo que en Python es `Counter` y `most_common` |
| `std/mapa` | `acumular`, `obtener_o`, `claves_ordenadas`, `completar`, `cuantas_claves` |
| `std/conjunto` | `Conjunto` sobre un mapa: `union`, `interseccion`, `diferencia` |
| `std/par` | `Par<A, B>`: dos valores juntos, para cuando uno no basta |
| `std/bytes` | enteros en orden de red, `a_hex`, `de_hex` |
| `std/vector` | `Vector<T>` sobre `bloque<T>`, escrito entero en Tcode |
| `std/formato` | `con_decimales`, `con_millares`, tablas alineadas |
| `std/prueba` | afirmaciones y resumen: probar Tcode desde Tcode |

Dos nombres piden explicación. `palabras` parte por espacios y `terminos`
por cualquier cosa que no sea letra ni dígito: lo primero es lo que quiere
quien separa campos de una línea, lo segundo lo que quiere un contador de
palabras. Y partir texto se llama `partir`, no `dividir`, porque `dividir`
es la división de `std/numero`: dos cosas distintas no pueden compartir
nombre mientras no haya espacios de nombres.

`std/lista` tiene dos familias casi iguales, una por tipo de elemento. Eso
es lo que cuesta no tener genéricos todavía, y se ve.

Lo que gana el programa que las usa se ve mejor que se explica:

```tcode
usar "std/cuenta";

fn main() -> usize ! {
    let texto = try leer_archivo(argumento(1));
    let cuenta = contar(palabras(minusculas(texto)));

    for palabra en mayores(cuenta, 5) {
        imprimir($"{obtener(cuenta, palabra) sino 0}  {palabra}\n");
    }
}
```

Eso mismo eran **107 líneas** antes de que existiera `std/`. En Python son 5.
Las cuatro de diferencia son el `usar`, el `try` al leer el archivo, y que
`obtener` devuelve un fallo en vez de un cero disfrazado: es decir, justo lo
que compra las garantías.

**Encadenar llamadas funciona**: `contar(palabras(minusculas(texto)))`. Un
valor recién creado se puede prestar, aunque no tenga nombre — el compilador
lo guarda hasta el final de la sentencia y lo libera ahí. Eso vale también
donde el valor se devuelve: `return $"[{rellenar(v, 8)}]"` suelta el `str`
de `rellenar` antes de salir, no después.

## Genéricas

Una función puede dejar tipos sin decidir: `fn primeras<T>(xs: &lista<T>,
n: usize) -> lista<T>`. Dentro de la firma y del cuerpo, `T` es un tipo más.

No hay borrado de tipos ni casts escondidos: de cada genérica sale **una
copia por cada juego de tipos con que se use**, y esa copia se comprueba
entera con los tipos ya puestos. Eso tiene una consecuencia que conviene ver
antes de escribir la primera:

```tcode
fn primeras<T>(xs: &lista<T>) -> lista<T> {
    var salida: lista<T> = [];
    for x en xs { anadir(salida, x); }
    return salida;
}
```

Con `T = usize` compila: copiar un número de una lista prestada no le quita
nada a nadie. Con `T = str` **no**, y el error lo dice:

```
error: ejemplo.t:3: `x` llego prestado: esta funcion no es su duenia y no
                    puede entregarlo. Pasa una copia, o recibelo por valor
  al usar `primeras` con T = str, desde ejemplo.t:9
```

La última línea es deliberada. Un error dentro de una genérica no se entiende
sin saber con qué tipos se la usó ni desde dónde: es lo que hace ilegibles los
errores de plantillas de C++, y aquí se dice en una línea, de dentro hacia
fuera.

**Los tipos se deducen de los argumentos; no se escriben.** No existe
`primeras<str>(xs)`. La razón es la gramática: `f<str>(x)` no se distingue de
`f < str > (x)` sin mirar mucho más allá, y preferimos una gramática sin
trucos. Si los argumentos no bastan para deducir un tipo, el compilador lo
dice y pide que se guarde el argumento en una variable con su tipo escrito.

Un mismo parámetro de tipo es un solo tipo en toda la llamada. `dos(1, s)`
sobre `fn dos<T>(a: T, b: T)` no compila, y el error dice qué argumento
fijó `T` primero.

Lo que **no** hay todavía: restricciones sobre `T`. Por eso `std/lista` sigue
teniendo una familia por tipo de elemento: `suma` necesita sumar, `incluye`
necesita comparar y `primeras` necesita copiar el elemento. Sin poder exigir
eso de `T`, esas funciones no pueden ser genéricas. Las que sí lo son
—`esta_vacia`, `ultima_posicion`— son justo las que no miran dentro del
elemento. Tampoco hay structs genéricos.

## `copiar`: copia profunda, explícita, sin anotar nada

`copiar(x)` da una copia independiente de cualquier valor: un número, un
`str`, un struct, una `lista<lista<str>>`, un `mapa<str, V>`. Tocar el
original después no toca la copia.

```tcode
let copia = copiar(xs);
empujar(xs[0], "!!");      // `copia` sigue como estaba
```

El copiador lo genera el compilador, uno por tipo, recursivo, y es el espejo
exacto de la liberación: **si el compilador sabe soltar un tipo, sabe
duplicarlo**. Eso no es una coincidencia feliz, es la misma información.

### Qué se tomó de dónde

| lenguaje | qué hace | qué nos llevamos |
|---|---|---|
| **Rust** | `Clone`, explícito, con `#[derive(Clone)]` en cada tipo | la explicitud: una copia profunda nunca es implícita |
| **C++** | constructores de copia implícitos | el contraejemplo: copias accidentales de O(n) que nadie escribió |
| **Swift** | semántica de valor con copy-on-write | la ergonomía, pero no el precio: esconde el coste y pide contar referencias |
| **Go** | no hay; te la escribes a mano cada vez | el aviso de lo que pasa si no existe |
| **Zig** | explícito, y el alojador se pasa a mano | que reservar memoria se vea |

Dónde lo mejoramos: en Rust hay que poner `#[derive(Clone)]` en cada tipo, y
si falta, el error aparece lejos de donde está el problema. Aquí **todo tipo
es copiable, siempre, sin escribir nada**, y se puede porque en Tcode no hay
semánticas que respetar: no hay `Rc`, ni punteros crudos, ni destructores que
la persona haya escrito. La estructura del tipo es toda la verdad. Se queda
la explicitud de Rust y se va la ceremonia.

Dónde somos peores, y conviene decirlo: `copiar(n)` sobre un número y
`copiar(m)` sobre un mapa grande se escriben igual, así que el coste no se ve
en la forma. Lo único que lo delata es que es una llamada y no una asignación.

### En una genérica

`copiar` es lo que permite que una genérica que necesita duplicar el elemento
lo sea de verdad:

```tcode
fn primeras<T>(xs: &lista<T>, cuantas: usize) -> lista<T> {
    var salida: lista<T> = [];
    var i = 0;
    for x en xs {
        if i == cuantas { break; }
        anadir(salida, copiar(x));
        i = i + 1;
    }
    return salida;
}
```

Eso compila para `T = usize`, `T = str` y `T = Cosa`. Sin `copiar` había que
escribir `x` en un caso y `nuevo(vista(x))` en otro, y no hay forma de
escribir las dos a la vez.

Para sumar o comparar el elemento hace falta exigírselo a `T`, y eso son las
restricciones.

## Restricciones sobre `T`

Lo que el cuerpo necesita del elemento va escrito en la firma:

```tcode
fn suma<T: numero>(ns: &lista<T>) -> T
fn incluye<T: igualable>(xs: &lista<T>, aguja: &T) -> bool
fn maximo<T: ordenable>(xs: &lista<T>) -> T !
```

Hay cuatro, y son **conjuntos de tipos con nombre**:

| restricción | tipos | para qué |
|---|---|---|
| `numero` | `usize`, `i64` | `+`, `-`, `*`, `/`, `%` |
| `igualable` | `usize`, `i64`, `bool`, `str`, `view` | `igual` |
| `ordenable` | `usize`, `i64`, `str`, `view` | `menor` |
| `texto` | `str`, `view` | lo que trabaja sobre bytes |

Una restricción **no es una interfaz que haya que implementar**. `usize`
cumple `numero` sin que nadie escriba nada en ningún sitio.

### Qué se tomó de dónde

| lenguaje | cómo lo hace | qué nos llevamos |
|---|---|---|
| **Go** (1.18) | *type sets*: `interface { ~int \| ~float64 }` | la grafía. Un conjunto de tipos, sin `impl`, sin coherencia, sin huérfanos |
| **Rust** | traits, con `impl` por tipo | lo que **no** copiamos: el sistema entero es mucha maquinaria para lo que hacía falta |
| **C++20** | *concepts*, predicados sobre expresiones | la pragmática: el cuerpo se sigue comprobando por instancia |
| **C++ pre-20** | SFINAE | el contraejemplo: el error sale de tres niveles más adentro |

**Dónde somos peores que Rust, y hay que decirlo.** En Rust el cuerpo de una
genérica se comprueba **una vez**, contra la restricción: si compila, compila
para todo `T` que la cumpla. Aquí no. La restricción se comprueba en la
llamada, y el cuerpo se sigue comprobando una vez por instancia. Puede pasar
que una genérica con restricción falle igualmente dentro del cuerpo para
algún tipo del conjunto. Es más débil, y es a propósito: un sistema de traits
completo es mucho más de lo que v0 necesita.

**Dónde somos mejores que no tenerlas.** El valor está en dónde aparece el
error:

```
$ cat sin.t
fn suma<T>(ns: &lista<T>) -> T { var t = ns[0]; return t; }

error: sin.t:1: en v0 no se puede sacar un elemento de un arreglo: dejaria
                un hueco. Mueve el arreglo entero
  al usar `suma` con T = str, desde sin.t:5
```

```
$ cat con.t
fn suma<T: numero>(ns: &lista<T>) -> T { ... }

error: con.t:6: `suma` pide que `T` sea `numero`, y aqui `T` es `str`.
                `numero` son: `i64`, `usize`
```

El primero te cuenta un problema de propiedad que no tienes. El segundo te
dice qué se pedía, qué diste y qué valdría.

### `igual` y `menor` sobre cualquier tipo sin partes

Para que un cuerpo genérico pueda comparar, `igual` y `menor` dejaron de ser
sólo de texto: valen para dos valores del mismo tipo sin partes —números,
`bool` en `igual`, `str` y `view`—. Sobre escalares bajan a `==` y `<` de C;
sobre texto, a `sv_equals` y `sv_cmp`.

Un struct o una lista **no** se comparan: habría que decidir qué significa, y
eso no se decide en silencio por quien escribe el programa.

## Structs genéricos

```tcode
struct Pila<T> { cosas: lista<T> }
struct Par<A, B> { primero: A, segundo: B }
struct Nodo<T> { valor: T, hijos: lista<Nodo<T>> }
```

Igual que las funciones: una copia por cada juego de tipos, y cada copia es
un struct normal a partir de ahí. `Nodo<T>` se contiene a sí mismo a través
de una lista, que es finito, y funciona.

El literal **no lleva los tipos**: salen de donde va a parar el valor, y si
de ahí no salen, de lo que hay en los campos.

```tcode
var ps: Pila<str> = Pila { cosas: [] };   // de la anotación
let t = par(nuevo("clave"), 9);           // de los argumentos
```

Si de ninguno de los dos sale, el compilador lo dice y pide la anotación.

`std/par` es la prueba de que sirve: una función devuelve un valor, y cuando
hacen falta dos, `Par<A, B>` los junta. **El compilador no sabe nada de
`Par`**: es un struct genérico corriente escrito en Tcode, con las mismas
reglas de propiedad que cualquier otro, y si `A` o `B` poseen memoria, el par
la posee y se libera solo.

Eso es lo que separa "un lenguaje con dos colecciones" de un lenguaje:
`lista<T>` y `mapa<K, V>` siguen dentro del compilador, pero ya no hacen
falta para escribir un contenedor.

## Enteros de ancho fijo, bits y bytes

`u8`, `u16`, `u32`, `u64`, `usize`, `i8`, `i16`, `i32`, `i64`. El ancho va en
el nombre, menos en `usize`, que mide cosas de la máquina y por eso vale lo
que valga ahí.

**La aritmética comprobada vale para todos.** Un `u8` que se pasa de 255
detiene el programa igual que un `usize` que se pasa de `SIZE_MAX`:

```
ejemplo.t:3: desbordamiento en `+`
```

Sólo se emiten las familias de operaciones que el programa usa: uno que sólo
maneja `usize` no carga con las nueve.

### Conversión: `como`

```tcode
let ancho = a como u32;     // aborta si el valor no cabe
let corto = v como? u8;     // se queda con los bits de abajo, a propósito
```

El `?` es el mismo de `+?`: *quiero salirme de la comprobación y lo digo*.
La comprobación es **de ida y vuelta** —se convierte, se vuelve a convertir
al tipo de origen, y si no sale lo mismo es que no cabía— así que vale para
cualquier pareja, con signo o sin él, sin comparar límites de tipos distintos.

```
ejemplo.t:2: el valor no cabe en `u8` viniendo de `u32`
```

### Bits

`&`, `|`, `^`, `<<`, `>>`, y `~` delante.

**Atan más que las comparaciones.** En C, `a & b == c` significa
`a & (b == c)`, que no es lo que nadie quiere y lleva cuarenta años obligando
a poner paréntesis. Aquí, como en Rust y en Go, es `(a & b) == c`.

Desplazar más que el ancho del tipo **detiene el programa** en vez de ser
comportamiento indefinido, y desplazar un negativo a la izquierda se hace
sobre los bits, no sobre el valor.

Un efecto de todo esto: `lista<lista<str>>` acaba en dos `>` pegados, que el
lexer lee como `>>`. Donde toca cerrar un tipo, el token se parte en dos. Es
lo mismo que hizo C++11 después de veinte años obligando a escribir `> >`
con un espacio en medio.

### Bytes

Un `str` guarda **bytes**, no texto. Puede llevar un cero dentro:

```tcode
let crudo = "\xde\xad\xbe\xef";    // 4 bytes
let cero  = "a\x00b";                // 3 bytes
let texto = "camión";                // 7 bytes, UTF-8 intacto
```

`\xNN` es un byte y nada más: no se confunde con el carácter Unicode del
mismo número, que en UTF-8 ocuparía dos. `empujar_byte(s, b)` añade uno.

Con eso, `std/bytes` hace lo que hasta ahora no se podía escribir en Tcode:
`poner_u16`/`poner_u32`/`poner_u64` y sus `leer_*` en orden de red, más
`a_hex` y `de_hex`. `ejemplos/binario.t` lo usa para un formato con suma de
verificación: escribirlo, leerlo, y detectar un byte cambiado.

### Qué se tomó de dónde

| lenguaje | cómo lo hace | qué nos llevamos |
|---|---|---|
| **Rust** | anchos explícitos, sin mezclas implícitas, `as` trunca | los anchos y la prohibición de mezclar |
| **Zig** | `@intCast` revienta si se pierde información | que **el caso por defecto sea el comprobado**: aquí `como` aborta y `como?` es la excepción declarada |
| **Go** | anchos fijos, conversión explícita, pero desborda en silencio | los anchos; no el silencio |
| **C** | promociones implícitas, `&` con menos precedencia que `==` | los dos contraejemplos: ninguna promoción automática, y los bits atan más |

En Rust `as` trunca sin avisar, que es su parte menos defendida; aquí lo que
se escribe corto (`como`) es lo seguro, y salirse cuesta un carácter más.

## Funciones como valor

El nombre de una función, sin paréntesis detrás, es un valor. Su tipo se
escribe como su firma:

```tcode
fn por_n(a: &Cosa, b: &Cosa) -> bool { return a.n < b.n; }

fn ordenadas_por<T>(xs: &lista<T>, antes: fn(&T, &T) -> bool) -> lista<T>
```

Eso es un puntero a función: **coste cero, y no posee nada**, así que se
copia como un número y no hay que liberarlo.

**No hay capturas.** Una clausura que se lleva variables consigo obliga a
decidir qué posee y cuánto vive, y eso es un diseño entero —en Rust son tres
traits— que v0 no tiene. Lo que hay es lo que basta para pasar un criterio,
y se dice en la firma.

Tampoco se puede pasar como valor una función que **puede fallar**, ni una
**genérica** (hay una por cada juego de tipos, y ahí no se sabe cuál). Las
dos cosas las dice el compilador cuando pasan.

### Qué se tomó de dónde

| lenguaje | cómo lo hace | qué nos llevamos |
|---|---|---|
| **C** | punteros a función, sintaxis que hay que leer en espiral | el modelo de coste; no la sintaxis |
| **Rust** | `fn` como puntero, más `Fn`/`FnMut`/`FnOnce` para clausuras | la separación: el puntero sin captura es su propio tipo, simple y barato |
| **Go** | clausuras con captura, y un recolector detrás que las sostiene | lo que no podemos permitirnos sin recolector |
| **Zig** | punteros a función, sin clausuras | la misma decisión, y por la misma razón |

### `ordenadas_por`

`std/lista` lo usa para lo que antes no se podía escribir:

```tcode
for c en ordenadas_por(cosas, por_n) { ... }
for n en ordenadas_por(numeros, al_reves) { ... }
```

No ordena en el sitio: ordena las **posiciones**, que son números y se mueven
libremente, y copia una sola vez en ese orden. Intercambiar dos elementos
dueños dentro de una lista dejaría un hueco sin dueño, y el compilador no lo
permite; así son *n* copias en vez de *n* log *n* intercambios imposibles.

## Decimales: un NaN para el programa donde aparece

`f64` y `f32`. Literales con punto o exponente: `3.5`, `1e-3`. Un número
escrito sin punto no decide su tipo, así que `let x: f64 = 1;` vale.

### La decisión

**Una operación que no da un número detiene el programa ahí mismo.**

```
ejemplo.t:4: `/` no dio un numero (NaN o infinito). Si lo querias,
             escribe `/?`.
```

Eso cubre los tres casos de una sola comprobación —`isfinite` sobre el
resultado—: `0.0/0.0` (NaN), `1.0/0.0` (infinito) y el desborde a infinito.
`+?`, `-?`, `*?` y `/?` devuelven el IEEE de siempre, dicho a propósito, con
el mismo `?` que ya significaba "me salgo de la comprobación" en los enteros.

Esto es lo que hacen los demás:

| | `0.0/0.0` | `1.0/0.0` | `1e308 * 10` |
|---|---|---|---|
| C, Go, Rust, Swift, Java | NaN, en silencio | infinito, en silencio | infinito, en silencio |
| Python | **lanza** | **lanza** | lanza (OverflowError) |
| **Tcode** | **para** | **para** | **para** |

El problema no es que exista el NaN: es que se propaga. Un NaN que nace en el
paso 3 contamina todo lo que toca y se descubre en el paso 900, con el
contexto ya perdido. Es exactamente el mismo argumento que justifica que un
desbordamiento entero pare, y la misma solución. Python es el único que hace
algo parecido, y sólo para la división.

El coste es una comparación por operación, que el compilador de C aprovecha
porque ya tiene el resultado en un registro.

### `==` avisa

```
aviso: ejemplo.t:6: `==` entre decimales compara bit a bit: `0.1 + 0.2` no es
       `0.3`. Si querias 'aproximadamente', usa `cerca(a, b, tolerancia)` de
       `std/numero`
```

No se prohíbe —comparar con `0.0` exacto a veces es justo lo que se quiere—
pero se dice. Rust necesita clippy para esto; aquí lo dice el compilador.

### Conversión

`como` entre enteros y decimales se comprueba de ida y vuelta, igual que
entre anchos:

```tcode
let x = n como f64;          // 7 -> 7.0
let k = exacto como usize;   // 3.0 -> 3, vale
let m = f como usize;        // 3.7 -> para: el valor no cabe
```

**Rust trunca aquí en silencio** (`3.7 as usize` da `3`). Esa es su parte
menos defendida, y aquí no pasa. Si lo que quieres es truncar, dilo:
`piso(f) como usize`.

Por eso `como?` de un decimal a un entero **no existe**: "quedarse con los
bits de abajo" no significa nada ahí. Hay que decir qué se hace con la parte
fraccionaria, y el error lo nombra: `piso`, `techo` o `redondear`.

### Al imprimir

Un `f64` que vale 1 se escribe `1.0`, no `1`. C y Go escriben `1`, y eso
hace que una salida no diga de qué tipo era el número. Un detalle pequeño
que se agradece leyendo un informe.

### Lo que trae `std`

`raiz`, `piso`, `techo`, `redondear`, `absoluto` son internas (viven en
`libm`). En `std/numero`: `cerca`, `porcentaje_exacto`, `acotar_decimal`,
`media_decimal`.

`%` sobre decimales **no existe**: es el resto de una división entera y con
decimales no tiene un significado único.

## `if` como valor

```tcode
let x = if n > 3 { 1 } else { 2 };
return if n > 100 { nuevo("grande") } else { nuevo("pequeno") };
```

Cada rama es **una expresión**, no un bloque, y el `else` es obligatorio.

Esa es la diferencia con Rust, donde `if` es una expresión porque un bloque
entero vale lo que vale su última expresión *sin punto y coma*. Eso es
elegante pero arrastra una regla sutil —añadir un `;` cambia el valor del
bloque— que hay que aprender y que muerde. Aquí no hay nada que aprender:
donde se espera un valor, las llaves llevan un valor.

Y no baja al `?:` de C: baja a una variable y un `if`, porque cada rama puede
necesitar emitir líneas propias —un temporal, una bandera de propiedad— y
dentro de `?:` no caben. El compilador de C lo vuelve a juntar.

Las dos ramas se comprueban como caminos que se excluyen, igual que el `if`
sentencia: lo que una mueve, la otra no lo ha movido.

## Clausuras

```tcode
let inicial = nuevo("a");
let empiezan = fn[inicial](x: &str) -> bool {
    return empieza_con(vista(x), vista(inicial));
};

for c en filtradas(frutas, empiezan) { ... }
```

La lista de captura va entre corchetes, es **explícita**, y se captura
**por valor**. Un `str` capturado se *mueve* a la clausura: a partir de ahí
el dueño es ella, y se libera sola al acabar el bloque.

### Por qué es simple aquí y difícil en otros sitios

Una clausura es exactamente **un struct con lo capturado dentro, más una
función que lo recibe**. No hay maquinaria nueva: de structs con dueño el
compilador ya lo sabía todo —cuándo liberarlos, cómo copiarlos, cuándo se
mueven— y la clausura hereda eso entero.

Lo que encarece las clausuras en otros lenguajes es capturar **por
referencia**: entonces hay que saber cuánto vive lo capturado.

| lenguaje | cómo | qué cuesta |
|---|---|---|
| **Rust** | por referencia o por movimiento, con `Fn`/`FnMut`/`FnOnce` | tres traits, porque hay que distinguir si la clausura lee, modifica o consume. Es la parte del lenguaje que más cuesta aprender |
| **C++** | lista explícita `[x, &y]`, tipo anónimo; `std::function` reserva | la captura por referencia trae los mismos colgados que un puntero |
| **Go, JS** | por referencia, con recolector detrás | no podemos permitírnoslo |
| **Swift** | captura fuerte + ARC | ciclos de retención |
| **Zig** | no hay | — |
| **Tcode** | por valor, lista explícita | no puedes capturar un préstamo. A cambio: cero traits, cero anotaciones, cero recolector |

Capturar un préstamo se rechaza y el error dice qué hacer:

```
error: f.t:2: `v` es `view`, un prestamo: una clausura captura por valor, y
              guardar un prestamo exigiria saber cuanto vive. Captura un
              `str` con `copiar(v)`
```

### Pasarla a una función

Cada clausura tiene su propio tipo, así que quien la recibe es **genérico**:

```tcode
fn filtradas<T, F>(xs: &lista<T>, cumple: F) -> lista<T>
```

Y ese mismo `F` acepta también una función con nombre, así que una sola
firma vale para las dos. Un `fn(&T, &T) -> bool` —puntero a función— no
acepta clausuras, y el error lo dice y propone hacerlo genérico.

No hay `FnMut`: la clausura recibe su entorno prestado para leer. Modificar
lo capturado desde dentro es lo que obliga a Rust a tener el segundo trait, y
v0 no lo necesita todavía.

En `std/lista` lo usan `filtradas`, `cuantas_cumplen` y `ordenadas_por`.

## Memoria propia: `bloque<T>`, `reservar` e `intercambiar`

`lista<T>` y `mapa<K, V>` los pone el compilador. Debajo de ellos no había
nada: no se podía escribir una colección propia en Tcode porque no había
forma de reservar memoria. Ahora sí.

```tcode
var b: bloque<str> = reservar(3);
imprimir(b[0]);              // "" — nace a ceros
b[0] = nuevo("hola");
redimensionar(b, 5);         // lo nuevo nace a ceros
redimensionar(b, 1);         // lo que sobra se libera antes de soltar
```

Un `bloque<T>` es memoria reservada de una pieza con su tamaño al lado.
Índices comprobados, y dueño: se libera solo, elemento a elemento.

### Por qué no hace falta `unsafe`

Reservar memoria en C o en Rust deja ranuras **sin inicializar**, y de ahí
sale todo lo demás: el `MaybeUninit` de Rust, el `unsafe` dentro de `Vec`, y
en C directamente leer basura.

En Tcode no hace falta, y es por una propiedad del lenguaje que estaba ahí
sin usar: **todo tipo puesto a ceros es un valor válido y vacío.** Un `str` a
ceros es el texto vacío. Una lista a ceros es la lista vacía. Un mapa a ceros
es el mapa vacío. Un struct a ceros tiene todos sus campos vacíos. Así que un
bloque se reserva con `calloc` y **todas sus ranuras son valores de verdad**
desde el primer momento. No hay estado intermedio que esconder.

### `intercambiar`

```tcode
let viejo = intercambiar(xs[i], vacio());
```

Pone un valor en un sitio y devuelve el que había. Es lo que permite **sacar
algo de una colección sin dejar un hueco sin dueño**, que es justo lo que el
compilador no dejaba hacer de ninguna otra forma. Con esto, dar la vuelta a
una `lista<str>` en el sitio —imposible hasta ahora— son seis líneas.

Es el `mem::replace` de Rust, y por la misma razón: es la operación mínima
que hace segura la salida de un valor de un sitio compartido.

### Una lista escrita en Tcode

`std/vector` es una lista dinámica completa —`agregar`, `sacar`, `cuantos`,
`capacidad`, `ajustar`— escrita **entera en Tcode**, sobre `bloque<T>`, sin
que el compilador sepa nada de ella:

```tcode
struct Vector<T> { datos: bloque<T>, largo: usize }
```

Crece al doble, encoge cuando se lo pides, y libera lo que le sobra. Eso es
lo que separa "un lenguaje con dos colecciones dentro del compilador" de uno
en el que las colecciones se escriben en el propio lenguaje.

`lista<T>` sigue siendo la que trae de serie, por ergonomía —literales `[]`,
`for`, `anadir`— pero ya no es la única posible, que era el punto.

## Depurar: el C generado apunta al `.t`

Tcode compila a C, así que `gdb`, `valgrind`, los sanitizers y los
perfiladores funcionaban desde el primer día —pero hablaban del `.c`
intermedio, que nadie escribió. Con directivas `#line` en el C generado,
todos ellos señalan el Tcode:

```
$ gdb ./mi_programa
Breakpoint 1, hondo (n=3) at mi.t:2
2           let a = n * 2;
(gdb) info locals
a = ...
(gdb) bt
#7  hondo (n=3) at mi.t:3
#8  main (argc=1, argv=...) at mi.t:7
```

Puntos de ruptura en funciones Tcode, la fuente Tcode listada, variables con
sus nombres de Tcode, y la pila en líneas de Tcode. **Sin escribir un
depurador**: no hacía falta escribirlo, hacía falta no perder el sitio.

Lo mismo vale para AddressSanitizer, UndefinedBehaviorSanitizer, `valgrind`
y `perf`: cualquier herramienta que lea información de depuración.

`--sin-lineas` las quita. Sólo sirve para depurar el propio compilador,
cuando lo que hay que mirar es el C.

## Formato

```
$ tcode mi.t --formatear            # a la salida
$ tcode mi.t --formatear --escribir # en su sitio
$ make formato                      # todo el repositorio
```

**Sin opciones.** Hay un estilo y es este. Una opción de formato es una
discusión que se repite en cada revisión de código, y no vale lo que cuesta:
eso lo demostró `gofmt` y lo confirmó `black`.

Qué hace: sangra por hondura de llaves con cuatro espacios, quita el espacio
al final de línea, deja como mucho una línea en blanco seguida, normaliza el
espacio alrededor de `,`, `;` y los paréntesis, y alinea entre sí los
comentarios de líneas seguidas.

### Qué NO hace, a propósito

**No mueve tokens de línea.** No decide dónde parte una expresión larga. Eso
tiene dos consecuencias:

- **No puede estropear nada.** La salida lexea exactamente a los mismos
  tokens que la entrada, y la suite lo comprueba sobre los 36 `.t` del
  repositorio en cada ejecución. Un formateador que reparte líneas puede
  cambiar lo que un programa significa si se equivoca con la precedencia;
  este no puede.
- **Quien escribe sigue mandando** sobre la forma de su código.

Ahí está la diferencia con `gofmt`, que sí reparte. En un lenguaje joven, un
formateador que se equivoca al partir una expresión hace más daño que bien.
Cuando la gramática lleve años quieta, se puede.

Lo que sí se pierde: la alineación hecha a mano entre sentencias. Es el trato
de `gofmt` — pierdes algo de ajuste fino, ganas no discutir nunca.

### Cómo se comprueba

Tres propiedades, en la suite, sobre todos los `.t` del repositorio:

1. **No cambia los tokens.** La salida lexea igual que la entrada.
2. **Es idempotente.** Formatear dos veces da lo mismo.
3. **El repositorio ya está formateado.** Si alguien sube algo sin formatear,
   la suite lo dice y nombra el archivo.

## Tipos suma: `enum` y `match`

Un valor que es una cosa **o** otra, y el compilador obliga a mirar cuál.

```tcode
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
        Json.Numero(n) -> texto(n),
        Json.Texto(s) -> {
            var r = nuevo("\"");
            empujar(r, s);
            empujar(r, "\"");
            return r;
        }
        _ -> nuevo("?"),
    };
}
```

Un brazo da un valor (`-> expr,`) o hace cosas (`-> { ... }`). Por dentro
son lo mismo: el cuerpo de un brazo que da valor es un `return` de esa
expresión. Un `match` suelto, como sentencia, no lleva `;` detrás, igual que
`if` y `while`.

### Es exhaustivo

Si falta una forma, el error la nombra:

```
al `match` le faltan formas: `Json.Verdad`, `Json.Lista`. Ponlas, o pon un
brazo `_` para lo que quede; si no, el día que añadas una variante este
sitio se quedaría callado
```

Un brazo repetido y un brazo detrás del `_` también son errores: los dos son
código que no se ejecuta nunca, y callárselo sería mentir.

### Un `match` mira, no desmonta

Lo que atrapa un patrón **se presta siempre**. Un `str` se ve como `view`;
cualquier otra cosa con dueño, como `&T`. Nunca hay que escribir `ref`, `&`
ni `as_ref()`.

Rust deja sacar el valor de dentro, y a cambio tiene que llevar la cuenta de
un enum medio movido; de ahí vienen `ref`, `ref mut`, `match *x` y los modos
de ligadura por defecto que costó años añadir. Aquí no hay medias tintas:
quien quiera quedarse con lo de dentro escribe `copiar(...)`, que es la misma
regla explícita que el resto del lenguaje.

Es menos potente. Es también menos que aprender, y el error de quedarse con
un puntero a lo que ya no está no se puede escribir.

### La etiqueta 0 es la primera variante

Siempre, y no es casualidad: en Tcode **todo tipo puesto a ceros es un valor
válido**, y esa invariante es la que permite que `reservar(n)` entregue
ranuras ya hechas sin que exista un `unsafe` ni un `MaybeUninit`. Un enum
tiene que respetarla como todo lo demás, así que el `calloc` de un
`bloque<Json>` da `Json.Nulo` en cada hueco.

Ni Rust ni Zig garantizan esto.

### Cómo se ve en C

```c
typedef struct Json Json;
#define SS_JSON_NULO 0
#define SS_JSON_VERDAD 1
...
struct Json
{
    uint32_t etiqueta;
    union
    {
        struct { bool _0; } v_Verdad;
        struct { int64_t _0; } v_Numero;
        struct { SafeString _0; } v_Texto;
        struct { ss_lista_Json _0; } v_Lista;
    } dato;
};
```

El `match` baja a un `switch` sobre `etiqueta`. La liberación y `copiar`
salen generadas, cada una con su propio `switch`: se suelta o se duplica lo
que lleve la forma que sea, y las que no llevan nada ni aparecen.

### Comparación

| | tipos suma | exhaustividad | dato del patrón |
|---|---|---|---|
| C | `enum` = enteros; unión a mano | no | sin comprobar |
| Go | no tiene; interfaz + `type switch` | no | asertado |
| C++ | `std::variant` + `std::visit` | parcial, ilegible | por visitante |
| Rust | sí | sí | mover o prestar, con `ref`/`&` |
| Swift | sí | sí | `let` / `case let` |
| Zig | `union(enum)` | sí | por captura `|x|` |
| **Tcode** | **sí** | **sí, con las que faltan nombradas** | **prestado siempre** |

Lo que Tcode todavía no tiene: enums con parámetros de tipo
(`enum Quiza<T>`), patrones anidados, patrones sobre literales o rangos, y
guardas (`if` dentro de un brazo).

## La puerta a C: `externo`

Tcode compila a C17, así que llamar a una función de C no cuesta nada: es la
misma llamada que escribiría un programa en C, sin envoltorio y sin nada que
traducir. Comparado con cgo (que cambia de pila, unos 100 ns por llamada) o
con ctypes (que lo resuelve al ejecutar), eso ya es gratis.

Lo interesante no es el coste. Es que el borde sigue siendo seguro.

```tcode
externo "math.h" {
    fn sqrt(x: f64) -> f64;
    fn pow(base: f64, exponente: f64) -> f64;
}

externo "stdlib.h" {
    fn getenv(nombre: str) -> cadena_c;
}

externo "sistema.c" {          // se compila y se enlaza junto al programa
    fn ahora_segundos() -> i64;
}
```

### No hay `unsafe` por llamada, y no hace falta

Rust marca cada llamada a C con `unsafe`. Aquí no, porque **desde Tcode no se
puede escribir una llamada que rompa la memoria**: en el borde sólo caben los
tipos que significan exactamente lo mismo a los dos lados, y de eso se
encarga el comprobador. Lo que pueda hacer mal la función de C es cosa de C
— y su nombre está escrito en el bloque, que se ve desde lejos y se busca con
un `grep`.

### Qué cabe en el borde

| | entrada | salida |
|---|---|---|
| `u8`…`u64`, `usize`, `i8`…`i64` | sí | sí |
| `f32`, `f64`, `bool` | sí | sí |
| `str` | sí, como `const char*` | no |
| `cadena_c` | no | sí, Tcode copia |
| nada (`()`) | — | sí |
| `view`, `lista`, `mapa`, structs, enums | no | no |

Un **`str` entra como `const char*`** porque el runtime garantiza el `\0`
final. Una **`view` no**: puede apuntar a la mitad de una cadena y no termina
en nada, así que C leería de más. Es la comprobación que Rust deja en manos
de `CString::new` y que aquí hace el compilador:

```
`f.s` es una `view`, y una vista puede apuntar a la mitad de una cadena:
no acaba en `\0` y C leería de más. Pasa un `str`, que sí acaba, o haz
`nuevo(v)` antes
```

Y si un `str` lleva un cero **en medio**, el programa **para en la línea donde
se entrega**, en vez de pasarle a C una cadena cortada. No es un fallo de
memoria; es una verdad a medias, y se trata igual que el desbordamiento o el
NaN. Rust devuelve un `Result` que hay que mirar; C trunca y calla.

Una función de C **presta** lo que recibe: `getenv(clave)` no se queda con
`clave`, así que `clave` sigue viva después y se libera como siempre.

`cadena_c` es un `char*` que **sigue siendo de C** (una literal, un `getenv`,
un `strerror`). Tcode se queda una copia, que ya es un `str` normal. Un
`char*` que hay que liberar —`strdup`— no cabe todavía: se envuelve.

### El escape completo: un `.c` de al lado

Lo que no cabe se envuelve en dos líneas de C propias. Si la cadena del
bloque acaba en `.c`, ese archivo **se compila y se enlaza** junto al
programa, y Tcode pone su prototipo:

```c
/* sistema.c */
#include <time.h>
long long ahora_segundos(void) { return (long long) time(NULL); }
```

`time(NULL)` pide un puntero y no cabe en el borde; envuelto, sí. No hace
falta un Makefile ni salir de la orden `tcode`.

### Comparación

| | coste por llamada | marca | tipos comprobados |
|---|---|---|---|
| Go (cgo) | ~100 ns, cambia de pila | `import "C"` | por cgo |
| Python (ctypes) | alto, al ejecutar | ninguna | ninguno |
| Rust | cero | `unsafe` en cada llamada | por firma, y punteros crudos |
| Zig | cero | ninguna | lee la cabecera de verdad |
| **Tcode** | **cero** | **el bloque `externo`** | **sólo lo que significa lo mismo** |

Zig gana en comodidad: `@cImport` lee la cabecera y no hay que declarar nada.
Tcode no puede — no sabe leer C —, así que la firma se escribe a mano, y si
no coincide con la de verdad lo dice el compilador de C. Es la deuda honesta
de este diseño.

### Lo que no hay

Punteros crudos, structs a través del borde, `callbacks` de C a Tcode,
varargs (`printf`), y devolver memoria que haya que liberar. Todo eso se
envuelve en un `.c` de al lado.

## Qué NO tiene v0

Es un v0 honesto. No hay: clausuras que modifiquen lo capturado
(`FnMut`), comprobación del cuerpo genérico una sola vez contra la
restricción (eso es Rust, y es más), enums con parámetros de tipo, patrones
anidados ni guardas, E/S incremental, punteros crudos ni recolector. La
puerta a C existe (`externo`) pero es estrecha a propósito: sin punteros, sin
structs y sin varargs.
Todo valor que sale
de su bloque sin ser devuelto ni movido se libera automáticamente, a
cualquier hondura.
