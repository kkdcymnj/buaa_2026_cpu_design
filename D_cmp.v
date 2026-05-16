`include "constant.v"

module D_cmp (
    input  wire [31:0]  op1,
    input  wire [31:0]  op2,
    input  wire [`cmp_sel_width-1:0]    cmpOp,

    output wire flag
);

wire eq  = (op1 == op2);
wire lt  = ($signed(op1) < $signed(op2));   // 有符号小于
wire ltu = (op1 < op2);                      // 无符号小于

wire beq  = eq;
wire bne  = ~eq;
wire blt  = lt;
wire bge  = ~lt;
wire bltu = ltu;
wire bgeu = ~ltu;

assign flag = 
    ({1{cmpOp[`cmp_beq]}}  & beq) |
    ({1{cmpOp[`cmp_bne]}}  & bne) |
    ({1{cmpOp[`cmp_blt]}}  & blt) |
    ({1{cmpOp[`cmp_bge]}}  & bge) |
    ({1{cmpOp[`cmp_bltu]}} & bltu) |
    ({1{cmpOp[`cmp_bgeu]}} & bgeu) |
    ({1{cmpOp[`cmp_b]}} & 1'b1);

endmodule //D_cmp
