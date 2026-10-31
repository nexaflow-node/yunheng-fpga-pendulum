function j280_w0_save(state,directory,metadata)
% Write captured records in index order. Missing rows remain absent and listed.
fid=fopen(fullfile(directory,'capture.json'),'w');
if fid<0,error('J280:File','Cannot create capture.json');end
c=onCleanup(@()fclose(fid));
metadata.fixed_up12=3061;metadata.official_display_offset=135;metadata.official_upright_display=3196;metadata.first_fall_stops_without_recapture=true;
metadata.record_interval_ms=16;metadata.sensor_interval_ms=1;
metadata.run_limit_ms=30000;metadata.duty_limit_permille=500;
metadata.feedback_filter=struct('sample_rate_Hz',1000,'sos_q28',[266466115 -526272766 260558092 268435456 -526272766 258588751],'format','Q28_fraction_saving_DF1');
% 4A575076 raw feedback identity was verified against K3=450 on the
% captured records. Keep this metadata in lockstep with the RTL firmware.
metadata.K_q8=[538,650,4690,450];metadata.Ku_q10=0;
metadata.observer='independent_angle_tracking_motor20_pend40_Hz';
metadata.output_mapping='linear_nominal_PWM_voltage_no_fixed_deadzone_compensation';
metadata.firmware_id=state.firmware_id;metadata.complete=state.complete;
metadata.record_count=state.count;metadata.total_records=state.total;
metadata.trace_capacity=2048;metadata.trace_policy='full_run_16sample_blocks_W0_zero3061_firstfall_stop';
metadata.retained_records=state.count;
if isempty(state.count),metadata.overwritten_records=[];
else,metadata.overwritten_records=max(0,state.total-state.count);end
metadata.freeze_ms=state.freeze_ms;metadata.freeze_info=state.freeze_info;
metadata.missing_indices=find(~state.seen)-1;metadata.duplicate_packets=state.duplicate_packets;
metadata.valid_packets=state.valid_packets;metadata.end_seen=state.end_seen;
if ~isempty(state.freeze_info)
    metadata.fault_code=double(bitand(uint32(state.freeze_info),uint32(15)));
    metadata.final_state=double(bitand(bitshift(uint32(state.freeze_info),-4),uint32(3)));
end
fprintf(fid,'%s',jsonencode(metadata,'PrettyPrint',true));clear c
statusNames={'host_s','packet_sequence','input_sequence','input_ms','raw12','up12','state','fault','theta_deg','arm_deg'};
if isempty(state.status_rows),st=array2table(zeros(0,10),'VariableNames',statusNames);
else,st=array2table(state.status_rows,'VariableNames',statusNames);end
st.official_display_raw=st.raw12+135;st.official_display_up=st.up12+135;
writetable(st,fullfile(directory,'status.csv'));
names={'record_index','input_sequence','input_ms','raw12','up12','state','fault', ...
 'sample_valid','motor_at_sample','encoder_count','theta_q16','arm_q16', ...
 'pend_window_q16','pend_filtered_q16','arm_window_q16','arm_filtered_q16', ...
 'corrected_arm_q16','corrected_arm_speed_q16','corrected_theta_q16','corrected_theta_speed_q16', ...
 'arm_error_q16','feedback_sum_q16','feedback_filter_delta_q16','position_integral_term_q16', ...
 'theta_integral_term_q16','request_before_clip_q16','request_q16','nominal_pwm_voltage_q16', ...
 'duty_permille','control_flags','output_target_permille','run_epoch_ms', ...
 'theta_deg','arm_deg','feedback_pend_speed_rad_s','arm_position_term_V', ...
 'arm_speed_term_V','pend_angle_term_V','pend_speed_term_V','bridge_enabled_at_commit'};
indices=find(state.seen);rows=zeros(numel(indices),numel(names));blocks=zeros(numel(indices),5);
for k=1:numel(indices)
    idx=indices(k);b=state.records(idx,:);
    w=double(typecast(uint8(b),'uint32'));s=double(typecast(uint8(b),'int32'));
    meta=uint32(w(3));d=double(typecast(uint8(b(89:90)),'int16'));
    flags=double(typecast(uint8(b(91:92)),'uint16'));
    out=double(typecast(uint8(b(93:96)),'int16'));
    blocks(k,:)=[s(25:27),double(bitand(uint32(w(28)),uint32(31))),double(bitget(uint32(w(28)),32))];
    rows(k,:)=[idx-1,w(1:2),double(bitand(meta,uint32(4095))), ...
      double(bitand(bitshift(meta,-12),uint32(4095))), ...
      double(bitand(bitshift(meta,-24),uint32(3))),double(bitand(bitshift(meta,-26),uint32(15))), ...
      double(bitget(meta,31)),double(bitget(meta,32)),s(4:22),d,flags,out(1),double(typecast(uint8(b(95:96)),'uint16')), ...
      s(5)/65536*180/pi,s(6)/65536*180/pi,s(14)/65536, ...
      s(15)*538/256/65536,s(12)*650/256/65536, ...
      s(13)*4690/256/65536,s(14)*450/256/65536,double(bitget(uint16(flags),8))];
