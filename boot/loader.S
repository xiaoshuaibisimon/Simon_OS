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
    hlt
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


;=============================================================================================================
;只是为了测试向下扩展时，堆栈的入栈顺序和字节存储方向，对OS并没有实际意义，忽略该段代码吧
    mov ax,SELECTOR_DATA1
    mov ds,ax;如果加载段选择子的时候出错，CPU会抛出异常，进一步执行异常处理程序，有可能是重新开始执行BIOS，进而死循环
    mov es,ax
    mov ss,ax

    mov esp,0x10000;esp指向64KB的地方
    ;mov esp,0x2000;这是合法的最小栈地址--段描述符中limit部分是0x1，
                        ;所以实际的锻界限县是(0x1×0x1000 + 0XFFF=0x1FFF)，由于这里是下扩展，所以最低有效地址是实际界限加1等于0x2000
                        ;对堆栈段的保护是在进行内存读写的时候发生，单独改变esp不会进行合法性检查，只有进行内存访问的时候才检查，
                        ;最大地址就是系统可用内存大小
                        ;在push/pop时，如果越过0x2000就会触发异常
    push word 0xCDEF
;=============================================================================================================

;确保使用正常的向上扩展模式--否则访问栈或者其他数据段会出现异常--安全性检查不通过
    mov ax,SELECTOR_DATA
    mov ds,ax;如果加载段选择子的时候出错，CPU会抛出异常，进一步执行异常处理程序，有可能是重新开始执行BIOS，进而死循环
    mov es,ax
    mov ss,ax

    mov esp,LOADER_STACK_TOP
;-----------------------------------------------------------------------------------------------------------------------------

;加载kernel文件到内存
    mov eax,KERNEL_START_SECTOR
    mov ebx,KERNEL_BIN_BASE_ADDR
    mov ecx,KERNEL_SECTOR_COUNT

    call rd_disk_m_32

;开启分页机制
    ;设置页目录和页表
    call setup_pages

    ;备份以前实模式物理地址下的GDT起始地址和界限
    sgdt [gdt_ptr]

    ;将视频段起始地址/段基址变成虚拟地址
    mov ebx,[gdt_ptr + 2]
    or dword [ebx + 0x18 + 4],0xc0000000 ;视频段是第三个段，每个描述符8个字节，段基址的高16位在高四字节

    ;将GDT的基址变成虚拟地址
    add dword [gdt_ptr + 2],0xc0000000 

    ;更新栈指针--以后用的都是虚拟地址，所以esp也要用虚拟地址，否则会找不到栈
    add esp,0xc0000000

    ;加载页目录到cr3
    mov eax,PAGE_DIR_TABLE_POS
    mov cr3,eax

    ;打开cr0的pg位--启用分页机制
    mov eax,cr0
    or eax,0x80000000
    mov cr0,eax

    ;重新加载修改过的全局描述符表起始地址
    lgdt [gdt_ptr]

    ;使用虚拟地址/新的视频段基址打印字符
    mov byte [gs:320],'V'



;==============================================================================================================================
;------------------------------------------------------------------------------------------------------------------------------
;    jmp $;加载内核完毕以后，loader使命结束，直接接力给kernel了，不用再在这里死循环了    
;==============================================================================================================================

    jmp SELECTOR_CODE:enter_kernel  ; 刷新流水线，避免分支预测的影响,这种cpu优化策略，最怕jmp跳转，
					     ; 这将导致之前做的预测失效，从而起到了刷新的作用。
enter_kernel:
    call kernel_init
    mov  esp,0xc009f000
    jmp  KERNEL_ENTRY_POINT


;设置页表
setup_pages:

;把页目录表所占的4KB清零
    mov ecx,4096
    mov esi,0
.clear_page_dir:
    mov byte [PAGE_DIR_TABLE_POS + esi],0
    inc esi
    loop .clear_page_dir

;开始创建页目录项
.create_pde:
    mov eax,PAGE_DIR_TABLE_POS
    add eax,0x1000  ;此时eax为第一个页表的位置
    mov ebx,eax ;备份第一个页表的地址到ebx

    or eax,(PG_US_U | PG_RW_W | PG_P);设置第一个页表的属性

    ;设置第0个目录项和第0xc00=768个目录项，使得从768到1022的目录项指向最开始的255个页表，--为的是所有进程共享内核空间，对应的虚拟地址是3GB-4GB
    ;同时第0个目录项也是指向最开始的页表（低端4MB内存）--为的是低端1MB的虚拟地址和物理地址
    mov [PAGE_DIR_TABLE_POS + 0x0],eax
    mov [PAGE_DIR_TABLE_POS + 0xc00],eax;0xc00以上的目录项属于内核空间的地址范围

    ;这是用虚拟地址访问页表的关键--会自动生成3段内存映射关系，每段都是一个页面/4KB
    sub eax,0x1000 ;使得eax指向页目录表的起始地址
    mov [PAGE_DIR_TABLE_POS + 4092],eax ;将最后一个页目录项填充为指向页目录自己--页目录占用一页空间，里面有1K个条目，也是一个物理页面，可以理解为特殊的页表

