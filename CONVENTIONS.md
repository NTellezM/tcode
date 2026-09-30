# Convenciones para asistentes

## Regla de oro

Lo nuevo del lenguaje entra **solo** en `tcodec.t` y `lib/*.t`.
`tcode/` (Python) solo recibe arreglos de corrección, nunca características.
`tests/python_congelado.json` no se toca: la sección CONGELADO falla si cambia.

## Tras tocar el compilador

- `make semilla` **solo cuando se pida explícitamente**. Actualiza
  `bootstrap/tcodec.c` y comprueba el punto fijo. No lo lances por iniciativa.
- Antes de proponer un cambio en `lib/generar.t`, ejecutar:
  `python3 tests/test_lenguaje.py PROGRAMA CUERPOS EXPRESIONES`
  y anotar qué programas del repositorio dejan de coincidir con Python.

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
- Cambios en `tcode/` (Python)
- Cambios en `tests/python_congelado.json`
- Reformatear archivos que no toques por otro motivo
