# Extensión de VS Code para Tcode

Trae, en un solo sitio: **resaltado** (gramática TextMate), el **icono** de
`.t`, el **completado** (con la biblioteca estándar) y el **contorno de
símbolos**, y el **LSP** (diagnósticos, formato, ir a la definición y la
firma de la función bajo el cursor al pasar por encima).

## La biblioteca estándar sin saberse las rutas

Al escribir `#` sale la lista de módulos de `std/` y el completado inserta la
directiva entera, con el cursor después del punto y coma:

```tcode
#            ->  #importar "texto.t";
```

Dentro de un `#importar "` solo falta el fichero, y dentro de un `use "` la
ruta de `std/`; en los dos se completa:

```tcode
#importar "tex"  ->  #importar "texto.t";
use "std/tex"    ->  use "std/texto";
```

Y un módulo ya importado (con `#importar "texto.t"` o con `use "std/texto"`)
aporta además sus funciones a la lista: `partir`, `unir`, `minusculas`... de
`std/texto`; `compilar`, `buscar`... de `std/regex`; `cuantos`, `trozo`... de
`std/utf8` y compañía.

Detrás de un `modulo.` solo salen las funciones de ese módulo (`texto.` no
ofrece el resto de la biblioteca), y pasar el ratón por encima de una función
enseña su firma entera, con sus tipos.

## La biblioteca, también fuera de un proyecto

Con un fichero suelto, sin carpeta de proyecto abierta y sin `TCODE_RAIZ`, la
raíz se descubre desde el propio `tcodec`: se busca en el `PATH` —o se toma la
ruta que digas en `tcode.lsp.tcodec`—, se siguen sus enlaces y se sube hasta
`runtime/cabecera.inc`. De ahí sale `std/`, así que un `tcodec` instalado basta
para tener diagnósticos y completado en cualquier `.t`, esté donde esté. El
orden completo es: `TCODE_RAIZ`, la carpeta del proyecto y, si no hay ninguna,
esa instalación.

## Instalar

La extensión lleva dentro el servidor y el árbol de sintaxis
(`server/server.js` y `server/tree-sitter-tcode.wasm`), así que basta con el
`.vsix`:

```sh
code --install-extension tcode-0.5.0.vsix
```

Recarga VS Code. Los archivos `.t` se resaltan solos y el LSP arranca si
`tcodec` está en el `PATH` (o lo configuras en `tcode.lsp.tcodec`); con eso ya
encuentra `std/` aunque el fichero esté suelto y no haya proyecto abierto.

## Qué necesita cada pieza

| pieza | qué necesita |
|---|---|
| resaltado, icono, completado y contorno | nada (va todo incluido) |
| diagnósticos y formato | `tcodec` en el PATH |
| ir a la definición y la firma al pasar por encima | nada (va incluido el árbol de sintaxis) |

## Empaquetar

```sh
npm install                    # una vez: las dependencias del servidor
npx @vscode/vsce package
```

El servidor es una **copia** de `contrib/lsp/server.js`: si lo tocas, cópialo
antes de empaquetar (`cp ../server.js server/server.js`), que es lo único que
no se enlaza solo. Lo mismo con el árbol, que sale de
`contrib/tree-sitter-tcode/`:

```sh
cp ../tree-sitter-tcode.wasm server/tree-sitter-tcode.wasm
```
