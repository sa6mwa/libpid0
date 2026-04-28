#include <cmocka.h>

#include <errno.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static void test_direct_mode_returns_submain_exit_code(void **state);
static void test_tty_foreground_handoff(void **state);
static void test_pid1_wrapper_returns_child_exit_code(void **state);
static void test_pid1_wrapper_forwards_sigterm(void **state);

static int run_process(char *const argv[], int *exit_code_out, pid_t *pid_out);
static int run_process_with_stderr_mode(char *const argv[], int *exit_code_out,
                                        pid_t *pid_out, int silence_stderr);
static int wait_for_process(pid_t pid, int *exit_code_out);
static int unshare_available(void);
static int run_unshare_helper(const char *mode, const char *arg,
                              int *exit_code_out, pid_t *pid_out);

int main(void) {
  const struct CMUnitTest tests[] = {
      cmocka_unit_test(test_direct_mode_returns_submain_exit_code),
      cmocka_unit_test(test_tty_foreground_handoff),
      cmocka_unit_test(test_pid1_wrapper_returns_child_exit_code),
      cmocka_unit_test(test_pid1_wrapper_forwards_sigterm),
  };

  return cmocka_run_group_tests(tests, NULL, NULL);
}

static void test_direct_mode_returns_submain_exit_code(void **state) {
  int exit_code = 0;
  char *const argv[] = {PID0_TEST_HELPER_PATH, "direct-exit", "42", NULL};
  (void)state;

  assert_int_equal(run_process(argv, &exit_code, NULL), 0);
  assert_int_equal(exit_code, 42);
}

static void test_tty_foreground_handoff(void **state) {
  int exit_code = 0;
  char *const argv[] = {PID0_TEST_HELPER_PATH, "tty-foreground", NULL};
  (void)state;

  assert_int_equal(run_process(argv, &exit_code, NULL), 0);
  assert_int_equal(exit_code, 0);
}

static void test_pid1_wrapper_returns_child_exit_code(void **state) {
  int exit_code = 0;
  (void)state;

  if (!unshare_available()) {
    skip();
  }

  assert_int_equal(
      run_unshare_helper("assert-not-pid1", "24", &exit_code, NULL), 0);
  assert_int_equal(exit_code, 24);
}

static void test_pid1_wrapper_forwards_sigterm(void **state) {
  int exit_code = 0;
  pid_t pid = -1;
  struct timespec delay = {0, 150 * 1000 * 1000};
  (void)state;

  if (!unshare_available()) {
    skip();
  }

  assert_int_equal(run_unshare_helper("signal-wait", NULL, &exit_code, &pid),
                   0);

  nanosleep(&delay, NULL);

  assert_int_equal(kill(pid, SIGTERM), 0);
  assert_int_equal(wait_for_process(pid, &exit_code), 0);
  assert_int_equal(exit_code, 128 + SIGTERM);
}

static int run_process(char *const argv[], int *exit_code_out, pid_t *pid_out) {
  return run_process_with_stderr_mode(argv, exit_code_out, pid_out, 0);
}

static int run_process_with_stderr_mode(char *const argv[], int *exit_code_out,
                                        pid_t *pid_out, int silence_stderr) {
  pid_t pid = fork();

  if (pid < 0) {
    return -1;
  }
  if (pid == 0) {
    FILE *null_stream;

    if (silence_stderr) {
      null_stream = freopen("/dev/null", "w", stderr);
      if (null_stream == NULL) {
        _exit(127);
      }
    }
    execv(argv[0], argv);
    _exit(127);
  }
  if (pid_out != NULL) {
    *pid_out = pid;
    return 0;
  }
  return wait_for_process(pid, exit_code_out);
}

static int wait_for_process(pid_t pid, int *exit_code_out) {
  int status = 0;

  for (;;) {
    if (waitpid(pid, &status, 0) >= 0) {
      break;
    }
    if (errno != EINTR) {
      return -1;
    }
  }

  if (WIFEXITED(status)) {
    *exit_code_out = WEXITSTATUS(status);
    return 0;
  }
  if (WIFSIGNALED(status)) {
    *exit_code_out = 128 + WTERMSIG(status);
    return 0;
  }
  *exit_code_out = 1;
  return 0;
}

static int unshare_available(void) {
  static int cached = -1;
  int exit_code = 0;
  char *const argv[] = {
      "/usr/bin/env",        "unshare",         "-Urpf", "--mount-proc",
      PID0_TEST_HELPER_PATH, "assert-not-pid1", "19",    NULL};

  if (access("/usr/bin/env", X_OK) != 0) {
    return 0;
  }
  if (cached >= 0) {
    return cached == 1;
  }
  if (run_process_with_stderr_mode(argv, &exit_code, NULL, 1) != 0) {
    cached = 0;
    return 0;
  }
  cached = exit_code == 19 ? 1 : 0;
  return cached == 1;
}

static int run_unshare_helper(const char *mode, const char *arg,
                              int *exit_code_out, pid_t *pid_out) {
  char *argv[] = {"/usr/bin/env",
                  "unshare",
                  "-Urpf",
                  "--mount-proc",
                  (char *)PID0_TEST_HELPER_PATH,
                  NULL,
                  NULL,
                  NULL};

  argv[5] = (char *)mode;
  argv[6] = (char *)arg;
  if (arg == NULL) {
    argv[6] = NULL;
  }
  return run_process(argv, exit_code_out, pid_out);
}
