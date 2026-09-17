# tb_filelist_uvm.f - Compile order for the UVM environment
#
# Requires a UVM-1.2-capable simulator (Questa, VCS, or Xcelium).
# Icarus Verilog's UVM support is very limited/incomplete -- use one
# of the above for Phase 10. Basic (Phase 9) tests still run fine on
# Icarus.
#
# Example (Questa):
#   vlog -sv +incdir+../uvm +incdir+. -f tb_filelist_uvm.f
#   vsim -c work.tb_top_uvm +UVM_TESTNAME=normal_test -do "run -all; quit"
#
# Example (VCS):
#   vcs -sverilog -ntb_opts uvm-1.2 +incdir+. -f tb_filelist_uvm.f -o simv
#   ./simv +UVM_TESTNAME=normal_test
#
# +incdir+. is required so the `include statements inside
# uvm_pkg_includes.sv (relative paths like "spi_agent/spi_seq_item.sv")
# can resolve when run from the uvm/ directory.

# ---- DUT (Phase 2-8 RTL) ----
-f ../filelist.f

# ---- UVM environment ----
soc_if.sv
uvm_pkg_includes.sv

# ---- Test program / config preload (referenced by soc_top params) ----
# (test_program.hex, config_data.hex must be copied into the sim run
#  directory from ../sim/, since $readmemh uses a relative path)

# ---- Top-level testbench ----
tb/tb_top_uvm.sv
