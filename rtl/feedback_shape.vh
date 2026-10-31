// N11: notch moved DOWN and WIDER (centre 12.5 Hz, ~12 Hz bandwidth, depth 0.6).
// N9 (centre 15.5/11 Hz) killed the 12-18 Hz rattle (38-63 permille) but the
// energy moved into 8-12 Hz (74-106 permille) and the arm sway stayed 18-25 deg.
// This one covers 8-18 Hz: H@8=0.82 10=0.69 12=0.60 15=0.66 17=0.74.
localparam signed [31:0] F_B0 = 32'sd264534603;
localparam signed [31:0] F_B1 = -32'sd515771780;
localparam signed [31:0] F_B2 = 32'sd252832045;
localparam signed [31:0] F_A0 = 32'sd268435456;
localparam signed [31:0] F_A1 = -32'sd515771780;
localparam signed [31:0] F_A2 = 32'sd248931193;
