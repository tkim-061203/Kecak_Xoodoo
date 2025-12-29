# ModelSim script to compile and run xoodoo testbench
# Usage: vsim -do run_xoodoo.do

# Create work library if it doesn't exist
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile files in dependency order
vlog -work work xoodoo_rc.v
vlog -work work xoodoo_round.v
vlog -work work xoodoo_n_rounds.v
vlog -work work xoodoo.v
vlog -work work tb_xoodoo.v

# Run simulation
vsim -voptargs=+acc work.tb_xoodoo

# Add waves to waveform viewer (optional)
add wave -radix hex /tb_xoodoo/clk_i
add wave -radix hex /tb_xoodoo/rst_i
add wave -radix hex /tb_xoodoo/start_i
add wave -radix hex /tb_xoodoo/state_valid_o
add wave -radix hex /tb_xoodoo/word_in
add wave -radix hex /tb_xoodoo/word_index_in
add wave -radix hex /tb_xoodoo/word_enable_in
add wave -radix hex /tb_xoodoo/word_out
add wave -radix hex /tb_xoodoo/iteration_count
add wave -radix hex /tb_xoodoo/current_state

# Run simulation
run -all

# Display completion message
echo "Simulation completed!"

