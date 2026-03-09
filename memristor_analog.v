module memristor_analog(
    input           MAX10_CLK1_50, // 50 MHz System Clock
    output  [9:0]   LEDR,          // LEDs (Visualizing State x)
	 
    output  [7:0]   HEX5,          
    output  [7:0]   HEX4,          
    output  [7:0]   HEX3,
	 
    output  [7:0]   HEX2,          
    output  [7:0]   HEX1,          
    output  [7:0]   HEX0,
	 inout   [1:0]   ARDUINO_IO
);

    //PLL and ADC Hardware Setup
    wire clk_10m, pll_locked;
    wire adc_response_valid; 
    wire [11:0] raw_adc_data;

    // Instantiate the PLL(50MHz->10MHz)
    sys_pll u_pll (
        .inclk0 (MAX10_CLK1_50),
        .c0     (clk_10m),
        .locked (pll_locked)
    );

    // Instantiate the ADC
    adc u0 (
        .clock_clk              (clk_10m),       
        .reset_sink_reset_n     (pll_locked),    
        .adc_pll_clock_clk      (clk_10m),       
        .adc_pll_locked_export  (pll_locked),    
        
        .command_valid          (1'b1),          
        .command_channel        (5'd1),          // Channel 1 = Arduino A0
        .command_startofpacket  (1'b1),
        .command_endofpacket    (1'b1),
        .command_ready          (),              

        .response_valid         (adc_response_valid),      
        .response_data          (raw_adc_data),
        .response_startofpacket (),
        .response_endofpacket   ()       
    );
	 
    //Data Cleaning & Conversion
    reg [11:0] clean_adc_data;

    always @(posedge clk_10m) begin
        if (adc_response_valid) begin
            clean_adc_data <= raw_adc_data; // 12 bit adc value 0-4095
        end
    end
    
	 // Clock Divider
    reg [15:0] clk_counter;
    reg clk_1k; // This will act as the clock for the memristor

    always @(posedge clk_10m) begin
        if (clk_counter >= 5000) begin
            clk_counter <= 0;
            clk_1k <= ~clk_1k; // Toggle High/Low
        end else begin
            clk_counter <= clk_counter + 1;
        end
    end
	 
    // Convert ADC (0-4095) to Q16.16 Voltage
    // 5.0V in Q16.16 is approx 327680
    // Factor: 327680/4095 = 80
    // V_in_q16 = clean_adc*80
    // 1. Calculate the absolute 0-5V voltage first
    wire signed [31:0] abs_voltage_q16;
    assign abs_voltage_q16 = {17'b0, clean_adc_data, 3'b0};  //{18'b0,clean_adc_data, 2'b0} + {17'b0, clean_adc_data, 3'b0}; //{15'b0, clean_adc_data, 4'b0}; //{14'b0, clean_adc_data, 6'b0} + {16'b0, clean_adc_data, 4'b0}; //{15'b0, clean_adc_data, 5'b0} + {16'b0, clean_adc_data, 4'b0};
    
	 //Memristor Emulation
    wire signed [31:0] I_out;
    wire [31:0] M_out;
    wire [31:0] x_out;
	 
    // 2. Define 2.5V in Q16.16 format (2.5 * 65536 = 163840)
	 reg signed [31:0] V_BIAS = 32'd0;  //32'd26214; //32'd19661;  //32'd32768;  //32'd65536;  //32'd163840;
	 reg c = 0;
	 
    // 3. Subtract 2.5V. 
	 wire signed [31:0] V_in_q16;
    assign V_in_q16 = abs_voltage_q16 - V_BIAS;

    // Time step (dt). 
    // Q16.16 representation of a small time step
    // 0.0001 * 65536 approx 6.5 -> Let's use 7
    wire [31:0] dt_val = 32'd310;
    
    memristor_emulator u_mem (
        .clk    (clk_1k),   //(clk_10m),    // (clk_1k),   //
        .rst_n  (pll_locked), // Reset if PLL unlocks
        .V_in   (V_in_q16),   // Voltage from ADC
        .dt_in  (dt_val),     // Simulation speed
        .I_out  (I_out),
        .M_out  (M_out),      // Resulting Resistance
        .x_out  (x_out)       // Internal state
    );
	 
	 always @(posedge clk_1k) begin
		  if (M_out < 32'd65536000*5) begin
				c = 1;
        end
		  if (M_out > 32'd1304166400) begin     //32'd1028915200
				c = 0;
        end
        if (c == 1) begin
            V_BIAS = 32'd19700;  //32'd32441;
        end 
		  if (c == 0) begin
            V_BIAS = 32'd0;
        end 
    end
	 
	 wire post_spike;
	 wire signed [31:0] V_mem;
	 wire [31:0]C_inv = 100000;
	 lif_neuron soma (
        .clk(clk_1k),
        .rst_n(pll_locked),
        .I_in(I_out* C_inv),    //the current from the memristor
        .dt_in(dt_val),        
        .spike_out(post_spike), 
        .V_mem(V_mem)      
    );

    reg [6:0] led_timer = 0;
    reg led_visible;

    always @(posedge clk_1k) begin
        if (post_spike == 1'b1) begin
            led_timer <= 10;      // Set timer ms
            led_visible <= 1'b1;  
        end else if (led_timer > 0) begin
            led_timer <= led_timer - 1; // Count down
        end else begin
            led_visible <= 1'b0;
        end
    end
    assign ARDUINO_IO[1] = led_visible;
	 //assign ARDUINO_IO[1] = post_spike;
	 
	 memristor_uart_bridge u_bridge_M (
        .clk(MAX10_CLK1_50),
        .data_in(M_out),  
        .tx_line(ARDUINO_IO[0]) // Pin D1
    );
	 
	
    // Display State on LEDs (x is 0.0 to 1.0 in Q16.16)
    // Top 10 bits of fraction part gives a 0-1024 range ideal for LEDs
    assign LEDR = x_out[15:6]; 
    //LEDR[0] = ARDUINO_IO[0];
    //Voltage Display Calculation (HEX 5,4,3)
    // Calculate Millivolts for display: (ADC * 5000) / 4096
    reg [31:0] voltage_mv;
    always @(posedge clk_10m) voltage_mv <= (abs_voltage_q16*1000) >> 16; //(clean_adc_data * 5000) >> 12;  //(V_in_q16 * 32'd1000) >>> 16;  //

    wire [3:0] v_digit_1v   = (voltage_mv / 1000) % 10;
    wire [3:0] v_digit_100m = (voltage_mv / 100) % 10;
    wire [3:0] v_digit_10m  = (voltage_mv / 10) % 10;

    // Resistance Display Calculation (HEX 2,1,0)
    // M_out is in Q16.16 Ohms. 
    // 1. Shift right 16 to get Integer Ohms.
    // 2. We want to display kOhms (e.g. 15.2 kOhms).
    // Formula: Val = Integer_Ohms / 100. (Gives 152 for 15200 ohms)
    reg [31:0] res_display_val;
    always @(posedge clk_10m) begin
        // (M_out >> 16) is Ohms. Divide by 100 to get "hundreds of ohms"
        res_display_val <= (M_out >> 16) / 100;
    end

    wire [3:0] r_digit_10k = (res_display_val / 100) % 10; // 10k place
    wire [3:0] r_digit_1k  = (res_display_val / 10) % 10;  // 1k place
    wire [3:0] r_digit_dec = (res_display_val) % 10;       // 0.1k place

    // 7-Segment Decoder
    function [7:0] get_hex;
        input [3:0] num;
        begin
            case (num)
                4'h0: get_hex = 8'b11000000; 
                4'h1: get_hex = 8'b11111001; 
                4'h2: get_hex = 8'b10100100; 
                4'h3: get_hex = 8'b10110000; 
                4'h4: get_hex = 8'b10011001; 
                4'h5: get_hex = 8'b10010010; 
                4'h6: get_hex = 8'b10000010; 
                4'h7: get_hex = 8'b11111000; 
                4'h8: get_hex = 8'b10000000; 
                4'h9: get_hex = 8'b10010000; 
                default: get_hex = 8'b11111111; 
            endcase
        end
    endfunction

    // Voltage Output
    assign HEX5 = get_hex(v_digit_1v) & 8'b01111111; // Dot ON (3.)
    assign HEX4 = get_hex(v_digit_100m);             // (3)
    assign HEX3 = get_hex(v_digit_10m);              // (0)

    // Resistance Output in kOhms
    assign HEX2 = get_hex(r_digit_10k);              // (1)
    assign HEX1 = get_hex(r_digit_1k) & 8'b01111111; // Dot ON (6.)
    assign HEX0 = get_hex(r_digit_dec);              // (0)

endmodule