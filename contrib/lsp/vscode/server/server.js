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
        Diagnostic, DiagnosticSeverity, ProposedFeatures, TextEdit } =
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

// La gramática lista antes de escuchar; si no está, el LSP igual arranca
// (diagnósticos y formato no la necesitan) y la definición queda muda.
gramatica()
    .then((lenguaje) => { analizador = new Parser(); analizador.setLanguage(lenguaje); })
    .catch(() => { /* sin gramática: no hay go-to-definition */ });

documents.listen(connection);
connection.listen();
