// 5 MHz ADC clock, capture 80ns after rising edge (phase 3 -> 4), 128-code mean.
// 25.6us averaging windows, not added 128ms control latency.
// (v5: unchanged from v2 -- proven interface.)
module c_adc(input clk,rst_n,input [9:0] data,output reg adc_clk,
 output reg [11:0] raw12,output reg have_sample);
 reg [3:0] phase;reg [9:0] adc_data_reg;reg capture,sample_clk;
 reg [6:0] n;reg [16:0] sum;
 wire [17:0] sum_next={1'b0,sum}+{8'b0,adc_data_reg};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin phase<=0;adc_clk<=0;sample_clk<=0;capture<=0;n<=0;sum<=0;raw12<=0;have_sample<=0;end
  else begin
   phase<=(phase==9)?4'd0:phase+1'b1;
   if(phase==9)adc_clk<=1;
   if(phase==4)adc_clk<=0;
   if(phase==3)sample_clk<=1;
   if(phase==8)sample_clk<=0;
   capture<=(phase==3);
   if(capture)begin
    if(n==127)begin raw12<=sum_next[16:5];n<=0;sum<=0;have_sample<=1;end
    else begin sum<=sum_next[16:0];n<=n+1'b1;end
   end
  end
 end
 // Dedicated divided clock makes the external bus launch/capture phase explicit
 // in STA. Transfer to the 50MHz sum occurs on the following system edge.
 always @(posedge sample_clk or negedge rst_n)begin
  if(!rst_n)adc_data_reg<=0;else adc_data_reg<=data;
 end
endmodule
