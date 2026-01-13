module CLA_16b(input [15:0] A, input [15:0] B, input Cin, output Cout, output [15:0] S,  output P, output G, output Ovfl);

	wire C1, C2, C3, C4;
	wire P0, P1, P2, P3, G0, G1, G2, G3;
	wire D1, D2, D3, D4;

	//#1 	
 	assign C1 = G0|(P0&Cin);
 	assign C2 = G1|(P1&G0)|(Cin&P0&P1);
 	assign C3 = G2|(P2&G1)|(P2&P1&G0)|(Cin&P0&P1&P2);
 	assign C4 = G3|(P3&G2)|(P3&P2&G1)|(P3&P2&P1&G0)|(Cin&P0&P1&P2&P3);


CLA_4b iCLA_lower_level[3:0](.A(A), .B(B), .Cin({C3, C2, C1, Cin}), .Cout({D4,D3,D2,D1}), .S(S), .P({P3, P2, P1, P0}),.G({G3, G2, G1, G0}));


assign P = P0&P1&P2&P3;
assign G = G3|(P3&G2)|(P3&P2&G1)|(P3&P2&P1&G0)|(Cin&P);

assign Cout = C4;
assign same_sign = (~(A[15] ^ B[15]));
assign Ovfl = same_sign & (A[15] ^ S[15]);


endmodule //CLA_16b