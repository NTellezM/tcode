# Cambios

Las versiones siguen `docs/COMPATIBILIDAD.md`. La de ahora está en `VERSION`.

## Sin publicar

### Añadido

- `programas/json.t`: el segundo programa real —valida y reformatea JSON, con
  un `Valor` recursivo (`lista<Valor>` y `mapa<str, Valor>`), texto y escapes
  (`\uXXXX` a UTF-8)—, y entra en la suite contra un oraculo de ida y vuelta
  con el `json` de Python. Es el item 6: mapas, genericas y texto intensivo,
  lo que las pruebas apenas tocaban.
- `make fuzz-safestr`: fuzzing del runtime C con libFuzzer (clang). La entrada
  se lee como un guion de operaciones sobre `SafeString` y `SafeView` y
  comprueba los invariantes de `safestr.h` bajo ASan+UBSan, ademas de los
  fallos de memoria. Corre tambien en la CI nocturna, junto al fuzzing del
  compilador. Es la respuesta a la pregunta abierta 4 de la auditoria.

### Añadido

- `contrib/tree-sitter-tcode`: la gramatica de tree-sitter —espejo del parser
  del compilador, con resaltado y el parser C generado—, para que Tcode se
  resalte y se pliegue en el editor. Es el primer paso del peldaño 2.

- `contrib/lsp`: un servidor LSP —diagnósticos (los errores del compilador,
  subrayados) y formato— que habla con el propio `tcodec`, sin un segundo
  analizador. Con una extensión mínima de VS Code. Es el LSP del peldaño 2.

- `bin/tcode`: el comando amigable —`tcode correr` (compila y ejecuta de una),
  `tcode nuevo` (crea un proyecto), `tcode comprobar`, `tcode formato` y
  `tcode version`—. No es un segundo compilador: es un nombre corto sobre
  `tcodec`, y `make instalar` lo deja en el PATH.

- `instalar.sh`: instala `tcodec` y `tcode` en `~/.local` sin sudo, y dice
  cómo añadirlo al PATH.
- La extensión de VS Code (`contrib/lsp/vscode`) ahora trae **resaltado**
  (gramática TextMate) e **icono** para los `.t`, además del LSP.

- `docs/GUIA.md`: «Tcode en 10 minutos» —instalar, hola mundo, structs,
  `view` contra `str`, genéricos, enums y fallos— con todos los ejemplos
  compilados y verificados. Es por donde entra un recién llegado.

- `std/json` y `std/cli`: dos bibliotecas nuevas. `json` lee y escribe JSON
  (un `Valor` recursivo, escapes `\uXXXX`); `cli` lee los argumentos
  (`--bandera`, `--opcion=valor`, y los sueltos). `programas/json.t` ahora las
  usa, asi que el oraculo de ida y vuelta contra el `json` de Python las
  ejercita (280 casos).
- `std/csv` y `std/azar`: dos mas. `csv` lee y escribe CSV (comillas, escapes
  y saltos de linea); `azar` da un entero entre dos, un indice valido, y baraja
  con Fisher-Yates. Igual que las anteriores, en forma libre.
- `std/ini`: lee y escribe INI (`[seccion]`, `clave = valor`, y `;`/`#`),
  a `mapa<str, mapa<str, str>>`, con `valor`/`valor_o` para consultar. La
  seccion sin nombre se escribe primero, que si no sus claves caen en la
  anterior al releer.

### Corregido

- `ejemplos/compilador/tipar.t`: al tipar `for clave, valor en mapa` con el
  mapa prestado (`&mapa<...>`), `valor_de` no quitaba el préstamo y el `valor`
  salía sin tipo. Lo destapó `std/json` al entrar al corpus; ahora la clave y
  el valor salen bien.
- El compilador de Python rechazaba devolver una vista sacada de un campo, un
  elemento o un `&T` de un parámetro —`sin_ceros(n.texto)`, `sin_ceros(xs[0])`,
  `sin_ceros(s)`— cuando la memoria es de quien llama. Ahora, para un
  parámetro `view`, mira el argumento como `vista(...)` —igual que `tcodec`— y
  acepta lo que debe. Lo destapó `std/ini`; es un arreglo de corrección, no
  cambia la superficie del oráculo congelado.

