"""
Genera programas de Tcode aleatorios pero validos por construccion.

La idea viene de los tests de ntvidia (~/Proyectos/ntvidia), que no comprueban
ejemplos sino invariantes: `no_starvation`, `sigma_bounds`, `ordering_property`.
Un test por ejemplo solo encuentra lo que a uno se le ocurrio escribir; un
test por propiedad encuentra lo que no se le ocurrio.

Para que la propiedad "todo programa aceptado corre limpio" signifique algo,
el generador tiene que producir programas que:

  - sean validos (si no, solo se prueba el rechazo);
  - no aborten en tiempo de ejecucion, asi que la aritmetica se mantiene
    pequeña y no hay division por variables ni indices fuera de rango;
  - terminen, asi que los `while` llevan siempre su contador.

Las sentencias salen en fases —declarar, mutar, leer— porque asi ningun
prestamo vivo se cruza con una mutacion. Eso no prueba el comprobador de
prestamos (para eso estan los casos de rechazo), prueba que el generador de
codigo no filtra ni libera de mas.
"""

import random

TIPOS_SIMPLES = ["usize", "bool"]
PALABRAS = ["ana", "beto", "cielo", "duna", "eco", "faro", "gris", "hilo"]


class Generador:
    def __init__(self, semilla):
        self.r = random.Random(semilla)
        self.structs = []
        self.funciones = []

    # ---------- utilidades ----------

    def palabra(self):
        return self.r.choice(PALABRAS)

    def num(self, tope=100):
        return self.r.randint(0, tope)

    # ---------- expresiones ----------

    def expr_usize(self, vars_usize, hondura=0):
        """Aritmetica acotada: nunca desborda ni divide por cero."""
        opciones = ["lit"]
        if vars_usize:
            opciones += ["var", "var"]
        if hondura < 2:
            opciones += ["suma", "mod", "mul"]

        cual = self.r.choice(opciones)
        if cual == "lit":
            return str(self.num())
        if cual == "var":
            return self.r.choice(vars_usize)
        if cual == "suma":
            return (f"({self.expr_usize(vars_usize, hondura + 1)} + "
                    f"{self.expr_usize(vars_usize, hondura + 1)})")
        if cual == "mod":
            return (f"({self.expr_usize(vars_usize, hondura + 1)} % "
                    f"{self.r.randint(1, 97)})")
        # multiplicar solo por un literal chico: el producto se queda acotado
        return f"(({self.expr_usize(vars_usize, hondura + 1)} % 50) * {self.r.randint(1, 20)})"

    def expr_bool(self, vars_usize, vars_bool):
        cual = self.r.choice(["cmp", "cmp", "lit", "bool", "not", "y"])
        if cual == "lit" or (cual == "bool" and not vars_bool):
            return self.r.choice(["true", "false"])
        if cual == "bool":
            return self.r.choice(vars_bool)
        if cual == "not":
            return f"(!{self.expr_bool(vars_usize, vars_bool)})"
        if cual == "y":
            return (f"({self.expr_bool(vars_usize, vars_bool)} && "
                    f"{self.expr_bool(vars_usize, vars_bool)})")
        op = self.r.choice(["<", "<=", ">", ">=", "==", "!="])
        return (f"({self.expr_usize(vars_usize)} {op} "
                f"{self.expr_usize(vars_usize)})")

    # ---------- cuerpo de una funcion ----------

    def cuerpo(self, sangria=1):
        """Devuelve (lineas, nombre_del_str_vivo_o_None)."""
        s = "    " * sangria
        lineas = []
        vars_usize, vars_bool, vars_str = [], [], []
        n = [0]

        def nombre(p):
            n[0] += 1
            return f"{p}{n[0]}"

        # --- fase 1: declarar ---
        for _ in range(self.r.randint(1, 4)):
            cual = self.r.choice(["usize", "usize", "bool", "str", "str"])
            v = nombre(cual[0])
            if cual == "usize":
                lineas.append(f"{s}var {v}: usize = {self.expr_usize(vars_usize)};")
                vars_usize.append(v)
            elif cual == "bool":
                lineas.append(f"{s}var {v}: bool = "
                              f"{self.expr_bool(vars_usize, vars_bool)};")
                vars_bool.append(v)
            else:
                lineas.append(f'{s}var {v}: str = nuevo("{self.palabra()}");')
                vars_str.append(v)

        if self.structs and self.r.random() < 0.5:
            st = self.r.choice(self.structs)
            v = nombre("e")
            campos = ", ".join(
                f"{c}: {self.expr_usize(vars_usize)}" for c in st["campos"])
            lineas.append(f"{s}var {v}: {st['nombre']} = "
                          f"{st['nombre']} {{ {campos} }};")
            for c in st["campos"]:
                if self.r.random() < 0.4:
                    lineas.append(f"{s}{v}.{c} = {self.expr_usize(vars_usize)};")
                vars_usize.append(f"{v}.{c}")

        if self.r.random() < 0.5:
            v = nombre("a")
            largo = self.r.randint(2, 5)
            elems = ", ".join(str(self.num()) for _ in range(largo))
            lineas.append(f"{s}var {v}: [usize; {largo}] = [{elems}];")
            idx = self.r.randrange(largo)
            lineas.append(f"{s}{v}[{idx}] = {self.expr_usize(vars_usize)};")
            vars_usize.append(f"{v}[{idx}]")

        # --- fase 2: mutar ---
        for vs in vars_str:
            for _ in range(self.r.randint(0, 3)):
                lineas.append(f'{s}empujar({vs}, "{self.palabra()}");')

        if vars_usize and self.r.random() < 0.6:
            v = vars_usize[0]
            lineas.append(f"{s}{v} = {self.expr_usize(vars_usize)};")

        # --- bucle con contador, siempre termina ---
        if self.r.random() < 0.5:
            i = nombre("i")
            tope = self.r.randint(1, 6)
            lineas.append(f"{s}var {i}: usize = 0;")
            lineas.append(f"{s}while {i} < {tope} {{")
            if vars_str:
                lineas.append(f'{s}    empujar({self.r.choice(vars_str)}, ".");')
            if vars_usize:
                v = vars_usize[0]
                lineas.append(f"{s}    {v} = ({v} + {i}) % 1000;")
            lineas.append(f"{s}    {i} = {i} + 1;")
            lineas.append(f"{s}}}")
            vars_usize.append(i)

        # --- condicional ---
        if self.r.random() < 0.5:
            lineas.append(f"{s}if {self.expr_bool(vars_usize, vars_bool)} {{")
            if vars_usize:
                lineas.append(f"{s}    imprimir({self.r.choice(vars_usize)});")
                lineas.append(f'{s}    imprimir(" ");')
            lineas.append(f"{s}}} else {{")
            lineas.append(f'{s}    imprimir("-");')
            lineas.append(f"{s}}}")

        # --- fase 3: leer. Los prestamos nacen y mueren aqui, sin mutaciones ---
        # Un `str` con una vista con nombre viva no se puede mover despues, asi
        # que se anota cual queda libre para entregarselo a `consumir`.
        libres = []
        for vs in vars_str:
            cual = self.r.random()
            if cual < 0.4:
                lineas.append(f"{s}imprimir({vs});")
                libres.append(vs)
            elif cual < 0.7:
                w = nombre("v")
                lineas.append(f"{s}let {w}: view = vista({vs});")
                lineas.append(f"{s}imprimir(largo({w}));")
            else:
                lineas.append(f"{s}imprimir(largo(vista({vs})));")
                libres.append(vs)
        for v in vars_usize[:2]:
            lineas.append(f"{s}imprimir({v});")
        lineas.append(f'{s}imprimir("\\n");')

        return lineas, (libres[-1] if libres else None)

    # ---------- programa ----------

    def programa(self):
        partes = []

        for k in range(self.r.randint(0, 2)):
            campos = [f"c{j}" for j in range(self.r.randint(1, 3))]
            nombre = f"S{k}"
            self.structs.append({"nombre": nombre, "campos": campos})
            cuerpo = ", ".join(f"{c}: usize" for c in campos)
            partes.append(f"struct {nombre} {{ {cuerpo} }}")

        # una funcion que consume un `str`: prueba los movimientos
        partes.append("fn consumir(s: str) -> usize { return largo(vista(s)); }")

        # una que puede fallar: prueba try y sino
        partes.append(
            "fn mitad(n: usize) -> usize ! {\n"
            "    if n == 0 { falla \"cero\"; }\n"
            "    return n / 2;\n"
            "}")

        auxiliares = []
        for k in range(self.r.randint(0, 2)):
            lineas, _ = self.cuerpo()
            nombre = f"aux{k}"
            auxiliares.append(nombre)
            partes.append(f"fn {nombre}() {{\n" + "\n".join(lineas) + "\n}")

        lineas, str_vivo = self.cuerpo()
        for a in auxiliares:
            lineas.append(f"    {a}();")
        if str_vivo is not None:
            lineas.append(f"    imprimir(consumir({str_vivo}));")
        lineas.append(f"    imprimir(mitad({self.r.randint(1, 50)}) sino 0);")
        lineas.append(f"    imprimir(mitad(0) sino 7);")
        lineas.append('    imprimir("\\n");')
        lineas.append("    return 0;")
        partes.append("fn main() -> usize {\n" + "\n".join(lineas) + "\n}")

        return "\n\n".join(partes) + "\n"


def generar(semilla):
    return Generador(semilla).programa()


if __name__ == "__main__":
    import sys
    print(generar(int(sys.argv[1]) if len(sys.argv) > 1 else 1))
