`include "constant.v"
`include "instr_code.v"

module D_control (
    input  wire [31:0]  instr,
    input  wire [1:0]   plv,

    output wire use_rj,
    output wire use_rdk,
    output wire useRd,
    output wire useCSR,
    output wire [2:0] GPR_new,

    output wire [`npc_select_width-1:0] nextPCSel,  
    output wire [`imm_select_width-1:0] immLen,  
    output wire sign_extend,

    output wire [`cmp_sel_width-1:0]    cmpOp,

    output wire [`alu_src_select_width-1:0] aluSrcA,
    output wire [`alu_src_select_width-1:0] aluSrcB,
    output wire [`alu_op_width-1:0]         aluOp,
    output wire mult,
    output wire div,
    output wire mult_div_signed,

    output wire memWrite,
    output wire memReadOrWrite,
    output wire memSigned,
    output wire [`data_type_sel_width-1:0]  memDataType,

    output wire regWrite,
    output wire [`reg_select_width-1:0]         regWriteAddrSel,
    output wire [`data_src_select_width-1:0]    regWriteDataSrc,

    output wire [4:0]   rd_addr,
    output wire [4:0]   rj_addr,
    output wire [4:0]   rk_addr,

    output wire [11:0]  imm_12,
    output wire [13:0]  imm_14,
    output wire [15:0]  imm_16,
    output wire [19:0]  imm_20,
    output wire [20:0]  imm_21,
    output wire [25:0]  imm_26,

    output wire [4:0]   shamt,

    // 异常与中断
    output wire csrWrite,
    output wire [`csr_addr_width-1:0] csrWriteAddr,
    output wire csrMask,
    output wire errorReturn,
    output wire notExistInstr,
    output wire isBreak,
    output wire isSyscall,
    output wire readHighCnt,
    output wire isIdle,
    output wire IPE,
    output wire refetch,

    // 页表操作
    output wire [       `TLB_OP_WIDTH-1:0] TLB_operation,

    // cache操作
    output wire [ `CACHE_TARGET_WIDTH-1:0] cache_target,
    output wire [     `CACHE_OP_WIDTH-1:0] cache_operation,

    output wire is_LL_W,
    output wire is_SC_W,
    output wire mem_write_cond,

    output wire [`MEM_BAR_WIDTH-1:0] mem_barrier
);

wire [63:0] instr_31_26_d;
wire [ 3:0] instr_25_24_d;
wire [ 3:0] instr_23_22_d;
wire [ 3:0] instr_21_20_d;
wire [31:0] instr_19_15_d;
wire [31:0] instr_14_10_d;
wire [31:0] instr_9_5_d;
wire [31:0] instr_4_0_d;

// 指令字段提取
wire [4:0] rd = instr[4:0];
wire [4:0] rj = instr[9:5];
wire [4:0] rk = instr[14:10];

// 立即数字段提取
assign imm_12 = instr[`I12_MSB:`I12_LSB];          // 12位立即数
assign imm_14 = instr[`I14_MSB:`I14_LSB];          // 14位立即数
assign imm_20 = instr[`I20_MSB:`I20_LSB];          // 20位立即数

// 偏移量字段提取
assign imm_16 = instr[`O16_MSB:`O16_LSB];          // 16位偏移
assign imm_21 = {instr[`O21_HI_MSB:`O21_HI_LSB],    // 21位偏移(拼接)
                    instr[`O21_LO_MSB:`O21_LO_LSB]};
assign imm_26 = {instr[`O26_HI_MSB:`O26_HI_LSB],    // 26位偏移(拼接)
                    instr[`O26_LO_MSB:`O26_LO_LSB]};

assign shamt = instr[14:10];

assign rd_addr = rd;
assign rj_addr = rj;
assign rk_addr = rk;


decoder #(
    .WIDTH(6)
) decoder_6_64 (
    .in (instr[31:26]),
    .out(instr_31_26_d)
);
decoder #(
    .WIDTH(2)
) decoder_2_4_0 (
    .in (instr[25:24]),
    .out(instr_25_24_d)
);
decoder #(
    .WIDTH(2)
) decoder_2_4_1 (
    .in (instr[23:22]),
    .out(instr_23_22_d)
);
decoder #(
    .WIDTH(2)
) decoder_2_4_2 (
    .in (instr[21:20]),
    .out(instr_21_20_d)
);
decoder #(
    .WIDTH(5)
) decoder_5_32_0 (
    .in (instr[19:15]),
    .out(instr_19_15_d)
);
decoder #(
    .WIDTH(5)
) decoder_5_32_1 (
    .in (instr[14:10]),
    .out(instr_14_10_d)
);
decoder #(
    .WIDTH(5)
) decoder_5_32_2 (
    .in (instr[9:5]),
    .out(instr_9_5_d)
);
decoder #(
    .WIDTH(5)
) decoder_5_32_3 (
    .in (instr[4:0]),
    .out(instr_4_0_d)
);

