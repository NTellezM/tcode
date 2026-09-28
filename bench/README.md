# Medidas

```
$ make bench              # las tablas
$ make bench-comprobar    # falla si algo pasa de bench/limites.json
$ python3 bench/medir.py --fijar   # pone los limites: lo medido x 1,25
```

Mide el C que escribe `tcodec`.

## Límites de regresión

Los segundos dependen de la máquina; las razones mucho menos. Por eso
`bench/limites.json` guarda razones:

- **Tcode / C** en cada caso con C a mano, con `-O2` y con `-O3`.
- **El compilador**: lo que tarda `tcodec` en escribir su propio C, en
  *unidades* — el tiempo del caso `aritmetica` en C a mano con `-O2`, medido
  en la misma máquina y en la misma pasada.

`make bench-comprobar` corre en la CI completa. Si un cambio hace el código
generado o el compilador más lento que su límite, falla; si la mejora es
de verdad, `--fijar` pone los límites nuevos y el cambio lo dice.

Compila cada caso tres veces y toma el mejor de cinco corridas:

| columna | qué es |
|---|---|
| **C a mano** | el mismo programa escrito en C, sin comprobaciones |
| **Tcode** | lo que produce el compilador |
| **Tcode\*** | el mismo C generado, con las comprobaciones anuladas a mano |

La tercera columna **no es un modo del lenguaje**. Existe sólo para aislar
cuánto cuestan las comprobaciones sobre código por lo demás idéntico. En
todos los casos iguala a la primera, que es la señal de que el resto de lo
que genera Tcode no cuesta nada.

## Resultados (2 vCPU, gcc 13, `-O3`)

| caso | C a mano | Tcode | Tcode\* | Tcode / C |
|---|---|---|---|---|
| aritmetica | 0.140s | 0.158s | 0.140s | **1.13x** |
| arreglo | 0.266s | 0.265s | 0.265s | **1.00x** |
| cadenas | 0.021s | 0.020s | 0.021s | **0.98x** |
| structs | 0.160s | 0.169s | 0.160s | **1.05x** |

Lo que se paga es la aritmética comprobada, y sólo cuando el bucle está
dominado por aritmética. Todo lo demás —índices comprobados, préstamos,
liberación automática, arreglos envueltos en struct, cadenas— sale a 1.00x.

Los índices comprobados no cuestan nada medible: el salto lo predice siempre
bien el procesador y cabe en huecos que ya estaban libres.

## `-O2` contra `-O3`

| caso | Tcode/C con `-O2` | Tcode/C con `-O3` |
|---|---|---|
| structs | 1.65x | **1.05x** |

La diferencia no son las comprobaciones: es que el cuerpo comprobado crece y
en `-O2` deja de caber en el presupuesto de integración de gcc. En el
desensamblado se ve directamente —`call dist2` en una versión, el cuerpo
integrado en la otra—. `-O3` lo recupera.

Por eso `tcode` acepta `-O`:

```
tcode programa.t -O3
```

El valor por defecto sigue siendo `-O2`, que es lo que espera quien viene de
C. Si tu programa tiene bucles cerrados con aritmética, prueba `-O3` y mide.

## El compilador

`tcodec` escribe su propio C —unas 20.900 líneas de Tcode más `std/`, 5 MB
de C— en **1,3 s** (gcc 13, `-O1` en la semilla; unas 9 unidades). Lo que
más pesa es copiar textos, listas y nodos (17 %) y buscar símbolos (14 %),
medido con callgrind.
