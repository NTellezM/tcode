# Tcode
#
#   make check        la suite del lenguaje
#   make propiedades  solo los tests por propiedad (TCODE_PROGRAMAS=1000 para mas)
#   make ejemplos     compila y corre los ejemplos
#   make bench        Tcode contra el mismo programa en C a mano
#   make formato      deja todo el codigo Tcode en el formato canonico
#   make limpiar      borra lo que genera todo lo anterior

PY ?= python3

.PHONY: all check propiedades bench ejemplos limpiar formato

all: check

bench:
	@$(PY) bench/medir.py

check:
	@$(PY) tests/test_lenguaje.py
	@$(PY) tests/test_propiedades.py

propiedades:
	@$(PY) tests/test_propiedades.py

ejemplos:
	@$(PY) -m tcode ejemplos/hola.t  >/dev/null && ./ejemplos/hola
	@echo
	@$(PY) -m tcode ejemplos/texto.t >/dev/null && ./ejemplos/texto
	@echo
	@$(PY) -m tcode ejemplos/inventario.t >/dev/null && ./ejemplos/inventario
	@echo
	@$(PY) -m tcode ejemplos/informe/informe.t >/dev/null && ./ejemplos/informe/informe
	@echo
	@$(PY) -m tcode ejemplos/contar.t >/dev/null && ./ejemplos/contar README.md
	@echo
	@$(PY) -m tcode ejemplos/frecuencia.t >/dev/null && ./ejemplos/frecuencia README.md 5
	@echo
	@$(PY) -m tcode ejemplos/ordenar.t >/dev/null && ./ejemplos/ordenar Makefile
	@echo
	@$(PY) -m tcode ejemplos/lexer/lexer.t >/dev/null && ./ejemplos/lexer/lexer ejemplos/lexer/lexer.t --contar
	@echo
	@$(PY) -m tcode ejemplos/lexer/parser.t >/dev/null && ./ejemplos/lexer/parser ejemplos/lexer/parser.t --callado

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
	@rm -rf tcode/__pycache__ tests/__pycache__

# Sin opciones: hay un estilo y es este.
formato:
	@for f in $$(find std ejemplos bench -name '*.t'); do \
	    $(PY) -m tcode "$$f" --formatear --escribir; \
	done
	@echo "listo"
