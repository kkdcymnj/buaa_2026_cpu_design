`include "constant.v"

module F_nextPC (
    input  wire [31:0]  F_PC,   
    input  wire D_valid,     
    input  wire D_done,
    input  wire [31:0]  D_PC,         
    input  wire         D_stall,    
    input  wire [`npc_select_width-1:0] nextPCSel,  
    input  wire cmpFlag,
    input  wire [`imm_select_width-1:0] offsetSrc, 
    input  wire [25:0]  offset26,         
    input  wire [20:0]  offset21,         
    input  wire [15:0]  offset16,         
    input  wire [31:0]  rj_value,        
    
    output wire [31:0]  nextPC,
    output wire [31:0]  branch_PC,

    input  wire [31:0] btb_flush_target,
    input  wire btb_flush,
    input  wire use_btb_target,
    input  wire [31:0] btb_pc_temp,

    input  wire [31:0]  W_PC,
    input  wire [31:0]  entry,
    input  wire [31:0]  returnAddr,
    input  wire [31:0]  br_target_buffer,
    input  wire request,
    input  wire errorReturn,
    input  wire idle,
    input  wire refetch,
    input  wire F_valid,
    input  wire wait_br_target
);

// 偏移量扩展（考虑指令对齐：乘以4）
wire [31:0] extended_offset;
assign extended_offset = 
    {32{offsetSrc[`imm_16]}} & {{14{offset16[15]}}, offset16, 2'b0} |
    {32{offsetSrc[`imm_21]}} & {{9{offset21[20]}}, offset21, 2'b0} |
    {32{offsetSrc[`imm_26]}} & {{4{offset26[25]}}, offset26, 2'b0};

// 各种目标PC计算 
assign branch_PC   = 
nextPCSel[`npc_jirl] ? (rj_value + extended_offset) :
D_PC + extended_offset;

assign nextPC = 
    /*(request) ? entry :
    (errorReturn) ? returnAddr :
    (idle | refetch) ? W_PC + 4:
    (wait_br_target) ? br_target_buffer:*/
    (btb_flush & F_valid) ? btb_flush_target :
    (use_btb_target) ? btb_pc_temp:
    F_PC + 32'h4;

endmodule