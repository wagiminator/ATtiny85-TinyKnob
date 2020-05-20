// tinyKnob
//
// USB volume control for ATtiny45/85 using rotary encoder and v-usb interface based
// on several examples from https://www.obdev.at/products/vusb/projects.html
// Recent project files can be found at https://easyeda.com/wagiminator
// This work is licensed under Creative Commons Attribution-ShareAlike 3.0 Unported License
// http://creativecommons.org/licenses/by-sa/3.0/
//
// 2020 by Stefan Wagner

// CPU clock
#define F_CPU       16500000        	// 16.5 MHz

// Libraries
#include <avr/io.h>
#include <avr/wdt.h>
#include <avr/interrupt.h>
#include <avr/pgmspace.h>
#include <util/delay.h>
#include "usbdrv.h"
#include "oddebug.h"

// Rotary encoder pins
#define ENC_SW      0b00000010      	// PB1
#define ENC_A       0b00001000      	// PB3
#define ENC_B       0b00010000      	// PB4

// Keyboard codes
#define VOLUMEMUTE  0xE2            	// Keyboard Volume Mute
#define VOLUMEUP    0xE9	        	// Keyboard Volume Up
#define VOLUMEDOWN  0xEA	        	// Keyboard Volume Down

// USB report descriptor
PROGMEM const char usbHidReportDescriptor[USB_CFG_HID_REPORT_DESCRIPTOR_LENGTH] = {
    0x05, 0x0c,							// USAGE_PAGE (Consumer Devices)
    0x09, 0x01,							// USAGE (Consumer Control)
    0xa1, 0x01,							// COLLECTION (Application)
    0x85, 0x01,							//   REPORT_ID (1)
    0x19, 0x00,							//   USAGE_MINIMUM (Unassigned)
    0x2a, 0x3c, 0x02,					//   USAGE_MAXIMUM (AC Format)
    0x15, 0x00,							//   LOGICAL_MINIMUM (0)
    0x26, 0x3c, 0x02,					//   LOGICAL_MAXIMUM (572)
    0x95, 0x01,							//   REPORT_COUNT (1)
    0x75, 0x10,							//   REPORT_SIZE (16)
    0x81, 0x00,							//   INPUT (Data,Var,Abs)
    0xc0								// END_COLLECTION
};

// Variables
static uchar reportBuffer[3] = {1,0,0};	// buffer for HID reports
static uchar idleRate;	            	// in 4 ms units
static uchar currentKey;		    	// current key to be sent
static uchar isSwitchPressed = 0;   	// state of rotary encoder switch


// Check rotary encoder
static void checkEncoder(void) {
    currentKey = 0;
	// Encoder turned ?
	if (!(PINB & ENC_A)) {
		// Clockwise ?
		if (PINB & ENC_B) currentKey = VOLUMEUP;
		else              currentKey = VOLUMEDOWN;
		// Wait until next detent
		while (!(PINB & ENC_A)) _delay_ms(5);
	} else {
	    // Mute button previously pressed ?
	    if (!isSwitchPressed && !(PINB & ENC_SW)) {
	        currentKey = VOLUMEMUTE;
	        isSwitchPressed = 1;
	        _delay_ms(5);
	    } else if (isSwitchPressed && (PINB & ENC_SW)) {
			isSwitchPressed = 0;
			_delay_ms(5);
		}
    }
}


uchar usbFunctionSetup(uchar data[8]) {
    usbRequest_t *rq = (void *)data;
    usbMsgPtr = reportBuffer;
    if ((rq->bmRequestType & USBRQ_TYPE_MASK) == USBRQ_TYPE_CLASS){
        if (rq->bRequest == USBRQ_HID_GET_REPORT) { 
            return sizeof(reportBuffer);
        } else if (rq->bRequest == USBRQ_HID_GET_IDLE) {
            usbMsgPtr = &idleRate;
            return 1;
        } else if (rq->bRequest == USBRQ_HID_SET_IDLE) {
            idleRate = rq->wValue.bytes[1];
        }
    }
	return 0;
}


// Oscillator calibration
static void calibrateOscillator(void) {
    uchar step = 128;
    uchar trialValue = 0, optimumValue;
    int   x, optimumDev, targetValue = (unsigned)(1499 * (double)F_CPU / 10.5e6 + 0.5);

    do {
        OSCCAL = trialValue + step;
        x = usbMeasureFrameLength();
        if (x < targetValue)
            trialValue += step;
        step >>= 1;
    } while(step > 0);

    optimumValue = trialValue;
    optimumDev = x;
    for (OSCCAL = trialValue - 1; OSCCAL <= trialValue + 1; OSCCAL++) {
        x = usbMeasureFrameLength() - targetValue;
        if (x < 0) x = -x;
        if (x < optimumDev) {
            optimumDev = x;
            optimumValue = OSCCAL;
        }
    }
    OSCCAL = optimumValue;
}


void usbEventResetReady(void) {
    calibrateOscillator();
}


int main(void) {
    usbInit();
    usbDeviceDisconnect();
    uchar i = 0;
    while(--i) {
        wdt_reset();
        _delay_ms(1);
    }
    usbDeviceConnect();
    wdt_enable(WDTO_1S);

	// turn on internal pull-up resistors for rotary encoder
    PORTB |= ENC_A | ENC_B | ENC_SW;

    sei();

    while(1) {
        wdt_reset();
        usbPoll();
		checkEncoder();
		if(usbInterruptIsReady() && (reportBuffer[1] != currentKey)) {
        	reportBuffer[1] = currentKey;
           	usbSetInterrupt(reportBuffer, sizeof(reportBuffer));
        }
	}
   	return 0;
}
