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
            opciones += ["suma", "mod", "mul", "resta", "suelta"]

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
        if cual == "resta":
            # `a - (a % k)` nunca baja de cero: la resta chequeada no aborta
            a = self.expr_usize(vars_usize, hondura + 1)
            return f"({a} - ({a} % {self.r.randint(1, 97)}))"
        if cual == "suelta":
            # los mismos valores acotados, pero con los operadores sin
            # chequeo: no desbordan, y asi se recorre tambien ese camino
            a = self.expr_usize(vars_usize, hondura + 1)
            op = self.r.choice(["suma", "resta", "mul"])
            if op == "suma":
                return f"({a} +? {self.num()})"
            if op == "resta":
                return f"({a} -? ({a} % {self.r.randint(1, 97)}))"
            return f"(({a} % 50) *? {self.r.randint(1, 20)})"
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
        vars_struct = []          # (nombre, tipo) para poder prestarlos
        vars_usize_puros = []     # variables usize sueltas, no campos
        n = [0]

        def nombre(p):
            n[0] += 1
            return f"{p}{n[0]}"

        # --- fase 1: declarar ---
        for _ in range(self.r.randint(1, 4)):
            cual = self.r.choice(["usize", "usize", "bool", "str", "str"])
            v = nombre(cual[0])
            if cual == "usize":
                # A veces con tipo y a veces sin el: las dos formas valen y
                # las dos tienen que probarse.
                anota = ": usize" if self.r.random() < 0.5 else ""
                lineas.append(f"{s}var {v}{anota} = "
                              f"{self.expr_usize(vars_usize)};")
                vars_usize.append(v)
                vars_usize_puros.append(v)
            elif cual == "bool":
                lineas.append(f"{s}var {v}: bool = "
                              f"{self.expr_bool(vars_usize, vars_bool)};")
                vars_bool.append(v)
            else:
                anota = ": str" if self.r.random() < 0.5 else ""
                lineas.append(f'{s}var {v}{anota} = nuevo("{self.palabra()}");')
                vars_str.append(v)

        if self.structs and self.r.random() < 0.5:
            st = self.r.choice(self.structs)
            v = nombre("e")
            campos = ", ".join(
                f"{c}: {self.expr_usize(vars_usize)}" for c in st["campos"])
            if st.get("texto"):
                campos = campos + f', t: nuevo("{self.palabra()}")'
            lineas.append(f"{s}var {v}: {st['nombre']} = "
                          f"{st['nombre']} {{ {campos} }};")
            vars_struct.append((v, st["nombre"]))
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

        # Coleccion de largo decidido en ejecucion. Esto hace que P2 recorra
        # de forma habitual los caminos de realloc, indexacion y liberacion.
        if self.r.random() < 0.7:
            v = nombre("l")
            cuantos = self.r.randint(1, 8)
            lineas.append(f"{s}var {v}: lista<usize> = [];")
            for _ in range(cuantos):
                lineas.append(
                    f"{s}anadir({v}, {self.expr_usize(vars_usize)});")
            idx = self.r.randrange(cuantos)
            lineas.append(f"{s}{v}[{idx}] = {self.expr_usize(vars_usize)};")
            vars_usize.append(f"{v}[{idx}]")
            if self.r.random() < 0.6:
                lineas.append(f"{s}ordenar({v});")
                lineas.append(f"{s}imprimir({v}[0]);")
            if self.r.random() < 0.7:
                e = nombre("e")
                lineas.append(f"{s}for {e} en {v} {{")
                if self.r.random() < 0.4:
                    lineas.append(f"{s}    if {e} % 7 == 0 {{ continue; }}")
                if self.r.random() < 0.4:
                    lineas.append(f"{s}    if {e} > 900 {{ break; }}")
                lineas.append(f"{s}    imprimir({e});")
                lineas.append(f"{s}}}")

        # Lista de valores DUENIOS: cada elemento hay que liberarlo, y al
        # crecer la lista los mueve de sitio. Es el caso que mas facil se
        # rompe y el que menos se escribe a mano.
        if self.r.random() < 0.5:
            v = nombre("ls")
            cuantos = self.r.randint(1, 5)
            lineas.append(f"{s}var {v}: lista<str> = [];")
            for _ in range(cuantos):
                if self.r.random() < 0.5:
                    lineas.append(f'{s}anadir({v}, nuevo("{self.palabra()}"));')
                else:
                    lineas.append(f"{s}anadir({v}, texto("
                                  f"{self.expr_usize(vars_usize)}));")
            # Recorrer una lista de duenios: el elemento llega prestado, y
            # cada vuelta reserva y libera su propio temporal.
            if self.r.random() < 0.7:
                e = nombre("e")
                t2 = nombre("t")
                lineas.append(f"{s}for {e} en {v} {{")
                lineas.append(f"{s}    let {t2}: str = texto(largo(vista({e})));")
                lineas.append(f"{s}    imprimir({t2});")
                if self.r.random() < 0.4:
                    lineas.append(f"{s}    if largo(vista({e})) > 4 {{ break; }}")
                lineas.append(f"{s}}}")
            idx = self.r.randrange(cuantos)
            lineas.append(f"{s}imprimir(largo(vista({v}[{idx}])));")
            # `largo(...)` no es un lugar: se lee, no se le asigna. No entra
            # en vars_usize, que tambien sirve de destino de asignaciones.

        # Mapa: insercion con claves repetidas, consulta de las que estan y de
        # las que no, y recorrido por `claves`. Las claves repetidas importan
        # porque ejercitan el reemplazo, que no reserva clave nueva.
        if self.r.random() < 0.6:
            v = nombre("mp")
            lineas.append(f"{s}var {v}: mapa<str, usize> = [];")
            usadas = [self.palabra() for _ in range(self.r.randint(1, 6))]
            for k in usadas + [self.r.choice(usadas)]:
                lineas.append(f'{s}poner({v}, "{k}", '
                              f"{self.expr_usize(vars_usize)});")
            lineas.append(f'{s}imprimir(tiene({v}, "{usadas[0]}"));')
            lineas.append(f'{s}imprimir(tiene({v}, "no_esta_esta_clave"));')
            lineas.append(f'{s}imprimir(obtener({v}, "{usadas[0]}") sino 0);')
            lineas.append(f'{s}imprimir(obtener({v}, "tampoco") sino 7);')
            if self.r.random() < 0.6:
                lineas.append(f'{s}imprimir(quitar({v}, "{usadas[0]}"));')
                lineas.append(f'{s}imprimir(quitar({v}, "jamas_estuvo"));')
                lineas.append(f'{s}imprimir(tiene({v}, "{usadas[0]}"));')
            # Recorrer el mapa prestando: ni una copia de clave.
            if self.r.random() < 0.7:
                ck = nombre("ck")
                cv = nombre("cv")
                lineas.append(f"{s}for {ck}, {cv} en {v} {{")
                lineas.append(f"{s}    imprimir(largo(vista({ck})) + {cv});")
                if self.r.random() < 0.3:
                    lineas.append(f"{s}    if {cv} > 900 {{ break; }}")
                lineas.append(f"{s}}}")
            if self.r.random() < 0.5:
                ck = nombre("ck")
                lineas.append(f"{s}for {ck} en {v} {{ imprimir(largo(vista({ck}))); }}")

            ks = nombre("ks")
            lineas.append(f"{s}var {ks}: lista<str> = claves({v});")
            lineas.append(f"{s}ordenar({ks});")
            lineas.append(f"{s}imprimir(largo({ks}));")
            if self.r.random() < 0.5:
                lineas.append(f"{s}if largo({ks}) > 0 {{")
                lineas.append(f"{s}    imprimir({ks}[0]);")
                lineas.append(f"{s}}}")

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

        # Prestar structs: el mismo dos veces para leer (permitido), y uno
        # para modificar. Ejercita las reglas y el paso por puntero.
        for st in self.structs:
            tipo_st = st["nombre"]
            propias = [x for x in vars_struct if x[1] == tipo_st]
            if not propias:
                continue
            var_st = self.r.choice(propias)[0]
            lineas.append(f"{s}imprimir(leer_{tipo_st}({var_st}));")
            if self.r.random() < 0.6:
                # dos prestamos de solo lectura de lo mismo: permitido
                lineas.append(
                    f"{s}imprimir(sumar_{tipo_st}({var_st}, {var_st}));")
            if self.r.random() < 0.6:
                lineas.append(f"{s}tocar_{tipo_st}({var_st}, {self.num(50)});")
                lineas.append(f"{s}imprimir(leer_{tipo_st}({var_st}));")

        # Prestar un `str`. Leerlo (`&str`) convive con una vista viva;
        # modificarlo (`mut str`) no, asi que `marcar` solo va sobre los que
        # no tienen ninguna vista con nombre encima.
        if vars_str and self.r.random() < 0.7:
            lineas.append(f"{s}imprimir(medir({self.r.choice(vars_str)}));")
        if libres and self.r.random() < 0.7:
            vs = self.r.choice(libres)
            lineas.append(f"{s}marcar({vs});")
            lineas.append(f"{s}imprimir(medir({vs}));")

        if vars_usize_puros and self.r.random() < 0.5:
            vu = self.r.choice(vars_usize_puros)
            lineas.append(f"{s}doblar({vu});")
            lineas.append(f"{s}imprimir({vu});")

        # Cadenas interpoladas: sueltas y guardadas, con escalares y texto.
        if vars_usize and self.r.random() < 0.7:
            v = self.r.choice(vars_usize)
            lineas.append(f'{s}imprimir($"[{{{v}}}]");')
        if vars_str and vars_usize and self.r.random() < 0.6:
            ip = nombre("ip")
            lineas.append(f'{s}let {ip}: str = $"{{{self.r.choice(vars_str)}}}'
                          f'={{{self.r.choice(vars_usize)}}} {{{{fin}}}}";')
            lineas.append(f"{s}imprimir(largo(vista({ip})));")

        # Mapa de structs: el valor se lee prestado con `&T`.
        if self.structs and self.r.random() < 0.5:
            st = self.r.choice(self.structs)
            ms = nombre("ms")
            lineas.append(f"{s}var {ms}: mapa<str, {st['nombre']}> = [];")
            usadas_mapa = []
            for _ in range(self.r.randint(1, 3)):
                campos = ", ".join(f"{c}: {self.expr_usize(vars_usize)}"
                                   for c in st["campos"])
                if st.get("texto"):
                    campos = campos + f', t: nuevo("{self.palabra()}")'
                k = self.palabra()
                usadas_mapa.append(k)
                lineas.append(f'{s}poner({ms}, "{k}", '
                              f"{st['nombre']} {{ {campos} }});")
            # Modificar EN EL SITIO lo que guarda el mapa: `obtener_mut`
            # devuelve un `&mut T` y por el se escribe sin sacar nada.
            clave_viva = usadas_mapa[0]
            if self.r.random() < 0.7:
                mu = nombre("mu")
                lineas.append(f'{s}if tiene({ms}, "{clave_viva}") {{')
                lineas.append(f"{s}    let {mu}: &mut {st['nombre']} = "
                              f'try obtener_mut({ms}, "{clave_viva}");')
                lineas.append(f"{s}    {mu}.{st['campos'][0]} = "
                              f"({mu}.{st['campos'][0]} + 1) % 1000;")
                lineas.append(f"{s}}}")

            # Y leerlo prestado, sin copiarlo.
            if self.r.random() < 0.6:
                ro = nombre("ro")
                lineas.append(f'{s}if tiene({ms}, "{clave_viva}") {{')
                # Sin anotar: `obtener` devuelve una copia si el struct no
                # posee memoria, y un prestamo si la posee. La inferencia se
                # encarga, y asi se prueban los dos caminos.
                lineas.append(f"{s}    let {ro} = "
                              f'try obtener({ms}, "{clave_viva}");')
                lineas.append(f"{s}    imprimir({ro}.{st['campos'][0]});")
                lineas.append(f"{s}}}")
            rk = nombre("rk")
            rv = nombre("rv")
            lineas.append(f"{s}for {rk}, {rv} en {ms} {{")
            lineas.append(f"{s}    imprimir(largo(vista({rk})) + "
                          f"{rv}.{st['campos'][0]});")
            lineas.append(f"{s}}}")

        # Mapa de textos: valor duenio, prestado al leerlo.
        if self.r.random() < 0.5:
            mt = nombre("mt")
            lineas.append(f"{s}var {mt}: mapa<str, str> = [];")
            usadas_texto = []
            for _ in range(self.r.randint(1, 4)):
                k = self.palabra()
                usadas_texto.append(k)
                lineas.append(f'{s}poner({mt}, "{k}", '
                              f'nuevo("{self.palabra()}"));')
            lineas.append(f'{s}imprimir(largo(obtener({mt}, "no_esta") sino ""));')
            if usadas_texto and self.r.random() < 0.6:
                mm = nombre("mm")
                lineas.append(f'{s}if tiene({mt}, "{usadas_texto[0]}") {{')
                lineas.append(f"{s}    let {mm}: &mut str = "
                              f'try obtener_mut({mt}, "{usadas_texto[0]}");')
                lineas.append(f'{s}    empujar({mm}, "+");')
                lineas.append(f"{s}}}")
            ck = nombre("ck")
            cv = nombre("cv")
            lineas.append(f"{s}for {ck}, {cv} en {mt} {{")
            lineas.append(f"{s}    imprimir(largo(vista({ck})) + largo({cv}));")
            lineas.append(f"{s}}}")

        # `texto` de un escalar: un `str` recien creado que hay que liberar.
        if vars_usize and self.r.random() < 0.5:
            t = nombre("t")
            lineas.append(f"{s}let {t}: str = texto("
                          f"{self.r.choice(vars_usize)});")
            lineas.append(f"{s}imprimir({t});")

        # Comparacion de orden entre textos.
        if vars_str and self.r.random() < 0.5:
            lineas.append(f'{s}imprimir(menor(vista({self.r.choice(vars_str)}), '
                          f'"{self.palabra()}"));')

        # `byte` con indice acotado por el largo: nunca se sale.
        if vars_str and self.r.random() < 0.5:
            vs = self.r.choice(vars_str)
            lineas.append(f"{s}if largo(vista({vs})) > 0 {{")
            lineas.append(f"{s}    imprimir(byte(vista({vs}), 0));")
            lineas.append(f"{s}}}")

        # `sino` con una alternativa DUENIA. La alternativa se consume solo si
        # la llamada falla, asi que en el otro camino sigue siendo nuestra.
        # Aqui se genera con las dos ramas, a proposito.
        if self.r.random() < 0.6:
            for falla_ahora in (0, self.r.randint(1, 9)):
                res = nombre("r")
                alt = nombre("alt")
                lineas.append(f'{s}let {alt}: str = nuevo("{self.palabra()}");')
                lineas.append(f"{s}let {res}: str = "
                              f"puede_fallar({falla_ahora}) sino {alt};")
                lineas.append(f"{s}imprimir(largo(vista({res})));")

        if self.r.random() < 0.4:
            lineas.append(f'{s}imprimir_error("");')
        lineas.append(f'{s}imprimir("\\n");')

        return lineas, (libres[-1] if libres else None)

    # ---------- programa ----------

    def programa(self):
        partes = []

        for k in range(self.r.randint(0, 2)):
            campos = [f"c{j}" for j in range(self.r.randint(1, 3))]
            nombre = f"S{k}"
            # Alguno con texto dentro: asi hay structs que POSEEN memoria, y
            # un mapa que los guarde presta en vez de copiar.
            con_texto = self.r.random() < 0.5
            self.structs.append({"nombre": nombre, "campos": campos,
                                 "texto": "t" if con_texto else None})
            cuerpo = ", ".join(f"{c}: usize" for c in campos)
            if con_texto:
                cuerpo = cuerpo + ", t: str"
            partes.append(f"struct {nombre} {{ {cuerpo} }}")

        # Funciones que reciben PRESTAMOS. Es la parte del lenguaje con mas
        # reglas —no mover lo prestado, no modificar lo compartido, no
        # prestar dos veces si uno modifica— y la unica que hasta ahora solo
        # se probaba con casos escritos a mano.
        for st in self.structs:
            n = st["nombre"]
            c0 = st["campos"][0]
            partes.append(
                f"fn leer_{n}(x: &{n}) -> usize {{ return x.{c0}; }}")
            partes.append(
                f"fn sumar_{n}(a: &{n}, b: &{n}) -> usize {{\n"
                f"    return (a.{c0} % 1000) + (b.{c0} % 1000);\n"
                f"}}")
            partes.append(
                f"fn tocar_{n}(x: mut {n}, d: usize) {{\n"
                f"    x.{c0} = (x.{c0} + d) % 1000;\n"
                f"}}")

        # Prestamos de `str`: leer sin copiar y modificar en el sitio.
        partes.append("fn medir(s: &str) -> usize { return largo(vista(s)); }")
        partes.append('fn marcar(s: mut str) { empujar(s, "#"); }')
        partes.append("fn doblar(n: mut usize) { n = (n * 2) % 1000; }")

        # una funcion que consume un `str`: prueba los movimientos
        partes.append("fn consumir(s: str) -> usize { return largo(vista(s)); }")

        # una que puede fallar: prueba try y sino
        partes.append(
            "fn mitad(n: usize) -> usize ! {\n"
            "    if n == 0 { falla \"cero\"; }\n"
            "    return n / 2;\n"
            "}")

        # Devuelve un `str` o falla. Sirve para ejercitar los dos caminos de
        # `sino` cuando la alternativa es duenia de su memoria.
        partes.append(
            "fn puede_fallar(n: usize) -> str ! {\n"
            "    if n != 0 { falla \"pedido\"; }\n"
            "    return nuevo(\"logrado\");\n"
            "}")

        # Lee un archivo que no existe: el camino de fallo de la E/S, con una
        # alternativa que tambien hay que liberar.
        partes.append(
            "fn leer_o(alterno: str) -> str {\n"
            "    return leer_archivo(\"/no/existe/tampoco\") sino alterno;\n"
            "}")

        # Un `str` temporal dentro de lo que se devuelve. Los cinco caminos
        # que salen antes de tiempo tienen que soltarlo: la limpieza de fin
        # de sentencia se emite detras del `return` y no se ejecuta.
        partes.append(
            "fn envuelto(n: usize) -> str {\n"
            "    return $\"[{copia(n)}]\";\n"
            "}")
        partes.append(
            "fn envuelto_falible(n: usize) -> str ! {\n"
            "    if n > 900 { falla \"grande\"; }\n"
            "    let dentro = try puede_fallar(0);\n"
            "    return $\"<{copia(n)}|{dentro}>\";\n"
            "}")
        partes.append(
            "fn copia(n: usize) -> str {\n"
            "    var s = nuevo(\"n=\");\n"
            "    empujar(s, texto(n));\n"
            "    return s;\n"
            "}")

        auxiliares = []
        for k in range(self.r.randint(0, 2)):
            lineas, _ = self.cuerpo()
            nombre = f"aux{k}"
            auxiliares.append(nombre)
            # Falibles: el cuerpo puede usar `try` (obtener_mut, dividir...).
            partes.append(f"fn {nombre}() ! {{\n" + "\n".join(lineas) + "\n}")

        lineas, str_vivo = self.cuerpo()
        for a in auxiliares:
            lineas.append(f"    try {a}();")
        if str_vivo is not None:
            lineas.append(f"    imprimir(consumir({str_vivo}));")
        lineas.append(f"    imprimir(mitad({self.r.randint(1, 50)}) sino 0);")
        lineas.append(f"    imprimir(envuelto({self.r.randint(0, 99)}));")
        lineas.append(f"    imprimir(envuelto_falible({self.r.randint(0, 99)}) "
                      f"sino nuevo(\"nada\"));")
        lineas.append(f"    imprimir(mitad(0) sino 7);")
        lineas.append(f'    let respaldo: str = nuevo("respaldo");')
        lineas.append(f"    let leido: str = leer_o(respaldo);")
        lineas.append(f"    imprimir(largo(vista(leido)));")
        lineas.append('    imprimir("\\n");')
        lineas.append("    return 0;")
        partes.append("fn main() -> usize ! {\n" + "\n".join(lineas) + "\n}")

        return "\n\n".join(partes) + "\n"


