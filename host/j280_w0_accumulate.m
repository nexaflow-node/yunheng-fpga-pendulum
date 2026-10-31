function state = j280_w0_accumulate(state,frames,hostSeconds)
% Indexed frozen runs only; reject mixed firmware/runs instead of merging them.
if isempty(state)
    state=struct('firmware_id','','count',[],'total',[], ...
        'freeze_ms',[],'freeze_info',[],'seen',false(0,1), ...
        'records',zeros(0,112,'uint8'),'end_seen',false,'complete',false, ...
        'duplicate_packets',0,'valid_packets',0,'status_rows',[], ...
        'terminal',zeros(1,112,'uint8'));
end
for k=1:size(frames,2)
    b=reshape(frames(:,k),1,[]);payload=b(5:140);
    h=double(typecast(uint8(payload(1:24)),'uint32'));
    if ~any(h(1)==hex2dec('4a5751a0')),error('J280:Firmware','Received a different firmware ID.');end
    thisId=sprintf('%08X',h(1));
    if isempty(state.firmware_id)
        state.firmware_id=thisId;
    elseif ~strcmp(state.firmware_id,thisId)
        error('J280:Firmware','Mixed firmware IDs in one capture (%s vs %s).',state.firmware_id,thisId);
    end
    state.valid_packets=state.valid_packets+1;
    if b(4)==0
        r=decode_prefix(payload(25:136));
        state.status_rows(end+1,:)=[hostSeconds,double(typecast(uint8(b(141:142)),'uint16')),r]; %#ok<AGROW>
        continue
    end
    if b(4)~=1 && b(4)~=2,error('J280:Kind','Unknown packet kind.');end
    if h(3)>2048 || h(6)<h(3),error('J280:Count','Invalid buffer count.');end
    if isempty(state.count)
        state.count=h(3);state.freeze_ms=h(4);state.freeze_info=h(5);state.total=h(6);
        state.records=zeros(state.count,112,'uint8');state.seen=false(state.count,1);
    elseif ~isequal([state.count,state.freeze_ms,state.freeze_info,state.total],h([3,4,5,6]))
        error('J280:MixedRun','Run changed during export. Preserve raw.bin and start a new capture.');
    end
    if b(4)==1
        if h(2)>=state.count,error('J280:Index','Record index is outside the frozen buffer.');end
        idx=h(2)+1;data=payload(25:136);
        if state.seen(idx)
            if ~isequal(state.records(idx,:),data),error('J280:Conflict','Repeated index has different data.');end
            state.duplicate_packets=state.duplicate_packets+1;
        else,state.records(idx,:)=data;state.seen(idx)=true;end
    else
        state.end_seen=true;state.terminal=payload(25:136);
    end
end
state.complete=~isempty(state.count) && state.end_seen && all(state.seen);
end

function row=decode_prefix(bytes)
w=double(typecast(uint8(bytes(1:40)),'uint32'));
s=double(typecast(uint8(bytes(1:40)),'int32'));
meta=uint32(w(3));
row=[w(1),w(2),double(bitand(meta,uint32(4095))), ...
    double(bitand(bitshift(meta,-12),uint32(4095))), ...
    double(bitand(bitshift(meta,-24),uint32(3))), ...
    double(bitand(bitshift(meta,-26),uint32(15))), ...
    s(5)/65536*180/pi,s(6)/65536*180/pi];
end
