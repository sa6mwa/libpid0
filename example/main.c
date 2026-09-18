#include "pid0/pid0.h"

#include <stdio.h>
#include <string.h>

static int example_submain(int argc, char **argv);
static int read_name_from_stdin(char *buffer, size_t buffer_size);

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
