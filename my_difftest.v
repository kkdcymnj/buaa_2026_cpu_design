`include "constant.v"
`include "instr_code.v"

module my_difftest #(
    parameter TLB_ENTRIES = 32
)(
    input  wire clk,
    input  wire reset,

    //commit interface
    input  wire valid,
    input  wire [31:0]  PC,
    input  wire [31:0]  instr,
    input  wire regWrite,
    input  wire [4:0]   regWriteAddr,
    input  wire [31:0]  regWriteData,
    input  wire [31:0]  csrReadData,
    input  wire [63:0]  counterVal,
    input  wire csrWrite,
    input  wire isCsrRead,
    input  wire isCsrWrite,
    input  wire isCsrXchg,
    input  wire [`csr_addr_width-1:0]  csrWriteAddr,
    input  wire [$clog2(TLB_ENTRIES)-1:0] TLB_f_index,
    input  wire [      `TLB_OP_WIDTH-1:0] TLB_operation,

    // exception interface
    input wire [   `exception_width-1:0] exception,
    input wire                           errorReturn,
    input wire [       `ECODE_WIDTH-1:0] ecode,

    // load/store interface
    input  wire memWrite,
    input  wire memReadOrWrite,
    input  wire memSigned,
    input  wire LL_bit,
    input  wire is_SC_W,
    input  wire is_LL_W,
    input  wire [2:0]   memDataType,
    input  wire [31:0]  memPaddr,
    input  wire [31:0]  memVaddr,
    input  wire [31:0]  rdVal,

    // CSR interface
    input wire [                   31:0] CRMD,
    input wire [                   31:0] PRMD,
    input wire [                   31:0] EUEN,
    input wire [                   31:0] ECFG,
    input wire [                   31:0] ESTAT,
    input wire [                   31:0] ERA,
    input wire [                   31:0] BADV,
    input wire [                   31:0] EENTRY,
    input wire [                   31:0] TLBIDX,
    input wire [                   31:0] TLBEHI,
    input wire [                   31:0] TLBELO0,
    input wire [                   31:0] TLBELO1,
    input wire [                   31:0] ASID,
    input wire [                   31:0] PGDL,
    input wire [                   31:0] PGDH,
    input wire [                   31:0] SAVE0,
    input wire [                   31:0] SAVE1,
    input wire [                   31:0] SAVE2,
    input wire [                   31:0] SAVE3,
    input wire [                   31:0] TID,
    input wire [                   31:0] TCFG,
    input wire [                   31:0] TVAL,
    input wire [                   31:0] TICLR,
    input wire [                   31:0] LLBCTL,
    input wire [                   31:0] TLBRENTRY,
    input wire [                   31:0] DMW0,
    input wire [                   31:0] DMW1,

    // GPR interface
    input wire [                   31:0] GPR             [31:0]
);

`ifdef CHIPLAB

reg DIFF_valid;
reg [31:0] DIFF_PC;
reg [31:0] DIFF_instr;
reg DIFF_instr_cnt;
reg DIFF_GPR_write_enable;
reg [4:0] DIFF_GPR_write_num;
reg [31:0] DIFF_GPR_write_data;
reg [63:0] DIFF_CSR_counter;
reg [31:0] DIFF_CSR_read_data;
reg DIFF_CSR_write_enable;
reg [`csr_addr_width-1:0] DIFF_CSR_write_number;
reg [7:0] DIFF_load_valid;
reg [7:0] DIFF_store_valid;
reg [31:0] DIFF_MEM_vaddr;
reg [31:0] DIFF_MEM_paddr;
reg [31:0] DIFF_MEM_write_data;
reg [`TLB_OP_WIDTH-1:0] DIFF_TLB_operation;
reg [$clog2(TLB_ENTRIES)-1:0] DIFF_TLB_f_index;
reg [`exception_width-1:0] DIFF_exception;
reg DIFF_ereturn;
reg [`ECODE_WIDTH-1:0] DIFF_ecode;
reg trap_valid;
reg [7:0] trap_code;
reg [63:0] cycleCnt;
reg [63:0] instrCnt;

wire cnt_related_instr = 
    instr[31:10] == 22'b0000000000000000011000 & instr[4:0] == 5'b00000 |
    instr[31:10] == 22'b0000000000000000011000 & instr[9:5] == 5'b00000 |
    instr[31:10] == 22'b0000000000000000011001 & instr[9:5] == 5'b00000;

wire memRead = memReadOrWrite & ~memWrite;
wire memRead_word = memRead & memDataType[`word] & ~is_LL_W;
wire memRead_half_signed = memRead & memDataType[`half] & memSigned;
wire memRead_half_unsigned = memRead & memDataType[`half] & ~memSigned;
wire memRead_byte_signed = memRead & memDataType[`byte] & memSigned;
wire memRead_byte_unsigned = memRead & memDataType[`byte] & ~memSigned;

