`include "constant.v"
`include "instr_code.v"

`define MAIN_IDLE 0
`define MAIN_LOOKUP 1
`define MAIN_MISS 2
`define MAIN_REPLACE 3
`define MAIN_REFILL 4
`define WRITE_BUFFER_IDLE 0
`define WRITE_BUFFER_WRITE 1   

module cache #(
    parameter CACHE_AW           = `CACHE_AW,
    parameter CACHE_DATA_NUM     = `CACHE_DATA_NUM,
    parameter CACHE_WAY_NUM      = `CACHE_WAY_NUM,
    parameter CACHE_LINE_BANKS   = `CACHE_LINE_BANKS,
    parameter CACHE_TAG_WIDTH    = `CACHE_TAG_WIDTH,
    parameter CACHE_INDEX_WIDTH  = `CACHE_INDEX_WIDTH,
    parameter CACHE_OFFSET_WIDTH = `CACHE_OFFSET_WIDTH,
    parameter CACHE_DATA_WIDTH   = `CACHE_DATA_WIDTH,
    parameter CACHE_STRB_WIDTH   = `CACHE_STRB_WIDTH    //storebuffer
) (
    input  wire                         clk,
    input  wire                         reset,
    // CPU interface
    input  wire                         valid,
    input  wire [`CACHE_OP_WIDTH + 1:0] op,
        // 0: read, 1: write, 
        // 2: cacop-store-tag, 3: cacop-index-op, 4: cacop-hit-op, 5:preld
    input  wire [                 31:0] vaddr,
    input  wire [                  2:0] access_size,
    input  wire [`CACHE_STRB_WIDTH-1:0] wstrb,
    input  wire [`CACHE_DATA_WIDTH-1:0] wdata,
    
    output wire                         addr_ok,
    output wire                         data_ok,
    output wire [`CACHE_DATA_WIDTH-1:0] rdata,
    // MMU interface
    output wire [                  2:0] search_op,
    input  wire [                 31:0] paddr,
    input  wire                         access_type,
    // AXI-like interface
    output wire                         rd_req, 
    output wire [                  2:0] rd_type,    
        // 读请求类型。3’b000——字节，3’b001——半字，3’b010——字，3’b100——Cache行。
    output wire [                 31:0] rd_addr,
    input  wire                         rd_rdy,
    input  wire                         ret_valid,
    input  wire [                  1:0] ret_last,
    input  wire [                 31:0] ret_data,
    output wire                         wr_req,
    output wire [                  2:0] wr_type,
    output wire [                 31:0] wr_addr,
    output wire [                  3:0] wr_wstrb,
    output wire [                127:0] wr_data,
    input  wire                         wr_rdy
);

//===============================================
// Wire declarations
//===============================================

reg  [  CACHE_DATA_WIDTH-1:0] local_rdata;

// Address decoding wires
wire [CACHE_INDEX_WIDTH-1:0] index;
wire [CACHE_OFFSET_WIDTH-1:0] offset;
wire [CACHE_TAG_WIDTH-1:0] tag;

// Control signals
wire is_cacop;
wire is_preld;
wire cacop_is_store_tag;
wire cacop_is_index_op;
wire cacop_is_hit_op;
wire cacop_need_writeback;

// Request buffer signals
wire request_buffer_enable;
wire is_cacop_1d;
wire is_preld_1d;
wire [1:0] cacop_code_1d;
wire op_1d;
wire access_type_1d;
wire [2:0] req_access_size_1d;
wire [CACHE_INDEX_WIDTH-1:0] index_1d;
wire [CACHE_TAG_WIDTH-1:0] tag_1d;
wire [CACHE_OFFSET_WIDTH-1:0] offset_1d;
wire [CACHE_STRB_WIDTH-1:0] wstrb_1d;
wire [CACHE_DATA_WIDTH-1:0] wdata_1d;

// Write buffer signals
reg [49:0] write_buffer;
wire [CACHE_DATA_WIDTH-1:0] write_buffer_data;
wire [CACHE_INDEX_WIDTH-1:0] write_buffer_index;
wire [CACHE_OFFSET_WIDTH-1:0] write_buffer_offset;
wire [CACHE_STRB_WIDTH-1:0] write_buffer_strb;
wire [CACHE_WAY_NUM-1:0] write_buffer_way;

