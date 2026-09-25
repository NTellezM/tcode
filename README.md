# Tcode

Un lenguaje de sistemas pequeño que compila a C portable, donde las clases de
fallo de memoria más comunes de C **no son expresables**.

```tcode
fn main() {
    let saludo = nuevo("hola, ");
    empujar(saludo, "mundo");
    imprimir(saludo);            // se libera sola al cerrar el bloque
}
```

Ahí hay propiedad, un préstamo y una liberación, y no se menciona ninguna: el
compilador las comprueba, tú no las escribes.

```tcode
fn saludo(nombre: view) -> str {
    var s: str = nuevo("Hola, ");
    empujar(s, nombre);
    empujar(s, "!");
    return s;            // el `ss_free` lo pone el compilador donde toca
}
```

```
$ python3 -m tcode ejemplos/hola.t && ./ejemplos/hola
Hola, mundo!
12 bytes
```

## De dónde sale

Tcode salió de auditar **safestr**, una librería de cadenas en C.
Auditándola encontramos cuatro fallos
de seguridad de memoria **en código escrito con cuidado poco común**:
invariantes documentadas, aliasing resuelto a mano, comprobaciones de
desbordamiento por todos lados. Aun así:

| Fallo en safestr (la librería de C) | Clase |
|---|---|
| `ss_reserve` con `n` enorme → bloque de 15 bytes con `capacity` de 2⁶⁴ | desbordamiento de entero → escritura fuera del heap |
| `ss_appendf(&s, "%s", ss_cstr(&s))` | use-after-free por aliasing a través de un `realloc` |
| `ss_setf(&s, "[%s]", ss_cstr(&s))` → `"[]"` | resultado silenciosamente incorrecto |
| `sv_to_long("-9223372036854775808")` | desbordamiento con signo (UB) |

La conclusión no fue "hay que escribir mejor C". Fue que esas cuatro clases
**no deberían ser expresables**. Eso es todo lo que este lenguaje intenta ser.

Hoy los cuatro son errores de compilación:

```
$ python3 -m tcode malo.t
error: malo.t:4: no se puede modificar `s`: esta prestada por `v`

1 error. No se genero nada.
```

## Las reglas

1. **Propiedad y préstamos.** Un `str` es dueño; un `view` toma prestado.
   Mientras viva un `view` derivado de un `str`, ese `str` no se puede mutar
   ni mover. Los préstamos terminan al cerrar el bloque, y **una vista no
   puede sobrevivir a lo que presta**: al cruzar un `return` el compilador
   infiere de dónde sale la memoria, sin anotaciones.
2. **Aritmética comprobada por defecto.** `+`, `-` y `*` abortan al
   desbordar, diciendo archivo y línea. Para envolver hay que escribirlo:
   `a *? b`.
3. **Sin conversiones implícitas.** `usize` e `i64` no se mezclan solos.
4. **Sin valores no inicializados.** `let` es inmutable, `var` mutable.
5. **Préstamos.** Pasar un valor lo mueve; `&T` lo presta para leer y
   `mut T` para modificar. Lo prestado no se puede mover, y dos préstamos de
   lo mismo sólo conviven si ninguno modifica.
6. **Los fallos no se pueden ignorar.** Una función que puede fallar lo dice
   con `!`; quien la llama elige entre `try` (que lo propaga) y `sino`
   (que da un valor). Olvidarse es un error de compilación, y un fallo
   libera lo que ya se había reservado.
7. **Un archivo es un módulo.** `usar "lib/texto.t";`, rutas relativas,
   carga única y detección de ciclos.
8. **Recorrer no invalida ni copia.** `for x en xs` y `for k, v en m` prestan
   la colección mientras dura y prestan cada elemento: modificarla por dentro
   es un error de compilación, no una corrupción en tiempo de ejecución, y
   recorrer un mapa no clona ni una clave.
9. **Propiedad recursiva y límites comprobados.** Un `struct` posee lo que
   poseen sus campos; un arreglo o `lista<T>`, lo que poseen sus elementos, y la
   liberación se genera sola a cualquier hondura. Todo índice se comprueba:
   salirse detiene el programa en vez de leer memoria ajena.

## Programas que consumen datos

Tcode ya puede leer entrada externa y no necesita conocer de antemano cuántos
elementos va a guardar:

```tcode
fn main() -> usize ! {
    let datos: str = try leer_archivo("entrada.txt");
    var saltos: lista<usize> = [];
    var i: usize = 0;
    while i < largo(vista(datos)) {
        if byte(vista(datos), i) == 10 { anadir(saltos, i); }
        i = i + 1;
    }
    imprimir(largo(saltos));
    return 0;
}
```

`lista<T>` crece de forma amortizada, comprueba cada índice y posee tanto su
buffer como los elementos que tengan memoria propia. `leer_archivo` es
falible: no se puede ignorar un error de apertura o lectura. `texto(x)`
convierte enteros y booleanos a `str`, y `byte(texto, i)` permite hacer
procesamiento binario sin introducir un tipo carácter implícito.

