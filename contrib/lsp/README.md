# tcode-lsp

Servidor [LSP](https://microsoft.github.io/language-server-protocol/) de Tcode.
Da **diagnósticos** (los errores del compilador, como subrayados), **formato**,
**ir a la definición** y la **firma de la función bajo el cursor** (hover). No
hay un segundo analizador para lo duro: los diagnósticos y el formato salen del
propio `tcodec`; la definición y el hover son sintácticos, con la gramática de
tree-sitter (`tree-sitter-tcode.wasm`), más las tablas de `std/` que lleva
dentro.

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
| `tcodec` | `TCODEC` | `tcodec` (del PATH, y si no junto al proyecto o en `~/.local/bin`) | el binario del compilador |
| `raiz` | `TCODE_RAIZ` | `TCODE_RAIZ`, la raíz del cliente si tiene `std/`, el proyecto del fichero y, si no hay ninguna, la instalación que se descubre desde el binario | la raíz del proyecto, donde está `std/` |

La raíz se descubre igual que en el compilador: se resuelve el binario —en el
`PATH` si va como nombre suelto, y si no junto al proyecto del fichero— y se
sube por sus directorios hasta `runtime/cabecera.inc`. Así un `.t` suelto,
fuera de todo proyecto, encuentra `std/` sin decirle nada.

Una carpeta que no tiene `std/` no se le pasa nunca al compilador: `TCODE_RAIZ`
desactiva su descubrimiento, de modo que imponerle una raíz que no lo es —la
carpeta padre de los proyectos, por ejemplo— convierte un `#importar` correcto
en «no encuentro el modulo». Si no hay ninguna raíz de verdad, se deja que la
descubra el propio compilador. Y si no aparece `tcodec` por ningún lado, se
avisa de eso mismo en vez de dejar el fichero sin diagnósticos.

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
