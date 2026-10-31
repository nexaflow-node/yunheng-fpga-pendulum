// v5 keys: SW1 = calibrate (IDLE) / stop (running, level-sensitive),
// SW2 = clear encoder (IDLE). D1 does not consume position-mode events.
// SW3 = start (IDLE, hold 1.5 s alone then release) / stop (running).
// In D1 all three synchronized key levels stop an active run.
// The top also gates the bridge from raw key levels before debounce.
module c_keys #(parameter DEBOUNCE_CYCLES=1000000,LONG_MS=1500)
 (input clk,rst_n,tick_ms,input [2:0] key_n,
 output reg calib,clear,start,mode_press,
 output wire stop_level,
 output wire sw3_level);
 reg [2:0] s1,s2,stable;reg [31:0] count[0:2];
 reg armed,holding,cancel;reg [15:0] held_ms;integer i;
 // key_n = {SW3,SW2,SW1}; low when pressed
 assign stop_level = (s2!=3'b111);   // any key physically low after synchronization
 assign sw3_level = ~s2[2];          // SW3 pressed (synced); used as the only runtime stop
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   s1<=7;s2<=7;stable<=7;calib<=0;clear<=0;start<=0;mode_press<=0;armed<=0;holding<=0;cancel<=0;held_ms<=0;
   for(i=0;i<3;i=i+1)count[i]<=0;
  end else begin
   s1<=key_n;s2<=s1;calib<=0;clear<=0;start<=0;mode_press<=0;
   if(!armed)begin
    if(s2!=7)begin for(i=0;i<3;i=i+1)count[i]<=0;end
    else if(count[0]>=DEBOUNCE_CYCLES-1)begin armed<=1;for(i=0;i<3;i=i+1)count[i]<=0;end
    else count[0]<=count[0]+1'b1;
   end else begin
    if(holding && (s2|3'b100)!=7)cancel<=1;
    if(tick_ms && holding && !stable[2] && held_ms<65535)held_ms<=held_ms+1'b1;
    for(i=0;i<3;i=i+1)begin
     if(s2[i]==stable[i])count[i]<=0;
     else if(count[i]>=DEBOUNCE_CYCLES-1)begin
      stable[i]<=s2[i];count[i]<=0;
      if(!s2[i])begin
       if(i==0)calib<=1;      // SW1 press event
       if(i==1)begin clear<=1;mode_press<=1;end  // SW2 press event
       if(i==2)begin holding<=1;held_ms<=0;cancel<=(s2!=3'b011);end
      end else if(i==2)begin
       holding<=0;
       if(holding && !cancel && held_ms>=LONG_MS && s2==7 && stable==3'b011)start<=1;
      end
     end else count[i]<=count[i]+1'b1;
    end
   end
  end
 end
endmodule
