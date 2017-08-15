%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR

;优化跳转过程，不用接着执行两次jmp
;jmp     loader_start

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


;存储内存容量--偏移地址64x8=0x200

    total_mem_size dd 0 ;4字节--物理地址是0x900+0x200=0xb00
;gdt指针，界限2bytes + gdt起始地址4bytes

    gdt_ptr dw GDT_LIMIT
            dd GDT_BASE ;6字节

;   取消掉实模式下的打印功能
;    loader_msg db 'loader in real Aha!'

; int 0x15的0xe820子功能返回的结果缓冲区，先取为224字节，每一个结果是20字节，为了让loader的有效指令的起始地址loader_start是整数，凑的整数，不必强求
    ards_buf    times 244 db 0 ;244字节
    ards_cnt    dw 0 ;2字节

    ;文件开头至此都是数据，一共是（5+59）x8 + 4 + 6 + 244 + 2 = 0x300

;此处距离文件开头/起始虚拟地址的偏移量就是0x300
loader_start:

;获取内存:int ox15;eax=0x0000E820;edx=0x534D4150
;eax--子功能号
;ebx--ARDS后续值，第一次必须为0，后面由BIOS自动更新--毕竟使用的是BIOS中断获取内存大小
;ecx--ARDS结构体大小，指示BIOS写入的字节数
;edx--固定签名SMAP的ASCII码，指定以后不用修改
;es:di--ARDS目标缓冲区起始地址


    xor ebx,ebx         ;第一次必须清0，后面不用管
    mov edx,0x534D4150  ;固定签名
    mov di,ards_buf     ;指定目标缓冲区
.e820_mem_get_loop:     
    mov eax,0x0000E820  ;指定子功能号
    mov ecx,20          ;指定子功能号

    int 0x15            ;调用内存获取中断
    jc  .e820_failed_e801   ;如果CF为1表示错误发生，尝试第二种获取方式

    add di,cx           ;更新目标缓冲区
    inc word [ards_cnt]  ;增加获取到的ards个数
    cmp ebx,0           ;判断是否全部获取结束
    jnz .e820_mem_get_loop  ;（ebx为0且cf为0的时候表示真的获取结束）

;在所有ards结构中，找出（base_add_low + length_low）的最大值，即内存容量
    mov cx,[ards_cnt] ;循环次数--获取到的结构体数
    mov ebx,ards_buf ;数组起始地址
    xor edx,edx      ;edx是三种获取方式存储结果内存的存储器，先清零
.find_max_mem:
    mov eax,[ebx]
    add eax,[ebx+8] ;计算base_add_low + length_low
    add ebx,20      ;指向下一个结构体
    cmp edx,eax     ;比较当前最大值和临时值
    jge .next_ards
    mov edx,eax     ;如果当前最大值比临时值小，需要更新最大值
.next_ards:
    loop .find_max_mem ;进行下一个ards结构体的判断

    jmp .mem_get_ok

;最大支持4GB的空间，用E801获取内存
;返回后ax和cx是低15MB，bx和dx是16MB到4GB
.e820_failed_e801:
    mov ax,0xE801
    int 0x15                ;进入中断
    jc .e801_failed_0x88    ;错误检查

    ;计算出低16MB的内存，转换单位，因为之前是KB为单位
    mov cx,0x400            ;单位是1KB
    mul cx                  ;得到实际字节数
    shl edx,16              ;结果的高16位
    and eax,0x0000FFFF      ;结果的低16位
    or edx,eax              ;结果组合
    add edx,0x100000        ;还要加上系统保留的1MB
    mov esi,edx             ;备份低地址空间的大小到esi

    ;将高地址的内存转换为字节为单位，之前是64KB为单位
    xor eax,eax             ;清零
    mov ax,bx               ;得到高地址空间的大小
    mov ecx,0x10000         ;单位64KB
    mul ecx                 ;单位转换--实际字节数
    add esi,eax             ;由于最多4GB，所以用低32位eax即可

    ;统一吧内存结果放到edx中
    mov edx,esi            
    jmp .mem_get_ok

;第三种获取方式，只能获取64MB大小，子功能号c存放到ah是0x88，返回的单位是KB,存放到ax
.e801_failed_0x88:
    mov ah,0x88 ;子功能号
    int 0x15    ;进入中断
    jc  .error_halt ;死机

    and eax,0x0000FFFF ;将结果扩展为32bits

    mov cx,0x400    
    mul cx      ;转换单位为字节
    shl edx,16  
    or  edx,eax ;结果组合成32为大小
    add edx,0x100000    ;加上系统保留的低1MB

.mem_get_ok:
    mov [total_mem_size],edx
    jmp .protect_mode_on
.error_halt:
    jmp $
;取消掉实模式下的打印功能
;-------------------------------------------------------------------------------
    ;打印字符串--0x13号子功能，用的BIOS中断
    ;mov sp,LOADER_BASE_ADDR
    ;mov ax,loader_msg
    ;mov bp,ax   ;es:bp--字符串首地址，es和cs一致（初始化了已经）

    ;光标位置主要用到dx中的数据，cx用得少
    ;mov cx,19   ;cx存储字符串长度，不包括结束符
    ;mov ax,0x1301   ;al设置写字符的方式，01--显示字符串，光标跟着移动
    ;mov bx,0x001F     ;bh存储要显示的页号，第0页，bl是字符属性
    ;mov dx,0x1800   ;（DH,DL）=坐标（行，列）,最后一行开始
    ;int 0x10

;-------------------------------------------------------------------------------

;准备进入保护模式
.protect_mode_on:
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
