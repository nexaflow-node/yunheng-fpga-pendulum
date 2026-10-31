function summary=summarize_W0(directory)
% Report observed metrics only; no automatic physical success judgement.
t=readtable(fullfile(directory,'trace.csv'));m=jsondecode(fileread(fullfile(directory,'capture.json')));
summary=struct('firmware_id','4a5751a0','fixed_up12',3061,'extra_wall_gain_V_rad',0,'physical_improvement_verified',false,'windows',[]);
if isfield(m,'fault_code'),summary.finish_code=m.fault_code;else,summary.finish_code=[];end
summary.warning='16ms block-last snapshots, not full1kHz extrema. Arm is motor-side encoder estimate. Reference zero is not actual settling.';
if ~isempty(t)
 epoch=t.run_epoch_ms/1000;ids=find(t.reference_q16==0,1);
 if isempty(ids),summary.first_reference_zero_s=[];else,summary.first_reference_zero_s=epoch(ids);end
 summary.samples=sum(t.monitor_sample_count);summary.last_epoch_s=epoch(end);
 summary.windows=repmat(struct('interval_s',[],'snapshots',0,'reference_range_deg',[],'arm_range_deg',[],'arm_est_speed_rms_deg_s',[],'arm_est_speed_peak_deg_s',[],'theta_range_deg',[],'wall_peak_V',[]),0,1);
 for start=0:5:floor(epoch(end)/5)*5
  mask=epoch>=start & epoch<start+5;if ~any(mask),continue,end
  q=t(mask,:);w=struct('interval_s',[start,min(start+5,epoch(end))],'snapshots',height(q), ...
   'reference_range_deg',[min(q.reference_deg),max(q.reference_deg)],'arm_range_deg',[min(q.arm_deg),max(q.arm_deg)], ...
   'arm_est_speed_rms_deg_s',sqrt(mean(q.arm_speed_deg_s.^2)),'arm_est_speed_peak_deg_s',max(abs(q.arm_speed_deg_s)), ...
   'theta_range_deg',[min(q.theta_deg),max(q.theta_deg)],'wall_peak_V',max(abs(q.home_wall_term_V)));
  summary.windows(end+1)=w;
  fprintf('W0 %.1f-%.1fs: arm[%.2f,%.2f]deg speedRMS %.2f peak %.2f deg/s ref[%.2f,%.2f]deg\n',w.interval_s,w.arm_range_deg,w.arm_est_speed_rms_deg_s,w.arm_est_speed_peak_deg_s,w.reference_range_deg);
 end
end
fid=fopen(fullfile(directory,'summary_W0.json'),'w');assert(fid>=0);c=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(summary,'PrettyPrint',true));
end
