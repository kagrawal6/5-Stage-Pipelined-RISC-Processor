module Rotater (Shift_Out, Shift_In, Shift_Val);
input [15:0] Shift_In; // This is the input data to perform shift operation on
input [3:0] Shift_Val; // Shift amount (used to shift the input data)
output [15:0] Shift_Out; // Shifted output data

wire [15:0] rotate_intrmdt;


// SRA (SHIFT RIGHT ARITHMETIC) LOGIC
assign rotate_intrmdt = (Shift_Val[1]) ? (Shift_Val[0] ? {Shift_In[2:0], Shift_In[15:3]} : {Shift_In[1:0], Shift_In[15:2]}  ) :
										   (Shift_Val[0] ? {Shift_In, Shift_In[15:1]} : Shift_In);

assign Shift_Out = (Shift_Val[3]) ? (Shift_Val[2] ? {rotate_intrmdt[11:0], rotate_intrmdt[15:12]} : {rotate_intrmdt[7:0], rotate_intrmdt[15:8]}) :
										   (Shift_Val[2] ? {rotate_intrmdt[3:0], rotate_intrmdt[15:4]}  :  rotate_intrmdt);
		


endmodule