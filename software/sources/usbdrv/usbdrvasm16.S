/* Name: usbdrvasm16.S
 * Project: AVR USB driver
 * Author: Christian Starkjohann
 * Creation Date: 2007-06-15
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
This file is the 16 MHz version of the asssembler part of the USB driver. It
requires a 16 MHz crystal (not a ceramic resonator and not a calibrated RC
oscillator).

See usbdrv.h for a description of the entire driver.

Since almost all of this code is timing critical, don't change unless you
really know what you are doing! Many parts require not only a maximum number
of CPU cycles, but even an exact number of cycles!
*/

;max stack usage: [ret(2), YL, SREG, YH, bitcnt, shift, x1, x2, x3, x4, cnt] = 12 bytes
;nominal frequency: 16 MHz -> 10.6666666 cycles per bit, 85.333333333 cycles per byte
; Numbers in brackets are clocks counted from center of last sync bit
; when instruction starts

SIG_INTERRUPT0:
;order of registers pushed: YL, SREG YH, [sofError], bitcnt, shift, x1, x2, x3, x4, cnt
    push    YL                  ;[-25] push only what is necessary to sync with edge ASAP
    in      YL, SREG            ;[-23]
    push    YL                  ;[-22]
    push    YH                  ;[-20]
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
    push    bitcnt              ;[-12]
;   [---]                       ;[-11]
    lds     YL, usbInputBufOffset;[-10]
;   [---]                       ;[-9]
    clr     YH                  ;[-8]
    subi    YL, lo8(-(usbRxBuf));[-7] [rx loop init]
    sbci    YH, hi8(-(usbRxBuf));[-6] [rx loop init]
    push    shift               ;[-5]
;   [---]                       ;[-4]
    ldi     bitcnt, 0x55        ;[-3] [rx loop init]
    sbis    USBIN, USBMINUS     ;[-2] we want two bits K (sample 2 cycles too early)
    rjmp    haveTwoBitsK        ;[-1]
    pop     shift               ;[0] undo the push from before
    pop     bitcnt              ;[2] undo the push from before
    rjmp    waitForK            ;[4] this was not the end of sync, retry
; The entire loop from waitForK until rjmp waitForK above must not exceed two
; bit times (= 21 cycles).

;----------------------------------------------------------------------------
; push more registers and initialize values while we sample the first bits:
;----------------------------------------------------------------------------
haveTwoBitsK:
    push    x1              ;[1]
    push    x2              ;[3]
    push    x3              ;[5]
    ldi     shift, 0        ;[7]
    ldi     x3, 1<<4        ;[8] [rx loop init] first sample is inverse bit, compensate that
    push    x4              ;[9] == leap

    in      x1, USBIN       ;[11] <-- sample bit 0
    andi    x1, USBMASK     ;[12]
    bst     x1, USBMINUS    ;[13]
    bld     shift, 7        ;[14]
    push    cnt             ;[15]
    ldi     leap, 0         ;[17] [rx loop init]
    ldi     cnt, USB_BUFSIZE;[18] [rx loop init]
    rjmp    rxbit1          ;[19] arrives at [21]

;----------------------------------------------------------------------------
; Receiver loop (numbers in brackets are cycles within byte after instr)
;----------------------------------------------------------------------------

unstuff6:
    andi    x2, USBMASK ;[03]
    ori     x3, 1<<6    ;[04] will not be shifted any more
    andi    shift, ~0x80;[05]
    mov     x1, x2      ;[06] sampled bit 7 is actually re-sampled bit 6
    subi    leap, 3     ;[07] since this is a short (10 cycle) bit, enforce leap bit
    rjmp    didUnstuff6 ;[08]

unstuff7:
    ori     x3, 1<<7    ;[09] will not be shifted any more
    in      x2, USBIN   ;[00] [10]  re-sample bit 7
    andi    x2, USBMASK ;[01]
    andi    shift, ~0x80;[02]
    subi    leap, 3     ;[03] since this is a short (10 cycle) bit, enforce leap bit
    rjmp    didUnstuff7 ;[04]

unstuffEven:
    ori     x3, 1<<6    ;[09] will be shifted right 6 times for bit 0
    in      x1, USBIN   ;[00] [10]
    andi    shift, ~0x80;[01]
    andi    x1, USBMASK ;[02]
    breq    se0         ;[03]
    subi    leap, 3     ;[04] since this is a short (10 cycle) bit, enforce leap bit
    nop                 ;[05]
    rjmp    didUnstuffE ;[06]

unstuffOdd:
    ori     x3, 1<<5    ;[09] will be shifted right 4 times for bit 1
    in      x2, USBIN   ;[00] [10]
    andi    shift, ~0x80;[01]
    andi    x2, USBMASK ;[02]
    breq    se0         ;[03]
    subi    leap, 3     ;[04] since this is a short (10 cycle) bit, enforce leap bit
    nop                 ;[05]
    rjmp    didUnstuffO ;[06]

rxByteLoop:
    andi    x1, USBMASK ;[03]
    eor     x2, x1      ;[04]
    subi    leap, 1     ;[05]
    brpl    skipLeap    ;[06]
    subi    leap, -3    ;1 one leap cycle every 3rd byte -> 85 + 1/3 cycles per byte
    nop                 ;1
skipLeap:
    subi    x2, 1       ;[08]
    ror     shift       ;[09]
didUnstuff6:
    cpi     shift, 0xfc ;[10]
    in      x2, USBIN   ;[00] [11] <-- sample bit 7
    brcc    unstuff6    ;[01]
    andi    x2, USBMASK ;[02]
    eor     x1, x2      ;[03]
    subi    x1, 1       ;[04]
    ror     shift       ;[05]