// Hit detection signals
wire [CACHE_TAG_WIDTH-1:0] tag_sel [CACHE_WAY_NUM-1:0];
wire [CACHE_WAY_NUM-1:0] valid_sel;
wire [CACHE_WAY_NUM-1:0] tag_hit;
wire req_hit;

// Replacement signals
wire evict_line_is_dirty;
wire [CACHE_TAG_WIDTH-1:0] replace_tag;
wire replace_rd;
wire [CACHE_INDEX_WIDTH-1:0] replace_index;
reg miss_buffer_replace_way;

// Refill signals
wire refill_wr;
wire [CACHE_INDEX_WIDTH-1:0] refill_index;
wire [CACHE_TAG_WIDTH-1:0] refill_tag;
wire [1:0] refill_bank;
wire [CACHE_STRB_WIDTH-1:0] refill_wstrb;
wire [CACHE_DATA_WIDTH-1:0] refill_data;
wire [CACHE_WAY_NUM-1:0] refill_way;

// Control signals
wire read_conflict;
wire wr_op;
wire rd_op;
wire rdreq_lookup_rd;
wire lookup_rd;
wire hitwrite_wr;

// Tag SRAM signals
wire tagv_rd;
wire tagv_wr;
wire [CACHE_AW-1:0] tagv_index;
wire [CACHE_WAY_NUM-1:0] tagv_way;
wire [CACHE_TAG_WIDTH:0] tagv_d;

// Data SRAM signals
wire data_rd;
wire data_wr;
wire [CACHE_AW-1:0] data_index;
wire [CACHE_STRB_WIDTH-1:0] data_wstrb;
wire [CACHE_WAY_NUM-1:0] data_way;
wire [1:0] data_offset;
wire [CACHE_DATA_WIDTH-1:0] data_d;

// SRAM arrays for cache
wire [CACHE_TAG_WIDTH:0] sram_tagv_q [CACHE_WAY_NUM-1:0];
wire sram_tagv_rd [CACHE_WAY_NUM-1:0];
wire sram_tagv_wr [CACHE_WAY_NUM-1:0];
wire [CACHE_AW-1:0] sram_tagv_index [CACHE_WAY_NUM-1:0];
wire [CACHE_TAG_WIDTH:0] sram_tagv_d [CACHE_WAY_NUM-1:0];

wire [CACHE_DATA_WIDTH-1:0] sram_data_q [CACHE_WAY_NUM-1:0][CACHE_LINE_BANKS-1:0];
wire sram_data_rd [CACHE_WAY_NUM-1:0][CACHE_LINE_BANKS-1:0];
wire sram_data_wr [CACHE_WAY_NUM-1:0][CACHE_LINE_BANKS-1:0];
wire signal;
wire [CACHE_STRB_WIDTH-1:0] sram_data_wstrb [CACHE_WAY_NUM-1:0][CACHE_LINE_BANKS-1:0];
wire [CACHE_AW-1:0] sram_data_index [CACHE_WAY_NUM-1:0][CACHE_LINE_BANKS-1:0];
wire [CACHE_DATA_WIDTH-1:0] sram_data_d [CACHE_WAY_NUM-1:0][CACHE_LINE_BANKS-1:0];
wire sram_data_ena [CACHE_WAY_NUM-1:0][CACHE_LINE_BANKS-1:0];
wire [CACHE_STRB_WIDTH-1:0] sram_data_wea [CACHE_WAY_NUM-1:0][CACHE_LINE_BANKS-1:0];

// Write request signals
wire last_wr_req_flag;

// Dirty bit table
reg [CACHE_DATA_NUM-1:0] dirty_bit_table [CACHE_WAY_NUM-1:0];

//===============================================
// registers
//===============================================

// TODO: 修改wr_addr和wr_data生成逻辑为组合逻辑

