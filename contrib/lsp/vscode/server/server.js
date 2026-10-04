// LSP de Tcode: diagnósticos, formato e ir a la definición.
//
// No hay un segundo analizador para lo duro: los diagnósticos salen del propio
// compilador (`tcodec --solo-comprobar`), que ya escribe
// `error: archivo:linea: mensaje` por la salida de error, y el formato de
// `tcodec --formatear`. El «ir a la definición» es sintáctico: usa la gramática
// de tree-sitter (`tree-sitter-tcode.wasm`) para encontrar el identificador
// bajo el cursor y su declaración. No es consciente de ámbitos ni de tipos;
// eso vendrá cuando el compilador exponga su análisis.
//
// Configuración (por `initializationOptions` o variables de entorno):
//   tcodec  -> ruta del binario (por defecto `tcodec`, o `$TCODEC`)
//   raiz    -> raíz del proyecto, donde está `std/` (por defecto `$TCODE_RAIZ`)

const path = require('path');
const { createConnection, TextDocuments, TextDocumentSyncKind,
        Diagnostic, DiagnosticSeverity, ProposedFeatures, TextEdit,
        CompletionItemKind, SymbolKind } =
        require('vscode-languageserver/node');
const { TextDocument } = require('vscode-languageserver-textdocument');
const { execFile } = require('child_process');
const { fileURLToPath } = require('url');
const { Parser, Language } = require('web-tree-sitter');

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

let tcodec = process.env.TCODEC || 'tcodec';
let raiz = process.env.TCODE_RAIZ || process.cwd();

connection.onInitialize((params) => {
    const opciones = params.initializationOptions || {};
    if (opciones.tcodec) tcodec = opciones.tcodec;
    if (opciones.raiz) raiz = opciones.raiz;
    return {
        capabilities: {
            textDocumentSync: TextDocumentSyncKind.Full,
            documentFormattingProvider: true,
            definitionProvider: true,
            completionProvider: { resolveProvider: false },
            documentSymbolProvider: true,
        },
    };
});

// Un re-chequeo por documento, con un respiro para no compilar a cada tecla.
const pendientes = new Map();

function ruta_de(uri) {
    return fileURLToPath(uri);
}

// `error: archivo:linea: mensaje` -> diagnostico en esa linea entera.
function diagnosticos_de(stderr, documento) {
    const salida = [];
    const lineas = stderr.split('\n');
    for (const linea of lineas) {
        const encajado = linea.match(/^error: (.+?):(\d+): (.*)$/);
        if (!encajado) continue;
        const fila = parseInt(encajado[2], 10) - 1;   // a cero
        if (fila < 0) continue;
        const mensaje = encajado[3];
        // Toda la linea: el compilador no da columna.
        const final_col = documento ? (documento.getText({
            start: { line: fila, character: 0 },
            end: { line: fila + 1, character: 0 },
        }).length) : 0;
        salida.push({
            severity: DiagnosticSeverity.Error,
            range: {
                start: { line: fila, character: 0 },
                end: { line: fila, character: final_col },
            },
            message: mensaje,
            source: 'tcodec',
        });
    }
    return salida;
}

function comprobar(documento) {
    const ruta = ruta_de(documento.uri);
    execFile(tcodec, ['--solo-comprobar', ruta], {
        cwd: raiz,
        env: Object.assign({}, process.env, { TCODE_RAIZ: raiz }),
    }, (_error, _stdout, stderr) => {
        connection.sendDiagnostics({
            uri: documento.uri,
            diagnostics: diagnosticos_de(stderr, documento),
        });
    });
}

function programar(documento) {
    clearTimeout(pendientes.get(documento.uri));
    const temporizador = setTimeout(() => comprobar(documento), 250);
    pendientes.set(documento.uri, temporizador);
}

documents.onDidOpen((evento) => programar(evento.document));
documents.onDidChangeContent((evento) => programar(evento.document));
documents.onDidClose((evento) => {
    clearTimeout(pendientes.get(evento.document.uri));
    connection.sendDiagnostics({ uri: evento.document.uri, diagnostics: [] });
});

connection.onDocumentFormatting((params) => {
    const documento = documents.get(params.textDocument.uri);
    if (!documento) return [];
    const ruta = ruta_de(params.textDocument.uri);
    return new Promise((resolver) => {
        execFile(tcodec, ['--formatear', ruta], {
            cwd: raiz,
            env: Object.assign({}, process.env, { TCODE_RAIZ: raiz }),
        }, (error, stdout) => {
            if (error || stdout === documento.getText()) {
                resolver([]);
                return;
            }
            const entero = {
                start: { line: 0, character: 0 },
                end: { line: documento.lineCount, character: 0 },
            };
            resolver([TextEdit.replace(entero, stdout)]);
        });
    });
});

// ---------- ir a la definición (sintáctico, vía tree-sitter) ----------