[`ejemplos/contar.t`](ejemplos/contar.t) es una utilidad completa que lee este
README y calcula líneas, palabras y bytes. Es deliberadamente pequeña, pero a
diferencia de los ejemplos de validación consume un archivo real cuyo tamaño y
contenido no controla el programa.

La especificación completa está en [`docs/ESPECIFICACION.md`](docs/ESPECIFICACION.md).

## Cómo funciona

```
fuente .t → lexer → parser → comprobador → generador → C → cc → binario
```

El compilador está en Python, sin dependencias. Genera C legible que se
enlaza contra `runtime/safestr.c` — la librería que originó todo esto, que
pasó a ser el runtime del lenguaje. El C generado se puede leer, versionar y compilar en
cualquier sitio donde haya un compilador de C17.

| Archivo | Qué hace |
|---|---|
| `tcode/lexer.py` | texto → tokens |
| `tcode/parser.py` | tokens → árbol (descenso recursivo) |
| `tcode/modulos.py` | resuelve `usar`, carga única, detecta ciclos |
| `tcode/comprobador.py` | tipos, propiedad, préstamos, mutabilidad |
| `tcode/generador.py` | árbol → C, con `ss_free` y comprobaciones insertadas |
| `tcode/explicar.py` | el modelo del comprobador, hecho legible |
| `tcode/nombres_c.py` | los nombres que en C ya son otra cosa (`log`, `EOF`) |
| `std/` | la biblioteca estándar, escrita en Tcode: 12 módulos, 941 líneas |
| `runtime/` | safestr, la librería de C original, ya corregida |

## El lexer y el parser de Tcode, escritos en Tcode

`ejemplos/lexer/lib/lexico.t` hace el análisis léxico del propio lenguaje:
comentarios, cadenas normales e interpoladas, números, identificadores,
palabras reservadas y símbolos de uno y dos caracteres.

Sobre los 49 `.t` del repositorio —incluido el suyo propio— produce
**163.887 tokens idénticos** a los del lexer del compilador, uno a uno. Eso
está en la suite, así que si alguna vez deja de coincidir, se sabe. Y ha
pasado: al reescribir `ejemplos/texto.t` con cadenas anidadas dentro de una
interpolación, el de Tcode dio siete tokens de más y la suite lo señaló al
instante.

```
$ ./ejemplos/lexer/lexer ejemplos/lexer/lib/lexico.t --contar
ejemplos/lexer/lib/lexico.t: 1400 tokens
  cadena  40   entero  125   fin  1
  ident  347   palabra  159  simbolo  728
```

Es el primer programa grande del lenguaje y su primera prueba de fuego: usa
`lista<Token>` con campos dueños, `mapa<str, usize>` para las palabras
reservadas, `for` con `break` y `continue`, fallos con `try`, cadenas
interpoladas para los mensajes, y lectura de archivos con argumentos. Corre
limpio bajo ASan y UBSan, y ante una entrada rota —una cadena sin cerrar, un
archivo binario— falla diciendo qué pasa, sin reventar ni filtrar.

`ejemplos/lexer/lib/sintaxis.t` son 1.624 líneas más: descenso recursivo con la
precedencia completa, sentencias, declaraciones y un árbol que se construye
de abajo arriba. Acepta y rechaza **exactamente** los mismos 49 archivos que
el parser del compilador, y sobre ellos produce 82.349 nodos:

```
$ ./ejemplos/lexer/parser ejemplos/lexer/parser.t --callado
ejemplos/lexer/parser.t: 87 nodos, hondura 10
```

Y dos capas más del comprobador, en `ejemplos/compilador/`:

- `lib/tipos.t` responde las dos preguntas de las que cuelga todo —¿este tipo
  es dueño de memoria?, ¿se puede guardar un valor suyo?—: **49 archivos, 367
  tipos**, las mismas respuestas que el comprobador de Python.
- `lib/tipar.t` dice **de qué tipo es cada variable de cada función**, con
  llamadas, campos, índices, préstamos y genéricas instanciadas: **44
  archivos, 4.797 variables**, los mismos tipos.
- `lib/propiedad.t` dice **qué le pasa a cada valor con dueño** —se presta,
  se entrega en la línea N, se mueve en la línea N, o se libera al cerrar su
  bloque—, que es lo único que de verdad separa a Tcode de C: **44 archivos,
  4.797 variables**, el mismo destino, sin ningún archivo pendiente.
- `lib/generar.t` es **el generador**: cómo se llama cada tipo en C, cómo
  queda la firma de cada función —**44 archivos, 629 firmas**— y el C de cada
  expresión que se devuelve: **1.441 de 1.667 expresiones, carácter por
  carácter**, las mismas que emite el generador de Python. Lo que aún no
  cubre sale marcado y no se compara; la suite exige un mínimo en vez de
  hacer como que están todas. Y **la función entera** —firma, cuerpo, y los
  `ss_free` puestos solos donde tocan—: **714 funciones idénticas**, línea por
  línea, normalizando sólo los números de temporal.

