;MBR
;---------------------------------------
%include "boot.inc"
SECTION MBR vstart=0x7c00   ;告诉编译器，起始地址是0x7c00，jmp 0:0x7c00
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov fs,ax               ;初始化其他的sreg，不能直接从立即数到sreg，只能通过通用寄存器做中转
    mov sp,0x7c00           ;初始化栈指针

    mov ax,0xb800
    mov gs,ax

;Clear display--0x06
;AH---功能号
;AL---上卷行数---0表示全部清屏
;BH---上卷行属性
;(CL,CH)--窗口左上角的(X,Y)位置
;(DL,DH)--窗口右下角的(X,Y)位置
;----------------------------------------

    mov ax,0x0600
    mov bx,0x0700
    mov cx,0x0000   ;(0,0)
    mov dx,0x184f   ;(80,25)

    int 0x10
;背景绿色，前景红色，字符串“Aloha Jack”
    mov byte [gs:0x00],'A'
    mov byte [gs:0x01],0xA4

    mov byte [gs:0x02],'l'
    mov byte [gs:0x03],0xA4

    mov byte [gs:0x04],'o'
    mov byte [gs:0x05],0xA4

    mov byte [gs:0x06],'h'
    mov byte [gs:0x07],0xA4

    mov byte [gs:0x08],'a'
    mov byte [gs:0x09],0xA4

    mov byte [gs:0x0a],' '
    mov byte [gs:0x0b],0xA4

    mov byte [gs:0x0c],'J'
    mov byte [gs:0x0d],0xA4

    mov byte [gs:0x0e],'a'
    mov byte [gs:0x0f],0xA4

    mov byte [gs:0x10],'c'
    mov byte [gs:0x11],0xA4

    mov byte [gs:0x12],'k'
    mov byte [gs:0x13],0xA4

;----------------added for load loader from disk，用eax，bx，cx做参数传递---------------------
    mov eax,LOADER_START_SECTOR    ;起始扇区地址，这里用LBA28，eax是32bits足够用了，但ax是16bits不够用来存放LBA地址
    mov bx,LOADER_BASE_ADDR         ;loader在内存中的起始地址/待写入的地址
    mov cx,SECTOR_COUNT                        ;待写入的扇区数

    call rd_disk_m_16               ;读取loader到指定地址

    jmp LOADER_BASE_ADDR            ;完成权力交接，将CPU交给loader，MBR一去不复返

;------------------rd_disk_m_16 function 读取硬盘n个扇区----------------------
rd_disk_m_16:
    ;0.参数备份，因为在out指令中/读数据过程中国会破坏这两个寄存器的值，所以需要先备份，或者在传递参数的时候用别的寄存器
    mov esi,eax                     ;备份eax--LBA格式的起始扇区地址
    mov di,cx                       ;备份cx--读入的扇区数

    ;1.设置要读取的扇区数
    mov dx,0x1f2
    mov al,cl
    out dx,al
    mov eax,esi                     ;恢复eax

    ;2.将LBA地址写入相应的端口/硬盘控制器的寄存器，根据bochs的配置选项选用主通道/IDE0通道
    mov dx,0x1f3                    ;LBA地址7-0 bit写入LBA low寄存器，主通道下是0x1f3
    out dx,al

    mov cl,8                        ;LBA地址15-8 bit写入LBA low寄存器，主通道下是0x1f4
    shr eax,cl
    mov dx,0x1f4                    
    out dx,al

                           
    shr eax,cl                      ;LBA地址23-16 bit写入LBA low寄存器，主通道下是0x1f5
    mov dx,0x1f5                    
    out dx,al

                           
    shr eax,cl                     ;LBA地址27-24 bit写入Device寄存器，主通道下是0x1f6
    and al,0x0f                    ;获取27-24 bit
    or al,0xe0                     ;设置使用LBA模式，bit5和bit7固定是1
    mov dx,0x1f6                    
    out dx,al

    ;3.写入读取命令--一旦写入该命令，便开始读取数据了
    mov dx,0x1f7
    mov al,0x20                    
    out dx,al

    ;4.检测硬盘状态
.not_ready:
    nop                             ;还是使用上一步的0x1f7端口，写的时候表示command，读的时候表示status，不用修改dx
    in al,dx
    and al,0x88
    cmp al,0x08                     ;只有当bit7为0（不忙），且bit4为1（准备好数据）时，才可进行下一步，否则循环等待硬盘就绪可读
    jnz .not_ready


    ;5.从数据端口读取数据
    mov ax,di                       ;恢复cx到ax，现在的ax表示要读取的扇区数
    mov dx,256                      ;一个扇区512字节，硬盘控制器的数据寄存器是16bits，一次能读取2个字节，所以一个扇区只需要读取256次（512/2）
    mul dx                          ;默认另一个乘数是ax，此时结果是32bits，dx：ax，由于在此ax==1，所以结果中的dx为0，只有低16bits有用
    mov cx,ax                       ;此时的cx表示读取n（通过原来cx传递备份到di又恢复到ax）个扇区需要读取的次数，用来做循环控制

    mov dx,0x1f0
.go_on_read:                        ;loop指令会自动查看cx的值，当cx为0的时候不再loop
    in ax,dx
    mov [bx],ax
    add bx,2
    loop .go_on_read
    
    ;6. 函数返回
    ret

;填充MBR剩余的空间

    times 510-($-$$) db 0
    db 0x55,0xAA                    ;MBR结束标志
