# Guía para auditar Tcode

Para quien revise Tcode sin haberlo escrito. Dice qué promete el lenguaje,
de qué depende esa promesa, dónde está implementada cada parte, cómo se
prueba ya, qué se decidió ser conservador a propósito y por dónde empezaría
a buscar. Las referencias `archivo:línea` son de la rama `camino-1.0`.

## Qué se promete

Para todo programa que **`tcodec` acepta**, compilado con un compilador de
`docs/PLATAFORMAS.md`:

1. **No hay comportamiento indefinido de C.** Ni desbordamientos con signo,
   ni conversiones fuera de rango, ni índices fuera de límites, ni
   desplazamientos del ancho o más, ni aliasing roto.
2. **No hay uso de memoria liberada, doble liberación ni fugas.** Todo valor
   con dueño se libera exactamente una vez, por cualquier camino: `return`,
   `falla`, `try`, `sino`, `break`, `continue`, brazos de `match`.
3. **Lo que no se puede hacer seguro, para el programa** con archivo y línea
   (un índice fuera de rango, una cuenta que se desborda, un `como` que no
   cabe), y sale con un código distinto de cero. Nunca sigue con un valor
   inventado.
4. **Lo que se sabe al compilar, se dice al compilar**: una cuenta de
   números escritos que pararía el programa no compila.

Lo que **no** se promete: exclusividad de acceso (se puede leer un mapa
mientras existe un `&mut` suyo; lo que se impide es lo que mueve memoria bajo
un préstamo vivo), terminación, ni ausencia de fallos de lógica.

## De qué depende (la base de confianza)

| Pieza | Tamaño | Qué hay que creer | Cómo se comprueba |
|---|---:|---|---|
| El comprobador de `tcodec` | `lib/comprobar.t`, 6.100 líneas | que rechaza todo lo que viola las reglas | REGLAS, RECHAZO, P10, fuzzing; comparación con Python |
| El generador de `tcodec` | `lib/generar.t`, `lib/programa.t`, `tcodec.t`, 10.000 líneas | que el C hace lo que dice el programa y libera bien | ACEPTA, P2 y `programas/` bajo ASan/UBSan; comparación byte a byte con Python |
| El runtime de C | `runtime/`, 3.200 líneas | `safestr.c` y las cabeceras que el C generado incluye | se ejecuta en cada programa de la suite bajo ASan/UBSan |
| La semilla | `bootstrap/tcodec.c`, 6 MB | que no trae nada que no esté en `tcodec.t` | compilación doble diversa (`make ddc`), abajo |
| El compilador de C y libc | — | que respetan C17 | la matriz de `make compiladores` |

### La semilla: compilación doble diversa

