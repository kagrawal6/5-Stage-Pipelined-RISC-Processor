module BitCell( input clk, 
				input rst, 
				input D, 
				input WriteEnable, 
				input ReadEnable1, 
				input ReadEnable2, 
				inout Bitline1, 
				inout Bitline2);

wire dff_q;
dff iDFF(.q(dff_q), .d(D), .wen(WriteEnable), .clk(clk), .rst(rst));

assign Bitline1 = (ReadEnable1) ? dff_q : 1'bz;
assign Bitline2 = (ReadEnable2) ? dff_q : 1'bz;

endmodule 
