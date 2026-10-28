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
  // relay Intel HEX payload from PC to Namco IPL
  if (Serial.available()) {
    char inChar = Serial.read();
    mySerial.print(inChar);
  }
}
