// W0: additional near-home wall disabled. Original KQ_0 position feedback retained.
// M4F adds only a broad scalar PD filter before the existing integrators.
// M1: kinematic tracking only; AD is two independent constant-velocity
// blocks and BD is identically zero. Output reports nominal PWM voltage,
// not measured motor voltage/torque. All state/predict arithmetic is retained
// to allow bit-level comparison against the existing Q16/Q20 core.
// v5 balance core: Kalman observer correct -> rate-smoothed LQR with
// theta + position integrators -> shared output stage -> observer predict.
// Mirrors ref_v5.py (Observer.correct, Balance.step, OutputStage.step,
// Observer.predict) operation for operation, in Q16 states / Q20 matrix
// entries / Q8 gains. One invocation per valid 1 kHz sample in BALANCE.
// The observer predicts with the effective voltage reported by the output
// stage (nominal average PWM voltage, not a physical torque measurement),
// not the LQR command.
// All variable x variable 32-bit multiplies (LB/AD/BD rows) go through a
// shared c_mul32 (2-cycle DSP-friendly); constant multiplies stay
// behavioral (synthesized as shift-add). Latency ~120 cycles << 1 ms.
module c_balance_core(input clk,rst_n,
 input sample_en,              // pulse: process this sample
 input soft_reset,             // pulse: invalid sample -- reset integrators
 input init_en,                // pulse: capture -- full observer init
 input signed [31:0] init_a,init_va,init_th,init_vth,
 input signed [31:0] th,a,vth_w,va_w,alpha_ref,
 input motor_active,
 output reg done, overrun,
 output wire signed [15:0] duty,
 output wire signed [31:0] xhat0,xhat1,xhat2,xhat3,  // prior state (tb)
 output wire signed [31:0] u_dbg, veff_dbg,
 output wire [447:0] trace_data);
 wire [31:0] trace_output; wire trace_clip,trace_rate;
 wire [15:0] trace_flags={3'b0,f_clip,5'b0,ma_r,trace_rate,trace_clip,(v_sel!=u_r),reinit,frozen_r,inside_r};
 wire signed [31:0] trace_theta_i=v_sel-pd;
 assign trace_data={trace_output,trace_flags,out_duty,veff_r,u_r,v_sel,
                    trace_theta_i,t_pos,t_up,pd1,a_err,xc3,xc2,xc1,xc0};
`include "v5_params.vh"
`include "feedback_shape.vh"
 localparam signed [31:0] LIN_MAX=P_CMD_MAX;
 reg signed [31:0] x0,x1,x2,x3;            // observer prior, Q16
 reg signed [31:0] xc0,xc1,xc2,xc3;        // corrected states
 reg signed [31:0] err_a,err_t;
 reg [3:0] err_streak;
 reg reinit;
 reg signed [31:0] th_m,a_m,vw,vaw,ref_m;
 reg ma_r, inside_r;
 reg signed [63:0] lbp_a,lbp_b,lsum;
 reg signed [63:0] pd_acc, uprod, pprod;
 reg signed [31:0] a_err, pd, pd1, t_up, pd2, t_pos;
 // Soft wall around the reference: outside +/-10 deg the position
 // authority grows gently (0 V at 10 deg, ~0.35 V at 20 deg, ~0.7 V at 30 deg),
 // inside the wall the original feedback is unchanged.
 localparam signed [31:0] RANGE_R = 32'sd11438;      // 10 deg

 wire signed [31:0] range_abs = (a_err<0)?-a_err:a_err;
 wire signed [31:0] range_ex  = (range_abs>RANGE_R)?(range_abs-RANGE_R):32'sd0;
 // The wall is a NEAR-HOME aid only: enable it when the reference has
