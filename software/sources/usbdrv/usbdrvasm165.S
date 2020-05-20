/* Name: usbdrvasm165.S
 * Project: AVR USB driver
 * Author: Christian Starkjohann
 * Creation Date: 2007-04-22
 * Tabsize: 4
 * Copyright: (c) 2007 by OBJECTIVE DEVELOPMENT Software GmbH
 * License: GNU GPL v2 (see License.txt) or proprietary (CommercialLicense.txt)
 * Revision: $Id$
 */

/* Do not link this file! Link usbdrvasm.S instead, which includes the
 * appropriate implementation!
 */

/*
General Description:
This file is the 16.5 MHz version of the USB driver. It is intended for the
ATTiny45 and similar controllers running on 16.5 MHz internal RC oscillator.
This version contains a phase locked loop in the receiver routine to cope with
slight clock rate deviations of up to +/- 1%.

See usbdrv.h for a description of the entire driver.

Since almost all of this code is timing critical, don't change unless you
really know what you are doing! Many parts require not only a maximum number
of CPU cycles, but even an exact number of cycles!
*/

;Software-receiver engine. Strict timing! Don't change unless you can preserve timing!
;interrupt response time: 4 cycles + insn running = 7 max if interrupts always enabled
;max allowable interrupt latency: 59 cycles -> max 52 cycles interrupt disable
;max stack usage: [ret(2), r0, SREG, YL, YH, shift, x1, x2, x3, x4, cnt] = 12 bytes
;nominal frequency: 16.5 MHz -> 11 cycles per bit
; 16.3125 MHz < F_CPU < 16.6875 MHz (+/- 1.1%)
; Numbers in brackets are clocks counted from center of last sync bit
; when instruction starts


SIG_INTERRUPT0:
;order of registers pushed: r0, SREG [sofError], YL, YH, shift, x1, x2, x3, x4, cnt
    push    r0                  ;[-23] push only what is necessary to sync with edge ASAP
    in      r0, SREG            ;[-21]
    push    r0                  ;[-20]
;----------------------------------------------------------------------------
; Synchronize with sync pattern:
;----------------------------------------------------------------------------
;sync byte (D-) pattern LSb to MSb: 01010100 [1 = idle = J, 0 = K]
;sync up with J to K edge during sync pattern -- use fastest possible loops
;first part has no timeout because it waits for IDLE or SE1 (== disconnected)
waitForJ:
    sbis    USBIN, USBMINUS     ;[-18] wait for D- == 1
    rjmp    waitForJ
waitForK:
;The following code results in a sampling window of < 1/4 bit which meets the spec.
    sbis    USBIN, USBMINUS     ;[-15]
    rjmp    foundK              ;[-14]
    sbis    USBIN, USBMINUS
    rjmp    foundK
    sbis    USBIN, USBMINUS
    rjmp    foundK
    sbis    USBIN, USBMINUS
    rjmp    foundK
    sbis    USBIN, USBMINUS
    rjmp    foundK
    sbis    USBIN, USBMINUS
    rjmp    foundK
    rjmp    sofError
foundK:                         ;[-12]
;{3, 5} after falling D- edge, average delay: 4 cycles [we want 5 for center sampling]
;we have 1 bit time for setup purposes, then sample again. Numbers in brackets
;are cycles from center of first sync (double K) bit after the instruction
    push    YL                  ;[-12]
;   [---]                       ;[-11]
    push    YH                  ;[-10]
;   [---]                       ;[-9]
    lds     YL, usbInputBufOffset;[-8]
;   [---]                       ;[-7]
    clr     YH                  ;[-6]
    subi    YL, lo8(-(usbRxBuf));[-5] [rx loop init]
    sbci    YH, hi8(-(usbRxBuf));[-4] [rx loop init]
    mov     r0, x2              ;[-3] [rx loop init]
    sbis    USBIN, USBMINUS     ;[-2] we want two bits K (sample 2 cycles too early)
    rjmp    haveTwoBitsK        ;[-1]
    pop     YH                  ;[0] undo the pushes from before
    pop     YL                  ;[2]
    rjmp    waitForK            ;[4] this was not the end of sync, retry
; The entire loop from waitForK until rjmp waitForK above must not exceed two
; bit times (= 22 cycles).

