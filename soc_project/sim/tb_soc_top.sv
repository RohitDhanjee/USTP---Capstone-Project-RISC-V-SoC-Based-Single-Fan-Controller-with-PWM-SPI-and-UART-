// =====================================================================
// tb_soc_top.sv - Directed Self-Checking Testbench
//
// Structure:
//   PART A - Full-SoC, program-driven "normal operation" tests:
//            reset, core execution, SRAM read/write, PWM enable/duty,
//            SPI transfer, UART transmit -- exercised by running
//            test_program.hex on the real core through soc_top.
//   PART B - Directed unit-level "error case" tests on the same RTL
//            peripheral modules (instantiated separately, driven
//            directly by the testbench), since these fault conditions
//            are awkward to hand-assemble into the core's program:
//              - PWM stall/fault detection
//              - SPI "start while busy" protocol error
//              - UART framing error
//
// Self-checking: a simple check_equal task tracks pass/fail counts
// and prints a final summary; $finish is called with a nonzero exit
// implied by PASS/FAIL banner if any check fails.
// =====================================================================

`timescale 1ns/1ps

module tb_soc_top;

    // -----------------------------------------------------------------
    // Clock / Reset
    // -----------------------------------------------------------------
    localparam real CLK_PERIOD_NS = 20.0; // 50 MHz
    localparam int  UART_CLKS_PER_BIT = 16; // kept small for fast sim

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS/2.0) clk = ~clk;

    // -----------------------------------------------------------------
    // Self-checking bookkeeping
    // -----------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic check_equal(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual === expected) begin
            pass_count++;
            $display("[PASS] %-40s actual=0x%08h expected=0x%08h", name, actual, expected);
        end else begin
            fail_count++;
            $display("[FAIL] %-40s actual=0x%08h expected=0x%08h", name, actual, expected);
        end
    endtask

    task automatic check_true(string name, logic cond);
        if (cond) begin
            pass_count++;
            $display("[PASS] %-40s", name);
        end else begin
            fail_count++;
            $display("[FAIL] %-40s", name);
        end
    endtask

    // ===================================================================
    // PART A: Full SoC (DUT) + external models
    // ===================================================================

    // SPI pins
    logic spi_sclk, spi_mosi, spi_miso, spi_cs_n;
    // UART pins
    logic uart_tx_line, uart_rx_line;
    // Fan fault-injection / debug
    logic        fan_stall_inject;
    logic        bus_error;
    logic [15:0] fan_rpm_debug;
    logic        pwm_out_debug;

    assign fan_stall_inject = 1'b0; // not exercised in Part A; see Part B for fault case

    soc_top #(
        .IMEM_INIT_FILE    ("test_program.hex"),
        .CFG_INIT_FILE     ("config_data.hex"),
        .UART_CLKS_PER_BIT (UART_CLKS_PER_BIT)
    ) u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .spi_sclk         (spi_sclk),
        .spi_mosi         (spi_mosi),
        .spi_miso         (spi_miso),
        .spi_cs_n         (spi_cs_n),
        .uart_tx_line     (uart_tx_line),
        .uart_rx_line     (uart_rx_line),
        .fan_stall_inject (fan_stall_inject),
        .bus_error        (bus_error),
        .fan_rpm_debug    (fan_rpm_debug),
        .pwm_out_debug    (pwm_out_debug)
    );

    // External SPI slave model (fake "smart fan module")
    logic [7:0] profile_bytes [0:7];
    logic [7:0] spi_rx_log    [0:7];
    int         spi_transfer_count;

    initial begin
        profile_bytes[0] = 8'hDE; profile_bytes[1] = 8'hAD;
        profile_bytes[2] = 8'hBE; profile_bytes[3] = 8'hEF;
        profile_bytes[4] = 8'h11; profile_bytes[5] = 8'h22;
        profile_bytes[6] = 8'h33; profile_bytes[7] = 8'h44;
    end

    spi_slave_model #(
        .NUM_PROFILE_BYTES (8)
    ) u_spi_slave (
        .sclk           (spi_sclk),
        .cs_n           (spi_cs_n),
        .mosi           (spi_mosi),
        .miso           (spi_miso),
        .profile_bytes  (profile_bytes),
        .rx_log         (spi_rx_log),
        .transfer_count (spi_transfer_count)
    );

    // External UART terminal model
    uart_terminal_model #(
        .BIT_PERIOD_NS (UART_CLKS_PER_BIT * CLK_PERIOD_NS) // = 320.0 ns
    ) u_uart_terminal (
        .term_tx_line (uart_rx_line), // terminal's TX drives DUT's rx
        .term_rx_line (uart_tx_line)  // terminal's RX watches DUT's tx
    );

    // -----------------------------------------------------------------
    // PART A test sequence
    // -----------------------------------------------------------------
    initial begin
        logic [7:0] uart_byte;
        bit         got_byte;

        rst_n = 1'b0;
        repeat (5) @(posedge clk);

        // ---- Reset test ----
        check_equal("Reset: PC = 0 after reset",
                     u_dut.u_core.pc, 32'h0000_0000);
        check_true ("Reset: bus_error is low after reset", (bus_error === 1'b0));

        @(negedge clk);
        rst_n = 1'b1;

        // Let the program run: SRAM ops + PWM setup + SPI transfer +
        // UART transmit all happen within the first ~1000 ns, but we
        // give generous margin for the polling loops.
        #20000; // 20 us -> 1000 clk cycles @ 50 MHz

        // ---- SRAM write/read test ----
        check_equal("SRAM: DMEM[0] written by core (=123)",
                     u_dut.u_dmem.mem[0], 32'd123);

        // ---- PWM test ----
        check_equal("PWM: PWM_DUTY register set to 128",
                     {24'd0, u_dut.u_pwm_controller.duty_reg}, 32'd128);
        check_true ("PWM: PWM enabled (en_reg = 1)",
                     u_dut.u_pwm_controller.en_reg);

        // Give the fan model a few more PWM windows to ramp up
        #20000;
        check_true ("PWM: fan_rpm_debug > 0 after enable (fan spinning up)",
                     (fan_rpm_debug > 16'd0));

        // ---- SPI test ----
        check_true ("SPI: at least one transfer completed",
                     (spi_transfer_count >= 1));
        check_equal("SPI: master received slave's first profile byte",
                     {24'd0, u_dut.u_dmem.mem[1][7:0]}, 32'h000000DE);
        check_equal("SPI: slave logged the byte the core sent (0xA5)",
                     {24'd0, spi_rx_log[0]}, 32'h000000A5);

        // ---- UART test ----
        got_byte = u_uart_terminal.get_next_byte(uart_byte);
        check_true ("UART: terminal received a byte from core",
                     got_byte);
        if (got_byte)
            check_equal("UART: received byte matches 'A' (0x41)",
                         {24'd0, uart_byte}, 32'h00000041);

        $display("\n===== PART A (Full SoC, normal operation) complete =====\n");

        // ---- Part B: directed error-case tests ----
        run_pwm_stall_fault_test();
        run_spi_start_while_busy_error_test();
        run_uart_frame_error_test();

        // ---- Final summary ----
        $display("\n===================================================");
        $display(" TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("===================================================\n");
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: %0d TEST(S) FAILED", fail_count);

        $finish;
    end

    // Safety timeout in case a wait loop never completes
    initial begin
        #500000;
        $display("[FAIL] TIMEOUT: simulation did not finish in time");
        fail_count++;
        $finish;
    end

    // ===================================================================
    // PART B: Directed unit-level error-case tests
    // ===================================================================

    // -------------------------------------------------------------
    // B1. PWM stall/fault detection
    // -------------------------------------------------------------
    logic          pwm_err_sel, pwm_err_we, pwm_err_re;
    logic [31:0]  pwm_err_addr, pwm_err_wdata, pwm_err_rdata;
    logic          pwm_err_out;
    logic [15:0]  pwm_err_rpm_in;

    pwm_controller #(
        .STALL_CYCLES (32) // small, for a fast directed test
    ) u_pwm_err (
        .clk     (clk),
        .rst_n   (rst_n),
        .sel     (pwm_err_sel),
        .addr    (pwm_err_addr),
        .wdata   (pwm_err_wdata),
        .we      (pwm_err_we),
        .re      (pwm_err_re),
        .rdata   (pwm_err_rdata),
        .pwm_out (pwm_err_out),
        .rpm_in  (pwm_err_rpm_in)
    );

    task automatic run_pwm_stall_fault_test();
        begin
            $display("---- B1: PWM stall/fault error case ----");
            pwm_err_sel   = 1'b0; pwm_err_we = 1'b0; pwm_err_re = 1'b0;
            pwm_err_addr  = 32'd0; pwm_err_wdata = 32'd0;
            pwm_err_rpm_in = 16'd0; // simulate a jammed fan: RPM never rises

            @(posedge clk);
            // Enable PWM (PWM_CTRL offset 0x0, EN=1)
            pwm_err_sel = 1'b1; pwm_err_we = 1'b1;
            pwm_err_addr = 32'h0; pwm_err_wdata = 32'h1;
            @(posedge clk);
            pwm_err_we = 1'b0;

            // Wait longer than STALL_CYCLES with rpm_in held at 0
            repeat (40) @(posedge clk);

            // Read PWM_STATUS (offset 0x8)
            pwm_err_re = 1'b1; pwm_err_addr = 32'h8;
            @(posedge clk);
            pwm_err_re = 1'b0;

            check_true("PWM error case: FAULT bit set on stalled fan",
                        pwm_err_rdata[1]);
        end
    endtask

    // -------------------------------------------------------------
    // B2. SPI "start while busy" protocol error
    // -------------------------------------------------------------
    logic          spi_err_sel, spi_err_we, spi_err_re;
    logic [31:0]  spi_err_addr, spi_err_wdata, spi_err_rdata;
    logic          spi_err_sclk, spi_err_mosi, spi_err_cs_n;

    spi_master u_spi_err (
        .clk    (clk),
        .rst_n  (rst_n),
        .sel    (spi_err_sel),
        .addr   (spi_err_addr),
        .wdata  (spi_err_wdata),
        .we     (spi_err_we),
        .re     (spi_err_re),
        .rdata  (spi_err_rdata),
        .sclk   (spi_err_sclk),
        .mosi   (spi_err_mosi),
        .miso   (1'b0),
        .cs_n   (spi_err_cs_n)
    );

    task automatic run_spi_start_while_busy_error_test();
        begin
            $display("---- B2: SPI start-while-busy error case ----");
            spi_err_sel = 1'b0; spi_err_we = 1'b0; spi_err_re = 1'b0;
            spi_err_addr = 32'd0; spi_err_wdata = 32'd0;

            @(posedge clk);
            // First START (legitimate) -> SPI_CTRL offset 0x0, START=1
            spi_err_sel = 1'b1; spi_err_we = 1'b1;
            spi_err_addr = 32'h0; spi_err_wdata = 32'h1;
            @(posedge clk);

            // Second START issued immediately while still busy -> error
            spi_err_wdata = 32'h1;
            @(posedge clk);
            spi_err_we = 1'b0;

            repeat (4) @(posedge clk);

            // Read SPI_STATUS (offset 0xC)
            spi_err_re = 1'b1; spi_err_addr = 32'hC;
            @(posedge clk);
            spi_err_re = 1'b0;

            check_true("SPI error case: ERROR bit set on start-while-busy",
                        spi_err_rdata[2]);
        end
    endtask

    // -------------------------------------------------------------
    // B3. UART framing error
    // -------------------------------------------------------------
    logic       uart_err_rx_line;
    logic [7:0] uart_err_rx_data;
    logic       uart_err_rx_valid;
    logic       uart_err_frame_error;

    uart_rx #(
        .CLKS_PER_BIT (UART_CLKS_PER_BIT)
    ) u_uart_rx_err (
        .clk         (clk),
        .rst_n       (rst_n),
        .rx_line     (uart_err_rx_line),
        .rx_data     (uart_err_rx_data),
        .rx_valid    (uart_err_rx_valid),
        .frame_error (uart_err_frame_error)
    );

    task automatic run_uart_frame_error_test();
        int i;
        begin
            $display("---- B3: UART framing error case ----");
            uart_err_rx_line = 1'b1; // idle

            @(posedge clk);
            // Drive a malformed frame: start bit, 8 data bits, then a
            // BAD stop bit (0 instead of 1) -> should raise frame_error
            uart_err_rx_line = 1'b0; // start bit
            #(UART_CLKS_PER_BIT * CLK_PERIOD_NS);

            for (i = 0; i < 8; i++) begin
                uart_err_rx_line = 1'b1; // arbitrary data bits (all 1s)
                #(UART_CLKS_PER_BIT * CLK_PERIOD_NS);
            end

            uart_err_rx_line = 1'b0; // BAD stop bit (should be 1)
            #(UART_CLKS_PER_BIT * CLK_PERIOD_NS);

            uart_err_rx_line = 1'b1; // release line back to idle
            #(UART_CLKS_PER_BIT * CLK_PERIOD_NS);

            check_true("UART error case: frame_error asserted on bad stop bit",
                        uart_err_frame_error_seen);
        end
    endtask

    // Latch the one-cycle frame_error pulse so the check above (which
    // samples after the fact) can still see that it occurred.
    logic uart_err_frame_error_seen;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            uart_err_frame_error_seen <= 1'b0;
        else if (uart_err_frame_error)
            uart_err_frame_error_seen <= 1'b1;
    end

    // -----------------------------------------------------------------
    // Waveform dump
    // -----------------------------------------------------------------
    initial begin
        $dumpfile("tb_soc_top.vcd");
        $dumpvars(0, tb_soc_top);
    end

endmodule
