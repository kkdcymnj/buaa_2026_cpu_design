// MMU.v
`include "constant.v"
`include "instr_code.v"

module MMU #(
    parameter TLBNUM = 16
) (
    // 时钟信号
    input  wire clk,
    // TLB操作
    input  wire [`TLB_OP_WIDTH-1:0] TLB_operation,
    input  wire [31:`VPPN_4KB_LSB] invtlb_vaddr,
    input  wire [9:0] invtlb_asid,
    input  wire [$clog2(TLBNUM)-1:0] TLB_rw_index,
    input  wire [`TLBEHI_WIDTH-1:0] TLB_sw_hi,
    input  wire [`TLBELO_WIDTH-1:0] TLB_w_lo0,
    input  wire [`TLBELO_WIDTH-1:0] TLB_w_lo1,
    input  wire [$clog2(TLBNUM)-1:0] TLB_f_index,
    output wire TLB_s_hit,
    output wire [$clog2(TLBNUM)-1:0] TLB_s_index,
    output wire [`TLBEHI_WIDTH-1:0] TLB_r_hi,
    output wire [`TLBELO_WIDTH-1:0] TLB_r_lo0,
    output wire [`TLBELO_WIDTH-1:0] TLB_r_lo1,
    // csr信息
    input  wire csr_da,
    input  wire csr_pg,
    input  wire [9:0]   csr_asid,
    input  wire [1:0]   csr_plv,
    input  wire csr_datf,
    input  wire csr_datm,
    // dmw配置信息
    input  wire [1:0]   dmw0_plv,
    input  wire [2:0]   dmw0_pseg,
    input  wire [2:0]   dmw0_vseg,
    input  wire [1:0]   dmw0_mat,
    input  wire [1:0]   dmw1_plv,
    input  wire [2:0]   dmw1_pseg,
    input  wire [2:0]   dmw1_vseg,
    input  wire [1:0]   dmw1_mat,
    // 取指令
    input  wire [2:0] inst_search_op,
    output  wire [31:0]  inst_paddr,
    input  wire [31:0]  inst_vaddr,
    // 取数据 
    input  wire [2:0] data_search_op,
    output  wire [31:0]  data_paddr,
    input  wire [31:0]  data_vaddr,
    // 例外
    output wire PIL,
    output wire PIS,
    output wire PIF,
    output wire PME,
    output wire inst_PPI,
    output wire data_PPI,
    output wire inst_TLBR,
    output wire data_TLBR,

    output wire inst_access_type,
    output wire data_access_type,

    output wire [$clog2(TLBNUM)-1:0] tlb_plru_victim_entry
);

assign tlb_plru_victim_entry = TLB_victim;

wire    data_tlb_hit;
wire    [$clog2(TLBNUM)-1:0]    data_tlb_index;
wire    [5:0]   data_tlb_ps;
wire    [31:`PPN_4KB_LSB]   data_tlb_ppn;
wire    [1:0]   data_tlb_plv;
wire    [1:0]   data_tlb_mat;
wire    data_tlb_d;
wire    data_tlb_v;

wire    inst_tlb_hit;
wire    [$clog2(TLBNUM)-1:0]    inst_tlb_index;
wire    [5:0]   inst_tlb_ps;
wire    [31:`PPN_4KB_LSB]   inst_tlb_ppn;
wire    [1:0]   inst_tlb_plv;
wire    [1:0]   inst_tlb_mat;
wire    inst_tlb_d;
wire    inst_tlb_v;

wire    [$clog2(TLBNUM)-1:0] TLB_wf_index;
wire    [$clog2(TLBNUM)-1:0] TLB_victim;

