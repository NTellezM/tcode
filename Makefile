# Tcode
#
#   make              construye el compilador, `./tcodec`, desde su C semilla
#   make semilla      pone al dia la semilla, `bootstrap/tcodec.c`
#   make check        la suite entera, y que el README diga lo que mide
#   make rapido       el lenguaje, probado con tcodec: segundos
#   make propiedades  solo los tests por propiedad (TCODE_PROGRAMAS=1000 para mas)
#   make cifras       pone en el README las cifras de la ultima `make check`
#   make ejemplos     compila y corre los ejemplos
#   make bench        Tcode contra el mismo programa en C a mano
#   make bench-comprobar  y falla si algo pasa de `bench/limites.json`
#   make formato      deja todo el codigo Tcode en el formato canonico
#   make lint         revisa el codigo Python con ruff y mypy
#   make mutar        rompe una regla en tcodec, y exige que la suite lo note
#   make compiladores la semilla, el punto fijo y `rapido` con cada compilador de C
#   make paquete      dist/tcode-VERSION.tar.gz, reproducible (arbol limpio)
#   make probar-paquete  y desde el, sin Python, tcodec y un programa
#   make version NUEVA=x.y.z  la version en todos sus sitios, y la semilla
#   make fuzz         rompe el codigo del repositorio al azar (FUZZ_SEGUNDOS=60)
#   make limpiar      borra lo que genera todo lo anterior
#   make instalar     tcodec, std/ y runtime/ en PREFIJO (/usr/local)
#   make desinstalar  lo quita de PREFIJO

PY ?= python3

.PHONY: all check rapido propiedades cifras grafo bench ejemplos limpiar formato lint mutar semilla compiladores con-un-cc punto-fijo-cc fuzz fuzz-safestr bench-comprobar instalar desinstalar paquete probar-paquete version icono

all: tcodec

