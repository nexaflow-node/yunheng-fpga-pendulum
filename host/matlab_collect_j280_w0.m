function directory=matlab_collect_j280_w0(port,baud,durationSeconds,outputRoot)
% Receive only: COM6 / 115200 / at most120s. Open before SW3 acceptance.
% Raw UART bytes are saved immediately; no serial writes or file overwrites.
if nargin<1,port='COM6';end
if nargin<2,baud=115200;end
if nargin<3,durationSeconds=120;end
if nargin<4,outputRoot=fullfile(fileparts(mfilename('fullpath')),'captures');end
if baud~=115200,error('J280:Baud','W0 firmware requires 115200 baud.');end
if durationSeconds<=0,error('J280:Duration','Duration must be positive.');end
if ~isfolder(outputRoot),mkdir(outputRoot);end
tag=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
directory=fullfile(outputRoot,['W0_',tag]);suffix=0;
while isfolder(directory),suffix=suffix+1;directory=fullfile(outputRoot,sprintf('W0_%s_%d',tag,suffix));end
mkdir(directory);
fid=fopen(fullfile(directory,'raw.bin'),'wb');
if fid<0,error('J280:File','Cannot create raw.bin');end
fileCleanup=onCleanup(@()fclose(fid));
link=serialport(port,baud,'Timeout',1);serialCleanup=onCleanup(@()delete(link));
flush(link);
state=j280_w0_accumulate([],zeros(144,0,'uint8'),0);
tail=uint8([]);crcErrors=0;junk=0;failure='';failureObject=[];
timer=tic;lastState=-1;runNumber=1;closedRuns={};lastProgress=-Inf;announcedFreeze=[];
fprintf('W0 collector ready: %s / %d. Start from natural hanging posture, SW3 hold1.5s then release.\n',port,baud);
fprintf('W0 extra wall OFF. Upright raw3100 (official display3235). FIRST fall stops without recapture.30s maximum,16sample blocks.\n');
fprintf('Save directory: %s\n',directory);
try
    while toc(timer)<durationSeconds
        n=link.NumBytesAvailable;
        if n==0,pause(0.01);continue,end
        bytes=read(link,n,'uint8');fwrite(fid,bytes,'uint8');
        [frames,tail,bad,discarded]=j280_w0_parse([tail,reshape(bytes,1,[])]);
        crcErrors=crcErrors+bad;junk=junk+discarded;
        [state,closed,events]=j280_w0_ingest(state,frames,toc(timer));
        for c=1:numel(closed)
            runDir=fullfile(directory,sprintf('run_%03d',runNumber));mkdir(runDir);
            j280_w0_save(closed{c},runDir,struct('run_number',runNumber,'boundary','board_restart','source_raw','../raw.bin'));
            closedRuns{end+1}=struct('run_number',runNumber,'directory',runDir,'complete',closed{c}.complete,'received_records',sum(closed{c}.seen)); %#ok<AGROW>
            fprintf('%s\nSaved: %s\n',events{c},runDir);runNumber=runNumber+1;
            announcedFreeze=[];lastState=-1;
        end
        if ~isempty(state.status_rows)
            current=state.status_rows(end,7);
            if current~=lastState,fprintf('Board state=%d, fault=%d\n',current,state.status_rows(end,8));lastState=current;end
        end
        if ~isempty(state.count)
            if isempty(announcedFreeze) || announcedFreeze~=state.freeze_ms
                fprintf('Motor stopped (code %d). Exporting %d records; keep power on and do not reset yet.\n',metadata_fault(state),state.count);
                announcedFreeze=state.freeze_ms;lastProgress=-Inf;
            end
            if toc(timer)-lastProgress>=1
                fprintf('Export progress: %d / %d records\n',sum(state.seen),state.count);lastProgress=toc(timer);
            end
        end
        if state.complete,break,end
    end
catch exception
    failure=exception.message;failureObject=exception;
end
metadata=struct('port',port,'baud',baud,'duration_limit_s',durationSeconds, ...
    'host_elapsed_s',toc(timer),'crc_errors',crcErrors,'discarded_bytes',junk, ...
    'unparsed_tail_bytes',numel(tail),'error',failure,'created_at',tag, ...
    'run_number',runNumber,'closed_runs',{closedRuns});
clear serialCleanup link fileCleanup
j280_w0_save(state,directory,metadata);
if ~isempty(failureObject),rethrow(failureObject),end
if state.complete
    fprintf('Frozen trace complete: %d records, fault=%d. UART released.\n',state.count,metadata_fault(state));
else
    fprintf('Capture incomplete; raw.bin and received rows saved. UART released.\n');
end
end
function f=metadata_fault(state)
f=double(bitand(uint32(state.freeze_info),uint32(15)));
end
