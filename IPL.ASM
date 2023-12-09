; IPL.MAIN (C)NAMCO extracted from Pac-Man (FDS)
; disassembled using https://www.masswerk.at/6502/disassembler.html
; cleaned up by TakuikaNinja

; constants
IPL_SIZE = $0600

; FDS hardware defines
RST_FLAG = $0102
RST_TYPE = $0103
PPU_CTRL = $2000
PPU_MASK = $2001
PPU_STATUS = $2002
PPU_ADDR = $2006
PPU_DATA = $2007
DMC_RAW  = $4011
JOY1     = $4016
JOY2     = $4017
FDS_DRIVE_STATUS = $4032
NMI_3    = $DFFA
BIOS_LICENSE_TXT = $ED37
BIOS_RESET = $FFFC

; BIOS routine defines
; these are documented in https://nesdev.org/FDS%20technical%20reference.txt
Delayms = $E153
EnPF = $E185
VINTWait = $E1B2
SetNumFiles = $E492
WaitForReady = $E64D
CheckBlockType = $E68F
WriteBlockType = $E6B0
EndOfBlockRead = $E706
EndOfBlockWrite = $E729
CheckDiskSet = $E74C
XferDone = $E778
XferByte = $E7A3
VRAMFill = $EA84
SetScroll = $EAEA

.org $0200
IPL_MAIN:

; VECT.IPL: disk game vector for NMI_3
Vect_NMI_3:
	.dw Bypass

; JUMP.IPL: written to PPU_CTRL followed by PPU_MASK for the license screen bypass
Jump_Data:
	.db $80, $00 ; enable NMIs, disable rendering

; unknown data, may have been reserved for additional vectors/file data
	.db $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $FF, $FF

; file header table
; indexed by Y during the disk access routines
FileHeaderTable:
	.dw Kyodaku
	.dw IPL
	.dw Main
	.dw CHR
	.dw Vect
	.dw Jump
	.dw Namco

; KYODAKU- file header structure
; this dumps the BIOS' license message into a compliant KYODAKU- file (whoops)
Kyodaku:
	.db $00 ; file number
	.db $01 ; file ID
	.db "KYODAKU-" ; file name
	.dw $2800 ; load address
	.dw $00E0 ; file data size
	.db $02 ; file type (nametable)
	.dw BIOS_LICENSE_TXT ; source address (license message in BIOS)
	.db $00 ; source address type (RAM)

; IPL.MAIN file header structure
IPL:
	.db $01 ; file number
	.db $02 ; file ID
	.db "IPL.MAIN" ; file name
	.dw IPL_MAIN ; load address
	.dw IPL_SIZE ; file data size ($0600)
	.db $00 ; file type (PRG)
	.dw IPL_MAIN ; source address (this program)
	.db $00 ; source address type (RAM)

; MAIN.PRG file header structure
Main:
	.db $02 ; file number
	.db $03 ; file ID
	.db "MAIN.PRG" ; file name
	.dw $6000 ; load address
	.dw $8000 ; file data size
	.db $00 ; file type (PRG)
	.dw $6000 ; source address (PRG-RAM)
	.db $00 ; source address type (RAM)

; CHR.FONT file header structure
CHR:
	.db $03 ; file number
	.db $04 ; file ID
	.db "CHR.FONT" ; file name
	.dw $0000 ; load address
	.dw $2000 ; file data size
	.db $01 ; file type (CHR)
	.dw $0000 ; source address (CHR-RAM)
	.db $01 ; source address type (VRAM)

; VECT.IPL file header structure
Vect:
	.db $04 ; file number
	.db $05 ; file ID
	.db "VECT.IPL" ; file name
	.dw NMI_3 ; load address
	.dw $0002 ; file data size
	.db $00 ; file type (PRG)
	.dw Vect_NMI_3 ; source address (start of this program)
	.db $00 ; source address type (RAM)

