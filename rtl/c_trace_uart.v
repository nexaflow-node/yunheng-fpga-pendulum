// 144-byte D6 frame: AA 55 D6 kind, 136 payload bytes, packet_seq u16,
// CRC16/CCITT-FALSE u16 little endian over bytes 0..141. UART 8N1.
module c_trace_uart #(parameter BAUD_CYCLES=434)
 (input clk,rst_n,trigger,input [7:0] kind,input [1087:0] payload,
 output wire tx,busy,output reg done);
 reg [1151:0] frame;
 reg [1135:0] scan;
 reg [15:0] sequence,crc;
 reg [7:0] crc_byte,tx_byte;
 reg [2:0] crc_bit;
 reg [3:0] tx_bit;
 reg [15:0] baud_count;
 reg [9:0] shift;
 reg [1:0] phase;
 wire feedback=crc[15]^scan[crc_bit];
 wire [15:0] crc_next={crc[14:0],1'b0}^(feedback?16'h1021:16'h0000);
 assign busy=(phase!=0);
 assign tx=(phase==2)?shift[0]:1'b1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   frame<=0;scan<=0;sequence<=0;crc<=16'hffff;crc_byte<=0;crc_bit<=7;
   tx_byte<=0;tx_bit<=0;baud_count<=0;shift<=10'h3ff;phase<=0;done<=0;
  end else begin
   done<=0;
   case(phase)
    0: if(trigger) begin
     frame<={16'd0,sequence,payload,kind,8'hd6,8'h55,8'haa};
     scan<={sequence,payload,kind,8'hd6,8'h55,8'haa};
     sequence<=sequence+1'b1;crc<=16'hffff;crc_byte<=0;crc_bit<=7;phase<=1;
    end
    1: begin
     crc<=crc_next;
     if(crc_bit!=0) crc_bit<=crc_bit-1'b1;
     else if(crc_byte==141) begin
      frame[1151:1136]<=crc_next;shift<={1'b1,frame[7:0],1'b0};
      tx_byte<=0;tx_bit<=0;baud_count<=0;phase<=2;
     end else begin scan<=scan>>8;crc_byte<=crc_byte+1'b1;crc_bit<=7;end
    end
    2: if(baud_count>=BAUD_CYCLES-1) begin
     baud_count<=0;
     if(tx_bit==9) begin
      if(tx_byte==143) begin phase<=0;done<=1;end
      else begin
       tx_byte<=tx_byte+1'b1;tx_bit<=0;frame<=frame>>8;
       shift<={1'b1,frame[15:8],1'b0};
      end
     end else begin tx_bit<=tx_bit+1'b1;shift<={1'b1,shift[9:1]};end
    end else baud_count<=baud_count+1'b1;
   endcase
  end
 end
endmodule
