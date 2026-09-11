// lib/celsius.t — una escala.

fn nombre() -> str { return nuevo("Celsius"); }

// Desde grados Kelvin por diez, para no necesitar decimales.
fn desde_kelvin(kd: usize) -> usize {
    if kd < 2732 { return 0; }
    return (kd - 2732) / 10;
}