### Documentado

- `docs/TIPOS.md`: el plan del modelo de tipos (de `str` a `Tipo`), en tres
  etapas con la garantia de C identico por etapa. Es posterior al 1.0.

## 1.0.0-rc3 — 2026-10-01, candidata local

### Corregido

- Un campo de struct —o una carga de enum— de tipo `&T` no decía de quién
  prestaba ni cuánto vivía, y salía mal en los dos compiladores: `tcodec` lo
  escribía en C por valor y con dueño, así que el struct y su dueño liberaban
  el mismo búfer (doble liberación, confirmada con ASan), y el compilador de
  Python escribía un puntero pero le daba el valor, con C que no compilaba.
  Ahora los dos lo rechazan al compilar, y el mensaje dice cuál es la forma
  de que un struct preste: el campo `view`. Lo encontró una revisión con
  ASan, y ninguna suite lo veía: ningún programa del repositorio tenía un
  campo así.
- Una vista de una vista —`& &T`— daba C que no compilaba, en los dos
  compiladores: el `const` se anteponía al tipo de dentro, que ya era
  `const T*`, y salía `const const T**`. Ahora el `const` va en el nivel del
  puntero (`const T* const*`; `T* const*` cuando dentro hay un `&mut T`, que
  tampoco cabe en un `const T**`), y la llamada presta el sitio donde vive el
  `&T` en vez de pasar el puntero tal cual, que daba un argumento de otro
  tipo. Lo encontró el fuzzing; el hallazgo guardado queda de regresión.
- Un `&T` dentro de un contenedor no se rechazaba: `lista<&str>`, `[&str; n]`
  y `bloque<&str>` se aceptaban en los dos compiladores, y un `mapa<str, &T>`
  se colaba en un campo de struct, en un parametro y en el retorno de una
  funcion. Usarlos tampoco iba bien: en Python el C no compilaba y `tcodec`
  se rendia con «no sabe escribir esta expresion». Ahora los contenedores
  rechazan un prestamo dentro, como ya hacia el mapa en una variable.
  Salió al ampliar FORMAS con una hoja `view`: al mirar qué contenedores
  aceptan una vista, apareció que aceptaban una referencia.

### Añadido

- FORMAS cubre el struct que presta: una hoja `vista` —el unico prestamo que
  se puede tener en la mano, porque sale de un literal— como campo de un
  struct, y ese struct dentro de otro. En una lista, un mapa, un arreglo o un
  enum no cabe, y la suite lo cuenta aparte. Son 198 formas en tres sitios,
  con los dos compiladores y bajo ASan. Un `&T` no puede ser hoja: una
  funcion no puede devolver un prestamo a algo suyo; esos casos son rechazos
  y viven en RECHAZO.
- Los generadores comprueban lo que antes solo contaban. FORMAS prueba sus 15
  formas «no se escribe» —una lista, un mapa, un arreglo y un enum de algo que
  presta, y un arreglo dentro de una lista— contra los dos compiladores, y
  vigila sus 7 huecos (Python los escribe y `tcodec` no): si uno cambia, lo
  dice, como la lista de rechazos que solo entiende `tcodec`. Y P10 pasa de
  una forma de struct que presta a nueve —el literal, `rebanar`, una funcion,
  `if`, `match`, y dos campos de hondo—, cada una con sus dos enlaces, sus
  cuatro invalidantes y la llamada con el prestamo sin nombre: 221 pares.
- `make cobertura`: la cobertura del compilador de Python, que dice que
  caminos del oraculo congelado no se pisan nunca. Compila el corpus de la
  suite y los rechazos escritos a mano en un solo proceso; hoy el 86%. Lo que
  queda son asserts defensivos que nadie dispara y las internas que el corpus
  no llama. Las secciones por capas compilan en hijos de `fork` y `coverage`
  no los ve, asi que es un suelo y no el total.
- `make mutar`: rompe a proposito una regla en los DOS compiladores —un fallo
  compartido, que la comparacion diferencial no puede ver, y la clase que mas
  fallos ha dado— y exige que REGLAS, RECHAZO o ACEPTA se quejen: las tres
  traen oraculo propio, sin comparar con el otro compilador. Tres mutaciones
  hoy: una lista que vuelve a aceptar prestamos, un campo de struct que vuelve
  a guardar un `&T`, y una vista de una vista que vuelve a dar
  `const const T**`. Las tres se cazan.

