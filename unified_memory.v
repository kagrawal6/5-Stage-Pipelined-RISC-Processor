module unified_memory (
    input clk,
    input rst,

    // IF stage inputs and outputs
    input [15:0] instr_addr, // Current value of instr_addr is the input to the I_CACHE
    output [15:0] instr, // Output of the I_CACHE is the instruction
    output instr_miss_stall, // Incase of an I_CACHE MISS, stall signal to stall instr_addr and IF_ID pipeline register

    // MEM stage inputs and outputs
    input [15:0] data_in, // Input data to D_CACHE
    input [15:0] address_in, // Input Address to D_CACHE
    input data_cache_enable, // Control signal from CPU. High when its a LW or SW instr
    input data_cache_wen, // Control signal from CPU. High when SW instr
    output [15:0] data_out, // Data output from D_CACHE for LW instr
    output data_miss_stall // Incase of a D_CACHE MISS. stall signal to stall all stages of CPU
);

wire instr_miss_detected; // Miss detected in I_CACHE
wire [15:0] instr_miss_address; // Address which caused a miss
wire instr_write_tag_array; // Control signal to enable writing to the meta_data_array of I_CACHE
wire instr_write_data_array; // Control signal to enable writing to the data_array of I_CACHE
wire [15:0] instr_cache_data; // Data to be written into the I_CACHE
wire [15:0] instr_cache_out; // Output data from I_CACHE 

wire data_miss_detected; // Miss detected in D_CACHE
wire [15:0] data_miss_address; // Address which caused the miss
wire data_write_data_array; // Control signal to write into the data_array of D_CACHE
wire data_write_tag_array; // Control signal to write into the meta_data_array of D_CACHE
wire [15:0] data_cache_data; // Data to be written into the D_CACHE
wire [15:0] data_cache_out; // Output data from D_CACHE

wire mem_write_en;
wire mem_en;
 

I_cache iICACHE(.clk(clk), .rst(rst), .addr_pc(instr_addr), .metadata_wen(instr_write_tag_array), .I_cache_wen(instr_write_data_array), 
                .I_data_in(instr_cache_data), .miss_detected(instr_miss_detected), .I_cache_out(instr_cache_out), .missed_addr(instr_miss_address));


D_cache iDCACHE(.clk(clk), .rst(rst), .addr(address_in), .metadata_wen(data_write_tag_array), .D_cache_wen(data_write_data_array),
                .D_data_in_mem(data_cache_data), .D_data_in_cpu(data_in), .is_LWSW(data_cache_enable), .is_SW(data_cache_wen), 
                .miss_detected(data_miss_detected), .D_cache_out(data_cache_out), .missed_addr(data_miss_address), .mem_write_en(mem_write_en), .mem_en(mem_en));

cache_memory_bridge iBRIDGE(.clk(clk), .rst(rst), .instr_miss_detected(instr_miss_detected), .instr_miss_address(instr_miss_address),
                            .instr_write_data_array(instr_write_data_array), .instr_write_tag_array(instr_write_tag_array), .data_miss_detected(data_miss_detected),
                            .data_miss_address(data_miss_address), .data_write_data_array(data_write_data_array), .data_write_tag_array(data_write_tag_array),
                            .data_miss_stall(data_miss_stall), .instr_miss_stall(instr_miss_stall), .instr_cache_data(instr_cache_data), .mem_en(mem_en), 
                            .data_cache_data(data_cache_data), .mem_write_en(mem_write_en), .mem_data_in(data_in), .mem_addr_in(address_in));


assign instr = instr_cache_out;  
assign data_out = data_cache_out;
    
endmodule
