# Rendimiento del compilador

Medido con `make bench-comprobar`, que calibra la máquina y expresa el tiempo
en «unidades» (límites en `bench/limites.json`). La cifra es `tcodec`
escribiendo su propio C.

- **Base**: 1,58 s = **11,23 unidades** (límite 11,9, ~6 % de margen).

## El perfil

`gprof` sobre el compilador compilándose a sí mismo. El compilador está
repartido: cargador 23,6 %, comprobador 22,8 %, generador 21,7 %. El coste
hoja dominante es el **churn de cadenas**:

| función | % self | llamadas | qué es |
|---|---:|---:|---|
| `ss_clone` | ~12 % | 10,5 M | `nuevo`/`copiar` de `str` |
| `ss_append_len` | ~11 % | 22,9 M | `empujar` a `str` |
| `ss_grow` | ~4,5 % | 22,9 M | crecer el buffer |
| `ss_free_fn` | ~3,7 % | 19,6 M | liberar |
| `ss_lang_rebanar_` | ~3 % | 15,1 M | `rebanar` |
| `buscar_desde` | ~6 % | 1,6 M | búsqueda lineal de subcadena |
| `es_de_nombre` | ~3 % | 7 M | carácter de identificador (ya óptimo) |
| `ss_copia_Nodo` | ~3 % | 680 K | copia profunda del AST |
| `ss_mapa_poner_mapa_str_usize` | ~3 % | 220 K | insertar en mapa |

El churn de cadenas (clone + append + grow + rebanar + free) suma **~33 %**.

Los orígenes de `ss_clone` son las **copias profundas** de las estructuras del
compilador: `ss_copia_Tipo` (3,3 M), `ss_copia_lista_str` (1,6 M),
`ss_copia_Nodo` (680 K), `ss_copia_mapa_str_usize` (800 K), además de
`escribir_tipo` (572 K). Los de `ss_append_len` son el lexer
(`recoger_tras`) y el generador construyendo el C a trozos.

## Lo que se intentó (y por qué se paró)

**1. Migrar los helpers `str` → `&Tipo`** (el round-trip `escribir_tipo`).
Revertido: `t.args[0]` (indexar la lista) **copia** el árbol, no lo presta, y
`Tipo` no es copiable. Para `sin_prestamo`/`encaja`, sustituir el
`escribir_tipo` (1 reserva) por una copia profunda (2–4 reservas) es peor.
Solo los predicados puros (`es_tipo_entero`, `es_decimal`…) migran bien, y se
llaman con `T.escribir_tipo` en pocos sitios: el ahorro es marginal.

**2. Quitar la búsqueda O(n·m) de `contiene_nombre`** (resolución de nombres
C). Se sustituyó por una sola pasada con `apuntar_nombres` + mapa. Correcto
(el punto fijo salió byte a byte) pero **empate**: el mapa por función y las
copias de `poner` compensan el ahorro de búsqueda. Revertido.

## Conclusión

El camino caliente ya es `str` + `forma_de` (la regla de `TIPOS.md`) y está
cerca de su óptimo **dado el diseño actual**. Los ahorros puntuales que
existen (~1–3 % cada uno) están por debajo del ruido de medición (~±3 %).

El siguiente salto real es **migrar el churn de cadenas a vistas/prestamos**:
`vista`/`&str` en vez de `str` propio donde el resultado solo se lee, y
construir el C de una vez en vez de `empujar` a trozos. Es un refactor amplio
de todo el compilador, no un ajuste puntual.

Cada paso se mide con `make bench-comprobar` y se valida con `make check`
(punto fijo + suite), que es la red de seguridad.

## Progreso de la migración

La unidad de medida fiable es el **perfil** (`gprof`), que cuenta las llamadas
de forma determinista; el tiempo de pared del `bench` tiene ±3 % de ruido y
solo sirve para confirmar el efecto acumulado.

| commit | qué se quitó | `ss_copia_Tipo` |
|---|---|---:|
| base | — | 1,67 M |
| `2a94738` | `escribir_de_mapa`: escribir el préstamo sin copiar | 1,39 M |
| `4bdb8ba` | `escribir_de_mapa_tipos`: lo mismo para `lista<Tipo>` | 1,28 M |

Lo que queda, en dos frentes:

- **La instanciación de genéricas** (`preparar_instancias`) es el mayor foco:
  copia `ss_copia_lista_str` 1,67 M y `ss_copia_mapa_str_usize` 802 K. Son
  copias **inherentes**: `resolver_reg`/`descubrir` mutan las listas
  (`st_tipos`) mientras iteran sus elementos, y el comprobador de préstamos
  exige iterar una copia. No se puede quitar con un ajuste.
- **El parser** (`preparar_con_error`) copia `ss_copia_Simbolo` 362 K,
  `ss_copia_Funcion` 387 K, `ss_copia_Token` 355 K al construir el AST:
  también inherente al valor por copia.

Lo que queda de «ajuste puntual» ya está hecho. Lo demás pide cambiar la
representación (listas por préstamos, o `Tipo`/`Nodo` copiables), que es un
refactor de otro orden, no un ahorro suelto.
