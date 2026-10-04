# Programas

Programas de uso real escritos en Tcode, cada uno comparado con algo que **no
es Tcode**: la herramienta del sistema que imita, o una implementación de
referencia en Python. La sección PROGRAMAS de la suite los compila con
AddressSanitizer y UndefinedBehaviorSanitizer y les pasa 40 entradas al azar
por programa, siempre las mismas.

| programa | hace | oráculo |
|---|---|---|
| `wc.t` | líneas, palabras y bytes | `wc` de GNU, `LC_ALL=C` |
| `base64.t` | codifica y decodifica base64 | `base64` de coreutils |
| `ordenar.t` | ordena líneas, `-r`, `-u` | `LC_ALL=C sort` |
| `buscar.t` | líneas que contienen un texto, `-n`, `-v`, `-i` | `LC_ALL=C grep -F` |
| `calc.t` | expresiones enteras en `i64` comprobado | evaluador en Python con los límites de `i64` |
| `vida.t` | el juego de la vida | implementación en Python |
| `json.t` | valida y reformatea JSON | el `json` de Python, ida y vuelta |

`tc-config.t` también vive aquí —junta `cli`, `toml` y `json`—, pero no entra
en la suite: no tiene un oráculo externo.

`calc` prueba la promesa central del lenguaje desde fuera: la cuenta que se
sale de `i64` o divide por cero para el programa justo en esa línea, después
de lo que ya imprimió, y el oráculo sabe cuándo porque evalúa en el mismo
orden.

Escribirlos encontró una cosa del programa y ninguna del compilador: el `wc`
de GNU sólo empieza una palabra con un carácter imprimible.

```
./tcodec programas/calc.t && printf '1 + 2 * 3\n' | ./programas/calc
```