# El compilador es `tcodec`, escrito en Tcode. Se construye desde su C
# semilla, `bootstrap/tcodec.c`: el C que `tcodec` escribe de si mismo,
# guardado en el repositorio como hacen Zig y Go. Compilada, la semilla es la
# etapa 0, y la etapa 0 compila `tcodec.t` tal como esta ahora. No hace falta
# Python: solo un compilador de C.
SEMILLA = bootstrap/tcodec.c
ETAPA0 = .cache/tcodec0
SISTEMA = ejemplos/compilador/lib/sistema_tcodec.c
# Los `.c` que acompañan a un modulo de `std/`: uno por cada `externo
# "algo.c"` de la biblioteca. Se pasan a mano a `cc` en los targets que
# compilan con `--mostrar-c`, porque ese modo no enlaza acompañantes —el C es
# el producto y lo enlaza quien lo pida—. No es opcional: el compilador
# escribe TODAS las funciones de TODOS los modulos que carga, aunque nadie las
# llame, asi que `bootstrap/tcodec.c` referencia estos simbolos y sin ellos el
# enlazador se queja.
STD_C = std/proceso.c std/terminal.c
RUNTIME_C = runtime/safestr.c
TCODEC_FUENTES = $(wildcard ejemplos/compilador/*.t ejemplos/compilador/lib/*.t \
	ejemplos/compilador/lib/*.c ejemplos/lexer/lib/*.t std/*.t std/*.c runtime/* \
	runtime/sistema/*)

$(ETAPA0): $(SEMILLA) $(SISTEMA) $(STD_C) $(wildcard runtime/*)
	@mkdir -p .cache
	@$(CC) -std=c17 -O1 -Iruntime $(SEMILLA) $(RUNTIME_C) $(SISTEMA) $(STD_C) -o $@ -lm

tcodec: $(ETAPA0) $(TCODEC_FUENTES)
	@TCODE_RAIZ=. ./$(ETAPA0) ejemplos/compilador/tcodec.t -o tcodec

# La semilla al dia: el C que escribe de si mismo el `tcodec` de ahora. Antes
# de guardarla se comprueba que es un punto fijo: compilada, vuelve a
# escribir exactamente ese C. Hace falta cuando `tcodec.t` quiere usar algo
# que la semilla vieja todavia no sabe compilar.
semilla: tcodec
	@TCODE_RAIZ=. ./tcodec ejemplos/compilador/tcodec.t --mostrar-c > .cache/semilla.c
	@$(CC) -std=c17 -O1 -Iruntime .cache/semilla.c $(RUNTIME_C) $(SISTEMA) $(STD_C) -o .cache/semilla -lm
	@TCODE_RAIZ=. ./.cache/semilla ejemplos/compilador/tcodec.t --mostrar-c \
	    | cmp -s - .cache/semilla.c \
	    || { echo "la semilla nueva no se reproduce a si misma"; exit 1; }
	@mv .cache/semilla.c $(SEMILLA)
	@echo "semilla al dia: $(SEMILLA)"

# Tcode promete C17 portable: esto lo mira con cada compilador de
# `COMPILADORES`, no solo con el `cc` de la maquina. Cada uno se pone como
# `cc` delante del PATH —asi lo usan tcodec y todas las secciones de la
# suite— y con su propia cache. Con cada uno: la semilla compila sin un solo
# aviso; el tcodec de ahora, construido desde ella, tambien, y compilado con
# este compilador vuelve a escribir su propio C byte a byte; y pasan las
# secciones rapidas.
COMPILADORES ?= gcc clang

compiladores:
	@for c in $(COMPILADORES); do \
	    ruta=$$(command -v $$c) || { echo "no esta $$c"; exit 1; }; \
	    mkdir -p .cache/cc-$$c && ln -sf "$$ruta" .cache/cc-$$c/cc; \
	    echo "=== $$c: $$($$c --version | head -1)"; \
	    PATH="$$PWD/.cache/cc-$$c:$$PATH" TCODE_CACHE="$$PWD/.cache/herramientas-$$c" \
	        $(MAKE) -s --no-print-directory con-un-cc CC=cc || exit 1; \
	done

CC_ESTRICTO = cc -std=c17 -O1 -Wall -Wextra -Werror -Iruntime

con-un-cc: punto-fijo-cc
	@$(PY) tests/test_lenguaje.py $(RAPIDAS)

# Sin la suite: lo que se puede comprobar con solo un compilador de C.
punto-fijo-cc:
	@mkdir -p .cache
	@$(CC_ESTRICTO) $(SEMILLA) $(RUNTIME_C) $(SISTEMA) $(STD_C) -o .cache/cc-etapa0 -lm
	@TCODE_RAIZ=. ./.cache/cc-etapa0 ejemplos/compilador/tcodec.t --mostrar-c \
	    > .cache/cc-etapa1.c
	@$(CC_ESTRICTO) .cache/cc-etapa1.c $(RUNTIME_C) $(SISTEMA) $(STD_C) -o .cache/cc-etapa1 -lm
	@TCODE_RAIZ=. ./.cache/cc-etapa1 ejemplos/compilador/tcodec.t --mostrar-c \
	    | cmp -s - .cache/cc-etapa1.c \
	    || { echo "tcodec no reproduce su C con este compilador"; exit 1; }
	@echo "    sin avisos, y tcodec reproduce su C byte a byte"

# Fuzzing sobre los `.t` del repositorio: cada fallo se reduce y se guarda
# en `tests/fuzz/hallazgos/`. `make check` repite los guardados.
FUZZ_SEGUNDOS ?= 60
FUZZ_RUNTIME_SEGUNDOS ?= 300
CLANG ?= clang

# Una version: ver `docs/VERSIONES.md`.
paquete:
	@$(PY) tests/paquete.py

probar-paquete:
	@$(PY) tests/paquete.py --probar

# La version vive en dos sitios, y la suite (SALIDA) exige que digan lo
# mismo: `VERSION` y lo que imprime `tcodec --version`. Cambiarla cambia el
# C de tcodec, asi que la semilla se pone al dia.
version:
	@test -n "$(NUEVA)" || { echo "uso: make version NUEVA=1.0.0"; exit 1; }
	@echo "$(NUEVA)" > VERSION
	@sed -i 's/imprimir("tcodec [^"]*\\n");/imprimir("tcodec $(NUEVA)\\n");/' \
	    ejemplos/compilador/tcodec.t
	@$(MAKE) -s --no-print-directory tcodec semilla
	@echo "version $(NUEVA): VERSION, tcodec y la semilla"

fuzz:
	@$(PY) tests/fuzz.py --segundos $(FUZZ_SEGUNDOS)

# Fuzzing del runtime C (safestr.c) con libFuzzer: necesita clang con
# -fsanitize=fuzzer. La entrada se lee como un guion de operaciones sobre
# SafeString y comprueba los invariantes de safestr.h, ademas de ASan+UBSan.
fuzz-safestr:
	@$(CLANG) -g -O1 -fsanitize=fuzzer,address,undefined -I runtime \
	    runtime/safestr.c tests/fuzz_safestr.c -o .cache/fuzz_safestr
	@mkdir -p .cache/safestr-hallazgos
	@ASAN_OPTIONS=quarantine_size_mb=16 .cache/fuzz_safestr \
	    -max_total_time=$(FUZZ_RUNTIME_SEGUNDOS) -rss_limit_mb=1024 \
	    -artifact_prefix=.cache/safestr-hallazgos/ -print_final_stats=1

# Instalado: `PREFIJO/lib/tcode/` lleva tcodec, `std/` y `runtime/` juntos,
# y `PREFIJO/bin/tcodec` es un enlace. tcodec sigue el enlace hasta su
# binario y sube hasta dar con `runtime/`, asi que no hace falta
# `TCODE_RAIZ`. `DESTDIR` es para quien empaqueta.
PREFIJO ?= /usr/local
INSTALADO = $(DESTDIR)$(PREFIJO)/lib/tcode

# El icono y el tipo MIME de `*.t` en el escritorio (Cinnamon/Nemo y GTK en
# general): una "T" como la de los archivos de C. Se pone en el usuario, no en
# el sistema, porque es gusto de quien escribe. `nemo -q` reinicia el gestor
# para que se vea sin cerrar sesion.
icono:
	@mkdir -p $(HOME)/.local/share/mime/packages \
	    $(HOME)/.local/share/icons/hicolor/scalable/mimetypes
	@cp extras/text-x-tcode.xml $(HOME)/.local/share/mime/packages/
	@cp extras/text-x-tcode.svg $(HOME)/.local/share/icons/hicolor/scalable/mimetypes/
	@update-mime-database $(HOME)/.local/share/mime/ 2>/dev/null || true
	@echo "icono de *.t puesto; si no lo ves, cierra y abre Nemo (nemo -q)"

instalar: tcodec
	@install -d $(INSTALADO)/std $(INSTALADO)/runtime/sistema $(DESTDIR)$(PREFIJO)/bin
	@install -m 755 tcodec $(INSTALADO)/tcodec
	@install -m 644 std/*.t std/*.c $(INSTALADO)/std/
	@install -m 644 runtime/*.c runtime/*.h runtime/*.inc $(INSTALADO)/runtime/
	@install -m 644 runtime/sistema/*.inc $(INSTALADO)/runtime/sistema/
	@install -m 644 VERSION $(INSTALADO)/VERSION
	@install -m 755 bin/tcode $(INSTALADO)/tcode
	@ln -sf ../lib/tcode/tcodec $(DESTDIR)$(PREFIJO)/bin/tcodec
	@ln -sf ../lib/tcode/tcode $(DESTDIR)$(PREFIJO)/bin/tcode
	@echo "tcodec $$(cat VERSION) en $(DESTDIR)$(PREFIJO)/bin/tcodec, y el comando tcode al lado"

desinstalar:
	@rm -rf $(INSTALADO)
	@rm -f $(DESTDIR)$(PREFIJO)/bin/tcodec
	@rm -f $(DESTDIR)$(PREFIJO)/bin/tcode
	@echo "quitado de $(DESTDIR)$(PREFIJO)"

bench: tcodec
	@$(PY) bench/medir.py

bench-comprobar: tcodec
	@$(PY) bench/medir.py --comprobar

# Mide lo que la suite mide y deja el resultado en `.cifras.json`. Lo usan
# `check`, que ademas comprueba que el README dice lo mismo, y `cifras`, que lo
# escribe: asi `make cifras` no puede escribir una medida que no corresponda al
# arbol de ahora, que es la trampa que hacia fallar el check una y otra vez.
medir:
	@$(PY) tests/test_lenguaje.py
	@$(PY) tests/test_propiedades.py
	@$(PY) tests/fuzz.py --repetir

check: medir
	@$(PY) tests/cifras.py --comprobar
	@$(PY) tests/grafo.py --comprobar
	@$(MAKE) --no-print-directory lint

# Las secciones rapidas de la suite del lenguaje. Una sola se pide por su
# nombre: `python3 tests/test_lenguaje.py ACEPTA`.
RAPIDAS = RECHAZO AVISA ACEPTA EQUIVALE GENERADOR SALIDA ARCHIVOS ABORTA MODULOS FORMATO LINEAS EJEMPLOS ESPECIFICACION CONGELADO

rapido:
	@$(PY) tests/test_lenguaje.py $(RAPIDAS)

cifras: medir
	@$(PY) tests/cifras.py

grafo:
	@$(PY) tests/grafo.py

propiedades:
	@$(PY) tests/test_propiedades.py

ejemplos: tcodec
	@./tcodec ejemplos/hola.t  >/dev/null && ./ejemplos/hola
	@echo
	@./tcodec ejemplos/texto.t >/dev/null && ./ejemplos/texto
	@echo
	@./tcodec ejemplos/inventario.t >/dev/null && ./ejemplos/inventario
	@echo
	@./tcodec ejemplos/informe/informe.t >/dev/null && ./ejemplos/informe/informe
	@echo
	@./tcodec ejemplos/contar.t >/dev/null && ./ejemplos/contar README.md
	@echo
	@./tcodec ejemplos/frecuencia.t >/dev/null && ./ejemplos/frecuencia README.md 5
	@echo
	@./tcodec ejemplos/ordenar.t >/dev/null && ./ejemplos/ordenar Makefile
	@echo
	@./tcodec ejemplos/lexer/lexer.t >/dev/null && ./ejemplos/lexer/lexer ejemplos/lexer/lexer.t --contar
	@echo
	@./tcodec ejemplos/lexer/parser.t >/dev/null && ./ejemplos/lexer/parser ejemplos/lexer/parser.t --callado

# El binario de un `.t` se llama como el sin la extension. Un `.c` solo se
# borra si lo escribio el compilador: `ejemplos/externo/sistema.c` y
# `lib/sistema_tcodec.c` son fuentes.
limpiar:
	@for f in $$(find ejemplos bench -name '*.t'); do \
	    b=$${f%.t}; if [ -f "$$b" ]; then rm -f "$$b"; fi; \
	done
	@grep -rl --include='*.c' 'Generado por el compilador de Tcode' ejemplos bench std 2>/dev/null \
	    | xargs rm -f
	@rm -f bench/*_c
	@rm -rf tests/__pycache__ .cache
	@rm -f tcodec

# Sin opciones: hay un estilo y es este.
formato: tcodec
	@for f in $$(find std ejemplos bench programas -name '*.t'); do \
	    ./tcodec "$$f" --formatear --escribir; \
	done
	@echo "listo"

# El codigo Python —el compilador de arranque y las suites— pasa `ruff` y
# `mypy`, con lo que dice `pyproject.toml`.
lint:
	@command -v ruff >/dev/null 2>&1 || { \
		echo "lint: falta ruff. Instalalo con:  pipx install ruff"; \
		echo "      y ten ~/.local/bin en el PATH."; exit 1; }
	@command -v mypy >/dev/null 2>&1 || { \
		echo "lint: falta mypy. Instalalo con:  pipx install mypy"; \
		echo "      y ten ~/.local/bin en el PATH."; exit 1; }
	@ruff check
	@mypy

# El mutador: rompe a proposito una regla en los DOS compiladores --un fallo
# compartido, que la comparacion diferencial no puede ver-- y exige que REGLAS,
# RECHAZO o ACEPTA se quejen. Trabaja sobre copias del arbol: no toca el
# repositorio. Tarda minutos, que cada copia construye su tcodec.
mutar:
	@$(PY) tests/mutar.py
