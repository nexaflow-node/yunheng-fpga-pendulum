// 4A575076 rebuild: symmetric swing/capture guards, bounded re-anchor,
// no-integral balance core, KQ=[538,315,4690,450], zero3100, wall off.
// ZP1: official display3235 = raw12 3100 +135; fixed upright zero corrected.
// K290 feedback/output/reference unchanged; FIRST fall stops for diagnosis.
// Integrated: M4FH30 balance core (unchanged 7.5 Hz shaping, both integrals,
// 30 s cap, D6 full-run monitor) + v6 softlimit120 automatic swing-up.
// Start accepts an upright manual hold as before, or swings up a hanging
// pendulum, captures within 30 deg / 4.5 rad/s for 3 samples and hands over
// with a fresh anchor/observer/integrators. Fall past 60 deg retries (<=5).
// v5 top level. Reuses the proven v2 board plumbing (ADC averaging,
// SW1 calibration, encoder counting, TB6612 bridge gating, UART
// telemetry) and wires in the v5 control chain:
//   c_sensor (windowed velocities) -> c_control (FSM) ->
//   c_balance_core (observer + LQR) -> c_output -> c_pwm;
//   committed samples -> trace RAM -> frozen UART export.
// SW1 calib (IDLE); SW2 clear encoder (IDLE); SW3 upright acceptance
// after holding 1.5 s and releasing. Any key stops an active run.
module j280_c_top #(parameter MS_CYCLES=50000,KEY_CYCLES=1000000,
 parameter MOTOR_REVERSE=0,ENCODER_REVERSE=0,ANGLE_REVERSE=1,TRACE_ADDR_BITS=11,TRACE_ENABLE=1)
 (input clk_50m,rst_n,key_zero_calib,key_pos_clear,key_motor_toggle,enc_a,enc_b,
 input [9:0] adc_data_in,output adc_clk,adc_oe_n,motor_pwm,motor_in1,motor_in2,
 output led_balance,led_calib_ok,led_motor_run,led_rsvd,uart_tx);
 localparam [11:0] FIXED_UP12=12'd3061;   // N3: 新套件闭环实测零点（3044 + 1.33deg*12.483）
 reg [15:0] ms_count;reg tick_ms;reg [7:0] telemetry_ms;reg telemetry_go;
 reg [2:0] reset_sync;wire reset_n=reset_sync[2];
 always @(posedge clk_50m or negedge rst_n)begin
  if(!rst_n)reset_sync<=0;else reset_sync<={reset_sync[1:0],1'b1};
 end
 always @(posedge clk_50m or negedge reset_n)begin
  if(!reset_n)begin ms_count<=0;tick_ms<=0;telemetry_ms<=0;telemetry_go<=0;end
  else begin
   tick_ms<=0;telemetry_go<=0;
   if(ms_count>=MS_CYCLES-1)begin
    ms_count<=0;tick_ms<=1;
    if(telemetry_ms==249)begin telemetry_ms<=0;telemetry_go<=1;end else telemetry_ms<=telemetry_ms+1'b1;
   end else ms_count<=ms_count+1'b1;
  end
 end
 wire calib_key,clear_key,start_key,mode_key;
 wire stop_level;
 wire sw3_stop;
 c_keys #(.DEBOUNCE_CYCLES(KEY_CYCLES),.LONG_MS(800)) keys
 (.clk(clk_50m),.rst_n(reset_n),.tick_ms(tick_ms),
  .key_n({key_motor_toggle,key_pos_clear,key_zero_calib}),
  .calib(calib_key),.clear(clear_key),.start(start_key),.mode_press(mode_key),
  .stop_level(stop_level),.sw3_level(sw3_stop));
 wire [11:0] raw12;wire have_sample;
 c_adc adc(.clk(clk_50m),.rst_n(reset_n),.data(adc_data_in),.adc_clk(adc_clk),.raw12(raw12),.have_sample(have_sample));
 assign adc_oe_n=0;
 wire [1:0] state;wire [3:0] fault;wire active;
 reg calibrated,calib_busy,calib_bad;
 reg [11:0] up12,calib_min,calib_max;reg [6:0] calib_n;reg [19:0] calib_sum;
 reg signed [31:0] calib_count;
 wire signed [31:0] enc_count;wire enc_bad;
 wire clear_encoder=clear_key && state==0 && !calib_busy;
 c_encoder #(.REVERSE(ENCODER_REVERSE)) encoder(.clk(clk_50m),.rst_n(reset_n),.enc_a(enc_a),.enc_b(enc_b),.clear(clear_encoder),.count(enc_count),.bad(enc_bad));
 wire signed [31:0] th,vth_w,vth_f,a,va_w,va_f;wire sensor_ready,sensor_valid,sensor_mature;
 c_sensor #(.ANGLE_REVERSE(ANGLE_REVERSE),.WINDOW(8)) sensors(.clk(clk_50m),.rst_n(reset_n),
  .sample_en(tick_ms && have_sample),.raw12(raw12),.up12(up12),.count(enc_count),
  .reset_history(calib_busy || clear_encoder),
  .mature(sensor_mature),.ready(sensor_ready),.valid(sensor_valid),
  .th(th),.vth_w(vth_w),.vth_f(vth_f),.a(a),.va_w(va_w),.va_f(va_f));
 wire [20:0] sum_final={1'b0,calib_sum}+{9'b0,raw12};
 wire calib_invalid=(raw12<16 || raw12>4076 || raw12+12'd16<calib_max || raw12>calib_min+12'd16 || enc_count>calib_count+1 || enc_count<calib_count-1);
 always @(posedge clk_50m or negedge reset_n)begin
  if(!reset_n)begin
   calibrated<=1;calib_busy<=0;calib_bad<=0;up12<=FIXED_UP12;calib_n<=0;calib_sum<=0;calib_min<=0;calib_max<=0;calib_count<=0;
  end else begin
   if(calib_key && state==0 && have_sample)begin
    calibrated<=0;calib_busy<=1;calib_bad<=0;calib_n<=0;calib_sum<=0;calib_min<=raw12;calib_max<=raw12;calib_count<=enc_count;
   end else if(calib_busy && tick_ms)begin
    if(calib_invalid)calib_bad<=1;
    if(raw12<calib_min)calib_min<=raw12;if(raw12>calib_max)calib_max<=raw12;
    if(calib_n==127)begin
     calib_busy<=0;
     if(!calib_bad && !calib_invalid)begin up12<=sum_final[18:7];calibrated<=1;end
    end else begin calib_n<=calib_n+1'b1;calib_sum<=sum_final[19:0];end
   end
  end
 end

 // M1 input epoch is latched at the exact ADC/encoder consumption edge.
 reg [31:0] ms_epoch,input_sequence,source_sequence,source_ms;
 reg [11:0] source_raw,source_up;
 reg signed [31:0] source_encoder;
 reg [319:0] sample_snapshot;
 reg [15:0] run_epoch,source_run_epoch;
 always @(posedge clk_50m or negedge reset_n)begin
  if(!reset_n)begin run_epoch<=0;source_run_epoch<=0;end
  else begin
   if(run_begin)run_epoch<=0;
   else if(active && tick_ms)run_epoch<=run_epoch+1'b1;
   if(tick_ms && have_sample)source_run_epoch<=active?(run_epoch+1'b1):0;
  end
 end
 // SW3 is the only runtime stop. SW1/SW2 are position keys in BALANCE,
 // so they must not cut the bridge there: a held key would coast the motor
 // and drop the pendulum.
 wire physical_stop=(!key_motor_toggle) ||
   ((state==2'd0) && (!key_zero_calib || !key_pos_clear));
 wire bridge_en_raw=active && sensor_valid && sensor_mature && have_sample
   && calibrated && !calib_busy && !enc_bad && rst_n && reset_n;
 wire signed [15:0] duty;
 wire signed [31:0] arm_anchor;
 wire signed [31:0] swing_u_unused;
 wire run_begin,freeze,commit;
 wire [447:0] core_trace;
 wire start_event=start_key && state==0 && !calib_busy;
 c_control #(.MAX_RUN_MS(30000)) ctrl(.clk(clk_50m),.rst_n(reset_n),.tick_ms(tick_ms),
  .sample_ready(sensor_ready),.valid(sensor_valid),.mature(sensor_mature),
  .start(start_event),.stop(sw3_stop),.calibrated(calibrated && !calib_busy),
  .key_inc(calib_key),.key_dec(mode_key),
  .motor_active(bridge_en_raw),.external_fault(enc_bad),
  .th(th),.vth_w(vth_w),.vth_f(vth_f),.a(a),.va_w(va_w),.va_f(va_f),
  .state(state),.fault_code(fault),.duty(duty),.active(active),
  .run_begin(run_begin),.freeze(freeze),.commit(commit),
  .trace_data(core_trace),.arm_anchor(arm_anchor),
  .swing_u(swing_u_unused));
 always @(posedge clk_50m or negedge reset_n) begin
  if(!reset_n) begin
   ms_epoch<=0;input_sequence<=0;source_sequence<=0;source_ms<=0;
   source_raw<=0;source_up<=0;source_encoder<=0;sample_snapshot<=0;
  end else begin
   if(tick_ms) ms_epoch<=ms_epoch+1'b1;
   if(tick_ms && have_sample) begin
    source_raw<=raw12;source_up<=up12;source_encoder<=enc_count;
    source_sequence<=input_sequence;source_ms<=ms_epoch;
    input_sequence<=input_sequence+1'b1;
   end
   if(sensor_ready) sample_snapshot<={va_f,va_w,vth_f,vth_w,a,th,source_encoder,
    bridge_en_raw && !physical_stop,sensor_valid,fault,state,
    source_up,source_raw,source_ms,source_sequence};
  end
 end
 wire signed [15:0] physical_duty=MOTOR_REVERSE?-duty:duty;
 c_pwm bridge(.clk(clk_50m),.rst_n(reset_n),.enable(bridge_en_raw && !physical_stop),
  .duty(physical_duty),.pwm(motor_pwm),.in1(motor_in1),.in2(motor_in2));
 assign led_balance=(state==2);assign led_calib_ok=calibrated;
 assign led_motor_run=bridge_en_raw && !physical_stop;
 assign led_rsvd=(state==3 || calib_bad);
 // Words 10..23 are the same committed core transaction as words 0..9.
 wire [15:0] commit_flags=core_trace[415:400] |
  {4'b0,motor_pwm,motor_in2,motor_in1,physical_stop,
   (bridge_en_raw && !physical_stop),7'b0};
 // Word23: unsigned run epoch in high16; signed pre-slew target in low16.
 wire [447:0] commit_trace={source_run_epoch,core_trace[431:416],commit_flags,core_trace[399:0]};
 wire record_commit=commit && source_run_epoch!=0 && !source_run_epoch[0];
 wire [767:0] record_data={commit_trace,sample_snapshot};
 reg [895:0] terminal_record;
 reg [31:0] freeze_ms,freeze_info;
 always @(posedge clk_50m or negedge reset_n) begin
  if(!reset_n) begin terminal_record<=0;freeze_ms<=0;freeze_info<=0;end
  else if(freeze && state==2'd3) begin
   freeze_ms<=ms_epoch;
   freeze_info<={23'd0,physical_stop,2'b0,state,fault};
   terminal_record<={576'd0,sample_snapshot[319:96],
    1'b0,sensor_valid,fault,state,sample_snapshot[87:64],sample_snapshot[63:0]};
  end
 end
 wire frozen;wire [TRACE_ADDR_BITS:0] trace_count;
 wire [31:0] trace_total;
 wire [TRACE_ADDR_BITS-1:0] read_index;
 wire [895:0] read_data;

 wire monitor_commit,monitor_freeze;
 wire [895:0]monitor_data;
 c_trace_monitor monitor(.clk(clk_50m),.rst_n(reset_n),.arm(run_begin),
  .commit(commit),.freeze_in(freeze && state==2'd3),.snapshot(record_data),.arm_anchor(arm_anchor),
  .record_en(monitor_commit),.freeze_out(monitor_freeze),.record_data(monitor_data));
 generate if(TRACE_ENABLE) begin:trace_enabled
  c_trace_buffer #(.WIDTH(896),.ADDR_BITS(TRACE_ADDR_BITS)) buffer(.clk(clk_50m),.rst_n(reset_n),
   .arm(run_begin),.record_en(monitor_commit),.freeze(monitor_freeze),.record_data(monitor_data),
   .read_index(read_index),.read_data(read_data),.frozen(frozen),
   .count(trace_count),.total(trace_total),.oldest());
 end else begin:trace_disabled
  assign read_data=0;assign trace_count=0;assign trace_total=0;
  assign frozen=(state==3);
 end endgenerate
 c_trace_export #(.ADDR_BITS(TRACE_ADDR_BITS),.FIRMWARE_ID(32'h4a575194)) export_uart(.clk(clk_50m),.rst_n(reset_n),
  .status_tick(telemetry_go),.frozen(frozen),.count(trace_count),.total(trace_total),
  .freeze_ms(freeze_ms),.freeze_info(freeze_info),.status_record({128'd0,record_data}),
  .terminal_record(terminal_record),.read_data(read_data),.read_index(read_index),.tx(uart_tx));
endmodule
