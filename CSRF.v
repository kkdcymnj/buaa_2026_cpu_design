`include "constant.v"
`include "instr_code.v"

module CSRF #(
    parameter TLBNUM = 16
) (
    input  wire clk,
    input  wire reset,

    input  wire [`csr_addr_width-1:0] csrAddr,
    input  wire [`csr_addr_width-1:0] csrReadAddr,
    input  wire writeEnable,
    input  wire [31:0]  writeMask,
    input  wire [31:0]  writeData,
    output wire [31:0]  readData,

    input  wire [31:0]  PC,
    input  wire errorReturn,
    input  wire [7:0]   hardwareInt,
    input  wire [1:0]   softwareInt,
    input  wire interProcessorInt,
    input  wire [`exception_width-1:0]  exception, 
    output wire [31:0]  returnAddr,
    output wire [31:0]  entry,
    output wire request,
    output wire interrupt, 

    input  wire [31:0]  vAddr,

    // TLB signals
    input  wire [`TLB_OP_READ:`TLB_OP_SRCH] TLB_operation,
    input  wire                             TLB_s_hit,
    input  wire [  $clog2(TLBNUM)-1:0] TLB_s_index,
    input  wire [        `TLBEHI_WIDTH-1:0] TLB_r_hi,
    input  wire [        `TLBELO_WIDTH-1:0] TLB_r_lo0,
    input  wire [        `TLBELO_WIDTH-1:0] TLB_r_lo1,
    output wire [  $clog2(TLBNUM)-1:0] TLB_rw_index,
    output wire [        `TLBEHI_WIDTH-1:0] TLB_sw_hi,
    output wire [        `TLBELO_WIDTH-1:0] TLB_w_lo0,
    output wire [        `TLBELO_WIDTH-1:0] TLB_w_lo1,
    output wire [  $clog2(TLBNUM)-1:0] TLB_f_index,
    // inst / data access signals
    output wire                             da,
    output wire                             pg,
    output wire [                      9:0] asid,
    output wire [                      1:0] plv,
    output wire [                      1:0] datf,
    output wire [                      1:0] datm,
    // inst access signals
    output wire [                      1:0] plv0,
    output wire [  `CSR_DMW_PSEG_WIDTH-1:0] pseg0,
    output wire [  `CSR_DMW_VSEG_WIDTH-1:0] vseg0,
    output wire [  `CSR_DMW_MAT_WIDTH-1:0] mat0,
    // data access signals
    output wire [                      1:0] plv1,
    output wire [  `CSR_DMW_PSEG_WIDTH-1:0] pseg1,
    output wire [  `CSR_DMW_VSEG_WIDTH-1:0] vseg1,
    output wire [  `CSR_DMW_MAT_WIDTH-1:0] mat1,
    // counter
    output wire [31:0] highCnt_out, 
    output wire [31:0] lowCnt_out,

    output wire llbit,
    input  wire llbit_write_enable,
    input  wire llbit_write_data,
    input  wire [31:0] E_paddr,
    input  wire [31:0] W_paddr,

    input  wire [$clog2(TLBNUM)-1:0] tlb_plru_victim_entry
);

wire [31:0] highCnt;
wire [31:0] lowCnt;

assign highCnt_out = highCnt;
assign lowCnt_out = lowCnt;

StableCounter u_StableCounter(
    .clk     (clk     ),
    .reset   (reset   ),
    .highCnt (highCnt ),
    .lowCnt  (lowCnt  )
);

wire [63:0] counter = {highCnt, lowCnt};

reg  [               31:0] CRMD;
reg  [               31:0] PRMD;
reg  [               31:0] ECFG;
reg  [               31:0] ESTAT;
reg  [               31:0] ERA;
reg  [               31:0] BADV;
reg  [               31:0] EENTRY;
reg  [               31:0] TLBIDX;
reg  [               31:0] TLBEHI;
reg  [               31:0] TLBELO0;
reg  [               31:0] TLBELO1;
reg  [               31:0] ASID;
reg  [               31:0] PGDL;
reg  [               31:0] PGDH;
wire [               31:0] PGD;
reg  [               31:0] SAVE      [3:0];
reg  [               31:0] LLBCTL;
reg  [               31:0] TID;
reg  [               31:0] TCFG;
reg  [               31:0] TVAL;
reg [               31:0] TICLR;
reg  [               31:0] TLBRENTRY;
reg  [               31:0] DMW       [1:0];

initial begin
    CRMD <= 32'b0;
    PRMD <= 32'b0;
    ECFG <= 32'b0;
    ESTAT <= 32'b0;
    ERA <= 32'b0;
    BADV <= 32'b0;
    EENTRY <= 32'b0;
    TLBIDX <= 32'b0;
    TLBEHI <= 32'b0;
    TLBELO0 <= 32'b0;
    TLBELO1 <= 32'b0;
    ASID <= 32'b0;
    PGDL <= 32'b0;
    PGDH <= 32'b0;
    SAVE[0] <= 32'b0;
    SAVE[1] <= 32'b0;
    SAVE[2] <= 32'b0;
    SAVE[3] <= 32'b0;
    LLBCTL <= 32'b0;
    TID <= 32'b0;
    TCFG <= 32'b0;
    TVAL <= 32'b0;
    TLBRENTRY <= 32'b0;
    DMW[0] <= 32'b0;
    DMW[1] <= 32'b0;
end

wire [   `ETYPE_WIDTH-1:0] etype;
wire [   `ECODE_WIDTH-1:0] ecode;
wire [`ESUBCODE_WIDTH-1:0] esubcode;

assign etype = exception[`EXCEPTION_INT] ? 6'd1 << `ETYPE_INT :
                exception[`EXCEPTION_ADEF] ? 6'd1 << `ETYPE_FETCH_ADEF :
                exception[`EXCEPTION_PIF] | exception[`EXCEPTION_F_PPI] |
                exception[`EXCEPTION_F_TLBR] ? 6'd1 << `ETYPE_FETCH_TLB :
                |exception[`EXCEPTION_IPE:`EXCEPTION_SYS] ? 6'd1 << `ETYPE_DECODE :
                exception[`EXCEPTION_ALE] ? 6'd1 << `ETYPE_EXECUTE_ALE :
                |exception[`EXCEPTION_PIS:`EXCEPTION_PIL] | exception[`EXCEPTION_PME] |
                exception[`EXCEPTION_M_PPI] | exception[`EXCEPTION_M_TLBR] ?
                6'd1 << `ETYPE_EXECUTE_TLB : `ETYPE_WIDTH'b0;
assign ecode = exception[`EXCEPTION_INT] ? `ECODE_INT :
                exception[`EXCEPTION_ADEF] ? `ECODE_ADEF :
                exception[`EXCEPTION_ADEM] ? `ECODE_ADEM :
                exception[`EXCEPTION_PIF] ? `ECODE_PIF :
                exception[`EXCEPTION_F_PPI] ? `ECODE_PPI :
                exception[`EXCEPTION_F_TLBR] ? `ECODE_TLBR :
                exception[`EXCEPTION_SYS] ? `ECODE_SYS  :
                exception[`EXCEPTION_BRK] ? `ECODE_BRK  :
                exception[`EXCEPTION_INE] ? `ECODE_INE  :
                exception[`EXCEPTION_IPE] ? `ECODE_IPE  :
                exception[`EXCEPTION_ALE] ? `ECODE_ALE  :
                exception[`EXCEPTION_PIL] ? `ECODE_PIL :
                exception[`EXCEPTION_PIS] ? `ECODE_PIS :
                exception[`EXCEPTION_PME] ? `ECODE_PME :
                exception[`EXCEPTION_M_PPI] ? `ECODE_PPI :
                exception[`EXCEPTION_M_TLBR] ? `ECODE_TLBR : `ECODE_WIDTH'b0;
