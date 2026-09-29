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

## Resultados (2 vCPU, gcc 13)

| caso | C a mano | Tcode `-O2` | Tcode/C `-O2` | Tcode/C `-O3` |
|---|---|---|---|---|
| aritmetica | 0.141s | 0.145s | **1.03x** | 1.12x |
| arreglo | 0.266s | 0.265s | **1.00x** | 1.00x |
| cadenas | 0.022s | 0.022s | **1.01x** | 1.02x |
| structs | 0.168s | 0.168s | **1.00x** | 1.04x |

Lo que se paga es la aritmética comprobada, y sólo cuando el bucle está
dominado por aritmética. Todo lo demás —índices comprobados, préstamos,
liberación automática, arreglos envueltos en struct, cadenas— sale a 1.00x.

Los índices comprobados no cuestan nada medible: el salto lo predice siempre
bien el procesador y cabe en huecos que ya estaban libres.

## Por qué las funciones salen `static`

El programa entero es un solo archivo de C, y sus funciones no se llaman
desde fuera. Hasta 1.0.0-rc1 salían con enlace externo, y en `-O2` eso
costaba caro: `structs` iba a **1.65x**. No eran las comprobaciones
—anuladas a mano, el mismo C iba a 1.00x—, sino que el cuerpo comprobado de
`dist2` crecía, gcc tenía que conservar una copia suelta de la función por
si alguien de fuera la llamaba, y dejaba de integrarla: en el desensamblado
había un `call dist2` por vuelta del bucle. Solo `-O3` lo recuperaba.

Con `static`, gcc sabe que nadie más la llama y la integra también en
`-O2`: `structs` pasa a 1.00x sin tocar el nivel. Cada función lleva además
`SS_LANG_QUIZA_SIN_USAR`, porque un programa puede no llamar a alguna y eso
no es un aviso para nadie. Los archivos de C de un `externo` no se ven
afectados: llaman a su sistema, no a funciones de Tcode.

`tcode` sigue aceptando `-O`, pero `-O2`, lo que espera quien viene de C, ya
no deja nada en la mesa:

```
tcode programa.t -O3
```

## El compilador

`tcodec` escribe su propio C —unas 20.900 líneas de Tcode más `std/`, 5 MB
de C— en **1,3 s** (gcc 13, `-O1` en la semilla; unas 9 unidades). Lo que
más pesa es copiar textos, listas y nodos (17 %) y buscar símbolos (14 %),
medido con callgrind.
