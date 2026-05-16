`include "constant.v"

module mycpu_top (
    input  wire        aclk,
    input  wire        aresetn,
    // read requast channel
    output wire [ 3:0] arid,
    output wire [31:0] araddr,
    output wire [ 7:0] arlen,             // fixed to 8'h00
    output wire [ 2:0] arsize,
    output wire [ 1:0] arburst,           // fixed to 2'b01
    output wire [ 1:0] arlock,            // fixed to 2'b00
    output wire [ 3:0] arcache,           // fixed to 4'b0000
    output wire [ 2:0] arprot,            // fixed to 3'b000
    output wire        arvalid,
    input  wire        arready,
    // read response channel
    input  wire [ 3:0] rid,
    input  wire [31:0] rdata,
    input  wire [ 1:0] rresp,             // ignored
    input  wire        rlast,             // ignored
    input  wire        rvalid,
    output wire        rready,
    // write requast channel
    output wire [ 3:0] awid,              // fixed to 4'b0001
    output wire [31:0] awaddr,
    output wire [ 7:0] awlen,             // fixed to 8'h00
    output wire [ 2:0] awsize,
    output wire [ 1:0] awburst,           // fixed to 2'b01
    output wire [ 1:0] awlock,            // fixed to 2'b00
    output wire [ 3:0] awcache,           // fixed to 4'b0000
    output wire [ 2:0] awprot,            // fixed to 3'b000
    output wire        awvalid,
    input  wire        awready,
    // write data channel
    output wire [ 3:0] wid,               // fixed to 4'b0001
    output wire [31:0] wdata,
    output wire [ 3:0] wstrb,
    output wire        wlast,             // fixed to 1'b1
    output wire        wvalid,
    input  wire        wready,
    // write response channel
    input  wire [ 3:0] bid,               // ignored
    input  wire        bresp,             // ignored
    input  wire        bvalid,
    output wire        bready,
    // hardware interrupt
`ifdef CHIPLAB
    input  wire [ 7:0] intrpt,
`endif 
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);  

wire [$clog2(`TLB_ENTRIES)-1:0] tlb_plru_victim_entry;

wire                            ICache_mem_rd_req;
wire [                     2:0] ICache_mem_rd_type;
wire [                    31:0] ICache_mem_rd_addr;
wire                            ICache_mem_rd_rdy;
wire                            ICache_mem_ret_valid;
wire                            ICache_mem_ret_last;
wire [                    31:0] ICache_mem_ret_data;

wire                            DCache_mem_rd_req;
wire [                     2:0] DCache_mem_rd_type;
wire [                    31:0] DCache_mem_rd_addr;
wire                            DCache_mem_rd_rdy;
wire                            DCache_mem_ret_valid;
wire                            DCache_mem_ret_last;
wire [                    31:0] DCache_mem_ret_data;
wire                            DCache_mem_wr_req;
wire [                     2:0] DCache_mem_wr_type;
wire [                    31:0] DCache_mem_wr_addr;
wire [                     3:0] DCache_mem_wr_wstrb;
wire [                   127:0] DCache_mem_wr_data;
wire                            DCache_mem_wr_rdy;
wire                            DCache_mem_wr_resp;

wire clk;
// inst sram interface
wire        inst_sram_req;
wire        inst_sram_wr;
wire [ 1:0] inst_sram_size;
wire [31:0] inst_sram_addr;
wire [ 3:0] inst_sram_wstrb;
wire [31:0] inst_sram_wdata;
wire        inst_sram_addr_ok;
wire        inst_sram_data_ok;
wire [31:0] inst_sram_rdata;
// data sram interface
wire        data_sram_req;
wire        data_sram_wr;
wire [ 1:0] data_sram_size;
wire [31:0] data_sram_addr;
wire [ 3:0] data_sram_wstrb;
wire [31:0] data_sram_wdata;
wire        data_sram_addr_ok;
wire        data_sram_data_ok;
wire [31:0] data_sram_rdata;

wire reset;

wire [2:0] inst_search_op;
wire [2:0] data_search_op;
wire inst_access_type;
wire data_access_type;

wire inst_cacop_req;
wire [4:0] inst_cacop_op;
wire [31:0] inst_cacop_vaddr;

AXI_Bridge u_AXI_Bridge(
    .aclk                  (aclk                  ),
    .aresetn               (aresetn               ),
    .clk                   (clk                   ),
    .reset                 (reset                 ),

    .inst_sram_req         (ICache_mem_rd_req),
    .inst_sram_rd_type     (ICache_mem_rd_type),
    .inst_sram_addr        (ICache_mem_rd_addr),
    .inst_sram_addr_ok     (ICache_mem_rd_rdy),
    .inst_sram_data_ok     (ICache_mem_ret_valid),
    .inst_sram_rdata       (ICache_mem_ret_data),
    .inst_sram_ret_last    (ICache_mem_ret_last),

    .data_sram_rd_req     (DCache_mem_rd_req),
    .data_sram_rd_type    (DCache_mem_rd_type),
    .data_sram_rd_addr    (DCache_mem_rd_addr),
    .data_sram_rd_addr_ok (DCache_mem_rd_rdy),
    .data_sram_ret_valid  (DCache_mem_ret_valid),
    .data_sram_rdata      (DCache_mem_ret_data),
    .data_sram_ret_last   (DCache_mem_ret_last),
    .data_sram_wr_req     (DCache_mem_wr_req),
    .data_sram_wr_type    (DCache_mem_wr_type),
    .data_sram_wr_addr    (DCache_mem_wr_addr),
    .data_sram_wr_wstrb   (DCache_mem_wr_wstrb),
    .data_sram_wr_data    (DCache_mem_wr_data),
    .data_sram_wr_addr_ok (DCache_mem_wr_rdy),
    .data_sram_wr_resp    (DCache_mem_wr_resp),

    .inst_sram_access_type (inst_access_type ),
    .data_sram_access_type (data_access_type ),

    .arid                  (arid                  ),
    .araddr                (araddr                ),
    .arlen                 (arlen                 ),
    .arsize                (arsize                ),
    .arburst               (arburst               ),
    .arlock                (arlock                ),
    .arcache               (arcache               ),
    .arprot                (arprot                ),
    .arvalid               (arvalid               ),
    .arready               (arready               ),
    .rid                   (rid                   ),
    .rdata                 (rdata                 ),
    .rresp                 (rresp                 ),
    .rlast                 (rlast                 ),
    .rvalid                (rvalid                ),
    .rready                (rready                ),
    .awid                  (awid                  ),
    .awaddr                (awaddr                ),
    .awlen                 (awlen                 ),
    .awsize                (awsize                ),
    .awburst               (awburst               ),
    .awlock                (awlock                ),
    .awcache               (awcache               ),
    .awprot                (awprot                ),
    .awvalid               (awvalid               ),
    .awready               (awready               ),
    .wid                   (wid                   ),
    .wdata                 (wdata                 ),
    .wstrb                 (wstrb                 ),
    .wvalid                (wvalid                ),
    .wlast                 (wlast                 ),
    .wready                (wready                ),
    .bid                   (bid                   ),
    .bresp                 (bresp                 ),
    .bvalid                (bvalid                ),
    .bready                (bready                )
);


// 异常相关常量定义
wire [`exception_width - 1:0] Pre_exception;
wire [`exception_width - 1:0] F_exception;
wire [`exception_width - 1:0] D_exception;
wire [`exception_width - 1:0] E_exception;
wire [`exception_width - 1:0] M_exception;
wire [`exception_width - 1:0] W_exception;

// F级流水线控制信号
wire F_ready;
wire F_valid;
wire F_to_D_valid;
wire F_done;
wire F_flush;
wire Pre_to_F_valid;

// D级流水线控制信号
wire D_ready;
wire D_valid;
wire D_to_E_valid;
wire D_done;

// E级流水线控制信号
wire E_ready;
wire E_valid;
wire E_to_M_valid;
wire E_ALU_done;
wire E_done;

// M级流水线控制信号
wire M_ready;
wire M_valid;
wire M_to_W_valid;
wire M_done;

// W级流水线控制信号
wire W_ready;
wire W_valid;
wire W_done;

// F级预取地址
wire [31:0] Pre_PC;
wire [31:0] branch_PC;
wire Pre_ADEF;
wire Pre_PIF;
wire Pre_PPI_Instr;
wire Pre_TLBR_Instr;

// F级信号
wire [31:0] F_PC;
wire [31:0] F_instr;
wire F_ADEF;
wire F_PIF;
wire F_PPI_Instr;
wire F_TLBR_Instr;
// wire inst_ram_req_valid;

