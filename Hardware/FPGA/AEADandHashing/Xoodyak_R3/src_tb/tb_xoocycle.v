`timescale 1ns/1ps

module tb_xoocycle;

  //--------------
  // Tham số
  //--------------
  localparam CLK_PERIOD = 10;

  //--------------
  // Tín hiệu chung
  //--------------
  reg         clk;
  reg         rst_n;

  // interface absorb
  reg         start_absorb;
  reg  [7:0]  absorb_data;
  reg [15:0]  absorb_len;

  // interface squeeze
  reg         start_squeeze;
  reg [15:0]  squeeze_len;

  // outputs
  wire [7:0]  squeeze_data;
  wire        squeeze_valid;
  wire        busy;

  //--------------
  // Instantiate DUT
  //--------------
  xoocycle dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .start_absorb  (start_absorb),
    .absorb_data   (absorb_data),
    .absorb_len    (absorb_len),
    .start_squeeze (start_squeeze),
    .squeeze_len   (squeeze_len),
    .squeeze_data  (squeeze_data),
    .squeeze_valid (squeeze_valid),
    .busy          (busy)
  );

  //--------------
  // Clock generator
  //--------------
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  //--------------
  // Test procedure
  //--------------
  initial begin
    // 1. Reset
    rst_n         = 0;
    start_absorb  = 0;
    absorb_data   = 0;
    absorb_len    = 0;
    start_squeeze = 0;
    squeeze_len   = 0;
    #(CLK_PERIOD*3);
    rst_n = 1;
    #(CLK_PERIOD*2);

    // ===== Test #1: Absorb 4 byte 0xA5 rồi Squeeze 4 byte =====
    $display("=== Test 1: absorb 4x 0xA5, squeeze 4 bytes ===");
    absorb_data  = 8'hA5;
    absorb_len   = 16'd4;
    @(posedge clk);
      start_absorb = 1;
    @(posedge clk);
      start_absorb = 0;
    // đợi absorb hoàn tất (busy nháy cao một chu kỳ)
    wait (busy == 1);
    wait (busy == 0);

    // bây giờ squeeze
    squeeze_len   = 16'd4;
    @(posedge clk);
      start_squeeze = 1;
    @(posedge clk);
      start_squeeze = 0;
    // đọc 4 lần khi squeeze_valid lên 1
    repeat (4) begin
      @(posedge clk);
      if (squeeze_valid) begin
        $display("  Squeeze byte = %h", squeeze_data);
      end
    end

    // ===== Test #2: Absorb 8 byte tăng dần, squeeze 8 byte =====
    $display("=== Test 2: absorb 8 x increasing bytes, squeeze 8 bytes ===");
    absorb_len = 16'd8;
    // để đơn giản, xoocycle impl đang nhồi cùng giá trị absorb_data mỗi lần;
    // nếu bạn muốn test nhiều giá trị khác nhau, bạn có thể sửa xoocycle để
    // đọc absorb_data mỗi xung clock.
    absorb_data = 8'h01;
    @(posedge clk); start_absorb = 1; @(posedge clk); start_absorb = 0;
    wait (busy == 1); wait (busy == 0);

    squeeze_len   = 16'd8;
    @(posedge clk); start_squeeze = 1; @(posedge clk); start_squeeze = 0;
    repeat (8) begin
      @(posedge clk);
      if (squeeze_valid)
        $display("  Squeeze byte = %h", squeeze_data);
    end

    $display("=== All tests done ===");
    $finish;
  end

endmodule
