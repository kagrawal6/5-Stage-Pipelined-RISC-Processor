// This files detects the D-cache miss and hit
// Accordingly, it will write and read from the D-cache

module D_cache (
    input clk,
    input rst,
    input [15:0] addr,               // address to read the instruction from
    input metadata_wen,                  // write enable for metadata
    input D_cache_wen,                   // write enable signal for D-cache
    input [15:0] D_data_in_mem,            // data to write in D-cache
    input [15:0] D_data_in_cpu,            // data input from cpu for sw instruction
    input is_LWSW,                        // is it a memory instruction
    input is_SW,                        // is it a SW instruction
    output miss_detected,               // high when it's a miss
    output [15:0] D_cache_out,
    output [15:0] missed_addr,
    output mem_write_en,
    output mem_en
);

wire [63:0] set_enable;             // (index) which set of the cache is to be read from or write into
wire [5:0] index;                   // index of the cache
wire [7:0] metadata_out_way0;       // 8 bits for {tag, valid, LRU} bit for way 0
wire [7:0] metadata_out_way1;       // 8 bits for {tag, valid, LRU} bit for way 1
wire miss0;                         // cache miss for way 0
wire miss1;                         // cache miss for way 1
wire [7:0] metadata_in0;            // data to write in metadata for way 0
wire [7:0] metadata_in1;            // data to write in metadata for way 1
wire en_way;                        // en_way = 0 to write in way 0 en_way = 1 to write in way 1
wire [7:0] word_block;
wire [7:0] word_enable;
wire [7:0] word_to_shift;
wire [7:0] word_shifted;
wire [15:0] D_cache_out0;
wire [15:0] D_cache_out1;
wire [5:0] tag_in0;
wire [5:0] tag_in1;
wire vld_in0;
wire vld_in1;
wire [15:0] D_data_in;



assign index = addr[9:4];

// one-hot encoding for set_enable
decoder_6_64 iDecoder6_4_0(
  .index(index),
  .cacheline_meta(set_enable)	// cache line to be read from
);

// Instantiating the metadata way array to check the valid bit and tag for a particular address
// And writing the updated value to the metadata waya array 
// metadata_way_array iMetadataWay0(
//     .clk(clk),
//     .rst(rst),
//     .data_in(metadata_in0),
//     .wen(((metadata_wen)|~miss0) & is_LWSW),
//     .set_enable(set_enable),
//     .data_out(metadata_out_way0)
// );

// metadata_way_array iMetadataWay1(
//     .clk(clk),
//     .rst(rst),
//     .data_in(metadata_in1),
//     .wen(((metadata_wen)|~miss1) & is_LWSW),
//     .set_enable(set_enable),
//     .data_out(metadata_out_way1)
// );

MetaDataArray MetaData_0(.clk(clk), .rst(rst), .DataIn(metadata_in0), .Write(((metadata_wen)|~miss0) & is_LWSW), .DataOut(metadata_out_way0), .BlockEnable(set_enable)); 
MetaDataArray MetaData_1(.clk(clk), .rst(rst), .DataIn(metadata_in1), .Write(((metadata_wen)|~miss1) & is_LWSW), .DataOut(metadata_out_way1), .BlockEnable(set_enable)); 

