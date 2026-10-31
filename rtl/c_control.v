// Integrated HOME variant: automatic swing-up + M4FH30 balance core that
// returns the arm to the INITIAL position captured at swing-up start.
//
// Entry (SW3 long-hold then release):
//   - pendulum within +/-10 deg and slow  -> immediate manual takeover,
//     byte-for-byte the M4FH30 acceptance path (capture_count==2) and its
//     anchor = current arm.
//   - pendulum hanging (|theta| > 2.5 rad) -> SWING: the proven v6 energy
//     pump (8% margin) drives through its own output stage (COMP_D=200,
//     cap 1000, slew 100/ms) with the 120 deg arm soft limit relative to
//     the attempt anchor.
//   - anything else -> fault 5 (bad start posture).
//
// Capture: |theta| < 20 deg, |theta_dot| < 3.0 rad/s on both filtered and
// window velocities, three consecutive samples. The capture arm condition is
// relative to the swing anchor, so the two physical half-turns use the same
// window. On capture the arm anchor is RE-LATCHED to the current arm, the
// M4FH30 core gets a full observer/integrator reset, both output stages
// are cleared, and the run epoch starts -> the D6 trace contains exactly
// the balance run, so its metrics stay comparable with M4FH30.
//
// Balance: the first upright episode is retained for diagnosis. A fall past
// 60 deg faults 6; there is no hidden recapture branch in this build.
//
// Trace/frame semantics are unchanged from M4FH30 (commit per bal_done,
// run_begin at capture, freeze on abort).
module c_control #(parameter MAX_RUN_MS=30000, ARM_LIMIT=68629,
 FALL_ANGLE=68634, WATCHDOG_MS=3)
 (input clk,rst_n,tick_ms,sample_ready,valid,mature,start,stop,calibrated,key_inc,key_dec,
  input motor_active,external_fault,
  input signed [31:0] th,vth_w,vth_f,a,va_w,va_f,
  output reg [1:0] state,output reg [3:0] fault_code,
  output reg signed [15:0] duty,output wire active,
  output reg run_begin,freeze,commit,
  output wire [447:0] trace_data,output reg signed [31:0] arm_anchor,
  output wire signed [31:0] swing_u);
