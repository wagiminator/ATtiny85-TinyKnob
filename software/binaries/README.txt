Change "t85" to "t45" if using ATtiny45.

avrdude -c usbtiny -p t85 -U flash:w:tinyknob.hex -U lfuse:w:0xe1:m -U hfuse:w:0xdd:m