// Check in both the ways if the valid is bit 1 
// if the valid bit is 1 then check for the tag bit if it is as same as the current address
// if it is not same then it's a miss
assign miss0 = is_LWSW ? (metadata_out_way0[1]   ?  ((metadata_out_way0[7:2] == addr[15:10])  ?  1'h0   :    1'h1)  :  1'h1) : 1'h0;
assign miss1 = is_LWSW ? (metadata_out_way1[1]   ?  ((metadata_out_way1[7:2] == addr[15:10])  ?  1'h0   :    1'h1)  :  1'h1) : 1'h0;

assign miss_detected = miss0 & miss1;        // miss is high when it's a miss in both the ways
assign missed_addr = miss_detected    ?    addr    :    16'h6969;

//if it's a hit or writing to the cache is done, then update the LRU bit to 1 for the respective way
assign LRU_bit0 = (~miss0 | (metadata_wen & ~en_way))    ?      1'h1     :       1'h0;      
assign LRU_bit1 = (~miss1 | (metadata_wen & en_way))     ?      1'h1     :       1'h0;            // MANALI: REMOVABLE WHILE SYNTHESIZING 

// Updating the metadata way array {tag, valid, LRU}
assign metadata_in0 = {tag_in0, vld_in0, LRU_bit0};
assign metadata_in1 = {tag_in1, vld_in1, LRU_bit1};

assign tag_in0 = ~en_way   ?   addr[15:10]   :   metadata_out_way0[7:2];
assign tag_in1 =  en_way   ?   addr[15:10]   :   metadata_out_way1[7:2];

assign vld_in0 = ~en_way    ?   (~metadata_out_way0[1]   ?   1'h1   :   metadata_out_way0[1])   :    
                                  metadata_out_way0[1]; 
assign vld_in1 = en_way    ?    (~metadata_out_way1[1]   ?   1'h1   :   metadata_out_way1[1])   :   
                                  metadata_out_way1[1]; 

// check the LRU bit to write the data in the correct cache way
// if the LRU bit for cache way 0 is high then we'll use way 1 to write the data in cache 
// if the LRU bit for way 0 is low then we'll use cache way 0 to write the data 
// if the LRU bit for both the ways is low then we'll write the data in way 0 by default
// en_way is 0 if the data is to be written in way 0 or else 1
assign en_way = metadata_out_way0[0]   ?   1'h1   :   1'h0;

decoder_3_8 iDecoder_3_8_0(
    .offset(addr[3:1]),
    .word_block(word_block)             // 3-bit offset converted in 8-bit one-hot to select the word in a cache line
);

// load it with 8'h01 in the beginning & keep shifting the word to left by 1 bit 
assign word_to_shift = ((~|word_shifted) | (word_shifted == 8'h80))   ?   8'h01    :    word_shifted << 1;

// if it's a hit, then just read a particular word block we got from the encoder
// if it's a miss then keep passing the shifted values to write in the cache 1 by 1
assign word_enable = miss_detected    ?   word_to_shift   :   word_block;

// shift register for incrementing word block
pldff #(.WIDTH(8)) iPldff0 (
    .q(word_shifted),              // DFF output
    .d(word_to_shift),             // DFF input
    .wen(D_cache_wen),             // One Write Enable for all bits
    .clk(clk),
    .rst(rst)                      // synchronous reset
);

assign D_data_in = is_SW   ?  (~miss_detected   ?   D_data_in_cpu   :   D_data_in_mem)   :   D_data_in_mem;

assign mem_write_en = ~miss_detected & is_SW;
assign mem_en = ~miss_detected & is_LWSW;

// writing cache data in way 0
// data_way_array iData_way_array0(
//     .clk(clk),
//     .rst(rst),
//     .data_in(D_data_in),
//     .wen((D_cache_wen & ~en_way) | (is_SW & ~miss0)),
//     .set_enable(set_enable),
//     .word_enable(word_enable),         
//     .data_out(D_cache_out0)
// );

// // writing cache data in way 1
// data_way_array iData_way_array1(
//     .clk(clk),
//     .rst(rst),
//     .data_in(D_data_in),
//     .wen((D_cache_wen & en_way)| (is_SW & ~miss1)),
//     .set_enable(set_enable),
//     .word_enable(word_enable),         
//     .data_out(D_cache_out1)
// );


DataArray Data_0(.clk(clk), .rst(rst), .DataIn(D_data_in), .Write((D_cache_wen & ~en_way) | (is_SW & ~miss0)), .BlockEnable(set_enable), .WordEnable(word_enable), .DataOut(D_cache_out0));
DataArray Data_1(.clk(clk), .rst(rst), .DataIn(D_data_in), .Write((D_cache_wen & en_way)| (is_SW & ~miss1)), .BlockEnable(set_enable), .WordEnable(word_enable), .DataOut(D_cache_out1));

// send the data out that is recently written in the D-cache, hence the data of which the LRU bit is high
assign D_cache_out = en_way   ?   D_cache_out0   :   D_cache_out1;

endmodule
