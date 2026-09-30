# Compatibilidad

> **Propuesta para 1.0.** Esto es lo que Tcode prometerá a partir de 1.0.
> Hasta entonces (0.x), cualquier cosa puede cambiar, y el `CHANGELOG.md`
> lo dice.

Las versiones son `MAYOR.MENOR.PARCHE` y están en `VERSION`; `tcodec
--version` dice la misma.

## Lo que no se rompe dentro de 1.x

**Un programa que compila con 1.x compila con toda 1.y posterior y hace lo
mismo**, con estas excepciones, que no son opcionales:

1. **Agujeros del lenguaje.** Si el compilador aceptaba algo que viola sus
   propias reglas —un uso después de liberar, un préstamo que sobrevive a su
   dueño, una cuenta que no se comprueba—, el arreglo lo rechaza. Así pasó con
   `s = s;` en 0.9. Un programa correcto no se ve afectado.
2. **Lo que la especificación no definía.** Si dos compiladores hacían cosas
   distintas porque nada decía cuál era la buena, se elige una, se escribe en
   `docs/ESPECIFICACION.md` y el `CHANGELOG.md` lo dice. Así pasó con los
   caracteres de un nombre en 0.9.
3. **Palabras reservadas de antemano.** Las palabras `protocolo`,
   `implementa`, `extiende`, `ancla` y `soltar` quedan reservadas en
   1.x aunque todavía no signifiquen nada. Un programa que las use
   como nombre deja de compilar. Se reservan ahora para poder añadir
   anclajes en 1.x sin romper programas después.

Dentro de 1.x no se quita ni se cambia de significado ninguna palabra, ningún
operador, ninguna función interna ni ninguna opción de `tcodec`.



## Lo que sí puede cambiar dentro de 1.x

- **Avisos nuevos.** Un aviso no impide compilar; con
  `--avisos-como-errores` sí, y eso es cosa de quien lo pide.
- **El texto de los errores.** Lo estable es que un error nombra archivo y
  línea, y que el programa no compila. Las palabras pueden mejorar.
- **El C generado.** No es una interfaz: puede cambiar de una versión a otra
  mientras el programa haga lo mismo. Lo que sí se mantiene es que compila sin
  avisos con los compiladores de `docs/PLATAFORMAS.md`.
- **`--explicar` y `--formatear`.** La salida de `--explicar` es para leerla,
  no para procesarla. El formato canónico puede cambiar en una versión
  menor; `--formatear --escribir` lo pone al día.
- **El rendimiento**, dentro de los límites de `bench/limites.json`.

## `std/`

- En 1.x no se quita ninguna función de `std/` ni cambia su firma.
- **Se pueden añadir funciones.** Ojo: un nombre nuevo en un módulo que tu
  programa usa con `usar "std/texto";` choca con uno tuyo del mismo nombre
  ("llega de dos sitios"). Para no depender de eso, usa los módulos de `std`
  con alias: `usar "std/texto" como texto;` y `texto.mayusculas(...)`.

## Módulos

La forma de encontrar un módulo (`usar "ruta"`, relativa al archivo, y
`std/` junto al compilador) no cambia en 1.x.

## Lo que marca una versión mayor

Cualquier cambio que haga que un programa correcto deje de compilar, o que
compile y haga otra cosa, fuera de las dos excepciones de arriba.
