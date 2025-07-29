/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Top-level module for Tiny Tapeout
module tt_um_mips_processor (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // Convert reset polarity (TT uses active low, your design uses active high)
  wire rst = ~rst_n;
  
  // Input controls
  wire debug_mode = ui_in[0];      // Debug mode enable
  wire [2:0] debug_sel = ui_in[3:1]; // Debug output selection
  wire step_mode = ui_in[4];       // Single step mode
  wire step_pulse = ui_in[5];      // Step pulse in step mode
  // ui_in[7:6] reserved for future use
  
  // Clock generation for step mode
  wire proc_clk = step_mode ? (step_pulse & clk) : clk;
  
  // Internal processor signals
  wire [15:0] alu_out;
  wire [3:0] alu_op;
  wire [15:0] read_data1, read_data2;
  wire [15:0] sign_ext_immediate;
  wire [3:0] rs, rt, rd, write_reg_out;
  wire [15:0] pc_out;
  wire [15:0] instruction;
  
  // Instantiate the MIPS processor
  mips_single_cycle cpu (
    .clk(proc_clk),
    .rst(rst),
    .ALU_out(alu_out),
    .ALUOp(alu_op),
    .Read_data1(read_data1),
    .Read_data2(read_data2),
    .sign_ext_immediate(sign_ext_immediate),
    .rs(rs),
    .rt(rt),
    .rd(rd),
    .Write_reg_out(write_reg_out),
    .pc_out(pc_out),
    .instruction(instruction)
  );
  
  // Debug output multiplexer
  reg [15:0] debug_data;
  always @(*) begin
    case (debug_sel)
      3'b000: debug_data = pc_out;
      3'b001: debug_data = instruction;
      3'b010: debug_data = alu_out;
      3'b011: debug_data = read_data1;
      3'b100: debug_data = read_data2;
      3'b101: debug_data = sign_ext_immediate;
      3'b110: debug_data = {12'b0, rs};
      3'b111: debug_data = {12'b0, write_reg_out};
      default: debug_data = 16'h0000;
    endcase
  end
  
  // Output assignments
  assign uo_out = debug_mode ? debug_data[7:0] : {4'b0, alu_op};
  
  // Use bidirectional IOs for additional outputs
  assign uio_out = debug_mode ? debug_data[15:8] : alu_out[7:0];
  assign uio_oe = 8'hFF; // All bidirectional pins as outputs
  
  // Unused inputs
  wire _unused = &{ena, uio_in, 1'b0};

endmodule

// Program Counter
module PC(
  input clk,
  input rst,
  input jump,
  input [15:0] jump_address,
  output wire [15:0] pc_out
);

  reg [15:0] p_c;
  wire [15:0] pc_next;

  assign pc_next = (jump) ? jump_address : (p_c + 2);

  always @(posedge clk or posedge rst) begin
    if (rst)
      p_c <= 0;
    else if (p_c >= 16'd30)  // wrap at last instruction (15*2 = 30)
      p_c <= 0;
    else
      p_c <= pc_next;
  end

  assign pc_out = p_c;

endmodule

// Instruction Memory
module instruction_memory(
  input [15:0] p_in,
  output wire [15:0] instruction
);
  reg [15:0] instruction1;
  reg [15:0] rom [15:0];
  initial begin
    rom[0]  = 16'b0000_0001_0010_0011;  // ADD
    rom[1]  = 16'b0001_0010_0011_0100;  // SUB
    rom[2]  = 16'b0010_0011_0100_0101;  // ADDI
    rom[3]  = 16'b0011_0100_0101_0011;  // LW
    rom[4]  = 16'b0100_0101_0100_0011;  // SW
    rom[5]  = 16'b0110_0100_0011_0011;  // XOR
    rom[6]  = 16'b0111_0000_0000_0011;  // OR
    rom[7]  = 16'b0010_0010_0010_1111;  // ADDI
    rom[8]  = 16'b0000_0001_0001_0001;  // ADD
    rom[9]  = 16'b0001_0011_0001_0000;  // SUB
    rom[10] = 16'b0011_0001_0010_0100;  // LW
    rom[11] = 16'b0100_0010_0011_0100;  // SW
    rom[12] = 16'b0010_0011_0000_0001;  // ADDI
    rom[13] = 16'b0001_0001_0000_0001;  // SUB
    rom[14] = 16'b0111_0000_0101_0100;  // OR
    rom[15] = 16'b0101_0000_0000_0000;  // JUMP (to 0)
  end
  always @(*) begin
    if ((p_in >> 1) < 16)
      instruction1 = rom[p_in >> 1];
    else
      instruction1 = 16'b0000_0000_0000_0000;
  end
  assign instruction = instruction1;
endmodule

// Decoder
module decode(
  input [15:0] instruction_in,
  output reg [3:0] rs, rt, opcode, rd, im,
  output reg [11:0] jump
);
always @(*) begin
  // Default values
  rs = 4'b0000;
  rt = 4'b0000;
  rd = 4'b0000;
  im = 4'b0000;
  jump = 12'b000000000000;
  opcode = instruction_in[15:12];   

  case(opcode)
    4'b0000: begin  // ADD
      rd = instruction_in[11:8];
      rs = instruction_in[7:4];
      rt = instruction_in[3:0];
    end

    4'b0001: begin  // SUB
      rd = instruction_in[11:8];
      rs = instruction_in[7:4];
      rt = instruction_in[3:0];
    end

    4'b0010: begin  // ADDI
      rd = instruction_in[11:8];
      rs = instruction_in[7:4];
      im = instruction_in[3:0];
    end

    4'b0011: begin  // LW
      rd = instruction_in[11:8];
      rs = instruction_in[7:4];
      im = instruction_in[3:0];
    end

    4'b0100: begin  // SW
      rt = instruction_in[11:8];
      rs = instruction_in[7:4];
      im = instruction_in[3:0];
    end

    4'b0101: begin  // JUMP
      jump = instruction_in[11:0];
    end

    4'b0110: begin  // XOR
      rd = instruction_in[11:8];
      rs = instruction_in[7:4];
      rt = instruction_in[3:0];
    end

    4'b0111: begin  // OR
      rd = instruction_in[11:8];
      rs = instruction_in[7:4];
      rt = instruction_in[3:0];
    end
  endcase
end
endmodule

// Control Unit
module control_unit(
    input [3:0] opcode,
    output reg RegDst, ALUsrc, MemtoReg, MemWrite, MemRead, RegWrite, jump,
    output reg [3:0] ALUOp
);

  always @(*) begin
    case (opcode)
      4'b0000: begin  // ADD
        RegDst = 1; ALUsrc = 0; MemtoReg = 0; RegWrite = 1;
        MemWrite = 0; MemRead = 0; jump = 0; ALUOp = 4'b0000;
      end

      4'b0001: begin  // SUB
        RegDst = 1; ALUsrc = 0; MemtoReg = 0; RegWrite = 1;
        MemWrite = 0; MemRead = 0; jump = 0; ALUOp = 4'b0001;
      end

      4'b0010: begin  // ADDI
        RegDst = 0; ALUsrc = 1; MemtoReg = 0; RegWrite = 1;
        MemWrite = 0; MemRead = 0; jump = 0; ALUOp = 4'b0010;
      end

      4'b0011: begin  // LW
        RegDst = 0; ALUsrc = 1; MemtoReg = 1; RegWrite = 1;
        MemWrite = 0; MemRead = 1; jump = 0; ALUOp = 4'b0011;
      end

      4'b0100: begin  // SW
        RegDst = 0; ALUsrc = 1; MemtoReg = 0; RegWrite = 0;
        MemWrite = 1; MemRead = 0; jump = 0; ALUOp = 4'b0100;
      end

      4'b0101: begin  // JUMP
        RegDst = 0; ALUsrc = 0; MemtoReg = 0; RegWrite = 0;
        MemWrite = 0; MemRead = 0; jump = 1; ALUOp = 4'b0000;
      end

      4'b0110: begin  // XOR
        RegDst = 1; ALUsrc = 0; MemtoReg = 0; RegWrite = 1;
        MemWrite = 0; MemRead = 0; jump = 0; ALUOp = 4'b0110;
      end

      4'b0111: begin  // OR
        RegDst = 1; ALUsrc = 0; MemtoReg = 0; RegWrite = 1;
        MemWrite = 0; MemRead = 0; jump = 0; ALUOp = 4'b0111;
      end

      default: begin
        RegDst = 0; ALUsrc = 0; MemtoReg = 0; RegWrite = 0;
        MemWrite = 0; MemRead = 0; jump = 0; ALUOp = 4'b0000;
      end
    endcase
  end
endmodule

// ALU
module ALU(
    input [15:0] s1,
    input [15:0] s2,
    input ALUsrc,
    input [3:0] ALUop,
    input [15:0] im,
    output reg [15:0] ALU_out
);

  wire [15:0] operand2;
  assign operand2 = ALUsrc ? im : s2;

  always @(*) begin
    case (ALUop)
      4'b0000: ALU_out = s1 + operand2;      // ADD
      4'b0001: ALU_out = s1 - operand2;      // SUB
      4'b0010: ALU_out = s1 + operand2;      // ADDI
      4'b0011: ALU_out = s1 + operand2;      // LW (addr calc)
      4'b0100: ALU_out = s1 + operand2;      // SW (addr calc)
      4'b0110: ALU_out = s1 ^ operand2;      // XOR
      4'b0111: ALU_out = s1 | operand2;      // OR
      default: ALU_out = 16'hDEAD;           // Invalid ALUOp
    endcase
  end
endmodule

// Register File
module register(
    input clk,
    input RegWrite,
    input [3:0] rs,
    input [3:0] rt,
    input [3:0] Write_reg,
    input [15:0] Write_data,
    output reg [15:0] Read_data1,
    output reg [15:0] Read_data2
);

    reg [15:0] register_mem [15:0];
    initial begin
        register_mem[0]  = 16'd0;     // R0 should be 0
        register_mem[1]  = 16'd20;
        register_mem[2]  = 16'd30;
        register_mem[3]  = 16'd50;
        register_mem[4]  = 16'd40;
        register_mem[5]  = 16'd60;
        register_mem[6]  = 16'd70;
        register_mem[7]  = 16'd80;
        register_mem[8]  = 16'd90;
        register_mem[9]  = 16'd100;
        register_mem[10] = 16'd110;
        register_mem[11] = 16'd120;
        register_mem[12] = 16'd130;
        register_mem[13] = 16'd140;
        register_mem[14] = 16'd150;
        register_mem[15] = 16'd160;
    end

    // Read ports (combinational)
    always @(*) begin
        Read_data1 = register_mem[rs];
        Read_data2 = register_mem[rt];
    end

    // Write port (synchronous, prevent writing to register 0)
    always @(posedge clk) begin
        if (RegWrite && Write_reg != 4'b0000)
            register_mem[Write_reg] <= Write_data;
    end
endmodule

// Data Memory
module data_memory(
    input clk,
    input mem_write,
    input mem_read,
    input [7:0] address,
    input [15:0] write_data,
    output reg [15:0] read_data
);

    reg [15:0] memory [0:255];

    // Initialize some RAM locations
    initial begin
        memory[3]   = 123;
        memory[14]  = 34;
        memory[43]  = 0;
        memory[54]  = 0;
        memory[58]  = 0;
        memory[63]  = 123;
        memory[150] = 0;
        memory[154] = 10;
    end

    always @(posedge clk) begin
        if (mem_write) begin
            memory[address] <= write_data;
        end

        if (mem_read) begin
            read_data <= memory[address];
        end else begin
            read_data <= 16'b0;
        end
    end
endmodule

// Modified MIPS Single Cycle (added pc_out and instruction outputs)
module mips_single_cycle(
    input clk,
    input rst,
    output wire [15:0] ALU_out,
    output wire [3:0] ALUOp,
    output wire [15:0] Read_data1,
    output wire [15:0] Read_data2,
    output wire [15:0] sign_ext_immediate,
    output wire [3:0] rs, rt, rd,
    output wire [3:0] Write_reg_out,
    output wire [15:0] pc_out,
    output wire [15:0] instruction
);

    wire [3:0] opcode, im;
    wire [11:0] jump_address;
    wire RegDst, ALUsrc, MemtoReg, MemWrite, MemRead, RegWrite, jump;
    wire [15:0] Write_data, MemOut;
    wire [3:0] Write_reg;

    // Program Counter
    PC pc_inst (
        .clk(clk),
        .rst(rst),
        .jump(jump),
        .jump_address({4'b0000, jump_address}),
        .pc_out(pc_out)
    );

    // Instruction Memory
    instruction_memory imem (
        .p_in(pc_out),
        .instruction(instruction)
    );

    // Decoder
    decode decode_inst (
        .instruction_in(instruction),
        .rs(rs),
        .rt(rt),
        .opcode(opcode),
        .rd(rd),
        .im(im),
        .jump(jump_address)
    );

    // Control Unit
    control_unit cu (
        .opcode(opcode),
        .RegDst(RegDst),
        .ALUsrc(ALUsrc),
        .MemtoReg(MemtoReg),
        .MemWrite(MemWrite),
        .MemRead(MemRead),
        .RegWrite(RegWrite),
        .jump(jump),
        .ALUOp(ALUOp)
    );

    // Register File
    register reg_file (
        .clk(clk),
        .RegWrite(RegWrite),
        .rs(rs),
        .rt(rt),
        .Write_reg(Write_reg),
        .Write_data(Write_data),
        .Read_data1(Read_data1),
        .Read_data2(Read_data2)
    );

    assign sign_ext_immediate = {{12{im[3]}}, im};

    // ALU
    ALU alu_inst (
        .s1(Read_data1),
        .s2(Read_data2),
        .ALUsrc(ALUsrc),
        .ALUop(ALUOp),
        .im(sign_ext_immediate),
        .ALU_out(ALU_out)
    );

    // Data Memory
    data_memory dm (
        .clk(clk),
        .mem_write(MemWrite),
        .mem_read(MemRead),
        .address(ALU_out[7:0]),
        .write_data(Read_data2),
        .read_data(MemOut)
    );

    assign Write_data = MemtoReg ? MemOut : ALU_out;
    assign Write_reg = RegDst ? rd : rt;
    assign Write_reg_out = Write_reg;
endmodule

`default_nettype wire
