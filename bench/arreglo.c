/* El mismo recorrido en C, sin comprobar el indice. */
#include <stdio.h>
#include <stddef.h>
int main(void)
{
    size_t v[64] = {
        13,41,7,58,22,3,47,19,60,31,5,52,28,9,44,17,
        62,35,1,50,26,11,39,15,57,29,6,48,24,2,43,20,
        61,37,4,53,27,10,45,18,59,33,8,51,25,12,40,16,
        63,36,0,49,23,14,42,21,55,30,38,54,32,46,34,56
    };
    size_t pos = 0, acc = 0;
    for (size_t i = 0; i < 200000000; i++) {
        pos = v[pos];
        acc = acc + pos;
    }
    printf("%zu\n", acc);
    return 0;
}
