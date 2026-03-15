#ifndef PID0_PID0_H
#define PID0_PID0_H

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*pid0_submain_fn)(int argc, char **argv);

/*
 * Run the supplied submain directly unless the current process is PID 1.
 * When running as PID 1, pid0 forks a managed child, forwards signals to the
 * child's process group, reaps adopted children, and exits with the child's
 * status.
 */
int pid0_run(pid0_submain_fn submain, int argc, char **argv);

#ifdef __cplusplus
}
#endif

#endif
