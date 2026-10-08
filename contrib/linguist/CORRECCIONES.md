# Correcciones al material de partida (2026-10-08)

Todo esto esta **medido**, no supuesto. El paquete completo y verificable esta en
`/home/nt/Proyectos/tcode-linguist/` (con `verify/run_all.sh --full` y
`verify/RESULTS.md`).

1. **El `language_id` propuesto no pasa el CI de Linguist.** `403937577` era un
   numero elegido a mano. `test/test_language_id.rb` exige que el id de un lenguaje
   nuevo sea `SHA256.hexdigest(nombre).to_i(16) % (2**30 - 1)`. Para el nombre
   **`Tcode`** el id correcto es **`417935118`** (comprobado contra el
   `languages.yml` de Linguist 9.7.0: 836 lenguajes, 836 ids unicos, y ese no
   aparece).
2. **El nombre del proyecto es `Tcode`, no `TCode`.** El repositorio dice `Tcode`
   en 355 sitios y `TCode` en 10, casi todos aqui. El nombre decide el id, asi que
   importa: `Tcode` -> `417935118`; `TCode` -> `169691322`. La entrada de
   `languages.yml` y la carpeta de muestras tienen que decir **lo mismo**.
3. **La heuristica que proponia este README no sirve, y esta medido.** Con la
   regla de Tcode primero se lleva 127 de 127 ficheros de test de Perl (y 9/9 de
   Raku, 3/3 de Terra, 4/4 de Turing); con ella ultima, 6 de 127 y el test minimo
   de Perl. La que va en `heuristics.yml` da **0 falsos positivos** en los cuatro
   (110/110 TCode, 0/133 Perl). Y tiene que ir **primero**, no ultima: el patron de
   flecha de Perl casa dentro de una cadena interpolada de Tcode
   (`let origen = $"p->dato.v_{vn}._{q}";`, `tcodec.t:1821`).
4. **En `heuristics.yml` hay que SUSTITUIR el bloque `.t`**, no anadir uno nuevo.
   Y la gramatica tiene que vivir en `syntaxes/` o `grammars/`: el cargador de
   Linguist solo acepta esos directorios (comprobado con su compilador real: en la
   raiz aborta con "contains no grammar files").

**Lo que falta y no se puede comprobar desde aqui**: el requisito de uso de
Linguist (ficheros indexados por extension en el ultimo ano, sin contar forks).
Es el motivo mas probable de rechazo y hace falta la busqueda de GitHub.