// Los nodos que declaran un nombre, con el campo `nombre` de la gramática.
const DECLARACIONES = ['fn', 'struct', 'enum', 'declaracion_local', 'param',
                       'campo_def', 'variante', 'tipo_param', 'captura'];

// La gramática se carga una vez, antes de atender peticiones.
async function gramatica() {
    await Parser.init();
    const ruta = path.join(__dirname, 'tree-sitter-tcode.wasm');
    return await Language.load(ruta);
}

let analizador = null;

connection.onDefinition((params) => {
    const documento = documents.get(params.textDocument.uri);
    if (!documento || !analizador) return null;
    const arbol = analizador.parse(documento.getText());
    const { line, character } = params.position;

    const nodo = arbol.rootNode.descendantForPosition({ row: line, column: character });
    if (!nodo || nodo.type !== 'ident') return null;
    const nombre = nodo.text;

    // Buscar la primera declaración con ese nombre, de arriba hacia abajo.
    for (const tipo of DECLARACIONES) {
        for (const candidato of arbol.rootNode.descendantsOfType(tipo)) {
            const campo = candidato.childForFieldName('nombre');
            if (campo && campo.text === nombre) {
                return [{
                    uri: params.textDocument.uri,
                    range: {
                        start: { line: campo.startPosition.row, character: campo.startPosition.column },
                        end: { line: campo.endPosition.row, character: campo.endPosition.column },
                    },
                }];
            }
        }
    }
    return null;
});

// ---------- completado ----------
//
// Las funciones internas del lenguaje, del índice de `docs/ESPECIFICACION.md`.
// El nombre con su firma va en `label`, lo que devuelve en `detail` y lo que
// hace en `documentation`. Son solo datos: no hay que analizar nada.

const INTERNAS = [
    ['vacio()', 'str', 'un texto vacío, con dueño'],
    ['nuevo(v)', 'str', 'copia un texto a uno con dueño'],
    ['vista(s)', 'view', 'presta `s`'],
    ['texto(x)', 'str', 'un número, bool, view o str como texto'],
    ['empujar(s, x)', '', 'añade al final de un texto'],
    ['empujar_byte(s, b)', '', 'añade un byte a un texto'],
    ['largo(x)', 'usize', 'bytes de un texto, elementos de una lista, arreglo, bloque o mapa'],
    ['byte(v, i)', 'usize', 'el byte `i`, con el índice comprobado'],
    ['rebanar(v, desde, hasta)', 'view', 'un trozo, con los límites comprobados'],
    ['igual(a, b)', 'bool', 'igualdad de dos valores sin partes'],
    ['menor(a, b)', 'bool', 'orden de dos valores sin partes; los textos, byte a byte'],
    ['imprimir(x)', '', 'a la salida'],
    ['imprimir_error(x)', '', 'a la salida de error'],
    ['anadir(xs, x)', '', 'añade al final de una lista; mueve `x` si tiene dueño'],
    ['truncar(xs, n)', '', 'recorta la lista a `n` elementos'],
    ['ordenar(xs)', '', 'ordena la lista en el sitio'],
    ['copiar(x)', 'T', 'copia profunda de cualquier valor'],
    ['reservar(n)', 'bloque<T>', '`n` ranuras, todas a ceros'],
    ['redimensionar(b, n)', '', 'cambia el tamaño del bloque; lo nuevo, a ceros'],
    ['intercambiar(sitio, valor)', 'T', 'deja `valor` en `sitio` y devuelve lo que había'],
    ['poner(m, clave, valor)', '', 'inserta o reemplaza en el mapa'],
    ['obtener(m, clave)', 'V!', 'una copia, una view o un &V, según V'],
    ['obtener_mut(m, clave)', '&mut V!', 'presta para modificar lo guardado'],
    ['tiene(m, clave)', 'bool', 'si la clave está en el mapa'],
    ['quitar(m, clave)', 'bool', 'borra la clave; dice si había algo'],
    ['claves(m)', 'lista<K>', 'copias de las claves, para recorrerlo'],
    ['raiz(x)', 'f32|f64', 'raíz cuadrada'],
    ['piso(x)', 'f32|f64', 'el mayor entero por debajo'],
    ['techo(x)', 'f32|f64', 'el menor entero por encima'],
    ['redondear(x)', 'f32|f64', 'redondea; el .5, lejos de cero'],
    ['absoluto(x)', 'i8|i16|i32|i64', 'valor absoluto de un entero con signo'],
    ['n_argumentos()', 'usize', 'cuántos argumentos, el programa incluido'],
    ['argumento(i)', 'view', 'el argumento `i`, con el índice comprobado'],
    ['leer_archivo(ruta)', 'str!', 'el archivo entero, bytes tal cual'],
    ['leer_parte_archivo(ruta, desde, cuantos)', 'str!', 'como mucho `cuantos` bytes desde `desde`'],
    ['escribir_archivo(ruta, contenido)', '!', 'reemplaza el archivo entero, de una vez'],
    ['leer_linea()', 'str!', 'una línea de la entrada, sin el salto'],
    ['entrada_completa()', 'str!', 'toda la entrada'],
    ['variable_entorno(nombre)', 'str!', 'falla si no está; vacía si está vacía'],
    ['ahora_ms()', 'i64', 'reloj de pared, en milisegundos'],
    ['monotono_ms()', 'i64', 'reloj para medir duraciones'],
    ['azar(n)', 'usize', 'de 0 a n - 1, sin sesgo'],
    ['sembrar(s)', '', 'fija la semilla de `azar`'],
];

