module flip_flop
(
    input wire sys_clk, //50MHZ
    input wire sys_res_n, 
    input wire key_in,

    output reg led_out
);

always @(posedge sys_clk or negedge sys_res_n)
    if(sys_res_n ==1'b0)
        led_out <=1'b0;
    else
        led_out <=key_in;



endmodule