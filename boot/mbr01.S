;MBR
;---------------------------------------
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

;打印结束
    jmp $           ;死循环

    times 510-($-$$) db 0
    db 0x55,0xAA         
