# Name: 	makefile
# Project: 	tinyKnob
# Author: 	Stefan Wagner
# Year: 	2020
# URL:		https://easyeda.com/wagiminator
#
# type "make help" in the command line

# Microcontroller Options
DEVICE 	= attiny85
CLOCK	= 16500000
PROGRMR = usbtiny
HFUSE	= 0xdd
LFUSE	= 0xe1

# Commands
AVRDUDE = avrdude -c $(PROGRMR) -p $(DEVICE)
COMPILE = avr-gcc -Wall -Os -Iusbdrv -I. -mmcu=$(DEVICE) -DF_CPU=$(CLOCK) -DDEBUG_LEVEL=0
OBJECTS = usbdrv/usbdrv.o usbdrv/usbdrvasm.o usbdrv/oddebug.o main.o
CLEAN	= rm -f main.lst main.obj main.cof main.list main.map main.eep.hex *.o usbdrv/*.o main.s usbdrv/oddebug.s usbdrv/usbdrv.s

# Symbolic Targets
all:	help

help:
	@echo "Use the following commands:"
	@echo "make hex	compile and build main.hex for $(DEVICE)"
	@echo "make asm	compile and disassemble to main.asm for $(DEVICE)"
	@echo "make bin	compile and build main.bin for $(DEVICE)"
	@echo "make upload	compile and upload to $(DEVICE) using $(PROGRMR)"
	@echo "make fuses	burn fuses of $(DEVICE) using $(PROGRMR) programmer"
	@echo "make install	compile, upload and burn fuses for $(DEVICE)"
	@echo "make clean	remove all build files"

bin:	$(OBJECTS)
	@echo "Building main.bin ..."
	@$(COMPILE) -o main.bin $(OBJECTS)
	@echo "Removing temporary files ..."
	@$(CLEAN)

hex:	bin
	@echo "Building main.hex ..."
	@avr-objcopy -j .text -j .data -O ihex main.bin main.hex
	@echo "FLASH: $(shell avr-size -d main.bin | awk '/[0-9]/ {print $$1 + $$2}') bytes"
	@echo "SRAM:  $(shell avr-size -d main.bin | awk '/[0-9]/ {print $$2 + $$3}') bytes"

asm:	bin
	@echo "Disassembling to main.asm ..."
	@avr-objdump -d main.bin > main.asm

upload:	hex
	@echo "Uploading to $(DEVICE) ..."
	@$(AVRDUDE) -U flash:w:main.hex:i

fuses:
	@echo "Burning fuses of $(DEVICE) ..."
	@$(AVRDUDE) -U hfuse:w:$(HFUSE):m -U lfuse:w:$(LFUSE):m

install: upload fuses

clean:
	@echo "Cleaning all up ..."
	@$(CLEAN)
	@rm -f main.bin main.hex main.asm

.c.o:
	@echo "Compiling $< for $(DEVICE) @ $(CLOCK)Hz ..."
	@$(COMPILE) -c $< -o $@

.S.o:
	@echo "Compiling $< for $(DEVICE) @ $(CLOCK)Hz ..."
	@$(COMPILE) -x assembler-with-cpp -c $< -o $@

.c.s:
	@echo "Compiling $< for $(DEVICE) @ $(CLOCK)Hz ..."
	@$(COMPILE) -S $< -o $@