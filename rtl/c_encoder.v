module c_encoder #(parameter FILTER_CYCLES=8,REVERSE=0)
 (input clk,rst_n,enc_a,enc_b,clear,output reg signed [31:0] count,output reg bad);
 reg [1:0] s1,s2,filt,prev;reg [7:0] fc0,fc1;reg [6:0] warmup;
 reg signed [1:0] delta;
 always @* begin
  case({prev,filt})
   4'b0010,4'b1011,4'b1101,4'b0100:delta=2'sd1;
   4'b0001,4'b0111,4'b1110,4'b1000:delta=-2'sd1;
   default:delta=0;
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin s1<=0;s2<=0;filt<=0;prev<=0;fc0<=0;fc1<=0;warmup<=0;count<=0;bad<=0;end
  else begin
   s1<={enc_a,enc_b};s2<=s1;prev<=filt;
   if(s2[0]==filt[0])fc0<=0;
   else if(fc0>=FILTER_CYCLES-1)begin filt[0]<=s2[0];fc0<=0;end else fc0<=fc0+1'b1;
   if(s2[1]==filt[1])fc1<=0;
   else if(fc1>=FILTER_CYCLES-1)begin filt[1]<=s2[1];fc1<=0;end else fc1<=fc1+1'b1;
   if(warmup<64)warmup<=warmup+1'b1;
   else if(clear)begin count<=0;bad<=0;end
   else begin
    count<=REVERSE?count-delta:count+delta;
    if((prev^filt)==2'b11)bad<=1;
   end
  end
 end
endmodule
