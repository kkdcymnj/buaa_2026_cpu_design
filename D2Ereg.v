`include "constant.v"

module D2Ereg (
    input  wire clk,
    input  wire reset,
    
    input  wire flush,
    input  wire stall,

    input  wire [31:0]  D_PC,
    output reg  [31:0]  E_PC,
    output reg  [31:0]  E_PCwith4,
    output reg  [31:0]  E_PCwith8,

    input  wire [2:0]   D_GPR_new,
    output reg  [2:0]   E_GPR_new,

    input  wire [`alu_src_select_width-1:0] D_aluSrcA,
    input  wire [`alu_src_select_width-1:0] D_aluSrcB,
    input  wire [`alu_op_width-1:0]         D_aluOp,
    input  wire [4:0]   D_shamt,
    input  wire D_mult,
    input  wire D_div,
    input  wire D_mult_div_signed, 
    output reg [`alu_src_select_width-1:0] E_aluSrcA,
    output reg [`alu_src_select_width-1:0] E_aluSrcB,
    output reg [`alu_op_width-1:0]         E_aluOp,
    output reg [4:0]   E_shamt,
    output reg E_mult,
    output reg E_div,
    output reg E_mult_div_signed,

    input  wire D_memWrite,
    input  wire D_memReadOrWrite,
    input  wire D_memSigned,
    input  wire [`data_type_sel_width-1:0]  D_memDataType,
    output reg  E_memWrite,
    output reg  E_memReadOrWrite,
    output reg  E_memSigned,
    output reg  [`data_type_sel_width-1:0]  E_memDataType,

    input  wire D_regWrite,
    input  wire [4:0]                           D_regWriteAddr,
    input  wire [`data_src_select_width-1:0]    D_regWriteDataSrc,
    output reg  E_regWrite,
    output reg  [4:0]                           E_regWriteAddr,
    output reg  [`data_src_select_width-1:0]    E_regWriteDataSrc,

    input  wire [31:0]  D_rjVal,
    input  wire [31:0]  D_rdkVal,
    input  wire [4:0]   D_rj,
    input  wire [4:0]   D_rdk,
    output reg  [31:0]  E_rjVal,
    output reg  [31:0]  E_rdkVal,
    output reg  [4:0]   E_rj,
    output reg  [4:0]   E_rdk,

    input  wire [31:0]  D_extended,
    output reg  [31:0]  E_extended,

    input  wire D_INE,
    input  wire D_BRK,
    input  wire D_SYSCALL,
    input  wire D_ADEF,
    input  wire D_INT,
    input  wire D_TLBR_Instr,
    input  wire D_IPE,
    input  wire D_PPI_Instr,
    input  wire D_PIF,
    output reg E_INE,
    output reg E_BRK,
    output reg E_SYSCALL,
    output reg E_ADEF,
    output reg E_INT,
    output reg E_TLBR_Instr,
    output reg E_IPE,
    output reg E_PPI_Instr,
    output reg E_PIF,

    input  wire D_csrWrite,
    input  wire [`csr_addr_width-1:0] D_csrWriteAddr,
    input  wire [31:0] D_csrMaskVal,
    input  wire D_csrMask,
    input  wire D_csrNum_TID,
    output reg  E_csrWrite,
    output reg  [`csr_addr_width-1:0] E_csrWriteAddr,
    output reg  [31:0] E_csrMaskVal,
    output reg  E_csrMask,
    output reg  E_csrNum_TID,

    input  wire [31:0] D_cnt_result,
    output reg  [31:0] E_cnt_result,

    input  wire D_errorReturn,
    input  wire D_idle,
    input  wire D_refetch,
    output reg E_errorReturn,
    output reg E_idle,
    output reg E_refetch,

    input  wire [`TLB_OP_WIDTH-1:0] D_TLB_operation,
    output reg [`TLB_OP_WIDTH-1:0] E_TLB_operation,

    input  wire [31:0] D_instr,
    output reg [31:0] E_instr, 

    input  wire [31:0] D_csrReadData,
    output reg [31:0] E_csrReadData,  

    input  wire [31:0] D_highCnt,
    input  wire [31:0] D_lowCnt,
    output reg  [31:0] E_highCnt,
    output reg  [31:0] E_lowCnt,

    //握手信号
    input  wire E_done,
    input  wire M_ready,
    input  wire D_to_E_valid,
    output reg  E_valid,
    output wire E_ready,
    output wire E_to_M_valid,

    input wire [ `CACHE_TARGET_WIDTH-1:0] D_cache_target,
    input wire [     `CACHE_OP_WIDTH-1:0] D_cache_operation,
    output reg [ `CACHE_TARGET_WIDTH-1:0] E_cache_target,
    output reg [     `CACHE_OP_WIDTH-1:0] E_cache_operation,

    input  wire D_is_LL_W,
    input  wire D_is_SC_W,
    input  wire D_mem_write_cond,
    input  wire D_LL_bit,
    output reg  E_is_LL_W,
    output reg  E_is_SC_W,
    output reg  E_mem_write_cond,
    output reg  E_LL_bit,

    input  wire [`MEM_BAR_WIDTH-1:0] D_mem_barrier,
    output reg  [`MEM_BAR_WIDTH-1:0] E_mem_barrier
);

assign E_ready = ~E_valid | (E_done & M_ready);
assign E_to_M_valid = E_valid & E_done;

always @(posedge clk ) begin
    if (reset) begin
        E_valid <= 0;
        E_PC <= `init_pc;
        E_PCwith4 <= `init_pc + 4;
        E_PCwith8 <= `init_pc + 8;     
        E_aluSrcA <= 0;
        E_aluSrcB <= 0;
        E_aluOp <= 0;
        E_shamt <= 0;
        E_mult <= 0;
        E_div <= 0;
        E_mult_div_signed <= 0;
        E_memWrite <= 0;
        E_memReadOrWrite <= 0;
        E_memSigned <= 0;
        E_memDataType <= 0;
        E_regWrite <= 0;
        E_regWriteAddr <= 0;
        E_regWriteDataSrc <= 0;
        E_rjVal <= 0;
        E_rdkVal <= 0;
        E_rj <= 0;
        E_rdk <= 0;
        E_extended <= 0;
        E_INE <= 0;
        E_BRK <= 0;
        E_SYSCALL <= 0;
        E_ADEF <= 0;
        E_INT <= 0;
        E_TLBR_Instr <= 0;
        E_IPE <= 0;
        E_PPI_Instr <= 0;
        E_PIF <= 0;
        E_csrWrite <= 0;
        E_csrWriteAddr <= 0;
        E_csrMaskVal <= 0;
        E_csrMask <= 0;
        E_csrNum_TID <= 0;
        E_cnt_result <= 0;
        E_errorReturn <= 0;
        E_idle <= 0;
        E_refetch <= 0;
        E_GPR_new <= 0;
        E_TLB_operation <= 0;
        E_instr <= 0;
        E_csrReadData <= 0;
        E_highCnt <= 0;
        E_lowCnt <= 0;
        E_cache_operation <= 0;
        E_cache_target <= 0;
        E_is_LL_W <= 0; 
        E_is_SC_W <= 0;
        E_mem_write_cond <= 0;
        E_LL_bit <= 0;
        E_mem_barrier <= 0;
    end
    else if(flush) begin
        E_valid <= 0;
    end
    else begin
        if (E_ready) begin
            E_valid <= D_to_E_valid;
        end
        if (D_to_E_valid & E_ready) begin
            // 信号流水
            E_PC <= D_PC;
            E_PCwith4 <= D_PC + 4;
            E_PCwith8 <= D_PC + 8;
            
            E_aluSrcA <= D_aluSrcA;
            E_aluSrcB <= D_aluSrcB;
            E_aluOp <= D_aluOp;
            E_shamt <= D_shamt;
            E_mult <= D_mult;
            E_div <= D_div;
            E_mult_div_signed <= D_mult_div_signed;

            E_memWrite <= D_memWrite;
            E_memReadOrWrite <= D_memReadOrWrite;
            E_memSigned <= D_memSigned;
            E_memDataType <= D_memDataType;

            E_regWrite <= D_regWrite;
            E_regWriteAddr <= D_regWriteAddr;     
            E_regWriteDataSrc <= D_regWriteDataSrc;

            E_rjVal <= D_rjVal;
            E_rdkVal <= D_rdkVal;
            E_rj <= D_rj;
            E_rdk <= D_rdk;

            E_extended <= D_extended;

            E_INE <= D_INE;
            E_BRK <= D_BRK;
            E_SYSCALL <= D_SYSCALL;
            E_ADEF <= D_ADEF;
            E_INT <= D_INT;
            E_TLBR_Instr <= D_TLBR_Instr;
            E_IPE <= D_IPE;
            E_PPI_Instr <= D_PPI_Instr;
            E_PIF <= D_PIF;

            E_csrWrite <= D_csrWrite;
            E_csrWriteAddr <= D_csrWriteAddr;
            E_csrMaskVal <= D_csrMaskVal;
            E_csrMask <= D_csrMask;
            E_csrNum_TID <= D_csrNum_TID;

            E_cnt_result <= D_cnt_result;
            E_highCnt <= D_highCnt;
            E_lowCnt <= D_lowCnt;
            
            E_errorReturn <= D_errorReturn;
            E_idle <= D_idle;
            E_refetch <= D_refetch;
            
            E_GPR_new <= D_GPR_new;

            E_TLB_operation <= D_TLB_operation;

            E_instr <= D_instr;

            E_csrReadData <= D_csrReadData;

            E_cache_operation <= D_cache_operation;
            E_cache_target <= D_cache_target;

            E_is_LL_W <= D_is_LL_W;
            E_is_SC_W <= D_is_SC_W;
            E_mem_write_cond <= D_mem_write_cond;
            E_LL_bit <= D_LL_bit;

            E_mem_barrier <= D_mem_barrier;
        end
    end
end

endmodule //D2Ereg