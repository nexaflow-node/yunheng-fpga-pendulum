// 11-cycle signed 32x32 -> 64 multiplier: one 9x17 signed partial product
// per cycle (cnt 1..8), then a two-stage registered assembly (cnt 9, 10).
// Why not a plain behavioral multiply: the GW2A synthesizer maps it to a
// LUT carry chain (~50 ns for a 16x16 -> misses the 20 ns setup by ~30 ns)
// and the device's 20 DSPs are all consumed by the constant multiplies in
// c_balance_core / c_output / c_sensor / c_swing. Every per-cycle multiply
// here is at most 9x17 = 26 bits, which keeps the carry chain short enough
// (measured: c_mul32 drops out of the violation list entirely).
// start at T -> done pulse at T+10; callers wait on done, so the extra
// latency is transparent.
module c_mul32(input clk,rst_n,input start,
 input signed [31:0] a,b,
 output reg signed [63:0] p,output reg done);
 // b split into a signed high half and an unsigned low half, 17 bits each
 wire signed [16:0] bh17 = {{1{b[31]}},b[31:16]};
 wire signed [16:0] bl17 = {1'b0,b[15:0]};
 // a split into four 9-bit signed bytes (a3 is the only signed one)
 wire signed [8:0] a0 = {1'b0,a[7:0]};
 wire signed [8:0] a1 = {1'b0,a[15:8]};
 wire signed [8:0] a2 = {1'b0,a[23:16]};
 wire signed [8:0] a3 = {a[31],a[31:24]};   // sign-extend, not zero-extend
 reg signed [25:0] t1,t2,t3,t4,t5,t6,t7,t8;   // |ti| <= 255*65535 < 2^24
 reg signed [47:0] ph,pl;                     // a*bh <= 2^46 ; a*bl < 2^47
 reg [3:0] cnt;
 reg run;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   t1<=0;t2<=0;t3<=0;t4<=0;t5<=0;t6<=0;t7<=0;t8<=0;
   ph<=0;pl<=0;cnt<=0;run<=0;done<=0;p<=0;
  end else begin
   done<=1'b0;
   if(start) begin cnt<=4'd1; run<=1'b1; end
   else if(run) begin
    case(cnt)
     4'd1: begin t1<=a0*bh17; cnt<=4'd2; end
     4'd2: begin t2<=a1*bh17; cnt<=4'd3; end
     4'd3: begin t3<=a2*bh17; cnt<=4'd4; end
     4'd4: begin t4<=a3*bh17; cnt<=4'd5; end
     4'd5: begin t5<=a0*bl17; cnt<=4'd6; end
     4'd6: begin t6<=a1*bl17; cnt<=4'd7; end
     4'd7: begin t7<=a2*bl17; cnt<=4'd8; end
     4'd8: begin t8<=a3*bl17; cnt<=4'd9; end
     // assembly stage 1: a*bh = t4<<24 + t3<<16 + t2<<8 + t1
     4'd9: begin
      ph<=({{22{t4[25]}},t4}<<<24)+({{22{t3[25]}},t3}<<<16)
         +({{22{t2[25]}},t2}<<<8)+{{22{t1[25]}},t1};
      pl<=({{22{t8[25]}},t8}<<<24)+({{22{t7[25]}},t7}<<<16)
         +({{22{t6[25]}},t6}<<<8)+{{22{t5[25]}},t5};
      cnt<=4'd10;
     end
     // assembly stage 2: p = (a*bh)<<16 + a*bl
     4'd10: begin
      p<=({{16{ph[47]}},ph}<<<16)+{{16{pl[47]}},pl};
      done<=1'b1;
      run<=1'b0;
     end
     default: run<=1'b0;
    endcase
   end
  end
 end
endmodule
