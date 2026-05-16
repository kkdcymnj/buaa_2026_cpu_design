//`include "macros.h"

module encoder #(
    parameter WIDTH = 32
) (
    input  wire [        WIDTH-1:0] in,
    output reg  [$clog2(WIDTH)-1:0] out
);

    integer i, j;
    always @(*) begin
        out = {$clog2(WIDTH) {1'b0}};
        for (i = 0; i < WIDTH; i = i + 1) begin
            for (j = 0; j < $clog2(WIDTH); j = j + 1) begin
                if (i[j]) begin
                    out[j] = out[j] | in[i];
                end else begin
                    out[j] = out[j];
                end
            end
        end
    end

endmodule
