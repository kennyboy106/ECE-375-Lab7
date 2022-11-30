;Plan
;
;
;
;   Configure USART1
;       Turn on receiver?   
;           Receiver is on PD2 - RXD1
;       Turn on transmitter?
;           Transmitters on PD3 - TXD1
;       Frame Format
;           Data Frame          8-bit
;           Stop bit            2 stop bits
;           Parity bit          disable
;           Asynchronous Operation
;           Controlled in:
;               UCSR1A
;               UCSR1B
;               UCSR1C
;       Baud                    2400
;           Controlled in:
;               UBRR1H
;               UBRR1L
;           Don't write to UBRR1H bits 15:12 (last 4 bits) they are reserved
;               Thus we can write 14 bits to it in general
;           Since we are doing double data rate we use the following eq to solve
;               for UBRR
;               UBRR = (f_clk / (8 * baud)) - 1 = 8Mhz / 8 * 2400 - 1 = 415.6667
;           415.666 == 416 -> $01A0
;           ldi  mpr, $A0
;           sts  UBRRL, mpr
;           lds  mpr, UBRRH
;           ori  mpr, 0b0000_0001
;           sts  UBRRH, mpr
;
;       Data Register is UDR1
;           To transmit use:
;               sts     UDR1, mpr
;           To relieve use:
;               LDS     mpr, UDR1
;
;       Configure Interrupts
;           UCSR1A
;               dont need to check this 
;               5 Enable UDREI - USART Data register empty
;               
;               1 Enable U2XI  - Double the USART transmission speed
;               0b0000_0010


;           UCSR1B
;               7 Enable RXCIE - Receive Complete Interrupt
;               4 Enable RXEN  - Receiver Enable
;               3 Enable TXEN  - Transmitter Enable
;               2 Set    UCSZ  - Character Size bit 3 of 3
;                   8-bit = 011
;               0b1001_1000

;           UCSR1C
;               7 Set UMSEL1   - USART Mode Select
;               6 Set UMSEL1   - USART Mode Select
;                   Asynch = 00
;               5 Set UPM1     - Parity Mode
;               4 Set UPM1     - Parity Mode
;                   Disabled = 00
;               3 Set USBS1    - Stop Bit Select
;                   2-bits = 1
;               2 Set UCSZ     - Character Size bit 2 of 3
;               1 Set UCSZ     - Character Size bit 1 of 3
;               0 Set UCPOL1   - Clock Polarity
;                   Falling XCKn Edge = 0
;               0b0000_1110

;
;
;
;   LCD Display
;       Need to display current 
;
;
;
;   Buttons
;       PD7 - Start/Ready
;       PD4 - Cycle gestures
;       PB7:4 - countdown timer
;           Need to use like a descending order kinda thing
;       PB3:0 - Used by LCDDriver so no touchy touchy
;
;   Wires
;       Connect as follows:
;       Board 1     Board 2
;       PD2         PD3
;       PD3         PD2
;       GND         GND
;
;
;
;   Game flow
;       Starting the game
;           We need to send a start code to the other board
;               Start can be    0b1000_0000
;           This needs to start the countdown for both boards
;
;
;       Comparing gestures
;           We want to have codes for what each selection is:
;               Rock can be     0b0000_0000
;               Scissors can be 0b0000_0001
;               Paper can be    0b0000_0010
;                               0b0000_0011
;           On the users board show on the LCD what they have selected
;           by using a word or letter - both are equally easy
;           
;           Once the timer is at 0 we send the gesture code to the other board
;           and compare to the current gesture on te board
;               If a board compares and determines it loses/wins, print status
;               on the LCD
;           *Make sure to enable global interrupts again when needed*
;           
;       Code Flow
;           Main function should do nothing at all
;           To start we press the start button, this goes to interrupt xxxx:
;               >Send the start code via USART to other board
;               >Display the ready msg on the screen until the other board send the ready
;               When receiving the ready msg, start counters
;               Display user choice on the second line
;               Load rock into data variable
;               Enable interrupt so the user can press another button to change option
;               Cycle through options when user presses button
;               When counter ends, send the selection variable to other board
;               receive selection from other board
;               display opponents choice on the first line
;               start the counters again
;               after counter ends display winner or loser
;               start counters again
;               after counter ends display welcome msg again
;
;

;
;
;
;
;
;
;
;
;

;***********************************************************
;*
;*   Author: Kenneth Tang
;*           Travis Fredrickson
;*     Date: 11/19/2022
;*
;***********************************************************

.include "m32U4def.inc"         ; Include definition file

;***********************************************************
;*  Internal Register Definitions and Constants
;***********************************************************
.def    mpr = r16               ; Multi-Purpose Register
.def    waitcnt = r17           ; Wait Loop Counter
.def    ilcnt = r18
.def    olcnt = r19

.equ    WTime = 15             ; Time to wait in wait loop

