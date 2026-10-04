# Cómo se publica una versión

Una versión es un commit con su número, su paquete y su etiqueta. Lo que
promete cada número está en [`COMPATIBILIDAD.md`](COMPATIBILIDAD.md).

## Los pasos

1. **El número.** `make version NUEVA=1.0.0-rc1` lo escribe en los dos
   sitios donde vive —`VERSION` y lo que imprime `tcodec --version`— y pone
   la semilla al día, porque cambiar el mensaje cambia el C de `tcodec`. La
   sección SALIDA falla si no dicen lo mismo.
2. **El `CHANGELOG.md`.** La sección de la versión deja de decir *sin
   publicar* y lleva la fecha.
3. **Todo en verde**, en local y en la CI:
   - `make check` —la suite, las propiedades, el fuzzing guardado, las
     cifras del README, el grafo y el lint—;
   - `make compiladores` con los compiladores que haya;
   - `make bench-comprobar`;
   - la CI de la rama: la matriz, macOS y la suite completa.
4. **El commit**, con el árbol limpio.
5. **El paquete.** `make probar-paquete` escribe
   `dist/tcode-X.Y.Z.tar.gz` y su `.sha256`, y lo comprueba: dos paquetes
   del mismo commit son iguales byte a byte, y desde el paquete abierto en
   otro sitio, con un `PATH` sin Python, se construye `tcodec` desde la
   semilla, alcanza su punto fijo, se instala y compila un programa.
6. **La etiqueta**: `git tag -a vX.Y.Z -m "Tcode X.Y.Z"` sobre ese commit, y
   el paquete y su suma publicados junto a ella.

## Qué es reproducible y qué no

El paquete es `git archive` del commit comprimido con `gzip -n`, que no
guarda fechas ni nombres. Con las mismas versiones de `git` y `gzip` da los
mismos bytes; con otras, el `.tar` de dentro es el mismo aunque la
compresión cambie. Por eso la suma que vale es la del paquete publicado.

El compilador que sale del paquete también es reproducible: la semilla es un
punto fijo (`make punto-fijo-cc`), y `make probar-paquete` lo comprueba
entero —construye `tcodec` desde la semilla y alcanza su punto fijo— sin
Python.

## Los números

- `X.Y.Z-rcN`: una candidata. Se publica para que otros la prueben; no
  promete nada que no prometa la versión sin `-rcN`.
- `X.Y.Z`: la versión. Desde `1.0.0`, `COMPATIBILIDAD.md` vale.
