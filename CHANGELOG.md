# Cambios

Las versiones siguen `docs/COMPATIBILIDAD.md`. La de ahora está en `VERSION`.

## Sin publicar

### Corregido

- Una variable o un parámetro que se llama igual que una función a la que
  se llama donde la variable está a la vista daba C que no compilaba, en
  los dos compiladores: en C la variable tapaba a la función. Ahora la
  función se renombra en el C como si chocara con otro módulo. Solo en ese
  caso: ningún programa que ya compilaba cambia su C. Lo encontró la
  biblioteca gráfica del Tamagotchi.
- `tcodec` no liberaba un struct cuyo único campo con dueño era un enum
  (`struct Ficha { quien: Nombre }`), ni uno con un campo de otro módulo
  (`hoja: Q.Hoja`): perdía esa memoria. Python sí lo liberaba. Ahora
  `tcodec` mira cada campo con la misma regla que el propio struct, y el C
  de los dos compiladores coincide. Lo encontró ASan en el Tamagotchi.
- Un struct con un campo arreglo (`b: [i64; 2]`) daba C que no compilaba,
  en los dos compiladores: el envoltorio del arreglo salía después del
  struct que lo lleva. Ahora sale justo antes. Solo cambia el C de esos
  programas, que antes no compilaban.
- Un préstamo que ya se tiene —lo que da `obtener` u `obtener_mut`, lo que
  atrapa un `match`— no se podía pasar a una función que presta, en los dos
  compiladores: se comparaba `&N` con el `N` del parámetro. Ahora pasa tal
  cual; un `&T` hacia un parámetro `mut` sigue siendo error, con un mensaje
  que dice por qué (antes pedía `mut &mut N`).
- `mapa<str, [T; n]>` daba C que no compilaba, en los dos compiladores: el
  mapa guarda un puntero al envoltorio del arreglo, que se definía después.
  Ahora esos envoltorios llevan nombre y se declaran antes; el C de los
  demás programas no cambia.
- `tcodec` escribía dos veces el envoltorio de `[Q.T; n]` (con y sin el
  alias del módulo), y no sabía copiar un enum que lleva un tipo con dueño
  de otro módulo (`Con(H.Nombre)`). Python no aceptaba esa forma de enum, y
  tipaba como `usize` un `match` de números escritos donde se esperaba otro
  entero.
- Con un local que no se puede llamar y se llama como una función
  (`var partes: lista<str>` y `partes(x)` o `T.partes(x)`), `tcodec` tomaba
  el tipo del local para la llamada y no sabía escribir la declaración que
  la guardaba. Ahora busca el local por el nombre entero, como el
  generador, y si no se puede llamar sigue con la función.
- La pregunta «¿este tipo es dueño de memoria?» tenía siete respuestas en
  cuatro archivos de `tcodec`, y de ahí salió la fuga de los structs con un
  enum. Ahora hay una sola regla, `posee_en` en `lib/tipos.t`, que conoce
  structs, genéricas, enums y alias de módulo.
- Los tipos de `tcodec` se normalizan una sola vez, al leer: tras mirar que
  cada archivo pide lo que usa, el árbol pierde el alias de módulo en cada
  sitio donde guarda un tipo (`Q.Caja`, `lista<H.Nombre>`, `Q.Sobre.Con`), y
  las firmas que se recogen al leer ya se guardan sin él. Tres de los
  fallos de arriba venían de una capa que olvidaba quitarlo; desde aquí
  ninguna lo ve, y `tcodec.t` pasa de quince sitios que lo quitaban a uno.
  Las llamadas lo conservan: `Q.hecho` dice de qué módulo es la función.
- `tests/fuzz.py` mira los errores de `cc` y `ld` en inglés (`LC_ALL=C`).

### Añadido

- Cinco palabras reservadas de antemano: `protocolo`, `implementa`,
  `extiende`, `ancla` y `soltar`. Todavía no significan nada, pero un
  programa que las use como nombre ya no compila. Se reservan ahora para
  poder añadir anclajes en 1.x sin romper programas después. Solo en
  `tcodec`; el compilador de Python está congelado y no las conoce.

