//`ifndef MACROS_VH
//`define MACROS_VH

`define CHIPLAB 

`define alu_add         0  
`define alu_sub         1  
`define alu_or          2  
`define alu_and         3  
`define alu_slt         4  
`define alu_sltu        5  
`define alu_sll         6  
`define alu_srl         7  
`define alu_sra         8  
`define alu_nor         9  
`define alu_xor         10 
`define alu_lui         11 
`define alu_andn        12 
`define alu_orn         13 
`define alu_slli        14 
`define alu_srli        15 
`define alu_srai        16
`define alu_div_w       17
`define alu_div_wu      18
`define alu_mod_w       19
`define alu_mod_wu      20
`define alu_op_width    21 

`define init_pc 32'h1c00_0000

`define npc_plus_4          0
`define npc_branch          1
`define npc_jirl            2
`define npc_era             3
`define npc_select_width    4

`define imm_16              0
`define imm_26              1
`define imm_21              2
`define imm_12              3
`define imm_14              4
`define imm_20              5
`define imm_select_width    8

`define byte                0
`define half                1
`define word                2
`define data_type_sel_width 3

`define cmp_beq         0
`define cmp_bne         1
`define cmp_blt         2
`define cmp_bge         3
`define cmp_bltu        4
`define cmp_bgeu        5
`define cmp_b           6
`define cmp_sel_width   7

`define alu_src_rj              0
`define alu_src_rdk             1
`define alu_src_pc              2
`define alu_src_imm             3
`define alu_src_four            4
`define alu_src_select_width    5

`define reg_rd              0
`define reg_rj              1
`define reg_rk              2
`define reg_link            3
`define reg_zero            4
`define reg_select_width    5

`define data_src_alu            0
`define data_src_pc             1
`define data_src_mul_hi         2
`define data_src_mul_lo         3
`define data_src_div_hi         4
`define data_src_div_lo         5
`define data_src_mem            6
`define data_src_cnt            7
`define data_src_csr            8
`define data_src_scw            9 
`define data_src_select_width   10

`define data_new_E   0
`define data_new_M   1
`define data_new_W   2

`define I12_MSB 21
`define I12_LSB 10
`define I14_MSB 23
`define I14_LSB 10
`define I20_MSB 24
`define I20_LSB 5

`define O16_MSB 25
`define O16_LSB 10
`define O21_HI_MSB 4
`define O21_HI_LSB 0
`define O21_LO_MSB 25
`define O21_LO_LSB 10
`define O26_HI_MSB 9
`define O26_HI_LSB 0
`define O26_LO_MSB 25
`define O26_LO_LSB 10

`define csr_addr_width 14 

`define ECODE_WIDTH 6
`define ECODE_INT 6'h00
`define ECODE_PIL 6'h01
`define ECODE_PIS 6'h02
`define ECODE_PIF 6'h03
`define ECODE_PME 6'h04
`define ECODE_PPI 6'h07
`define ECODE_ADEF 6'h08
`define ECODE_ADEM 6'h08
`define ECODE_ALE 6'h09
`define ECODE_SYS 6'h0b
`define ECODE_BRK 6'h0c
`define ECODE_INE 6'h0d
`define ECODE_IPE 6'h0e
`define ECODE_TLBR 6'h3f

`define ESUBCODE_WIDTH 9
`define ESUBCODE_OTHER 9'd0
`define ESUBCODE_ADEM 9'd1

`define exception_width 16
`define EXCEPTION_INT 0
`define EXCEPTION_PIL 1
`define EXCEPTION_PIS 2
`define EXCEPTION_PIF 3
`define EXCEPTION_PME 4
`define EXCEPTION_F_PPI 5
`define EXCEPTION_M_PPI 6
`define EXCEPTION_ADEF 7
`define EXCEPTION_ADEM 8
`define EXCEPTION_ALE 9
`define EXCEPTION_SYS 10
`define EXCEPTION_BRK 11
`define EXCEPTION_INE 12
`define EXCEPTION_IPE 13
`define EXCEPTION_F_TLBR 14
`define EXCEPTION_M_TLBR 15
`define EXCEPTION_TLBR 15:14

`define CSR_CRMD 14'h0000
`define CSR_CRMD_PLV 1:0
`define CSR_CRMD_IE 2
`define CSR_CRMD_DA 3
`define CSR_CRMD_PG 4
`define CSR_CRMD_DATF 6:5
`define CSR_CRMD_DATM 8:7
`define CSR_CRMD_0 31:9
`define CSR_CRMD_0_WIDTH 23

