// Freeze exports repeat until reset; host can recover a dropped frame by index.
module c_trace_export #(parameter ADDR_BITS=11,BAUD_CYCLES=434,
 FIRMWARE_ID=32'h4a463430)
 (input clk,rst_n,status_tick,frozen,
 input [ADDR_BITS:0] count,input [31:0] total,freeze_ms,freeze_info,
 input [895:0] status_record,terminal_record,read_data,
 output reg [ADDR_BITS-1:0] read_index,output wire tx);
 reg [3:0] phase;
 reg trigger;reg [7:0] kind;reg [1087:0] payload;
 wire busy,done;
 wire [31:0] count32={{(31-ADDR_BITS){1'b0}},count};
 wire [31:0] index32={{(32-ADDR_BITS){1'b0}},read_index};
 c_trace_uart #(.BAUD_CYCLES(BAUD_CYCLES)) uart(.clk(clk),.rst_n(rst_n),
  .trigger(trigger),.kind(kind),.payload(payload),.tx(tx),.busy(busy),.done(done));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin phase<=0;trigger<=0;kind<=0;payload<=0;read_index<=0;end
  else begin
   trigger<=0;
   case(phase)
    0: if(frozen && !busy) begin read_index<=0;phase<=(count!=0)?1:5;end
       else if(status_tick && !busy) begin
        kind<=0;payload<={status_record,total,freeze_info,freeze_ms,count32,32'hffffffff,FIRMWARE_ID};
        trigger<=1;
       end
    1: phase<=2; // RAM address was registered on previous clock
    2: phase<=3; // wait for synchronous read and settling
    3: if(!busy) begin
        kind<=1;payload<={read_data,total,freeze_info,freeze_ms,count32,index32,FIRMWARE_ID};
        trigger<=1;phase<=4;
       end
    4: if(done) begin
        if(index32+1>=count32) phase<=5;
        else begin read_index<=read_index+1'b1;phase<=1;end
       end
    5: if(!busy) begin
        kind<=2;payload<={terminal_record,total,freeze_info,freeze_ms,count32,32'hffffffff,FIRMWARE_ID};
        trigger<=1;phase<=6;
       end
    6: if(done) phase<=7;
    7: if(status_tick) begin read_index<=0;phase<=(count!=0)?1:5;end
    default:phase<=0;
   endcase
  end
 end
endmodule
