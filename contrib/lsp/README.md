# tcode-lsp

Servidor [LSP](https://microsoft.github.io/language-server-protocol/) de Tcode.
Da **diagnósticos** (los errores del compilador, como subrayados), **formato** e
**ir a la definición**. No hay un segundo analizador para lo duro: los dos
primeros salen del propio `tcodec`; el «ir a la definición» es sintáctico, con
la gramática de tree-sitter (`tree-sitter-tcode.wasm`).

## Requisitos

- `tcodec` compilado (`make` en la raíz del repositorio).
- Node 18 o más.

## Instalar y ejecutar

```sh
cd contrib/lsp
npm install
```

El servidor lee JSON-RPC de la entrada y escribe a la salida. Un cliente (VS
Code, Neovim, Helix…) lo lanza así:

```sh
node server.js --stdio
```

## Configuración

Por `initializationOptions` o variables de entorno:

| opción | variable | por defecto | qué es |
|---|---|---|---|
| `tcodec` | `TCODEC` | `tcodec` (del PATH) | el binario del compilador |
| `raiz` | `TCODE_RAIZ` | el directorio de trabajo | la raíz del proyecto, donde está `std/` |

El compilador da `error: archivo:linea: mensaje` (sin columna), así que el
subrayado cubre la línea entera.

## Prueba rápida, sin editor

```sh
node contrib/lsp/server.js --stdio <<'EOF'
Content-Length: ...\r\n
...initialize...
EOF
```

## Regenerar la gramática

`tree-sitter-tcode.wasm` es la gramática compilada. Si cambia
`contrib/tree-sitter-tcode/grammar.js`, regenera y copia:

```sh
cd ../tree-sitter-tcode && npx tree-sitter build --wasm
cp tree-sitter-tcode.wasm ../lsp/
```

## Qué hace falta para usarlo de verdad

El servidor es el lado «inteligente»; el editor necesita un cliente que lo
arranque. En `vscode/` hay una extensión mínima que lo hace: copia la carpeta
en `~/.vscode/extensions/` (o ábrela con «Extension Development Host»).
