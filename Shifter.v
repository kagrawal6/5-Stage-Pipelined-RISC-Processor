module Shifter (Shift_Out, Shift_In, Shift_Val, Mode);
input [15:0] Shift_In; // This is the input data to perform shift operation on
input [3:0] Shift_Val; // Shift amount (used to shift the input data)
input Mode; // To indicate 0=SLL or 1=SRA
output [15:0] Shift_Out; // Shifted output data

wire [15:0] shift_l_intrmdt1,shift_l_final;
wire [15:0] shift_r_intrmdt1,shift_r_final;

// SRA (SHIFT RIGHT ARITHMETIC) LOGIC
assign shift_r_intrmdt1 = (Shift_Val[1]) ? (Shift_Val[0] ? {{{3{Shift_In[15]}}}, Shift_In[15:3]} :  {{{2{Shift_In[15]}}}, Shift_In[15:2]}) :
										   (Shift_Val[0] ? {{{1{Shift_In[15]}}}, Shift_In[15:1]} :  Shift_In);

assign shift_r_final = (Shift_Val[3]) ? (Shift_Val[2] ? {{{12{shift_r_intrmdt1[15]}}}, shift_r_intrmdt1[15:12]} :  {{{8{shift_r_intrmdt1[15]}}}, shift_r_intrmdt1[15:8]}) :
										   (Shift_Val[2] ? {{{4{shift_r_intrmdt1[15]}}}, shift_r_intrmdt1[15:4]} :  shift_r_intrmdt1);
		

//SLL (SHIFT LEFT LOGICAL) LOGIC
assign shift_l_intrmdt1 = (Shift_Val[1]) ? (Shift_Val[0] ? {Shift_In[12:0], 3'b000} : {Shift_In[13:0], 2'b00}) :
										   (Shift_Val[0] ? {Shift_In[14:0], 1'b0} : Shift_In);

assign shift_l_final = (Shift_Val[3]) ? (Shift_Val[2] ? {shift_l_intrmdt1[3:0], 12'h000} : {shift_l_intrmdt1[7:0], 8'h00}) :
										(Shift_Val[2] ? {shift_l_intrmdt1[11:0], 4'h0} : shift_l_intrmdt1);

assign Shift_Out = Mode ? (shift_r_final) : (shift_l_final);


endmodule
