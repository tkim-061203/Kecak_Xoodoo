//--------------------------------------------------------------------------------
// N rounds computation module
// Matches xoodoo_n_rounds.vhd functionality
// Uses flattened 384-bit vectors for Verilog compatibility
//--------------------------------------------------------------------------------
module xoodoo_n_rounds(
    state_in,
    state_out,
    rc_state_in,
    rc_state_out
);
    parameter roundPerCycle = 2;
    
    input  [383:0] state_in;
    output [383:0] state_out;
    input  [5:0]   rc_state_in;
    output [5:0]   rc_state_out;
    
    // Intermediate states for each round (flattened)
    wire [383:0] round_outputs [0:roundPerCycle-1];
    wire [31:0]  round_rc_values [0:roundPerCycle-1];
    wire [5:0]   round_rc_outputs [0:roundPerCycle-1];
    
    // Generate rounds
    genvar r;
    generate
        for (r = 0; r < roundPerCycle; r = r + 1) begin : gen_rounds
            // Round constant for this round
            xoodoo_rc rc_inst(
                .state_in(r == 0 ? rc_state_in : round_rc_outputs[r-1]),
                .state_out(round_rc_outputs[r]),
                .rc(round_rc_values[r])
            );
            
            // Round computation
            xoodoo_round round_inst(
                .state_in(r == 0 ? state_in : round_outputs[r-1]),
                .rc(round_rc_values[r]),
                .state_out(round_outputs[r])
            );
        end
    endgenerate
    
    // Output from last round
    assign state_out = round_outputs[roundPerCycle-1];
    assign rc_state_out = round_rc_outputs[roundPerCycle-1];
    
endmodule

