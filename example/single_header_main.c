#define PID0_IMPLEMENTATION 1
#include "libpid0_single_header.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static int example_submain(int argc, char **argv);
static void sleep_for_configured_duration(void);
static unsigned int configured_sleep_seconds(void);

int main(int argc, char **argv) {
  return pid0_run(example_submain, argc, argv);
}

static int example_submain(int argc, char **argv) {
  const char *name = argc > 1 ? argv[1] : "World";

  printf("Hello %s from single-header libpid0!\n", name);
  fflush(stdout);
  sleep_for_configured_duration();
  return 0;
}

static void sleep_for_configured_duration(void) {
  struct timespec remaining = {(time_t)configured_sleep_seconds(), 0};

  while (nanosleep(&remaining, &remaining) != 0) {
    if (errno != EINTR) {
      perror("single-header-example: nanosleep");
      return;
    }
  }
}

static unsigned int configured_sleep_seconds(void) {
  const char *value = getenv("PID0_EXAMPLE_SLEEP_SECONDS");

  if (value == NULL || *value == '\0') {
    return 1U;
  }

  char *end = NULL;
  unsigned long parsed = strtoul(value, &end, 10);
  if (end == value || *end != '\0') {
    fprintf(stderr,
            "single-header-example: invalid PID0_EXAMPLE_SLEEP_SECONDS=%s, "
            "using default 1\n",
            value);
    return 1U;
  }

  return (unsigned int)parsed;
}
