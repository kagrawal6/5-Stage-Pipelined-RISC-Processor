 module CLA_4b(input [3:0] A, input [3:0] B, input Cin, output Cout, output [3:0]S,  output P, output G, output Ovfl);

 	wire P0, P1, P2, P3, G0, G1, G2, G3; // MY PROPAGATE AND GENERATE SIGNALS
 	wire C1, C2, C3, C4; // MY CARRY SIGNALS
	wire same_sign;

 	assign P0 = A[0]^B[0];
 	assign P1 = A[1]^B[1];
 	assign P2 = A[2]^B[2];
 	assign P3 = A[3]^B[3];

 	assign G0 = A[0]&B[0];
 	assign G1 = A[1]&B[1];
 	assign G2 = A[2]&B[2]; 
 	assign G3 = A[3]&B[3];

 	assign C1 = G0|(P0&Cin);
 	assign C2 = G1|(P1&G0)|(Cin&P0&P1);
 	assign C3 = G2|(P2&G1)|(P2&P1&G0)|(Cin&P0&P1&P2);
 	assign C4 = G3|(P3&G2)|(P3&P2&G1)|(P3&P2&P1&G0)|(Cin&P0&P1&P2&P3);

 	assign S[0] = P0^Cin;
 	assign S[1] = P1^C1;
 	assign S[2] = P2^C2;
 	assign S[3] = P3^C3;

 	assign P = P0&P1&P2&P3;
 	assign G = G3|(P3&G2)|(P3&P2&G1)|(P3&P2&P1&G0)|(Cin&P);

 	assign Cout = C4;
 	assign same_sign = (~(P3));
	assign Ovfl = same_sign & (A[3] ^ S[3]);


 endmodule //CLA_4b