`include "v5_params.vh"
 localparam IDLE=2'd0,SWING=2'd1,BALANCE=2'd2,FAULT=2'd3;
 localparam signed [31:0] ARM_HARD=32'sd823548;   // +/-2 turns absolute
 localparam signed [31:0] SWING_ARM_MAX=32'sd171572; // 150 deg rel: swing stroke hard bound
 localparam signed [31:0] CAP_VA_LIM  =32'sd163840;  // 2.5 rad/s arm speed at capture
 localparam signed [31:0] REANCHOR_MAX = 32'sd5727;  // +/-5 deg target correction
 localparam signed [31:0] REANCHOR_SLEW = 32'sd3;     // ~2.6 deg/s per ms
 localparam signed [31:0] CAP_THETA_GOOD = 32'sd13795;  // 12 deg
 localparam signed [31:0] CAP_THETA_FAST = 32'sd18350;  // 16 deg
 localparam signed [31:0] CAP_VTH_MIN = 32'sd98304;     // 1.5 rad/s
 reg init_pulse,soft_rst,bal_go,start_pending,sw_go,sw_out_go;
 reg [2:0] bal_dly;
 reg [15:0] run_ms,swing_total_ms,balance_ms;
 reg [7:0] missing_ms,pending_ms,bad_ms;
 reg [1:0] capture_count;
 reg signed [31:0] ref_cur;            // slewed balance reference
 reg signed [31:0] pos_rel;          // position-mode target offset (+/-30 deg)
 reg signed [31:0] q_min,q_max;      // arm extremes in the 5-8 s settle window
 reg q_armed,reanchor_pending;
 // relative target: capture arm + offset. The arm never has to travel to an
 // absolute 0, so the far-capture / 60 deg arm-limit failure mode is avoided.
 wire signed [31:0] pos_target = arm_anchor + pos_rel;
 // DIAG event recorder: after 3 s of balance, an arm-speed excursion above
 // 4 rad/s arms a 750 ms timer; when it expires the trace is frozen WITHOUT
 // changing state or duty. The control law is untouched.
 reg evt_armed,evt_wait; reg [15:0] evt_ms;
 wire bal_done,bal_over,sw_done,sw_over,sw_out_done;
 wire signed [15:0] bal_duty,sw_duty;
 wire signed [31:0] sw_u_i;
 assign swing_u=sw_u_i;
 assign active=(state==SWING)||(state==BALANCE);
 // Balance motion is bounded to +/-2 turns (ARM_HARD), so a signed 22-bit
 // Q16 angle is sufficient. Keeping this subtraction narrow avoids carrying
 // an unnecessary 33-bit adder through the control timing path.
 wire signed [21:0] a_q22=$signed(a[21:0]);
 wire signed [21:0] ref_q22=$signed(ref_cur[21:0]);
 wire signed [22:0] rel_ref=$signed({a_q22[21],a_q22})-
                            $signed({ref_q22[21],ref_q22});
 wire unsafe_arm=(rel_ref>$signed(ARM_LIMIT))||(rel_ref<-$signed(ARM_LIMIT));
 // During the one-shot re-anchor, allow the small bounded correction to move
 // even when the arm is still outside the ordinary position-mode gate.
 wire reanchor_safe=(th<32'sd11438)&&(th>-32'sd11438);
 wire abs_arm_hi=(a>ARM_HARD)||(a<-ARM_HARD);
 wire fall=(th>FALL_ANGLE)||(th<-FALL_ANGLE);
 wire swing_abs_arm=(a>ARM_HARD)||(a<-ARM_HARD);
 wire manual_ok=(th<=32'sd11438)&&(th>=-32'sd11438)
   &&(vth_w<=32'sd65536)&&(vth_w>=-32'sd65536)
   &&(vth_f<=32'sd65536)&&(vth_f>=-32'sd65536)
   &&(va_w<=32'sd32768)&&(va_w>=-32'sd32768)
   &&(va_f<=32'sd32768)&&(va_f>=-32'sd32768);
 wire hanging=(th>32'sd163840)||(th<-32'sd163840);
 wire signed [21:0] anchor_q22=$signed(arm_anchor[21:0]);
 wire signed [22:0] swing_rel=$signed({a_q22[21],a_q22})-
                               $signed({anchor_q22[21],anchor_q22});
 wire cap_arm_ok=(swing_rel<$signed(SWING_ARM_MAX)) &&
                 (swing_rel>-$signed(SWING_ARM_MAX));
 wire signed [31:0] th_abs=(th<0)?-th:th;
 wire th_toward=((th>0)&&(vth_f<0))||((th<0)&&(vth_f>0));
 wire cap_theta_ok=(th_abs<CAP_THETA_GOOD)||
                   ((th_abs<CAP_THETA_FAST)&&th_toward&&
                    (vth_f>CAP_VTH_MIN || vth_f<-CAP_VTH_MIN));
 wire capture_cond=(th_abs<P_CAP_ANGLE)&&cap_theta_ok&&cap_arm_ok
   &&(vth_f<P_CAP_SPEED)&&(vth_f>-P_CAP_SPEED)
   &&(vth_w<P_CAP_SPEED)&&(vth_w>-P_CAP_SPEED)
   &&(va_w<CAP_VA_LIM)&&(va_w>-CAP_VA_LIM);
 wire capture_ok=capture_cond;
 wire swing_arm_hi=(swing_rel>SWING_ARM_MAX)||(swing_rel<-SWING_ARM_MAX);
 c_balance_core core(.clk(clk),.rst_n(rst_n),.sample_en(bal_go),
  .soft_reset(soft_rst),.init_en(init_pulse),.init_a(a),.init_va(va_w),
  .init_th(th),.init_vth(vth_f),.th(th),.a(a),.vth_w(vth_w),.va_w(va_w),
  .alpha_ref(ref_cur),.motor_active(motor_active),.done(bal_done),
  .overrun(bal_over),.duty(bal_duty),.xhat0(),.xhat1(),.xhat2(),.xhat3(),
  .u_dbg(),.veff_dbg(),.trace_data(trace_data));
 c_swing pump(.clk(clk),.rst_n(rst_n),.sample_en(sw_go),
  .enable(state==SWING && valid && motor_active),
  .th(th),.vth_f(vth_f),.a($signed(a)-$signed(arm_anchor)),.va_f(va_f),
  .u(sw_u_i),.done(sw_done),.overrun(sw_over));
 // Swing output stage reproduces the v6 chain (2.4 V deadband inverse, full
 // duty, 100/ms slew); the balance stage inside the core keeps its own
 // COMP_D=0 / 500 / 60 settings untouched.
 c_output #(.RATE_LIMIT(100),.COMP_D(200),.DUTY_CAP(1000)) sw_out(
  .clk(clk),.rst_n(rst_n),.go(sw_out_go),.enable(motor_active),
  .clear(init_pulse||soft_rst||(state!=SWING)),
  .u(sw_u_i),.done(sw_out_done),.duty(sw_duty),.veff(),
  .trace_stage(),.trace_clip(),.trace_rate());
 // ---- bounded stall release (balance only, merged from 4A575056) ----
 // Measured breakaway under load is ~170-223 permille; the no-integral LQR
 // can sit at ~90 and never move. When the encoder has not changed for
 // 150 ms and |a-ref|>4 deg (pendulum within 15 deg), ramp a feedforward
 // toward the reference at 200 permille/s (cap 300) and drop it on motion.
 localparam signed [31:0] REL_ERR_ON  = 32'sd4576;
 localparam signed [31:0] REL_ERR_OFF = 32'sd1716;
 localparam signed [31:0] REL_STEP    = 32'sd300;
 localparam [15:0] REL_HOLD_MS = 16'd150;
 reg signed [31:0] a_hold;
 reg [15:0] hold_ms;
 reg [3:0] rel_div;
 reg signed [15:0] rel_mag,rel_term;
 wire a_moved=(a>a_hold+REL_STEP)||(a<a_hold-REL_STEP);
 wire rel_upright=(th<32'sd17153)&&(th>-32'sd17153);
 wire want_release=rel_upright&&((rel_ref>REL_ERR_ON)||(rel_ref<-REL_ERR_ON));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   a_hold<=0;hold_ms<=0;rel_div<=0;rel_mag<=0;rel_term<=0;
  end else if(state!=BALANCE) begin
   a_hold<=a;hold_ms<=0;rel_div<=0;rel_mag<=0;rel_term<=0;
  end else if(tick_ms) begin
   if(a_moved) begin
    a_hold<=a;hold_ms<=0;rel_div<=0;rel_mag<=0;rel_term<=0;
   end else begin
    if(hold_ms<16'hFFFF) hold_ms<=hold_ms+1'b1;
    if((rel_ref<REL_ERR_OFF)&&(rel_ref>-REL_ERR_OFF)) begin
     hold_ms<=0;rel_div<=0;rel_mag<=0;rel_term<=0;
    end else if(want_release && hold_ms>=REL_HOLD_MS) begin
     if(rel_div==4'd4) begin
      rel_div<=0;
      if(rel_mag<16'sd300) rel_mag<=rel_mag+1'b1;
     end else rel_div<=rel_div+1'b1;
     rel_term<=(rel_ref>0)?-rel_mag:rel_mag;
    end else begin
     rel_div<=0;
     if(rel_mag>0) rel_mag<=rel_mag-1'b1;
     rel_term<=0;
    end
   end
  end
 end
 wire signed [16:0] bal_cmd=$signed(bal_duty)+$signed(rel_term);
 task abort_run;
 input [3:0] reason;
 begin
  state<=FAULT;fault_code<=reason;duty<=0;soft_rst<=1;
  evt_armed<=0;evt_wait<=0;evt_ms<=0;
  init_pulse<=0;bal_go<=0;bal_dly<=0;start_pending<=0;sw_go<=0;sw_out_go<=0;
  freeze<=1;commit<=0;
 end
 endtask
 task enter_balance;
 begin
  arm_anchor<=a;ref_cur<=a;pos_rel<=0;q_min<=a;q_max<=a;q_armed<=0;reanchor_pending<=0;state<=BALANCE;fault_code<=0;run_ms<=0;missing_ms<=0;
  evt_armed<=0;evt_wait<=0;evt_ms<=0;
  balance_ms<=0;duty<=0;init_pulse<=1;soft_rst<=1;bal_dly<=0;
  start_pending<=0;capture_count<=0;run_begin<=1;
 end
 endtask
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;fault_code<=0;duty<=0;arm_anchor<=0;
   evt_armed<=0;evt_wait<=0;evt_ms<=0;
   init_pulse<=0;soft_rst<=0;bal_go<=0;bal_dly<=0;
   start_pending<=0;pending_ms<=0;capture_count<=0;
   run_ms<=0;missing_ms<=0;run_begin<=0;freeze<=0;commit<=0;
   sw_go<=0;sw_out_go<=0;swing_total_ms<=0;balance_ms<=0;bad_ms<=0;
   ref_cur<=0;pos_rel<=0;q_min<=0;q_max<=0;q_armed<=0;reanchor_pending<=0;
  end else begin
   run_begin<=0;freeze<=0;commit<=0;
   init_pulse<=0;soft_rst<=0;bal_go<=0;sw_go<=0;sw_out_go<=0;
   case(state)
    IDLE: begin
     duty<=0;
     if(start && !start_pending) begin start_pending<=1;pending_ms<=0;capture_count<=0;end
     if(start_pending) begin
      if(stop) abort_run(4'd1);
      else if(external_fault) abort_run(4'd9);
      else if(tick_ms && pending_ms>=9) abort_run(4'd5);
      else begin
       if(tick_ms) pending_ms<=pending_ms+1'b1;
       if(sample_ready) begin
        if(!valid || !mature || !calibrated) abort_run(4'd5);
        else if(manual_ok) begin
         if(capture_count==2) enter_balance;
         else capture_count<=capture_count+1'b1;
        end else if(hanging) begin
         state<=SWING;swing_total_ms<=0;balance_ms<=0;missing_ms<=0;bad_ms<=0;
         capture_count<=0;arm_anchor<=a;run_ms<=0;
        end else abort_run(4'd5);
       end
      end
     end
    end
    SWING: begin
     if(stop) abort_run(4'd1);
     else if(external_fault) abort_run(4'd9);
     else if(swing_abs_arm) abort_run(4'd2);
     else if(swing_arm_hi) abort_run(4'd2);
     else if(sw_over) abort_run(4'd8);
     else if(tick_ms && !sample_ready && missing_ms>=WATCHDOG_MS-1) abort_run(4'd3);
     else if(tick_ms && swing_total_ms>=P_SWING_PATIENCE_MS) abort_run(4'd4);
     else begin
      if(tick_ms) begin
       if(missing_ms<8'hFF) missing_ms<=missing_ms+1'b1;
       if(swing_total_ms<16'hFFFF) swing_total_ms<=swing_total_ms+1'b1;
      end
      if(sample_ready) begin
       missing_ms<=0;
       if(!valid) begin
        // Short dropouts are tolerated during swing (the pump state holds);
        // 20 consecutive bad samples (~20 ms) abort.
        // The potentiometer dead zone (theta ~= +-90 deg) yields invalid
        // samples for tens of ms while the pendulum crosses it at speed.
        // Hold duty=0 and resume the pump afterwards; only a 255 ms
        // continuous dropout is treated as a sensor failure.
        if(bad_ms>=8'd255) abort_run(4'd3);
        else begin bad_ms<=bad_ms+1'b1;duty<=0;end
       end else begin
        bad_ms<=0;
        if(capture_ok) begin
         if(capture_count==2) enter_balance;
         else begin capture_count<=capture_count+1'b1;duty<=0;end
        end else begin capture_count<=0;sw_go<=1;end
       end
      end
      if(sw_done) sw_out_go<=1;
      if(sw_out_done) duty<=(sw_duty>16'sd1000)?16'sd1000:
                            ((sw_duty<-16'sd1000)?-16'sd1000:sw_duty);
     end
    end
    BALANCE: begin
     if(stop) abort_run(4'd1);
     else if(external_fault) abort_run(4'd9);
     else if(unsafe_arm||abs_arm_hi) abort_run(4'd2);
     else if(bal_over) abort_run(4'd8);
     else if(sample_ready && (!valid || !mature || !calibrated)) abort_run(4'd3);
     else if(sample_ready && fall) abort_run(4'd6); // ZP1 retain FIRST upright episode; no recapture
     else if(tick_ms && run_ms>=MAX_RUN_MS-1) abort_run(4'd7);
     else if(tick_ms && !sample_ready && missing_ms>=WATCHDOG_MS-1) abort_run(4'd3);
     else begin
      // The key outputs are single-clock pulses; they must be sampled every
      // clock, not inside sample_ready, or presses are silently dropped.
      if(key_inc) pos_rel<=(pos_rel==32'sd17157)?32'sd0:32'sd17157;
      if(key_dec) pos_rel<=(pos_rel==-32'sd17157)?32'sd0:-32'sd17157;
      if(tick_ms) begin
       run_ms<=run_ms+1'b1;
       missing_ms<=missing_ms+1'b1;
       if(balance_ms<16'hFFFF) balance_ms<=balance_ms+1'b1;
       // One-shot re-anchor: measure the 5--8 s envelope, then request only
       // a bounded +/-5 deg correction toward its midpoint. The reference
       // itself slews in the sample_ready branch below.
       if(balance_ms==16'd5000) begin q_min<=a;q_max<=a;q_armed<=1'b1;end
       if(balance_ms==16'd8000 && q_armed) begin
        if((((q_min+q_max)>>>1)-arm_anchor)>REANCHOR_MAX)
          pos_rel<=REANCHOR_MAX;
        else if((((q_min+q_max)>>>1)-arm_anchor)<-REANCHOR_MAX)
          pos_rel<=-REANCHOR_MAX;
        else
          pos_rel<=((q_min+q_max)>>>1)-arm_anchor;
        q_armed<=1'b0;reanchor_pending<=1'b1;
       end
       if(!evt_armed && balance_ms>16'd8000 && ((va_w>32'sd262144)||(va_w<-32'sd262144)))
        begin evt_armed<=1;evt_wait<=1;evt_ms<=0;end
       if(evt_wait) begin
        if(evt_ms>=16'd750) begin evt_wait<=0;freeze<=1;end
        else evt_ms<=evt_ms+1'b1;
       end
      end
      if(sample_ready) begin
       missing_ms<=0;bal_dly<=3'd6;
       if(q_armed) begin
        if(a<q_min) q_min<=a;
        if(a>q_max) q_max<=a;
       end
       if(balance_ms>=16'd3000) swing_total_ms<=0;   // stable: re-arm patience
       // Position mode and the one-shot re-anchor share the same slew. The
       // re-anchor is allowed to cross the ordinary 32 deg arm gate because
       // its target is already clamped to +/-5 deg around the capture arm.
       if(reanchor_pending && reanchor_safe) begin
        if(ref_cur>pos_target+REANCHOR_SLEW) ref_cur<=ref_cur-REANCHOR_SLEW;
        else if(ref_cur<pos_target-REANCHOR_SLEW) ref_cur<=ref_cur+REANCHOR_SLEW;
        else begin ref_cur<=pos_target;reanchor_pending<=1'b0;end
       end else if(!reanchor_pending && th<32'sd11438 && th>-32'sd11438 && rel_ref<32'sd36600 && rel_ref>-32'sd36600) begin
        if(ref_cur>pos_target+P_REF_SLEW) ref_cur<=ref_cur-P_REF_SLEW;
        else if(ref_cur<pos_target-P_REF_SLEW) ref_cur<=ref_cur+P_REF_SLEW;
        else ref_cur<=pos_target;
       end
      end
      else if(bal_dly!=0) begin
       bal_dly<=bal_dly-1'b1;
       if(bal_dly==1) bal_go<=1;
      end
      if(bal_done) begin
       duty<=(bal_cmd>17'sd500)?16'sd500:((bal_cmd<-17'sd500)?-16'sd500:bal_cmd[15:0]);
       commit<=1;
      end
     end
    end
    default: duty<=0;   // FAULT latches
   endcase
  end
 end
endmodule
