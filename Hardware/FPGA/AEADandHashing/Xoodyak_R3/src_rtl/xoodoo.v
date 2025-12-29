//--------------------------------------------------------------------------------
// Xoodoo permutation with configurable rounds per cycle
// Matches functionality of xoodoo.vhd
//--------------------------------------------------------------------------------

module xoodoo(
    clk_i,
    rst_i,
    start_i,
    state_valid_o,
    init_reg,
    word_in,
    word_index_in,
    word_enable_in,
    domain_i,
    domain_enable_i,
    word_out
);
    // Port declarations
    input               clk_i;
    input               rst_i;
    input               start_i;
    output              state_valid_o;
    input               init_reg;
    input      [31:0]   word_in;
    input      [3:0]    word_index_in;  // 0 to 11
    input               word_enable_in;
    input      [31:0]   domain_i;
    input               domain_enable_i;
    output     [31:0]   word_out;

    // Parameters
    parameter roundPerCycle = 2;
    parameter active_rst = 1'b1;

    // Internal state representation: 3 planes x 4 words x 32 bits = 384 bits
    // State layout: state[plane][word] where plane=0..2, word=0..3
    // Packed representation: [383:0] = [plane2, plane1, plane0]
    // Word at plane y, word x is at bit position: 128*y + 32*x + bit
    reg  [383:0] reg_value;
    wire [383:0] round_in_state;
    wire [383:0] round_out_state;
    
    // Round constant state machine (6 bits)
    reg  [5:0]  rc_state_in;
    wire [5:0]  rc_state_out;
    
    // Control signals
    reg         done;
    reg         running;
    
    // N rounds computation module (uses flattened 384-bit vectors)
    xoodoo_n_rounds #(.roundPerCycle(roundPerCycle)) rounds_inst(
        .state_in(reg_value),
        .state_out(round_out_state),
        .rc_state_in(rc_state_in),
        .rc_state_out(rc_state_out)
    );
    
    // State register: handles word loading, domain separation, and state updates
    always @(posedge clk_i) begin
        if (rst_i == active_rst) begin
            // Reset all state to zero
            reg_value <= 384'h0;
        end else begin
            if (init_reg == 1'b1) begin
                // Initialize all state to zero
                reg_value <= 384'h0;
            end else if (running == 1'b1 || start_i == 1'b1) begin
                // Update state from round output
                reg_value <= round_out_state;
            end else begin
                // Word-by-word loading and domain separation
                if (domain_enable_i == 1'b1) begin
                    reg_value[383:352] <= reg_value[383:352] ^ domain_i;
                end
                if (word_enable_in == 1'b1) begin
                    reg_value[word_index_in*32 +: 32] <= 
                        reg_value[word_index_in*32 +: 32] ^ word_in;
                end
            end
        end
    end
    
    // Word output: read from register
    assign word_out = reg_value[word_index_in*32 +: 32];
    
    // Main FSM controller
    always @(posedge clk_i) begin
        if (rst_i == active_rst) begin
            done <= 1'b0;
            running <= 1'b0;
            rc_state_in <= 6'b011011;  // Initial RC state
        end else begin
            // Default: keep running state and update rc_state_in
            if (start_i == 1'b1) begin
                done <= 1'b0;
                running <= 1'b1;
                rc_state_in <= rc_state_out;
            end else if (running == 1'b1) begin
                done <= 1'b0;
                running <= 1'b1;
                rc_state_in <= rc_state_out;
            end
            
            // Check if permutation is complete (RC state = "010011")
            // This check happens after the above assignments
            if (rc_state_out == 6'b010011) begin
                done <= 1'b1;
                running <= 1'b0;
                rc_state_in <= 6'b011011;  // Reset RC state for next permutation
            end
        end
    end
    
    assign state_valid_o = done;
    
endmodule

