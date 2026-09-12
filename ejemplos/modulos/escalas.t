// escalas.t — dos modulos que declaran lo mismo, en el mismo programa.
//
// `usar` a secas trae los nombres tal cual; `como` les pone delante el del
// modulo. Traer los dos a secas seria un error, y el compilador diria como
// arreglarlo.
//
//     ./escalas

usar "lib/celsius.t" como c;
usar "lib/fahrenheit.t" como f;
usar "std/texto";

fn linea(escala: view, grados: usize) -> str {
    return $"{rellenar(escala, 12)}{grados}\n";
}

fn main() -> usize {
    let kelvin_por_diez = 3000; // 300,0 K

    imprimir(linea(c.nombre(), c.desde_kelvin(kelvin_por_diez)));
    imprimir(linea(f.nombre(), f.desde_kelvin(kelvin_por_diez)));
}
