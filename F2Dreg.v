`include "constant.v"

module F2Dreg (
    input  wire clk,
    input  wire reset,

    input  wire flush,

    input  wire [31:0]  F_PC,
    input  wire [31:0]  F_instr,
    output reg [31:0]   D_PC,
    output reg [31:0]   D_PCwith4,
    output reg [31:0]   D_PCwith8,
    output reg [31:0]   D_instr,

    input  wire F_ADEF,
    input  wire F_PIF,
    input  wire F_PPI_Instr,
    input  wire F_TLBR_Instr,
    output reg D_ADEF,
    output reg D_PIF,
    output reg D_PPI_Instr,
    output reg D_TLBR_Instr,

    // 握手信号
    input  wire D_done,
    input  wire E_ready,
    input  wire F_to_D_valid,
    output reg  D_valid,
    output wire D_ready,
    output wire D_to_E_valid,

    input  wire D_btb_flush,

    input  wire [31:0] F_btb_pc,
    input  wire [4:0]   F_btb_index,
    input  wire F_btb_taken,
    input  wire F_btb_enable,
    output reg  [31:0] D_btb_pc,
    output reg  [4:0]   D_btb_index,
    output reg  D_btb_taken,
    output reg  D_btb_enable
);

assign D_ready = ~D_valid | (D_done & E_ready);
assign D_to_E_valid = D_done & D_valid;

// wire writeEnable = ~D_stall;

always @(posedge clk ) begin
    if (reset) begin
        D_valid <= 0;
        D_PC <= `init_pc ;
        D_PCwith4 <= `init_pc + 4;
        D_PCwith8 <= `init_pc + 8;
        D_instr <= 0;
        D_ADEF <= 0;
        D_TLBR_Instr <= 0;
        D_PPI_Instr <= 0;
        D_PIF <= 0;
        D_btb_pc <= 0;
        D_btb_index <= 0;
        D_btb_taken <= 0;
        D_btb_enable <= 0;
    end
    else if(flush) begin
        D_valid <= 0;
    end
    else begin
        if(D_ready) begin
            if (D_btb_flush & E_ready) begin
                D_valid <= 0;
            end
            else begin
                D_valid <= F_to_D_valid;
            end
        end

        if(F_to_D_valid & D_ready) begin
            D_PC <= F_PC;
            D_PCwith4 <= F_PC + 4;
            D_PCwith8 <= F_PC + 8;
            D_instr <= F_instr;
            D_ADEF <= F_ADEF;
            D_TLBR_Instr <= F_TLBR_Instr;
            D_PPI_Instr <= F_PPI_Instr;
            D_PIF <= F_PIF;
            D_btb_pc <= F_btb_pc;
            D_btb_index <= F_btb_index;
            D_btb_taken <= F_btb_taken;
            D_btb_enable <= F_btb_enable;
        end
    end
end

endmodule //F2Dreg