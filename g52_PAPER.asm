#make_bin#

#LOAD_SEGMENT=FFFFh#
#LOAD_OFFSET=0000h#

#CS=0000h#
#IP=0000h#

#DS=0000h#
#ES=0000h#

#SS=0000h#
#SP=FFFEh#

#AX=0000h#
#BX=0000h#
#CX=0000h#
#DX=0000h#
#SI=0000h#
#DI=0000h#
#BP=0000h#
	   
	   ;IO addresses	
		portA	 		equ		00h
		portB	 		equ		02h
		portC	 		equ		04h
		portCtrl 		equ		06h
		
		timr0	 		equ		08h
		timr1	 		equ		0Ah
		timr2	 		equ		0Ch
		timrCtrl 		equ		0Eh
		
		;PB7 connected to LED0 (bottom LED)
		;PC0 - PC7 connected to LEDs 1 to 8
		;PA0 - START pushbutton (active low)
		;PA1 - STOP pushbutton (active low)
		;PB0 - PB6 connected to 74LS760 for driving abcdefg in 7 seg display
		
		;IVT							;bytes 
         jmp     main					;[0,3)
		 db		 5		dup(0)			;[3,8)
		 dw		 every50ms				;[8, 10)   NMI ISR runs every 50ms
		 db		 1014 	dup(0)			;[10, 1024)
		 
		;LOOKUP TABLE					;[1024, 1042)
		;maps 9 common anode LED on/off states to common cathode 7 segment display hex: 0abcdefg 
		 db		 11111111b, 11111110b, 11111100b, 11111000b, 11110000b, 11100000b, 11000000b, 10000000b, 00000000b 	
		 db		 6dh,6dh,66h,66h,4fh,4fh,5bh,5bh,06h
		;db		 06h,5bh,4fh,66h,6dh,7dh,07h,7fh,6fh 
				 ;1   2   3   4   5   6   7   8   9
				 