Las dos se comparan contra el comprobador de Python en cada ejecución de la
suite, sobre el código real del repositorio.

## Tcode se compila a sí mismo

`ejemplos/compilador/tcodec.t` junta todo lo anterior y escribe **el archivo
C entero** de un programa: cabecera, structs, listas y mapas con sus
funciones, tipos resultado, liberadores, copiadores, las copias de cada
genérica, los ayudantes del sistema, la aritmética que hace falta, los
prototipos y todas las funciones. Son **18.114 líneas de Tcode** (lexer,
parser, tipado, comprobador, generador, formateador y el programa) y el resultado se compara byte a
byte con el del generador de Python: **los 25 programas del repositorio, idénticos**,
entre ellos el lexer, el parser y el propio `tcodec`.

Y hace el último paso él solo: llama al compilador de C, enlaza lo que
piden los `externo` y deja el binario, con las mismas opciones y las mismas
salvaguardas que `tcode` —la salida nunca es el fuente, y un fallo del
compilador de C deja el binario anterior como estaba—:

```
$ export TCODE_RAIZ=.
$ ./tcodec programa.t                 # compila a binario
$ ./tcodec programa.t -o otro -O3
$ ./tcodec programa.t --emitir-c      # deja programa.c
$ ./tcodec programa.t --mostrar-c     # el C por la salida
$ ./tcodec programa.t --solo-comprobar
```

Y el punto fijo, sin Python más que para la primera etapa:

```
$ python3 -m tcode ejemplos/compilador/tcodec.t                        # etapa 1
$ ./ejemplos/compilador/tcodec ejemplos/compilador/tcodec.t -o etapa2  # sin Python
$ ./ejemplos/compilador/tcodec ejemplos/compilador/tcodec.t --mostrar-c > etapa1.c
$ ./etapa2 ejemplos/compilador/tcodec.t --mostrar-c | cmp - etapa1.c && echo igual
igual
```

El `tcodec` construido por sí mismo vuelve a escribir exactamente los mismos
bytes (4,72 MB), y el construido desde su propio C también, bajo
AddressSanitizer y UBSan; la suite comprueba las dos cosas en cada ejecución.
A partir de ahí el compilador ya no necesita a Python para existir, que es el
paso que dieron Go en la 1.5 y Rust con su primer `rustc` escrito en Rust. Lo
que necesita del sistema y Tcode no trae —ejecutar el compilador de C, un
temporal, sustituir un archivo de una vez, subir la pila— son 173 líneas de C en
`lib/sistema_tcodec.c`, que `tcodec` pide con un `externo` como cualquier
otro programa.

### Y también sabe decir que no

Un compilador no es sólo lo que escribe: es lo que se niega a escribir.
`lib/comprobar.t` son 5.272 líneas con las reglas del comprobador de Python
—tipos, propiedad, préstamos, mutabilidad, fallos, literales, genéricas
comprobadas en cada copia, clausuras— y los **mismos mensajes, en el mismo
orden**. `tcodec` lo pasa antes de escribir nada:

```
$ TCODE_RAIZ=. ./tcodec malo.t
error: malo.t:4: no se puede modificar `s`: esta prestada por `v`

1 error. No se genero nada.
```

La suite pasa por los dos compiladores cada programa que tiene que
rechazarse: **los 210 dan el mismo primer error, carácter por carácter**,
también los de sintaxis, que salen del lexer y el parser en Tcode con su
archivo, su línea y lo que encontraron:

```
$ TCODE_RAIZ=. ./tcodec roto.t
error: roto.t:3: se esperaba ';', se encontro ')'
```

Y como siete casos no bastan para fiarse de un parser, la suite rompe cada
archivo del repositorio de varias formas —un token de menos o de más, un
símbolo fuera de sitio, una cadena sin cerrar, un carácter que no existe— y
exige el mismo primer error en todos: **243 de 243**. Y el otro lado, que
importa más: **ninguno de los 167 programas correctos** —los del repositorio
y los de la suite— se rechaza. `tcodec --solo-comprobar` hace sólo esta
parte.

Alinear los dos parsers encontró dos fallos en el de Tcode, que ya escribía
C distinto sin que nada lo dijera: `a || b && c` se leía `(a || b) && c`
—`&&` tiene que atar más—, y `1_000` llegaba tal cual al C, que no lo
entiende.

Escribe clausuras —también las que capturan algo con dueño, que se mueve al
struct de la clausura, y las que van dentro de una genérica, una por copia
y numeradas como el original—, tipos función, structs genéricos
(`Par<A, B>`), bloques, `externo`, enums, arreglos `[T; N]`, funciones
repetidas entre módulos, funciones con nombre de palabra de C (`union`),
`else if` y `escribir_archivo`. Escribe los 25 programas del repositorio,
`pruebas.t` incluido. Lo que todavía no sabe escribir lo rechaza diciendo
qué es, sin dejar medio archivo.

