// TLB.v
`include "constant.v"
`include "instr_code.v"

module TLB
#(
    parameter TLBNUM = 16  // TLB条目数量，默认16项，必须为2的幂
)
(
    input  wire                      clk,  // 时钟信号

    // search port
    input  wire [31:`VPPN_4KB_LSB] s_vppn,
    input  wire [                    9:0] s_asid,
    output wire                           s_hit,
    output wire [$clog2(TLBNUM)-1:0]      s_index,

    // ========== 搜索端口0（用于取指阶段） ==========
    input  wire [31:`VPPN_4KB_LSB] s0_vppn,
    input  wire                      s0_va_bit12,
    input  wire [               9:0] s0_asid,
    output wire                      s0_found,
    output wire [$clog2(TLBNUM)-1:0] s0_index,
    output wire [31:`PPN_4KB_LSB] s0_ppn,
    output wire [               5:0] s0_ps,
    output wire [               1:0] s0_plv,
    output wire [               1:0] s0_mat,
    output wire                      s0_d,
    output wire                      s0_v,

    // ========== 搜索端口1（用于加载/存储阶段） ==========
    input  wire [31:`VPPN_4KB_LSB] s1_vppn,
    input  wire                      s1_va_bit12,
    input  wire [               9:0] s1_asid,
    output wire                      s1_found,
    output wire [$clog2(TLBNUM)-1:0] s1_index,
    output wire [31:`PPN_4KB_LSB] s1_ppn,
    output wire [               5:0] s1_ps,
    output wire [               1:0] s1_plv,
    output wire [               1:0] s1_mat,
    output wire                      s1_d,
    output wire                      s1_v,

    // ========== 写端口 ==========
    input  wire                      we,
    input  wire [$clog2(TLBNUM)-1:0] w_index,
    input  wire                      w_e,
    input  wire [31:`VPPN_4KB_LSB] w_vppn,
    input  wire [               5:0] w_ps,
    input  wire [               9:0] w_asid,
    input  wire                      w_g,
    input  wire [31:`PPN_4KB_LSB] w_ppn0,
    input  wire [               1:0] w_plv0,
    input  wire [               1:0] w_mat0,
    input  wire                      w_d0,
    input  wire                      w_v0,
    input  wire [31:`PPN_4KB_LSB] w_ppn1,
    input  wire [               1:0] w_plv1,
    input  wire [               1:0] w_mat1,
    input  wire                      w_d1,
    input  wire                      w_v1,

    // ========== 读端口 ==========
    input  wire [$clog2(TLBNUM)-1:0] r_index,
    output wire                      r_e,
    output wire [31:`VPPN_4KB_LSB] r_vppn,
    output wire [               5:0] r_ps,
    output wire [               9:0] r_asid,
    output wire                      r_g,
    output wire [31:`PPN_4KB_LSB] r_ppn0,
    output wire [               1:0] r_plv0,
    output wire [               1:0] r_mat0,
    output wire                      r_d0,
    output wire                      r_v0,
    output wire [31:`PPN_4KB_LSB] r_ppn1,
    output wire [               1:0] r_plv1,
    output wire [               1:0] r_mat1,
    output wire                      r_d1,
    output wire                      r_v1,

    // INVTLB
    input  wire [10:4]   inv_op,
    input  wire [9:0]   inv_asid,
    input  wire [31:`VPPN_4KB_LSB]  inv_va,
    
    // PLRU牺牲项输出（用于TLB缺失重填）
    output wire [$clog2(TLBNUM)-1:0] victim,
    
    // TLB缺失信号（用于触发PLRU更新）
    input  wire inst_tlbr,
    input  wire data_tlbr
);