;开始创建页表项
    mov ecx,256 ;目前先创建1MB低端内存的页表项，每页大小是4KB，所以一共需要256个页，对应256个页表项
    mov esi,0
    mov edx,PG_US_U|PG_RW_W|PG_P ;设置页表项属性和位置（初始位置是0地址）--表示用户属性，所有特权级可以访问entry指向的内存，存在于内存中，可写
.create_pte:
    mov [ebx+esi*4],edx ;将edx表示的物理页地址存入第一个页表中（ebx在前面已经备份了第一个页表项的起始地址）
    add edx,4096 ;下一个页地址
    inc esi ;下一个索引
    loop  .create_pte ;循环填充256个页表项

;创建内核其他页表的页目录项(但此处没有填充PTE分配物理页框--还没有实际对应的物理页，只能找到页表，但页表是空的)
    mov eax,PAGE_DIR_TABLE_POS
    add eax,0x2000
    or eax,PG_US_U|PG_RW_W|PG_P  ;此时eax指向了第二个页表

    mov ebx,PAGE_DIR_TABLE_POS   ;ebx指向了页目录表的起始地址
    mov ecx,254 ;循环次数--因为只是769--1022,共254个，768已经填充了，指向第一个页表，1023也填充了，指向页目录表本身
    mov esi,769 ;起始索引号
.create_kernel_pde:
    mov [ebx+esi*4],eax ;从第二个页表开始，依次将每个页表（2-255）的物理地址填充到剩余的页目录项里面
    inc esi ;修改索引
    add eax,0x1000 ;修改页表地址
    loop .create_kernel_pde ;循环填充

    ret

;-------------------------------------------------------------------------------
			   ;功能:读取硬盘n个扇区
rd_disk_m_32:	   
;-------------------------------------------------------------------------------
							 ; eax=LBA扇区号
							 ; ebx=将数据写入的内存地址
							 ; ecx=读入的扇区数
      mov esi,eax	   ; 备份eax
      mov di,cx		   ; 备份扇区数到di
;读写硬盘:
;第1步：设置要读取的扇区数
      mov dx,0x1f2
      mov al,cl
      out dx,al            ;读取的扇区数

      mov eax,esi	   ;恢复ax

;第2步：将LBA地址存入0x1f3 ~ 0x1f6

      ;LBA地址7~0位写入端口0x1f3
      mov dx,0x1f3                       
      out dx,al                          

      ;LBA地址15~8位写入端口0x1f4
      mov cl,8
      shr eax,cl
      mov dx,0x1f4
      out dx,al

      ;LBA地址23~16位写入端口0x1f5
      shr eax,cl
      mov dx,0x1f5
      out dx,al

      shr eax,cl
      and al,0x0f	   ;lba第24~27位
      or al,0xe0	   ; 设置7～4位为1110,表示lba模式
      mov dx,0x1f6
      out dx,al

;第3步：向0x1f7端口写入读命令，0x20 
      mov dx,0x1f7
      mov al,0x20                        
      out dx,al

;;;;;;; 至此,硬盘控制器便从指定的lba地址(eax)处,读出连续的cx个扇区,下面检查硬盘状态,不忙就能把这cx个扇区的数据读出来

;第4步：检测硬盘状态
  .not_ready:		   ;测试0x1f7端口(status寄存器)的的BSY位
      ;同一端口,写时表示写入命令字,读时表示读入硬盘状态
      nop
      in al,dx
      and al,0x88	   ;第4位为1表示硬盘控制器已准备好数据传输,第7位为1表示硬盘忙
      cmp al,0x08
      jnz .not_ready	   ;若未准备好,继续等。

;第5步：从0x1f0端口读数据
      mov ax, di	   ;以下从硬盘端口读数据用insw指令更快捷,不过尽可能多的演示命令使用,
			   ;在此先用这种方法,在后面内容会用到insw和outsw等

      mov dx, 256	   ;di为要读取的扇区数,一个扇区有512字节,每次读入一个字,共需di*512/2次,所以di*256
      mul dx
      mov cx, ax	   
      mov dx, 0x1f0
  .go_on_read:
      in ax,dx		
      mov [ebx], ax
      add ebx, 2
			  ; 由于在实模式下偏移地址为16位,所以用bx只会访问到0~FFFFh的偏移。
			  ; loader的栈指针为0x900,bx为指向的数据输出缓冲区,且为16位，
			  ; 超过0xffff后,bx部分会从0开始,所以当要读取的扇区数过大,待写入的地址超过bx的范围时，
			  ; 从硬盘上读出的数据会把0x0000~0xffff的覆盖，
			  ; 造成栈被破坏,所以ret返回时,返回地址被破坏了,已经不是之前正确的地址,
			  ; 故程序出会错,不知道会跑到哪里去。
			  ; 所以改为ebx代替bx指向缓冲区,这样生成的机器码前面会有0x66和0x67来反转。
			  ; 0X66用于反转默认的操作数大小! 0X67用于反转默认的寻址方式.
			  ; cpu处于16位模式时,会理所当然的认为操作数和寻址都是16位,处于32位模式时,
			  ; 也会认为要执行的指令是32位.
			  ; 当我们在其中任意模式下用了另外模式的寻址方式或操作数大小时,编译器会在指令前帮我们加上0x66或0x67，
			  ; 临时改变当前cpu模式到另外的模式下.
			  ; 假设当前运行在16位模式,遇到0X66时,操作数大小变为32位.
			  ; 假设当前运行在32位模式,遇到0X66时,操作数大小变为16位.
			  ; 假设当前运行在16位模式,遇到0X67时,寻址方式变为32位寻址
			  ; 假设当前运行在32位模式,遇到0X67时,寻址方式变为16位寻址.
              ;这里又由于直接是保护模式，所以用32位寄存器，避免wrap around

      loop .go_on_read
      ret

