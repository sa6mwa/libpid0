#include "pid0/pid0.h"

#include "pid0_internal.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static int pid0_supervise(pid0_submain_fn submain, int argc, char **argv);
static void pid0_add_timespec(const struct timespec *lhs,
                              const struct timespec *rhs,
                              struct timespec *result);
static int pid0_remaining_timeout(const struct timespec *deadline,
                                  struct timespec *remaining);
static int pid0_parse_duration_component(const char **cursor,
                                         struct timespec *timeout_out);
static void pid0_warn_invalid_timeout(const char *value);

int pid0_run(pid0_submain_fn submain, int argc, char **argv) {
  if (submain == NULL) {
    fprintf(stderr, "pid0: submain must not be NULL\n");
    return 64;
  }

  if (getpid() != 1) {
    return submain(argc, argv);
  }

  return pid0_supervise(submain, argc, argv);
}

int pid0_is_terminal_fd(int fd) { return fd >= 0 && isatty(fd) == 1; }

int pid0_set_foreground_pgrp_for_stdio(pid_t pgid) {
  const int fds[] = {STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO};
  int last_error = 0;
  size_t i;
  size_t j;

  for (i = 0; i < sizeof(fds) / sizeof(fds[0]); ++i) {
    int fd = fds[i];
    int seen = 0;

    for (j = 0; j < i; ++j) {
      if (fds[j] == fd) {
        seen = 1;
        break;
      }
    }
    if (seen || !pid0_is_terminal_fd(fd)) {
      continue;
    }

    if (tcsetpgrp(fd, pgid) != 0) {
      if (errno == ENOTTY || errno == EPERM) {
        continue;
      }
      last_error = errno;
    }
  }

  if (last_error != 0) {
    errno = last_error;
    return -1;
  }
  return 0;
}

int pid0_is_terminate_signal(int signum) {
  return signum == SIGTERM || signum == SIGINT || signum == SIGQUIT ||
         signum == SIGHUP;
}

int pid0_parse_stop_timeout(const char *value, struct timespec *timeout_out) {
  const char *cursor = value;
  struct timespec timeout = {PID0_DEFAULT_STOP_TIMEOUT_SECONDS, 0};

  if (timeout_out == NULL) {
    errno = EINVAL;
    return -1;
  }

  if (value == NULL || value[0] == '\0') {
    *timeout_out = timeout;
    return 0;
  }

  if (value[0] == '-') {
    errno = EINVAL;
    return -1;
  }

  timeout.tv_sec = 0;
  timeout.tv_nsec = 0;

  while (*cursor != '\0') {
    if (pid0_parse_duration_component(&cursor, &timeout) != 0) {
      return -1;
    }
  }

  *timeout_out = timeout;
  return 0;
}

int pid0_load_stop_timeout(struct timespec *timeout_out) {
  const char *value = getenv(PID0_STOP_TIMEOUT_ENV);

  if (pid0_parse_stop_timeout(value, timeout_out) == 0) {
    return 0;
  }

  if (value != NULL && value[0] != '\0') {
    pid0_warn_invalid_timeout(value);
  }
  timeout_out->tv_sec = PID0_DEFAULT_STOP_TIMEOUT_SECONDS;
  timeout_out->tv_nsec = 0;
  return 0;
}

int pid0_wait_for_managed_child(pid_t managed_pid, int *exit_code_out,
                                int nonblock) {
  int options = nonblock ? WNOHANG : 0;
  int reap_any_child = managed_pid < 0;

  if (exit_code_out == NULL) {
    errno = EINVAL;
    return -1;
  }

  for (;;) {
    int status = 0;
    pid_t waited = waitpid(-1, &status, options);

    if (waited == 0 && nonblock) {
      return 0;
    }
    if (waited < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno == ECHILD) {
        *exit_code_out = 0;
        return reap_any_child ? 0 : 1;
      }
      return -1;
    }
    if (!reap_any_child && waited != managed_pid) {
      if (nonblock) {
        continue;
      }
      options = 0;
      continue;
    }

    if (WIFEXITED(status)) {
      *exit_code_out = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
      *exit_code_out = 128 + WTERMSIG(status);
    } else {
      *exit_code_out = 1;
    }
    return 1;
  }
}

void pid0_drain_zombies_nonblock(void) {
  int discard = 0;

  while (pid0_wait_for_managed_child(-1, &discard, 1) == 1) {
  }
}

