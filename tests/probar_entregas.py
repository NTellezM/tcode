import os
import sys, os, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generador_entregas as G
fuente, esperado = G.generar(int(sys.argv[1]))
d = tempfile.mkdtemp(); open(f"{d}/p.t","w").write(fuente)
import subprocess
r = subprocess.run([os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tcodec"), f"{d}/p.t", "-o", f"{d}/p", "--asan", "--sin-avisos"], capture_output=True, text=True)
if r.returncode: print("NO COMPILA:", r.stderr[:1500]); print(fuente[:3000]); sys.exit(1)
e = subprocess.run([f"{d}/p"], capture_output=True, text=True, env=dict(os.environ, ASAN_OPTIONS="detect_leaks=1:halt_on_error=1"))
import re
m = re.search(r"ERROR: AddressSanitizer: [a-z-]+|ERROR: LeakSanitizer: [a-z ]+|runtime error", e.stderr)
if e.stdout == esperado and e.returncode == 0 and not m: print("BIEN")
else: print("FALLA:", m.group(0) if m else "", "salida", repr(e.stdout), "esperada", repr(esperado), "codigo", e.returncode)