Y las herramientas de alrededor, también con las mismas palabras que las de
Python, comparadas en la suite: los errores de módulos (un ciclo, un módulo
que no está, un nombre que llega de dos sitios, algo que se usa sin
pedirlo), los avisos —variables y parámetros sin usar, un `var` que podría
ser `let`, `como T` sobre algo que ya es `T`, `==` entre decimales—,
`--formatear` en `lib/formato.t`, y `--explicar`, que dice quién es dueño de
qué y dónde se libera cada cosa. Con eso `tcodec` hace todo lo que hace
`tcode`.

Escribirlo encontró fallos reales en el original, que se arreglaron con su
prueba: fugas en salidas tempranas, banderas de propiedad por nombre en vez
de por declaración (C que no compilaba), `for x en [1, 2]` sin su typedef,
un archivo que veía funciones de módulos que no importaba, y un tipo función
que recibe otro (`fn(fn(usize) -> usize, usize) -> usize`), que el
comprobador partía por las comas de dentro.

## Lo que encontró una revisión

Una revisión con programas escritos para romperlo encontró seis formas de
usar memoria ya liberada que el compilador aceptaba, las seis en los dos
compiladores, y las seis confirmadas con AddressSanitizer:

| el programa | por qué colgaba |
|---|---|
| `g(s, vista(s))` con `fn g(a: mut str, b: view)` | una vista sin nombre no prestaba durante la llamada: el fallo 2 de safestr, en una función propia |
| `let v = f(vista(s));` con `f` un puntero a función | la vista no prestaba de lo que se le pasó, y dos préstamos de lo mismo no se miraban |
| `match e { E.A(t) -> { e = E.B; imprimir(t); } }` | lo que atrapa un patrón no prestaba del valor mirado |
| `let v = if c { vista(a) } else { vista(b) };` | la vista de un `if` no prestaba de sus ramas |
| `arr[0] = vista(s)` en un bloque de dentro | un arreglo guardaba vistas sin saber de quién prestaba cada una |
| `nuevo("??=")` | en C17 `??=` es un trigrafo: C leía un `#` y el largo de al lado leía de más |

Hoy los seis son errores de compilación —el último, un literal bien
escrito—, y el compilador en Tcode tenía dos más propios (una clausura o una
genérica que devuelven una vista) que también se cerraron. La misma revisión
arregló un `match` suelto que descartaba sus brazos sin decir nada, `-x`
sobre un `u8` que daba la vuelta, `/?` entre enteros que escribía C
inválido, `imprimir` que se paraba en el primer byte cero, `rebanar` que
fuera de rango daba una vista vacía en vez de parar, y nombres como `log`,
`EOF` o `tm`, que en C ya son otra cosa y hacían que el C no compilara.

Y uno que no era de memoria pero sí de la regla 2: con un número escrito
delante, la cuenta se hacía en `usize` aunque el comprobador ya supiera que
el literal tomaba el tipo del otro lado. `1 + x` con `x: f64 = 2.5` daba
`3`; `0 > n` con `n: i32 = -3`, `false`; `1 + x` con `x: u8 = 255`, `256`
sin parar; `let a: i64 = 5 - 10;` paraba por desbordamiento, e
`imprimir(-1)` escribía `18446744073709551615`. Ahora los dos generadores
hacen la cuenta en el mismo tipo que decide el comprobador.

La causa era de diseño, no de un caso: el generador volvía a deducir el tipo
de cada expresión por su cuenta, y se equivocaba donde el comprobador ya
sabía la respuesta. Por eso ahora **el comprobador anota el tipo de cada
expresión** —con los números escritos ya decididos por su contexto— y los
dos generadores lo leen de ahí. En Python va en el propio nodo; en el
compilador escrito en Tcode, que no tiene punteros, cada nodo lleva un número
y el comprobador devuelve un mapa `función#número → tipo`.

Y para que un fallo así no vuelva a pasar desapercibido hay una propiedad
más, **P11**: programas de aritmética con su salida calculada aparte, en
Python, con las reglas de la especificación. Con el compilador anterior, 125
de 200 daban otra cosa. Al escribirla salieron más:

| el programa | qué pasaba |
|---|---|
| `(if c { 1.5 } else { f }) * f` con `f: f32` | la cuenta se hacía en `f64`: con `f` en el máximo daba `1.15792e+77` en vez de parar |
| `(if c { 300 } else { x }) + 0` con `x: u8` | la rama escrita no se comprobaba: daba `44`. Lo mismo en un `match` |
| `let r: u8 = -(3 + 4);` | compilaba y daba `249` |
| `dice("izq") + (if c { dice("der") } else { 0 })` | escribía `der izq`: el operando que necesita sentencias propias corría antes que los de su izquierda, también en llamadas, structs y arreglos |
| `mismo(1 + x)` con `x: i16` | la genérica deducía `usize` y rechazaba el programa |
| `mismo(g(mismo(x)))` | `tcodec` escribía las dos copias en otro orden que Python |
| `junta(nuevo("a"), if c { nuevo("bb") } else { nuevo("") })` | `tcodec` soltaba dos veces el `str` que el `if` le entregaba a la función |