;其实执行该函数的时候，已经打开分页机制，设计的地址都应该是虚拟地址，只不过由于在搬运内核释放映像的过程中，
;操作的是低端1MB内存，物理地址和虚拟地址是一样的值
;gcc -c -o  main.o main.c -m32
;ld main.o -Ttext 0xc0001500 -e main -o kernel.bin -melf_i386
;xxd -u -a -g 1 -s 0 -l 2048 kernel.bin 
;gcc -S main.c -o main.S -m32
;发现执行不正常，用b设置断点从loader的入口地址开始（物理地址），发现死在rep操作，表明访问了非法内存，其实可以ptime获取此时执行的指令条数，从新用sba设置断点
;判断读的elf header和程序头的数据是否正确--通过比对kernel.bin和内存中物理地址为0x70000处的数据，发现正确读取了kernel.bin到内存
;既然正确读取了kernel到内存，但是在复制的时候存在非法内存访问，只能说明kernel对应elf格式中读取出来的参数有问题，比对kernel中的文件头，发现他是64位的elf文件
;宿主机是64位的Linux，模拟器是32位的x86，所以elf格式不匹配，参数选取错误。应该编译出32位用的elf文件。gcc用-m32选项，ld用-melf_i386选项。
;再编译出main.c对应的汇编文件，看看进入main以后如何处理栈
;全速运行模拟器以后，用print-stack查看栈中数据，再和自己设定的临时变量比对，结合汇编文件，判断是否正确执行到了main.c

kernel_init:
    xor eax,eax
    xor ebx,ebx ;记录程序头表地址
    xor ecx,ecx ;记录程序头的数量
    xor edx,edx ;记录程序头的大小

    ;在ELF  header中进行信息采集
    mov dx,[KERNEL_BIN_BASE_ADDR+42] ;获取ELF格式文件中program header的大小
    mov ebx,[KERNEL_BIN_BASE_ADDR+28] ;读取program header tables在文件中的偏移量
    add ebx,KERNEL_BIN_BASE_ADDR ;加上内核的起始物理地址便得到程序头表的物理地址，也是第一个程序头的虚拟地址

    mov cx,[KERNEL_BIN_BASE_ADDR + 44] ;获取程序头/段头/segment的个数

.each_segment:
    cmp byte [ebx+0],PT_NULL ;如果程序头的p_type为0--表示该头未使用，直接检查下一个头
    je  .PTNULL ;检查下一个segment

    ;为mem_cpy传递参数，从右往左依次压入
    push dword [ebx+16] ;表示本段在文件中的大小--单位是字节

    mov eax,[ebx+4] ;本段在文件内的起始偏移字节
    add eax,KERNEL_BIN_BASE_ADDR ;获取本段对应的物理地址

    push eax ;压入mem_cpy的第二个参数，原地址
    push dword [ebx+8] ;压入mem_cpy的第一个参数，目标地址

    call mem_cpy ;完成本段的数据复制--建立内核映像的一个段
    add esp,12 ;回收栈空间

.PTNULL:
    add ebx,edx ;ebx指向下一个程序头
    loop .each_segment ;

    ret
;复制一块数据到目标地址，参数由栈提供，主调函数将实参压栈
mem_cpy:
    cld ;清除eflags寄存器中的标志位，设置为地址递增
    push ebp ;使用ebp作为参数的基址--有的时候要快速访问栈里面的内容，用ebp好于esp
    mov ebp,esp ;设置ebp指向保存旧的ebp的位置，再往上8个字节就是存储第一个参数的位置--call指令调用函数的时候自动压入返回地址
    push ecx ;保存ecx--因为外层遍历程序头表还要用到

    mov edi,[ebp+8] ;取出目的地址
    mov esi,[ebp+12] ;取出原地址
    mov ecx,[ebp+16] ;取出要拷贝的字节数

    rep movsb ;根据ecx逐个字节拷贝

    ;恢复环境
    pop ecx 
    pop ebp
    ret