- Prestar un sitio: `let x: &T = l[i];` lee un elemento, un campo o una
  variable sin copiarlo, y `let x: &mut T = l[i];` deja modificarlo por
  `x`. Mientras `x` se use, la variable de la que sale queda prestada
  entera. Antes la única forma de leer un elemento con dueño era
  `copiar(...)` —una copia profunda—, y el mensaje de error lo decía; ahora
  sugiere el préstamo. Solo con tipos que tienen partes; con un escalar, el
  error de siempre. Igual en los dos compiladores.

### Cambiado

- `tcodec` tarda un 8 % menos en escribir su propio C (1,32 s a 1,22 s).
  Una comprobación sobre el C ya escrito recorría todas las líneas una vez
  por cada prefijo y por cada genérica, y era el 27 % del tiempo; ahora es
  una sola pasada. El propio compilador presta nodos y funciones en vez de
  copiarlos donde puede.

- Las funciones del programa salen `static` en el C, con
  `SS_LANG_QUIZA_SIN_USAR`. El programa es un solo archivo de C y nadie de
  fuera las llama; con enlace externo, gcc en `-O2` dejaba de integrar una
  función pequeña cuyo cuerpo crecía con las comprobaciones, y el caso
  `structs` del benchmark iba a 1.65x de C. Ahora va a 1.00x con el `-O2` de
  siempre. Cambia el C de todos los programas, igual en los dos
  compiladores; los archivos de C de un `externo` no se ven afectados.

### Añadido

- Sección FORMAS en la suite: cada forma de guardar un tipo dentro de otro
  —siete hojas, cinco envolturas, una o dos de hondo, en uno, dos o tres
  archivos—, 588 programas con los dos compiladores y bajo ASan. Encontró
  todo lo anterior.

## 1.0.0-rc1 — 2026-09-28, candidata local

La primera candidata a 1.0. Recoge todo lo que se trabajó como 0.9.0, que no
llegó a publicarse. Está etiquetada en local (`v1.0.0-rc1`); falta la CI en
otras máquinas antes de publicarla, y `docs/COMPATIBILIDAD.md` sigue siendo
una propuesta.

Antes de cerrarla: 1.000 programas de propiedades (27.605 comprobaciones) y
una hora de fuzzing (43.112 mutantes), sin fallos.

### Lenguaje

- Patrones alternativos con `|` en `match`, con capturas y guardas.
- Enums importados con alias en tipos, construcciones y patrones:
  `t.Estado.Listo`, `t.Resultado.Valor(x)`.
- Un `match` exhaustivo cuyos brazos salen cuenta como salida de la función.
- **Nombres de UAX #31**: `_`, letras ASCII y XID_Start / XID_Continue
  (Unicode 15.0). Antes `tcodec` aceptaba cualquier byte no ASCII y Python
  usaba `isalpha()`; `×`, `€` o un espacio de ancho cero ya no son nombres.
- **Los dígitos de un número son los ASCII**: `²` y `٣` no son números.
- **Un `.t` es UTF-8 válido**; si no, el error dice la línea.
- **Controles bidireccionales** (U+202A–U+202E, U+2066–U+2069) rechazados en
  todo el archivo ("Trojan Source").
- Un módulo que se usa no puede tener `fn main`; la ruta de un `usar` no
  puede llevar un byte cero ni terminar en `/`. Los tres son un error en la
  línea del `usar`.

### Especificación

- **Ya no es un borrador de v0**: `docs/ESPECIFICACION.md` es la de 1.0.
  Gramática completa sacada del parser, con un programa de muestra que usa
  cada producción; la parte léxica entera (comentarios, números, cadenas y
  escapes, palabras reservadas, símbolos); un índice de las 42 funciones
  internas; y *Lo que Tcode 1.0 no tiene*, cada cosa comprobada.
