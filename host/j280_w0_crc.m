function value = j280_w0_crc(bytes)
% CRC16/CCITT-FALSE: polynomial 1021, initial FFFF, no reflection/xorout.
persistent lut
if isempty(lut)
    lut=zeros(1,256,'uint16');
    for n=0:255
        c=bitshift(uint16(n),8);
        for k=1:8
            if bitget(c,16), c=bitxor(bitshift(c,1),uint16(hex2dec('1021')));
            else, c=bitshift(c,1); end
        end
        lut(n+1)=c;
    end
end
value=uint16(65535);
for b=reshape(uint8(bytes),1,[])
    index=bitxor(bitshift(value,-8),uint16(b));
    value=bitxor(bitshift(value,8),lut(double(index)+1));
end
end
