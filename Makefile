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
#   make formato      deja todo el codigo Tcode en el formato canonico
#   make lint         revisa el codigo Python con ruff y mypy
#   make limpiar      borra lo que genera todo lo anterior

PY ?= python3

.PHONY: all check rapido propiedades cifras bench ejemplos limpiar formato lint semilla

all: tcodec

# El compilador es `tcodec`, escrito en Tcode. Se construye desde su C
# semilla, `bootstrap/tcodec.c`: el C que `tcodec` escribe de si mismo,
# guardado en el repositorio como hacen Zig y Go. Compilada, la semilla es la
# etapa 0, y la etapa 0 compila `tcodec.t` tal como esta ahora. No hace falta
# Python: solo un compilador de C.
SEMILLA = bootstrap/tcodec.c
ETAPA0 = .cache/tcodec0
SISTEMA = ejemplos/compilador/lib/sistema_tcodec.c
RUNTIME_C = runtime/safestr.c
TCODEC_FUENTES = $(wildcard ejemplos/compilador/*.t ejemplos/compilador/lib/*.t \
	ejemplos/compilador/lib/*.c ejemplos/lexer/lib/*.t std/*.t runtime/* \
	runtime/sistema/*)

$(ETAPA0): $(SEMILLA) $(SISTEMA) $(wildcard runtime/*)
	@mkdir -p .cache
	@$(CC) -std=c17 -O1 -Iruntime $(SEMILLA) $(RUNTIME_C) $(SISTEMA) -o $@ -lm

tcodec: $(ETAPA0) $(TCODEC_FUENTES)
	@TCODE_RAIZ=. ./$(ETAPA0) ejemplos/compilador/tcodec.t -o tcodec

# La semilla al dia: el C que escribe de si mismo el `tcodec` de ahora. Antes
# de guardarla se comprueba que es un punto fijo: compilada, vuelve a
# escribir exactamente ese C. Hace falta cuando `tcodec.t` quiere usar algo
# que la semilla vieja todavia no sabe compilar.
semilla: tcodec
	@TCODE_RAIZ=. ./tcodec ejemplos/compilador/tcodec.t --mostrar-c > .cache/semilla.c
	@$(CC) -std=c17 -O1 -Iruntime .cache/semilla.c $(RUNTIME_C) $(SISTEMA) -o .cache/semilla -lm
	@TCODE_RAIZ=. ./.cache/semilla ejemplos/compilador/tcodec.t --mostrar-c \
	    | cmp -s - .cache/semilla.c \
	    || { echo "la semilla nueva no se reproduce a si misma"; exit 1; }
	@mv .cache/semilla.c $(SEMILLA)
	@echo "semilla al dia: $(SEMILLA)"

bench:
	@$(PY) bench/medir.py

check:
	@$(PY) tests/test_lenguaje.py
	@$(PY) tests/test_propiedades.py
	@$(PY) tests/cifras.py --comprobar

# Las secciones que prueban el lenguaje con `tcodec`; las que tardan son las
# que comparan sus capas con las del compilador de Python. Una sola se pide
# por su nombre: `python3 tests/test_lenguaje.py ACEPTA`.
RAPIDAS = RECHAZO AVISA ACEPTA SALIDA ARCHIVOS ABORTA MODULOS FORMATO LINEAS EJEMPLOS

rapido:
	@$(PY) tests/test_lenguaje.py $(RAPIDAS)

cifras:
	@$(PY) tests/cifras.py

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
	@rm -rf tcode/__pycache__ tests/__pycache__ .cache
	@rm -f tcodec

# Sin opciones: hay un estilo y es este.
formato: tcodec
	@for f in $$(find std ejemplos bench -name '*.t'); do \
	    ./tcodec "$$f" --formatear --escribir; \
	done
	@echo "listo"

# El codigo Python —el compilador de arranque y las suites— pasa `ruff` y
# `mypy`, con lo que dice `pyproject.toml`.
lint:
	@ruff check
	@mypy
