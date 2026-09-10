# safestr — el lenguaje
#
#   make check      la suite del lenguaje
#   make ejemplos   compila y corre los ejemplos
#   make limpiar

PY ?= python3

.PHONY: all check bench ejemplos limpiar

all: check

bench:
	@$(PY) bench/medir.py

check:
	@$(PY) tests/test_lenguaje.py

ejemplos:
	@$(PY) -m tcode ejemplos/hola.t  >/dev/null && ./ejemplos/hola
	@echo
	@$(PY) -m tcode ejemplos/texto.t >/dev/null && ./ejemplos/texto
	@echo
	@$(PY) -m tcode ejemplos/inventario.t >/dev/null && ./ejemplos/inventario
	@echo
	@$(PY) -m tcode ejemplos/informe/informe.t >/dev/null && ./ejemplos/informe/informe

limpiar:
	@rm -f ejemplos/hola ejemplos/texto ejemplos/inventario ejemplos/*.c
	@rm -f ejemplos/informe/informe ejemplos/informe/*.c
	@rm -rf tcode/__pycache__ tests/__pycache__
