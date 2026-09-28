# Cambios

Las versiones siguen `docs/COMPATIBILIDAD.md`. La de ahora está en `VERSION`.

## 0.9.0 — sin publicar

El camino a 1.0.

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

### Herramientas

- `make instalar` / `make desinstalar` (`PREFIJO`, `DESTDIR`).
- `make compiladores`: gcc y clang, sin avisos y con punto fijo.
- `make fuzz` y `tests/fuzz.py`: fuzzing del código real, con los hallazgos
  guardados como regresión.
- `make bench-comprobar`: medidas con límites de regresión.
- `docs/PLATAFORMAS.md` y `docs/COMPATIBILIDAD.md`.

## 0.1.0

La primera versión con número: `tcodec` autoalojado, construido desde su
semilla sin Python.
