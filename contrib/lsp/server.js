// LSP de Tcode: diagnósticos y formato.
//
// No hay un segundo analizador: los diagnósticos salen del propio compilador
// (`tcodec --solo-comprobar`), que ya escribe `error: archivo:linea: mensaje`
// por la salida de error. El formato sale de `tcodec --formatear`, que escribe
// el resultado por la salida normal. El servidor solo traduce eso al
// protocolo.
//
// Configuración (por `initializationOptions` o variables de entorno):
//   tcodec  -> ruta del binario (por defecto `tcodec`, o `$TCODEC`)
//   raiz    -> raíz del proyecto, donde está `std/` (por defecto `$TCODE_RAIZ`)

const { createConnection, TextDocuments, TextDocumentSyncKind,
        Diagnostic, DiagnosticSeverity, ProposedFeatures, TextEdit, Position } =
        require('vscode-languageserver/node');
const { TextDocument } = require('vscode-languageserver-textdocument');
const { execFile } = require('child_process');
const { fileURLToPath } = require('url');

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

documents.listen(connection);
connection.listen();
