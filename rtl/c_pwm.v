// TB6612FNG documented modes. All states assume board STBY remains high.
// Direction is held throughout an energized PWM period. PWM-low then
// selects short brake. Zero command selects explicit short brake (11,0).
// D2PB compares only this zero-command mode against D2PS high-Z (00,1).
// Disabled/reset selects short brake (11,0), retaining immediate key gate.
module c_pwm #(parameter PERIOD=2500)(input clk,rst_n,enable,input signed [15:0] duty,
 output wire pwm,in1,in2);
 reg [15:0] counter,compare;
 reg reverse,reversal_blank;
 wire [15:0] magnitude=(duty<0)?-duty:duty;
 wire [15:0] limited=(magnitude>1000)?16'd1000:magnitude;
 wire [31:0] compare_next;
 generate if(PERIOD==2500)begin:exact_20k
  wire [12:0] times5={3'b0,limited[9:0]}*13'd5;
  assign compare_next={20'b0,times5[12:1]};
 end else begin:other_period
  wire [31:0] compare_product=limited*PERIOD;
  assign compare_next=compare_product/1000;
 end endgenerate
 wire disabled=(!enable || !rst_n);
 wire zero_brake=(!disabled && compare==0);
 wire on=(counter<compare) && !reversal_blank;
 assign pwm=disabled?1'b0:(zero_brake?1'b0:on);
 assign in1=disabled?1'b1:(zero_brake?1'b1:!reverse);
 assign in2=disabled?1'b1:(zero_brake?1'b1:reverse);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin counter<=0;compare<=0;reverse<=0;reversal_blank<=0;end
  else if(!enable)begin
   // A key release cannot resume a stale compare value: one disabled
   // clock clears it. Re-enable waits for a fresh PWM boundary.
   counter<=0;compare<=0;reverse<=0;reversal_blank<=0;
  end else if(counter>=PERIOD-1)begin
   counter<=0;compare<=compare_next[15:0];
   reverse<=duty<0;
   // Change direction with drive suppressed for a full carrier period.
   // During this 50 us interval the new direction + PWM-low is brake,
   // never positive or negative supply drive.
   reversal_blank<=(limited!=0 && reverse!=(duty<0));
  end else counter<=counter+1'b1;
 end
endmodule
