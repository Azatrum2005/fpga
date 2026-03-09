module memristor_emulator (
    input clk,
    input rst_n,
    input signed [31:0] V_in,           // Input voltage (signed Q16.16)
    input [31:0] dt_in,                 // Time step in Q16.16 (seconds)
    
    output reg signed [31:0] I_out,     // Output current (signed Q16.16) 
    output reg [31:0] M_out,            // Memristance (unsigned Q16.16)
    output reg [31:0] x_out             // State variable (unsigned Q16.16)
);

    // Parameters
    parameter [31:0] Ron =  32'h13000000;       //32'h00640000; 
    parameter [31:0] Roff = 32'h4F000000;       //32'h3E800000;
    parameter [31:0] k_coeff = 32'h0000F000;
    parameter [31:0] x0 = 32'h00000400;         // h00001199 0.07 initial state
    parameter [31:0] p = 32'h00012000;          //in Q16.16
    parameter [31:0] j = 32'h00020000;          //in Q16.16
	 parameter [31:0] V_th = 32'h00004000; // 0.5V in Q16.16
    
    // Constants
    parameter [31:0] TWO = 32'h00020000;        // 2.0
    parameter [31:0] ONE = 32'h00010000;        // 1.0 in Q16.16
    parameter [31:0] HALF = 32'h00008000;       // 0.5 in Q16.16
    parameter [31:0] POINT_75 = 32'h0000C000;   // 0.75 in Q16.16
    
    // Internal registers
    reg [31:0] x;                // State variable (0 to 1 in Q16.16)
    reg [31:0] M;                // Memristance (unsigned Q16.16)
    reg signed [31:0] I;         // Current (signed Q16.16)
    reg [31:0] f;                // Window function (Q16.16)
    
    // Separate temporary calculation registers for each computation
    reg [63:0] temp64_M1, temp64_M2;
    reg signed [63:0] stemp64_I;
    reg [63:0] temp64_sq, temp64_first, temp64_second, temp64_f;
    reg [31:0] temp32_diff;
    reg [31:0] temp32_sq;
    reg [31:0] temp32_first;
    reg [31:0] temp32_second;
    reg signed [31:0] stemp32_centered;
    reg signed [31:0] dx;
    reg signed [31:0] abs_dx;

    // Window function intermediates
    reg [31:0] inner_term;
    reg [31:0] window_temp;

    // Sequential state update temporaries
    reg signed [63:0] stemp64_dx1, stemp64_dx2, stemp64_dx3;
    reg [63:0] temp64_x;

    // Initialize state
    initial begin
        x = x0;
        I = 0;
        M = Roff;
    end

    // Combinational: Calculate M, I, and f
    always @(*) begin
        // ===== 1. MEMRISTANCE: M(x) = Ron*x + Roff*(1-x) =====
        temp64_M1 = Ron * x;  //x;                    // Q16.16 * Q16.16 = Q32.32
        
        if (x <= ONE) begin
            temp64_M2 = Roff * (ONE - x);  //(ONE - x);       // Roff * (1-x)
            M = temp64_M1[47:16] + temp64_M2[47:16];
        end else begin
            M = Ron;                            // If x>1, clamp to Ron
        end
        
        // Ensure M stays in valid range
        if (M < Ron) M = Ron;
        if (M > Roff) M = Roff;
        M_out = M;
        
        //2. CURRENT: I = V / M (FIXED signed division) =====
        if (M > 32'h00001000) begin  // M > 0.0625Ω
            stemp64_I = $signed(V_in);          // Properly sign-extend
            stemp64_I = stemp64_I <<< 16;       // Arithmetic left shift
            
            // Divide by M (treat M as positive)
            stemp64_I = stemp64_I / $signed({1'b0, M});
            
            // Clamp to ±15mA (983 in Q16.16 = 0.015 * 65536)
            if (stemp64_I > 64'sd983) begin
                I = 32'sd983;
            end else if (stemp64_I < -64'sd983) begin
                I = -32'sd983;
            end else begin
                I = stemp64_I[31:0];
            end
        end else begin
            // M too small - return 15mA with sign of voltage
            if (V_in[31] == 1'b1) begin
                I = -32'sd983;
            end else begin
                I = 32'sd983;
            end
        end
        I_out = I;
        
        //3. WINDOW FUNCTION: f(x) = j * (1 - [(x-0.5)^2 + 0.75]^p) =====
        
        // Calculate (x - 0.5)
        if (x >= HALF) begin
            stemp32_centered = x - HALF;
        end else begin
            stemp32_centered = HALF - x;
        end
        
        // Square it: (x-0.5)^2
        temp64_sq = stemp32_centered * stemp32_centered;
        
        // Add 0.75: (x-0.5)^2 + 0.75
        inner_term = temp64_sq[47:16] + POINT_75;
        
        // Calculate inner_term^p using approximation
        // Calculate inner_term - 1
        if (inner_term > ONE) begin
            temp32_diff = inner_term - ONE;
        end else begin
            temp32_diff = ONE - inner_term;
        end

        // temp32_diff^2 for second order term
        temp64_sq = temp32_diff * temp32_diff;
        temp32_sq = temp64_sq[47:16];

        // First order: temp32_diff * (p - ONE)
        temp64_first = temp32_diff * (p - ONE);
        temp32_first = temp64_first[47:16];

        // Second order: temp32_sq * (p - ONE) * (p - TWO) / 2
        temp64_second = temp32_sq * (p - ONE);
        temp64_second = (temp64_second[47:16]) * (TWO - p);
        temp32_second = temp64_second[47:16] >> 1;

        // Combine: 1 + first_order - second_order
        if (inner_term > ONE) begin
            if (temp32_second > temp32_first) begin
                window_temp = ONE - (temp32_second - temp32_first);
            end else begin
                window_temp = ONE + (temp32_first - temp32_second);
            end
        end 
        else begin
            if ((temp32_first + temp32_second) >= ONE) begin
                window_temp = 32'h00000100;
            end else begin
                window_temp = ONE - temp32_first - temp32_second;
            end
        end
        
        // j * (1 - inner_term^p)
        temp64_f = window_temp * j;
        f = temp64_f[47:16];

        // Clamp f to non-negative and reasonable range
        if (f[31] == 1'b1) begin
            f = 32'h00000400;
        end
        if (f > ONE) begin
            f = ONE;
        end
        if (f < 32'h00000400) begin
            f = 32'h00000400;
        end
    end
    
	 reg is_above_threshold;
    reg signed [31:0] abs_V;
    
    always @(*) begin
        abs_V = (V_in[31]) ? -V_in : V_in;
        is_above_threshold = (abs_V > V_th);
    end
	 
    // Sequential: Update state x
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= x0;
        end else begin
            //STATE UPDATE: dx = k * V * f(x) =====
            if (is_above_threshold) begin
            // Calculate: V * f
            stemp64_dx1 = $signed(V_in) * $signed({1'b0, f});
            stemp64_dx2 = stemp64_dx1 >>> 16;
            
            // Multiply by base coefficient: k_coeff * V * f
            stemp64_dx2 = stemp64_dx2 * $signed({1'b0, k_coeff});
            stemp64_dx3 = stemp64_dx2 >>> 16;
            
            // CRITICAL: Multiply by time step dt
            stemp64_dx3 = stemp64_dx3 * $signed({1'b0, dt_in});
            dx = stemp64_dx3[47:16];
            
            // Get absolute value for safe arithmetic
            if (dx[31] == 1'b1) begin
                abs_dx = -dx;
            end else begin
                abs_dx = dx;
            end
            
            // Update x based on sign of dx
            if (dx[31] == 1'b0) begin
                // Positive dx: increase x (voltage > 0)
                temp64_x = x + abs_dx;
                if (temp64_x >= ONE) begin
                    x <= ONE;
                end else begin
                    x <= temp64_x[31:0];
                end
            end else begin
                if (abs_dx >= x) begin
                    x <= 32'h00000400;
                end else begin
                    x <= x - abs_dx;
                end
                
                // Enforce minimum
                if (x < 32'h00000400) begin
                    x <= 32'h00000400;
                end
            end
				
            end else begin
					dx = 0;
				end
            x_out <= x;
        end
    end
endmodule