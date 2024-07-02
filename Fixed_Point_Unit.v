`include "Defines.vh"

module Fixed_Point_Unit 
#(
    parameter WIDTH = 32,
    parameter FBITS = 10
)
(
    input wire clk,
    input wire reset,
    
    input wire [WIDTH - 1 : 0] operand_1,
    input wire [WIDTH - 1 : 0] operand_2,
    
    input wire [ 1 : 0] operation,

    output reg [WIDTH - 1 : 0] result,
    output reg ready
);

    // Main operation logic
    always @(*)
    begin
        case (operation)
            `FPU_ADD    : begin 
                result <= operand_1 + operand_2; 
                ready <= 1; 
            end
            `FPU_SUB    : begin 
                result <= operand_1 - operand_2; 
                ready <= 1; 
            end
            `FPU_MUL    : begin 
                result <= product[WIDTH + FBITS - 1 : FBITS]; 
                ready <= product_ready; 
            end
            `FPU_SQRT   : begin 
                result <= sqrt_result; 
                ready <= sqrt_done; 
            end
            default     : begin 
                result <= 'bz; 
                ready <= 0; 
            end
        endcase
    end

    // Ready signal reset logic
    always @(posedge reset)
    begin
        if (reset)  
            ready = 0;
        else        
            ready = 'bz;
    end

    // ------------------- //
    // Square Root Circuit //
    // ------------------- //
    reg [WIDTH - 1 : 0] sqrt_result;
    reg sqrt_done;

    // Define states for the square root state machine
    localparam SQRT_IDLE = 2'b00, SQRT_START = 2'b01, SQRT_CALC = 2'b10, SQRT_DONE = 2'b11;

    reg [1 : 0] sqrt_state, sqrt_next_state;

    reg sqrt_init;
    reg sqrt_busy;

    // Registers for the square root algorithm
    reg [WIDTH - 1 : 0] remainder, remainder_next;     // Current remainder
    reg [WIDTH - 1 : 0] quotient, quotient_next;       // Current result
    reg [WIDTH + 1 : 0] acc, acc_next;                 // Accumulator
    reg [WIDTH + 1 : 0] test_sub;                      // Test subtraction result

    reg [4 : 0] iter_count = 0;

    // State transition logic
    always @(posedge clk) 
    begin
        if (operation == `FPU_SQRT)
            sqrt_state <= sqrt_next_state;
        else
            sqrt_state <= SQRT_IDLE;
            sqrt_done <= 0;
    end 

    // Next state and control signal logic
    always @(*) 
    begin
        sqrt_next_state = sqrt_state;
        case (sqrt_state)
            SQRT_IDLE: 
                if (operation == `FPU_SQRT)
                begin
                    sqrt_next_state = SQRT_START;
                    sqrt_init <= 0;
                end
            SQRT_START:
            begin
                sqrt_next_state = SQRT_CALC;
                sqrt_init <= 1;
            end
            SQRT_CALC:
            begin
                if (iter_count == ((WIDTH + FBITS) >> 1) - 1)
                    sqrt_next_state = SQRT_DONE;
                    sqrt_init <= 0;
            end
            SQRT_DONE:
                sqrt_next_state = SQRT_IDLE;
        endcase
    end                            

    // Square root calculation logic
    always @(*)
    begin
        test_sub = acc - {quotient, 2'b01};

        if (test_sub[WIDTH + 1] == 0) 
        begin
            {acc_next, remainder_next} = {test_sub[WIDTH - 1 : 0], remainder, 2'b0};
            quotient_next = {quotient[WIDTH - 2 : 0], 1'b1};
        end 
        else 
        begin
            {acc_next, remainder_next} = {acc[WIDTH - 1 : 0], remainder, 2'b0};
            quotient_next = quotient << 1;
        end
    end

    // Square root sequential logic
    always @(posedge clk) 
    begin
        if (sqrt_init)
        begin
            // Initialize for new square root calculation
            sqrt_busy <= 1;
            sqrt_done <= 0;
            iter_count <= 0;
            quotient <= 0;
            {acc, remainder} <= {{WIDTH{1'b0}}, operand_1, 2'b0};
        end

        else if (sqrt_busy)
        begin
            if (iter_count == ((WIDTH + FBITS) >> 1)-1) 
            begin  // Final iteration
                sqrt_busy <= 0;
                sqrt_done <= 1;
                sqrt_result <= quotient_next;
            end

            else 
            begin  // Continue to next iteration
                iter_count <= iter_count + 1;
                remainder <= remainder_next;
                acc <= acc_next;
                quotient <= quotient_next;
                sqrt_done <= 0;
            end
        end
    end

    // ------------------ //
    // Multiplier Circuit //
    // ------------------ //   
    reg [64 - 1 : 0] product;
    reg product_ready;

    reg [2:0] mul_state;

    // Operands for the 16x16 multiplier
    reg [15 : 0] mul_op1, mul_op2;
    wire [31 : 0] mul_result;

    // Partial products for 32x32 multiplication
    reg [31 : 0] P1, P2, P3, P4;

    // Instantiate 16x16 multiplier
    Multiplier multiplier
    (
        .operand_1(mul_op1),
        .operand_2(mul_op2),
        .product(mul_result)
    );

    // Multiplication state machine and logic
    always @(posedge clk or posedge reset)
    begin
        if (reset) begin
            // Reset all multiplication-related registers
            mul_state <= 0;
            product_ready <= 0;
            product <= 0;
            {P1, P2, P3, P4} <= 0;
            {mul_op1, mul_op2} <= 0;
        end
        else if (operation == `FPU_MUL) begin
            case (mul_state)
                0: begin // Multiply lower halves: A1 * B1
                    mul_op1 <= operand_1[15:0];
                    mul_op2 <= operand_2[15:0];
                    mul_state <= 1;
                end
                1: begin // Multiply upper half of A with lower half of B: A2 * B1
                    P1 <= mul_result;
                    mul_op1 <= operand_1[31:16];
                    mul_op2 <= operand_2[15:0];
                    mul_state <= 2;
                end
                2: begin // Multiply lower half of A with upper half of B: A1 * B2
                    P2 <= mul_result << 16;
                    mul_op1 <= operand_1[15:0];
                    mul_op2 <= operand_2[31:16];
                    mul_state <= 3;
                end
                3: begin // Multiply upper halves: A2 * B2
                    P3 <= mul_result << 16;
                    mul_op1 <= operand_1[31:16];
                    mul_op2 <= operand_2[31:16];
                    mul_state <= 4;
                end
                4: begin // Prepare final partial product
                    P4 <= mul_result << 32;
                    mul_state <= 5;
                end
                5: begin // Combine all partial products
                    product <= P1 + P2 + P3 + P4;
                    product_ready <= 1;
                    mul_state <= 0;
                end
                default: mul_state <= 0;
            endcase
        end
    end
endmodule

module Multiplier
(
    input wire [15 : 0] operand_1,
    input wire [15 : 0] operand_2,

    output reg [31 : 0] product
);

    always @(*)
    begin
        product <= operand_1 * operand_2;
    end
endmodule
