// lib/clase.t — de que clase es cada nodo del arbol.
//
// Un nodo es una declaracion, una sentencia o una expresion, y cada
// capa del compilador mira cual antes de nada. Como enum, un `match`
// sobre ella tiene que cubrirlas todas, y compararla es comparar un
// numero. La primera es la de un nodo a ceros.

enum Clase {
    Vacio,
    Programa,
    Usar,
    Alias,
    Fn,
    Param,
    RetornoTipo,
    Falible,
    TipoParam,
    Restriccion,
    Struct,
    CampoDef,
    Enum,
    Variante,
    Lleva,
    Externo,
    Externa,
    Bloque,
    Declaracion,
    Asignacion,
    Expresion,
    Retorno,
    Falla,
    Si,
    Sino,
    Mientras,
    Para,
    Rango,
    Romper,
    Continuar,
    Match,
    Brazo,
    Guarda,
    Patron,
    Captura,
    Atrapa,
    Binaria,
    Unaria,
    Conversion,
    Try,
    SiExpr,
    Llamada,
    Campo,
    Indice,
    Variable,
    Entero,
    Decimal,
    Cadena,
    Interpolada,
    Booleano,
    Literal,
    LiteralLista,
    LiteralStruct,
    EnumLit,
    Cierre,
    Mut,
}

// Como se llama en los mensajes y en lo que muestran las herramientas: lo
// que se escribia antes de que hubiera enum. El `match` las cubre todas, asi
// que una clase nueva sin nombre no compila.
fn nombre_de_clase(c: Clase) -> view {
    var nombre: view = "";
    match c {
        Clase.Vacio -> { nombre = "vacio"; }
        Clase.Programa -> { nombre = "programa"; }
        Clase.Usar -> { nombre = "usar"; }
        Clase.Alias -> { nombre = "alias"; }
        Clase.Fn -> { nombre = "fn"; }
        Clase.Param -> { nombre = "param"; }
        Clase.RetornoTipo -> { nombre = "retorno_tipo"; }
        Clase.Falible -> { nombre = "falible"; }
        Clase.TipoParam -> { nombre = "tipo_param"; }
        Clase.Restriccion -> { nombre = "restriccion"; }
        Clase.Struct -> { nombre = "struct"; }
        Clase.CampoDef -> { nombre = "campo_def"; }
        Clase.Enum -> { nombre = "enum"; }
        Clase.Variante -> { nombre = "variante"; }
        Clase.Lleva -> { nombre = "lleva"; }
        Clase.Externo -> { nombre = "externo"; }
        Clase.Externa -> { nombre = "externa"; }
        Clase.Bloque -> { nombre = "bloque"; }
        Clase.Declaracion -> { nombre = "declaracion"; }
        Clase.Asignacion -> { nombre = "asignacion"; }
        Clase.Expresion -> { nombre = "expresion"; }
        Clase.Retorno -> { nombre = "retorno"; }
        Clase.Falla -> { nombre = "falla"; }
        Clase.Si -> { nombre = "si"; }
        Clase.Sino -> { nombre = "sino"; }
        Clase.Mientras -> { nombre = "mientras"; }
        Clase.Para -> { nombre = "para"; }
        Clase.Rango -> { nombre = "rango"; }
        Clase.Romper -> { nombre = "romper"; }
        Clase.Continuar -> { nombre = "continuar"; }
        Clase.Match -> { nombre = "match"; }
        Clase.Brazo -> { nombre = "brazo"; }
        Clase.Guarda -> { nombre = "guarda"; }
        Clase.Patron -> { nombre = "patron"; }
        Clase.Captura -> { nombre = "captura"; }
        Clase.Atrapa -> { nombre = "atrapa"; }
        Clase.Binaria -> { nombre = "binaria"; }
        Clase.Unaria -> { nombre = "unaria"; }
        Clase.Conversion -> { nombre = "conversion"; }
        Clase.Try -> { nombre = "try"; }
        Clase.SiExpr -> { nombre = "si_expr"; }
        Clase.Llamada -> { nombre = "llamada"; }
        Clase.Campo -> { nombre = "campo"; }
        Clase.Indice -> { nombre = "indice"; }
        Clase.Variable -> { nombre = "variable"; }
        Clase.Entero -> { nombre = "entero"; }
        Clase.Decimal -> { nombre = "decimal"; }
        Clase.Cadena -> { nombre = "cadena"; }
        Clase.Interpolada -> { nombre = "interpolada"; }
        Clase.Booleano -> { nombre = "booleano"; }
        Clase.Literal -> { nombre = "literal"; }
        Clase.LiteralLista -> { nombre = "literal_lista"; }
        Clase.LiteralStruct -> { nombre = "literal_struct"; }
        Clase.EnumLit -> { nombre = "enum_lit"; }
        Clase.Cierre -> { nombre = "cierre"; }
        Clase.Mut -> { nombre = "mut"; }
    }
    return nombre;
}
