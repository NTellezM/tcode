// Extensión mínima de VS Code: arranca el servidor LSP de Tcode.
// El servidor vive en `../server.js` (esta carpeta es `contrib/lsp/vscode/`).

const path = require('path');
const { workspace } = require('vscode');
const { LanguageClient, ServerOptions, TransportKind } = require('vscode-languageclient/node');

let cliente;

function activar(contexto) {
    const servidor = path.join(__dirname, '..', 'server.js');
    const config = workspace.getConfiguration('tcode.lsp');
    const opciones = {
        tcodec: config.get('tcodec', 'tcodec'),
        raiz: config.get('raiz', '') ||
            (workspace.workspaceFolders && workspace.workspaceFolders[0]
                ? workspace.workspaceFolders[0].uri.fsPath : ''),
    };
    const serverOptions = {
        run: { command: 'node', args: [servidor, '--stdio'], options: { env: process.env } },
        debug: { command: 'node', args: [servidor, '--stdio'], options: { env: process.env } },
    };
    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'tcode' }],
        initializationOptions: opciones,
    };
    cliente = new LanguageClient('tcode', 'Tcode', serverOptions, clientOptions);
    cliente.start();
}

function desactivar() {
    if (cliente) {
        return cliente.stop();
    }
    return undefined;
}

module.exports = { activate: activar, deactivate: desactivar };
