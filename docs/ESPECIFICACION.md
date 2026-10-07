# Tcode — especificación del lenguaje, 1.0 (borrador)

> **Cómo leer esto.** Lo que un programa puede escribir está en
> [El texto del programa](#el-texto-del-programa) y en la
> [Gramática](#gramática); las funciones que trae el lenguaje, en el
> [índice de funciones internas](#índice-de-funciones-internas); lo que no
> tiene, en [Lo que Tcode 1.0 no tiene](#lo-que-tcode-10-no-tiene). El resto
> explica cada regla con su porqué, en el orden en que se fueron
> añadiendo. Lo que se promete que no cambia está en
> [`COMPATIBILIDAD.md`](COMPATIBILIDAD.md).
>
> La suite mantiene esto en sintonía con el compilador: el programa de
> muestra de la gramática compila y corre, y el índice de funciones internas
> nombra exactamente las que conoce `tcodec` (sección ESPECIFICACION).

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

Una **cadena literal no es un `str`, es un `view`**: presta memoria que vive
tanto como el programa, y nadie la libera. Por eso `f("texto")` no vale donde
la función pide un `str` con dueño —el error dice que recibió un `view`—, y
hace falta `nuevo("texto")`. Es lo que hace que `fn estatica() -> view {
return "constante"; }` sea correcto y que `let v: view = nuevo("x");` no lo
sea: `nuevo` sí fabrica un dueño, y moriría al acabar la sentencia.

Mientras se vaya a usar un `view` derivado de un `str`, ese `str` **no se
puede mutar ni mover**. El préstamo dura hasta el último uso de la vista, no
hasta el final de su bloque:

```tcode
var s: str = nuevo("hola");
let v: view = vista(s);
empujar(s, " mundo");   // error: `s` está prestado por `v`
imprimir(v);            // ...porque `v` se usa aquí

let w: view = vista(s);
imprimir(w);            // último uso de `w`
empujar(s, "!");        // bien: ya nadie mira a `s`
```

Una vista se vuelve a usar si se nombra en la sentencia en curso, en las que
la siguen dentro de su bloque, o en cualquier parte de un bucle que envuelva
al punto donde se modifica: la vuelta siguiente puede volver a leerla. Es la
regla de Rust desde 2018 (*non-lexical lifetimes*), dicha por nombres en vez
de por un grafo de flujo: más conservadora, y cabe en una línea. Ante la duda
—una rama de un `if` anterior que la usa, dentro de la misma sentencia—, la
vista sigue viva.

Esto es exactamente el caso 2 de la tabla, y también el "CONTRATO DE VIDA
ÚTIL" que safestr documentaba y pedía respetar con criterio.

Cuando el valor de una expresión se tira —una expresión suelta como `s;`,
`p.n;` o `vista(s);`—, esa expresión solo **lee**: si lo que hay es un sitio
(una variable, un campo, un elemento), el sitio no se mueve y sigue siendo de
quien era. Mover es entregarlo: pasarlo a una función que se lo queda, meterlo
en un literal o devolverlo. La decisión la toma el comprobador, no la forma de
la expresión, y el generador solo la obedece.

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
imprimir(p);
```

Ante la duda, la inferencia rechaza. Prefiere negarse a un programa correcto
antes que aceptar uno colgante.

El préstamo viaja por **todo** lo que puede dar una vista, no sólo por
`vista` y `rebanar`: las dos ramas de un `if` como valor, los brazos de un
`match` como valor, lo que queda a la derecha de un `sino`, una llamada a una
genérica (`id(vista(s))`), a un puntero a función o a una clausura, y un
struct que presta. En todos, la vista que sale presta de todo lo que entró:

```tcode
let v = if c { vista(s) } else { "z" };
empujar(s, "x");          // error: `s` esta prestada por `v`
imprimir(v);

let f: fn(view) -> view = primero;
let w = f(vista(s));
s = nuevo("otra");        // error: `s` esta prestada por `w`
imprimir(w);
```

Lo que un `match` enlaza también mira dentro del valor mirado, así que lo
presta mientras viva:

```tcode
var e = E.A(nuevo("hola"));
let t = match e { E.A(x) -> x, E.B -> "z" };
e = E.B;                  // error: `e` esta prestada por `t`
imprimir(t);
```

Vale igual para lo que llega prestado con `&T` o `mut T`: `vista(p.nombre)`
de un `p: &Persona`, `vista(xs[0])` de un `xs: &list<str>`, o la de un
`s: mut str` después de modificarlo. La memoria es de quien llama.

En quien llama, **la vista presta de todo lo que se le prestó a la
función**. La firma no dice de cuál de sus parámetros sale, así que se
supone lo peor:

```tcode
fn la_larga(a: &str, b: &str) -> view { ... }

let v = la_larga(a, b);
empujar(b, "x");        // error: `b` esta prestada por `v`
imprimir(v);
```

Y tres reglas que cierran lo que queda:

- **Una vista no vive más que su dueño.** Al guardarla —también al
  reasignarla— el dueño tiene que estar declarado en el mismo bloque que la
  vista o en uno de fuera:

  ```tcode
  var v: view = "";
  if c {
      let s = nuevo("hola");
      v = vista(s);     // error: `v` vive mas que `s`
  }
  ```

- **Reasignar no suelta lo anterior.** La vista sigue prestando de todo lo que
  se le dio hasta que muere: si la asignación va en una rama, la otra puede
  no haberla hecho. Y su procedencia es la peor de todas, así que
  `v = vista(local); return v;` se rechaza igual que `return vista(local);`.

- **Una vista de un temporal no se guarda.** `f(nuevo("x"))` presta de un
  `str` que se libera al acabar la sentencia: usarlo ahí mismo vale
  (`imprimir(f(nuevo("x")))`), guardarlo en una variable no.

### 2. Aritmética comprobada por defecto (mata los fallos 1 y 4)

`+`, `-` y `*` sobre enteros comprueban desbordamiento. Al desbordar, el
programa aborta con el archivo y la línea. No hay comportamiento indefinido.

Para optar por no comprobar, hay que escribirlo:

```tcode
let a: usize = x *? y;   // multiplicación envolvente, explícita
```

En tipos con signo la vuelta y las operaciones de bits son módulo `2^N`, igual
en cualquier compilador C17: el C generado reconstruye el valor negativo sin
depender de convertir un entero sin signo fuera de rango a uno con signo. El
desplazamiento derecho de un negativo es aritmético y rellena con unos.

La división signed también cierra el único borde especial de C17:
`INT_MIN / -1` aborta como desbordamiento antes de dividir. En
`INT_MIN % -1` el resto matemático es `0`, y eso devuelve Tcode sin ejecutar
la operación que C considera indefinida.

Negar el mínimo signed tampoco llega al operador unario de C: `-INT_MIN`
aborta como desbordamiento en `-`; cualquier otro valor se niega normalmente.
Un entero sin signo no se niega: `-x` con `x: u8` es un error de compilación,
no la vuelta módulo `2^N` que haría C. Para eso está `0 -? x`.

### 3. Sin conversiones implícitas (mata el fallo 4 por otra vía)

No existe la conversión silenciosa entre anchos ni entre signos. `i64` y
`usize` no se mezclan sin decirlo.

Un número escrito no tiene tipo propio: toma el del otro lado de la
operación, y la cuenta se hace en ese tipo. `1 + x` con `x: u8` es una suma
de `u8`, que para al pasar de 255; `0 > n` con `n: i32` compara con signo; y
`2 * x` con `x: f64` es una multiplicación de decimales. Si los dos lados son
números escritos, la cuenta se hace en el tipo que se espera de ella:
`let a: i64 = 5 - 10;` vale `-5`, y `let y: u8 = 200 + 100;` se desborda.
Sin nada que lo decida, `1 + 2` es un `usize` y `-1` un `i64`.

Una cuenta hecha sólo de números escritos no espera a que el programa corra:
se hace al compilar, en su tipo, con las mismas reglas —de izquierda a
derecha, parando en la primera operación que falla—. Lo que en marcha
pararía el programa es un error de compilación, en su línea:

```
ejemplo.t:2: `200 + 100` no cabe en `u8`: es una cuenta de numeros escritos, y se hace al compilar
```

Igual con `1 - 2` sin tipo (un `usize` no baja de cero), `7 / (3 - 3)`,
`1 << 32` en un `u32`, y `300 como u8`. Con `+?`, `-?` y `*?` la cuenta da la vuelta y no
para nunca. Una rama de un `if` cuya condición no se sabe se cuenta sola, y
lo que depende de cuál se tome queda para cuando corra:
`(if c { 200 } else { 1 }) + 100` en un `u8` compila, y para si `c` es cierto.

Lo mismo con las ramas de un `if` y los brazos de un `match`: una rama que es
un número escrito toma el tipo de la otra, y tiene que caber en él. Con
`x: u8`, `if c { 300 } else { x }` no compila. Una rama entera y otra decimal
dan un decimal, como `1 + 2.5`. Donde va un decimal, los números escritos son
decimales: `let r: f64 = 7 % 2;` no compila, porque con decimales no hay
resto. Y `-(3 + 4)` no cabe en un `u8`, igual que `-7`.

### La complejidad vive en una capa, no en la superficie

Las reglas de arriba las comprueba el compilador. Lo que **escribes** no tiene
por qué repetirlas:

```tcode
fn main() {
    var saludo = nuevo("hola, ");
    empujar(saludo, "mundo");
    imprimir(saludo);
}
```

Ahí hay propiedad, un préstamo y una liberación automática, y no se menciona
ninguna. Tres cosas lo hacen posible:

**El tipo se deduce del valor.** `let n = 42;` en vez de `let n: usize = 42;`.
Se escribe sólo cuando dice algo que el valor no dice: `let xs: list<usize> =
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

Una función que declara tipo de retorno tiene que salir por `return` o `fail`
en **todos** los caminos. Un `while` no cuenta: puede no dar ni una vuelta.

```
error: `g` promete devolver `usize` pero hay un camino que llega al final
sin `return`
```

`main` es la excepción: si no dice otra cosa, sale con cero.

### 4. Sin valores no inicializados

Toda variable se inicializa en su declaración. `let` es inmutable; `var` es
mutable. La inmutabilidad es lo normal.

Un nombre no se puede declarar dos veces en el mismo bloque, ni tapar a una
variable de un bloque que envuelve al actual. Dos bloques hermanos sí pueden
usar el mismo nombre, y una clausura puede llamar a su parámetro como a una
variable de quien la crea, porque es otra función.

- **Rust y Go** dejan tapar. En Rust es cómodo para transformar un valor sin
  inventar nombres (`let x = x.trim()`); en Go es una fuente conocida de
  fallos (`err` tapado dentro de un `if`), tanto que `go vet` tiene un
  analizador solo para eso.
- **Zig, C# y Java** lo prohíben. Tcode hace lo mismo: leer un nombre sin
  saber a cuál de las dos variables se refiere es donde nacen los fallos.
- Hay además una razón de implementación: en el C generado la variable de
  fuera se vuelve innombrable dentro, y una salida temprana desde ahí no
  podría liberarla.
- **Peor que Rust:** a veces hay que inventar un segundo nombre. Medido antes
  de decidir, ningún programa del repositorio tapaba variables.

### Orden de evaluación

Las subexpresiones se evalúan **de izquierda a derecha**. En una llamada se
evalúan los argumentos en el orden escrito; en una operación binaria, primero
el operando izquierdo. Las funciones internas y las declaradas con `externo`
siguen la misma regla. El C generado la hace explícita con temporales: no
depende del orden que el compilador de C decida usar.

Vale también cuando un operando necesita sentencias propias —un `if` o un
`match` como valor—: lo que va antes de él se calcula antes, en temporales.

```tcode
let x = f() + (if c { g() } else { 0 });   // f, y despues g
```

`&&` y `||` además conservan cortocircuito: el lado derecho sólo se evalúa si
el izquierdo no determina ya el resultado.

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

- **Campos `view`: el struct presta.** Un struct con un campo `view` —o con
  otro struct que presta— se trata como una vista, sin anotar vidas en el
  tipo: es la vida única implícita de un `struct Foo<'a>` de Rust.

  ```tcode
  struct Palabra { texto: view, n: usize }

  let s = nuevo("hola mundo");
  let p = Palabra { texto: rebanar(vista(s), 0, 4), n: 4 };
  empujar(s, "!");      // error: `s` esta prestada por `p`
  imprimir(p.texto);
  ```

  Presta de lo que se le puso al construirlo; un campo `view` suyo presta
  de lo mismo; no vive más que sus dueños, y no sale de la función si presta
  de algo local. Una función que lo devuelve presta de todo lo que se le
  prestó, igual que una que devuelve `view`. Y no se guarda donde nadie
  sabría cuánto vive: ni en una `list`, un arreglo fijo, un `map` o un
  `bloque`, ni en un enum, ni en lo que captura una clausura. Tampoco se
  guarda una vista en un struct que llegó prestado: quien lo prestó no sabría
  de dónde presta ahora. Un campo `&T` no vale —tampoco `&mut T`—: no dice de
  quién presta ni cuánto vive, y el struct no lo sigue. Para prestar está
  `view`.
- **Sacar un campo.** `let n = p.nombre;` saca el campo de una variable que
  es dueña del struct. En C se copia y su sitio queda a ceros —que en Tcode
  es un valor válido—, así que al liberar el struct ese campo no suelta nada.
  Desde ahí, el campo no se usa, ni el struct entero, hasta que se le dé otro
  valor; los otros campos, sí:

  ```tcode
  let n = p.nombre;
  imprimir(p.edad);     // bien
  entregar(p);          // error: `p` esta a medio mover
  p.nombre = nuevo("eva");
  entregar(p);          // bien: vuelve a estar entero
  ```

  Solo se saca donde vive la variable, no dentro de un `if`, un `match` o un
  bucle —después no se sabría si sigue ahí—, salvo en un `return`, que se va
  de la función. De algo prestado no se saca nada. Un elemento de una lista o
  de un arreglo tampoco: su índice no se conoce al compilar, y para eso está
  `intercambiar(...)`.
- **Prestar un sitio.** Para leer un elemento o un campo sin copiarlo, se
  presta: `let x: &Articulo = inv[2];` apunta al elemento, y
  `let x: &mut Articulo = inv[2];` deja modificarlo por `x`. Mientras `x` se
  use, la lista entera queda prestada —de un elemento no se sigue el índice,
  como en una llamada—: no se mueve ni se modifica, salvo a través de un
  `&mut`. Solo se presta lo que tiene partes; un escalar se copia.

  ```
  error: no se puede modificar `inv`: esta prestada por `x`
  ```
- **Recursión directa por valor.** `struct Nodo { hijo: Nodo }` no tiene tamaño
  finito y da error; la recursión mediante `list<Nodo>` sí está permitida.

#### Listas dinámicas

`list<T>` es una colección dueña cuyo largo se decide en ejecución:

```tcode
var numeros: list<usize> = [];
var nombres: list<str> = [nuevo("Ana"), nuevo("Beto")];
anadir(numeros, 10);
anadir(nombres, nuevo("Cielo"));
imprimir(nombres[2]);
```

El buffer crece de forma amortizada. `anadir` exige una lista `var`, mueve el
elemento si éste posee memoria y conserva el tipo concreto también en el C
generado. Al cerrar el bloque se liberan primero los elementos dueños y luego
el buffer. La indexación usa la misma comprobación que los arreglos fijos.

Una lista introduce indirección, por lo que permite estructuras recursivas de
tamaño finito (`struct Nodo { hijos: list<Nodo> }`). No se puede guardar
`view` —ni un struct que presta— en listas ni en arreglos fijos: cada
elemento podría prestar de un dueño distinto, y saber cuál necesitaría vidas
útiles en el tipo. Tampoco se usa un arreglo fijo como elemento de lista.

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

Lo que se presta es un camino, no la variable entera: `p.a` y `p.b` son
memoria distinta y conviven, también si los dos se modifican; `p` y `p.b` no,
porque uno contiene al otro, y el error nombra lo que se presta dos veces:

```tcode
h(p.a, p.b);        // bien: dos campos distintos
g(p.a, vista(p.b)); // bien: `vista(p.b)` presta sólo `p.b`
k(p, p.b);          // error: `p` se presta dos veces en la misma llamada a `k`
```

Un índice no se sigue: `v[i]` y `v[j]` pueden ser el mismo elemento, así que
`v[i].a` y `v[j].b` prestan los dos `v` entera.

Una `view` —o un struct que presta— pasada a una función cuenta como
préstamo para leer durante la llamada, lleve nombre o no. Es el fallo 2 de
safestr dicho en una línea:

```tcode
fn g(a: mut str, b: view) { empujar(a, "..."); imprimir(b); }

g(s, vista(s));   // error: `s` se presta dos veces en la misma llamada a `g`
```

`g` puede hacer crecer `a`, y al crecer el buffer se mueve: `b` quedaría
mirando memoria liberada. Vale igual si `g` es un puntero a función o una
clausura; entonces el mensaje nombra los argumentos por su posición.

### 7. Módulos: un archivo es un módulo

```tcode
use "lib/texto.t";
use "lib/calculo.t";
```

Las rutas son relativas al archivo que las escribe. Cada módulo se carga una
sola vez aunque lo pidan varios, y las dependencias circulares se detectan y
se explican:

```
error: dependencia circular entre modulos: a.t -> b.t -> a.t
```

`use "std/texto"` busca en la biblioteca que viene con el compilador, no
junto al programa. La extensión `.t` es opcional: se escribe el nombre del
módulo, no el del archivo.

`#importar "texto.t"` trae un módulo de la biblioteca que viene con el
compilador sin escribir la carpeta: se escribe el nombre del archivo, con su
`.t`. La carpeta `std/` la pone el compilador, así que `#importar "std/texto.t"`
no vale; y al revés, `use "texto"` sin la carpeta no encuentra nada. Las dos
formas dicen lo mismo por caminos distintos: con `use`, la ruta se escribe
entera —`use "std/texto"`—; con `#importar`, sólo el nombre del archivo
—`#importar "texto.t"`—. Vale también con alias: `#importar "utf8.t" como U;`.

Las funciones **internas** del lenguaje —`imprimir`, `largo`, `rebanar`,
`byte`, `leer_linea`…— no se piden: están siempre, sin `use` ni `#importar`.

### Espacios de nombres

Los nombres se resuelven **por archivo**: cada uno ve lo que él mismo
importa, y nada más. Dos módulos pueden declarar `contar` sin estorbarse.

Lo que importa un módulo importado **no** se ve: si `contar.t` usa
`std/texto`, y `std/texto` usa `std/caracter`, `contar.t` no puede llamar a
`es_blanco` sin su propio `use "std/caracter"`.

```
error: contar.t:29: `es_blanco` esta en std/caracter.t, que este archivo no
       usa. Se veia porque lo usa otro modulo, pero cada archivo tiene que
       pedir lo suyo: añade `use "...";`
```

Es la regla de Python, Go y Rust. C hace lo contrario: un `#include` arrastra
los suyos, y un archivo compila por lo que incluye un tercero hasta que ese
tercero deja de incluirlo. Medido al introducir la regla, tres ejemplos del
repositorio dependían de ese arrastre sin saberlo.

```tcode
use "lib/celsius.t" como c;
use "lib/fahrenheit.t" como f;

imprimir(c.nombre());        // "Celsius"
imprimir(f.nombre());        // "Fahrenheit"
```

`use` a secas trae los nombres tal cual. Sólo choca si **un mismo archivo**
trae dos iguales de forma llana, y entonces el error dice de dónde vienen los
dos y cómo arreglarlo:

```
error: app.t:2: `contar` llega de dos sitios, uno.t y dos.t. Dale un nombre
                a uno de los dos: `use "..." como algo;` y luego
                `algo.contar`
```

Vale también para los tipos y las formas de un enum: `t.Caja`,
`t.Par<usize, str>`, `t.Estado.Listo` y patrones como
`t.Resultado.Valor(x)`.

`como` **no es palabra reservada**: sólo significa eso detrás de una ruta de
`use`, así que sigue valiendo como nombre de variable.

Con una excepción: los nombres de **struct y enum son globales**, como si
todos los módulos vivieran en el mismo archivo. Dos módulos no pueden declarar
el mismo `struct` ni el mismo `enum` —genérico o no—, y el error dice los dos
sitios, con su línea:

```
error: a.t:2: el struct `Partes` ya esta definido en b.t:1: los nombres de
              struct y enum son globales entre modulos; ponle otro nombre a uno
```

Así que un nombre de tipo se elige pensando en el programa entero, no en el
módulo: `Valor`, `Partes` o `Nodo` a secas los quiere más de una biblioteca, y
uno de los dos acaba renombrado (`ValorToml`, `PartesUrl`). Las funciones, en
cambio, sí se resuelven por archivo y el cargador las renombra cuando chocan.

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

Cuando choca, lleva delante el nombre del archivo: `texto__palabras`. Si dos
de los que lo declaran se llaman igual en carpetas distintas (`x.t` y
`lib/x.t`), a esos dos les va la ruta entera, `x__f` y `lib_x__f`, para que
no acaben siendo la misma función en C.

Con C pasa lo mismo, por una sola regla. Un nombre de Tcode que en C ya
significa algo —una palabra reservada (`int`, `union`, `restrict`), un
nombre de las cabeceras que incluye el C generado (`exp`, `stdout`, `errno`,
`SIZE_MAX`), uno reservado por la norma (`_Algo`, `__algo`) o uno con los
prefijos del runtime (`ss_`, `sv_`)— sale en el C como `ss_id_<nombre>`. Los
mensajes siguen diciendo el nombre del `.t`, y los demás nombres no se tocan.
Lo que se declara en un bloque `externo` y `main` se quedan como están: son
de C a propósito.

### 8. Fallos: no se pueden ignorar

Una función que puede fallar lo declara con `!` después del tipo de retorno,
y sale con `fail`:

```tcode
fn dividir(a: usize, b: usize) -> usize ! {
    if b == 0 {
        fail "division por cero";
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
`return` posterior entrega no está movida todavía en el `fail` de antes. El
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
una costumbre — y esa diferencia costó tres fugas (`fail`, `try` y `sino`),
cada una encontrada corriendo, no leyendo.

`try` y `sino` no van en la condición de un `while` —se evaluarían una
sola vez—, y el motivo de `fail` es una cadena escrita, no un texto
construido.

### 9. Entrada de archivos y texto construido

`leer_archivo(ruta) -> str !` lee el archivo completo en modo binario. Es
falible, así que exige `try` o `sino`; distingue apertura, lectura y falta de
memoria sin dejar buffers ni descriptores abiertos. Los bytes cero se
conservan. `byte(texto, i)` devuelve un valor entre 0 y 255 y comprueba el
índice.

`leer_parte_archivo(ruta, desde, cuantos) -> str !` lee como máximo
`cuantos` bytes desde una posición. Devuelve texto vacío al llegar al final y
rechaza un tamaño cero. `std/archivo` construye encima `por_partes`, que llama
a una función por cada bloque y mantiene acotada la memoria, y
`partes_de_archivo`, que conserva los bloques cuando sí se necesitan después.

`texto(x) -> str` materializa un entero, `bool`, `view` o `str`. Los
decimales no entran; `imprimir` y la cadena interpolada sí los escriben.

### Avisos

Un aviso no impide compilar; señala algo que probablemente no era lo que se
quería. Un `_` delante del nombre lo silencia, y de paso le dice a quien lea
el código que es a propósito.

- variable declarada y nunca usada
- valores que se asignan y nunca se leen
- `var` que nunca se modifica: puede ser `let`
- parámetro que no se usa
- parámetro `mut T` que nunca se modifica: podría ser `&T`
- captura `mut` de una clausura que nunca se modifica: puede ir sin `mut`

`--avisos-como-errores` los convierte en errores; `--sin-avisos` los calla.

### Ver lo que el compilador infirió

El análisis de propiedad y préstamos normalmente sólo se ve cuando falla.
`tcode programa.t --explicar` lo muestra cuando sale bien: por variable, si
es dueña o prestada, dónde se mueve, dónde se libera, y de dónde sale cada
vista. Es el mismo modelo que produce los errores, escrito en positivo.

## El texto del programa

Un `.t` es **UTF-8 válido**. Si no lo es, el error dice la línea del primer
byte que no encaja: las reglas son las de RFC 3629, sin formas largas, sin
sustitutos y sin pasar de U+10FFFF.

**Los controles bidireccionales no valen en ningún sitio**, tampoco dentro de
una cadena o un comentario: U+202A–U+202E y U+2066–U+2069 hacen que el código
se vea distinto de como se compila ("Trojan Source", CVE-2021-42574).

**Un nombre** empieza por `_`, una letra ASCII o un carácter XID_Start, y
sigue con eso, dígitos ASCII o caracteres XID_Continue (UAX #31, con las
tablas de Unicode 15.0 que guarda `tests/generar_xid.py` para los dos
compiladores). `año`, `π` y `名前` son nombres; `×`, `€` y el espacio de
ancho cero no, y el error los nombra por su código: `caracter inesperado
U+00D7`. Los nombres no se normalizan: `é` escrita de una pieza y `e` con el
acento combinado son dos nombres distintos.

**Los dígitos de un número son los ASCII**, `0` a `9`. `²` o `٣` no son
números.

**Comentarios**: `//` hasta el final de la línea, y `/* ... */`, que no se
anidan. Un `/*` sin cerrar es un error.

**Números.** Un entero son dígitos, con `_` donde ayude a leerlo (`1_000`);
un cero delante no cambia la base (`010` es diez). Un hexadecimal es `$`
seguido de dígitos hexadecimales (`$FF`, `$1a2b`, `$0`); cabe en `u64`, así
que hasta dieciséis dígitos, y mayúsculas y minúsculas valen igual. Un decimal
lleva dígitos a los dos lados del punto (`1.5`, no `1.` ni `.5`) y puede
llevar exponente (`1.5e2`, `2E-3`). Un número pegado a una letra (`12abc`) es
un error. El signo no es parte del número: `-1` es `-` aplicado a `1`.

**Cadenas**: `"..."`, con los escapes `\n`, `\t`, `\0`, `\\`, `\"` y
`\xNN` (un byte en hexadecimal; no un carácter Unicode). Cualquier otro
escape es un error. Una **cadena interpolada**, `$"...{expr}..."`, admite
además `\{` y `\}`, y `{{` y `}}` para una llave escrita; dentro de las
llaves va cualquier expresión.

**Palabras reservadas**: `fn`, `let`, `var`, `mut`, `if`, `else`, `while`,
`for`, `en`, `break`, `continue`, `return`, `true`, `false`, `use`, `try`,
`sino`, `fail`, `struct`, `enum`, `match`, `externo`, `list`, `map`, y
los tipos `str`, `view`, `bool`, `u8`, `u16`, `u32`, `u64`, `usize`, `i8`,
`i16`, `i32`, `i64`, `f32` y `f64`. `como`, `bloque`, `cadena_c` y `_` no lo
son: son nombres con significado en su sitio, y fuera de él se pueden usar.

**Reservadas de antemano**: `protocol`, `implements`, `extends`, `anchor` y
`drop`. Todavía no significan nada, pero ya no valen como nombre: se
reservan para poder añadir anclajes en 1.x sin romper programas después.
Usarlas como nombre es un error de sintaxis, como cualquier otra reservada.

**Símbolos**: `( ) { } [ ] , ; : . = + - * / % < > ! & | ^ ~ ? $`, y de dos
caracteres `-> == != <= >= && || << >> .. +? -? *? /?`. El más largo gana:
`+?` es uno, no `+` y `?`.

## Gramática

`X?` es opcional, `X*` cero o más, `X+` una o más. Las palabras entre
comillas son literales. `NOMBRE` es un nombre; `CADENA`, `ENTERO`,
`DECIMAL` e `INTERPOLADA`, los literales de arriba. `ALIAS` es un nombre
dado con `use ... como`; `STRUCT`, `ENUM` y `PARAM_T`, nombres declarados
como struct, enum o parámetro de tipo de la función en curso.

```
programa    := usar* declaracion*
usar        := ("use" | "#importar") CADENA ("como" NOMBRE)? ";"
declaracion := struct | enum | externo | funcion

struct      := "struct" NOMBRE params_tipo? "{" (campo ("," campo)* ","?)? "}"
campo       := NOMBRE ":" tipo
enum        := "enum" NOMBRE "{" variante ("," variante)* ","? "}"
variante    := NOMBRE ("(" tipo ("," tipo)* ")")?
externo     := "externo" CADENA "{" firma_c+ "}"
firma_c     := "fn" NOMBRE "(" (NOMBRE ":" tipo_c ("," NOMBRE ":" tipo_c)*)? ")"
               ("->" tipo)? ";"
tipo_c      := tipo | "buffer"
funcion     := "fn" NOMBRE params_tipo? "(" params? ")" ("->" tipo)? "!"? bloque
params_tipo := "<" param_tipo ("," param_tipo)* ">"
param_tipo  := NOMBRE (":" restriccion)?
restriccion := "decimal" | "entero" | "igualable" | "numero" | "ordenable" | "texto"
params      := param ("," param)*
param       := NOMBRE ":" ("mut" | "&" | "&" "mut")? tipo

tipo        := "&" "mut"? tipo
             | "str" | "view" | "bool" | "usize" | "u8" | "u16" | "u32" | "u64"
             | "i8" | "i16" | "i32" | "i64" | "f32" | "f64"
             | "list" "<" tipo ">" | "map" "<" tipo "," tipo ">"
             | "bloque" "<" tipo ">" | "[" tipo ";" ENTERO "]"
             | "fn" "(" (tipo ("," tipo)*)? ")" ("->" tipo)?
             | (STRUCT | ENUM | ALIAS "." NOMBRE) ("<" tipo ("," tipo)* ">")?
             | PARAM_T | "cadena_c"

bloque      := "{" sentencia* "}"
sentencia   := ("let" | "var") NOMBRE (":" tipo)? "=" expr ";"
             | "if" expr bloque ("else" (bloque | sentencia_if))?
             | "while" expr bloque
             | "for" NOMBRE ("," NOMBRE)? "en" expr (".." expr)? bloque
             | "break" ";" | "continue" ";"
             | "return" expr? ";"
             | "fail" CADENA ";"
             | match
             | lugar "=" expr ";"
             | expr ";"
lugar       := NOMBRE ("." NOMBRE | "[" expr "]")*

expr        := o ("sino" o)?
o           := y ("||" y)*
y           := igualdad ("&&" igualdad)*
igualdad    := orden (("==" | "!=") orden)*
orden       := bit_o (("<" | "<=" | ">" | ">=") bit_o)*
bit_o       := bit_x ("|" bit_x)*
bit_x       := bit_y ("^" bit_y)*
bit_y       := desplaza ("&" desplaza)*
desplaza    := suma (("<<" | ">>") suma)*
suma        := producto (("+" | "-" | "+?" | "-?") producto)*
producto    := conversion (("*" | "/" | "%" | "*?" | "/?") conversion)*
conversion  := unario (("como" | "como" "?") tipo)*
unario      := "try" unario | ("!" | "-" | "~") unario | postfijo
postfijo    := primario ("." NOMBRE ("(" args? ")")? | "[" expr "]")*
primario    := ENTERO | DECIMAL | CADENA | INTERPOLADA | "true" | "false"
             | "[" args? "]"
             | NOMBRE ("(" args? ")")?
             | STRUCT "{" inicios "}"
             | ENUM "." NOMBRE ("(" args? ")")?
             | ALIAS "." NOMBRE ("(" args? ")" | "{" inicios "}")?
             | ALIAS "." NOMBRE "." NOMBRE ("(" args? ")")?
             | "if" expr "{" expr "}" "else" "{" expr "}"
             | clausura | match | "(" expr ")"
args        := expr ("," expr)*
inicios     := (NOMBRE ":" expr ("," NOMBRE ":" expr)* ","?)?
clausura    := "fn" ("[" (captura ("," captura)*)? "]")? "(" params? ")"
               ("->" tipo)? "!"? bloque
captura     := "mut"? NOMBRE

match       := "match" expr "{" brazo+ "}"
brazo       := patrones ("if" expr)? "->" (bloque ","? | expr ",")
             -- el ultimo brazo con expresion puede ir sin ","
patrones    := patron ("|" patron)*
patron      := "_" | forma
forma       := (ENUM | ALIAS "." NOMBRE) "." NOMBRE
               ("(" (posicion ("," posicion)*)? ")")?
posicion    := forma | NOMBRE | "-"? ENTERO | CADENA | "true" | "false"
```

Lo que la gramática sola no dice:

- **Precedencia.** De menos a más: `sino`, `||`, `&&`, `==` `!=`, las
  comparaciones, `|`, `^`, `&`, los desplazamientos, `+` `-`, `*` `/` `%`,
  `como`, los unarios, y `.` e `[]`. **Los operadores de bits atan más que
  las comparaciones**, al revés que en C: `a & b == c` es `(a & b) == c`.
  Todos los binarios asocian por la izquierda.
- **`x.f(a)` es `f(x, a)`**: lo de delante del punto va primero. Un
  `ALIAS.f(...)` es la función `f` del módulo, no esto.
- **`else if`** es un `else` cuyo bloque es ese `if`.
- **Un `match` suelto** es una sentencia y no lleva `;`; el que da un valor
  va en una expresión (`return match ...;`, `let x = match ...;`).
- **Un literal de struct** sólo se lee así si el nombre es de un struct
  declarado; si no, `Nombre {` es un nombre seguido de un bloque.
- **A la izquierda de `=`** sólo puede ir un `lugar`: una variable, un campo
  o un elemento.
- **Los `use`** van todos al principio del archivo. Vale igual para
  `#importar`: es la forma de pedir un módulo de `std/` escribiendo sólo el
  nombre del archivo.
- **`tipo_c` sólo existe en la firma de un `externo`.** `buffer` es un `str`
  que la función de C puede escribir; en el resto del lenguaje no es un tipo.

Este programa usa cada producción. La suite lo compila y lo corre bajo
AddressSanitizer: si la gramática deja de describir el lenguaje, se nota.

```tcode muestra
use "std/texto" como t;

/* Un comentario de bloque. */
externo "math.h" { fn sqrt(x: f64) -> f64; }

struct Par<A, B> { a: A, b: B, }
enum Forma { Punto, Circulo(f64), Rect(i64, i64), }
enum Arbol { Hoja(i64), Nodo(list<Arbol>) }

fn mayor<T: ordenable>(x: T, y: T) -> T {
    if menor(x, y) { return y; } else { return x; }
}

fn area(f: &Forma) -> f64 {
    return match f {
        Forma.Circulo(r) -> 3.0 * r * r,
        Forma.Rect(an, al) if an > 0 -> (an * al) como f64,
        Forma.Punto | Forma.Rect(_, _) -> 0.0,
    };
}

fn suma(a: &Arbol) -> i64 {
    match a {
        Arbol.Hoja(n) -> { return n; }
        Arbol.Nodo(hijos) -> {
            var s: i64 = 0;
            for h en hijos { s = s + suma(h); }
            return s;
        }
    }
}

fn mitad(n: usize) -> usize ! {
    if n % 2 != 0 { fail "impar"; }
    return n / 2;
}

fn uno_o_dos(n: usize, dos: bool) -> usize { if dos { return n * 2; } return n; }

// Un comentario de linea.
fn cuenta(p: &mut Par<usize, str>) { p.a = p.a + 1; }

fn crece(s: mut str, veces: usize) {
    for _i en 0..veces { empujar(s, "+"); }
}

fn main() -> usize ! {
    var p = Par { a: 1, b: nuevo("uno") };
    cuenta(p);
    let grande = 1_000 + (300 como? u8 como usize);
    let exponente: f64 = 1.5e2 /? 2.0;
    let resta: u8 = 0 -? 1;
    var xs: list<usize> = [3, 1, 2];
    xs.anadir(4);
    ordenar(xs);
    let arr: [u8; 3] = [1, 2, 3];
    var m: map<str, usize> = [];
    poner(m, "k", xs[0]);
    let k = obtener(m, "k") sino 0;
    let cuadrado = fn[k](x: usize) -> usize { return x * x + k; };
    let h: fn(usize, bool) -> usize = uno_o_dos;
    let doble = try mitad(h(4, true));
    let r = mitad(3) sino 0;
    var s = nuevo("a");
    crece(s, 2);
    let bits = (5 & 3 | 8 ^ 1) << 1 >> 1;
    let envuelta: u8 = (arr[2] *? 100) +? 1;
    let signo = -(2 como i64) + ~(0 como i64);
    let c = if p.a == 2 && !false || true { "si" } else { "no" };
    var i = 0;
    while i < 3 {
        i = i + 1;
        if i == 1 { continue; } else if i == 3 { break; }
    }
    let arbol = Arbol.Nodo([Arbol.Hoja(4), Arbol.Hoja(5)]);
    imprimir($"{p.b} {xs[0]} {k} {cuadrado(2)} {doble} {r} {s} {bits} {envuelta}\n");
    imprimir($"{signo} {c} {i} {suma(arbol)} {mayor(2, 7)} {area(Forma.Rect(2, 3))} {sqrt(4.0)}\n");
    imprimir($"{grande} {exponente} {resta}\n");
    imprimir($"{t.mayusculas("fin")} {{llaves}} \x41\t|\n");
    return 0;
}
```

Un programa puede anidar expresiones y bloques hasta **5000 niveles**. Más
allá, los dos compiladores lo rechazan con un error en la línea donde se
pasa, en vez de agotar su pila:

```
error: hondo.t:1: el programa anida mas de 5000 niveles; parte la expresion
       o el bloque en trozos, se encontro '('
```

## Funciones internas

Cada una es una operación de la librería de C, con la regla de préstamo que
le corresponde.

| safestr | C generado | efecto sobre préstamos |
|---|---|---|
| `nuevo(cadena) -> str` | `ss_from` | crea un dueño |
| `vacio() -> str` | `ss_new` | crea un dueño |
| `vista(s: str) -> view` | `ss_view` | **presta** `s` |
| `empujar(s: mut str, x)` | `ss_append` / `ss_append_view` | **muta** `s` |
| `largo(x) -> usize` | `ss_len` / `sv_len_of` | solo lee |
| `igual(a, b) -> bool` | `sv_equals` | solo lee |
| `rebanar(v: view, a, b) -> view` | `sv_slice`, con límites comprobados | hereda el préstamo de `v` |
| `imprimir(x)` | `fwrite` / `printf` | solo lee |
| `anadir(xs: mut list<T>, x: T)` | `realloc` + asignación comprobada | **muta** `xs`, mueve `x` si es dueño |
| `leer_archivo(ruta: view) -> str !` | `fopen` / `fread` / `fclose` | crea un dueño; el fallo es explícito |
| `leer_parte_archivo(ruta: view, desde, cuantos) -> str !` | `fseek` / `fread` / `fclose` | crea un dueño de tamaño acotado; vacío indica fin |
| `byte(texto: view, i) -> usize` | acceso con límite comprobado | solo lee |
| `texto(x) -> str` | `ss_appendf` / copia | crea un dueño |

`rebanar` fuera de rango —el final antes del principio, o más allá del
largo— no devuelve una vista vacía ni lee de más: detiene el programa, igual
que un índice.

```
mi.t:3: rebanar(2, 9) fuera de rango (el texto tiene 4 bytes)
```

### Índice de funciones internas

Todas las que trae el lenguaje, sin `use` ni `#importar` nada. Las que **fallan** van con
`try` o `sino`, como cualquier función `!`. El detalle de cada una está en la
sección que se nombra.

| función | falla | qué hace | dónde |
|---|---|---|---|
| `vacio() -> str` |  | un texto vacío, con dueño | Funciones internas |
| `nuevo(v: view) -> str` |  | copia un texto a uno con dueño | Funciones internas |
| `vista(s) -> view` |  | presta `s` | Funciones internas |
| `texto(x) -> str` |  | un entero, `bool`, `view` o `str` como texto | 9. Entrada de archivos y texto construido |
| `empujar(s: mut str, x: view)` |  | añade al final | Funciones internas |
| `empujar_byte(s: mut str, b: u8)` |  | añade un byte | Bytes |
| `largo(x) -> usize` |  | bytes de un texto, elementos de una lista, arreglo, bloque o mapa | Funciones internas |
| `byte(v: view, i: usize) -> usize` |  | el byte `i`, con el índice comprobado | Funciones internas |
| `rebanar(v: view, desde, hasta) -> view` |  | un trozo, con los límites comprobados | Funciones internas |
| `igual(a, b) -> bool` |  | igualdad de dos valores sin partes | `igual` y `menor` sobre cualquier tipo sin partes |
| `menor(a, b) -> bool` |  | orden de dos valores sin partes; los textos, byte a byte | `igual` y `menor` sobre cualquier tipo sin partes |
| `imprimir(x)` |  | a la salida | 11. Salida, escritura y orden |
| `imprimir_error(x)` |  | a la salida de error | 11. Salida, escritura y orden |
| `anadir(xs: mut list<T>, x: T)` |  | añade al final; mueve `x` si tiene dueño | Listas dinámicas |
| `truncar(xs: mut list<T>, n: usize)` |  | recorta a `n`; lo que sobra se libera antes de soltar | Listas dinámicas |
| `ordenar(xs: mut list<T>)` |  | ordena en el sitio: `bool`, los números o `str` | 12. Recorridos |
| `copiar(x: &T) -> T` |  | copia profunda de cualquier valor | `copiar`: copia profunda, explícita, sin anotar nada |
| `reservar(n: usize) -> bloque<T>` |  | `n` ranuras, todas a ceros | Memoria propia: `bloque<T>`, `reservar` e `intercambiar` |
| `redimensionar(b: mut bloque<T>, n: usize)` |  | cambia el tamaño; lo nuevo, a ceros | Memoria propia: `bloque<T>`, `reservar` e `intercambiar` |
| `intercambiar(sitio, valor: T) -> T` |  | deja `valor` en `sitio` y devuelve lo que había | `intercambiar` |
| `poner(m: mut map<K, V>, clave, valor)` |  | inserta o reemplaza | 10. Mapas y argumentos |
| `obtener(m, clave) -> V` | sí | una copia, una `view` o un `&V`, según `V` | 10. Mapas y argumentos |
| `obtener_mut(m: mut map<K, V>, clave) -> &mut V` | sí | presta para modificar lo guardado | `&mut T`: préstamos que sí escriben |
| `tiene(m, clave) -> bool` |  | si la clave está | 10. Mapas y argumentos |
| `quitar(m: mut map<K, V>, clave) -> bool` |  | borra; dice si había algo | Borrado en los mapas |
| `claves(m) -> list<K>` |  | copias de las claves | 10. Mapas y argumentos |
| `raiz(x), piso(x), techo(x), redondear(x)` |  | de `f32` o `f64`, en su tipo; `redondear` lleva el `.5` lejos de cero | Lo que trae `std` |
| `absoluto(x)` |  | de un entero con signo; el del mínimo para el programa | Lo que trae `std` |
| `n_argumentos() -> usize` |  | cuántos argumentos, el programa incluido | Argumentos de la línea de órdenes |
| `argumento(i: usize) -> view` |  | el argumento `i`, con el índice comprobado | Argumentos de la línea de órdenes |
| `leer_archivo(ruta: view) -> str` | sí | el archivo entero, bytes tal cual | 9. Entrada de archivos y texto construido |
| `leer_parte_archivo(ruta: view, desde, cuantos) -> str` | sí | como mucho `cuantos` bytes desde `desde`; vacío al final | Funciones internas |
| `escribir_archivo(ruta: view, contenido: view)` | sí | reemplaza el archivo entero, de una vez | 11. Salida, escritura y orden |
| `leer_linea() -> str` | sí | una línea de la entrada, sin el salto; falla al acabarse | El sistema: lo que no puede ir por `externo` |
| `entrada_completa() -> str` | sí | toda la entrada | El sistema: lo que no puede ir por `externo` |
| `variable_entorno(nombre: view) -> str` | sí | falla si no está; vacía si está vacía | El sistema: lo que no puede ir por `externo` |
| `ahora_ms() -> i64` |  | reloj de pared, en milisegundos | El sistema: lo que no puede ir por `externo` |
| `monotono_ms() -> i64` |  | reloj para medir duraciones | El sistema: lo que no puede ir por `externo` |
| `azar(n: usize) -> usize` |  | de `0` a `n - 1`, sin sesgo | El sistema: lo que no puede ir por `externo` |
| `sembrar(s: u64)` |  | fija la semilla de `azar` | El sistema: lo que no puede ir por `externo` |

### 10. Mapas y argumentos

`map<K, V>` es una tabla hash dueña de sus claves:

```tcode
var cuenta: map<str, usize> = [];
poner(cuenta, "hola", 1);
let n: usize = obtener(cuenta, "hola") sino 0;
```

| operación | qué hace |
|---|---|
| `poner(m: mut map<K,V>, clave, valor)` | inserta o reemplaza; el mapa **copia** la clave |
| `obtener(m, clave) -> V !` | falible: una clave ausente no es un caso especial, es un fallo |
| `tiene(m, clave) -> bool` | sin construir el valor |
| `claves(m) -> list<K>` | copias, para poder recorrerlo |
| `largo(m) -> usize` | cuántas entradas |
| `obtener_mut(m, clave) -> &mut V !` | presta para modificar lo guardado (ver `&mut T`) |
| `quitar(m, clave) -> bool` | borra, y dice si había algo (ver *Borrado en los mapas*) |

Por dentro es direccionamiento abierto con sondeo lineal y capacidad
potencia de dos, que crece al 70% de ocupación. Borrar no deja lápidas, así
que una celda con clave vacía corta la búsqueda.

Que `obtener` sea falible no es celo: es la misma decisión que en
`leer_archivo`. Una clave que no está no es un valor, y devolver un cero
disfrazado es exactamente cómo se cuelan los errores.

**Los límites, dichos donde se declara el mapa:**

- **La clave tiene que ser `str`.** Se consulta con un `view`, sin copiar.
- **El valor es cualquier tipo que se pueda guardar, menos `view` y
  `&T`**: un mapa guarda valores, no préstamos. Un escalar, un `str`, un
  struct, un enum, una lista, otro mapa, un bloque o un arreglo.

Lo que devuelve `obtener` depende del valor. Para un escalar, una copia;
para un `str`, **una vista prestada del texto que ya vive dentro de la
tabla**, así que no se saca al dueño ni se copia nada:

  ```tcode
  var cfg: map<str, str> = [];
  poner(cfg, "host", nuevo("localhost"));
  let h: view = obtener(cfg, "host") sino "(sin valor)";
  ```

  Esa vista presta del mapa, así que modificarlo mientras se vaya a usar es
  un error:

  ```
  error: no se puede modificar `cfg`: esta prestada por `h`
  ```

  Y no puede salir de la función, por la misma regla que cualquier vista de
  algo local.

  Para cualquier otro valor —un struct, una lista, un mapa—, `obtener`
  devuelve un **`&V`**: un préstamo de solo lectura del valor que está en
  la tabla.

  ```tcode
  struct Simbolo { tipo: str, mutable: bool, usos: usize }

  var tabla: map<str, Simbolo> = [];
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
y es falible como su gemela de lectura. `imprimir` también escribe los bytes
tal cual: un texto con un cero en medio sale entero, no cortado donde un
`printf("%s")` creería que acaba.

Para el orden hay dos piezas:

| | |
|---|---|
| `menor(a, b) -> bool` | orden de dos valores del mismo tipo: números, `str` y `view` |
| `ordenar(xs: mut list<T>)` | ordena en el sitio |

`menor` e `igual` valen para dos valores del mismo tipo sin partes, como se
cuenta en [*`igual` y `menor` sobre cualquier tipo sin partes*](#igual-y-menor-sobre-cualquier-tipo-sin-partes).
`ordenar` funciona sobre `bool`, los once números y `str`, que son los
tipos con un orden evidente. **Un struct no lo tiene**: cuál de sus campos
manda es una decisión del programa, no del lenguaje, y el compilador lo dice
en vez de inventarse uno.

### Borrado en los mapas

`quitar(m: mut map<K,V>, clave) -> bool` devuelve si había algo que quitar,
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

Recorre una `list<T>`, un arreglo o un `map<K, V>`. Sobre un mapa se
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
`{obtener(m, k) sino ""}`, `{a.campo}`. Para escribir una llave, `{{` y `}}`, o
`\{` y `\}`: son lo mismo, y el formateador las deja como `{{` y `}}`.

Un hueco puede llevar sus propias cadenas, escritas como en cualquier otro
sitio: `$"{obtener(m, "k") sino "?"}"`. La forma antigua, `\"` dentro del
hueco, sigue valiendo. Y un error dentro de un hueco se dice en la línea
de la cadena, no en la primera del archivo.

No hay formato en tiempo de ejecución. Cada hueco se convierte con las
mismas reglas que `imprimir`, y como el tipo se conoce al compilar, el C que
sale es una secuencia de `ss_append_view` — no un `printf` con cadena
variable. `imprimir` y los huecos escriben números, `bool` y texto, o un
préstamo de uno de ellos. Lo demás —una lista, un struct, un enum, una
función— es un error de compilación que dice qué hacer, no un `?` en la
salida. Un enum se escribe con un `match` que da el nombre de cada forma.

## Autoanálisis

El **frontend de Tcode, escrito en Tcode**: el léxico en
`ejemplos/lexer/lib/lexico.t` y la sintaxis en `lexer.t` y `parser.t`.

La suite los compila y los corre en cada ejecución, sobre `ejemplos/hola.t`,
y `make cifras` mide en el README lo que imprimen sobre su propio código: los
tokens de `lexico.t` y los nodos de `parser.t`.

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
- Se pasa tal cual a una función que presta: con `ver(x: &Simbolo)`,
  `ver(s)` le da el mismo puntero. Lo que atrapa un `match` es igual. Un
  `&mut T` también va a un parámetro `mut T`; un `&T`, no, y el error lo
  dice.
- Un mapa guarda valores, no préstamos: `map<str, &T>` es un error.

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
| `std/texto` | `palabras`, `terminos`, `lineas`, `partir`, `unir`, `recortar`, `rellenar`, `alinear`, `minusculas`, `mayusculas`, `apariciones`, `repetir`, `reemplazar`, `empieza_con`, `termina_con`, `contiene`, `indice_de`, `a_entero` |
| `std/iterador` | recorridos de una pasada: `para_cada`, `todas`, `alguna`, `primera_que`, `plegar`, `transformar` |
| `std/archivo` | `por_partes` con memoria acotada y `partes_de_archivo` |
| `std/lista` | genéricas sobre `list<T>`: `suma`, `maximo`, `minimo`, `media`, `invertir`, `incluye`, `posicion`, `primeras`, `invertida`, `aplanar`, `esta_vacia`, `ultima_posicion`, `ordenadas_por`, `filtradas`, `cuantas_cumplen` |
| `std/numero` | `dividir`, `resto`, `porcentaje`, `menor_de`, `mayor_de`, `acotar` |
| `std/cuenta` | `contar` y `mayores` — lo que en Python es `Counter` y `most_common` |
| `std/mapa` | `acumular`, `obtener_o`, `claves_ordenadas`, `valores_ordenados`, `actualizar`, `completar`, `cuantas_claves` |
| `std/conjunto` | `Conjunto` sobre un mapa: `union`, `interseccion`, `diferencia` |
| `std/par` | `Par<A, B>`: dos valores juntos, para cuando uno no basta |
| `std/bytes` | enteros en orden de red, `a_hex`, `de_hex` |
| `std/vector` | `Vector<T>` sobre `bloque<T>`, con conversión a `list<T>` |
| `std/formato` | `con_decimales`, `con_millares`, tablas alineadas |
| `std/prueba` | afirmaciones y resumen: probar Tcode desde Tcode |
| `std/terminal` | el cursor y el dibujo (`subir`, `borrar_linea`, `barra`, `marco`), el tamaño (`filas`, `columnas`, `tiene_tamano`), el teclado (`modo_crudo`, `leer_tecla`, `leer_tecla_con_tope`) y el ratón (`activar_raton`, `es_raton`, `raton_boton`, `raton_x`…) |
| `std/proceso` | `ejecutar` y `va_bien` para el código de salida, `salida_de` y `salida_de_hasta` para lo que la orden imprime |

Dos nombres piden explicación. `palabras` parte por espacios y `terminos`
por cualquier cosa que no sea letra ni dígito: lo primero es lo que quiere
quien separa campos de una línea, lo segundo lo que quiere un contador de
palabras. Y partir texto se llama `partir`, no `dividir`, porque `dividir`
es la división de `std/numero`: dos cosas distintas no pueden compartir
nombre mientras no haya espacios de nombres.

`std/lista` es genérica: `suma<T: numero>`, `maximo<T: ordenable>`,
`incluye<T: igualable>` y `primeras<T>` valen para cualquier lista cuyo
elemento cumpla lo que el cuerpo necesita. Eso es lo que pide una restricción,
y por eso ya no hace falta una familia de funciones por tipo de elemento.

Lo que gana el programa que las usa se ve mejor que se explica:

```tcode
use "std/cuenta";
use "std/texto";

fn main() -> usize ! {
    let texto = try leer_archivo(argumento(1));
    let cuenta = contar(palabras(minusculas(texto)));

    for palabra en mayores(cuenta, 5) {
        imprimir($"{obtener(cuenta, palabra) sino 0}  {palabra}\n");
    }
}
```

Eso mismo eran **107 líneas** antes de que existiera `std/`. En Python son 5.
Las cuatro de diferencia son el `use`, el `try` al leer el archivo, y que
`obtener` devuelve un fallo en vez de un cero disfrazado: es decir, justo lo
que compra las garantías.

**Encadenar llamadas funciona**: `contar(palabras(minusculas(texto)))`. Un
valor recién creado se puede prestar, aunque no tenga nombre — el compilador
lo guarda hasta el final de la sentencia y lo libera ahí. Eso vale también
donde el valor se devuelve: `return $"[{rellenar(v, 8)}]"` suelta el `str`
de `rellenar` antes de salir, no después.

### `std/terminal`: dibujar, medir y leer

Lo que se dibuja son **códigos de escape, y eso es texto**: `subir(2)`,
`borrar_linea()`, una `barra` de avance o un `marco` son funciones normales
que devuelven `str`, y quien llama decide si eso va a una terminal o a un
archivo. Nada de esa mitad necesita backend. Lo que sí habla con el
terminal son tres cosas —el tamaño, el teclado y el ratón—, y las tres
cruzan el borde de `externo` por `std/terminal.c`, al lado del módulo: por
el borde sólo pasan números y `bool`, y el resto —`ioctl`, `poll`, el
`FILE*` de stdio— no cabe.

**El tamaño siempre tiene respuesta.** `filas()` y `columnas()` devuelven lo
que diga `ioctl(TIOCGWINSZ)`, o **24 y 80** cuando no hay una terminal de
verdad, y `tiene_tamano()` distingue las dos cosas: es lo que hay que mirar
antes de dibujar algo que ocupe la pantalla entera. El recambio no es
cortesía: en una pseudoterminal recién abierta y sin tamaño fijado, `ioctl`
acierta y devuelve cero, y un cero como tamaño es peor que no saberlo.

**El tope de tiempo devuelve un nombre, no el texto vacío.**
`leer_tecla_con_tope(milisegundos)` es lo que deja repintar un cronómetro
mientras se espera una tecla: se repinta, se mira si hay tecla, y si no la
hay se vuelve a repintar. Cuando se acaba el tiempo devuelve `"sin_tecla"`,
que es un nombre propio **a propósito**: `leer_tecla` ya devuelve `""` para
una secuencia que no conoce —Mayús+flecha, por ejemplo—, que hay que
ignorar, y con el mismo texto no se podrían distinguir «todavía no hay
tecla» de «esa tecla no la sé». El ESC suelto no cambia de contrato:
sigue siendo la tecla Escape, porque esperar unos milisegundos a ver si
llega más partiría las secuencias por la mitad en un enlace lento —ssh, un
multiplexor—. `milisegundos` negativo espera sin tope, como `leer_tecla`.

**El ratón llega como texto, y se lee como texto.** Con `activar_raton()`
el terminal manda cada clic en SGR —`?1002h` para pulsar, soltar y
arrastrar, `?1006h` para que venga como texto y no como tres bytes en
crudo—; `leer_tecla` devuelve el evento como
`raton:<botón>:<acción>:<x>:<y>` (`raton:izquierda:pulsa:12:5`), y
`es_raton`, `raton_boton`, `raton_accion`, `raton_x` y `raton_y` lo leen sin
partir la cadena a mano. Las coordenadas van de 1 en adelante, como las
manda el terminal: quien dibuje un tablero les resta uno.

`desactivar_raton()` **devuelve la cadena y no imprime**: este módulo no
escribe. Quien lo use tiene que imprimirla al salir, junto a `modo_normal`,
o el terminal sigue mandando secuencias de ratón a la shell, que las pinta
como basura. Es la misma regla que con el modo crudo: un `fail` que se
propague deja el terminal tocado, y `stty sane` lo arregla en la shell.

```tcode
use "std/terminal";

fn main() -> usize {
    // Si la salida no es una terminal, esto son 24x80: se puede dibujar un
    // marco sin preguntar antes.
    let alto = filas();
    let ancho = columnas();
    imprimir($"{alto}x{ancho}\n");

    // El cronómetro: mientras no llegue una tecla, se repinta.
    var paso = 0;
    var tecla = leer_tecla_con_tope(50);
    while tecla == "sin_tecla" {
        imprimir(giro(paso));
        paso = paso + 1;
        tecla = leer_tecla_con_tope(50);
    }

    // El ratón, si es un evento de ratón y no una tecla.
    if es_raton(tecla) {
        let boton = raton_boton(tecla) sino nuevo("?");
        let x = raton_x(tecla) sino 0;
        let y = raton_y(tecla) sino 0;
        imprimir($"{boton} en {x}:{y}\n");
    }
    return 0;
}
```

`leer_tecla` devuelve `""` cuando la secuencia no se conoce y
`"fin_de_entrada"` cuando la entrada se cerró, y `leer_tecla_con_tope`
devuelve además `"sin_tecla"` cuando se acaba el tiempo. Las tres cosas se
ignoran de forma distinta, y por eso tienen nombres distintos; el bucle de
arriba sale en cuanto llega cualquier otra cosa, porque
`leer_tecla_con_tope` no espera a entender la tecla, sólo a que haya algo
que leer.

### `std/proceso`: lanzar una orden y quedarse con lo que imprime

`ejecutar(orden)` devuelve el código de salida, y `salida_de(orden)` devuelve
**lo que la orden imprimió** en un `str` de Tcode. La orden es la misma en
las dos: va por el shell, así que entiende tuberías, redirecciones y
variables de entorno. Eso no es un detalle de implementación, es la decisión:
`ejecutar` ya usaba `system` y `salida_de` usa `popen`, que también pasa por
`/bin/sh`; con `pipe`+`fork`+`exec` habría que partir la orden en `argv` a
mano y las dos funciones dejarían de entender lo mismo. Lo que se paga es
que `popen` da **un solo flujo**: se lee la salida estándar, y el error
estándar se queda donde estaba.

**Que la orden salga con error no es un fallo.** El `!` de las tres es para
lo que impide contestar: que no se pudiera lanzar, que el shell no encontrara
la orden —el 127, el mismo trato que en `ejecutar`— o que la salida no
cupiera en el tope. El código de salida se mira sólo para eso: una orden que
sale con 1 es una respuesta, y su texto vuelve igual.

**`salida_de_hasta(orden, tope)` lleva tope porque la salida no se sabe
cuánto mide.** El texto crece en un búfer de C hasta que la orden termina o
hasta el tope; sin tope, un `yes` o un `cat /dev/zero` se comerían la
memoria del proceso. Al llegar al tope **falla**, en vez de devolver medio
texto como si fuera el texto entero. El `salida_de` de siempre lleva 8 MiB.

El tope se cumple **exacto**, también por debajo de los 4 KiB del primer
bloque: el búfer nunca empieza por encima del tope, y cuando ya mide el tope
se prueba un byte más —en el hueco del terminador— para distinguir «se acabó
justo en el tope», que es un éxito, de «había más», que falla.

**Es para texto, no para bytes.** La copia que sale de C usa `strlen`, así
que un cero en medio de la salida la corta ahí: `salida_de` sirve para lo
que una orden imprime de verdad —líneas, JSON, un `uname`—, no para leer un
binario.

El `FILE*` de `popen`, el búfer que crece y su liberación viven en
`std/proceso.c`, al lado del módulo, y no por gusto: un puntero opaco y
memoria que hay que soltar no caben en el borde de `externo`. Tcode copia el
texto al volver de la captura —esa copia la hace el borde por `cadena_c`— y
el búfer de C se suelta acto seguido, antes de cualquier `!`.

```tcode
use "std/proceso" como proceso;

fn main() -> usize ! {
    // La orden entiende tuberías y redirecciones: es la misma que `ejecutar`.
    let lineas = try proceso.salida_de("wc -l < std/proceso.t");
    imprimir($"std/proceso.t tiene {lineas}");

    // Una orden que sale con error no es un fallo: el texto vuelve igual.
    let saludo = try proceso.salida_de("printf hola; exit 3");
    imprimir($"la orden falló y aun así dijo {saludo}\n");

    // El tope: si la salida no cabe, esto falla en vez de devolver medio texto.
    let poco = try proceso.salida_de_hasta("printf 1234567890", 4096);
    imprimir($"cabían {largo(poco)} bytes\n");
    return 0;
}
```

Eso imprime `std/proceso.t tiene 85`, `la orden falló y aun así dijo hola` y
`cabían 10 bytes`: en la tercera, la orden imprime menos que el tope, así que
no se corta nada.

## Genéricas

Una función puede dejar tipos sin decidir: `fn primeras<T>(xs: &list<T>,
n: usize) -> list<T>`. Dentro de la firma y del cuerpo, `T` es un tipo más.

No hay borrado de tipos ni casts escondidos: de cada genérica sale **una
copia por cada juego de tipos con que se use**, y esa copia se comprueba
entera con los tipos ya puestos. Eso tiene una consecuencia que conviene ver
antes de escribir la primera:

```tcode
fn primeras<T>(xs: &list<T>) -> list<T> {
    var salida: list<T> = [];
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
Se deduce con las mismas reglas con que se comprueba: en `mismo(1 + x)` el
`1` toma el tipo de `x`, y una conversión, un `if` o `absoluto(x)` dicen el
suyo.

Un mismo parámetro de tipo es un solo tipo en toda la llamada. `dos(1, s)`
sobre `fn dos<T>(a: T, b: T)` no compila, y el error dice qué argumento
fijó `T` primero.

Lo que el cuerpo necesita del elemento se le pide a `T` con una
**restricción**, escrita en la firma: `fn suma<T: numero>(ns: &list<T>) -> T`.
Son conjuntos de tipos con nombre, y son lo que hace genéricas a `suma`,
`maximo`, `incluye` o `primeras` de `std/lista`. Con `T` sin restricción el
cuerpo sólo puede tratarlo como cualquier valor: copiarlo, moverlo o mirarlo
por encima. Los structs también llevan parámetros de tipo (`struct Pila<T>`),
como se cuenta más abajo.

## `copiar`: copia profunda, explícita, sin anotar nada

`copiar(x)` da una copia independiente de cualquier valor: un número, un
`str`, un struct, una `list<list<str>>`, un `map<str, V>`. Tocar el
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
fn primeras<T>(xs: &list<T>, cuantas: usize) -> list<T> {
    var salida: list<T> = [];
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
fn suma<T: numero>(ns: &list<T>) -> T
fn incluye<T: igualable>(xs: &list<T>, aguja: &T) -> bool
fn maximo<T: ordenable>(xs: &list<T>) -> T !
```

Hay seis, y son **conjuntos de tipos con nombre**:

| restricción | tipos | para qué |
|---|---|---|
| `numero` | `u8`, `u16`, `u32`, `u64`, `usize`, `i8`, `i16`, `i32`, `i64`, `f32`, `f64` | `+`, `-`, `*`, `/` |
| `entero` | los mismos, sin `f32` ni `f64` | `%`, `&`, `\|`, `^`, `<<`, `>>`, `~` |
| `decimal` | `f32`, `f64` | `/?` y lo que sólo tiene sentido con decimales |
| `igualable` | todos los números, `bool`, `str` y `view` | `igual` |
| `ordenable` | todos los números, `str` y `view` | `menor` |
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

**Compila para todo `T` que la cumpla, como en Rust.** En Rust el cuerpo de
una genérica se comprueba una vez, contra la restricción. Aquí las
restricciones son **conjuntos finitos**, así que se consigue lo mismo sin
traits: el cuerpo se comprueba con **cada tipo del conjunto**, también con los
que nadie usa, y también si la genérica no se llama nunca.

```
fn primera<T: igualable>(xs: &list<T>) -> T { let t = xs[0]; return t; }

error: f.t:1: no se puede sacar un elemento de una lista y dejar el hueco
              sin duenio. ...
  al comprobar `primera` con T = str: la restriccion lo admite, asi que el
  cuerpo tiene que valer tambien asi
```

aunque el programa solo la use con `usize`. Se saltan los tipos que dejan la
firma sin sentido —`T = view` sobre un `&list<T>`: nadie podría llamarla
así—. Un parámetro sin restricción no tiene conjunto: se prueba con los tipos
con que se usó.

**Dónde somos mejores que no tenerlas.** El valor está en dónde aparece el
error:

```
$ cat sin.t
fn suma<T>(ns: &list<T>) -> T { var t = ns[0]; return t; }

error: sin.t:1: no se puede sacar un elemento de una lista y dejar el hueco
                sin duenio. Si solo quieres leerlo, prestalo:
                `let x: &str = ...`; si lo necesitas tuyo, `copiar(...)`; si
                quieres sacarlo, di que dejas en su sitio: `intercambiar(...)`
  al usar `suma` con T = str, desde sin.t:5
```

```
$ cat con.t
fn suma<T: numero>(ns: &list<T>) -> T { ... }

error: con.t:6: `suma` pide que `T` sea `numero`, y aqui `T` es `str`.
                `numero` son: `f32`, `f64`, `i16`, `i32`, `i64`, `i8`,
                `u16`, `u32`, `u64`, `u8`, `usize`
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
struct Pila<T> { cosas: list<T> }
struct Par<A, B> { primero: A, segundo: B }
struct Nodo<T> { valor: T, hijos: list<Nodo<T>> }
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
`list<T>` y `map<K, V>` siguen dentro del compilador, pero ya no hacen
falta para escribir un contenedor.

## Enteros de ancho fijo, bits y bytes

`u8`, `u16`, `u32`, `u64`, `usize`, `i8`, `i16`, `i32`, `i64`. El ancho va en
el nombre, menos en `usize`, que mide cosas de la máquina y por eso vale lo
que valga ahí.

El literal toma el tipo del lugar donde se usa, pero no se trunca para caber:
`let x: u8 = 256;` es un error de compilación. Los mínimos con signo son
válidos (`-128` en `i8`, `-9223372036854775808` en `i64`) porque el signo y la
magnitud se comprueban juntos. Una magnitud mayor que `u64` se rechaza en el
parser con un diagnóstico acotado, aunque el texto tenga millones de dígitos.

Un literal `usize` se comprueba contra 64 bits, porque el compilador no sabe
cuánto mide `size_t` en la máquina de destino. Por encima de `2^32 − 1` el C
generado lo pregunta al compilador de C (`SS_LANG_USIZE_LIT`): en un destino
de 32 bits, `let n: usize = 5000000000;` no compila en vez de truncarse. Un
cero delante no cambia la base: `010` es diez.

**La aritmética comprobada vale para todos.** Un `u8` que se pasa de 255
detiene el programa igual que un `usize` que se pasa de `SIZE_MAX`:

```
ejemplo.t:3: desbordamiento en `+`
```

Sólo se emiten las familias de operaciones que el programa usa: uno que sólo
maneja `usize` no carga con las nueve.

### Conversión: `como`

```tcode
let ancho = a como u32;     // aborta si el valor no cabe; con numeros
                            // escritos, no compila: `300 como u8`
let corto = v como? u8;     // se queda con los bits de abajo, a propósito
```

El `?` es el mismo de `+?`: *quiero salirme de la comprobación y lo digo*.
Entre enteros se compara primero en `intmax_t`/`uintmax_t` contra los límites
del destino y sólo después se convierte; ningún cruce de signo ni
estrechamiento depende del resultado que C elija para un cast fuera de rango.
De decimal a entero se demuestran antes del cast la finitud, la ausencia de
fracción y el intervalo `[−2^(N−1), 2^(N−1))` o `[0, 2^N)`: NaN, infinito y
los bordes redondeados no llegan nunca a una conversión indefinida de C17.

De entero a decimal tampoco se vuelve a convertir el resultado: se cuenta la
magnitud binaria y se comprueban los bits que quedarían fuera de la mantisa.
Así `2^53` cabe exactamente en `f64`, pero `2^53 + 1` y `u64::MAX` no pierden
un bit en silencio ni pueden redondearse hasta `2^64`.

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

Un efecto de todo esto: `list<list<str>>` acaba en dos `>` pegados, que el
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

fn ordenadas_por<T, F>(xs: &list<T>, antes: F) -> list<T>
```

Eso es un puntero a función: **coste cero, y no posee nada**, así que se
copia como un número y no hay que liberarlo.

**Un puntero a función no captura nada.** Para llevarse variables consigo
están las [clausuras](#clausuras), con la lista de lo que capturan escrita
delante: decidir qué posee y cuánto vive es un diseño entero —en Rust son
tres traits— y aquí se resuelve capturando por valor.

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
El literal tiene que ser finito en su tipo de destino: por ejemplo, `1e309`
no es un `f64` válido y `3.5e38` no es un `f32` válido. El compilador lo
rechaza antes de emitir C; nunca depende de que el backend lo redondee a
infinito. El borde es exactamente donde C empezaría a redondear a infinito,
así que `3.4028235e38`, la forma corta del máximo de `f32`, vale y da ese
máximo.

Un entero escrito donde va un decimal tiene que caber exacto, igual que con
`como`: `let x: f64 = 9007199254740992;` (`2^53`) vale, pero
`9007199254740993` es un error de compilación en vez de redondearse en
silencio.

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
`/?` sólo existe entre decimales: entre enteros no hay vuelta que dar, y
dividir por cero no tiene un resultado que devolver en su lugar.

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

`como` entre enteros y decimales comprueba que no se pierda información. Al
ir de decimal a entero, valida finitud, fracción y rango antes de convertir:

```tcode
let x = n como f64;          // 7 -> 7.0
let k = exacto como usize;   // 3.0 -> 3, vale
let m = f como usize;        // 3.7 -> para: el valor no cabe
```

Al ir de entero a decimal, valida primero que los bits significativos que no
caben en la mantisa sean todos cero. No usa un cast de vuelta al entero, que
sería peligroso si el redondeo produjera justo `2^64`.

Al estrechar `f64` a `f32`, comprueba finitud y `FLT_MAX` antes del cast; una
vez dentro del rango, la ida y vuelta rechaza cualquier redondeo de precisión.

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
fn filtradas<T, F>(xs: &list<T>, cumple: F) -> list<T>
```

Y ese mismo `F` acepta también una función con nombre, así que una sola
firma vale para las dos. Un `fn(&T, &T) -> bool` —puntero a función— no
acepta clausuras, y el error lo dice y propone hacerlo genérico.

### Modificar lo capturado: `mut` en la captura

```tcode
let n: usize = 0;
var contar = fn[mut n]() -> usize {
    n = n + 1;
    return n;
};
contar();    // 1
contar();    // 2; la `n` de fuera sigue valiendo 0
```

Lo capturado con `mut` es **la copia de la clausura**, no la variable de
fuera: capturar sigue siendo por valor. Lo que la clausura cambia se queda
en su struct, y sigue ahí en la llamada siguiente. Un contador, un
acumulador, un generador: estado propio, sin préstamos que vigilar.

El `mut` va en la captura, igual que en un parámetro: se ve en la línea
donde nace qué puede cambiar. Modificar algo capturado sin `mut` es un
error que dice cómo arreglarlo, y un `mut` que nunca se usa, un aviso.

Llamar a una clausura así **la modifica**, y eso se comprueba como
cualquier otra modificación, sin reglas nuevas:

- guardada en una variable, la variable tiene que ser `var`;
- una genérica que la llame la recibe como `mut F`, y lo que cambie, cambia
  en la de quien llama;
- `copiar` da otra clausura con su propio estado, que desde ahí va por
  separado.

```tcode
fn repetir<F>(n: usize, f: mut F) { ... }

repetir(3, contar);   // `contar` sigue contando desde donde lo dejó
```

Es lo que en Rust separa `Fn` de `FnMut`, y aquí no necesita un trait: la
clausura es un struct, y un struct ya se presta para leer (`&`) o para
modificar (`mut`). Por dentro, su función recibe el entorno como `mut
Cierre_N` en vez de `&Cierre_N`, y nada más cambia.

```
error: f.t:3: `n` se capturo para leer: para modificarlo dentro de la
              clausura, capturalo con `fn[mut n]`
error: f.t:9: `f` es una clausura que modifica lo que capturo, y llamarla
              la modifica: recibela como `f: mut F`
```

En `std/lista` lo usan `filtradas`, `cuantas_cumplen` y `ordenadas_por`.

## Memoria propia: `bloque<T>`, `reservar` e `intercambiar`

`list<T>` y `map<K, V>` los pone el compilador. Debajo de ellos no había
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
Un `&mut bloque<T>` puede cambiarlo de tamaño, pero no mientras exista una
vista o un préstamo vivo de sus elementos: al encoger, esa memoria se libera.
El bloque también queda reservado durante el cálculo del tamaño nuevo: ese
cálculo puede consultarlo, pero no consumirlo ni modificarlo.
Si el bloque está dentro de otra colección, se localiza una sola vez y antes
de calcular el tamaño nuevo.

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
una `list<str>` en el sitio —imposible hasta ahora— son seis líneas.

El sitio y cada índice que lo identifica se evalúan una sola vez. Mientras se
calcula el reemplazo, el destino queda reservado: se puede leer o copiar, pero
no moverlo ni modificarlo desde el segundo argumento.

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

`list<T>` sigue siendo la que trae de serie, por ergonomía —literales `[]`,
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
  tokens que la entrada, y la suite lo comprueba sobre todos los `.t` del
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
    Lista(list<Json>),
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

Varios patrones que hacen lo mismo se pueden reunir con `|`:

```tcode
match e {
    Estado.Inicial | Estado.Terminado -> imprimir("quieto"),
    Estado.Trabajando(n) | Estado.Esperando(n) -> imprimir(n),
}
```

Cada alternativa se comprueba por separado. Por eso, si el cuerpo usa un
nombre atrapado, ese nombre tiene que aparecer en todas las alternativas.
Una guarda escrita después de las alternativas se aplica a cada una.

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

`==` y `!=` comparan un enum **sin datos** por su etiqueta:
`n.clase == Clase.Para`. Uno en el que alguna forma lleva algo no se compara
así —habría que decidir qué es ser iguales—, y se mira con `match`. Lo mismo
vale para un struct, una lista, un mapa o un arreglo: `==` no compara lo que
tiene partes.

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

### Patrones anidados, literales y guardas

En cada posición de un patrón va un nombre, `_`, un literal o otra forma, y
el brazo puede llevar una guarda:

```tcode
match f {
    Forma.Circulo(0) -> nuevo("vacio"),
    Forma.Circulo(r) if r > 100 -> nuevo("grande"),
    Forma.Etiqueta(s, Color.Otro(c)) -> $"{s} de color {c}",
    Forma.Etiqueta("hola", _) -> nuevo("saludo"),
    _ -> nuevo("otra"),
}
```

Un brazo con guarda, o con un literal o una forma en alguna posición, puede
no casar, así que no cubre su forma él solo: la exhaustividad pide un brazo
sin condiciones para esa forma, o un `_`, y el error dice cuáles faltan. Lo
anidado se atrapa igual que lo de fuera —prestado—, y `_` en una posición no
atrapa nada. Una guarda no mueve nada: se evalúa aunque el brazo no llegue a
casar.

Un `match` así no cabe en un `switch` de C: sale como una fila de `if`, y el
brazo que casa salta al final con un `goto`. De paso, un `break` dentro del
`switch` de un `match` simple sale del bucle, no del `switch`.

Tcode no tiene enums con parámetros de tipo (`enum Quiza<T>`) ni patrones
sobre rangos. Un enum no lleva vistas ni structs que prestan.

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
| `buffer` | sí, un `str` que C puede escribir | no |
| `cadena_c` | no | sí, Tcode copia |
| nada (`()`) | — | sí |
| `view`, `list`, `map`, structs, enums | no | no |

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

**`buffer` es un `str` en el que la función de C va a escribir.** Sólo vale
en la firma de un `externo`, y al llamarla hay que pasarle una variable `var`:
el generador le quita el `const` a propósito, porque C escribirá dentro.
Fuera de un `externo` `buffer` no es un tipo —el error lo dice—, y como
nombre de variable sigue valiendo.

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
falta un Makefile ni salir de la orden `tcode`. El archivo se resuelve
**relativo al directorio del módulo que declara el bloque**, no al del
programa que lo usa: `externo "proceso.c"` dentro de `std/proceso.t` busca
`std/proceso.c`. Por eso un módulo de `std/` puede traer su acompañante y
usarlo desde cualquier programa, escriba donde escriba su `.t`.

El acompañante **no se incluye**: no hay un `#include "proceso.c"` por
ningún lado. Se compila aparte y se enlaza, y en el C generado sólo queda el
prototipo. Es lo que evita que dos módulos que envuelven la misma cabecera
choquen entre sí.

**`--mostrar-c` no lo enlaza, y `--emitir-c` tampoco.** Los dos modos tienen
el C por producto, y quien lo pida es quien enlaza, así que los `.c`
acompañantes se pasan a mano junto al C generado. Por eso el `Makefile` los
tiene en `STD_C` —hoy `std/proceso.c` y `std/terminal.c`— en las cuatro
líneas de `cc` que compilan la semilla, y la suite los declara en `apoyo` en
sus casos. No es opcional aunque `-O1` tire las funciones `static` que nadie
llama: `tcodec` escribe TODAS las funciones de TODOS los módulos que carga,
así que el C generado **referencia** esos símbolos aunque nadie los use, y
sin ellos el enlazador se queja. Con `-O0`, o con `-ffunction-sections`, no
hay optimizador que los tire; la regla no puede depender de que GCC siga
tirando estáticos muertos.

Un `.c` escrito a mano junto a un módulo es **fuente**, y va en el
repositorio. Es la razón de que `.gitignore` tenga destapados
`std/proceso.c` y `std/terminal.c` fichero a fichero, con el porqué escrito
al lado: sin ellos, `externo "algo.c"` no encuentra su archivo en una copia
limpia, `install` no lo lleva y el paquete de `git archive` saldría sin él.
Los `.c` que el compilador escribe para cada programa siguen ignorados por
la regla general.

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

## El sistema: lo que no puede ir por `externo`

`getenv` devuelve un `char*` que no es de nadie. En Tcode la memoria tiene
dueño, así que estas siete son internas del lenguaje y no una biblioteca: lo
que devuelven es un `str` de verdad, con su liberación automática.

| | | |
|---|---|---|
| `leer_linea() -> str !` | una línea de la entrada, sin el salto | falla al acabarse |
| `entrada_completa() -> str !` | toda la entrada | |
| `variable_entorno(v) -> str !` | del entorno | falla si no está |
| `ahora_ms() -> i64` | reloj de pared, ms desde 1970 | |
| `monotono_ms() -> i64` | reloj monótono, para durar | |
| `azar(tope) -> usize` | en `[0, tope)` | aborta con `tope == 0` |
| `sembrar(semilla)` | fija el azar, para poder repetir | |

En las cinco primeras hay una decisión que C tomó al revés:

**`leer_linea` crece lo que haga falta.** `fgets` corta y deja el resto para
la vuelta siguiente, que es peor que fallar porque parece que funciona. El
`bufio.Scanner` de Go deja de leer a los 64 KB y no lo dice. Aquí no hay
línea demasiado larga, y un `\r\n` de Windows tampoco es parte de la línea.

**El fin de la entrada es un fallo, no una cadena vacía.** Una línea en
blanco devuelve `""` y no falla; acabarse la entrada falla. Con `try`, o con
un `sino` que dé otra cosa, se distinguen. Con el atajo `sino nuevo("")` no:
las dos dejan el mismo texto vacío, así que un bucle que pare con
`largo(linea) == 0` trata igual un `Enter` y el fin de la entrada. Es la
diferencia entre el `input()` de Python (que levanta `EOFError`) y leer un
`""` sin saber cuál de las dos cosas pasó.

**`variable_entorno` distingue «no está» de «está vacía».** `getenv` no
puede: las dos dan algo falso. Go necesitó un `LookupEnv` aparte para esto y
Rust un `Result`; aquí sale del mismo `!` que ya tiene el lenguaje.

**Hay dos relojes, y el nombre dice cuál es cuál.** Medir una duración con el
de pared es el error clásico — salta con el NTP y con el cambio de hora. Y el
`clock()` de C mide tiempo de *CPU* aunque medio mundo lo use para lo otro.
`monotono_ms` usa `CLOCK_MONOTONIC` donde exista; donde no, cae al de pared,
que es lo único que hay en C17.

**`azar` no tiene el sesgo de `rand() % n`.** Si el tope no divide al rango,
los primeros valores saldrían más veces. Se descarta el sobrante, como en
Rust y en Go. El generador es xoshiro256++, no el `rand()` de C. Sin semilla
puesta, la elige el reloj; con `sembrar`, sale siempre lo mismo, que es lo
que hace falta para que una prueba sirva de algo.

Cada una entra en el C generado **sólo si el programa la usa**: quien no lee
la entrada no carga con el código de leerla.

Está en `ejemplos/sistema.t`.

## Lo que solo sabe `tcodec`

Estas formas entraron en el lenguaje cuando el compilador de Python ya había
quedado congelado, así que sólo las conoce `tcodec` — que hoy es el único
compilador (ver el README). Cada novedad de aquí es una forma más corta de
escribir algo que ya existía, y `tcodec` la traduce a esa forma antes de
escribir C, así que el C que sale es el mismo que con la forma larga. Nada de
esto añade reglas de propiedad nuevas: los préstamos, las vidas y los errores
son los de siempre.

### Vistas implícitas

Un `str` ya se prestaba solo al pasarlo donde una función pide `view`. Ahora
también donde se pide una vista fuera de una llamada:

```tcode
let v: view = s;                                    // let v: view = vista(s);
v = p.nombre;                                       // v = vista(p.nombre);
fn nombre(p: &Persona) -> view { return p.nombre; } // return vista(p.nombre);
```

Solo un `str` con nombre —una variable, un campo, un elemento—: uno sin
nombre, como `nuevo("x")`, moriría al acabar la sentencia, así que
`let v: view = nuevo("x");` sigue siendo un error. `let v = s;` sin tipo
escrito sigue moviendo `s`: la vista se pide escribiendo `view`.

### `==` y `!=` entre textos

```tcode
if nombre == "main" { ... }        // igual(nombre, "main")
if ext != vista(otra) { ... }      // !igual(ext, vista(otra))
```

Entre dos textos —`str` o `view`, en cualquier combinación— `==` compara el
contenido, como `igual`. Antes era un error con un `str` y, entre dos `view`,
comparaba en silencio los punteros: eso ya no pasa. Un texto con un número
sigue siendo un error: `no se pueden comparar `str` y `usize``.

### Llamada con punto

```tcode
xs.anadir(v);              // anadir(xs, v)
let n = s.largo();         // largo(s)
let d = x.suma(4).doble(); // doble(suma(x, 4))
```

`a.f(b, c)` es `f(a, b, c)`, para cualquier función —las internas, las de
`std` y las propias— y encadenado. Es solo sintaxis: `f` recibe `a` como
primer argumento con todo lo que eso implica. Si `f` lo modifica, `a` tiene
que ser `var`; si lo toma por valor, se mueve. No hay métodos ni búsqueda por
tipo: si `f` no existe, el error es el de una llamada a `f`. `Forma.Variante(x)`
de un `enum` sigue siendo lo que era.

### Rangos en `for`

```tcode
for i en 0..n { ... }            // i = 0, 1, ..., n - 1
for j en -2..fin { ... }         // con signo: los dos extremos, del mismo tipo
```

`a..b` va de `a` a `b` sin llegar a `b`, en el tipo entero de los extremos
(un número escrito toma el del otro, y sin nada que lo decida es `usize`).
Cada extremo se calcula **una vez**, antes de la primera vuelta y en su
orden: cambiar dentro del cuerpo lo que dio el final no alarga el bucle. Si
`a >= b` no da ninguna vuelta. El número es de solo lectura, como el
elemento de cualquier `for`, y `break` y `continue` son los de siempre. En C
es el `for` de toda la vida:

```c
size_t ss_tmp3 = n;
for (size_t ss_k1 = (size_t)0; ss_k1 < ss_tmp3; ss_k1++)
{
    SS_LANG_QUIZA_SIN_USAR size_t i = ss_k1;
    ...
}
```

Un rango solo existe en la cabecera de un `for`: no es un valor que se
guarde.

## Lo que Tcode 1.0 no tiene

Todo esto lo rechaza el compilador con un error que lo dice, en su línea.

**Tipos**
- Enums con parámetros de tipo (`enum Quiza<T>`); los structs sí los tienen.
- Restricciones propias: las de `T` son las seis de la gramática, sin
  traits ni interfaces que declarar.
- Claves de mapa que no sean `str`.
- Préstamos guardados: una `view`, un `&T` o un struct que presta no van en
  listas, arreglos, bloques, mapas ni enums. Un arreglo fijo no va en una
  lista.
- Un campo de struct de tipo `&T`/`&mut T`: no dice de quién presta ni cuánto
  vive, y en C quedaba el valor copiado sin dueño. Para que el struct preste
  de lo que le pongan, el campo es `view`; si el campo es suyo, no lleva `&`.

**Funciones**
- Sobrecarga: un nombre es una sola función.
- Pasar como valor una función que puede fallar, o una genérica.

**Control**
- Patrones sobre rangos en un `match`.
- `try` o `sino` en la condición de un `while`, y un motivo de `fail` que
  no sea una cadena escrita.
- Excepciones: un fallo es un valor, y se trata o se sube.

**Memoria y sistema**
- Punteros crudos, aritmética de punteros, `unsafe` y recolector de basura.
  Todo valor que sale de su bloque sin ser devuelto ni movido se libera
  solo, a cualquier hondura.
- Escritura incremental: `escribir_archivo` reemplaza el archivo entero.
- La puerta a C (`externo`) es estrecha a propósito: sin punteros, sin
  structs, sin varargs; una función de C no puede ser genérica ni fallar.

**Texto**
- Normalizar los nombres: `é` compuesta y `e` con acento combinado son dos
  nombres distintos.

Las plataformas que se comprueban están en
[`PLATAFORMAS.md`](PLATAFORMAS.md).
