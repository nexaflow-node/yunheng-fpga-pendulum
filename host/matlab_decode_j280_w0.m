function directory=matlab_decode_j280_w0(rawPath,outputRoot)
% Recover saved raw bytes after an interrupted collector, without opening COM.
if nargin<2,outputRoot=fileparts(rawPath);end
tag=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
directory=fullfile(outputRoot,['decoded_',tag]);suffix=0;
while isfolder(directory),suffix=suffix+1;directory=fullfile(outputRoot,sprintf('decoded_%s_%d',tag,suffix));end
fid=fopen(rawPath,'rb');if fid<0,error('J280:File','Cannot read raw capture.');end
cleanup=onCleanup(@()fclose(fid));
state=j280_w0_accumulate([],zeros(144,0,'uint8'),NaN);
tail=uint8([]);badTotal=0;junkTotal=0;runNumber=1;closedRuns={};
mkdir(directory);
while ~feof(fid)
    b=fread(fid,65536,'*uint8').';
    [frames,tail,bad,junk]=j280_w0_parse([tail,b]);
    [state,closed,events]=j280_w0_ingest(state,frames,NaN);
    for c=1:numel(closed)
        runDir=fullfile(directory,sprintf('run_%03d',runNumber));mkdir(runDir);
        j280_w0_save(closed{c},runDir,struct('source_raw',rawPath,'offline_decode',true,'run_number',runNumber,'boundary','board_restart'));
        closedRuns{end+1}=struct('run_number',runNumber,'directory',runDir,'complete',closed{c}.complete,'received_records',sum(closed{c}.seen)); %#ok<AGROW>
        fprintf('%s\n',events{c});runNumber=runNumber+1;
    end
    badTotal=badTotal+bad;junkTotal=junkTotal+junk;
end
clear cleanup
j280_w0_save(state,directory,struct('source_raw',rawPath,'crc_errors',badTotal, ...
 'discarded_bytes',junkTotal,'unparsed_tail_bytes',numel(tail),'offline_decode',true, ...
 'run_number',runNumber,'closed_runs',{closedRuns}));
fprintf('Saved offline decode: %s (complete=%d)\n',directory,state.complete);
end
