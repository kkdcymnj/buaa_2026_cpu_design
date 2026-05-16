module blk_mem_gen_tagv
#(  // 参数不生效仅做标记
    parameter WIDTH = 21    ,
    parameter DEPTH = 256
)
( 
    input  [ 7:0]          addra   ,
    input                  clka    ,
    input  [20:0]          dina    ,
    output [20:0]          douta   ,
    input                  ena     ,
    input                  wea 
);

reg [20:0] mem_reg [255:0];
reg [20:0] output_buffer;

always @(posedge clka) begin
    if (ena) begin
        if (wea) begin
            mem_reg[addra] <= dina;
        end
        else begin
            output_buffer <= mem_reg[addra];
        end
    end
end

assign douta = output_buffer;

endmodule