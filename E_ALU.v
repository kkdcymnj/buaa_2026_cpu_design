`include "constant.v"

module E_ALU (
	input  wire E_valid,
	input  wire clk,
	input  wire reset, 
	input [31:0] operand1,
	input [31:0] operand2,
	input [`alu_op_width-1:0] ALUOp,
	input [4:0] shamt,
	output [31:0] E_alu_result,
	output wire [31:0]	E_memAddr,
	output wire E_ALU_done

	/*output wire [31:0]  div_result,
	output wire [31:0]  mod_result,
	output wire div_complete */
);

wire op_add = ALUOp[`alu_add];
wire op_sub = ALUOp[`alu_sub];
wire op_or  = ALUOp[`alu_or];
wire op_and = ALUOp[`alu_and];
wire op_slt = ALUOp[`alu_slt];
wire op_sltu = ALUOp[`alu_sltu];
wire op_sll = ALUOp[`alu_sll];
wire op_srl = ALUOp[`alu_srl];	
wire op_sra = ALUOp[`alu_sra];
wire op_nor = ALUOp[`alu_nor];
wire op_xor = ALUOp[`alu_xor];
wire op_lui = ALUOp[`alu_lui];
wire op_andn = ALUOp[`alu_andn];
wire op_orn = ALUOp[`alu_orn];
wire op_slli = ALUOp[`alu_slli];
wire op_srli = ALUOp[`alu_srli];
wire op_srai = ALUOp[`alu_srai];
wire op_div_w = ALUOp[`alu_div_w];
wire op_div_wu = ALUOp[`alu_div_wu];
wire op_mod_w = ALUOp[`alu_mod_w];
wire op_mod_wu = ALUOp[`alu_mod_wu];

wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] sll_result;
wire [31:0] sr_result;	//srl, sra
wire [31:0] lui_result;
wire [31:0] andn_result;
wire [31:0] orn_result;

// 加法器：add, sub, slt, sltu

wire [31:0] adder_operand1 = operand1;
wire [31:0] adder_operand2 = 
	(op_sub | op_slt | op_sltu) ? ~operand2 : operand2;
wire adder_cin = op_sub | op_slt | op_sltu; // 补码运算，取反加1
wire adder_cout;
wire [31:0] adder_result;

E_full_adder #(
	.WIDTH(32)
) e_full_adder (
	.addend1(adder_operand1),
	.addend2(adder_operand2),
	.cin(adder_cin),
	.sum(adder_result),
	.cout(adder_cout)
);

assign add_sub_result = adder_result;
assign sltu_result = {{31{1'b0}}, {~adder_cout}};
assign slt_result[31:1] = 0;
assign slt_result[0] = 
	(operand1[31] & ~operand2[31]) |
	((operand1[31] ~^ operand2[31]) & adder_result[31]);

wire [4:0] shamtNum = (op_slli | op_srli | op_srai) ? shamt : operand2[4:0];

// sll
assign sll_result = operand1 << shamtNum;

// 移位器：srl, sra
E_right_shifter #(
	.WIDTH(32)
) e_right_shifter (
	.operand(operand1),
	.shamt(shamtNum),
	.is_arithmetic(op_sra | op_srai),
	.result(sr_result)
);

// 其他简单逻辑运算
assign and_result = operand1 & operand2;
assign or_result = operand1 | operand2;
assign nor_result = ~(operand1 | operand2);
assign xor_result = operand1 ^ operand2;
assign lui_result = operand2;	//已经处理过的立即数
assign andn_result = operand1 & ~operand2;
assign andn_result = operand1 | ~operand2;

wire [31:0] E_div_result;
wire [31:0] E_mod_result;
wire E_div_complete_ahead;
wire E_div_done;

/*
E_divider e_divider(
	.div_en     (E_valid & (op_div_w | op_div_wu | op_mod_w | op_mod_wu)),
	.div_clk    (clk),
	.div_reset  (reset),
	.div_signed (op_div_w | op_mod_w),
	.operand1   (operand1),
	.operand2   (operand2),
	.quotient   (div_result),
	.remainder  (mod_result),
	//.complete   (E_div_complete_ahead),
	.complete_delay   (div_complete)
);
*/

assign E_alu_result =
({32{op_add | op_sub}} & add_sub_result) |
({32{op_slt}} & slt_result) |
({32{op_sltu}} & sltu_result) |
({32{op_and}} & and_result) |
({32{op_or}} & or_result) |
({32{op_nor}} & nor_result) |
({32{op_xor}} & xor_result) |
({32{op_sll | op_slli}} & sll_result) |
({32{op_srl | op_srli}} & sr_result) |
({32{op_sra | op_srai}} & sr_result) |
({32{op_lui}} & lui_result) |
({32{op_andn}} & andn_result) |
({32{op_orn}} & orn_result) /*|
({32{op_div_w | op_div_wu}} & E_div_result) |
({32{op_mod_w | op_mod_wu}} & E_mod_result)*/;

assign E_memAddr = add_sub_result;

// 使用了阻塞流水线的除法器设计
assign E_ALU_done = /*(op_div_w | op_div_wu | op_mod_w | op_mod_wu) ? E_div_done :*/ 1'b1;

endmodule //E_ALU