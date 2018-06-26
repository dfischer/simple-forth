  .macro fw word:req, rest:vararg
    .4byte \word /* FWSIZE */
    .ifnb \rest ; fw \rest ; .endif
  .endm

    next_inst .req r11
    rsp .req r12

  forth_interpreter:
    str next_inst, [rsp, #-4]!
    mov next_inst, r0
    /* b next */

  next:
    /**
    mov r0, #'t' ; bl uart_putc ; mov r0, #'o' ; bl uart_putc ; mov r0, #'p' ; bl uart_putc ; mov r0, #':' ; bl uart_putc ; mov r0, #' ' ; bl uart_putc
    ldr r0, [sp] ; bl puthex
    mov r0, next_inst
    bl puthex
    /**/
    ldr r0, [next_inst], #4 /* FWSIZE */
    /**
    bl puthex
    push {r0-r1} ; mov r0, #'\n' ; bl uart_putc ; pop {r0-r1}
    /**/
    ldr r1, [r0], #4 /* FWSIZE */
    bx r1

  exit:
    ldr next_inst, [rsp], #4
    b next

  tohex:
    cmp r0, #10
    addge r0, #'A'-10
    addlt r0, #'0'
    bx lr

  puthex:
    push {r0-r4,lr}
    ror r2, r0, #28 /* 01 23 45 67 */
    mov r0, #'0' ; bl uart_putc
    mov r0, #'x' ; bl uart_putc
    mov r3, #15
    mov r4, #8
  puthex_loop:
    and r0, r2, r3 ; bl tohex ; bl uart_putc
    ror r2, #28
    subs r4, #1
    bne puthex_loop
  puthex_end:
    mov r0, #'\n' ; bl uart_putc
    pop {r0-r4,pc}

  .set previous_entry, 0
  .macro entry name:req, label, imm=0, hid=0
  .balign 4 /* Align to power of 2 */
  1:fw previous_entry ; .set previous_entry, 1b
  .byte \hid, \imm ; .balign 4
  fw 2f-3f ; 3:.ascii "\name" ; 2: .byte 0
  .balign 4 /* Align to power of 2 */
  fw 1b
  .ifc _,\label
  .globl \name ; \name :
  .else
  .globl \label ; \label :
  .endif
  .endm

  entry "EXIT", EXIT
    fw exit

  .macro inst i, insts:vararg
    \i
    .ifnb \insts ; inst \insts ; .endif
  .endm
  .macro fasm name:req, label, pop, push, i:vararg
    entry \name, \label
    fw 1f
  1: .ifnc _,\pop ; pop {\pop} ; .endif
    inst \i
    .ifnc _,\push ; push {\push} ; .endif
    b next
  .endm

  .macro binops name:req, label, op:req, rest:vararg
    fasm \name, \label, r0-r1, r1, "\op r1, r0"
    .ifnb \rest ; binops \rest ; .endif
  .endm
  .macro binrels name:req, label, rel:req, rest:vararg
    fasm \name, \label, r0-r1, r0, "cmp r1, r0", "mov r0, #0", "mov\rel r0, #-1"
    .ifnb \rest ; binrels \rest ; .endif
  .endm

  binops "+", ADD, add,   "-", SUB, sub,   "*", STAR, mul
  binops "LSHIFT", _, lsl,   "RSHIFT", _, lsr
  binops "&", AND, and,   "|", OR, orr,    "XOR", _, eor

  binrels "<>", NOT_EQUAL, ne,    "U<", U_LESS_THAN, lo
  binrels "\x3d", EQUAL, eq,    "U>", U_GREATER_THAN, hi
  binrels "<", LESS_THAN, lt,    ">", GREATER_THAN, gt

  fasm "NEGATE", _, r0, r0, "rsb r0, #0"
  fasm "INVERT", _, r0, r0, "mvn r0, r0"
  fasm "C\x64", C_FETCH, r0, r0, "ldrB r0, [r0]"
  fasm "\x64", FETCH, r0, r0, "ldr r0, [r0]" /* FWSIZE */
  fasm "C!", C_STORE, r0-r1, _, "strB r1, [r0]"
  fasm "!", STORE, r0-r1, _, "str r1, [r0]" /* FWSIZE */

  fasm "BRANCH", _, _, _, "ldr r0, [next_inst]", "add next_inst, r0" /* FWSIZE */
  fasm "0BRANCH", ZBRANCH, r1, _, "ldr r0, [next_inst]", "cmp r1, #0", "addeq next_inst, r0", "addne next_inst, #4" /* FWSIZE */
  fasm "[']", LIT, _, r0, "ldr r0, [next_inst], #4" /* FWSIZE */

  fasm "CELL-SIZE", CELL_SIZE, _, r0, "mov r0, #4" /* CELLSIZE */
  fasm "CHAR-SIZE", CHAR_SIZE, _, r0, "mov r0, #1" /* CHARSIZE */

  fasm "NIP", _, r0-r1, r0
  fasm "DROP", _, _, _, "add sp, #4" /* CELLSIZE */
  fasm "DUP", _, _, r0, "ldr r0, [sp]"
  fasm "OVER", _, _, r0, "ldr r0, [sp, #4]" /* CELLSIZE */
  fasm "PICK", _, r0, r0, "ldr r0, [sp, r0, LSL #2]" /* CELLSIZE */
  fasm "ROT", _, r0-r2, r2, "push {r0-r1}"
  fasm "SWAP", _, r0-r1, r1,"push {r0}"

  fasm "R\x64", R_FETCH, _, r0, "ldr r0, [rsp]" /* FWSIZE */
  fasm "R>", R_FROM, _, r0, "ldr r0, [rsp], #4" /* FWSIZE */
  fasm ">R", TO_R, r0, _, "str r0, [rsp, #-4]!" /* FWSIZE */
  fasm "DEPTH", _, _, r0, "rsb r0, sp, #0x8000", "lsr r0, #2" /* FWSIZE */

  /* HERE_VAR */
  /* LATEST */
  /* STATE */

fasm "HCF", _, _, _, "1: b 1b"
fasm "TOP", _, _, _, "ldr r0, [sp]", "bl puthex"

  fasm "KEY", _, _, r0, "bl uart_getc", "bl uart_putc"

  fasm "EMIT", _, r0, _, "bl uart_putc"

  fasm "HEX.", HEX_PRINT, r0, _, "bl puthex"
  fasm "HEXAMINE", _, _, _, "ldr r0, [sp]", "bl puthex", "ldr r0, [sp, #4]", "bl puthex", "ldr r0, [sp, #8]", "bl puthex"
  fasm "HEXRTSTK", _, _, _, "ldr r0, [rsp]", "bl puthex", "ldr r0, [rsp, #4]", "bl puthex", "ldr r0, [rsp, #8]", "bl puthex"

  entry "EXECUTE", EXECUTE
    fw 1f
  1:pop {r0}
    ldr r1, [r0], #4 /* FWSIZE */
    bx r1