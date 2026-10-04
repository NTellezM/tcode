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
//   raiz    -> raíz del proyecto, donde está `std/`. Se resuelve en este
//              orden: `$TCODE_RAIZ`, la raíz que manda el cliente (el
//              proyecto abierto) y, si no hay ninguna, la instalación que se
//              descubre desde el propio binario —en el `PATH` si va suelto,
//              subiendo hasta `runtime/cabecera.inc`—, igual que el
//              `raiz_instalada()` del compilador.

const path = require('path');
const fs = require('fs');
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
    // La raíz, en el orden que pide el compilador: `TCODE_RAIZ`, el proyecto
    // abierto y, si no hay ninguna, la instalación que se descubre desde el
    // binario. Si no se encuentra nada, el directorio de trabajo, lo de
    // siempre.
    raiz = process.env.TCODE_RAIZ || opciones.raiz || raiz_instalada() || process.cwd();
    return {
        capabilities: {
            textDocumentSync: TextDocumentSyncKind.Full,
            documentFormattingProvider: true,
            definitionProvider: true,
            hoverProvider: true,
            completionProvider: {
                resolveProvider: false,
                // `#` trae los módulos de `std/`; `"` los trae al abrir el
                // texto de un `#importar` o de un `use`; `.` las funciones
                // del módulo que se acaba de escribir (`texto.`).
                triggerCharacters: ['#', '"', '.'],
            },
            documentSymbolProvider: true,
        },
    };
});

// Igual que `raiz_instalada()` del compilador: se resuelve el propio binario
// —en el `PATH` si va como nombre suelto, con sus enlaces ya resueltos— y se
// sube por sus directorios hasta dar con `runtime/cabecera.inc`, que es donde
// vive `std/`. Así un fichero suelto, fuera de todo proyecto, encuentra la
// biblioteca igual que un `tcodec` instalado. "" si no se encuentra.
function raiz_instalada() {
    let binario = ruta_del_binario(tcodec);
    while (binario) {
        if (es_archivo(path.join(binario, 'runtime', 'cabecera.inc'))) return binario;
        const padre = path.dirname(binario);
        binario = padre === binario ? '' : padre;
    }
    return '';
}

// La ruta de verdad del binario `nombre`: si va suelto, el primero que
// aparezca recorriendo el `PATH` —el trozo vacío es el directorio actual—, el
// mismo que habría ejecutado el shell; si lleva barra, tal cual. "" si no está.
function ruta_del_binario(nombre) {
    const candidatos = [];
    if (nombre.includes('/') || nombre.includes('\\')) {
        candidatos.push(nombre);
    } else {
        for (const carpeta of (process.env.PATH || '').split(path.delimiter)) {
            candidatos.push(path.join(carpeta === '' ? '.' : carpeta, nombre));
        }
    }
    for (const candidato of candidatos) {
        const real = resolver(candidato);
        if (real) return real;
    }
    return '';
}

// La ruta con sus enlaces resueltos, o "" si no es un fichero.
function resolver(ruta) {
    try {
        const real = fs.realpathSync(ruta);
        return fs.statSync(real).isFile() ? real : '';
    } catch (_) {
        return '';
    }
}

function es_archivo(ruta) {
    try {
        return fs.statSync(ruta).isFile();
    } catch (_) {
        return false;
    }
}

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

// ---------- el hover ----------
//
// La firma de la función bajo el cursor. Las de `std/` y las internas salen de
// las tablas de más abajo —`partir_firma` ya las parte en etiqueta y en lo que
// devuelven—, y las del propio documento, de la gramática. No hay tipos: es la
// misma información que el completado, puesta para leer.

connection.onHover((params) => {
    const documento = documents.get(params.textDocument.uri);
    if (!documento || !analizador) return null;
    const texto = documento.getText();
    const arbol = analizador.parse(texto);
    const nodo = arbol.rootNode.descendantForPosition({
        row: params.position.line, column: params.position.character,
    });
    if (!nodo || nodo.type !== 'ident') return null;
    const ficha = ficha_de_funcion(nodo.text, texto, nodo.startIndex, arbol);
    if (!ficha) return null;
    return {
        contents: [{ language: 'tcode', value: ficha.firma }]
            .concat(ficha.que ? [ficha.que] : []),
        range: rango_de(nodo),
    };
});

