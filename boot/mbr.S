;MBR
;---------------------------------------
SECTION MBR vstart=0x7c00   ;告诉编译器，起始地址是0x7c00，jmp 0:0x7c00
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov fs,ax               ;初始化其他的sreg，不能直接从立即数到sreg，只能通过通用寄存器做中转
    mov sp,0x7c00           ;初始化栈指针


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

;获取光标位置
;.get_cursor
    mov ah,3    ;0x03号子功能获取光标位置
    mov bh,0    ;存储待获取光标的页号
    int 0x10    ;ch=光标开始行，cl=光标结束行，dh=光标所在行号，dl=光标所在列号

;打印字符串--0x13号子功能
    mov ax,message
    mov bp,ax   ;es:bp--字符串首地址，es和cs一致（初始化了已经）

    ;光标位置主要用到dx中的数据，cx用得少
    mov cx,10   ;cx存储字符串长度，不包括结束符
    mov ax,0x1301   ;al设置写字符的方式，01--显示字符串，光标跟着移动
    mov bx, 0x02     ;bh存储要显示的页号，第0页，bl是字符属性，02h--黑底绿字
    int 0x10

;打印结束
    jmp $           ;死循环

    message db "Aloha Jack"
    times 510-($-$$) db 0
    db 0x55,0xAA         
