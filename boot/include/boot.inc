LOADER_BASE_ADDR equ 0x900  ;loader被MBR加载到内存中的此地址
LOADER_START_SECTOR equ 0x2 ;loader的起始扇区序号--从0开始计数
SECTOR_COUNT equ  0x4

;GDT 描述符属性
DESC_G_4K               equ     0x800000 ;bit23=1，内存段颗粒为4KB

DESC_D_32               equ     0x400000 ;bit22=1，表示代码段中指令中有效地址以及操作数是32位，用EIP寄存器

DESC_L                  equ     0x000000 ;bit21=0，表示32位的代码段/编程

DESC_AVL                equ     0x000000 ;bit20=0，暂时没用到，对操作系统有效

DESC_LIMIT_CODE_H4      equ     0x0F0000  ;bits[19-16]=0xF，表示代码段界限的高4bits，这里吧代码段和普通数据段的limit都设置为全F，整个区间就是4GB 
DESC_LIMIT_DATA_H4      equ     DESC_LIMIT_CODE_H4 ;bits[19-16]=0xF，表示数据段界限的高4bits 
DESC_LIMIT_DATA1_H4      equ     0x000000 ;bits[19-16]=0x0，表示数据段界限的高4bits,由于bochs配置的内存只是32MB，
                                          ;所以我们在向下扩展的时候，界限用1就可以了，也就是不用最低的4KB空间
DESC_LIMIT_VIDEO_H4     equ     0x000000 ;bits[19-16]=0x0，表示用于显存的数据段界限的高4bits，结合实模式下1MB内存布局和颗粒为4KB，
                                         ;可知道用于文本模式的显存区间limit只是(0xbffff-0xb8000)/4KB = 7,所以limit的高4为是0 

DESC_P                  equ     0x8000  ;bit15=1，表示内存段存在

DESC_DPL_0              equ     0x0000  ;bits[14-13]，表示描述符特权级
DESC_DPL_1              equ     0x2000
DESC_DPL_2              equ     0x4000
DESC_DPL_3              equ     0x6000

DESC_S_CODE             equ     0x1000  ;bit12=1，表示非系统段--代码段
DESC_S_DATA             equ     DESC_S_CODE ;bit12=1，表示非系统段--数据段
DESC_S_SYS              equ     0x0000 ;bit12=0，表示系统段

DESC_TYPE_CODE          equ     0x0800 ;bits[11-8]，表示内存段类型--代码段，可执行，非一致性，不可读，未访问
DESC_TYPE_DATA          equ     0x0200 ;bits[11-8]，表示内存段类型--数据段，不可执行，向上扩展，可写，未访问
DESC_TYPE_DATA1         equ     0x0600 ;bits[11-8]，表示内存段类型--数据段，不可执行，向下扩展，可写，未访问

;代码段的高32bits
DESC_CODE_H4BYTES       equ     ((0x00 << 24) + DESC_G_4K + DESC_D_32 +  \
                                DESC_L + DESC_AVL + DESC_LIMIT_CODE_H4 +  \
                                DESC_P +DESC_DPL_0 + DESC_S_CODE + DESC_TYPE_CODE + 0x00)

;数据段的高32bits
DESC_DATA_H4BYTES       equ     ((0x00 << 24) + DESC_G_4K + DESC_D_32 +  \
                                DESC_L + DESC_AVL + DESC_LIMIT_DATA_H4 +  \
                                DESC_P +DESC_DPL_0 + DESC_S_DATA + DESC_TYPE_DATA + 0x00)

;显存段的高32bits
DESC_VIDEO_H4BYTES      equ     ((0x00 << 24) + DESC_G_4K + DESC_D_32 +  \
                                DESC_L + DESC_AVL + DESC_LIMIT_VIDEO_H4 +  \
                                DESC_P +DESC_DPL_0 + DESC_S_DATA + DESC_TYPE_DATA + 0x0B)

;数据段的高32bits
DESC_DATA1_H4BYTES       equ     ((0x00 << 24) + DESC_G_4K + DESC_D_32 +  \
                                DESC_L + DESC_AVL + DESC_LIMIT_DATA1_H4 +  \
                                DESC_P +DESC_DPL_0 + DESC_S_DATA + DESC_TYPE_DATA1 + 0x00)


;选择子属性
RPL0                    equ     00b ;请求特权级
RPL1                    equ     01b
RPL2                    equ     10b
RPL3                    equ     11b

TI_GDT                  equ     000b ;段描述符所在的表在GDT
TI_LDT                  equ     100b ;在LDT


;页目录项和页表项属性
PAGE_DIR_TABLE_POS      equ     0x100000 ;页目录表起始地址，1MB地址下一个字节

PG_P                    equ     1b
PG_RW_W                 equ     10b
PG_RW_R                 equ     00b

PG_US_S                 equ     000b
PG_US_U                 equ     100b

;加载内核
KERNEL_START_SECTOR     equ     0x9 ;0号被MBR用，2-5被loader用，从9号扇区开始存放内核文件
KERNEL_BIN_BASE_ADDR    equ     0x70000  ;只要是在0x7e00---0x9fbff之间都可以，但也的保证存得下内核文件，
                                            ;假设内核100KB，选一个整数0x70000，他到0x9fbff之间将近190KB，足够用了，可以改成其他地址的
KERNEL_SECTOR_COUNT     equ     200 ;200个扇区足够存放内核了

KERNEL_ENTRY_POINT      equ     0xc0001500  ;loader.bin的起始地址是0x900，假设他有2KB大小，为了使用他建立的GDT等全局资源
                                            ;我们可用的起始地址是0x900+2048=0x1100，取比他大的一个整数，选择0x1500，对应成虚拟地址就是0xc0001500.
                                            ;可换其他值

PT_NULL                 equ     0