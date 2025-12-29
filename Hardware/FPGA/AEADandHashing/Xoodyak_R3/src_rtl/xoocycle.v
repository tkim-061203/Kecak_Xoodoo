module xoocycle (
  input               clk,
  input               rst_n,
  input               start_absorb,
  input      [7:0]    absorb_data,
  input     [15:0]    absorb_len,
  input               start_squeeze,
  input     [15:0]    squeeze_len,
  output reg [7:0]    squeeze_data,
  output reg          squeeze_valid,
  output reg          busy
);

  // Parameters
  parameter SPONGE_BYTES = 48;
  parameter ROUNDS       = 12;
  localparam SPONGE_BITS = SPONGE_BYTES * 8;
  localparam HASH_RATE   = 16;

  // Domain separators
  localparam [7:0] DOMAIN_DEFAULT = 8'h00;
  localparam [7:0] DOMAIN_ABSORB  = 8'h03;
  localparam [7:0] DOMAIN_SQUEEZE = 8'h40;

  // Packed sponge state (384-bit)
  reg [SPONGE_BITS-1:0] sponge;
  wire [SPONGE_BITS-1:0] perm_state;
  reg perm_start;
  wire perm_done;

  // Instantiate Xoodoo permutation with separate output wire
  xoodoo perm_inst (
    .clk      (clk),
    .rst_n    (rst_n),
    .start    (perm_start),
    .state_in (sponge),
    .state_out(perm_state),
    .done     (perm_done)
  );

  integer offset, step, j;

  // Up primitive: domain separation, permutation, update sponge
  task up_primitive;
    input integer len;    // unused for packed version
    input [7:0] domain;
    begin
      sponge[(SPONGE_BYTES-1)*8 +:8] = sponge[(SPONGE_BYTES-1)*8 +:8] ^ domain;
      perm_start = 1'b1;
      @(posedge clk);
      perm_start = 1'b0;
      wait (perm_done);
      sponge = perm_state;  // capture new state
    end
  endtask

  // Down primitive: XOR input bytes, padding and domain, update sponge
  task down_primitive;
    input integer len;
    input [7:0] in_byte;
    input [7:0] domain;
    begin
      for (j = 0; j < len; j = j + 1)
        sponge[j*8 +:8] = sponge[j*8 +:8] ^ in_byte;
      sponge[len*8 +:8] = sponge[len*8 +:8] ^ 8'h01;
      sponge[(SPONGE_BYTES-1)*8 +:8] = sponge[(SPONGE_BYTES-1)*8 +:8] ^ domain;
      @(posedge clk);
      // Perform a permute to apply changes
      perm_start = 1'b1;
      @(posedge clk);
      perm_start = 1'b0;
      wait (perm_done);
      sponge = perm_state;
    end
  endtask

  // AbsorbAny: split input into HASH_RATE-byte blocks
  task absorb_any;
    input integer total_len;
    input [7:0] in_byte;
    begin
      offset = 0;
      while (offset < total_len) begin
        step = (total_len - offset < HASH_RATE) ? (total_len - offset) : HASH_RATE;
        if (offset == 0)
          down_primitive(step, in_byte, DOMAIN_ABSORB);
        else
          down_primitive(step, in_byte, DOMAIN_DEFAULT);
        offset = offset + step;
      end
    end
  endtask

// SqueezeAny: split output into HASH_RATE-byte blocks
  task squeeze_any;
    input integer total_len;
    begin
      offset = 0;
      while (offset < total_len) begin
        step = (total_len - offset < HASH_RATE) ?
               (total_len - offset) : HASH_RATE;
        
        if (offset == 0)
          // Khối đầu tiên: chỉ cần gọi UP với domain SQUEEZE
          up_primitive(step, DOMAIN_SQUEEZE);
        else begin
          // CÁC KHỐI TIẾP THEO (ĐÃ SỬA):
          // 1. Phải gọi DOWN (hấp thụ khối rỗng) theo đặc tả Duplex/Cyclist
          down_primitive(0, DOMAIN_DEFAULT);
          // 2. Bây giờ mới gọi UP để tạo khối dữ liệu tiếp theo
          up_primitive(step, DOMAIN_DEFAULT);
        end

        // Xuất dữ liệu đã được chuẩn bị bởi up_primitive
        for (j = 0; j < step; j = j + 1) begin
          squeeze_data  = sponge[j*8 +:8];
          squeeze_valid = 1'b1;
          @(posedge clk);
        end
        squeeze_valid = 1'b0;
        offset = offset + step;
      end
    end
  endtask

  // FSM control
  reg state;
  localparam IDLE = 1'b0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy          <= 1'b0;
      perm_start    <= 1'b0;
      squeeze_valid <= 1'b0;
      state         <= IDLE;
    end else begin
      case (state)
        IDLE: begin
          if (start_absorb) begin
            busy   <= 1'b1;
            sponge <= {SPONGE_BITS{1'b0}};
            absorb_any(absorb_len, absorb_data);
            busy   <= 1'b0;
          end else if (start_squeeze) begin
            busy   <= 1'b1;
            squeeze_any(squeeze_len);
            busy   <= 1'b0;
          end
        end
      endcase
    end
  end

endmodule
