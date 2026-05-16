`include "constant.v"

`define READ_IDIE 2'b00
`define READ_WAIT_AR 2'b01
`define READ_GET_DATA 2'b11

`define WRITE_IDLE 0
`define WRITE_LATCH 1
`define WRITE_WAIT_AW 2
`define WRITE_WRITE_DATA 3
`define WRITE_RESPONSE 4 

`define DATA_ARID 1
`define INST_ARID 0

module AXI_Bridge (
    input  wire aclk,
    input  wire aresetn,
    output wire clk,
    output reg  reset,

    input  wire        inst_sram_req,
    input  wire [ 2:0] inst_sram_rd_type,
    input  wire [31:0] inst_sram_addr,
    output reg         inst_sram_addr_ok,
    output wire        inst_sram_data_ok,
    output wire [31:0] inst_sram_rdata,
    output wire        inst_sram_ret_last,

    input  wire        data_sram_rd_req,
    input  wire [ 2:0] data_sram_rd_type,
    input  wire [31:0] data_sram_rd_addr,
    output reg         data_sram_rd_addr_ok,

    input  wire         data_sram_wr_req,
    input  wire [  2:0] data_sram_wr_type,
    input  wire [ 31:0] data_sram_wr_addr,
    input  wire [  3:0] data_sram_wr_wstrb,
    input  wire [127:0] data_sram_wr_data,
    output wire         data_sram_wr_addr_ok,
    output reg          data_sram_wr_resp,

    output wire        data_sram_ret_valid,
    output wire [31:0] data_sram_rdata,
    output wire        data_sram_ret_last,

    // 0: 强序非缓存, 1: 一致可缓存
    input wire inst_sram_access_type,
    input wire data_sram_access_type,

    output reg  [ 3:0] arid,
    output reg  [31:0] araddr,
    output reg  [ 7:0] arlen,
    output reg  [ 2:0] arsize,
    output wire [ 1:0] arburst,
    output wire [ 1:0] arlock,
    output wire [ 3:0] arcache,
    output wire [ 2:0] arprot,
    output reg         arvalid,
    input  wire        arready,

    input  wire [ 3:0] rid,
    input  wire [31:0] rdata,
    input  wire [ 1:0] rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output reg         rready,

    output wire [ 3:0] awid,
    output reg  [31:0] awaddr,
    output reg  [ 7:0] awlen,
    output reg  [ 2:0] awsize,
    output wire [ 1:0] awburst,
    output wire [ 1:0] awlock,
    output wire [ 3:0] awcache,
    output wire [ 2:0] awprot,
    output reg         awvalid,
    input  wire        awready,

    output wire [ 3:0] wid,
    output reg  [31:0] wdata,
    output reg  [ 3:0] wstrb,
    output reg         wvalid,
    output reg         wlast,
    input  wire        wready,

    input  wire [3:0] bid,
    input  wire [1:0] bresp,
    input  wire       bvalid,
    output reg        bready
);

assign clk = aclk;
always @(posedge aclk) 
    reset <= ~aresetn;

assign arburst = 2'b01;
assign arlock  = 2'b00;
assign arcache = 4'b0000;
assign arprot  = 3'b000;
assign awid    = 4'b0001;
assign awburst = 2'b01;
assign awlock  = 2'b00;
assign awcache = 4'b0000;
assign awprot  = 3'b000;
assign wid     = 4'b0001;
// assign rready  = 1'b1;

wire cpu_rd_req = data_sram_rd_req | inst_sram_req;
wire rd_from_data = data_sram_rd_req;
wire rd_from_inst = ~data_sram_rd_req & inst_sram_req;

wire [2:0] curr_rd_type = rd_from_data ? data_sram_rd_type : inst_sram_rd_type;
wire [31:0] curr_rd_addr = rd_from_data ? data_sram_rd_addr : inst_sram_addr;
wire is_burst_rd = (curr_rd_type == 3'b100 && cpu_rd_req);

reg write_pending;
reg [3:0] write_id;

wire curr_rd_access_type = 
    rd_from_data ? data_sram_access_type : inst_sram_access_type;
wire writing_block = 
    write_pending & 
        ((inst_sram_req && !inst_sram_access_type) || 
        (data_sram_rd_req && !data_sram_access_type) || 
        (data_sram_wr_req && !data_sram_access_type));

//READ状态机
reg [1:0] read_state;
reg [ 1:0] burst_cnt_rd;

reg        cur_rd_is_data;
reg [ 3:0] cur_rd_id;
reg [31:0] _cache_rdata;
reg        cache_rvalid;
reg        cache_rlast;

always @(posedge clk ) begin
    if (reset) begin
        arvalid <= 0;
        araddr <= 0;
        arlen <= 0;
        arsize <= 0;
        arid <= 0;
        inst_sram_addr_ok <= 0;
        data_sram_rd_addr_ok <= 0;
        cur_rd_is_data <= 0;
        cur_rd_id <= 0;
        burst_cnt_rd <= 0;
        read_state <= `READ_IDIE;
    end
    else begin
        inst_sram_addr_ok <= 0;
        data_sram_rd_addr_ok <= 0;
        case (read_state)
            `READ_IDIE: begin
                if (cpu_rd_req & !writing_block) begin
                    arvalid <= 1;
                    araddr <= curr_rd_addr;
                    arid <= rd_from_data ? 1 : 0;
                    cur_rd_id <= rd_from_data ? 1 : 0;
                    cur_rd_is_data <= rd_from_data;
                    arlen <= is_burst_rd ? 3 : 0;
                    arsize <= is_burst_rd ? 3'b010 : curr_rd_type;
                    read_state <= `READ_WAIT_AR;
                end
            end
            `READ_WAIT_AR: begin
                if (arvalid & arready) begin
                    arvalid <= 0;
                    burst_cnt_rd <= 0;
                    read_state <= `READ_GET_DATA;
                    if (cur_rd_is_data) begin
                        data_sram_rd_addr_ok <= 1;
                    end
                    else begin
                        inst_sram_addr_ok <= 1;
                    end
                    rready <= 1;
                end
            end
            `READ_GET_DATA: begin
                if (rvalid & rlast) begin
                    read_state <= `READ_IDIE;
                    rready <= 0;
                end
            end
        endcase
    end