;----------------------------------------------------------------------------
; push more registers and initialize values while we sample the first bits:
;----------------------------------------------------------------------------
haveTwoBitsK:               ;[1]
    push    shift           ;[1]
    push    x1              ;[3]
    push    x2              ;[5]
    push    x3              ;[7]
    ldi     shift, 0xff     ;[9] [rx loop init]
    ori     x3, 0xff        ;[10] [rx loop init] == ser x3, clear zero flag

    in      x1, USBIN       ;[11] <-- sample bit 0
    bst     x1, USBMINUS    ;[12]
    bld     shift, 0        ;[13]
    push    x4              ;[14] == phase
;   [---]                   ;[15]
    push    cnt             ;[16]
;   [---]                   ;[17]
    ldi     phase, 0        ;[18] [rx loop init]
    ldi     cnt, USB_BUFSIZE;[19] [rx loop init]
    rjmp    rxbit1          ;[20]
;   [---]                   ;[21]

;----------------------------------------------------------------------------
; Receiver loop (numbers in brackets are cycles within byte after instr)
;----------------------------------------------------------------------------
/*
byte oriented operations done during loop:
bit 0: store data
bit 1: SE0 check
bit 2: overflow check
bit 3: catch up
bit 4: rjmp to achieve conditional jump range
bit 5: PLL
bit 6: catch up
bit 7: jump, fixup bitstuff
; 87 [+ 2] cycles
------------------------------------------------------------------
*/
continueWithBit5:
    in      x2, USBIN       ;[055] <-- bit 5
    eor     r0, x2          ;[056]
    or      phase, r0       ;[057]
    sbrc    phase, USBMINUS ;[058]
    lpm                     ;[059] optional nop3; modifies r0
    in      phase, USBIN    ;[060] <-- phase
    eor     x1, x2          ;[061]
    bst     x1, USBMINUS    ;[062]
    bld     shift, 5        ;[063]
    andi    shift, 0x3f     ;[064]
    in      x1, USBIN       ;[065] <-- bit 6
    breq    unstuff5        ;[066] *** unstuff escape
    eor     phase, x1       ;[067]
    eor     x2, x1          ;[068]
    bst     x2, USBMINUS    ;[069]
    bld     shift, 6        ;[070]
didUnstuff6:                ;[   ]
    in      r0, USBIN       ;[071] <-- phase
    cpi     shift, 0x02     ;[072]
    brlo    unstuff6        ;[073] *** unstuff escape
didUnstuff5:                ;[   ]
    nop2                    ;[074]
;   [---]                   ;[075]
    in      x2, USBIN       ;[076] <-- bit 7
    eor     x1, x2          ;[077]
    bst     x1, USBMINUS    ;[078]
    bld     shift, 7        ;[079]
didUnstuff7:                ;[   ]
    eor     r0, x2          ;[080]
    or      phase, r0       ;[081]
    in      r0, USBIN       ;[082] <-- phase
    cpi     shift, 0x04     ;[083]
    brsh    rxLoop          ;[084]
;   [---]                   ;[085]
unstuff7:                   ;[   ]
    andi    x3, ~0x80       ;[085]
    ori     shift, 0x80     ;[086]
    in      x2, USBIN       ;[087] <-- sample stuffed bit 7
    nop                     ;[088]
    rjmp    didUnstuff7     ;[089]
;   [---]                   ;[090]
                            ;[080]

unstuff5:                   ;[067]
    eor     phase, x1       ;[068]
    andi    x3, ~0x20       ;[069]
    ori     shift, 0x20     ;[070]
    in      r0, USBIN       ;[071] <-- phase
    mov     x2, x1          ;[072]
    nop                     ;[073]
    nop2                    ;[074]
;   [---]                   ;[075]
    in      x1, USBIN       ;[076] <-- bit 6
    eor     r0, x1          ;[077]
    or      phase, r0       ;[078]
    eor     x2, x1          ;[079]
    bst     x2, USBMINUS    ;[080]
    bld     shift, 6        ;[081] no need to check bitstuffing, we just had one
    in      r0, USBIN       ;[082] <-- phase
    rjmp    didUnstuff5     ;[083]
;   [---]                   ;[084]
                            ;[074]

unstuff6:                   ;[074]
    andi    x3, ~0x40       ;[075]
    in      x1, USBIN       ;[076] <-- bit 6 again
    ori     shift, 0x40     ;[077]
    nop2                    ;[078]
;   [---]                   ;[079]
    rjmp    didUnstuff6     ;[080]
;   [---]                   ;[081]
                            ;[071]