didUnstuff7:
    cpi     shift, 0xfc ;[06]
    brcc    unstuff7    ;[07]
    eor     x3, shift   ;[08] reconstruct: x3 is 1 at bit locations we changed, 0 at others
    st      y+, x3      ;[09] store data
rxBitLoop:
    in      x1, USBIN   ;[00] [11] <-- sample bit 0/2/4
    andi    x1, USBMASK ;[01]
    eor     x2, x1      ;[02]
    andi    x3, 0x3f    ;[03] topmost two bits reserved for 6 and 7
    subi    x2, 1       ;[04]
    ror     shift       ;[05]
    cpi     shift, 0xfc ;[06]
    brcc    unstuffEven ;[07]
didUnstuffE:
    lsr     x3          ;[08]
    lsr     x3          ;[09]
rxbit1:
    in      x2, USBIN   ;[00] [10] <-- sample bit 1/3/5
    andi    x2, USBMASK ;[01]
    breq    se0         ;[02]
    eor     x1, x2      ;[03]
    subi    x1, 1       ;[04]
    ror     shift       ;[05]
    cpi     shift, 0xfc ;[06]
    brcc    unstuffOdd  ;[07]
didUnstuffO:
    subi    bitcnt, 0xab;[08] == addi 0x55, 0x55 = 0x100/3
    brcs    rxBitLoop   ;[09]

    subi    cnt, 1      ;[10]
    in      x1, USBIN   ;[00] [11] <-- sample bit 6
    brcc    rxByteLoop  ;[01]
    rjmp    ignorePacket; overflow

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
    pop     bitcnt
sofError:
    pop     YH
    pop     YL
    out     SREG, YL
    pop     YL
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
    pop     bitcnt              ;[50]
    in      YL, USB_INTR_PENDING;[52]
    sbrc    YL, USB_INTR_PENDING_BIT;[53] check whether data is already arriving
    rjmp    waitForJ            ;[54] save the pops and pushes -- a new interrupt is aready pending
    rjmp    sofError            ;[55] not an error, but it does the pops and reti we want


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

bitstuffN:
    eor     x1, x4          ;[5]
    ldi     x2, 0           ;[6]
    nop2                    ;[7]
    nop                     ;[9]
    out     USBOUT, x1      ;[10] <-- out
    rjmp    didStuffN       ;[0]
    
bitstuff6:
    eor     x1, x4          ;[4]
    ldi     x2, 0           ;[5]
    nop2                    ;[6] C is zero (brcc)
    rjmp    didStuff6       ;[8]

bitstuff7:
    eor     x1, x4          ;[3]
    ldi     x2, 0           ;[4]
    rjmp    didStuff7       ;[5]


sendNakAndReti:
    ldi     x3, USBPID_NAK  ;[-18]
    rjmp    sendX3AndReti   ;[-17]
sendAckAndReti:
    ldi     cnt, USBPID_ACK ;[-17]
sendCntAndReti:
    mov     x3, cnt         ;[-16]
sendX3AndReti:
    ldi     YL, 20          ;[-15] x3==r20 address is 20
    ldi     YH, 0           ;[-14]
    ldi     cnt, 2          ;[-13]
;   rjmp    usbSendAndReti      fallthrough

;usbSend:
;pointer to data in 'Y'
;number of bytes in 'cnt' -- including sync byte [range 2 ... 12]
;uses: x1...x4, btcnt, shift, cnt, Y
;Numbers in brackets are time since first bit of sync pattern is sent
;We don't match the transfer rate exactly (don't insert leap cycles every third
;byte) because the spec demands only 1.5% precision anyway.
usbSendAndReti:             ; 12 cycles until SOP
    in      x2, USBDDR      ;[-12]
    ori     x2, USBMASK     ;[-11]
    sbi     USBOUT, USBMINUS;[-10] prepare idle state; D+ and D- must have been 0 (no pullups)
    in      x1, USBOUT      ;[-8] port mirror for tx loop
    out     USBDDR, x2      ;[-7] <- acquire bus
; need not init x2 (bitstuff history) because sync starts with 0
    ldi     x4, USBMASK     ;[-6] exor mask
    ldi     shift, 0x80     ;[-5] sync byte is first byte sent
txByteLoop:
    ldi     bitcnt, 0x2a    ;[-4] [6] binary 00101010
txBitLoop:
    sbrs    shift, 0        ;[-3] [7]
    eor     x1, x4          ;[-2] [8]
    out     USBOUT, x1      ;[-1] [9] <-- out N
    ror     shift           ;[0] [10]
    ror     x2              ;[1]
didStuffN:
    cpi     x2, 0xfc        ;[2]
    brcc    bitstuffN       ;[3]
    lsr     bitcnt          ;[4]
    brcc    txBitLoop       ;[5]
    brne    txBitLoop       ;[6]

    sbrs    shift, 0        ;[7]
    eor     x1, x4          ;[8]
    ror     shift           ;[9]
didStuff6:
    out     USBOUT, x1      ;[-1] [10] <-- out 6
    ror     x2              ;[0] [11]
    cpi     x2, 0xfc        ;[1]
    brcc    bitstuff6       ;[2]
    sbrs    shift, 0        ;[3]
    eor     x1, x4          ;[4]
    ror     shift           ;[5]
    ror     x2              ;[6]
didStuff7:
    nop                     ;[7]
    nop2                    ;[8]
    out     USBOUT, x1      ;[-1][10] <-- out 7
    cpi     x2, 0xfc        ;[0] [11]
    brcc    bitstuff7       ;[1]
    ld      shift, y+       ;[2]
    dec     cnt             ;[4]
    brne    txByteLoop      ;[4]
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