### Cambiado

- Diez funciones del compilador que nadie llamaba —`tipo_de_nombre`,
  `direccion_de`, `lleva_coma`, `hacer_bloque`, `hacer_mapa`, `ya_esta`,
  `destino_para`, `recoger_structs`, `recoger_enums` y `modulos_usados`— se
  han quitado: 56 lineas menos, y ninguna se menciona en todo el repositorio,
  ni pasandola como valor. Y tres del oraculo de Python que salieron de la
  misma cuenta: `clave_mapa` y `valor_mapa`, los dos accesores de `mapa` que
  nadie usaba --el codigo llama a `partes_mapa` directo, 19 veces--, y el
  metodo `fue_movida`. Ninguna esta en la superficie congelada, y el lado Tcode
  tiene las suyas en uso (`valor_de_mapa`), asi que no se rompe el espejo.
- `interna`, la funcion que comprueba las internas del lenguaje, pesaba 347
  lineas: ahora es un despacho plano y diez funciones de una interna cada una
  —`interna_comparar`, `interna_numeros`, `interna_reservar`,
  `interna_redimensionar`, `interna_intercambiar`, `interna_copiar`,
  `interna_largo`, `interna_anadir`, `interna_ordenar`, `interna_texto`—,
  todas de 15 a 35 lineas, como ya era `interna_mapa`. El C que sale es el
  mismo, byte a byte.
- `interna_pura`, la parte del generador que baja las internas a C, pesaba 504
  lineas: ahora es un despacho plano y dieciseis funciones de una interna cada
  una —`interna_pura_redimensionar`, `interna_pura_intercambiar`,
  `interna_pura_argumento`, `interna_pura_largo`, `interna_pura_nuevo`,
  `interna_pura_vista`, `interna_pura_comparar`, `interna_pura_byte`,
  `interna_pura_mapa`, `interna_pura_copiar`, `interna_pura_imprimir`,
  `interna_pura_texto`, `interna_pura_numeros`, `interna_pura_ordenar`,
  `interna_pura_empujar_byte`, `interna_pura_rebanar`—, de 9 a 64 lineas. El C
  que sale es el mismo, byte a byte.
- `expresion_c` (274 lineas) y `comprobar_sentencia_sin_contar` (333) eran un
  `match` sobre la clase del nodo: ahora son un despacho y siete y nueve
  funciones de un brazo cada una —`expresion_sola_c`, `variable_c`,
  `enum_lit_c`, `decimal_c`, `literal_lista_c`, `campo_c`, `unaria_c`, y
  `sentencia_declaracion`, `sentencia_asignacion`, `sentencia_si`,
  `sentencia_para`, `sentencia_mientras`, `sentencia_retorno`,
  `sentencia_falla`, `sentencia_expresion`, `sentencia_otra`—. Cada una lleva
  justo lo que usa: el compilador senalo los parametros que sobraban y se
  ajustaron. El C que sale es el mismo, byte a byte.
- `comprobar_programa` (289 lineas) y `generar_soporte` (239) eran una
  secuencia de fases sin nombre: ahora cada fase es una funcion —`registrar_*`,
  `validar_*` y `comprobar_*` en el primero, y `declarar_tipos`,
  `definir_tipos`, `internas_del_sistema`, `soltar_structs` y `soltar_enums`
  en el segundo—. El C que sale es el mismo, byte a byte.

## 1.0.0-rc2 — 2026-09-30, candidata local

### Corregido

- Una variable o un parámetro que se llama igual que una función a la que
  se llama donde la variable está a la vista daba C que no compilaba, en
  los dos compiladores: en C la variable tapaba a la función. Ahora la
  función se renombra en el C como si chocara con otro módulo. Solo en ese
  caso: ningún programa que ya compilaba cambia su C. Lo encontró la
  biblioteca gráfica del Tamagotchi.
- `tcodec` no liberaba un struct cuyo único campo con dueño era un enum
  (`struct Ficha { quien: Nombre }`), ni uno con un campo de otro módulo
  (`hoja: Q.Hoja`): perdía esa memoria. Python sí lo liberaba. Ahora
  `tcodec` mira cada campo con la misma regla que el propio struct, y el C
  de los dos compiladores coincide. Lo encontró ASan en el Tamagotchi.