// 页表项
reg  [TLBNUM-1:0] tlb_e;
reg  [TLBNUM-1:0] tlb_ps4MB;
reg  [31:`VPPN_4KB_LSB] tlb_vppn     [TLBNUM-1:0];
reg  [       9:0] tlb_asid     [TLBNUM-1:0];
reg  [TLBNUM-1:0] tlb_g;
reg  [31:`PPN_4KB_LSB] tlb_ppn0     [TLBNUM-1:0];
reg  [       1:0] tlb_plv0     [TLBNUM-1:0];
reg  [       1:0] tlb_mat0     [TLBNUM-1:0];
reg  [TLBNUM-1:0] tlb_d0;
reg  [TLBNUM-1:0] tlb_v0;
reg  [31:`PPN_4KB_LSB] tlb_ppn1     [TLBNUM-1:0];
reg  [       1:0] tlb_plv1     [TLBNUM-1:0];
reg  [       1:0] tlb_mat1     [TLBNUM-1:0];
reg  [TLBNUM-1:0] tlb_d1;
reg  [TLBNUM-1:0] tlb_v1;

// PLRU二叉树节点
localparam PLRU_NODES = TLBNUM - 1;
reg  [PLRU_NODES-1:0] plru_tree;  // PLRU树节点，0表示向左，1表示向右

// 命中信号
wire [TLBNUM - 1: 0] match0;
wire [TLBNUM - 1: 0] match1;
wire [TLBNUM - 1: 0] match;

// 无效化信号
wire inv_match_asid [TLBNUM - 1:0];
wire inv_match_va [TLBNUM - 1:0];
wire do_inv [TLBNUM - 1:0];

// 奇偶选择信号
wire s0_odd;
wire s1_odd;

// PLRU更新请求
wire update_plru_req;
reg  [$clog2(TLBNUM)-1:0] update_index;

// ========== PLRU树操作函数 ==========

// 获取父节点索引
function integer get_parent;
    input integer node;
    begin
        get_parent = (node - 1) >> 1;
    end
endfunction

// 获取左子节点索引
function integer get_left_child;
    input integer node;
    begin
        get_left_child = (node << 1) + 1;
    end
endfunction

// 获取右子节点索引
function integer get_right_child;
    input integer node;
    begin
        get_right_child = (node << 1) + 2;
    end
endfunction

// 判断节点是否为左子节点
function integer is_left_child;
    input integer node;
    begin
        is_left_child = (node & 1);
    end
endfunction

// 遍历PLRU树，找到牺牲项索引
function automatic [$clog2(TLBNUM)-1:0] get_victim;
    integer node;
    begin
        node = 0;
        while (node < PLRU_NODES) begin
            if (plru_tree[node])
                node = get_right_child(node);
            else
                node = get_left_child(node);
        end
        get_victim = node - PLRU_NODES;
    end
endfunction

// 更新PLRU树
function automatic update_plru;
    input integer accessed_index;
    integer node;
    begin
        node = PLRU_NODES + accessed_index;
        while (node > 0) begin
            node = get_parent(node);
            if (node < PLRU_NODES) begin
                if (is_left_child(node))
                    plru_tree[node] <= 1'b1;
                else
                    plru_tree[node] <= 1'b0;
            end
        end
    end
endfunction

// ========== TLB读操作 ==========
assign r_vppn = tlb_vppn[r_index];
assign r_ps   = (tlb_ps4MB[r_index] ? 22 : 12);
assign r_g    = tlb_g[r_index];
assign r_asid = tlb_asid[r_index];
assign r_e    = tlb_e[r_index];
assign r_ppn0 = tlb_ppn0[r_index];
assign r_plv0 = tlb_plv0[r_index];
assign r_mat0 = tlb_mat0[r_index];
assign r_d0   = tlb_d0[r_index];
assign r_v0   = tlb_v0[r_index];
assign r_ppn1 = tlb_ppn1[r_index];
assign r_plv1 = tlb_plv1[r_index];
assign r_mat1 = tlb_mat1[r_index];
assign r_d1   = tlb_d1[r_index];
assign r_v1   = tlb_v1[r_index];

// ========== TLB写操作和无效化 ==========
genvar i;
generate
    for (i = 0; i < TLBNUM; i = i + 1) begin : gen_tlb_entry
        always @(posedge clk) begin
            // TLB write
            if (we & (w_index == i)) begin
                tlb_vppn[i] <= w_vppn;
                tlb_ps4MB[i]   <= (w_ps > 12);
                tlb_g[i]    <= w_g;
                tlb_asid[i] <= w_asid;
                tlb_e[i]    <= w_e;
                tlb_ppn0[i] <= w_ppn0;
                tlb_plv0[i] <= w_plv0;
                tlb_mat0[i] <= w_mat0;
                tlb_d0[i]   <= w_d0;
                tlb_v0[i]   <= w_v0;
                tlb_ppn1[i] <= w_ppn1;
                tlb_plv1[i] <= w_plv1;
                tlb_mat1[i] <= w_mat1;
                tlb_d1[i]   <= w_d1;
                tlb_v1[i]   <= w_v1;
            end 
            // TLB invalidation
            else if(do_inv[i]) begin
                tlb_e[i] <= 1'b0;
            end
        end
        
        // TLB lookup match signals
        assign match[i] = tlb_e[i] & (tlb_g[i] | tlb_asid[i] == s_asid) &
                            (tlb_ps4MB[i] ? 
                                tlb_vppn[i][31:`VPPN_4MB_LSB] == s_vppn[31:`VPPN_4MB_LSB] :
                                tlb_vppn[i][31:`VPPN_4KB_LSB] == s_vppn[31:`VPPN_4KB_LSB]);
        
        assign match0[i] = tlb_e[i] & (tlb_g[i] | tlb_asid[i] == s0_asid) &
                            (tlb_ps4MB[i] ? 
                                tlb_vppn[i][31:`VPPN_4MB_LSB] == s0_vppn[31:`VPPN_4MB_LSB] :
                                tlb_vppn[i][31:`VPPN_4KB_LSB] == s0_vppn[31:`VPPN_4KB_LSB]);
        
        assign match1[i] = tlb_e[i] & (tlb_g[i] | tlb_asid[i] == s1_asid) &
                            (tlb_ps4MB[i] ? 
                                tlb_vppn[i][31:`VPPN_4MB_LSB] == s1_vppn[31:`VPPN_4MB_LSB] :
                                tlb_vppn[i][31:`VPPN_4KB_LSB] == s1_vppn[31:`VPPN_4KB_LSB]);
        
        // INV操作匹配信号
        assign inv_match_asid[i] = (inv_asid == tlb_asid[i]);
        
        assign inv_match_va[i] = (tlb_ps4MB[i] ? 
                                    tlb_vppn[i][31:`VPPN_4MB_LSB] == inv_va[31:`VPPN_4MB_LSB] :
                                    tlb_vppn[i][31:`VPPN_4KB_LSB] == inv_va[31:`VPPN_4KB_LSB]);
        
        assign do_inv[i] = 
                    (inv_op[4] | inv_op[5]) |
                    (inv_op[6] & tlb_g[i]) |
                    (inv_op[7] & ~tlb_g[i]) |
                    (inv_op[8] & ~tlb_g[i] & inv_match_asid[i]) |
                    (inv_op[9] & ~tlb_g[i] & inv_match_asid[i] & inv_match_va[i]) |
                    (inv_op[10] & (tlb_g[i] | inv_match_asid[i]) & inv_match_va[i]);
    end
endgenerate

// ========== PLRU更新逻辑 ==========
// 当TLB命中时更新PLRU
wire s0_hit;
wire s1_hit;

assign s0_hit = s0_found & s0_v;
assign s1_hit = s1_found & s1_v;

// 选择需要更新的索引（优先数据访问）
assign update_plru_req = s0_hit | s1_hit;

always @(posedge clk) begin
    if (s1_hit) begin
        update_plru(s1_index);
    end else if (s0_hit) begin
        update_plru(s0_index);
    end
end

// ========== 输出PLRU牺牲项 ==========
// 组合逻辑输出当前最久未使用的TLB项
assign victim = get_victim();

// ========== 搜索端口0输出 ==========
assign s0_found = |match0;
encoder #(
    .WIDTH(TLBNUM)
) encoder_s0 (
    .in (match0),
    .out(s0_index)
);
assign s0_ps  = tlb_ps4MB[s0_index] ? 22 : 12;
assign s0_odd = tlb_ps4MB[s0_index] ? s0_vppn[`VPPN_4MB_LSB-1] : s0_va_bit12;
assign s0_ppn = s0_odd ? tlb_ppn1[s0_index] : tlb_ppn0[s0_index];
assign s0_plv = s0_odd ? tlb_plv1[s0_index] : tlb_plv0[s0_index];
assign s0_mat = s0_odd ? tlb_mat1[s0_index] : tlb_mat0[s0_index];
assign s0_d   = s0_odd ? tlb_d1[s0_index] : tlb_d0[s0_index];
assign s0_v   = s0_odd ? tlb_v1[s0_index] : tlb_v0[s0_index];

// ========== 搜索端口1输出 ==========
assign s1_found = |match1;
encoder #(
    .WIDTH(TLBNUM)
) encoder_s1 (
    .in (match1),
    .out(s1_index)
);
assign s1_ps  = tlb_ps4MB[s1_index] ? 22 : 12;
assign s1_odd = tlb_ps4MB[s1_index] ? s1_vppn[`VPPN_4MB_LSB-1] : s1_va_bit12;
assign s1_ppn = s1_odd ? tlb_ppn1[s1_index] : tlb_ppn0[s1_index];
assign s1_plv = s1_odd ? tlb_plv1[s1_index] : tlb_plv0[s1_index];
assign s1_mat = s1_odd ? tlb_mat1[s1_index] : tlb_mat0[s1_index];
assign s1_d   = s1_odd ? tlb_d1[s1_index] : tlb_d0[s1_index];
assign s1_v   = s1_odd ? tlb_v1[s1_index] : tlb_v0[s1_index];

// ========== 搜索端口（通用）输出 ==========
encoder #(
    .WIDTH(TLBNUM)
) encoder_s (
    .in (match),
    .out(s_index)
);
assign s_hit = |match;

endmodule //TLB