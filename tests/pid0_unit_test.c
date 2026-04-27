#ifdef PID0_SINGLE_HEADER_TEST
#define PID0_IMPLEMENTATION 1
#include "libpid0_single_header.h"
#else
#include "pid0_internal.h"
#endif

#include <cmocka.h>

#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static void test_parse_stop_timeout_defaults(void **state);
static void test_parse_stop_timeout_accepts_units(void **state);
static void test_parse_stop_timeout_rejects_invalid_values(void **state);
static void test_is_terminate_signal(void **state);
static void test_wait_for_managed_child_reaps_other_children(void **state);
static void test_drain_zombies_nonblock(void **state);

int main(void) {
  const struct CMUnitTest tests[] = {
      cmocka_unit_test(test_parse_stop_timeout_defaults),
      cmocka_unit_test(test_parse_stop_timeout_accepts_units),
      cmocka_unit_test(test_parse_stop_timeout_rejects_invalid_values),
      cmocka_unit_test(test_is_terminate_signal),
      cmocka_unit_test(test_wait_for_managed_child_reaps_other_children),
      cmocka_unit_test(test_drain_zombies_nonblock),
  };

  return cmocka_run_group_tests(tests, NULL, NULL);
}

static void test_parse_stop_timeout_defaults(void **state) {
  struct timespec timeout;
  (void)state;

  assert_int_equal(pid0_parse_stop_timeout(NULL, &timeout), 0);
  assert_int_equal(timeout.tv_sec, PID0_DEFAULT_STOP_TIMEOUT_SECONDS);
  assert_int_equal(timeout.tv_nsec, 0);

  assert_int_equal(pid0_parse_stop_timeout("", &timeout), 0);
  assert_int_equal(timeout.tv_sec, PID0_DEFAULT_STOP_TIMEOUT_SECONDS);
}

static void test_parse_stop_timeout_accepts_units(void **state) {
  struct timespec timeout;
  (void)state;

  assert_int_equal(pid0_parse_stop_timeout("12", &timeout), 0);
  assert_int_equal(timeout.tv_sec, 12);

  assert_int_equal(pid0_parse_stop_timeout("1m15s", &timeout), 0);
  assert_int_equal(timeout.tv_sec, 75);

  assert_int_equal(pid0_parse_stop_timeout("2h3m4s", &timeout), 0);
  assert_int_equal(timeout.tv_sec, 2 * 3600 + 3 * 60 + 4);
}

static void test_parse_stop_timeout_rejects_invalid_values(void **state) {
  struct timespec timeout;
  (void)state;

  errno = 0;
  assert_int_equal(pid0_parse_stop_timeout("-1s", &timeout), -1);
  assert_int_equal(errno, EINVAL);

  errno = 0;
  assert_int_equal(pid0_parse_stop_timeout("5x", &timeout), -1);
  assert_int_equal(errno, EINVAL);
}

static void test_is_terminate_signal(void **state) {
  (void)state;

  assert_true(pid0_is_terminate_signal(SIGTERM));
  assert_true(pid0_is_terminate_signal(SIGINT));
  assert_true(pid0_is_terminate_signal(SIGQUIT));
  assert_true(pid0_is_terminate_signal(SIGHUP));
  assert_false(pid0_is_terminate_signal(SIGUSR1));
}

static void test_wait_for_managed_child_reaps_other_children(void **state) {
  int exit_code = -1;
  int status = 0;
  pid_t extra_pid;
  pid_t managed_pid;
  (void)state;

  extra_pid = fork();
  assert_true(extra_pid >= 0);
  if (extra_pid == 0) {
    _exit(0);
  }

  managed_pid = fork();
  assert_true(managed_pid >= 0);
  if (managed_pid == 0) {
    struct timespec delay = {0, 100 * 1000 * 1000};
    nanosleep(&delay, NULL);
    _exit(7);
  }

  assert_int_equal(pid0_wait_for_managed_child(managed_pid, &exit_code, false),
                   1);
  assert_int_equal(exit_code, 7);

  errno = 0;
  assert_int_equal(waitpid(extra_pid, &status, WNOHANG), -1);
  assert_int_equal(errno, ECHILD);
}

static void test_drain_zombies_nonblock(void **state) {
  int status = 0;
  pid_t pid;
  (void)state;

  pid = fork();
  assert_true(pid >= 0);
  if (pid == 0) {
    _exit(0);
  }

  struct timespec delay = {0, 50 * 1000 * 1000};
  nanosleep(&delay, NULL);
  pid0_drain_zombies_nonblock();

  errno = 0;
  assert_int_equal(waitpid(pid, &status, WNOHANG), -1);
  assert_int_equal(errno, ECHILD);
}
