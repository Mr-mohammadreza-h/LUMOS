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

    // Result calculation based on the operation
    always @(*)
    begin
        case (operation)
            `FPU_ADD    : begin result <= operand_1 + operand_2; ready <= 1; end
            `FPU_SUB    : begin result <= operand_1 - operand_2; ready <= 1; end
            `FPU_MUL    : begin result <= mult_result[WIDTH + FBITS - 1 : FBITS]; ready <= mult_ready; end
            `FPU_SQRT   : begin result <= root; ready <= root_ready; end
            default     : begin result <= 'bz; ready <= 0; end
        endcase
    end

    always @(posedge reset)
    begin
        if (reset)  ready <= 0;
        else        ready <= 'bz;
    end

    // ------------------- //
    // Square Root Circuit //
    // ------------------- //
    reg [WIDTH - 1 : 0] root;
    reg root_ready;
    reg [WIDTH*2-1 : 0] radicand;
    reg [WIDTH-1 : 0] root_candidate;
    reg [WIDTH*2-1 : 0] remainder;
    reg [WIDTH-1 : 0] root_shift;
    reg [5:0] bit_position;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            root <= 0;
            root_ready <= 0;
            radicand <= 0;
            root_candidate <= 0;
            remainder <= 0;
            root_shift <= 0;
            bit_position <= 0;
        end else if (operation == `FPU_SQRT) begin
            radicand <= operand_1 << FBITS;
            root_candidate <= 0;
            remainder <= 0;
            root_shift <= 1 << (WIDTH - 2);
            bit_position <= WIDTH - 1;
            root_ready <= 0;
            root <= 0;

            while (root_shift != 0) begin
                remainder = remainder - (root_candidate << 1 | root_shift);
                root_candidate = root_candidate << 1 | 1;

                if (remainder < 0) begin
                    remainder = remainder + (root_candidate << 1 | root_shift);
                    root_candidate = root_candidate - 1;
                end

                root_shift = root_shift >> 2;
                bit_position = bit_position - 2;
            end

            root <= root_candidate;
            root_ready <= 1;
        end
    end

    // ------------------ //
    // Multiplier Circuit //
    // ------------------ //   
    reg [63:0] mult_result;
    reg mult_ready;
    reg [2:0] mult_state;
    
    reg [15:0] mult_op1, mult_op2;
    wire [31:0] mult_intermediate;
    reg [31:0] partial_product_1, partial_product_2, partial_product_3, partial_product_4;

    Multiplier multiplier
    (
        .operand_1(mult_op1),
        .operand_2(mult_op2),
        .product(mult_intermediate)
    );

    always @(posedge clk or posedge reset)
    begin
        if (reset) begin
            mult_state <= 0;
            mult_ready <= 0;
            mult_result <= 0;
            partial_product_1 <= 0;
            partial_product_2 <= 0;
            partial_product_3 <= 0;
            partial_product_4 <= 0;
            mult_op1 <= 0;
            mult_op2 <= 0;
        end
        else if (operation == `FPU_MUL) begin
            case (mult_state)
                0: begin // Step 1: Lower 16 bits of both operands
                    mult_op1 <= operand_1[15:0];
                    mult_op2 <= operand_2[15:0];
                    mult_state <= 1;
                end
                1: begin // Step 2: Upper 16 bits of operand_1 and lower 16 bits of operand_2
                    partial_product_1 <= mult_intermediate;
                    mult_op1 <= operand_1[31:16];
                    mult_op2 <= operand_2[15:0];
                    mult_state <= 2;
                end
                2: begin // Step 3: Lower 16 bits of operand_1 and upper 16 bits of operand_2
                    partial_product_2 <= mult_intermediate << 16;
                    mult_op1 <= operand_1[15:0];
                    mult_op2 <= operand_2[31:16];
                    mult_state <= 3;
                end
                3: begin // Step 4: Upper 16 bits of both operands
                    partial_product_3 <= mult_intermediate << 16;
                    mult_op1 <= operand_1[31:16];
                    mult_op2 <= operand_2[31:16];
                    mult_state <= 4;
                end
                4: begin // Combine results
                    partial_product_4 <= mult_intermediate << 32;
                    mult_state <= 5;
                end
                5: begin
                    mult_result <= partial_product_1 + partial_product_2 + partial_product_3 + partial_product_4;
                    mult_ready <= 1;
                    mult_state <= 0;
                end
                default: mult_state <= 0;
            endcase
        end
    end
endmodule

module Multiplier
(
    input wire [15:0] operand_1,
    input wire [15:0] operand_2,
    output reg [31:0] product
);
    always @(*)
    begin
        product = operand_1 * operand_2;
    end
endmodule