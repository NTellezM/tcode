"""Arbol sintactico de safestr. Solo datos: sin logica."""

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Nodo:
    linea: int = field(default=0, kw_only=True)


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
class Retorno(Nodo):
    valor: Optional[Nodo]

@dataclass
class ExprSentencia(Nodo):
    expr: Nodo


# ---------- declaraciones de alto nivel ----------

@dataclass
class Parametro:
    nombre: str
    tipo: str
    mutable: bool
    movida: bool = False

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
