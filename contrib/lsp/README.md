# tcode-lsp

Servidor [LSP](https://microsoft.github.io/language-server-protocol/) de Tcode.
Da **diagnósticos** (los errores del compilador, como subrayados) y **formato**.
No hay un segundo analizador: los dos salen del propio `tcodec`.

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

## Qué hace falta para usarlo de verdad

El servidor es el lado «inteligente»; el editor necesita un cliente que lo
arranque. En `vscode/` hay una extensión mínima que lo hace: copia la carpeta
en `~/.vscode/extensions/` (o ábrela con «Extension Development Host»).