// ============================================================================
// 指令译码
// ============================================================================
// 基础算术逻辑指令

wire nop      = ~|instr;  // 全0指令视为nop

wire add_w    = instr_31_26_d[`ADD_W_31_26]    & instr_25_24_d[`ADD_W_25_24]    &
                instr_23_22_d[`ADD_W_23_22]    & instr_21_20_d[`ADD_W_21_20]    &
                instr_19_15_d[`ADD_W_19_15];

wire sub_w    = instr_31_26_d[`SUB_W_31_26]    & instr_25_24_d[`SUB_W_25_24]    &
                instr_23_22_d[`SUB_W_23_22]    & instr_21_20_d[`SUB_W_21_20]    &
                instr_19_15_d[`SUB_W_19_15];

wire slt      = instr_31_26_d[`SLT_31_26]      & instr_25_24_d[`SLT_25_24]      &
                instr_23_22_d[`SLT_23_22]      & instr_21_20_d[`SLT_21_20]      &
                instr_19_15_d[`SLT_19_15];

wire sltu     = instr_31_26_d[`SLTU_31_26]     & instr_25_24_d[`SLTU_25_24]     &
                instr_23_22_d[`SLTU_23_22]     & instr_21_20_d[`SLTU_21_20]     &
                instr_19_15_d[`SLTU_19_15];

wire __nor    = instr_31_26_d[`NOR_31_26]      & instr_25_24_d[`NOR_25_24]      &
                instr_23_22_d[`NOR_23_22]      & instr_21_20_d[`NOR_21_20]      &
                instr_19_15_d[`NOR_19_15];

wire __and    = instr_31_26_d[`AND_31_26]      & instr_25_24_d[`AND_25_24]      &
                instr_23_22_d[`AND_23_22]      & instr_21_20_d[`AND_21_20]      &
                instr_19_15_d[`AND_19_15];

wire __or     = instr_31_26_d[`OR_31_26]       & instr_25_24_d[`OR_25_24]       &
                instr_23_22_d[`OR_23_22]       & instr_21_20_d[`OR_21_20]       &
                instr_19_15_d[`OR_19_15];

wire __xor    = instr_31_26_d[`XOR_31_26]      & instr_25_24_d[`XOR_25_24]      &
                instr_23_22_d[`XOR_23_22]      & instr_21_20_d[`XOR_21_20]      &
                instr_19_15_d[`XOR_19_15];

// 移位指令
wire sll_w    = instr_31_26_d[`SLL_W_31_26]    & instr_25_24_d[`SLL_W_25_24]    &
                instr_23_22_d[`SLL_W_23_22]    & instr_21_20_d[`SLL_W_21_20]    &
                instr_19_15_d[`SLL_W_19_15];

wire srl_w    = instr_31_26_d[`SRL_W_31_26]    & instr_25_24_d[`SRL_W_25_24]    &
                instr_23_22_d[`SRL_W_23_22]    & instr_21_20_d[`SRL_W_21_20]    &
                instr_19_15_d[`SRL_W_19_15];

wire sra_w    = instr_31_26_d[`SRA_W_31_26]    & instr_25_24_d[`SRA_W_25_24]    &
                instr_23_22_d[`SRA_W_23_22]    & instr_21_20_d[`SRA_W_21_20]    &
                instr_19_15_d[`SRA_W_19_15];

wire slli_w   = instr_31_26_d[`SLLI_W_31_26]   & instr_25_24_d[`SLLI_W_25_24]   &
                instr_23_22_d[`SLLI_W_23_22]   & instr_21_20_d[`SLLI_W_21_20]   &
                instr_19_15_d[`SLLI_W_19_15];

wire srli_w   = instr_31_26_d[`SRLI_W_31_26]   & instr_25_24_d[`SRLI_W_25_24]   &
                instr_23_22_d[`SRLI_W_23_22]   & instr_21_20_d[`SRLI_W_21_20]   &
                instr_19_15_d[`SRLI_W_19_15];

wire srai_w   = instr_31_26_d[`SRAI_W_31_26]   & instr_25_24_d[`SRAI_W_25_24]   &
                instr_23_22_d[`SRAI_W_23_22]   & instr_21_20_d[`SRAI_W_21_20]   &
                instr_19_15_d[`SRAI_W_19_15];

