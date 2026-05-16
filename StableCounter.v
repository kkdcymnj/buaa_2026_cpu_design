`include "constant.v"
`include "instr_code.v"

module StableCounter (
    input  wire clk,
    input  wire reset,
    output wire [31:0]  highCnt,
    output wire [31:0]  lowCnt
);

reg [63:0]  counter;

always @(posedge clk ) begin
    if (reset) begin
        counter <= 64'b0;
    end
    else begin
        counter <= counter + 64'b1;
    end
end

assign highCnt = counter[63:32];
assign lowCnt = counter[31:0];

endmodule //StableCounter