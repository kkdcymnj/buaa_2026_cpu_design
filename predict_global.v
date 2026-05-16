`include "constant.v"

`define PC_TAG_HIGH 25
`define PC_TAG_LOW  11
`define PC_INDEX_HIGH 10
`define PC_INDEX_LOW  2

module predict_global #(
    parameter BTBNUM        = 1024,          // BTB条目数
    parameter RASNUM        = 32,           // RAS深度
    parameter GHISTORY_WIDTH = 9,           // 全局历史宽度
    parameter PHT_WIDTH     = 6            // PHT索引宽度 
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

localparam PHT_DEPTH = (1 << PHT_WIDTH) * (1 << GHISTORY_WIDTH); 

// 全局历史寄存器
reg [GHISTORY_WIDTH-1:0] global_history;
wire [GHISTORY_WIDTH-1:0] next_global_history;
wire [GHISTORY_WIDTH-1:0] update_global_history;

// 计算下一时刻的全局历史
assign next_global_history = {right_orien, global_history[GHISTORY_WIDTH-1:1]};

// 选择用于更新的历史值（使用正确的方向）
assign update_global_history = (predict_error || predict_correct || add_entry || target_error) ? 
                                next_global_history : global_history;

// PHT存储
reg [1:0] pht_entry [0:PHT_DEPTH-1];

// PHT索引计算函数
function [$clog2(PHT_DEPTH)-1:0] pht_index;
    input [PHT_WIDTH-1:0] pht_addr;
    input [GHISTORY_WIDTH-1:0] history;
    begin
        pht_index = (pht_addr << GHISTORY_WIDTH) | history;
    end
endfunction

// 计算PC哈希值
wire [PHT_WIDTH-1:0] hashed_operate_pc;
assign hashed_operate_pc = 
    operate_pc[31:26] ^ operate_pc[25:20] ^ operate_pc[19:14] ^ operate_pc[13:8] ^ operate_pc[7:2];

wire [PHT_WIDTH-1:0] pht_addr;
assign pht_addr = hashed_operate_pc ^ global_history;

// BTB存储
reg [14:0] btb_tag [0:BTBNUM-1];     // tag: PC[25:11]
reg [29:0] btb_target [0:BTBNUM-1];  // 目标地址高30位
reg [BTBNUM-1:0] btb_valid;

// BTB索引
wire [$clog2(BTBNUM)-1:0] btb_add_entry_index;
assign btb_add_entry_index = operate_pc[`PC_INDEX_HIGH : `PC_INDEX_LOW];

// RAS栈
reg [29:0] ras_stack [0:RASNUM-1];   // 返回地址(高30位)
reg [$clog2(RASNUM)-1:0] ras_ptr;    // 栈指针，指向当前可用栈顶
reg ras_empty;

// RAS操作
always @(posedge clk) begin
    if (reset) begin
        ras_ptr   <= 0;
        ras_empty <= 1'b1;
        for (integer r = 0; r < RASNUM; r = r + 1) begin
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

// Fetch阶段缓冲
reg [31:0] fetch_pc_buffer;
reg fetch_en_buffer;

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

// Fetch级BTB索引
wire [$clog2(BTBNUM)-1:0] fetch_btb_index;
assign fetch_btb_index = fetch_pc_buffer[`PC_INDEX_HIGH : `PC_INDEX_LOW];

// BTB匹配判断
wire btb_match;
assign btb_match = fetch_en_buffer && btb_valid[fetch_btb_index] && 
                   (fetch_pc_buffer[`PC_TAG_HIGH:`PC_TAG_LOW] == btb_tag[fetch_btb_index]);

// RAS匹配判断
wire ras_match;
assign ras_match = fetch_en_buffer && ras_pop_return && !ras_empty; 

// PHT和全局历史更新
integer j;
always @(posedge clk) begin
    if (reset) begin
        btb_valid <= 0;
        global_history <= 0;
        
        for (j = 0; j < PHT_DEPTH; j = j + 1) begin
            pht_entry[j] = 2'b10;  // 初始化为弱跳转
        end
    end 
    else if (operate_enable) begin
        if (!ras_pop_return) begin
            // BTB条目添加
            if (add_entry) begin
                btb_valid[btb_add_entry_index]   <= 1'b1;
                btb_tag[btb_add_entry_index]     <= operate_pc[`PC_TAG_HIGH:`PC_TAG_LOW];
                btb_target[btb_add_entry_index]  <= right_target[31:2];
                
                // 初始化PHT当前条目为弱跳转
                pht_entry[pht_index(pht_addr, global_history)] <= 2'b10;
            end
            
            // 目标错误时更新BTB
            else if (target_error) begin
                btb_target[operate_btb_index] <= right_target[31:2];
                pht_entry[pht_index(pht_addr, global_history)] <= 2'b10;
            end

            // 方向预测错误或正确时更新PHT
            else if (predict_error || predict_correct) begin
                if (right_orien) begin
                    if (pht_entry[pht_index(pht_addr, global_history)] != 2'b11) begin
                        pht_entry[pht_index(pht_addr, global_history)] <= pht_entry[pht_index(pht_addr, global_history)] + 1'b1;
                    end
                end else begin
                    if (pht_entry[pht_index(pht_addr, global_history)] != 2'b00) begin
                        pht_entry[pht_index(pht_addr, global_history)] <= pht_entry[pht_index(pht_addr, global_history)] - 1'b1;
                    end
                end
            end

            // 更新全局历史寄存器（在所有需要更新的情况下）
            if (add_entry || target_error || predict_error || predict_correct) begin
                global_history <= update_global_history;
            end
        end
    end
end

// BTB删除操作
always @(posedge clk) begin
    if (operate_enable && delete_entry && !ras_pop_return) begin
        btb_valid[operate_btb_index] <= 1'b0;
    end
end

// Fetch级PC哈希
wire [PHT_WIDTH-1:0] hashed_fetch_pc;
assign hashed_fetch_pc = 
    fetch_pc_buffer[31:26] ^ fetch_pc_buffer[25:20] ^ fetch_pc_buffer[19:14] ^ 
    fetch_pc_buffer[13:8] ^ fetch_pc_buffer[7:2];

// Fetch级PHT地址
wire [PHT_WIDTH-1:0] fetch_pht_addr;
assign fetch_pht_addr = hashed_fetch_pc ^ global_history;

// Fetch级PHT计数器读取
wire [1:0] fetch_pht_counter;
assign fetch_pht_counter = pht_entry[pht_index(fetch_pht_addr, global_history)];

// RAS安全读取指针
wire [$clog2(RASNUM)-1:0] ras_read_ptr;
assign ras_read_ptr = (ras_ptr == 0) ? 0 : ras_ptr - 1'b1;

// 输出赋值
assign btb_enable = ras_match | btb_match;
assign btb_taken  = ras_match | (btb_match && fetch_pht_counter[1]);
assign btb_pc     = ras_match ? {ras_stack[ras_read_ptr], 2'b0} : {btb_target[fetch_btb_index], 2'b0};
assign btb_index  = fetch_btb_index;

endmodule