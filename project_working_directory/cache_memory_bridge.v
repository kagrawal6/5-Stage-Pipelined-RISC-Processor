module cache_memory_bridge(
    input clk,
    input rst,

    input instr_miss_detected,
    input [15:0] instr_miss_address,
    output instr_write_data_array,
    output instr_write_tag_array,

    input data_miss_detected,
    input [15:0] data_miss_address,
    output data_write_data_array,
    output data_write_tag_array,
    
    output data_miss_stall,
    output instr_miss_stall,

    output [15:0] instr_cache_data,
    output [15:0] data_cache_data,

    input mem_write_en,
    input mem_en,
    input [15:0] mem_data_in,
    input [15:0] mem_addr_in
);
 
    wire miss_detected; // active high when tag match logic detects a miss
    wire [15:0] miss_address; // address that missed the cache
    wire cache_miss_handler_busy; // asserted while FSM is busy handling the miss (can be used as pipeline stall signal)
    wire write_data_array; // write enable to cache data array to signal when filling with memory_data
    wire write_tag_array; // write enable to cache tag array to signal when all words are filled in to data array
    wire [15:0] memory_address; // address to read from memory
    wire memory_enable; // enables the memory module only when reading the data
    wire [15:0] memory_data; // data returned by memory (after delay)
    wire memory_data_valid; // active high indicates valid data returning on memory bus
    wire [15:0] cache_data;
    wire stall;
    wire instr_in_flight;

    // wire instr_miss_detected_RE;
    // wire data_miss_detected_RE;

    // Cache Miss Handler. Will handle any cache miss, whether data or instr
    cache_miss_handler iCMH(.clk(clk), .rst(rst), .cache_miss_handler_busy(cache_miss_handler_busy), .write_data_array(write_data_array),
                            .write_tag_array(write_tag_array), .memory_address(memory_address), .memory_enable(memory_enable),
                            .memory_data(memory_data), .memory_data_valid(memory_data_valid), .cache_data(cache_data), .stall(stall),
                            .miss_detected(miss_detected), .miss_address(miss_address), .instr_in_flight(instr_in_flight));

    // Global memory
    memory4c iMEM(.clk(clk), .rst(rst), .wr(mem_write_en), .enable(memory_enable | mem_write_en), .addr(mem_write_en ? mem_addr_in : memory_address),
                  .data_in(mem_data_in), .data_valid(memory_data_valid), .data_out(memory_data));

    // Incase of both instr and data memory have a cache miss at the same time, we are prioritizing instr cache miss
    assign miss_detected = ~(cache_miss_handler_busy) ? 
                            (instr_miss_detected & ~instr_in_flight) ? 1'b1 : 
                            data_miss_detected ? instr_miss_detected ? 1'b1 : instr_in_flight ? 1'b0 : 1'b1 : 1'b0 : 1'b0; 
    assign miss_address = (instr_miss_detected & ~instr_in_flight) ? instr_miss_address : 
                          data_miss_detected ? data_miss_address : 16'h0000;

    assign instr_write_data_array = instr_miss_detected ? write_data_array : 1'b0;
    assign instr_write_tag_array = instr_miss_detected ? write_tag_array : 1'b0;

    assign data_write_data_array = (data_miss_detected & ~instr_miss_detected) ? write_data_array : 1'b0;
    assign data_write_tag_array = (data_miss_detected & ~instr_miss_detected) ? write_tag_array : 1'b0;

    assign instr_miss_stall = instr_miss_detected ? stall : 1'b0;
    assign data_miss_stall = data_miss_detected ? stall : 1'b0;

    assign instr_cache_data = instr_miss_detected ? cache_data : 16'h0000;
    assign data_cache_data = data_miss_detected ? cache_data : 16'h0000;

endmodule