.equ    SIGNAL_READY        = 0b1111_1111   ; Signal for ready to start game
.equ    SIGNAL_NOT_READY    = 0b0000_0000   ; Signal for not ready to start game
.equ    SIGNAL_ROCK         = 0b0000_0001   ; Signal for Rock
.equ    SIGNAL_PAPER        = 0b0000_0010   ; Signal for Paper
.equ    SIGNAL_SCISSORS     = 0b0000_0011   ; Signal for Scissors

;***********************************************************
;*  Start of Code Segment
;***********************************************************
.cseg                           ; Beginning of code segment

;***********************************************************
;*  Interrupt Vectors
;***********************************************************
.org    $0000                   ; Beginning of IVs
        rjmp INIT            ; Reset interrupt


.org    $0002                   ; INT0  Cycle through selection
        rcall CYCLE_HAND
        reti

.org    $0004                   ; INT1 Send Start Msg
        rcall NEXT_GAME_STAGE
        reti

.org    $0028                   ; Timer/Counter 1 Overflow
        rcall TIMER
        reti

.org    $0032                   ; USART1 Rx Complete
        rcall MESSAGE_RECEIVE
        reti

.org    $0034                   ; USART Data Register Empty
        reti

.org    $0036                   ; USART1 Tx Complete
        rcall READY_CHECK
        reti



.org    $0056                   ; End of Interrupt Vectors

;***********************************************************
;*  Program Initialization
;***********************************************************
INIT:
    ; Initialize the Stack Pointer
    ldi     mpr, high(RAMEND)
    out     SPH, mpr
    ldi     mpr, low(RAMEND)
    out     SPL, mpr

    ; I/O Ports
    ldi     mpr, (1<<PD3 | 0b0000_0000) ; Set Port D pin 3 (TXD1) for output
    out     DDRD, mpr                   ; Set Port D pin 2 (RXD1) for input
    ldi     mpr, $FF                    ; Enable pull up resistors
    out     PORTD, mpr

    ; Configure PORTB for output
    ldi     mpr, $FF
    out     DDRB, mpr
    ldi     mpr, $00
    out     PORTB, mpr

    ; USART1 Config
    ; Set double data rate
    ldi     mpr, (1<<U2X1)
    sts     UCSR1A, mpr
    ; Set recieve & transmit complete interrupts, transmitter & reciever enable, 8 data bits frame formate
    ldi     mpr, (1<<RXCIE1 | 1<<TXCIE1 | 0<<UDRIE1 | 1<<RXEN1 | 1<<TXEN1 | 0<<UCSZ12)
    sts     UCSR1B, mpr
    ; Set frame formate: 8 data bits, 2 stop bits, asnych, no parity
    ldi     mpr, (0<<UMSEL11 | 0<<UMSEL10 | 0<<UPM11 | 0<<UPM10 | 1<<USBS1 | 1<<UCSZ11 | 1<<UCSZ10 | 0<<UCPOL1)
    sts     UCSR1C, mpr
    ; Baud to 2400 @ double data rate
    ldi     mpr, high(416)
    sts     UBRR1H, mpr
    ldi     mpr, low(416)
    sts     UBRR1L, mpr
    
    ; Timer/Counter 1
    ; Setup for normal mode WGM 0000
    ; COM disconnected 00
    ; Use OCR1A for top value
    ; CS TBD, using 100
    ldi     mpr, (0<<COM1A1 | 0<<COM1A0 | 0<<COM1B1 | 0<<COM1B0 | 0<<WGM11 | 0<<WGM10)
    sts     TCCR1A, mpr
    ldi     mpr, (0<<WGM13 | 0<<WGM12 | 1<<CS12 | 0<<CS11 | 0<<CS10)
    sts     TCCR1B, mpr
    
    ; LED Initialization
    call    LCDInit                         ; Initialize LCD
    call    LCDBacklightOn
    ldi     ZH, high(STRING_IDLE<<1)        ; Point Z to the welcome string
    ldi     ZL, low(STRING_IDLE<<1)
    call    LCD_ALL                         ; Print welcome message

    ; Data Memory Variables
        ; TIMER_STAGE
    ldi     mpr, 4
    ldi     XH, high(TIMER_STAGE)
    ldi     XL, low(TIMER_STAGE)
    st      X, mpr

        ; GAME_STAGE
    ldi     mpr, 0
    ldi     XH, high(GAME_STAGE)
    ldi     XL, low(GAME_STAGE)
    st      X, mpr

        ; HANDs
    ldi     mpr, SIGNAL_ROCK    ; Default hand
    ldi     XH, high(HAND_OPNT)
    ldi     XL, low(HAND_OPNT)
    st      X, mpr
    ldi     XH, high(HAND_USER)
    ldi     XL, low(HAND_USER)
    st      X, mpr

        ; READY Flags
    ldi     mpr, SIGNAL_NOT_READY
    ldi     XH, high(READY_OPNT)
    ldi     XL, low(READY_OPNT)
    st      X, mpr
    ldi     XH, high(READY_USER)
    ldi     XL, low(READY_USER)
    st      X, mpr

   

    ; External Interrupts
    ; Initialize external interrupts
    ldi     mpr, 0b0000_1010            ; Set INT1, INT0 to trigger on 
    sts     EICRA, mpr                  ; falling edge

    ; Configure the External Interrupt Mask
    ldi     mpr, (0<<INT1 | 0<<INT0)    ; Disable INT1 and INT0 for now
    out     EIMSK, mpr

    rcall   NEXT_GAME_STAGE


    ; Enable global interrupts
    sei


