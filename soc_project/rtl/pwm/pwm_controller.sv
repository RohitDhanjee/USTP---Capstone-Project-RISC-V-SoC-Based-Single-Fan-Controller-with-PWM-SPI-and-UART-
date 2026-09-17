// =====================================================================
// pwm_controller.sv - Single-Channel PWM Fan Controller
//
// Register map (offsets relative to base 0x3000_0000, see memory_map.md):
//   0x0  PWM_CTRL    R/W  [0]=EN, [1]=SOFT_RESET
//   0x4  PWM_DUTY    R/W  [7:0]  duty cycle (0-255)
//   0x8  PWM_STATUS  R    [0]=RUNNING, [1]=FAULT
//   0xC  PWM_RPM     R    [15:0] simulated RPM (from fan model)
//
// PWM generation: free-running 8-bit counter compared against the duty
// register. pwm_out is high while counter < duty_reg.
//
// FAULT is asserted if the PWM is enabled but the fan model reports
// rpm_in == 0 for STALL_CYCLES consecutive clock cycles (stall
// detection), representing a jammed/disconnected fan.
// =====================================================================

module pwm_controller #(
    parameter int STALL_CYCLES = 1024
) (
    input  logic         clk,
    input  logic         rst_n,

    // Bus interface (from addr_decoder)
    input  logic          sel,
    input  logic [31:0]  addr,
    input  logic [31:0]  wdata,
    input  logic          we,
    input  logic          re,
    output logic [31:0]  rdata,

    // To fan model
    output logic          pwm_out,

    // From fan model
    input  logic [15:0]  rpm_in
);

    // -----------------------------------------------------------------
    // Registers
    // -----------------------------------------------------------------
    logic        en_reg;
    logic        soft_reset_reg;
    logic [7:0]  duty_reg;

    wire [3:0] reg_offset = addr[3:0];

    // Write path
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_reg         <= 1'b0;
            soft_reset_reg <= 1'b0;
            duty_reg       <= 8'd0;
        end else if (sel && we) begin
            case (reg_offset)
                4'h0: begin
                    en_reg         <= wdata[0];
                    soft_reset_reg <= wdata[1];
                end
                4'h4: duty_reg <= wdata[7:0];
                default: ; // STATUS/RPM are read-only, ignore writes
            endcase
        end else begin
            soft_reset_reg <= 1'b0; // self-clearing pulse
        end
    end

    // -----------------------------------------------------------------
    // PWM generation: free-running counter + comparator
    // -----------------------------------------------------------------
    logic [7:0] pwm_counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_reg)
            pwm_counter <= 8'd0;
        else
            pwm_counter <= pwm_counter + 8'd1;
    end

    assign pwm_out = en_reg && (pwm_counter < duty_reg);

    // -----------------------------------------------------------------
    // Stall / fault detection
    // -----------------------------------------------------------------
    logic [$clog2(STALL_CYCLES+1)-1:0] stall_counter;
    logic fault_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset_reg) begin
            stall_counter <= '0;
            fault_reg     <= 1'b0;
        end else if (en_reg && (rpm_in == 16'd0)) begin
            if (stall_counter == STALL_CYCLES) begin
                fault_reg <= 1'b1;
            end else begin
                stall_counter <= stall_counter + 1'b1;
            end
        end else begin
            stall_counter <= '0;
            fault_reg     <= 1'b0;
        end
    end

    wire running_flag = en_reg && (rpm_in != 16'd0);

    // -----------------------------------------------------------------
    // Read path
    // -----------------------------------------------------------------
    always_comb begin
        rdata = 32'd0;
        if (sel && re) begin
            case (reg_offset)
                4'h0: rdata = {30'd0, soft_reset_reg, en_reg};
                4'h4: rdata = {24'd0, duty_reg};
                4'h8: rdata = {30'd0, fault_reg, running_flag};
                4'hC: rdata = {16'd0, rpm_in};
                default: rdata = 32'd0;
            endcase
        end
    end

endmodule
