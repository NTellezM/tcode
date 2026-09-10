"""
Explica lo que el compilador infirio.

Tcode se apoya en un analisis —quien es duenio de que, quien lo presta, donde
se libera, de donde sale cada vista— que hasta ahora solo se veia cuando
fallaba, en forma de error. Esto lo muestra cuando sale bien.

Sirve para tres cosas: aprender el modelo sin pelearse con el, entender por
que un programa que compila hace lo que hace, y revisar el propio compilador
(si lo que dice aqui no cuadra, el error esta en el analisis, no en el
programa).
"""

from tcode.comprobador import (
    ESTATICO, PARAMETRO, LOCAL, es_arreglo, partes_arreglo, UNIDAD,
)


def _firma(f):
    partes = []
    for p in f.params:
        if p.mutable:
            partes.append(f"{p.nombre}: mut {p.tipo}")
        elif p.compartido:
            partes.append(f"{p.nombre}: &{p.tipo}")
        else:
            partes.append(f"{p.nombre}: {p.tipo}")
    firma = f"fn {f.nombre}({', '.join(partes)})"
    if f.retorno not in (None, UNIDAD):
        firma += f" -> {f.retorno}"
    if f.falible:
        firma += " !"
    return firma


def _papel(sim, comp, es_param):
    """La primera columna: que es esta variable."""
    if sim.prestado:
        return "prestado para leer" if not sim.mutable else "prestado, modificable"
    if sim.tipo == "view":
        return "vista"
    if comp.posee(sim.tipo):
        return "DUEÑA" if not es_param else "DUEÑA (recibida)"
    return "valor"


def _destino(sim, comp, es_param):
    """La segunda columna: que pasa con su memoria."""
    if sim.tipo == "view":
        origen = f" de `{sim.origen}`" if sim.origen else ""
        if sim.procedencia == ESTATICO:
            return "apunta a un literal: vive todo el programa"
        if sim.procedencia == PARAMETRO:
            return f"presta{origen or ' de un parametro'}: la memoria es de quien llama"
        return f"presta{origen}: muere con el"

    if sim.prestado:
        return "no se libera aqui: es de quien llama"

    if not comp.posee(sim.tipo):
        return ""

    if sim.entregada_en:
        return f"se entrega en la linea {sim.entregada_en} (return)"
    if sim.movida:
        a = f" a `{sim.movida_a}`" if sim.movida_a else ""
        return (f"se mueve{a} en la linea {sim.movida_en}; lleva bandera por "
                f"si el programa sale antes")

    if es_arreglo(sim.tipo):
        elem, n = partes_arreglo(sim.tipo)
        if comp.posee(elem):
            return (f"se libera sola al cerrar su bloque, "
                    f"elemento por elemento ({n})")
    return "se libera sola al cerrar su bloque"


def explicar(comp, archivo):
    lineas = [f"{archivo}", ""]

    if not comp.structs and not comp.informe:
        lineas.append("  (nada que explicar)")
        return "\n".join(lineas)

    for nombre, st in comp.structs.items():
        posee = comp.posee(nombre)
        lineas.append(f"  struct {nombre}"
                      + ("   es DUEÑO: contiene memoria que hay que liberar"
                         if posee else "   solo datos: nada que liberar"))
        for c in st.campos:
            marca = "  <- duenio" if comp.posee(c.tipo) else ""
            lineas.append(f"      {c.nombre}: {c.tipo}{marca}")
        if posee:
            lineas.append(f"      el compilador genera `ss_drop_{nombre}` "
                          f"y lo llama donde haga falta")
        lineas.append("")

    for entrada in comp.informe:
        f = entrada["funcion"]
        simbolos = entrada["simbolos"]
        lineas.append(f"  {_firma(f)}")
        if f.falible and f.nombre == "main":
            lineas.append("      puede fallar: si falla, el programa imprime "
                          "`error: <motivo>` y sale con codigo 1")
        elif f.falible:
            lineas.append("      puede fallar: quien la llame tiene que usar "
                          "`try` o `sino`")

        nombres_param = {p.nombre for p in f.params}
        if not simbolos:
            lineas.append("      (sin variables)")
            lineas.append("")
            continue

        ancho_n = max(len(s.nombre) for s in simbolos)
        ancho_t = max(len(s.tipo) for s in simbolos)
        ancho_p = max(len(_papel(s, comp, s.nombre in nombres_param))
                      for s in simbolos)

        for sim in simbolos:
            es_param = sim.nombre in nombres_param
            papel = _papel(sim, comp, es_param)
            destino = _destino(sim, comp, es_param)
            mut = "var" if sim.mutable and not es_param else "let"
            if es_param:
                mut = "arg"
            lineas.append(
                f"      {mut} {sim.nombre:<{ancho_n}}  {sim.tipo:<{ancho_t}}  "
                f"{papel:<{ancho_p}}  {destino}".rstrip())

        duenias = [s for s in simbolos
                   if comp.posee(s.tipo) and not s.prestado]
        if duenias:
            solas = sum(1 for s in duenias if not s.movida and not s.entregada_en)
            entregadas = sum(1 for s in duenias if s.entregada_en)
            movidas = sum(1 for s in duenias if s.movida)
            trozos = []
            if solas:
                trozos.append(f"{solas} se libera{'n' if solas > 1 else ''} sola"
                              f"{'s' if solas > 1 else ''}")
            if entregadas:
                trozos.append(f"{entregadas} se entrega"
                              f"{'n' if entregadas > 1 else ''}")
            if movidas:
                trozos.append(f"{movidas} se mueve"
                              f"{'n' if movidas > 1 else ''}")
            lineas.append(f"      {len(duenias)} valor(es) con memoria propia: "
                          + ", ".join(trozos))
        lineas.append("")

    return "\n".join(lineas).rstrip() + "\n"
