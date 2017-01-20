#ifndef SCREEN_H
#define SCREEN_H

#include <stdint.h>

#define SCREEN_ADDR 0xb800
#define SCREEN_COLS 80
#define SCREEN_ROWS 25

#define BLACK 0x00
#define BLUE 0x01
#define GREEN 0x02
#define CYAN 0x03
#define RED 0x04
#define MAGENTA 0x05
#define BROWN 0x06
#define LIGHT_GREY 0x07
#define DARK_GREY 0x08
#define LIGHT_BLUE 0x09
#define LIGHT_GREEN 0x0A
#define LIGHT_CYAN 0x0B
#define LIGHT_RED 0x0C
#define LIGHT_MAGENTA 0x0D
#define LIGHT_BROWN 0x0E
#define WHITE 0x0F

/* clears whole screen */
void clear_screen();

void scroll();

/* prints a character at the given position */
void screen_print(char c, uint8_t row, uint8_t col);

/* print a character at the current position */
void printc(char s);

/* print a null-byte terminated string at the current position */
void printstr(char* s);

/* print a "len" characters at the current position */
void printstrl(char* s, uint8_t len);

void printint(uint8_t k);

uint32_t number_of_digits(uint32_t k);

void printk(uint32_t k);

void printhl(uint32_t dword);

void printhw(uint16_t word);

void printhb(uint8_t byte);

void printl(uint32_t l);

void printw(uint16_t word);

void printb(uint8_t byte);

#endif