// 乘除指令
wire mul_w    = instr_31_26_d[`MUL_W_31_26]    & instr_25_24_d[`MUL_W_25_24]    &
                instr_23_22_d[`MUL_W_23_22]    & instr_21_20_d[`MUL_W_21_20]    &
                instr_19_15_d[`MUL_W_19_15];

wire mulh_w   = instr_31_26_d[`MULH_W_31_26]   & instr_25_24_d[`MULH_W_25_24]   &
                instr_23_22_d[`MULH_W_23_22]   & instr_21_20_d[`MULH_W_21_20]   &
                instr_19_15_d[`MULH_W_19_15];

wire mulhu_wu = instr_31_26_d[`MULHU_WU_31_26] & instr_25_24_d[`MULHU_WU_25_24] &
                instr_23_22_d[`MULHU_WU_23_22] & instr_21_20_d[`MULHU_WU_21_20] &
                instr_19_15_d[`MULHU_WU_19_15];

wire div_w    = instr_31_26_d[`DIV_W_31_26]    & instr_25_24_d[`DIV_W_25_24]    &
                instr_23_22_d[`DIV_W_23_22]    & instr_21_20_d[`DIV_W_21_20]    &
                instr_19_15_d[`DIV_W_19_15];

wire mod_w    = instr_31_26_d[`MOD_W_31_26]    & instr_25_24_d[`MOD_W_25_24]    &
                instr_23_22_d[`MOD_W_23_22]    & instr_21_20_d[`MOD_W_21_20]    &
                instr_19_15_d[`MOD_W_19_15];

wire div_wu   = instr_31_26_d[`DIV_WU_31_26]   & instr_25_24_d[`DIV_WU_25_24]   &
                instr_23_22_d[`DIV_WU_23_22]   & instr_21_20_d[`DIV_WU_21_20]   &
                instr_19_15_d[`DIV_WU_19_15];

wire mod_wu   = instr_31_26_d[`MOD_WU_31_26]   & instr_25_24_d[`MOD_WU_25_24]   &
                instr_23_22_d[`MOD_WU_23_22]   & instr_21_20_d[`MOD_WU_21_20]   &
                instr_19_15_d[`MOD_WU_19_15];

// 立即数算术逻辑指令
wire slti     = instr_31_26_d[`SLTI_31_26]     & instr_25_24_d[`SLTI_25_24]     &
                instr_23_22_d[`SLTI_23_22];

wire sltui    = instr_31_26_d[`SLTUI_31_26]    & instr_25_24_d[`SLTUI_25_24]    &
                instr_23_22_d[`SLTUI_23_22];

wire addi_w   = instr_31_26_d[`ADDI_W_31_26]   & instr_25_24_d[`ADDI_W_25_24]   &
                instr_23_22_d[`ADDI_W_23_22];

wire andi     = instr_31_26_d[`ANDI_31_26]     & instr_25_24_d[`ANDI_25_24]     &
                instr_23_22_d[`ANDI_23_22];

wire ori      = instr_31_26_d[`ORI_31_26]      & instr_25_24_d[`ORI_25_24]      &
                instr_23_22_d[`ORI_23_22];

wire xori     = instr_31_26_d[`XORI_31_26]     & instr_25_24_d[`XORI_25_24]     &
                instr_23_22_d[`XORI_23_22];

// 分支跳转指令
wire jirl     = instr_31_26_d[`JIRL_31_26];
wire b        = instr_31_26_d[`B_31_26];
wire bl       = instr_31_26_d[`BL_31_26];
wire beq      = instr_31_26_d[`BEQ_31_26];
wire bne      = instr_31_26_d[`BNE_31_26];
wire blt      = instr_31_26_d[`BLT_31_26];
wire bge      = instr_31_26_d[`BGE_31_26];
wire bltu     = instr_31_26_d[`BLTU_31_26];
wire bgeu     = instr_31_26_d[`BGEU_31_26];

// 加载存储指令
wire ld_b     = instr_31_26_d[`LD_B_31_26]     & instr_25_24_d[`LD_B_25_24]     &
                instr_23_22_d[`LD_B_23_22];

wire ld_h     = instr_31_26_d[`LD_H_31_26]     & instr_25_24_d[`LD_H_25_24]     &
                instr_23_22_d[`LD_H_23_22];

wire ld_w     = instr_31_26_d[`LD_W_31_26]     & instr_25_24_d[`LD_W_25_24]     &
                instr_23_22_d[`LD_W_23_22];

wire st_b     = instr_31_26_d[`ST_B_31_26]     & instr_25_24_d[`ST_B_25_24]     &
                instr_23_22_d[`ST_B_23_22];