;***********************************************************
;*  Main Program
;***********************************************************
MAIN:

        rjmp    MAIN


;***********************************************************
;*  Functions and Subroutines
;***********************************************************
; Printing functions ----------------
LCD_ALL:
    ;-----------------------------------------------------------
    ; Func: LCD All
    ; Desc: Prints a string to the entire LCD
    ;       Assumes Z already points to string.
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    ilcnt
    push    XH
    push    XL

    ; Set parameters
    ldi     XH, $01                     ; Point X to LCD top line
    ldi     XL, $00                     ; ^
    ldi     ilcnt, 32                   ; Loop 32 times for 32 characters

 LCD_ALL_LOOP:
    ; Load in characters
    lpm     mpr, Z+
    st      X+, mpr
    dec     ilcnt
    brne    LCD_ALL_LOOP

    ; Write to LCD
    call    LCDWrite

    ; Restore variables
    pop     XL
    pop     XH
    pop     ilcnt
    pop     mpr

    ; Return from function
    ret

LCD_TOP:
    ;-----------------------------------------------------------
    ; Func: LCD Top
    ; Desc: Prints a string to the top row of the LCD
    ;       Assumes Z already points to string.
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    ilcnt
    push    XH
    push    XL

    ; Set parameters
    ldi     XH, $01                     ; Point X to LCD top line
    ldi     XL, $00                     ; ^
    ldi     ilcnt, 16                   ; Loop 16 times for 16 characters

 LCD_TOP_LOOP:
    ; Load in characters
    lpm     mpr, Z+
    st      X+, mpr
    dec     ilcnt
    brne    LCD_TOP_LOOP

    ; Write to LCD
    call    LCDWrite

    ; Restore variables
    pop     XL
    pop     XH
    pop     ilcnt
    pop     mpr

    ; Return from function
    ret
    
LCD_BOTTOM:
    ;-----------------------------------------------------------
    ; Func: LCD Bottom
    ; Desc: Prints a string to the bottom row of the LCD
    ;       Assumes Z already points to string.
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    ilcnt
    push    XH
    push    XL

    ; Set parameters
    ldi     XH, $01                     ; Point X to LCD bottom line
    ldi     XL, $10                     ; ^
    ldi     ilcnt, 16                   ; Loop 16 times for 16 characters

 LCD_BOTTOM_LOOP:
    ; Load in characters
    lpm     mpr, Z+
    st      X+, mpr
    dec     ilcnt
    brne    LCD_BOTTOM_LOOP

    ; Write to LCD
    call    LCDWrite

    ; Restore variables
    pop     XL
    pop     XH
    pop     ilcnt
    pop     mpr

    ; Return from function
    ret


; USART -----------------------------
MESSAGE_RECEIVE:
    ;----------------------------------------------------------------
    ; Sub:  Message Receive
    ; Desc: After receiving data, this function decides what to do with it
    ;       It performs checks on it to see what was sent in then branches
    ;       to the appropriate function.
    ;----------------------------------------------------------------
    push mpr
    push ZH
    push ZL
    push olcnt
    cli                             ; Turn interrupts off
    
    ;--------- Read message in UDR1 -----------;
    lds     mpr, UDR1               ; Read the incoming data
    ldi     olcnt, SIGNAL_READY     ; Check to see if msg is SIGNAL_READY 
    cpse    mpr, olcnt
    rjmp    MR_R2                   ; Skipped if equal
    call    RECEIVE_START           ; Go to receive start
    rjmp    MR_R5

 MR_R2:
    ldi     olcnt, SIGNAL_ROCK      ; Check to see if msg is ROCK
    cpse    mpr, olcnt
    rjmp    MR_R3
    call    STORE_HAND
    rjmp    MR_R5
 MR_R3:
    ldi     olcnt, SIGNAL_PAPER     ; Check to see if msg is PAPER
    cpse    mpr, olcnt
    rjmp    MR_R4
    call    STORE_HAND
    rjmp    MR_R5
 MR_R4:
    ldi     olcnt, SIGNAL_PAPER     ; Check to see if msg is SCISSOR
    cpse    mpr, olcnt
    rjmp    MR_R5
    call    STORE_HAND
    rjmp    MR_R5
 MR_R5:


    sei                             ; Turn interrupts back on
    pop olcnt
    pop ZL
    pop ZH
    pop mpr
    ret

