# Extensión de VS Code para Tcode

Trae, en un solo sitio: **resaltado** (gramática TextMate), el **icono** de
`.t`, y el **LSP** (diagnósticos, formato e ir a la definición).

## Instalar (a mano, mientras no esté en el Marketplace)

La extensión espera el servidor LSP en `../server.js`, así que lo más cómodo es
un enlace al árbol:

```sh
# 1. dependencias del servidor (una vez)
cd contrib/lsp && npm install

# 2. enlaza la extensión donde VS Code la encuentra
ln -s "$PWD/vscode" ~/.vscode/extensions/tcode
```

Recarga VS Code. Los archivos `.t` se resaltan solos y el LSP arranca si
`tcodec` está en el `PATH` (o lo configuras en `tcode.lsp.tcodec`).

## Qué necesita cada pieza

| pieza | qué necesita |
|---|---|
| resaltado | nada (va incluida la gramática) |
| icono | nada (va incluido) |
| diagnósticos / formato | `tcodec` en el PATH |
| ir a la definición | `contrib/lsp/tree-sitter-tcode.wasm` |

## Empaquetar para el Marketplace (pendiente)

Hoy el servidor vive en `../`; para publicar hay que **empaquetar** `server.js`,
`tree-sitter-tcode.wasm` y `node_modules` dentro de la extensión (`vsce package`),
y publicarla. Es el paso «publicar» del peldaño 2.