// reached the origin (|ref|<3 deg). During the return the wall is off,
// so the homing transient keeps the proven wall270 behaviour.
wire wall_en = 1'b0; // W0 single-variable diagnostic: remove extra wall only
wire signed [31:0] range_mag = wall_en ? (range_ex<<9) : 32'sd0; // 2 V/rad beyond the wall
 wire signed [63:0] range_term = (a_err<0)?-$signed({{32{range_mag[31]}},range_mag}):$signed({{32{range_mag[31]}},range_mag});
 reg signed [31:0] integral, cand, old_i, pos_i;
 reg frozen_r, sign_c, sign_o;
 reg [25:0] mag_c, mag_o;
 reg signed [63:0] prod_c, prod_o;
 reg [16:0] q_c, q_o;
 reg [26:0] qt_c, qt_o;
 reg signed [31:0] i_v_cand, i_v_old, v_cand, v_sel;
 reg signed [31:0] u_r, veff_r;
 reg signed [63:0] pr_acc;
 // Five products share the existing multiplier. Q16 histories, Q28
 // coefficients and signed64 accumulator; carry output fraction to prevent
 // a DC offset from repeated truncation. Reset on init/invalid sample.
 reg signed [31:0] f_x1,f_x2,f_y1,f_y2,f_y;
 reg signed [63:0] f_acc;
 reg [27:0] f_fraction;
 reg f_clip;
 wire signed [63:0] f_y64={{32{f_y[31]}},f_y};
 reg [6:0] step;
 reg out_go;
 reg mul_go;
 reg signed [31:0] mul_a, mul_b;
 wire mul_done; wire signed [63:0] mul_p;
 c_mul32 mul(.clk(clk),.rst_n(rst_n),.start(mul_go),.a(mul_a),.b(mul_b),
  .p(mul_p),.done(mul_done));
 wire out_done; wire signed [15:0] out_duty; wire signed [31:0] out_veff;
 assign duty=out_duty;
 assign xhat0=x0; assign xhat1=x1; assign xhat2=x2; assign xhat3=x3;
 assign u_dbg=u_r; assign veff_dbg=veff_r;
 c_output #(.RATE_LIMIT(P_BAL_RATE_LIMIT)) u_out(.clk(clk),.rst_n(rst_n),.go(out_go),.enable(ma_r),
   .clear(init_en||soft_reset),.u(u_r),.done(out_done),.duty(out_duty),.veff(out_veff),
   .trace_stage(trace_output),.trace_clip(trace_clip),.trace_rate(trace_rate));
 wire signed [31:0] t0=x0+(lsum>>>20);
 wire signed [31:0] t1=x1+(lsum>>>20);
 wire signed [31:0] t2=x2+(lsum>>>20);
 wire signed [31:0] t3=x3+(lsum>>>20);
 // Exact shift-add forms of the constant multiplies that would otherwise
 // claim DSPs (all 20 are spent). Bit-identical to the "*C" forms:
 //   4294968 = 2^22+2^17-2^15+2^11+2^8+2^6-2^3  (mag<=65536000 -> 49-bit)
 //   1000    = 2^10-2^4-2^3                     (q<=65536     -> 27-bit)
 wire signed [51:0] mgc52 = $signed({26'b0,mag_c});
 wire signed [51:0] prod_c_w = (mgc52<<<22)+(mgc52<<<17)-(mgc52<<<15)+(mgc52<<<11)
                              +(mgc52<<<8)+(mgc52<<<6)-(mgc52<<<3);
 wire signed [51:0] mgo52 = $signed({26'b0,mag_o});
 wire signed [51:0] prod_o_w = (mgo52<<<22)+(mgo52<<<17)-(mgo52<<<15)+(mgo52<<<11)
                              +(mgo52<<<8)+(mgo52<<<6)-(mgo52<<<3);
 wire [26:0] qc_e = {10'b0,q_c};
 wire [26:0] qt_c_w = (qc_e<<10)-(qc_e<<4)-(qc_e<<3);
 wire [26:0] qo_e = {10'b0,q_o};
 wire [26:0] qt_o_w = (qo_e<<10)-(qo_e<<4)-(qo_e<<3);
 // q_o is corrected one cycle before the old integral is converted back to
 // voltage.  Use the corrected value explicitly: a nonblocking assignment
 // to q_o and a read of q_o in the same clock edge otherwise leaves the
 // anti-windup path one reciprocal count high whenever the remainder is
 // nonzero.
 wire [16:0] q_o_corr = (qt_o>mag_o && q_o!=0) ? (q_o-1'b1) : q_o;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   step<=0;done<=0;overrun<=0;
   x0<=0;x1<=0;x2<=0;x3<=0;xc0<=0;xc1<=0;xc2<=0;xc3<=0;
   err_a<=0;err_t<=0;err_streak<=0;reinit<=0;
   th_m<=0;a_m<=0;vw<=0;vaw<=0;ref_m<=0;ma_r<=1;inside_r<=0;
   lbp_a<=0;lbp_b<=0;lsum<=0;
   pd_acc<=0;uprod<=0;pprod<=0;a_err<=0;pd<=0;pd1<=0;t_up<=0;pd2<=0;t_pos<=0;
   integral<=0;cand<=0;old_i<=0;pos_i<=0;frozen_r<=0;
   sign_c<=0;sign_o<=0;mag_c<=0;mag_o<=0;prod_c<=0;prod_o<=0;q_c<=0;q_o<=0;
   qt_c<=0;qt_o<=0;i_v_cand<=0;i_v_old<=0;v_cand<=0;v_sel<=0;
   u_r<=0;veff_r<=0;pr_acc<=0;out_go<=0;mul_go<=0;
   mul_a<=0;mul_b<=0;
   f_x1<=0;f_x2<=0;f_y1<=0;f_y2<=0;f_y<=0;f_acc<=0;f_fraction<=0;f_clip<=0;
  end else begin
   done<=0; out_go<=0; mul_go<=0;
   if(init_en) begin
    // capture: full observer init + integrator/output-stage reset
    x0<=(init_a>32'sd900000)?32'sd900000:((init_a<-32'sd900000)?-32'sd900000:init_a);
    x1<=(init_va>P_VEL_CLIP)?P_VEL_CLIP:((init_va<-P_VEL_CLIP)?-P_VEL_CLIP:init_va);
    x2<=(init_th>32'sd1200000)?32'sd1200000:((init_th<-32'sd1200000)?-32'sd1200000:init_th);
    x3<=(init_vth>P_VEL_CLIP)?P_VEL_CLIP:((init_vth<-P_VEL_CLIP)?-P_VEL_CLIP:init_vth);
    integral<=0;pos_i<=0;u_r<=0;veff_r<=0;err_streak<=0;step<=0;
    f_x1<=0;f_x2<=0;f_y1<=0;f_y2<=0;f_y<=0;f_acc<=0;f_fraction<=0;f_clip<=0;
   end else if(soft_reset) begin
    // invalid sample: integrators and output stage reset, observer holds
    integral<=0;pos_i<=0;u_r<=0;veff_r<=0;step<=0;
    f_x1<=0;f_x2<=0;f_y1<=0;f_y2<=0;f_y<=0;f_acc<=0;f_fraction<=0;f_clip<=0;
   end else if(sample_en && step!=0) begin
    overrun<=1;step<=0;
   end else begin
    case(step)
     // ---------- phase A: observer correction ----------
     0: if(sample_en) begin
      th_m<=th;a_m<=a;vw<=vth_w;vaw<=va_w;ref_m<=alpha_ref;ma_r<=motor_active;
      err_a<=a-x0; err_t<=th-x2;
      inside_r<=((th<=P_I_WINDOW)&&(th>=-P_I_WINDOW));
      step<=1;
     end
     1: begin
      if((err_t>0?err_t:-err_t)>P_OBS_ERR_RESET) begin
       if(err_streak<4'd15) err_streak<=err_streak+1;
       reinit<=((err_streak+1)>=P_OBS_ERR_MS);
      end else begin
       err_streak<=0; reinit<=0;
      end
      step<=2;
     end
     2: begin
      if(reinit) begin
       // re-init from measurements + window velocities, zero innovation
       x0<=(a_m>32'sd900000)?32'sd900000:((a_m<-32'sd900000)?-32'sd900000:a_m);
       x1<=(vaw>P_VEL_CLIP)?P_VEL_CLIP:((vaw<-P_VEL_CLIP)?-P_VEL_CLIP:vaw);
       x2<=(th_m>32'sd1200000)?32'sd1200000:((th_m<-32'sd1200000)?-32'sd1200000:th_m);
       x3<=(vw>P_VEL_CLIP)?P_VEL_CLIP:((vw<-P_VEL_CLIP)?-P_VEL_CLIP:vw);
       xc0<=(a_m>32'sd900000)?32'sd900000:((a_m<-32'sd900000)?-32'sd900000:a_m);
       xc1<=(vaw>P_VEL_CLIP)?P_VEL_CLIP:((vaw<-P_VEL_CLIP)?-P_VEL_CLIP:vaw);
       xc2<=(th_m>32'sd1200000)?32'sd1200000:((th_m<-32'sd1200000)?-32'sd1200000:th_m);
       xc3<=(vw>P_VEL_CLIP)?P_VEL_CLIP:((vw<-P_VEL_CLIP)?-P_VEL_CLIP:vw);
       err_a<=0;err_t<=0;err_streak<=0;
       step<=14;
      end else begin
       mul_a<=LB_00; mul_b<=err_a; mul_go<=1; step<=3;
      end
     end
     3: if(mul_done) begin lbp_a<=mul_p; mul_a<=LB_01; mul_b<=err_t; mul_go<=1; step<=4; end
     4: if(mul_done) begin lbp_b<=mul_p; step<=5; end
     5: begin lsum<=lbp_a+lbp_b; step<=6; end
     6: begin
      xc0<=(t0>32'sd900000)?32'sd900000:((t0<-32'sd900000)?-32'sd900000:t0);
      mul_a<=LB_10; mul_b<=err_a; mul_go<=1; step<=7;
     end
     7: if(mul_done) begin lbp_a<=mul_p; mul_a<=LB_11; mul_b<=err_t; mul_go<=1; step<=8; end
     8: if(mul_done) begin lbp_b<=mul_p; step<=9; end
     9: begin lsum<=lbp_a+lbp_b; step<=10; end
     10: begin
      xc1<=(t1>P_VEL_CLIP)?P_VEL_CLIP:((t1<-P_VEL_CLIP)?-P_VEL_CLIP:t1);
      mul_a<=LB_20; mul_b<=err_a; mul_go<=1; step<=11;
     end
     11: if(mul_done) begin lbp_a<=mul_p; mul_a<=LB_21; mul_b<=err_t; mul_go<=1; step<=12; end
     12: if(mul_done) begin lbp_b<=mul_p; step<=13; end
     13: begin lsum<=lbp_a+lbp_b; step<=15; end
     15: begin
      xc2<=(t2>32'sd1200000)?32'sd1200000:((t2<-32'sd1200000)?-32'sd1200000:t2);
      mul_a<=LB_30; mul_b<=err_a; mul_go<=1; step<=16;
     end
     16: if(mul_done) begin lbp_a<=mul_p; mul_a<=LB_31; mul_b<=err_t; mul_go<=1; step<=17; end
     17: if(mul_done) begin lbp_b<=mul_p; step<=18; end
     18: begin lsum<=lbp_a+lbp_b; step<=19; end
     19: begin
      xc3<=(t3>P_VEL_CLIP)?P_VEL_CLIP:((t3<-P_VEL_CLIP)?-P_VEL_CLIP:t3);
      step<=14;
     end
     // ---------- phase B: LQR + integrators ----------
     14: begin a_err<=xc0-ref_m; step<=20; end
     20: begin
      if(inside_r) begin
       pos_i<=((pos_i+a_err)>P_POS_I_LIMIT)?P_POS_I_LIMIT:
              ((pos_i+a_err)<-P_POS_I_LIMIT)?-P_POS_I_LIMIT:(pos_i+a_err);
      end
      pd_acc<=range_term;
      step<=21;
     end
     21: begin pd_acc<=pd_acc+KQ_0*a_err; step<=22; end
     22: begin pd_acc<=pd_acc+KQ_1*xc1; step<=23; end
     23: begin pd_acc<=pd_acc+KQ_2*xc2; step<=24; end
     24: begin pd_acc<=pd_acc+KQ_3*xc3; uprod<=KU_PREV*u_r; pprod<=pos_i*P_POS_I_K; step<=25; end
     25: begin
      pd1<=pd_acc>>>8;
      t_up<=uprod>>>10;
      step<=26;
     end
     26: begin
      t_pos<=pprod>>>16;
      mul_a<=F_B0;mul_b<=pd1;mul_go<=1;step<=71;
     end
     71: if(mul_done) begin
      f_acc<=mul_p+$signed({36'b0,f_fraction});
      mul_a<=F_B1;mul_b<=f_x1;mul_go<=1;step<=72;
     end
     72: if(mul_done) begin f_acc<=f_acc+mul_p;mul_a<=F_B2;mul_b<=f_x2;mul_go<=1;step<=73;end
     73: if(mul_done) begin f_acc<=f_acc+mul_p;mul_a<=F_A1;mul_b<=f_y1;mul_go<=1;step<=74;end
     74: if(mul_done) begin f_acc<=f_acc-mul_p;mul_a<=F_A2;mul_b<=f_y2;mul_go<=1;step<=75;end
     75: if(mul_done) begin f_acc<=f_acc-mul_p;step<=76;end
     76: begin
      f_y<=(f_acc>>>28>64'sd134217728)?32'sd134217728:
           ((f_acc>>>28<-64'sd134217728)?-32'sd134217728:f_acc>>>28);
      f_clip<=((f_acc>>>28>64'sd134217728)||(f_acc>>>28<-64'sd134217728));
      step<=77;
     end
     77: begin
      pd2<=f_y;t_up<=f_y-pd1;
      f_x2<=f_x1;f_x1<=pd1;f_y2<=f_y1;f_y1<=f_y;
      f_fraction<=f_clip?28'd0:(f_acc-(f_y64<<<28));
      step<=27;
     end
     27: begin pd<=pd2+t_pos; step<=28; end
     // ---------- phase C: theta integral + anti-windup freeze ----------
     28: begin
      if(inside_r)
        cand<=((integral+th_m)>P_I_LIMIT)?P_I_LIMIT:
              ((integral+th_m)<-P_I_LIMIT)?-P_I_LIMIT:(integral+th_m);
      else
        cand<=0;
      old_i<=inside_r?integral:0;
      step<=29;
     end
     29: begin sign_c<=(cand<0); mag_c<=(cand<0)?(-cand):cand; step<=30; end
     30: begin prod_c<=prod_c_w; step<=31; end
     31: begin q_c<=prod_c[48:32]; step<=32; end
     32: begin qt_c<=qt_c_w; step<=33; end
     33: begin if(qt_c>mag_c) q_c<=q_c-1; step<=34; end
     34: begin i_v_cand<=sign_c?-q_c:q_c; step<=35; end
     35: begin v_cand<=pd+i_v_cand; step<=36; end
     36: begin
      frozen_r<=((v_cand>LIN_MAX)&&(th_m>0))||((v_cand<-LIN_MAX)&&(th_m<0));
      step<=37;
     end
     37: begin
      if(!frozen_r) begin
       integral<=cand; v_sel<=v_cand; step<=42;
      end else begin
       sign_o<=(old_i<0); mag_o<=(old_i<0)?(-old_i):old_i; step<=38;
      end
     end
     38: begin prod_o<=prod_o_w; step<=39; end
     39: begin q_o<=prod_o[48:32]; step<=40; end
     40: begin qt_o<=qt_o_w; step<=41; end
     41: begin
      if(qt_o>mag_o && q_o!=0) q_o<=q_o-1;
      i_v_old<=sign_o ? -$signed(q_o_corr) : $signed(q_o_corr);
      integral<=old_i;
      step<=42;
     end
     42: begin
      if(frozen_r) v_sel<=pd+i_v_old;
      step<=43;
     end
     // ---------- phase D: command + shared output stage ----------
     43: begin
      u_r<=(v_sel>P_CMD_MAX)?P_CMD_MAX:((v_sel<-P_CMD_MAX)?-P_CMD_MAX:v_sel);
      step<=44;
     end
     44: begin out_go<=1; step<=45; end
     45: if(out_done) begin
      veff_r<=out_veff;
      step<=46;
     end
     // ---------- phase E: observer prediction (mul32 chain) ----------
     46: begin mul_a<=AD_00; mul_b<=xc0; mul_go<=1; step<=47; end
     47: if(mul_done) begin pr_acc<=mul_p; mul_a<=AD_01; mul_b<=xc1; mul_go<=1; step<=48; end
     48: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=AD_02; mul_b<=xc2; mul_go<=1; step<=49; end
     49: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=AD_03; mul_b<=xc3; mul_go<=1; step<=50; end
     50: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=BD_0; mul_b<=veff_r; mul_go<=1; step<=51; end
     51: if(mul_done) begin pr_acc<=pr_acc+mul_p; step<=52; end
     52: begin x0<=(pr_acc>>>20>32'sd900000)?32'sd900000:
                ((pr_acc>>>20<-32'sd900000)?-32'sd900000:pr_acc>>>20);
      mul_a<=AD_10; mul_b<=xc0; mul_go<=1; step<=53; end
     53: if(mul_done) begin pr_acc<=mul_p; mul_a<=AD_11; mul_b<=xc1; mul_go<=1; step<=54; end
     54: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=AD_12; mul_b<=xc2; mul_go<=1; step<=55; end
     55: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=AD_13; mul_b<=xc3; mul_go<=1; step<=56; end
     56: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=BD_1; mul_b<=veff_r; mul_go<=1; step<=57; end
     57: if(mul_done) begin pr_acc<=pr_acc+mul_p; step<=58; end
     58: begin x1<=(pr_acc>>>20>P_VEL_CLIP)?P_VEL_CLIP:
                ((pr_acc>>>20<-P_VEL_CLIP)?-P_VEL_CLIP:pr_acc>>>20);
      mul_a<=AD_20; mul_b<=xc0; mul_go<=1; step<=59; end
     59: if(mul_done) begin pr_acc<=mul_p; mul_a<=AD_21; mul_b<=xc1; mul_go<=1; step<=60; end
     60: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=AD_22; mul_b<=xc2; mul_go<=1; step<=61; end
     61: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=AD_23; mul_b<=xc3; mul_go<=1; step<=62; end
     62: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=BD_2; mul_b<=veff_r; mul_go<=1; step<=63; end
     63: if(mul_done) begin pr_acc<=pr_acc+mul_p; step<=64; end
     64: begin x2<=(pr_acc>>>20>32'sd1200000)?32'sd1200000:
                ((pr_acc>>>20<-32'sd1200000)?-32'sd1200000:pr_acc>>>20);
      mul_a<=AD_30; mul_b<=xc0; mul_go<=1; step<=65; end
     65: if(mul_done) begin pr_acc<=mul_p; mul_a<=AD_31; mul_b<=xc1; mul_go<=1; step<=66; end
     66: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=AD_32; mul_b<=xc2; mul_go<=1; step<=67; end
     67: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=AD_33; mul_b<=xc3; mul_go<=1; step<=68; end
     68: if(mul_done) begin pr_acc<=pr_acc+mul_p; mul_a<=BD_3; mul_b<=veff_r; mul_go<=1; step<=69; end
     69: if(mul_done) begin pr_acc<=pr_acc+mul_p; step<=70; end
     70: begin x3<=(pr_acc>>>20>P_VEL_CLIP)?P_VEL_CLIP:
                ((pr_acc>>>20<-P_VEL_CLIP)?-P_VEL_CLIP:pr_acc>>>20);
      done<=1; step<=0;
     end
     default: step<=0;
    endcase
   end
  end
 end
endmodule
