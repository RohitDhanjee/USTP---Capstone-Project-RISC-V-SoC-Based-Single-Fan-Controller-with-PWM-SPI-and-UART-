// =====================================================================
// uvm_pkg_includes.sv - SoC UVM Package
//
// Compile order requirement: soc_if.sv MUST be compiled BEFORE this
// package (interfaces cannot be declared inside a package, but classes
// in this package reference `virtual soc_if`, which requires the
// interface to already be visible at the compilation-unit scope).
//
// See tb_filelist_uvm.f for the full recommended compile order.
// =====================================================================

`include "uvm_macros.svh"

package soc_uvm_pkg;

    import uvm_pkg::*;

    // ---- SPI agent ----
    `include "spi_agent/spi_seq_item.sv"
    `include "spi_agent/spi_sequencer.sv"
    `include "spi_agent/spi_driver.sv"
    `include "spi_agent/spi_monitor.sv"
    `include "spi_agent/spi_agent.sv"

    // ---- UART agent ----
    `include "uart_agent/uart_seq_item.sv"
    `include "uart_agent/uart_sequencer.sv"
    `include "uart_agent/uart_driver.sv"
    `include "uart_agent/uart_monitor.sv"
    `include "uart_agent/uart_agent.sv"

    // ---- PWM agent (monitor-only) ----
    `include "pwm_agent/pwm_monitor.sv"
    `include "pwm_agent/pwm_agent.sv"

    // ---- Scoreboard / coverage ----
    `include "scoreboard.sv"

    // ---- Environment ----
    `include "env.sv"

    // ---- Sequences ----
    `include "sequences/normal_seq.sv"
    `include "sequences/error_seq.sv"
    `include "sequences/stall_seq.sv"
    `include "sequences/failsafe_seq.sv"

    // ---- Tests ----
    `include "test_lib.sv"

endpackage