READY_CHECK:
    ;----------------------------------------------------------------
    ; Sub:  Transmit Check
    ; Desc: Does a status check after a message has been transmitter on USART1
    ;----------------------------------------------------------------
    push mpr
    push ilcnt
    push ZH
    push ZL
    push XH
    push XL

    ;--------- Check to see if we should start the game ----------------;
    ldi     ZH, high(READY_USER)            ; Load both ready flags
    ldi     ZL, low(READY_USER)
    ld      mpr, Z
    ldi     XH, high(READY_OPNT)
    ldi     XL, low(READY_OPNT)
    ld      ilcnt, X
    cpi     mpr, SIGNAL_READY
    brne    TC_END                          ; If they aren't equal jump to end
    cpi     ilcnt, SIGNAL_READY
    brne    TC_END                          ; If they aren't equal jump to end

    ldi     mpr, SIGNAL_NOT_READY           ; Change ready flags
    st      Z, mpr
    st      X, mpr
    rcall   NEXT_GAME_STAGE                 ; If both flags are ready, advance game
    
 TC_END:
    ; Other checks
    pop XL
    pop XH
    pop ZL
    pop ZH
    pop ilcnt
    pop mpr
    ret

SEND_READY:
    ; Here we need to send a message via USART
    push mpr
    push waitcnt
    push ZH
    push ZL


    ldi     ZH, high(READY_USER)        ; Load the ready flag
    ldi     ZL, low(READY_USER)
    ldi     mpr, SIGNAL_READY
    st      Z, mpr                      ; Store a 1 to the ready flag

    ;-------------- Transmit via USART ----------;
 Ready_Transmit:
    lds     mpr, UCSR1A                 ; Load in USART status register
    sbrs    mpr, UDRE1                  ; Check the UDRE1 flag
    rjmp    Ready_Transmit              ; Loop back until data register is empty

    ldi     mpr, SIGNAL_READY              ; Send the start message to the other board
    sts     UDR1, mpr

    ; Clear the queue
    rcall   BUSY_WAIT               ; Wait to clear queue
    ldi     mpr, 0b0000_0011        ; Clear interrupts
    out     EIFR, mpr

    pop ZL
    pop ZH
    pop waitcnt
    pop mpr
    ret

RECEIVE_START:
    push mpr
    push ZH
    push ZL

    ldi     mpr, SIGNAL_READY                      ; Change opponents ready flag to 1
    ldi     ZH, high(READY_OPNT)
    ldi     ZL, low(READY_OPNT)
    st      Z, mpr
    call    READY_CHECK              ; Check to see if we should start

    pop ZL
    pop ZH
    pop mpr
    ret

SEND_HAND:
    push mpr
    push ZH
    push ZL

 Hand_Transmit:
    ; See if the USART data register is empty
    lds     mpr, UCSR1A     ; UDRE1 will be 1 when buffer is empty
    sbrs    mpr, UDRE1      ; Test only the 5th bit
    rjmp    Hand_Transmit

    ldi     ZH, high(HAND_USER)     ; Load the user's hand
    ldi     ZL, low(HAND_USER)      
    ld      mpr, Z 
    sts     UDR1, mpr               ; Send user's hand via USART1

    pop ZL
    pop ZH
    pop mpr
    ret