unstuff0:                   ;[013]
    eor     r0, x2          ;[014]
    or      phase, r0       ;[015]
    andi    x2, USBMASK     ;[016] check for SE0
    in      r0, USBIN       ;[017] <-- phase
    breq    didUnstuff0     ;[018] direct jump to se0 would be too long
    andi    x3, ~0x01       ;[019]
    ori     shift, 0x01     ;[020]
    mov     x1, x2          ;[021] mov existing sample
    in      x2, USBIN       ;[022] <-- bit 1 again
    rjmp    didUnstuff0     ;[023]
;   [---]                   ;[024]
                            ;[014]

unstuff1:                   ;[024]
    eor     r0, x1          ;[025]
    or      phase, r0       ;[026]
    andi    x3, ~0x02       ;[027]
    in      r0, USBIN       ;[028] <-- phase
    ori     shift, 0x02     ;[029]
    mov     x2, x1          ;[030]
    rjmp    didUnstuff1     ;[031]
;   [---]                   ;[032]
                            ;[022]

unstuff2:                   ;[035]
    eor     r0, x2          ;[036]
    or      phase, r0       ;[037]
    andi    x3, ~0x04       ;[038]
    in      r0, USBIN       ;[039] <-- phase
    ori     shift, 0x04     ;[040]
    mov     x1, x2          ;[041]
    rjmp    didUnstuff2     ;[042]
;   [---]                   ;[043]
                            ;[033]

unstuff3:                   ;[043]
    in      x2, USBIN       ;[044] <-- bit 3 again
    eor     r0, x2          ;[045]
    or      phase, r0       ;[046]
    andi    x3, ~0x08       ;[047]
    ori     shift, 0x08     ;[048]
    nop                     ;[049]
    in      r0, USBIN       ;[050] <-- phase
    rjmp    didUnstuff3     ;[051]
;   [---]                   ;[052]
                            ;[042]

unstuff4:                   ;[053]
    andi    x3, ~0x10       ;[054]
    in      x1, USBIN       ;[055] <-- bit 4 again
    ori     shift, 0x10     ;[056]
    rjmp    didUnstuff4     ;[057]
;   [---]                   ;[058]
                            ;[048]

rxLoop:                     ;[085]
    eor     x3, shift       ;[086] reconstruct: x3 is 0 at bit locations we changed, 1 at others
    in      x1, USBIN       ;[000] <-- bit 0
    st      y+, x3          ;[001]
;   [---]                   ;[002]
    eor     r0, x1          ;[003]
    or      phase, r0       ;[004]
    eor     x2, x1          ;[005]
    in      r0, USBIN       ;[006] <-- phase
    ser     x3              ;[007]
    bst     x2, USBMINUS    ;[008]
    bld     shift, 0        ;[009]
    andi    shift, 0xf9     ;[010]
rxbit1:                     ;[   ]
    in      x2, USBIN       ;[011] <-- bit 1
    breq    unstuff0        ;[012] *** unstuff escape
    andi    x2, USBMASK     ;[013] SE0 check for bit 1
didUnstuff0:                ;[   ] Z only set if we detected SE0 in bitstuff
    breq    se0             ;[014]
    eor     r0, x2          ;[015]
    or      phase, r0       ;[016]
    in      r0, USBIN       ;[017] <-- phase
    eor     x1, x2          ;[018]
    bst     x1, USBMINUS    ;[019]
    bld     shift, 1        ;[020]
    andi    shift, 0xf3     ;[021]
didUnstuff1:                ;[   ]
    in      x1, USBIN       ;[022] <-- bit 2
    breq    unstuff1        ;[023] *** unstuff escape
    eor     r0, x1          ;[024]
    or      phase, r0       ;[025]
    subi    cnt, 1          ;[026] overflow check
    brcs    overflow        ;[027]
    in      r0, USBIN       ;[028] <-- phase
    eor     x2, x1          ;[029]
    bst     x2, USBMINUS    ;[030]
    bld     shift, 2        ;[031]
    andi    shift, 0xe7     ;[032]
didUnstuff2:                ;[   ]
    in      x2, USBIN       ;[033] <-- bit 3
    breq    unstuff2        ;[034] *** unstuff escape
    eor     r0, x2          ;[035]
    or      phase, r0       ;[036]
    eor     x1, x2          ;[037]
    bst     x1, USBMINUS    ;[038]
    in      r0, USBIN       ;[039] <-- phase
    bld     shift, 3        ;[040]
    andi    shift, 0xcf     ;[041]
