module cache_miss_handler(
    input clk,
    input rst, 
    input miss_detected, // active high when tag match logic detects a miss
    input [15:0] miss_address, // address that missed the cache
    output cache_miss_handler_busy, // asserted while FSM is busy handling the miss (can be used as pipeline stall signal)
    output write_data_array, // write enable to cache data array to signal when filling with memory_data
    output write_tag_array, // write enable to cache tag array to signal when all words are filled in to data array
    output [15:0] memory_address, // address to read from memory
    output memory_enable, // enables the memory module only when reading the data
    input [15:0] memory_data, // data returned by memory (after delay)
    input memory_data_valid, // active high indicates valid data returning on memory bus
    output [15:0] cache_data,
    output stall,
    output instr_in_flight
);

    wire [11:0] cnt_status; // Wire connects to the output of shift register
    wire [11:0] nxt_status; // Input to the shift register.

    ////////////////////////////////////////////////////////////////////////////////
    // Next address calculator /////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////
    wire [15:0] start_address;
    wire [15:0] cnt_address; // Holds the current address that is being read from the memory
    wire [15:0] nxt_address; // Holds the next address that is to be read from the memory

    CLA_16b ADDR_INCRMTR(.A(cnt_address), 
                           .B(16'h0002), 
                           .S(nxt_address), 
                           .Cin(1'b0));

    pldff #(.WIDTH(16)) CNT_ADDR(.d(miss_detected ? start_address : nxt_address), 
                                 .q(cnt_address), 
                                 .clk(clk), 
                                 .rst(rst), 
                                 .wen(1'b1));

    ////////////////////////////////////////////////////////////////////////////////
    // Shift register to keep track of transactions ////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////    
    pldff #(12) STATUS_SHIFT_REG(.clk(clk), 
                                 .rst(rst), 
                                 .d(nxt_status), 
                                 .q(cnt_status), 
                                 .wen(1'b1)); 


    assign memory_address = cnt_address; // As miss is detected, the first address is the blocks starting address
    assign nxt_status = miss_detected ? {cnt_status[10:0], 1'b1} : {cnt_status[10:0], 1'b0}; // When miss is detected, we load the status register with 12'h001 
    assign cache_miss_handler_busy =(|cnt_status[6:0]); // As long as a transaction is in process, handler is busy
    assign stall = (|cnt_status) | miss_detected; // Stall signal to halt the execution of CPU
    assign start_address = miss_address & 16'hFFF0; // Calculating the starting address of the block
    assign write_data_array = memory_data_valid; // Data_array is enabled as long as data from the memory is valid
    assign write_tag_array = cnt_status[11]; // We only update the tag_array once all the transactions are complete
    assign memory_enable = (|cnt_status[7:0]); // Control signal to enable the global memory
    assign instr_in_flight = |cnt_status[11:7]; // Checking if any miss is receiving data from main memory
    assign cache_data = memory_data;

endmodule 