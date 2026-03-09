module ledswitch(
    // Input: Slide Switch 0
    input wire [0:0] SW,
    // Output: Arduino Header Pin 0 (Digital Pin 0)
    inout wire [0:0] ARDUINO_IO,
	 inout wire [0:0] GPIO // Changed from ARDUINO_IO
);
    // ==========================================
    // LOGIC: Direct Connection
    // ==========================================
    // When SW[0] is UP (1), ARDUINO_IO[0] outputs 3.3V (HIGH)
    // When SW[0] is DOWN (0), ARDUINO_IO[0] outputs 0V (LOW)
    assign ARDUINO_IO[0] = SW[0];
	 // Control the pin on the long 40-pin header
    assign GPIO[0] = SW[0];
endmodule