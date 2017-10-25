#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif


/**
 * C implementation of coroutines.
 *
 * This implementation works in an AMD64 environment with the System V calling
 * convention (e.g. on Linux and Mac OS X).
 *
 * To use it, define a coroutine function, call it, and call coro_continue until
 * it returns NULL. The coroutine function can take any arguments, and must
 * return a pointer to a struct coro_t. THe coroutine function should call
 * coro_start() before it does anything significant (e.g. calls malloc()). At
 * this point, a coroutine object will be created, and control will return to
 * the coroutine's caller. The caller can call coro_continue(coro, NULL) to
 * start the coroutine, which will execute until it calls coro_continue, at
 * which point control will return to the caller. Any value passed into
 * coro_continue will be returned in the other context; in this way,
 * coro_continue implements both the equivalents of yield and send functionality
 * in e.g. Python.
 *
 * Generally, coroutine functions will follow this pattern:
 * - Call coro_start before doing any significant work.
 * - Call coro_continue multiple times.
 * - Return NULL.
 *
 * Generally, coroutine callers will follow this pattern:
 * - Call the coroutine function.
 * - Call coro_continue on it multiple times until it returns NULL and
 *   coro_finished returns 1.
 * - Call coro_close on it.
 */



struct coro_t {
  int64_t stack_base;
  int64_t stack_size;
  int64_t saved_rsp; // NULL if the coroutine is completed (can't be resumed)
  int64_t saved_rbp;
  int64_t saved_rbx;
  int64_t saved_r12;
  int64_t saved_r13;
  int64_t saved_r14;
  int64_t saved_r15;
  int64_t not_started; // initially 1; set to 0 after first coro_continue call
};




/* coro_start: convert the current stack frame into a coroutine and return it to
 *   the caller.
 *
 * This function should be called in the coroutine function only. The coroutine
 * object is returned into both the coroutine and the caller's stack frame. The
 * coroutine's stack frame is moved into the coroutine object and the coroutine
 * is suspended; execution resumes from the coroutine callsite instead.
 */
struct coro_t* coro_start();

/* coro_continue: yield a value from or send a value into a coroutine
 *
 * When called within a coroutine, this function yields a value to the caller.
 * When called outside a coroutine, this function sends a value into the
 * coroutine. This function swaps execution contexts - if called from outside a
 * coroutine, the coroutine resumes; if called from inside a coroutine, the
 * coroutine is suspended.
 *
 * When called for the first time on a coroutine, the argument is ignored, since
 * the coroutine is suspended at the coro_start call instead of a coro_continue
 * call.
 *
 * If the coroutine has already returned, coro_continue returns NULL
 * immediately. When NULL is returned, you can call coro_finished to determine
 * whether the coroutine has returned or yielded NULL.
 */
void* coro_continue(struct coro_t*, void*);

/* coro_started: returns 1 if coro_continue has ever been called on a coroutine.
 */
int coro_started(struct coro_t*);

/* coro_finished: returns 1 if the coroutine function has returned.
 */
int coro_finished(struct coro_t*);

/* coro_close: destroy a coroutine, canceling it if necessary
 *
 * This function must not be called in the coroutine that's being closed. To
 * cancel a coroutine early from within the coroutine, just return normally.
 * When coro_close is called on an unfinished coroutine (for which coro_finished
 * does not return 1), no cleanup is performed; any pending destructors or
 * allocated memory in the coroutine will not be cleaned up.
 *
 * The return value has the same meaning as for munmap().
 */
int coro_close(struct coro_t*);

#ifdef __cplusplus
} // extern "C"
#endif
