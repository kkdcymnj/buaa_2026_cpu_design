`include "constant.v"

`define PC_TAG_HIGH 25
`define PC_TAG_LOW  11
`define PC_INDEX_HIGH 10
`define PC_INDEX_LOW  2

`define BHR_INDEX_HIGH `BHR_INDEX_LOW + $clog2(BHRNUM) - 1
`define BHR_INDEX_LOW  4

module predict_tournament #(
    parameter BTBNUM         = 1024,          // BTB条目数
    parameter RASNUM         = 32,            // RAS深度
    parameter GHISTORY_WIDTH = 9,             // 全局历史宽度
    parameter PHT_WIDTH      = 6,             // PHT索引宽度（Gshare）
    parameter BHRNUM         = 1024,          // 局部BHR条目数
    parameter LOCAL_HISTORY_WIDTH = 5,        // 局部历史宽度
    parameter LOCAL_PHT_WIDTH = 10            // 局部PHT索引宽度
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

localparam PHT_DEPTH = (1 << PHT_WIDTH) * (1 << GHISTORY_WIDTH);
localparam LOCAL_PHT_DEPTH = (1 << LOCAL_PHT_WIDTH) * (1 << LOCAL_HISTORY_WIDTH);

// ---------------------- 全局预测器 (Gshare) ----------------------
reg [GHISTORY_WIDTH-1:0] global_history;
reg [1:0] gshare_pht [0:PHT_DEPTH-1];

wire [PHT_WIDTH-1:0] hashed_pc_gshare;
assign hashed_pc_gshare = operate_pc[31:26] ^ operate_pc[25:20] ^ operate_pc[19:14] ^ operate_pc[13:8] ^ operate_pc[7:2];
wire [PHT_WIDTH-1:0] gshare_pht_addr = hashed_pc_gshare ^ global_history;

function [$clog2(PHT_DEPTH)-1:0] gshare_index;
    input [PHT_WIDTH-1:0] addr;
    input [GHISTORY_WIDTH-1:0] hist;
    begin
        gshare_index = (addr << GHISTORY_WIDTH) | hist;
    end
endfunction

// ---------------------- 局部预测器 (BHR + PHT) ----------------------
reg [LOCAL_HISTORY_WIDTH-1:0] bhr_table [0:BHRNUM-1];
reg [1:0] local_pht [0:LOCAL_PHT_DEPTH-1];

wire [$clog2(BHRNUM)-1:0] local_bhr_addr = operate_pc[`BHR_INDEX_HIGH : `BHR_INDEX_LOW];
wire [LOCAL_HISTORY_WIDTH-1:0] local_bhr_value = bhr_table[local_bhr_addr];

wire [LOCAL_PHT_WIDTH-1:0] hashed_pc_local;
assign hashed_pc_local = operate_pc[31:22] ^ operate_pc[21:12] ^ operate_pc[11:2];
wire [LOCAL_PHT_WIDTH-1:0] local_pht_addr = hashed_pc_local ^ local_bhr_value;

function [$clog2(LOCAL_PHT_DEPTH)-1:0] local_pht_index;
    input [LOCAL_PHT_WIDTH-1:0] addr;
    input [LOCAL_HISTORY_WIDTH-1:0] hist;
    begin
        local_pht_index = (addr << LOCAL_HISTORY_WIDTH) | hist;
    end
endfunction

// ---------------------- 选择器 (Chooser) ----------------------
localparam CHOOSER_DEPTH = 1 << LOCAL_PHT_DEPTH;  
reg [1:0] chooser [0:CHOOSER_DEPTH-1];
wire [LOCAL_PHT_DEPTH-1:0] chooser_idx = gshare_pht_addr ^ local_pht_addr;  

// ---------------------- BTB & RAS (与之前相同) ----------------------
reg [14:0] btb_tag [0:BTBNUM-1];
reg [29:0] btb_target [0:BTBNUM-1];
reg [BTBNUM-1:0] btb_valid;
wire [$clog2(BTBNUM)-1:0] btb_add_entry_index = operate_pc[`PC_INDEX_HIGH : `PC_INDEX_LOW];

reg [29:0] ras_stack [0:RASNUM-1];
reg [$clog2(RASNUM)-1:0] ras_ptr;
reg ras_empty;

