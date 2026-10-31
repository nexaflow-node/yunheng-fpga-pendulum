// Single run per reset; stores complete committed records, oldest first.
// No memory reset loop: infer block RAM. Synchronous read has one cycle latency.
module c_trace_buffer #(parameter WIDTH=768,ADDR_BITS=11)
 (input clk,rst_n,arm,record_en,freeze,input [WIDTH-1:0] record_data,
 input [ADDR_BITS-1:0] read_index,output reg [WIDTH-1:0] read_data,
 output reg frozen,output reg [ADDR_BITS:0] count,output reg [31:0] total,
 output wire [ADDR_BITS-1:0] oldest);
 localparam DEPTH=(1<<ADDR_BITS);
 reg [WIDTH-1:0] mem[0:DEPTH-1];
 reg [ADDR_BITS-1:0] wr;
 reg armed;
 assign oldest=(count==DEPTH)?wr:{ADDR_BITS{1'b0}};
 wire [ADDR_BITS-1:0] rd_addr=oldest+read_index;
 // Separate read/write process prevents reset mux on RAM data.
 always @(posedge clk) begin
  read_data<=mem[rd_addr];
  if(armed && !frozen && !arm && record_en) mem[wr]<=record_data;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin wr<=0;count<=0;total<=0;armed<=0;frozen<=0;end
  else if(arm) begin wr<=0;count<=0;total<=0;armed<=1;frozen<=0;end
  else if(!frozen) begin
   if(armed && record_en) begin
    wr<=wr+1'b1;total<=total+1'b1;
    if(count<DEPTH) count<=count+1'b1;
   end
   // A simultaneous final commit is included before the freeze.
   if(freeze) begin frozen<=1;armed<=0;end
  end
 end
endmodule
