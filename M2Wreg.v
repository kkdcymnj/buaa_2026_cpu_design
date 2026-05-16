`include "constant.v"

module M2Wreg (
    input  wire clk,
    input  wire reset,
    
    input  wire flush,

    input  wire [31:0]  M_PC,
    output reg  [31:0]  W_PC,
    output reg  [31:0]  W_PCwith4,
    output reg  [31:0]  W_PCwith8,

    input  wire [2:0]   M_GPR_new,
    output reg  [2:0]   W_GPR_new,

    input  wire [31:0]  M_alu_result,
    input  wire [63:0]  M_mult_result,
    input  wire [31:0]  M_div_result,
    input  wire [31:0]  M_mod_result,
    output reg  [31:0]  W_alu_result,
    output reg  [63:0]  W_mult_result,
    output reg  [31:0]  W_div_result,
    output reg  [31:0]  W_mod_result,

    input  wire [31:0]  M_mem_result,
    output reg  [31:0]  W_mem_result, 

    input  wire M_regWrite,
    input  wire [4:0]     M_regWriteAddr,
    input  wire [`data_src_select_width-1:0]    M_regWriteDataSrc,
    output reg  W_regWrite,
    output reg  [4:0]     W_regWriteAddr,
    output reg  [`data_src_select_width-1:0]    W_regWriteDataSrc,
    
    input  wire M_memWrite,
    input  wire M_memReadOrWrite,
    input  wire [31:0] M_memAddr,
    output reg  W_memWrite,
    output reg  W_memReadOrWrite,
    output reg  [31:0] W_memAddr,

    input  wire M_csrWrite,
    input  wire [`csr_addr_width-1:0] M_csrWriteAddr,
    input  wire [31:0] M_csrMaskVal,
    input  wire M_csrNum_TID,
    output reg  W_csrWrite,
    output reg  [`csr_addr_width-1:0] W_csrWriteAddr,
    output reg  [31:0] W_csrMaskVal,
    output reg  W_csrNum_TID,

    input  wire [31:0] M_cnt_result,
    output reg  [31:0] W_cnt_result,
    input  wire [31:0]  M_highCnt,
    input  wire [31:0] M_lowCnt,
    output reg  [31:0] W_highCnt,
    output reg  [31:0] W_lowCnt,

    input  wire M_INE,
    input  wire M_BRK,
    input  wire M_SYSCALL,
    input  wire M_ADEF,
    input  wire M_INT,
    input  wire M_ALE,
    input  wire M_TLBR_Data,
    input  wire M_TLBR_Instr,
    input  wire M_IPE,
    input  wire M_PPI_Data,
    input  wire M_PPI_Instr,
    input  wire M_PME,
    input  wire M_PIF,
    input  wire M_PIS,
    input  wire M_PIL,
    input  wire M_ADEM,
    output reg  W_INE,
    output reg  W_BRK,
    output reg  W_SYSCALL,
    output reg  W_ADEF,
    output reg  W_INT,
    output reg  W_ALE,
    output reg  W_TLBR_Data,
    output reg  W_TLBR_Instr,
    output reg  W_IPE,  
    output reg  W_PPI_Data,
    output reg  W_PPI_Instr,
    output reg  W_PME,
    output reg  W_PIF,
    output reg  W_PIS,
    output reg  W_PIL,
    output reg  W_ADEM,

    input  wire [31:0] M_rdkVal,
    input  wire [31:0] M_rjVal,
    output reg  [31:0] W_rdkVal,
    output reg  [31:0] W_rjVal,

    input  wire M_errorReturn,
    input  wire M_idle,
    input  wire M_refetch,
    output reg W_errorReturn,
    output reg W_idle,
    output reg W_refetch,

    input  wire [`TLB_OP_WIDTH-1:0] M_TLB_operation,
    output reg [`TLB_OP_WIDTH-1:0] W_TLB_operation,

    input  wire [31:0] M_instr,
    output reg  [31:0] W_instr,

    input  wire [31:0] M_paddr,
    output reg  [31:0] W_paddr,

    input wire M_memSigned,
    input wire [`data_type_sel_width-1:0] M_memDataType,
    output reg W_memSigned,
    output reg [`data_type_sel_width-1:0] W_memDataType,

    input  wire [31:0] M_csrReadData,
    output reg [31:0] W_csrReadData,  

    // 握手信号
    input  wire W_done,
    input  wire M_to_W_valid,
    output wire W_ready,
    output reg  W_valid,

    input  wire M_is_LL_W,
    input  wire M_is_SC_W,
    input  wire M_mem_write_cond,
    input  wire M_LL_bit,
    output reg  W_is_LL_W,
    output reg  W_is_SC_W,
    output reg  W_mem_write_cond,
    output reg  W_LL_bit
);

assign W_ready = ~W_valid | (W_done);

always @(posedge clk ) begin
    if (reset) begin
        W_valid <= 0;
        W_PC <= `init_pc;
        W_PCwith4 <= `init_pc + 4;
        W_PCwith8 <= `init_pc + 8;
        W_alu_result <= 0;
        W_mult_result <= 0;
        W_div_result <= 0;  
        W_mod_result <= 0;
        W_regWrite <= 0;
        W_regWriteAddr <= 0;
        W_regWriteDataSrc <= 0; 
        W_csrWrite <= 0;
        W_csrWriteAddr <= 0;
        W_csrMaskVal <= 0;
        W_csrNum_TID <= 0;
        W_cnt_result <= 0;
        W_INE <= 0;
        W_BRK <= 0;
        W_SYSCALL <= 0;
        W_ADEF <= 0;
        W_INT <= 0;
        W_ADEM <= 0;
        W_ALE <= 0;
        W_TLBR_Data <= 0;
        W_TLBR_Instr <= 0;
        W_IPE <= 0;
        W_PPI_Data <= 0;
        W_PPI_Instr <= 0;
        W_PME <= 0;
        W_PIF <= 0;
        W_PIS <= 0; 
        W_PIL <= 0;
        W_memAddr <= 0;
        W_rdkVal <= 0;
        W_rjVal <= 0;
        W_errorReturn <= 0;
        W_GPR_new <= 0;
        W_TLB_operation <= 0;
        W_idle <= 0;
        W_refetch <= 0;
        W_instr <= 0;
        W_memWrite <= 0;
        W_memReadOrWrite <= 0;
        W_memAddr <= 0;
        W_paddr <= 0;
        W_memSigned <= 0;
        W_memDataType <= 0;
        W_csrReadData <= 0;
        W_highCnt <= 0;
        W_lowCnt <= 0;
        W_is_LL_W <= 0; 
        W_is_SC_W <= 0;
        W_mem_write_cond <= 0;
        W_LL_bit <= 0;
    end
    else if(flush) begin
        W_valid <= 0;
    end
    else begin
        if (W_ready) begin
            W_valid <= M_to_W_valid;
        end

        if (W_ready & M_to_W_valid) begin
            W_PC <= M_PC;
            W_PCwith4 <= M_PC + 4;
            W_PCwith8 <= M_PC + 8;
            W_alu_result <= M_alu_result;
            W_mult_result <= M_mult_result;
            W_div_result <= M_div_result;
            W_mod_result <= M_mod_result;
            W_regWrite <= M_regWrite;
            W_regWriteAddr <= M_regWriteAddr;
            W_regWriteDataSrc <= M_regWriteDataSrc;
            W_mem_result <= M_mem_result;
            
            W_csrWrite <= M_csrWrite;
            W_csrWriteAddr <= M_csrWriteAddr;
            W_csrMaskVal <= M_csrMaskVal; 
            W_csrNum_TID <= M_csrNum_TID;

            W_cnt_result <= M_cnt_result;
            W_highCnt <= M_highCnt;
            W_lowCnt <= M_lowCnt;

            W_INE <= M_INE;
            W_BRK <= M_BRK;
            W_SYSCALL <= M_SYSCALL;
            W_ADEF <= M_ADEF;
            W_INT <= M_INT;
            W_ALE <= M_ALE;
            W_TLBR_Data <= M_TLBR_Data;
            W_TLBR_Instr <= M_TLBR_Instr;
            W_IPE <= M_IPE;
            W_PPI_Data <= M_PPI_Data;
            W_PPI_Instr <= M_PPI_Instr;
            W_PME <= M_PME;
            W_PIF <= M_PIF;
            W_PIS <= M_PIS;
            W_PIL <= M_PIL;
            W_ADEM <= M_ADEM;

            W_memAddr <= M_memAddr;

            W_rdkVal <= M_rdkVal;
            W_rjVal <= M_rjVal;

            W_errorReturn <= M_errorReturn;
            W_idle <= M_idle;
            W_refetch <= M_refetch;

            W_TLB_operation <= M_TLB_operation;

            W_GPR_new <= M_GPR_new;

            W_instr <= M_instr;

            W_memWrite <= M_memWrite;
            W_memReadOrWrite <= M_memReadOrWrite;

            W_memDataType <= M_memDataType;
            W_memSigned <= M_memSigned;

            W_paddr <= M_paddr;

            W_csrReadData <= M_csrReadData;

            W_is_LL_W <= M_is_LL_W;
            W_is_SC_W <= M_is_SC_W;
            W_mem_write_cond <= M_mem_write_cond;
            W_LL_bit <= M_LL_bit;
        end
    end
end

endmodule //M2Wreg
