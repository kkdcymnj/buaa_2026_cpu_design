module divider (
    input  wire div_en,        // 除法请求信号（输入）- 单周期脉冲
    input  wire div_clk,
    input  wire div_reset,    
    input  wire div_signed,    // 是否是有符号除法
    
    input  wire [4:0] div_reg_dst,

    input  wire [31:0]  operand1,
    input  wire [31:0]  operand2,
    output wire [31:0]  quotient,
    output wire [31:0]  remainder,
    output wire complete,
    output wire complete_delay,      // 除法完成信号
    output reg busy,

    output reg [4:0] div_reg_dst_buf
);

reg [32:0] unsigned_quotient;
reg [32:0] unsigned_remainder;
reg [32:0] temp_remainder;
wire [32:0] temp_decrease;
reg [7:0] count;

wire [32:0] unsigned_op1;
wire [32:0] unsigned_op2;

reg div_signed_buffer;
reg op1_31_buffer;
reg op2_31_buffer;
wire real_div_signed;
wire real_op1_31;
wire real_op2_31;
reg [31:0] op1_buffer;
reg [31:0] op2_buffer;

// wire complete_delay;
wire real_complete;

reg delay;

assign complete_delay = (count == 8'hf0);
assign complete = (count == 8'hff);
assign real_complete = complete_delay | complete;

always @(posedge div_clk ) begin
    if (div_reset) begin
        div_signed_buffer <= 0;
        op1_31_buffer <= 0;
        op2_31_buffer <= 0;
        delay <= 0;
    end
    else if(div_en) begin
        div_signed_buffer <= div_signed;
        op1_31_buffer <= operand1[31];
        op2_31_buffer <= operand2[31];
        div_reg_dst_buf <= div_reg_dst;
        op1_buffer <= operand1;
        op2_buffer <= operand2;
        // delay <= 1;
    end
end

assign real_div_signed = real_complete ? div_signed_buffer : div_signed;
assign real_op1_31 = real_complete ? op1_31_buffer : operand1[31];
assign real_op2_31 = real_complete ? op2_31_buffer : operand2[31];

assign unsigned_op1 = 
    {1'b0, 
    {real_div_signed ? (operand1[31] ? (~operand1 + 32'b1) : operand1) : operand1}};
assign unsigned_op2 = 
    {1'b0, 
    {real_div_signed ? (operand2[31] ? (~operand2 + 32'b1) : operand2) : operand2}};

always @(posedge div_clk ) begin
    if (div_reset) begin
        count <= 8'd32;
        temp_remainder <= 33'd0;
        unsigned_quotient <= 33'd0;
        unsigned_remainder <= 33'd0;
    end
    else if(~div_en | complete_delay) begin
        count <= 8'd32;
        temp_remainder <= 33'd0;
    end
    else if(~count[7]) begin
        if (temp_decrease[32]) begin
            unsigned_quotient <= {unsigned_quotient[31:0], 1'b0};
            temp_remainder <= {{temp_remainder[31:0], unsigned_op1[count]}};
        end
        else begin
            unsigned_quotient <= {unsigned_quotient[31:0], 1'b1};
            temp_remainder <= temp_decrease;
        end
        count <= count - 1;
    end
    else begin
        unsigned_remainder <= temp_remainder;
        count <= 8'hf0;
    end
end

assign temp_decrease = 
    {{temp_remainder[31:0], unsigned_op1[count]}} - unsigned_op2;

wire [32:0] temp_quotient_res = 
    (real_div_signed ? 
        ((real_op1_31 == real_op2_31) ? unsigned_quotient : ~(unsigned_quotient - 1)) 
        : unsigned_quotient);   

wire [32:0] temp_remainder_res = 
    (real_div_signed ? 
        ((real_op1_31) ? ~(unsigned_remainder - 1) : unsigned_remainder) 
        : unsigned_remainder);   

assign  quotient = temp_quotient_res[31:0];
assign  remainder = temp_remainder_res[31:0];

/*
// TODO：busy信号：有问题
always @(posedge div_clk or posedge div_reset) begin
    if (div_reset) begin
        busy <= 1'b0;
    end else begin
        // 当接收到开始信号且除法器空闲时，busy置1
        if (div_en && count == 8'd32 && !complete_delay && !complete) begin
            busy <= 1'b1;
        end
        // 当除法完成时，busy清0
        else if (div_en && complete_delay) begin
            busy <= 1'b0;
        end
    end
end
*/

endmodule