def generar(semilla):
    return Generador(semilla).programa()


def generar_modulos(semilla):
    """Un programa repartido en archivos, con `usar` entre ellos.

    Devuelve {ruta relativa: contenido}. El principal se llama `app.t`.
    Prueba lo que un archivo suelto no toca: que los structs y las funciones
    crucen de modulo a modulo, y que la carga en rombo no duplique nada.
    """
    g = Generador(semilla)
    r = g.r

    # Un modulo de base con un struct y funciones sobre el.
    campos = [f"c{j}" for j in range(r.randint(1, 2))]
    con_texto = r.random() < 0.5
    cuerpo = ", ".join(f"{c}: usize" for c in campos)
    if con_texto:
        cuerpo += ", t: str"
    base = [f"struct Dato {{ {cuerpo} }}", ""]
    base.append("fn primero(d: &Dato) -> usize { return d." + campos[0] + "; }")
    base.append("fn subir(d: mut Dato, cuanto: usize) {")
    base.append(f"    d.{campos[0]} = (d.{campos[0]} + cuanto) % 1000;")
    base.append("}")
    # un `str` que nace en un modulo y muere en otro: la responsabilidad de
    # liberarlo cruza el archivo
    base.append("")
    base.append("fn etiqueta(d: &Dato) -> str {")
    base.append(f'    var e: str = nuevo("{g.palabra()}");')
    base.append("    empujar(e, \"=\");")
    base.append(f"    return e;")
    base.append("}")
    # una funcion falible declarada aqui y usada con `try` alla
    base.append("")
    base.append("fn chequear(n: usize) -> usize ! {")
    base.append(f"    if n > {r.randint(900, 1200)} {{ falla \"muy grande\"; }}")
    base.append("    return n;")
    base.append("}")

    valores = ", ".join(f"{c}: {r.randint(0, 99)}" for c in campos)
    if con_texto:
        valores += f', t: nuevo("{g.palabra()}")'

    # Un modulo intermedio que usa el de base: la carga es en cadena.
    medio = ['usar "base.t";', "",
             "fn crear() -> Dato {",
             f"    return Dato {{ {valores} }};",
             "}", "",
             "fn doble(d: &Dato) -> usize { return primero(d) * 2; }"]

    # El principal usa los dos: el de base llega por dos caminos y no se
    # puede cargar dos veces.
    app = ['usar "lib/medio.t";', 'usar "lib/base.t";', "",
           "fn main() -> usize ! {",
           "    var d = crear();",
           f"    subir(d, {r.randint(1, 50)});",
           '    imprimir($"{primero(d)} {doble(d)}");']
    if con_texto:
        app.append('    imprimir($" {d.t}");')
    app.append("    let e: str = etiqueta(d);")
    app.append('    imprimir($" {e}");')
    app.append("    let v = try chequear(primero(d));")
    app.append('    imprimir($" {v}");')
    app += ['    imprimir("' + chr(92) + 'n");', "    return 0;", "}"]

    return {
        "lib/base.t": "\n".join(base) + "\n",
        "lib/medio.t": "\n".join(medio) + "\n",
        "app.t": "\n".join(app) + "\n",
    }


if __name__ == "__main__":
    import sys
    print(generar(int(sys.argv[1]) if len(sys.argv) > 1 else 1))
