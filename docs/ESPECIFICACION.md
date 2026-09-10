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

En v0 no hay espacios de nombres: lo que trae un `usar` entra al mismo saco.
Dos declaraciones con el mismo nombre son un error, y el mensaje dice en qué
archivo está la otra.

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
programa   := usar* (struct | funcion)*
usar       := "usar" cadena ";"
struct     := "struct" ident "{" (ident ":" tipo ",")* "}"
funcion    := "fn" ident "(" params? ")" ("->" tipo)? "!"? bloque
params     := param ("," param)*
param      := ident ":" ("mut" | "&")? tipo
tipo       := "str" | "view" | "usize" | "i64" | "bool"
            | "lista" "<" tipo ">"
            | IDENT_STRUCT | "[" tipo ";" entero "]"
bloque     := "{" sentencia* "}"

sentencia  := "let" ident ":" tipo "=" expr ";"
            | "var" ident ":" tipo "=" expr ";"
            | lugar "=" expr ";"
            | "if" expr bloque ("else" bloque)?
            | "while" expr bloque
            | "return" expr? ";"
            | "falla" cadena ";"
            | expr ";"

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
primario   := entero | cadena | "true" | "false" | ident
            | ident "(" args? ")" | "(" expr ")"
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

## Qué NO tiene v0

Es un v0 honesto. No hay: genéricos definidos por el usuario, espacios de
nombres, diccionarios, E/S incremental, aritmética de punteros ni recolector.
Todo valor que sale
de su bloque sin ser devuelto ni movido se libera automáticamente, a
cualquier hondura.
