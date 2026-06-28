`include "constant.v"

`define PC_TAG_HIGH `PC_TAG_LOW + 14
`define PC_TAG_LOW  `PC_INDEX_LOW + $clog2(BHRNUM) - 2 
`define PC_INDEX_HIGH `PC_INDEX_LOW + $clog2(BHRNUM) - 1 
`define PC_INDEX_LOW  2
`define BHR_INDEX_HIGH `BHR_INDEX_LOW + $clog2(BHRNUM) - 1      // 10位地址需要 [13:4] (10位)
`define BHR_INDEX_LOW  4       // 从8改为4

module predict_local #(
    parameter BTBNUM        = 1024,          // BTB条目数
    parameter RASNUM        = 32,           // RAS深度
    parameter BHRNUM        = 1024,         // BHR条目数 (2^10)
    parameter HISTORY_WIDTH = 5,            // 全局/局部历史宽度
    parameter PHT_WIDTH     = 10            // PHT索引宽度 (2^10=1024组)
) (
    input  wire clk,
    input  wire reset,

    input  wire        inst_fetch,
    input  wire [31:0] fetch_pc,
    output wire [31:0] btb_pc,              // 预测目标地址
    output wire        btb_taken,           // 预测是否跳转
    output wire        btb_enable,          // 预测有效
    output wire [$clog2(BTBNUM)-1:0] btb_index,  // 命中索引(调试用)

    input  wire        operate_enable,
    input  wire        ras_push_call,
    input  wire        ras_pop_return,
    input  wire [31:0] operate_pc,
    input  wire [$clog2(BTBNUM)-1:0] operate_btb_index,
    input  wire        add_entry,          // 添加BTB条目
    input  wire        delete_entry,       // 删除BTB条目
    input  wire [31:0] right_target,       // 正确目标地址
    input  wire        target_error,       // 目标预测错误
    input  wire        predict_error,      // 方向预测错误
    input  wire        predict_correct,    // 方向预测正确
    input  wire        right_orien         // 实际分支方向
);

localparam PHT_DEPTH  = (1 << PHT_WIDTH) * (1 << HISTORY_WIDTH);  // 1024 * 16 = 16384

(* ram_style = "block" *) reg [HISTORY_WIDTH-1:0] bht_entry [0:BHRNUM-1];  // BRAM 默认初始值全 0

// BHT operate 路径：同步读（地址寄存 → BRAM 数据下一拍有效）
reg [$clog2(BHRNUM)-1:0] bht_addr_r;
reg [HISTORY_WIDTH-1:0] bht_value_r;

always @(posedge clk) begin
    bht_addr_r  <= operate_pc[`BHR_INDEX_HIGH : `BHR_INDEX_LOW];
    bht_value_r <= bht_entry[operate_pc[`BHR_INDEX_HIGH : `BHR_INDEX_LOW]];
end

// operate 路径 1 级流水寄存器（与 bht_value_r 对齐）
reg                 operate_enable_d1;
reg                 ras_push_call_d1;
reg                 ras_pop_return_d1;
reg [31:0]          operate_pc_d1;
reg                 add_entry_d1;
reg                 delete_entry_d1;
reg                 target_error_d1;
reg                 predict_error_d1;
reg                 predict_correct_d1;
reg                 right_orien_d1;
reg [31:0]          right_target_d1;
reg [$clog2(BTBNUM)-1:0] operate_btb_index_d1;
reg [$clog2(BTBNUM)-1:0] btb_add_entry_index_d1;
reg [PHT_WIDTH-1:0] hashed_operate_pc_d1;

always @(posedge clk) begin
    // 锁存一级流水
    operate_enable_d1      <= operate_enable;
    ras_push_call_d1       <= ras_push_call;
    ras_pop_return_d1      <= ras_pop_return;
    operate_pc_d1          <= operate_pc;
    add_entry_d1           <= add_entry;
    delete_entry_d1        <= delete_entry;
    target_error_d1        <= target_error;
    predict_error_d1       <= predict_error;
    predict_correct_d1     <= predict_correct;
    right_orien_d1         <= right_orien;
    right_target_d1        <= right_target;
    operate_btb_index_d1   <= operate_btb_index;
    btb_add_entry_index_d1 <= operate_pc[`PC_INDEX_HIGH : `PC_INDEX_LOW];
    hashed_operate_pc_d1   <= operate_pc[31:22] ^ operate_pc[21:12] ^ operate_pc[11:2];
end

(* ram_style = "block" *) reg [1:0] pht_entry [0:PHT_DEPTH-1];

// PHT BRAM 配置时初始化为弱跳转 (BRAM 支持 initial 块)
integer init_pht;
initial begin
    for (init_pht = 0; init_pht < PHT_DEPTH; init_pht = init_pht + 1) begin
        pht_entry[init_pht] = 2'b10;
    end
end

// PHT索引计算函数 - 完整保留
function [$clog2(PHT_DEPTH)-1:0] pht_index;
    input [PHT_WIDTH-1:0] pht_addr;
    input [HISTORY_WIDTH-1:0] history;
    begin
        pht_index = (pht_addr << HISTORY_WIDTH) | history;
    end
endfunction

wire [PHT_WIDTH-1:0] pht_addr;
assign pht_addr = hashed_operate_pc_d1 ^ {bht_value_r, {PHT_WIDTH-HISTORY_WIDTH{1'b0}}};

(* ram_style = "block" *) reg [14:0] btb_tag [0:BTBNUM-1];     // tag: PC[25:11]
(* ram_style = "block" *) reg [29:0] btb_target [0:BTBNUM-1];  // 目标地址高30位
reg [BTBNUM-1:0] btb_valid;

// BTB索引（已在流水寄存器 btb_add_entry_index_d1 中计算）

reg [29:0] ras_stack [0:RASNUM-1];   // 返回地址(高30位)
reg [$clog2(RASNUM)-1:0] ras_ptr;    // 栈指针，指向当前可用栈顶
reg ras_empty;

integer r;
always @(posedge clk) begin
    if (reset) begin
        ras_ptr   <= 0;
        ras_empty <= 1'b1;
        for (r = 0; r < RASNUM; r = r + 1) begin
            ras_stack[r] <= 30'b0;
        end
    end else if (operate_enable) begin
        if (ras_push_call) begin
            ras_stack[ras_ptr] <= operate_pc[31:2] + 30'b1; // 压入当前 PC+4
            ras_ptr            <= ras_ptr + 1'b1;
            ras_empty          <= 1'b0;
        end 
        else if (ras_pop_return && !ras_empty) begin
            ras_ptr            <= ras_ptr - 1'b1;
            if (ras_ptr - 1'b1 == 0) begin
                ras_empty      <= 1'b1;
            end
        end
    end
end

// Fetch 级连续 BRAM 预读（每周期读取，保证数据始终比 inst_fetch 提前 1 拍就绪）
// 原理：Pre_PC 在两次 fetch 之间保持稳定，利用 BRAM 1 拍延迟做超前查找
reg [31:0] fetch_pc_buffer;
reg                 fetch_output_valid;
reg [14:0]          fetch_btb_tag_r;
reg [29:0]          fetch_btb_target_r;
reg                 fetch_btb_valid_r;
reg [HISTORY_WIDTH-1:0] fetch_bht_value_r;
reg [1:0]           fetch_pht_counter_r;

always @(posedge clk) begin
    if (reset) begin
        fetch_pc_buffer     <= 32'b0;
        fetch_output_valid  <= 1'b0;
        fetch_btb_tag_r     <= 0;
        fetch_btb_target_r  <= 0;
        fetch_btb_valid_r   <= 1'b0;
        fetch_bht_value_r   <= 0;
        fetch_pht_counter_r <= 0;
    end else begin
        // 每周期捕获 fetch_pc（Pre_PC 在 fetch 间隙稳定不变）
        fetch_pc_buffer <= fetch_pc;
        // 每周期对 fetch_pc_buffer 发起 BRAM 同步读，下一拍数据有效
        fetch_btb_tag_r    <= btb_tag[fetch_pc_buffer[`PC_INDEX_HIGH:`PC_INDEX_LOW]];
        fetch_btb_target_r <= btb_target[fetch_pc_buffer[`PC_INDEX_HIGH:`PC_INDEX_LOW]];
        fetch_btb_valid_r  <= btb_valid[fetch_pc_buffer[`PC_INDEX_HIGH:`PC_INDEX_LOW]];
        fetch_bht_value_r  <= bht_entry[fetch_pc_buffer[`BHR_INDEX_HIGH:`BHR_INDEX_LOW]];
        fetch_pht_counter_r <= pht_entry[pht_index(
            (fetch_pc_buffer[31:22] ^ fetch_pc_buffer[21:12] ^ fetch_pc_buffer[11:2])
            ^ {bht_entry[fetch_pc_buffer[`BHR_INDEX_HIGH:`BHR_INDEX_LOW]], {PHT_WIDTH-HISTORY_WIDTH{1'b0}}},
            bht_entry[fetch_pc_buffer[`BHR_INDEX_HIGH:`BHR_INDEX_LOW]]
        )];
        // inst_fetch 有效时标定输出有效（下一拍 Pre_to_F_valid 会为高）
        fetch_output_valid <= inst_fetch;
    end
end

wire btb_match;
assign btb_match = fetch_output_valid && fetch_btb_valid_r && 
                   (fetch_pc_buffer[`PC_TAG_HIGH:`PC_TAG_LOW] == fetch_btb_tag_r);

wire ras_match;
assign ras_match = fetch_output_valid && ras_pop_return && !ras_empty; 

always @(posedge clk) begin
    if (reset) begin
        btb_valid <= 0;
    end 
    else if (operate_enable_d1) begin
        if (!ras_pop_return_d1) begin
            if (add_entry_d1) begin
                btb_valid[btb_add_entry_index_d1]   <= 1'b1;
                btb_tag[btb_add_entry_index_d1]     <= operate_pc_d1[`PC_TAG_HIGH:`PC_TAG_LOW];
                btb_target[btb_add_entry_index_d1]  <= right_target_d1[31:2];
                
                // 初始化PHT当前条目为弱跳转
                pht_entry[pht_index(pht_addr, bht_value_r)] <= 2'b10;
            end
            
            else if (delete_entry_d1) begin
                btb_valid[operate_btb_index_d1] <= 1'b0;
            end

            else if (target_error_d1) begin
                btb_target[operate_btb_index_d1] <= right_target_d1[31:2];
                pht_entry[pht_index(pht_addr, bht_value_r)] <= 2'b10;
            end

            else if (predict_error_d1 || predict_correct_d1) begin
                if (right_orien_d1) begin
                    if (pht_entry[pht_index(pht_addr, bht_value_r)] != 2'b11) begin
                        pht_entry[pht_index(pht_addr, bht_value_r)] <= pht_entry[pht_index(pht_addr, bht_value_r)] + 1'b1;
                    end
                end else begin
                    if (pht_entry[pht_index(pht_addr, bht_value_r)] != 2'b00) begin
                        pht_entry[pht_index(pht_addr, bht_value_r)] <= pht_entry[pht_index(pht_addr, bht_value_r)] - 1'b1;
                    end
                end
            end

            if (add_entry_d1 || target_error_d1 || predict_error_d1 || predict_correct_d1) begin
                bht_entry[bht_addr_r] <= {right_orien_d1, bht_value_r[HISTORY_WIDTH-1:1]};
            end
        end
    end
end

// RAS 安全读取指针
wire [$clog2(RASNUM)-1:0] ras_read_ptr;
assign ras_read_ptr = (ras_ptr == 0) ? 0 : ras_ptr - 1'b1;

// 输出赋值（全部使用同步读取后的寄存器信号）
assign btb_enable = ras_match | btb_match;
assign btb_taken  = ras_match | (btb_match && fetch_pht_counter_r[1]);
assign btb_pc     = ras_match ? {ras_stack[ras_read_ptr], 2'b0} : {fetch_btb_target_r, 2'b0};
assign btb_index  = fetch_pc_buffer[`PC_INDEX_HIGH : `PC_INDEX_LOW];

endmodule