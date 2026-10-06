"""
Genera programas de Tcode aleatorios pero validos por construccion.

Los tests por propiedad no comprueban ejemplos sino invariantes. Un test por
ejemplo solo encuentra lo que a uno se le ocurrio escribir; un test por
propiedad encuentra lo que no se le ocurrio.

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

La fase de leer incluye, ademas, las lecturas que atraviesan un `if` o un
`match` como valor —`largo(if c { xs } else { ys })`, `for x en if ...`,
`(if c { p } else { q }).campo`, `match if c { a } else { b } { ... }`, y la
mixta— con duenio y usando la variable **despues**. Esa es la zona por la
que salieron los defectos de memoria del generador de C, y la que casi no
se tocaba: alli la rama se presta, no se mueve, y el duenio tiene que
llegar entero a la sentencia siguiente (`lecturas_por_condicional`).
"""

import random

TIPOS_SIMPLES = ["usize", "bool"]
PALABRAS = ["ana", "beto", "cielo", "duna", "eco", "faro", "gris", "hilo"]


class Generador:
    def __init__(self, semilla):
        self.r = random.Random(semilla)
        self.structs = []
        self.enums = []
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
        vars_lista_duenia = []    # `list<str>`: cada elemento es un duenio
        vars_lista_simple = []    # `list<usize>`: copiable, no posee nada
        vars_mapa = []            # `map<str, usize>`
        vars_enum = []            # (nombre, descripcion del enum)
        n = [0]

        def nombre(p):
            # Con guion: `u8` e `i8` son tipos, y un nombre como `u8` dejo de
            # ser legal cuando llegaron los anchos fijos.
            n[0] += 1
            return f"{p}_{n[0]}"

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

        if self.structs and self.r.random() < 0.7:
            # Uno o dos valores: las formas de lectura que pasan por un `if`
            # necesitan dos del mismo tipo, y con uno solo no hay condicional.
            for _ in range(self.r.randint(1, 2)):
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
                        lineas.append(f"{s}{v}.{c} = "
                                      f"{self.expr_usize(vars_usize)};")
                    vars_usize.append(f"{v}.{c}")

        # Un enum con duenio dentro: es lo que hace que mover un brazo de
        # `match` se note, y lo que da escrutinio a `match if ...`. El
        # primero siempre tiene valores: el `match` como valor lo necesita.
        for i, e in enumerate(self.enums):
            if i > 0 and self.r.random() >= 0.6:
                continue
            for _ in range(self.r.randint(1, 2)):
                v = nombre("en")
                rama = self.r.choice(["A", "B"])
                if e["carga"] is None:
                    lineas.append(f"{s}let {v}: {e['nombre']} = "
                                  f"{e['nombre']}.{rama};")
                else:
                    lineas.append(f'{s}let {v}: {e["nombre"]} = '
                                  f'{e["nombre"]}.{rama}'
                                  f'(nuevo("{self.palabra()}"));')
                vars_enum.append((v, e))

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
            lineas.append(f"{s}var {v}: list<usize> = [];")
            vars_lista_simple.append(v)
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
            lineas.append(f"{s}var {v}: list<str> = [];")
            vars_lista_duenia.append(v)
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
            lineas.append(f"{s}var {v}: map<str, usize> = [];")
            vars_mapa.append(v)
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
            lineas.append(f"{s}var {ks}: list<str> = claves({v});")
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

        # La zona que el generador casi no tocaba: una lectura con duenio que
        # atraviesa un `if` o un `match` como valor, y el duenio usado despues.
        lineas.extend(self.lecturas_por_condicional(s, nombre, {
            "usize": vars_usize, "bool": vars_bool,
            "lista_duenia": vars_lista_duenia,
            "lista_simple": vars_lista_simple,
            "mapa": vars_mapa, "struct": vars_struct, "enum": vars_enum}))

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
            lineas.append(f"{s}var {ms}: map<str, {st['nombre']}> = [];")
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
            lineas.append(f"{s}var {mt}: map<str, str> = [];")
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

    # ---------- lecturas que atraviesan un `if` o un `match` ----------

    def lecturas_por_condicional(self, s, nombre, ctx):
        """La zona que el generador casi no tocaba: una lectura con duenio
        que pasa por un `if` o un `match` como valor, y **el uso del duenio
        despues**.

        La rama de un `if` o de un `match` leido se **presta**: no se mueve,
        y la variable tiene que seguir viva y entera al acabar la sentencia.
        Usarla despues es lo que hace visible el movimiento equivocado, que
        es como salieron los defectos: doble `free`, uso tras liberar y
        fugas. Cada forma se emite solo si el cuerpo declaro con que.
        """
        r = self.r
        lineas = []
        vusize, vbool = ctx["usize"], ctx["bool"]
        listas_d = ctx["lista_duenia"]
        listas_s = ctx["lista_simple"]
        mapas = ctx["mapa"]
        enums = ctx["enum"]

        def cond():
            # Con variable cuando la hay: asi las dos ramas se recorren de
            # verdad, segun lo que valga en ejecucion, y no una sola.
            return self.expr_bool(vusize, vbool)

        def par_de(lista, tipo):
            """Dos nombres distintos de la misma clase. Si solo hay uno, el
            companero nace aqui, con `copiar`, y se usa en la misma forma:
            asi no queda una declaracion sin uso, que el compilador avisa."""
            if len(lista) >= 2:
                return r.sample(lista, 2)
            if len(lista) == 1:
                y = nombre("p")
                lineas.append(f"{s}let {y}: {tipo} = copiar({lista[0]});")
                return [lista[0], y]
            return None

        # Structs que POSEEN memoria, por tipo: hacen falta dos del mismo
        # tipo para que el `if` sea un condicional de verdad.
        por_tipo = {}
        for v, t in ctx["struct"]:
            st = next((x for x in self.structs if x["nombre"] == t), None)
            if st and st.get("texto"):
                por_tipo.setdefault(t, []).append(v)
        unitarios = [v for v, e in enums if e["carga"] is None]

        # 1. `largo(if c { xs } else { ys })`, sobre una lista y sobre un
        # mapa, y despues se recorre `xs`.
        if r.random() < 0.7:
            par = par_de(listas_d, "list<str>")
            if par:
                x, y = par
                n1 = nombre("n")
                lineas.append(f"{s}let {n1}: usize = "
                              f"largo(if {cond()} {{ {x} }} else {{ {y} }});")
                lineas.append(f"{s}imprimir({n1});")
                lineas.append(f"{s}imprimir(largo({x}));")
        if r.random() < 0.7:
            par = par_de(mapas, "map<str, usize>")
            if par:
                x, y = par
                n1, k1 = nombre("n"), nombre("k")
                lineas.append(f"{s}let {n1}: usize = "
                              f"largo(if {cond()} {{ {x} }} else {{ {y} }});")
                lineas.append(f"{s}imprimir({n1});")
                lineas.append(f"{s}for {k1} en {x} {{ "
                              f"imprimir(largo(vista({k1}))); }}")
        # La misma lectura, pero el condicional es un `match`: los brazos se
        # prestan igual, y el duenio tiene que llegar entero detras.
        if unitarios and r.random() < 0.6:
            ev = r.choice(unitarios)
            nombre_e = next(e["nombre"] for v, e in enums if v == ev)
            par = par_de(listas_d, "list<str>")
            if par:
                x, y = par
                n1 = nombre("n")
                lineas.append(f"{s}let {n1}: usize = largo(match {ev} {{ "
                              f"{nombre_e}.A -> {x}, {nombre_e}.B -> {y} }});")
                lineas.append(f"{s}imprimir({n1});")
                lineas.append(f"{s}imprimir(largo({x}));")

        # 2. `for x en if c { xs } else { ys } { ... }`, y luego `xs`.
        if r.random() < 0.7:
            par = par_de(listas_s, "list<usize>")
            if par:
                x, y = par
                acc, e2 = nombre("acc"), nombre("e")
                lineas.append(f"{s}var {acc}: usize = 0;")
                lineas.append(f"{s}for {e2} en if {cond()} "
                              f"{{ {x} }} else {{ {y} }} {{")
                lineas.append(f"{s}    {acc} = ({acc} + {e2}) % 1000;")
                lineas.append(f"{s}}}")
                lineas.append(f"{s}imprimir({acc});")
                lineas.append(f"{s}imprimir({x}[0]);")
        if r.random() < 0.7:
            par = par_de(listas_d, "list<str>")
            if par:
                x, y = par
                acc, e2 = nombre("acc"), nombre("e")
                lineas.append(f"{s}var {acc}: usize = 0;")
                lineas.append(f"{s}for {e2} en if {cond()} "
                              f"{{ {x} }} else {{ {y} }} {{")
                lineas.append(f"{s}    {acc} = {acc} + largo({e2});")
                lineas.append(f"{s}}}")
                lineas.append(f"{s}imprimir({acc});")
                lineas.append(f"{s}imprimir(largo({x}));")
        if r.random() < 0.7:
            par = par_de(mapas, "map<str, usize>")
            if par:
                x, y = par
                acc, k1, k2 = nombre("acc"), nombre("k"), nombre("k")
                lineas.append(f"{s}var {acc}: usize = 0;")
                lineas.append(f"{s}for {k1} en if {cond()} "
                              f"{{ {x} }} else {{ {y} }} {{")
                lineas.append(f"{s}    {acc} = {acc} + 1;")
                lineas.append(f"{s}}}")
                lineas.append(f"{s}imprimir({acc});")
                lineas.append(f"{s}for {k2} en {x} {{ "
                              f"imprimir(largo(vista({k2}))); }}")

        # 3, 4, 5 y 7, con structs que poseen memoria: el campo de un `if`
        # leido, guardado y descartado; la condicion de un `si` y de un
        # `mientras`, que tambien son contexto de lectura; el `match` como
        # valor leido; y la mixta, con una rama que es un sitio y la otra un
        # valor recien hecho. En todas, `p` y `q` se usan despues.
        for tipo, vs in sorted(por_tipo.items()):
            if not vs or r.random() >= 0.85:
                continue
            st = next(x for x in self.structs if x["nombre"] == tipo)
            campo = st["campos"][0]
            pareja = list(vs)
            if len(pareja) < 2:
                comp = nombre("e")
                campos = ", ".join(f"{c}: {self.num()}"
                                   for c in st["campos"])
                if st.get("texto"):
                    campos += f', t: nuevo("{self.palabra()}")'
                lineas.append(f"{s}let {comp}: {tipo} = "
                              f"{tipo} {{ {campos} }};")
                pareja.append(comp)
            p, q = r.sample(pareja, 2)
            r3 = nombre("r")
            lineas.append(f"{s}let {r3}: usize = "
                          f"(if {cond()} {{ {p} }} else {{ {q} }}).{campo};")
            lineas.append(f"{s}imprimir({r3});")
            lineas.append(f'{s}imprimir($"{{{p}.t}}");')
            if r.random() < 0.7:
                lineas.append(f"{s}(if {cond()} "
                              f"{{ {p} }} else {{ {q} }}).{campo};")
                lineas.append(f'{s}imprimir($"{{{q}.t}}");')
            if r.random() < 0.7:
                lineas.append(f"{s}if (if {cond()} {{ {p} }} else {{ {q} }})."
                              f"{campo} == {p}.{campo} {{")
                lineas.append(f'{s}    imprimir("leido");')
                lineas.append(f"{s}}}")
                lineas.append(f'{s}imprimir($"{{{p}.t}}");')
            if r.random() < 0.5:
                w = nombre("w")
                lineas.append(f"{s}var {w}: usize = 0;")
                lineas.append(f"{s}while {w} < 1 && (if {cond()} "
                              f"{{ {p} }} else {{ {q} }}).{campo} == "
                              f"{p}.{campo} {{")
                lineas.append(f"{s}    {w} = {w} + 1;")
                lineas.append(f"{s}}}")
                lineas.append(f'{s}imprimir($"{{{q}.t}}");')
            if unitarios and r.random() < 0.7:
                ev = r.choice(unitarios)
                nombre_e = next(e["nombre"] for v, e in enums if v == ev)
                r6 = nombre("r")
                lineas.append(f"{s}let {r6}: usize = leer_{tipo}(match {ev} {{ "
                              f"{nombre_e}.A -> {p}, {nombre_e}.B -> {q} }});")
                lineas.append(f"{s}imprimir({r6});")
                lineas.append(f'{s}imprimir($"{{{p}.t}}");')
                # El campo de un `match` leido, que es el mismo caso por el
                # otro camino: el brazo se presta y `p` y `q` siguen ahi.
                r9 = nombre("r")
                lineas.append(f"{s}let {r9}: usize = (match {ev} {{ "
                              f"{nombre_e}.A -> {p}, {nombre_e}.B -> {q} }})."
                              f"{campo};")
                lineas.append(f"{s}imprimir({r9});")
                lineas.append(f'{s}imprimir($"{{{q}.t}}");')
            if r.random() < 0.7:
                r7 = nombre("r")
                lineas.append(f"{s}let {r7}: usize = leer_{tipo}("
                              f"if {cond()} {{ {p} }} "
                              f"else {{ dame_{tipo}() }});")
                lineas.append(f"{s}imprimir({r7});")
                lineas.append(f'{s}imprimir($"{{{p}.t}}");')
            if r.random() < 0.5:
                r8 = nombre("r")
                lineas.append(f"{s}let {r8}: usize = leer_{tipo}("
                              f"if {cond()} {{ dame_{tipo}() }} "
                              f"else {{ {p} }});")
                lineas.append(f"{s}imprimir({r8});")
                lineas.append(f'{s}imprimir($"{{{p}.t}}");')

        # 5. `(if c { xs } else { ys })[0]`: se indexa la rama prestada. La
        # lista es de elementos copiables, que es lo que deja indexar sin
        # sacar nada del sitio.
        if r.random() < 0.7:
            par = par_de(listas_s, "list<usize>")
            if par:
                x, y = par
                v5 = nombre("v")
                lineas.append(f"{s}let {v5}: usize = "
                              f"(if {cond()} {{ {x} }} else {{ {y} }})[0];")
                lineas.append(f"{s}imprimir({v5});")
                lineas.append(f"{s}imprimir({x}[0]);")
        if unitarios and r.random() < 0.6:
            ev = r.choice(unitarios)
            nombre_e = next(e["nombre"] for v, e in enums if v == ev)
            par = par_de(listas_s, "list<usize>")
            if par:
                x, y = par
                v5 = nombre("v")
                lineas.append(f"{s}let {v5}: usize = (match {ev} {{ "
                              f"{nombre_e}.A -> {x}, {nombre_e}.B -> {y} }})[0];")
                lineas.append(f"{s}imprimir({v5});")
                lineas.append(f"{s}imprimir({y}[0]);")

        # 6. `match if c { a } else { b } { ... }`: el escrutinio es una
        # lectura, y el enum se vuelve a mirar despues.
        por_enum = {}
        for v, e in enums:
            por_enum.setdefault(e["nombre"], []).append(v)
        for nombre_e, vs in sorted(por_enum.items()):
            if not vs or r.random() >= 0.8:
                continue
            e = next(x for x in self.enums if x["nombre"] == nombre_e)
            pareja = list(vs)
            if len(pareja) < 2:
                comp, rama = nombre("en"), r.choice(["A", "B"])
                if e["carga"] is None:
                    lineas.append(f"{s}let {comp}: {nombre_e} = "
                                  f"{nombre_e}.{rama};")
                else:
                    lineas.append(f'{s}let {comp}: {nombre_e} = '
                                  f'{nombre_e}.{rama}'
                                  f'(nuevo("{self.palabra()}"));')
                pareja.append(comp)
            a, b = r.sample(pareja, 2)
            if e["carga"] is None:
                linea_a = f'{s}    {nombre_e}.A -> imprimir("aa"),'
                linea_b = f'{s}    {nombre_e}.B -> imprimir("bb"),'
            else:
                b1, b2 = nombre("b"), nombre("b")
                linea_a = (f'{s}    {nombre_e}.A({b1}) -> '
                           f"imprimir(largo({b1})),")
                linea_b = (f'{s}    {nombre_e}.B({b2}) -> '
                           f"imprimir(largo({b2})),")
            lineas.append(f"{s}match if {cond()} {{ {a} }} else {{ {b} }} {{")
            lineas.append(linea_a)
            lineas.append(linea_b)
            lineas.append(f"{s}}}")
            if e["carga"] is None:
                otra = f'{s}    {nombre_e}.A -> imprimir("aa"),'
            else:
                b3 = nombre("b")
                otra = (f'{s}    {nombre_e}.A({b3}) -> '
                        f"imprimir(largo({b3})),")
            lineas.append(f"{s}match {a} {{")
            lineas.append(otra)
            lineas.append(linea_b)
            lineas.append(f"{s}}}")

        # 7, con una lista: una rama es el sitio y la otra una copia recien
        # hecha. Es la mixta de la coleccion, como la de los structs.
        if listas_d and r.random() < 0.5:
            x = r.choice(listas_d)
            copia, n7 = nombre("ls"), nombre("n")
            lineas.append(f"{s}let {copia}: list<str> = copiar({x});")
            lineas.append(f"{s}let {n7}: usize = "
                          f"largo(if {cond()} {{ {x} }} else {{ {copia} }});")
            lineas.append(f"{s}imprimir({n7});")
            lineas.append(f"{s}imprimir(largo({x}));")

        return lineas

    # ---------- programa ----------

    def programa(self):
        partes = []

        for k in range(self.r.randint(1, 2)):
            campos = [f"c{j}" for j in range(self.r.randint(1, 3))]
            nombre = f"S{k}"
            # Alguno con texto dentro: asi hay structs que POSEEN memoria, y
            # un mapa que los guarde presta en vez de copiar. El primero
            # siempre: las formas de lectura con duenio lo necesitan, y sin
            # un struct que posea no habria nada que mover ni que soltar.
            con_texto = k == 0 or self.r.random() < 0.5
            self.structs.append({"nombre": nombre, "campos": campos,
                                 "texto": "t" if con_texto else None})
            cuerpo = ", ".join(f"{c}: usize" for c in campos)
            if con_texto:
                cuerpo = cuerpo + ", t: str"
            partes.append(f"struct {nombre} {{ {cuerpo} }}")

        # Enums: el escrutinio de un `match if ...` y los brazos de un
        # `match` como valor necesitan variantes. Unos llevan un `str`
        # dentro —asi el enum POSEe memoria y moverlo o liberarlo se nota—
        # y otros no, que es lo que deja que un brazo entregue un struct. El
        # primero va sin carga: el `match` como valor lo necesita, y asi
        # cualquier programa con enums recorre los dos caminos.
        for k in range(self.r.randint(0, 2)):
            nombre = f"E{k}"
            if k == 0:
                carga = None
            else:
                carga = "str" if self.r.random() < 0.6 else None
            self.enums.append({"nombre": nombre, "carga": carga})
            if carga is None:
                partes.append(f"enum {nombre} {{ A, B }}")
            else:
                partes.append(f"enum {nombre} {{ A({carga}), B({carga}) }}")

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
            # Un struct recien hecho: es la rama que no es un sitio, la otra
            # mitad de la forma mixta `if c { p } else { dame_S() }`.
            valores = ", ".join(f"{c}: {self.r.randint(0, 99)}"
                                for c in st["campos"])
            if st.get("texto"):
                valores = valores + f', t: nuevo("{self.palabra()}")'
            partes.append(
                f"fn dame_{n}() -> {n} {{ return {n} {{ {valores} }}; }}")

        # Prestamos de `str`: leer sin copiar y modificar en el sitio.
        partes.append("fn medir(s: &str) -> usize { return largo(vista(s)); }")
        partes.append('fn marcar(s: mut str) { empujar(s, "#"); }')
        partes.append("fn doblar(n: mut usize) { n = (n * 2) % 1000; }")

        # una funcion que consume un `str`: prueba los movimientos
        partes.append("fn consumir(s: str) -> usize { return largo(vista(s)); }")

        # una que puede fallar: prueba try y sino
        partes.append(
            "fn mitad(n: usize) -> usize ! {\n"
            "    if n == 0 { fail \"cero\"; }\n"
            "    return n / 2;\n"
            "}")

        # Devuelve un `str` o falla. Sirve para ejercitar los dos caminos de
        # `sino` cuando la alternativa es duenia de su memoria.
        partes.append(
            "fn puede_fallar(n: usize) -> str ! {\n"
            "    if n != 0 { fail \"pedido\"; }\n"
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
            "    if n > 900 { fail \"grande\"; }\n"
            "    let dentro = try puede_fallar(0);\n"
            "    return $\"<{copia(n)}|{dentro}>\";\n"
            "}")
        # Un struct generico, usado con un tipo que posee memoria y con uno
        # que no: la copia del struct se hace por cada juego de tipos, y
        # liberar la de `str` no se parece a liberar la de `usize`.
        partes.append("struct Caja<T> { dentro: list<T> }")
        partes.append(
            "fn en_caja<T>(xs: &list<T>) -> Caja<T> {\n"
            "    return Caja { dentro: copiar(xs) };\n"
            "}")
        partes.append(
            "fn cuantas_en<T>(c: &Caja<T>) -> usize {\n"
            "    return largo(c.dentro);\n"
            "}")

        # Una funcion como valor, y ordenar con el criterio que se le pase.
        partes.append(
            "fn antes_n(a: &usize, b: &usize) -> bool {\n"
            "    return a < b;\n"
            "}")
        partes.append(
            "fn antes_rev(a: &usize, b: &usize) -> bool {\n"
            "    return a > b;\n"
            "}")
        partes.append(
            "fn con_criterio_gen<F>(xs: &list<usize>, antes: F) -> usize {\n"
            "    var mejor = 0;\n"
            "    var i = 1;\n"
            "    while i < largo(xs) {\n"
            "        if antes(xs[i], xs[mejor]) { mejor = i; }\n"
            "        i = i + 1;\n"
            "    }\n"
            "    return mejor;\n"
            "}")
        partes.append(
            "fn cuantas_cumplen<T, F>(xs: &list<T>, cumple: F) -> usize {\n"
            "    var n = 0;\n"
            "    for x en xs { if cumple(x) { n = n + 1; } }\n"
            "    return n;\n"
            "}")
        partes.append(
            "fn con_criterio(xs: &list<usize>, antes: fn(&usize, &usize) -> bool)\n"
            "        -> usize {\n"
            "    var mejor = 0;\n"
            "    var i = 1;\n"
            "    while i < largo(xs) {\n"
            "        if antes(xs[i], xs[mejor]) { mejor = i; }\n"
            "        i = i + 1;\n"
            "    }\n"
            "    return mejor;\n"
            "}")

        # Genericas: una plantilla, una copia por cada juego de tipos. Se usan
        # con un tipo que posee memoria y con uno que no, que es donde las
        # reglas de propiedad cambian de respuesta con el mismo cuerpo.
        partes.append(
            "fn cuantas<T>(xs: &list<T>) -> usize {\n"
            "    return largo(xs);\n"
            "}")
        partes.append(
            "fn sin_nada<T>(xs: &list<T>) -> bool {\n"
            "    return cuantas(xs) == 0;\n"
            "}")
        # Con restriccion: el cuerpo suma y compara, y la firma lo declara.
        partes.append(
            "fn total<T: numero>(ns: &list<T>) -> T {\n"
            "    var t: T = 0;\n"
            "    for n en ns { t = t +? n; }\n"
            "    return t;\n"
            "}")
        partes.append(
            "fn esta<T: igualable>(xs: &list<T>, aguja: &T) -> bool {\n"
            "    for x en xs { if igual(x, aguja) { return true; } }\n"
            "    return false;\n"
            "}")
        partes.append(
            "fn ultimo_sitio<T>(xs: &list<T>) -> usize ! {\n"
            "    if sin_nada(xs) { fail \"vacia\"; }\n"
            "    return largo(xs) - 1;\n"
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
        # La misma generica con `usize` y con `str`.
        lineas.append("    var g_ns: list<usize> = [];")
        lineas.append(f"    anadir(g_ns, {self.r.randint(0, 99)});")
        lineas.append("    var g_ss: list<str> = [];")
        lineas.append(f'    anadir(g_ss, nuevo("{self.palabra()}"));')
        # Copia profunda: de una lista de textos, de una anidada y de un
        # escalar. Cada copia es memoria nueva que alguien tiene que soltar.
        # Memoria cruda: un bloque que crece y encoge, y valores que entran
        # y salen de el sin dejar huecos.
        lineas.append("    var b_txt: bloque<str> = reservar(2);")
        lineas.append(f'    b_txt[0] = nuevo("{self.palabra()}");')
        lineas.append("    redimensionar(b_txt, 5);")
        lineas.append(f'    b_txt[4] = nuevo("{self.palabra()}");')
        lineas.append("    imprimir(largo(b_txt));")
        lineas.append("    let b_sacado = intercambiar(b_txt[0], vacio());")
        lineas.append("    imprimir(largo(vista(b_sacado)));")
        lineas.append("    redimensionar(b_txt, 1);")
        lineas.append("    imprimir(largo(b_txt));")

        # Decimales. Los valores se eligen para que ninguna operacion salga
        # de los numeros: lo que se prueba es que el C sale limpio.
        # El unico `if` como valor de aqui es numerico y sin duenio: los que
        # POSEEN memoria, que son los que encontraron los defectos, los pone
        # `lecturas_por_condicional` en cada cuerpo.
        lineas.append(f"    let d_a: f64 = {self.r.randint(1, 900)}.5;")
        lineas.append(f"    let d_b: f64 = {self.r.randint(1, 90)}.25;")
        lineas.append("    let d_cual = if d_a > d_b { d_a } else { d_b };")
        lineas.append("    imprimir(d_cual);")
        lineas.append("    imprimir(d_a + d_b);")
        lineas.append("    imprimir(d_a / d_b);")
        lineas.append("    imprimir(raiz(d_a));")
        lineas.append("    imprimir(piso(d_a) como usize);")
        lineas.append("    imprimir(redondear(d_b));")
        lineas.append("    imprimir(absoluto(d_b -? d_a));")
        lineas.append(f"    imprimir({self.r.randint(0, 99)} como f64);")
        lineas.append("    imprimir(d_a < d_b);")

        # Anchos fijos, bits y conversiones. Todo acotado para que no aborte:
        # lo que se prueba es que el C sale limpio y la memoria tambien.
        a = self.r.randint(0, 255)
        lineas.append(f"    let w_a: u8 = {a};")
        lineas.append(f"    let w_b: u32 = {self.r.randint(0, 4294967295)};")
        lineas.append(f"    let w_c: i32 = {self.r.randint(0, 1000000)};")
        lineas.append(f"    let w_d = (w_b >> {self.r.randint(0, 24)}) & 255;")
        lineas.append("    imprimir(w_d);")
        lineas.append(f"    imprimir(w_b ^ {self.r.randint(0, 65535)});")
        lineas.append("    imprimir(~w_a);")
        lineas.append(f"    imprimir(w_c *? {self.r.randint(1, 3)});")
        lineas.append("    imprimir(w_a como u32);")
        lineas.append("    imprimir(w_b como? u8);")
        lineas.append("    imprimir(w_d como u8);")
        # Y bytes crudos en un buffer.
        lineas.append("    var w_buf = vacio();")
        lineas.append("    empujar_byte(w_buf, w_a);")
        lineas.append('    empujar(w_buf, "\\x00\\xff");')
        lineas.append("    imprimir(largo(w_buf));")
        lineas.append("    let g_copia = copiar(g_ss);")
        lineas.append("    var g_hondo: list<list<str>> = [];")
        lineas.append("    anadir(g_hondo, copiar(g_ss));")
        lineas.append("    let g_hondo2 = copiar(g_hondo);")
        lineas.append("    imprimir(largo(g_copia));")
        lineas.append("    imprimir(largo(g_hondo2));")
        lineas.append(f"    imprimir(copiar({self.r.randint(0, 99)}));")
        lineas.append("    let g_caja = en_caja(g_ss);")
        lineas.append("    let g_caja_n = en_caja(g_ns);")
        lineas.append("    imprimir(cuantas_en(g_caja));")
        lineas.append("    imprimir(cuantas_en(g_caja_n));")
        # Una clausura que captura un escalar y otra que captura un `str`:
        # la segunda posee memoria y su struct la tiene que liberar.
        lineas.append(f"    let c_tope: usize = {self.r.randint(0, 99)};")
        lineas.append("    let c_menor = fn[c_tope](a: &usize, b: &usize) -> bool {")
        lineas.append("        return (a % (c_tope +? 1)) < (b % (c_tope +? 1));")
        lineas.append("    };")
        lineas.append("    imprimir(con_criterio_gen(g_ns, c_menor));")
        lineas.append(f'    let c_marca = nuevo("{self.palabra()}");')
        lineas.append("    let c_igual = fn[c_marca](x: &str) -> bool {")
        lineas.append("        return igual(vista(x), vista(c_marca));")
        lineas.append("    };")
        lineas.append("    imprimir(cuantas_cumplen(g_ss, c_igual));")
        lineas.append("    imprimir(con_criterio(g_ns, antes_n));")
        lineas.append("    let g_criterio = antes_rev;")
        lineas.append("    imprimir(con_criterio(g_ns, g_criterio));")
        lineas.append("    imprimir(total(g_ns));")
        lineas.append(f'    let g_aguja = nuevo("{self.palabra()}");')
        lineas.append("    imprimir(esta(g_ss, g_aguja));")
        lineas.append("    imprimir(cuantas(g_ns));")
        lineas.append("    imprimir(sin_nada(g_ss));")
        lineas.append("    imprimir(try ultimo_sitio(g_ss));")
        lineas.append(f"    imprimir(envuelto({self.r.randint(0, 99)}));")
        lineas.append(f"    imprimir(envuelto_falible({self.r.randint(0, 99)}) "
                      f"sino nuevo(\"nada\"));")
        lineas.append("    imprimir(mitad(0) sino 7);")
        lineas.append('    let respaldo: str = nuevo("respaldo");')
        lineas.append("    let leido: str = leer_o(respaldo);")
        lineas.append("    imprimir(largo(vista(leido)));")
        lineas.append('    imprimir("\\n");')
        lineas.append("    return 0;")
        partes.append("fn main() -> usize ! {\n" + "\n".join(lineas) + "\n}")

        return "\n\n".join(partes) + "\n"


def generar(semilla):
    return Generador(semilla).programa()


def generar_modulos(semilla):
    """Un programa repartido en archivos, con `use` entre ellos.

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
    base.append("    return e;")
    base.append("}")
    # una funcion falible declarada aqui y usada con `try` alla
    base.append("")
    # Una generica declarada aqui y usada alla, con dos tipos distintos: la
    # copia se crea en el modulo que la usa, no donde esta la plantilla.
    base.append("")
    base.append("fn cuantas<T>(xs: &list<T>) -> usize {")
    base.append("    return largo(xs);")
    base.append("}")
    base.append("")
    base.append("fn chequear(n: usize) -> usize ! {")
    base.append(f"    if n > {r.randint(900, 1200)} {{ fail \"muy grande\"; }}")
    base.append("    return n;")
    base.append("}")

    valores = ", ".join(f"{c}: {r.randint(0, 99)}" for c in campos)
    if con_texto:
        valores += f', t: nuevo("{g.palabra()}")'

    # Un modulo intermedio que usa el de base: la carga es en cadena.
    medio = ['use "base.t";', "",
             "fn crear() -> Dato {",
             f"    return Dato {{ {valores} }};",
             "}", "",
             "fn doble(d: &Dato) -> usize { return primero(d) * 2; }"]

    # Un modulo traido con `como`: se ve que el `como` separa de verdad, con
    # una funcion propia que se llama calificada. (Los tipos por archivo, dos
    # structs con el mismo nombre, son post-1.0.)
    otro = ["fn doble_otro(x: usize) -> usize {", "    return x * 2;", "}"]

    # El principal usa los tres: `base` llega por dos caminos y no se puede
    # cargar dos veces, y `otro` llega con nombre propio.
    app = ['use "lib/medio.t";', 'use "lib/base.t";',
           'use "lib/otro.t" como o;', "",
           "fn main() -> usize ! {",
           "    var d = crear();",
           f"    subir(d, {r.randint(1, 50)});",
           '    imprimir($"{primero(d)} {doble(d)}");']
    if con_texto:
        app.append('    imprimir($" {d.t}");')
    app.append("    var g_ns: list<usize> = [];")
    app.append(f"    anadir(g_ns, {r.randint(0, 99)});")
    app.append("    var g_ss: list<str> = [];")
    app.append(f'    anadir(g_ss, nuevo("{g.palabra()}"));')
    app.append('    imprimir($" {cuantas(g_ns)}{cuantas(g_ss)}");')
    app.append('    imprimir($" {o.doble_otro(primero(d))}");')
    app.append("    let e: str = etiqueta(d);")
    app.append('    imprimir($" {e}");')
    app.append("    let v = try chequear(primero(d));")
    app.append('    imprimir($" {v}");')
    app += ['    imprimir("' + chr(92) + 'n");', "    return 0;", "}"]

    return {
        "lib/otro.t": "\n".join(otro) + "\n",
        "lib/base.t": "\n".join(base) + "\n",
        "lib/medio.t": "\n".join(medio) + "\n",
        "app.t": "\n".join(app) + "\n",
    }


if __name__ == "__main__":
    import sys
    print(generar(int(sys.argv[1]) if len(sys.argv) > 1 else 1))
