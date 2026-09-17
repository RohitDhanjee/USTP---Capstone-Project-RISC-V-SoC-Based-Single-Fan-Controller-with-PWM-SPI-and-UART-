# filelist.f - Compile order for soc_top and dependencies
# Usage example (Icarus Verilog):
#   iverilog -g2012 -f filelist.f -o soc_sim
# Usage example (Verilator lint):
#   verilator --lint-only -f filelist.f
#
# Packages / shared defs first
rtl/core/alu.sv                    # defines alu_pkg, must compile before users

# Core
rtl/core/regfile.sv
rtl/core/imm_gen.sv
rtl/core/control_unit.sv
rtl/core/rv32i_core.sv
rtl/core/imem.sv

# Memories
rtl/mem/dmem.sv
rtl/mem/config_sram.sv

# Bus
rtl/bus/addr_decoder.sv

# PWM
rtl/pwm/pwm_controller.sv
rtl/pwm/fan_model.sv

# SPI
rtl/spi/spi_master.sv
rtl/spi/spi_slave_model.sv          # testbench-side, keep out of synth fileset

# UART
rtl/uart/uart_tx.sv
rtl/uart/uart_rx.sv
rtl/uart/uart_top.sv
rtl/uart/uart_terminal_model.sv     # testbench-side, keep out of synth fileset

# Top-level
rtl/soc_top.sv
