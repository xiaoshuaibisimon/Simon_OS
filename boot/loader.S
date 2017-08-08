%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR

    mov ax,0xb800
    mov gs,ax

;背景绿色，前景红色，字符串“Aloha Jack”
    mov byte [gs:0x00],'A'
    mov byte [gs:0x01],0xF9

    mov byte [gs:0x02],'l'
    mov byte [gs:0x03],0xF9

    mov byte [gs:0x04],'o'
    mov byte [gs:0x05],0xF9

    mov byte [gs:0x06],'h'
    mov byte [gs:0x07],0xF9

    mov byte [gs:0x08],'a'
    mov byte [gs:0x09],0xF9

    mov byte [gs:0x0a],' '
    mov byte [gs:0x0b],0xF9

    mov byte [gs:0x0c],'S'
    mov byte [gs:0x0d],0xF9

    mov byte [gs:0x0e],'i'
    mov byte [gs:0x0f],0xF9

    mov byte [gs:0x10],'m'
    mov byte [gs:0x11],0xF9

    mov byte [gs:0x12],'o'
    mov byte [gs:0x13],0xF9

    mov byte [gs:0x14],'n'
    mov byte [gs:0x15],0xF9

    jmp $