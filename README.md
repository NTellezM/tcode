# Tcode

Un lenguaje de sistemas pequeño que compila a C portable, donde las clases de
fallo de memoria más comunes de C **no son expresables**.

```tcode
fn saludo(nombre: view) -> str {
    var s: str = nuevo("Hola, ");
    empujar(s, nombre);
    empujar(s, "!");
    return s;            // el `ss_free` lo pone el compilador donde toca
}
```

```
$ python3 -m tcode ejemplos/hola.t && ./ejemplos/hola
Hola, mundo!
12 bytes
```

## De dónde sale

Tcode salió de auditar **safestr**, una librería de cadenas en C.
Auditándola encontramos cuatro fallos
de seguridad de memoria **en código escrito con cuidado poco común**:
invariantes documentadas, aliasing resuelto a mano, comprobaciones de
desbordamiento por todos lados. Aun así:

| Fallo en safestr (la librería de C) | Clase |
|---|---|
| `ss_reserve` con `n` enorme → bloque de 15 bytes con `capacity` de 2⁶⁴ | desbordamiento de entero → escritura fuera del heap |
| `ss_appendf(&s, "%s", ss_cstr(&s))` | use-after-free por aliasing a través de un `realloc` |
| `ss_setf(&s, "[%s]", ss_cstr(&s))` → `"[]"` | resultado silenciosamente incorrecto |
| `sv_to_long("-9223372036854775808")` | desbordamiento con signo (UB) |

La conclusión no fue "hay que escribir mejor C". Fue que esas cuatro clases
**no deberían ser expresables**. Eso es todo lo que este lenguaje intenta ser.

Hoy los cuatro son errores de compilación:

```
$ python3 -m tcode malo.t
error: malo.t:4: no se puede modificar `s`: esta prestada por `v`

1 error. No se genero nada.
```

## Las cuatro reglas

1. **Propiedad y préstamos.** Un `str` es dueño; un `view` toma prestado.
   Mientras viva un `view` derivado de un `str`, ese `str` no se puede mutar
   ni mover. Los préstamos terminan al cerrar el bloque, y **una vista no
   puede sobrevivir a lo que presta**: al cruzar un `return` el compilador
   infiere de dónde sale la memoria, sin anotaciones.
2. **Aritmética comprobada por defecto.** `+`, `-` y `*` abortan al
   desbordar, diciendo archivo y línea. Para envolver hay que escribirlo:
   `a *? b`.
3. **Sin conversiones implícitas.** `usize` e `i64` no se mezclan solos.
4. **Sin valores no inicializados.** `let` es inmutable, `var` mutable.
5. **Préstamos.** Pasar un valor lo mueve; `&T` lo presta para leer y
   `mut T` para modificar. Lo prestado no se puede mover, y dos préstamos de
   lo mismo sólo conviven si ninguno modifica.
6. **Los fallos no se pueden ignorar.** Una función que puede fallar lo dice
   con `!`; quien la llama elige entre `try` (que lo propaga) y `sino`
   (que da un valor). Olvidarse es un error de compilación, y un fallo
   libera lo que ya se había reservado.
7. **Un archivo es un módulo.** `usar "lib/texto.t";`, rutas relativas,
   carga única y detección de ciclos.
8. **Propiedad recursiva y límites comprobados.** Un `struct` posee lo que
   poseen sus campos; un arreglo, lo que poseen sus elementos, y la
   liberación se genera sola a cualquier hondura. Todo índice se comprueba:
   salirse detiene el programa en vez de leer memoria ajena.

La especificación completa está en [`docs/ESPECIFICACION.md`](docs/ESPECIFICACION.md).

## Cómo funciona

```
fuente .t → lexer → parser → comprobador → generador → C → cc → binario
```

El compilador está en Python, sin dependencias. Genera C legible que se
enlaza contra `runtime/safestr.c` — la librería que originó todo esto, que
pasó a ser el runtime del lenguaje. El C generado se puede leer, versionar y compilar en
cualquier sitio donde haya un compilador de C17.

| Archivo | Qué hace |
|---|---|
| `tcode/lexer.py` | texto → tokens |
| `tcode/parser.py` | tokens → árbol (descenso recursivo) |
| `tcode/modulos.py` | resuelve `usar`, carga única, detecta ciclos |
| `tcode/comprobador.py` | tipos, propiedad, préstamos, mutabilidad |
| `tcode/generador.py` | árbol → C, con `ss_free` y comprobaciones insertadas |
| `runtime/` | safestr, la librería de C original, ya corregida |

## Uso

```
python3 -m tcode programa.t              # compila a binario
python3 -m tcode programa.t --emitir-c   # deja el C y no invoca a cc
python3 -m tcode programa.t --solo-comprobar
```

## Estado

**v0, y lo digo en serio.** Funciona de punta a punta y la suite pasa, pero
falta casi todo lo que un lenguaje necesita para ser usable en producción.

Hay: funciones, `let`/`var`, `if`/`else`, `while`, `return`, aritmética
comprobada, `str`/`view`/`usize`/`i64`/`bool`, préstamos con ámbito léxico,
liberación automática, y ocho funciones internas sobre la librería de C.

Hay también: `struct`, arreglos de tamaño fijo con índices comprobados,
structs anidados, arreglos de structs, propiedad recursiva, préstamos de
structs (`&T` y `mut T`), módulos y fallos como valores.

No hay: genéricos, espacios de nombres, arreglos de tamaño variable, ni el
propio compilador escrito en Tcode. Tampoco: campos `view` dentro de un
struct (el muro real: exige la vida útil en el tipo), movimientos parciales
de un campo o elemento, ni devolver una vista de un parámetro prestado.

```
$ make check
74 casos, 0 fallas
```

Los 48 casos de rechazo comprueban que los programas malos no compilan; los
18 de aceptación corren bajo AddressSanitizer y UndefinedBehaviorSanitizer y
comparan la salida exacta; 4 comprueban que la aritmética y los índices
comprobados detienen el programa en vez de seguir con basura; y 5 arman un
programa de varios archivos en un directorio temporal para probar la carga de
módulos, los ciclos y los nombres repetidos.
