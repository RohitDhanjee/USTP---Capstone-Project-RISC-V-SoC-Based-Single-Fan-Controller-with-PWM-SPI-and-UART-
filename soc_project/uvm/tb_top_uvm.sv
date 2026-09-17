// =====================================================================
// tb_top_uvm.sv - UVM Top-Level Testbench
//
// Instantiates soc_top (DUT), the soc_if interface, hooks up
// hierarchical taps into a few internal DUT status registers (so the
// PWM monitor / stall sequences can observe fault/enable/duty without
// needing new soc_top ports), and kicks off UVM via run_test().
// =====================================================================

`timescale 1ns/1ps

module tb_top_uvm;

    import uvm_pkg::*;
    import soc_uvm_pkg::*;

    localparam real CLK_PERIOD_NS      = 20.0; // 50 MHz
    localparam int  UART_CLKS_PER_BIT  = 16;   // small, fast-sim baud

    // -----------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS/2.0) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
    end

    // -----------------------------------------------------------------
    // Interface
    // -----------------------------------------------------------------
    soc_if vif (.clk(clk), .rst_n(rst_n));

    // -----------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------
    soc_top #(
        .IMEM_INIT_FILE    ("test_program.hex"),
        .CFG_INIT_FILE     ("config_data.hex"),
        .UART_CLKS_PER_BIT (UART_CLKS_PER_BIT)
    ) u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .spi_sclk         (vif.spi_sclk),
        .spi_mosi         (vif.spi_mosi),
        .spi_miso         (vif.spi_miso),
        .spi_cs_n         (vif.spi_cs_n),
        .uart_tx_line     (vif.uart_tx_line),
        .uart_rx_line     (vif.uart_rx_line),
        .fan_stall_inject (vif.fan_stall_inject),
        .bus_error        (vif.bus_error),
        .fan_rpm_debug    (vif.fan_rpm_debug),
        .pwm_out_debug    (vif.pwm_out_debug)
    );

    // -----------------------------------------------------------------
    // Hierarchical status taps (internal DUT signals -> interface)
    // -----------------------------------------------------------------
    assign vif.pwm_en_tap    = u_dut.u_pwm_controller.en_reg;
    assign vif.pwm_fault_tap = u_dut.u_pwm_controller.fault_reg;
    assign vif.pwm_duty_tap  = u_dut.u_pwm_controller.duty_reg;
    assign vif.spi_error_tap = u_dut.u_spi_master.error_reg;

    // Default line states before any driver takes over
    initial begin
        vif.fan_stall_inject = 1'b0;
    end

    // -----------------------------------------------------------------
    // UVM setup + run
    // -----------------------------------------------------------------
    initial begin
        uvm_config_db#(virtual soc_if)::set(null, "*", "vif", vif);
        run_test(); // test name supplied via +UVM_TESTNAME=... on the command line
    end

    // -----------------------------------------------------------------
    // Waveform dump
    // -----------------------------------------------------------------
    initial begin
        $dumpfile("tb_top_uvm.vcd");
        $dumpvars(0, tb_top_uvm);
    end

    // -----------------------------------------------------------------
    // Safety timeout
    // -----------------------------------------------------------------
    initial begin
        #2_000_000; // 2 ms
        `uvm_fatal("TB_TOP", "Global simulation timeout reached")
    end

endmodule
