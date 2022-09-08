# TinyKnob - Rotary Encoder with USB Interface
TinyKnob is a rotary encoder with a USB interface based on the ATtiny45/85 and the V-USB software-only implementation of USB1.1 devices on AVR microcontrollers (https://www.obdev.at/products/vusb/index.html). The example code implements a volume control knob for PCs which works without installing any driver by acting like a generic HID device.

![TinyKnob_pic1.jpg](https://raw.githubusercontent.com/wagiminator/ATtiny85-TinyKnob/master/documentation/TinyKnob_pic1.jpg)

# Compiling and Uploading the Firmware
## If using the precompiled hex-file
- Make sure you have installed [avrdude](https://learn.adafruit.com/usbtinyisp/avrdude).
- Connect your programmer to your PC and to the ICSP header on the board.
- Open a terminal.
- Navigate to the folder with the hex-file.
- Execute the following command (if necessary replace "t85" with your chip and "usbasp" with the programmer you use):
  ```
  avrdude -c usbasp -p t85 -U flash:w:tinyknob.hex -U lfuse:w:0xe1:m -U hfuse:w:0xdd:m
  ```

## If using the makefile (Linux/Mac)
- Make sure you have installed [avr-gcc toolchain and avrdude](http://maxembedded.com/2015/06/setting-up-avr-gcc-toolchain-on-linux-and-mac-os-x/).
- Connect your programmer to your PC and to the ICSP header on the board.
- Open the makefile and change the chip if you are not using ATtiny85 and the programmer if you are not using usbasp.
- Open a terminal.
- Navigate to the folder with the makefile and the Arduino sketch.
- Run "make install" to compile, burn the fuses and upload the firmware.

# References, Links and Notes
1. [ATtiny25/45/85 Datasheet](https://ww1.microchip.com/downloads/en/DeviceDoc/Atmel-2586-AVR-8-bit-Microcontroller-ATtiny25-ATtiny45-ATtiny85_Datasheet.pdf)
2. [V-USB Info](https://www.obdev.at/products/vusb/index.html)

![TinyKnob_pic2.jpg](https://raw.githubusercontent.com/wagiminator/ATtiny85-TinyKnob/master/documentation/TinyKnob_pic2.jpg)
![TinyKnob_pic3.jpg](https://raw.githubusercontent.com/wagiminator/ATtiny85-TinyKnob/master/documentation/TinyKnob_pic3.jpg)

# License
![license.png](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)

This work is licensed under Creative Commons Attribution-ShareAlike 3.0 Unported License. 
(http://creativecommons.org/licenses/by-sa/3.0/)