Lo que la dejó ver es la lección: la suite solo generaba programas válidos,
y un comprobador de préstamos se equivoca justo con los que no lo son. Por
eso ahora hay una propiedad más, P10, que genera a propósito programas que
toman una vista, invalidan a su dueño y la usan, por cada forma que el
lenguaje tiene de fabricar una vista. Con el compilador de antes, 26 de esos
86 programas compilaban. Y P11 es lo mismo para los números: la suite miraba
que un programa corriera limpio, no que imprimiera lo correcto.

## Formato

```
$ tcode mi.t --formatear --escribir
$ make formato
```

Sin opciones, como `gofmt`: hay un estilo y es este. Pero **no mueve tokens
de línea** — no decide dónde parte una expresión larga. Por eso no puede
estropear nada: la salida lexea exactamente a los mismos tokens que la
entrada, y la suite lo comprueba sobre los 54 `.t` del repositorio, junto con
que formatear dos veces da lo mismo y que el repositorio ya está formateado.

## Depurar

Tcode compila a C, así que `gdb`, `valgrind`, los sanitizers y `perf` ya
funcionaban — pero hablaban del `.c` intermedio. Con directivas `#line` en el
C generado, todos señalan el Tcode:

```
Breakpoint 1, hondo (n=3) at mi.t:2
2           let a = n * 2;
(gdb) bt
#7  hondo (n=3) at mi.t:3
#8  main (argc=1, argv=...) at mi.t:7
```

Puntos de ruptura en funciones Tcode, la fuente listada, variables con sus
nombres. Sin escribir un depurador: no hacía falta escribirlo, hacía falta no
perder el sitio.

## Velocidad

Medido contra el mismo programa escrito en C a mano (`make bench`):

| caso | C a mano | Tcode | Tcode / C |
|---|---|---|---|
| aritmética | 0.140s | 0.158s | **1.13x** |
| arreglo (índices comprobados) | 0.266s | 0.265s | **1.00x** |
| cadenas | 0.021s | 0.020s | **0.98x** |
| structs prestados | 0.160s | 0.169s | **1.05x** |

Lo único que se paga es la aritmética comprobada, y sólo cuando el bucle está
dominado por aritmética. Los índices comprobados, los préstamos, la
liberación automática y los arreglos envueltos en struct salen a 1.00x.

El detalle está en [`bench/README.md`](bench/README.md), incluido por qué
`-O3` importa aquí y por qué el compilador escrito en Python no se nota
(es el 0.5% del tiempo; el otro 99.5% es gcc).

## Probarlo

Hace falta Python 3 y un compilador de C. Nada más: el compilador no tiene
dependencias.

```
git clone <este repo> && cd tcode
python3 -m tcode --version
make check          # la suite completa
make ejemplos       # compila y corre los ejemplos
```

Tu primer programa:

```
$ cat > hola.t <<'FIN'
fn main() -> usize {
    imprimir("hola\n");
    return 0;
}
FIN
$ python3 -m tcode hola.t && ./hola
hola
```

Si quieres invocarlo como `tcode` desde cualquier sitio:

```
echo 'python3 -m tcode "$@"' > ~/.local/bin/tcode && chmod +x ~/.local/bin/tcode
```

(El compilador se ejecuta desde el directorio del repo, que es donde vive
`runtime/`.)

## Uso

```
python3 -m tcode programa.t              # compila a binario
python3 -m tcode programa.t -o mi_binario
python3 -m tcode programa.t -O3          # nivel de optimizacion del backend
python3 -m tcode programa.t --emitir-c   # deja el C y no invoca a cc
python3 -m tcode programa.t --explicar   # que infirio el compilador
python3 -m tcode programa.t --solo-comprobar
```

La salida binaria nunca puede ser el propio fuente, tampoco mediante un
enlace ni por usar un archivo sin extensión. Un nombre de salida terminado en
`.t` también se rechaza para que una compilación no pueda sobrescribir código.
El C, el formato y el binario se construyen primero en un temporal vecino y
sólo reemplazan el destino al terminar: si falla el backend, el binario
anterior queda intacto.

## Avisos

Un aviso no impide compilar. Señala algo que probablemente no era lo que
querías, y apunta **al código que escribiste**, no al C generado:

```
$ python3 -m tcode area.t
aviso: area.t:2: `total` se declara `var` y nunca se modifica; puede ser `let`
aviso: area.t:3: `sobra` se declara y no se usa; si es a proposito llamala `_sobra`
aviso: area.t:1: el parametro `b` de `area` no se usa; si es a proposito llamalo `_b`
```

Los cinco que hay hoy:

| | |
|---|---|
| variable declarada y nunca usada | `_nombre` lo silencia |
| valores que se asignan y nunca se leen | |
| `var` que nunca se modifica | *puede ser `let`* |
| parámetro que no se usa | `_nombre` lo silencia |
| parámetro `mut T` que nunca se modifica | *podría ser `&T`* |

