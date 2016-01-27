// n4fpga.v - Top level module for the ECE 544 Getting Started project
//
//
// Author:	Roy Kravitz
// Modified by:	Rehan Iqbal
// Organization: Portland State University
//
// Description:
// 
// This module provides the top level for the Getting Started hardware.
// The module assume that a PmodCLP is plugged into the JA and JB
// expansion ports and that a PmodENC is plugged into the JD expansion 
// port (bottom row).  
//
//////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module n4fpga (

    /******************************************************************/
    /* Top-level port declarations                                    */
    /******************************************************************/

    input               clk,                    // 100Mhz clock from on-board oscillator

    // Pushbuttons & switches

    input               btnC,                   // center pushbutton
    input               btnU,                   // up (North) pushbutton
    input               btnL,                   // left (West) pushbutton
    input               btnD,                   // down (South) pushbutton
    input               btnR,                   // right (East) pushbutton
    input               btnCpuReset,            // CPU reset pushbutton
    input   [15:0]      sw,                     // Nexys4 on-board slide switches

    // LEDs & 7-segment display

    output	[15:0] 		led,			        // Nexys4 on-board LEDs   
    output  [7:0]       an,                     // 7-segment display anodes
    output  [6:0]       seg,                    // 7-segment display segments 
    output              dp,                     // 7-segment display decimal points 
    
    // RGB LEDs

    output              RGB1_Blue,              // RGB1 LED (RefDes: LD16) 
    output              RGB1_Green,             // RGB1 LED (RefDes: LD16)
    output              RGB1_Red,               // RGB1 LED (RefDes: LD16)
    output              RGB2_Blue,              // RGB2 LED (RefDes: LD17)
    output              RGB2_Green,             // RGB2 LED (RefDes: LD17) 
    output              RGB2_Red,               // RGB2 LED (RefDes: LD17)

    // UART serial port (19200 baud)

    input				uart_rtl_rxd,	        // USB UART Rx
    output				uart_rtl_txd,	        // USB UART Tx
    
    // Pmod connectors

    output	[7:0] 		JA,		                // PmodCLP data bus (both rows used)
    output	[7:0] 		JB,				        // PmodCLP control signals (bottom row only)
    output	[7:0] 		JC,                     // debug signals (bottom row only)
	input	[7:0]		JD);                    // PmodENC signals

    /******************************************************************/
    /* Local parameters and variables                                 */
    /******************************************************************/

    // Global signals

    wire				sysclk;                 // 100MHz system clock
    wire                clk_100mhz;             // 100MHz clock generated by EMBSYS
    wire				sysreset_n;             // active-low reset signal for Microblaze
    wire                sysreset;               // active-high reset signal for any logic blocks

    // Connections between Pmod JD <--> rotary encoder

    wire				rotary_a;               // quadrature-encoded A input from encoder
    wire                rotary_b;               // quadrature-encoded B input from encoder
    wire                rotary_press;           // debounced pushbutton from encoder; stored in ROTLCD_STS register
    wire                rotary_sw;              // debounced slide switch from encoder; stored in ROTLCD_STS register

    // Connections between Pmod JA/JB/JC <--> LCD display

    wire	[7:0]		lcd_d;                  // 8-bit data bus to the display
    wire				lcd_rs;                 // Register select: high for data transfer, low for instruction register
    wire                lcd_rw;                 // Read/write signal: high for read mode, low for write mode
    wire                lcd_e;                  // Read/write strobe: high for read OE; falling edge writes data

    // Connections between AXI Timer <--> GPIO

    wire	[7:0]	    gpio_in;				// GPIO input port for EMBSYS
    wire	[7:0]	    gpio_out;				// GPIO output port for EMBSYS

    wire                pwm_out;                // AXI Timer PWM --> GPIO input

    // Connections between hw_detect <--> GPIO

    wire    [31:0]      high_count;             // how long PWM was 'high'
    wire    [31:0]      low_count;              // how long PWM was 'low'

    /******************************************************************/
    /* Global Assignments                                             */
    /******************************************************************/

    // global signals

    assign sysclk = clk;
    assign sysreset_n = btnCpuReset;        // active-low reset signal for Microblaze
    assign sysreset = ~sysreset_n;          // active-high reset signal for any logic blocks

    // 20kHz signal from FIT interrupt routine (used for debugging)

    wire   clk_20khz;
    assign clk_20khz = gpio_out[0];

    // PWM output on led[15]; Microblaze controls LEDs via Nexys4IO block
    // so we write '0' and OR with PWM output
    
    wire   [15:0]      led_int;                                    // Nexys4IO drives these outputs
    assign led = {(pwm_out | led_int[15]), led_int[14:0]};         // LEDs are driven by led

    // output LCD signals to ports JA/JB/JC

    assign JA = lcd_d[7:0];                                                     // 8-bit data bus (both rows used)
    assign JB = {1'b0, lcd_e, lcd_rw, lcd_rs, 2'b00, clk_20khz, pwm_out};       // control signals (bottom row only)
    assign JC = {lcd_e, lcd_rs, lcd_rw, 1'b0, lcd_d[3:0]};                      // debug signals (bottom row only)

    // input rotary signals from port JD

    assign rotary_a = JD[5];                // quadrature-encoded A input from encoder
    assign rotary_b = JD[4];                // quadrature-encoded B input from encoder
    assign rotary_press = JD[6];            // pushbutton from encoder; stored in ROTLCD_STS register
    assign rotary_sw = JD[7];               // slide switch from encoder; stored in ROTLCD_STS register

    // wrap the pwm_out from the timer back to the application for software pulse-width detect

    assign gpio_in = {7'b0000000, pwm_out};

    /******************************************************************/
    /* hw_detect instantiation                                        */
    /******************************************************************/

    hw_detect HWDET (

        .clock              (clk_100mhz),       // I [ 0 ] 100MHz system clock
        .reset              (sysreset),         // I [ 0 ] active-high reset signal from Nexys4
        .pwm                (pwm_out),          // I [ 0 ] PWM signal from AXI Timer in EMBSYS

        .high_count         (high_count),       // O [31:0] how long PWM was 'high' --> GPIO input on Microblaze
        .low_count          (low_count));       // O [31:0] how long PWM was 'low' --> GPIO input on Microblaze
    			
    /******************************************************************/
    /* EMBSYS instantiation                                           */
    /******************************************************************/

    system EMBSYS (

        // Global signals
        
        .sysreset_n                 (sysreset_n),       // I [ 0 ] active-low reset signal for Microblaze
        .sysclk                     (sysclk),           // I [ 0 ] 100MHz clock from on-board oscillator
        .clk_100mhz                 (clk_100mhz),       // O [ 0 ] 100MHz clock from ClockWiz module

        // Connections with LCD display

        .PmodCLP_DataBus            (lcd_d),            // O [7:0] 8-bit data bus to the display
        .PmodCLP_E                  (lcd_e),            // O [ 0 ] Read/write strobe: high for read OE; falling edge writes data
        .PmodCLP_RS                 (lcd_rs),           // O [ 0 ] Register select: high for data transfer, low for instruction register
        .PmodCLP_RW                 (lcd_rw),           // O [ 0 ] Read/write signal: high for read mode, low for write mode

        // Connections with rotary encoder

        .PmodENC_A                  (rotary_a),         // I [ 0 ] quadrature-encoded A input from encoder
        .PmodENC_B                  (rotary_b),         // I [ 0 ] quadrature-encoded B input from encoder
        .PmodENC_BTN                (rotary_press),     // I [ 0 ] debounced pushbutton from encoder; stored in ROTLCD_STS register
        .PmodENC_SWT                (rotary_sw),        // I [ 0 ] debounced slide switch fromencoder; stored in ROTLCD_STS register

        // Connections with RGB LEDs

        .RGB1_Blue                  (RGB1_Blue),        // O [ 0 ] tri-color LED (RefDes: LD16)
        .RGB1_Green                 (RGB1_Green),       // O [ 0 ] tri-color LED (RefDes: LD16)
        .RGB1_Red                   (RGB1_Red),         // O [ 0 ] tri-color LED (RefDes: LD16)
        .RGB2_Blue                  (RGB2_Blue),        // O [ 0 ] tri-color LED (RefDes: LD17)
        .RGB2_Green                 (RGB2_Green),       // O [ 0 ] tri-color LED (RefDes: LD17)
        .RGB2_Red                   (RGB2_Red),         // O [ 0 ] tri-color LED (RefDes: LD17)

        // Connections with pushbuttons & switches

        .btnC                       (btnC),             // I [ 0 ]  center pushbutton input
        .btnD                       (btnD),             // I [ 0 ]  down pushbutton input
        .btnL                       (btnL),             // I [ 0 ]  left pushbutton input
        .btnR                       (btnR),             // I [ 0 ]  right pushbutton input 
        .btnU                       (btnU),             // I [ 0 ]  up pushbutton input
        .sw                         (sw),               // I [15:0] slide switch inputs

        // Connections with LEDs & 7-segment display

        .dp                         (dp),               // O [ 0 ]  7-segment display decimal points
        .an                         (an),               // O [7:0]  7-segment display anodes
        .seg                        (seg),              // O [6:0]  7-segment display segments
        .led                        (led_int),          // O [15:0] Nexys4 on-board LEDs

        // Connections with UART

        .uart_rtl_rxd               (uart_rtl_rxd),     // I [ 0 ] USB UART Rx (19200 baud)
        .uart_rtl_txd               (uart_rtl_txd),     // O [ 0 ] USB UART Tx (19200 baud)

        // Connections with GPIO

        .gpio_0_GPIO2_tri_o         (gpio_out),         // O [7:0] GPIO output port; AXI Timer 'clk_20khz' --> bit[0]
        .gpio_0_GPIO_tri_i          (gpio_in),          // I [7:0] GPIO input port; AXI Timer 'pwm_out' --> bit[0]
        
        .gpio_1_GPIO_tri_i          (high_count),       // I [7:0] GPIO input port
        .gpio_1_GPIO2_tri_i         (low_count),        // I [7:0] GPIO input port

        // Connections with AXI Timer

        .pwm0                       (pwm_out));         // O [ 0 ] AXI Timer's PWM output signal

endmodule