; Core game -------------------------
NEXT_GAME_STAGE:
    ;-----------------------------------------------------------
    ; Func: 
    ; Desc: This is essentially the core function of the game.
    ;       Game stages change as follows:
    ;           0 -> 1      0 = IDLE
    ;           1 -> 2      1 = READY UP
    ;           2 -> 3      2 = SELECT HAND
    ;           3 -> 4      3 = REVEAL HANDS
    ;           4 -> 0      4 = RESULT
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    XH
    push    XL

    ; Branch based on current Game Stage
    ldi     XH, high(GAME_STAGE)
    ldi     XL, low(GAME_STAGE)
    ld      mpr, X

    cpi     mpr, 0
    breq    NEXT_GAME_STAGE_0
    cpi     mpr, 1
    breq    NEXT_GAME_STAGE_1
    cpi     mpr, 2
    breq    NEXT_GAME_STAGE_2
    cpi     mpr, 3
    breq    NEXT_GAME_STAGE_3
    cpi     mpr, 4
    breq    NEXT_GAME_STAGE_4
    cpi     mpr, 5
    breq    NEXT_GAME_STAGE_5

    ; If no compare match, branch to end
    rjmp    NEXT_GAME_STAGE_END

 NEXT_GAME_STAGE_0:                     ; IDLE
    rcall   GAME_STAGE_0                ; Do stuff for this stage
    ldi     mpr, 1                      ; Update GAME_STAGE
    st      X, mpr                      ; ^
    ldi     mpr, (1<<INT1)              ; Enable INT1 (PD7) so it can start the game again
    out     EIMSK, mpr                  ; ^
    rjmp    NEXT_GAME_STAGE_END         ; Jump to end

 NEXT_GAME_STAGE_1:                     ; READY UP
    ldi     mpr, (0<<INT1)              ; Disable INT1 (PD7) because it's only use was to start the game
    out     EIMSK, mpr                  ; ^
    rcall   GAME_STAGE_1                ; Do stuff for this stage
    ldi     mpr, 2                      ; Update GAME_STAGE
    st      X, mpr                      ; ^
    rjmp    NEXT_GAME_STAGE_END         ; Jump to end
    
 NEXT_GAME_STAGE_2:                     ; CHOOSE HAND
    rcall   GAME_STAGE_2                ; Do stuff for this stage
    ldi     mpr, 3                      ; Update GAME_STAGE
    st      X, mpr                      ; ^
    ldi     mpr, (1<<INT0)              ; Enable INT0 so hand can be changed
    out     EIMSK, mpr                  ; ^
    rjmp    NEXT_GAME_STAGE_END         ; Jump to end

 NEXT_GAME_STAGE_3:
    ldi     mpr, (0<<INT0)              ; Disable INT0 so hand cannot be changed
    out     EIMSK, mpr                  ; ^
    ; Send user hand to USART
    call    SEND_HAND
    ; Recieve hand USART
    ; Taken care of by receive complete interrupt
    ldi     mpr, 4                      ; Update GAME_STAGE
    st      X, mpr                      ; ^

 NEXT_GAME_STAGE_4:                     ; REVEAL HANDS
    rcall   GAME_STAGE_4                ; Do stuff for this stage
    ldi     mpr, 5                      ; Update GAME_STAGE
    st      X, mpr                      ; ^
    rjmp    NEXT_GAME_STAGE_END         ; Jump to end

 NEXT_GAME_STAGE_5:                     ; RESULT
    rcall   GAME_STAGE_5                ; Do stuff for this stage
    ldi     mpr, 0                      ; Update GAME_STAGE, so it wraps around and next time it begins at the start
    st      X, mpr                      ; ^
    rjmp    NEXT_GAME_STAGE_END         ; Jump to end

 NEXT_GAME_STAGE_END:
    ; Clear interrupt queue
    rcall   BUSY_WAIT
    ldi     mpr, 0b1111_1111
    out     EIFR, mpr

    ; Restore variables
    pop     XL
    pop     XH
    pop     mpr

    ; Return from function
    ret

GAME_STAGE_0:
    ;-----------------------------------------------------------
    ; Func: 
    ; Desc: GAME_STAGE_0 = IDLE
    ;-----------------------------------------------------------
    ; Save variables
    push    ZH
    push    ZL

    ; Print to LCD
    ldi     ZH, high(STRING_IDLE<<1)
    ldi     ZL, low(STRING_IDLE<<1)
    rcall   LCD_ALL

    ; Restore variables
    pop     ZL
    pop     ZH

    ; Return from function
    ret

GAME_STAGE_1:
    ;-----------------------------------------------------------
    ; Func: 
    ; Desc: GAME_STAGE_1 = READY UP
    ;-----------------------------------------------------------
    ; Save variables
    push    ZH
    push    ZL

    ; Print to LCD
    ldi     ZH, high(STRING_READY_UP<<1)
    ldi     ZL, low(STRING_READY_UP<<1)
    rcall   LCD_ALL

    ; Send ready message to other board
    rcall   SEND_READY

    ; Restore variables
    pop     ZL
    pop     ZH

    ; Return from function
    ret

GAME_STAGE_2:
    ;-----------------------------------------------------------
    ; Func: 
    ; Desc: GAME_STAGE_2 = CHOOSE HAND
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    XH
    push    XL
    push    ZH
    push    ZL

    ; Start 6 second timer
    rcall   TIMER

    ; Print to LCD
    ldi     ZH, high(STRING_CHOOSE_HAND<<1)
    ldi     ZL, low(STRING_CHOOSE_HAND<<1)
    rcall   LCD_TOP

    ; Load in HAND_USER
    ldi     XH, high(HAND_USER)
    ldi     XL, low(HAND_USER)
    ld      mpr, X

    ; Display default hand
    cpi     mpr, SIGNAL_ROCK
    breq    GAME_STAGE_2_ROCK
    cpi     mpr, SIGNAL_PAPER
    breq    GAME_STAGE_2_PAPER
    cpi     mpr, SIGNAL_SCISSORS
    breq    GAME_STAGE_2_SCISSORS

    ; If no compare match, jump to end
    rjmp    GAME_STAGE_2_END

 GAME_STAGE_2_ROCK:                         ; Change to ROCK
    ; Change Data Memory variable HAND_USER
    ldi     mpr, SIGNAL_ROCK
    st      X, mpr

    ; Print to LCD
    ldi     ZH, high(STRING_ROCK<<1)        ; Point Z to string
    ldi     ZL, low(STRING_ROCK<<1)         ; ^
    rcall   LCD_BOTTOM

    ; Jump to end
    rjmp    GAME_STAGE_2_END

 GAME_STAGE_2_PAPER:                            ; Change to PAPER
    ; Change Data Memory variable HAND_USER
    ldi     mpr, SIGNAL_PAPER
    st      X, mpr

    ; Print to LCD
    ldi     ZH, high(STRING_PAPER<<1)       ; Point Z to string
    ldi     ZL, low(STRING_PAPER<<1)        ; ^
    rcall   LCD_BOTTOM

    ; Jump to end
    rjmp    GAME_STAGE_2_END

 GAME_STAGE_2_SCISSORS:                     ; Change to SCISSORS
    ; Change Data Memory variable HAND_USER
    ldi     mpr, SIGNAL_SCISSORS
    st      X, mpr

    ; Print to LCD
    ldi     ZH, high(STRING_SCISSORS<<1)    ; Point Z to string
    ldi     ZL, low(STRING_SCISSORS<<1)     ; ^
    rcall   LCD_BOTTOM

    ; Jump to end
    rjmp    GAME_STAGE_2_END

 GAME_STAGE_2_END:
    ; Restore variables
    pop     ZL
    pop     ZH
    pop     XL
    pop     XH
    pop     mpr

    ; Return from function
    ret