- Un struct con un campo arreglo (`b: [i64; 2]`) daba C que no compilaba,
  en los dos compiladores: el envoltorio del arreglo salía después del
  struct que lo lleva. Ahora sale justo antes. Solo cambia el C de esos
  programas, que antes no compilaban.
- Un préstamo que ya se tiene —lo que da `obtener` u `obtener_mut`, lo que
  atrapa un `match`— no se podía pasar a una función que presta, en los dos
  compiladores: se comparaba `&N` con el `N` del parámetro. Ahora pasa tal
  cual; un `&T` hacia un parámetro `mut` sigue siendo error, con un mensaje
  que dice por qué (antes pedía `mut &mut N`).
- `mapa<str, [T; n]>` daba C que no compilaba, en los dos compiladores: el
  mapa guarda un puntero al envoltorio del arreglo, que se definía después.
  Ahora esos envoltorios llevan nombre y se declaran antes; el C de los
  demás programas no cambia.
- `tcodec` escribía dos veces el envoltorio de `[Q.T; n]` (con y sin el
  alias del módulo), y no sabía copiar un enum que lleva un tipo con dueño
  de otro módulo (`Con(H.Nombre)`). Python no aceptaba esa forma de enum, y
  tipaba como `usize` un `match` de números escritos donde se esperaba otro
  entero.
- Con un local que no se puede llamar y se llama como una función
  (`var partes: lista<str>` y `partes(x)` o `T.partes(x)`), `tcodec` tomaba
  el tipo del local para la llamada y no sabía escribir la declaración que
  la guardaba. Ahora busca el local por el nombre entero, como el
  generador, y si no se puede llamar sigue con la función.
- La pregunta «¿este tipo es dueño de memoria?» tenía siete respuestas en
  cuatro archivos de `tcodec`, y de ahí salió la fuga de los structs con un
  enum. Ahora hay una sola regla, `posee_en` en `lib/tipos.t`, que conoce
  structs, genéricas, enums y alias de módulo.
- Los tipos de `tcodec` se normalizan una sola vez, al leer: tras mirar que
  cada archivo pide lo que usa, el árbol pierde el alias de módulo en cada
  sitio donde guarda un tipo (`Q.Caja`, `lista<H.Nombre>`, `Q.Sobre.Con`), y
  las firmas que se recogen al leer ya se guardan sin él. Tres de los
  fallos de arriba venían de una capa que olvidaba quitarlo; desde aquí
  ninguna lo ve, y `tcodec.t` pasa de quince sitios que lo quitaban a uno.
  Las llamadas lo conservan: `Q.hecho` dice de qué módulo es la función.
- `tests/fuzz.py` mira los errores de `cc` y `ld` en inglés (`LC_ALL=C`).

### Corregido

- Los fallos del compilador que dicen que todavia no sabe escribir algo
  —copiar bloques, arreglos o bloques dentro de un enum, mapas donde no caben,
  un nombre repetido entre modulos, una clausura o una copia que no salen— ya
  dicen en que archivo y en que linea del programa se pidieron: `error: p.t:1:
  tcodec no escribe bloques ni arreglos dentro de un enum`. Antes salian como
  `tcodec: ...` sin sitio, que es lo que el contrato del fuzzing no admite, y
  hay un hallazgo guardado de eso mismo (`894fb7b540ee`). Son 19 mensajes: 18
  ya dicen el sitio —14 llamadas de `rechazo` y 4 de la generacion de copias y
  clausuras—, y el sitio lo pone el programa: el nodo que lo pidio, el `usar`
  que traia el modulo, o donde se declaro el nombre. El otro, el del tipo que
  no se puede registrar, se ha quitado: quien lo pedia ya lo dice con su linea
  y ademas nombra el tipo.
