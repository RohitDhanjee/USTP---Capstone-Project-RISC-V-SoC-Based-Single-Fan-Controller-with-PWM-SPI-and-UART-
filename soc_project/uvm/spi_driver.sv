// =====================================================================
// spi_driver.sv - SPI Driver
//
// The DUT's spi_master is always the SPI *master*. This driver plays
// the role of the external SPI *slave* (the "smart fan module"),
// consuming spi_seq_item transactions from the sequencer and driving
// MISO accordingly, while capturing what the DUT sent on MOSI.
//
// Edge convention (Mode 0, matches spi_master.sv / spi_slave_model.sv):
//   - Slave drives MISO on SCLK falling edge (setup for master's
//     next high phase).
//   - Slave samples MOSI on SCLK rising edge.
// =====================================================================

`ifndef SPI_DRIVER_SV
`define SPI_DRIVER_SV

class spi_driver extends uvm_driver #(spi_seq_item);

    `uvm_component_utils(spi_driver)

    virtual soc_if vif;

    function new(string name = "spi_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual soc_if)::get(this, "", "vif", vif))
            `uvm_fatal("SPI_DRV", "Virtual interface not set for spi_driver")
    endfunction

    task run_phase(uvm_phase phase);
        spi_seq_item req;
        bit [7:0] tx_shift, rx_shift;
        bit [2:0] bit_cnt;

        vif.spi_miso <= 1'b0;

        forever begin
            seq_item_port.get_next_item(req);

            // Wait for the DUT to assert CS (start of a transfer)
            @(negedge vif.spi_cs_n);

            tx_shift = req.resp_byte;
            rx_shift = 8'd0;
            bit_cnt  = 3'd0;

            fork
                begin : drive_miso
                    forever begin
                        @(negedge vif.spi_sclk or posedge vif.spi_cs_n);
                        if (vif.spi_cs_n) disable drive_miso;
                        vif.spi_miso <= req.inject_no_response ? 1'b0 : tx_shift[7];
                        tx_shift = {tx_shift[6:0], 1'b0};
                    end
                end
                begin : sample_mosi
                    forever begin
                        @(posedge vif.spi_sclk or posedge vif.spi_cs_n);
                        if (vif.spi_cs_n) disable sample_mosi;
                        rx_shift = {rx_shift[6:0], vif.spi_mosi};
                        bit_cnt  = bit_cnt + 3'd1;
                    end
                end
                begin : wait_cs_done
                    @(posedge vif.spi_cs_n);
                end
            join_any
            disable fork;

            req.mosi_byte = rx_shift;
            req.miso_byte = req.resp_byte;

            `uvm_info("SPI_DRV",
                $sformatf("Transfer done: sent=0x%0h received=0x%0h no_resp=%0b",
                          req.resp_byte, req.mosi_byte, req.inject_no_response),
                UVM_MEDIUM)

            seq_item_port.item_done();
        end
    endtask

endclass

`endif
