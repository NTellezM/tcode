# safestr — especificación del lenguaje, v0

## Por qué existe

safestr nació como una librería de C. Auditándola encontramos cuatro fallos
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
no deberían ser expresables**. Ese es el único motivo por el que safestr
existe como lenguaje.

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

```safestr
var s: str = nuevo("hola");
let v: view = vista(s);
empujar(s, " mundo");   // error: `s` está prestado por `v`
```

Esto es exactamente el caso 2 de la tabla, y también el "CONTRATO DE VIDA
ÚTIL" que la librería en C documentaba y pedía respetar con criterio.

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

```safestr
fn primero(v: view) -> view { return rebanar(v, 0, 1); }   // ok
fn estatica()      -> view { return "constante"; }         // ok

fn colgante() -> view {
    var s: str = nuevo("hola");
    return vista(s);      // error: `s` muere al cerrar la funcion
}
```

Y el préstamo sigue vivo en quien llama, aunque haya pasado por medio una
función:

```safestr
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

```safestr
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

```safestr
struct Articulo { nombre: str, unidades: usize }

var inv: [Articulo; 4] = [ crear("tornillos", 420), ... ];
inv[2].unidades = inv[2].unidades + 50;
```

Cuatro `str` vivos ahí dentro, y ni un `ss_free` en el archivo. El compilador
emite `ss_drop_Articulo` y el bucle que lo aplica a los cuatro elementos.

**Todo índice se comprueba.** Salirse no lee memoria ajena: detiene el
programa diciendo dónde.

```
inventario.sfs:4: indice 3 fuera de rango (el arreglo tiene 3 elementos)
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
- **Structs recursivos.** Sin tamaño finito; da error.

## Gramática v0

```
programa   := (struct | funcion)*
struct     := "struct" ident "{" (ident ":" tipo ",")* "}"
funcion    := "fn" ident "(" params? ")" ("->" tipo)? bloque
params     := param ("," param)*
param      := ident ":" ("mut")? tipo
tipo       := "str" | "view" | "usize" | "i64" | "bool"
            | IDENT_STRUCT | "[" tipo ";" entero "]"
bloque     := "{" sentencia* "}"

sentencia  := "let" ident ":" tipo "=" expr ";"
            | "var" ident ":" tipo "=" expr ";"
            | lugar "=" expr ";"
            | "if" expr bloque ("else" bloque)?
            | "while" expr bloque
            | "return" expr? ";"
            | expr ";"

expr       := o
o          := y ("||" y)*
y          := igualdad ("&&" igualdad)*
igualdad   := comparacion (("==" | "!=") comparacion)*
comparacion:= suma (("<" | "<=" | ">" | ">=") suma)*
suma       := producto (("+" | "-" | "+?" | "-?") producto)*
producto   := unario (("*" | "/" | "%" | "*?") unario)*
unario     := ("!" | "-") unario | postfijo
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

## Qué NO tiene v0

Es un v0 honesto. No hay: genéricos, módulos, arreglos de tamaño variable,
manejo de errores, aritmética de punteros, ni recolector. Todo valor que sale
de su bloque sin ser devuelto ni movido se libera automáticamente, a
cualquier hondura.
