// std/fecha.t — fechas y horas desde `ahora_ms`.
//
//     let ms = fecha.ahora();          // milisegundos desde 1970, en UTC
//     let p  = fecha.a_partes(ms);     // anio, mes, dia, hora, minuto...
//     let s  = fecha.formatear(ms);    // "2026-10-02T21:30:00Z"
//
// Todo en UTC: no hay zonas horarias, que es lo que de verdad se puede hacer
// sin una base de datos de husos. El calendario gregoriano, con sus bisiestos.
//
// Un bucle de juego no mira el calendario: mira cuanto tarda y espera sin
// girar en el sitio.
//
//     let antes = fecha.milisegundos_monotonico();
//     fecha.dormir_milisegundos(16);
//     let tardo = fecha.milisegundos_monotonico() - antes;
//
// `ahora` es la hora de pared —la que marca el reloj del sistema, que salta
// cuando el NTP corrige o cuando alguien la cambia a mano—, y
// `milisegundos_monotonico` es la que solo avanza. Para medir una duracion
// se usa la segunda: con la primera, un salto de hora da un tiempo negativo
// o un fotograma que dura dos horas.

struct Partes {
    anio: i64,
    mes: i64,        // 1..12
    dia: i64,        // 1..31
    hora: i64,       // 0..23
    minuto: i64,     // 0..59
    segundo: i64,    // 0..59
    dia_semana: i64, // 0 domingo .. 6 sabado
}

fn ahora() -> i64 {
    return ahora_ms();
}

// Milisegundos desde 1970 a sus partes, por el calendario civil. La cuenta es
// la de Howard Hinnant: `dias` a anio/mes/dia sin tablas ni bucles.
fn a_partes(ms: i64) -> Partes {
    var dias = ms / 86400000;
    var resto = ms % 86400000;
    if resto < 0 { resto = resto + 86400000; dias = dias - 1; }
    let hora = resto / 3600000;
    let minuto = resto % 3600000 / 60000;
    let segundo = resto % 60000 / 1000;
    // 1970-01-01 fue jueves, que es el 4.
    var dia_semana = (dias + 4) % 7;
    if dia_semana < 0 { dia_semana = dia_semana + 7; }

    let z = dias + 719468;
    let era = z / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    var anio = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let dia = doy - (153 * mp + 2) / 5 + 1;
    var mes = mp + 3;
    if mp >= 10 { mes = mp - 9; }
    if mes <= 2 { anio = anio + 1; }

    return Partes {
        anio: anio, mes: mes, dia: dia, hora: hora,
        minuto: minuto, segundo: segundo, dia_semana: dia_semana,
    };
}

// Las partes, de vuelta a milisegundos.
fn a_ms(p: &Partes) -> i64 {
    var y = p.anio;
    let m = p.mes;
    if m <= 2 { y = y - 1; }
    let era = y / 400;
    let yoe = y - era * 400;
    var mm = m + 9;
    if m > 2 { mm = m - 3; }
    let doy = (153 * mm + 2) / 5 + p.dia - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let dias = era * 146097 + doe - 719468;
    return dias * 86400000 + p.hora * 3600000 + p.minuto * 60000 + p.segundo * 1000;
}

fn dos(n: i64) -> str {
    if n < 10 { return $"0{n}"; }
    return $"{n}";
}

// "2026-10-02" de unos milisegundos.
fn a_fecha(ms: i64) -> str {
    let p = a_partes(ms);
    return $"{p.anio}-{dos(p.mes)}-{dos(p.dia)}";
}

// "21:30:00" de unos milisegundos.
fn a_hora(ms: i64) -> str {
    let p = a_partes(ms);
    return $"{dos(p.hora)}:{dos(p.minuto)}:{dos(p.segundo)}";
}

// ISO 8601, en UTC: "2026-10-02T21:30:00Z".
fn formatear(ms: i64) -> str {
    let p = a_partes(ms);
    return $"{p.anio}-{dos(p.mes)}-{dos(p.dia)}T{dos(p.hora)}:{dos(p.minuto)}:{dos(p.segundo)}Z";
}

// El nombre del dia de la semana, para leerlo.
fn dia_de_semana(p: &Partes) -> view {
    if p.dia_semana == 0 { return "domingo"; }
    if p.dia_semana == 1 { return "lunes"; }
    if p.dia_semana == 2 { return "martes"; }
    if p.dia_semana == 3 { return "miercoles"; }
    if p.dia_semana == 4 { return "jueves"; }
    if p.dia_semana == 5 { return "viernes"; }
    return "sabado";
}

// ----------------------------------------------------- el reloj y la espera

externo "unistd.h" {
    // Las dos duermen de verdad: el proceso suelta el procesador y el sistema
    // lo despierta. Cruzan el borde de `externo` porque solo llevan y
    // devuelven enteros.
    //
    // `usleep` vive bajo `_DEFAULT_SOURCE` en glibc: con `-std=c17` y sin esa
    // macro no esta declarada, el compilador de C avisa de una declaracion
    // implicita —y desde GCC 14 eso es un error—. `tcodec` la define al
    // compilar el C, asi que aqui no hay aviso; quien compile este modulo por
    // su cuenta tiene que definirla.
    fn usleep(microsegundos: u32) -> i32;
    fn sleep(segundos: u32) -> u32;
}

// Duerme `ms` milisegundos. `usleep` toma los microsegundos en 32 bits, asi
// que las esperas muy largas van por tramos de mil segundos.
fn dormir_milisegundos(ms: usize) {
    var quedan = ms;
    while quedan > 0 {
        var trozo = quedan;
        if trozo > 1000000 { trozo = 1000000; }
        usleep((trozo * 1000) como u32);
        quedan = quedan - trozo;
    }
}

// Duerme `s` segundos, enteros. `sleep` va de segundo en segundo y, si una
// senal lo corta, devuelve los que le faltaban: por eso el bucle.
fn dormir_segundos(s: usize) {
    var quedan = s;
    while quedan > 0 {
        var trozo = quedan;
        if trozo > 1000000000 { trozo = 1000000000; }
        let r = sleep(trozo como u32);
        if r == 0 { quedan = 0; } else { quedan = r como usize; }
    }
}

// El reloj que solo avanza, en milisegundos. `ahora` es la hora de pared;
// esta no salta si alguien cambia la hora del sistema. Es el `monotono_ms`
// del runtime, que pide `CLOCK_MONOTONIC` a POSIX y cae al reloj de pared
// donde la plataforma no se lo declare —glibc necesita `_DEFAULT_SOURCE` en
// la linea de `cc`—. Si alguna vez vale lo mismo que `ahora`, es que cayo al
// de pared.
fn milisegundos_monotonico() -> i64 {
    return monotono_ms();
}
