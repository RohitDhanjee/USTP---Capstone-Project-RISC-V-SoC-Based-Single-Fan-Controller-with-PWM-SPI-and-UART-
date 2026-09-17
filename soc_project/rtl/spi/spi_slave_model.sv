// =====================================================================
// spi_slave_model.sv - SPI Slave Behavioral Model (testbench-side)
//
// Not a DUT peripheral -- represents an external device (e.g. a
// "smart fan module") that the spi_master talks to. Responds to each
// 8-bit transfer with the next byte from a preloaded profile_bytes[]
// array (e.g. fan profile data: temp thresholds, duty values, ID),
// and captures whatever the master sends on MOSI into rx_log[] for
// the testbench to check.
//
// Mode 0 SPI (CPOL=0, CPHA=0): slave shifts MISO out on SCLK falling
// edge (so it is stable for the master's rising-edge sample), and
// samples MOSI on SCLK rising edge -- matching spi_master.sv.
// =====================================================================

module spi_slave_model #(
    parameter int NUM_PROFILE_BYTES = 8
) (
    input  logic          sclk,
    input  logic          cs_n,
    input  logic          mosi,
    output logic          miso,

    // Testbench control/inspection
    input  logic [7:0]   profile_bytes [0:NUM_PROFILE_BYTES-1],
    output logic [7:0]   rx_log        [0:NUM_PROFILE_BYTES-1],
    output int           transfer_count
);

    logic [7:0] tx_shift;
    logic [7:0] rx_shift;
    logic [2:0] bit_cnt;
    int         profile_idx;

    // Load next profile byte whenever CS is asserted (falling edge)
    always @(negedge cs_n) begin
        tx_shift = profile_bytes[profile_idx % NUM_PROFILE_BYTES];
        bit_cnt  = 3'd0;
        rx_shift = 8'd0;
    end

    // Drive MISO on SCLK falling edge (setup for master's next rising
    // edge sample), MSB first
    always @(negedge sclk or posedge cs_n) begin
        if (cs_n) begin
            miso <= 1'b0;
        end else begin
            miso <= tx_shift[7];
        end
    end

    // Sample MOSI on SCLK rising edge, shift both registers
    always @(posedge sclk) begin
        if (!cs_n) begin
            rx_shift = {rx_shift[6:0], mosi};
            tx_shift = {tx_shift[6:0], 1'b0};
            bit_cnt  = bit_cnt + 3'd1;
        end
    end

    // On CS deassert (transfer complete), log received byte and
    // advance to the next profile byte for the following transfer
    always @(posedge cs_n) begin
        if (bit_cnt == 3'd0) begin // full 8 bits were shifted (wrapped back to 0)
            rx_log[profile_idx % NUM_PROFILE_BYTES] <= rx_shift;
            profile_idx <= profile_idx + 1;
            transfer_count <= transfer_count + 1;
        end
    end

    initial begin
        profile_idx    = 0;
        transfer_count = 0;
        miso           = 1'b0;
    end

endmodule