// La ficha de la función `nombre`, o `null` si bajo el cursor no hay ninguna.
// Si delante hay un `modulo.` —o el alias de un `use ... como`— solo vale ese
// módulo; si no, vale la del documento, una interna o la de un módulo
// importado sin alias.
function ficha_de_funcion(nombre, texto, desde, arbol) {
    const receptor = modulo_antes(texto.slice(0, desde));
    if (receptor !== null) {
        const modulo = modulo_de(receptor, texto);
        return modulo ? ficha_en_modulo(nombre, modulo) : null;
    }
    for (const fn of arbol.rootNode.descendantsOfType('fn')) {
        const campo = fn.childForFieldName('nombre');
        if (!campo || campo.text !== nombre) continue;
        const cuerpo = fn.text.indexOf('{');
        return {
            firma: (cuerpo < 0 ? fn.text : fn.text.slice(0, cuerpo)).trim(),
            que: 'declarada en este archivo',
        };
    }
    const interna = FUNCIONES_INTERNAS.get(nombre);
    if (interna) {
        return {
            firma: interna[0] + (interna[1] ? ' -> ' + interna[1] : ''),
            que: interna[2],
        };
    }
    for (const [importado, alias] of modulos_importados(texto)) {
        if (alias !== '') continue;   // con alias, solo se ve tras `alias.`
        const modulo = MODULOS.find((m) => m[0] === importado);
        if (!modulo) continue;
        const encontrada = ficha_en_modulo(nombre, modulo);
        if (encontrada) return encontrada;
    }
    return null;
}

// La ficha de `nombre` dentro de un módulo, o `null` si no está. La firma tal
// cual está en `std/*.t`, con sus tipos.
function ficha_en_modulo(nombre, modulo) {
    for (const firma of modulo[2]) {
        const { etiqueta, devuelve } = partir_firma(firma);
        if (etiqueta.split('(')[0] !== nombre) continue;
        return {
            firma: firma,
            devuelve: devuelve,
            que: 'std/' + modulo[0] + ' · ' + modulo[1],
        };
    }
    return null;
}

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
    ['claves(m)', 'list<K>', 'copias de las claves, para recorrerlo'],
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

// El nombre suelto -> la ficha, para el hover.
const FUNCIONES_INTERNAS = new Map(
    INTERNAS.map(([firma, devuelve, que]) => [firma.split('(')[0], [firma, devuelve, que]]));

const PALABRAS = ['fn', 'if', 'else', 'while', 'for', 'match', 'return', 'fail',
                  'break', 'continue', 'let', 'var', 'mut', 'try', 'sino', 'en',
                  'use', 'struct', 'enum', 'externo', 'como', 'anchor', 'drop',
                  'extends', 'protocol', 'implements'];

const TIPOS = ['str', 'view', 'usize', 'u8', 'u16', 'u32', 'u64', 'i8', 'i16',
               'i32', 'i64', 'f32', 'f64', 'bool', 'map', 'list', 'bloque', 'cadena_c'];

const CONSTANTES = ['true', 'false'];

// ---------- la biblioteca estándar ----------
//
// `#importar "texto.t"` es lo mismo que `use "std/texto"`. Al escribir `#`
// salen los módulos y se inserta la directiva entera; dentro de
// `#importar "` solo falta el fichero, y dentro de un `use "` la ruta de
// `std/`. Los módulos que el documento ya importa aportan además sus
// funciones, para no tener que saberse los nombres.
//
// Cada módulo es `[nombre, qué es, [firmas...]]`, con la firma tal cual está
// en `std/*.t`: de ahí salen la etiqueta (sin tipos), lo que devuelve y la
// ayuda. No están todas, solo las que se usan de verdad.

