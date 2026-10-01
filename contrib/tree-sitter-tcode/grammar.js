// Árbol de sintaxis de Tcode para tree-sitter.
//
// Es un espejo de `ejemplos/lexer/lib/sintaxis.t`: las reglas y los nombres
// de nodo son los que el compilador ya usa (`nombre_de_clase`). Los operadores
// quedan anónimos y se resaltan por su texto en `queries/highlights.scm`.

module.exports = grammar({
  name: 'tcode',

  extras: $ => [
    /\s/,
    $.comentario,
  ],

  word: $ => $.ident,

  conflicts: $ => [
    // `ident {` puede ser un literal de struct o una variable seguida de un
    // bloque: el GLR lo decide segun lo que siga dentro de las llaves.
    [$.literal_struct, $.variable],
    // `match` es a la vez sentencia y expresion: la misma rama por dos caminos.
    [$.sentencia, $.primario],
  ],

  rules: {
    // ---------- raíz ----------

    programa: $ => repeat(choice($.usar, $.declaracion)),

    comentario: $ => token(choice(
      seq('//', /[^\n]*/),
      seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/'),
    )),

    usar: $ => seq(
      'usar', $.cadena, optional(seq('como', field('alias', $.ident))), ';',
    ),

    // ---------- declaraciones ----------

    declaracion: $ => choice($.struct, $.enum, $.externo, $.fn),

    struct: $ => seq(
      'struct', field('nombre', $.ident), optional($.tipo_params),
      '{', repeat(seq($.campo_def, optional(','))), '}',
    ),

    campo_def: $ => seq(field('nombre', $.ident), ':', $._tipo),

    enum: $ => seq(
      'enum', field('nombre', $.ident),
      '{', repeat(seq($.variante, optional(','))), '}',
    ),

    variante: $ => seq(
      field('nombre', $.ident),
      optional(seq('(', repeat(seq($._tipo, optional(','))), ')')),
    ),

    externo: $ => seq(
      'externo', $.cadena, '{', repeat($.fn_externa), '}',
    ),

    fn_externa: $ => seq(
      'fn', field('nombre', $.ident), $.parametros,
      optional($.retorno_tipo), ';',
    ),

    fn: $ => seq(
      'fn', field('nombre', $.ident), optional($.tipo_params),
      $.parametros, optional($.retorno_tipo), optional('!'),
      $.bloque,
    ),

    tipo_params: $ => seq('<', repeat(seq($.tipo_param, optional(','))), '>'),

    tipo_param: $ => seq(
      field('nombre', $.ident), optional(seq(':', $.restriccion)),
    ),

    restriccion: $ => $.ident,

    parametros: $ => seq('(', repeat(seq($.param, optional(','))), ')'),

    param: $ => seq(
      field('nombre', $.ident), ':',
      optional($.marca),
      $._tipo,
    ),

    // El `&`/`mut` del parámetro gana sobre el `&` del tipo: `x: &T` es
    // marca `&` + tipo `T`, como lo lee el compilador.
    marca: $ => prec(1, choice('mut', '&', seq('&', 'mut'))),

    retorno_tipo: $ => seq('->', $._tipo),

    // ---------- tipos ----------

    _tipo: $ => choice(
      $.tipo_prestado,
      $.tipo_funcion,
      $.tipo_arreglo,
      $.tipo_contenedor,
      $.tipo_primitivo,
      $.tipo_simple,
    ),

    // Los tipos del lenguaje: palabras reservadas, no identificadores.
    tipo_primitivo: $ => choice(
      'str', 'view', 'usize', 'u8', 'u16', 'u32', 'u64',
      'i8', 'i16', 'i32', 'i64', 'f32', 'f64', 'bool',
    ),

    tipo_prestado: $ => seq('&', optional('mut'), $._tipo),

    tipo_funcion: $ => prec.right(seq(
      'fn', '(', repeat(seq($._tipo, optional(','))), ')',
      optional(seq('->', $._tipo)),
    )),

    tipo_arreglo: $ => seq('[', $._tipo, ';', $.entero, ']'),

    // `mapa<clave, valor>` y `lista<tipo>`: son palabras reservadas.
    tipo_contenedor: $ => seq(
      choice('mapa', 'lista'),
      '<', repeat1(seq($._tipo, optional(','))), '>',
    ),

    // Un nombre solo, calificado, o aplicado: `str`, `par.Par<...>`,
    // `bloque<T>`, `Par<A, B>`.
    tipo_simple: $ => choice(
      prec(1, seq($.ident, optional(seq('.', $.ident)),
                  '<', repeat1(seq($._tipo, optional(','))), '>')),
      seq($.ident, optional(seq('.', $.ident))),
    ),

    // ---------- sentencias ----------

    bloque: $ => seq('{', repeat($.sentencia), '}'),

    sentencia: $ => choice(
      $.declaracion_local,
      $.si,
      $.mientras,
      $.para,
      $.match,
      $.romper,
      $.continuar,
      $.retorno,
      $.falla,
      $.asignacion,
      $.expresion_suelta,
    ),

    declaracion_local: $ => seq(
      choice('let', 'var'), field('nombre', $.ident),
      optional(seq(':', $._tipo)),
      '=', $.expresion, ';',
    ),

    si: $ => prec.right(seq(
      'if', $.expresion, $.bloque,
      optional($.rama_else),
    )),

    rama_else: $ => seq('else', choice($.bloque, $.si)),

    mientras: $ => seq('while', $.expresion, $.bloque),

    para: $ => seq(
      'for', $.ident, optional(seq(',', $.ident)), 'en',
      choice($.rango, $.expresion),
      $.bloque,
    ),

    rango: $ => seq($.expresion, '..', $.expresion),

    romper: $ => seq('break', ';'),
    continuar: $ => seq('continue', ';'),

    retorno: $ => seq('return', optional($.expresion), ';'),

    falla: $ => seq('falla', $.cadena, ';'),

    asignacion: $ => seq($.expresion, '=', $.expresion, ';'),

    expresion_suelta: $ => seq($.expresion, ';'),

    // ---------- expresiones, de menor a mayor precedencia ----------

    expresion: $ => choice(
      $.sino,
      $._desplazar_o_mas,
    ),

    // `a sino b` ata menos que todo.
    sino: $ => prec.left(1, seq($._desplazar_o_mas, 'sino', $._desplazar_o_mas)),

    _desplazar_o_mas: $ => prec.left(2, seq(
      $._o, repeat(seq('||', $._o)),
    )),

    _o: $ => prec.left(3, seq(
      $._y, repeat(seq('&&', $._y)),
    )),

    _y: $ => prec.left(4, seq(
      $._igualdad, repeat(seq(choice('==', '!='), $._igualdad)),
    )),

    _igualdad: $ => prec.left(5, seq(
      $._orden, repeat(seq(choice('<', '<=', '>', '>='), $._orden)),
    )),

    _orden: $ => prec.left(6, seq(
      $._bor, repeat(seq('|', $._bor)),
    )),

    _bor: $ => prec.left(7, seq(
      $._bxor, repeat(seq('^', $._bxor)),
    )),

    _bxor: $ => prec.left(8, seq(
      $._band, repeat(seq('&', $._band)),
    )),

    _band: $ => prec.left(9, seq(
      $._desplazar, repeat(seq(choice('<<', '>>'), $._desplazar)),
    )),

    _desplazar: $ => prec.left(10, seq(
      $._suma, repeat(seq(choice('+', '-', '+?', '-?'), $._suma)),
    )),

    _suma: $ => prec.left(11, seq(
      $._multiplicar, repeat(seq(choice('*', '/', '%', '*?', '/?'), $._multiplicar)),
    )),

    _multiplicar: $ => $._conversion,

    // `x como u8`, `x como? u8`: ata más que cualquier binario.
    _conversion: $ => prec.left(12, seq(
      $._unario, repeat(seq('como', optional('?'), $._tipo)),
    )),

    _unario: $ => choice(
      seq('try', $._unario),
      seq(choice('!', '-', '~'), $._unario),
      $._postfijo,
    ),

    _postfijo: $ => prec.left(13, seq(
      $.primario,
      repeat(choice(
        $.metodo,
        $.campo,
        $.indice,
      )),
    )),

    // `xs.anadir(v)`: el metodo gana sobre el campo suelto.
    metodo: $ => prec(1, seq('.', field('campo', $.ident), $.argumentos)),

    campo: $ => seq('.', field('campo', $.ident)),

    indice: $ => seq('[', $.expresion, ']'),

    primario: $ => choice(
      $.cierre,
      $.si_expr,
      $.match,
      $.interpolada,
      $.cadena,
      $.entero,
      $.decimal,
      $.booleano,
      $.literal_lista,
      $.llamada,
      $.literal_struct,
      $.variable,
      seq('(', $.expresion, ')'),
    ),

    cierre: $ => seq(
      'fn',
      optional(seq('[', repeat(seq($.captura, optional(','))), ']')),
      $.parametros, optional($.retorno_tipo), optional('!'),
      $.bloque,
    ),

    captura: $ => seq(optional('mut'), $.ident),

    // `if c { a } else { b }` como valor: cada rama es una expresión suelta.
    si_expr: $ => seq(
      'if', $.expresion, '{', $.expresion, '}',
      'else', '{', $.expresion, '}',
    ),

    match: $ => seq(
      'match', $.expresion, '{',
      repeat(seq($.brazo, optional(','))),
      '}',
    ),

    brazo: $ => seq(
      $.patron, repeat(seq('|', $.patron)),
      optional($.guarda),
      '->',
      choice($.bloque, $.expresion),
    ),

    guarda: $ => seq('if', $.expresion),

    patron: $ => choice(
      '_',
      seq($.ident, '.', $.ident, optional(seq('(', repeat(seq($.posicion_patron, optional(','))), ')'))),
    ),

    posicion_patron: $ => choice(
      $.patron,
      $.entero,
      $.decimal,
      $.cadena,
      $.booleano,
      $.ident,
    ),

    booleano: $ => choice('true', 'false'),

    entero: $ => /[0-9][0-9_]*/,

    decimal: $ => /[0-9][0-9_]*\.[0-9][0-9_]*([eE][+-]?[0-9]+)?|[0-9][0-9_]*[eE][+-]?[0-9]+/,

    cadena: $ => /"(?:[^"\\\n]|\\.)*"/,

    interpolada: $ => /\$"(?:[^"\\]|\\.|\{[^{}]*\})*"/,

    literal_lista: $ => seq('[', repeat(seq($.expresion, optional(','))), ']'),

    llamada: $ => prec(1, seq($.ident, $.argumentos)),

    argumentos: $ => seq('(', repeat(seq($.expresion, optional(','))), ')'),

    // `Punto { x: 1 }` o `G.Sitio { archivo: ... }` (calificado).
    literal_struct: $ => seq(
      $.ident, optional(seq('.', $.ident)),
      '{', repeat(seq($.campo_inicial, optional(','))), '}',
    ),

    campo_inicial: $ => seq(field('nombre', $.ident), ':', $.expresion),

    variable: $ => $.ident,

    ident: $ => /[\p{XID_Start}_][\p{XID_Continue}]*/,
  },
});