Un `_` delante del nombre lo calla, como en Rust: dice que es a propósito y
quien lea el código no tiene que preguntárselo.

```
python3 -m tcode programa.t --avisos-como-errores   # no compila si hay avisos
python3 -m tcode programa.t --sin-avisos
```

## `--explicar`

Tcode se apoya en un análisis —quién es dueño de qué, quién presta a quién,
dónde se libera cada cosa, de dónde sale cada vista— que normalmente sólo se
ve cuando **falla**, en forma de error. `--explicar` lo muestra cuando sale
bien:

```
$ python3 -m tcode ejemplos/informe/informe.t --explicar

  struct Articulo   es DUEÑO: contiene memoria que hay que liberar
      nombre: str  <- duenio
      unidades: usize
      el compilador genera `ss_drop_Articulo` y lo llama donde haga falta

  fn linea(a: &Articulo, total: usize) -> str !
      puede fallar: quien la llame tiene que usar `try` o `sino`
      arg a       Articulo  prestado para leer  no se libera aqui: es de quien llama
      var s       str       DUEÑA               se entrega en la linea 27 (return)
      let nombre  str       DUEÑA               se libera sola al cerrar su bloque
      4 valor(es) con memoria propia: 3 se liberan solas, 1 se entrega
```

Y explica también los casos difíciles, como una variable que se mueve pero
podría no llegar a moverse:

```
      var caja  Caja  DUEÑA  se mueve a `consumir` en la linea 14;
                             lleva bandera por si el programa sale antes
```

Sirve para tres cosas: aprender el modelo sin pelearse con él, entender por
qué un programa que compila hace lo que hace, y **revisar el propio
compilador** — si lo que dice ahí no cuadra, el fallo está en el análisis.
Por eso es una de las propiedades que comprueba la suite.

## Estado

**v0, y lo digo en serio.** Funciona de punta a punta y la suite pasa, pero
falta casi todo lo que un lenguaje necesita para ser usable en producción.

Hay: funciones, `let`/`var`, `if`/`else`, `while`, `return`, aritmética
comprobada, `str`/`view`/`usize`/`i64`/`bool`, préstamos con ámbito léxico,
liberación automática, lectura completa de archivos y conversión básica a
texto.

Hay también: `struct`, arreglos de tamaño fijo con índices comprobados,
structs anidados, arreglos de structs, propiedad recursiva, préstamos de
structs (`&T` y `mut T`), `lista<T>` dinámica, `mapa<str, V>` con tabla hash,
argumentos de la línea de órdenes, `ordenar` y `menor`, salida de error y
escritura de archivos, `for`/`break`/`continue`, `mapa<str, V>` con `obtener` prestado y `&T` y `&mut T` como tipos, cadenas interpoladas, módulos y fallos como valores.

Hay además una biblioteca estándar escrita en Tcode —`std/caracter`,
`std/texto`, `std/lista`, `std/numero`, `std/cuenta`, `std/bytes`,
`std/conjunto`, `std/formato`, `std/mapa`, `std/par`, `std/prueba` y
`std/vector`—, 941 líneas que ningún programa tiene ya que copiarse. Los ejemplos del repositorio las usan, y no
queda una sola función duplicada entre `ejemplos/` y `std/`.

Y **`copiar(x)`**: copia profunda de cualquier valor —número, `str`, struct,
`lista<lista<str>>`, mapa— con el copiador generado por el compilador, uno
por tipo. Explícita como el `Clone` de Rust, pero sin `derive`: todo tipo es
copiable siempre, porque la estructura del tipo es toda la verdad que hay.

Y **funciones genéricas**: `fn primeras<T>(xs: &lista<T>) -> lista<T>`, con
una copia por cada juego de tipos, los tipos deducidos de los argumentos, y
errores que dicen con qué tipos se instanció y desde dónde.

Con **restricciones** sobre los parámetros de tipo —`fn suma<T: numero>`,
`fn incluye<T: igualable>`— tomadas de los *type sets* de Go: un conjunto de
tipos con nombre, sin `impl` y sin coherencia. Sirven para que el error salga
en la llamada y diga qué se pedía, en vez de salir de tres niveles más
adentro del cuerpo.

Y **tipos suma**: `enum Json { Nulo, Numero(i64), Texto(str), Lista(lista<Json>) }`
con `match` **exhaustivo** —si falta una forma, el error la nombra— y sin
`ref` ni `&` en los patrones, porque un `match` mira y no desmonta: lo que
atrapa el patrón se presta siempre, y quien quiera quedarse con lo de dentro
escribe `copiar(...)`. La etiqueta 0 es la primera variante, así que un enum
a ceros sigue siendo un valor válido y cabe en la memoria que da `reservar`
sin ningún `unsafe`; ni Rust ni Zig garantizan eso. Está en `ejemplos/json.t`.

