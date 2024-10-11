-----------------------
-- Name: IPL.LUA
-- Author: TakuikaNinja
-----------------------
-- Simulates the Namco IPL Interface for use in FDS games developed by Namco.
-- The current disk should be ejected for direct execution of loaded code, 
-- or swapped to a blank one to be overwritten instead.
-- Messages will be displayed to indicate the program status.
-- 
-- Successfully tested on "Pac-Man (Japan) (Disk Writer).fds"
-----------------------
-- Changelog:
-- 2024-07-22 - Initial creation, added file loading
-- 2024-07-23 - Added warning for FPS dip (due to emulator state manipulation)
-- 2024-10-11 - Overhauled to fully simulate the $4016/$4017 interface
-----------------------

local consoleType = emu.getState()["consoleType"]
if consoleType ~= "Nes" then
	emu.displayMessage("Script", "This script only works on the NES/FC.")
	return
end

-- dump the contents of a table, for use when analysing emu.getState()
function dump(o)
   if type(o) == 'table' then
      local s = '{ \n'
      for k,v in pairs(o) do
         --if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. k..': ' .. dump(v) .. ', \n'
      end
      return s .. '}'
   else
      return tostring(o)
   end
end

strobeRef = nil
polRef = nil

function prepareIPL()
	readPayloadFile()
	
	-- IPL Interface
	strobeRef = emu.addMemoryCallback(strobe, emu.callbackType.write, 0x4016)
	pollRef = emu.addMemoryCallback(poll, emu.callbackType.read, 0x4017)
	
	-- IPL states
	emu.addMemoryCallback(processDevice, emu.callbackType.exec, 0x0570)
	emu.addMemoryCallback(processingComplete, emu.callbackType.exec, 0x0348)
	emu.addMemoryCallback(badChecksum, emu.callbackType.exec, 0x031F)
	emu.addMemoryCallback(badChecksum, emu.callbackType.exec, 0x033B)
	emu.addMemoryCallback(badRecordType, emu.callbackType.exec, 0x0370)
	
	-- Code execution
	emu.addMemoryCallback(executeReset, emu.callbackType.exec, 0x0588)
	
	-- Disk I/O
	emu.addMemoryCallback(diskWrite, emu.callbackType.exec, 0x058B)
	emu.addMemoryCallback(badDiskWrite, emu.callbackType.exec, 0x0595)
	emu.addMemoryCallback(diskRead, emu.callbackType.exec, 0x0598)
	emu.addMemoryCallback(readbackPassed, emu.callbackType.exec, 0x05A5)
	emu.addMemoryCallback(readbackFailed, emu.callbackType.exec, 0x05A2)
	
	emu.displayMessage(script, "Beginning simulation of IPL interface...")
	emu.displayMessage(script, "Eject/swap disk before resuming.")
	emu.breakExecution()
end

STATUS = 0x08 -- %00001000, bit 3
DATA = 0x16 -- %00010110, bits 1/2/4
dataByte = 0
BITS = 8
bitsRemaining = 0 -- 

PADDING = 4
paddingBits = PADDING

lastValue = 0
strobed  = false

-- Intel HEX payload
idx = 1
hexPayload = ":02694200BEEFA6:00000001FF" -- default for when I/O fails (note: crashes the FDS)

function strobe(address, value)
	value = value & 1 -- we only care about bit 0
	if value == 1 then
		strobed = false
	elseif lastValue == 1 then
		-- resetting the transfer after the strobe makes the most sense here
		strobed = true
		idx = 1
		bitsRemaining = 0
		paddingBits = PADDING
		emu.log("$4016 strobe: init transfer")
	end
	lastValue = value
end

function poll(address, value)
	local output = value & ~DATA -- preserve unused bits
	
	-- set status bit if strobed
	if strobed then
		output = output | STATUS
	end
	
	-- now deal with padding/data bits
	local currentBit = 0
	if bitsRemaining == 0 then
		if paddingBits > 0 then
			-- send appropriate padding bit
			if paddingBits == 2 then
				currentBit = 1 -- 1 -> 0 transition = RS232 start bit
			end
			paddingBits = paddingBits - 1
			emu.log("padding bit = " .. currentBit)
		end
		
		if paddingBits == 0 then
			-- fetch new byte from payload if padding is exhausted
			dataByte = fetchPayloadByte()
			bitsRemaining = BITS
			paddingBits = PADDING
		end
	else
		-- transfer bit 0 from current data byte
		currentBit = dataByte & 1
		dataByte = dataByte >> 1
		bitsRemaining = bitsRemaining - 1
		emu.log("data bit = " .. currentBit)
	end
	
	-- compose & return final output
	output = (output | (currentBit * DATA)) & 0xff
	emu.log(string.format("$4017 = %#02x", output))
	return output
end

function fetchPayloadByte()
	local char = '0' -- send ASCII 0s if payload was exhausted
	if idx <= #hexPayload then
		char = hexPayload:sub(idx,idx)
		idx = idx + 1
	end
	local byte = char:byte()
	emu.log(string.format("HEX payload: char = %s, byte = %#02x", char, byte))
	return byte
end

function processDevice()
	emu.displayMessage(script, "Processing IPL interface...")
end

function processingComplete()
	emu.displayMessage(script, "IPL processing complete!")
end

function badChecksum()
	emu.displayMessage(script, "Wrong checksum in record.")
end

function badRecordType()
	emu.displayMessage(script, "Record type not set to data type")
end

function executeReset()
	emu.displayMessage(script, "Executing BIOS reset...")
	removeInterfaceCallbacks()
end

function diskWrite()
	emu.displayMessage(script, "Writing data to disk...")
end

function badDiskWrite()
	emu.displayMessage(script, "Disk write failed.")
end

function diskRead()
	emu.displayMessage(script, "Performing disk readback check...")
end

function readbackPassed()
	emu.displayMessage(script, "Disk readback check passed!")
	removeInterfaceCallbacks()
end

function readbackFailed()
	emu.displayMessage(script, "Disk readback check failed.")
end

-- remove IPL Interface callbacks so they do not interfere with normal execution afterwards
function removeInterfaceCallbacks()
	emu.removeMemoryCallback(strobeRef, emu.callbackType.write, 0x4016)
	emu.removeMemoryCallback(pollRef, emu.callbackType.read, 0x4017)
	emu.removeMemoryCallback(IPLRef, emu.callbackType.exec, 0x050A)
	emu.displayMessage(script, "Removed IPL entrypoint/interface callbacks.")
end

-- Attempt to read payload from "LuaScriptData/IPL/payload.hex"
function readPayloadFile()
	local readSuccess = false
	local dir = emu.getScriptDataFolder()
	if dir ~= nil then
		local file = io.open(dir .. "/payload.hex", "rb")
		if file ~= nil then
			emu.displayMessage(script, "Reading payload...")
			hexPayload = file:read("*all")
			file:close()
			readSuccess = true
		end
	end
	if readSuccess == false then
		emu.displayMessage(script, "Using default payload...")
	end
	emu.log('"' .. hexPayload .. '"')
end

-- Memory callbacks
IPLRef = emu.addMemoryCallback(prepareIPL, emu.callbackType.exec, 0x050A)

script = "IPL.LUA"
emu.displayMessage("Script", script)
