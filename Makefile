# safestr — el lenguaje
#
#   make check      la suite del lenguaje
#   make ejemplos   compila y corre los ejemplos
#   make limpiar

PY ?= python3

.PHONY: all check ejemplos limpiar

all: check

check:
	@$(PY) tests/test_lenguaje.py

ejemplos:
	@$(PY) -m safestrc ejemplos/hola.sfs  >/dev/null && ./ejemplos/hola
	@echo
	@$(PY) -m safestrc ejemplos/texto.sfs >/dev/null && ./ejemplos/texto
	@echo
	@$(PY) -m safestrc ejemplos/inventario.sfs >/dev/null && ./ejemplos/inventario
	@echo
	@$(PY) -m safestrc ejemplos/informe/informe.sfs >/dev/null && ./ejemplos/informe/informe

limpiar:
	@rm -f ejemplos/hola ejemplos/texto ejemplos/inventario ejemplos/*.c
	@rm -f ejemplos/informe/informe ejemplos/informe/*.c
	@rm -rf safestrc/__pycache__ tests/__pycache__
