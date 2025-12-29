module Xoodoo(
    clk,
    rst_n,    
    start,
    state_in,
    state_out,
    done
);
    // Port declarations
    input         clk;
    input         rst_n;    
    input         start;
    input  [383:0] state_in;
    output [383:0] state_out;
    output        done;

    // Outputs stored in regs
    reg    [383:0] state_out;
    reg            done;

    // Internal state and control
    reg    [383:0] state;
    reg      [3:0] round_counter;
    reg            processing;
    parameter NUM_ROUNDS = 12;

    // Round constants C_i for i = -11 ... 0
    wire [31:0] rc [0:NUM_ROUNDS-1];
    assign rc[ 0] = 32'h00000058;
    assign rc[ 1] = 32'h00000038;
    assign rc[ 2] = 32'h000003C0;
    assign rc[ 3] = 32'h000000D0;
    assign rc[ 4] = 32'h00000120;
    assign rc[ 5] = 32'h00000014;
    assign rc[ 6] = 32'h00000060;
    assign rc[ 7] = 32'h0000002C;
    assign rc[ 8] = 32'h00000380;
    assign rc[ 9] = 32'h000000F0;
    assign rc[10] = 32'h000001A0;
    assign rc[11] = 32'h00000012;

    // 32-bit rotate-left
    function [31:0] rotl32;
        input [31:0] x;
        input [4:0]  n;
        begin
            rotl32 = (x << n) | (x >> (32 - n));
        end
    endfunction

    // One round of Xoodoo
    function [383:0] apply_round;
        input [383:0] cur;
        input [31:0]  rc_val;
        reg   [31:0] A   [0:2][0:3];
        reg   [31:0] P   [0:3];
        reg   [31:0] E   [0:3];
        reg   [31:0] tmp [0:3];
        reg   [31:0] B0, B1, B2;
        integer      x, y;
        begin
            for (y = 0; y < 3; y = y + 1)
                for (x = 0; x < 4; x = x + 1)
                    A[y][x] = cur[((11 - (x+4*y)) * 32) +: 32];

            // θ: parity
            for (x = 0; x < 4; x = x + 1)
                P[x] = A[0][x] ^ A[1][x] ^ A[2][x];
            // θ: effect E[x] = rotl(P[x-1],5) XOR rotl(P[x-1],14)
            for (x = 0; x < 4; x = x + 1)
                E[x] = rotl32(P[(x+3)%4], 5) ^ rotl32(P[(x+3)%4],14);
            // θ: apply
            for (y = 0; y < 3; y = y + 1)
                for (x = 0; x < 4; x = x + 1)
                    A[y][x] = A[y][x] ^ E[x];

            // ρ_west
            for (x = 0; x < 4; x = x + 1)
                tmp[x] = A[1][x];
            for (x = 0; x < 4; x = x + 1)
                A[1][x] = tmp[(x+3)%4];
            for (x = 0; x < 4; x = x + 1)
                A[2][x] = rotl32(A[2][x], 11);

            // ι
            A[0][0] = A[0][0] ^ rc_val;

            // χ
            for (x = 0; x < 4; x = x + 1) begin
                B0 = (~A[1][x]) & A[2][x];
                B1 = (~A[2][x]) & A[0][x];
                B2 = (~A[0][x]) & A[1][x];
                A[0][x] = A[0][x] ^ B0;
                A[1][x] = A[1][x] ^ B1;
                A[2][x] = A[2][x] ^ B2;
            end

            // ρ_east
            for (x = 0; x < 4; x = x + 1)
                A[1][x] = rotl32(A[1][x], 1);
            for (x = 0; x < 4; x = x + 1)
                tmp[x] = A[2][x];
            for (x = 0; x < 4; x = x + 1)
                A[2][x] = rotl32(tmp[(x+2)%4], 8);

            // --- pack lanes back MSB-first ---
            for (y = 0; y < 3; y = y + 1)
                for (x = 0; x < 4; x = x + 1)
                    apply_round[((11 - (x+4*y)) * 32) +: 32] = A[y][x];
        end
    endfunction

    // FSM controller with active-low reset
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin  
            state         <= 384'h0;
            state_out     <= 384'h0;
            done          <= 1'b0;
            round_counter <= 4'd0;
            processing    <= 1'b0;
        end else if (start && !processing) begin
            state         <= state_in;
            round_counter <= 4'd0;
            processing    <= 1'b1;
            done          <= 1'b0;
        end else if (processing) begin
            if (round_counter < NUM_ROUNDS) begin
                state         <= apply_round(state, rc[round_counter]);
                round_counter <= round_counter + 1;
            end else begin
                state_out   <= state;
                done        <= 1'b1;
                processing  <= 1'b0;
            end
        end
    end
endmodule