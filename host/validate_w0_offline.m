function validate_w0_offline
% Pure offline: reads generated RTL fixture. Never opens a serial port.
here=fileparts(mfilename('fullpath'));addpath(here,'-begin');
fixture=fullfile(here,'offline_fixture');raw=readbytes(fullfile(fixture,'w0_fullrun_rtl.bin'));
[frames,tail,bad,junk]=j280_w0_parse(raw);
assert(size(frames,2)==1876 && isempty(tail) && bad==0 && junk==0);
fr=zeros(144,0,'uint8');remaining=uint8([]);position=1;parts=[1,2,17,143,144,299,4093];p=1;
while position<=numel(raw)
 n=min(parts(p),numel(raw)-position+1);
 [f,remaining,b,j]=j280_w0_parse([remaining,raw(position:position+n-1)]);
 assert(b==0 && j==0);fr=[fr,f]; %#ok<AGROW>
 position=position+n;p=mod(p,numel(parts))+1;
end
assert(isempty(remaining) && isequal(fr,frames));
state=j280_w0_accumulate([],frames,NaN);
assert(state.complete && state.count==1875 && state.total==1875 && strcmp(state.firmware_id,'4a5751a0'));
out=fullfile(fixture,'validation_decode');if ~isfolder(out),mkdir(out);end
j280_w0_save(state,out,struct('offline_fixture',true));
t=readtable(fullfile(out,'trace.csv'));expected=readtable(fullfile(fixture,'expected.csv'));
for k=1:numel(expected.Properties.VariableNames)
 n=expected.Properties.VariableNames{k};assert(isequal(t.(n),expected.(n)),n);
end
meta=jsondecode(fileread(fullfile(out,'capture.json')));
assert(meta.feedback_identity_ok && meta.output_identity_ok && meta.extra_wall_identity_ok && meta.extra_wall_gain_V_rad==0 && meta.duty_limit_permille==500 && meta.record_interval_ms==16 && isequal(meta.K_q8(:).',[538,650,4690,450]));
assert(strcmp(meta.observer,'independent_angle_tracking_motor20_pend40_Hz'));
assert(height(t)==1875 && sum(t.monitor_sample_count)==29999 && t.monitor_sample_count(end)==15);
assert(all(t.feedback_identity_error_q16==0));
state=j280_w0_accumulate(state,frames(:,1),NaN);assert(state.duplicate_packets==1);
wrong=readbytes(fullfile(fixture,'wrong_id.bin'));f=j280_w0_parse(wrong);caught=false;
try,j280_w0_accumulate([],f,NaN);catch ex,caught=strcmp(ex.identifier,'J280:Firmware');end
assert(caught,'Wrong firmware must be rejected');
damaged=raw;damaged(40)=bitxor(damaged(40),uint8(1));[f,tail,bad,junk]=j280_w0_parse(damaged);
assert(size(f,2)==1875 && isempty(tail) && bad>=1 && junk>=1);
changed=frames(:,1);changed(17:20)=typecast(uint32(state.freeze_ms+1),'uint8').';
[fresh,closed,events]=j280_w0_ingest(state,changed,NaN); %#ok<ASGLU>
assert(numel(closed)==1 && sum(fresh.seen)==1 && ~fresh.complete);
decoded=matlab_decode_j280_w0(fullfile(fixture,'w0_fullrun_rtl.bin'),fixture);
m=jsondecode(fileread(fullfile(decoded,'capture.json')));assert(m.complete && m.feedback_identity_ok && m.monitor_total_control_samples==29999);
nf=j280_w0_parse(readbytes(fullfile(fixture,'w0_native_top.bin')));ns=j280_w0_accumulate([],nf,NaN);assert(ns.complete && ns.count==157);
nd=fullfile(fixture,'native_validation');if ~isfolder(nd),mkdir(nd);end
j280_w0_save(ns,nd,struct('offline_fixture',true));nt=readtable(fullfile(nd,'trace.csv'));ne=readtable(fullfile(fixture,'native_expected.csv'));
for k=1:numel(ne.Properties.VariableNames),n=ne.Properties.VariableNames{k};assert(isequal(nt.(n),ne.(n)),n);end
nm=jsondecode(fileread(fullfile(nd,'capture.json')));assert(nm.fault_code==6 && nm.feedback_identity_ok && nm.output_identity_ok && nm.extra_wall_identity_ok && nm.fixed_up12==3061 && nm.official_upright_display==3196 && nm.first_fall_stops_without_recapture);
assert(sum(nt.monitor_sample_count)==2500 && nt.monitor_sample_count(end)==4 && all(nt.reference_q16==0));
assert(all(nt.official_display_raw==3235 & nt.official_display_up==3235));
terminalHex=strtrim(fileread(fullfile(nd,'terminal.hex')));assert(strcmp(terminalHex,lower(reshape(dec2hex(ns.terminal,2).',1,[]))));
empty=j280_w0_accumulate([],zeros(144,0,'uint8'),NaN);ed=fullfile(fixture,'empty_validation');if ~isfolder(ed),mkdir(ed);end
j280_w0_save(empty,ed,struct('offline_fixture',true));
ss=summarize_W0(nd);assert(ss.finish_code==6 && ~ss.physical_improvement_verified);
es=summarize_W0(ed);assert(isempty(es.windows));
fprintf('W0_MATLAB_OFFLINE_PASS 1875records 29999samples partial15 wall0 feedback native157partial4 firstFall6 zero3100 display3235 empty CRC fragmentation strictID duplicate split decode\n');
end
function b=readbytes(p)
f=fopen(p,'rb');assert(f>=0);c=onCleanup(@()fclose(f));b=fread(f,Inf,'*uint8').';
end
