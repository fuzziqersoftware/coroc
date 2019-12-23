.intel_syntax noprefix


.globl _coro_start
_coro_start:
  mov   rsi, 0x4000

.globl _coro_start_stack
_coro_start_stack:
  # the stack currently looks like this (higher addresses later):
  #   - return addr for call to coro_start <- RSP
  #   - frame data for calling frame (belonging to coroutine function)
  #   - saved rbp for call to coroutine function <- RBP
  #   - return addr for call to coroutine function
  #   - frame data for calling frame (belonging to coroutine's caller)
  #
  # after this call, there will be two stacks. the main stack should look like
  # this at the time the ret instruction for this function is reached:
  #   - return addr for call to coroutine function <- RSP
  #   - frame data for calling frame (belonging to coroutine's caller)
  #
  # the stack in the coroutine object should look like this at the time the ret
  # instruction is reached:
  #   - return addr for call to coro_start <- RSP
  #   - frame data for calling frame (belonging to coroutine function)
  #   - saved rbp for call to coroutine function <- RBP
  #   - addr of coro_return
  #   - coroutine object 

  push    rsi

  # allocate a new coroutine stack. the coroutine struct will be at the very top
  # of the stack, and the stack will grow downward beyond it. note that rsi
  # contains the stack size already
  mov     rdi, 0  # addr
  mov     rdx, 0x03  # prot = PROT_READ|PROT_WRITE
  mov     rcx, 0x1002  # flags = MAP_ANONYMOUS|MAP_PRIVATE
  mov     r8, -1  # fd
  mov     r9, 0  # offset
  call    _mmap
  pop     rsi

  # if mmap failed, return NULL
  cmp     rax, -1  # MAP_FAILED
  jne     _coro_start__mmap_ok
  xor     rax, rax
  ret

_coro_start__mmap_ok:
  # r9 = rsp from call to coro_start; switch to coroutine stack
  lea     r9, [rax + rsi]
  xchg    rsp, r9

  # set up the new coroutine object by pushing the necessary stuff
  push    0  # coro that delegated to this coro
  push    0  # coro that this coro delegated to
  push    0x01  # flags (not started)
  push    r15  # saved r15
  push    r14  # saved r14
  push    r13  # saved r13
  push    r12  # saved r12
  push    rbx  # saved rbx
  push    0  # rbp for frame from call to coro_start (will be filled in later)
  push    0  # rsp for frame from call to coro_start (will be filled in later)
  push    rsi  # stack size
  push    rax  # stack base addr
  mov     r8, rsp  # r8 = pointer to coroutine object

  # set up the caller's stack. it will have a fake return address on it that
  # will make the coroutine function return to coro_return when it returns
  lea     rdx, [rip + _coro_return]
  push    rdx

  # copy the caller's stack downward until src and (new) rsp match
  mov     rcx, rbp
_coro_start__copy_stack_frame:
  push    [rcx]
  sub     rcx, 8
  cmp     rcx, r9
  jge     _coro_start__copy_stack_frame

  # fill in the rsp and rbp for the coroutine object. correct rbp by the
  # difference between the new stack and old stack
  lea     r10, [rsp + rbp]  # r10 = old rbp + new stack (rsp) - old stack (r9)
  sub     r10, r9
  mov     [r8 + 0x10], rsp
  mov     [r8 + 0x18], r10

  # switch back to main stack and remove the last stack frame - we just moved it
  # into the coroutine object
  mov     rsp, rbp
  pop     rbp

  # return the coroutine object instead, skipping that frame entirely
  mov     rax, r8
  ret



_coro_return:
  # rdi = coroutine, rsi = 0 (for return value from coro_continue)
  mov     rdi, rsp
  xor     rsi, rsi

  # later on, we'll mark the coroutine as finished by setting saved_rsp to NULL,
  # and save the return value in the saved_rbp field. the xchg opcodes below
  # will do this appropriately
  xor     rsp, rsp
  mov     rbp, rax

  # check if it's a delegate; if it is, then we should return to from_coro
  # instead of swapping the contexts now
  mov     rcx, [rdi + 0x58]
  test    rcx, rcx
  jz      _coro_return__not_delegate

_coro_return__is_delegate:
  # if the coro is a delegate, return to from_coro instead. this means moving
  # the saved context into from_coro and returning there instead of switching
  # back to the caller (which is past the entire delegation chain). to implement
  # this, we load the context from the terminated coro, then immediately call
  # coro_continue on from_coro (so the just-restored context is saved there
  # instead). from_coro resumes from the call to coro_delegate.
  xchg    [rdi + 0x10], rsp
  xchg    [rdi + 0x18], rbp
  xchg    [rdi + 0x20], rbx
  xchg    [rdi + 0x28], r12
  xchg    [rdi + 0x30], r13
  xchg    [rdi + 0x38], r14
  xchg    [rdi + 0x40], r15

  # unlink the delegate and resume from_coro
  xor     rdx, rdx
  mov     [rdi + 0x58], rdx
  mov     [rcx + 0x50], rdx
  mov     rdi, rcx

  # the return value is the function's return value (which is still in rax)
  mov     rsi, rax