const MODULOS = [
    ['archivo', 'leer archivos con memoria acotada',
     ['por_partes<F>(ruta: view, tamano: usize, visitar: F) !',
      'partes_de_archivo(ruta: view, tamano: usize) -> list<str> !']],
    ['azar', 'aleatoriedad sobre `azar` y `sembrar`',
     ['entero_entre(desde: usize, hasta: usize) -> usize !',
      'indice_al_azar<T>(xs: &list<T>) -> usize !',
      'barajar<T>(xs: mut list<T>)']],
    ['base64', 'base64 (RFC 4648)',
     ['codificar(v: view) -> str',
      'decodificar(v: view) -> str !']],
    ['bit', 'manejo de bits',
     ['mascara(n: usize) -> u64',
      'prueba(x: u64, n: usize) -> bool',
      'pon(x: u64, n: usize) -> u64',
      'quita(x: u64, n: usize) -> u64',
      'alterna(x: u64, n: usize) -> u64',
      'cuenta(x: u64) -> usize',
      'a_binario(x: u64, digitos: usize) -> str']],
    ['bytes', 'leer y escribir enteros en un buffer',
     ['poner_u8(destino: mut str, v: u8)',
      'poner_u16(destino: mut str, v: u16)',
      'poner_u32(destino: mut str, v: u32)',
      'poner_u64(destino: mut str, v: u64)',
      'leer_u8(v: view, desde: usize) -> u8 !',
      'leer_u16(v: view, desde: usize) -> u16 !',
      'leer_u32(v: view, desde: usize) -> u32 !',
      'leer_u64(v: view, desde: usize) -> u64 !',
      'a_hex(v: view) -> str',
      'de_hex(v: view) -> str !']],
    ['camino', 'rutas de archivo, con `/`',
     ['absoluta(ruta: view) -> bool',
      'nombre_de(ruta: view) -> view',
      'carpeta_de(ruta: view) -> view',
      'extension(ruta: view) -> view',
      'sin_extension(ruta: view) -> view',
      'unir_ruta(a: view, b: view) -> str',
      'juntar(trozos: &list<str>) -> str',
      'normalizar(ruta: view) -> str']],
    ['caracter', 'clasificación de bytes ASCII',
     ['es_blanco(b: usize) -> bool',
      'es_digito(b: usize) -> bool',
      'es_minuscula(b: usize) -> bool',
      'es_mayuscula(b: usize) -> bool',
      'es_letra(b: usize) -> bool',
      'es_alfanumerico(b: usize) -> bool']],
    ['cli', 'leer los argumentos del programa',
     ['leer() -> Argumentos',
      'tiene_bandera(a: &Argumentos, nombre: view) -> bool',
      'opcion(a: &Argumentos, nombre: view) -> str']],
    ['cola', 'una cola FIFO y una de doble extremo',
     ['nueva_cola<T>() -> Cola<T>',
      'cola_vacia<T>(c: &Cola<T>) -> bool',
      'cuantos_en_cola<T>(c: &Cola<T>) -> usize',
      'encolar<T>(c: mut Cola<T>, x: T)',
      'desencolar<T>(c: mut Cola<T>) -> T !',
      'frente<T>(c: &Cola<T>) -> T !',
      'nueva_doble<T>() -> Doble<T>',
      'meter_detras<T>(d: mut Doble<T>, x: T)',
      'meter_delante<T>(d: mut Doble<T>, x: T)',
      'sacar_delante<T>(d: mut Doble<T>) -> T !',
      'sacar_detras<T>(d: mut Doble<T>) -> T !',
      'primero<T>(d: &Doble<T>) -> T !',
      'ultimo<T>(d: &Doble<T>) -> T !']],
    ['color', 'colores y estilos ANSI',
     ['pintar(codigo: view, texto: view) -> str',
      'negrita(texto: view) -> str',
      'tenue(texto: view) -> str',
      'subrayado(texto: view) -> str',
      'rojo(texto: view) -> str',
      'verde(texto: view) -> str',
      'amarillo(texto: view) -> str',
      'azul(texto: view) -> str',
      'magenta(texto: view) -> str',
      'cian(texto: view) -> str',
      'blanco(texto: view) -> str',
      'color_256(n: usize, texto: view) -> str']],
    ['compresion', 'descomprimir DEFLATE, zlib y gzip',
     ['adler32(v: view) -> u32',
      'inflar_deflate(datos: view) -> str !',
      'inflar_zlib(datos: view) -> str !',
      'inflar_gzip(datos: view) -> str !',
      'deflar_guardado(datos: view) -> str']],
    ['conjunto', 'un conjunto de textos',
     ['conjunto() -> Conjunto',
      'de_lista(xs: &list<str>) -> Conjunto',
      'agregar_uno(c: mut Conjunto, x: view)',
      'contiene_a(c: &Conjunto, x: view) -> bool',
      'quitar_uno(c: mut Conjunto, x: view) -> bool',
      'cuantos_hay(c: &Conjunto) -> usize',
      'elementos(c: &Conjunto) -> list<str>',
      'union(a: &Conjunto, b: &Conjunto) -> Conjunto',
      'interseccion(a: &Conjunto, b: &Conjunto) -> Conjunto',
      'diferencia(a: &Conjunto, b: &Conjunto) -> Conjunto']],
    ['crc', 'CRC-32, la suma de zlib, gzip y PNG',
     ['crc32(v: view) -> u32',
      'crc32_continuar(previa: u32, v: view) -> u32']],
    ['csv', 'leer y escribir CSV (RFC 4180)',
     ['leer(texto: view) -> list<list<str>>',
      'escribir(filas: &list<list<str>>) -> str']],
    ['cuenta', 'lo que en Python te da `collections.Counter`',
     ['contar(cosas: &list<str>) -> map<str, usize>',
      'mayores(m: &map<str, usize>, cuantas: usize) -> list<str>']],
    ['fecha', 'fechas y horas desde `ahora_ms`',
     ['ahora() -> i64',
      'a_partes(ms: i64) -> Partes',
      'a_ms(p: &Partes) -> i64',
      'a_fecha(ms: i64) -> str',
      'a_hora(ms: i64) -> str',
      'formatear(ms: i64) -> str',
      'dia_de_semana(p: &Partes) -> view']],
    ['formato', 'poner números y tablas donde se puedan leer',
     ['con_decimales(x: f64, cuantos: usize) -> str',
      'con_millares(n: usize) -> str',
      'fila(celdas: &list<str>, anchos: &list<usize>, sep: view) -> str',
      'anchos_de(filas: &list<list<str>>) -> list<usize>']],
    ['glob', 'coincidencia de patrones, con `*` y `?`',
     ['coincide(texto: view, patron: view) -> bool',
      'coincidentes(xs: &list<str>, patron: view) -> list<str>']],
    ['hash', 'hashes rápidos de contenido',
     ['fnv1a(v: view) -> u64',
      'djb2(v: view) -> u64',
      'a_hex(h: u64) -> str',
      'potencia(base: u64, exponente: usize) -> u64']],
    ['ini', 'leer y escribir INI',
     ['leer(texto: view) -> map<str, map<str, str>>',
      'escribir(ini: &map<str, map<str, str>>) -> str',
      'valor(ini: &map<str, map<str, str>>, seccion: view, clave: view) -> str !',
      'valor_o(ini: &map<str, map<str, str>>, seccion: view, clave: view, alterno: view) -> str']],
    ['iterador', 'recorridos que componen sin colecciones intermedias',
     ['para_cada<T, F>(xs: &list<T>, hacer: F)',
      'todas<T, F>(xs: &list<T>, cumple: F) -> bool',
      'alguna<T, F>(xs: &list<T>, cumple: F) -> bool',
      'primera_que<T, F>(xs: &list<T>, cumple: F) -> T !',
      'plegar<T, A, F>(xs: &list<T>, inicial: A, combinar: F) -> A',
      'transformar<T, F>(xs: &list<T>, convertir: F) -> list<T>']],
    ['json', 'leer y escribir JSON',
     ['leer(texto: view) -> Valor !',
      'escribir(v: &Valor) -> str',
      'escribir_con_sangria(v: &Valor) -> str']],
    ['lista', 'lo que se le pide a una lista y no viene de serie',
     ['esta_vacia<T>(xs: &list<T>) -> bool',
      'ultima_posicion<T>(xs: &list<T>) -> usize !',
      'primeras<T>(xs: &list<T>, cuantas: usize) -> list<T>',
      'invertida<T>(xs: &list<T>) -> list<T>',
      'aplanar<T>(xss: &list<list<T>>) -> list<T>',
      'ordenadas_por<T, F>(xs: &list<T>, antes: F) -> list<T>',
      'filtradas<T, F>(xs: &list<T>, cumple: F) -> list<T>',
      'cuantas_cumplen<T, F>(xs: &list<T>, cumple: F) -> usize',
      'incluye<T: igualable>(xs: &list<T>, aguja: &T) -> bool',
      'posicion<T: igualable>(xs: &list<T>, aguja: &T) -> usize !',
      'maximo<T: ordenable>(xs: &list<T>) -> T !',
      'minimo<T: ordenable>(xs: &list<T>) -> T !',
      'suma<T: numero>(ns: &list<T>) -> T',
      'media(ns: &list<usize>) -> usize !',
      'invertir<T: numero>(ns: mut list<T>)']],
    ['log', 'avisos con nivel y hora',
     ['con_nivel(minimo: i64) -> Log',
      'etiqueta(nivel: i64) -> view',
      'depura(l: &Log, mensaje: view)',
      'informa(l: &Log, mensaje: view)',
      'avisa(l: &Log, mensaje: view)',
      'error(l: &Log, mensaje: view)']],
    ['mapa', 'lo que se le pide a un mapa y no viene de serie',
     ['esta_vacio<V>(m: &map<str, V>) -> bool',
      'obtener_o<V>(m: &map<str, V>, clave: view, alterno: V) -> V',
      'acumular(m: mut map<str, usize>, clave: view, cuanto: usize)',
      'claves_ordenadas<V>(m: &map<str, V>) -> list<str>',
      'valores_ordenados<V>(m: &map<str, V>) -> list<V> !',
      'actualizar<V>(destino: mut map<str, V>, otro: &map<str, V>) !',
      'completar<V>(destino: mut map<str, V>, otro: &map<str, V>) !',
      'cuantas_claves<V, F>(m: &map<str, V>, cumple: F) -> usize']],
    ['numero', 'aritmética que puede fallar, y lo declara',
     ['dividir(a: usize, b: usize) -> usize !',
      'resto(a: usize, b: usize) -> usize !',
      'porcentaje(parte: usize, total: usize) -> usize !',
      'menor_de(a: usize, b: usize) -> usize',
      'mayor_de(a: usize, b: usize) -> usize',
      'acotar(n: usize, minimo_val: usize, maximo_val: usize) -> usize',
      'cerca(a: f64, b: f64, tolerancia: f64) -> bool',
      'porcentaje_exacto(parte: f64, total: f64) -> f64 !',
      'acotar_decimal(x: f64, minimo_val: f64, maximo_val: f64) -> f64',
      'media_decimal(suma: f64, cuantos: usize) -> f64 !']],
    ['par', 'dos valores juntos',
     ['par<A, B>(a: A, b: B) -> Par<A, B>',
      'volteado<A, B>(p: &Par<A, B>) -> Par<B, A>']],
    ['pila', 'una pila LIFO',
     ['cuantos<T>(p: &Pila<T>) -> usize',
      'vacia<T>(p: &Pila<T>) -> bool',
      'apilar<T>(p: mut Pila<T>, x: T)',
      'desapilar<T>(p: mut Pila<T>, vacio_t: T) -> T !',
      'cima<T>(p: &Pila<T>) -> T !']],
    ['plantilla', 'rellenar una plantilla con `{clave}`',
     ['rellenar(patron: view, datos: &map<str, str>) -> str']],
    ['prioridad', 'una cola de prioridad (montículo de mínimos)',
     ['prioridad_vacia<T: numero>(p: &Prioridad<T>) -> bool',
      'cuantos_en_prioridad<T: numero>(p: &Prioridad<T>) -> usize',
      'meter_con_prioridad<T: numero>(p: mut Prioridad<T>, x: T)',
      'ver_el_primero<T: numero>(p: &Prioridad<T>) -> T !',
      'sacar_el_primero<T: numero>(p: mut Prioridad<T>) -> T !']],
    ['prueba', 'comprobar cosas desde Tcode',
     ['pruebas() -> Pruebas',
      'afirmar(p: mut Pruebas, que: view, cierto: bool)',
      'afirmar_igual_texto(p: mut Pruebas, que: view, dado: view, esperado: view)',
      'afirmar_igual_numero(p: mut Pruebas, que: view, dado: usize, esperado: usize)',
      'terminar(p: &Pruebas) -> usize']],
    ['regex', 'expresiones regulares',
     ['compilar(patron: view) -> Patron !',
      'motor(p: &Patron, v: view) -> Motor',
      'casamenta(p: &Patron, v: view) -> bool',
      'busca(p: &Patron, v: view) -> bool',
      'buscar(p: &Patron, v: view) -> Rango !',
      'capturas(p: &Patron, v: view) -> list<str> !',
      'sustituir(m: &Motor, v: view, con: view, salida: mut str)',
      'reemplazar(p: &Patron, v: view, con: view) -> str',
      'reemplazar_todo(p: &Patron, v: view, con: view) -> str',
      'partir(p: &Patron, v: view) -> list<str>']],
    ['sha256', 'SHA-256 (FIPS 180-4), en Tcode puro',
     ['resumen(v: view) -> str',
      'resumen_hex(v: view) -> str',
      'nuevo_resumen() -> Resumen',
      'anadir_al_resumen(r: mut Resumen, v: view)',
      'terminar_resumen(r: &Resumen) -> str',
      'terminar_resumen_hex(r: &Resumen) -> str',
      'hmac_sha256(clave: view, mensaje: view) -> str',
      'sha256_de_fichero(ruta: view) -> str !']],
    ['tabla', 'tablas de texto alineadas',
     ['repetir(t: view, veces: usize) -> str',
      'dibujar(cabecera: &list<str>, filas: &list<list<str>>) -> str']],
    ['terminal', 'mover el cursor y dibujar en una terminal',
     ['escape(codigo: view) -> str',
      'subir(n: usize) -> str',
      'bajar(n: usize) -> str',
      'derecha(n: usize) -> str',
      'izquierda(n: usize) -> str',
      'a_columna(n: usize) -> str',
      'a_inicio_de_linea() -> str',
      'borrar_linea() -> str',
      'borrar_pantalla() -> str',
      'ocultar_cursor() -> str',
      'mostrar_cursor() -> str',
      'sin_codigos(v: view) -> str',
      'ancho_visible(v: view) -> usize',
      'barra(hechos: usize, total: usize, ancho: usize) -> str',
      'giro(paso: usize) -> str',
      'marco(lineas: &list<str>) -> list<str>']],
    ['texto', 'lo que en Python te dan los métodos de `str`',
     ['minusculas(v: view) -> str',
      'mayusculas(v: view) -> str',
      'palabras(v: view) -> list<str>',
      'terminos(v: view) -> list<str>',
      'partir(v: view, sep: view) -> list<str> !',
      'lineas(v: view) -> list<str>',
      'apariciones(v: view, aguja: view) -> usize !',
      'a_entero(v: view) -> usize !',
      'recortar(v: view) -> view',
      'empieza_con(v: view, prefijo: view) -> bool',
      'termina_con(v: view, sufijo: view) -> bool',
      'indice_de(pajar: view, aguja: view) -> usize !',
      'contiene(pajar: view, aguja: view) -> bool',
      'repetir(v: view, veces: usize) -> str',
      'unir(trozos: &list<str>, sep: view) -> str',
      'reemplazar(v: view, viejo: view, nuevo_texto: view) -> str !',
      'rellenar(v: view, ancho: usize) -> str',
      'alinear(v: view, ancho: usize) -> str']],
    ['toml', 'leer TOML (lo esencial)',
     ['leer(texto: view) -> map<str, ValorToml> !',
      'tiene_clave(t: &map<str, ValorToml>, clave: view) -> bool',
      'texto_de(t: &map<str, ValorToml>, clave: view, alterno: view) -> str',
      'entero_de(t: &map<str, ValorToml>, clave: view, alterno: i64) -> i64',
      'decimal_de(t: &map<str, ValorToml>, clave: view, alterno: f64) -> f64',
      'cierto_de(t: &map<str, ValorToml>, clave: view, alterno: bool) -> bool',
      'crudo_de(t: &map<str, ValorToml>, clave: view) -> ValorToml !',
      'lista_de(t: &map<str, ValorToml>, clave: view) -> list<ValorToml> !']],
    ['url', 'partir y rearmar direcciones de internet (RFC 3986)',
     ['analizar(v: view) -> Partes',
      'construir(p: &Partes) -> str',
      'parametros(consulta: view) -> list<Par<str, str>>',
      'valor_de(consulta: view, nombre: view) -> str !',
      'codificar_componente(v: view) -> str',
      'decodificar_componente(v: view) -> str !',
      'decodificar_formulario(v: view) -> str !']],
    ['utf8', 'leer y escribir texto como caracteres, no como bytes',
     ['caracter(v: view, i: usize) -> u32 !',
      'caracter_o(v: view, i: usize, defecto: u32) -> u32',
      'siguiente(v: view, i: usize) -> usize',
      'cuantos(v: view) -> usize',
      'valido(v: view) -> bool',
      'indices(v: view) -> list<usize>',
      'trozo(v: view, desde: usize, hasta: usize) -> view',
      'codificar(destino: mut str, c: u32) !',
      'de_caracter(c: u32) -> str !',
      'ancho_de(c: u32) -> usize',
      'ancho(v: view) -> usize',
      'recortar_a_ancho(v: view, columnas: usize) -> view']],
    ['uuid', 'identificadores únicos (UUID v4)',
     ['sembrar_del_reloj()',
      'v4() -> str',
      'formatear(b: &list<usize>) -> str']],
    ['vector', 'una lista dinámica escrita en Tcode',
     ['cuantos<T>(v: &Vector<T>) -> usize',
      'capacidad<T>(v: &Vector<T>) -> usize',
      'agregar<T>(v: mut Vector<T>, x: T)',
      'sacar<T>(v: mut Vector<T>, vacio_del_tipo: T) -> T !',
      'copia_de<T>(v: &Vector<T>, i: usize) -> T !',
      'a_lista<T>(v: &Vector<T>) -> list<T>',
      'ajustar<T>(v: mut Vector<T>)']],
];