// D级信号
wire [31:0] D_PC;
wire [31:0] D_PCwith4;
wire [31:0] D_PCwith8;
wire [31:0] D_instr;
/*
wire [3:0]  D_T_use_rj;
wire [3:0]  D_T_use_rdk;
wire [3:0]  D_T_new;
*/
wire D_use_rj;
wire D_use_rdk;
wire D_use_CSR;
wire [2:0] D_GPR_new;
wire [`npc_select_width-1:0]    D_nextPCSel;
wire [`imm_select_width-1:0]    D_immLen;
wire D_sign_extend;
wire [`cmp_sel_width-1:0]   D_cmpOp;
wire [`alu_src_select_width-1:0]    D_aluSrcA;
wire [`alu_src_select_width-1:0]    D_aluSrcB;
wire [`alu_op_width-1:0]    D_aluOp;
wire D_mult;
wire D_div;
wire D_mult_div_signed;
wire D_memWrite;
wire D_memReadOrWrite;
wire D_memSigned;
wire [`data_type_sel_width-1:0] D_memDataType;
wire D_regWrite;
wire [`reg_select_width-1:0]    D_regWriteAddrSel;   
wire [4:0]  D_regWriteAddr;
wire [`data_src_select_width-1:0]   D_regWriteDataSrc;
wire [4:0]  D_rj;
wire [4:0]  D_rk;
wire [4:0]  D_rd;
wire [4:0]  D_rdk;
wire [4:0]  D_shamt;
wire [31:0] D_rjVal;
wire [31:0] D_rdkVal;
wire [31:0] D_rjVal_temp;
wire [31:0] D_rdkVal_temp;
wire D_cmp_flag;
wire [11:0]  D_imm_12;
wire [13:0]  D_imm_14;
wire [15:0]  D_imm_16;
wire [19:0]  D_imm_20;
wire [20:0]  D_imm_21;
wire [25:0]  D_imm_26;
wire [31:0]  D_extended;
wire D_stall;
wire D_branch_jump_stall;
// wire D_csrStall;
wire D_useRd;
wire D_branch;
wire D_branch_instr;
wire D_branch_valid;
wire [`TLB_OP_WIDTH-1:0] D_TLB_operation;
wire D_refetch;
wire D_idle;
wire [ `CACHE_TARGET_WIDTH-1:0] D_cache_target;
wire [     `CACHE_OP_WIDTH-1:0] D_cache_operation;
/*wire D_LL_bit;*/
wire D_is_LL_W;
wire D_is_SC_W;
wire [`MEM_BAR_WIDTH-1:0] D_mem_barrier;
// D级异常相关信号
wire D_INE;
wire D_BRK;
wire D_SYSCALL;
wire D_INT;
wire D_ADEF;
wire D_TLBR_Instr;
wire D_IPE;
wire D_PPI_Instr;
wire D_PIF;

// D级CSRF相关信号
wire D_csrWrite;
wire [13:0] D_csrWriteAddr;
wire D_csrMask;
wire [31:0] D_csrReadData;
wire [31:0] D_csrMaskVal;
wire D_errorReturn;
wire D_notExistInstr;
wire D_isBreak;
wire D_isSyscall;
wire D_readHighCnt;
wire [31:0] D_highCnt;
wire [31:0] D_lowCnt;
wire [31:0] D_cnt_result;

// E级信号
wire [31:0] E_forward_data;
wire [31:0] E_PC;
wire [31:0] E_PCwith4;
wire [31:0] E_PCwith8;
//wire [3:0]  E_T_new;
wire [2:0]  E_GPR_new;
wire [`alu_src_select_width-1:0] E_aluSrcA;
wire [`alu_src_select_width-1:0] E_aluSrcB;
wire [`alu_op_width-1:0]         E_aluOp;
wire [4:0]   E_shamt;
wire E_mult;
wire E_div;
wire E_mult_div_signed;
wire E_memWrite;
wire E_memReadOrWrite;
wire E_memSigned;
wire [`data_type_sel_width-1:0] E_memDataType;
wire E_regWrite;
//wire [`reg_select_width-1:0]    E_regWriteAddrSel;
wire [4:0]   E_regWriteAddr;
wire [`data_src_select_width-1:0]   E_regWriteDataSrc;
wire [4:0]   E_rj;
wire [4:0]   E_rk;
wire [4:0]   E_rdk;
wire [31:0]  E_rjVal;
wire [31:0]  E_rdkVal;
//wire [31:0]  E_rjVal_temp;
//wire [31:0]  E_rdkVal_temp;
wire [31:0]  E_extended;
wire [31:0]  E_alu_result;
wire [63:0]  E_mult_result;
/*
wire [31:0]  E_div_quotient;
wire [31:0]  E_div_remainder;
wire E_mult_start;
wire E_mult_busy;
wire E_div_start;
wire E_div_complete;
wire E_div_busy;
*/
wire [31:0]  E_operand1;
wire [31:0]  E_operand2;
wire [31:0]  E_memAddr;
wire [`TLB_OP_WIDTH-1:0] E_TLB_operation;
wire E_refetch;
wire E_idle;
wire [31:0] E_instr;
wire [31:0] E_highCnt;
wire [31:0] E_lowCnt;
wire [ `CACHE_TARGET_WIDTH-1:0] E_cache_target;
wire [     `CACHE_OP_WIDTH-1:0] E_cache_operation;
wire E_is_LL_W;
wire E_is_SC_W;
wire E_LL_bit;
wire [`MEM_BAR_WIDTH-1:0] E_mem_barrier;
wire [31:0] E_div_result;
wire [31:0] E_mod_result;

// E级异常相关信号
wire E_INE;
wire E_BRK;
wire E_SYSCALL;
wire E_ADEF;
wire E_INT;
wire E_ALE;
wire E_ADEM;
wire E_TLBR_Data;
wire E_TLBR_Instr;
wire E_IPE;
wire E_PPI_Data;
wire E_PPI_Instr;
wire E_PME;
wire E_PIF;
wire E_PIS;
wire E_PIL;
//wire E_PPI;

// E级CSRF相关信号
wire E_csrWrite;
wire E_csrMask;
wire [31:0] E_csrReadData;
wire [13:0] E_csrWriteAddr;
wire [31:0] E_csrMaskVal;
wire E_errorReturn;
wire [31:0] E_cnt_result;

// M级信号
wire [31:0] M_forward_data;
wire [31:0] M_PC;
wire [31:0] M_PCwith4;  
wire [31:0] M_PCwith8;
//wire [3:0]  M_T_new;
wire [2:0]  M_GPR_new;
wire [31:0] M_alu_result;
wire [63:0] M_mult_result;
wire [31:0] M_div_result;
wire [31:0] M_mod_result;
wire M_memWrite;
wire M_memReadOrWrite;
wire M_memSigned;
wire [`data_type_sel_width-1:0] M_memDataType;
wire M_regWrite;
wire [4:0]  M_regWriteAddr;
wire [`data_src_select_width-1:0] M_regWriteDataSrc;
wire [4:0]  M_rj;
wire [4:0]  M_rk;
wire [4:0]  M_rdk;
wire [31:0] M_rjVal;
wire [31:0] M_rdkVal;
//wire [31:0] M_rjVal_temp;
//wire [31:0] M_rdkVal_temp;
wire [31:0] M_mem_result;
wire [31:0] M_regWriteData;
wire [31:0] M_memAddr;
wire [`TLB_OP_WIDTH-1:0] M_TLB_operation;
wire M_refetch;
wire M_idle;
wire [31:0] M_instr;
wire [31:0] M_paddr;
wire [31:0] M_highCnt;
wire [31:0] M_lowCnt;
// wire [ `CACHE_TARGET_WIDTH-1:0] M_cache_target;
// wire [     `CACHE_OP_WIDTH-1:0] M_cache_operation;
wire M_is_LL_W;
wire M_is_SC_W;
wire M_LL_bit;
wire [ `CACHE_TARGET_WIDTH-1:0] M_cache_target;
wire [`MEM_BAR_WIDTH-1:0] M_mem_barrier;
wire div_complete;
wire div_busy;
wire [4:0] div_dest;

// M级异常相关信号
wire M_INE;
wire M_BRK;
wire M_SYSCALL;
wire M_ADEF;
wire M_INT;
wire M_ALE;
wire M_ADEM;
wire M_TLBR_Data;
wire M_TLBR_Instr;
wire M_IPE;
wire M_PPI_Data;
wire M_PPI_Instr;
wire M_PME;
wire M_PIF;
wire M_PIS;
wire M_PIL;

// M级CSRF相关信号
wire M_csrWrite;
wire M_csrMask;
wire [31:0] M_csrReadData;
wire [13:0] M_csrWriteAddr;
wire [31:0] M_csrMaskVal;
wire M_errorReturn;
wire [31:0] M_cnt_result;

// W级信号
wire [31:0] W_PC;
wire [31:0] W_PCwith4;
wire [31:0] W_PCwith8;
//wire [3:0]  W_T_new;
wire [2:0]  W_GPR_new;
wire [31:0] W_alu_result;
wire [63:0] W_mult_result;
wire [31:0] W_div_result;
wire [31:0] W_mod_result;
wire W_regWrite;
wire [4:0]  W_regWriteAddr;
wire [`data_src_select_width-1:0] W_regWriteDataSrc;
wire [31:0] W_regWriteData;
wire [31:0] W_mem_result;
wire [31:0] W_memAddr;
wire W_memSigned;
wire [`data_type_sel_width-1:0] W_memDataType;
wire [31:0] W_rdkVal;
wire [31:0] W_rjVal;
wire [`TLB_OP_WIDTH-1:0] W_TLB_operation;
wire W_refetch;
wire W_idle;
wire [31:0] W_instr;
wire W_memWrite;
wire W_memReadOrWrite;
wire [31:0] W_paddr;
wire [31:0] W_highCnt;
wire [31:0] W_lowCnt;
wire W_LL_bit;
wire W_is_LL_W;
wire W_is_SC_W;
wire [`MEM_BAR_WIDTH-1:0] W_mem_barrier;

// W级CSRF相关信号
wire W_csrWrite;
wire [13:0] W_csrWriteAddr;
wire [31:0] W_csrMaskVal;
wire [31:0] W_csrWriteData;
wire [31:0] W_csrReadData;
wire W_errorReturn;
wire [31:0] W_cnt_result;

// W级异常相关信号
wire W_INE;
wire W_BRK;
wire W_SYSCALL;
wire W_ADEF;
wire W_INT;
wire W_ALE;
wire W_ADEM;
wire W_TLBR_Data;
wire W_TLBR_Instr;
wire W_IPE;
wire W_PPI_Data;
wire W_PPI_Instr;
wire W_PME;
wire W_PIF;
wire W_PIS;
wire W_PIL;

// 异常/中断处理相关信号
wire W_request;
wire [31:0] W_entry;
wire [31:0] W_returnAddr;
wire W_interrupt;

// CSR相关信号
wire W_csr_da;
wire W_csr_pg;
wire [9:0] W_csr_asid;
wire [1:0] W_csr_plv;
wire W_csr_datf;
wire W_csr_datm;

// DMW配置信号
wire [1:0] W_dmw0_plv;
wire [2:0] W_dmw0_pseg;
wire [2:0] W_dmw0_vseg;
wire [2:0] W_dmw0_mat;
wire [1:0] W_dmw1_plv;
wire [2:0] W_dmw1_pseg;
wire [2:0] W_dmw1_vseg;
wire [2:0] W_dmw1_mat;

// TLBR相关信号
wire [$clog2(`TLB_ENTRIES)-1:0] W_TLB_rw_index;
wire [`TLBEHI_WIDTH-1:0] W_TLB_sw_hi;
wire [`TLBELO_WIDTH-1:0] W_TLB_w_lo0;
wire [`TLBELO_WIDTH-1:0] W_TLB_w_lo1;
wire [$clog2(`TLB_ENTRIES)-1:0] W_TLB_f_index;
wire W_TLB_s_hit;
wire [$clog2(`TLB_ENTRIES)-1:0] W_TLB_s_index;
wire [`TLBEHI_WIDTH-1:0] W_TLB_r_hi;
wire [`TLBELO_WIDTH-1:0] W_TLB_r_lo0;
wire [`TLBELO_WIDTH-1:0] W_TLB_r_lo1;

// flush信号
wire flush;
wire refetch;
wire idle;

// 分支预测信号
wire D_operate_enable;
wire D_ras_push_call;
wire D_ras_pop_return;
wire [31:0]  D_operate_pc;
wire [$clog2(`BTBNUM)-1:0]  D_operate_btb_index;
wire D_add_entry;
wire D_delete_entry;
wire [31:0]  D_right_target;
wire D_target_error;
wire D_predict_error;
wire D_predict_correct;
wire D_right_orien;

