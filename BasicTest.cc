#include <assert.h>
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
  return (struct coro_t*)(last_num - first_num);
}


struct coro_t* coro2(int64_t first_num, int64_t last_num, int64_t times) {
  struct coro_t* coro = coro_start();
  assert(coro_started(coro));
  assert(!coro_finished(coro));

  int64_t sum = 0;
  for (; times; times--) {
    struct coro_t* subcoro = coro1(first_num, last_num);
    assert(!coro_started(subcoro));
    assert(!coro_finished(subcoro));

    sum += (int64_t)coro_delegate(coro, subcoro);
    assert(coro_started(subcoro));
    assert(coro_finished(subcoro));
    coro_close(subcoro);
  }

  assert(coro_started(coro));
  assert(!coro_finished(coro));
  return (struct coro_t*)sum;
}


struct coro_t* coro3(int64_t first_num, int64_t last_num, int64_t times) {
  struct coro_t* coro = coro_start();
  assert(coro_started(coro));
  assert(!coro_finished(coro));

  struct coro_t* subcoro = coro2(first_num, last_num, times);
  assert(!coro_started(subcoro));
  assert(!coro_finished(subcoro));

  void* ret = coro_delegate(coro, subcoro);
  assert(coro_started(subcoro));
  assert(coro_finished(subcoro));
  coro_close(subcoro);

  assert(coro_started(coro));
  assert(!coro_finished(coro));
  return (struct coro_t*)ret;
}


void check_coro(struct coro_t* coro, int64_t min_x, int64_t max_x, int64_t times) {

  assert(!coro_started(coro));
  assert(!coro_finished(coro));

  for (int64_t t = 0; t < times; t++) {
    int64_t x = 0;
    int64_t expected_x = min_x;
    while ((x = (int64_t)coro_continue(coro, (void*)x))) {
      assert(x == expected_x);
      assert(coro_started(coro));
      assert(!coro_finished(coro));
      expected_x++;
      if (expected_x > max_x) {
        expected_x = min_x;
      }
    }
    assert(x == 0);
    assert(expected_x == min_x);
  }

  assert(coro_started(coro));
  assert(coro_finished(coro));
  assert(coro_return_value(coro) == (void*)((max_x - min_x) * times));

  coro_close(coro);
}


int main(int argc, char* argv[]) {
  int64_t min_x = 5, max_x = 15, times = 3;

  {
    fprintf(stderr, "-- basic coro\n");
    struct coro_t* coro = coro1(min_x, max_x);
    check_coro(coro, min_x, max_x, 1);
  }

  {
    fprintf(stderr, "-- delegated coro\n");
    struct coro_t* coro = coro2(min_x, max_x, times);
    check_coro(coro, min_x, max_x, times);
  }

  {
    fprintf(stderr, "-- multiple delegation\n");
    struct coro_t* coro = coro3(min_x, max_x, times);
    check_coro(coro, min_x, max_x, times);
  }

  fprintf(stderr, "-- all tests passed\n");
  return 0;
}
