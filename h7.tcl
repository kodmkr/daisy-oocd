source [find interface/stlink.cfg]

transport select hla_swd

set QUADSPI 1

source [find target/stm32h7x.cfg]

reset_config srst_only

source [find addrs.tcl]
source [find funcs.tcl]

## PC7 is USER_LED on Daisy
proc led {arg} {
    global RCC GPIOC

    mmw $RCC(AHB4ENR) $(1 << 2) 0 ;# turn on clock

    if [string equal $arg init] {
        mmw $GPIOC(MODER)   $(0b01 << 14) $(0b10 << 14)
        mmw $GPIOC(OSPEEDR) $(0b11 << 14) 0
    } else {
        if {$arg} {
            mmw $GPIOC(BSRR) $(1 << 7) 0
        } else {
            mmw $GPIOC(BSRR) $(1 << 23) 0
        }
    }
}

## Flash initialization for Daisy board
# PF8  => IO0 (AF10  V)
# PF9  => IO1 (AF10  V)
# PF7  => IO2 (AF09  V)
# PF6  => IO3 (AF09  V)
# PF10 => CLK (AF09  V)
# PG6  => CS  (AF10  V)
proc qspi_init {} {
    global RCC GPIOF GPIOG QSPI
    #                    GPIOGEN=1  GPIOFEN=1
    mmw $RCC(AHB4ENR) $((1 << 6) | (1 << 5)) 0

    #                   QSPIEN=1
    mmw $RCC(AHB3ENR) $(1 << 14)             0
    sleep 1

    ## PF08 : IO0 (AF10)
    mmw $GPIOF(MODER)   $(0b10 << 16)  $(0b11 << 16)
    mmw $GPIOF(OSPEEDR) $(0b11 << 16)  0
    mmw $GPIOF(AFRH)    $(0b1010 << 0) $(0b1111 << 0)

    ## PF09 : IO1 (AF10)
    mmw $GPIOF(MODER)   $(0b10 << 18)  $(0b11 << 18)
    mmw $GPIOF(OSPEEDR) $(0b11 << 18)  0
    mmw $GPIOF(AFRH)    $(0b1010 << 4) $(0b1111 << 4)

    ## PF07 : IO2 (AF09)
    mmw $GPIOF(MODER)   $(0b10 << 14)   $(0b11 << 14)
    mmw $GPIOF(OSPEEDR) $(0b11 << 14)   0
    mmw $GPIOF(AFRL)    $(0b1001 << 28) $(0b1111 << 28)

    ## PF06 : IO3 (AF09)
    mmw $GPIOF(MODER)   $(0b10 << 12)   $(0b11 << 12)
    mmw $GPIOF(OSPEEDR) $(0b11 << 12)   0
    mmw $GPIOF(AFRL)    $(0b1001 << 24) $(0b1111 << 24)

    ## PF10 : CLK (AF09)
    mmw $GPIOF(MODER)   $(0b10 << 20)  $(0b11 << 20)
    mmw $GPIOF(OSPEEDR) $(0b11 << 20)  0
    mmw $GPIOF(AFRH)    $(0b1001 << 8) $(0b1111 << 8)

    ## PG06 : CS  (AF10)
    mmw $GPIOG(MODER)   $(0b10 << 12)   $(0b11 << 12)
    mmw $GPIOG(OSPEEDR) $(0b11 << 12)   0
    mmw $GPIOG(AFRL)    $(0b1010 << 24) $(0b1111 << 24)

    # reset QSPI peripheral
    mmw $RCC(AHB3RSTR) $(1 << 14) 0
    mmw $RCC(AHB3RSTR) 0          $(1 << 14)

    # 64MHz clock div 2 --> 32MHz
    #                  PRESC=1     ASPM=1      FTHRESH=3  SSHIFT=0   EN=1
    mww $QSPI(CR)  $( (1 << 24) | (1 << 22) | (3 << 8) | (0 << 4) | (1 << 0))

    # is25lp064 has 64Mbit = 8MB = 8388608 bytes
    # ==> log_2(8388608) = 23 ==> FSIZE = 22 = 16h
    #                FSIZE=16h       CSHT=2
    mww $QSPI(DCR) $((0x16 << 16) | (0b010 << 8))

    ## Reset
    #                  IMODE=1       INSTR=RSTEN(66h)
    mww $QSPI(CCR) $((0b01 << 8) | (0x66 << 0))
    sleep 1
    #                  IMODE=1       INSTR=RST(99h)
    mww $QSPI(CCR) $((0b01 << 8) | (0x99 << 0))
    sleep 1

    #                 DMODE=1        IMODE=1       INSTR=SRP(C0h)
    mww $QSPI(CCR) $((0b01 << 24) | (0b01 << 8) | (0xC0 << 0))
    mww $QSPI(DLR) 0    ;# 1b to be transferred
    mww $QSPI(DR)  0x00 ;# 8 dummy cycles for READ REGISTER
    sleep 1

    #                CTCF=1
    mmw $QSPI(FCR) $(1 << 1) 0

    #                 FMODE=3        DMODE=1        DCYC=0            ADSIZE=10      ADMODE=01      IMODE=01      INSTR=NORD(03h)
    mww $QSPI(CCR) $((0b11 << 26) | (0b01 << 24) | (0b00000 << 18) | (0b10 << 12) | (0b01 << 10) | (0b01 << 8) | (0x03 << 0))
}

$_CHIPNAME.cpu0 configure -event reset-init {
    # HSI clock is at 64MHz after reset.

    adapter speed 2000

    qspi_init
}
