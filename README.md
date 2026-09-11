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

## Las cuatro reglas

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
| `std/` | la biblioteca estándar, escrita en Tcode |
| `runtime/` | safestr, la librería de C original, ya corregida |

## El lexer y el parser de Tcode, escritos en Tcode

`ejemplos/lexer/lexer.t` son 259 líneas que hacen el análisis léxico del
propio lenguaje: comentarios, cadenas normales e interpoladas, números,
identificadores, palabras reservadas y símbolos de uno y dos caracteres.

Sobre los diez `.t` del repositorio —incluido el suyo propio— produce
**4.660 tokens idénticos** a los del lexer del compilador, uno a uno. Eso
está en la suite, así que si alguna vez deja de coincidir, se sabe.

```
$ ./ejemplos/lexer/lexer ejemplos/lexer/lexer.t --contar
ejemplos/lexer/lexer.t: 1688 tokens
  cadena  40      entero  136     fin  1        ident  405
  interpolada  4  palabra  225    simbolo  877
```

Es el primer programa grande del lenguaje y su primera prueba de fuego: usa
`lista<Token>` con campos dueños, `mapa<str, usize>` para las palabras
reservadas, `for` con `break` y `continue`, fallos con `try`, cadenas
interpoladas para los mensajes, y lectura de archivos con argumentos. Corre
limpio bajo ASan y UBSan, y ante una entrada rota —una cadena sin cerrar, un
archivo binario— falla diciendo qué pasa, sin reventar ni filtrar.

`ejemplos/lexer/parser.t` son 621 líneas más: descenso recursivo con la
precedencia completa, sentencias, declaraciones y un árbol que se construye
de abajo arriba. Acepta y rechaza **exactamente** los mismos doce archivos
que el parser del compilador, y sobre ellos produce 4.592 nodos:

```
$ ./ejemplos/lexer/parser ejemplos/lexer/parser.t --callado
ejemplos/lexer/parser.t: 2109 nodos, hondura 16
```

Falta el comprobador y el generador para que Tcode se compile a sí mismo.
Pero el análisis ya no es una promesa: son 884 líneas de Tcode que hacen el
trabajo del frontend y coinciden con el original, comprobado en cada
ejecución de la suite.

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
make ejemplos       # compila y corre los cinco ejemplos
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
python3 -m tcode programa.t -O3          # nivel de optimizacion del backend
python3 -m tcode programa.t --emitir-c   # deja el C y no invoca a cc
python3 -m tcode programa.t --explicar   # que infirio el compilador
python3 -m tcode programa.t --solo-comprobar
```

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

No hay: genéricos definidos por el usuario, espacios de nombres, diccionarios,
E/S incremental ni el propio compilador escrito en Tcode. Tampoco: campos `view` dentro de un
struct (el muro real: exige la vida útil en el tipo), movimientos parciales
de un campo o elemento, ni devolver una vista de un parámetro prestado.

```
$ make check
197 casos, 0 fallas
548 comprobaciones sobre 60 programas, 0 fallas
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

`tests/generador_programas.py` produce programas válidos por construcción
—con `lista<usize>` y `lista<str>`, `mapa<str, usize>`, préstamos `&T` y
`mut T` de structs y de `str`, `texto`, `byte`, y las **dos** ramas de un
`sino` cuya alternativa es dueña de su memoria—
—con cadenas propias, structs, arreglos, listas dinámicas, préstamos,
movimientos y fallos— y
acotados para que no aborten ni se cuelguen. Para insistir más:

```
TCODE_PROGRAMAS=1000 make propiedades
```

Los casos de rechazo comprueban que los programas malos no compilan; los de
aceptación corren bajo AddressSanitizer y UndefinedBehaviorSanitizer y comparan
la salida exacta, incluida una lectura binaria real. Otros comprueban que la
aritmética y los índices detienen el programa en vez de seguir con basura, y
arman programas de varios archivos para probar módulos, ciclos y nombres
repetidos.
