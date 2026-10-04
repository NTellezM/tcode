# Plan: devolver las palabras robadas

## El criterio

No es «pasar todo a inglés». Es esto:

> El lenguaje tiene dos mitades, y las dos están bien donde están.
>
> - La **gramática** (`fn`, `if`, `for`, `let`, `return`) está en inglés: son
>   palabras cortas, estructurales, que el ojo salta como salta las llaves, y
>   que cualquier hispanohablante lee sin traducir. Además tienen la misma
>   forma que en C y en Rust.
> - El **vocabulario** (los nombres, el `std`) está en español: `es_blanco`,
>   `largo`, `imprimir`, `contador_palabras`. Eso es lo que hace que el código
>   se lea como una frase y no como una traducción.
>
> El problema no es la mezcla. El problema es que **seis palabras reservadas
> roban palabras comunes del español**: no puedes llamar `mapa` a un mapa ni
> `lista` a una lista. Eso es un impuesto que paga cada programa, para siempre.

Así que se cambian **sólo las que roban**, y se queda todo lo demás — incluido
lo que hace bello el código.

## 1. Lo que se cambia

### Las que roban una palabra que de verdad usas

| español | inglés | tcode | pokered | total |
|---|---|---:|---:|---:|
| `lista` | `list` | 3.414 | 294 | 3.708 |
| `mapa` | `map` | 1.142 | 225 | 1.367 |
| `usar` | `use` | 402 | 614 | 1.016 |
| `falla` | `fail` | 208 | 251 | 459 |
| | | | | **6.550** |

Las cuatro inglesas son términos técnicos que cualquier hispano lee de
corrido, y a cambio se recuperan cuatro palabras del idioma. `list` y `map`
son además las dos que más duelen: nombrar `lista` a una lista es lo más
natural del mundo.

### Las reservadas de antemano (gratis)

`soltar`, `extiende`, `protocolo`, `implementa` y `ancla` están reservadas
pero **no significan nada todavía** (la especificación lo dice: se guardan
«para poder añadir anclajes en 1.x sin romper programas después»). Sólo están
en la tabla del lexer: **renombrarlas no toca ni una línea de código**.

| español | inglés |
|---|---|
| `soltar` | `drop` |
| `extiende` | `extends` |
| `protocolo` | `protocol` |
| `implementa` | `implements` |
| `ancla` | `anchor` |

También roban palabras (`protocolo`, `soltar` son nombres plausibles), así que
entran en el mismo criterio — y salen gratis.

## 2. Lo que se queda

| palabra | tcode | pokered | por qué se queda |
|---|---:|---:|---|
| `en` | 3.519 | 1.383 | `for i en 0..largo(texto)` es lo que mejor se lee, y casi nadie llama `en` a una variable |
| `sino` | 614 | 185 | tampoco es nombre de nada: «lo que queda a la derecha de un sino» |
| `como` | 867 | 1.695 | **no está reservada** (es contextual): no roba nada |
| `externo` | 50 | 2 | es vocabulario —un concepto—, no pegamento |
| todo el `std` | — | — | `imprimir`, `largo`, `es_letra`… es el encanto y no choca con nada |

Con esto, el bucle más común del lenguaje queda intacto:

```tcodec
for i en 0..largo(texto) {
    if !es_blanco(byte(texto, i)) {
```

Y lo que cambia queda en sitios que **no se leen como prosa**: una anotación de
tipo (`xs: list<str>`), una directiva de cabecera (`use "std/texto"`).

## 3. El transbordo (por qué hay fases)

La cadena de construcción es:

```
bootstrap/tcodec.c  →  .cache/tcodec0  →  compila  ejemplos/compilador/tcodec.t  →  tcodec
   (C congelado)        (etapa 0)                    (la fuente)
```

El compilador congelado **sólo conoce las palabras viejas**. Si se renombra la
fuente de golpe, la etapa 0 no la sabe leer y no hay forma de arrancar. Por eso
el renombrado va en **tres fases**, y cada una deja el punto fijo cerrado.

### Fase A — el compilador entiende los dos idiomas (hecha)

Objetivo: aceptar las viejas **y** las nuevas.

Lo primero que salió al hacerlo es que este plan se quedaba corto: no eran «el
lexer y el analizador», sino **siete sitios en seis ficheros** los que comparan
contra esas palabras:

| fichero | qué compara |
|---|---|
| `ejemplos/lexer/lib/lexico.t` | `es_reservada`, la tabla |
| `ejemplos/lexer/lib/sintaxis.t` | `mapa`, `lista`, `falla` y `usar` ×5 |
| `ejemplos/compilador/lib/tipos.t` | `lista`, `mapa` |
| `ejemplos/compilador/tcodec.t` | `usar` ×2, el cargador de módulos |
| `ejemplos/compilador/tipar.t` | `usar` |
| `ejemplos/compilador/lib/formato.t` | `lista`, `mapa` |
| `ejemplos/lexer/lib/clase.t` | los nombres que salen en los mensajes |

