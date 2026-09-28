// std/par.t — dos valores juntos.
//
// Una funcion devuelve un valor. Cuando hacen falta dos, esto es lo que hay,
// y no lo pone el compilador: `Par` es un struct generico corriente, escrito
// en Tcode, con las mismas reglas de propiedad que cualquier otro. Si `A` o
// `B` poseen memoria, el par la posee, y se libera sola.

struct Par<A, B> { primero: A, segundo: B }

fn par<A, B>(a: A, b: B) -> Par<A, B> {
    return Par { primero: a, segundo: b };
}

// Del reves, por si el que recibe los quiere al contrario.
fn volteado<A, B>(p: &Par<A, B>) -> Par<B, A> {
    return Par { primero: copiar(p.segundo), segundo: copiar(p.primero) };
}
