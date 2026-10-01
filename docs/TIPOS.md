# El modelo de tipos: de texto a estructura

Esto es el plan del último refactor interno grande. No cambia el lenguaje:
toca cómo el compilador representa los tipos, no lo que acepta ni lo que
emite. Es **posterior al 1.0**: la congelación existe para que el código se
quede quieto, y esto es lo contrario de quieto.

## Estado actual

Los tipos viven como `str` por todo el compilador: `Contexto.tipo_de` y
`Mundo` devuelven y guardan texto, y unas ~430 líneas reparten el mismo
conocimiento —`&mut ` es un préstamo, `lista<...>` es una lista, `Par<A, B>`
es una aplicación— en forma de `empieza_con`, `rebanar`, `partir_tipos` y
`entre_angulos` desparramados.

**La base ya está** en `lib/tipos.t`:

- `Forma` (9 casos): `Nombre`, `Lista`, `Bloque`, `Mapa`, `Rango`, `Arreglo`,
  `Presta`, `PrestaMut`, `Funcion`.
- `Tipo` (árbol): `forma`, `nombre`, `args: lista<Tipo>`, `cuantos`, `devuelve`.
- `leer_tipo(str) -> Tipo` y `escribir_tipo(Tipo) -> str`, inversas entre sí.
- `forma_de(str) -> Forma`, la pregunta barata que no reserva nada.

Es decir: no hay que inventar nada. Hay que **usarlo** en el resto del
compilador, que hoy sigue hablando en `str`.

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

## Las etapas (cada una, C idéntico)

La garantía de que no se rompe nada es la misma que ha funcionado todo el
camino: el compilador se rehace a sí mismo y su C sale **byte a byte igual**;
el punto fijo, el DDC y la suite entera tienen que quedar verdes antes de
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

1. **Rendimiento.** `leer_tipo` reserva (el árbol es `lista<Tipo>`); el camino
   caliente hoy usa `forma_de`, que no reserva. La regla: `forma_de` para
   decidir, `leer_tipo` solo cuando hace falta el árbol. Guardarraíl:
   `make bench-comprobar`, que falla si algo se pasa del límite.
2. **Los alias.** `sin_alias_tipo` expande sobre texto; hay que re-expresarlo
   sobre `Tipo`. Es el único sitio no mecánico.
3. **El oráculo de Python.** Sigue en `str`, congelado. No importa: el DDC
   compara el **C emitido**, no la representación interna. El modelo
   estructurado es solo de `tcodec`.
4. **No a medias.** Cada etapa termina con `make check`, `make compiladores`
   y el punto fijo verdes, y se commitea sola. Un compilador a medio migrar
   es peor que el de hoy.

## Criterio de entrada

Arrancar **después** de cortar el 1.0 (cuando la congelación pase y esté la
etiqueta). Es el primer trabajo del 1.1, no de la congelación.