; JUMP.IPL file header structure
Jump:
	.db $05 ; file number
	.db $06 ; file ID
	.db "JUMP.IPL" ; file name
	.dw PPU_CTRL ; load address
	.dw $0002 ; file data size
	.db $00 ; file type (PRG)
	.dw Jump_Data ; source address (2 bytes into this program)
	.db $00 ; source address type (RAM)

; (C)NAMCO file header structure
; this dumps the pattern tables into a large file
; the BIOS will attempt to seek through this file but will then be interrupted by an NMI
; (this file is still checked by the program, so this probably also discourages bootlegging)
Namco:
	.db $06 ; file number
	.db $40 ; file ID larger than a typical boot file code (i.e. never actually loaded)
	.db "(C)NAMCO" ; file name containing copyright
	.dw $C000 ; load address
	.dw $2000 ; file data size
	.db $00 ; file type (PRG)
	.dw $0000 ; source address (CHR-RAM)
	.db $01 ; source address type (VRAM)

;----------------------

; poll unknown expansion port device
; poll device until $4017 & %00010110 != 0
PollDevice:
		LDA JOY2
		AND #$16 ; %00010110
		BEQ PollDevice

; then poll device until $4017 & #00010110 == 0
; this likely aligns the device's output to either d1, d2, or d4
AlignLoop:
		LDA JOY2
		AND #$16 ; %00010110
		BNE AlignLoop

; timed code, probably to wait until a valid response can be read
		LDX #$04
TimedLoop1:
		DEX
		BNE TimedLoop1

		LDA $00  ; waste a few cycles
		LDA #$80 ; init result + ring counter

PollLoop:
		PHA ; save in stack

; more timed code
		LDX #$04
TimedLoop2:
		DEX
		BNE TimedLoop2

		NOP
		NOP
		NOP

; poll device
; bit ordering appears to be 76543210 (ring counter is shifted to the right)
		LDA JOY2
		AND #$16 ; %00010110
		CMP #$01 ; set carry if A >= $01
		PLA
		ROR A
		BCC PollLoop

		STA DMC_RAW ; audio feedback?
		RTS

; read unknown expansion port device and process data
ProcessDevice:
		JSR PollDevice
		CMP #$3A
		BNE ProcessDevice ; keep polling until result == $3A

		JSR ReadByte
		STA $19 ; length, max is $FF
		BEQ EndProcessing ; branch to exit routine if 0

		STA $10 ; init checksum
		LDA PPU_STATUS ; reset PPU flip-flop
		JSR ReadByte
		STA $13 ; destination high byte
		CLC
		ADC $10
		STA $10 ; checksum
		JSR ReadByte
		STA $12 ; destination low byte
		CLC
		ADC $10
		STA $10 ; checksum
		JSR ReadByte ; this appears to be a separator byte before the data
		CMP #$00
		BNE NonZeroSeparator ; branch to error screen if not 0

		LDA $13 ; note that the carry is set here
		ADC #$1F ; d7 is set if [$13] >= $60 (i.e. destination >= $6000)
		BMI LoadPRG ; branch to PRG-RAM load routine if d7 of result is set

; load data from device into nametables at ($12)+$2000
; the prior addition check means that the lowest possible address is $2000
LoadNAM:
		STA PPU_ADDR
		LDA $12
		STA PPU_ADDR
		LDY #$00

LoadNAMLoop:
		JSR ReadByte ; load data byte
		STA PPU_DATA ; store in VRAM
		CLC
		ADC $10
		STA $10 ; update checksum
		INY
		CPY $19 ; compare against length byte
		BCC LoadNAMLoop ; loop until Y >= length

		JSR ReadByte ; read checksum compliment
		CLC
		ADC $10 ; final checksum
		BEQ ProcessDevice ; return to processing if result is 0

		JMP ErrorSound ; otherwise, the checksum was invalid. error

; load data from device into PRG-RAM
; the prior addition check means that the lowest possible address is $6000
LoadPRG:
		LDY #$00

