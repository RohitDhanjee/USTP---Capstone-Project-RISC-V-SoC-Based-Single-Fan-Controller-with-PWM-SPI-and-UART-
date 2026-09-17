// =====================================================================
// stall_seq.sv - Fan Stall Injection Sequence
//
// Not tied to a specific agent's sequencer -- drives vif.fan_stall_inject
// directly (obtained via uvm_config_db) to simulate a jammed/disconnected
// fan while PWM is enabled, long enough for pwm_controller's stall
// counter (STALL_CYCLES) to trip the FAULT status bit.
//
// This models the "stall detection" verification requirement from the
// project description. Run this as a plain uvm_sequence on any
// sequencer (it doesn't send items to it) or invoked directly from a
// test's run_phase.
// =====================================================================

`ifndef STALL_SEQ_SV
`define STALL_SEQ_SV

class stall_seq extends uvm_sequence #(uvm_sequence_item);

    `uvm_object_utils(stall_seq)

    virtual soc_if vif;
    int stall_duration_cycles = 1200; // > pwm_controller's STALL_CYCLES (1024)

    function new(string name = "stall_seq");
        super.new(name);
    endfunction

    task body();
        if (!uvm_config_db#(virtual soc_if)::get(null, "*", "vif", vif))
            `uvm_fatal("STALL_SEQ", "Could not get vif from config_db")

        `uvm_info("STALL_SEQ",
            $sformatf("Injecting fan stall for %0d clk cycles", stall_duration_cycles),
            UVM_MEDIUM)

        vif.fan_stall_inject <= 1'b1;
        repeat (stall_duration_cycles) @(posedge vif.clk);

        `uvm_info("STALL_SEQ",
            $sformatf("Releasing fan stall (pwm_fault_tap=%0b)", vif.pwm_fault_tap),
            UVM_MEDIUM)

        vif.fan_stall_inject <= 1'b0;
    endtask

endclass

`endif
