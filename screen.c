#include <screen.h>
#include <memory.h>

/* how many spaces a full tab should equal */
#define TAB_WIDTH 4

static uint16_t *screen = (uint16_t*)(SCREEN_ADDR << 4);

/* current row */
static uint8_t row = 0;
/* current col */
static uint8_t col = 0;

static inline uint8_t get_color_attribute(uint8_t fg, uint8_t bg)
{
  return (bg << 4) | (fg & 0x0F);
}

static inline uint16_t get_text_attribute(char c, uint8_t fg, uint8_t bg)
{
  return (get_color_attribute(fg, bg) << 8) | c;
}

/* clears whole screen */
void clear_screen()
{
  uint16_t blank = get_text_attribute(' ', WHITE, BLACK);
  memsetw(screen, blank, SCREEN_ROWS * SCREEN_COLS);

  /*int i;
  for (i = 0; i < SCREEN_ROWS * SCREEN_COLS; ++i) {
    screen[i] = blank;
  }*/
}

/* moves all rows one up */
void scroll() {
  /* move everything one row back */
  memcpyw(screen, screen + SCREEN_COLS, SCREEN_ROWS * SCREEN_COLS - SCREEN_COLS);
  /* set last row to empty character */
  uint16_t blank = get_text_attribute(' ', WHITE, BLACK);
  memsetw(screen + SCREEN_ROWS * SCREEN_COLS - SCREEN_COLS, blank, SCREEN_COLS);

  // uint8_t i;
  // uint16_t prev = 0;
  // for (i = 1; i < SCREEN_ROWS; i++) {
  //   /* copy current row to prevous one */
  //   memcpyw(screen + prev, screen + prev + SCREEN_COLS, SCREEN_COLS);
  //   prev += SCREEN_COLS;
  // }
  // /* zero out last row */
  // uint16_t c = get_text_attribute(' ', WHITE, BLACK);
  // memsetw(screen + prev, c, SCREEN_COLS);
}

/* prints a character at the given position */
void screen_print(char c, uint8_t row, uint8_t col)
{
  uint16_t data = get_text_attribute(c, WHITE, BLACK);
  screen[row * SCREEN_COLS + col] = data;
}

/* print a character at the current position */
void printc(char s) {
  if (row == SCREEN_ROWS) {
    scroll();
    row = row - 1;
  }

  if (s == '\n') {
    col = 0;
    row++;
  } else if (s == '\t') {
  	uint8_t spaces = TAB_WIDTH - col % TAB_WIDTH;
  	uint8_t end = col + spaces;

  	/* make sure we don't cross any rows */
  	if (end > SCREEN_COLS) {
  		end = SCREEN_COLS;
  	}

  	uint8_t i;
  	for (i = col; i < end; i++) {
  		screen_print(' ', row, col++);
  	}
  } else if (s >= 0x20 && s <= 0x7E ) {
  	/* print everything that you can type on a keyboard ... */
    screen_print(s, row, col++);
  }

  if (col == SCREEN_COLS) {
    col = 0;
    row++;
  }
}

/* print a null-byte terminated string at the current position */
void printstr(char* s)
{
  while (*s) {
    printc(*s++);
  }
}

/* print a "len" characters at the current position */
void printstrl(char* s, uint8_t len) {
  uint8_t k;
  for (k = 0; k < len; k++) {
    printc(s[k]);
  }
}

void printint(uint8_t k) {
  char c = '0' + k;
  printc(c);
}

uint32_t number_of_digits(uint32_t k) {
  uint32_t p = 10, q = 1;
  while (k > p) {
    q++;
    p = p * 10;
  }
  return q;
}

void printk(uint32_t k) {
  uint32_t p, q;

  /* there's max. 10 digits in a 32 bit int */
  char buf[10];
  memset((uint8_t*)buf, 0, 10);

  q = 0;
  do {
    p = k % 10;
    k = k / 10;

    buf[10 - (q++) - 1] = '0' + p;
  } while (k > 0);

  for (p = 0; p < 10; p++) {
    if (buf[p] == 0) {
      continue;
    }
    printc(buf[p]);
  }
}

void printhl(uint32_t dword) {
  /* print string representation of "word" as hex */
  char* alphabet = "0123456789ABCDEF";

  /* max. 8 nibbles in a 32 bit int */
  char buf[8];

  uint8_t p, q = 0;
  do {
    buf[8 - (q++) - 1] = alphabet[dword % 16];
    dword = dword / 16;
  } while (q < 8);

  for (p = 0; p < q; p++) {
    printc(buf[p]);
  }
}

void printhw(uint16_t word) {
  printhl((uint32_t)word);
}

void printhb(uint8_t byte) {
  printhl((uint32_t)byte);
}

void printl(uint32_t l) {
  printk(l);
}

void printw(uint16_t word) {
  printk((uint32_t)word);
}

void printb(uint8_t byte) {
  printk((uint32_t)byte);
}
