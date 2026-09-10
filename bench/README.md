# Medidas

```
$ python3 bench/medir.py
```

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

| | |
|---|---|
| frontend de Tcode | ~40.000 líneas/s |
| porcentaje del tiempo total | **0.5%** |

El otro 99.5% es gcc compilando el C generado. Escribir el frontend en
Python no se nota: el cuello de botella es el backend, y es el mismo que
tendría cualquier proyecto de C.