`bootstrap/tcodec.c` es el C que `tcodec` escribe de sí mismo, y de él se
construye todo. Una semilla con algo escondido lo pasaría a cada compilador
que se construye con ella sin aparecer en ningún fuente ("Reflections on
Trusting Trust", Thompson 1984). `tests/ddc.py` hace la prueba de Wheeler:

- **A**: la semilla construye `tcodec`, y ese `tcodec` escribe el C de
  `tcodec.t`.
- **B**: el compilador de Python —otro programa, en otro lenguaje, que no
  usa la semilla— compila `tcodec.t` sin azúcar; `cc` lo convierte en un
  `tcodec`, y ese escribe el C de `tcodec.t`.

A y B dan el mismo C, byte a byte (6 MB). Corre en `make check` y en
`make ddc`. Una puerta escondida tendría que estar también, igual, en el
compilador de Python.

**Ojo para después de 1.0**: el compilador de Python se retira de la suite,
pero es el segundo camino de esta prueba. Tiene que quedarse ejecutable.

## Cada invariante, dónde vive y cómo se prueba

Las funciones son de `ejemplos/compilador/lib/`. «Python» es `tcode/`, el
compilador congelado; su versión de cada cosa es el mismo algoritmo, y la
suite compara las dos.

### 1. Propiedad y movimientos

Un valor con dueño tiene uno solo. Pasarlo por valor, devolverlo o
asignarlo lo mueve; usarlo después es un error.

- **Dónde**: `comprobar.t:1022` `mover`, `:969` `a_medio_mover` (un struct
  del que se sacó un campo), `:1115` `mutar`, `:3321` `sacar_campo`. Los
  caminos que se excluyen (`if`, brazos de `match`) se llevan con
  `:1162` `foto` y `restaurar_foto`.
- **En el C**: lo que se mueve sólo por algunos caminos lleva una bandera en
  ejecución (`ss_vivo_x`): `generar.t:3357` `lleva_bandera`,
  `:3731` `apagar_las_de`, `:2704` `movidas_en`.
- **Se prueba con**: REGLAS (usar lo movido, mover en un bucle, lo que se
  llevó una clausura), ACEPTA bajo ASan, P2, y la capa PROPIEDAD, que compara
  el destino de cada una de las 6.300 variables del repositorio con Python.

### 2. Préstamos y vidas

`&T` lee; `mut T` y `&mut T` modifican. Una vista vive hasta su último uso,
y no sobrevive a su dueño ni a nada que pueda mover su memoria.

- **Dónde**: `comprobar.t:5095` `prestamos_vivos`, `:5072` `vive_despues`
  (el último uso), `:1349` `procedencia_de` y `:1802` `prestados_por` (de
  quién presta una vista, también a través de funciones, `if`, `match`,
  genéricas y structs que prestan), `:1877` `apuntar` («vive más que»).
- **Se prueba con**: P10 (una vista contra cada forma de invalidar a su
  dueño y cada forma de transportarla), REGLAS (modificar lo prestado,
  prestar dos veces, vistas que viven más, redimensionar lo prestado).
- **Mirar**: la tabla de *Lo que encontró una revisión* del README. Los seis
  agujeros de memoria que se encontraron estaban aquí, en formas de
  *transportar* una vista, no en la regla.

### 3. Liberaciones

Al cerrar un bloque se libera lo que sigue siendo de ese bloque, a cualquier
hondura, en orden inverso de declaración; en cada salida temprana, lo de
todos los bloques que se abandonan.

- **Dónde**: `generar.t:3363` `cerrar_bloque`, `:3483` `liberar_todo`,
  `:3527` `liberar_uno`, `:3580` `liberacion` (cómo se libera cada tipo:
  `str`, listas, mapas, structs, enums, bloques, clausuras).
- **Se prueba con**: ASan con detección de fugas en ACEPTA, P2, P10,
  `programas/` y `tests/fuzz.py` (que compila y corre los mutantes que se
  aceptan).

### 4. Temporales

Lo que una expresión crea y nadie guarda se libera al acabar la sentencia.

- **Dónde**: `generar.t:3300` `nuevo_temporal`, `:3392` `reclamar`.
- **Mirar**: temporales dentro de condiciones de `while`, de guardas de
  `match` y de argumentos que fallan a medias (`f(g(), try h())`).

### 5. Orden de evaluación

De izquierda a derecha, y cada subexpresión una vez. El C generado lo hace
explícito con temporales: no depende del orden que elija el compilador de C.

- **Dónde**: `generar.t` alrededor de `:1534`, `:3902` y `:4114`; índices y
  operandos con efectos se guardan en temporales antes de usarse.
- **Se prueba con**: P11 (un oráculo aritmético en Python evalúa en el mismo
  orden), `programas/calc.t` (la cuenta que se sale para en su sitio exacto).

### 6. Aritmética y conversiones

`+`, `-`, `*` comprueban; `/` y `%` comprueban el divisor y `MIN / -1`;
`<<` y `>>` el ancho; `como` que el valor quepa; los decimales, que no haya
conversión indefinida (NaN, infinitos, bordes redondeados).

- **Dónde**: en el C, `runtime/cabecera.inc:98` en adelante
  (`SS_LANG_DESB_*`); al compilar, `comprobar.t:2840` `valor_escrito` (las
  cuentas de números escritos) y `comprobar_conversion`.
- **Se prueba con**: P11, ABORTA, REGLAS, `programas/calc.t`.
- **Las dos versiones**: con `__builtin_*_overflow` si el compilador los
  tiene, y una fórmula portable que comprueba antes de operar si no. gcc y
  clang siempre tienen los builtins, así que P11 corre cada programa dos
  veces, la segunda con `-DSS_LANG_SIN_BUILTINS`, que fuerza la portable: la
  salida y las paradas tienen que ser las mismas.

### 7. Índices, rebanadas y bloques

Todo acceso por índice se comprueba (`runtime/cabecera.inc:429`
`ss_lang_indice_`); `rebanar` comprueba sus límites. Un bloque recién
reservado está a ceros, y todo tipo a ceros es un valor válido: no hay
memoria sin inicializar.

- **Dónde**: `generar.t:1247` `indice_c`; `intercambiar` y `redimensionar`
  en `comprobar.t` (reserva el sitio mientras calcula el reemplazo; fija la
  dirección y rechaza préstamos vivos).

### 8. El borde con C

`externo` sólo deja pasar tipos que significan lo mismo a los dos lados. Un
`str` entra como `const char*`; si lleva un cero en medio, el programa para.
`cadena_c` copia lo que devuelve C.

- **Mirar**: es el único sitio donde el programa confía en código que Tcode
  no comprueba. La promesa acaba en el borde.

### 9. El texto del programa

UTF-8 estricto, sin controles bidireccionales, nombres de UAX #31: los dos
lexers (`ejemplos/lexer/lib/lexico.t`, `tcode/lexer.py`) con las mismas
tablas (`tests/generar_xid.py`).

## Cómo se prueba, de un vistazo

| Sección | Qué juzga | Oráculo |
|---|---|---|
| ACEPTA, EJEMPLOS | programas escritos a mano compilan y corren limpios | ASan/UBSan, salida esperada |
| RECHAZO | programas que no deben compilar, con su mensaje | escrito a mano |
| REGLAS | cada regla, en pares mínimos y siete contextos | la construcción del par |
| P1–P13 (`tests/test_propiedades.py`) | programas generados al azar | ASan/UBSan, oráculo aritmético, Python |
| PROGRAMAS | seis programas reales | `wc`, `base64`, `sort`, `grep`, Python |
| PROGRAMA, CUERPOS, TIPAR, PROPIEDAD… | cada capa de `tcodec` contra la de Python | Python |
| `tests/fuzz.py` | mutantes del código real | no revienta; lo que acepta corre limpio |
| DDC | la semilla | Python, por otro camino |
| ESPECIFICACION, CONGELADO | la documentación y el oráculo | el código |

## Decisiones conservadoras (a propósito)

Rechazan programas que serían seguros, a cambio de reglas que se pueden
comprobar sin anotar vidas:

- La vida del **dueño** es su bloque: una vista a un dueño de un bloque de
  dentro no puede guardarse fuera aunque no se use después.
- No se puede **mover** algo de fuera dentro de un bucle, ni sacar un campo
  dentro de un `if`, un `match` o un bucle.
- No se **saca** un elemento de una lista o un bloque: se `intercambia` o se
  `copia`.
- **No se guardan préstamos** en listas, arreglos, bloques, mapas ni enums.
  Un campo de struct tampoco guarda un `&T`: si el struct presta de lo que le
  pongan, el campo es `view`.
- Las **clausuras capturan por valor**.
- Una función que **puede fallar** o una **genérica** no se pasan como valor.

## Límites conocidos

En un solo sitio; cada uno se explica donde se enlaza.

- Lo que el lenguaje no tiene: [Lo que Tcode 1.0 no
  tiene](ESPECIFICACION.md#lo-que-tcode-10-no-tiene).
- Dónde se comprueba que funciona: [PLATAFORMAS.md](PLATAFORMAS.md). Sólo
  64 bits; sin Windows.
- Los nombres no se normalizan (NFC).
- El compilador de Python, que es el segundo camino de DDC, no conoce el
  azúcar de `tcodec`: la prueba necesita la copia sin azúcar.
- **Una genérica cuyo tipo de retorno es el tipo del parámetro no se puede
  usar con `T = view`.** El comprobador no puede saber que `f(x)` devuelve
  una vista que sale de un parámetro, así que rechaza `aplica<T, F>(x: T,
  f: F) -> T` cuando `T = view`. Afecta a cualquier forma con ese perfil, y
  por eso el caso «clausura genérica» de la [pregunta abierta
  1](#preguntas-abiertas-por-dónde-empezaría) no está en P10.

## Preguntas abiertas: por dónde empezaría

1. **Formas de transportar un préstamo** que REGLAS y P10 no generan: una
   vista dentro del valor de un `if` dentro de un argumento de una clausura
   genérica, por ejemplo. La historia dice que los agujeros están en la
   combinación, no en la regla.
2. **Banderas de movimiento** en construcciones anidadas: un `match` con
   guardas dentro de un bucle con `continue`, donde un brazo mueve.
3. **`obtener_mut` y el rehash**: se rechaza `poner` mientras vive el
   préstamo; ¿hay otro camino que haga crecer la tabla?
4. **`runtime/safestr.c`**: es C escrito a mano, el origen del proyecto, y
   cada programa lo enlaza. Desde el 2026-10-01 tiene su fuzzing con
   libFuzzer (`make fuzz-safestr`, tambien en la CI nocturna): la entrada se
   lee como un guion de operaciones sobre `SafeString` y comprueba los
   invariantes de `safestr.h` bajo ASan+UBSan.
5. **Los fallos que compartían los dos compiladores** (ver `CHANGELOG.md`,
   1.0.0-rc1, *Corregido*): la comparación con Python no puede ver un error de
   diseño que está en los dos.

## Cómo reproducir

```
make                  # tcodec desde la semilla
make check            # la suite entera, DDC incluido
make ddc              # sólo la compilación doble diversa
make fuzz FUZZ_SEGUNDOS=3600
TCODE_PROGRAMAS=1000 make propiedades
make compiladores COMPILADORES="gcc-12 gcc-13 clang-18"
make cobertura        # que caminos del oraculo de Python no se pisan
make mutar            # rompe una regla en los dos compiladores: tiene que notarse
./tcodec programa.t --explicar   # lo que el compilador infirió de cada valor
./tcodec programa.t --mostrar-c  # el C, con #line apuntando al .t
```
