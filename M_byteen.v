`include "constant.v"

// 在E级发挥作用，不要被名字误导

module M_byteen (
    input  wire [31:0] alu_result,
    input  wire                             writeEnable,
    input  wire [`data_type_sel_width-1:0]  dataType,  // 独热码
    input  wire [31:0]                      address,
    input  wire E_valid,
    input  wire M_valid,
    input  wire W_valid,
    input  wire [`exception_width-1:0]  E_exception,
    input  wire [`exception_width-1:0]  M_exception,
    input  wire [`exception_width-1:0]  W_exception,
    input  wire E_memReadOrWrite,
    input  wire M_ready,
    input  wire ALE,
    input  wire request,
    output wire [3:0]                       byteEnable,
    output wire data_sram_wr,
    output wire data_sram_req,
    output wire [1:0] data_sram_size,

    input  wire [`CACHE_TARGET_WIDTH-1:0] cache_target,
    input  wire [    `CACHE_OP_WIDTH-1:0] cache_operation,
    output wire [`CACHE_OP_WIDTH + 1:0] data_op,

    // inst_cacop
    output wire inst_cacop_req,
    output wire [4:0] inst_cacop_op,
    output wire [31:0] inst_cacop_vaddr,

    input  wire LL_bit,
    input  wire is_LL_W,
    input  wire is_SC_W,
    output wire data_load,
    output wire data_store
);

assign data_load = 
    (E_memReadOrWrite & ~writeEnable) | cache_operation[`CACHE_OP_HIT_OP] |
    cache_operation[`CACHE_OP_PRELD];
assign data_store = (is_SC_W && LL_bit) | writeEnable;

assign data_op = {cache_operation, data_store, E_memReadOrWrite & ~writeEnable};

assign data_sram_req = 
    (data_store | (E_memReadOrWrite & ~writeEnable) 
        | cache_target[`CACHE_TARGET_DCACHE])& 
    M_ready & 
    E_valid & ~|E_exception &
    ~(M_valid & |M_exception) &
    ~(W_valid & |W_exception);

assign data_sram_wr = data_store;

assign data_sram_size = 
    ({2{dataType[`word]}} & 2'b10) |
    ({2{dataType[`half]}} & 2'b01) |
    ({2{dataType[`byte]}} & 2'b00) ;

// 地址位选择
wire [1:0] addr_low = address[1:0];
wire       addr_bit1 = address[1];
wire       addr_bit0 = address[0];

// 字节使能生成 - 使用逻辑表达式
assign byteEnable[0] = 
    data_store & (
        (dataType[`word]) |                                      // 字访问
        (dataType[`half] & ~addr_bit1) |                        // 半字访问（低16位）
        (dataType[`byte] & (addr_low == 2'b00)));               // 字节访问（最低字节）

assign byteEnable[1] = 
    data_store & (
        (dataType[`word]) |                                      // 字访问
        (dataType[`half] & ~addr_bit1) |                        // 半字访问（低16位）
        (dataType[`byte] & (addr_low == 2'b01)));               // 字节访问（次低字节）

assign byteEnable[2] = 
    data_store & (
        (dataType[`word]) |                                      // 字访问
        (dataType[`half] & addr_bit1) |                         // 半字访问（高16位）
        (dataType[`byte] & (addr_low == 2'b10)));               // 字节访问（次高字节）

assign byteEnable[3] = 
    data_store & (
        (dataType[`word]) |                                      // 字访问
        (dataType[`half] & addr_bit1) |                         // 半字访问（高16位）
        (dataType[`byte] & (addr_low == 2'b11)));               // 字节访问（最高字节）

//inst_cacop

assign inst_cacop_req = 
    E_valid & cache_target[`CACHE_TARGET_ICACHE] & ~|E_exception & M_ready;
assign inst_cacop_op[1:0] = 2'b00;
assign inst_cacop_op[4:2] = cache_operation;
assign inst_cacop_vaddr = alu_result;

endmodule