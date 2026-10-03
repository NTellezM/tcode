# Sin el oráculo: `tcodec`, solo

El plan para que `tcodec` deje de necesitar el compilador de Python
(`tcode/*.py`, unas 12.000 líneas) y sea el único compilador. Como el
refactor de tipos de `TIPOS.md`, es posterior al 1.0: toca cómo se verifica
el compilador, no lo que acepta.

## La garantía que se queda

Hoy «no rompí nada» se mira por dos lados:

1. **El punto fijo de auto-hospedaje** (`make semilla`): `tcodec` escribe su
   propio C (`--mostrar-c`), ese C se compila con `cc`, y el `tcodec`
   resultante vuelve a escribir el **mismo C byte a byte**. No toca Python:
   solo `tcodec` + `cc`.
2. **El DDC** (`make ddc`): el `tcodec` de ahora y el compilador de Python
   escriben el mismo C.

Al quitar el oráculo, la (2) desaparece y la (1) pasa a ser **la única**
garantía. Y es suficiente: cualquier cambio que rompa la compilación o
altere el C emitido rompe el punto fijo. La referencia deja de ser el
compilador de Python y pasa a ser la semilla `bootstrap/tcodec.c`.

## Las fases

Cada una termina con `make check` verde y se commitea sola.

1. **El punto fijo como única garantía.** Confirmar que `make semilla` corre
   sin Python (solo `tcodec` + `cc`) y dejarlo escrito como la red de
   seguridad que sustituye al DDC. *(este documento)*

2. **Portar la suite a solo-`tcodec`.** Las secciones de `test_lenguaje.py`
   que aceptan, rechazan y comparan salida se corren con `tcodec` a secas
   (compilar + ejecutar + comparar, o esperar el rechazo con el mensaje
   exacto), sin compilarlo dos veces.

3. **Decidir qué capas se van.** `ddc`, `cobertura`, `mutar` y las capas
   aisladas (`expresiones`, `firmas`, `cuerpos`) comparan contra Python: se
   eliminan o se reescriben sobre `tcodec`.

4. **Borrar `tcode/*.py`** y los objetivos del Makefile que lo usan.

5. **Ya sin oráculo**, retomar la representación interna de tipos con
   libertad —y solo entonces optimizar el camino caliente, si hay un
   objetivo medible—.

## Nota sobre el camino caliente

El camino caliente del comprobador ya es `str` + `forma_de` (no reserva para
decidir), que es la regla de `TIPOS.md`. Quitar el oráculo no acelera eso
directamente: acelera la verificación (no se corre todo dos veces) y
desbloquea cambios futuros de representación.
