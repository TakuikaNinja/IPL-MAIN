# IPL.MAIN

Resources relating to the IPL.MAIN program present in Namco's FDS games

# Acknowledgements

This project was inspired by a remark from NewRisingSun.  
The program was extracted from Pac-Man (FDS), disassembled using https://www.masswerk.at/6502/disassembler.html, and was manually cleaned up by TakuikaNinja.  
The program is copyrighted by Namco as indicated in the `(C)NAMCO` file. Because of this, this project should only be used for archival and educational purposes.  

# Background

Famicom Disk System games developed by Namco include a 1.5KiB bootstrap program internally named "IPL.MAIN", loaded into console internal RAM starting at $0200. 
It is executed by way of disk files triggering an NMI during the loading process. It checks for the presence of an unknown expansion port device on startup. 
If the device is not detected, the program displays a fake license screen and starts the loaded game. This is what players will normally see. 
However, the program does more interesting things if the device happens to be present.  

The device will be named the _Namco IPL Interface_ for the time being.

## Supported FDS Games

Commercial games, in release order:
- Pac-Man
- Xevious
- Galaga
- Dig Dug
- Galaxian
- Dig Dug II

Custom disks created using the IPL are also supported, since the IPL automatically includes itself when saving data to disks.

# Included Files

- This `README` file containing general information about the IPL.MAIN program and its interface.
- `IPL.ASM`, which is a disassembly of the IPL.MAIN program. It targets [asm6f](https://github.com/freem/asm6f) and can be reassembled to an identical binary file.
- `IPL.lua`, which is a Lua script for [Mesen2](https://www.mesen.ca/) which simulates the interface.
- `IPL-Arduino/IPL-Arduino.ino`, which is an Arduino sketch which simulates the interface.
- `payload.hex`, which is an example Intel HEX payload to be loaded by the IPL. See usage section for details.
- `.gitignore`, just so no one accidentally pushes binary files to the repository.

# Usage

## Emulator (Mesen2)

Demonstration: https://youtu.be/cozQygiiEqQ

1. Place the payload file in `LuaScriptData/IPL` in Mesen2's home directory.
1. Load a supported FDS game, then open and run `IPL.lua`.
1. Hard-reset the emulated FDS. The script will automatically pause the emulator upon detecting the IPL to allow the disk to be ejected or swapped before overwriting its contents. Pick an option and resume emulation to continue the process.
1. The script will display status messages throughout the process. See status indicators below for how they correlate to the screen colours.

## Hardware (Arduino)

Demonstration: https://youtu.be/jX9ZZXXkR2c

1. Wire the Famicom expansion port and Arduino as explained below.
1. Compile and upload `IPL-Arduino/IPL-Arduino.ino` to an Arduino.
1. Load a supported FDS game. The screen should show a solid blue upon loading. Eject or swap the disk at this point if desired.
1. Use the serial monitor to upload the payload file contents as text. Line endings must be "Both NL & CR". The sketch targets 19200 baud on the USB side by default, alter this if there are speed/reliability issues.
1. Consult the status screen indicators below to determine the IPL status.

### Wiring

Modified diagram from https://www.nesdev.org/wiki/Expansion_port
```
       (top)    Famicom    (bottom)
               Male DA-15
                 /\
                |   \
                | .   \
                |   .  |
joypad 2 /D1 -> | 07   |
                |   .  |
joypad 2 /D2 -> | 06   |
                |   .  |
joypad 2 /D3 -> | 05   |
                |   12 | -> OUT0 ($4016 write data, bit 0, strobe on pads)
joypad 2 /D4 -> | 04   |
                |   .  |
                | .    |
                |   .  |
                | .    |
                |   .  |
                | .   /
                |   /
                 \/
```
- joypad 2 /D1, /D2, D4: 5V TTL RX (serial input), connect one of them to Arduino digital pin 3 (SoftwareSerial TX)
- joypad 2 /D3 and OUT0: short these pins to trigger the IPL

# Links

- https://github.com/TakuikaNinja/IPL-MAIN - This repository
- https://github.com/TakuikaNinja/IPL-demo - Example program which targets the Namco IPL Interface
- https://www.nesdev.org/wiki/Namco_IPL_Interface - Nesdev Wiki article for the Namco IPL Interface
- https://forums.nesdev.org/viewtopic.php?t=24983 - Forum discussion

# Device Information

The Namco IPL Interface is connected to the Famicom's DA15 expansion port before starting the program. 
This is currently suspected to be a RS232-like serial interface connected to a development system. 
The baud rate is likely to be 38400, as this equates to 46.60 CPU cycles per bit which is very close to the 47 cycle wait used by IPL.MAIN. 
The interface sends binary data which primarily consists of ASCII data. The program detects the interface, interprets the data, and transfers it to the Famicom's PPU or PRG-RAM accordingly. 
Once this is complete, the program either executes the loaded PRG-RAM code, or saves the data to an inserted disk.  
If the data is written to disk, a readback check is then performed to verify the files' contents. Disk accesses are done using low-level routines from the FDS BIOS.
The screen colour changes depending on the program's status. $4011 is written to during device polling, and the most common error screen will emit a crude sawtooth wave.

# Interface Detection

The program attempts to detect the interface by doing the following:
1. Write 1 to $4016
1. Read from $4017
1. Write 0 to $4016
1. Read $4017 again and XOR with the previous read
1. Check if bit 3 was set (`%00001000`)

# Interface Polling

The polling process begins with what appears to be an alignment process:
1. Poll $4017 until either bits 1, 2, or 4 are set (`%00010110`)
1. Poll $4017 until bits 1, 2, and 4 are all cleared

Then, the interface is polled to obtain 8 bits, with timed code present:
1. Init ring counter with $80
1. Read $4017
1. AND result with $16 (`%00010110`)
1. Compare the result against $01 to set the carry
1. Right rotate (ROR) the carry into the ring counter
1. Repeat until the ring counter bit is shifted into the carry
1. Output result to $4011

This means the order of the bits in the polling result is `76543210`.

# Interface Processing

1. Poll interface until a raw $3A byte is found
1. Read 1 ASCII-encoded byte to obtain length
1. If length == 0, poll device 10 times and exit
1. Otherwise, init the checksum with the length byte
1. Read 2 ASCII-encoded bytes to form a destination address in ($12), add values to checksum
1. Read 1 ASCII-encoded byte, branch to an error screen which sets the BG to $15 if != 0
1. Otherwise, if destination >= $6000, transfer to PRG-RAM
1. Otherwise, transfer to PPU nametables
1. Repeat

## Data Transfer Process

The data transfer process is identical between PPU nametables & PRG-RAM aside from the storage method:
1. Set destination address - PPU nametables: ($12)+$2000 used for PPUADDR, PRG-RAM: ($12)
1. Load ASCII-encoded bytes and store them at the destination until the offset matches the length, updating the checksum in the process
1. Read 1 ASCII-encoded byte to get the checksum complement and add it to the checksum
1. If the checksum == 0, return to processing
1. Otherwise, display an error screen which sets the BG to `$15` and continually increments $4011 (crude sawtooth)

## Data Transfer Format

The data transfer process expects a variant of the [Intel HEX](https://en.wikipedia.org/wiki/Intel_HEX) format described as the following:
1. Start code, raw $3A byte (":")
1. ASCII-encoded length
1. ASCII-encoded destination high byte & ASCII destination low byte
1. ASCII-encoded record type (must be $00, data type)
1. ASCII-encoded data
1. ASCII-encoded checksum complement

An example record expressed as a list of ASCII strings:
`":", "02", "6942", "00", "BEEF", "A6"`

An example of the final record (length = 0, traditional EOF + 1 byte):
`":", "00", "0000", "01", "FF", "00"`

## IPL Status Indicators

The IPL sets the screen colour by filling palette RAM in order to indicate its status. The tables below list the known colours and their respective statuses.

### IPL Data Transfer

| Colour (raw value) | Sound? | Status |
| ------------------ | ------ | ------ |
| Blue ($11) | Y | Transferring interface data |
| Black ($0F) | N | Transfer complete |
| Magenta ($15) | Y | Incorrect record checksum |
| Magenta ($15) | N | Record type != data type |

### Disk Writes

| Colour (raw value) | Sound? | Status |
| ------------------ | ------ | ------ |
| Magenta ($15) | N | Writing to disk |
| Brown ($17) | N | Disk readback check |
| Black ($0F) | N | Readback success |
| Magenta ($15) | Y | Disk Write/Readback failure |

### Notes

- ASCII-encoded bytes are stored using ASCII strings of hexadecimal values. (e.g. $5F -> "5", "F" -> $35, $46)
- The checksum addition is performed with the carry always cleared, starting from the length value.
- The safest point to eject/swap disks would be during the interface data transfer (blue screen), as the interface could stall the transfer before a record is sent.

# To-Do List

- [x] Document the screen colours which indicate the program status.
- [x] Simulate the interface hardware using a Lua script.
- [x] Replicate the interface hardware.
- [x] Run the program on real hardware.

