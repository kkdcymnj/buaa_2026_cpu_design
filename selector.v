module selector
#(
    parameter WIDTH = 32  // TLB条目数量，默认16项
)
 (
    input  [WIDTH-1:0] in,
    output [$clog2(WIDTH)-1:0] out_en
);

wire [WIDTH-1:0] one_in;

assign one_in[0] = in[0];

genvar i;
generate 
	for (i=1; i<WIDTH; i=i+1)
	begin: sel_one
		assign one_in[i] = in[i] && ~|in[i-1:0];
	end
endgenerate

encoder #(
    .WIDTH(WIDTH)
) u_encoder (
    .in(one_in),
    .out(out_en)
);

endmodule