main:    ;0x0412 (1042th byte) is .bin entry point (Instruction at FFFF0: jmp main)
		  cli 
          mov       ax,0
          mov       ds,ax          
          mov       ss,ax		 
		  mov		es,ax
          mov       sp,01FFFH ;end of RAM 1
		 		  	 		 
		 ;timers as divide-by-N counters
          mov       al,00110100b		
          out       timrCtrl,al 				
          mov       al,01110100b 
          out       timrCtrl,al
		  mov		al,10110100b
		  out		timrCtrl,al

		 ;dividing 2.5 MHz from 8284 PCLK = CLK/2 for 50 ms real time interrupts
		 ;2.5 MHz / (125 * 1000) = 20 Hz --> 50ms 
          mov       al,0E8h				;0x0E38  = 1000	
          out       timr0,al			;2.5 MHz / 1000 = 2500 Hz
		  mov		al,03h
		  out		timr0,al
		 ;timr0's OUT CASCADES into timr1's CLK input
		  mov       al,7Dh				;0x007D  = 125	
          out       timr1,al			;2500 Hz / 125 = 20 Hz --> 50ms interrupts to NMI
		  mov		al,0h
		  out		timr1,al	  
		 ;timr2 holds a random number between [1, 81] 
		  mov		al,51h  ;51h = 81d				 
		  out		timr2,al
		  mov		al,0
		  out		timr2,al

		  mov       al,10010000b		;Port B,C: output, Port A: input
		  out 		portCtrl,al 
		 
		 ;ensures we correctly register 2 distinct button presses of the START button
		 ;(if we're pressing start to reset after score display)
x0:		  in		al,portA
		  and		al,00000001b
		  cmp		al,0
		  jz		x0				    ;polling start button
		  in		al,portA
		  and		al,00000010b
		  cmp		al,0				;polling stop button
		  jz        x0
		  call		dbnc				;20ms delay
     	  in		al,portA
		  and		al,00000001b
		  cmp		al,0
		  jz		x0				    ;polling start button
		  in		al,portA
		  and		al,00000010b
		  cmp		al,0				;polling stop button
		  jz        x0
		  
		 ;proceeds only if all buttons are actually released
		 
		  
		  mov       al,0ffh				;LEDs off (common anode)
		  out       portC,al
		  mov		al, 80h
		  out		portB,al
		  
		  mov       dl,0				;counts 50ms real time interrupts
		  mov		si,0				;ticksDisabled? (flag)
		  mov		di,1024				;lookup table address		  
		  
x1:		  in		al,portA
		  and		al,00000001b
		  cmp		al,0
		  jnz		x1					;polling start button		  
		    
		  
		  mov		dl,0				;RESET WAIT COUNTER
		  mov		al,11011000b		;8254 READ BACK
		  out		timrCtrl,al		    
		  
		  in		al,timr2		  	;read lsb = random number in [1, 81]    
		  mov		dh, al
		  add		dh,79				;[1,81] + 79 --> [80, 160] * 50ms = [4, 8] seconds   
		  in		al,timr2			;read msb=00, and discard
		  
		  
x2:		  in		al,portA
		  and		al,00000010b
		  cmp		al,0
		  jnz       noblink
		  
		  call		blink				;use pressed stop button during wait
		  jmp		x1
		  
noblink:  cmp		dh,dl
		  jnz		x2					;[4,8] second wait loop	  
		  		  	  
		  mov		al,0				;let end of wait be t = 0s
		  out		portB,al			;0th LED tuned on at t = 0s
		  mov		bl,0ffh				;bl reflects LED states, 11111111 = all off
		  
x3:		  in		al,portA
		  and		al,00000010b
		  cmp		al,0				;polling stop button
		  jz		disp
		  
nstp:	  mov		al,bl				;bl shifted left every 50 ms after t = 0s
I1:		  out       portC,al			;LEDS update at t = 50ms, 100ms, 150ms ...
I2:		  cmp       bl,0				;bl = 00000000 means all LEDS on
		  jnz       x3					
		  mov		al,bl				
		  out       portC,al			;covers an edge case where bl might become zero after I1, before I2
		  
disp:	  mov		si,1 				;ticksDisabled, bl doesn't change anymore		  
		  mov		cx,9				;bl is compared to 9 possible states
		  mov		al,bl				;stored in a lookup table
		  repne		scasb
		  add		di, 8
		  mov		al, [di]
		  out		portB, al
		  
		  
		 ;pressing start now clears display and sets up device for another test
x4:		  in		al,portA
		  and		al,00000001b
		  cmp		al,0
		  jnz		x4			        ;polling start button
		  call		dbnc				;20ms delay
		  in		al,portA
		  and		al,00000001b
		  cmp		al,0
		  jnz		x4					;genuine buttonpress?
		;debounce necessary here because we need										
		;to act on 2 distinct button presses of the same button
		;START is checked again after this to start random wait of [4,8]s
		;bounce noise can cause faulty cascade to wrong part of code 
		  jmp 		x0

;NMI ISR
every50ms:cmp si,1
		  jz  notick
		  inc dl
		  shl bl,1
		  
notick:   iret
          
blink:    mov		cx, 5			   ;blink count = 5
		  
b1:		 ;LEDs on
		  mov       al,00h				
		  out       portC,al		  
		  out		portB,al				 
		  call		delay				
		  
		 ;LEDs off 
		  mov       al,0ffh				
		  out       portC,al
		  mov		al, 80h
		  out		portB,al	  
		  call		delay						  
		  
		  loop		b1
		  
		  ret	

;Software delay of approx. .25s
;used for blinking LEDs at 4 Hz
;and delay when user presses start to clear score and reset
;loop cx takes 18 clock periods
delay: 	  push 		cx					;save cx before using it		
		  mov		cx,0FFFFh
d1:		  loop		d1	
		  mov		cx,3909				;65535 + 3909 = 69444
		  pop 		cx					;(69443*18 + 5) / (5 MHz) ~ 0.25s
		  ret

;Software delay of approx. 20ms for debouce
dbnc:     push		cx
     	  push 		cx					;save cx before using it			
		  mov		cx,5556
y1:		  loop		y1					;(5555*18 + 5) / (5 MHz) ~ 0.02s 
		  pop 		cx
		  ret
		  		  