didUnstuff3:                ;[   ]
    breq    unstuff3        ;[042] *** unstuff escape
    nop                     ;[043]
    in      x1, USBIN       ;[044] <-- bit 4
    eor     x2, x1          ;[045]
    bst     x2, USBMINUS    ;[046]
    bld     shift, 4        ;[047]
didUnstuff4:                ;[   ]
    eor     r0, x1          ;[048]
    or      phase, r0       ;[049]
    in      r0, USBIN       ;[050] <-- phase
    andi    shift, 0x9f     ;[051]
    breq    unstuff4        ;[052] *** unstuff escape
    rjmp    continueWithBit5;[053]
;   [---]                   ;[054]

;----------------------------------------------------------------------------
; Processing of received packet (numbers in brackets are cycles after center of SE0)
;----------------------------------------------------------------------------
;This is the only non-error exit point for the software receiver loop
;we don't check any CRCs here because there is no time left.
#define token   x1
se0:
    subi    cnt, USB_BUFSIZE    ;[5]
    neg     cnt                 ;[6]
    cpi     cnt, 3              ;[7]
    ldi     x2, 1<<USB_INTR_PENDING_BIT ;[8]
    out     USB_INTR_PENDING, x2;[9] clear pending intr and check flag later. SE0 should be over.
    brlo    doReturn            ;[10] this is probably an ACK, NAK or similar packet
    sub     YL, cnt             ;[11]
    sbci    YH, 0               ;[12]
    ld      token, y            ;[13]
    cpi     token, USBPID_DATA0 ;[15]
    breq    handleData          ;[16]
    cpi     token, USBPID_DATA1 ;[17]
    breq    handleData          ;[18]
    ldd     x2, y+1             ;[19] ADDR and 1 bit endpoint number
    mov     x3, x2              ;[21] store for endpoint number
    andi    x2, 0x7f            ;[22] x2 is now ADDR
    lds     shift, usbDeviceAddr;[23]
    cp      x2, shift           ;[25]
overflow:                       ; This is a hack: brcs overflow will never have Z flag set
    brne    ignorePacket        ;[26] packet for different address
    cpi     token, USBPID_IN    ;[27]
    breq    handleIn            ;[28]
    cpi     token, USBPID_SETUP ;[29]
    breq    handleSetupOrOut    ;[30]
    cpi     token, USBPID_OUT   ;[31]
    breq    handleSetupOrOut    ;[32]
;   rjmp    ignorePacket        ;fallthrough, should not happen anyway.

ignorePacket:
    clr     shift
    sts     usbCurrentTok, shift
doReturn:
    pop     cnt
    pop     x4
    pop     x3
    pop     x2
    pop     x1
    pop     shift
    pop     YH
    pop     YL
sofError:
    pop     r0
    out     SREG, r0
    pop     r0
    reti

#if USB_CFG_HAVE_INTRIN_ENDPOINT && USB_CFG_HAVE_INTRIN_ENDPOINT3
handleIn3:
    lds     cnt, usbTxLen3      ;[43]
    sbrc    cnt, 4              ;[45]
    rjmp    sendCntAndReti      ;[46] 48 + 16 = 64 until SOP
    sts     usbTxLen3, x1       ;[47] x1 == USBPID_NAK from above
    ldi     YL, lo8(usbTxBuf3)  ;[49]
    ldi     YH, hi8(usbTxBuf3)  ;[50]
    rjmp    usbSendAndReti      ;[51] 53 + 12 = 65 until SOP
#endif

;Setup and Out are followed by a data packet two bit times (16 cycles) after
;the end of SE0. The sync code allows up to 40 cycles delay from the start of
;the sync pattern until the first bit is sampled. That's a total of 56 cycles.
handleSetupOrOut:               ;[34]
#if USB_CFG_IMPLEMENT_FN_WRITEOUT   /* if we have data for second OUT endpoint, set usbCurrentTok to -1 */
    sbrc    x3, 7               ;[34] skip if endpoint 0
    ldi     token, -1           ;[35] indicate that this is endpoint 1 OUT
#endif
    sts     usbCurrentTok, token;[36]
    pop     cnt                 ;[38]
    pop     x4                  ;[40]
    pop     x3                  ;[42]
    pop     x2                  ;[44]
    pop     x1                  ;[46]
    pop     shift               ;[48]
    pop     YH                  ;[50]
    pop     YL                  ;[52]
    in      r0, USB_INTR_PENDING;[54]
    sbrc    r0, USB_INTR_PENDING_BIT;[55] check whether data is already arriving
    rjmp    waitForJ            ;[56] save the pops and pushes -- a new interrupt is aready pending
    rjmp    sofError            ;[57] not an error, but it does the pops and reti we want


