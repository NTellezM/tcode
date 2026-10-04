; Resaltado de Tcode.

; ---------- palabras clave ----------
[
  "fn" "if" "else" "while" "for" "match" "return" "fail" "break" "continue"
  "let" "var" "mut" "try" "sino" "en" "use" "struct" "enum" "externo" "como"
] @keyword

; ---------- tipos primitivos ----------
[
  "str" "view" "usize" "u8" "u16" "u32" "u64" "i8" "i16" "i32" "i64" "f32"
  "f64" "bool" "map" "list"
] @type.builtin

; ---------- literales ----------
[
  "true" "false"
] @boolean

(entero) @number
(decimal) @number.float

(cadena) @string
(interpolada) @string

(comentario) @comment @spell

; ---------- identificadores ----------
(fn nombre: (ident) @function)
(struct nombre: (ident) @type)
(enum nombre: (ident) @type)
(variante nombre: (ident) @constant)
(campo_def nombre: (ident) @property)
(param nombre: (ident) @parameter)
(tipo_param nombre: (ident) @type.parameter)
(declaracion_local nombre: (ident) @variable)
(campo_inicial nombre: (ident) @property)
(captura (ident) @variable)

; usos
(variable) @variable
(llamada (ident) @function)
(metodo campo: (ident) @function.method)
(campo campo: (ident) @property)

; ---------- operadores ----------
[
  "=" "+" "-" "*" "/" "%" "+?" "-?" "*?" "/?"
  "==" "!=" "<" "<=" ">" ">="
  "&&" "||" "!" "&" "|" "^" "<<" ">>" "~"
  "->" ".."
] @operator

; ---------- puntuación ----------
[
  "(" ")" "{" "}" "[" "]" "," ";" ":" "."
] @punctuation.delimiter
