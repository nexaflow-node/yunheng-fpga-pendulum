// Monitor only. Sum every committed sample; preserve the last raw snapshot.
// D6 record: base96B, theta/relative-arm/duty signed sums, count/overflow.
module c_trace_monitor(input clk,rst_n,arm,commit,freeze_in,
 input [767:0] snapshot,input signed [31:0] arm_anchor,
 output reg record_en,freeze_out,output reg [895:0] record_data);
 reg [4:0] count;
 reg signed [36:0] ts,asum,ds;
 reg [767:0] last_snapshot;
 reg closed;
 wire signed [31:0] theta=snapshot[159:128];
 wire signed [32:0] rel=$signed({snapshot[191],snapshot[191:160]})-$signed({arm_anchor[31],arm_anchor});
 wire signed [15:0] duty=snapshot[719:704];
 wire signed [36:0] tn=ts+theta,an=asum+rel,dn=ds+duty;
 wire [4:0] nn=count+1'b1;
 wire ovn=(tn[36:31]!={6{tn[31]}})||(an[36:31]!={6{an[31]}})||(dn[36:31]!={6{dn[31]}});
 wire ovo=(ts[36:31]!={6{ts[31]}})||(asum[36:31]!={6{asum[31]}})||(ds[36:31]!={6{ds[31]}});
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin count<=0;ts<=0;asum<=0;ds<=0;last_snapshot<=0;closed<=1;record_en<=0;freeze_out<=0;record_data<=0;end
  else begin
   record_en<=0;freeze_out<=0;
   if(arm)begin count<=0;ts<=0;asum<=0;ds<=0;closed<=0;last_snapshot<=0;end
   else if(!closed)begin
    if(commit)begin
     last_snapshot<=snapshot;
     if(count==15 || freeze_in)begin
      record_data<={{ovn,26'd0,nn},dn[31:0],an[31:0],tn[31:0],snapshot};
      record_en<=1;count<=0;ts<=0;asum<=0;ds<=0;
     end else begin count<=nn;ts<=tn;asum<=an;ds<=dn;end
    end else if(freeze_in && count!=0)begin
     record_data<={{ovo,26'd0,count},ds[31:0],asum[31:0],ts[31:0],last_snapshot};
     record_en<=1;count<=0;ts<=0;asum<=0;ds<=0;
    end
    if(freeze_in)begin freeze_out<=1;closed<=1;end
   end
  end
 end
endmodule
