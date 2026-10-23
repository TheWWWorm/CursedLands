set pagination off
thread 1
frame 0
info registers rdi rsi rip
x/3gx $rsi
x/12i $pc-25
frame 1
set $vmframe=$rbp
set $func=*(unsigned long*)($vmframe-0x1e8)
set $ip=*(int*)($vmframe-0x1e0)
set $code=*(unsigned long*)($func+0x2d8)
printf "GDScriptFunction=%#lx ip=%d\n",$func,$ip
printf "Function name (UTF-32):\n"
x/ws *(unsigned long*)(*(unsigned long*)$func+8)
printf "Script source (UTF-32):\n"
x/ws *(unsigned long*)(*(unsigned long*)($func+8)+8)
printf "Address bases: stack, constants, members\n"
x/3gx $vmframe-0xd0
printf "Instruction and operands\n"
x/3wx $code+$ip*4
bt 14
thread 2
bt 20