wire st_h     = instr_31_26_d[`ST_H_31_26]     & instr_25_24_d[`ST_H_25_24]     &
                instr_23_22_d[`ST_H_23_22];

wire st_w     = instr_31_26_d[`ST_W_31_26]     & instr_25_24_d[`ST_W_25_24]     &
                instr_23_22_d[`ST_W_23_22];

wire ld_bu    = instr_31_26_d[`LD_BU_31_26]    & instr_25_24_d[`LD_BU_25_24]    &
                instr_23_22_d[`LD_BU_23_22];

wire ld_hu    = instr_31_26_d[`LD_HU_31_26]    & instr_25_24_d[`LD_HU_25_24]    &
                instr_23_22_d[`LD_HU_23_22];

// 高地位加载指令
wire lu12i_w  = instr_31_26_d[`LU12I_W_31_26]  & ~instr[25];
wire pcaddu12i= instr_31_26_d[`PCADDU12I_31_26]& ~instr[25];

// 异常与中断指令
wire csrrd = instr_31_26_d[`CSRRD_31_26] & instr_25_24_d[`CSRRD_25_24] &
                instr_9_5_d[`CSRRD_9_5];
wire csrwr = instr_31_26_d[`CSRWR_31_26] & instr_25_24_d[`CSRWR_25_24] &
                instr_9_5_d[`CSRWR_9_5];
wire csrxchg = instr_31_26_d[`CSRXCHG_31_26] & instr_25_24_d[`CSRXCHG_25_24] &
                ~instr_9_5_d[`CSRRD_9_5] & ~instr_9_5_d[`CSRWR_9_5];
wire ertn = instr_31_26_d[`ERTN_31_26] & instr_25_24_d[`ERTN_25_24] &
            instr_23_22_d[`ERTN_23_22] & instr_21_20_d[`ERTN_21_20] &
            instr_19_15_d[`ERTN_19_15] & instr_14_10_d[`ERTN_14_10] &
            instr_9_5_d[`ERTN_9_5] & instr_4_0_d[`ERTN_4_0];
wire rdcntid_w = instr_31_26_d[`RDCNTID_W_31_26] & instr_25_24_d[`RDCNTID_W_25_24] &
            instr_23_22_d[`RDCNTID_W_23_22] & instr_21_20_d[`RDCNTID_W_21_20] &
            instr_19_15_d[`RDCNTID_W_19_15] & instr_14_10_d[`RDCNTID_W_14_10] &
            instr_4_0_d[`RDCNTID_W_4_0];
wire rdcntvl_w = instr_31_26_d[`RDCNTVL_W_31_26] & instr_25_24_d[`RDCNTVL_W_25_24] &
            instr_23_22_d[`RDCNTVL_W_23_22] & instr_21_20_d[`RDCNTVL_W_21_20] &
            instr_19_15_d[`RDCNTVL_W_19_15] & instr_14_10_d[`RDCNTVL_W_14_10] &
            instr_9_5_d[`RDCNTVL_W_9_5];
wire rdcntvh_w = instr_31_26_d[`RDCNTVH_W_31_26] & instr_25_24_d[`RDCNTVH_W_25_24] &
            instr_23_22_d[`RDCNTVH_W_23_22] & instr_21_20_d[`RDCNTVH_W_21_20] &
            instr_19_15_d[`RDCNTVH_W_19_15] & instr_14_10_d[`RDCNTVH_W_14_10] &
            instr_9_5_d[`RDCNTVH_W_9_5];
wire syscall = instr_31_26_d[`SYSCALL_31_26] & instr_25_24_d[`SYSCALL_25_24] &
            instr_23_22_d[`SYSCALL_23_22] & instr_21_20_d[`SYSCALL_21_20] &
            instr_19_15_d[`SYSCALL_19_15];