handleData:
    lds     token, usbCurrentTok;[20]
    tst     token               ;[22]
    breq    doReturn            ;[23]
    lds     x2, usbRxLen        ;[24]
    tst     x2                  ;[26]
    brne    sendNakAndReti      ;[27]
; 2006-03-11: The following two lines fix a problem where the device was not
; recognized if usbPoll() was called less frequently than once every 4 ms.
    cpi     cnt, 4              ;[28] zero sized data packets are status phase only -- ignore and ack
    brmi    sendAckAndReti      ;[29] keep rx buffer clean -- we must not NAK next SETUP
    sts     usbRxLen, cnt       ;[30] store received data, swap buffers
    sts     usbRxToken, token   ;[32]
    lds     x2, usbInputBufOffset;[34] swap buffers
    ldi     cnt, USB_BUFSIZE    ;[36]
    sub     cnt, x2             ;[37]
    sts     usbInputBufOffset, cnt;[38] buffers now swapped
    rjmp    sendAckAndReti      ;[40] 42 + 17 = 59 until SOP

handleIn:
;We don't send any data as long as the C code has not processed the current
;input data and potentially updated the output data. That's more efficient
;in terms of code size than clearing the tx buffers when a packet is received.
    lds     x1, usbRxLen        ;[30]
    cpi     x1, 1               ;[32] negative values are flow control, 0 means "buffer free"
    brge    sendNakAndReti      ;[33] unprocessed input packet?
    ldi     x1, USBPID_NAK      ;[34] prepare value for usbTxLen
#if USB_CFG_HAVE_INTRIN_ENDPOINT
    sbrc    x3, 7               ;[35] x3 contains addr + endpoint
    rjmp    handleIn1           ;[36]
#endif
    lds     cnt, usbTxLen       ;[37]
    sbrc    cnt, 4              ;[39] all handshake tokens have bit 4 set
    rjmp    sendCntAndReti      ;[40] 42 + 16 = 58 until SOP
    sts     usbTxLen, x1        ;[41] x1 == USBPID_NAK from above
    ldi     YL, lo8(usbTxBuf)   ;[43]
    ldi     YH, hi8(usbTxBuf)   ;[44]
    rjmp    usbSendAndReti      ;[45] 47 + 12 = 59 until SOP

; Comment about when to set usbTxLen to USBPID_NAK:
; We should set it back when we receive the ACK from the host. This would
; be simple to implement: One static variable which stores whether the last
; tx was for endpoint 0 or 1 and a compare in the receiver to distinguish the
; ACK. However, we set it back immediately when we send the package,
; assuming that no error occurs and the host sends an ACK. We save one byte
; RAM this way and avoid potential problems with endless retries. The rest of
; the driver assumes error-free transfers anyway.

#if USB_CFG_HAVE_INTRIN_ENDPOINT    /* placed here due to relative jump range */
handleIn1:                      ;[38]
#if USB_CFG_HAVE_INTRIN_ENDPOINT3
; 2006-06-10 as suggested by O.Tamura: support second INTR IN / BULK IN endpoint
    ldd     x2, y+2             ;[38]
    sbrc    x2, 0               ;[40]
    rjmp    handleIn3           ;[41]
#endif
    lds     cnt, usbTxLen1      ;[42]
    sbrc    cnt, 4              ;[44] all handshake tokens have bit 4 set
    rjmp    sendCntAndReti      ;[45] 47 + 16 = 63 until SOP
    sts     usbTxLen1, x1       ;[46] x1 == USBPID_NAK from above
    ldi     YL, lo8(usbTxBuf1)  ;[48]
    ldi     YH, hi8(usbTxBuf1)  ;[49]
    rjmp    usbSendAndReti      ;[50] 52 + 12 + 64 until SOP
#endif


; USB spec says:
; idle = J
; J = (D+ = 0), (D- = 1)
; K = (D+ = 1), (D- = 0)
; Spec allows 7.5 bit times from EOP to SOP for replies

bitstuff7:
    eor     x1, x4          ;[4]
    ldi     x2, 0           ;[5]
    nop2                    ;[6] C is zero (brcc)
    rjmp    didStuff7       ;[8]

