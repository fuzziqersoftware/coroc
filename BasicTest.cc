#include <assert.h>
#include <inttypes.h>
#include <stdio.h>

#include "coroc.h"


struct coro_t* coro1(int64_t first_num, int64_t last_num) {
  struct coro_t* coro = coro_start();
  assert(coro_started(coro));
  assert(!coro_finished(coro));

  int64_t x;
  for (x = first_num; x <= last_num; x++) {
    int64_t sent_x = (int64_t)coro_continue(coro, (void*)x);
    assert(sent_x == x);
    assert(coro_started(coro));
    assert(!coro_finished(coro));
  }

  assert(coro_started(coro));
  assert(!coro_finished(coro));
  return NULL;
}


int main(int argc, char* argv[]) {
  int64_t min_x = 5, max_x = 10;
  struct coro_t* coro = coro1(min_x, max_x);

  assert(!coro_started(coro));
  assert(!coro_finished(coro));

  int64_t x = 0;
  int64_t expected_x = 5;
  while ((x = (int64_t)coro_continue(coro, (void*)x))) {
    assert(x == expected_x);
    assert(coro_started(coro));
    assert(!coro_finished(coro));
    expected_x++;
  }
  assert(x == 0);
  assert(coro_started(coro));
  assert(coro_finished(coro));

  coro_close(coro);

  assert(expected_x == max_x + 1);
  return 0;
}
