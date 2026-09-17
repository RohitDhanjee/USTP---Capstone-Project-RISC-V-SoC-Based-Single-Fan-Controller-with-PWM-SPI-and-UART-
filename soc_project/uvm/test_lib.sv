// =====================================================================
// test_lib.sv - UVM Tests
//
//   base_test      : builds the env, wires up the virtual interface
//                     and UART timing to all agents. Not run directly.
//   normal_test     : runs SPI/UART normal sequences (profile load +
//                     host commands), letting the core's own program
//                     (test_program.hex) run concurrently.
//   error_test      : runs SPI "no response" and UART "bad frame"
//                     error sequences.
//   failsafe_test   : runs the stall -> recovery fail-safe sequence.
//   regression_test : runs normal, error, and failsafe scenarios
//                     back-to-back for a single full-regression run.
// =====================================================================

`ifndef TEST_LIB_SV
`define TEST_LIB_SV

class base_test extends uvm_test;

    `uvm_component_utils(base_test)

    soc_env env;
    virtual soc_if vif;
    real uart_bit_period_ns = 320.0; // must match tb_top_uvm's DUT config

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("BASE_TEST", "Could not get vif from config_db")

        env = soc_env::type_id::create("env", this);

        // Propagate vif + UART timing to every agent component
        uvm_config_db#(virtual soc_if)::set(this, "env.*", "vif", vif);
        uvm_config_db#(real)::set(this, "env.uart_agt.*", "bit_period_ns", uart_bit_period_ns);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

endclass

// ---------------------------------------------------------------------
class normal_test extends base_test;

    `uvm_component_utils(normal_test)

    function new(string name = "normal_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_normal_seq  spi_seq;
        uart_normal_seq uart_seq;

        phase.raise_objection(this);
        `uvm_info("NORMAL_TEST", "Starting normal-operation test", UVM_LOW)

        // Let the core's own program (test_program.hex) run through
        // reset and its initial SRAM/PWM/SPI/UART sequence first.
        #20000;

        spi_seq  = spi_normal_seq::type_id::create("spi_seq");
        uart_seq = uart_normal_seq::type_id::create("uart_seq");

        fork
            spi_seq.start(env.spi_agt.sequencer);
            uart_seq.start(env.uart_agt.sequencer);
        join

        #20000;

        `uvm_info("NORMAL_TEST", "Normal-operation test complete", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass

// ---------------------------------------------------------------------
class error_test extends base_test;

    `uvm_component_utils(error_test)

    function new(string name = "error_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_error_seq  spi_err;
        uart_error_seq uart_err;

        phase.raise_objection(this);
        `uvm_info("ERROR_TEST", "Starting error-case test", UVM_LOW)

        #20000;

        spi_err  = spi_error_seq::type_id::create("spi_err");
        uart_err = uart_error_seq::type_id::create("uart_err");

        spi_err.start(env.spi_agt.sequencer);
        #5000;
        uart_err.start(env.uart_agt.sequencer);

        #10000;

        `uvm_info("ERROR_TEST", "Error-case test complete", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass

// ---------------------------------------------------------------------
class failsafe_test extends base_test;

    `uvm_component_utils(failsafe_test)

    function new(string name = "failsafe_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        failsafe_seq fs_seq;

        phase.raise_objection(this);
        `uvm_info("FAILSAFE_TEST", "Starting fail-safe (stall/recovery) test", UVM_LOW)

        // Give the core time to enable PWM first (per test_program.hex)
        #5000;

        fs_seq = failsafe_seq::type_id::create("fs_seq");
        fs_seq.start(null); // not tied to a sequencer; drives vif directly

        `uvm_info("FAILSAFE_TEST", "Fail-safe test complete", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass

// ---------------------------------------------------------------------
class regression_test extends base_test;

    `uvm_component_utils(regression_test)

    function new(string name = "regression_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_normal_seq  spi_norm;
        uart_normal_seq uart_norm;
        spi_error_seq   spi_err;
        uart_error_seq  uart_err;
        failsafe_seq    fs_seq;

        phase.raise_objection(this);
        `uvm_info("REGRESSION_TEST", "Starting full regression", UVM_LOW)

        #20000; // let core program run

        spi_norm  = spi_normal_seq::type_id::create("spi_norm");
        uart_norm = uart_normal_seq::type_id::create("uart_norm");
        fork
            spi_norm.start(env.spi_agt.sequencer);
            uart_norm.start(env.uart_agt.sequencer);
        join

        #10000;

        spi_err  = spi_error_seq::type_id::create("spi_err");
        uart_err = uart_error_seq::type_id::create("uart_err");
        spi_err.start(env.spi_agt.sequencer);
        #5000;
        uart_err.start(env.uart_agt.sequencer);

        #10000;

        fs_seq = failsafe_seq::type_id::create("fs_seq");
        fs_seq.start(null);

        `uvm_info("REGRESSION_TEST", "Full regression complete", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass

`endif
