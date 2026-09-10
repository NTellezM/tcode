/* El equivalente en C escrito a mano, sin comprobaciones. */
#include <stdio.h>
#include <stddef.h>
int main(void)
{
    size_t acc = 0;
    for (size_t i = 0; i < 200000000; i++)
        acc = acc + i % 7;
    printf("%zu\n", acc);
    return 0;
}
