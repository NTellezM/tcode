/*
 * Fuzzing de runtime/safestr.c con libFuzzer.
 *
 * La entrada se lee como un guion de operaciones sobre un punado de
 * SafeString: se escriben, se recortan, se convierten en vistas y se comparan.
 * Ademas de que ASan+UBSan no digan nada, se comprueban invariantes que la
 * libreria promete (safestr.h): que las vistas y los strings dueños miden y
 * comparan igual, que el contenido vuelve entero, que el error de memoria es
 * pegajoso, etc. Si un invariante falla, aborta; el fuzzer lo guarda como
 * hallazgo.
 *
 *    make fuzz-safestr FUZZ_SEGUNDOS=60
 */
#include "safestr.h"

#include <assert.h>
#include <stdint.h>
#include <stdlib.h>

#define N 8              /* strings vivos a la vez */
#define SLOTS 64         /* maximo de operaciones por entrada */

static const uint8_t *entrada;
static size_t n_entrada;
static size_t pos;

static uint8_t byte_entrada(void)
{
    if (pos >= n_entrada) return 0;
    return entrada[pos++];
}

/* Un largo de 0..65535, con los bytes que haya. */
static size_t largo_entrada(void)
{
    size_t v = byte_entrada();
    if (v == 255) v = 256 + ((size_t)byte_entrada() << 8) + byte_entrada();
    if (v > 4096) v = 4096;      /* el guion no pide gigantes */
    return v;
}

/* Los `n` bytes siguientes, como vista: viven mientras viva la entrada. */
static SafeView vista_entrada(size_t n)
{
    size_t restante = (pos < n_entrada) ? n_entrada - pos : 0;
    if (n > restante) n = restante;
    SafeView v = sv_len((const char *)entrada + pos, n);
    pos += n;
    return v;
}

/* El texto de un string como vista, para comprobar sin tocar nada. */
static SafeView vista_de(const SafeString *s)
{
    return ss_view(s);
}