wire __break = instr_31_26_d[`BREAK_31_26] & instr_25_24_d[`BREAK_25_24] &
            instr_23_22_d[`BREAK_23_22] & instr_21_20_d[`BREAK_21_20] &
            instr_19_15_d[`BREAK_19_15];

// TLB 指令

wire tlbsrch = instr_31_26_d[`TLBSRCH_31_26] & instr_25_24_d[`TLBSRCH_25_24] &
                instr_23_22_d[`TLBSRCH_23_22] & instr_21_20_d[`TLBSRCH_21_20] &
                instr_19_15_d[`TLBSRCH_19_15] & instr_14_10_d[`TLBSRCH_14_10] &
                instr_9_5_d[`TLBSRCH_9_5] & instr_4_0_d[`TLBSRCH_4_0];
wire tlbrd = instr_31_26_d[`TLBRD_31_26] & instr_25_24_d[`TLBRD_25_24] &
                instr_23_22_d[`TLBRD_23_22] & instr_21_20_d[`TLBRD_21_20] &
                instr_19_15_d[`TLBRD_19_15] & instr_14_10_d[`TLBRD_14_10] &
                instr_9_5_d[`TLBRD_9_5] & instr_4_0_d[`TLBRD_4_0];
wire tlbwr = instr_31_26_d[`TLBWR_31_26] & instr_25_24_d[`TLBWR_25_24] &
                instr_23_22_d[`TLBWR_23_22] & instr_21_20_d[`TLBWR_21_20] &
                instr_19_15_d[`TLBWR_19_15] & instr_14_10_d[`TLBWR_14_10] &
                instr_9_5_d[`TLBWR_9_5] & instr_4_0_d[`TLBWR_4_0];
wire tlbfill = instr_31_26_d[`TLBFILL_31_26] & instr_25_24_d[`TLBFILL_25_24] &
                instr_23_22_d[`TLBFILL_23_22] & instr_21_20_d[`TLBFILL_21_20] &
                instr_19_15_d[`TLBFILL_19_15] & instr_14_10_d[`TLBFILL_14_10] &
                instr_9_5_d[`TLBFILL_9_5] & instr_4_0_d[`TLBFILL_4_0];
wire idle = instr_31_26_d[`IDLE_31_26] & instr_25_24_d[`IDLE_25_24] &
                instr_23_22_d[`IDLE_23_22] & instr_21_20_d[`IDLE_21_20] &
                instr_19_15_d[`IDLE_19_15];
wire invtlb = instr_31_26_d[`INVTLB_31_26] & instr_25_24_d[`INVTLB_25_24] &
                instr_23_22_d[`INVTLB_23_22] & instr_21_20_d[`INVTLB_21_20] &
                instr_19_15_d[`INVTLB_19_15] & |instr_4_0_d[6:0];

wire ll_w = instr_31_26_d[`LL_W_31_26] & instr_25_24_d[`LL_W_25_24];
wire sc_w = instr_31_26_d[`SC_W_31_26] & instr_25_24_d[`SC_W_25_24];

wire cacop = instr_31_26_d[`CACOP_31_26] & instr_25_24_d[`CACOP_25_24] &
                 instr_23_22_d[`CACOP_23_22];

wire preld = instr_31_26_d[`PRELD_31_26] & instr_25_24_d[`PRELD_25_24] &
                instr_23_22_d[`PRELD_23_22];
wire dbar  = instr_31_26_d[`DBAR_31_26] & instr_25_24_d[`DBAR_25_24] &
                instr_23_22_d[`DBAR_23_22] & instr_21_20_d[`DBAR_21_20] &
                instr_19_15_d[`DBAR_19_15];
wire ibar  = instr_31_26_d[`IBAR_31_26] & instr_25_24_d[`IBAR_25_24] &
                instr_23_22_d[`IBAR_23_22] & instr_21_20_d[`IBAR_21_20] &
                instr_19_15_d[`IBAR_19_15];

// ============================================================================
// use_*：使用哪一个寄存器
// ============================================================================
assign use_rj = 
    (jirl | bl | beq | bne | blt | bge | bltu | bgeu) |
    (add_w | sub_w | slt | sltu | __and | __nor | __or | __xor |
     sll_w | srl_w | sra_w | slli_w | srli_w | srai_w |
     mul_w | mulh_w | mulhu_wu | div_w | mod_w | div_wu | mod_wu |
     addi_w | andi | ori | xori | slti | sltui |
     ld_b | ld_h | ld_w | ld_bu | ld_hu | st_b | st_h | st_w |
     csrxchg | invtlb |
     cacop | ll_w | sc_w) | preld;

assign use_rdk = 
    (beq | bne | blt | bge | bltu | bgeu) |
    (add_w | sub_w | slt | sltu | __and | __nor | __or | __xor |
     sll_w | srl_w | sra_w | 
     mul_w | mulh_w | mulhu_wu | div_w | mod_w | div_wu | mod_wu |
     st_b | st_h | st_w | sc_w |
     csrxchg | csrwr | invtlb) ;

assign useRd = 
    st_b | st_h | st_w | sc_w |
    beq | bne | blt | bge | bltu | bgeu | 
    csrwr | csrxchg;

assign useCSR = rdcntid_w | csrrd | csrwr | csrxchg | sc_w;

// ============================================================================
// T_new: 指令结果产生所需周期数（乘除类指令不包含在内）
// ============================================================================

assign GPR_new[`data_new_E] = jirl | bl | rdcntvl_w | rdcntvh_w |
                            csrrd | csrwr | csrxchg | rdcntid_w;

