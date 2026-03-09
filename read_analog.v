module read_analog(
    input           MAX10_CLK1_50, // 50 MHz System Clock
    output  [9:0]   LEDR,          // LEDs
    output  [7:0]   HEX0,          // Ones
    output  [7:0]   HEX1,          // Tens
    output  [7:0]   HEX2,          // Hundreds
    output  [7:0]   HEX3           // Thousands
);

    // ==========================================
    // 1. PLL and ADC Setup
    // ==========================================
    wire clk_10m, pll_locked;
    
    // NEW: Signal to tell us when data is actually ready
    wire adc_response_valid; 
    wire [11:0] raw_adc_data;

    sys_pll u_pll (
        .inclk0 (MAX10_CLK1_50),
        .c0     (clk_10m),
        .locked (pll_locked)
    );

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

    // ==========================================
    // 2. Data Latching (The Fix)
    // ==========================================
    reg [11:0] clean_adc_data;

    always @(posedge clk_10m) begin
        // Only update the stored value if the ADC says "Data is Valid"
        if (adc_response_valid) begin
            clean_adc_data <= raw_adc_data;
        end
    end

    // Use the CLEAN data for LEDs
    assign LEDR = clean_adc_data[11:2]; 

    // ==========================================
    // 3. Voltage Calculation
    // ==========================================
    reg [31:0] voltage_mv;
    
    always @(posedge clk_10m) begin
        // Use clean_adc_data instead of raw_adc_data
        voltage_mv <= (clean_adc_data * 5000) >> 12;
    end

    // ==========================================
    // 4. Digit Extraction
    // ==========================================
    wire [3:0] digit_1v   = (voltage_mv / 1000) % 10;
    wire [3:0] digit_100mv= (voltage_mv / 100) % 10;
    wire [3:0] digit_10mv = (voltage_mv / 10) % 10;
    wire [3:0] digit_1mv  = (voltage_mv) % 10;

    // ==========================================
    // 5. 7-Segment Decoder
    // ==========================================
    function [7:0] get_hex;
        input [3:0] num;
        begin
            // Active Low: 0 = ON, 1 = OFF
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

    // Assign to Outputs (Bit 7 is the Dot)
    assign HEX3 = get_hex(digit_1v) & 8'b01111111; // Dot ON
    assign HEX2 = get_hex(digit_100mv);
    assign HEX1 = get_hex(digit_10mv);
    assign HEX0 = get_hex(digit_1mv);

endmodule