`include "constant.v"

module M_dataExt (
    input  wire [1:0]   addrLow,
    input  wire [31:0]  dataIn,
    input  wire [`data_type_sel_width-1:0]  dataType,
    input  wire isSigned,

    //控制信号
    input  wire [`exception_width-1:0] M_exception,
    input  wire M_memReadOrWrite,
    input  wire data_sram_data_ok,
    input  wire inst_sram_data_ok,
    input  wire LL_bit,
    input  wire is_LL_W,
    input  wire is_SC_W,
    input  wire [ `CACHE_TARGET_WIDTH-1:0] cache_target,
    input  wire div_complete,
    input  wire div_instr,  // 当前指令是否是除法指令
    output wire M_done,

    output wire [31:0]  dataOut
);

// TODO: M_done：无异常、如果要读写则数据准备好
assign M_done = 
    |M_exception ? 1'b1:
    (M_memReadOrWrite | is_SC_W & LL_bit | cache_target[`CACHE_TARGET_DCACHE]) ? 
        data_sram_data_ok : 
    cache_target[`CACHE_TARGET_ICACHE] ? inst_sram_data_ok:
    //div_instr ? div_complete :
        1'b1;

wire [1:0] byte_sel = addrLow;
wire half_sel = addrLow[1];

wire [7:0] byte_content = dataIn[byte_sel*8 +: 8];
wire [15:0] half_content = dataIn[half_sel*16 +: 16];
wire [31:0] word_content = dataIn;

wire [31:0] byte_extended = 
    { {24{isSigned & byte_content[7]}}, byte_content };
wire [31:0] half_extended = 
    { {16{isSigned & half_content[15]}}, half_content };
wire [31:0] word_extended = word_content;

assign dataOut =
    {32{dataType[`byte]}} & byte_extended |
    {32{dataType[`half]}} & half_extended |
    {32{dataType[`word]}} & word_extended;

endmodule //M_dataExt