- Corregido lo que ya no era cierto: los mapas guardan cualquier valor que
  se pueda guardar salvo `view` y `&T`, y se borran; las clausuras existen;
  los mensajes citados son los de ahora.
- La sección ESPECIFICACION de la suite compila y corre la muestra, y
  exige que el índice nombre exactamente las internas de `tcodec`.

### Biblioteca

- `std/archivo`: lectura por partes con memoria acotada
  (`leer_parte_archivo`).
- `std/iterador`: recorridos de una pasada, plegado y transformación.
- Más operaciones en `std/texto`, `std/mapa` y `std/vector`.

### Corregido

- `s = s;` con un `str`, una lista o un struct era un **uso después de
  liberar** que el comprobador aceptaba. `p.s = p.s;` daba C que no
  compilaba, y `u = u;` C que clang rechaza.
- Sacar un campo marcaba su línea y no su nodo: otro `p.s` en la misma línea
  daba C que no compilaba.
- Un enum con una lista dentro (`Lista(lista<Json>)`) no declaraba esa lista.
- `tcodec` abortaba con un byte cero en la ruta de un `usar`, y Python se
  escapaba con una excepción; también con un archivo que no es UTF-8.
- Los fallos internos del generador salían sin archivo ni línea.
- El formateador separaba `&mut Par<A, B>` y `mut Vector<T>`, escribía
  `como ? u8` y cambiaba `1_000` por `1000`.
- `anadir` y `ordenar` por un `&mut lista<T>` de `obtener_mut` se
  rechazaban.
- `tcodec` no compilaba en macOS: `_XOPEN_SOURCE` escondía `mkdtemp`. Lo
  encontró la CI.
- `300 como u8` compilaba y paraba el programa al correr; es una cuenta de
  números escritos y ahora es un error de compilación, como `let x: u8 =
  256;`.
- Una lista declarada sólo dentro de un `for` o de un brazo de `match` no
  se declaraba en el C: Python escribía C que no compilaba y `tcodec` se
  negaba.

### El compilador de Python

- **Congelado de verdad.** Hasta aquí recibió lo mismo que `tcodec`; desde
  esta versión sólo recibe arreglos de corrección. Lo que sabe está guardado en
  `tests/python_congelado.json` y la sección CONGELADO falla si cambia. Lo
  nuevo del lenguaje va sólo a `tcodec` y se prueba con oráculos que no son
  Python. Se retira después de 1.0.

### Herramientas

- `make instalar` / `make desinstalar` (`PREFIJO`, `DESTDIR`).
- `make paquete` / `make probar-paquete`: el `.tar.gz` de una versión,
  reproducible, que se construye sin Python; `make version NUEVA=...`; el
  procedimiento en `docs/VERSIONES.md`.
- `make compiladores`: gcc y clang, sin avisos y con punto fijo.
- `make fuzz` y `tests/fuzz.py`: fuzzing del código real, con los hallazgos
  guardados como regresión.
- `make bench-comprobar`: medidas con límites de regresión.
- Sección REGLAS (`tests/reglas.py`): el oráculo de rechazo que no es un
  compilador. 44 reglas en pares mínimos —propiedad, préstamos, tipos,
  fallos, genéricas, clausuras, `como`, bloques, enums, structs— en siete
  contextos: 270 pares.
- `docs/PLATAFORMAS.md` y `docs/COMPATIBILIDAD.md`.
- `docs/AUDITORIA.md`: qué se promete, la base de confianza, dónde vive cada
  invariante, cómo se prueba, lo conservador y por dónde empezar.
- `make ddc` y `tests/ddc.py`: compilación doble diversa. La semilla y el
  compilador de Python, sin ella, construyen el mismo `tcodec`; corre en
  `make check`.
- La versión portable de la aritmética comprobada (sin
  `__builtin_*_overflow`) no la ejecutaba nada: P11 corre cada programa
  también con `-DSS_LANG_SIN_BUILTINS`.

## 0.1.0

La primera versión con número: `tcodec` autoalojado, construido desde su
semilla sin Python.