LoadPRGLoop:
		JSR ReadByte ; load data byte
		STA ($12),Y ; store in PRG-RAM
		CLC
		ADC $10
		STA $10 ; update checksum
		INY
		CPY $19 ; compare against length byte
		BCC LoadPRGLoop ; loop until Y >= length

		JSR ReadByte ; read checksum compliment
		CLC
		ADC $10 ; final checksum
		BEQ ProcessDevice ; return to processing if result is 0

		JMP ErrorSound ; otherwise, the checksum was invalid. error

; read 10 bytes of remaining data(?), then exit device processing
EndProcessing:
		LDY #$0A

ExtraReadLoop:
		JSR PollDevice
		DEY
		BNE ExtraReadLoop

		LDA #$00
		RTS

; read an ASCII-encoded byte
; 2 ASCII-encoded nybbles are read and merged
ReadByte:
		JSR ReadNybble
		ASL A
		ASL A
		ASL A
		ASL A
		STA $18
		JSR ReadNybble
		ORA $18
		RTS

; read an ASCII-encoded nybble
ReadNybble:
		JSR PollDevice
		CMP #$41 ; ASCII 'A'
		BCC IsNumber ; branch ahead if result < 'A'

		SBC #$07 ; otherwise subtract $07
	
IsNumber:
		AND #$0F ; mask to lower nybble
		RTS

;----------------------

; fill palettes with $15 and increment $4011 forever (crude sawtooth)
; error screen with audio feedback
ErrorSound:
		LDA #$15
		JSR FillPalettes

Sawtooth:
		INX
		STX DMC_RAW ; audio feedback?
		JMP Sawtooth  ; jump back to increment $4011 forever

; disable NMIs & rendering, then fill palettes with $15 and loop forever
; an error screen called only when the separator byte between the length/destination and data is nonzero
NonZeroSeparator:
		LDA #$00
		STA PPU_CTRL
		STA PPU_MASK
		LDA #$15
		JSR FillPalettes

Endless:
		JMP Endless ; endless loop, need I say more?

;----------------------

; fill palette RAM with contents of A
FillPalettes:
		LDX PPU_STATUS
		LDX #$3F
		STX PPU_ADDR
		LDX #$00
		STX PPU_ADDR
		LDX #$20
		
PaletteLoop:
		STA PPU_DATA
		DEX
		BNE PaletteLoop

		RTS

;----------------------

; fake license screen palette data, indexed with X
LicensePalette:
	.db $0F, $20, $0F, $20, $0F, $0F, $0F, $0F

; fake license screen routine, assuming the license screen message was already loaded into the nametables
; not sure why the actual BIOS routine wasn't used here since the program has full control at this point
; maybe a good entrypoint couldn't be found? (or maybe some tomfoolery was involved)
FakeLicenseScreen:
; start by initialising the upper nametable
		LDA #$20
		LDX #$24
		LDY #$55
		JSR VRAMFill ; fill $2000 nametable with $24 and its attributes with $55

; now set up the attribute table in the lower nametable (likely macros)
		LDA #$2C ; fill $20 attribute bytes at $2CE0 with $24
		STA PPU_ADDR
		LDA #$E0
		STA PPU_ADDR
		LDX #$20
		LDA #$24

AttrFillLoop1:
		STA PPU_DATA
		DEX
		BNE AttrFillLoop1

		LDA #$2F ; fill $10 attribute bytes at $2FC0 with $00
		STA PPU_ADDR
		LDA #$C0
		STA PPU_ADDR
		LDX #$10
		LDA #$00

AttrFillLoop2:
		STA PPU_DATA
		DEX
		BNE AttrFillLoop2

		LDX #$30 ; fill $30 more attribute bytes with $55
		LDA #$55

AttrFillLoop3:
		STA PPU_DATA
		DEX
		BNE AttrFillLoop3

; now wait until vblank, then safely write palettes (prevents visible stripes)
		JSR VINTWait
		LDA PPU_STATUS
		LDA #$3F
		STA PPU_ADDR
		LDA #$00
		STA PPU_ADDR
		LDX #$00

