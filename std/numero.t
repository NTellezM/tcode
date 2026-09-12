// std/numero.t — aritmetica que puede fallar, y lo declara.
//
// Los operadores `+`, `-` y `*` ya abortan si desbordan: eso lo pone el
// compilador y no hace falta pedirlo. Lo que no puede poner el compilador es
// que dividir entre cero sea un error *recuperable* en vez de una parada, y
// eso es lo que hay aqui.

fn dividir(a: usize, b: usize) -> usize ! {
    if b == 0 { falla "division por cero"; }
    return a / b;
}

fn resto(a: usize, b: usize) -> usize ! {
    if b == 0 { falla "resto de una division por cero"; }
    return a % b;
}

// El porcentaje de `parte` sobre `total`, redondeado hacia abajo.
fn porcentaje(parte: usize, total: usize) -> usize ! {
    if total == 0 { falla "no hay total sobre el que calcular un porcentaje"; }
    return try dividir(parte * 100, total);
}

fn menor_de(a: usize, b: usize) -> usize {
    if a < b { return a; }
    return b;
}

fn mayor_de(a: usize, b: usize) -> usize {
    if a > b { return a; }
    return b;
}

// Acota un valor a un intervalo cerrado.
fn acotar(n: usize, minimo_val: usize, maximo_val: usize) -> usize {
    return menor_de(mayor_de(n, minimo_val), maximo_val);
}

// ---------- decimales ----------

// Si dos decimales estan lo bastante cerca. Es lo que casi siempre se queria
// escribir al poner `==`: `0.1 + 0.2` no es `0.3` ni lo va a ser nunca, y
// compararlos bit a bit da `false` sin que nada este mal.
fn cerca(a: f64, b: f64, tolerancia: f64) -> bool {
    return absoluto(a -? b) <= tolerancia;
}

// Un porcentaje que no pierde la parte decimal por el camino.
fn porcentaje_exacto(parte: f64, total: f64) -> f64 ! {
    if cerca(total, 0.0, 0.0) { falla "no hay total sobre el que calcular"; }
    return (parte * 100.0) / total;
}

// Acota un decimal a un intervalo cerrado.
fn acotar_decimal(x: f64, minimo_val: f64, maximo_val: f64) -> f64 {
    if x < minimo_val { return minimo_val; }
    if x > maximo_val { return maximo_val; }
    return x;
}

// Media que no trunca: `media` de `std/lista` divide enteros.
fn media_decimal(suma: f64, cuantos: usize) -> f64 ! {
    if cuantos == 0 { falla "no hay nada de lo que sacar la media"; }
    return suma / (cuantos como f64);
}