static int pid0_supervise(pid0_submain_fn submain, int argc, char **argv) {
  sigset_t signal_mask;
  sigset_t old_mask;
  struct timespec stop_timeout;
  struct timespec deadline = {0, 0};
  int kill_armed = 0;
  int kill_sent = 0;
  pid_t child_pid = -1;

  if (sigfillset(&signal_mask) != 0) {
    perror("pid0: sigfillset");
    return 111;
  }
  sigdelset(&signal_mask, SIGKILL);
  sigdelset(&signal_mask, SIGSTOP);

  if (sigprocmask(SIG_BLOCK, &signal_mask, &old_mask) != 0) {
    perror("pid0: sigprocmask");
    return 111;
  }

  if (pid0_load_stop_timeout(&stop_timeout) != 0) {
    sigprocmask(SIG_SETMASK, &old_mask, NULL);
    return 111;
  }

  child_pid = fork();
  if (child_pid < 0) {
    perror("pid0: fork");
    sigprocmask(SIG_SETMASK, &old_mask, NULL);
    return 111;
  }

  if (child_pid == 0) {
    if (sigprocmask(SIG_SETMASK, &old_mask, NULL) != 0) {
      perror("pid0: child sigprocmask");
      _exit(111);
    }
    if (setpgid(0, 0) != 0) {
      perror("pid0: child setpgid");
      _exit(111);
    }
    return submain(argc, argv);
  }

  if (setpgid(child_pid, child_pid) != 0 && errno != EACCES && errno != ESRCH) {
    perror("pid0: parent setpgid");
  }

  if (pid0_set_foreground_pgrp_for_stdio(child_pid) != 0) {
    perror("pid0: tcsetpgrp");
  }

  for (;;) {
    int exit_code = 0;
    int child_state = pid0_wait_for_managed_child(child_pid, &exit_code, 1);
    struct timespec wait_timeout;
    struct timespec *wait_timeout_ptr = NULL;
    siginfo_t info;
    int signum;

    if (child_state < 0) {
      perror("pid0: waitpid");
      sigprocmask(SIG_SETMASK, &old_mask, NULL);
      return 111;
    }
    if (child_state == 1) {
      struct timespec brief_delay = {0, 50 * 1000 * 1000};
      nanosleep(&brief_delay, NULL);
      pid0_drain_zombies_nonblock();
      sigprocmask(SIG_SETMASK, &old_mask, NULL);
      return exit_code;
    }

    if (kill_armed && !kill_sent) {
      if (pid0_remaining_timeout(&deadline, &wait_timeout) == 0) {
        if (kill(-child_pid, SIGKILL) != 0 && errno != ESRCH) {
          perror("pid0: kill(SIGKILL)");
        }
        kill_sent = 1;
      } else {
        wait_timeout_ptr = &wait_timeout;
      }
    }

    signum = sigtimedwait(&signal_mask, &info, wait_timeout_ptr);
    if (signum < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno == EAGAIN) {
        if (kill(-child_pid, SIGKILL) != 0 && errno != ESRCH) {
          perror("pid0: kill(SIGKILL)");
        }
        kill_sent = 1;
        continue;
      }
      perror("pid0: sigtimedwait");
      continue;
    }

    if (signum == SIGCHLD) {
      continue;
    }

    if (kill(-child_pid, signum) != 0 && errno != ESRCH) {
      perror("pid0: kill");
    }

    if (pid0_is_terminate_signal(signum) && !kill_armed) {
      struct timespec now;

      if (clock_gettime(CLOCK_MONOTONIC, &now) == 0) {
        pid0_add_timespec(&now, &stop_timeout, &deadline);
        kill_armed = 1;
      }
    }
  }
}

static void pid0_add_timespec(const struct timespec *lhs,
                              const struct timespec *rhs,
                              struct timespec *result) {
  result->tv_sec = lhs->tv_sec + rhs->tv_sec;
  result->tv_nsec = lhs->tv_nsec + rhs->tv_nsec;
  if (result->tv_nsec >= 1000L * 1000L * 1000L) {
    result->tv_sec += 1;
    result->tv_nsec -= 1000L * 1000L * 1000L;
  }
}

static int pid0_remaining_timeout(const struct timespec *deadline,
                                  struct timespec *remaining) {
  struct timespec now;

  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
    return -1;
  }
  if (deadline->tv_sec < now.tv_sec ||
      (deadline->tv_sec == now.tv_sec && deadline->tv_nsec <= now.tv_nsec)) {
    remaining->tv_sec = 0;
    remaining->tv_nsec = 0;
    return 0;
  }

  remaining->tv_sec = deadline->tv_sec - now.tv_sec;
  if (deadline->tv_nsec >= now.tv_nsec) {
    remaining->tv_nsec = deadline->tv_nsec - now.tv_nsec;
  } else {
    remaining->tv_sec -= 1;
    remaining->tv_nsec =
        (1000L * 1000L * 1000L) + deadline->tv_nsec - now.tv_nsec;
  }
  return 1;
}

static int pid0_parse_duration_component(const char **cursor,
                                         struct timespec *timeout_out) {
  char *end = NULL;
  unsigned long amount = strtoul(*cursor, &end, 10);
  unsigned long seconds = 0;

  if (end == *cursor) {
    errno = EINVAL;
    return -1;
  }
  if (*end == '\0') {
    timeout_out->tv_sec += (time_t)amount;
    *cursor = end;
    return 0;
  }

  switch (*end) {
  case 'h':
    seconds = amount * 60UL * 60UL;
    break;
  case 'm':
    seconds = amount * 60UL;
    break;
  case 's':
    seconds = amount;
    break;
  default:
    errno = EINVAL;
    return -1;
  }

  timeout_out->tv_sec += (time_t)seconds;
  *cursor = end + 1;
  return 0;
}

static void pid0_warn_invalid_timeout(const char *value) {
  fprintf(stderr, "pid0: invalid %s=%s, using default %ds\n",
          PID0_STOP_TIMEOUT_ENV, value, PID0_DEFAULT_STOP_TIMEOUT_SECONDS);
}
