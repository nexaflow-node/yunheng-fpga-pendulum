// Atomic 24-byte frame, 9600 baud, at most 25 Hz.
// AA 55 C3 state fault flags raw12(LE,2) theta(LE,s32)
// omega_f(LE,s32) arm(LE,s32) duty(LE,s16) sequence XOR.
// The host MATLAB collector consumes this established 24-byte protocol.
module c_uart #(parameter BAUD_CYCLES=5208)
 (input clk,rst_n,trigger,input [1:0] state,input [3:0] fault,input [7:0] flags,
 input [11:0] raw12,input signed [31:0] th,vt,a,va,input signed [15:0] duty,output wire tx);
 reg [183:0] payload;       // 23 bytes, byte 0 is AA (least significant)
 reg [7:0] sequence,checksum;
 reg [4:0] idx;
 reg [12:0] baud_count;
 reg [3:0] bit_idx;
 reg [9:0] shift;
 reg [1:0] mode;            // 0 idle, 1 XOR build, 2 transmit, 3 load next byte
 wire [183:0] payload_shift=payload>>(idx*8);
 wire [7:0] payload_byte=payload_shift[7:0];
 wire [7:0] current_byte=(idx==23)?checksum:payload_byte;
 assign tx=(mode==2)?shift[0]:1'b1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   payload<=0;sequence<=0;checksum<=0;idx<=0;baud_count<=0;
   bit_idx<=0;shift<=1023;mode<=0;
  end else case(mode)
   0: if(trigger) begin
    // va remains an RTL port but is omitted to preserve the 24-byte host
    // protocol: 3 header + 1+1+1 + 2 + 4+4+4 + 2 + 1 + 1 bytes.
    payload<={sequence,duty,a,vt,th,4'b0,raw12,flags,4'b0,fault,6'b0,state,
              8'hc3,8'h55,8'haa};
    sequence<=sequence+1'b1;
    checksum<=0;idx<=0;mode<=1;
   end
   1: begin
    checksum<=checksum^payload_byte;
    if(idx==22) begin
     idx<=0;baud_count<=0;bit_idx<=0;
     shift<={1'b1,payload[7:0],1'b0};
     mode<=2;
    end else idx<=idx+1'b1;
   end
   2: if(baud_count>=BAUD_CYCLES-1) begin
    baud_count<=0;
    if(bit_idx==9) begin
     bit_idx<=0;
     if(idx==23) mode<=0;
     else begin idx<=idx+1'b1;mode<=3;end
    end else begin
     bit_idx<=bit_idx+1'b1;
     shift<={1'b1,shift[9:1]};
    end
   end else baud_count<=baud_count+1'b1;
   3: begin
    shift<={1'b1,current_byte,1'b0};
    mode<=2;
   end
  endcase
 end
endmodule
