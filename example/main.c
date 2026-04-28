#include "pid0/pid0.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int example_submain(int argc, char **argv);
static int read_name_from_stdin(char *buffer, size_t buffer_size);
static void sleep_for_configured_duration(void);
static unsigned int configured_sleep_seconds(void);

int main(int argc, char **argv) {
  return pid0_run(example_submain, argc, argv);
}

static int example_submain(int argc, char **argv) {
  char input_buffer[256];
  const char *name = "World";

  if (argc > 1) {
    if (strcmp(argv[1], "-i") == 0) {
      if (read_name_from_stdin(input_buffer, sizeof(input_buffer)) != 0) {
        return 1;
      }
      if (input_buffer[0] != '\0') {
        name = input_buffer;
      }
    } else {
      name = argv[1];
    }
  }

  printf("Hello %s!\n", name);
  fflush(stdout);
  sleep_for_configured_duration();
  return 0;
}

static int read_name_from_stdin(char *buffer, size_t buffer_size) {
  size_t length;
  int ch = 0;

  if (buffer == NULL || buffer_size < 2) {
    fprintf(stderr, "example: invalid input buffer\n");
    return -1;
  }

  fputs("Name: ", stdout);
  fflush(stdout);

  if (fgets(buffer, (int)buffer_size, stdin) == NULL) {
    if (ferror(stdin)) {
      perror("example: fgets");
    }
    return -1;
  }

  length = strlen(buffer);
  if (length > 0 && buffer[length - 1] == '\n') {
    buffer[length - 1] = '\0';
    return 0;
  }

  while ((ch = getchar()) != '\n' && ch != EOF) {
  }
  fprintf(stderr, "example: input too long\n");
  return -1;
}

static void sleep_for_configured_duration(void) {
  struct timespec remaining;

  remaining.tv_sec = (time_t)configured_sleep_seconds();
  remaining.tv_nsec = 0;

  while (nanosleep(&remaining, &remaining) != 0) {
    if (errno != EINTR) {
      perror("example: nanosleep");
      return;
    }
  }
}

static unsigned int configured_sleep_seconds(void) {
  const char *value = getenv("PID0_EXAMPLE_SLEEP_SECONDS");
  char *end = NULL;
  unsigned long parsed;

  if (value == NULL || *value == '\0') {
    return 10U;
  }

  parsed = strtoul(value, &end, 10);
  if (end == value || *end != '\0') {
    fprintf(
        stderr,
        "example: invalid PID0_EXAMPLE_SLEEP_SECONDS=%s, using default 10\n",
        value);
    return 10U;
  }

  return (unsigned int)parsed;
}
