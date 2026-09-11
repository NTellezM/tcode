// lib/fahrenheit.t — otra escala, con las mismas funciones.
//
// `nombre` y `desde_kelvin` se llaman igual que en `celsius.t`, y no se
// estorban: cada archivo ve lo que el mismo importa.

fn nombre() -> str { return nuevo("Fahrenheit"); }

fn desde_kelvin(kd: usize) -> usize {
    if kd < 2553 { return 0; }
    return ((kd - 2553) * 9) / 50;
}