GAME_STAGE_4:
    ;-----------------------------------------------------------
    ; Func: 
    ; Desc: GAME_STAGE_4 = REVEAL HANDS
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    XH
    push    XL
    push    ZH
    push    ZL

    ; Start 6 second timer
    rcall   TIMER
    
    ; Branch based on Opponent Hand
    ldi     XH, high(HAND_OPNT)
    ldi     XL, low(HAND_OPNT)
    ld      mpr, X
    
    cpi     mpr, 1
    breq    GAME_STAGE_4_ROCK
    cpi     mpr, 2
    breq    GAME_STAGE_4_PAPER
    cpi     mpr, 3
    breq    GAME_STAGE_4_SCISSORS

    ; If no compare match, branch to end
    rjmp    GAME_STAGE_4_END

 GAME_STAGE_4_ROCK:
    ; Print to LCD
    ldi     ZH, high(STRING_ROCK<<1)
    ldi     ZL, low(STRING_ROCK<<1)
    rcall   LCD_TOP

    ; Jump to end
    rjmp    GAME_STAGE_4_END

 GAME_STAGE_4_PAPER:
    ; Print to LCD
    ldi     ZH, high(STRING_PAPER<<1)
    ldi     ZL, low(STRING_PAPER<<1)
    rcall   LCD_TOP

    ; Jump to end
    rjmp    GAME_STAGE_4_END

 GAME_STAGE_4_SCISSORS:
    ; Print to LCD
    ldi     ZH, high(STRING_SCISSORS<<1)
    ldi     ZL, low(STRING_SCISSORS<<1)
    rcall   LCD_TOP

    ; Jump to end
    rjmp    GAME_STAGE_4_END

 GAME_STAGE_4_END:
    ; Restore variables
    pop     ZL
    pop     ZH
    pop     XL
    pop     XH
    pop     mpr

    ; Return from function
    ret

GAME_STAGE_5:
    ;-----------------------------------------------------------
    ; Func: 
    ; Desc: GAME_STAGE_5 = RESULT
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    ilcnt
    push    XH
    push    XL
    push    ZH
    push    ZL

    ; Start 6 second timer
    rcall   TIMER

    ; Decide Won/Lost/Draw
        ; Calculate result value
            ; Won   = -2, 1
            ; Lost  = -1, 2
            ; Draw  = 0
    ldi     XH, high(HAND_USER)
    ldi     XL, low(HAND_USER)
    ld      mpr, X
    ldi     XH, high(HAND_OPNT)
    ldi     XL, low(HAND_OPNT)
    ld      ilcnt, X
    sub     mpr, ilcnt              ; Result value stored in mpr

    ; Branch based on result
    cpi     mpr, -2
    breq    GAME_STAGE_5_WON
    cpi     mpr, 1
    breq    GAME_STAGE_5_WON
    cpi     mpr, -1
    breq    GAME_STAGE_5_LOST
    cpi     mpr, 2
    breq    GAME_STAGE_5_LOST
    cpi     mpr, 0
    breq    GAME_STAGE_5_DRAW

    ; If no compare match, jump to end
    rjmp    GAME_STAGE_5_END

 GAME_STAGE_5_WON:
    ; Print to LCD
    ldi     ZH, high(STRING_WON<<1)
    ldi     ZL, low(STRING_WON<<1)
    rcall   LCD_TOP

    ; Jump to end
    rjmp    GAME_STAGE_5_END

 GAME_STAGE_5_LOST:
    ; Print to LCD
    ldi     ZH, high(STRING_LOST<<1)
    ldi     ZL, low(STRING_LOST<<1)
    rcall   LCD_TOP

    ; Jump to end
    rjmp    GAME_STAGE_5_END

 GAME_STAGE_5_DRAW:
    ; Print to LCD
    ldi     ZH, high(STRING_DRAW<<1)
    ldi     ZL, low(STRING_DRAW<<1)
    rcall   LCD_TOP

    ; Jump to end
    rjmp    GAME_STAGE_5_END

 GAME_STAGE_5_END:
    ; Restore variables
    pop     ZL
    pop     ZH
    pop     XL
    pop     XH
    pop     ilcnt
    pop     mpr

    ; Return from function
    ret