const PALABRAS = ['fn', 'if', 'else', 'while', 'for', 'match', 'return', 'falla',
                  'break', 'continue', 'let', 'var', 'mut', 'try', 'sino', 'en',
                  'usar', 'struct', 'enum', 'externo', 'como', 'ancla', 'soltar',
                  'extiende', 'protocolo', 'implementa'];

const TIPOS = ['str', 'view', 'usize', 'u8', 'u16', 'u32', 'u64', 'i8', 'i16',
               'i32', 'i64', 'f32', 'f64', 'bool', 'mapa', 'lista', 'bloque', 'cadena_c'];

const CONSTANTES = ['true', 'false'];

connection.onCompletion(() => {
    const salida = [];
    for (const [firma, devuelve, que] of INTERNAS) {
        salida.push({
            label: firma,
            kind: CompletionItemKind.Function,
            detail: devuelve ? '-> ' + devuelve : '',
            documentation: que,
            insertText: firma.split('(')[0] + '(',
        });
    }
    for (const p of PALABRAS) salida.push({ label: p, kind: CompletionItemKind.Keyword });
    for (const t of TIPOS) salida.push({ label: t, kind: CompletionItemKind.TypeParameter });
    for (const c of CONSTANTES) salida.push({ label: c, kind: CompletionItemKind.Constant });
    return salida;
});

// ---------- el contorno (símbolos) ----------
//
// Con el árbol de tree-sitter: `fn`, `struct` y `enum` son símbolos, y sus
// campos y variantes cuelgan dentro. Es sintáctico, como ir a la definición.

const SIMBOLOS = [['fn', SymbolKind.Function], ['struct', SymbolKind.Struct],
                  ['enum', SymbolKind.Enum]];
const MIEMBROS = [['campo_def', SymbolKind.Field], ['variante', SymbolKind.EnumMember]];

function rango_de(nodo) {
    return {
        start: { line: nodo.startPosition.row, character: nodo.startPosition.column },
        end: { line: nodo.endPosition.row, character: nodo.endPosition.column },
    };
}

// La clase de un nodo en una tabla `[tipo, clase]`, o `null` si no está.
function clase_de(nodo, tabla) {
    for (const [tipo, clase] of tabla) {
        if (nodo.type === tipo) return clase;
    }
    return null;
}

// El símbolo de un nodo con campo `nombre`, o `null` si no lo lleva (los nodos
// de la palabra clave —el `fn` suelto— no lo tienen). Los miembros se buscan
// entre los hijos DIRECTOS: `descendantsOfType` baja también a los hermanos
// (un `campo_def` devolvía el siguiente `campo_def`), y eso colgaba.
function simbolo_de(nodo, clase) {
    const campo = nodo.childForFieldName('nombre');
    if (!campo) return null;
    const hijos = [];
    for (const hijo of nodo.namedChildren) {
        const clase_hijo = clase_de(hijo, MIEMBROS);
        if (clase_hijo === null) continue;
        const miembro = simbolo_de(hijo, clase_hijo);
        if (miembro) hijos.push(miembro);
    }
    return {
        name: campo.text,
        kind: clase,
        range: rango_de(nodo),
        selectionRange: rango_de(campo),
        children: hijos,
    };
}

// Recorre el árbol y se queda con los símbolos, en orden de aparición. Baja
// por los envoltorios (`programa`, `declaracion`) pero no por el cuerpo de una
// función: dentro de un símbolo ya se miran sus miembros.
function recoger_simbolos(nodo, salida) {
    for (const hijo of nodo.namedChildren) {
        const clase = clase_de(hijo, SIMBOLOS);
        if (clase !== null) {
            const simbolo = simbolo_de(hijo, clase);
            if (simbolo) salida.push(simbolo);
            continue;
        }
        recoger_simbolos(hijo, salida);
    }
}

connection.onDocumentSymbol((params) => {
    const documento = documents.get(params.textDocument.uri);
    if (!documento || !analizador) return [];
    const arbol = analizador.parse(documento.getText());
    const salida = [];
    recoger_simbolos(arbol.rootNode, salida);
    return salida;
});

// La gramática lista antes de escuchar; si no está, el LSP igual arranca
// (diagnósticos y formato no la necesitan) y la definición queda muda.
gramatica()
    .then((lenguaje) => { analizador = new Parser(); analizador.setLanguage(lenguaje); })
    .catch(() => { /* sin gramática: no hay go-to-definition */ });

documents.listen(connection);
connection.listen();