- Y las cuentas del propio compilador —`X se usa y el recorrido no la
  registro`, que es lo que cazo `047b1a5da3f2`— dicen ya lo que son: `... Es
  un fallo del compilador, no de tu programa`. No piden sitio: quien se queja
  trabaja sobre el C ya generado, y el nodo del programa se perdio al
  generarlo; inventar una linea seria mentir. El juez del fuzzing los sigue
  cazando, ahora con una firma que dice lo que pasa en vez de «rechaza sin
  archivo y linea». Son ocho mensajes, y el de `emitir_funcion` ademas lleva
  sitio, que ahi el nodo y la ruta estan a mano.

### Añadido

- Cinco palabras reservadas de antemano: `protocolo`, `implementa`,
  `extiende`, `ancla` y `soltar`. Todavía no significan nada, pero un
  programa que las use como nombre ya no compila. Se reservan ahora para
  poder añadir anclajes en 1.x sin romper programas después. Solo en
  `tcodec`; el compilador de Python está congelado y no las conoce.

- P10 cubre un `&str` prestado de un contenedor: `let v = xs[0];`
  con `xs: lista<str>`, invalidado por `anadir` o reasignando la
  lista. Es la forma que faltaba: un préstamo a un sitio dentro de
  una lista, y la lista la que crece.

- La composicion de tres capas (funcion sobre funcion sobre `if`)
  tambien esta cubierta: `id(primero(if c { vista(s) } else { "z" }))`.
  El caso literal de la auditoria —una vista dentro de un `if`
  dentro de un argumento de una clausura generica— no se puede
  probar todavia: el comprobador no acepta `aplica<T, F>` con
  `T = view`, porque no puede saber que `f(x)` devuelve una vista
  que sale de un parametro. Queda anotado como limite conocido.

- Prestar un sitio: `let x: &T = l[i];` lee un elemento, un campo o una
  variable sin copiarlo, y `let x: &mut T = l[i];` deja modificarlo por
  `x`. Mientras `x` se use, la variable de la que sale queda prestada
  entera. Antes la única forma de leer un elemento con dueño era
  `copiar(...)` —una copia profunda—, y el mensaje de error lo decía; ahora
  sugiere el préstamo. Solo con tipos que tienen partes; con un escalar, el
  error de siempre. Igual en los dos compiladores.

### Cambiado

- `tcodec` tarda un 8 % menos en escribir su propio C (1,32 s a 1,22 s).
  Una comprobación sobre el C ya escrito recorría todas las líneas una vez
  por cada prefijo y por cada genérica, y era el 27 % del tiempo; ahora es
  una sola pasada. El propio compilador presta nodos y funciones en vez de
  copiarlos donde puede.

- Las funciones del programa salen `static` en el C, con
  `SS_LANG_QUIZA_SIN_USAR`. El programa es un solo archivo de C y nadie de
  fuera las llama; con enlace externo, gcc en `-O2` dejaba de integrar una
  función pequeña cuyo cuerpo crecía con las comprobaciones, y el caso
  `structs` del benchmark iba a 1.65x de C. Ahora va a 1.00x con el `-O2` de
  siempre. Cambia el C de todos los programas, igual en los dos
  compiladores; los archivos de C de un `externo` no se ven afectados.

### Añadido

- Sección FORMAS en la suite: cada forma de guardar un tipo dentro de otro
  —siete hojas, cinco envolturas, una o dos de hondo, en uno, dos o tres
  archivos—, 588 programas con los dos compiladores y bajo ASan. Encontró
  todo lo anterior.
- P14: un valor que se mueve por algunos caminos y por otros no se
  libera exactamente una vez, por cualquier camino (`if` con `continue`,
  `match` con guardas, `break` en un bucle anidado). El generador de C
  lleva una bandera `ss_vivo_x` para esos casos; ASan la comprueba.

- Dos notas para los tests que vengan:
  - Python no conoce los rangos `0..n` (son azúcar de `tcodec`); los
    programas que compila de oráculo recorren con `for i en [0, 1, 2]`.
  - El comprobador no modela que `continue` sale del camino: mover una
    variable en un brazo de `match` que termina en `continue` y usarla
    después del `match` lo rechaza, aunque el flujo nunca llegue ahí.
    Queda como límite conocido.

## 1.0.0-rc1 — 2026-09-28, candidata local

La primera candidata a 1.0. Recoge todo lo que se trabajó como 0.9.0, que no
llegó a publicarse. Está etiquetada en local (`v1.0.0-rc1`); falta la CI en
otras máquinas antes de publicarla, y `docs/COMPATIBILIDAD.md` sigue siendo
una propuesta.

