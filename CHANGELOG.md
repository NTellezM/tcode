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
- `tests/fuzz.py` mira los errores de `cc` y `ld` en inglés (`LC_ALL=C`).

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
