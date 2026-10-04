# Extensión de VS Code para Tcode

Trae, en un solo sitio: **resaltado** (gramática TextMate), el **icono** de
`.t`, el **completado** y el **contorno de símbolos**, y el **LSP**
(diagnósticos, formato e ir a la definición).

## Instalar

La extensión lleva dentro el servidor y el árbol de sintaxis
(`server/server.js` y `server/tree-sitter-tcode.wasm`), así que basta con el
`.vsix`:

```sh
code --install-extension tcode-0.2.0.vsix
```

Recarga VS Code. Los archivos `.t` se resaltan solos y el LSP arranca si
`tcodec` está en el `PATH` (o lo configuras en `tcode.lsp.tcodec`).

## Qué necesita cada pieza

| pieza | qué necesita |
|---|---|
| resaltado, icono, completado y contorno | nada (va todo incluido) |
| diagnósticos y formato | `tcodec` en el PATH |
| ir a la definición | nada (va incluido el árbol de sintaxis) |

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