reg [2:0] main_state;
reg [2:0] main_next_state;
reg write_buffer_state;
reg write_buffer_next_state;
reg write_buffer_valid;
reg [1:0] return_cnt_from_axi;
reg replace_way;
wire [1:0] rand_data;
reg wr_req_reg;
reg [31:0] wr_addr_reg;
reg [3:0] wr_wstrb_reg;
reg [2:0] wr_type_reg;
reg [127:0] wr_data_reg;
reg [76:0] request_buffer_reg;

//===============================================
// lru替换算法
//===============================================

reg [CACHE_DATA_NUM-1:0] lru_state;  // 2-way LRU: 0=Way0 newer, 1=Way1 newer

//===============================================
// Address decoding
//===============================================

assign index = vaddr[`CACHE_INDEX_WIDTH+`CACHE_OFFSET_WIDTH-1 : `CACHE_OFFSET_WIDTH];
assign offset = vaddr[`CACHE_OFFSET_WIDTH-1 : 0];
assign tag = paddr[31 : `CACHE_INDEX_WIDTH+`CACHE_OFFSET_WIDTH];
assign is_cacop = |op[4:2];
assign is_preld = op[5];
assign search_op = {op[1], op[0] | (|op[5:4]), |op[3:2]};
                    //write, 查询索引， 直接索引

// CACOP type detection
assign cacop_is_store_tag = is_cacop_1d && (cacop_code_1d == `CACOP_TYPE_STORE_TAG);
assign cacop_is_index_op = is_cacop_1d && (cacop_code_1d == `CACOP_TYPE_INDEX_OP);
assign cacop_is_hit_op = is_cacop_1d && (cacop_code_1d == `CACOP_TYPE_HIT_OP);
assign cacop_need_writeback = is_cacop_1d & valid_sel[replace_way] &
                              evict_line_is_dirty & 
                              (cacop_is_index_op | (cacop_is_hit_op & |tag_hit));

//===============================================
// Request buffer
//===============================================

assign request_buffer_enable = 
    main_next_state == `MAIN_LOOKUP;

assign is_preld_1d = request_buffer_reg[76];
assign is_cacop_1d = request_buffer_reg[75];
assign cacop_code_1d = request_buffer_reg[74:73];
assign op_1d = request_buffer_reg[72];      // 代表是否要写
assign access_type_1d = request_buffer_reg[71];
assign req_access_size_1d = request_buffer_reg[70:68];
assign index_1d = request_buffer_reg[67:60];
assign tag_1d = request_buffer_reg[59:40];
assign offset_1d = request_buffer_reg[39:36];
assign wstrb_1d = request_buffer_reg[35:32];
assign wdata_1d = request_buffer_reg[31:0];

always @(posedge clk) begin
    if (reset) begin
        request_buffer_reg <= 0;
    end
    else if (request_buffer_enable) begin
        request_buffer_reg <= {
            is_preld,
            is_cacop,
            {op[4], op[3]},
            op[1],
            access_type,
            access_size,
            index,
            tag,
            offset,
            wstrb,
            wdata
        };
    end
end

//===============================================
// Write buffer
//===============================================

assign {
    write_buffer_data,
    write_buffer_index,
    write_buffer_offset,
    write_buffer_strb,
    write_buffer_way
} = write_buffer;

always @(posedge clk) begin
    if (reset) begin
        write_buffer <= 0;
    end
    else if (write_buffer_next_state == `WRITE_BUFFER_WRITE) begin
        write_buffer <= {
            wdata_1d,
            index_1d,
            offset_1d,
            wstrb_1d,
            tag_hit     // 命中哪一路
        };
    end
end

// Write buffer state machine
always @(posedge clk) begin
    if (reset) begin
        write_buffer_state <= `MAIN_IDLE;
    end
    else begin
        write_buffer_state <= write_buffer_next_state;
    end
end

// 写cache块：当前Lookup+命中+write操作+非cacop
always @(*) begin
    case (write_buffer_state)
        `WRITE_BUFFER_IDLE:
            write_buffer_next_state = 
                (main_state == `MAIN_LOOKUP && req_hit && op_1d && !is_cacop_1d) ?
                    `WRITE_BUFFER_WRITE :
                    `WRITE_BUFFER_IDLE;
        `WRITE_BUFFER_WRITE:
            write_buffer_next_state = 
                (main_state == `MAIN_LOOKUP && req_hit && op_1d && !is_cacop_1d) ?
                    `WRITE_BUFFER_WRITE :
                    `WRITE_BUFFER_IDLE;
        default:
            write_buffer_next_state = `WRITE_BUFFER_IDLE;
    endcase
end

always @(posedge clk) begin
    if (reset) begin
        write_buffer_valid <= 0;
    end
    else if (write_buffer_next_state == `WRITE_BUFFER_WRITE) begin
        write_buffer_valid <= 1;
    end
    else if (write_buffer_next_state == `WRITE_BUFFER_IDLE) begin
        write_buffer_valid <= 0;
    end
end

//===============================================
// Miss buffer and replacement
//===============================================

always @(posedge clk) begin
    if (reset) begin
        return_cnt_from_axi <= 0;
    end
    else if ((main_state == `MAIN_MISS && main_next_state == `MAIN_REFILL) ||
             (main_state == `MAIN_REPLACE && main_next_state == `MAIN_REFILL)) begin
        return_cnt_from_axi <= 0;
    end
    else if (main_state == `MAIN_REFILL && ret_valid) begin
        if (ret_last[0]) begin
            return_cnt_from_axi <= 0;
        end
        else begin
            return_cnt_from_axi <= return_cnt_from_axi + 1;
        end
    end
