#include "pid0_internal.h"

#include <unistd.h>

int main(void) {
  char input[4097];
  struct timespec timeout;
  ssize_t count = read(STDIN_FILENO, input, sizeof(input) - 1);

  if (count > 0) {
    input[count] = '\0';
    (void)pid0_parse_stop_timeout(input, &timeout);
  }
  return 0;
}
