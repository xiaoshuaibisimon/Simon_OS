%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR

jmp     loader_start

;构建GDT
GDT_BASE:   
    dd 0x00000000
    dd 0x00000000

CODE_DESC:
    dd 0x0000FFFF
    dd DESC_CODE_H4BYTES

DATA_STACK_DESC:
    dd 0x0000FFFF
    dd DESC_DATA_H4BYTES

VIDEO_DESC:
    dd 0x80000007 ;limit = (0xbffff-0xb8000)/4KB=7（不是完全相等，根据描述符段界限和实际段界限的公式换算出来的）
                    ;实际段界限 = 描述符段界限 x 0x1000 + 0xFFF，实际段界限就是有效地址，就是偏移地址，就是范围
    dd DESC_VIDEO_H4BYTES  

DATA_STACK1_DESC:
    dd 0x00000001 ;界限是1，表示最低的4KBx2字节的空间，该段不能使用，理论上有效空间是（8KB=0x2000）--4GB（0xFFFFFFFF），但考虑到bochs虚拟机的配置，只能到32MB
    dd DESC_DATA1_H4BYTES  

GDT_SIZE    equ  $ - GDT_BASE
GDT_LIMIT   equ  GDT_SIZE - 1

    times 59 dq 0 ;预留60个段描述符
SELECTOR_CODE   equ  (0x1 << 3) + TI_GDT + RPL0  
SELECTOR_DATA   equ  (0x2 << 3) + TI_GDT + RPL0  
SELECTOR_VIDEO   equ  (0x3 << 3) + TI_GDT + RPL0  
SELECTOR_DATA1   equ  (0x4 << 3) + TI_GDT + RPL0  

;gdt指针，界限2bytes + gdt起始地址4bytes

    gdt_ptr dw GDT_LIMIT
            dd GDT_BASE

    loader_msg db 'loader in real Aha!'

loader_start:

    ;打印字符串--0x13号子功能，用的BIOS中断
    mov sp,LOADER_BASE_ADDR
    mov ax,loader_msg
    mov bp,ax   ;es:bp--字符串首地址，es和cs一致（初始化了已经）

    ;光标位置主要用到dx中的数据，cx用得少
    mov cx,19   ;cx存储字符串长度，不包括结束符
    mov ax,0x1301   ;al设置写字符的方式，01--显示字符串，光标跟着移动
    mov bx,0x001F     ;bh存储要显示的页号，第0页，bl是字符属性
    mov dx,0x1800   ;（DH,DL）=坐标（行，列）,最后一行开始
    int 0x10

;准备进入保护模式

    ;1. 打开A20地址线--不能直接操作端口里的数据--读--修改--写
    in  al,0x92
    or  al,0x02
    out 0x92,al

    ;2. 加载gdt
    lgdt [gdt_ptr]

    ;3. 将CR0的pe设置为1--不能直接操作CR0里的数据--读--修改--写
    mov eax,cr0
    or  eax,0x01
    mov cr0,eax

    ;4. 利用无条件长跳转指令清空流水线，解决指令译码错误，并重新加载CS的值，同时更新段描述符缓冲寄存器，重新解释指令格式，否则会出错
    jmp dword  SELECTOR_CODE:p_mode_start

[bits 32]
p_mode_start:
    mov ax,SELECTOR_DATA
    mov ds,ax;如果加载段选择子的时候出错，CPU会抛出异常，进一步执行异常处理程序，有可能是重新开始执行BIOS，进而死循环
    mov es,ax
    mov ss,ax

    mov esp,LOADER_STACK_TOP
    push word 0xabcd
    mov ax,SELECTOR_VIDEO
    mov gs,ax

    mov byte [gs:160],'P'

    mov ax,SELECTOR_DATA1
    mov ds,ax;如果加载段选择子的时候出错，CPU会抛出异常，进一步执行异常处理程序，有可能是重新开始执行BIOS，进而死循环
    mov es,ax
    mov ss,ax

    mov esp,0x10000;esp指向64KB的地方
    ;mov esp,0x2000;这是合法的最小栈地址--段描述符中limit部分是0x1，
                        ;所以实际的锻界限县是(0x1×0x1000 + 0XFFF=0x1FFF)，由于这里是上扩展，所以最低有效地址是实际界限加1等于0x2000
                        ;对堆栈段的保护是在进行内存读写的时候发生，单独改变esp不会进行合法性检查，只有进行内存访问的时候才检查，
                        ;在push/pop时，如果越过0x2000就会触发异常
    push word 0xCDEF

    jmp $