wire [7:0] load_valid = 
    {
        2'b0, 
        is_LL_W,
        memRead_word,
        memRead_half_unsigned,
        memRead_half_signed,
        memRead_byte_unsigned,
        memRead_byte_signed
    };

wire memWrite_word = memWrite & memDataType[`word];
wire memWrite_byte = memWrite & memDataType[`byte];
wire memWrite_half = memWrite & memDataType[`half];

wire [7:0] store_valid = 
    {
        4'b0,
        is_SC_W & LL_bit,
        memWrite_word,
        memWrite_half,
        memWrite_byte
    };

wire [31:0] MEM_write_data = 
    {32{memWrite_byte}} &
    ({24'b0, rdVal[7:0]} << ({3'b0, memVaddr[1:0]} << 3)) |
    {32{memWrite_half}} &
    ({16'b0, rdVal[15:0]} << ({4'b0, memVaddr[1]} << 4)) |
    {32{memWrite_word | is_SC_W}} & rdVal;

always @(posedge clk) begin
    if (reset) begin
        DIFF_valid            <= 1'b0;
        DIFF_PC               <= 32'h0;
        DIFF_instr            <= 32'h0;
        DIFF_instr_cnt        <= 1'b0;
        DIFF_GPR_write_enable <= 1'b0;
        DIFF_GPR_write_num    <= 5'b0;
        DIFF_GPR_write_data   <= 32'h0;
        DIFF_CSR_counter      <= 64'h0;
        DIFF_CSR_read_data    <= 32'h0;
        DIFF_CSR_write_enable <= 1'b0;
        DIFF_CSR_write_number <= `csr_addr_width'b0;
        DIFF_load_valid       <= 8'b0;
        DIFF_store_valid      <= 8'b0;
        DIFF_MEM_vaddr        <= 32'h0;
        DIFF_MEM_paddr        <= 32'h0;
        DIFF_MEM_write_data   <= 32'h0;
        DIFF_TLB_operation    <= `TLB_OP_WIDTH'b0;
        DIFF_TLB_f_index      <= {$clog2(TLB_ENTRIES) {1'b0}};
        DIFF_exception        <= `exception_width'b0;
        DIFF_ereturn          <= 1'b0;
        DIFF_ecode            <= `ECODE_WIDTH'b0;
        trap_valid            <= 1'b0;
        trap_code             <= 8'b0;
        cycleCnt              <= 64'h0;
        instrCnt              <= 64'h0;
    end else begin
        DIFF_valid            <= valid;
        DIFF_PC               <= PC;
        DIFF_instr            <= instr;
        DIFF_instr_cnt        <= cnt_related_instr;
        DIFF_GPR_write_enable <= regWrite;
        DIFF_GPR_write_num    <= regWriteAddr;
        DIFF_GPR_write_data   <= regWriteData;
        DIFF_CSR_counter      <= counterVal;
        DIFF_CSR_read_data    <= csrReadData;
        DIFF_CSR_write_enable <= isCsrWrite || isCsrXchg || isCsrRead;
        DIFF_CSR_write_number <= csrWriteAddr;
        DIFF_load_valid       <= load_valid;
        DIFF_store_valid      <= store_valid;
        DIFF_MEM_vaddr        <= memVaddr;
        DIFF_MEM_paddr        <= memPaddr;
        DIFF_MEM_write_data   <= MEM_write_data;
        DIFF_TLB_operation    <= TLB_operation;
        DIFF_TLB_f_index      <= TLB_f_index;
        DIFF_exception        <= exception;
        DIFF_ereturn          <= errorReturn;
        DIFF_ecode            <= ecode;
        trap_valid            <= 1'b0;
        trap_code             <= GPR[10][7:0];
        cycleCnt              <= cycleCnt + 1'b1;
        instrCnt              <= instrCnt + valid;
    end
end

DifftestInstrCommit DifftestInstrCommit (
    .clock         (clk),
    .coreid        (0),
    .index         (0),
    .valid         (DIFF_valid & ~|DIFF_exception),
    .pc            (DIFF_PC),
    .instr         (DIFF_instr),
    .skip          (0),
    .is_TLBFILL    (DIFF_TLB_operation[`TLB_OP_FILL]),
    .TLBFILL_index (DIFF_TLB_f_index),
    .is_CNTinst    (DIFF_instr_cnt),
    .timer_64_value(DIFF_CSR_counter),
    .wen           (DIFF_GPR_write_enable),
    .wdest         ({3'b0, DIFF_GPR_write_num}),
    .wdata         (DIFF_GPR_write_data),
    .csr_rstat     (DIFF_CSR_write_enable & DIFF_CSR_write_number == `CSR_ESTAT),
    .csr_data      (DIFF_CSR_read_data)
);

DifftestExcpEvent DifftestExcpEvent (
    .clock        (clk),
    .coreid       (0),
    .excp_valid   (|DIFF_exception),
    .eret         (DIFF_ereturn),
    .intrNo       (ESTAT[12:2]),
    .cause        (DIFF_ecode),
    .exceptionPC  (DIFF_PC),
    .exceptionInst(DIFF_instr)
);

DifftestTrapEvent DifftestTrapEvent (
    .clock   (clk),
    .coreid  (0),
    .valid   (trap_valid),
    .code    (trap_code),
    .pc      (DIFF_PC),
    .cycleCnt(cycleCnt),
    .instrCnt(instrCnt)
);

DifftestStoreEvent DifftestStoreEvent (
    .clock     (clk),
    .coreid    (0),
    .index     (0),
    .valid     (DIFF_store_valid),
    .storePAddr(DIFF_MEM_paddr),
    .storeVAddr(DIFF_MEM_vaddr),
    .storeData (DIFF_MEM_write_data)
);

DifftestLoadEvent DifftestLoadEvent (
    .clock (clk),
    .coreid(0),
    .index (0),
    .valid (DIFF_load_valid),
    .paddr (DIFF_MEM_paddr),
    .vaddr (DIFF_MEM_vaddr)
);

DifftestCSRRegState DifftestCSRRegState (
    .clock    (clk),
    .coreid   (0),
    .crmd     (CRMD),
    .prmd     (PRMD),
    .euen     (EUEN),
    .ecfg     (ECFG),
    .estat    (ESTAT),
    .era      (ERA),
    .badv     (BADV),
    .eentry   (EENTRY),
    .tlbidx   (TLBIDX),
    .tlbehi   (TLBEHI),
    .tlbelo0  (TLBELO0),
    .tlbelo1  (TLBELO1),
    .asid     (ASID),
    .pgdl     (PGDL),
    .pgdh     (PGDH),
    .save0    (SAVE0),
    .save1    (SAVE1),
    .save2    (SAVE2),
    .save3    (SAVE3),
    .tid      (TID),
    .tcfg     (TCFG),
    .tval     (TVAL),
    .ticlr    (TICLR),
    .llbctl   (LLBCTL),
    .tlbrentry(TLBRENTRY),
    .dmw0     (DMW0),
    .dmw1     (DMW1)
);

DifftestGRegState DifftestGRegState (
    .clock (clk),
    .coreid(0),
    .gpr_0 (32'b0),
    .gpr_1 (GPR[1]),
    .gpr_2 (GPR[2]),
    .gpr_3 (GPR[3]),
    .gpr_4 (GPR[4]),
    .gpr_5 (GPR[5]),
    .gpr_6 (GPR[6]),
    .gpr_7 (GPR[7]),
    .gpr_8 (GPR[8]),
    .gpr_9 (GPR[9]),
    .gpr_10(GPR[10]),
    .gpr_11(GPR[11]),
    .gpr_12(GPR[12]),
    .gpr_13(GPR[13]),
    .gpr_14(GPR[14]),
    .gpr_15(GPR[15]),
    .gpr_16(GPR[16]),
    .gpr_17(GPR[17]),
    .gpr_18(GPR[18]),
    .gpr_19(GPR[19]),
    .gpr_20(GPR[20]),
    .gpr_21(GPR[21]),
    .gpr_22(GPR[22]),
    .gpr_23(GPR[23]),
    .gpr_24(GPR[24]),
    .gpr_25(GPR[25]),
    .gpr_26(GPR[26]),
    .gpr_27(GPR[27]),
    .gpr_28(GPR[28]),
    .gpr_29(GPR[29]),
    .gpr_30(GPR[30]),
    .gpr_31(GPR[31])
);
`endif 

endmodule //difftest
