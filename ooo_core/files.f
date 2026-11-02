// Source list for the out-of-order core (paths relative to ooo_core/).
// Reused from the phase-3 design: ALU arithmetic blocks and the course main memory.
../project_working_directory/Adder_ALU.v
../project_working_directory/Subtractor.v
../project_working_directory/XOR.v
../project_working_directory/RED.v
../project_working_directory/PSA_16bit.v
../project_working_directory/Shifter_ALU.v
../project_working_directory/Shifter.v
../project_working_directory/Rotater.v
../project_working_directory/CLA_16b.v
../project_working_directory/CLA_4b.v
../project_working_directory/memory4c.v
// New out-of-order core.
rtl/decoder.v
rtl/rob.v
rtl/issue_queue.v
rtl/exec_units.v
rtl/lsu.v
rtl/cache.v
rtl/mem_system.v
rtl/bp_basic.v
rtl/bp_tournament.v
rtl/bp_perceptron.v
rtl/bp_tage.v
rtl/branch_predictor.v
rtl/frontend.v
rtl/cpu.v
tb/cpu_tb.v
