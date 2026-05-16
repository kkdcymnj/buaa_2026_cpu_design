`include "constant.v"

module D_extend (
    input  wire [11:0]  imm_12,
    input  wire [13:0]  imm_14,
    input  wire [15:0]  imm_16,
    input  wire [19:0]  imm_20,

    input  wire isSigned,
    input  wire [`imm_select_width-1:0] imm_len,    // 独热编码

    output wire [31:0]  result
);

// 各立即数的符号位
wire sign_12 = imm_12[11];
wire sign_14 = imm_14[13];
wire sign_16 = imm_16[15];
wire sign_20 = imm_20[19];

wire [31:0] ext_12 = 
    { {20{isSigned ? sign_12 : 1'b0}}, imm_12 };

// 仅有LL和SC指令使用
wire [31:0] ext_14 = 
    { {16{isSigned ? sign_14 : 1'b0}}, imm_14, 2'b0 };

wire [31:0] ext_16 = 
    { {16{isSigned ? sign_16 : 1'b0}}, imm_16 };
    
// 20位立即数扩展（左移12位，用于lu12i.w）
wire [31:0] ext_20 = 
    { imm_20, 12'b0 };

// 根据imm_len选择最终结果
assign result = 
    ({32{imm_len[`imm_12]}} & ext_12) |
    ({32{imm_len[`imm_14]}} & ext_14) |
    ({32{imm_len[`imm_16]}} & ext_16) |
    ({32{imm_len[`imm_20]}} & ext_20) ;

endmodule