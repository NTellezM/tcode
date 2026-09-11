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
