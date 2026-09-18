#define PID0_IMPLEMENTATION 1
#include "libpid0_single_header.h"

#include <stdio.h>

static int example_submain(int argc, char **argv);

int main(int argc, char **argv) {
  return pid0_run(example_submain, argc, argv);
}

static int example_submain(int argc, char **argv) {
  const char *name = argc > 1 ? argv[1] : "World";

  printf("Hello %s from single-header libpid0!\n", name);
  fflush(stdout);
  return 0;
}
