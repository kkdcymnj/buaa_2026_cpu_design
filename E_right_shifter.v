module E_right_shifter #(
    WIDTH = 32
)(
    input   wire [WIDTH-1:0]            operand,
    input   wire [$clog2(WIDTH)-1:0]    shamt,
    input   wire                        is_arithmetic,
    output  wire [WIDTH-1:0]            result
);

wire [WIDTH-1+(2<<$clog2(WIDTH)):0] temp;
assign temp   
    = {{(2 << $clog2(WIDTH)) {operand[WIDTH-1] & is_arithmetic}}, operand} >> shamt;
assign result = temp[WIDTH-1:0];
endmodule
//E_shifter