LicensePaletteLoop:
		LDA LicensePalette,X ; load palette entries
		STA PPU_DATA
		INX
		CPX #$08
		BCC LicensePaletteLoop

		LDA #$00 ; move PPUADDR from $3Fxx to $0000 to prevent rare palette corruptions
		STA PPU_ADDR
		STA PPU_ADDR

; setup routine call to swap data in VRAM
		LDA #$00 ; ($12) = $2000
		STA $12
		LDA #$20
		STA $13
		LDA #$00 ; ($14) = $1000
		STA $14
		LDA #$10
		STA $15
		LDY #$C0 ; length = $04C0
		LDX #$04
		JSR SwapVRAM

; prepare to load the BIOS font bitmaps
; (they couldn't use the BIOS routine due to it trashing the $0400 page)
		LDA #$00 ; ($14) = $1000
		STA $14
		LDA #$10
		STA $15
		LDX #$12 ; X = $12 for the later ($00,X) loads
		LDA #$01 ; ($12) = $E001, the start of the BIOS font bitmaps
		STA $00,X
		LDA #$E0
		STA $01,X
		LDA #$29 ; init primary counter

FontLoadLoop:
		PHA ; save primary counter in stack
		LDA PPU_STATUS ; reset PPU flip-flop
		LDA $15 ; PPU_ADDR == ($14)
		STA PPU_ADDR
		LDA $14
		STA PPU_ADDR
		LDY #$08 ; init secondary counter

BitmapLoadLoop:
		LDA ($00,X) ; load from ($12) into PPU_DATA
		STA PPU_DATA
		INC $00,X ; standard 16-bit increment here
		BNE NoOverflow

		INC $01,X

NoOverflow:
		DEY ; decrement secondary counter
		BNE BitmapLoadLoop ; loop until secondary counter == 0

		LDA $14 ; ($14) += $0010
		CLC
		ADC #$10
		STA $14
		LDA $15
		ADC #$00
		STA $15
		PLA ; retrieve and decrement primary counter
		SEC
		SBC #$01
		BNE FontLoadLoop ; loop until primary counter == 0

; scroll the license message onscreen and display it
		LDA #$00 ; init Y scroll mirror
		STA $FC
		LDA #$A0 ; init display timer

ScrollMessageLoop:
		PHA ; save timer in stack
		JSR ScrollScreen
		JSR ScrollScreen
		PLA ; retrieve and decrement timer
		SEC
		SBC #$01
		BNE ScrollMessageLoop ; loop until timer becomes 0

; same VRAM swap setup as earlier, probably a macro
		LDA #$00 ; ($12) = $2000
		STA $12
		LDA #$20
		STA $13
		LDA #$00 ; ($14) = $1000
		STA $14
		LDA #$10
		STA $15
		LDY #$C0 ; length = $04C0
		LDX #$04
		JSR SwapVRAM
		
; now we're done with the fake license screen
		JSR VINTWait
		LDA #$35 ; set stack variables to use the disk game reset vector
		STA RST_FLAG
		LDA #$AC
		STA RST_TYPE

ResetCall:
		JMP (BIOS_RESET) ; call the BIOS reset to run the game

ScrollScreen:
		JSR VINTWait ; wait a frame
		JSR SetScroll
		JSR EnPF ; enable BG rendering
		LDX $FC ; increment Y scroll mirror by 2
		INX
		INX
		CPX #$B0
		BCS SkipMirror ; stop further scrolling if at or past $B0

		STX $FC ; otherwise write to mirror

SkipMirror:
		RTS

;----------------------

; routine to swap data between 2 locations in VRAM
; ($12) = address 1
; ($14) = address 2
; X,Y forms a 16-bit length counter, with X being the high byte
SwapVRAM:
		LDA #$00 ; disable rendering to safely access PPU
		STA PPU_MASK

SwapLoop:
; read 1 byte each from the corresponding addresses
		LDA PPU_STATUS ; reset PPU flip-flop
		LDA $13 ; PPU_ADDR = ($13)
		STA PPU_ADDR
		LDA $12
		STA PPU_ADDR
		LDA PPU_DATA ; dummy read
		LDA PPU_DATA ; real read 1
		PHA ; save read 1

		LDA PPU_STATUS ; reset PPU flip-flop
		LDA $15 ; PPU_ADDR = ($14)
		STA PPU_ADDR
		LDA $14
		STA PPU_ADDR
		LDA PPU_DATA ; dummy read
		LDA PPU_DATA ; real read 2
		PHA ; save read 2

; write each byte to the opposite addresses
		LDA PPU_STATUS ; reset PPU flip-flop
		LDA $13 ; PPU_ADDR = ($13)
		STA PPU_ADDR
		LDA $12
		STA PPU_ADDR
		PLA ; retrieve read 2
		STA PPU_DATA ; write at address 1

		LDA PPU_STATUS ; reset PPU flip-flop
		LDA $15 ; PPU_ADDR = ($14)
		STA PPU_ADDR
		LDA $14
		STA PPU_ADDR
		PLA ; retrieve read 1
		STA PPU_DATA ; write at address 2

; increment ($12) and ($14)
		INC $12
		BNE NextInc

		INC $13
		
NextInc:
		INC $14
		BNE DecLength

		INC $15

; decrement the length counter and repeat the swap process until the counter reaches 0
DecLength:
		DEY
		BNE SwapLoop

		DEX
		BNE SwapLoop

		RTS

;----------------------

; NMI bypass entrypoint
Bypass:
		LDA #$10 ; set BG pattern table
		STA PPU_CTRL
		LDA #$00 ; disable rendering
		STA PPU_MASK
		JSR XferDone ; crude way of resetting disk drive
		LDX #$FF ; init stack pointer
		TXS

; check for presence of an unknown expansion port device
; based on the interfacing, it appears to be an EEPROM device similar to the Battle Box
		LDX #$01
		LDY #$00
		STX JOY1 ; $4016 = 1
		LDA JOY2 ; A = $4017
		STY JOY1 ; $4016 = 0
		EOR JOY2 ; A ^ $4017
		AND #$08 ; %00001000
		BNE DeviceFound ; branch if D3 set

		JMP FakeLicenseScreen ; otherwise init fake license screen (normal game boot)

; clear pattern tables
DeviceFound:
		LDA PPU_STATUS
		LDA #$00
		STA PPU_ADDR
		STA PPU_ADDR
		LDX #$20
		LDY #$00

CHRClearLoop:
		STA PPU_DATA
		DEY
		BNE CHRClearLoop

		DEX
		BNE CHRClearLoop

; fill PRG-RAM ($6000~$DFFF) with $FF, this trashes the disk game vectors
; (VECT.IPL is required to load the correct NMI_3 vector afterwards)
		LDX #$12
		LDA #$00
		STA $00,X
		LDA #$60
		STA $01,X

PRGFillLoop:
		LDA #$FF
		STA ($00,X)
		INC $00,X
		BNE PRGFillLoop

		INC $01,X
		LDA $01,X
		CMP #$E0
		BCC PRGFillLoop

; main logic
		LDA #$11 ; set colour to indicate device processing
		JSR FillPalettes
		LDA #$00 ; disable NMIs & rendering
		STA PPU_CTRL
		STA PPU_MASK
		JSR ProcessDevice ; load data from unknown expansion port device
		LDA #$35 ; set stack variables to use the disk game reset vector
		STA RST_FLAG
		LDA #$AC
		STA RST_TYPE
		LDA #$0F ; set colour to indicate end of processing
		JSR FillPalettes
		LDA FDS_DRIVE_STATUS
		LSR A ; carry = 0 if disk inserted
		BCC StartDiskWrite ; branch to do disk access if disk is inserted

		JMP ResetCall ; otherwise jump to JMP (BIOS_RESET) to run the newly loaded code

StartDiskWrite:
		LDA #$15 ; set colour to indicate disk write
		JSR FillPalettes
		JSR WriteToDisk
		BEQ StartDiskRead ; branch if successful

		JMP ErrorSound ; otherwise jump to error screen

StartDiskRead:
		LDA #$17 ; set colour to indicate disk readback check
		JSR FillPalettes
		JSR ReadbackCheck
		BEQ Success ; branch if successful

		JMP ErrorSound ; otherwise jump to error screen

; fill palettes with $0f and loop forever
; success screen
Success:
		LDA #$0F
		JSR FillPalettes
		
EndlessFun:
		JMP EndlessFun ; endless loop, need I say more?

;----------------------

; write files to disk
WriteToDisk:
		TSX ; save stack pointer
		STX $04
		LDA #$00 ; disable NMIs and rendering
		STA PPU_CTRL
		STA PPU_MASK
		
		JSR WaitForReady ; wait for disk drive to become ready
		LDY #$C8 ; ~200ms delay
		JSR Delayms
		LDY #$43 ; ~67ms delay
		JSR Delayms
		
		LDA #$01 ; check for disk info block
		JSR CheckBlockType ; A is preserved in this routine

		LDY #$38 ; number of bytes in the file info block, excluding the CRC

DummyReadLoop1:
		JSR XferByte ; dummy reads to finish reading the file info block
		DEY
		BNE DummyReadLoop1

		JSR CheckDiskSet ; check if disk is inserted
		LDA #$07 ; set file amount to $07
		JSR SetNumFiles
		
		LDA #$00 ; init file header table offset

WriteNextFile:
		PHA ; save offset to stack
		ASL A ; left shift since this is a table of words
		TAY
		LDA FileHeaderTable,Y ; ($12) = file header indexed by Y
		STA $12
		LDA FileHeaderTable+1,Y
		STA $13

		LDA #$03 ; write file header block type
		JSR WriteBlockType

		LDY #$00 ; init file data offset

FileHeaderWriteLoop:
		LDA ($12),Y ; write file header from ($12) to disk
		JSR XferByte
		INY
		CPY #$0F
		BCC FileHeaderWriteLoop

		JSR EndOfBlockWrite ; this writes the CRC of the file block

		LDY #$0C ; ($16) = file data size in file header structure
		LDA ($12),Y
		STA $16
		LDY #$0D
		LDA ($12),Y
		STA $17
		
		LDA PPU_STATUS ; reset PPU flip-flop
		LDY #$10 ; PPU_ADDR = ($14) = source address in file header structure
		LDA ($12),Y
		STA $15
		STA PPU_ADDR
		LDY #$0F
		LDA ($12),Y
		STA $14
		STA PPU_ADDR
		LDA PPU_DATA ; dummy read
		
		LDY #$11 ; A = source address type in file header structure
		LDA ($12),Y
		PHA ; save to stack

		LDA #$04 ; write file data block type
		JSR WriteBlockType

		PLA ; retrieve source address type and transfer to Y
		TAY

FileDataWriteLoop:
		CPY #$00
		BNE WriteFromVRAM ; write from VRAM if source address type != 0

		LDX #$14 ; A = ($14)
		LDA ($00,X)
		INC $00,X ; 16-bit increment
		BNE WriteByte

		INC $01,X
		JMP WriteByte

WriteFromVRAM:
		LDA PPU_DATA ; real read

WriteByte:
		JSR XferByte
		LDA $16 ; 16-bit decrement
		BNE NextDec_Write

		DEC $17

NextDec_Write:
		DEC $16
		LDA $16
		ORA $17
		BNE FileDataWriteLoop ; loop until file data size == 0

		JSR EndOfBlockWrite ; write CRC

		PLA ; retreive file header table offset and increment it
		CLC
		ADC #$01
		CMP #$07
		BCS WriteOK ; branch if result >= $07

		JMP WriteNextFile ; otherwise loop

; disk write success
WriteOK:
		JSR XferDone
		LDX #$00
		RTS

;----------------------

; disk readback check
; the contents of the written files must match system memory
ReadbackCheck:
		TSX ; save stack pointer
		STX $04
		LDA #$00 ; disable NMIs and rendering
		STA PPU_CTRL
		STA PPU_MASK

		JSR WaitForReady ; wait for disk drive to become ready
		LDY #$C8 ; ~200ms delay
		JSR Delayms
		LDY #$43 ; ~67ms delay
		JSR Delayms
		LDA #$01 ; check for file info block type
		JSR CheckBlockType
		
		LDY #$38 ; number of bytes in the file info block, excluding the CRC

DummyReadLoop2:
		JSR XferByte ; dummy reads to finish reading the file info block
		DEY
		BNE DummyReadLoop2

		JSR CheckDiskSet ; check if disk is inserted
		LDA #$02 ; check for file amount block type
		JSR CheckBlockType
		JSR XferByte ; read file amount
		CMP #$07
		BEQ FileAmountOK ; continue if file amount == $07

		JMP ReadbackBad ; otherwise, this is a readback failure

FileAmountOK:
		JSR EndOfBlockRead ; this checks the CRC of the file block

		LDA #$00 ; init file header table offset

ReadNextFile:
		PHA ; save offset to stack
		ASL A ; left shift since this is a table of words
		TAY
		LDA FileHeaderTable,Y ; ($12) = file header indexed by Y
		STA $12
		LDA FileHeaderTable+1,Y
		STA $13

		LDA #$03 ; check for file header block type
		JSR CheckBlockType
		
		LDY #$00

FileHeaderReadLoop:
		JSR XferByte ; check that the file header block matches ($12)
		CMP ($12),Y
		BEQ FileHeaderByteOK

		JMP ReadbackBad ; if any bytes don't match, this is a readback failure

FileHeaderByteOK:
		INY
		CPY #$0F
		BCC FileHeaderReadLoop

		JSR EndOfBlockRead ; check CRC

		LDY #$0C ; ($16) = file data size in file header structure
		LDA ($12),Y
		STA $16
		LDY #$0D
		LDA ($12),Y
		STA $17
		
		LDA PPU_STATUS ; reset PPU flip-flop
		LDY #$10 ; PPU_ADDR = ($14) = source address in file header structure
		LDA ($12),Y
		STA $15
		STA PPU_ADDR
		LDY #$0F
		LDA ($12),Y
		STA $14
		STA PPU_ADDR
		LDA PPU_DATA ; dummy read
		
		LDY #$11 ; A = source address type in file header structure
		LDA ($12),Y
		PHA ; save to stack

		LDA #$04 ; check for file data block type
		JSR CheckBlockType

		PLA ; retrieve source address type and transfer to Y
		TAY

FileDataReadLoop:
		CPY #$00
		BNE ReadFromVRAM ; read from VRAM if source address type != 0

		LDX #$14 ; A = ($14)
		LDA ($00,X)
		INC $00,X ; 16-bit increment
		BNE CompareBytes

		INC $01,X
		JMP CompareBytes

ReadFromVRAM:
		LDA PPU_DATA ; real read

CompareBytes:
		STA $12 ; save in $12
		JSR XferByte ; read byte from disk
		CMP $12
		BEQ CompareOK ; continue if byte matches contents of $12

		JMP ReadbackBad ; otherwise, this is a readback failure

CompareOK:
		LDA $16 ; 16-bit decrement
		BNE NextDec_Read

		DEC $17

NextDec_Read:
		DEC $16
		LDA $16
		ORA $17
		BNE FileDataReadLoop

		JSR EndOfBlockRead ; check CRC

		PLA ; retreive file header table offset and increment it
		CLC
		ADC #$01
		CMP #$07
		BCS ReadbackOK ; branch if result >= $07

		JMP ReadNextFile ; loop otherwise

; disk readback success
ReadbackOK:
		JSR XferDone
		LDX #$00
		RTS

; disk readback failure
ReadbackBad:
		JSR XferDone
		LDX $04
		TXS
		LDX #$50
		RTS

;----------------------

; padding
.pad IPL_MAIN + IPL_SIZE