assign GPR_new[`data_new_M] = add_w | sub_w | slt | sltu | __and | __nor | __or | __xor |
                sll_w | srl_w | sra_w | mul_w | mulh_w | mulhu_wu  | slli_w | srli_w | srai_w |
                slti | sltui | addi_w | andi | ori | xori | pcaddu12i| lu12i_w |
                sc_w;

assign GPR_new[`data_new_W] = ld_b | ld_h | ld_w | ld_bu | ld_hu | ll_w |
                div_w | mod_w | div_wu | mod_wu;

// ============================================================================
// 立即数类型选择 (immLen)
// ============================================================================
assign immLen[`imm_12] = addi_w | andi | ori | xori | slti | sltui |
                          ld_b | ld_h | ld_w | ld_bu | ld_hu |
                          st_b | st_h | st_w | cacop | preld;
assign immLen[`imm_14] = ll_w | sc_w;  
assign immLen[`imm_16] = beq | bne | blt | bge | bltu | bgeu | jirl;
assign immLen[`imm_20] = lu12i_w | pcaddu12i;
assign immLen[`imm_21] = 1'b0;  // 21位偏移暂未使用
assign immLen[`imm_26] = b | bl;

assign sign_extend = 
    // 需要符号扩展的指令
    (addi_w | slti | sltui | ld_b | ld_h | ld_w | ld_bu | ld_hu | 
     st_b | st_h | st_w |                     // I12型
     ll_w | sc_w |                       // I14型
     jirl | beq | bne | blt | bge | bltu | bgeu | // I16型
     b | bl |
     cacop | preld) ? 1'b1 :                           // I21型
    
    // 默认值
    1'b0;

