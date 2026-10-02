#!/usr/bin/env bash
# Instala tcode y tcodec en ~/.local (sin sudo).
#
#   ./instalar.sh
#
# O en otro sitio:  PREFIJO=/usr/local ./instalar.sh
set -euo pipefail

PREFIJO="${PREFIJO:-$HOME/.local}"

make instalar PREFIJO="$PREFIJO"

echo ""
echo "Instalado en $PREFIJO. Para que \`tcode\` funcione desde cualquier sitio,"
echo "añade a tu ~/.bashrc (o ~/.zshrc):"
echo ""
echo "  export PATH=\"$PREFIJO/bin:\$PATH\""
echo ""
echo "Y listo:"
echo "  tcode version"
echo "  tcode nuevo hola && cd hola && tcode correr main.t"
