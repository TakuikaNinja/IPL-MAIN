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

function PrepareIPL()
	ReadPayloadFile()
	local state = emu.getState()
	state["cpu.a"] = 0x08 -- pretend the IPL interface was detected
	emu.setState(state)
	emu.displayMessage(script, "Beginning simulation of IPL interface...")
	emu.displayMessage(script, "Eject/swap disk before resuming.")
	emu.breakExecution()
end

function ProcessDevice()
	emu.displayMessage(script, "Processing IPL interface...")
	emu.displayMessage(script, "Frame rate may be slowed down.")
end

function PollDevice()
	local state = emu.getState()
	local char = '0' -- send ASCII 0s if payload was exhausted
	if idx <= #hexPayload then
		char = hexPayload:sub(idx,idx)
		idx = idx + 1
	end
	state["cpu.a"] = char:byte() -- send ASCII byte
	state["cpu.pc"] = 0x02C5 -- jump to end of routine (STA $4011)
	emu.setState(state)
	emu.log("PollDevice(): HEX payload char = " .. char)
end

function ProcessingComplete()
	emu.displayMessage(script, "IPL processing complete!")
end

function BadChecksum()
	emu.displayMessage(script, "Wrong checksum in record.")
end

function BadRecordType()
	emu.displayMessage(script, "Record type not set to data type")
end

function ExecuteReset()
	emu.displayMessage(script, "Executing BIOS reset...")
end

function DiskWrite()
	emu.displayMessage(script, "Writing data to disk...")
end

function BadDiskWrite()
	emu.displayMessage(script, "Disk write failed.")
end

function DiskRead()
	emu.displayMessage(script, "Performing disk readback check...")
end

function ReadbackPassed()
	emu.displayMessage(script, "Disk readback check passed!")
end

function ReadbackFailed()
	emu.displayMessage(script, "Disk readback check failed.")
end

script = "IPL.LUA"

-- Intel HEX payload
idx = 1
hexPayload = ":02694200BEEFA6:00000001FF" -- default for when I/O fails

-- Attempt to read payload from "LuaScriptData/IPL/payload.hex"
function ReadPayloadFile()
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

-- IPL interface processing
emu.addMemoryCallback(PrepareIPL, emu.callbackType.exec, 0x052A)
emu.addMemoryCallback(ProcessDevice, emu.callbackType.exec, 0x0570)
emu.addMemoryCallback(PollDevice, emu.callbackType.exec, 0x029A)
emu.addMemoryCallback(ProcessingComplete, emu.callbackType.exec, 0x0348)
emu.addMemoryCallback(BadChecksum, emu.callbackType.exec, 0x031F)
emu.addMemoryCallback(BadChecksum, emu.callbackType.exec, 0x033B)
emu.addMemoryCallback(BadRecordType, emu.callbackType.exec, 0x0370)

-- Code execution
emu.addMemoryCallback(ExecuteReset, emu.callbackType.exec, 0x0588)

-- Disk I/O
emu.addMemoryCallback(DiskWrite, emu.callbackType.exec, 0x058B)
emu.addMemoryCallback(BadDiskWrite, emu.callbackType.exec, 0x0595)
emu.addMemoryCallback(DiskRead, emu.callbackType.exec, 0x0598)
emu.addMemoryCallback(ReadbackPassed, emu.callbackType.exec, 0x05A5)
emu.addMemoryCallback(ReadbackFailed, emu.callbackType.exec, 0x05A2)

emu.displayMessage("Script", script)
