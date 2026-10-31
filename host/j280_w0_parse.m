function [packets,tail,badCRC,junk] = j280_w0_parse(bytes)
% Incremental wire parser. Caller retains tail across arbitrary read splits.
tail=reshape(uint8(bytes),1,[]); packets=zeros(144,0,'uint8'); badCRC=0;junk=0;
while numel(tail)>=3
    p=find(tail(1:end-2)==170 & tail(2:end-1)==85 & tail(3:end)==214,1);
    if isempty(p)
        remove=max(0,numel(tail)-2);junk=junk+remove;tail=tail(remove+1:end);break
    end
    if p>1,junk=junk+p-1;tail=tail(p:end);end
    if numel(tail)<144,break,end
    frame=tail(1:144);
    expected=uint16(double(frame(143))+256*double(frame(144)));
    if j280_w0_crc(frame(1:142))~=expected
        badCRC=badCRC+1;tail=tail(2:end);continue
    end
    packets(:,end+1)=frame(:); %#ok<AGROW>
    tail=tail(145:end);
end
end
