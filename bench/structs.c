/* Lo mismo en C: structs por puntero const, sin comprobaciones. */
#include <stdio.h>
#include <stddef.h>

typedef struct { size_t x, y; } Punto;

static size_t dist2(const Punto* a, const Punto* b)
{
    size_t dx = a->x > b->x ? a->x - b->x : b->x - a->x;
    size_t dy = a->y > b->y ? a->y - b->y : b->y - a->y;
    return dx * dx + dy * dy;
}

int main(void)
{
    Punto p = {0, 0}, q = {3, 4};
    size_t acc = 0;
    for (size_t i = 0; i < 100000000; i++) {
        p.x = i % 1000;
        q.y = i % 977;
        acc += dist2(&p, &q) % 1024;
    }
    printf("%zu\n", acc);
    return 0;
}