assign TLB_wf_index = 
        TLB_operation[`TLB_OP_FILL] ? TLB_f_index : TLB_rw_index ;

TLB #(
    .TLBNUM(TLBNUM)
) u_TLB(
    .clk          (clk          ),

    .s_vppn     (TLB_sw_hi[`TLBEHI_VPPN]),
    .s_asid     (TLB_sw_hi[`TLBEHI_ASID]),
    .s_hit      (TLB_s_hit),
    .s_index    (TLB_s_index),

    .s0_vppn      (inst_vaddr[31:`VPPN_4KB_LSB]),
    .s0_va_bit12  (inst_vaddr[12]),
    .s0_asid      (csr_asid),
    .s0_found     (inst_tlb_hit),
    .s0_index     (inst_tlb_index),
    .s0_ppn       (inst_tlb_ppn),
    .s0_ps        (inst_tlb_ps),
    .s0_plv       (inst_tlb_plv),
    .s0_mat       (inst_tlb_mat),
    .s0_d         (inst_tlb_d),
    .s0_v         (inst_tlb_v),

    .s1_vppn      (data_vaddr[31:`VPPN_4KB_LSB]),
    .s1_va_bit12  (data_vaddr[12]),
    .s1_asid      (csr_asid),
    .s1_found     (data_tlb_hit),
    .s1_index     (data_tlb_index),
    .s1_ppn       (data_tlb_ppn),
    .s1_ps        (data_tlb_ps),
    .s1_plv       (data_tlb_plv),
    .s1_mat       (data_tlb_mat),
    .s1_d         (data_tlb_d),
    .s1_v         (data_tlb_v),
    
    .we         (TLB_operation[`TLB_OP_WRITE] | TLB_operation[`TLB_OP_FILL]),
    .w_index    (TLB_wf_index),
    .w_vppn     (TLB_sw_hi[`TLBEHI_VPPN]),
    .w_ps       (TLB_sw_hi[`TLBEHI_PS]),
    .w_g        (TLB_sw_hi[`TLBEHI_G]),
    .w_asid     (TLB_sw_hi[`TLBEHI_ASID]),
    .w_e        (TLB_sw_hi[`TLBEHI_E]),
    .w_ppn0     (TLB_w_lo0[`TLBELO_PPN]),
    .w_plv0     (TLB_w_lo0[`TLBELO_PLV]),
    .w_mat0     (TLB_w_lo0[`TLBELO_MAT]),
    .w_d0       (TLB_w_lo0[`TLBELO_D]),
    .w_v0       (TLB_w_lo0[`TLBELO_V]),
    .w_ppn1     (TLB_w_lo1[`TLBELO_PPN]),
    .w_plv1     (TLB_w_lo1[`TLBELO_PLV]),
    .w_mat1     (TLB_w_lo1[`TLBELO_MAT]),
    .w_d1       (TLB_w_lo1[`TLBELO_D]),
    .w_v1       (TLB_w_lo1[`TLBELO_V]),

    .r_index    (TLB_rw_index),
    .r_vppn     (TLB_r_hi[`TLBEHI_VPPN]),
    .r_ps       (TLB_r_hi[`TLBEHI_PS]),
    .r_g        (TLB_r_hi[`TLBEHI_G]),
    .r_asid     (TLB_r_hi[`TLBEHI_ASID]),
    .r_e        (TLB_r_hi[`TLBEHI_E]),
    .r_ppn0     (TLB_r_lo0[`TLBELO_PPN]),
    .r_plv0     (TLB_r_lo0[`TLBELO_PLV]),
    .r_mat0     (TLB_r_lo0[`TLBELO_MAT]),
    .r_d0       (TLB_r_lo0[`TLBELO_D]),
    .r_v0       (TLB_r_lo0[`TLBELO_V]),
    .r_ppn1     (TLB_r_lo1[`TLBELO_PPN]),
    .r_plv1     (TLB_r_lo1[`TLBELO_PLV]),
    .r_mat1     (TLB_r_lo1[`TLBELO_MAT]),
    .r_d1       (TLB_r_lo1[`TLBELO_D]),
    .r_v1       (TLB_r_lo1[`TLBELO_V]),

    .inv_op       (TLB_operation[10:4]),
    .inv_asid     (invtlb_asid),
    .inv_va       (invtlb_vaddr),
    
    // PLRU牺牲项输出（用于TLB缺失重填）
    .victim       (TLB_victim),
    
    // TLB缺失信号
    .inst_tlbr    (inst_TLBR),
    .data_tlbr    (data_TLBR)
);

// 地址直接翻译模式
wire direct_mode = csr_da & ~csr_pg;

// 虚实地址转换
wire inst_dmw0_hit = (inst_vaddr[31:29] == dmw0_vseg) & (dmw0_plv >= csr_plv);
wire inst_dmw1_hit = (inst_vaddr[31:29] == dmw1_vseg) & (dmw1_plv >= csr_plv);
assign inst_paddr = 
        direct_mode ? inst_vaddr :
        inst_dmw0_hit ? {dmw0_pseg, inst_vaddr[28:0]} :
        inst_dmw1_hit ? {dmw1_pseg, inst_vaddr[28:0]} :
        inst_tlb_ps == 12 ? {inst_tlb_ppn[31:`PPN_4KB_LSB], inst_vaddr[11:0]} :
        {inst_tlb_ppn[31:`PPN_4MB_LSB], inst_vaddr[20:0]};

wire data_dmw0_hit = (data_vaddr[31:29] == dmw0_vseg) & (dmw0_plv >= csr_plv);
wire data_dmw1_hit = (data_vaddr[31:29] == dmw1_vseg) & (dmw1_plv >= csr_plv);
assign data_paddr = 
        direct_mode ? data_vaddr :
        data_dmw0_hit ? {dmw0_pseg, data_vaddr[28:0]} :
        data_dmw1_hit ? {dmw1_pseg, data_vaddr[28:0]} :
        data_tlb_ps == 12 ? {data_tlb_ppn[31:`PPN_4KB_LSB], data_vaddr[11:0]} :
        {data_tlb_ppn[31:`PPN_4MB_LSB], data_vaddr[20:0]};

// 异常
assign PIL = data_search_op[1] & ~direct_mode & ~data_dmw0_hit & ~data_dmw1_hit &
                data_tlb_hit & ~data_tlb_v;
assign PIS = data_search_op[2] & ~direct_mode & ~data_dmw0_hit & ~data_dmw1_hit &
                data_tlb_hit & ~data_tlb_v;
assign PIF = inst_search_op[1] & ~direct_mode & ~inst_dmw0_hit & ~inst_dmw1_hit &
                inst_tlb_hit & ~inst_tlb_v;
assign PME = data_search_op[2] & ~direct_mode & ~data_dmw0_hit & ~data_dmw1_hit &
                data_tlb_hit & data_tlb_v & (csr_plv <= data_tlb_plv) & ~data_tlb_d;
assign inst_PPI = inst_search_op[1] & ~direct_mode & ~inst_dmw0_hit & ~inst_dmw1_hit &
                    inst_tlb_hit & inst_tlb_v & (csr_plv > inst_tlb_plv);
assign data_PPI = |data_search_op[2:1] & ~direct_mode & ~data_dmw0_hit & ~data_dmw1_hit &
                    data_tlb_hit & data_tlb_v & (csr_plv > data_tlb_plv);
assign inst_TLBR = 
    inst_search_op[1] & ~direct_mode & ~inst_dmw0_hit & ~inst_dmw1_hit & ~inst_tlb_hit;
assign data_TLBR = 
    |data_search_op[2:1] & ~direct_mode & ~data_dmw0_hit & ~data_dmw1_hit 
    & ~data_tlb_hit;

// 0: 强序非缓存, 1: 一致可缓存
assign inst_access_type = 
    direct_mode ? csr_datf :
    inst_dmw0_hit ? dmw0_mat :
    inst_dmw1_hit ? dmw1_mat :
    inst_tlb_mat;
    
assign data_access_type = 
    direct_mode ? csr_datm :
    data_dmw0_hit ? dmw0_mat :
    data_dmw1_hit ? dmw1_mat :
    data_tlb_mat;

endmodule //MMU