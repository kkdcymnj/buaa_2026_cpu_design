`include "constant.v"

`define PC_TAG_HIGH `PC_TAG_LOW + 14
`define PC_TAG_LOW  `PC_INDEX_LOW + $clog2(BHRNUM) - 2 
`define PC_INDEX_HIGH `PC_INDEX_LOW + $clog2(BHRNUM) - 1 
`define PC_INDEX_LOW  2
`define BHR_INDEX_HIGH `BHR_INDEX_LOW + $clog2(BHRNUM) - 1      // 10位地址需要 [13:4] (10位)
`define BHR_INDEX_LOW  4       // 从8改为4

module predict_local_tri #(
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
    output wire [31:0] pred_pc,              // 预测目标地址
    output wire        pred_taken,           // 预测是否跳转
    output wire        pred_enable,          // 预测有效
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

localparam PHT_DEPTH  = (1 << PHT_WIDTH) * (1 << HISTORY_WIDTH);  // 1024 * 32 = 32768

wire [PHT_WIDTH-1:0] hashed_operate_pc;
assign hashed_operate_pc = 
    operate_pc[31:22] ^ operate_pc[21:12] ^ operate_pc[11:2];

reg [HISTORY_WIDTH-1:0] bht_entry [0:BHRNUM-1];
wire [$clog2(BHRNUM)-1:0] bht_addr;
wire [HISTORY_WIDTH-1:0] bht_value;

assign bht_addr = operate_pc[`BHR_INDEX_HIGH : `BHR_INDEX_LOW];
assign bht_value = bht_entry[bht_addr];

// PHT升级为3位饱和计数器 (0-7)
// 预测方向: 值 >= 4 时预测跳转 (强跳转/弱跳转分界线)
reg [2:0] pht_entry [0:PHT_DEPTH-1];  // 从1:0改为2:0

// PHT索引计算函数
function [$clog2(PHT_DEPTH)-1:0] pht_index;
    input [PHT_WIDTH-1:0] pht_addr;
    input [HISTORY_WIDTH-1:0] history;
    begin
        pht_index = (pht_addr << HISTORY_WIDTH) | history;
    end
endfunction

wire [PHT_WIDTH-1:0] pht_addr;
assign pht_addr = hashed_operate_pc ^ {bht_value, {PHT_WIDTH-HISTORY_WIDTH{1'b0}}};

reg [14:0] btb_tag [0:BTBNUM-1];     // tag: PC[25:11]
reg [29:0] btb_target [0:BTBNUM-1];  // 目标地址高30位
reg [BTBNUM-1:0] btb_valid;

// BTB索引
wire [$clog2(BTBNUM)-1:0] btb_add_entry_index;
assign btb_add_entry_index = operate_pc[`PC_INDEX_HIGH : `PC_INDEX_LOW];

reg [29:0] ras_stack [0:RASNUM-1];   // 返回地址(高30位)
reg [$clog2(RASNUM)-1:0] ras_ptr;    // 栈指针，指向当前可用栈顶
reg ras_empty;

always @(posedge clk) begin
    if (reset) begin
        ras_ptr   <= 0;
        ras_empty <= 1'b1;
        for (integer r = 0; r < RASNUM; r = r + 1) begin
            ras_stack[r] = 30'b0;
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

wire [$clog2(BTBNUM)-1:0] fetch_btb_index;
assign fetch_btb_index = fetch_pc_buffer[`PC_INDEX_HIGH : `PC_INDEX_LOW];

wire btb_match;
assign btb_match = fetch_en_buffer && btb_valid[fetch_btb_index] && 
                   (fetch_pc_buffer[`PC_TAG_HIGH:`PC_TAG_LOW] == btb_tag[fetch_btb_index]);

wire ras_match;
assign ras_match = fetch_en_buffer && ras_pop_return && !ras_empty; 

integer j;
always @(posedge clk) begin
    if (reset) begin
        btb_valid <= 0;
    
        // 初始化3位PHT为中间值4 (弱跳转)
        for (j = 0; j < PHT_DEPTH; j = j + 1) begin
            pht_entry[j] = 3'b100;  // 初始化为4，表示弱跳转
        end
        
        // BHT复位初始化
        for (j = 0; j < BHRNUM; j = j + 1) begin
            bht_entry[j] = 0;
        end
    end 
    else if (operate_enable) begin
        if (!ras_pop_return) begin
            if (add_entry) begin
                btb_valid[btb_add_entry_index]   <= 1'b1;
                btb_tag[btb_add_entry_index]     <= operate_pc[`PC_TAG_HIGH:`PC_TAG_LOW];
                btb_target[btb_add_entry_index]  <= right_target[31:2];
                
                // 初始化PHT当前条目为弱跳转 (4)
                pht_entry[pht_index(pht_addr, bht_value)] <= 3'b100;
            end
            
            else if (target_error) begin
                btb_target[operate_btb_index] <= right_target[31:2];
                // 目标错误时重置为弱跳转
                pht_entry[pht_index(pht_addr, bht_value)] <= 3'b100;
            end

            else if (predict_error || predict_correct) begin
                // 3位饱和计数器更新逻辑 (0-7范围)
                if (right_orien) begin
                    // 分支实际发生：计数器+1，上限为7
                    if (pht_entry[pht_index(pht_addr, bht_value)] != 3'b111) begin
                        pht_entry[pht_index(pht_addr, bht_value)] <= pht_entry[pht_index(pht_addr, bht_value)] + 1'b1;
                    end
                end else begin
                    // 分支实际未发生：计数器-1，下限为0
                    if (pht_entry[pht_index(pht_addr, bht_value)] != 3'b000) begin
                        pht_entry[pht_index(pht_addr, bht_value)] <= pht_entry[pht_index(pht_addr, bht_value)] - 1'b1;
                    end
                end
            end

            if (add_entry || target_error || predict_error || predict_correct) begin
                bht_entry[bht_addr] <= {right_orien, bht_entry[bht_addr][HISTORY_WIDTH-1:1]};
            end
        end
    end
end

always @(posedge clk) begin
    if (operate_enable && delete_entry && !ras_pop_return) begin
        btb_valid[operate_btb_index] <= 1'b0;
    end
end

// Fetch级PC哈希
wire [PHT_WIDTH-1:0] hashed_fetch_pc;
assign hashed_fetch_pc = 
    fetch_pc_buffer[31:22] ^ fetch_pc_buffer[21:12] ^ fetch_pc_buffer[11:2];

// Fetch级BHT读取
wire [HISTORY_WIDTH-1:0] fetch_bht_value;
wire [$clog2(BHRNUM)-1:0] fetch_bht_addr;
assign fetch_bht_addr = fetch_pc_buffer[`BHR_INDEX_HIGH : `BHR_INDEX_LOW];
assign fetch_bht_value = bht_entry[fetch_bht_addr];

// Fetch级PHT地址
wire [PHT_WIDTH-1:0] fetch_pht_addr;
assign fetch_pht_addr = hashed_fetch_pc ^ {fetch_bht_value, {PHT_WIDTH-HISTORY_WIDTH{1'b0}}};

// Fetch级PHT计数器读取 (3位)
wire [2:0] fetch_pht_counter;
assign fetch_pht_counter = pht_entry[pht_index(fetch_pht_addr, fetch_bht_value)];

// RAS安全读取指针
wire [$clog2(RASNUM)-1:0] ras_read_ptr;
assign ras_read_ptr = (ras_ptr == 0) ? 0 : ras_ptr - 1'b1;

// 输出赋值 - 注意：3位计数器取最高位(bit2)判断强跳转/弱跳转
// 也可以使用 >=4 的判断方式
assign pred_enable = ras_match | btb_match;
// 预测跳转条件：计数器值 >= 4 (3'b100)
assign pred_taken  = ras_match | (btb_match && (fetch_pht_counter >= 3'b100));
assign pred_pc     = ras_match ? {ras_stack[ras_read_ptr], 2'b0} : {btb_target[fetch_btb_index], 2'b0};
assign btb_index   = fetch_btb_index;

endmodule