`define CSR_PRMD 14'h0001
`define CSR_PRMD_PPLV 1:0
`define CSR_PRMD_PIE 2
`define CSR_PRMD_0 31:3
`define CSR_PRMD_0_WIDTH 29

`define CSR_ECFG 14'h0004
`define CSR_ECFG_LIE 12:0
`define CSR_ECFG_LIE_9_0 9:0
`define CSR_ECFG_0_LO 10
`define CSR_ECFG_LIE_12_11 12:11
`define CSR_ECFG_0_HI 31:13
`define CSR_ECFG_0_LO_WIDTH 1
`define CSR_ECFG_0_HI_WIDTH 19

`define CSR_ESTAT 14'h0005
`define CSR_ESTAT_IS 12:0
`define CSR_ESTAT_IS_1_0 1:0
`define CSR_ESTAT_IS_9_2 9:2
`define CSR_ESTAT_0_LO 10
`define CSR_ESTAT_IS_11 11
`define CSR_ESTAT_IS_12 12
`define CSR_ESTAT_0_MD 15:13
`define CSR_ESTAT_ECODE 21:16
`define CSR_ESTAT_ECODE_WIDTH 6
`define CSR_ESTAT_ESUBCODE 30:22
`define CSR_ESTAT_0_HI 31
`define CSR_ESTAT_0_LO_WIDTH 1
`define CSR_ESTAT_0_MD_WIDTH 3
`define CSR_ESTAT_0_HI_WIDTH 1

`define CSR_ERA 14'h0006
`define CSR_ERA_PC 31:0

`define CSR_BADV 14'h0007
`define CSR_BADV_VADDR 31:0

`define CSR_EENTRY 14'h000c
`define CSR_EENTRY_0 5:0
`define CSR_EENTRY_VA 31:6
`define CSR_EENTRY_0_WIDTH 6

`ifdef CHIPLAB
    `define TLB_ENTRIES 32 
`else
    `define TLB_ENTRIES 16
`endif  
`define CSR_TLBIDX 14'h0010
`define CSR_TLBIDX_INDEX $clog2(`TLB_ENTRIES)-1:0
`define CSR_TLBIDX_0_LO 23:$clog2(`TLB_ENTRIES)
`define CSR_TLBIDX_PS 29:24
`define CSR_TLBIDX_0_HI 30
`define CSR_TLBIDX_NE 31
`define CSR_TLBIDX_PS_WIDTH 6
// `define CSR_TLBIDX_0_LO_WIDTH (23-$clog2(`TLB_ENTRIES)+1)
`define CSR_TLBIDX_0_HI_WIDTH 1

`define CSR_TLBEHI 14'h0011
`define CSR_TLBEHI_0 12:0
`define CSR_TLBEHI_VPPN 31:`VPPN_4KB_LSB
`define CSR_TLBEHI_VPPN_WIDTH 19
`define CSR_TLBEHI_0_WIDTH 13

`define PALEN 32
`define CSR_TLBELO0 14'h0012
`define CSR_TLBELO0_V 0
`define CSR_TLBELO0_D 1
`define CSR_TLBELO0_PLV 3:2
`define CSR_TLBELO0_MAT 5:4
`define CSR_TLBELO0_G 6
`define CSR_TLBELO0_0_LO 7
`define CSR_TLBELO0_PPN `PALEN-5:8
`define CSR_TLBELO0_0_HI 31:`PALEN-4
`define CSR_TLBELO0_0_LO_WIDTH 1
// `define CSR_TLBELO0_PPN_WIDTH `PALEN-5-8+1
// `define CSR_TLBELO0_0_HI_WIDTH 31-(`PALEN-4)+1