_coro_return__not_delegate:

.globl _coro_continue
_coro_continue:
  # if the coro has a delegate, continue that one instead
  mov     rdx, [rdi + 0x50]
  test    rdx, rdx
  cmovnz  rdi, rdx
  jnz     _coro_continue

  # if saved_rsp is blank, the coroutine is finished
  xchg    [rdi + 0x10], rsp
  test    rsp, rsp
  jnz     _coro_continue__coroutine_can_continue

  # return to the caller's stack and return NULL
  xchg    [rdi + 0x10], rsp
  xor     rax, rax
  ret

_coro_continue__coroutine_can_continue:
  # swap the contexts and return the second argument
  xchg    [rdi + 0x18], rbp
  xchg    [rdi + 0x20], rbx
  xchg    [rdi + 0x28], r12
  xchg    [rdi + 0x30], r13
  xchg    [rdi + 0x38], r14
  xchg    [rdi + 0x40], r15

  # mark the coroutine as started. if it wasn't started before, return the
  # pointer to the coroutine instead of the passed-in value
  xor     rax, rax
  xchg    [rdi + 0x48], rax
  test    rax, rax
  cmovnz  rsi, rdi

  # return. we don't have to do anything special here; the correct return
  # address should be next on the stack that we just swapped to
  mov     rax, rsi
  ret



.globl _coro_delegate
_coro_delegate:
  # delegation requires some state shuffling. basically we need to know 3 things
  # at any point in time:
  # 1. where we are in to_coro (or where to resume inside to_coro)
  # 2. where to return to when to_coro yields (or where we are outside coros)
  # 3. where to return to when to_coro finishes
  # we store these in the following locations when to_coro is executing:
  # 1. in the cpu registers
  # 2. in to_coro's register state
  # 3. in from_coro's register state
  # we store these in the following locations when to_coro is not executing:
  # 1. in to_coro's register state
  # 2. in the cpu registers
  # 3. in from_coro's register state

  # at call time, the various locations look like this:
  # - cpu regs: location/context in from_coro
  # - to_coro state: location/context in to_coro
  # - from_coro state: location/context outside coros
  # we need to change it to:
  # - cpu regs: location/context in to_coro
  # - to_coro state: location/context outside coros
  # - from_coro state: location/context in from_coro

  # set the delegated to/from pointers appropriately
  mov     [rdi + 0x50], rsi  # from_coro->delegated_to_coro = to_coro
  mov     [rsi + 0x58], rdi  # to_coro->delegated_from_coro = from_coro

  # get the context from from_coro (this is where to_coro should return to when
  # it yields) and save the current context to it (this is where to_coro should
  # return to when it returns, at the coro_delegate callsite)
  xchg    [rdi + 0x10], rsp
  xchg    [rdi + 0x18], rbp
  xchg    [rdi + 0x20], rbx
  xchg    [rdi + 0x28], r12
  xchg    [rdi + 0x30], r13
  xchg    [rdi + 0x38], r14
  xchg    [rdi + 0x40], r15

  # now the various locations hold:
  # - cpu regs: location/context outside coros
  # - to_coro state: location/context in to_coro
  # - from_coro state: location/context in from_coro
  # to get to the state we want, just resume to_coro as if we had called
  # coro_continue(to_coro, NULL). this will swap the contents of the first two
  # locations
  mov     rdi, rsi
  xor     rsi, rsi
  jmp     _coro_continue



.globl _coro_started
_coro_started:
  # return !coro->not_started
  mov     rax, [rdi + 0x48]
  xor     rax, 1
  ret



.globl _coro_finished
_coro_finished:
  # return 1 if there's no saved rsp (so we can't continue); else 0
  xor     rax, rax
  mov     rcx, [rdi + 0x10]
  test    rcx, rcx
  setz    al
  ret



.globl _coro_return_value
_coro_return_value:
  # if the coro is finished, the return value is stored in the rbp slot. if it's
  # not finished, the caller should already know this
  mov     rax, [rdi + 0x18]
  ret



.globl _coro_close
_coro_close:
  # if you call this from inside the coroutine, it will unmap the stack area and
  # you'll get a segfault. that's what you get for not reading the dox

  # just call munmap
  mov     rsi, [rdi + 0x08]  # stack size
  mov     rdi, [rdi + 0x00]  # stack base
  jmp     _munmap
