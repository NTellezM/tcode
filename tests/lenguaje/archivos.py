"""ARCHIVOS: lectura real, incluida entrada binaria."""

import os
import tempfile

from .comun import (
    Resultado,
    compilar_y_correr,
)

TITULO = "lectura real, incluida entrada binaria"


def correr(suite: Resultado) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        suite.total += 1
        entrada = os.path.join(tmp, "entrada.bin")
        with open(entrada, "wb") as f:
            f.write(b"uno\n\x00dos")
        ruta = entrada.replace("\\", "\\\\").replace('"', '\\"')
        fuente = f'''fn main() -> usize ! {{
        let datos: str = try leer_archivo("{ruta}");
        imprimir(largo(vista(datos))); imprimir(" ");
        imprimir(byte(vista(datos), 4)); imprimir("\\n");
        return 0;
    }}'''
        try:
            rc, out, err = compilar_y_correr(fuente, tmp)
        except AssertionError as exc:
            suite.falla("leer un archivo completo", str(exc))
        else:
            if rc != 0 or out != "8 0\n":
                suite.falla("leer un archivo completo",
                            f"codigo {rc}, salida {out!r}, stderr {err!r}")
            elif "runtime error" in err or "AddressSanitizer" in err:
                suite.falla("leer un archivo completo", f"sanitizer se quejo:\n{err}")

        # Ida y vuelta: escribir con bytes cero dentro y volver a leerlo.
        suite.total += 1
        salida = os.path.join(tmp, "salida.bin")
        ruta_s = salida.replace("\\", "\\\\").replace('"', '\\"')
        fuente = f'''fn main() -> usize ! {{
        var datos: str = nuevo("ab");
        empujar(datos, "\\0cd");
        try escribir_archivo("{ruta_s}", vista(datos));
        let vuelta: str = try leer_archivo("{ruta_s}");
        imprimir(largo(vista(vuelta))); imprimir(" ");
        imprimir(byte(vista(vuelta), 2)); imprimir(" ");
        imprimir(igual(vista(datos), vista(vuelta))); imprimir("\\n");
        imprimir_error("esto va al diagnostico");
        return 0;
    }}'''
        try:
            rc, out, err = compilar_y_correr(fuente, tmp)
        except AssertionError as exc:
            suite.falla("escribir y volver a leer", str(exc))
        else:
            if rc != 0 or out != "5 0 true\n":
                suite.falla("escribir y volver a leer",
                            f"codigo {rc}, salida {out!r}, stderr {err!r}")
            elif "esto va al diagnostico" not in err:
                suite.falla("escribir y volver a leer",
                            "`imprimir_error` no salio por la salida de error")
            elif "AddressSanitizer" in err:
                suite.falla("escribir y volver a leer", f"sanitizer se quejo:\n{err}")

        # La ruta se calcula antes que los datos. Si C invirtiera los argumentos,
        # `datos` veria 1 y `ruta` intentaria escribir en un lugar inexistente.
        suite.total += 1
        orden = os.path.join(tmp, "orden.bin")
        ruta_o = orden.replace("\\", "\\\\").replace('"', '\\"')
        fuente = f'''fn ruta(n: mut usize) -> view {{
        n = n + 1;
        if n == 1 {{ return "{ruta_o}"; }}
        return "/no/existe/orden.bin";
    }}
    fn datos(n: mut usize) -> view {{
        n = n + 1;
        if n == 2 {{ return "bien"; }}
        return "mal";
    }}
    fn main() -> usize ! {{
        var n: usize = 0;
        try escribir_archivo(ruta(n), datos(n));
        let vuelta = try leer_archivo("{ruta_o}");
        imprimir(vuelta); imprimir(" "); imprimir(n); imprimir("\\n");
        return 0;
    }}'''
        try:
            rc, out, err = compilar_y_correr(fuente, tmp)
        except AssertionError as exc:
            suite.falla("escribir_archivo evalua ruta antes que datos", str(exc))
        else:
            if rc != 0 or out != "bien 2\n":
                suite.falla("escribir_archivo evalua ruta antes que datos",
                            f"codigo {rc}, salida {out!r}, stderr {err!r}")
            elif "runtime error" in err or "AddressSanitizer" in err:
                suite.falla("escribir_archivo evalua ruta antes que datos",
                            f"sanitizer se quejo:\n{err}")

        # Escribir donde no se puede es un fallo, no un cuelgue.
        suite.total += 1
        fuente = '''fn main() -> usize ! {
        try escribir_archivo("/no/existe/de/verdad.txt", "x");
        return 0;
    }'''
        try:
            rc, out, err = compilar_y_correr(fuente, tmp)
        except AssertionError as exc:
            suite.falla("escribir donde no se puede", str(exc))
        else:
            if rc == 0 or "no se pudo abrir el archivo para escribir" not in err:
                suite.falla("escribir donde no se puede",
                            f"codigo {rc}, stderr {err!r}")
