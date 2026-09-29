# Plataformas

Tcode compila a C17 y necesita, para compilar un programa, un compilador de C
y un sistema POSIX. Lo que sigue es lo que se **comprueba**, no lo que
probablemente funcione.

## Soportadas

| Plataforma | Compiladores de C | Qué se comprueba | Dónde |
|---|---|---|---|
| Linux x86-64 (Ubuntu 24.04) | gcc 12, 13 y 14; clang 16, 17 y 18 | la semilla y `tcodec` sin un aviso con `-Wall -Wextra -Werror`; `tcodec` reproduce su C byte a byte; las secciones rápidas de la suite bajo ASan y UBSan | CI, `compiladores` |
| Linux x86-64 (Ubuntu 24.04) | gcc 13 | la suite entera, las propiedades, el fuzzing guardado y las medidas | CI, `completa` |
| macOS arm64 (macOS 14) | clang de Apple | sin avisos, punto fijo, y los ejemplos compilan y corren | CI, `macos` |

En local se comprueban igual gcc 12, gcc 13 y clang 18 con
`make compiladores COMPILADORES="gcc-12 gcc-13 clang-18"`.

Las filas de la CI están configuradas y todavía **no se han ejecutado**: la
tabla vale cuando la CI de la rama que las añade salga en verde.

## Qué hace falta

- **Para compilar `tcodec`**: un compilador de C17 (`make` construye desde la
  semilla, `bootstrap/tcodec.c`). No hace falta Python.
- **Para compilar un programa**: `tcodec`, `std/` y `runtime/` —`make
  instalar` los deja juntos— y un `cc` (o el que diga `CC`).
- **Para la suite**: Python 3.11 o más nuevo, sin dependencias. `make lint`
  pide `ruff` y `mypy`.

## Lo que se da por hecho

- **64 bits.** `usize` es `size_t`, y todo lo que se prueba es de 64 bits.
  Un sistema de 32 bits no se ha probado nunca.
- **POSIX.** `tcodec` usa `system`, `mkdtemp`, `mkstemp`, `realpath`,
  `rename` y `stat` para llamar a `cc` y escribir de una vez. En Linux sube
  el límite de pila y se vuelve a ejecutar (`/proc/self/exe`); en macOS
  compila con la pila de siempre, que basta para el propio compilador y todos
  los ejemplos.
- **UTF-8.** Los `.t` son UTF-8; los nombres no ASCII (UAX #31) llegan al C
  tal cual, y gcc desde la 10 y clang los aceptan.

## No soportadas

- **Windows.** No hay `system` con la misma semántica ni `mkdtemp`, y nadie
  lo ha intentado. WSL es Linux.
- **Otros sistemas POSIX** (FreeBSD, OpenBSD…): probablemente funcionan,
  pero `tcodec_raiz_instalada` no sabe encontrar su propio ejecutable en
  ellos; con `TCODE_RAIZ` debería bastar. Sin comprobar.
