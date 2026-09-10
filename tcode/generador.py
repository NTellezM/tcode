"""
Genera C a partir del arbol ya comprobado.

Dos cosas que el generador hace y el programador de C tendria que hacer a
mano, que son justo donde se equivoca:

  - insertar `ss_free` al cerrar cada bloque, para los `str` que no se
    movieron;
  - envolver `+`, `-` y `*` en comprobaciones de desbordamiento.
"""

from tcode.nodos import (
    Entero, Cadena, Booleano, Variable, Llamada, Binaria, Unaria,
    Campo, Indice, LiteralStruct, LiteralArreglo, Try, Sino, Falla,
    Declaracion, Asignacion, Si, Mientras, Retorno, ExprSentencia,
    Funcion, Struct,
)
from tcode.comprobador import (
    INTERNAS, UNIDAD, es_arreglo, partes_arreglo, elem_de, largo_arreglo,
)

TIPOS_C = {
    "str": "SafeString",
    "view": "SafeView",
    "usize": "size_t",
    "i64": "int64_t",
    "bool": "bool",
    None: "void",
    UNIDAD: "void",
}

CABECERA = r'''/* Generado por el compilador de Tcode. No editar a mano. */

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "safestr.h"

/* Este archivo lo escribe el compilador, no una persona. Un aviso sobre una
   variable que no se usa, o sobre `x == x`, habla del programa en Tcode y no
   de este C: apuntar aqui no le sirve a nadie. Que Tcode avise por su cuenta
   de esas cosas es otra conversacion, pero el ruido de gcc sobre codigo
   generado se apaga. */
#if defined(__GNUC__) || defined(__clang__)
#  pragma GCC diagnostic ignored "-Wtautological-compare"
#  pragma GCC diagnostic ignored "-Wtype-limits"
#endif

/* Un programa puede no usar todas las comprobaciones; eso no es un aviso
   que le sirva a nadie. */
#if defined(__GNUC__) || defined(__clang__)
#  define SS_LANG_QUIZA_SIN_USAR __attribute__((unused))
/* Un desbordamiento detiene el programa: el camino no vuelve y casi nunca se
   toma. Decirselo al compilador saca ese codigo del bucle caliente. */
#  define SS_LANG_NO_VUELVE  __attribute__((noreturn, cold, noinline))
#  define SS_LANG_RARO(c)    __builtin_expect(!!(c), 0)
#  define SS_LANG_SIEMPRE    __attribute__((always_inline)) inline
#else
#  define SS_LANG_QUIZA_SIN_USAR
#  define SS_LANG_NO_VUELVE
#  define SS_LANG_RARO(c)    (c)
#  define SS_LANG_SIEMPRE
#endif

/* Aritmetica comprobada: en Tcode el desbordamiento no es silencioso.
   Aborta diciendo donde, en vez de seguir con un valor equivocado. */
SS_LANG_QUIZA_SIN_USAR SS_LANG_NO_VUELVE
static void ss_lang_desborde_(const char* op, const char* archivo, int linea)
{
    fprintf(stderr, "%s:%d: desbordamiento en `%s`\n", archivo, linea, op);
    abort();
}

SS_LANG_QUIZA_SIN_USAR SS_LANG_NO_VUELVE
static void ss_lang_division_cero_(const char* archivo, int linea)
{
    fprintf(stderr, "%s:%d: division por cero\n", archivo, linea);
    abort();
}

/* Cada operacion se comprueba antes de confiar en ella.
 *
 * Donde el compilador ofrece los builtins de desbordamiento se usan: salen
 * como la instruccion aritmetica de siempre mas un salto condicional que
 * casi nunca se toma. La version portable que va debajo es correcta pero
 * cuesta: la de multiplicar necesita una division, que son decenas de
 * ciclos, y se nota en un bucle cerrado. */
#if defined(__GNUC__) || defined(__clang__)
#  define SS_LANG_HAY_BUILTINS 1
#endif

#define SS_LANG_DEFINIR_ARIT(sufijo, tipo, tmax, tmin)                        \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_suma_##sufijo(tipo a, tipo b, const char* ar, int ln)     \
{                                                                             \
    tipo r;                                                                   \
    if (ss_lang_suma_desborda_##sufijo(a, b, &r))                             \
        ss_lang_desborde_("+", ar, ln);                                       \
    return r;                                                                 \
}                                                                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_resta_##sufijo(tipo a, tipo b, const char* ar, int ln)    \
{                                                                             \
    tipo r;                                                                   \
    if (ss_lang_resta_desborda_##sufijo(a, b, &r))                            \
        ss_lang_desborde_("-", ar, ln);                                       \
    return r;                                                                 \
}                                                                             \
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE                                        \
static tipo ss_lang_mul_##sufijo(tipo a, tipo b, const char* ar, int ln)      \
{                                                                             \
    tipo r;                                                                   \
    if (ss_lang_mul_desborda_##sufijo(a, b, &r))                              \
        ss_lang_desborde_("*", ar, ln);                                       \
    return r;                                                                 \
}

#ifdef SS_LANG_HAY_BUILTINS

#  define ss_lang_suma_desborda_u(a, b, r)  __builtin_add_overflow((a), (b), (r))
#  define ss_lang_resta_desborda_u(a, b, r) __builtin_sub_overflow((a), (b), (r))
#  define ss_lang_mul_desborda_u(a, b, r)   __builtin_mul_overflow((a), (b), (r))
#  define ss_lang_suma_desborda_i(a, b, r)  __builtin_add_overflow((a), (b), (r))
#  define ss_lang_resta_desborda_i(a, b, r) __builtin_sub_overflow((a), (b), (r))
#  define ss_lang_mul_desborda_i(a, b, r)   __builtin_mul_overflow((a), (b), (r))

#else   /* portable: mas caro, sobre todo al multiplicar */

static int ss_lang_suma_desborda_u(size_t a, size_t b, size_t* r)
{ *r = a + b; return a > SIZE_MAX - b; }

static int ss_lang_resta_desborda_u(size_t a, size_t b, size_t* r)
{ *r = a - b; return a < b; }

static int ss_lang_mul_desborda_u(size_t a, size_t b, size_t* r)
{ *r = a * b; return a != 0 && b > SIZE_MAX / a; }

static int ss_lang_suma_desborda_i(int64_t a, int64_t b, int64_t* r)
{
    if ((b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b)) return 1;
    *r = a + b; return 0;
}

static int ss_lang_resta_desborda_i(int64_t a, int64_t b, int64_t* r)
{
    if ((b < 0 && a > INT64_MAX + b) || (b > 0 && a < INT64_MIN + b)) return 1;
    *r = a - b; return 0;
}

static int ss_lang_mul_desborda_i(int64_t a, int64_t b, int64_t* r)
{
    if (a != 0 && b != 0)
    {
        if (a > 0 ? (b > 0 ? a > INT64_MAX / b : b < INT64_MIN / a)
                  : (b > 0 ? a < INT64_MIN / b : a < INT64_MAX / b))
            return 1;
    }
    *r = a * b; return 0;
}

#endif

SS_LANG_DEFINIR_ARIT(u, size_t, SIZE_MAX, 0)
SS_LANG_DEFINIR_ARIT(i, int64_t, INT64_MAX, INT64_MIN)

#define SS_LANG_SUMA_U(a, b, ar, ln)  ss_lang_suma_u((a), (b), ar, ln)
#define SS_LANG_RESTA_U(a, b, ar, ln) ss_lang_resta_u((a), (b), ar, ln)
#define SS_LANG_MUL_U(a, b, ar, ln)   ss_lang_mul_u((a), (b), ar, ln)
#define SS_LANG_SUMA_I(a, b, ar, ln)  ss_lang_suma_i((a), (b), ar, ln)
#define SS_LANG_RESTA_I(a, b, ar, ln) ss_lang_resta_i((a), (b), ar, ln)
#define SS_LANG_MUL_I(a, b, ar, ln)   ss_lang_mul_i((a), (b), ar, ln)

#define SS_LANG_DIV(a, b, arch, ln) \
    (((b) == 0) ? (ss_lang_division_cero_(arch, ln), 0) : ((a) / (b)))

#define SS_LANG_MOD(a, b, arch, ln) \
    (((b) == 0) ? (ss_lang_division_cero_(arch, ln), 0) : ((a) % (b)))

/* Indexar fuera de rango no lee memoria ajena: detiene el programa. */
SS_LANG_QUIZA_SIN_USAR SS_LANG_SIEMPRE
static size_t ss_lang_indice_(size_t i, size_t n, const char* arch, int ln)
{
    if (SS_LANG_RARO(i >= n))
    {
        fprintf(stderr, "%s:%d: indice %zu fuera de rango (el arreglo tiene "
                        "%zu elemento%s)\n", arch, ln, i, n, n == 1 ? "" : "s");
        abort();
    }
    return i;
}

'''


