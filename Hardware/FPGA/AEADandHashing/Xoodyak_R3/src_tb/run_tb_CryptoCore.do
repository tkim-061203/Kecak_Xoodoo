# ModelSim script to compile and run CryptoCore testbench
# Usage: vsim -do run_tb_CryptoCore.do

# Create work library if it doesn't exist
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile files in dependency order
vlog -work work ../src_rtl/xoodoo_rc.v
vlog -work work ../src_rtl/xoodoo_round.v
vlog -work work ../src_rtl/xoodoo_n_rounds.v
vlog -work work ../src_rtl/xoodoo.v
vlog -work work ../src_rtl/CryptoCore.v
vlog -work work tb_CryptoCore.v

# Run simulation
vsim -voptargs=+acc work.tb_CryptoCore

# Add waves to waveform viewer
add wave -radix hex /tb_CryptoCore/clk
add wave -radix hex /tb_CryptoCore/rst
add wave -radix hex /tb_CryptoCore/key
add wave -radix hex /tb_CryptoCore/key_valid
add wave -radix hex /tb_CryptoCore/key_ready
add wave -radix hex /tb_CryptoCore/bdi
add wave -radix hex /tb_CryptoCore/bdi_valid
add wave -radix hex /tb_CryptoCore/bdi_ready
add wave -radix hex /tb_CryptoCore/bdi_type
add wave -radix hex /tb_CryptoCore/bdo
add wave -radix hex /tb_CryptoCore/bdo_valid
add wave -radix hex /tb_CryptoCore/bdo_ready
add wave -radix hex /tb_CryptoCore/bdo_type
add wave -radix hex /tb_CryptoCore/msg_auth
add wave -radix hex /tb_CryptoCore/msg_auth_valid
add wave -radix hex /tb_CryptoCore/decrypt_in

# Add internal signals from DUT
add wave -radix hex /tb_CryptoCore/dut/state_s
add wave -radix hex /tb_CryptoCore/dut/word_cnt_s
add wave -radix hex /tb_CryptoCore/dut/xoodoo_start_s
add wave -radix hex /tb_CryptoCore/dut/xoodoo_valid_s

# Run simulation
run -all

# Display completion message
echo "Simulation completed!"

