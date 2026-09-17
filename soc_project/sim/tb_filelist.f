# tb_filelist.f - Compile order for simulating tb_soc_top
# Usage (Icarus Verilog):
#   iverilog -g2012 -f tb_filelist.f -o tb_sim
#   vvp tb_sim
# Hex files (test_program.hex, config_data.hex) must be in the sim
# working directory (referenced by relative path in soc_top parameters).

-f ../filelist.f          # soc_top + all DUT RTL (includes spi_slave_model.sv
                           # and uart_terminal_model.sv, which are testbench-side
                           # but declared alongside their DUT counterparts)
tb_soc_top.sv