STORE_HAND:
    ;-----------------------------------------------------------
    ; Func: Store hand
    ; Desc: Stores the incoming opponents hand to HAND_OPNT
    ;-----------------------------------------------------------
    push mpr
    push ZH
    push ZL

    ldi     ZH, high(HAND_OPNT)     ; mpr currently holds OPNT hand
    ldi     ZL, low(HAND_OPNT)
    st      Z, mpr                  ; Store the hand received
    call    NEXT_GAME_STAGE         ; Advance once we receive the hand

    pop ZL
    pop ZH
    pop mpr
    ret 

CYCLE_HAND:
    ;-----------------------------------------------------------
    ; Func: 
    ; Desc:
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    XH
    push    XL
    push    ZH
    push    ZL

    ; Load in HAND_USER
    ldi     XH, high(HAND_USER)
    ldi     XL, low(HAND_USER)
    ld      mpr, X

    ; Change hand based on current hand
    cpi     mpr, SIGNAL_ROCK
    breq    CYCLE_HAND_PAPER
    cpi     mpr, SIGNAL_PAPER
    breq    CYCLE_HAND_SCISSORS
    cpi     mpr, SIGNAL_SCISSORS
    breq    CYCLE_HAND_ROCK

    ; If no compare match, jump to end
    rjmp    CYCLE_HAND_END

 CYCLE_HAND_ROCK:                           ; Change to ROCK
    ; Change Data Memory variable HAND_USER
    ldi     mpr, SIGNAL_ROCK
    st      X, mpr

    ; Print to LCD
    ldi     ZH, high(STRING_ROCK<<1)        ; Point Z to string
    ldi     ZL, low(STRING_ROCK<<1)         ; ^
    rcall   LCD_BOTTOM

    ; Jump to end
    rjmp    CYCLE_HAND_END

 CYCLE_HAND_PAPER:                          ; Change to PAPER
    ; Change Data Memory variable HAND_USER
    ldi     mpr, SIGNAL_PAPER
    st      X, mpr

    ; Print to LCD
    ldi     ZH, high(STRING_PAPER<<1)       ; Point Z to string
    ldi     ZL, low(STRING_PAPER<<1)        ; ^
    rcall   LCD_BOTTOM

    ; Jump to end
    rjmp    CYCLE_HAND_END

 CYCLE_HAND_SCISSORS:                       ; Change to SCISSORS
    ; Change Data Memory variable HAND_USER
    ldi     mpr, SIGNAL_SCISSORS
    st      X, mpr

    ; Print to LCD
    ldi     ZH, high(STRING_SCISSORS<<1)    ; Point Z to string
    ldi     ZL, low(STRING_SCISSORS<<1)     ; ^
    rcall   LCD_BOTTOM

    ; Jump to end
    rjmp    CYCLE_HAND_END

 CYCLE_HAND_END:
    ; Clear interrupt queue
    rcall   BUSY_WAIT
    ldi     mpr, 0b1111_1111
    out     EIFR, mpr

    ; Restore variables
    pop     ZL
    pop     ZH
    pop     XL
    pop     XH
    pop     mpr

    ; Return from function
    ret

