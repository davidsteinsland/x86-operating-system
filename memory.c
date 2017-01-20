#include <memory.h>

uint8_t* memcpy(uint8_t *dest, const uint8_t *src, uint32_t count)
{
  uint32_t i;
  for (i = 0; i < count; i++) {
    dest[i] = src[i];
  }
  return dest;
}

uint16_t* memcpyw(uint16_t *dest, const uint16_t *src, uint32_t count)
{
  uint32_t i;
  for (i = 0; i < count; i++) {
    dest[i] = src[i];
  }
  return dest;
}

uint8_t* memset(uint8_t *dest, uint8_t val, uint32_t count)
{
  uint32_t i;
  for (i = 0; i < count; i++) {
    dest[i] = val;
  }
  return dest;
}

uint16_t* memsetw(uint16_t *dest, uint16_t val, uint32_t count)
{
    uint32_t i;
    for (i = 0; i < count; i++) {
      dest[i] = val;
    }
    return dest;
}
