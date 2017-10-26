# coroc

coroc is a C library for writing coroutines.

### Why?

Because I felt like it. Philosophical arguments can be made about whether coroutines "belong" in C or not, and this library doesn't attempt to answer that question. This is just a proof of concept.

## Building

- Build the library and test it by running `make`.
- Run `sudo make install`.

## Usage

Call a coroutine like this:

    struct coro_t* coro = coroutine_function();

    // have to pass NULL the first time (the value is ignored)
    void* yielded_value = coro_continue(coro, NULL);
    yielded_value = coro_continue(coro, value);

    ...

    // when the coroutine function returns, future coro_continue() calls will
    // return NULL immediately, and coro_finished() will return 1. when the
    // coroutine is finished, close it:
    coro_close(coro);

Write a coroutine like this (it can take any arguments, but must return a struct coro_t*):

    struct coro_t* coroutine_function(int arg, const char* arg2) {
      struct coro_t* coro = coro_start();

      // just an example. you might have different control flow surrounding your
      // coro_continue calls
      void* value;
      while (value = coro_continue(coro, NULL)) {
        ...
      }

      return NULL; // the caller can get this value with coro_return_value()
    }

Coroutines can also delegate to each other (this is similar to Python's `yield from`):

    struct coro_t* coroutine_function(int arg, const char* arg2) {
      struct coro_t* coro = coro_start();

      struct coro_t* subcoro = other_coroutine_function();
      void* return_value = coro_delegate(coro, subcoro);
      coro_close(subcoro);

      ...
    }

There are also a few functions that you can use to examine the state of a coroutine (whether it has started, whether it has finished, what its return value was). See coroc.h for descriptions of all the relevant functions.