wire [31:0]  F_btb_pc;
wire F_btb_taken;
wire F_btb_enable;
wire [$clog2(`BTBNUM)-1:0]   F_btb_index;
wire [31:0]  D_btb_pc;
wire D_btb_taken;
wire D_btb_enable;
wire [$clog2(`BTBNUM)-1:0]   D_btb_index;

wire D_btb_flush;
wire [31:0] D_btb_flush_target;

// =====F级===== //
//TODO: 修正F级信号以接入icache
reg         inst_sram_data_ok_valid;
reg         inst_sram_temp_ok;
reg  [31:0] inst_temp;
reg         inst_fetch;
wire [2:0] inst_access_size;
wire [4:0] inst_op;

assign inst_access_size  = 3'b010;

assign inst_op = 1; //read only

assign Pre_ADEF = (|Pre_PC[1:0]) /*| 
        Pre_PC[31] &
        ((W_csr_da & ~W_csr_pg & W_csr_plv==3) | 
        (~W_csr_da & W_csr_pg & W_csr_plv>W_dmw0_plv))*/;   //取指令异常

assign F_flush = 
    /*D_branch | */
    (W_errorReturn & W_valid) | 
    (W_request) |
    idle | refetch;

assign inst_sram_req = 
        inst_fetch &
        ~reset & 
        ~(F_flush | D_btb_flush) & ~|Pre_exception &
        (~F_valid & inst_sram_data_ok_valid | (F_done & D_ready));

assign inst_sram_wr = 1'b0;
assign inst_sram_size = 2'b10;
assign inst_sram_wstrb = 4'b0000;
// assign inst_sram_addr = Pre_PC;
assign inst_sram_wdata = 32'h0;

always @(posedge clk) begin
    if (reset) begin
        inst_fetch <= 1;
    end
    else if(W_interrupt) begin
        inst_fetch <= 1;
    end
    else if(idle) begin
        inst_fetch <= 0;
    end 
end

always @(posedge clk) begin   // 取出来的数据能不能用
    if (reset) begin
        inst_sram_data_ok_valid <= 1'b1;
    end else if ((F_flush | D_btb_flush)  & F_valid & ~F_done) begin
        inst_sram_data_ok_valid <= 1'b0;
    end else if (inst_sram_data_ok) begin
        inst_sram_data_ok_valid <= 1'b1;
    end
end

always @(posedge clk) begin
    if (reset) begin
        inst_sram_temp_ok <= 1'b0;
        inst_temp <= `init_pc;
    end else if (F_flush | D_btb_flush) begin
        inst_sram_temp_ok <= 1'b0;
    end else if (inst_sram_data_ok_valid & inst_sram_data_ok & ~D_ready) begin
        inst_sram_temp_ok <= 1'b1;
        inst_temp         <= inst_sram_rdata;   //D级还没有准备好，取出的指令要暂存
    end else if (D_ready) begin
        inst_sram_temp_ok <= 1'b0;
    end
end

/*
reg [ 2:0] br_target_inst_req_state;
reg [31:0] br_target_inst_req_buffer;
localparam br_target_inst_req_empty = 3'b001;
localparam br_target_inst_req_wait_slot = 3'b010;
localparam br_target_inst_req_wait_br_target = 3'b100;
always @(posedge clk) begin
    if (reset) begin
        br_target_inst_req_state <= br_target_inst_req_empty;
    end
    else case (br_target_inst_req_state) 
        br_target_inst_req_empty: begin
            if (F_flush) begin  // flush_sign：都是普通的flush信号
                br_target_inst_req_state <= br_target_inst_req_empty; 
            end
            else if(D_btb_flush && !F_valid && !inst_sram_addr_ok) begin
                br_target_inst_req_state  <= br_target_inst_req_wait_slot;
                br_target_inst_req_buffer <= D_btb_flush_target;
            end
            else if(D_btb_flush && !inst_sram_addr_ok && F_valid || 
                D_btb_flush && inst_sram_addr_ok && !F_valid) begin
                br_target_inst_req_state  <= br_target_inst_req_wait_br_target;
                br_target_inst_req_buffer <= D_btb_flush_target;
            end
        end
        br_target_inst_req_wait_slot: begin
            if(F_flush) begin
                br_target_inst_req_state <= br_target_inst_req_empty;
            end
            else if(Pre_to_F_valid) begin
                br_target_inst_req_state <= br_target_inst_req_wait_br_target;
            end
        end
        br_target_inst_req_wait_br_target: begin
            if(Pre_to_F_valid || F_flush) begin
                br_target_inst_req_state <= br_target_inst_req_empty;
            end
        end
        default: begin
            br_target_inst_req_state <= br_target_inst_req_empty;
        end
    endcase
end
*/

// TODO: 添加FetchBuffer
reg btb_lock_en;
reg [37:0] btb_info_buffer;
wire [31:0] btb_pc_temp;
wire [$clog2(`BTBNUM)-1:0] btb_index_temp;
wire btb_taken_temp;
wire btb_enable_temp;
wire use_btb_target;
always @(posedge clk ) begin
    if (reset | F_flush | inst_fetch) begin
        btb_lock_en <= 0;
    end
    else if(F_btb_enable && ~Pre_to_F_valid) begin
        btb_lock_en <= 1;
        btb_info_buffer <= {F_btb_taken, F_btb_index, F_btb_pc};
    end
end
assign btb_pc_temp = {32{btb_lock_en}} & btb_info_buffer[31:0] | F_btb_pc;
assign btb_index_temp = {5{btb_lock_en}} & btb_info_buffer[36:32] | F_btb_index;
assign btb_taken_temp = btb_lock_en & btb_info_buffer[37] | F_btb_taken;
assign btb_enable_temp = btb_lock_en | F_btb_enable;
assign use_btb_target = 
    F_btb_taken & F_btb_enable | btb_lock_en & btb_info_buffer[37];

assign F_instr = inst_sram_temp_ok ? inst_temp : inst_sram_rdata;

assign F_done = (inst_sram_data_ok_valid & inst_sram_data_ok) | 
                inst_sram_temp_ok | (|F_exception);

