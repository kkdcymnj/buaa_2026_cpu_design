`include "constant.v"

`define PC_TAG_HIGH 24
`define PC_TAG_LOW  10
`define PC_INDEX_HIGH 11
`define PC_INDEX_LOW  2

module predict_tage #(
    parameter BTBNUM            = 1024,          // BTB条目数
    parameter RASNUM            = 32,            // RAS深度
    parameter GHISTORY_WIDTH    = 64,            // 全局历史最大宽度
    // TAGE 参数
    parameter TAGE_TABLES       = 5,             // T0-T4共5个表 (不包含基础预测器)
    parameter BASE_PHT_DEPTH    = 1024,          // 基础预测器PHT深度
    parameter TAG_WIDTH         = 10,            // Tag位宽
    parameter USEFUL_WIDTH      = 2,             // 有用计数器位宽 (2-bit)
    parameter PRED_WIDTH        = 3,             // 预测计数器位宽改为3位
    parameter AGING_PERIOD      = 256 * 1024     // 256K 个分支指令
) (
    input  wire clk,
    input  wire reset,

    input  wire        inst_fetch,
    input  wire [31:0] fetch_pc,
    output wire [31:0] btb_pc,
    output wire        btb_taken,
    output wire        btb_enable,
    output wire [$clog2(BTBNUM)-1:0] btb_index,

    input  wire        operate_enable,
    input  wire        ras_push_call,
    input  wire        ras_pop_return,
    input  wire [31:0] operate_pc,
    input  wire [$clog2(BTBNUM)-1:0] operate_btb_index,
    input  wire        add_entry,
    input  wire        delete_entry,
    input  wire [31:0] right_target,
    input  wire        target_error,
    input  wire        predict_error,
    input  wire        predict_correct,
    input  wire        right_orien
);

// ==================== 参数计算 ====================
// 每个TAGE表的历史长度 (几何递增: 4,8,16,32,64)
wire [31:0] TABLE_HIST_LEN [0:TAGE_TABLES-1];
generate
    genvar g_t;
    for (g_t = 0; g_t < TAGE_TABLES; g_t = g_t + 1) begin : gen_hist_len
        case (g_t)
            0: assign TABLE_HIST_LEN[g_t] = 4;
            1: assign TABLE_HIST_LEN[g_t] = 8;
            2: assign TABLE_HIST_LEN[g_t] = 16;
            3: assign TABLE_HIST_LEN[g_t] = 32;
            4: assign TABLE_HIST_LEN[g_t] = 64;
            default: assign TABLE_HIST_LEN[g_t] = 4;
        endcase
    end
endgenerate

localparam PHT_WIDTH = 10;
localparam PHT_DEPTH = 1 << PHT_WIDTH;

// 预测计数器为3位，饱和值为7 (3'b111)
localparam PRED_SATURATED = 3'b111;
localparam PRED_WEAK_LOW  = 3'b011;   // 弱信心下限
localparam PRED_WEAK_HIGH = 3'b100;   // 弱信心上限

// ==================== TAGE表项结构 ====================
typedef struct packed {
    logic valid;
    logic [TAG_WIDTH-1:0] tag;
    logic [PRED_WIDTH-1:0] pred;
    logic [USEFUL_WIDTH-1:0] useful;
} tage_entry_t;

tage_entry_t tage_table [0:TAGE_TABLES-1][0:PHT_DEPTH-1];

// ==================== 基础预测器 ====================
reg [PRED_WIDTH-1:0] base_pht [0:BASE_PHT_DEPTH-1];

// ==================== 全局历史寄存器 ====================
reg [GHISTORY_WIDTH-1:0] global_history;
wire [GHISTORY_WIDTH-1:0] next_global_history;
wire [GHISTORY_WIDTH-1:0] update_global_history;

assign next_global_history = {right_orien, global_history[GHISTORY_WIDTH-1:1]};
assign update_global_history = (predict_error || predict_correct || add_entry || target_error) ? 
                                next_global_history : global_history;

// ==================== 老化计数器 ====================
reg [17:0] branch_counter;     // 2^18 = 262144 > 256K
reg        aging_phase;        // 0: 重置 MSB, 1: 重置 LSB
reg        aging_enable;

// ==================== 辅助函数 ====================
function [PHT_WIDTH-1:0] fold_history;
    input [GHISTORY_WIDTH-1:0] history;
    input int hist_len;
    begin
        int f_i;
        int bit_idx;
        fold_history = 0;
        for (f_i = 0; f_i < GHISTORY_WIDTH; f_i = f_i + hist_len) begin
            if (f_i + hist_len <= GHISTORY_WIDTH) begin
                for (bit_idx = 0; bit_idx < hist_len; bit_idx = bit_idx + 1) begin
                    if (history[f_i + bit_idx])
                        fold_history = fold_history ^ (1 << bit_idx);
                end
            end else begin
                for (bit_idx = 0; f_i + bit_idx < GHISTORY_WIDTH; bit_idx = bit_idx + 1) begin
                    if (history[f_i + bit_idx])
                        fold_history = fold_history ^ (1 << bit_idx);
                end
            end
        end
        fold_history = fold_history & ((1 << PHT_WIDTH) - 1);
    end
endfunction

function [PHT_WIDTH-1:0] hash_pc;
    input [31:0] pc;
    begin
        hash_pc = pc[31:22] ^ pc[21:12] ^ pc[11:2];
        hash_pc = hash_pc & ((1 << PHT_WIDTH) - 1);
    end
endfunction

function [PHT_WIDTH-1:0] calc_index;
    input [PHT_WIDTH-1:0] pc_hash;
    input [PHT_WIDTH-1:0] folded_hist;
    begin
        calc_index = pc_hash ^ folded_hist;
    end
endfunction

function [TAG_WIDTH-1:0] calc_tag;
    input [31:0] pc;
    input [GHISTORY_WIDTH-1:0] history;
    input int hist_len;
    begin
        logic [TAG_WIDTH-1:0] pc_high;
        logic [TAG_WIDTH-1:0] hist_folded;
        pc_high = pc[31:22] ^ pc[21:12];
        hist_folded = fold_history(history, hist_len);
        calc_tag = pc_high ^ hist_folded;
        calc_tag = calc_tag & ((1 << TAG_WIDTH) - 1);
    end
endfunction

// ==================== 当前操作PC相关信号 ====================
wire [PHT_WIDTH-1:0] pc_hash_op;
wire [PHT_WIDTH-1:0] base_index_op;
wire [PRED_WIDTH-1:0] base_pred_op;

wire [PHT_WIDTH-1:0] tage_index_op [0:TAGE_TABLES-1];
wire [TAG_WIDTH-1:0] tage_tag_op [0:TAGE_TABLES-1];
wire [TAGE_TABLES-1:0] tage_hit_op;  
wire [PRED_WIDTH-1:0] tage_pred_op [0:TAGE_TABLES-1];
wire [USEFUL_WIDTH-1:0] tage_useful_op [0:TAGE_TABLES-1];

assign pc_hash_op = hash_pc(operate_pc);
assign base_index_op = pc_hash_op;
assign base_pred_op = base_pht[base_index_op];

generate
    for (genvar g_t1 = 0; g_t1 < TAGE_TABLES; g_t1 = g_t1 + 1) begin : gen_tage_op
        wire [PHT_WIDTH-1:0] folded_hist;
        assign folded_hist = fold_history(global_history, TABLE_HIST_LEN[g_t1]);
        assign tage_index_op[g_t1] = calc_index(pc_hash_op, folded_hist);
        assign tage_tag_op[g_t1] = calc_tag(operate_pc, global_history, TABLE_HIST_LEN[g_t1]);
        assign tage_hit_op[g_t1] = tage_table[g_t1][tage_index_op[g_t1]].valid && 
                                 (tage_table[g_t1][tage_index_op[g_t1]].tag == tage_tag_op[g_t1]);
        assign tage_pred_op[g_t1] = tage_table[g_t1][tage_index_op[g_t1]].pred;
        assign tage_useful_op[g_t1] = tage_table[g_t1][tage_index_op[g_t1]].useful;
    end
endgenerate

// ==================== Fetch级信号 ====================
reg [31:0] fetch_pc_buffer;
reg fetch_en_buffer;

wire [PHT_WIDTH-1:0] pc_hash_fetch;
wire [PHT_WIDTH-1:0] base_index_fetch;
wire [PRED_WIDTH-1:0] base_pred_fetch;

wire [PHT_WIDTH-1:0] tage_index_fetch [0:TAGE_TABLES-1];
wire [TAGE_TABLES-1:0] tage_hit_fetch;
wire [PRED_WIDTH-1:0] tage_pred_fetch [0:TAGE_TABLES-1];
wire [USEFUL_WIDTH-1:0] tage_useful_fetch [0:TAGE_TABLES-1];

// ==================== BTB和RAS ====================
reg [14:0] btb_tag [0:BTBNUM-1];
reg [29:0] btb_target [0:BTBNUM-1];
reg [BTBNUM-1:0] btb_valid;

wire [$clog2(BTBNUM)-1:0] btb_add_entry_index;
assign btb_add_entry_index = operate_pc[`PC_INDEX_HIGH : `PC_INDEX_LOW];

reg [29:0] ras_stack [0:RASNUM-1];
reg [$clog2(RASNUM)-1:0] ras_ptr;
reg ras_empty;

always @(posedge clk) begin
    if (reset) begin
        ras_ptr <= 0;
        ras_empty <= 1'b1;
        for (integer r = 0; r < RASNUM; r = r + 1) begin
            ras_stack[r] = 30'b0;
        end
    end else if (operate_enable) begin
        if (ras_push_call) begin
            ras_stack[ras_ptr] <= operate_pc[31:2] + 30'b1;
            ras_ptr <= ras_ptr + 1'b1;
            ras_empty <= 1'b0;
        end else if (ras_pop_return && !ras_empty) begin
            ras_ptr <= ras_ptr - 1'b1;
            if (ras_ptr - 1'b1 == 0) begin
                ras_empty <= 1'b1;
            end
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        fetch_en_buffer <= 1'b0;
    end else begin
        fetch_en_buffer <= inst_fetch;
    end
    if (inst_fetch) begin
        fetch_pc_buffer <= fetch_pc;
    end
end

wire [$clog2(BTBNUM)-1:0] fetch_btb_index;
assign fetch_btb_index = fetch_pc_buffer[`PC_INDEX_HIGH : `PC_INDEX_LOW];

wire btb_match;
assign btb_match = fetch_en_buffer && btb_valid[fetch_btb_index] && 
                   (fetch_pc_buffer[`PC_TAG_HIGH:`PC_TAG_LOW] == btb_tag[fetch_btb_index]);

wire ras_match;
assign ras_match = fetch_en_buffer && ras_pop_return && !ras_empty;

// ==================== Fetch级TAGE预测值计算 ====================
assign pc_hash_fetch = hash_pc(fetch_pc_buffer);
assign base_index_fetch = pc_hash_fetch;
assign base_pred_fetch = base_pht[base_index_fetch];

generate
    for (genvar g_t2 = 0; g_t2 < TAGE_TABLES; g_t2 = g_t2 + 1) begin : gen_fetch_tage
        wire [PHT_WIDTH-1:0] folded_hist_fetch;
        assign folded_hist_fetch = fold_history(global_history, TABLE_HIST_LEN[g_t2]);
        assign tage_index_fetch[g_t2] = calc_index(pc_hash_fetch, folded_hist_fetch);
        assign tage_hit_fetch[g_t2] = tage_table[g_t2][tage_index_fetch[g_t2]].valid && 
                                    (tage_table[g_t2][tage_index_fetch[g_t2]].tag == 
                                     calc_tag(fetch_pc_buffer, global_history, TABLE_HIST_LEN[g_t2]));
        assign tage_pred_fetch[g_t2] = tage_table[g_t2][tage_index_fetch[g_t2]].pred;
        assign tage_useful_fetch[g_t2] = tage_table[g_t2][tage_index_fetch[g_t2]].useful;
    end
endgenerate

// ==================== 预测选择逻辑 ====================
wire [TAGE_TABLES:0] hit_mask;
wire [$clog2(TAGE_TABLES+1)-1:0] provider;
wire [$clog2(TAGE_TABLES+1)-1:0] alt_provider;
wire [PRED_WIDTH-1:0] alt_pred_value;
wire [PRED_WIDTH-1:0] main_pred_value;
wire use_alt;
wire [PRED_WIDTH-1:0] final_pred;

// 构建hit_mask (bit0=基础预测器, bit1=T0, bit2=T1, ..., bit5=T4)
assign hit_mask = {tage_hit_fetch[4], tage_hit_fetch[3], tage_hit_fetch[2],
                   tage_hit_fetch[1], tage_hit_fetch[0], 1'b1};

// 编码器：选择最长历史的命中表作为provider（最高位）
encoder #(.WIDTH(TAGE_TABLES+1)) u_encoder (
    .in(hit_mask),
    .out(provider)
);

// AltProvider选择：选择最近（历史最短）的命中表（除了provider本身）
wire [TAGE_TABLES+1-1:0] alt_candidate_mask;
assign alt_candidate_mask = hit_mask & ~(1 << provider);

encoder #(.WIDTH(TAGE_TABLES+1)) alt_encoder (
    .in(alt_candidate_mask),
    .out(alt_provider)
);

// 预测值选择
assign alt_pred_value = (alt_provider == 0) ? base_pred_fetch : 
                        tage_pred_fetch[alt_provider-1];

assign main_pred_value = (provider == 0) ? base_pred_fetch : 
                         tage_pred_fetch[provider-1];

// 信心判断：当provider不是基础预测器且provider的表项信心不足时，使用alt
// 修正：恢复 useful==0 的判断
wire provider_weak;
assign provider_weak = (provider > 0) && 
                       (tage_pred_fetch[provider-1] >= PRED_WEAK_LOW) && 
                       (tage_pred_fetch[provider-1] <= PRED_WEAK_HIGH);

assign use_alt = (provider > 0) && (provider_weak || (tage_useful_fetch[provider-1] == 0));
assign final_pred = use_alt ? alt_pred_value : main_pred_value;

// 最终分支方向
wire final_taken;
assign final_taken = final_pred[PRED_WIDTH-1];

// ==================== 更新逻辑 ====================
reg [PHT_WIDTH-1:0] update_base_idx;
reg [PRED_WIDTH-1:0] update_base_pred;
reg [PHT_WIDTH-1:0] update_tage_idx [0:TAGE_TABLES-1];
reg [TAG_WIDTH-1:0] update_tage_tag [0:TAGE_TABLES-1];
reg [PRED_WIDTH-1:0] update_tage_pred [0:TAGE_TABLES-1];
reg [TAGE_TABLES-1:0] update_tage_hit;
reg [USEFUL_WIDTH-1:0] update_tage_useful [0:TAGE_TABLES-1];
reg [TAGE_TABLES:0] update_provider;
reg [PRED_WIDTH-1:0] update_alt_pred;
reg update_use_alt;

// 新增：用于延迟更新的寄存器
reg [PHT_WIDTH-1:0] allocate_tage_idx [0:TAGE_TABLES-1];
reg [TAG_WIDTH-1:0] allocate_tage_tag [0:TAGE_TABLES-1];
reg allocate_entry;

integer i;
integer j;

always @(posedge clk) begin
    if (reset) begin
        btb_valid <= 0;
        global_history <= 0;
        
        // 老化计数器初始化
        branch_counter <= 0;
        aging_phase <= 0;
        aging_enable <= 0;
        
        // 基础预测器初始化为弱跳转
        for (i = 0; i < BASE_PHT_DEPTH; i = i + 1) begin
            base_pht[i] = PRED_WEAK_HIGH;
        end
        
        for (j = 0; j < TAGE_TABLES; j = j + 1) begin
            for (i = 0; i < PHT_DEPTH; i = i + 1) begin
                tage_table[j][i].valid = 1'b0;
                tage_table[j][i].tag = 0;
                tage_table[j][i].pred = PRED_WEAK_HIGH;
                tage_table[j][i].useful = 0;
            end
        end
        
        allocate_entry <= 1'b0;
    end 
    else if (operate_enable && !ras_pop_return) begin
        update_base_idx = base_index_op;
        update_base_pred = base_pred_op;
        for (j = 0; j < TAGE_TABLES; j = j + 1) begin
            update_tage_idx[j] = tage_index_op[j];
            update_tage_tag[j] = tage_tag_op[j];
            update_tage_pred[j] = tage_pred_op[j];
            update_tage_hit[j] = tage_hit_op[j];
            update_tage_useful[j] = tage_useful_op[j];
        end
        update_provider = provider;
        update_alt_pred = alt_pred_value;
        update_use_alt = use_alt;
        
        // 分支计数和老化触发
        if (add_entry || target_error || predict_error || predict_correct) begin
            if (branch_counter == AGING_PERIOD - 1) begin
                branch_counter <= 0;
                aging_enable <= 1'b1;
                aging_phase <= ~aging_phase;
            end else begin
                branch_counter <= branch_counter + 1'b1;
                aging_enable <= 1'b0;
            end
        end else begin
            aging_enable <= 1'b0;
        end
        
        if (add_entry) begin
            btb_valid[btb_add_entry_index] <= 1'b1;
            btb_tag[btb_add_entry_index] <= operate_pc[`PC_TAG_HIGH:`PC_TAG_LOW];
            btb_target[btb_add_entry_index] <= right_target[31:2];
        end else if (target_error) begin
            btb_target[operate_btb_index] <= right_target[31:2];
        end
        
        if (add_entry || target_error || predict_error || predict_correct) begin
            // 更新基础预测器
            if (right_orien) begin
                if (base_pht[update_base_idx] != PRED_SATURATED)
                    base_pht[update_base_idx] <= base_pht[update_base_idx] + 1'b1;
            end else begin
                if (base_pht[update_base_idx] != 0)
                    base_pht[update_base_idx] <= base_pht[update_base_idx] - 1'b1;
            end
            
            // 更新TAGE表
            for (j = 0; j < TAGE_TABLES; j = j + 1) begin
                if (update_tage_hit[j]) begin
                    // 更新预测计数器
                    if (right_orien) begin
                        if (update_tage_pred[j] != PRED_SATURATED)
                            tage_table[j][update_tage_idx[j]].pred = update_tage_pred[j] + 1'b1;
                    end else begin
                        if (update_tage_pred[j] != 0)
                            tage_table[j][update_tage_idx[j]].pred = update_tage_pred[j] - 1'b1;
                    end
                    
                    // Useful 计数器更新（仅当该表是 provider 且没有使用 altpred 时）
                    if (update_provider > 0 && j == update_provider - 1) begin
                        if (!update_use_alt) begin
                            if (update_alt_pred != main_pred_value) begin
                                // 修正：判断 provider 的预测是否正确（不是 final_taken）
                                logic provider_correct;
                                provider_correct = (main_pred_value[PRED_WIDTH-1] == right_orien);
                                
                                if (provider_correct) begin
                                    if (update_tage_useful[j] != ((1 << USEFUL_WIDTH) - 1))
                                        tage_table[j][update_tage_idx[j]].useful = update_tage_useful[j] + 1'b1;
                                end else begin
                                    if (update_tage_useful[j] != 0)
                                        tage_table[j][update_tage_idx[j]].useful = update_tage_useful[j] - 1'b1;
                                end
                            end
                        end
                    end
                end
            end
            
            // 分配新条目标记
            if (predict_error && (update_provider < TAGE_TABLES)) begin
                allocate_entry <= 1'b1;
                // 保存分配所需的索引和标签
                for (j = 0; j < TAGE_TABLES; j = j + 1) begin
                    allocate_tage_idx[j] = tage_index_op[j];
                    allocate_tage_tag[j] = tage_tag_op[j];
                end
            end else begin
                allocate_entry <= 1'b0;
            end
            
            global_history <= update_global_history;
        end
    end
end

// ==================== 独立的老化操作块 ====================
always @(posedge clk) begin
    if (reset) begin
        // 已在主 reset 中初始化
    end else if (aging_enable && !operate_enable) begin
        // 仅在非更新周期执行老化，避免冲突
        if (aging_phase == 0) begin
            // 重置所有 TAGE 表的 useful MSB
            for (j = 0; j < TAGE_TABLES; j = j + 1) begin
                for (i = 0; i < PHT_DEPTH; i = i + 1) begin
                    tage_table[j][i].useful = {1'b0, tage_table[j][i].useful[0]};
                end
            end
        end else begin
            // 重置所有 TAGE 表的 useful LSB
            for (j = 0; j < TAGE_TABLES; j = j + 1) begin
                for (i = 0; i < PHT_DEPTH; i = i + 1) begin
                    tage_table[j][i].useful = {tage_table[j][i].useful[1], 1'b0};
                end
            end
        end
    end
end

// ==================== 独立的条目分配块 ====================
always @(posedge clk) begin
    if (reset) begin
        // 已在主 reset 中初始化
    end else if (allocate_entry) begin
        integer found_entry = 0;
        integer target_j = -1;
        integer start_j = update_provider + 1;
        
        // 从 provider+1 开始找（更长的历史）
        for (j = start_j; j < TAGE_TABLES && !found_entry; j = j + 1) begin
            if (!tage_table[j][allocate_tage_idx[j]].valid) begin
                target_j = j;
                found_entry = 1;
            end else if (tage_table[j][allocate_tage_idx[j]].useful == 0) begin
                target_j = j;
                found_entry = 1;
            end
        end
        
        if (found_entry) begin
            tage_table[target_j][allocate_tage_idx[target_j]].valid <= 1'b1;
            tage_table[target_j][allocate_tage_idx[target_j]].tag <= allocate_tage_tag[target_j];
            tage_table[target_j][allocate_tage_idx[target_j]].pred <= PRED_WEAK_HIGH;
            tage_table[target_j][allocate_tage_idx[target_j]].useful <= 0;
        end else begin
            // 递减所有候选表的useful
            for (j = start_j; j < TAGE_TABLES; j = j + 1) begin
                if (tage_table[j][allocate_tage_idx[j]].useful > 0) begin
                    tage_table[j][allocate_tage_idx[j]].useful = tage_table[j][allocate_tage_idx[j]].useful - 1;
                end
            end
        end
    end
end

always @(posedge clk) begin
    if (operate_enable && delete_entry && !ras_pop_return) begin
        btb_valid[operate_btb_index] <= 1'b0;
    end
end

// ==================== 输出赋值 ====================
wire [$clog2(RASNUM)-1:0] ras_read_ptr;
assign ras_read_ptr = (ras_ptr == 0) ? 0 : ras_ptr - 1'b1;

assign btb_enable = ras_match | btb_match;
assign btb_taken = ras_match | (btb_match && final_taken);
assign btb_pc = ras_match ? {ras_stack[ras_read_ptr], 2'b0} : {btb_target[fetch_btb_index], 2'b0};
assign btb_index = fetch_btb_index;

endmodule