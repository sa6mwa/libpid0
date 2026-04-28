#ifndef PID0_INTERNAL_H
#define PID0_INTERNAL_H

#include <sys/types.h>
#include <time.h>

#define PID0_STOP_TIMEOUT_ENV "PID0_STOP_TIMEOUT"
#define PID0_DEFAULT_STOP_TIMEOUT_SECONDS 30

int pid0_is_terminal_fd(int fd);
int pid0_set_foreground_pgrp_for_stdio(pid_t pgid);
int pid0_is_terminate_signal(int signum);
int pid0_parse_stop_timeout(const char *value, struct timespec *timeout_out);
int pid0_load_stop_timeout(struct timespec *timeout_out);
int pid0_wait_for_managed_child(pid_t managed_pid, int *exit_code_out,
                                int nonblock);
void pid0_drain_zombies_nonblock(void);

#endif
