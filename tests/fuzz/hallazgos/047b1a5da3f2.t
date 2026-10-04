enum Json {
    Nulo,
    Verdad(bool),
    Numero(i64),
    Texto(str),
    Lista(list<Json>) }
fn escribir(v: &Json) -> str {
    return match v {
        Json.Nulo -> nuevo("null"),
        Json.Verdad(b) -> nuevo(if b { "true" } else { "false" }),
        Json.Numero(n) -> texto(n),
        Json.Texto(s) -> {
            var r = nuevo("\"");
            empujar(r, s);
            return r;
        }
        Json.Lista(xs) -> {
            var r = nuevo("[");
            var primero = true;
            for x en xs {
                if !primero { empujar(r, ","); }
                primero = false;
            }
            return r;
        }
    };
}
