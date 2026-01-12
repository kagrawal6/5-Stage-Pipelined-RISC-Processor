module decoder_3_8 (
    input [2:0] offset,
    output [7:0] word_block             // cache block in a set to write/read from
);

// decoding the cache block in a set to be read from

assign word_block = 	    (offset == 0)	?	8'h1		:
                            (offset == 1)	?	8'h2		:
                            (offset == 2)	?	8'h4	    :
                            (offset == 3)	?	8'h8	    :
                            (offset == 4)	?	8'h10	    :
                            (offset == 5)	?	8'h20	    :
                            (offset == 6)	?	8'h40		:
                                                8'h80;

endmodule