end

// 暂存读出的数据
always @(posedge clk ) begin
    if (reset) begin
        _cache_rdata <= 0;
        cache_rvalid <= 0;
        cache_rlast <= 0;
    end
    else if (rvalid & (rid[0] == cur_rd_id)) begin
        _cache_rdata <= rdata;
    end
    cache_rvalid <= rvalid & (rid[0] == cur_rd_id);
    cache_rlast <= rvalid & (rid[0] == cur_rd_id) & rlast;
end

//WRITE状态机
reg [2:0] write_state;

reg [  2:0] burst_cnt_wr;
reg [127:0] burst_wr_buf;
reg [ 31:0] wr_addr_buf;
reg [  2:0] wr_type_buf;
reg [  3:0] wr_strb_buf;
reg         wr_is_burst;
reg         wr_req_buf;
reg         wr_access_type_buf;
reg         data_sram_wr_req_d;

wire [31:0] suc_selected_wdata = 
    wr_addr_buf[3:2] == 2'b00 ? burst_wr_buf[31:0] :
    wr_addr_buf[3:2] == 2'b01 ? burst_wr_buf[63:32] :
    wr_addr_buf[3:2] == 2'b10 ? burst_wr_buf[95:64] :
    burst_wr_buf[127:96];

always @(posedge clk ) begin
    if (reset) begin
        awvalid <= 0;
        awaddr <= 0;
        awlen <= 0;
        awsize <= 0;
        wvalid <= 0;
        wdata <= 0;
        wstrb <= 0;
        wlast <= 0;
        bready <= 0;
        burst_cnt_wr <= 0;
        write_state <= `WRITE_IDLE;
        wr_req_buf         <= 0;
        burst_wr_buf       <= 128'b0;
        wr_addr_buf        <= 32'b0;
        wr_type_buf        <= 3'b0;
        wr_strb_buf        <= 4'b0;
        wr_is_burst        <= 1'b0;
        wr_access_type_buf <= 1'b0;
        write_pending      <= 0;
        write_id           <= 0;
    end
    else begin
        if (bvalid && (bid == write_id)) begin
            write_pending <= 0;
        end
        data_sram_wr_resp  <= 0;
        data_sram_wr_req_d <= data_sram_wr_req;
        case (write_state)
            `WRITE_IDLE: begin
                if (data_sram_wr_req & ~writing_block) begin
                    wr_is_burst        <= (data_sram_wr_type == 3'b100);
                    burst_wr_buf       <= data_sram_wr_data;
                    wr_addr_buf        <= data_sram_wr_addr;
                    wr_type_buf        <= data_sram_wr_type;
                    wr_strb_buf        <= data_sram_wr_wstrb;
                    wr_access_type_buf <= data_sram_access_type;
                    wr_req_buf         <= 1;
                    write_state        <= `WRITE_LATCH;
                end
            end
            `WRITE_LATCH: begin
                awvalid <= 1;
                awaddr <= wr_addr_buf;
                awlen <= wr_is_burst ? 3 : 0;
                awsize <= wr_is_burst ? 3'b010 : wr_type_buf;
                write_state <= `WRITE_WAIT_AW;
                if (!wr_access_type_buf) begin
                    write_pending <= 1;
                    write_id <= 1;
                end
            end
            `WRITE_WAIT_AW: begin
                if (awvalid & awready) begin
                    awvalid <= 0;
                    wvalid <= 1;
                    wdata <=
                        wr_is_burst ? burst_wr_buf[31:0] :
                        wr_access_type_buf ? burst_wr_buf[31:0] :
                        suc_selected_wdata;
                    wstrb <= 
                        wr_is_burst ? 4'b1111 : wr_strb_buf;
                    burst_cnt_wr <= wr_is_burst ? 3 : 0;
                    burst_wr_buf <= {32'b0, burst_wr_buf[127:32]};
                    wlast <= wr_is_burst ? 0 : 1;
                    write_state <= `WRITE_WRITE_DATA;
                end
            end
            `WRITE_WRITE_DATA: begin
                if (wvalid & wready) begin
                    if (wlast) begin
                        wvalid   <= 1'b0;
                        wlast    <= 1'b0;
                        bready   <= 1;
                        write_state <= `WRITE_RESPONSE;
                    end
                    else begin
                        if (burst_cnt_wr == 1) begin
                            wlast <= 1'b1;
                        end
                        wdata        <= burst_wr_buf[31:0];
                        burst_wr_buf <= {32'b0, burst_wr_buf[127:32]};
                        burst_cnt_wr <= burst_cnt_wr - 1;
                    end
                end
            end
            `WRITE_RESPONSE: begin
                if (bvalid && bready) begin
                    bready            <= 0;
                    data_sram_wr_resp <= 1;
                    wr_req_buf        <= 0;
                    write_state       <= `WRITE_IDLE;
                end
            end
        endcase
    end
end

assign data_sram_rdata = _cache_rdata;
assign data_sram_ret_valid = cache_rvalid & cur_rd_is_data;
assign data_sram_ret_last  = cache_rlast & cur_rd_is_data;
assign inst_sram_rdata = _cache_rdata;
assign inst_sram_data_ok = cache_rvalid & ~cur_rd_is_data;
assign inst_sram_ret_last = cache_rlast & ~cur_rd_is_data;

assign data_sram_wr_addr_ok = !wr_req_buf && !writing_block;

endmodule //AXI_bridge