// El nombre del módulo -> qué es, para el completado.
const DESCRIPCION = new Map(MODULOS.map(([nombre, que]) => [nombre, que]));

// `filtradas<T, F>(xs: &list<T>, cumple: F) -> list<T> !` se parte en la
// etiqueta sin tipos (`filtradas(xs, cumple)`) y lo que devuelve (`list<T>!`).
function partir_firma(firma) {
    const falla = firma.endsWith(' !');
    const cuerpo = falla ? firma.slice(0, -2) : firma;
    const corte = cuerpo.indexOf(' -> ');
    const cabecera = corte < 0 ? cuerpo : cuerpo.slice(0, corte);
    let devuelve = corte < 0 ? '' : cuerpo.slice(corte + 4);
    if (falla) devuelve = devuelve ? devuelve + '!' : '!';
    return { etiqueta: sin_tipos(cabecera), devuelve: devuelve };
}

// El nombre y los parámetros, sin sus tipos: `filtradas<T, F>(xs: &list<T>,
// cumple: F)` -> `filtradas(xs, cumple)`. Las comas dentro de `<>`, `()` o
// `[]` no separan parámetros.
function sin_tipos(cabecera) {
    const abre = cabecera.search(/[<(]/);
    if (abre < 0) return cabecera.trim();
    const nombre = cabecera.slice(0, abre).trim();
    const dentro = cabecera.slice(cabecera.indexOf('(', abre) + 1, cabecera.lastIndexOf(')'));
    const parametros = [];
    let hondo = 0;
    let desde = 0;
    for (let i = 0; i <= dentro.length; i++) {
        const c = dentro[i];
        if (c === '<' || c === '(' || c === '[') hondo++;
        else if (c === '>' || c === ')' || c === ']') hondo--;
        if ((c === ',' && hondo === 0) || i === dentro.length) {
            const parametro = dentro.slice(desde, i);
            const dos_puntos = parametro.indexOf(':');
            parametros.push((dos_puntos < 0 ? parametro : parametro.slice(0, dos_puntos)).trim());
            desde = i + 1;
        }
    }
    const lista = parametros.filter((p) => p !== '');
    return nombre + '(' + lista.join(', ') + ')';
}

// Los módulos que el documento ya importa, en orden y sin repetir, con su
// alias si lo llevan (`use "std/texto" como t`). Valen las dos grafías:
// `use "std/texto"` y `#importar "texto.t"`.
function modulos_importados(texto) {
    const salida = [];
    const visto = new Set();
    const patron = /(?:use|#importar)\s+"([A-Za-z0-9_\/]+?)(?:\.t)?"(?:\s+como\s+([A-Za-z_][A-Za-z0-9_]*))?/g;
    let encajado;
    while ((encajado = patron.exec(texto)) !== null) {
        const nombre = encajado[1].replace(/^std\//, '');
        const alias = encajado[2] || '';
        const clave = nombre + ' ' + alias;
        if (visto.has(clave)) continue;
        visto.add(clave);
        salida.push([nombre, alias]);
    }
    return salida;
}

// El módulo que nombra `nombre` en este documento: su alias (`use "std/texto"
// como t` -> `t`) o el nombre de la biblioteca (`texto`). `null` si no es uno.
function modulo_de(nombre, texto) {
    for (const [importado, alias] of modulos_importados(texto)) {
        if (alias === nombre) {
            const modulo = MODULOS.find((m) => m[0] === importado);
            if (modulo) return modulo;
        }
    }
    return MODULOS.find((m) => m[0] === nombre) || null;
}

// El `modulo.` justo antes del cursor, si lo hay. Un `1.` no cuenta —es un
// decimal—, y `esto.` sí, aunque `esto` no sea un módulo: quien decide es
// `modulo_de`.
function modulo_antes(antes) {
    const encajado = antes.match(/([A-Za-z_][A-Za-z0-9_]*)\.[A-Za-z0-9_]*$/);
    return encajado ? encajado[1] : null;
}

// Las funciones de un módulo como elementos de completado. `puestos` evita
// repetir un nombre entre módulos y contra las internas.
function items_de_modulo(modulo, puestos) {
    const salida = [];
    for (const firma of modulo[2]) {
        const { etiqueta, devuelve } = partir_firma(firma);
        const clave = etiqueta.split('(')[0];
        if (puestos.has(clave)) continue;
        puestos.add(clave);
        salida.push({
            label: etiqueta,
            kind: CompletionItemKind.Function,
            detail: devuelve ? '-> ' + devuelve : '',
            documentation: 'std/' + modulo[0] + ' · ' + firma,
            insertText: clave + '(',
            filterText: clave,
        });
    }
    return salida;
}

// Los módulos que hay de verdad en `std/`, bajo la raíz que se descubrió. Los
// que no estén en la tabla de arriba se ofrecen igual, sin firmas: la lista de
// módulos sale de la biblioteca, no de la tabla. Se lee una vez por raíz.
let en_disco = null;

function nombres_en_disco() {
    if (en_disco && en_disco.raiz === raiz) return en_disco.nombres;
    const nombres = [];
    try {
        for (const fichero of fs.readdirSync(path.join(raiz, 'std'))) {
            if (fichero.endsWith('.t')) nombres.push(fichero.slice(0, -2));
        }
    } catch (_) { /* sin `std/` a la vista: queda la tabla */ }
    en_disco = { raiz: raiz, nombres: nombres };
    return nombres;
}

// ¿El cursor está dentro de un `use "`? Devuelve lo ya escrito dentro de las
// comillas, o `null` si no es el caso.
function dentro_de_use(antes) {
    const encajado = antes.match(/(?:^|\n)[^\S\n]*use[^\S\n]+"([^"\n]*)$/);
    return encajado ? encajado[1] : null;
}

// ¿Y dentro de un `#importar "`? Igual, lo que ya se escribió del fichero.
function dentro_de_importar(antes) {
    const encajado = antes.match(/(?:^|\n)[^\S\n]*#importar[^\S\n]+"([^"\n]*)$/);
    return encajado ? encajado[1] : null;
}

// ¿El cursor está dentro de un texto `"..."`? Basta con mirar la línea: una
// comilla sin cerrar. Sirve para no ofrecer `#módulo` dentro de un texto
// cualquiera ni de un comentario.
function dentro_de_texto(antes) {
    const linea = antes.slice(antes.lastIndexOf('\n') + 1);
    if (/^\s*\/\//.test(linea)) return true;
    let dentro = false;
    for (let i = 0; i < linea.length; i++) {
        if (linea[i] === '\\') { i++; continue; }
        if (linea[i] === '"') dentro = !dentro;
    }
    return dentro;
}

connection.onCompletion((params) => {
    const documento = documents.get(params.textDocument.uri);
    const texto = documento ? documento.getText() : '';
    const offset = documento ? documento.offsetAt(params.position) : 0;
    const antes = texto.slice(0, offset);

    // Un `#`, o estar dentro de un importe, abre la lista de módulos. Con el
    // `#` se inserta la directiva entera; dentro de `#importar "` el fichero
    // con su `.t`, y dentro de un `use "` la ruta de `std/`.
    const en_use = dentro_de_use(antes);
    const en_importar = dentro_de_importar(antes);
    const almohadilla = en_use === null && en_importar === null && !dentro_de_texto(antes)
        ? antes.match(/#[A-Za-z0-9_\/]*$/) : null;

    // Tras `modulo.` solo salen las funciones de ese módulo: `texto.` no
    // ofrece el resto de la biblioteca. Un `1.5` no es un módulo —lo descarta
    // `modulo_antes`—, así que ahí queda la lista de siempre.
    if (en_use === null && en_importar === null && almohadilla === null
            && !dentro_de_texto(antes)) {
        const receptor = modulo_antes(antes);
        const modulo = receptor === null ? null : modulo_de(receptor, texto);
        if (modulo) return items_de_modulo(modulo, new Set());
    }

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

    if (!documento) return salida;

    if (en_use !== null || en_importar !== null || almohadilla !== null) {
        // La tabla de arriba más lo que haya en `std/` de la raíz descubierta.
        const nombres = MODULOS.map((m) => m[0]);
        for (const nombre of nombres_en_disco()) {
            if (!nombres.includes(nombre)) nombres.push(nombre);
        }
        for (const nombre of nombres) {
            const que = DESCRIPCION.get(nombre) || 'un módulo de la biblioteca';
            let inserta;
            let etiqueta;
            let prefijo;
            if (en_use !== null) {
                inserta = 'std/' + nombre;
                etiqueta = inserta;
                prefijo = en_use;
            } else if (en_importar !== null) {
                inserta = nombre + '.t';
                etiqueta = inserta;
                prefijo = en_importar;
            } else {
                inserta = '#importar "' + nombre + '.t";';
                etiqueta = '#' + nombre;
                prefijo = almohadilla[0];
            }
            salida.push({
                label: etiqueta,
                kind: CompletionItemKind.Module,
                detail: inserta,
                documentation: que + '  (`#importar "' + nombre + '.t";` es `use "std/'
                    + nombre + '";`)',
                // El cliente filtra por lo que se reemplaza: que encajen la
                // directiva, el fichero y la ruta de `std/`.
                filterText: '#' + nombre + ' ' + nombre + '.t std/' + nombre,
                textEdit: TextEdit.replace({
                    start: documento.positionAt(offset - prefijo.length),
                    end: documento.positionAt(offset),
                }, inserta),
                sortText: '0' + nombre,
            });
        }
    }

    // Las funciones de los módulos ya importados, para no saberse los nombres.
    // Con alias solo se ven tras el punto, y de eso se encarga el filtro de
    // arriba.
    const puestos = new Set(INTERNAS.map(([f]) => f.split('(')[0]));
    for (const [nombre, alias] of modulos_importados(texto)) {
        if (alias !== '') continue;
        const modulo = MODULOS.find((m) => m[0] === nombre);
        if (!modulo) continue;
        for (const item of items_de_modulo(modulo, puestos)) salida.push(item);
    }
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
