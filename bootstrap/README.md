# La semilla

`tcodec.c` es el C que `tcodec` escribe de sí mismo: el compilador entero,
generado, sin tocar a mano. Es lo único que hace falta, además de un
compilador de C, para construir Tcode desde cero:

```
cc -std=c17 -O1 -Iruntime bootstrap/tcodec.c runtime/safestr.c \
   ejemplos/compilador/lib/sistema_tcodec.c -o tcodec0 -lm
TCODE_RAIZ=. ./tcodec0 ejemplos/compilador/tcodec.t -o tcodec
```

Es lo que hace `make`. La semilla no tiene que ser la última versión de
`tcodec`: basta con que sepa compilar el `tcodec.t` de ahora. Cuando
`tcodec.t` quiere usar algo del lenguaje que la semilla aún no conoce, se
pone al día en dos pasos —primero entra la novedad, después `make semilla`—,
y `make semilla` solo la guarda si es un punto fijo: compilada, vuelve a
escribir exactamente el mismo C.