/* signo de un entero: -1, 0 o 1. */
static int signo(int x)
{
    return (x > 0) - (x < 0);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 4) return 0;      /* muy corto: nada que hacer */
    entrada = data;
    n_entrada = size;
    pos = 0;

    SafeString s[N];
    for (int i = 0; i < N; i++) s[i] = ss_new();

    int pasos = 0;
    while (pos + 1 < n_entrada && pasos < SLOTS) {
        uint8_t op = byte_entrada();
        size_t a = byte_entrada() % N;
        size_t b = byte_entrada() % N;
        pasos++;

        /* Ningun string crece sin fin: el que se paso, vuelve a nacer. */
        for (int i = 0; i < N; i++)
            if (ss_len(&s[i]) > (1u << 20)) { ss_free(&s[i]); s[i] = ss_new(); }

        switch (op % 26) {
        case 0: { /* set_len: reemplaza por bytes crudos */
            size_t n = largo_entrada();
            SafeView v = vista_entrada(n);
            ss_set_len(&s[a], v.ptr, v.len);
            break;
        }
        case 1: { /* append_len */
            size_t n = largo_entrada();
            SafeView v = vista_entrada(n);
            ss_append_len(&s[a], v.ptr, v.len);
            break;
        }
        case 2: { /* append_char */
            char c = (char)byte_entrada();
            ss_append_char(&s[a], c);
            break;
        }
        case 3: { /* insert_len */
            size_t n = largo_entrada();
            size_t en = byte_entrada() % (ss_len(&s[a]) + 1);
            SafeView v = vista_entrada(n);
            ss_insert_len(&s[a], en, v.ptr, v.len);
            break;
        }
        case 4: { /* remove */
            size_t desde = byte_entrada() % (ss_len(&s[a]) + 1);
            size_t hasta = desde + byte_entrada();
            ss_remove(&s[a], desde, hasta);
            break;
        }
        case 5: { /* pop */
            ss_pop(&s[a]);
            break;
        }
        case 6: ss_trim(&s[a]); break;
        case 7: ss_to_upper(&s[a]); break;
        case 8: ss_to_lower(&s[a]); break;
        case 9: ss_chomp(&s[a]); break;
        case 10: { /* reserve + shrink, con numeros pequenos */
            size_t n = byte_entrada() + byte_entrada();
            ss_reserve(&s[a], n);
            ss_shrink(&s[a]);
            break;
        }
        case 11: { /* clone en otro slot */
            SafeString copia = ss_clone(&s[a]);
            ss_free(&s[b]);
            s[b] = copia;
            break;
        }
        case 12: { /* set_ss: reemplaza b por a (sin alias) */
            if (a != b) {
                SafeString copia = ss_clone(&s[a]);
                ss_free(&s[b]);
                s[b] = copia;
            }
            break;
        }
        case 13: { /* clear */
            ss_clear(&s[a]);
            break;
        }
        case 14: { /* free: vuelve a nacer */
            ss_free(&s[a]);
            s[a] = ss_new();
            break;
        }
        case 15: { /* append_ss: dobla si es a si mismo, asi que acotado */
            if (ss_len(&s[a]) <= (1u << 16)) ss_append_ss(&s[a], &s[b]);
            break;
        }
        case 16: { /* replace_all de un byte por dos bytes */
            char viejo[2] = { (char)byte_entrada(), 0 };
            char nuevo[3] = { (char)byte_entrada(), (char)byte_entrada(), 0 };
            if (viejo[0] != 0 && nuevo[0] != 0)
                ss_replace_all(&s[a], viejo, nuevo);
            break;
        }
        /* ---- vistas: operan y se descartan ---- */
        case 17: { /* view_slice + sv_index_of / sv_contains */
            size_t n = largo_entrada();
            SafeView aguja = vista_entrada(n);
            SafeView heno = vista_de(&s[a]);
            (void)sv_index_of(heno, aguja);
            (void)sv_contains(heno, aguja);
            break;
        }
        case 18: { /* sv_starts_with / sv_ends_with */
            size_t n = largo_entrada();
            SafeView pref = vista_entrada(n);
            SafeView heno = vista_de(&s[a]);
            (void)sv_starts_with(heno, pref);
            (void)sv_ends_with(heno, pref);
            break;
        }
        case 19: { /* sv_to_long */
            bool ok = false;
            (void)sv_to_long(vista_de(&s[a]), &ok);
            break;
        }
        case 20: { /* sv_next: trocea por un separador */
            size_t n = largo_entrada();
            SafeView sep = vista_entrada(n);
            SafeView resto = vista_de(&s[a]);
            SafeView campo;
            int vueltas = 0;
            while (sv_next(&resto, sep, &campo) && vueltas < 32) vueltas++;
            break;
        }
        case 21: { /* ss_split_view */
            size_t n = largo_entrada();
            SafeView sep = vista_entrada(n);
            SafeView campos[16];
            (void)ss_split_view(vista_de(&s[a]), sep, campos, 16);
            break;
        }
        case 22: { /* ss_view_slice */
            size_t desde = byte_entrada() % (ss_len(&s[a]) + 1);
            size_t hasta = desde + byte_entrada();
            (void)ss_view_slice(&s[a], desde, hasta);
            break;
        }
        /* ---- oraculos: igualdad entre string dueño y vista ---- */
        case 23: {
            /* la vista de un string lee exactamente su contenido */
            SafeView v = vista_de(&s[a]);
            assert(ss_equals_len(&s[a], v.ptr, v.len));
            break;
        }
        case 24: {
            /* equals, hash y cmp dicen lo mismo por las dos vias */
            bool e_ss = ss_equals(&s[a], &s[b]);
            bool e_sv = sv_equals(vista_de(&s[a]), vista_de(&s[b]));
            assert(e_ss == e_sv);
            assert(ss_hash(&s[a]) == sv_hash(vista_de(&s[a])));
            assert(signo(ss_cmp(&s[a], &s[b])) ==
                   signo(sv_cmp(vista_de(&s[a]), vista_de(&s[b]))));
            break;
        }
        case 25: {
            /* ss_index_of y ss_contains no se contradicen */
            size_t n = largo_entrada();
            SafeView aguja = vista_entrada(n);
            size_t donde = ss_index_of_len(&s[a], aguja.ptr, aguja.len);
            bool esta = ss_contains_len(&s[a], aguja.ptr, aguja.len);
            assert(esta == (donde != SS_NPOS));
            if (donde != SS_NPOS) {
                SafeView trozo = ss_view_slice(&s[a], donde, donde + aguja.len);
                assert(sv_equals(trozo, aguja));
            }
            break;
        }
        }
    }

    for (int i = 0; i < N; i++) ss_free(&s[i]);
    return 0;
}
