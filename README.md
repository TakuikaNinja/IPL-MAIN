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

# Included Files

- This README file containing general information about the IPL.MAIN program and its interface.
- IPL.ASM, which is a disassembly of the IPL.MAIN program. It targets [asm6f](https://github.com/freem/asm6f) and can be reassembled to an identical binary file.
- .gitignore, just so no one accidentally pushes binary files to the repository.

# Links

- https://github.com/TakuikaNinja/IPL-MAIN - This repository
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

An example "packet" expressed as a list of ASCII strings:
`":", "02", "6942", "00", "BEEF", "A6"`

An example of the final packet (length = 0, 10 bytes padding):
`":", "00", "0000", "00", "00", "00"`

This termination method (as opposed to using the $01 record type for EOF) is used by most [CP/M-80](https://en.wikipedia.org/wiki/CP/M-80) assemblers.

### Notes

- ASCII-encoded bytes are stored using ASCII strings of hexadecimal values. (e.g. $5F -> "5", "F" -> $35, $46)
- The checksum addition is performed with the carry always cleared, starting from the length value.

# To-Do List

- [ ] Document the screen colours which indicate the program status.
- [ ] Attempt to emulate the interface. (software/hardware)
- [ ] Run the program on real hardware.