end

always @(*) begin
    if (reset) begin
        replace_way = 0;
    end
    else if (main_state == `MAIN_LOOKUP && 
             (main_next_state == `MAIN_MISS ||
              is_cacop_1d && main_next_state != `MAIN_IDLE)) begin
        if (cacop_is_hit_op) begin
            replace_way = |(tag_hit & 2'b10);
        end
        else if(cacop_is_store_tag || cacop_is_index_op) begin
            replace_way = offset_1d[0];
        end
        else if (~access_type_1d && |tag_hit) begin
            replace_way = |(tag_hit & 2'b10);
        end
        else begin
            // replace_way = |(rand_data & 2'b10);
            replace_way = lru_state[index_1d] ? 1'b0 : 1'b1;
        end
    end
end

reg [7:0] r_lfsr;

always @(posedge clk) begin
    if (reset) begin
        r_lfsr <= 8'b1;
    end
    else begin
        r_lfsr[0] <= r_lfsr[7];
        r_lfsr[1] <= r_lfsr[0];
        r_lfsr[2] <= r_lfsr[1];
        r_lfsr[3] <= r_lfsr[2];
        r_lfsr[4] <= r_lfsr[3] ^ r_lfsr[7];
        r_lfsr[5] <= r_lfsr[4] ^ r_lfsr[7];
        r_lfsr[6] <= r_lfsr[5] ^ r_lfsr[7];
        r_lfsr[7] <= r_lfsr[6];
    end
end

assign rand_data = r_lfsr[7:6];

assign evict_line_is_dirty = dirty_bit_table[replace_way][index_1d];
assign replace_tag = sram_tagv_q[miss_buffer_replace_way][CACHE_TAG_WIDTH:1];
//cache块替换时要读出cache内容
assign replace_rd = main_state == `MAIN_MISS && main_next_state == `MAIN_REPLACE;
assign replace_index = index_1d;

//===============================================
// Hit detection
//===============================================

generate
    genvar i;
    for (i = 0; i < CACHE_WAY_NUM; i = i + 1) begin : gen_HIT_TAG
        assign tag_sel[i]   = sram_tagv_q[i][CACHE_TAG_WIDTH:1];
        assign valid_sel[i] = sram_tagv_q[i][0];
        assign tag_hit[i]   = (tag_1d == tag_sel[i]) && valid_sel[i];
    end
endgenerate

assign req_hit = |tag_hit & (access_type_1d | is_cacop_1d);

//===============================================
// Dirty bit table
//===============================================

generate
    for (i = 0; i < CACHE_WAY_NUM; i = i + 1) begin : gen_DIRTY
        always @(posedge clk) begin
            if (reset) begin
                dirty_bit_table[i] <= 0;
            end
            else if (write_buffer_valid && write_buffer_way == (1 << i)) begin
                dirty_bit_table[i][write_buffer_index] <= 1;
            end
            else if (main_state == `MAIN_REFILL && data_way[i] && op_1d && 
                     access_type_1d && !is_cacop_1d) begin
                dirty_bit_table[i][refill_index] <= 1;
            end
            else if (main_state == `MAIN_REFILL && data_way[i] && 
                     access_type_1d && (!op_1d || is_cacop_1d)) begin
                dirty_bit_table[i][refill_index] <= 0;
            end
        end
    end
endgenerate

//===============================================
// Refill signals
//===============================================
wire [31:0] write_in;
assign write_in = {(wstrb_1d[3] ? wdata_1d[31:24] : ret_data[31:24]), 
                   (wstrb_1d[2] ? wdata_1d[23:16] : ret_data[23:16]),
                   (wstrb_1d[1] ? wdata_1d[15: 8] : ret_data[15: 8]),
                   (wstrb_1d[0] ? wdata_1d[ 7: 0] : ret_data[ 7: 0])};

assign refill_wr = (main_state == `MAIN_REFILL & is_cacop_1d) | ret_valid;
assign refill_index = index_1d;
assign refill_tag = tag_1d;
assign refill_bank = return_cnt_from_axi;
assign refill_wstrb = wstrb_1d;
assign refill_data = (op_1d && (refill_bank == offset_1d[3:2])) ? write_in : ret_data;
assign refill_way = (1<<replace_way);

