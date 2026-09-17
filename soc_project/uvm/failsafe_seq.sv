// =====================================================================
// failsafe_seq.sv - Fail-Safe Behavior Sequence
//
// Exercises the full fail-safe flow:
//   1. Fan runs normally (assumed already enabled by prior test steps).
//   2. Fan stalls (jammed) -> FAULT should assert after STALL_CYCLES.
//   3. Fan is un-jammed (stall released) -> FAULT should clear once
//      pwm_controller observes rpm_in != 0 again.
//
// This is the project's "fail-safe behavior" verification requirement:
// the system must detect the fault condition AND recover cleanly once
// the fault clears, rather than latching into a permanently broken
// state.
// =====================================================================

`ifndef FAILSAFE_SEQ_SV
`define FAILSAFE_SEQ_SV

class failsafe_seq extends uvm_sequence #(uvm_sequence_item);

    `uvm_object_utils(failsafe_seq)

    virtual soc_if vif;
    int stall_cycles    = 1200; // > STALL_CYCLES threshold (1024)
    int recovery_cycles = 600;  // time given for FAULT to clear after recovery

    function new(string name = "failsafe_seq");
        super.new(name);
    endfunction

    task body();
        bit fault_seen_during_stall;
        bit fault_cleared_after_recovery;

        if (!uvm_config_db#(virtual soc_if)::get(null, "*", "vif", vif))
            `uvm_fatal("FAILSAFE_SEQ", "Could not get vif from config_db")

        // ---- Step 1: inject stall ----
        `uvm_info("FAILSAFE_SEQ", "Step 1: injecting fan stall", UVM_MEDIUM)
        vif.fan_stall_inject <= 1'b1;

        fault_seen_during_stall = 1'b0;
        repeat (stall_cycles) begin
            @(posedge vif.clk);
            if (vif.pwm_fault_tap)
                fault_seen_during_stall = 1'b1;
        end

        if (fault_seen_during_stall)
            `uvm_info("FAILSAFE_SEQ", "PASS: FAULT asserted during stall", UVM_LOW)
        else
            `uvm_error("FAILSAFE_SEQ", "FAIL: FAULT never asserted during stall")

        // ---- Step 2: release stall, allow recovery ----
        `uvm_info("FAILSAFE_SEQ", "Step 2: releasing stall, checking recovery", UVM_MEDIUM)
        vif.fan_stall_inject <= 1'b0;

        fault_cleared_after_recovery = 1'b0;
        repeat (recovery_cycles) begin
            @(posedge vif.clk);
            if (!vif.pwm_fault_tap)
                fault_cleared_after_recovery = 1'b1;
        end

        if (fault_cleared_after_recovery)
            `uvm_info("FAILSAFE_SEQ", "PASS: FAULT cleared after fan recovery", UVM_LOW)
        else
            `uvm_error("FAILSAFE_SEQ", "FAIL: FAULT did not clear after fan recovery")
    endtask

endclass

`endif
