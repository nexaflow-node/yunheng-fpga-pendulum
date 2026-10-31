function [state,closed,events]=j280_w0_ingest(state,frames,hostSeconds)
% Keep the strict one-run checker; archive a reset run before accepting another.
% Every frame is processed separately so a read chunk cannot lose earlier rows.
closed={};events={};
if isempty(state),state=j280_w0_accumulate([],zeros(144,0,'uint8'),hostSeconds);end
for k=1:size(frames,2)
    frame=frames(:,k);b=reshape(frame,1,[]);
    fwid=double(typecast(uint8(b(5:8)),'uint32'));
    if b(4)==0 && any(fwid==hex2dec('4a5751a0'))
        inputMs=double(typecast(uint8(b(33:36)),'uint32'));
        frozenToLive=~isempty(state.count);
        clockReset=isfield(state,'last_status_ms') && inputMs<state.last_status_ms ...
            && ~(state.last_status_ms>4294901760 && inputMs<65536);
        if frozenToLive || clockReset
            closed{end+1}=state; %#ok<AGROW>
            events{end+1}=sprintf('Board restarted; preserved previous run separately (%d received records).',sum(state.seen)); %#ok<AGROW>
            state=j280_w0_accumulate([],zeros(144,0,'uint8'),hostSeconds);
        end
        state=j280_w0_accumulate(state,frame,hostSeconds);
        state.last_status_ms=inputMs;
        continue
    end
    try
        state=j280_w0_accumulate(state,frame,hostSeconds);
    catch exception
        if ~strcmp(exception.identifier,'J280:MixedRun'),rethrow(exception),end
        closed{end+1}=state; %#ok<AGROW>
        events{end+1}=sprintf('Frozen run identity changed; preserved previous run separately (%d received records).',sum(state.seen)); %#ok<AGROW>
        state=j280_w0_accumulate([],frame,hostSeconds);
    end
end
end