def mangle(t):
    """Nombre C valido para un tipo: `[usize; 3]` -> `arr_usize_3`."""
    if es_arreglo(t):
        elem, n = partes_arreglo(t)
        return f"arr_{mangle(elem)}_{n}"
    return t


class Generador:
    def __init__(self, comprobador, archivo="<entrada>"):
        self.c = comprobador
        self.archivo = archivo
        self.lineas = []
        self.sangria = 0
        # pila de bloques: cada uno con los `str` declarados que hay que liberar
        self.pila = []
        self.tmp = 0
        # El generador lleva su propia tabla: los ambitos del comprobador ya
        # se cerraron cuando llegamos aqui.
        self.vars = []
        self.arreglos = {}     # tipo Tcode -> nombre del typedef en C
        self.resultados = {}   # tipo Tcode -> nombre del typedef de resultado
        self.bucle = 0         # contador para variables de bucle de liberacion
        self.func = None       # funcion que se esta generando
        # Variables que se mueven en algun punto: llevan una bandera en
        # tiempo de ejecucion, porque el punto donde se liberan depende del
        # camino que tome el programa.
        self.con_bandera = set()
        self.pendientes = []

    # ---------- utilidades ----------

    # ---------- tipos ----------

    def tipo_c(self, t):
        """Nombre C de un tipo. Los arreglos van envueltos en un struct.

        En C un arreglo desnudo no se puede asignar, ni pasar por valor, ni
        devolver: se degrada a puntero. Envolverlo en un struct le devuelve la
        semantica de valor que el lenguaje promete.
        """
        if es_arreglo(t):
            return self.registrar_arreglo(t)
        return TIPOS_C.get(t, t)

    def tipo_resultado(self, t):
        """El `T !` de Tcode es un struct: motivo == NULL significa que fue
        bien. Un solo puntero en vez de un booleano mas el valor."""
        clave = t if t not in (None, UNIDAD) else UNIDAD
        if clave not in self.resultados:
            sufijo = "unidad" if clave is UNIDAD else mangle(clave)
            self.resultados[clave] = f"ss_res_{sufijo}"
        return self.resultados[clave]

    def registrar_arreglo(self, t):
        if t not in self.arreglos:
            elem, _ = partes_arreglo(t)
            if es_arreglo(elem):
                self.registrar_arreglo(elem)
            self.arreglos[t] = f"ss_{mangle(t)}"
        return self.arreglos[t]

    def recolectar_tipos(self, decls):
        """Registra todos los tipos de arreglo que aparecen en el programa."""
        def mirar(t):
            if t and es_arreglo(t):
                self.registrar_arreglo(t)

        for d in decls:
            if isinstance(d, Struct):
                for c in d.campos:
                    mirar(c.tipo)
            elif isinstance(d, Funcion):
                mirar(d.retorno)
                if d.falible:
                    if d.retorno not in (None, UNIDAD):
                        mirar(d.retorno)
                    self.tipo_resultado(d.retorno)
                for p in d.params:
                    mirar(p.tipo)
                self._mirar_cuerpo(d.cuerpo, mirar)

    def _mirar_cuerpo(self, sentencias, mirar):
        for s in sentencias:
            if isinstance(s, Declaracion):
                mirar(s.tipo)
            elif isinstance(s, Si):
                self._mirar_cuerpo(s.entonces, mirar)
                if s.sino:
                    self._mirar_cuerpo(s.sino, mirar)
            elif isinstance(s, Mientras):
                self._mirar_cuerpo(s.cuerpo, mirar)

    def orden_structs(self, structs):
        """Un struct por valor necesita el tamaño del que lleva dentro, asi
        que hay que definirlos en orden de dependencia."""
        por_nombre = {st.nombre: st for st in structs}
        listos, salida = set(), []

        def visitar(nombre):
            if nombre in listos or nombre not in por_nombre:
                return
            listos.add(nombre)
            for c in por_nombre[nombre].campos:
                t = c.tipo
                while es_arreglo(t):
                    t = elem_de(t)
                visitar(t)
            salida.append(por_nombre[nombre])

        for st in structs:
            visitar(st.nombre)
        return salida

    def emitir(self, texto=""):
        self.lineas.append("    " * self.sangria + texto if texto else "")

    def declarar(self, nombre, tipo, por_puntero=False, decl=None):
        self.vars[-1][nombre] = (tipo, por_puntero, decl)

    def buscar(self, nombre):
        for ambito in reversed(self.vars):
            if nombre in ambito:
                return ambito[nombre]
        return None

    def tipo_var(self, nombre):
        v = self.buscar(nombre)
        return v[0] if v else None

    def es_puntero(self, nombre):
        v = self.buscar(nombre)
        return bool(v and v[1])

    def fue_movida(self, nombre):
        """Si el valor se movio a otro sitio, aqui ya no somos duenios."""
        v = self.buscar(nombre)
        return bool(v and v[2] is not None and getattr(v[2], "movida", False))

    def ref(self, nombre):
        """Como referirse a `nombre` cuando se necesita un SafeString*."""
        return nombre if self.es_puntero(nombre) else f"&{nombre}"

    def nuevo_tmp(self):
        self.tmp += 1
        return f"ss_tmp{self.tmp}"

    def arch(self, nodo=None):
        a = (getattr(nodo, "archivo", "") or self.archivo) if nodo else self.archivo
        return '"' + a.replace("\\", "\\\\").replace('"', '\\"') + '"'

    # ---------- programa ----------

    def generar(self, decls):
        structs = [d for d in decls if isinstance(d, Struct)]
        funciones = [d for d in decls if isinstance(d, Funcion)]

        self.lineas.append(CABECERA)
        self.recolectar_tipos(decls)

        # structs, en orden de dependencia
        for st in self.orden_structs(structs):
            self.lineas.append(f"typedef struct {st.nombre}")
            self.lineas.append("{")
            for c in st.campos:
                self.lineas.append(f"    {self.tipo_c(c.tipo)} {c.nombre};")
            self.lineas.append(f"}} {st.nombre};")
            self.lineas.append("")

        # envoltorios de arreglo, de dentro hacia fuera
        for t in sorted(self.arreglos, key=lambda x: x.count("[")):
            elem, n = partes_arreglo(t)
            self.lineas.append(
                f"typedef struct {{ {self.tipo_c(elem)} e[{n}]; }} "
                f"{self.arreglos[t]};")
        if self.arreglos:
            self.lineas.append("")

        for t, nombre in self.resultados.items():
            if t is UNIDAD or t == UNIDAD:
                self.lineas.append(
                    f"typedef struct {{ const char* motivo; }} {nombre};")
            else:
                self.lineas.append(
                    f"typedef struct {{ const char* motivo; "
                    f"{self.tipo_c(t)} valor; }} {nombre};")
        if self.resultados:
            self.lineas.append("")

        # liberadores de los structs que poseen memoria
        for st in self.orden_structs(structs):
            if not self.c.posee(st.nombre):
                continue
            self.lineas.append(f"static void ss_drop_{st.nombre}({st.nombre}* p)")
            self.lineas.append("{")
            self.sangria = 1
            marca = len(self.lineas)
            for c in st.campos:
                self.liberacion(f"p->{c.nombre}", c.tipo)
            self.lineas.extend(self.lineas[marca:marca])
            self.sangria = 0
            self.lineas.append("}")
            self.lineas.append("")

        for f in funciones:
            if f.nombre != "main":
                self.lineas.append(self.prototipo(f) + ";")
        self.lineas.append("")

        for f in funciones:
            self.funcion(f)
            self.lineas.append("")

        return "\n".join(self.lineas)

    def prototipo(self, f: Funcion):
        if f.nombre == "main" and not f.falible:
            return "int main(void)"
        params = []
        for p in f.params:
            tc = self.tipo_c(p.tipo)
            if p.mutable:
                params.append(f"SS_LANG_QUIZA_SIN_USAR {tc}* {p.nombre}")
            elif p.compartido:
                # solo lectura: el `const` lo documenta y lo hace cumplir el
                # propio compilador de C
                params.append(f"SS_LANG_QUIZA_SIN_USAR const {tc}* {p.nombre}")
            else:
                params.append(f"SS_LANG_QUIZA_SIN_USAR {tc} {p.nombre}")
        if f.falible:
            ret = self.tipo_resultado(f.retorno)
        elif f.retorno in (None, UNIDAD):
            ret = "void"
        else:
            ret = self.tipo_c(f.retorno)
        nombre = "ss_main_" if f.nombre == "main" else f.nombre
        return f"{ret} {nombre}({', '.join(params) or 'void'})"

    def funcion(self, f: Funcion):
        self.func = f
        self.emitir(self.prototipo(f))
        self.emitir("{")
        self.sangria += 1
        # los parametros `str` por valor son propiedad de la funcion: se liberan
        propios = [p.nombre for p in f.params
                   if self.c.posee(p.tipo) and not p.prestado]
        self.pila.append(list(propios))
        self.vars.append({})
        self.con_bandera = set()
        for p in f.params:
            self.declarar(p.nombre, p.tipo, p.prestado, decl=p)
        for p in f.params:
            if p.movida and self.c.posee(p.tipo) and not p.prestado:
                self.con_bandera.add(p.nombre)
                self.emitir(f"bool ss_vivo_{p.nombre} = true;")

        for s in f.cuerpo:
            self.sentencia(s)

        # Si el cuerpo ya termino en `return`, todo lo que siga es codigo
        # muerto: el `return` se encargo de liberar.
        if not self._termina_en_retorno(f.cuerpo):
            self.liberar_bloque(self.pila[-1])
            if f.falible:
                self.emitir(f"return ({self.tipo_resultado(f.retorno)})"
                            f"{{ .motivo = NULL }};")
            elif f.nombre == "main":
                self.emitir("return 0;")
        self.pila.pop()
        self.vars.pop()
        self.sangria -= 1
        self.emitir("}")

        # `main` falible: un envoltorio que informa y devuelve codigo distinto
        # de cero, para que el fallo no se pierda al salir del programa.
        if f.nombre == "main" and f.falible:
            self.emitir("")
            self.emitir("int main(void)")
            self.emitir("{")
            self.sangria += 1
            self.emitir(f"{self.tipo_resultado(f.retorno)} r = ss_main_();")
            self.emitir("if (r.motivo != NULL)")
            self.emitir("{")
            self.sangria += 1
            self.emitir(r'fprintf(stderr, "error: %s\n", r.motivo);')
            self.emitir("return 1;")
            self.sangria -= 1
            self.emitir("}")
            self.emitir("return (int) r.valor;"
                        if f.retorno not in (None, UNIDAD) else "return 0;")
            self.sangria -= 1
            self.emitir("}")
        self.func = None

    # ---------- liberacion automatica ----------

    def liberacion(self, expr_c, tipo):
        """Emite lo que haga falta para devolver la memoria de `expr_c`."""
        if tipo == "str":
            self.emitir(f"ss_free(&{expr_c});")
            return

        if es_arreglo(tipo):
            elem, n = partes_arreglo(tipo)
            if not self.c.posee(elem):
                return
            self.bucle += 1
            i = f"ss_i{self.bucle}"
            self.emitir(f"for (size_t {i} = 0; {i} < {n}; {i}++)")
            self.emitir("{")
            self.sangria += 1
            self.liberacion(f"{expr_c}.e[{i}]", elem)
            self.sangria -= 1
            self.emitir("}")
            return

        if tipo in self.c.structs and self.c.posee(tipo):
            self.emitir(f"ss_drop_{tipo}(&{expr_c});")

    def liberar_bloque(self, nombres, excepto=None):
        for n in reversed(nombres):
            if n == excepto:
                continue
            if n in self.con_bandera:
                # se movio en algun camino: lo decide la bandera
                self.emitir(f"if (ss_vivo_{n})")
                self.emitir("{")
                self.sangria += 1
                self.liberacion(n, self.tipo_var(n))
                self.sangria -= 1
                self.emitir("}")
                continue
            if self.fue_movida(n):
                continue
            self.liberacion(n, self.tipo_var(n))

    def liberar_todo(self, excepto=None):
        for marco in reversed(self.pila):
            self.liberar_bloque(marco, excepto)

    # ---------- sentencias ----------

    def bloque(self, sentencias):
        self.emitir("{")
        self.sangria += 1
        self.pila.append([])
        self.vars.append({})
        for s in sentencias:
            self.sentencia(s)
        if not self._termina_en_retorno(sentencias):
            self.liberar_bloque(self.pila[-1])
        self.pila.pop()
        self.vars.pop()
        self.sangria -= 1
        self.emitir("}")

    @staticmethod
    def _termina_en_retorno(sentencias):
        return bool(sentencias) and isinstance(sentencias[-1], Retorno)

    def sentencia(self, s):
        anteriores = self.pendientes
        self.pendientes = []
        self._sentencia(s)
        for n in self.pendientes:
            self.emitir(f"ss_vivo_{n} = false;")
        self.pendientes = anteriores

    def _sentencia(self, s):
        if isinstance(s, Declaracion):
            tc = self.tipo_c(s.tipo)
            # Una variable declarada y no usada es legitima en Tcode; el aviso
            # de gcc apuntaria a este C, que el usuario no escribio.
            self.emitir(f"SS_LANG_QUIZA_SIN_USAR {tc} {s.nombre} = "
                        f"{self.expr(s.valor, s.tipo)};")
            self.declarar(s.nombre, s.tipo, decl=s)
            if self.c.posee(s.tipo):
                self.pila[-1].append(s.nombre)
                if s.movida:
                    self.con_bandera.add(s.nombre)
                    self.emitir(f"bool ss_vivo_{s.nombre} = true;")
            return

        if isinstance(s, Asignacion):
            destino = self.lugar(s.lugar)
            tipo = self._tipo_de(s.lugar)
            if self.c.posee(tipo):
                # el valor viejo se pierde: devolverlo antes de pisarlo
                self.liberacion(destino, tipo)
            self.emitir(f"{destino} = {self.expr(s.valor, tipo)};")
            return

        if isinstance(s, Si):
            self.emitir(f"if ({self.expr(s.cond, 'bool')})")
            self.bloque(s.entonces)
            if s.sino is not None:
                self.emitir("else")
                self.bloque(s.sino)
            return

        if isinstance(s, Mientras):
            self.emitir(f"while ({self.expr(s.cond, 'bool')})")
            self.bloque(s.cuerpo)
            return

        if isinstance(s, Falla):
            lit = s.motivo.replace("\\", "\\\\").replace('"', '\\"') \
                          .replace("\n", "\\n").replace("\t", "\\t")
            self.liberar_todo()
            self.emitir(f"return ({self.tipo_resultado(self.func.retorno)})"
                        f'{{ .motivo = "{lit}" }};')
            return

        if isinstance(s, Retorno):
            falible = self.func is not None and self.func.falible
            if s.valor is None:
                self.liberar_todo()
                if falible:
                    self.emitir(f"return ({self.tipo_resultado(self.func.retorno)})"
                                f"{{ .motivo = NULL }};")
                else:
                    self.emitir("return;")
                return
            # Si se devuelve una variable duenia, esa NO se libera: se entrega.
            devuelta = s.valor.nombre if isinstance(s.valor, Variable) else None
            valor = self.expr(s.valor, self.func.retorno if self.func else None)
            envolver = (lambda v: f"({self.tipo_resultado(self.func.retorno)})"
                                  f"{{ .motivo = NULL, .valor = {v} }}") \
                       if falible else (lambda v: v)
            if devuelta is not None:
                self.liberar_todo(excepto=devuelta)
                self.emitir(f"return {envolver(devuelta)};")
            else:
                tmp = self.nuevo_tmp()
                self.emitir(f"{self.tipo_c(self._tipo_de(s.valor))} {tmp} = {valor};")
                self.liberar_todo()
                self.emitir(f"return {envolver(tmp)};")
            return

        if isinstance(s, ExprSentencia):
            c = self.expr(s.expr, None)
            if c:
                self.emitir(c + ";")
            return

        raise AssertionError(type(s).__name__)

    def _tipo_de(self, e):
        if isinstance(e, Entero):
            return "usize"
        if isinstance(e, Cadena):
            return "view"
        if isinstance(e, Booleano):
            return "bool"
        if isinstance(e, Variable):
            return self.tipo_var(e.nombre) or "usize"
        if isinstance(e, Llamada):
            if e.nombre in INTERNAS:
                return INTERNAS[e.nombre]["retorno"]
            f = self.c.funciones.get(e.nombre)
            return f.retorno if f else "usize"
        if isinstance(e, Try):
            return self._tipo_de(e.expr)
        if isinstance(e, Sino):
            return self._tipo_de(e.expr)
        if isinstance(e, Campo):
            base = self._tipo_de(e.objeto)
            st = self.c.structs.get(base)
            if st:
                for c in st.campos:
                    if c.nombre == e.nombre:
                        return c.tipo
            return "usize"
        if isinstance(e, Indice):
            base = self._tipo_de(e.arreglo)
            return elem_de(base) if es_arreglo(base) else "usize"
        if isinstance(e, LiteralStruct):
            return e.tipo
        if isinstance(e, LiteralArreglo):
            elem = self._tipo_de(e.elementos[0]) if e.elementos else "usize"
            return f"[{elem}; {len(e.elementos)}]"
        if isinstance(e, Binaria):
            if e.op in {"==", "!=", "<", "<=", ">", ">=", "&&", "||"}:
                return "bool"
            return self._tipo_de(e.izq)
        if isinstance(e, Unaria):
            return "bool" if e.op == "!" else self._tipo_de(e.valor)
        return "usize"

    # ---------- expresiones ----------

    def expr(self, e, esperado):
        if isinstance(e, Entero):
            return f"(int64_t){e.valor}" if esperado == "i64" else f"(size_t){e.valor}"

        if isinstance(e, Cadena):
            lit = (e.valor.replace("\\", "\\\\").replace('"', '\\"')
                          .replace("\n", "\\n").replace("\t", "\\t")
                          .replace("\0", "\\0"))
            return f'sv_len("{lit}", {len(e.valor.encode("utf-8"))})'

        if isinstance(e, Booleano):
            return "true" if e.valor else "false"

        if isinstance(e, Variable):
            # un parametro `mut str` llega como puntero
            if self.es_puntero(e.nombre):
                return f"(*{e.nombre})"
            return e.nombre

        if isinstance(e, Unaria):
            return f"({e.op}{self.expr(e.valor, esperado)})"

        if isinstance(e, Try):
            interna = e.expr
            t = self._tipo_de(interna)
            tmp = self.nuevo_tmp()
            llamada = self.llamada(interna)
            self.emitir(f"{self.tipo_resultado(t)} {tmp} = {llamada};")
            self.emitir(f"if ({tmp}.motivo != NULL)")
            self.emitir("{")
            self.sangria += 1
            self.liberar_todo()
            self.emitir(f"return ({self.tipo_resultado(self.func.retorno)})"
                        f"{{ .motivo = {tmp}.motivo }};")
            self.sangria -= 1
            self.emitir("}")
            return "" if t in (None, UNIDAD) else f"{tmp}.valor"

        if isinstance(e, Sino):
            interna = e.expr
            t = self._tipo_de(interna)
            tmp = self.nuevo_tmp()
            llamada = self.llamada(interna)
            self.emitir(f"{self.tipo_resultado(t)} {tmp} = {llamada};")
            if t in (None, UNIDAD):
                return ""
            alt = self.expr(e.alternativa, t)
            return f"({tmp}.motivo != NULL ? ({alt}) : {tmp}.valor)"

        if isinstance(e, (Campo, Indice)):
            return self.lugar(e)

        if isinstance(e, LiteralStruct):
            st = self.c.structs.get(e.tipo)
            tipos = {c.nombre: c.tipo for c in st.campos} if st else {}
            partes = ", ".join(
                f".{n} = {self.expr(v, tipos.get(n))}" for n, v in e.campos)
            return f"({e.tipo}){{ {partes} }}"

        if isinstance(e, LiteralArreglo):
            t = esperado if (esperado and es_arreglo(esperado)) else self._tipo_de(e)
            elem = elem_de(t)
            partes = ", ".join(self.expr(x, elem) for x in e.elementos)
            return f"({self.tipo_c(t)}){{{{ {partes} }}}}"

        if isinstance(e, Binaria):
            return self.binaria(e, esperado)

        if isinstance(e, Llamada):
            return self.llamada(e)

        raise AssertionError(type(e).__name__)

    def lugar(self, e):
        """C para un sitio al que se puede leer y escribir."""
        if isinstance(e, Variable):
            return f"(*{e.nombre})" if self.es_puntero(e.nombre) else e.nombre
        if isinstance(e, Campo):
            return f"{self.lugar(e.objeto)}.{e.nombre}"
        if isinstance(e, Indice):
            base = self._tipo_de(e.arreglo)
            n = largo_arreglo(base) if es_arreglo(base) else 0
            idx = self.expr(e.indice, "usize")
            return (f"{self.lugar(e.arreglo)}.e"
                    f"[ss_lang_indice_({idx}, {n}, {self.arch(e)}, {e.linea})]")
        return self.expr(e, None)

    def binaria(self, e: Binaria, esperado):
        t = self._tipo_de(e.izq)
        if t not in {"usize", "i64"}:
            t = self._tipo_de(e.der)
        sufijo = "I" if t == "i64" else "U"
        izq = self.expr(e.izq, t)
        der = self.expr(e.der, t)
        pos = f"{self.arch(e)}, {e.linea}"

        if e.op in {"+", "-", "*"}:
            macro = {"+": "SUMA", "-": "RESTA", "*": "MUL"}[e.op]
            return f"SS_LANG_{macro}_{sufijo}({izq}, {der}, {pos})"

        if e.op in {"+?", "-?", "*?"}:
            return f"({izq} {e.op[0]} {der})"      # envolvente, pedida a proposito

        if e.op == "/":
            return f"SS_LANG_DIV({izq}, {der}, {pos})"
        if e.op == "%":
            return f"SS_LANG_MOD({izq}, {der}, {pos})"

        return f"({izq} {e.op} {der})"

    def llamada(self, e: Llamada):
        n = e.nombre

        if n == "vacio":
            return "ss_new()"
        if n == "nuevo":
            return f"ss_from_view({self.como_vista(e.args[0])})"
        if n == "vista":
            return f"ss_view({self.dir_de(e.args[0])})"
        if n == "largo":
            return f"sv_len_of({self.como_vista(e.args[0])})"
        if n == "igual":
            return (f"sv_equals({self.como_vista(e.args[0])}, "
                    f"{self.como_vista(e.args[1])})")
        if n == "rebanar":
            return (f"sv_slice({self.como_vista(e.args[0])}, "
                    f"{self.expr(e.args[1], 'usize')}, "
                    f"{self.expr(e.args[2], 'usize')})")
        if n == "empujar":
            return (f"ss_append_view({self.dir_de(e.args[0])}, "
                    f"{self.como_vista(e.args[1])})")
        if n == "imprimir":
            return self.imprimir(e.args[0])

        # funcion del usuario
        f = self.c.funciones.get(n)
        args = []
        for i, a in enumerate(e.args):
            p = f.params[i] if f and i < len(f.params) else None
            if p is not None and p.prestado:
                args.append(self.dir_de(a))
            else:
                if (p is not None and isinstance(a, Variable)
                        and a.nombre in self.con_bandera
                        and self.c.posee(p.tipo)):
                    self.pendientes.append(a.nombre)
                args.append(self.expr(a, p.tipo if p else None))
        destino = "ss_main_" if n == "main" else n
        return f"{destino}({', '.join(args)})"

    def dir_de(self, a):
        """La direccion de un sitio con nombre: `&x`, `&p.campo`, `&v.e[i]`."""
        if isinstance(a, Variable):
            return self.ref(a.nombre)
        return f"&{self.lugar(a)}"

    def como_vista(self, a):
        """Un argumento donde se pide una SafeView."""
        if self._tipo_de(a) == "str" and isinstance(a, (Variable, Campo, Indice)):
            return f"ss_view({self.dir_de(a)})"
        return self.expr(a, "view")

    def imprimir(self, a):
        t = self._tipo_de(a)
        if t == "str":
            return f'printf("%s", ss_cstr({self.dir_de(a)}))'
        if t == "view":
            v = self.como_vista(a)
            return f'printf(SV_FMT, SV_ARG({v}))'
        if t == "usize":
            return f'printf("%zu", {self.expr(a, "usize")})'
        if t == "i64":
            return f'printf("%lld", (long long){self.expr(a, "i64")})'
        if t == "bool":
            return f'printf("%s", ({self.expr(a, "bool")}) ? "true" : "false")'
        return f'printf("%s", "?")'


def generar(funciones, comprobador, archivo="<entrada>"):
    return Generador(comprobador, archivo).generar(funciones)
