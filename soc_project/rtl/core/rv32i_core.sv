// =====================================================================
// rv32i_core.sv - RV32I Single-Cycle Core (Top-Level)
//
// Interfaces:
//   - Instruction memory: imem_addr (out) / imem_rdata (in)
//   - Data memory / peripheral bus: dmem_addr, dmem_wdata, dmem_we,
//     dmem_re (out) / dmem_rdata (in)
//
// Supports base RV32I integer instructions (see architecture.md 3.2).
// All loads/stores are treated as word (32-bit) accesses in this
// project (LW/SW only), matching the SRAM/peripheral register widths.
// =====================================================================

module rv32i_core
    import alu_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // Instruction memory interface
    output logic [31:0]  imem_addr,
    input  logic [31:0]  imem_rdata,

    // Data memory / peripheral bus interface
    output logic [31:0]  dmem_addr,
    output logic [31:0]  dmem_wdata,
    output logic         dmem_we,
    output logic         dmem_re,
    input  logic [31:0]  dmem_rdata
);

    // -----------------------------------------------------------------
    // Program Counter
    // -----------------------------------------------------------------
    logic [31:0] pc, pc_next, pc_plus4;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= 32'd0;
        else
            pc <= pc_next;
    end

    assign imem_addr = pc;
    assign pc_plus4  = pc + 32'd4;

    // -----------------------------------------------------------------
    // Instruction fields
    // -----------------------------------------------------------------
    logic [31:0] instr;
    assign instr = imem_rdata;

    logic [6:0] opcode;
    logic [4:0] rd_addr, rs1_addr, rs2_addr;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode   = instr[6:0];
    assign rd_addr  = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign funct7   = instr[31:25];

    // -----------------------------------------------------------------
    // Control Unit
    // -----------------------------------------------------------------
    alu_op_e alu_op;
    logic    alu_src_b, mem_we, mem_re, reg_we;
    logic [1:0] wb_sel;
    logic    branch, jump, jalr, pc_plus_imm_for_auipc, illegal_instr;

    control_unit u_control (
        .opcode                (opcode),
        .funct3                (funct3),
        .funct7                (funct7),
        .alu_op                (alu_op),
        .alu_src_b             (alu_src_b),
        .mem_we                (mem_we),
        .mem_re                (mem_re),
        .reg_we                (reg_we),
        .wb_sel                (wb_sel),
        .branch                (branch),
        .jump                  (jump),
        .jalr                  (jalr),
        .pc_plus_imm_for_auipc (pc_plus_imm_for_auipc),
        .illegal_instr         (illegal_instr)
    );

    // -----------------------------------------------------------------
    // Immediate Generator
    // -----------------------------------------------------------------
    logic [31:0] imm;
    imm_gen u_imm_gen (
        .instr   (instr),
        .imm_out (imm)
    );

    // -----------------------------------------------------------------
    // Register File
    // -----------------------------------------------------------------
    logic [31:0] rs1_data, rs2_data, rd_wdata;

    regfile u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .rd_addr  (rd_addr),
        .rd_data  (rd_wdata),
        .rd_we    (reg_we)
    );

    // -----------------------------------------------------------------
    // ALU
    // -----------------------------------------------------------------
    logic [31:0] alu_operand_a, alu_operand_b, alu_result;
    logic        alu_zero;

    assign alu_operand_a = pc_plus_imm_for_auipc ? pc : rs1_data;
    assign alu_operand_b = alu_src_b ? imm : rs2_data;

    alu u_alu (
        .operand_a (alu_operand_a),
        .operand_b (alu_operand_b),
        .alu_op    (alu_op),
        .result    (alu_result),
        .zero_flag (alu_zero)
    );

    // -----------------------------------------------------------------
    // Branch condition resolution
    // -----------------------------------------------------------------
    logic branch_taken;
    always_comb begin
        branch_taken = 1'b0;
        if (branch) begin
            case (funct3)
                3'b000: branch_taken = alu_zero;                 // BEQ
                3'b001: branch_taken = ~alu_zero;                // BNE
                3'b100: branch_taken = alu_result[0];            // BLT  (SLT result)
                3'b101: branch_taken = ~alu_result[0];           // BGE
                3'b110: branch_taken = alu_result[0];            // BLTU (SLTU result)
                3'b111: branch_taken = ~alu_result[0];           // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

    // -----------------------------------------------------------------
    // Data memory / peripheral bus interface
    // -----------------------------------------------------------------
    assign dmem_addr  = alu_result;   // rs1 + imm (base + offset)
    assign dmem_wdata = rs2_data;
    assign dmem_we    = mem_we;
    assign dmem_re    = mem_re;

    // -----------------------------------------------------------------
    // Writeback mux
    // -----------------------------------------------------------------
    always_comb begin
        case (wb_sel)
            2'b00:   rd_wdata = alu_result;   // ALU result
            2'b01:   rd_wdata = dmem_rdata;   // Load data
            2'b10:   rd_wdata = pc_plus4;     // JAL/JALR return address
            2'b11:   rd_wdata = imm;          // LUI
            default: rd_wdata = 32'd0;
        endcase
    end

    // -----------------------------------------------------------------
    // Next PC logic
    // -----------------------------------------------------------------
    always_comb begin
        if (jalr)
            pc_next = (rs1_data + imm) & ~32'd1; // clear LSB per spec
        else if (jump) // JAL
            pc_next = pc + imm;
        else if (branch_taken)
            pc_next = pc + imm;
        else
            pc_next = pc_plus4;
    end

endmodule