always @(posedge clk) begin
    if (reset) begin
        ras_ptr <= 0;
        ras_empty <= 1'b1;
        for (integer r = 0; r < RASNUM; r = r + 1) ras_stack[r] = 30'b0;
    end else if (operate_enable) begin
        if (ras_push_call) begin
            ras_stack[ras_ptr] <= operate_pc[31:2] + 30'b1;
            ras_ptr <= ras_ptr + 1'b1;
            ras_empty <= 1'b0;
        end else if (ras_pop_return && !ras_empty) begin
            ras_ptr <= ras_ptr - 1'b1;
            if (ras_ptr - 1'b1 == 0) ras_empty <= 1'b1;
        end
    end
end

// Fetch 缓冲
reg [31:0] fetch_pc_buffer;
reg fetch_en_buffer;
always @(posedge clk) begin
    fetch_en_buffer <= reset ? 1'b0 : inst_fetch;
    if (inst_fetch) fetch_pc_buffer <= fetch_pc;
end

wire [$clog2(BTBNUM)-1:0] fetch_btb_index = fetch_pc_buffer[`PC_INDEX_HIGH : `PC_INDEX_LOW];
wire btb_match = fetch_en_buffer && btb_valid[fetch_btb_index] &&
                 (fetch_pc_buffer[`PC_TAG_HIGH:`PC_TAG_LOW] == btb_tag[fetch_btb_index]);
wire ras_match = fetch_en_buffer && ras_pop_return && !ras_empty;

// Fetch 级预测值
wire [PHT_WIDTH-1:0] fetch_hashed_pc = fetch_pc_buffer[31:26] ^ fetch_pc_buffer[25:20] ^ fetch_pc_buffer[19:14] ^ fetch_pc_buffer[13:8] ^ fetch_pc_buffer[7:2];
wire [GHISTORY_WIDTH-1:0] fetch_global_history = global_history;
wire [1:0] gshare_pred = gshare_pht[gshare_index(fetch_hashed_pc ^ fetch_global_history, fetch_global_history)];

wire [$clog2(BHRNUM)-1:0] fetch_bhr_addr = fetch_pc_buffer[`BHR_INDEX_HIGH : `BHR_INDEX_LOW];
wire [LOCAL_HISTORY_WIDTH-1:0] fetch_bhr_value = bhr_table[fetch_bhr_addr];
wire [LOCAL_PHT_WIDTH-1:0] fetch_hashed_local = fetch_pc_buffer[31:22] ^ fetch_pc_buffer[21:12] ^ fetch_pc_buffer[11:2];
wire [1:0] local_pred = local_pht[local_pht_index(fetch_hashed_local ^ fetch_bhr_value, fetch_bhr_value)];

wire [1:0] chooser_pred = chooser[fetch_hashed_pc];
wire use_global = (chooser_pred[1] == 1'b1);  // 2-bit: 11/10 选全局, 01/00 选局部
wire final_taken = use_global ? gshare_pred[1] : local_pred[1];

// ---------------------- 更新逻辑 ----------------------
integer i;            
wire gshare_correct;
wire local_correct;                
assign gshare_correct = (gshare_pred[1] == right_orien);
assign local_correct = (local_pred[1] == right_orien);
always @(posedge clk) begin
    if (reset) begin
        btb_valid <= 0;
        global_history <= 0;
        for (i = 0; i < PHT_DEPTH; i = i + 1) gshare_pht[i] = 2'b10;
        for (i = 0; i < LOCAL_PHT_DEPTH; i = i + 1) local_pht[i] = 2'b10;
        for (i = 0; i < BHRNUM; i = i + 1) bhr_table[i] = 0;
        for (i = 0; i < CHOOSER_DEPTH; i = i + 1) chooser[i] = 2'b10;  // 偏向全局初始
    end else if (operate_enable && !ras_pop_return) begin
        // BTB 更新
        if (add_entry) begin
            btb_valid[btb_add_entry_index] <= 1;
            btb_tag[btb_add_entry_index] <= operate_pc[`PC_TAG_HIGH:`PC_TAG_LOW];
            btb_target[btb_add_entry_index] <= right_target[31:2];
        end else if (target_error) begin
            btb_target[operate_btb_index] <= right_target[31:2];
        end

        // 更新两个预测器的PHT
        if (add_entry || target_error || predict_error || predict_correct) begin
            // Gshare PHT 更新
            if (right_orien)
                if (gshare_pht[gshare_index(gshare_pht_addr, global_history)] != 2'b11)
                    gshare_pht[gshare_index(gshare_pht_addr, global_history)] <= gshare_pht[gshare_index(gshare_pht_addr, global_history)] + 1;
            else
                if (gshare_pht[gshare_index(gshare_pht_addr, global_history)] != 2'b00)
                    gshare_pht[gshare_index(gshare_pht_addr, global_history)] <= gshare_pht[gshare_index(gshare_pht_addr, global_history)] - 1;

            // Local PHT 更新
            if (right_orien)
                if (local_pht[local_pht_index(local_pht_addr, local_bhr_value)] != 2'b11)
                    local_pht[local_pht_index(local_pht_addr, local_bhr_value)] <= local_pht[local_pht_index(local_pht_addr, local_bhr_value)] + 1;
            else
                if (local_pht[local_pht_index(local_pht_addr, local_bhr_value)] != 2'b00)
                    local_pht[local_pht_index(local_pht_addr, local_bhr_value)] <= local_pht[local_pht_index(local_pht_addr, local_bhr_value)] - 1;

            // 局部 BHR 更新
            bhr_table[local_bhr_addr] <= {right_orien, local_bhr_value[LOCAL_HISTORY_WIDTH-1:1]};

            // Chooser 更新：哪个预测正确就增加其权重
            if (predict_error || predict_correct) begin
                // 实际正确方向 right_orien

                if (gshare_correct && !local_correct) begin
                    if (chooser[chooser_idx] != 2'b11) chooser[chooser_idx] <= chooser[chooser_idx] + 1;
                end else if (!gshare_correct && local_correct) begin
                    if (chooser[chooser_idx] != 2'b00) chooser[chooser_idx] <= chooser[chooser_idx] - 1;
                end
            end

            // 更新全局历史
            global_history <= {right_orien, global_history[GHISTORY_WIDTH-1:1]};
        end
    end
end

always @(posedge clk) begin
    if (operate_enable && delete_entry && !ras_pop_return)
        btb_valid[operate_btb_index] <= 1'b0;
end

wire ras_read_ptr = (ras_ptr == 0) ? 0 : ras_ptr - 1;
assign btb_enable = ras_match | btb_match;
assign btb_taken = ras_match | (btb_match && final_taken);
assign btb_pc = ras_match ? {ras_stack[ras_read_ptr], 2'b0} : {btb_target[fetch_btb_index], 2'b0};
assign btb_index = fetch_btb_index;

endmodule