end
t=array2table(rows,'VariableNames',names);
t.monitor_theta_sum_q16=blocks(:,1);t.monitor_relative_arm_sum_q16=blocks(:,2);
t.monitor_duty_sum_permille=blocks(:,3);t.monitor_sample_count=blocks(:,4);t.monitor_overflow=blocks(:,5);
t.monitor_theta_mean_deg=t.monitor_theta_sum_q16./t.monitor_sample_count/65536*180/pi;
t.monitor_relative_arm_mean_deg=t.monitor_relative_arm_sum_q16./t.monitor_sample_count/65536*180/pi;
t.monitor_duty_mean_percent=t.monitor_duty_sum_permille./t.monitor_sample_count/10;
t.monitor_mid_epoch_ms=t.run_epoch_ms-(t.monitor_sample_count-1)/2;
t.reference_q16=t.corrected_arm_q16-t.arm_error_q16;
t.reference_deg=t.reference_q16/65536*180/pi;
t.arm_speed_deg_s=t.corrected_arm_speed_q16/65536*180/pi;
t.pend_speed_deg_s=t.corrected_theta_speed_q16/65536*180/pi;
t.home_wall_reference_gate=double(abs(t.reference_q16)<3436);
t.home_wall_enabled=zeros(height(t),1);
t.home_wall_term_q16=sign(t.arm_error_q16).*max(abs(t.arm_error_q16)-11438,0)*2.*t.home_wall_enabled;
t.home_wall_term_V=t.home_wall_term_q16/65536;
expectedFeedback=floor((538*t.arm_error_q16+650*t.corrected_arm_speed_q16+4690*t.corrected_theta_q16+450*t.corrected_theta_speed_q16)/256)+t.home_wall_term_q16;
t.feedback_identity_error_q16=t.feedback_sum_q16-expectedFeedback;
metadata.feedback_identity_ok=all(t.feedback_identity_error_q16==0);
metadata.feedback_mismatch_record_indices=t.record_index(t.feedback_identity_error_q16~=0);
metadata.baseline_firmware_id='4A5A5031';metadata.extra_wall_gain_V_rad=0;metadata.diagnostic_only=false;metadata.hardware_improvement_verified=false;
metadata.control_variant='KQ_538_650_4690_450_obs07_notch125_zero3061';

t.expected_linear_output_target_permille=sign(t.request_q16).*floor(floor(abs(t.request_q16)*1000/65536)/12);
t.output_mapping_identity_error=t.output_target_permille-t.expected_linear_output_target_permille;
t.expected_nominal_pwm_q16=sign(t.duty_permille).*floor(abs(t.duty_permille)*786432/1000);
t.output_nominal_identity_error=t.nominal_pwm_voltage_q16-t.expected_nominal_pwm_q16;
metadata.output_identity_ok=all(t.output_mapping_identity_error==0 & t.output_nominal_identity_error==0 & abs(t.duty_permille)<=500);
metadata.extra_wall_identity_ok=all(t.home_wall_term_q16==0 & t.home_wall_enabled==0);
metadata.monitor_format='D6_144B_112Brecord_16sample_sums';metadata.monitor_max_Hz=62.5;
metadata.monitor_total_control_samples=sum(t.monitor_sample_count);
metadata.monitor_overflow_rows=find(t.monitor_overflow~=0)-1;
metadata.monitor_mean_is_boxcar=true;metadata.snapshot_is_block_last_sample=true;
metadata.analysis_warning='K290 gains/output/ref retained; extra wall OFF; upright zero3061; FIRST fall stops. Control1kHz.16sample boxcar sums and block-last snapshots, nominal62.5Hz; partial end uses actual count. Suitable for slow repeated arm motion, not every1ms jerk peak.';

fl=uint16(t.control_flags);
t.gpio_in1=double(bitget(fl,10));t.gpio_in2=double(bitget(fl,11));t.gpio_pwm=double(bitget(fl,12));
t.bridge_mode_at_commit=zeros(height(t),1);
t.bridge_mode_at_commit(t.gpio_in1==1 & t.gpio_in2==0 & t.gpio_pwm==1)=1;
t.bridge_mode_at_commit(t.gpio_in1==0 & t.gpio_in2==1 & t.gpio_pwm==1)=2;
t.bridge_mode_at_commit(t.gpio_in1==1 & t.gpio_in2==1 & t.gpio_pwm==0)=3;
t.bridge_mode_at_commit(t.gpio_in1==0 & t.gpio_in2==0 & t.gpio_pwm==1)=4;
t.official_display_raw=t.raw12+135;t.official_display_up=t.up12+135;
metadata.observed_up12=unique(t.up12);
writetable(t,fullfile(directory,'trace.csv'));
% Persist the true elapsed run window; first row need not be epoch2.
if isempty(t),metadata.retained_start_epoch_ms=[];metadata.retained_end_epoch_ms=[];
else,metadata.retained_start_epoch_ms=t.run_epoch_ms(1);metadata.retained_end_epoch_ms=t.run_epoch_ms(end);end
fid=fopen(fullfile(directory,'capture.json'),'w');if fid<0,error('J280:File','Cannot write final metadata');end
c=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(metadata,'PrettyPrint',true));clear c
if state.end_seen
    % Terminal prefix is a stopped snapshot; remaining words are deliberately zero.
    fid=fopen(fullfile(directory,'terminal.hex'),'w');c=onCleanup(@()fclose(fid));
    fprintf(fid,'%02x',state.terminal);fprintf(fid,'\n');clear c
end
end
