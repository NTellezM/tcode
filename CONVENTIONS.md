# Convenciones para asistentes

## Regla de oro

Lo nuevo del lenguaje entra **solo** en el compilador de Tcode
(`ejemplos/compilador/` y `ejemplos/lexer/`). El compilador de Python
(`tcode/`) se borró: `tcodec` es el único (ver `docs/sin-oraculo.md`).
`tests/python_congelado.json` es la instantánea de aquel compilador y ya no
lo comprueba ninguna sección: es un registro.

## Tras tocar el compilador

- `make semilla` **solo cuando se pida explícitamente**. Actualiza
  `bootstrap/tcodec.c` y comprueba el punto fijo. No lo lances por iniciativa.
- Antes de proponer un cambio en `ejemplos/compilador/lib/generar.t`,
  ejecutar `make rapido` y `make semilla`. La comparación con Python que se
  hacía aquí se retiró con el oráculo (`docs/sin-oraculo.md`).

## Toda regla nueva

- Un par mínimo en `tests/reglas.py` (versión que rompe / versión que no).
- Si toca préstamos, un caso en `tests/prestamos.py`.
- Si añade sintaxis, una entrada en la suite de `tests/lenguaje/`.

## Estilo

- Los `.t` del repositorio están formateados. `make formato` antes de terminar.
- Los mensajes de error van en español, con archivo y línea.
- No inventes APIs nuevas de `std/` sin discutirlo antes.

## Lo que NO hagas sin pedirlo

- `make semilla`
- `git commit` / `git push`
- Cambios en `tests/python_congelado.json`
- Reformatear archivos que no toques por otro motivo