assign esubcode = {8'b0, exception[`EXCEPTION_ADEM]};

assign request = |exception; //外部中断+内部异常

// CRMD
always @(posedge clk ) begin
    if (reset) begin
        CRMD[`CSR_CRMD_PLV] <= 2'b0;
        CRMD[`CSR_CRMD_IE] <= 1'b0;
        CRMD[`CSR_CRMD_DA] <= 1'b1;
        CRMD[`CSR_CRMD_PG] <= 1'b0;
        CRMD[`CSR_CRMD_DATF] <= 2'b0;
        CRMD[`CSR_CRMD_DATM] <= 2'b0;
        CRMD[`CSR_CRMD_0] <= `CSR_CRMD_0_WIDTH'b0;
    end
    else if(request) begin
        CRMD[`CSR_CRMD_PLV] <= 2'b0;
        CRMD[`CSR_CRMD_IE] <= 2'b0;
        if (etype[`ETYPE_FETCH_TLB] & exception[`EXCEPTION_F_TLBR] |
            etype[`ETYPE_EXECUTE_TLB] & exception[`EXCEPTION_M_TLBR]) begin
            CRMD[`CSR_CRMD_DA] <= 1'b1;
            CRMD[`CSR_CRMD_PG] <= 1'b0;
        end
    end
    else if(errorReturn) begin
        CRMD[`CSR_CRMD_PLV] <= PRMD[`CSR_PRMD_PPLV];
        CRMD[`CSR_CRMD_IE] <= PRMD[`CSR_PRMD_PIE];
        if (ESTAT[`CSR_ESTAT_ECODE] == `ECODE_TLBR) begin
            CRMD[`CSR_CRMD_DA] <= 1'b0;
            CRMD[`CSR_CRMD_PG] <= 1'b1;
        end
    end
    else if(writeEnable && csrAddr == `CSR_CRMD) begin
        CRMD[`CSR_CRMD_PLV] <= 
            (writeMask[`CSR_CRMD_PLV] & writeData[`CSR_CRMD_PLV]) | 
            (~writeMask[`CSR_CRMD_PLV] & CRMD[`CSR_CRMD_PLV]);
        CRMD[`CSR_CRMD_IE] <= 
            (writeMask[`CSR_CRMD_IE] & writeData[`CSR_CRMD_IE]) | 
            (~writeMask[`CSR_CRMD_IE] & CRMD[`CSR_CRMD_IE]);
        CRMD[`CSR_CRMD_DA]   <= 
            (writeMask[`CSR_CRMD_DA] & writeData[`CSR_CRMD_DA]) | 
            (~writeMask[`CSR_CRMD_DA] & CRMD[`CSR_CRMD_DA]);
        CRMD[`CSR_CRMD_PG]   <= 
            (writeMask[`CSR_CRMD_PG] & writeData[`CSR_CRMD_PG]) | 
            (~writeMask[`CSR_CRMD_PG] & CRMD[`CSR_CRMD_PG]);
        CRMD[`CSR_CRMD_DATF] <= 
            (writeMask[`CSR_CRMD_DATF] & writeData[`CSR_CRMD_DATF]) | 
            (~writeMask[`CSR_CRMD_DATF] & CRMD[`CSR_CRMD_DATF]);
        CRMD[`CSR_CRMD_DATM] <= 
            (writeMask[`CSR_CRMD_DATM] & writeData[`CSR_CRMD_DATM]) | 
            (~writeMask[`CSR_CRMD_DATM] & CRMD[`CSR_CRMD_DATM]);
    end
    CRMD[`CSR_CRMD_0] <= `CSR_CRMD_0_WIDTH'b0;
end

//PRMD
always @(posedge clk ) begin
    if (reset) begin
        PRMD[31:3] <= 29'b0;
    end
    else if(request) begin
        PRMD[`CSR_PRMD_PPLV] <= CRMD[`CSR_CRMD_PLV];
        PRMD[`CSR_PRMD_PIE] <= CRMD[`CSR_CRMD_IE];
    end
    else if(writeEnable && csrAddr == `CSR_PRMD) begin
        PRMD[`CSR_PRMD_PPLV] <= 
            (writeMask[`CSR_PRMD_PPLV] & writeData[`CSR_PRMD_PPLV]) | 
            (~writeMask[`CSR_PRMD_PPLV] & PRMD[`CSR_PRMD_PPLV]);
        PRMD[`CSR_PRMD_PIE] <= 
            (writeMask[`CSR_PRMD_PIE] & writeData[`CSR_PRMD_PIE]) | 
            (~writeMask[`CSR_PRMD_PIE] & PRMD[`CSR_PRMD_PIE]);
    end
    PRMD[`CSR_PRMD_0] <= `CSR_PRMD_0_WIDTH'b0;
end

//ECFG
always @(posedge clk ) begin
    if (reset) begin
        ECFG <= 32'b0;
    end
    else if(writeEnable && csrAddr == `CSR_ECFG) begin
        ECFG[12:0] <=   writeMask[12:0] & writeData[12:0] |
                        ~writeMask[12:0] & writeData[12:0];
    end
    // TODO：从gitee下载的exp16包中，golden-trace可能有问题，ECFG恒为0的位会被写入1
    ECFG[`CSR_ECFG_0_LO] <= `CSR_ECFG_0_LO_WIDTH'b0;
    ECFG[`CSR_ECFG_0_HI] <= `CSR_ECFG_0_HI_WIDTH'b0;
end

//ESTAT
always @(posedge clk) begin
    if (reset) begin
        ESTAT[`CSR_ESTAT_IS_1_0] <= 2'b0;
        ESTAT[`CSR_ESTAT_0_LO] <= `CSR_ESTAT_0_LO_WIDTH'b0;
        ESTAT[`CSR_ESTAT_IS_12] <= 1'b0;
        ESTAT[`CSR_ESTAT_0_MD] <= `CSR_ESTAT_0_MD_WIDTH'b0;
        ESTAT[`CSR_ESTAT_ECODE] <= `CSR_ESTAT_ECODE_WIDTH'b0;
        ESTAT[`CSR_ESTAT_0_HI] <= 1'b0;
    end
    else if(writeEnable && csrAddr == `CSR_ESTAT) begin
        ESTAT[`CSR_ESTAT_IS_1_0] <= 
            (writeMask[`CSR_ESTAT_IS_1_0] & writeData[`CSR_ESTAT_IS_1_0]) | 
            (~writeMask[`CSR_ESTAT_IS_1_0] & ESTAT[`CSR_ESTAT_IS_1_0]);
    end
    
    if (request) begin
        ESTAT[`CSR_ESTAT_ECODE]    <= ecode;
        ESTAT[`CSR_ESTAT_ESUBCODE] <= esubcode;
    end
    
    ESTAT[`CSR_ESTAT_IS_9_2] <= hardwareInt;
    ESTAT[`CSR_ESTAT_IS_12] <= interProcessorInt;

    //TIMER INTERRUPT
    if (TCFG[`CSR_TCFG_EN] & ~|TVAL[`CSR_TVAL_TVAL]) begin // 倒计时为0则置中断
        ESTAT[`CSR_ESTAT_IS_11] <= 1'b1;
    end
    else if (writeEnable & csrAddr == `CSR_TICLR &
                writeMask[`CSR_TICLR_CLR] & writeData[`CSR_TICLR_CLR]) begin
        ESTAT[`CSR_ESTAT_IS_11] <= 1'b0;    // 给TICLR置1以去除中断
    end

    ESTAT[`CSR_ESTAT_0_LO]  <= `CSR_ESTAT_0_LO_WIDTH'b0;
    ESTAT[`CSR_ESTAT_0_MD]  <= `CSR_ESTAT_0_MD_WIDTH'b0;
    ESTAT[`CSR_ESTAT_0_HI] <= `CSR_ESTAT_0_HI_WIDTH'b0;
end

//ERA
always @(posedge clk ) begin
    if (request) begin
        ERA[`CSR_ERA_PC] <= PC;
    end else if (writeEnable & csrAddr == `CSR_ERA) begin
        ERA[`CSR_ERA_PC] <= 
            (writeMask[`CSR_ERA_PC] & writeData[`CSR_ERA_PC]) | 
            (~writeMask[`CSR_ERA_PC] & ERA[`CSR_ERA_PC]);
    end
