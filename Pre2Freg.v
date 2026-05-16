`include "constant.v"
`include "instr_code.v"

module Pre2Freg (
    input  wire clk,
    input  wire reset,
    
    // 控制信号
    input  wire request,
    input  wire errorReturn,
    input  wire [31:0] entry,
    input  wire [31:0] returnAddr,
    input  wire D_branch,
    input  wire refetch,
    input  wire idle,
    input  wire [31:0] W_PC,

    // 握手信号
    input  wire F_done,
    input  wire D_ready,
    input  wire Pre_to_F_valid,
    output reg  F_valid,
    output wire F_ready,
    output wire F_to_D_valid,

    input  wire [31:0]  Pre_PC,
    input  wire [31:0]  branch_PC, 
    input  wire Pre_ADEF,
    input  wire Pre_PIF,
    input  wire Pre_PPI_Instr,
    input  wire Pre_TLBR_Instr,
    output reg [31:0]  F_PC,
    output reg F_ADEF,
    output reg F_PIF,
    output reg F_PPI_Instr,
    output reg F_TLBR_Instr,

    input  wire [31:0] btb_flush_target,
    input  wire btb_flush
);

assign F_ready = ~F_valid | (F_done & D_ready);
assign F_to_D_valid = F_done & F_valid /*& ~D_branch*/;

always @(posedge clk ) begin
    if (reset) begin
        F_valid <= 0;
        F_PC <= `init_pc - 4;   // 这样下一个周期就能进入目标的PC
        F_ADEF <= 0;
        F_TLBR_Instr <= 0;
        F_PPI_Instr <= 0;
        F_PIF <= 0;
    end
    else if(request) begin
        F_valid <= 0;
        F_PC <= entry - 4;
    end
    else if(errorReturn) begin  
        F_valid <= 0;
        F_PC <= returnAddr - 4;
    end
    else if(refetch | idle) begin
        F_valid <= 0;
        F_PC <= W_PC;
    end
    /*else if(D_branch) begin
        F_valid <= 0;
        F_PC <= branch_PC - 4;
    end*/
    else if(btb_flush) begin
        F_valid <= 0;
        F_PC <= btb_flush_target - 4;
    end
    else begin
        // 是否有效
        if (F_ready) begin
            F_valid <= Pre_to_F_valid;
        end
        // 接收上一级流水来的信号
        if (Pre_to_F_valid & F_ready) begin
            F_PC <= Pre_PC;
            F_ADEF <= Pre_ADEF;
            F_TLBR_Instr <= Pre_TLBR_Instr;
            F_PPI_Instr <= Pre_PPI_Instr;
            F_PIF <= Pre_PIF;
        end
    end
end

endmodule //F_PC