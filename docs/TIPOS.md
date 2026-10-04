# El modelo de tipos: de texto a estructura

Esto es el plan del último refactor interno grande. No cambia el lenguaje:
toca cómo el compilador representa los tipos, no lo que acepta ni lo que
emite. Es **posterior al 1.0**: la congelación existe para que el código se
quede quieto, y esto es lo contrario de quieto.

> **Estado (2026-10-04).** El refactor ya está en marcha, y arrancó antes de
> cortar el 1.0: `Contexto` y `Mundo` guardan `Tipo` en varios campos (la
> Etapa 3 se cerró en `9066fe8`) y las consultas van migrando (`aef7436`). El
> estado de abajo es el de **antes** de empezar, y las menciones al oráculo
> de Python y al DDC también son de entonces: el oráculo se borró después
> (`docs/sin-oraculo.md`).

## Estado antes de empezar (2026-10-01)

Los tipos viven como `str` por todo el compilador: `Contexto.tipo_de` y
`Mundo` devuelven y guardan texto, y unas ~430 líneas reparten el mismo
conocimiento —`&mut ` es un préstamo, `list<...>` es una lista, `Par<A, B>`
es una aplicación— en forma de `empieza_con`, `rebanar`, `partir_tipos` y
`entre_angulos` desparramados.

**La base ya está** en `lib/tipos.t`:

- `Forma` (9 casos): `Nombre`, `Lista`, `Bloque`, `Mapa`, `Rango`, `Arreglo`,
  `Presta`, `PrestaMut`, `Funcion`.
- `Tipo` (árbol): `forma`, `nombre`, `args: list<Tipo>`, `cuantos`, `devuelve`.
- `leer_tipo(str) -> Tipo` y `escribir_tipo(Tipo) -> str`, inversas entre sí.
- `forma_de(str) -> Forma`, la pregunta barata que no reserva nada.

Es decir: no hay que inventar nada. Hay que **usarlo** en el resto del
compilador, que entonces seguía hablando en `str`.

## Alcance, medido

| archivo | sitios que tocan el texto del tipo |
|---|---:|
| `lib/comprobar.t` | 176 |
| `lib/generar.t` | 108 |
| `tcodec.t` | 84 |
| `lib/tipar.t` | 33 |
| `lib/programa.t` | 20 |
| `lib/tipos.t` (interno) | 12 |
| **total** | **~434** |

## El objetivo

`Tipo` es el tipo primario; `str` queda solo en la frontera: donde el código
fuente se lee (`leer_tipo`) y donde el C se escribe (`escribir_tipo`).
`Mundo` y `Contexto` guardan `Tipo`, no `str`. Ningún `empieza_con(t, "&")`
ni `rebanar` de un tipo fuera de `tipos.t`.

**El almacén del camino caliente es la excepción.** Las firmas de función
(`Param.tipo`, `Funcion.retorno`) y la tabla de símbolos del comprobador
(`Simbolo.tipo`) se quedan en `str`: se leen en cada llamada y en cada
referencia a variable, y `Tipo` no es copiable (lleva `list<Tipo>`), así que
guardarlo ahí obligaría a una copia profunda en cada lectura. Ahí la frontera
`str` es legítima por rendimiento: se decide con `forma_de` (que no reserva)
y se llama `leer_tipo` solo cuando hace falta el árbol, que es la regla del
riesgo 1. El registro global (`st_tipos`, `en_formas`, `anotados`) sí guarda
`Tipo`.

## Las etapas (cada una, C idéntico)

La garantía de que no se rompe nada es la misma que ha funcionado todo el
camino: el compilador se rehace a sí mismo y su C sale **byte a byte igual**;
el punto fijo y la suite entera tienen que quedar verdes antes de
seguir. Una etapa a la vez, nunca a medias.

### Etapa 1 — el módulo se vuelve la única fuente de verdad

Reescribir las consultas de `tipos.t` (`apuntado`, `partes`, `elemento`,
`valor_de_mapa`, `base`, `es_*`, …) para que **internamente** pasen por
`forma_de`/`leer_tipo` en vez de cortar el texto a mano. Las firmas siguen
devolviendo `str`/`bool`, así que ningún llamador se entera. Cierra el hueco
donde dos funciones parseaban distinto (de ahí salió el `const const T**`).

### Etapa 2 — las consultas devuelven estructura

`Contexto.tipo_de` devuelve `Tipo`; los ~430 sitios consumen `Tipo` (con
`match forma` en vez de `if empieza_con`). Es el grueso, y es mecánico: el
compilador mismo señala cada sitio que deja de compilar.

### Etapa 3 — lo guardado es estructura

`Mundo` y `Contexto` guardan `Tipo` en lugar de `str`. Desaparece el
`leer/escribir` por todo el medio; solo queda en la entrada y la salida.

## Los riesgos y su guardarraíl

1. **Rendimiento.** `leer_tipo` reserva (el árbol es `list<Tipo>`); el camino
   caliente hoy usa `forma_de`, que no reserva. La regla: `forma_de` para
   decidir, `leer_tipo` solo cuando hace falta el árbol. Guardarraíl:
   `make bench-comprobar`, que falla si algo se pasa del límite.
2. **Los alias.** `sin_alias_tipo` expande sobre texto; hay que re-expresarlo
   sobre `Tipo`. Es el único sitio no mecánico.
3. **El oráculo de Python.** Entonces seguía en `str`, congelado, y el DDC
   comparaba el **C emitido**, no la representación interna. Ya no existe
   (`docs/sin-oraculo.md`): hoy la garantía es el punto fijo.
4. **No a medias.** Cada etapa termina con `make check`, `make compiladores`
   y el punto fijo verdes, y se commitea sola. Un compilador a medio migrar
   es peor que el de hoy.

## Aparte: los nombres de tipo son globales

No es el refactor de arriba, pero cae en el mismo viaje y conviene tenerlo
escrito. Hoy los **tipos** (struct y enum, genéricos o no) tienen nombre
**global**: `tcodec` rechaza dos módulos que declaren
el mismo —«no admite un struct/enum repetido entre módulos»—. Las
**funciones**, en cambio, se resuelven por archivo y se manglean al chocar.

Lo destapó `tc-config` al juntar `std/json` y `std/toml`: los dos querían un
`Valor`, que es el nombre natural del tipo de un dato, y cada biblioteca
querrá el suyo. Rodeado renombrando el de TOML a `ValorToml`.

El arreglo:

1. **Cargador**: no rechazar; guardar cada tipo con su módulo y un nombre
   interno único (`modulo__Tipo`) **solo cuando choca**, como se hace ya con
   las funciones.
2. **Resolución**: `Modulo.Enum.Variante` y `Modulo.Struct { ... }` apuntan al
   tipo de ese módulo; la forma a secas, al propio o al único importado.
3. **C**: el tag del enum (`etiqueta`, hoy `SS_VALOR_TEXTO`) y el nombre del
   struct usan el nombre interno único, no el escrito.

Como el refactor de arriba, es post-1.0: toca los tipos, que están congelados.

## Criterio de entrada

Arrancar **después** de cortar el 1.0 (cuando la congelación pase y esté la
etiqueta). Es el primer trabajo del 1.1, no de la congelación.