assign Pre_exception = 
    {1'b0, Pre_TLBR_Instr, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
    Pre_ADEF, 1'b0, Pre_PPI_Instr, 1'b0, Pre_PIF, 1'b0, 1'b0, 1'b0};

assign Pre_to_F_valid = inst_sram_req  & inst_sram_addr_ok | |Pre_exception;

assign F_exception = 
    {1'b0, F_TLBR_Instr, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
    F_ADEF, 1'b0, F_PPI_Instr, 1'b0, F_PIF, 1'b0, 1'b0, 1'b0};


Pre2Freg u_Pre2Freg(
    .clk            (clk),
    .reset          (reset),
    .request        (W_request),
    .errorReturn    (W_errorReturn & W_valid),    
    .entry          (W_entry),
    .returnAddr     (W_returnAddr),
    .D_branch       (D_branch),
    .refetch        (refetch),
    .idle           (idle),
    .W_PC           (W_PC),
    .F_done         (F_done),
    .D_ready        (D_ready),
    .Pre_to_F_valid (Pre_to_F_valid),
    .F_valid        (F_valid),
    .F_ready        (F_ready),
    .F_to_D_valid   (F_to_D_valid),
    .Pre_PC         (Pre_PC),
    .Pre_ADEF       (Pre_ADEF),
    .Pre_TLBR_Instr (Pre_TLBR_Instr),
    .Pre_PPI_Instr  (Pre_PPI_Instr),
    .Pre_PIF        (Pre_PIF),
    .branch_PC      (branch_PC),
    .F_PC           (F_PC),
    .F_ADEF         (F_ADEF),
    .F_TLBR_Instr   (F_TLBR_Instr),
    .F_PPI_Instr    (F_PPI_Instr),
    .F_PIF          (F_PIF),
    .btb_flush      (D_btb_flush),
    .btb_flush_target (D_btb_flush_target)
);

F_nextPC f_nextPC(
    .F_PC      (F_PC),
    .D_PC      (D_PC),
    .D_valid   (D_valid),
    .D_done    (D_done),
    .D_stall   (D_stall),
    .nextPCSel (D_nextPCSel),
    .cmpFlag   (D_cmp_flag),
    .offsetSrc (D_immLen),
    .offset26  (D_imm_26),
    .offset21  (D_imm_21),
    .offset16  (D_imm_16),
    .rj_value  (D_rjVal),

    .nextPC    (Pre_PC),
    .branch_PC (branch_PC),

    .btb_flush_target  (D_btb_flush_target),
    .btb_flush         (D_btb_flush),
    .use_btb_target     (use_btb_target),
    .btb_pc_temp        (btb_pc_temp),

    .W_PC           (W_PC),
    .entry          (W_entry),
    .returnAddr     (W_returnAddr),
    .br_target_buffer  (br_target_inst_req_buffer),
    .request        (W_request),
    .errorReturn    (W_errorReturn & W_valid),
    .idle           (idle),
    .refetch        (refetch),
    //.wait_br_target    (br_target_inst_req_state == br_target_inst_req_wait_br_target),
    .F_valid        (F_valid)
);


// =====D级===== //
assign D_INE = D_notExistInstr;
assign D_BRK = D_isBreak;
assign D_SYSCALL = D_isSyscall;  
assign D_exception = 
    {1'b0, D_TLBR_Instr, D_IPE, D_INE, D_BRK, D_SYSCALL, 1'b0, 1'b0,
    D_ADEF, 1'b0, D_PPI_Instr, 1'b0, D_PIF, 1'b0, 1'b0, D_INT};

/*
StableCounter u_StableCounter(
    .clk     (clk),
    .reset   (reset),
    .highCnt (D_highCnt),
    .lowCnt  (D_lowCnt)
);
*/

F2Dreg u_F2Dreg(
    .clk          (clk),
    .reset        (reset),
    .flush        (flush),
    //.cancel       (D_branch),
    .F_PC         (F_PC),
    .F_instr      (F_instr),
    .D_PC         (D_PC),
    .D_PCwith4    (D_PCwith4),
    .D_PCwith8    (D_PCwith8),
    .D_instr      (D_instr),
    .F_ADEF       (F_ADEF),
    .F_TLBR_Instr (F_TLBR_Instr),
    .F_PPI_Instr  (F_PPI_Instr),
    .F_PIF        (F_PIF),
    .D_ADEF       (D_ADEF),
    .D_TLBR_Instr (D_TLBR_Instr),
    .D_PPI_Instr  (D_PPI_Instr),
    .D_PIF        (D_PIF),
    .D_done       (D_done),
    .E_ready      (E_ready),
    .F_to_D_valid (F_to_D_valid),
    .D_valid      (D_valid),
    .D_ready      (D_ready),
    .D_to_E_valid (D_to_E_valid),
    .F_btb_pc       (btb_pc_temp),
    .F_btb_taken    (btb_taken_temp),
    .F_btb_enable   (btb_enable_temp),
    .F_btb_index    (btb_index_temp),
    .D_btb_pc       (D_btb_pc),
    .D_btb_taken    (D_btb_taken),
    .D_btb_enable   (D_btb_enable),
    .D_btb_index    (D_btb_index),
    .D_btb_flush     (D_btb_flush)
);

D_GRF d_GRF(
    .clk         (clk),
    .reset       (reset),
    .writeEnable (|debug_wb_rf_we),
    .A1          (D_rj),
    .A2          (D_rdk),            // rd或rk的值，根据指令而异，在control模块就可得出
    .A3          (W_regWriteAddr),
    .writeData   (W_regWriteData),
    .currentPC   (W_PC),
    .RD1         (D_rjVal_temp),
    .RD2         (D_rdkVal_temp)
);

D_control d_control(
    .instr           (D_instr),
    .plv             (W_csr_plv),
    .use_rj          (D_use_rj),
    .use_rdk         (D_use_rdk),
    .useRd           (D_useRd),
    .useCSR          (D_use_CSR),
    .GPR_new         (D_GPR_new),
    .nextPCSel       (D_nextPCSel),
    .immLen          (D_immLen),
    .sign_extend     (D_sign_extend),
    .cmpOp           (D_cmpOp),
    .aluSrcA         (D_aluSrcA),
    .aluSrcB         (D_aluSrcB),
    .aluOp           (D_aluOp),
    .mult            (D_mult),
    .div             (D_div),
    .mult_div_signed (D_mult_div_signed),
    .memWrite        (D_memWrite),
    .memReadOrWrite  (D_memReadOrWrite),
    .memSigned       (D_memSigned),
    .memDataType     (D_memDataType),
    .regWrite        (D_regWrite),
    .regWriteAddrSel (D_regWriteAddrSel),
    .regWriteDataSrc (D_regWriteDataSrc),

    .rd_addr         (D_rd),
    .rj_addr         (D_rj),
    .rk_addr         (D_rk),

    .imm_12          (D_imm_12),
    .imm_14          (D_imm_14),
    .imm_16          (D_imm_16),
    .imm_20          (D_imm_20),
    .imm_21          (D_imm_21),
    .imm_26          (D_imm_26),

    .shamt           (D_shamt),

    .csrWrite        (D_csrWrite),
    .csrWriteAddr    (D_csrWriteAddr),
    .csrMask         (D_csrMask),
    .errorReturn     (D_errorReturn),
    .notExistInstr   (D_notExistInstr),
    .isBreak         (D_isBreak),
    .isSyscall       (D_isSyscall),
    .readHighCnt     (D_readHighCnt),
    .isIdle          (D_idle),
    .IPE             (D_IPE),
    .refetch         (D_refetch),
    
    .TLB_operation   (D_TLB_operation),

    .cache_target    (D_cache_target),
    .cache_operation (D_cache_operation),

    .is_LL_W         (D_is_LL_W),
    .is_SC_W         (D_is_SC_W),

    .mem_barrier     (D_mem_barrier)
);

assign D_rdk = (D_useRd) ? D_rd : D_rk;

assign D_csrMaskVal = (D_csrMask) ? D_rjVal : {32{1'b1}};    // 仅有部分指令需要配置write_mask

assign D_regWriteAddr = (D_regWriteAddrSel[`reg_rd]) ? D_rd :
                        (D_regWriteAddrSel[`reg_rj]) ? D_rj :
                        (D_regWriteAddrSel[`reg_rk]) ? D_rk :
                        (D_regWriteAddrSel[`reg_link]) ? 5'b00001 : 
                        (D_regWriteAddrSel[`reg_zero]) ? 5'b00000 : 
                        D_rd; // reg_zero或默认情况写入0号寄存器

assign D_cnt_result = (D_readHighCnt) ? D_highCnt : D_lowCnt;

// 转发

wire addr_rj_forward_from_E = 
    E_regWrite & E_regWriteAddr!=0 & E_regWriteAddr==D_rj;
wire addr_rdk_forward_from_E = 
    E_regWrite & E_regWriteAddr!=0 & E_regWriteAddr==D_rdk;
wire addr_rj_forward_from_M =
    M_regWrite & M_regWriteAddr!=0 & M_regWriteAddr==D_rj;
wire addr_rdk_forward_from_M =
    M_regWrite & M_regWriteAddr!=0 & M_regWriteAddr==D_rdk;

assign D_rdkVal = 
    E_valid & addr_rdk_forward_from_E & E_GPR_new[`data_new_E] ? E_forward_data :
    M_valid & addr_rdk_forward_from_M & |M_GPR_new[`data_new_M:`data_new_E] ? M_forward_data :
    D_rdkVal_temp;
assign D_rjVal = 
    E_valid & addr_rj_forward_from_E & E_GPR_new[`data_new_E] ? E_forward_data :
    M_valid & addr_rj_forward_from_M & |M_GPR_new[`data_new_M:`data_new_E] ? M_forward_data :
    D_rjVal_temp;

// 阻塞

wire addr_rj_stall_from_E = 
    D_use_rj & (|E_GPR_new[`data_new_W:`data_new_M]) & 
    E_regWrite & E_regWriteAddr!=0 & E_regWriteAddr==D_rj;
wire addr_rdk_stall_from_E =
    D_use_rdk & (|E_GPR_new[`data_new_W:`data_new_M]) & 
    E_regWrite & E_regWriteAddr!=0 & E_regWriteAddr==D_rdk;
wire addr_rj_stall_from_M =
    D_use_rj & (|M_GPR_new[`data_new_W]) & 
    M_regWrite & M_regWriteAddr!=0 & M_regWriteAddr==D_rj;
wire addr_rdk_stall_from_M =
    D_use_rdk & (|M_GPR_new[`data_new_W]) & 
    M_regWrite & M_regWriteAddr!=0 & M_regWriteAddr==D_rdk;

wire d_e_csr_stall = 
    D_use_CSR & E_csrWrite &
    (D_csrWriteAddr == E_csrWriteAddr | 
        D_csrWriteAddr == `CSR_PGD & 
            (E_csrWriteAddr == `CSR_BADV | E_csrWriteAddr == `CSR_PGDL | 
            E_csrWriteAddr == `CSR_PGDH));

wire d_m_csr_stall = 
    D_use_CSR & M_csrWrite &
    (D_csrWriteAddr == M_csrWriteAddr | 
        D_csrWriteAddr == `CSR_PGD & 
        (M_csrWriteAddr == `CSR_BADV | M_csrWriteAddr == `CSR_PGDL | 
        M_csrWriteAddr == `CSR_PGDH));

wire d_w_csr_stall = 
    D_use_CSR & W_csrWrite &
    (D_csrWriteAddr == W_csrWriteAddr | 
        D_csrWriteAddr == `CSR_PGD & 
        (W_csrWriteAddr == `CSR_BADV | W_csrWriteAddr == `CSR_PGDL | 
        W_csrWriteAddr == `CSR_PGDH));

wire d_e_int_stall = 
    E_csrWrite & 
        (E_csrWriteAddr == `CSR_CRMD |
        E_csrWriteAddr == `CSR_TCFG | E_csrWriteAddr == `CSR_ECFG | 
        E_csrWriteAddr == `CSR_ESTAT | E_csrWriteAddr == `CSR_TICLR);

wire d_m_int_stall = 
    M_csrWrite & 
        (M_csrWriteAddr == `CSR_CRMD |
        M_csrWriteAddr == `CSR_TCFG | M_csrWriteAddr == `CSR_ECFG | 
        M_csrWriteAddr == `CSR_ESTAT | M_csrWriteAddr == `CSR_TICLR);

wire d_w_int_stall = 
    W_csrWrite & 
        (W_csrWriteAddr == `CSR_CRMD |
        W_csrWriteAddr == `CSR_TCFG | W_csrWriteAddr == `CSR_ECFG | 
        W_csrWriteAddr == `CSR_ESTAT | W_csrWriteAddr == `CSR_TICLR);

wire d_e_tlb_stall = 
    D_use_CSR & 
    ((E_TLB_operation[`TLB_OP_SRCH] & D_csrWriteAddr == `CSR_TLBIDX) |
    (E_TLB_operation[`TLB_OP_READ] & 
        (D_csrWriteAddr == `CSR_TLBIDX | 
        D_csrWriteAddr == `CSR_ASID | D_csrWriteAddr == `CSR_TLBEHI |
        D_csrWriteAddr == `CSR_TLBELO0 | D_csrWriteAddr == `CSR_TLBELO1)));

wire d_m_tlb_stall = 
    D_use_CSR & 
    ((M_TLB_operation[`TLB_OP_SRCH] & D_csrWriteAddr == `CSR_TLBIDX) |
    (M_TLB_operation[`TLB_OP_READ] & 
        (D_csrWriteAddr == `CSR_TLBIDX | 
        D_csrWriteAddr == `CSR_ASID | D_csrWriteAddr == `CSR_TLBEHI |
        D_csrWriteAddr == `CSR_TLBELO0 | D_csrWriteAddr == `CSR_TLBELO1)));

wire d_w_tlb_stall = 
    D_use_CSR & 
    ((W_TLB_operation[`TLB_OP_SRCH] & D_csrWriteAddr == `CSR_TLBIDX) |
    (W_TLB_operation[`TLB_OP_READ] & 
        (D_csrWriteAddr == `CSR_TLBIDX | 
        D_csrWriteAddr == `CSR_ASID | D_csrWriteAddr == `CSR_TLBEHI |
        D_csrWriteAddr == `CSR_TLBELO0 | D_csrWriteAddr == `CSR_TLBELO1)));


wire div_stall = 
    /*(D_regWriteDataSrc[`data_src_div_hi] | D_regWriteDataSrc[`data_src_div_lo]) 
    & div_busy |
    div_busy & 
        (D_use_rj & D_rj == div_dest & div_dest != 0 | 
        D_use_rdk & D_rdk == div_dest & div_dest != 0)*/ 0;

wire csr_stall = 
    E_valid & d_e_csr_stall |
    M_valid & d_m_csr_stall |
    W_valid & d_w_csr_stall ;

wire int_stall = 
    E_valid & d_e_int_stall |
    M_valid & d_m_int_stall |
    W_valid & d_w_int_stall;

wire flush_stall = 
    E_valid & (|E_exception | E_errorReturn | E_refetch | E_idle) |
    M_valid & (|M_exception | M_errorReturn | M_refetch | M_idle) |
    W_valid & (|W_exception | W_errorReturn | W_refetch | W_idle);

wire tlb_stall = 
    E_valid & d_e_tlb_stall |
    M_valid & d_m_tlb_stall |
    W_valid & d_w_tlb_stall;

wire dbar_stall = D_mem_barrier[`MEM_BAR_DATA] &
                        (E_valid & (E_memReadOrWrite | E_is_SC_W) |
                        M_valid & (M_memReadOrWrite | M_is_SC_W));

wire ibar_stall = D_mem_barrier[`MEM_BAR_INST] & 
                        (E_valid & (E_memWrite | E_is_SC_W) |
                        M_valid & (M_memWrite | M_is_SC_W));

wire data_stall = (D_memReadOrWrite | D_is_SC_W) &
                    (E_valid & E_mem_barrier[`MEM_BAR_DATA] |
                    M_valid & M_mem_barrier[`MEM_BAR_DATA]);

assign D_stall = 
    E_valid & (addr_rj_stall_from_E | addr_rdk_stall_from_E) |
    M_valid & (addr_rj_stall_from_M | addr_rdk_stall_from_M) |
    csr_stall | int_stall | tlb_stall | dbar_stall | ibar_stall | data_stall |
    flush_stall | div_stall;

assign D_branch_jump_stall = 
    D_nextPCSel[`npc_jirl] & 
        (E_valid & addr_rj_stall_from_E | M_valid & addr_rj_stall_from_M) |
    D_nextPCSel[`npc_branch] &
        (E_valid & (addr_rj_stall_from_E | addr_rdk_stall_from_E) |
        M_valid & (addr_rj_stall_from_M | addr_rdk_stall_from_M));

assign D_done = ~D_stall | |D_exception;

assign D_branch = 
    D_valid & ~D_branch_jump_stall & 
    (D_nextPCSel[`npc_jirl] | D_nextPCSel[`npc_branch] & D_cmp_flag);

assign D_branch_instr = D_nextPCSel[`npc_jirl] | D_nextPCSel[`npc_branch];

assign D_branch_valid = D_nextPCSel[`npc_jirl] | D_nextPCSel[`npc_branch] & D_cmp_flag;

assign D_INT = 
    W_interrupt & ~int_stall;

D_extend d_extend(
    .imm_12   (D_imm_12),
    .imm_14   (D_imm_14),
    .imm_16   (D_imm_16),
    .imm_20   (D_imm_20),
    .isSigned (D_sign_extend),
    .imm_len  (D_immLen),
    .result   (D_extended)
);

D_cmp d_cmp(
    .op1   (D_rjVal),
    .op2   (D_rdkVal),
    .cmpOp (D_cmpOp),
    .flag  (D_cmp_flag)
);

// =====D级分支预测器控制信号===== //
assign D_operate_enable = 
    D_valid & D_done & E_ready & ~|D_exception;
assign D_operate_pc = D_PC;
assign D_ras_pop_return = D_nextPCSel[`npc_jirl];
assign D_ras_push_call = D_regWriteAddrSel[`reg_link];
assign D_add_entry = D_branch_instr & D_branch_valid & ~D_btb_enable;
assign D_delete_entry = ~D_branch_instr & D_btb_enable;
assign D_predict_error = 
    D_branch_instr &
    D_btb_enable & (D_btb_taken ^ D_branch_valid);
assign D_predict_correct =
    D_branch_instr &
    D_btb_enable & !(D_btb_taken ^ D_branch_valid);
assign D_target_error = 
    D_branch_instr &
    D_btb_enable & (D_btb_taken & D_branch_valid) & (D_btb_pc != branch_PC);
assign D_right_orien = D_branch_valid;
assign D_right_target = branch_PC;
assign D_operate_btb_index = D_btb_index;

assign D_btb_flush = 
    (D_add_entry | D_delete_entry | D_predict_error | D_target_error) &
    D_valid & D_done & ~|D_exception;
assign D_btb_flush_target = 
    D_branch_valid ? branch_PC : D_PCwith4;


// =====E级===== //
assign E_exception = 
    {E_TLBR_Data, E_TLBR_Instr, E_IPE, E_INE, E_BRK, E_SYSCALL, E_ALE, E_ADEM,
    E_ADEF, E_PPI_Data, E_PPI_Instr, E_PME, E_PIF, E_PIS, E_PIL, E_INT};

wire [`CACHE_OP_WIDTH+1:0] data_op;

wire data_load;
wire data_store;

D2Ereg u_D2Ereg(
    .clk               (clk),
    .reset             (reset),
    .flush             (flush),
    .stall             (D_stall),
    .D_PC              (D_PC),
    .E_PC              (E_PC),
    .E_PCwith4         (E_PCwith4),
    .E_PCwith8         (E_PCwith8),
    .D_GPR_new           (D_GPR_new),
    .E_GPR_new           (E_GPR_new),
    .D_aluSrcA         (D_aluSrcA),
    .D_aluSrcB         (D_aluSrcB),
    .D_aluOp           (D_aluOp),
    .D_shamt           (D_shamt),
    .D_mult            (D_mult),
    .D_div             (D_div),
    .D_mult_div_signed (D_mult_div_signed),
    .E_aluSrcA         (E_aluSrcA),
    .E_aluSrcB         (E_aluSrcB),
    .E_aluOp           (E_aluOp),
    .E_shamt           (E_shamt),
    .E_mult            (E_mult),
    .E_div             (E_div),
    .E_mult_div_signed (E_mult_div_signed),
    .D_memWrite        (D_memWrite),
    .D_memReadOrWrite  (D_memReadOrWrite),
    .D_memSigned       (D_memSigned),
    .D_memDataType     (D_memDataType),
    .E_memWrite        (E_memWrite),
    .E_memReadOrWrite  (E_memReadOrWrite),
    .E_memSigned       (E_memSigned),
    .E_memDataType     (E_memDataType),
    .D_regWrite        (D_regWrite),
    .D_regWriteAddr    (D_regWriteAddr),
    .D_regWriteDataSrc (D_regWriteDataSrc),
    .E_regWrite        (E_regWrite),
    .E_regWriteAddr    (E_regWriteAddr),
    .E_regWriteDataSrc (E_regWriteDataSrc),
    .D_rjVal           (D_rjVal),
    .D_rdkVal          (D_rdkVal),
    .D_rj              (D_rj),
    .D_rdk             (D_rdk),
    .E_rjVal           (E_rjVal),
    .E_rdkVal          (E_rdkVal),
    .E_rj              (E_rj),
    .E_rdk             (E_rdk),
    .D_extended        (D_extended),
    .E_extended        (E_extended),

    .D_INE           (D_INE),
    .D_BRK           (D_BRK),
    .D_SYSCALL       (D_SYSCALL),
    .D_ADEF          (D_ADEF),
    .D_INT           (D_INT),
    .D_TLBR_Instr    (D_TLBR_Instr),
    .D_IPE           (D_IPE),   
    .D_PPI_Instr     (D_PPI_Instr),
    .D_PIF           (D_PIF),
    .E_INE           (E_INE),
    .E_BRK           (E_BRK),
    .E_SYSCALL       (E_SYSCALL),
    .E_ADEF          (E_ADEF),
    .E_INT           (E_INT),
    .E_TLBR_Instr    (E_TLBR_Instr),
    .E_IPE           (E_IPE),
    .E_PPI_Instr     (E_PPI_Instr), 
    .E_PIF           (E_PIF),

    .D_csrWrite        (D_csrWrite),
    .D_csrWriteAddr    (D_csrWriteAddr),
    .D_csrMaskVal      (D_csrMaskVal),
    .D_csrMask         (D_csrMask),
    //.D_csrNum_TID      (D_csrNum_TID),
    .E_csrWrite        (E_csrWrite),
    .E_csrWriteAddr    (E_csrWriteAddr),
    .E_csrMaskVal      (E_csrMaskVal),
    .E_csrMask         (E_csrMask),
    //.E_csrNum_TID      (E_csrNum_TID),
    .D_cnt_result      (D_cnt_result),
    .E_cnt_result      (E_cnt_result),
    .D_errorReturn     (D_errorReturn),
    .D_idle            (D_idle),
    .D_refetch        (D_refetch),
    .E_errorReturn     (E_errorReturn),
    .E_idle            (E_idle),
    .E_refetch        (E_refetch),
    .E_done            (E_done),
    .M_ready           (M_ready),
    .D_to_E_valid      (D_to_E_valid),
    .E_valid           (E_valid),
    .E_ready           (E_ready),
    .E_to_M_valid      (E_to_M_valid),
    .D_TLB_operation   (D_TLB_operation),
    .E_TLB_operation   (E_TLB_operation),

    .D_instr          (D_instr),
    .E_instr          (E_instr),

    .D_csrReadData    (D_csrReadData),
    .E_csrReadData    (E_csrReadData),

    .D_highCnt        (D_highCnt),
    .D_lowCnt         (D_lowCnt),
    .E_highCnt        (E_highCnt),
    .E_lowCnt         (E_lowCnt),

    .D_cache_operation (D_cache_operation),
    .D_cache_target    (D_cache_target),
    .E_cache_operation (E_cache_operation),
    .E_cache_target    (E_cache_target),

    .D_is_LL_W         (D_is_LL_W),
    .D_is_SC_W         (D_is_SC_W),
    .E_is_LL_W         (E_is_LL_W),
    .E_is_SC_W         (E_is_SC_W),

    .D_mem_barrier     (D_mem_barrier),
    .E_mem_barrier     (E_mem_barrier)
);

// assign E_csrMaskVal = (E_csrMask) ? {32{1'b1}} : E_rjVal;

// 操作数的assign语句
assign E_operand1 = (E_aluSrcA[`alu_src_rj]) ? E_rjVal :
                    (E_aluSrcA[`alu_src_rdk]) ? E_rdkVal :
                    (E_aluSrcA[`alu_src_imm]) ? E_extended :
                    (E_aluSrcA[`alu_src_pc]) ? E_PC :
                    (E_aluSrcA[`alu_src_four]) ? 32'h4 :
                    32'b0;

assign E_operand2 = (E_aluSrcB[`alu_src_rj]) ? E_rjVal :
                    (E_aluSrcB[`alu_src_rdk]) ? E_rdkVal :
                    (E_aluSrcB[`alu_src_imm]) ? E_extended :
                    (E_aluSrcB[`alu_src_pc]) ? E_PC :
                    (E_aluSrcB[`alu_src_four]) ? 32'h4 :
                    32'b0;

E_ALU e_ALU(
    .E_valid      (E_valid),
    .clk          (clk),
    .reset        (reset),
    .operand1     (E_operand1),
    .operand2     (E_operand2),
    .ALUOp        (E_aluOp),
    .shamt        (E_shamt),
    .E_alu_result (E_alu_result),
    .E_memAddr    (E_memAddr),
    .E_ALU_done   (E_ALU_done)

    /*.div_result    (M_div_result),
    .mod_result    (M_mod_result),
    .div_complete  (div_complete)*/
);

assign E_done = 
    |E_exception ? 1'b1 : 
    (E_regWriteDataSrc[`data_src_div_hi] | E_regWriteDataSrc[`data_src_div_lo]) ?
        div_complete:
    (((E_memReadOrWrite & ~E_memWrite) | data_store) 
            | E_cache_target[`CACHE_TARGET_DCACHE]) ? 
        (data_sram_req & data_sram_addr_ok) : 
    (E_cache_target[`CACHE_TARGET_ICACHE]) ? 
        (inst_cacop_req & inst_sram_addr_ok) : 
    E_ALU_done;

assign E_ALE = 
    (
        ((E_memReadOrWrite | E_LL_bit & E_is_SC_W) 
            && E_memDataType[`word] && (|E_memAddr[1:0])) || // word访问地址未对齐
        (E_memReadOrWrite && E_memDataType[`half] && (|E_memAddr[0]))
    ) 
    & ~E_cache_operation[`CACHE_OP_HIT_OP];   
    // half访问地址未对齐; 对于hit-op而言不需要检查对齐（见指令手册）。

assign E_ADEM = 
    /*(E_memReadOrWrite & E_alu_result[31]) &
    ((W_csr_da & ~W_csr_pg & W_csr_plv==3) | 
        (~W_csr_da & W_csr_pg & W_csr_plv>W_dmw1_plv))*/0;

assign E_forward_data = 
    {32{E_regWriteDataSrc[`data_src_div_hi]}} & E_mod_result |
    {32{E_regWriteDataSrc[`data_src_div_lo]}} & E_div_result |
    {32{E_regWriteDataSrc[`data_src_alu]}} & E_alu_result | 
    {32{E_regWriteDataSrc[`data_src_cnt]}} & E_cnt_result |
    {32{E_regWriteDataSrc[`data_src_csr]}} & E_csrReadData;

E_multiplier e_multiplier(  
    .mul_clk    (clk),
    .reset      (reset),
    .mul_signed (E_mult_div_signed),
    .x          (E_operand1),
    .y          (E_operand2),
    .result     (E_mult_result) // assign M_mult_result = E_mult_result
);

divider u_divider(
	.div_en     (E_valid & (E_regWriteDataSrc[`data_src_div_hi] | E_regWriteDataSrc[`data_src_div_lo])),
	.div_clk    (clk),
	.div_reset  (reset),
	.div_signed (E_aluOp[`alu_div_w] | E_aluOp[`alu_mod_w]),
	.operand1   (E_operand1),
	.operand2   (E_operand2),
	.quotient   (E_div_result),
	.remainder  (E_mod_result),
	//.complete   (E_div_complete_ahead),
	.complete_delay   (div_complete),
    .busy       (div_busy),
    .div_reg_dst_buf  (div_dest)
);

// 由于历史原因，该模块被标注为M级的，其实是在E级发挥的作用
// TODO: 增加接入dcache的信号

M_byteen m_byteen(
    .alu_result  (E_alu_result),

    .writeEnable (E_memWrite),
    .dataType    (E_memDataType),
    .address     (E_memAddr),
    .M_ready     (M_ready),
    .E_valid          (E_valid          ),
    .M_valid          (M_valid          ),
    .W_valid          (W_valid          ),
    .E_exception      (E_exception      ),
    .M_exception      (M_exception      ),
    .W_exception      (W_exception      ),
    .E_memReadOrWrite (E_memReadOrWrite ),
    .ALE         (E_ALE),
    .request     (W_request),
    .byteEnable  (data_sram_wstrb),
    .data_sram_wr (data_sram_wr),
    .data_sram_req (data_sram_req),
    .data_sram_size (data_sram_size),

    .cache_target (E_cache_target),
    .cache_operation (E_cache_operation),
    .data_op (data_op),

    // inst_cacop
    .inst_cacop_req (inst_cacop_req),
    .inst_cacop_op (inst_cacop_op),
    .inst_cacop_vaddr (inst_cacop_vaddr),

    .LL_bit (E_LL_bit),
    .is_LL_W (E_is_LL_W),
    .is_SC_W (E_is_SC_W),
    .data_load (data_load),
    .data_store (data_store)
);

assign data_sram_wdata = 
    //E_rdkVal << {{data_sram_addr[1:0]}, {3'b000}}
    ({32{E_memDataType[`byte]}} & {4{E_rdkVal[7:0]}}) |
    ({32{E_memDataType[`half]}} & {2{E_rdkVal[15:0]}}) |
    ({32{E_memDataType[`word]}} & {{E_rdkVal[31:0]}});

// =====M级===== //
assign M_exception = 
    {M_TLBR_Data, M_TLBR_Instr, M_IPE, M_INE, M_BRK, M_SYSCALL, M_ALE, M_ADEM,
    M_ADEF, M_PPI_Data, M_PPI_Instr, M_PME, M_PIF, M_PIS, M_PIL, M_INT};

E2Mreg u_E2Mreg(
    .clk               (clk),
    .reset             (reset),
    .flush             (flush),
    .E_PC              (E_PC),
    .M_PC              (M_PC),
    .M_PCwith4         (M_PCwith4),
    .M_PCwith8         (M_PCwith8),
    .E_GPR_new           (E_GPR_new),
    .M_GPR_new           (M_GPR_new),
    .E_alu_result      (E_alu_result),
    .M_alu_result      (M_alu_result),
    .E_memWrite        (E_memWrite),
    .E_memReadOrWrite  (E_memReadOrWrite),
    .E_memSigned       (E_memSigned),
    .E_memDataType     (E_memDataType),
    .E_memAddr         (E_memAddr),
    .M_memWrite        (M_memWrite),
    .M_memReadOrWrite  (M_memReadOrWrite),
    .M_memSigned       (M_memSigned),
    .M_memDataType     (M_memDataType),
    .M_memAddr         (M_memAddr),
    .E_regWrite        (E_regWrite),
    .E_regWriteAddr    (E_regWriteAddr),
    .E_regWriteDataSrc (E_regWriteDataSrc),
    .M_regWrite        (M_regWrite),
    .M_regWriteAddr    (M_regWriteAddr),
    .M_regWriteDataSrc (M_regWriteDataSrc),
    .E_rjVal           (E_rjVal),
    .E_rdkVal          (E_rdkVal),
    .E_rj              (E_rj),
    .E_rdk             (E_rdk),
    .M_rjVal           (M_rjVal),
    .M_rdkVal          (M_rdkVal),
    .M_rj              (M_rj),
    .M_rdk             (M_rdk),
    .E_INE             (E_INE),
    .E_BRK             (E_BRK),
    .E_SYSCALL         (E_SYSCALL),
    .E_ADEF            (E_ADEF),
    .E_INT             (E_INT),
    .E_ALE             (E_ALE),
    .E_TLBR_Data        (E_TLBR_Data),
    .E_TLBR_Instr       (E_TLBR_Instr),
    .E_IPE             (E_IPE),
    .E_PPI_Data         (E_PPI_Data),
    .E_PPI_Instr        (E_PPI_Instr),
    .E_PME             (E_PME),
    .E_PIF             (E_PIF),
    .E_PIS             (E_PIS),
    .E_PIL             (E_PIL),
    .E_ADEM            (E_ADEM),
    .M_INE             (M_INE),
    .M_BRK             (M_BRK),
    .M_SYSCALL         (M_SYSCALL),
    .M_ADEF            (M_ADEF),
    .M_INT             (M_INT),
    .M_ALE             (M_ALE),
    .M_TLBR_Data        (M_TLBR_Data),
    .M_TLBR_Instr       (M_TLBR_Instr),
    .M_IPE             (M_IPE),
    .M_PPI_Data         (M_PPI_Data),
    .M_PPI_Instr        (M_PPI_Instr),
    .M_PME             (M_PME),
    .M_PIF             (M_PIF),
    .M_PIS             (M_PIS),
    .M_PIL             (M_PIL),
    .M_ADEM            (M_ADEM),
    .E_csrWrite        (E_csrWrite),
    .E_csrWriteAddr    (E_csrWriteAddr),
    .E_csrMaskVal      (E_csrMaskVal),
    .E_csrMask         (E_csrMask),
    .E_errorReturn     (E_errorReturn),
    .E_idle            (E_idle),
    .E_refetch        (E_refetch),
    //.E_csrNum_TID      (E_csrNum_TID),
    .M_csrWrite        (M_csrWrite),
    .M_csrWriteAddr    (M_csrWriteAddr),
    .M_csrMaskVal      (M_csrMaskVal),
    .M_csrMask         (M_csrMask),
    .M_errorReturn     (M_errorReturn),
    .M_idle            (M_idle),
    .M_refetch        (M_refetch),
    //.M_csrNum_TID      (M_csrNum_TID),
    .E_cnt_result      (E_cnt_result),
    .M_cnt_result      (M_cnt_result),
    .M_done            (M_done),
    .W_ready           (W_ready),
    .E_to_M_valid      (E_to_M_valid),
    .M_valid           (M_valid),
    .M_ready           (M_ready),
    .M_to_W_valid      (M_to_W_valid),
    .E_TLB_operation   (E_TLB_operation),
    .M_TLB_operation   (M_TLB_operation),

    .E_instr          (E_instr),
    .M_instr          (M_instr),

    .E_paddr          (data_sram_addr),
    .M_paddr          (M_paddr),

    .E_csrReadData     (E_csrReadData),
    .M_csrReadData     (M_csrReadData),

    .E_highCnt         (E_highCnt),
    .E_lowCnt          (E_lowCnt),
    .M_highCnt         (M_highCnt),
    .M_lowCnt          (M_lowCnt),

    .E_LL_bit          (E_LL_bit),
    .E_is_LL_W         (E_is_LL_W),
    .E_is_SC_W         (E_is_SC_W),
    .M_LL_bit          (M_LL_bit),
    .M_is_LL_W         (M_is_LL_W),
    .M_is_SC_W         (M_is_SC_W),

    .E_cache_target    (E_cache_target),
    .M_cache_target    (M_cache_target),

    .E_mem_barrier      (E_mem_barrier),
    .M_mem_barrier      (M_mem_barrier),

    .E_div_result    (E_div_result),
    .E_mod_result    (E_mod_result),
    .M_div_result    (M_div_result),
    .M_mod_result    (M_mod_result)
);

//assign M_csrMaskVal = (M_csrMask) ? {32{1'b1}} : M_rjVal;

M_dataExt m_dataExt(
    .addrLow  (M_memAddr[1:0]),
    .dataIn   (data_sram_rdata),
    .dataType (M_memDataType),
    .isSigned (M_memSigned),
    
    .M_exception (M_exception),
    .M_memReadOrWrite (M_memReadOrWrite),
    .data_sram_data_ok (data_sram_data_ok),
    .inst_sram_data_ok (inst_sram_data_ok),
    .M_done   (M_done),
    .LL_bit   (M_LL_bit),
    .is_LL_W  (M_is_LL_W),
    .is_SC_W  (M_is_SC_W),
    .cache_target  (M_cache_target),
    .div_complete  (div_complete),
    .div_instr  (M_regWriteDataSrc[`data_src_div_hi] | M_regWriteDataSrc[`data_src_div_lo]),

    .dataOut  (M_mem_result)
);

assign M_mult_result = E_mult_result;

assign M_forward_data = 
    {32{M_regWriteDataSrc[`data_src_mul_hi]}} & M_mult_result[63:32] |
    {32{M_regWriteDataSrc[`data_src_mul_lo]}} & M_mult_result[31:0] |
    {32{M_regWriteDataSrc[`data_src_div_hi]}} & M_mod_result |
    {32{M_regWriteDataSrc[`data_src_div_lo]}} & M_div_result |
    {32{M_regWriteDataSrc[`data_src_alu]}} & M_alu_result | 
    {32{M_regWriteDataSrc[`data_src_pc]}} & M_PC | 
    {32{M_regWriteDataSrc[`data_src_mem]}} & M_mem_result |
    {32{M_regWriteDataSrc[`data_src_cnt]}} & M_cnt_result |
    {32{M_regWriteDataSrc[`data_src_csr]}} & M_csrReadData |
    {32{M_regWriteDataSrc[`data_src_scw]}} & M_LL_bit;

assign M_regWriteData = (M_regWriteDataSrc[`data_src_alu]) ? M_alu_result :
                        (M_regWriteDataSrc[`data_src_pc]) ? M_PC :
                        (M_regWriteDataSrc[`data_src_mul_hi]) ? M_mult_result[63:32] :
                        (M_regWriteDataSrc[`data_src_mul_lo]) ? M_mult_result[31:0] :
                        (M_regWriteDataSrc[`data_src_div_hi]) ? M_mod_result :
                        (M_regWriteDataSrc[`data_src_div_lo]) ? M_div_result :
                        (M_regWriteDataSrc[`data_src_mem]) ? M_mem_result :
                        (M_regWriteDataSrc[`data_src_cnt]) ? M_cnt_result :
                        (M_regWriteDataSrc[`data_src_csr]) ? M_csrReadData :
                        (M_regWriteDataSrc[`data_src_scw]) ? M_LL_bit :
                        32'b0;

// =====W级===== //

assign W_done = /*(W_regWriteDataSrc[`data_src_div_hi] | W_regWriteDataSrc[`data_src_div_lo]) ? div_complete :*/ 1'b1;
wire [`exception_width-1:0] exception;
wire errorReturn;

M2Wreg u_M2Wreg(
    .clk               (clk),
    .reset             (reset),
    .flush             (flush),
    .M_PC              (M_PC),
    .W_PC              (W_PC),
    .W_PCwith4         (W_PCwith4),
    .W_PCwith8         (W_PCwith8),
    .M_GPR_new           (M_GPR_new),
    .W_GPR_new           (W_GPR_new),
    .M_alu_result      (M_alu_result),
    .W_alu_result      (W_alu_result),
    .M_mult_result     (M_mult_result),
    .W_mult_result     (W_mult_result),
    .M_mem_result      (M_mem_result),
    .W_mem_result      (W_mem_result),
    .M_regWrite        (M_regWrite),
    .M_regWriteAddr    (M_regWriteAddr),
    .M_regWriteDataSrc (M_regWriteDataSrc),
    .W_regWrite        (W_regWrite),
    .W_regWriteAddr    (W_regWriteAddr),
    .W_regWriteDataSrc (W_regWriteDataSrc),
    .M_csrWrite        (M_csrWrite),
    .M_csrWriteAddr    (M_csrWriteAddr),
    .M_csrMaskVal      (M_csrMaskVal),
    //.M_csrNum_TID      (M_csrNum_TID),
    .W_csrWrite        (W_csrWrite),
    .W_csrWriteAddr    (W_csrWriteAddr),
    .W_csrMaskVal      (W_csrMaskVal),
    //.W_csrNum_TID      (W_csrNum_TID),
    .M_cnt_result      (M_cnt_result),
    .W_cnt_result      (W_cnt_result),
    .M_INE             (M_INE),
    .M_BRK             (M_BRK),
    .M_SYSCALL         (M_SYSCALL),
    .M_ADEF            (M_ADEF),
    .M_INT             (M_INT),
    .M_ALE             (M_ALE),
    .M_TLBR_Data        (M_TLBR_Data),
    .M_TLBR_Instr       (M_TLBR_Instr),
    .M_IPE             (M_IPE),
    .M_PPI_Data         (M_PPI_Data),
    .M_PPI_Instr        (M_PPI_Instr),
    .M_PME             (M_PME),
    .M_PIF             (M_PIF),
    .M_PIS             (M_PIS),
    .M_PIL             (M_PIL),
    .M_ADEM            (M_ADEM),
    .W_INE             (W_INE),
    .W_BRK             (W_BRK),
    .W_SYSCALL         (W_SYSCALL),
    .W_ADEF            (W_ADEF),
    .W_INT             (W_INT),
    .W_ALE             (W_ALE),
    .W_TLBR_Data        (W_TLBR_Data),
    .W_TLBR_Instr       (W_TLBR_Instr),
    .W_IPE             (W_IPE),
    .W_PPI_Data         (W_PPI_Data),
    .W_PPI_Instr        (W_PPI_Instr),
    .W_PME             (W_PME),
    .W_PIF             (W_PIF),
    .W_PIS             (W_PIS),
    .W_PIL             (W_PIL),
    .W_ADEM            (W_ADEM),
    .M_memAddr         (M_memAddr),
    .W_memAddr         (W_memAddr),
    .M_rdkVal          (M_rdkVal),
    .M_rjVal          (M_rjVal),
    .W_rdkVal          (W_rdkVal),
    .W_rjVal          (W_rjVal),
    .M_errorReturn     (M_errorReturn),
    .M_idle            (M_idle),
    .M_refetch         (M_refetch),
    .W_errorReturn     (W_errorReturn),
    .W_idle            (W_idle),
    .W_refetch         (W_refetch),
    .W_done            (W_done),
    .M_to_W_valid      (M_to_W_valid),
    .W_ready           (W_ready),
    .W_valid           (W_valid),
    .M_TLB_operation   (M_TLB_operation),
    .W_TLB_operation   (W_TLB_operation),

    .M_memWrite       (M_memWrite),
    .M_memDataType    (M_memDataType),
    .M_memSigned      (M_memSigned),
    .M_memReadOrWrite  (M_memReadOrWrite),
    .W_memWrite       (W_memWrite),
    .W_memReadOrWrite  (W_memReadOrWrite),
    .W_memDataType    (W_memDataType),
    .W_memSigned      (W_memSigned),

    .M_instr          (M_instr),
    .W_instr          (W_instr),

    .M_paddr          (M_paddr),
    .W_paddr          (W_paddr),

    .M_csrReadData    (M_csrReadData),
    .W_csrReadData    (W_csrReadData),

    .M_highCnt        (M_highCnt),
    .M_lowCnt         (M_lowCnt),
    .W_highCnt        (W_highCnt),
    .W_lowCnt         (W_lowCnt),

    .M_LL_bit         (M_LL_bit),
    .M_is_LL_W        (M_is_LL_W),
    .M_is_SC_W        (M_is_SC_W),
    .W_LL_bit         (W_LL_bit),
    .W_is_LL_W        (W_is_LL_W),  
    .W_is_SC_W        (W_is_SC_W),

    .M_div_result       (M_div_result),
    .M_mod_result       (M_mod_result),
    .W_div_result       (W_div_result),
    .W_mod_result       (W_mod_result)
);

wire [`TLB_OP_WIDTH-1:0] W_real_tlb_op;

assign W_real_tlb_op = 
    {`TLB_OP_WIDTH{W_valid & ~|W_exception}} & W_TLB_operation;

wire llbit_write_enable = 
        W_valid & ~|W_exception & (W_is_LL_W | W_is_SC_W);

wire llbit_write_data = (W_is_LL_W & 1'b1) | (W_is_SC_W & 1'b0);

CSRF #(
    .TLBNUM(`TLB_ENTRIES)
) u_CSRF (
    .clk               (clk),
    .reset             (reset),
    .csrAddr           (W_csrWriteAddr),
    .writeEnable       (W_csrWrite & W_valid & ~|W_exception),
    .writeMask         (W_csrMaskVal),
    .writeData         (W_csrWriteData),
    .readData          (D_csrReadData),
    .csrReadAddr       (D_csrWriteAddr),
    .PC                (W_PC),
    .errorReturn       (errorReturn),
    .hardwareInt       (intrpt),
    .softwareInt       (2'b0),
    .interProcessorInt (1'b0),
    .exception         (exception),
    .returnAddr        (W_returnAddr),
    .entry             (W_entry),
    .request           (W_request),
    .interrupt         (W_interrupt),
    .vAddr             (W_alu_result),

    .TLB_operation     (W_real_tlb_op[`TLB_OP_READ:`TLB_OP_SRCH]),
    .TLB_rw_index      (W_TLB_rw_index),
    .TLB_sw_hi         (W_TLB_sw_hi),
    .TLB_w_lo0         (W_TLB_w_lo0),
    .TLB_w_lo1         (W_TLB_w_lo1),
    .TLB_f_index       (W_TLB_f_index),
    .TLB_s_hit         (W_TLB_s_hit),
    .TLB_s_index       (W_TLB_s_index),
    .TLB_r_hi          (W_TLB_r_hi),
    .TLB_r_lo0         (W_TLB_r_lo0),
    .TLB_r_lo1         (W_TLB_r_lo1),
    .da                (W_csr_da),
    .pg                (W_csr_pg),
    .asid              (W_csr_asid),
    .plv               (W_csr_plv),
    .plv0              (W_dmw0_plv),
    .pseg0             (W_dmw0_pseg),
    .vseg0             (W_dmw0_vseg),
    .mat0              (W_dmw0_mat),
    .plv1              (W_dmw1_plv),
    .pseg1             (W_dmw1_pseg),
    .vseg1             (W_dmw1_vseg),
    .mat1              (W_dmw1_mat),
    .datf              (W_csr_datf),
    .datm              (W_csr_datm),

    .highCnt_out       (D_highCnt),
    .lowCnt_out        (D_lowCnt),

    .llbit             (E_LL_bit),
    .llbit_write_enable(llbit_write_enable),
    .llbit_write_data  (llbit_write_data),
    .E_paddr             (data_sram_addr),
    .W_paddr             (W_paddr),

    .tlb_plru_victim_entry (tlb_plru_victim_entry)
);

// TODO: 修改MMU，提供dcache、icache相关信号


MMU #(
    .TLBNUM(`TLB_ENTRIES)
) u_MMU (
    .clk           (clk             ),
    .TLB_operation (W_real_tlb_op   ),
    .invtlb_vaddr  (W_rdkVal[31:`VPPN_4KB_LSB]),
    .invtlb_asid   (W_rjVal[9:0]),
    .TLB_rw_index  (W_TLB_rw_index  ),
    .TLB_sw_hi     (W_TLB_sw_hi     ),
    .TLB_w_lo0     (W_TLB_w_lo0     ),
    .TLB_w_lo1     (W_TLB_w_lo1     ),
    .TLB_f_index   (W_TLB_f_index   ),
    .TLB_s_hit     (W_TLB_s_hit     ),
    .TLB_s_index   (W_TLB_s_index   ),
    .TLB_r_hi      (W_TLB_r_hi      ),
    .TLB_r_lo0     (W_TLB_r_lo0     ),
    .TLB_r_lo1     (W_TLB_r_lo1     ),

    .csr_da        (W_csr_da        ),
    .csr_pg        (W_csr_pg        ),
    .csr_asid      (W_csr_asid      ),
    .csr_plv       (W_csr_plv       ),
    .csr_datf      (W_csr_datf      ),
    .csr_datm      (W_csr_datm      ),
    .dmw0_plv      (W_dmw0_plv      ),
    .dmw0_pseg     (W_dmw0_pseg     ),
    .dmw0_vseg     (W_dmw0_vseg     ),
    .dmw0_mat      (W_dmw0_mat),
    .dmw1_plv      (W_dmw1_plv      ),
    .dmw1_pseg     (W_dmw1_pseg     ),
    .dmw1_vseg     (W_dmw1_vseg     ),
    .dmw1_mat      (W_dmw1_mat),

    .inst_search_op (inst_search_op),
    .inst_paddr    (inst_sram_addr    ),
    .inst_vaddr    (inst_search_op[0] ? inst_cacop_vaddr : Pre_PC),

    .data_search_op (data_search_op),
    .data_paddr    (data_sram_addr    ),
    .data_vaddr    (E_alu_result    ),

    .PIL           (E_PIL),
    .PIS           (E_PIS),
    .PIF           (Pre_PIF),
    .PME           (E_PME),
    .inst_PPI      (Pre_PPI_Instr),
    .data_PPI      (E_PPI_Data),
    .inst_TLBR     (Pre_TLBR_Instr),
    .data_TLBR     (E_TLBR_Data),

    .inst_access_type  (inst_access_type),
    .data_access_type  (data_access_type),

    .tlb_plru_victim_entry (tlb_plru_victim_entry)
);

assign exception = {`exception_width{W_valid}} & W_exception;
assign errorReturn = W_errorReturn & W_valid;

assign W_exception = 
    {W_TLBR_Data, W_TLBR_Instr, W_IPE, W_INE, W_BRK, W_SYSCALL, W_ALE, W_ADEM,
    W_ADEF, W_PPI_Data, W_PPI_Instr, W_PME, W_PIF, W_PIS, W_PIL, W_INT};

assign debug_wb_pc = W_PC;
assign debug_wb_rf_wdata = W_regWriteData;
assign debug_wb_rf_we = {4{W_regWrite & (|W_regWriteAddr) & W_valid & ~|W_exception /*& W_done*/}};
assign debug_wb_rf_wnum = W_regWriteAddr;

assign W_csrWriteData = W_rdkVal;

assign W_regWriteData = (W_regWriteDataSrc[`data_src_alu]) ? W_alu_result :
                        (W_regWriteDataSrc[`data_src_pc]) ? W_PC :
                        (W_regWriteDataSrc[`data_src_mul_hi]) ? W_mult_result[63:32] :
                        (W_regWriteDataSrc[`data_src_mul_lo]) ? W_mult_result[31:0] :
                        (W_regWriteDataSrc[`data_src_div_hi]) ? W_mod_result :
                        (W_regWriteDataSrc[`data_src_div_lo]) ? W_div_result :
                        (W_regWriteDataSrc[`data_src_mem]) ? W_mem_result :
                        (W_regWriteDataSrc[`data_src_cnt]) ? W_cnt_result :
                        (W_regWriteDataSrc[`data_src_csr]) ? W_csrReadData :
                        (W_regWriteDataSrc[`data_src_scw]) ? W_LL_bit :
                        32'b0;

assign flush = W_request | (W_valid & (W_errorReturn | W_idle | W_refetch));

assign idle = (W_idle & W_valid & ~W_exception[`EXCEPTION_IPE]); 

assign refetch =  (W_refetch & W_valid);

wire [63:0] W_counterVal = {W_highCnt, W_lowCnt};

// cache

cache i_cache(
    .clk         (clk         ),
    .reset       (reset       ),
    .valid       (inst_sram_req | inst_cacop_req),
    .op          (inst_cacop_req ? inst_cacop_op : inst_op),
    .vaddr       (inst_cacop_req ? inst_cacop_vaddr : Pre_PC),
    .access_size (inst_access_size),
    .wstrb       (inst_sram_wstrb),
    .wdata       (inst_sram_wdata),
    .addr_ok     (inst_sram_addr_ok),
    .data_ok     (inst_sram_data_ok),
    .rdata       (inst_sram_rdata),

    .search_op   (inst_search_op),
    .paddr       (inst_sram_addr),
    .access_type (inst_access_type),

    .rd_req     (ICache_mem_rd_req),
    .rd_type    (ICache_mem_rd_type),
    .rd_addr    (ICache_mem_rd_addr),
    .rd_rdy     (ICache_mem_rd_rdy),
    .ret_valid  (ICache_mem_ret_valid),
    .ret_last   ({1'b0, ICache_mem_ret_last}),
    .ret_data   (ICache_mem_ret_data),
    .wr_req     (),
    .wr_type    (),
    .wr_addr    (),
    .wr_wstrb   (),
    .wr_data    (),
    .wr_rdy     (1'b1)
);

cache d_cache(
    .clk         (clk         ),
    .reset       (reset       ),
    .valid       (data_sram_req),
    .op          (data_op),
    .vaddr       (E_alu_result),
    .access_size ({1'b0,data_sram_size}),
    .wstrb       (data_sram_wstrb),
    .wdata       (data_sram_wdata),
    .addr_ok     (data_sram_addr_ok),
    .data_ok     (data_sram_data_ok),
    .rdata       (data_sram_rdata),

    .search_op   (data_search_op),
    .paddr       (data_sram_addr),
    .access_type (data_access_type),

    .rd_req     (DCache_mem_rd_req),
    .rd_type    (DCache_mem_rd_type),
    .rd_addr    (DCache_mem_rd_addr),
    .rd_rdy     (DCache_mem_rd_rdy),
    .ret_valid  (DCache_mem_ret_valid),
    .ret_last   ({1'b0, DCache_mem_ret_last}),
    .ret_data   (DCache_mem_ret_data),
    .wr_req     (DCache_mem_wr_req),
    .wr_type    (DCache_mem_wr_type),
    .wr_addr    (DCache_mem_wr_addr),
    .wr_wstrb   (DCache_mem_wr_wstrb),
    .wr_data    (DCache_mem_wr_data),
    .wr_rdy     (DCache_mem_wr_rdy)
);

// 分支预测
predict_local u_predict(
    .clk               (clk               ),
    .reset             (reset             ),

    .inst_fetch        (Pre_to_F_valid & F_ready),
    .fetch_pc          (Pre_PC            ),
    .btb_pc            (F_btb_pc        ),
    .btb_taken         (F_btb_taken     ), 
    .btb_enable        (F_btb_enable     ),
    .btb_index         (F_btb_index      ),

    .operate_enable    (D_operate_enable    ),
    .ras_push_call     (D_ras_push_call     ),
    .ras_pop_return    (D_ras_pop_return    ),
    .operate_pc        (D_operate_pc        ),
    .operate_btb_index (D_operate_btb_index ),
    .add_entry         (D_add_entry         ),
    .delete_entry      (D_delete_entry      ),
    .right_target      (D_right_target      ),
    .target_error      (D_target_error      ),
    .predict_error     (D_predict_error     ),
    .predict_correct   (D_predict_correct   ),
    .right_orien       (D_right_orien       )
);


endmodule //mycpu_top
