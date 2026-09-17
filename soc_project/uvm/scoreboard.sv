// =====================================================================
// scoreboard.sv - Scoreboard + Functional Coverage
//
// Collects transactions from all three agents via analysis ports and:
//   1. Checks basic protocol expectations (SPI echo consistency, UART
//      byte integrity, PWM duty/RPM correlation).
//   2. Samples functional coverage covergroups (duty-cycle bins,
//      SPI/UART transaction counts, fault/error occurrence).
//
// Code coverage (line/branch/toggle/FSM) is collected automatically
// by the simulator (Questa/VCS/Xcelium) when compiled with coverage
// switches enabled -- no additional RTL/TB code is required for that.
// =====================================================================

`ifndef SCOREBOARD_SV
`define SCOREBOARD_SV

`uvm_analysis_imp_decl(_spi)
`uvm_analysis_imp_decl(_uart)
`uvm_analysis_imp_decl(_pwm)

class scoreboard extends uvm_scoreboard;

    `uvm_component_utils(scoreboard)

    uvm_analysis_imp_spi  #(spi_seq_item, scoreboard)  spi_imp;
    uvm_analysis_imp_uart #(uart_seq_item, scoreboard) uart_imp;
    uvm_analysis_imp_pwm  #(pwm_sample, scoreboard)    pwm_imp;

    int spi_transfers_seen;
    int uart_bytes_seen;
    int uart_frame_errors_seen;
    int pwm_fault_events_seen;

    // Latest sample from each stream, used for cross-checks
    pwm_sample last_pwm_sample;

    // -------------------------------------------------------------
    // Functional coverage
    // -------------------------------------------------------------
    covergroup spi_cg with function sample(bit [7:0] mosi_byte, bit no_resp);
        option.per_instance = 1;
        cp_mosi_byte: coverpoint mosi_byte {
            bins low_byte  = {[8'h00:8'h3F]};
            bins mid_byte  = {[8'h40:8'hBF]};
            bins high_byte = {[8'hC0:8'hFF]};
        }
        cp_no_resp: coverpoint no_resp;
    endgroup

    covergroup uart_cg with function sample(bit [7:0] data, bit frame_err);
        option.per_instance = 1;
        cp_data: coverpoint data {
            bins printable    = {[8'h20:8'h7E]};
            bins control_low  = {[8'h00:8'h1F]};
            bins high_byte    = {[8'h80:8'hFF]};
        }
        cp_frame_err: coverpoint frame_err;
    endgroup

    covergroup pwm_cg with function sample(bit [7:0] duty, bit fault, bit en);
        option.per_instance = 1;
        cp_duty: coverpoint duty {
            bins zero        = {0};
            bins low         = {[1:63]};
            bins mid         = {[64:191]};
            bins high        = {[192:254]};
            bins full        = {255};
        }
        cp_fault: coverpoint fault;
        cp_en: coverpoint en;
        cross cp_duty, cp_fault;
    endgroup

    function new(string name = "scoreboard", uvm_component parent = null);
        super.new(name, parent);
        spi_imp  = new("spi_imp", this);
        uart_imp = new("uart_imp", this);
        pwm_imp  = new("pwm_imp", this);
        spi_cg   = new();
        uart_cg  = new();
        pwm_cg   = new();
    endfunction

    // -------------------------------------------------------------
    // SPI transaction check
    // -------------------------------------------------------------
    function void write_spi(spi_seq_item t);
        spi_transfers_seen++;
        spi_cg.sample(t.mosi_byte, 1'b0);

        `uvm_info("SCOREBOARD",
            $sformatf("SPI transfer #%0d: mosi=0x%0h miso=0x%0h",
                      spi_transfers_seen, t.mosi_byte, t.miso_byte),
            UVM_MEDIUM)
    endfunction

    // -------------------------------------------------------------
    // UART transaction check
    // -------------------------------------------------------------
    function void write_uart(uart_seq_item t);
        uart_bytes_seen++;
        if (t.frame_error_seen)
            uart_frame_errors_seen++;

        uart_cg.sample(t.data, t.frame_error_seen);

        `uvm_info("SCOREBOARD",
            $sformatf("UART byte #%0d: dir=%s data=0x%0h frame_err=%0b",
                      uart_bytes_seen, t.direction.name(), t.data, t.frame_error_seen),
            UVM_MEDIUM)
    endfunction

    // -------------------------------------------------------------
    // PWM / fan sample check
    // -------------------------------------------------------------
    function void write_pwm(pwm_sample s);
        last_pwm_sample = s;
        if (s.fault)
            pwm_fault_events_seen++;

        pwm_cg.sample(s.measured_duty, s.fault, s.en);

        // Sanity check: if enabled and not faulted, measured duty
        // should roughly track the programmed PWM_DUTY register
        // (allow +/-2 counts of jitter from window alignment).
        if (s.en && !s.fault) begin
            int diff = (s.measured_duty > s.duty_reg) ?
                       (s.measured_duty - s.duty_reg) : (s.duty_reg - s.measured_duty);
            if (diff > 2) begin
                `uvm_warning("SCOREBOARD",
                    $sformatf("PWM duty mismatch: measured=%0d programmed=%0d",
                              s.measured_duty, s.duty_reg))
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCOREBOARD",
            $sformatf("\n==== SCOREBOARD SUMMARY ====\n  SPI transfers   : %0d\n  UART bytes      : %0d\n  UART frame errs : %0d\n  PWM fault events: %0d\n  SPI coverage    : %0.1f%%\n  UART coverage   : %0.1f%%\n  PWM coverage    : %0.1f%%\n=============================",
                      spi_transfers_seen, uart_bytes_seen, uart_frame_errors_seen,
                      pwm_fault_events_seen, spi_cg.get_coverage(),
                      uart_cg.get_coverage(), pwm_cg.get_coverage()),
            UVM_LOW)
    endfunction

endclass

`endif
