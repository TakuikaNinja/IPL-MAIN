#include <SoftwareSerial.h>

// Configure software serial with inverted logic needed by Namco IPL
SoftwareSerial mySerial(2, 3, true);

void setup() {
  // init PC serial
  Serial.begin(19200);
  while (!Serial){;}
  
  // init Namco IPL serial
  mySerial.begin(38400);
}

void loop() {
  // read Intel HEX payload from PC
  String hexPayload = "";
  while (Serial.available() > 0) {
    char inChar = Serial.read();
    hexPayload += inChar;
  }

  // relay to Namco IPL if length changed
  if (hexPayload.length() != 0) {
    //Serial.print(hexPayload);
    mySerial.print(hexPayload);
  }
}
