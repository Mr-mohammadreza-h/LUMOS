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

    // Internal signals
    reg [63:0] product;
    reg product_ready;
    reg [WIDTH-1:0] root;
    reg root_ready;
    reg [15:0] mul_op1, mul_op2;
    wire [31:0] mul_result;

    // Multiplier instance
    Multiplier multiplier
    (
        .operand_1(mul_op1),
        .operand_2(mul_op2),
        .product(mul_result)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            result <= 0;
            ready <= 0;
            root <= 0;
            root_ready <= 0;
            product <= 0;
            product_ready <= 0;
        end else begin
            case (operation)
                `FPU_ADD: begin
                    result <= operand_1 + operand_2;
                    ready <= 1;
                end
                `FPU_SUB: begin
                    result <= operand_1 - operand_2;
                    ready <= 1;
                end
                `FPU_MUL: begin
                    result <= product[WIDTH + FBITS - 1 : FBITS];
                    ready <= product_ready;
                end
                `FPU_SQRT: begin
                    result <= root;
                    ready <= root_ready;
                end
                default: begin
                    result <= 0;
                    ready <= 0;
                end
            endcase
        end
    end

    // Square Root Calculator
    reg [WIDTH-1:0] radicand, sqrt, remainder;
    reg [5:0] iter_count;
    reg [1:0] sqrt_state;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            root <= 0;
            root_ready <= 0;
            sqrt_state <= 0;
            iter_count <= 0;
            radicand <= 0;
            sqrt <= 0;
            remainder <= 0;
        end else if (operation == `FPU_SQRT) begin
            case (sqrt_state)
                0: begin // Initialize
                    radicand <= operand_1;
                    sqrt <= 0;
                    remainder <= 0;
                    iter_count <= 0;
                    sqrt_state <= 1;
                end
                1: begin // Main calculation loop
                    if (iter_count < (WIDTH + FBITS) / 2) begin
                        remainder <= {remainder[WIDTH-3:0], radicand[WIDTH-1:WIDTH-2]};
                        radicand <= {radicand[WIDTH-3:0], 2'b00};
                        
                        if (remainder >= (sqrt + 1)) begin
                            remainder <= remainder - (sqrt + 1);
                            sqrt <= {sqrt[WIDTH-2:0], 1'b1};
                        end else begin
                            sqrt <= {sqrt[WIDTH-2:0], 1'b0};
                        end
                        iter_count <= iter_count + 1;
                    end else begin
                        root <= sqrt << (FBITS / 2);
                        root_ready <= 1;
                        sqrt_state <= 0;
                    end
                end
            endcase
        end
    end

    // Multiplier Circuit
    reg [2:0] mul_state;
    reg [31:0] P1, P2, P3, P4;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mul_state <= 0;
            product_ready <= 0;
            product <= 0;
            P1 <= 0;
            P2 <= 0;
            P3 <= 0;
            P4 <= 0;
            mul_op1 <= 0;
            mul_op2 <= 0;
        end else if (operation == `FPU_MUL) begin
            case (mul_state)
                0: begin // A1 * B1
                    mul_op1 <= operand_1[15:0];
                    mul_op2 <= operand_2[15:0];
                    mul_state <= 1;
                end
                1: begin // A2 * B1
                    P1 <= mul_result;
                    mul_op1 <= operand_1[31:16];
                    mul_op2 <= operand_2[15:0];
                    mul_state <= 2;
                end
                2: begin // A1 * B2
                    P2 <= mul_result << 16;
                    mul_op1 <= operand_1[15:0];
                    mul_op2 <= operand_2[31:16];
                    mul_state <= 3;
                end
                3: begin // A2 * B2
                    P3 <= mul_result << 16;
                    mul_op1 <= operand_1[31:16];
                    mul_op2 <= operand_2[31:16];
                    mul_state <= 4;
                end
                4: begin // Combine results
                    P4 <= mul_result << 32;
                    mul_state <= 5;
                end
                5: begin
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

    always @(*) begin
        product <= operand_1 * operand_2;
    end
endmodule