bitstuffN:
    eor     x1, x4          ;[5]
    ldi     x2, 0           ;[6]
    lpm                     ;[7] 3 cycle NOP, modifies r0
    out     USBOUT, x1      ;[10] <-- out
    rjmp    didStuffN       ;[0]

#define bitStatus   x3

sendNakAndReti:
    ldi     cnt, USBPID_NAK ;[-19]
    rjmp    sendCntAndReti  ;[-18]
sendAckAndReti:
    ldi     cnt, USBPID_ACK ;[-17]
sendCntAndReti:
    mov     r0, cnt         ;[-16]
    ldi     YL, 0           ;[-15] R0 address is 0
    ldi     YH, 0           ;[-14]
    ldi     cnt, 2          ;[-13]
;   rjmp    usbSendAndReti      fallthrough

;usbSend:
;pointer to data in 'Y'
;number of bytes in 'cnt' -- including sync byte [range 2 ... 12]
;uses: x1...x4, shift, cnt, Y
;Numbers in brackets are time since first bit of sync pattern is sent
usbSendAndReti:             ; 12 cycles until SOP
    in      x2, USBDDR      ;[-12]
    ori     x2, USBMASK     ;[-11]
    sbi     USBOUT, USBMINUS;[-10] prepare idle state; D+ and D- must have been 0 (no pullups)
    in      x1, USBOUT      ;[-8] port mirror for tx loop
    out     USBDDR, x2      ;[-7] <- acquire bus
; need not init x2 (bitstuff history) because sync starts with 0
    ldi     x4, USBMASK     ;[-6] exor mask
    ldi     shift, 0x80     ;[-5] sync byte is first byte sent
    ldi     bitStatus, 0xff ;[-4] init bit loop counter, works for up to 12 bytes
byteloop:
bitloop:
    sbrs    shift, 0        ;[8] [-3]
    eor     x1, x4          ;[9] [-2]
    out     USBOUT, x1      ;[10] [-1] <-- out
    ror     shift           ;[0]
    ror     x2              ;[1]
didStuffN:
    cpi     x2, 0xfc        ;[2]
    brcc    bitstuffN       ;[3]
    nop                     ;[4]
    subi    bitStatus, 37   ;[5] 256 / 7 ~=~ 37
    brcc    bitloop         ;[6] when we leave the loop, bitStatus has almost the initial value
    sbrs    shift, 0        ;[7]
    eor     x1, x4          ;[8]
    ror     shift           ;[9]
didStuff7:
    out     USBOUT, x1      ;[10] <-- out
    ror     x2              ;[0]
    cpi     x2, 0xfc        ;[1]
    brcc    bitstuff7       ;[2]
    ld      shift, y+       ;[3]
    dec     cnt             ;[5]
    brne    byteloop        ;[6]
;make SE0:
    cbr     x1, USBMASK     ;[7] prepare SE0 [spec says EOP may be 21 to 25 cycles]
    lds     x2, usbNewDeviceAddr;[8]
    out     USBOUT, x1      ;[10] <-- out SE0 -- from now 2 bits = 22 cycles until bus idle
;2006-03-06: moved transfer of new address to usbDeviceAddr from C-Code to asm:
;set address only after data packet was sent, not after handshake
    subi    YL, 2           ;[0]
    sbci    YH, 0           ;[1]
    breq    skipAddrAssign  ;[2]
    sts     usbDeviceAddr, x2; if not skipped: SE0 is one cycle longer
skipAddrAssign:
;end of usbDeviceAddress transfer
    ldi     x2, 1<<USB_INTR_PENDING_BIT;[4] int0 occurred during TX -- clear pending flag
    out     USB_INTR_PENDING, x2;[5]
    ori     x1, USBIDLE     ;[6]
    in      x2, USBDDR      ;[7]
    cbr     x2, USBMASK     ;[8] set both pins to input
    mov     x3, x1          ;[9]
    cbr     x3, USBMASK     ;[10] configure no pullup on both pins
    ldi     x4, 4           ;[11]
se0Delay:
    dec     x4              ;[12] [15] [18] [21]
    brne    se0Delay        ;[13] [16] [19] [22]
    out     USBOUT, x1      ;[23] <-- out J (idle) -- end of SE0 (EOP signal)
    out     USBDDR, x2      ;[24] <-- release bus now
    out     USBOUT, x3      ;[25] <-- ensure no pull-up resistors are active
    rjmp    doReturn

