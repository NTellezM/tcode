# Registrar TCode en GitHub Linguist

Materiales para que GitHub reconozca TCode (extensión `.t`) en la barra de
lenguajes y en el resaltado de sintaxis. Hoy GitHub confunde `.t` con Perl; hasta
que TCode esté registrado, los proyectos que lo usan marcan los `.t` como
`-linguist-detectable` en su `.gitattributes`.

## Qué hay aquí

- `tcode.tmLanguage.json` — gramática TextMate de TCode: comentarios, cadenas
  (incluidas las interpoladas `$"…"`), números, palabras clave, tipos y
  operadores.
- `languages.yml` — fragmento con la entrada propuesta para Linguist.

## Pasos

1. **Gramática**. Revisa `tcode.tmLanguage.json`. Puedes probarla en local con
   VS Code (generador "New Language Support") o con `vscode-tmgrammar-test`.
2. **Entrada en `languages.yml`**. Añade el bloque a
   `github/linguist` → `lib/linguist/languages.yml`. Elige un `language_id`
   entero que no esté en uso.
3. **Gramática en Linguist**. Linguist resuelve las gramáticas por su
   `tm_scope` (`source.tcode`) desde un repositorio aparte de gramáticas;
   publica la gramática y referencia ese scope en la entrada.
4. **Conflicto de extensión**. `.t` ya lo usa Perl (sus ficheros de test).
   Para que GitHub distinga, añade una heurística en
   `lib/linguist/heuristics.yml`: un fichero TCode suele empezar con `fn `,
   `use `, `#importar `, `struct `, `//` o `var `, mientras que un test Perl
   usa `use Test::More` o `use strict`. Sin heurística, GitHub usará las
   muestras de código para adivinar.
5. **PR**. Sigue la guía oficial "Adding a language" en
   <https://github.com/github-linguist/linguist/blob/main/CONTRIBUTING.md>.

## Fuente de verdad

Las palabras reservadas y los símbolos están en
`ejemplos/lexer/lib/lexico.t` (`es_reservada` y su `analizar`). Si cambian,
actualiza la gramática.