Y **lo que el programa le pide a la máquina**, que no puede ir por `externo`
porque devuelve memoria y la memoria tiene dueño: `leer_linea`,
`entrada_completa`, `variable_entorno`, dos relojes (`ahora_ms` de pared y
`monotono_ms` para medir duraciones, con el nombre diciendo cuál es cuál), y
`azar`/`sembrar` sin el sesgo de `rand() % n`. `leer_linea` crece lo que haga
falta —el `bufio.Scanner` de Go deja de leer a los 64 KB y no lo dice—, el fin
de la entrada es un fallo y no una cadena vacía, y `variable_entorno`
distingue «no está» de «está vacía», que `getenv` no puede. Está en
`ejemplos/sistema.t`.

Y **la puerta a C**: `externo "math.h" { fn sqrt(x: f64) -> f64; }`. Compila a
C17, así que la llamada no cuesta nada —es la misma que escribiría un
programa en C—, y no lleva `unsafe` por llamada como en Rust porque no hace
falta: en el borde sólo caben los tipos que significan exactamente lo mismo a
los dos lados. Un `str` entra como `const char*` porque siempre acaba en
`\0`; una `view` no, y el compilador lo dice. Si un `str` lleva un cero *en
medio*, el programa para en esa línea en vez de darle a C una cadena cortada.
Y si la cabecera acaba en `.c`, se compila y se enlaza junto al programa: lo
que no cabe en el borde se envuelve en dos líneas de C, sin salir de `tcode`.
Está en `ejemplos/externo/`.

Y **structs genéricos**: `struct Pila<T>`, `struct Par<A, B>`, y
`struct Nodo<T> { valor: T, hijos: lista<Nodo<T>> }`, que se contiene a sí
mismo. `std/par` es un contenedor escrito en Tcode del que el compilador no
sabe nada: es lo que separa "un lenguaje con dos colecciones" de un lenguaje.

Y **memoria propia**: `bloque<T>` con `reservar(n)` y `redimensionar`, más
`intercambiar(sitio, valor)`. `std/vector` es una lista dinámica completa
escrita **entera en Tcode** sobre eso, sin que el compilador sepa nada de
ella. No hace falta `unsafe` para escribirla, y la razón es una propiedad del
lenguaje que estaba sin usar: **todo tipo puesto a ceros es un valor válido y
vacío**, así que un bloque recién reservado no tiene ranuras sin inicializar
—que es de donde salen el `MaybeUninit` de Rust y el `unsafe` dentro de
`Vec`—.

Y **clausuras**: `fn[inicial](x: &str) -> bool { ... }`, con lista de captura
explícita y **por valor**. Un `str` capturado se mueve a la clausura y se
libera con ella. Por eso son simples aquí: una clausura es un struct con lo
capturado más una función que lo recibe, y de structs con dueño el compilador
ya lo sabía todo. Sin traits, sin anotaciones, sin recolector — el precio es
que no puedes capturar un préstamo, y el error lo dice. Con `fn[mut n]` la
clausura modifica **su** copia, que se queda entre una llamada y otra: un
contador sin préstamos. Llamarla la modifica, así que se guarda en un `var`
y una genérica la recibe como `mut F` — lo que Rust separa en `FnMut`, aquí
es el `mut` de siempre.

Y **`if` como valor**: `let x = if n > 3 { 1 } else { 2 };`. Cada rama es una
expresión y el `else` es obligatorio — así no hay que aprender la regla sutil
de Rust, donde añadir un `;` cambia lo que vale un bloque.

Y **decimales** (`f64`, `f32`) con una decisión que no toma ningún lenguaje
grande: **una operación que no da un número detiene el programa donde
aparece.** `0.0/0.0`, `1.0/0.0` y el desborde a infinito paran, igual que ya
paraba un desbordamiento entero; `+?`, `-?`, `*?` y `/?` devuelven el IEEE de
siempre si lo pides. El problema del NaN no es que exista: es que nace en el
paso 3 y se descubre en el paso 900. Además, `==` entre decimales avisa (Rust
necesita clippy para eso), `3.7 como usize` para en vez de truncar en
silencio como hace `as` en Rust, y un `f64` que vale 1 se imprime `1.0`.

Y **funciones como valor**: el nombre de una función es un puntero a
función, de coste cero y sin dueño. `fn ordenadas_por<T>(xs: &lista<T>,
antes: fn(&T, &T) -> bool)` ordena con el criterio que se le pase. Un
puntero a función no captura nada; para eso están las clausuras.

Y **enteros de ancho fijo** —`u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`,
`i64`, `usize`— con la aritmética comprobada en todos ellos; **operaciones de
bits** (`&`, `|`, `^`, `<<`, `>>`, `~`) que atan más que las comparaciones,
no menos que ellas como en C; conversión `como` que aborta si el valor no
cabe (`como?` para salirse a propósito); y **bytes crudos**: `\xNN` en una
cadena, `empujar_byte`, y `std/bytes` con enteros en orden de red y hex.
`ejemplos/binario.t` escribe y lee un formato binario con suma de
verificación — lo que antes de esto no se podía escribir en Tcode.

