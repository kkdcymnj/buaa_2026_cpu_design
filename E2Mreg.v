`include "constant.v"

module E2Mreg (
    input  wire clk,
    input  wire reset,
    
    input  wire flush,

    input  wire [31:0]  E_PC,
    output reg  [31:0]  M_PC,
    output reg  [31:0]  M_PCwith4,
    output reg  [31:0]  M_PCwith8,

    input  wire [2:0]   E_GPR_new,
    output reg  [2:0]   M_GPR_new,

    input  wire [31:0]  E_alu_result,
    output reg  [31:0]  M_alu_result,

    input  wire E_memWrite,
    input  wire E_memReadOrWrite,
    input  wire E_memSigned,
    input  wire [`data_type_sel_width-1:0]  E_memDataType,
    input  wire [31:0]  E_memAddr,
    output reg  M_memWrite,
    output reg  M_memReadOrWrite,
    output reg  M_memSigned,
    output reg  [`data_type_sel_width-1:0]  M_memDataType,
    output reg [31:0]   M_memAddr,

    input  wire E_regWrite,
    input  wire [4:0]                           E_regWriteAddr,
    input  wire [`data_src_select_width-1:0]    E_regWriteDataSrc,
    output reg  M_regWrite,
    output reg  [4:0]                           M_regWriteAddr,
    output reg  [`data_src_select_width-1:0]    M_regWriteDataSrc,

    input  wire [31:0]  E_rjVal,
    input  wire [31:0]  E_rdkVal,
    input  wire [4:0]   E_rj,
    input  wire [4:0]   E_rdk,
    output reg  [31:0]  M_rjVal,
    output reg  [31:0]  M_rdkVal,
    output reg  [4:0]   M_rj,
    output reg  [4:0]   M_rdk,

    /*
    {M_TLBR_Data, M_TLBR_Instr, M_IPE, M_INE, M_BRK, M_SYSCALL, M_ALE, 1'b0,
    M_ADEF, M_PPI_Data, M_PPI_Instr, M_PME, M_PIF, M_PIS, M_PIL, M_INT};
    */
    input  wire E_INE,
    input  wire E_BRK,
    input  wire E_SYSCALL,
    input  wire E_ADEF,
    input  wire E_INT,
    input  wire E_ALE,
    input  wire E_TLBR_Data,
    input  wire E_TLBR_Instr,
    input  wire E_IPE,
    input  wire E_PPI_Data,
    input  wire E_PPI_Instr,
    input  wire E_PME,
    input  wire E_PIF,
    input  wire E_PIS,
    input  wire E_PIL,
    input  wire E_ADEM,
    output reg  M_INE,
    output reg  M_BRK,
    output reg  M_SYSCALL,
    output reg  M_ADEF,
    output reg  M_INT,
    output reg  M_ALE,
    output reg  M_TLBR_Data,
    output reg  M_TLBR_Instr,
    output reg  M_IPE,
    output reg  M_PPI_Data,
    output reg  M_PPI_Instr,
    output reg  M_PME,
    output reg  M_PIF,
    output reg  M_PIS,
    output reg  M_PIL,   
    output reg  M_ADEM,
    
    input  wire E_csrWrite,
    input  wire [`csr_addr_width-1:0] E_csrWriteAddr,
    input  wire [31:0] E_csrMaskVal,
    input  wire E_csrMask,
    input  wire E_errorReturn,
    input  wire E_idle,
    input  wire E_refetch,
    input  wire E_csrNum_TID,
    output reg  M_csrWrite,
    output reg  [`csr_addr_width-1:0] M_csrWriteAddr,
    output reg  [31:0] M_csrMaskVal,
    output reg  M_csrMask, 
    output reg  M_errorReturn,
    output reg  M_idle,
    output reg  M_refetch,
    output reg  M_csrNum_TID,

    input  wire [31:0]  E_cnt_result,
    output reg  [31:0]  M_cnt_result,
    input  wire [31:0]  E_highCnt,
    input  wire [31:0]  E_lowCnt,
    output reg  [31:0]  M_highCnt,
    output reg  [31:0]  M_lowCnt,

    input  wire [`TLB_OP_WIDTH-1:0] E_TLB_operation,
    output reg [`TLB_OP_WIDTH-1:0] M_TLB_operation,

    input  wire [31:0] E_instr,
    output reg [31:0] M_instr,

    input  wire [31:0] E_paddr,
    output reg  [31:0] M_paddr,  

    input  wire [31:0] E_csrReadData,
    output reg [31:0] M_csrReadData,  

    // 握手信号
    input  wire M_done,
    input  wire W_ready,
    input  wire E_to_M_valid,
    output reg  M_valid,
    output wire M_ready,
    output wire M_to_W_valid,

    input  wire E_is_LL_W,
    input  wire E_is_SC_W,
    input  wire E_mem_write_cond,
    input  wire E_LL_bit,
    output reg  M_is_LL_W,
    output reg  M_is_SC_W,
    output reg  M_mem_write_cond,
    output reg  M_LL_bit,

    input  wire  [`CACHE_TARGET_WIDTH-1:0] E_cache_target,
    output reg   [`CACHE_TARGET_WIDTH-1:0] M_cache_target,

    input  wire [`MEM_BAR_WIDTH-1:0] E_mem_barrier,
    output reg  [`MEM_BAR_WIDTH-1:0] M_mem_barrier,

    input  wire [31:0] E_div_result,
    input  wire [31:0] E_mod_result,
    output reg  [31:0] M_div_result,
    output reg  [31:0] M_mod_result
);

assign M_ready = ~M_valid | (M_done & W_ready);
assign M_to_W_valid = M_done & M_valid;

always @(posedge clk ) begin
    if (reset) begin
        M_valid <= 0;
        M_PC <= `init_pc;
        M_PCwith4 <= `init_pc + 4;
        M_PCwith8 <= `init_pc + 8;
        M_alu_result <= 0;
        M_memWrite <= 0;
        M_memReadOrWrite <= 0;
        M_memSigned <= 0;
        M_memDataType <= 0;
        M_memAddr <= 0;
        M_regWrite <= 0;    
        M_regWriteAddr <= 0;
        M_regWriteDataSrc <= 0;
        M_rjVal <= 0;
        M_rdkVal <= 0;
        M_rj <= 0;
        M_rdk <= 0;
        M_INE <= 0;
        M_BRK <= 0;
        M_SYSCALL <= 0;
        M_ADEF <= 0;
        M_INT <= 0; 
        M_ALE <= 0;
        M_ADEM <= 0;
        M_TLBR_Data <= 0;
        M_TLBR_Instr <= 0;
        M_IPE <= 0;
        M_PPI_Data <= 0;
        M_PPI_Instr <= 0;   
        M_PME <= 0;
        M_PIF <= 0;
        M_PIS <= 0;
        M_PIL <= 0;
        M_csrWrite <= 0;
        M_csrWriteAddr <= 0;
        M_csrMaskVal <= 0;
        M_csrMask <= 0;
        M_csrNum_TID <= 0;
        M_cnt_result <= 0;
        M_errorReturn <= 0;
        M_idle <= 0;
        M_refetch <= 0;
        M_GPR_new <= 0;   
        M_TLB_operation <= 0;
        M_instr <= 0;
        M_paddr <= 0;
        M_csrReadData <= 0;
        M_highCnt <= 0;
        M_lowCnt <= 0;
        M_is_LL_W <= 0; 
        M_is_SC_W <= 0;
        M_mem_write_cond <= 0;
        M_LL_bit <= 0;
        M_cache_target <= 0;
        M_mem_barrier <= 0;
        M_div_result <= 0;
        M_mod_result <= 0;
    end
    else if (flush) begin
        M_valid <= 0;
    end
    else begin
        if (M_ready) begin
            M_valid <= E_to_M_valid;
        end

        if (E_to_M_valid & M_ready) begin
            M_PC <= E_PC;
            M_PCwith4 <= E_PC + 4;
            M_PCwith8 <= E_PC + 8;

            M_alu_result <= E_alu_result;

            M_memWrite <= E_memWrite;
            M_memSigned <= E_memSigned;
            M_memDataType <= E_memDataType;
            M_memAddr <= E_memAddr;

            M_regWrite <= E_regWrite;
            M_memReadOrWrite <= E_memReadOrWrite;
            M_regWriteAddr <= E_regWriteAddr;
            M_regWriteDataSrc <= E_regWriteDataSrc;

            M_rjVal <= E_rjVal;
            M_rdkVal <= E_rdkVal; 
            M_rj <= E_rj;
            M_rdk <= E_rdk;

            M_INE <= E_INE;
            M_BRK <= E_BRK;
            M_SYSCALL <= E_SYSCALL;
            M_ADEF <= E_ADEF;
            M_INT <= E_INT;
            M_ALE <= E_ALE;
            M_TLBR_Data <= E_TLBR_Data;
            M_TLBR_Instr <= E_TLBR_Instr;
            M_IPE <= E_IPE;
            M_PPI_Data <= E_PPI_Data;
            M_PPI_Instr <= E_PPI_Instr;
            M_PME <= E_PME;
            M_PIF <= E_PIF;
            M_PIS <= E_PIS;
            M_PIL <= E_PIL;
            M_ADEM <= E_ADEM;

            M_csrWrite <= E_csrWrite;
            M_csrWriteAddr <= E_csrWriteAddr;
            M_csrMaskVal <= E_csrMaskVal;
            M_csrMask <= E_csrMask;
            M_csrNum_TID <= E_csrNum_TID;

            M_cnt_result <= E_cnt_result;
            M_highCnt <= E_highCnt;
            M_lowCnt <= E_lowCnt;

            M_errorReturn <= E_errorReturn;
            M_idle <= E_idle;
            M_refetch <= E_refetch;

            M_TLB_operation <= E_TLB_operation;

            M_GPR_new <= E_GPR_new;

            M_instr <= E_instr;

            M_paddr <= E_paddr;

            M_csrReadData <= E_csrReadData;

            M_is_LL_W <= E_is_LL_W;
            M_is_SC_W <= E_is_SC_W;
            M_mem_write_cond <= E_mem_write_cond;
            M_LL_bit <= E_LL_bit;

            M_cache_target <= E_cache_target;

            M_mem_barrier <= E_mem_barrier;

            M_div_result <= E_div_result;
            M_mod_result <= E_mod_result;
        end
    end

end

endmodule //E2Mreg