end

//BADV
always @(posedge clk) begin
    if (etype[`ETYPE_FETCH_ADEF] | etype[`ETYPE_FETCH_TLB] |
        etype[`ETYPE_EXECUTE_ALE] | etype[`ETYPE_EXECUTE_TLB] |
        exception[`EXCEPTION_ADEM]) begin
        BADV[`CSR_BADV_VADDR] <= (exception[`EXCEPTION_PIF] |
                                    exception[`EXCEPTION_F_PPI] |
                                    exception[`EXCEPTION_ADEF] |
                                    exception[`EXCEPTION_F_TLBR]) ? PC :
                                    vAddr;
    end else if (writeEnable && csrAddr == `CSR_BADV) begin
        BADV[`CSR_BADV_VADDR] <= 
            (writeMask[`CSR_BADV_VADDR] & writeData[`CSR_BADV_VADDR]) | 
            (~writeMask[`CSR_BADV_VADDR] & BADV[`CSR_BADV_VADDR]);
    end
end

//EENTRY
always @(posedge clk ) begin
    if (reset) begin
        EENTRY[`CSR_EENTRY_0] <= `CSR_EENTRY_0_WIDTH'b0;
    end
    else if (writeEnable && csrAddr == `CSR_EENTRY) begin
        EENTRY[`CSR_EENTRY_VA] <= 
            (writeMask[`CSR_EENTRY_VA] & writeData[`CSR_EENTRY_VA]) | 
            (~writeMask[`CSR_EENTRY_VA] & EENTRY[`CSR_EENTRY_VA]);
    end
    EENTRY[`CSR_EENTRY_0] <= `CSR_EENTRY_0_WIDTH'b0;
end

//SAVE
always @(posedge clk ) begin
    if (writeEnable) begin
        if (csrAddr == `CSR_SAVE0) begin
            SAVE[0] <= 
                (writeMask & writeData) | 
                (~writeMask & SAVE[0]);
        end
        if (csrAddr == `CSR_SAVE1) begin
            SAVE[1] <= 
                (writeMask & writeData) | 
                (~writeMask & SAVE[1]);
        end
        if (csrAddr == `CSR_SAVE2) begin
            SAVE[2] <= 
                (writeMask & writeData) | 
                (~writeMask & SAVE[2]);
        end
        if (csrAddr == `CSR_SAVE3) begin
            SAVE[3] <= 
                (writeMask & writeData) | 
                (~writeMask & SAVE[3]);
        end
    end
end

//TID
always @(posedge clk ) begin
    if (reset) begin
        TID[`CSR_TID_TID] <= {22'b0, `COREID};
    end 
    else if(writeEnable && csrAddr == `CSR_TID) begin
        TID[`CSR_TID_TID] <= 
            (writeMask[`CSR_TID_TID] & writeData[`CSR_TID_TID]) | 
            (~writeMask[`CSR_TID_TID] & TID[`CSR_TID_TID]);
    end
end

//TCFG
always @(posedge clk ) begin
    if (reset) begin
        TCFG[`CSR_TCFG_EN] <= 1'b0;
    end 
    else if (writeEnable & csrAddr == `CSR_TCFG) begin
        TCFG[`CSR_TCFG_EN] <= 
            (writeMask[`CSR_TCFG_EN] & writeData[`CSR_TCFG_EN]) | 
            (~writeMask[`CSR_TCFG_EN] & TCFG[`CSR_TCFG_EN]);
    end

    if (writeEnable & csrAddr == `CSR_TCFG) begin
        TCFG[`CSR_TCFG_PERIODIC] <= 
            (writeMask[`CSR_TCFG_PERIODIC] & writeData[`CSR_TCFG_PERIODIC]) | 
            (~writeMask[`CSR_TCFG_PERIODIC] & TCFG[`CSR_TCFG_PERIODIC]);
        TCFG[`CSR_TCFG_INITVAL] <= 
            (writeMask[`CSR_TCFG_INITVAL] & writeData[`CSR_TCFG_INITVAL]) | 
            (~writeMask[`CSR_TCFG_INITVAL] & TCFG[`CSR_TCFG_INITVAL]);
    end
end

//TVAL
wire [31:0] TCFG_set_data = 
    {TCFG[`CSR_TCFG_INITVAL], TCFG[`CSR_TCFG_PERIODIC], TCFG[`CSR_TCFG_EN]};
wire [31:0] TVAL_next = 
    (writeMask[31:0] & writeData[31:0]) | (~writeMask[31:0] & TCFG_set_data);

always @(posedge clk ) begin
    if (reset) begin
        TVAL[`CSR_TVAL_TVAL] <= `CSR_TVAL_TVAL_INIT;
    end
    else if(writeEnable && csrAddr == `CSR_TCFG) begin
        if (writeData[`CSR_TCFG_EN]) begin
            TVAL[`CSR_TVAL_TVAL] <= {writeData[`CSR_TCFG_INITVAL], 2'b0};
        end else begin
            TVAL[`CSR_TVAL_TVAL] <= 32'hffffffff;
        end
    end
    else if(TCFG[`CSR_TCFG_EN] & (~&TVAL[`CSR_TVAL_TVAL])) begin  // 倒计时中途
        if ((~|TVAL[`CSR_TVAL_TVAL]) & TCFG[`CSR_TCFG_PERIODIC]) begin
            TVAL[`CSR_TVAL_TVAL] <= {TCFG[`CSR_TCFG_INITVAL], 2'b00};
        end else begin
            TVAL[`CSR_TVAL_TVAL] <= TVAL[`CSR_TVAL_TVAL] - 32'd1;
        end
    end
end

//TICLR读出值恒为0
always @(posedge clk ) begin
    TICLR <= 0;
end

always @(posedge clk) begin
    if (reset) begin
        TLBIDX[`CSR_TLBIDX_NE] <= 1'b0;
    end else if (writeEnable & csrAddr == `CSR_TLBIDX) begin
        TLBIDX[`CSR_TLBIDX_INDEX] <= 
                (writeMask[`CSR_TLBIDX_INDEX] & writeData[`CSR_TLBIDX_INDEX]) | 
                (~writeMask[`CSR_TLBIDX_INDEX] & TLBIDX[`CSR_TLBIDX_INDEX]);
        TLBIDX[`CSR_TLBIDX_PS]    <= 
                (writeMask[`CSR_TLBIDX_PS] & writeData[`CSR_TLBIDX_PS]) | 
                (~writeMask[`CSR_TLBIDX_PS] & TLBIDX[`CSR_TLBIDX_PS]);
        TLBIDX[`CSR_TLBIDX_NE]    <= 
                (writeMask[`CSR_TLBIDX_NE] & writeData[`CSR_TLBIDX_NE]) | 
                (~writeMask[`CSR_TLBIDX_NE] & TLBIDX[`CSR_TLBIDX_NE]);
    end else if (TLB_operation[`TLB_OP_SRCH]) begin
        if (TLB_s_hit) begin
            TLBIDX[`CSR_TLBIDX_INDEX] <= TLB_s_index;
            TLBIDX[`CSR_TLBIDX_NE]    <= 1'b0;
        end else begin
            TLBIDX[`CSR_TLBIDX_NE] <= 1'b1;
        end
    end else if (TLB_operation[`TLB_OP_READ]) begin
        if (TLB_r_hi[`TLBEHI_E]) begin
            TLBIDX[`CSR_TLBIDX_PS] <= TLB_r_hi[`TLBEHI_PS];
            TLBIDX[`CSR_TLBIDX_NE] <= 1'b0;
        end else begin
            TLBIDX[`CSR_TLBIDX_PS] <= `CSR_TLBIDX_PS_WIDTH'b0;
            TLBIDX[`CSR_TLBIDX_NE] <= 1'b1;
        end
    end
    TLBIDX[`CSR_TLBIDX_0_LO] <= 0;  // (23-$clog2(`TLB_ENTRIES)+1)'b0;
    TLBIDX[`CSR_TLBIDX_0_HI] <= `CSR_TLBIDX_0_HI_WIDTH'b0;
end

always @(posedge clk) begin
    TLBEHI[`CSR_TLBEHI_0] <= `CSR_TLBEHI_0_WIDTH'b0;
    if (writeEnable & csrAddr == `CSR_TLBEHI) begin
        TLBEHI[`CSR_TLBEHI_VPPN] <= 
            (writeMask[`CSR_TLBEHI_VPPN] & writeData[`CSR_TLBEHI_VPPN]) | 
            (~writeMask[`CSR_TLBEHI_VPPN] & TLBEHI[`CSR_TLBEHI_VPPN]);
    end else if (etype[`ETYPE_FETCH_TLB] | etype[`ETYPE_EXECUTE_TLB]) begin
        TLBEHI[`CSR_TLBEHI_VPPN] <= exception[`EXCEPTION_PIF] |
                                    exception[`EXCEPTION_F_PPI] |
                                    exception[`EXCEPTION_F_TLBR] ? PC[`CSR_TLBEHI_VPPN] :
                                    vAddr[`CSR_TLBEHI_VPPN];
    end else if (TLB_operation[`TLB_OP_READ]) begin
        if (TLB_r_hi[`TLBEHI_E]) begin
            TLBEHI[`CSR_TLBEHI_VPPN] <= TLB_r_hi[`TLBEHI_VPPN];
        end else begin
            TLBEHI[`CSR_TLBEHI_VPPN] <= `CSR_TLBEHI_VPPN_WIDTH'b0;
        end
    end
end

always @(posedge clk) begin
    if (writeEnable && csrAddr == `CSR_TLBELO0) begin
        TLBELO0[`CSR_TLBELO0_V]   <= 
            (writeMask[`CSR_TLBELO0_V] & writeData[`CSR_TLBELO0_V]) | 
            (~writeMask[`CSR_TLBELO0_V] & TLBELO0[`CSR_TLBELO0_V]);
        TLBELO0[`CSR_TLBELO0_D]   <= 
            (writeMask[`CSR_TLBELO0_D] & writeData[`CSR_TLBELO0_D]) | 
            (~writeMask[`CSR_TLBELO0_D] & TLBELO0[`CSR_TLBELO0_D]);
        TLBELO0[`CSR_TLBELO0_PLV] <= 
            (writeMask[`CSR_TLBELO0_PLV] & writeData[`CSR_TLBELO0_PLV]) | 
            (~writeMask[`CSR_TLBELO0_PLV] & TLBELO0[`CSR_TLBELO0_PLV]);
        TLBELO0[`CSR_TLBELO0_MAT] <= 
            (writeMask[`CSR_TLBELO0_MAT] & writeData[`CSR_TLBELO0_MAT]) | 
            (~writeMask[`CSR_TLBELO0_MAT] & TLBELO0[`CSR_TLBELO0_MAT]);
        TLBELO0[`CSR_TLBELO0_G]   <= 
            (writeMask[`CSR_TLBELO0_G] & writeData[`CSR_TLBELO0_G]) | 
            (~writeMask[`CSR_TLBELO0_G] & TLBELO0[`CSR_TLBELO0_G]);
        TLBELO0[`CSR_TLBELO0_PPN] <= 
            (writeMask[`CSR_TLBELO0_PPN] & writeData[`CSR_TLBELO0_PPN]) | 
            (~writeMask[`CSR_TLBELO0_PPN] & TLBELO0[`CSR_TLBELO0_PPN]);
    end else if (TLB_operation[`TLB_OP_READ]) begin
        if (TLB_r_hi[`TLBEHI_E]) begin
            TLBELO0[`CSR_TLBELO0_V]   <= TLB_r_lo0[`TLBELO_V];
            TLBELO0[`CSR_TLBELO0_D]   <= TLB_r_lo0[`TLBELO_D];
            TLBELO0[`CSR_TLBELO0_PLV] <= TLB_r_lo0[`TLBELO_PLV];
            TLBELO0[`CSR_TLBELO0_MAT] <= TLB_r_lo0[`TLBELO_MAT];
            TLBELO0[`CSR_TLBELO0_G]   <= TLB_r_hi[`TLBEHI_G];
            TLBELO0[`CSR_TLBELO0_PPN] <= TLB_r_lo0[`TLBELO_PPN];
        end else begin
            TLBELO0[`CSR_TLBELO0_V]   <= 1'b0;
            TLBELO0[`CSR_TLBELO0_D]   <= 1'b0;
            TLBELO0[`CSR_TLBELO0_PLV] <= 2'b0;
            TLBELO0[`CSR_TLBELO0_MAT] <= 2'b0;
            TLBELO0[`CSR_TLBELO0_G]   <= 1'b0;
            TLBELO0[`CSR_TLBELO0_PPN] <= 0;  // (`PALEN-5-8+1)'b0;
        end
    end
    TLBELO0[`CSR_TLBELO0_0_LO] <= `CSR_TLBELO0_0_LO_WIDTH'b0;
    TLBELO0[`CSR_TLBELO0_0_HI] <= 0;  // (31-`TLBELO_WIDTH+1)'b0;
end

always @(posedge clk) begin
    if (writeEnable && csrAddr == `CSR_TLBELO1) begin
        TLBELO1[`CSR_TLBELO1_V]   <= 
            (writeMask[`CSR_TLBELO1_V] & writeData[`CSR_TLBELO1_V]) | 
            (~writeMask[`CSR_TLBELO1_V] & TLBELO1[`CSR_TLBELO1_V]);
        TLBELO1[`CSR_TLBELO1_D]   <= 
            (writeMask[`CSR_TLBELO1_D] & writeData[`CSR_TLBELO1_D]) | 
            (~writeMask[`CSR_TLBELO1_D] & TLBELO1[`CSR_TLBELO1_D]);
        TLBELO1[`CSR_TLBELO1_PLV] <= 
            (writeMask[`CSR_TLBELO1_PLV] & writeData[`CSR_TLBELO1_PLV]) | 
            (~writeMask[`CSR_TLBELO1_PLV] & TLBELO1[`CSR_TLBELO1_PLV]);
        TLBELO1[`CSR_TLBELO1_MAT] <= 
            (writeMask[`CSR_TLBELO1_MAT] & writeData[`CSR_TLBELO1_MAT]) | 
            (~writeMask[`CSR_TLBELO1_MAT] & TLBELO1[`CSR_TLBELO1_MAT]);
        TLBELO1[`CSR_TLBELO1_G]   <= 
            (writeMask[`CSR_TLBELO1_G] & writeData[`CSR_TLBELO1_G]) | 
            (~writeMask[`CSR_TLBELO1_G] & TLBELO1[`CSR_TLBELO1_G]);
        TLBELO1[`CSR_TLBELO1_PPN] <= 
            (writeMask[`CSR_TLBELO1_PPN] & writeData[`CSR_TLBELO1_PPN]) | 
            (~writeMask[`CSR_TLBELO1_PPN] & TLBELO1[`CSR_TLBELO1_PPN]);
    end else if (TLB_operation[`TLB_OP_READ]) begin
        if (TLB_r_hi[`TLBEHI_E]) begin
            TLBELO1[`CSR_TLBELO1_V]   <= TLB_r_lo1[`TLBELO_V];
            TLBELO1[`CSR_TLBELO1_D]   <= TLB_r_lo1[`TLBELO_D];
            TLBELO1[`CSR_TLBELO1_PLV] <= TLB_r_lo1[`TLBELO_PLV];
            TLBELO1[`CSR_TLBELO1_MAT] <= TLB_r_lo1[`TLBELO_MAT];
            TLBELO1[`CSR_TLBELO1_G]   <= TLB_r_hi[`TLBEHI_G];
            TLBELO1[`CSR_TLBELO1_PPN] <= TLB_r_lo1[`TLBELO_PPN];
        end else begin
            TLBELO1[`CSR_TLBELO1_V]   <= 1'b0;
            TLBELO1[`CSR_TLBELO1_D]   <= 1'b0;
            TLBELO1[`CSR_TLBELO1_PLV] <= 2'b0;
            TLBELO1[`CSR_TLBELO1_MAT] <= 2'b0;
            TLBELO1[`CSR_TLBELO1_G]   <= 1'b0;
            TLBELO1[`CSR_TLBELO1_PPN] <= 0;  // (`PALEN-5-8+1)'b0;
        end
    end
    TLBELO1[`CSR_TLBELO1_0_LO] <= `CSR_TLBELO1_0_LO_WIDTH'b0;
    TLBELO1[`CSR_TLBELO1_0_HI] <= 0;  // (31-`TLBELO_WIDTH+1)'b0;
end

always @(posedge clk) begin
    if (writeEnable && csrAddr == `CSR_ASID) begin
        ASID[`CSR_ASID_ASID] <= 
            (writeMask[`CSR_ASID_ASID] & writeData[`CSR_ASID_ASID]) | 
            (~writeMask[`CSR_ASID_ASID] & ASID[`CSR_ASID_ASID]);
    end else if (TLB_operation[`TLB_OP_READ]) begin
        if (TLB_r_hi[`TLBEHI_E]) begin
            ASID[`CSR_ASID_ASID] <= TLB_r_hi[`TLBEHI_ASID];
        end else begin
            ASID[`CSR_ASID_ASID] <= `CSR_ASID_ASID_WIDTH'b0;
        end
    end
    ASID[`CSR_ASID_0_LO]     <= `CSR_ASID_0_LO_WIDTH'b0;
    ASID[`CSR_ASID_ASIDBITS] <= `CSR_ASID_ASIDBITS_WIDTH'd`CSR_ASID_ASID_WIDTH;
    ASID[`CSR_ASID_0_HI]     <= `CSR_ASID_0_HI_WIDTH'b0;
end

always @(posedge clk) begin
    PGDL[`CSR_PGDL_0] <= `CSR_PGDL_0_WIDTH'b0;
    if (writeEnable && csrAddr == `CSR_PGDL) begin
        PGDL[`CSR_PGDL_BASE] <= 
            (writeMask[`CSR_PGDL_BASE] & writeData[`CSR_PGDL_BASE]) | 
            (~writeMask[`CSR_PGDL_BASE] & PGDL[`CSR_PGDL_BASE]);
    end
end

always @(posedge clk) begin
    PGDH[`CSR_PGDH_0] <= `CSR_PGDH_0_WIDTH'b0;
    if (writeEnable && csrAddr == `CSR_PGDH) begin
        PGDH[`CSR_PGDH_BASE] <= 
            (writeMask[`CSR_PGDH_BASE] & writeData[`CSR_PGDH_BASE]) | 
            (~writeMask[`CSR_PGDH_BASE] & PGDH[`CSR_PGDH_BASE]);
    end
end

assign PGD = BADV[31] ? PGDH : PGDL;

 always @(posedge clk) begin
    DMW[0][`CSR_DMW_0_LO] <= `CSR_DMW_0_LO_WIDTH'b0;
    DMW[0][`CSR_DMW_0_MD] <= `CSR_DMW_0_MD_WIDTH'b0;
    DMW[0][`CSR_DMW_0_HI] <= `CSR_DMW_0_HI_WIDTH'b0;
    if (reset) begin
        DMW[0][`CSR_DMW_PLV0] <= 1'b0;
        DMW[0][`CSR_DMW_PLV3] <= 1'b0;
    end else if (writeEnable && csrAddr == `CSR_DMW0) begin
        DMW[0][`CSR_DMW_PLV0] <= 
            (writeMask[`CSR_DMW_PLV0] & writeData[`CSR_DMW_PLV0]) | 
            (~writeMask[`CSR_DMW_PLV0] & DMW[0][`CSR_DMW_PLV0]);
        DMW[0][`CSR_DMW_PLV3] <= 
            (writeMask[`CSR_DMW_PLV3] & writeData[`CSR_DMW_PLV3]) | 
            (~writeMask[`CSR_DMW_PLV3] & DMW[0][`CSR_DMW_PLV3]);
        DMW[0][`CSR_DMW_MAT]  <= 
            (writeMask[`CSR_DMW_MAT] & writeData[`CSR_DMW_MAT]) | 
            (~writeMask[`CSR_DMW_MAT] & DMW[0][`CSR_DMW_MAT]);
        DMW[0][`CSR_DMW_PSEG] <= 
            (writeMask[`CSR_DMW_PSEG] & writeData[`CSR_DMW_PSEG]) | 
            (~writeMask[`CSR_DMW_PSEG] & DMW[0][`CSR_DMW_PSEG]);
        DMW[0][`CSR_DMW_VSEG] <= 
            (writeMask[`CSR_DMW_VSEG] & writeData[`CSR_DMW_VSEG]) | 
            (~writeMask[`CSR_DMW_VSEG] & DMW[0][`CSR_DMW_VSEG]);
    end
    DMW[1][`CSR_DMW_0_LO] <= `CSR_DMW_0_LO_WIDTH'b0;
    DMW[1][`CSR_DMW_0_MD] <= `CSR_DMW_0_MD_WIDTH'b0;
    DMW[1][`CSR_DMW_0_HI] <= `CSR_DMW_0_HI_WIDTH'b0;
    if (reset) begin
        DMW[1][`CSR_DMW_PLV0] <= 1'b0;
        DMW[1][`CSR_DMW_PLV3] <= 1'b0;
    end else if (writeEnable && csrAddr == `CSR_DMW1) begin
        DMW[1][`CSR_DMW_PLV0] <= 
            (writeMask[`CSR_DMW_PLV0] & writeData[`CSR_DMW_PLV0]) | 
            (~writeMask[`CSR_DMW_PLV0] & DMW[1][`CSR_DMW_PLV0]);
        DMW[1][`CSR_DMW_PLV3] <= 
            (writeMask[`CSR_DMW_PLV3] & writeData[`CSR_DMW_PLV3]) | 
            (~writeMask[`CSR_DMW_PLV3] & DMW[1][`CSR_DMW_PLV3]);
        DMW[1][`CSR_DMW_MAT]  <= 
            (writeMask[`CSR_DMW_MAT] & writeData[`CSR_DMW_MAT]) | 
            (~writeMask[`CSR_DMW_MAT] & DMW[1][`CSR_DMW_MAT]);
        DMW[1][`CSR_DMW_PSEG] <= 
            (writeMask[`CSR_DMW_PSEG] & writeData[`CSR_DMW_PSEG]) | 
            (~writeMask[`CSR_DMW_PSEG] & DMW[1][`CSR_DMW_PSEG]);
        DMW[1][`CSR_DMW_VSEG] <= 
            (writeMask[`CSR_DMW_VSEG] & writeData[`CSR_DMW_VSEG]) | 
            (~writeMask[`CSR_DMW_VSEG] & DMW[1][`CSR_DMW_VSEG]);
    end
end

always @(posedge clk) begin
    TLBRENTRY[`CSR_TLBRENTRY_0] <= `CSR_TLBRENTRY_0_WIDTH'b0;
    if (writeEnable & csrAddr == `CSR_TLBRENTRY) begin
        TLBRENTRY[`CSR_TLBRENTRY_PA] <= 
            (writeMask[`CSR_TLBRENTRY_PA] & writeData[`CSR_TLBRENTRY_PA]) | 
            (~writeMask[`CSR_TLBRENTRY_PA] & TLBRENTRY[`CSR_TLBRENTRY_PA]);
    end
end

reg [31:4] lladdr;
always @(posedge clk) begin
    if (reset) begin
        LLBCTL[`CSR_LLBCTL_ROLLB] <= 1'b0;
        LLBCTL[`CSR_LLBCTL_KLO]   <= 1'b0;
        lladdr                    <= 0;
    end else if (errorReturn) begin
        if (~LLBCTL[`CSR_LLBCTL_KLO]) begin
            LLBCTL[`CSR_LLBCTL_ROLLB] <= 1'b0;
        end
        LLBCTL[`CSR_LLBCTL_KLO] <= 1'b0;
    end else if (llbit_write_enable) begin
        LLBCTL[`CSR_LLBCTL_ROLLB] <= llbit_write_data;
        if (llbit_write_data) begin
            lladdr <= W_paddr[31:4];
        end
    end else if (writeEnable & csrAddr == `CSR_LLBCTL) begin
        if (writeData[`CSR_LLBCTL_WCLLB]) begin
            LLBCTL[`CSR_LLBCTL_ROLLB] <= 1'b0;
        end
        LLBCTL[`CSR_LLBCTL_KLO] <= 
            (writeMask[`CSR_LLBCTL_KLO] & writeData[`CSR_LLBCTL_KLO]) | 
            (~writeMask[`CSR_LLBCTL_KLO] & LLBCTL[`CSR_LLBCTL_KLO]);
    end
    LLBCTL[`CSR_LLBCTL_WCLLB] <= 1'b0;
    LLBCTL[`CSR_LLBCTL_0]     <= `CSR_LLBCTL_0_WIDTH'b0;
end
assign llbit = (LLBCTL[`CSR_LLBCTL_ROLLB] & lladdr == E_paddr[31:4]);

assign readData = {32{csrReadAddr == `CSR_CRMD}} & CRMD |
                    {32{csrReadAddr == `CSR_PRMD}} & PRMD |
                    {32{csrReadAddr == `CSR_ECFG}} & ECFG |
                    {32{csrReadAddr == `CSR_ESTAT}} & ESTAT |
                    {32{csrReadAddr == `CSR_ERA}} & ERA |
                    {32{csrReadAddr == `CSR_BADV}} & BADV |
                    {32{csrReadAddr == `CSR_EENTRY}} & EENTRY |
                    {32{csrReadAddr == `CSR_TLBIDX}} & TLBIDX |
                    {32{csrReadAddr == `CSR_TLBEHI}} & TLBEHI |
                    {32{csrReadAddr == `CSR_TLBELO0}} & TLBELO0 |
                    {32{csrReadAddr == `CSR_TLBELO1}} & TLBELO1 |
                    {32{csrReadAddr == `CSR_ASID}} & ASID |
                    {32{csrReadAddr == `CSR_PGDL}} & PGDL |
                    {32{csrReadAddr == `CSR_PGDH}} & PGDH |
                    {32{csrReadAddr == `CSR_PGD}} & PGD |
                    {32{csrReadAddr == `CSR_SAVE0}} & SAVE[0] |
                    {32{csrReadAddr == `CSR_SAVE1}} & SAVE[1] |
                    {32{csrReadAddr == `CSR_SAVE2}} & SAVE[2] |
                    {32{csrReadAddr == `CSR_SAVE3}} & SAVE[3] |
                    {32{csrReadAddr == `CSR_LLBCTL}} & LLBCTL |
                    {32{csrReadAddr == `CSR_TID}} & TID |
                    {32{csrReadAddr == `CSR_TCFG}} & TCFG |
                    {32{csrReadAddr == `CSR_TVAL}} & TVAL |
                    {32{csrReadAddr == `CSR_TICLR}} & 0 |
                    {32{csrReadAddr == `CSR_TLBRENTRY}} & TLBRENTRY |
                    {32{csrReadAddr == `CSR_DMW0}} & DMW[0] |
                    {32{csrReadAddr == `CSR_DMW1}} & DMW[1];

assign TLB_rw_index = TLBIDX[`CSR_TLBIDX_INDEX];
assign TLB_sw_hi[`TLBEHI_E] = 
    (ESTAT[`CSR_ESTAT_ECODE] == `ECODE_TLBR) | ~TLBIDX[`CSR_TLBIDX_NE];
assign TLB_sw_hi[`TLBEHI_ASID] = ASID[`CSR_ASID_ASID];
assign TLB_sw_hi[`TLBEHI_G] = TLBELO0[`CSR_TLBELO0_G] & TLBELO1[`CSR_TLBELO1_G];
assign TLB_sw_hi[`TLBEHI_PS] = TLBIDX[`CSR_TLBIDX_PS];
assign TLB_sw_hi[`TLBEHI_VPPN] = TLBEHI[`CSR_TLBEHI_VPPN];
assign TLB_w_lo0[`TLBELO_V] = TLBELO0[`CSR_TLBELO0_V];
assign TLB_w_lo0[`TLBELO_D] = TLBELO0[`CSR_TLBELO0_D];
assign TLB_w_lo0[`TLBELO_MAT] = TLBELO0[`CSR_TLBELO0_MAT];
assign TLB_w_lo0[`TLBELO_PLV] = TLBELO0[`CSR_TLBELO0_PLV];
assign TLB_w_lo0[`TLBELO_PPN] = TLBELO0[`CSR_TLBELO0_PPN];
assign TLB_w_lo1[`TLBELO_V] = TLBELO1[`CSR_TLBELO1_V];
assign TLB_w_lo1[`TLBELO_D] = TLBELO1[`CSR_TLBELO1_D];
assign TLB_w_lo1[`TLBELO_MAT] = TLBELO1[`CSR_TLBELO1_MAT];
assign TLB_w_lo1[`TLBELO_PLV] = TLBELO1[`CSR_TLBELO1_PLV];
assign TLB_w_lo1[`TLBELO_PPN] = TLBELO1[`CSR_TLBELO1_PPN];

// TODO：修正为PLRU法
assign TLB_f_index = /*counter[$clog2(TLBNUM)-1:0]*/tlb_plru_victim_entry;  

assign da = CRMD[`CSR_CRMD_DA];
assign pg = CRMD[`CSR_CRMD_PG];
assign asid = ASID[`CSR_ASID_ASID];
assign plv = CRMD[`CSR_CRMD_PLV];

encoder #(
    .WIDTH(`CSR_DMW_PLV_WIDTH)
) enc_plv0 (
    .in (DMW[0][`CSR_DMW_PLV]),
    .out(plv0)
);
assign pseg0 = DMW[0][`CSR_DMW_PSEG];
assign vseg0 = DMW[0][`CSR_DMW_VSEG];

encoder #(
    .WIDTH(`CSR_DMW_PLV_WIDTH)
) enc_plv1 (
    .in (DMW[1][`CSR_DMW_PLV]),
    .out(plv1)
);
assign pseg1 = DMW[1][`CSR_DMW_PSEG];
assign vseg1 = DMW[1][`CSR_DMW_VSEG];

assign datf = CRMD[`CSR_CRMD_DATF];
assign datm = CRMD[`CSR_CRMD_DATM];

assign mat0 = DMW[0][`CSR_DMW_MAT];
assign mat1 = DMW[1][`CSR_DMW_MAT];

// ============ 输出端口赋值 ============
assign returnAddr = ERA;     
assign entry   = etype[`ETYPE_FETCH_TLB] & exception[`EXCEPTION_F_TLBR] |
                  etype[`ETYPE_EXECUTE_TLB] & exception[`EXCEPTION_M_TLBR] ? 
                    TLBRENTRY : 
                EENTRY;

assign interrupt = 
    CRMD[`CSR_CRMD_IE] & 
    |({ECFG[`CSR_ECFG_LIE_12_11], ECFG[`CSR_ECFG_LIE_9_0]} & 
      {ESTAT[12:11], ESTAT[9:0]});

endmodule //CSRF