// ============================================================================
// 下一PC选择 (nextPCSel)
// ============================================================================
// assign nextPCSel[`npc_plus_4] = ~(jirl | b | bl | beq | bne | blt | bge | bltu | bgeu);
assign nextPCSel[`npc_branch] = beq | bne | blt | bge | bltu | bgeu | b | bl;
assign nextPCSel[`npc_jirl]   = jirl;
assign nextPCSel[`npc_era]    = ertn;
assign nextPCSel[`npc_plus_4] = ~(nextPCSel[`npc_branch] | nextPCSel[`npc_jirl] | nextPCSel[`npc_era]);

// ============================================================================
// 比较操作类型 (cmpOp)
// ============================================================================
assign cmpOp[`cmp_beq]  = beq;
assign cmpOp[`cmp_bne]  = bne;
assign cmpOp[`cmp_blt]  = blt;
assign cmpOp[`cmp_bge]  = bge;
assign cmpOp[`cmp_bltu] = bltu;
assign cmpOp[`cmp_bgeu] = bgeu;
assign cmpOp[`cmp_b] = b | bl;

// ============================================================================
// ALU源操作数选择 (aluSrcA)
// ============================================================================
assign aluSrcA[`alu_src_rj]  = add_w | sub_w | slt | sltu | __and | __nor | __or | __xor |
                                sll_w | srl_w | sra_w | slli_w | srli_w | srai_w |
                                mul_w | mulh_w | mulhu_wu | div_w | mod_w | div_wu | mod_wu |
                                addi_w | andi | ori | xori | slti | sltui |
                                ld_b | ld_h | ld_w | ld_bu | ld_hu | st_b | st_h | st_w | cacop |
                                ll_w | sc_w  | preld
                                /*beq | bne | blt | bge | bltu | bgeu*/ ;
assign aluSrcA[`alu_src_rdk]  = csrwr;
assign aluSrcA[`alu_src_pc]  = pcaddu12i | bl | jirl;
assign aluSrcA[`alu_src_imm] = 1'b0;
assign aluSrcA[`alu_src_four]= 1'b0;

// ============================================================================
// ALU源操作数选择 (aluSrcB)
// ============================================================================
assign aluSrcB[`alu_src_rj]  = 1'b0;
assign aluSrcB[`alu_src_rdk]  = add_w | sub_w | slt | sltu | __and | __nor | __or | __xor |
                                sll_w | srl_w | sra_w |
                                mul_w | mulh_w | mulhu_wu | div_w | mod_w | div_wu | mod_wu;
assign aluSrcB[`alu_src_pc]  = 1'b0;
assign aluSrcB[`alu_src_imm] = addi_w | andi | ori | xori | slti | sltui |
                                ld_b | ld_h | ld_w | ld_bu | ld_hu |
                                lu12i_w | pcaddu12i | cacop |
                                /*beq | bne | blt | bge | bltu | bgeu |*/
                                st_b | st_h | st_w | ll_w | sc_w | preld;
assign aluSrcB[`alu_src_four]= bl | jirl;

// ============================================================================
// ALU操作类型 (aluOp)
// ============================================================================
assign aluOp[`alu_add]  = add_w | addi_w | ld_b | ld_h | ld_w | ld_bu | ld_hu |
                           st_b | st_h | st_w | pcaddu12i | bl | jirl | cacop |
                           ll_w | sc_w | preld;
assign aluOp[`alu_sub]  = sub_w;
assign aluOp[`alu_and]  = __and | andi;
assign aluOp[`alu_or]   = __or | ori;
assign aluOp[`alu_xor]  = __xor | xori;
assign aluOp[`alu_nor]  = __nor;
assign aluOp[`alu_slt]  = slt | slti;
assign aluOp[`alu_sltu] = sltu | sltui;
assign aluOp[`alu_sll]  = sll_w;
assign aluOp[`alu_srl]  = srl_w;
assign aluOp[`alu_sra]  = sra_w;
assign aluOp[`alu_slli] = slli_w;
assign aluOp[`alu_srli] = srli_w;
assign aluOp[`alu_srai] = srai_w;
assign aluOp[`alu_lui]  = lu12i_w;
assign aluOp[`alu_div_w] = div_w;
assign aluOp[`alu_div_wu] = div_wu;
assign aluOp[`alu_mod_w] = mod_w;
assign aluOp[`alu_mod_wu] = mod_wu;
assign aluOp[`alu_andn] = 1'b0;
assign aluOp[`alu_orn]  = 1'b0;

// ============================================================================
// 乘除指令标志 (mult, div)
// ============================================================================
assign mult = mul_w | mulh_w | mulhu_wu;
assign div  = div_w | mod_w | div_wu | mod_wu;
assign mult_div_signed = mul_w | mulh_w | div_w | mod_w;

// ============================================================================
// 访存控制信号 (memWrite, memSigned, memDataType)
// ============================================================================
assign memWrite = st_b | st_h | st_w;
assign memReadOrWrite = ld_b | ld_h | ld_w | ld_bu | ld_hu | st_b | st_h | st_w |
                        ll_w;

assign memSigned = ld_b | ld_h;  // ld_bu/ld_hu无符号

assign memDataType[`byte] = ld_b | ld_bu | st_b;
assign memDataType[`half] = ld_h | ld_hu | st_h;
assign memDataType[`word] = ld_w | st_w | ll_w | sc_w;

// ============================================================================
// 寄存器写控制 (regWrite)
// ============================================================================
assign regWrite = add_w | sub_w | slt | sltu | __and | __nor | __or | __xor |
                  sll_w | srl_w | sra_w | slli_w | srli_w | srai_w |
                  addi_w | andi | ori | xori | slti | sltui |
                  ld_b | ld_h | ld_w | ld_bu | ld_hu |
                  lu12i_w | pcaddu12i |
                  bl | (jirl & (rd != 5'd0)) |
                  rdcntid_w | rdcntvh_w | rdcntvl_w |
                  csrrd | csrwr | csrxchg |
                  div_w | div_wu | mod_w | mod_wu | mul_w | mulh_w | mulhu_wu |
                  ll_w | sc_w;

// ============================================================================
// 写寄存器地址选择 (regWriteAddr)
// ============================================================================
assign regWriteAddrSel[`reg_rd]   = 
    ~(|regWriteAddrSel[`reg_zero:`reg_rj]) & regWrite;  // 大多数指令写rd
assign regWriteAddrSel[`reg_rj]   = rdcntid_w;
assign regWriteAddrSel[`reg_rk]   = 1'b0;
assign regWriteAddrSel[`reg_link] = bl;  // bl写r1，jirl写rd
assign regWriteAddrSel[`reg_zero] = 1'b0;

// ============================================================================
// 写回数据来源选择 (regWriteDataSrc)
// ============================================================================
assign regWriteDataSrc[`data_src_alu]    = 
    ~(|regWriteDataSrc[`data_src_scw:`data_src_pc]);
assign regWriteDataSrc[`data_src_pc]     =  1'b0;
assign regWriteDataSrc[`data_src_mul_hi] = mulh_w | mulhu_wu ;
assign regWriteDataSrc[`data_src_mul_lo] = mul_w ;
assign regWriteDataSrc[`data_src_div_hi] = mod_w | mod_wu;
assign regWriteDataSrc[`data_src_div_lo] = div_w | div_wu;
assign regWriteDataSrc[`data_src_mem]    = ld_b | ld_h | ld_w | ld_bu | ld_hu | ll_w;
assign regWriteDataSrc[`data_src_cnt]    = rdcntvh_w | rdcntvl_w;
assign regWriteDataSrc[`data_src_csr]    = csrrd | csrwr | csrxchg | rdcntid_w;
assign regWriteDataSrc[`data_src_scw]    = sc_w;

// ============================================================================
// 关于CSR的操作
// ============================================================================

wire csrNum_TID = rdcntid_w;
assign csrWrite = csrwr | csrxchg | ll_w;
// 具体涉及哪一个csr地址
assign csrWriteAddr = 
        (csrNum_TID) ? `CSR_TID : 
        (is_LL_W | is_SC_W) ? `CSR_LLBCTL : 
        instr[23:10];
assign csrMask = csrxchg;

// tlb具体操作
assign TLB_operation[`TLB_OP_SRCH] = tlbsrch;
assign TLB_operation[`TLB_OP_READ] = tlbrd;
assign TLB_operation[`TLB_OP_WRITE] = tlbwr;
assign TLB_operation[`TLB_OP_FILL] = tlbfill;
assign TLB_operation[`TLB_OP_INV] = {`TLB_INVOP_WIDTH{invtlb}} & {instr_4_0_d[6:0]};


assign notExistInstr = ~(rdcntid_w | rdcntvl_w | rdcntvh_w |
    add_w | sub_w | slt | sltu | __nor | __and | __or | __xor |
    sll_w | srl_w | sra_w | mul_w | mulh_w | mulhu_wu | div_w | mod_w |
    div_wu | mod_wu | __break | syscall | slli_w | srli_w | srai_w |
    slti | sltui | addi_w | andi | ori | xori | csrrd | csrwr |
    csrxchg | ertn | lu12i_w | pcaddu12i |
    ld_b | ld_h | ld_w | st_b | st_h | st_w |
    ld_bu | ld_hu |
    jirl | b | bl | beq | bne | blt | bge | bltu | bgeu |
    tlbsrch | tlbrd | tlbwr | tlbfill | invtlb | idle |
    cacop | ll_w | sc_w | preld | dbar | ibar);

assign errorReturn = ertn;
assign isBreak = __break;
assign isSyscall = syscall;
assign isIdle = idle;

wire privileged =   
        csrrd | csrwr | csrxchg |
        tlbsrch | tlbrd | tlbwr | tlbfill | invtlb |
        (cacop & instr[4:3] != `CACOP_TYPE_HIT_OP) |
        ertn | idle;
assign IPE = privileged & plv != 2'b00;

assign refetch = tlbrd | tlbwr | tlbfill | invtlb |
                (csrwr | csrxchg) & 
                        (csrWriteAddr == `CSR_CRMD | csrWriteAddr == `CSR_ASID |
                        csrWriteAddr == `CSR_DMW0 | csrWriteAddr == `CSR_DMW1) |
                (cacop & instr[2:0] ==`CACOP_TARGET_ICACHE) | ibar;

// ============================================================================
// 读取StableCounter
// ============================================================================

assign readHighCnt = rdcntvh_w;

// ============================================================================
// cache操作（cacop）
// ============================================================================

assign cache_target[`CACHE_TARGET_ICACHE] = 
    cacop & instr[2:0] == `CACOP_TARGET_ICACHE |
    preld & instr_4_0_d[8];
assign cache_target[`CACHE_TARGET_DCACHE] = 
    cacop & instr[2:0] == `CACOP_TARGET_DCACHE |
    preld & instr_4_0_d[0];

assign cache_operation[`CACHE_OP_STORE_TAG] = 
    cacop & instr[4:3] == `CACOP_TYPE_STORE_TAG;
assign cache_operation[`CACHE_OP_INDEX_OP] = 
    cacop & instr[4:3] == `CACOP_TYPE_INDEX_OP;
assign cache_operation[`CACHE_OP_HIT_OP] = 
    cacop & instr[4:3] == `CACOP_TYPE_HIT_OP;
assign cache_operation[`CACHE_OP_PRELD] = 
    preld & (instr_4_0_d[0] | instr_4_0_d[8]);

assign is_LL_W = ll_w;
assign mem_write_cond = sc_w;
assign is_SC_W = sc_w;

assign mem_barrier[`MEM_BAR_INST] = ibar;
assign mem_barrier[`MEM_BAR_DATA] = dbar;

endmodule