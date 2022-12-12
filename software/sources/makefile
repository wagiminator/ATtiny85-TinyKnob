# ===================================================================================
# Project:  tinyKnob
# Author:   Stefan Wagner
# Year:     2020
# URL:      https://github.com/wagiminator
# ===================================================================================
# Type "make help" in the command line.
# ===================================================================================

# Input and Output File Names
SKETCH   = main.c
TARGET   = tinyknob

# Microcontroller Settings
DEVICE  ?= attiny85
CLOCK    = 16500000
HFUSE    = 0xdd
LFUSE    = 0xe1

# Programmer Settings
PROGRMR ?= usbasp

# Toolchain
CC       = avr-gcc
OBJCOPY  = avr-objcopy
OBJDUMP  = avr-objdump
AVRSIZE  = avr-size
AVRDUDE  = avrdude -c $(PROGRMR) -p $(DEVICE)
CLEAN    = rm -f main.lst main.obj main.cof main.list main.map main.eep.hex *.o usbdrv/*.o main.s usbdrv/oddebug.s usbdrv/usbdrv.s

# Objects
OBJECTS  = usbdrv/usbdrv.o usbdrv/usbdrvasm.o usbdrv/oddebug.o main.o

# Compiler Flags
CFLAGS   = -Wall -Os -Iusbdrv -I. -mmcu=$(DEVICE) -DF_CPU=$(CLOCK) -DDEBUG_LEVEL=0

# Symbolic Targets
help:
	@echo "Use the following commands:"
	@echo "make all       compile and build $(TARGET).elf/.bin/.hex/.asm for $(DEVICE)"
	@echo "make hex       compile and build $(TARGET).hex for $(DEVICE)"
	@echo "make asm       compile and disassemble to $(TARGET).asm for $(DEVICE)"
	@echo "make bin       compile and build $(TARGET).bin for $(DEVICE)"
	@echo "make upload    compile and upload to $(DEVICE) using $(PROGRMR)"
	@echo "make fuses     burn fuses of $(DEVICE) using $(PROGRMR) programmer"
	@echo "make install   compile, upload and burn fuses for $(DEVICE)"
	@echo "make clean     remove all build files"

all:	buildelf buildbin buildhex buildasm removetemp size

elf:	buildelf removetemp size

bin:	buildelf buildbin removetemp size removeelf

hex:	buildelf buildhex removetemp size removeelf

asm:	buildelf buildasm removetemp size removeelf

flash:	upload fuses

install: upload fuses

upload:	hex
	@echo "Uploading $(TARGET).hex to $(DEVICE) using $(PROGRMR) ..."
	@$(AVRDUDE) -U flash:w:$(TARGET).hex:i

fuses:
	@echo "Burning fuses of $(DEVICE) ..."
	@$(AVRDUDE) -U lfuse:w:$(LFUSE):m  -U hfuse:w:$(HFUSE):m

clean:
	@echo "Cleaning all up ..."
	@$(CLEAN)
	@rm -f $(TARGET).elf $(TARGET).bin $(TARGET).hex $(TARGET).asm

buildelf:	$(OBJECTS)
	@echo "Building $(TARGET).elf ..."
	@$(CC) $(CFLAGS) -o $(TARGET).elf $(OBJECTS)

buildbin:
	@echo "Building $(TARGET).bin ..."
	@$(OBJCOPY) -O binary -R .eeprom $(TARGET).elf $(TARGET).bin

buildhex:
	@echo "Building $(TARGET).hex ..."
	@$(OBJCOPY) -j .text -j .data -O ihex $(TARGET).elf $(TARGET).hex

buildasm:
	@echo "Disassembling to $(TARGET).asm ..."
	@$(OBJDUMP) -d $(TARGET).elf > $(TARGET).asm

size:
	@echo "------------------"
	@echo "FLASH: $(shell $(AVRSIZE) -d $(TARGET).elf | awk '/[0-9]/ {print $$1 + $$2}') bytes"
	@echo "SRAM:  $(shell $(AVRSIZE) -d $(TARGET).elf | awk '/[0-9]/ {print $$2 + $$3}') bytes"
	@echo "------------------"

removetemp:
	@echo "Removing temporary files ..."
	@$(CLEAN)

removeelf:
	@echo "Removing $(TARGET).elf ..."
	@rm -f $(TARGET).elf

.c.o:
	@echo "Compiling $< for $(DEVICE) @ $(CLOCK)Hz ..."
	@$(CC) $(CFLAGS) -c $< -o $@

.S.o:
	@echo "Compiling $< for $(DEVICE) @ $(CLOCK)Hz ..."
	@$(CC) $(CFLAGS) -x assembler-with-cpp -c $< -o $@

.c.s:
	@echo "Compiling $< for $(DEVICE) @ $(CLOCK)Hz ..."
	@$(CC) $(CFLAGS) -S $< -o $@
