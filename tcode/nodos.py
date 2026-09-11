"""Arbol sintactico de Tcode. Solo datos: sin logica."""

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Nodo:
    linea: int = field(default=0, kw_only=True)
    # De que archivo salio, para que el error lo diga con varios modulos
    archivo: str = field(default="", kw_only=True)


# ---------- expresiones ----------

@dataclass
class Entero(Nodo):
    valor: int

@dataclass
class Cadena(Nodo):
    valor: str

@dataclass
class Booleano(Nodo):
    valor: bool

@dataclass
class Variable(Nodo):
    nombre: str

@dataclass
class Llamada(Nodo):
    nombre: str
    args: list

@dataclass
class Campo(Nodo):
    """Acceso a un campo: `p.x`"""
    objeto: Nodo
    nombre: str

@dataclass
class Indice(Nodo):
    """Acceso a un elemento: `v[i]`"""
    arreglo: Nodo
    indice: Nodo

@dataclass
class LiteralStruct(Nodo):
    tipo: str
    campos: list          # [(nombre, expr)]

@dataclass
class LiteralArreglo(Nodo):
    elementos: list

@dataclass
class Try(Nodo):
    """`try f(..)`: si falla, la falla sube al que llamo."""
    expr: Nodo

@dataclass
class Sino(Nodo):
    """`f(..) sino valor`: si falla, se usa `valor`."""
    expr: Nodo
    alternativa: Nodo

@dataclass
class Binaria(Nodo):
    op: str
    izq: Nodo
    der: Nodo

@dataclass
class Unaria(Nodo):
    op: str
    valor: Nodo


# ---------- sentencias ----------

@dataclass
class Declaracion(Nodo):
    nombre: str
    tipo: str
    valor: Nodo
    mutable: bool
    # La pone el comprobador: si el valor se movio a otro sitio, el generador
    # no debe liberarlo al cerrar el bloque.
    movida: bool = False

@dataclass
class Asignacion(Nodo):
    """El destino puede ser `x`, `p.campo` o `v[i]`."""
    lugar: Nodo
    valor: Nodo

@dataclass
class Si(Nodo):
    cond: Nodo
    entonces: list
    sino: Optional[list]

@dataclass
class Mientras(Nodo):
    cond: Nodo
    cuerpo: list

@dataclass
class Para(Nodo):
    """`for x en xs { ... }` sobre una lista o un arreglo."""
    variable: str
    coleccion: Nodo
    cuerpo: list

@dataclass
class Romper(Nodo):
    pass

@dataclass
class Continuar(Nodo):
    pass

@dataclass
class Retorno(Nodo):
    valor: Optional[Nodo]

@dataclass
class Falla(Nodo):
    """`falla "motivo";` sale de la funcion con una falla."""
    motivo: str

@dataclass
class ExprSentencia(Nodo):
    expr: Nodo


# ---------- declaraciones de alto nivel ----------

@dataclass
class Parametro:
    nombre: str
    tipo: str
    mutable: bool          # `mut T`: prestado para modificar
    compartido: bool = False   # `&T`: prestado para leer
    movida: bool = False

    @property
    def prestado(self):
        return self.mutable or self.compartido

@dataclass
class Usar(Nodo):
    ruta: str

@dataclass
class CampoDef:
    nombre: str
    tipo: str
    linea: int = 0

@dataclass
class Struct(Nodo):
    nombre: str
    campos: list          # [CampoDef]

@dataclass
class Funcion(Nodo):
    nombre: str
    params: list
    retorno: Optional[str]
    cuerpo: list
    # declarada con `!`: puede fallar
    falible: bool = False
