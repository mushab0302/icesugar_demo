module top_tm1638_demo(
    input clk,

    output reg tm_cs,
    output tm_clk,
    inout  tm_dio
    );

    localparam 
        HIGH    = 1'b1,
        LOW     = 1'b0;

    localparam [6:0]
        S_0     = 7'b0111111,
        S_1     = 7'b0000110,
        S_2     = 7'b1011011,
        S_3     = 7'b1001111,
        S_4     = 7'b1100110,
        S_5     = 7'b1101101,
        S_6     = 7'b1111101,
        S_7     = 7'b0000111,
        S_8     = 7'b1111111,
        S_t     = 7'b1111000,
        S_e     = 7'b1111011,
        S_dash  = 7'b1000000,
        S_BLK   = 7'b0000000;

    localparam [7:0]
        C_READ  = 8'b01000010,
        C_WRITE = 8'b01000000,
        C_DISP  = 8'b10001111,
        C_ADDR  = 8'b11000000;

    localparam CLK_DIV = 19; // speed of scanner

    reg rst = HIGH;

    reg [5:0] instruction_step;
    reg [7:0] keys;

    reg [7:0] larson;
    reg larson_dir;
    reg [CLK_DIV:0] counter;

    reg [6:0] text_mem [0:19];

    // --- SCROLLING VARIABLES ---
    reg [4:0] scroll_idx;     // Holds the starting index (0 to 10)
    reg [21:0] scroll_counter;// Slower clock divider for rate-limiting
    reg s1_prev, s2_prev;     // Edge-detection registers
    reg [23:0] scroll_cooldown; // Cooldown timer to prevent rapid multi-stepping
    
    // set up tristate IO pin for display
    reg tm_rw;
    wire dio_in, dio_out;
    SB_IO #(
        .PIN_TYPE(6'b101001),
        .PULLUP(1'b1)
    ) tm_dio_io (
        .PACKAGE_PIN(tm_dio),
        .OUTPUT_ENABLE(tm_rw),
        .D_IN_0(dio_in),
        .D_OUT_0(dio_out)
    );

    // setup tm1638 module with it's tristate IO
    wire tm_latch, busy;
    wire [7:0] tm_data, tm_in;
    reg [7:0] tm_out;

    assign tm_in = tm_data;
    assign tm_data = tm_rw ? tm_out : 8'hZZ;

    tm1638 u_tm1638 (
        .clk(clk),
        .rst(rst),
        .data_latch(tm_latch),
        .data(tm_data),
        .rw(tm_rw),
        .busy(busy),
        .sclk(tm_clk),
        .dio_in(dio_in),
        .dio_out(dio_out)
    );

    initial begin
        text_mem[0]  = S_BLK;
        text_mem[1]  = S_2;    text_mem[2]  = S_1;    text_mem[3]  = S_dash;
        text_mem[4]  = S_4;    text_mem[5]  = S_8;    text_mem[6]  = S_1;
        text_mem[7]  = S_2;    text_mem[8]  = S_2;    text_mem[9]  = S_3;
        text_mem[10] = S_dash; text_mem[11] = S_t;    text_mem[12] = S_e;
        text_mem[13] = S_dash; text_mem[14] = S_5;    text_mem[15] = S_3;
        text_mem[16] = S_1;    text_mem[17] = S_1;    text_mem[18] = S_6;
        text_mem[19] = S_BLK;
    end

    // handles displaying digits and shifting inside key check
    task display_digit;
        input [2:0] key;
        input [6:0] segs;

        begin
            tm_latch <= HIGH;

            if (keys[key])
                tm_out <= {1'b1, segs}; // decimal on
            else
                tm_out <= {1'b0, segs}; // decimal off
        end
    endtask

    // handles animating the LEDs 1-8
    task display_led;
        input [2:0] dot;

        begin
            tm_latch <= HIGH;
            tm_out <= {7'b0, larson[dot]};
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            instruction_step <= 6'b0;
            tm_cs <= HIGH;
            tm_rw <= HIGH;
            rst <= LOW;

            counter <= 0;
            keys <= 8'b0;
            larson_dir <= 0;
            larson <= 8'b00010000;

            // Initialize scrolling state
            scroll_idx <= 1;
            scroll_counter <= 0;
            s1_prev <= 0;
            s2_prev <= 0;
            scroll_cooldown <= 0;

        end else begin
            if (&counter) begin
                larson_dir <= larson[6] ? 0 : larson[1] ? 1 : larson_dir;

                if (larson_dir)
                    larson <= {larson[6:0], larson[7]};
                else
                    larson <= {larson[0], larson[7:1]};
            end

            // --- BUTTON EDGE-TRIGGERED SCROLL ---
            s1_prev <= keys[7]; // S1 (adjust index if needed)
            s2_prev <= keys[6]; // S2 (adjust index if needed)

            // Decrement cooldown timer if active
            if (scroll_cooldown > 0) begin
                scroll_cooldown <= scroll_cooldown - 1;
            end 
            else begin
                if (keys[7] && !s1_prev) begin
                    s1_prev <= 1'b1;
                    if (scroll_idx < 4'd11) begin
                        scroll_idx <= scroll_idx + 1;
                    end
                    scroll_cooldown <= 24'd12_000_000; // Reset cooldown on press
                end 
                else if (!keys[7]) begin
                    s1_prev <= 1'b0; // Clear edge trigger when button released
                end

                if (keys[6] && !s2_prev) begin
                    s2_prev <= 1'b1;
                    if (scroll_idx > 1) begin
                        scroll_idx <= scroll_idx - 1;
                    end
                    scroll_cooldown <= 24'd12_000_000; // Reset cooldown on press
                end 
                else if (!keys[6]) begin
                    s2_prev <= 1'b0; // Clear edge trigger when button released
                end

                // AUTO-SCROLL (Executes ONLY when timer expires AND no buttons are held)
                if (scroll_cooldown == 0 && !keys[7] && !keys[6]) begin
                    if (scroll_dir == 0) begin
                        scroll_idx <= scroll_idx + 1;
                        scroll_dir <= 1;
                    end else begin
                        scroll_idx <= scroll_idx - 1;
                        scroll_dir <= 0;
                    end
                    scroll_cooldown <= 24'd10_000_000; // Cooldown for auto-step
                end
            end

            if (counter[0] && ~busy) begin
                case (instruction_step)
                    // *** KEYS ***
                    1:  {tm_cs, tm_rw}     <= {LOW, HIGH};
                    2:  {tm_latch, tm_out} <= {HIGH, C_READ}; // read mode
                    3:  {tm_latch, tm_rw}  <= {HIGH, LOW};

                    // read back keys S1 - S8
                    4:  {keys[7], keys[3]} <= {tm_in[0], tm_in[4]};
                    5:  {tm_latch}         <= {HIGH};
                    6:  {keys[6], keys[2]} <= {tm_in[0], tm_in[4]};
                    7:  {tm_latch}         <= {HIGH};
                    8:  {keys[5], keys[1]} <= {tm_in[0], tm_in[4]};
                    9:  {tm_latch}         <= {HIGH};
                    10: {keys[4], keys[0]} <= {tm_in[0], tm_in[4]};
                    11: {tm_cs}            <= {HIGH};

                    // *** DISPLAY ***
                    12: {tm_cs, tm_rw}     <= {LOW, HIGH};
                    13: {tm_latch, tm_out} <= {HIGH, C_WRITE}; // write mode
                    14: {tm_cs}            <= {HIGH};

                    15: {tm_cs, tm_rw}     <= {LOW, HIGH};
                    16: {tm_latch, tm_out} <= {HIGH, C_ADDR}; // set addr 0 pos

                    // Using scroll_idx offsets
                    17: display_digit(3'd7, text_mem[scroll_idx + 3'd0]); // Digit 1
                    18: display_led(3'd0);        // LED 1

                    19: display_digit(3'd6, text_mem[scroll_idx + 3'd1]); // Digit 2
                    20: display_led(3'd1);        // LED 2

                    21: display_digit(3'd5, text_mem[scroll_idx + 3'd2]); // Digit 3
                    22: display_led(3'd2);        // LED 3

                    23: display_digit(3'd4, text_mem[scroll_idx + 3'd3]); // Digit 4
                    24: display_led(3'd3);        // LED 4

                    25: display_digit(3'd3, text_mem[scroll_idx + 3'd4]); // Digit 5
                    26: display_led(3'd4);        // LED 5

                    27: display_digit(3'd2, text_mem[scroll_idx + 3'd5]); // Digit 6
                    28: display_led(3'd5);        // LED 6

                    29: display_digit(3'd1, text_mem[scroll_idx + 3'd6]); // Digit 7
                    30: display_led(3'd6);        // LED 7

                    31: display_digit(3'd0, text_mem[scroll_idx + 3'd7]); // Digit 8
                    32: display_led(3'd7);        // LED 8

                    33: {tm_cs}            <= {HIGH};

                    34: {tm_cs, tm_rw}     <= {LOW, HIGH};
                    35: {tm_latch, tm_out} <= {HIGH, C_DISP}; // display on, full bright
                    36: {tm_cs, instruction_step} <= {HIGH, 6'b0};

                endcase

                instruction_step <= instruction_step + 1;

            end else if (busy) begin
                tm_latch <= LOW;
            end

            counter <= counter + 1;
        end
    end
endmodule