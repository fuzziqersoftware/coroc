.intel_syntax noprefix


.globl _coro_start
_coro_start:

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

  # allocate a new coroutine stack. the coroutine struct will be at the very top
  # of the stack, and the stack will grow downward beyond it.
  mov rdi, 0  # addr
  mov rsi, 0x1000  # size
  mov rdx, 0x03  # prot = PROT_READ|PROT_WRITE
  mov rcx, 0x1002  # flags = MAP_ANONYMOUS|MAP_PRIVATE
  mov r8, -1  # fd
  mov r9, 0  # offset
  sub rsp, 8  # 16-byte alignment
  call _mmap
  add rsp, 8

  # if mmap failed, return NULL
  cmp rax, -1  # MAP_FAILED
  jne 0f  # _coro_start__mmap_ok
  xor rax, rax
  ret

0: _coro_start__mmap_ok:
  # r9 = rsp from call to coro_start; switch to coroutine stack
  lea r9, [rax + 0x1000]
  xchg rsp, r9

  # set up the new coroutine object by pushing the necessary stuff
  push 0x01  # flags (not started)
  push r15  # saved r15
  push r14  # saved r14
  push r13  # saved r13
  push r12  # saved r12
  push rbx  # saved rbx
  push 0  # rbp for frame from call to coro_start (will be filled in later)
  push 0  # rsp for frame from call to coro_start (will be filled in later)
  push 0x1000  # stack size
  push rax  # stack base addr
  mov r8, rsp  # r8 = pointer to coroutine object

  # set up the caller's stack. it will have a fake return address on it that
  # will make the coroutine function "return" to coro_close when it returns
  lea rdx, [rip + _coro_return]
  push rdx

  # copy the caller's stack downward until src and (new) rsp match
  mov rcx, rbp
1: _coro_start__copy_stack_frame:
  push [rcx]
  sub rcx, 8
  cmp rcx, r9
  jge 1b # _coro_start__copy_stack_frame

  # fill in the rsp and rbp for the coroutine object. correct rbp by the
  # difference between the new stack and old stack
  lea r10, [rsp + rbp]  # r10 = old rbp + new stack (rsp) - old stack (r9)
  sub r10, r9
  mov [r8 + 0x10], rsp
  mov [r8 + 0x18], r10

  # switch back to main stack and remove the last stack frame - we just moved it
  # into the coroutine object
  mov rsp, rbp
  pop rbp

  # return the coroutine object instead, skipping that frame entirely
  mov rax, r8
  ret



_coro_return:
  # when we reach here, the coroutine object is directly on the stack
  mov rdi, rsp
  xor rsi, rsi  # returns NULL to the caller

  # mark the coroutine as exhausted by setting saved_rsp to NULL
  xor rsp, rsp

.globl _coro_continue
_coro_continue:
  # if saved_rsp is blank, the coroutine is exhausted
  xchg [rdi + 0x10], rsp
  test rsp, rsp
  jnz 3f  # _coro_continue__coroutine_can_continue

  # return to the caller's stack and return NULL
  xchg [rdi + 0x10], rsp
  xor rax, rax
  ret

3: _coro_continue__coroutine_can_continue:
  # swap the contexts and return the second argument
  xchg [rdi + 0x18], rbp
  xchg [rdi + 0x20], rbx
  xchg [rdi + 0x28], r12
  xchg [rdi + 0x30], r13
  xchg [rdi + 0x38], r14
  xchg [rdi + 0x40], r15

  # mark the coroutine as started. if it wasn't started before, return the
  # pointer to the coroutine instead of the passed-in value
  xor rax, rax
  xchg [rdi + 0x48], rax
  test rax, rax
  cmovnz rsi, rdi

  # return. we don't have to do anything special here; the correct return
  # address should be next on the stack that we just swapped to
  mov rax, rsi
  ret



.globl _coro_started
_coro_started:
  # return !coro->not_started
  mov rax, [rdi + 0x48]
  xor rax, 1
  ret



.globl _coro_finished
_coro_finished:
  # return 1 if there's no saved rsp (so we can't continue); else 0
  xor rax, rax
  mov rcx, [rdi + 0x10]
  test rcx, rcx
  setz al
  ret



.globl _coro_close
_coro_close:
  # if you call this from inside the coroutine, it will unmap the stack area and
  # you'll get a segfault. that's what you get for not reading the dox

  # just call munmap
  mov rsi, [rdi + 0x08]  # stack size
  mov rdi, [rdi + 0x00]  # stack base
  jmp _munmap