`define CSR_TLBELO1 14'h0013
`define CSR_TLBELO1_V 0
`define CSR_TLBELO1_D 1
`define CSR_TLBELO1_PLV 3:2
`define CSR_TLBELO1_MAT 5:4
`define CSR_TLBELO1_G 6
`define CSR_TLBELO1_0_LO 7
`define CSR_TLBELO1_PPN `PALEN-5:8
`define CSR_TLBELO1_0_HI 31:`PALEN-4
`define CSR_TLBELO1_0_LO_WIDTH 1
// `define CSR_TLBELO1_PPN_WIDTH `PALEN-5-8+1
// `define CSR_TLBELO1_0_HI_WIDTH 31-(`PALEN-4)+1

`define CSR_ASID 14'h0018
`define CSR_ASID_ASID 9:0
`define CSR_ASID_0_LO 15:10
`define CSR_ASID_ASIDBITS 23:16
`define CSR_ASID_0_HI 31:24
`define CSR_ASID_ASID_WIDTH 10
`define CSR_ASID_ASIDBITS_WIDTH 8
`define CSR_ASID_0_LO_WIDTH 6
`define CSR_ASID_0_HI_WIDTH 8

`define CSR_CPUID 14'h0020
`define CSR_CPUID_COREID 8:0
`define CSR_CPUID_0 31:9
`define CSR_CPUID_0_WIDTH 23

`define COREID_WIDTH 9
`define COREID 9'b0

`define CSR_SAVE0 14'h0030
`define CSR_SAVE1 14'h0031
`define CSR_SAVE2 14'h0032
`define CSR_SAVE3 14'h0033
`define CSR_SAVE_DATA 31:0

`define CSR_TID 14'h0040
`define CSR_TID_TID 31:0

`define CSR_TCFG 14'h0041
`define CSR_TCFG_EN 0
`define CSR_TCFG_PERIODIC 1
`define CSR_TCFG_INITVAL 31:2

`define CSR_TVAL 14'h0042
`define CSR_TVAL_TVAL 31:0
`define CSR_TVAL_TVAL_WIDTH 32
`define CSR_TVAL_TVAL_INIT 32'hffffffff

`define CSR_TICLR 14'h0044
`define CSR_TICLR_CLR 0
`define CSR_TICLR_0 31:1
`define CSR_TICLR_0_WIDTH 31

`define CSR_TLBRENTRY 14'h0088
`define CSR_TLBRENTRY_0 5:0
`define CSR_TLBRENTRY_PA 31:6
`define CSR_TLBRENTRY_0_WIDTH 6

`define CSR_DMW0 14'h0180
`define CSR_DMW1 14'h0181
`define CSR_DMW_PLV0 0
`define CSR_DMW_0_LO 2:1
`define CSR_DMW_PLV3 3
`define CSR_DMW_MAT 5:4
`define CSR_DMW_0_MD 24:6
`define CSR_DMW_PSEG 27:25
`define CSR_DMW_0_HI 28
`define CSR_DMW_VSEG 31:29
`define CSR_DMW_PLV 3:0
`define CSR_DMW_PLV_WIDTH 4
`define CSR_DMW_PSEG_WIDTH 3
`define CSR_DMW_VSEG_WIDTH 3
`define CSR_DMW_MAT_WIDTH 2
`define CSR_DMW_0_LO_WIDTH 2
`define CSR_DMW_0_MD_WIDTH 19
`define CSR_DMW_0_HI_WIDTH 1

`define CSR_PGDL 14'h0019
`define CSR_PGDL_0 11:0
`define CSR_PGDL_BASE 31:12
`define CSR_PGDL_0_WIDTH 12

`define CSR_PGDH 14'h001a
`define CSR_PGDH_0 11:0
`define CSR_PGDH_BASE 31:12
`define CSR_PGDH_0_WIDTH 12

`define CSR_PGD 14'h001b
`define CSR_PGD_0 11:0
`define CSR_PGD_BASE 31:12
`define CSR_PGD_0_WIDTH 12