//===============================================
// Conflict detection
//===============================================

assign read_conflict = 
    write_buffer_state == `WRITE_BUFFER_WRITE && (rd_op | is_cacop) /*&& offset[3:2] == write_buffer_offset[3:2]*/ ||
    main_state == `MAIN_LOOKUP && (rd_op | is_cacop) && op_1d /*&& offset[3:2] == offset_1d[3:2]*/;

//===============================================
// Main state machine
//===============================================

assign wr_op = valid & op[1];
assign rd_op = valid & op[0];
assign rdreq_lookup_rd = (main_next_state == `MAIN_LOOKUP);
assign lookup_rd = (main_next_state == `MAIN_LOOKUP) || 
                   (main_state == `MAIN_IDLE && valid && is_cacop);
assign hitwrite_wr = write_buffer_valid;

always @(posedge clk) begin
    if (reset) begin
        main_state <= `MAIN_IDLE;
        miss_buffer_replace_way <= 0;
    end
    else begin
        main_state <= main_next_state;
        if (main_state == `MAIN_LOOKUP && 
            (main_next_state == `MAIN_MISS || main_next_state == `MAIN_REPLACE)) begin
            miss_buffer_replace_way <= replace_way;
        end
    end
end

always @(*) begin
    case (main_state)
        `MAIN_IDLE:
            main_next_state = 
                (wr_op || (rd_op && !read_conflict) || is_cacop || is_preld) ? `MAIN_LOOKUP :
                `MAIN_IDLE;
        `MAIN_LOOKUP:
            if (is_cacop_1d) begin
                if (cacop_is_hit_op && !req_hit) begin
                    main_next_state = `MAIN_IDLE;
                end
                else if (cacop_need_writeback) begin
                    main_next_state = wr_rdy ? `MAIN_REPLACE : `MAIN_MISS;
                end
                else begin
                    main_next_state = `MAIN_REFILL;
                end
            end
            else if (!req_hit || !access_type_1d) begin
                main_next_state = `MAIN_MISS;
            end
            else begin
                main_next_state = 
                    (!valid || (rd_op && read_conflict)) ? `MAIN_IDLE :
                    `MAIN_LOOKUP;
            end
        `MAIN_MISS:
            main_next_state = 
                (evict_line_is_dirty || (is_cacop_1d && cacop_need_writeback)) ?
                    (last_wr_req_flag ? `MAIN_REPLACE : `MAIN_MISS) :
                `MAIN_REPLACE;
        `MAIN_REPLACE:
            main_next_state = 
                rd_rdy ? `MAIN_REFILL : `MAIN_REPLACE;
        `MAIN_REFILL:
            main_next_state = 
                ((ret_valid && ret_last[0]) || is_cacop_1d) ? `MAIN_IDLE : 
                `MAIN_REFILL;
        default:
            main_next_state = `MAIN_IDLE;
    endcase
end

//===============================================
// Write request generation
//===============================================

reg delay_valid;

always @(posedge clk) begin
    if (reset) begin
        wr_req_reg <= 0;
        wr_addr_reg <= 0;
        wr_wstrb_reg <= 0;
        wr_type_reg <= 0;
        wr_data_reg <= 0;
        delay_valid <= 0;
    end
    else begin
        if (delay_valid) begin
            wr_data_reg <= {
                sram_data_q[miss_buffer_replace_way][3],
                sram_data_q[miss_buffer_replace_way][2],
                sram_data_q[miss_buffer_replace_way][1],
                sram_data_q[miss_buffer_replace_way][0]
            };
            wr_addr_reg <= {replace_tag, index_1d, 4'b0};
            wr_type_reg <= 3'b100;
            wr_wstrb_reg <= 4'b1111;
            wr_req_reg <= 1'b1;
            delay_valid <= 0;
        end
        else if (!wr_req_reg &&
            (main_state == `MAIN_MISS || 
                (main_state == `MAIN_LOOKUP && is_cacop_1d)) &&
            (evict_line_is_dirty || cacop_need_writeback)) begin
            delay_valid <= 1;
            /*wr_data_reg <= {
                sram_data_q[miss_buffer_replace_way][3],
                sram_data_q[miss_buffer_replace_way][2],
                sram_data_q[miss_buffer_replace_way][1],
                sram_data_q[miss_buffer_replace_way][0]
            };
            wr_addr_reg <= {replace_tag, index_1d, 4'b0};
            wr_type_reg <= 3'b100;
            wr_wstrb_reg <= 4'b1111;
            wr_req_reg <= 1'b1;*/
        end
        else if (!wr_req_reg && main_state == `MAIN_MISS &&
                  !access_type_1d && op_1d) begin
            wr_addr_reg <= {tag_1d, index_1d, offset_1d[3:0]};
            wr_type_reg <= req_access_size_1d;
            wr_wstrb_reg <= wstrb_1d;
            wr_data_reg <= offset_1d[3:2] == 2'b00 ? {96'b0, wdata_1d} :
                           offset_1d[3:2] == 2'b01 ? {64'b0, wdata_1d, 32'b0} :
                           offset_1d[3:2] == 2'b10 ? {32'b0, wdata_1d, 64'b0} :
                           {wdata_1d, 96'b0};
            wr_req_reg <= 1'b1;
        end
        else if (wr_req_reg && wr_rdy && wr_type_reg == 3'b100) begin
            if (main_state == `MAIN_MISS && !access_type_1d && op_1d) begin
                wr_addr_reg <= {tag_1d, index_1d, offset_1d[3:0]};
                wr_type_reg <= req_access_size_1d;
                wr_wstrb_reg <= wstrb_1d;
                wr_data_reg <= offset_1d[3:2] == 2'b00 ? {96'b0, wdata_1d} :
                               offset_1d[3:2] == 2'b01 ? {64'b0, wdata_1d, 32'b0} :
                               offset_1d[3:2] == 2'b10 ? {32'b0, wdata_1d, 64'b0} :
                               {wdata_1d, 96'b0};
            end
            else begin
                wr_req_reg <= 1'b0;
            end
        end
        else if (wr_req_reg && wr_rdy && wr_type_reg != 3'b100) begin
            wr_req_reg <= 1'b0;
        end
    end
end

/*always @(*) begin
    if (!wr_req_reg &&
            (main_state == `MAIN_MISS || 
                (main_state == `MAIN_LOOKUP && is_cacop_1d)) &&
            (evict_line_is_dirty || cacop_need_writeback)) begin
        wr_data_reg = {
                sram_data_q[miss_buffer_replace_way][3],
                sram_data_q[miss_buffer_replace_way][2],
                sram_data_q[miss_buffer_replace_way][1],
                sram_data_q[miss_buffer_replace_way][0]
            };
        wr_addr_reg = {replace_tag, index_1d, 4'b0};
    end
    else begin
        wr_data_reg = offset_1d[3:2] == 2'b00 ? {96'b0, wdata_1d} :
                    offset_1d[3:2] == 2'b01 ? {64'b0, wdata_1d, 32'b0} :
                    offset_1d[3:2] == 2'b10 ? {32'b0, wdata_1d, 64'b0} :
                    {wdata_1d, 96'b0};
        wr_addr_reg = {tag_1d, index_1d, offset_1d[3:0]};
    end
end*/

assign wr_req = wr_req_reg;
assign wr_type = wr_type_reg;
assign wr_data = wr_data_reg;
assign wr_addr = wr_addr_reg;
assign wr_wstrb = wr_wstrb_reg;
assign last_wr_req_flag = 
    wr_req_reg && wr_rdy && 
    (!(main_state == `MAIN_MISS && !access_type_1d && op_1d) || 
     wr_type_reg != 3'b100);

assign rd_addr = 
    (access_type_1d) ? {refill_tag, refill_index, 4'b0} :
    {tag_1d, index_1d, offset_1d[3:0]};
assign rd_type = access_type_1d ? 3'b100 : req_access_size_1d;
assign rd_req = (main_state == `MAIN_REPLACE) && !wr_req && wr_rdy;

//===============================================
// Tag SRAM control
//===============================================

assign tagv_rd = lookup_rd | replace_rd;
assign tagv_wr = 
    (refill_wr && access_type_1d) || 
    (refill_wr && (cacop_is_index_op || cacop_is_store_tag || (cacop_is_hit_op & |tag_hit)));
assign tagv_index = lookup_rd ? index :
                    replace_rd ? replace_index :
                    refill_index;
assign tagv_way = lookup_rd ? {CACHE_WAY_NUM{1'b1}} :
                  replace_rd | cacop_is_hit_op ? (1 << replace_way) :
                  (cacop_is_hit_op & |tag_hit) | cacop_is_index_op ? {CACHE_WAY_NUM{1'b1}} :
                  refill_way;
assign tagv_d = cacop_is_store_tag ? {{CACHE_TAG_WIDTH{1'b0}}, 1'b0} :
                cacop_is_index_op | (cacop_is_hit_op & |tag_hit) ? 
                    {tag_sel[replace_way], 1'b0} :
                {tag_1d, 1'b1};

//===============================================
// Data SRAM control
//===============================================

wire write_buffer_signal;
assign data_rd = rdreq_lookup_rd | replace_rd;
assign data_wr = (refill_wr && access_type_1d && !is_cacop_1d) || hitwrite_wr;
assign data_index = write_buffer_valid ? write_buffer_index :
                    rdreq_lookup_rd ? index :
                    replace_index;
assign data_wstrb = write_buffer_valid ? write_buffer_strb :
                    refill_wr ? {CACHE_STRB_WIDTH{1'b1}} : 
                    0;
assign data_offset = write_buffer_valid ? write_buffer_offset[3:2] :
                     refill_bank;
assign data_d = write_buffer_valid ? write_buffer_data :
                refill_data;
assign data_way = write_buffer_valid ? write_buffer_way :
                  refill_way;

//===============================================
// SRAM instantiation
//===============================================

generate
    for (i = 0; i < CACHE_WAY_NUM; i = i + 1) begin : gen_SRAM_WAY
        // Tag SRAM signals
        assign sram_tagv_rd[i]    = tagv_rd;
        assign sram_tagv_wr[i]    = tagv_wr & tagv_way[i];
        assign sram_tagv_index[i] = tagv_index;
        assign sram_tagv_d[i]     = tagv_d;
        blk_mem_gen_tagv u_tagv_sram (
            .clka (clk),
            .ena  (
                /*access_type_1d ||
                main_state == `MAIN_IDLE || main_state == `MAIN_LOOKUP */
                sram_tagv_wr[i] | sram_tagv_rd[i]
            ),
            .wea  (sram_tagv_wr[i]),
            .addra(sram_tagv_index[i]),
            .dina (sram_tagv_d[i]),
            .douta(sram_tagv_q[i])
        );
        
        // Data SRAM signals for each bank
        genvar j;
        for (j = 0; j < CACHE_LINE_BANKS; j = j + 1) begin : gen_SRAM_BANK
            assign sram_data_rd[i][j] = rdreq_lookup_rd | replace_rd;
            assign sram_data_wr[i][j] = data_wr & (data_way[i]) & (data_offset == j);
            assign sram_data_wstrb[i][j] = data_wstrb;
            assign sram_data_index[i][j] = data_index;
            assign sram_data_d[i][j] = data_d;
            assign sram_data_ena[i][j] = /*sram_data_rd[i][j] | sram_data_wr[i][j]*/
                ~(~access_type_1d || cacop_is_store_tag) ||
                main_state == `MAIN_IDLE || main_state == `MAIN_LOOKUP ;
            assign sram_data_wea[i][j] = sram_data_wr[i][j] ? sram_data_wstrb[i][j] :
                                                                 {CACHE_STRB_WIDTH{1'b0}};
            blk_mem_gen_data u_data_sram (
                .clka (clk),
                .ena  (sram_data_ena[i][j]),
                .wea  (sram_data_wea[i][j]),
                .addra(sram_data_index[i][j]),
                .dina (sram_data_d[i][j]),
                .douta(sram_data_q[i][j])
            );
        end
    end
endgenerate

//===============================================
// Output assignments
//===============================================

assign addr_ok = 
    (main_state == `MAIN_IDLE && !write_buffer_valid && !read_conflict) ||
    (main_state == `MAIN_LOOKUP && main_next_state == `MAIN_LOOKUP && !is_cacop_1d);

assign data_ok = 
    (main_state == `MAIN_LOOKUP && req_hit && !is_cacop_1d) ||
    (main_state == `MAIN_LOOKUP && op_1d && !is_cacop_1d) ||
    (main_state == `MAIN_REFILL && !op_1d && ret_valid && !is_cacop_1d &&
        (access_type_1d ? (return_cnt_from_axi == offset_1d[3:2]) : 1)) ||
    (main_state == `MAIN_LOOKUP && cacop_is_hit_op && !req_hit) ||
    (main_state == `MAIN_REFILL && is_cacop_1d) ||
    (main_state == `MAIN_REFILL && is_preld_1d);

integer m;
always @(*) begin
    local_rdata = {CACHE_DATA_WIDTH{1'b0}};
    for (m = 0; m < CACHE_WAY_NUM; m = m + 1) begin
        if (tag_hit[m]) begin
            local_rdata = sram_data_q[m][offset_1d[3:2]];
        end   
    end
end

assign rdata = 
    (main_state == `MAIN_LOOKUP && req_hit) ?  local_rdata : ret_data;

//===============================================
// lru algorithm
//===============================================

// LRU update on hit
always @(posedge clk) begin
    if (reset) begin
        // already initialized
        lru_state <= 0;
    end
    else if (main_state == `MAIN_LOOKUP && req_hit && !is_cacop_1d) begin
        // 命中时，标记该 way 为最近使用
        if (tag_hit[0]) begin
            lru_state[index_1d] <= 1'b0;  // Way0 最近使用
        end
        else if (tag_hit[1]) begin
            lru_state[index_1d] <= 1'b1;  // Way1 最近使用
        end
    end
    // 写缓冲写入时也要更新 LRU
    else if (write_buffer_valid) begin
        if (write_buffer_way[0]) begin
            lru_state[write_buffer_index] <= 1'b0;
        end
        else if (write_buffer_way[1]) begin
            lru_state[write_buffer_index] <= 1'b1;
        end
    end
    else if (main_state == `MAIN_REFILL && refill_wr && access_type_1d) begin
        if (refill_way[0]) begin
            lru_state[refill_index] <= 1'b0;
        end
        else if (refill_way[1]) begin
            lru_state[refill_index] <= 1'b1;
        end
    end
end

endmodule