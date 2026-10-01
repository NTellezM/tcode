# tree-sitter-tcode

Gramática de [tree-sitter](https://tree-sitter.github.io) para Tcode. Es un
espejo del parser del compilador (`ejemplos/lexer/lib/sintaxis.t`): las reglas
y los nombres de nodo son los que el compilador ya usa (`nombre_de_clase`).

## Generar y probar

```sh
npm install                 # trae tree-sitter-cli
npx tree-sitter generate    # src/parser.c desde grammar.js
npx tree-sitter test        # el corpus en test/corpus/
```

## Probar contra el compilador real

```sh
npx tree-sitter parse ../../ejemplos/compilador/tcodec.t
```

Todo el compilador, el lexer, `std/` y `programas/` parsean sin errores ni
nodos `MISSING`.

## Qué hay

- `grammar.js` — la gramática (el DSL de tree-sitter).
- `queries/highlights.scm` — resaltado de sintaxis.
- `test/corpus/` — casos de prueba con su árbol esperado.
- `src/` — el parser C generado, listo para consumir.

## Limitaciones conocidas

- `como` y `bloque` son palabras *de contexto* en Tcode (el lexer las trata
  como identificadores); aquí se lexan como palabras clave, así que un
  programa que las use como nombre de variable se resaltará raro. Es un
  caso poco común.
- El `bloque<T>` de los tipos es indistinguible de un genérico `Par<A, B>`:
  ambos son `ident <...>`. Se resuelve igual que en el compilador.