`define ETYPE_WIDTH 6
`define ETYPE_INT 0
`define ETYPE_FETCH_ADEF 1
`define ETYPE_FETCH_TLB 2
`define ETYPE_DECODE 3
`define ETYPE_EXECUTE_ALE 4
`define ETYPE_EXECUTE_TLB 5

`define PPN_4KB_LSB 12
`define PPN_4MB_LSB 21
`define VPPN_4KB_LSB 13
`define VPPN_4MB_LSB 22

`define TLB_OP_WIDTH 11
`define TLB_OP_SRCH 0
`define TLB_OP_READ 1
`define TLB_OP_WRITE 2
`define TLB_OP_FILL 3
`define TLB_OP_INV 10:4
`define TLB_INVOP_WIDTH 7

`define VPPN_WIDTH 19 
`define TLBEHI_WIDTH (1+10+1+6+`VPPN_WIDTH)
`define TLBEHI_E 0
`define TLBEHI_ASID 10:1
`define TLBEHI_G 11
`define TLBEHI_PS 17:12
`define TLBEHI_VPPN `VPPN_WIDTH+17:18

`define PPN_WIDTH 20
`define TLBELO_WIDTH (1+1+2+2+`PPN_WIDTH)
`define TLBELO_V 0
`define TLBELO_D 1
`define TLBELO_MAT 3:2
`define TLBELO_PLV 5:4
`define TLBELO_PPN `PPN_WIDTH+5:6

`define CACOP_31_26 6'b000001
`define CACOP_25_24 2'b10
`define CACOP_23_22 2'b00

`define CACOP_OP_TYPE_MSB 4
`define CACOP_OP_TYPE_LSB 3
`define CACOP_TARGET_MSB 2
`define CACOP_TARGET_LSB 0

`define CACOP_TARGET_ICACHE 3'b000
`define CACOP_TARGET_DCACHE 3'b001
`define CACOP_TYPE_STORE_TAG 2'b00
`define CACOP_TYPE_INDEX_OP  2'b01
`define CACOP_TYPE_HIT_OP    2'b10

`define CACHE_TARGET_WIDTH 2
`define CACHE_TARGET_ICACHE 0
`define CACHE_TARGET_DCACHE 1

`define CACHE_OP_WIDTH 4
`define CACHE_OP_STORE_TAG 0
`define CACHE_OP_INDEX 1
`define CACHE_OP_INDEX_OP 1
`define CACHE_OP_HIT 2
`define CACHE_OP_HIT_OP 2
`define CACHE_OP_PRELD 3

`define CACHE_DATA_NUM           256
`define CACHE_WAY_NUM            2
`define CACHE_INDEX_WIDTH        8
`define CACHE_TAG_WIDTH          20
`define CACHE_OFFSET_WIDTH       4
`define CACHE_DATA_WIDTH         32
`define CACHE_STRB_WIDTH         4
`define CACHE_AW                 $clog2(`CACHE_DATA_NUM)
`define CACHE_LINE_BANKS   4
`define SRAM_SIZE_CACHE_LINE 2'b10

`define CSR_LLBCTL 14'h0060
`define CSR_LLBCTL_ROLLB 0
`define CSR_LLBCTL_WCLLB 1
`define CSR_LLBCTL_KLO 2
`define CSR_LLBCTL_0 31:3
`define CSR_LLBCTL_0_WIDTH 29

`define PRELD_31_26 6'b001010
`define PRELD_25_24 2'b10
`define PRELD_23_22 2'b11

`define DBAR_31_26 6'b001110
`define DBAR_25_24 2'b00
`define DBAR_23_22 2'b01
`define DBAR_21_20 2'b11
`define DBAR_19_15 5'b00100

`define IBAR_31_26 6'b001110
`define IBAR_25_24 2'b00
`define IBAR_23_22 2'b01
`define IBAR_21_20 2'b11
`define IBAR_19_15 5'b00101

`define MEM_BAR_WIDTH 2
`define MEM_BAR_INST 0
`define MEM_BAR_DATA 1

`define BTBNUM 32
`define RASNUM 16 
//`endif
