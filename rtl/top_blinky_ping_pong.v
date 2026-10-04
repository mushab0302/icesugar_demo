module top_blinky_ping_pong (
    input clock,
    output led1, led2, led3, led4, led5
);

   // atur bits untuk mengatur kecepatan 
   localparam BITS = 22; 
   reg [BITS-1:0] counter = 0;
   reg [4:0] leds = 5'b00010;
   reg dir = 0; // 0 = shift left (1->3), 1 = shift right (3->1)

   always @(posedge clock) begin
      counter <= counter + 1;
   end

   wire tick = (counter == 0);

   always @(posedge clock) begin
      if (tick) begin
         if (dir == 0) begin
            // saat index 3, ganti arah ke 1 (shift right)
            if (leds == 5'b01000) begin
               leds <= leds >> 1;
               dir <= 1'b1;
            end else begin
               leds <= leds << 1;
            end
         end else begin
            // saat index 1, ganti arah ke 0 (shift left)
            if (leds == 5'b00010) begin
               leds <= leds << 1;
               dir <= 1'b0;
            end else begin
               leds <= leds >> 1;
            end
         end
      end
   end

   assign {led5, led4, led3, led2, led1} = leds;

endmodule