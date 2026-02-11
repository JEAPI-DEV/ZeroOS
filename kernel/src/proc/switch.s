.global switchContext
.type switchContext, @function

# void switchContext(Context* old, Context* new);
# old: %rdi, new: %rsi
switchContext:
    # Save old context
    push %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rsp, (%rdi)

    # Restore new context
    mov (%rsi), %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret

# entry: %rbx, arg: %r12, exit: %r13
.global thread_entry_stub
thread_entry_stub:
    sti             # Enable interrupts for new threads
    mov %r12, %rdi  # Move arg to 1st argument register
    call *%rbx      # Call thread function
    call *%r13      # Call thread exit
    hlt             # Should never be reached