TIMER:
    ;-----------------------------------------------------------
    ; Func: 
    ; Desc: 
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    XH
    push    XL

    ldi     mpr, $48        ; Write to high byte first
    sts     TCNT1H, mpr     ; ^
    ldi     mpr, $E5        ; Write to low byte second
    sts     TCNT1L, mpr     ; ^

    ; Load in TIMER_STAGE
    ldi     XH, high(TIMER_STAGE)
    ldi     XL, low(TIMER_STAGE)
    ld      mpr, X

    ; Branch based on current TIMER_STAGE
    cpi     mpr, 4
    breq    TIMER_4
    cpi     mpr, 3
    breq    TIMER_3
    cpi     mpr, 2
    breq    TIMER_2
    cpi     mpr, 1
    breq    TIMER_1
    cpi     mpr, 0
    breq    TIMER_0

    ; If no compare match, branch to end
    rjmp    TIMER_END

 TIMER_4:                        ; Start timer
    ldi     mpr, (1<<TOIE1)     ; TOIE1 = 1 = Overflow Interrupt Enabled
    sts     TIMSK1, mpr         ; ^
    ldi     mpr, 3              ; Update TIMER_STAGE
    st      X, mpr              ; ^
    in      mpr, PINB           ; Update LEDs
    andi    mpr, 0b0000_1111    ; ^
    ori     mpr, 0b1111_0000    ; ^
    out     PORTB, mpr          ; ^
    rjmp    TIMER_END           ; Jump to end

 TIMER_3:
    ldi     mpr, 2              ; Update TIMER_STAGE
    st      X, mpr              ; ^
    in      mpr, PINB           ; Update LEDs
    andi    mpr, 0b0000_1111    ; ^
    ori     mpr, 0b0111_0000    ; ^
    out     PORTB, mpr          ; ^
    rjmp    TIMER_END           ; Jump to end

 TIMER_2:
    ldi     mpr, 1              ; Update TIMER_STAGE
    st      X, mpr              ; ^
    in      mpr, PINB           ; Update LEDs
    andi    mpr, 0b0000_1111    ; ^
    ori     mpr, 0b0011_0000    ; ^
    out     PORTB, mpr          ; ^
    rjmp    TIMER_END           ; Jump to end

 TIMER_1:
    ldi     mpr, 0              ; Update TIMER_STAGE
    st      X, mpr              ; ^
    in      mpr, PINB           ; Update LEDs
    andi    mpr, 0b0000_1111    ; ^
    ori     mpr, 0b0001_0000    ; ^
    out     PORTB, mpr          ; ^
    rjmp    TIMER_END           ; Jump to end

 TIMER_0:                        ; End timer
    ldi     mpr, (0<<TOIE1)     ; TOIE1 = 0 = Overflow Interrupt Disabled
    sts     TIMSK1, mpr         ; ^
    ldi     mpr, 4              ; Update TIMER_STAGE, so it wraps around and next time it begins at the start
    st      X, mpr              ; ^
    in      mpr, PINB           ; Update LEDs
    andi    mpr, 0b0000_1111    ; ^
    ori     mpr, 0b0000_0000    ; ^
    out     PORTB, mpr          ; ^
    rcall   NEXT_GAME_STAGE     ; Update GAME_STAGE
    rjmp    TIMER_END           ; Jump to end

 TIMER_END:
    ; Restore variables
    pop     XL
    pop     XH
    pop     mpr

    ; Return from function
    ret

BUSY_WAIT:
    ;----------------------------------------------------------------
    ; Func: BUSY_WAIT
    ; Desc: A wait loop that is 16 + 159975*waitcnt cycles or roughly
    ;       mpr*10ms.  Just initialize wait for the specific amount
    ;       of time in 10ms intervals. Here is the general eqaution
    ;       for the number of clock cycles in the wait loop:
    ;       ((3 * ilcnt + 3) * olcnt + 3) * mpr + 13 + call
    ;----------------------------------------------------------------
    ; Save variables
    push    mpr
    push    ilcnt
    push    olcnt
    
    ldi     mpr, 15
 BUSY_WAIT_LOOP:
    ldi     olcnt, 224      ; Load olcnt register
 BUSY_WAIT_OLOOP:
    ldi     ilcnt, 237      ; Load ilcnt register
 BUSY_WAIT_ILOOP:
    dec     ilcnt           ; Decrement ilcnt
    brne    BUSY_WAIT_ILOOP ; Continue Inner Loop
    dec     olcnt           ; Decrement olcnt
    brne    BUSY_WAIT_OLOOP ; Continue Outer Loop
    dec     mpr
    brne    BUSY_WAIT_LOOP

    ; Restore variables
    pop     olcnt
    pop     ilcnt
    pop     mpr

    ; Return from function
    ret

;***********************************************************
;*  Stored Program Data
;***********************************************************
STRING_IDLE:
        .DB "Welcome!        Please press PD7"
STRING_READY_UP:
        .DB "Ready. Waiting  for the opponent"
STRING_CHOOSE_HAND:
        .DB "Choose your hand"
STRING_WON:
        .DB "You Win!        "
STRING_LOST:
        .DB "You Lose!       "
STRING_DRAW:
        .DB "Draw            "
STRING_ROCK:
        .DB "Rock            "
STRING_PAPER:
        .DB "Paper           "
STRING_SCISSORS:
        .DB "Scissor         "

;***********************************************************
;*  Data Memory Allocation
;***********************************************************
.dseg
.org    $0200
TIMER_STAGE:        ; TIMER_STAGE value for timer loop and LED display
    .byte 1
GAME_STAGE:         ; Indicates the current stage the game is in
    .byte 1
HAND_OPNT:          ; Opponent choice: Rock / Paper / Scissors
    .byte 1
HAND_USER:          ; User choice: Rock / Paper / Scissors
    .byte 1
READY_OPNT:         ; Opponent ready
    .byte 1
READY_USER:         ; User ready
    .byte 1

;***********************************************************
;*  Additional Program Includes
;***********************************************************
.include "LCDDriver.asm"

