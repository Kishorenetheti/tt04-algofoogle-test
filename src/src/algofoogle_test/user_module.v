module tt_um_algofoogle_test(
    // 8 dedicated user inputs:
    input   wire [7:0]  ui_in,

    // 8 dedicated user outputs:
    output  wire [7:0]  uo_out,

    // 8 bidirectional user IOs:
    input   wire [7:0]  uio_in,     // Input path.
    output  wire [7:0]  uio_out,    // Output path.
    output  wire [7:0]  uio_oe,     // Enable path (active high: 0=input, 1=output)

    // Control:
    input   wire        ena,        // Can be ignored for now.
    input   wire        clk,        // 25.175MHz ideal, but 25.000MHz is good enough.
    input   wire        rst_n       // Active low reset
);

    reg [63:0] counter;
    reg [63:0] alt;

    assign uo_out = { counter[63:60], counter[3:0] };

    assign uio_oe = 8'hFF;
    assign uio_out = { alt[63:60], alt[3:0] };

    always @(posedge clk) begin
        if (~rst_n) begin
            counter <= 0;
            alt <= counter;
        end else begin
            counter <= counter + 1'b1;
            alt <= alt - 1'b1;
        end
    end

endmodule