Y el último es el que decide la dirección. `clase.t` da los nombres de los
errores (`Clase.Usar -> "usar"`, `Clase.Falla -> "falla"`), y hay textos como
el de `sintaxis.t` («\`falla\` no lleva paréntesis»). Esos nombres tienen que
decir lo que **escribe quien programa**. Canonizar hacia las nuevas, como decía
este plan, habría dejado al compilador diciendo «`use`» mientras el código de
todo el mundo dice `usar`.

Así que se canoniza **hacia las viejas**:

1. **Lexer** (`lexico.t`) — lo único que cambia de verdad:
   - `canonica` traduce la nueva a la de siempre (`list` → `lista`).
   - `es_reservada` canoniza antes de mirar, así valen las dos formas.
   - El token se emite canonizado… salvo con `comentarios` (el formateador),
     que guarda lo escrito para no traducir nada por su cuenta.
2. **Formateador** (`formato.t`): `es_generico` conoce las dos formas, porque
   ve la palabra tal como se escribió. Sin eso, `list<str>` salía formateado
   como `list < str >`.
3. **Lo demás no se toca**: el analizador, los tipos, el cargador y el tipado
   siguen comparando contra las palabras de siempre, y los mensajes también.

`make tcodec && make semilla`, y `make check` en verde.

**Lo que se gana**: el código de siempre sigue compilando igual, y ya se puede
escribir `list<str>`, `map<K,V>`, `use` y `fail` — y las cinco reservadas de
antemano con su nombre nuevo.

### Fase B — el barrido (hecha la parte del código)

**NO puede ser un `sed` a lo bruto.** `lista`, `mapa`, `usar` y `falla` son
palabras españolas corrientes y salen mucho en la prosa de los comentarios:

| palabra | este repo | en comentarios | pokered | en comentarios |
|---|---:|---:|---:|---:|
| `lista` | 3.414 | 196 | 294 | 37 |
| `mapa` | 1.142 | 117 | 225 | 170 |
| `usar` | 402 | 71 | 614 | 7 |
| `falla` | 208 | 27 | 251 | 15 |

Un `sed 's/\blista\b/list/g'` convertiría «la lista de espera» en «la list de
espera». La sustitución tiene que ser **consciente de los tokens**: sólo la
palabra que el lexer marca como `palabra`, nunca la que va dentro de un
comentario o de una cadena.

La herramienta es `tcodec --formatear --renombrar [--escribir]`: el formateador
de siempre más `nueva()` del lexer —la inversa de `canonica()`—, que en vez de
dejar la palabra como se escribió la cambia por su nombre nuevo. Como el
repositorio ya está en formato canónico, el diff es **sólo la palabra**: 76
ficheros, ni un espacio de más.

Barrido: `ejemplos/compilador/*.t` y `lib/*.t`, `ejemplos/lexer/lib/*.t`,
`std/*.t`, `tests/**/*.t` (los hallazgos del fuzzing incluidos), `programas/*.t`
y los ejemplos. Los `.mut_fuzz_*.t` **se borraron** (20 restos de las pruebas).

Lo que **no** se barre aquí, y por qué:

| qué | por qué |
|---|---|
| los fragmentos de `tests/lenguaje/*.py` | el mismo fichero lleva el programa de entrada **y la salida esperada**, y la salida esperada cita las palabras viejas hasta que el compilador cambie de idioma |
| `docs/ESPECIFICACION.md`, `docs/GUIA.md` y `docs/AUDITORIA.md` | `especificacion.py` comprueba que la especificación diga lo que hace el compilador: cambian juntos o el test falla |

Las gramáticas del editor sí se tocan, porque el editor tiene que entender las
dos mientras dure el transbordo: resaltan las dos formas y el completado ya
propone las nuevas.

Y hay un sitio que **no** se podía dejar para después aunque lo pareciera:
`tests/grafo.py` lleva su propia lista de palabras reservadas para distinguir
`palabra` de `ident`, y con el código ya renombrado dejó de reconocer los tipos.
El grafo salió **vacío** —de 94 flechas a 0— y `make check` ni se inmutó, porque
solo comprueba que el documento coincida con lo que dice la herramienta, no que
la herramienta siga viendo algo. Se arregló ahí mismo, aceptando las dos formas.
Es el fallo a buscar a mano en un cambio así: una herramienta que analiza el
código por su cuenta y se queda ciega sin decirlo.

`make tcodec && make semilla`, y `make check` en verde.

### Fase C — quitar las viejas (hecha)

Aquí se renombra **por dentro**, todo a la vez, con el código ya escrito en las
nuevas (que es lo que hace la fase B). Lo que salió, y que el plan no tenía
contado:

1. **Los siete sitios de la fase A** pasan a las nuevas: las comparaciones de
   `sintaxis.t`, `tipos.t`, `tcodec.t` y `tipar.t`, `es_generico`, y los nombres
   de los mensajes (`clase.t`).

2. **La representación interna del tipo** también hablaba en viejo: el
   analizador construía `lista<...>`/`mapa<...>` y `tipos.t`/`tipar.t` los
   comparaban por prefijo con `empieza(t, "lista<")`. Como los mensajes
   incrustan esa cadena, el usuario habría visto `lista<usize>` donde escribe
   `list<usize>`. Van los dos lados a la vez —el que la construye y el que la
   compara—, o el compilador no reconoce sus propios tipos.

3. **Los textos que nombran la palabra**: los que van entre backticks (`` `usar
   \"...\";` ``) y los que listan tipos (`se esperaba un tipo (..., list<tipo>,
   map<clave, valor>, ...)`). El prosa se queda: «la clave no esta en el mapa»
   sigue diciendo mapa, que es español, no la palabra clave.

4. **Lexer**: fuera `canonica` y `nueva`, fuera las viejas de `es_reservada`, y
   el token se emite tal cual se escribió. Fuera también el `--renombrar` del
   formateador, que sólo existía para el barrido.

5. **Los tests**, que fue lo más pesado: los fragmentos de `tests/lenguaje/*.py`
   van en tuplas `(nombre, programa, salida)` y en llamadas `Regla(...)`, y las
   herramientas (`generador_programas.py`, `reglas.py`) generan programas con
   las palabras dentro. Se renombró con `ast` —para no tocar ni los nombres ni
   el código Python del propio test— y quedó un detalle que hay que mirar a
   mano: `acepta.py` tiene una salida esperada que **es** `lista<` porque el
   programa rebana los seis primeros caracteres de `"lista<P.Nodo>"`.

6. **Los documentos** y las listas de las herramientas, que se quedan sólo con
   las nuevas para no arrastrar las viejas.

`make tcodec && make semilla`, y `make check` en verde.

**Lo que se gana**: `lista`, `mapa`, `usar` y `falla` vuelven a ser palabras
normales del idioma. `var lista: list<str> = [];` compila.

## 4. ¿Y `pokered-tcode`?

Usa el compilador por ruta (`TCODEC ?= ../tcode/tcodec`), así que:

| fase | ¿hay que tocar pokered? |
|---|---|
| **A** | **No.** Sigue compilando tal cual |
| **B** | **No.** Nada suyo cambia |
| **C** | **Sí**, o deja de compilar: ~1.400 sitios |

Y hay una tercera salida: **no hacer la fase C**. Si el lexer se queda
aceptando las dos, pokered no se toca nunca. El precio es que las palabras
viejas quedan aceptadas para siempre.

El renombrado de pokered es **puramente léxico**: el C generado sale idéntico y
las pruebas contra la ROM (las trazas, los `fixtures` byte a byte) tienen que
dar lo mismo. Aun así hay que **volver a correrlas**, que es la única garantía.

**Ojo con la coordinación**: pokered tiene trabajo sin commitear ahora mismo
(`lib/poke/audio.t`, el bloque D del audio). El renombrado hay que hacerlo
**cuando esa rama esté cerrada**, no en paralelo, o se pisan.

## 5. Verificación en cada fase

- `make check` — la suite entera (0 fallas) y las cifras del README al día.
- `make semilla` — el **punto fijo byte a byte**; es el seguro de que el
  renombrado no cambió el significado de nada.
- `make grafo` — los grafos y `docs/llamadas.md` al día.
- `tests/lenguaje/especificacion.py` comprueba que **lo que dice la
  especificación es lo que hace el compilador**: si se renombra el código y no
  la spec, esa prueba falla — y es justo lo que queremos que pase.

## 6. Riesgos

| riesgo | cómo se cubre |
|---|---|
| La etapa 0 no lee la fuente nueva | Las fases A/B/C: nunca se renombra antes de que acepte las dos |
| El `sed` destroza los comentarios | Barrido consciente de tokens (el lexer), no `sed` |
| El formateador «traduce» el código | En la fase A se guarda lo escrito cuando `comentarios` está puesto |
| La spec y el código se separan | `especificacion.py` lo detecta |
| Colisión con identificadores | `list`/`map`/`use`/`fail` no se usan hoy como nombre (comprobado) |
| Nombres que empiezan igual | El barrido va por palabra completa (`\blista\b`), no por prefijo |

## 7. Orden recomendado

1. Fase A, un commit. `make semilla` verde.
2. Fase B, un commit. `make check` + `make semilla`.
3. Fase C, un commit.
4. `pokered-tcode`, cuando la rama del audio esté cerrada.