Y **espacios de nombres**: los nombres se resuelven por archivo, como en
Python. Dos módulos pueden declarar `contar` sin estorbarse; sólo choca si un
mismo archivo los trae a los dos de forma llana, y entonces el error dice
cómo arreglarlo con `usar "..." como algo;`. El renombrado interno sólo
ocurre donde de verdad choca: mientras `palabras` sea de un solo módulo, en
el C generado se sigue llamando `palabras`.

Y **structs que prestan**: un struct con un campo `view` se trata como una
vista —la vida única implícita de un `struct Foo<'a>` de Rust, sin anotarla—:
presta de lo que se le puso, no vive más que sus dueños y no se guarda en una
lista, un mapa ni un enum. Se puede **sacar un campo** de un struct propio
(`let n = p.nombre;`): su sitio queda a ceros, y el struct no se usa entero
hasta que se reponga. El `match` admite **patrones anidados, literales y
guardas**, con la exhaustividad pidiendo un brazo sin condiciones por forma. Y
una **genérica con restricción compila para todo su conjunto**: el cuerpo se
comprueba con cada tipo que la restricción admite, como en Rust, porque aquí
los conjuntos son finitos.

No hay: E/S incremental, enums con parámetros de tipo, ni patrones sobre
rangos.

Una función sí puede devolver una vista de lo que le prestaron —un `&str`,
un campo de un `&T`, un elemento de una `&lista`, un `mut str`—, y quien
llama queda protegido: la vista presta de todo lo que se le pasó prestado,
no vive más que su dueño aunque se reasigne, y no se guarda si sale de un
temporal.

```
$ make check
1979 casos, 0 fallas
816 comprobaciones sobre 60 programas, 0 fallas
```

La suite tiene dos mitades. La primera son **casos por ejemplo**: este
programa da esta salida, este otro no compila y el error dice esto.

La segunda son **propiedades sobre programas generados al azar**, que es lo
que encuentra lo que a nadie se le ocurrió escribir a mano:

| | invariante |
|---|---|
| **P1** | todo programa aceptado genera C que `cc` acepta con `-Wall -Wextra -Werror` |
| **P2** | todo programa aceptado corre limpio bajo ASan y UBSan: ni fugas, ni doble free, ni uso tras liberar |
| **P3** | compilar dos veces da C byte a byte idéntico |
| **P4** | todo error nombra un archivo y una línea que existen |
| **P5** | el compilador nunca revienta, con entrada válida o inválida |
| **P6** | `--explicar` funciona sobre todo programa aceptado y nombra todas sus funciones y variables |
| **P7** | todo aviso nombra un archivo y una línea que existen, y ningún aviso impide compilar |
| **P8** | ante un programa **roto a propósito**, el compilador o lo acepta o lo rechaza diciendo dónde: nunca una excepción, nunca un cuelgue |
| **P9** | un programa repartido en varios archivos, con `usar` en rombo, compila y corre igual: los structs y las funciones cruzan de módulo, y un `str` que nace en uno y muere en otro no se filtra |
| **P10** | una vista no sobrevive a que su dueño se reasigne, crezca, se mueva o se libere, venga de `vista`, `rebanar`, un `if` o un `match`, una función, un puntero a función, una clausura, una genérica, un struct que presta o un mapa: el programa que la usa después no compila, y su gemelo que la deja morir antes corre limpio bajo ASan |
| **P11** | un programa de aritmética imprime lo que tiene que imprimir y para donde tiene que parar —con los nueve enteros y los dos decimales, números escritos a cada lado, conversiones, `if` como valor, llamadas, genéricas, campos y arreglos—, y `tcodec` escribe para él el mismo C que Python, byte a byte |

`tests/generador_programas.py` produce programas válidos por construcción
—con cadenas propias, structs, arreglos, `lista<usize>` y `lista<str>`,
`mapa<str, usize>`, préstamos `&T` y `mut T` de structs y de `str`,
movimientos, fallos, `texto`, `byte`, y las **dos** ramas de un `sino`
cuya alternativa es dueña de su memoria— y acotados para que no aborten ni
se cuelguen. `tests/violaciones.py` hace lo contrario, para P10: programas
que no deberían compilar. Y `tests/oraculo.py`, para P11, genera programas
de aritmética y calcula en Python lo que tienen que imprimir, o dónde y con
qué mensaje tienen que parar. Para insistir más:

```
TCODE_PROGRAMAS=1000 make propiedades
```

Los casos de rechazo comprueban que los programas malos no compilan; los de
aceptación corren bajo AddressSanitizer y UndefinedBehaviorSanitizer y comparan
la salida exacta, incluida una lectura binaria real. Los programas de
`ejemplos/` se compilan y se corren ahí también: la vitrina del lenguaje
tiene que estar tan comprobada como el resto, y la primera vez que se hizo
apareció una fuga real. Otros comprueban que la
aritmética y los índices detienen el programa en vez de seguir con basura, y
arman programas de varios archivos para probar módulos, ciclos y nombres
repetidos.
