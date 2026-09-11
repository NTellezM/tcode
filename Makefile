# safestr — el lenguaje
#
#   make check      la suite del lenguaje
#   make ejemplos   compila y corre los ejemplos
#   make limpiar

PY ?= python3

.PHONY: all check propiedades bench ejemplos limpiar

all: check

bench:
	@$(PY) bench/medir.py

check:
	@$(PY) tests/test_lenguaje.py
	@$(PY) tests/test_propiedades.py

# Mas programas generados. TCODE_PROGRAMAS=1000 make propiedades
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

limpiar:
	@rm -f ejemplos/hola ejemplos/texto ejemplos/inventario ejemplos/contar ejemplos/*.c
	@rm -f ejemplos/informe/informe ejemplos/informe/*.c
	@rm -rf tcode/__pycache__ tests/__pycache__
