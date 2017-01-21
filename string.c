#include <string.h>

uint32_t strlen(const char* s)
{
  uint32_t i = 0;
  while (*s++) {
    i++;
  }
  return i;
}
