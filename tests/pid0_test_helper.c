#include "pid0/pid0.h"

#include "pid0_internal.h"

#include <errno.h>
#include <pty.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static int parse_int(const char *value, int *result);
static int mode_direct_exit(int argc, char **argv);
static int mode_assert_not_pid1(int argc, char **argv);
static int mode_signal_wait(int argc, char **argv);
static int mode_tty_foreground(void);

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s MODE [ARGS...]\n", argv[0]);
    return 2;
  }

  if (strcmp(argv[1], "tty-foreground") == 0) {
    return mode_tty_foreground();
  }

  if (strcmp(argv[1], "direct-exit") == 0) {
    return pid0_run(mode_direct_exit, argc, argv);
  }
  if (strcmp(argv[1], "assert-not-pid1") == 0) {
    return pid0_run(mode_assert_not_pid1, argc, argv);
  }
  if (strcmp(argv[1], "signal-wait") == 0) {
    return pid0_run(mode_signal_wait, argc, argv);
  }

  fprintf(stderr, "unknown mode: %s\n", argv[1]);
  return 2;
}

static int parse_int(const char *value, int *result) {
  char *end = NULL;
  long parsed = strtol(value, &end, 10);

  if (value == NULL || *value == '\0' || end == value || *end != '\0') {
    return -1;
  }

  *result = (int)parsed;
  return 0;
}

static int mode_direct_exit(int argc, char **argv) {
  int code = 0;

  if (argc < 3 || parse_int(argv[2], &code) != 0) {
    fprintf(stderr, "direct-exit requires an integer code\n");
    return 2;
  }
  return code;
}

static int mode_assert_not_pid1(int argc, char **argv) {
  int code = 0;

  if (argc < 3 || parse_int(argv[2], &code) != 0) {
    fprintf(stderr, "assert-not-pid1 requires an integer code\n");
    return 2;
  }
  return getpid() == 1 ? 97 : code;
}

static int mode_signal_wait(int argc, char **argv) {
  (void)argc;
  (void)argv;

  for (;;) {
    pause();
  }

  return 0;
}

static int mode_tty_foreground(void) {
  int master_fd = -1;
  int slave_fd = -1;

  if (openpty(&master_fd, &slave_fd, NULL, NULL, NULL) != 0) {
    perror("openpty");
    return 2;
  }

  if (setsid() < 0 && errno != EPERM) {
    perror("setsid");
    return 2;
  }
  if (ioctl(slave_fd, TIOCSCTTY, 0) != 0) {
    perror("TIOCSCTTY");
    return 2;
  }
  if (tcsetpgrp(slave_fd, getpgrp()) != 0) {
    perror("tcsetpgrp(self)");
    return 2;
  }
  if (dup2(slave_fd, STDIN_FILENO) < 0 || dup2(slave_fd, STDOUT_FILENO) < 0 ||
      dup2(slave_fd, STDERR_FILENO) < 0) {
    perror("dup2");
    return 2;
  }

  pid_t child_pid = fork();
  if (child_pid < 0) {
    perror("fork");
    return 2;
  }
  if (child_pid == 0) {
    if (setpgid(0, 0) != 0) {
      _exit(3);
    }
    sleep(2);
    _exit(0);
  }

  if (setpgid(child_pid, child_pid) != 0 && errno != EACCES && errno != ESRCH) {
    perror("setpgid");
    kill(child_pid, SIGKILL);
    waitpid(child_pid, NULL, 0);
    return 2;
  }
  if (pid0_set_foreground_pgrp_for_stdio(child_pid) != 0) {
    perror("pid0_set_foreground_pgrp_for_stdio");
    kill(child_pid, SIGKILL);
    waitpid(child_pid, NULL, 0);
    return 2;
  }

  pid_t foreground = tcgetpgrp(STDIN_FILENO);
  if (foreground != child_pid) {
    fprintf(stderr, "foreground pgid=%d expected=%d\n", (int)foreground,
            (int)child_pid);
    kill(child_pid, SIGKILL);
    waitpid(child_pid, NULL, 0);
    return 2;
  }

  kill(child_pid, SIGKILL);
  waitpid(child_pid, NULL, 0);
  return 0;
}