Antes de cerrarla: 1.000 programas de propiedades (27.605 comprobaciones) y
una hora de fuzzing (43.112 mutantes), sin fallos.

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

### Especificación

- **Ya no es un borrador de v0**: `docs/ESPECIFICACION.md` es la de 1.0.
  Gramática completa sacada del parser, con un programa de muestra que usa
  cada producción; la parte léxica entera (comentarios, números, cadenas y
  escapes, palabras reservadas, símbolos); un índice de las 42 funciones
  internas; y *Lo que Tcode 1.0 no tiene*, cada cosa comprobada.
- Corregido lo que ya no era cierto: los mapas guardan cualquier valor que
  se pueda guardar salvo `view` y `&T`, y se borran; las clausuras existen;
  los mensajes citados son los de ahora.
- La sección ESPECIFICACION de la suite compila y corre la muestra, y
  exige que el índice nombre exactamente las internas de `tcodec`.

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
- El formateador separaba `&mut Par<A, B>` y `mut Vector<T>`, escribía
  `como ? u8` y cambiaba `1_000` por `1000`.
- `anadir` y `ordenar` por un `&mut lista<T>` de `obtener_mut` se
  rechazaban.
- `tcodec` no compilaba en macOS: `_XOPEN_SOURCE` escondía `mkdtemp`. Lo
  encontró la CI.
- `300 como u8` compilaba y paraba el programa al correr; es una cuenta de
  números escritos y ahora es un error de compilación, como `let x: u8 =
  256;`.
- Una lista declarada sólo dentro de un `for` o de un brazo de `match` no
  se declaraba en el C: Python escribía C que no compilaba y `tcodec` se
  negaba.
- `let x: &str = xs[0];` usado donde se pide una vista: el generador de
  Python escribía `ss_view((*x))`, que C rechaza, y el de `tcodec` se
  negaba a escribir la expresión. Ahora los dos emiten `ss_view(x)`,
  donde `x` ya es el `const SafeString *`. Un `&str` como variable
  local no había llegado al generador en ningún test; lo encontró el
  generador de préstamos que se estaba añadiendo para la rc2.

### El compilador de Python

- **Congelado de verdad.** Hasta aquí recibió lo mismo que `tcodec`; desde
  esta versión sólo recibe arreglos de corrección. Lo que sabe está guardado en
  `tests/python_congelado.json` y la sección CONGELADO falla si cambia. Lo
  nuevo del lenguaje va sólo a `tcodec` y se prueba con oráculos que no son
  Python. Se retira después de 1.0.

### Herramientas

- `make instalar` / `make desinstalar` (`PREFIJO`, `DESTDIR`).
- `make paquete` / `make probar-paquete`: el `.tar.gz` de una versión,
  reproducible, que se construye sin Python; `make version NUEVA=...`; el
  procedimiento en `docs/VERSIONES.md`.
- `make compiladores`: gcc y clang, sin avisos y con punto fijo.
- `make fuzz` y `tests/fuzz.py`: fuzzing del código real, con los hallazgos
  guardados como regresión.
- `make bench-comprobar`: medidas con límites de regresión.
- Sección REGLAS (`tests/reglas.py`): el oráculo de rechazo que no es un
  compilador. 44 reglas en pares mínimos —propiedad, préstamos, tipos,
  fallos, genéricas, clausuras, `como`, bloques, enums, structs— en siete
  contextos: 270 pares.
- `docs/PLATAFORMAS.md` y `docs/COMPATIBILIDAD.md`.
- `docs/AUDITORIA.md`: qué se promete, la base de confianza, dónde vive cada
  invariante, cómo se prueba, lo conservador y por dónde empezar.
- `make ddc` y `tests/ddc.py`: compilación doble diversa. La semilla y el
  compilador de Python, sin ella, construyen el mismo `tcodec`; corre en
  `make check`.
- La versión portable de la aritmética comprobada (sin
  `__builtin_*_overflow`) no la ejecutaba nada: P11 corre cada programa
  también con `-DSS_LANG_SIN_BUILTINS`.

## 0.1.0

La primera versión con número: `tcodec` autoalojado, construido desde su
semilla sin Python.
