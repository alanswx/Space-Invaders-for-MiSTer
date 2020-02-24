//============================================================================
//  Arcade: Space Invaders
//
//  Port to MiSTer Dave Wood (oldgit)
//  April 2019 
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================
module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned
	
	
		// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT

);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : (status[2] | landscape) ? 8'd4 : 8'd3;
assign HDMI_ARY = status[1] ? 8'd9  : (status[2] | landscape) ? 8'd3 : 8'd4;



`include "build_id.v" 
localparam CONF_STR = {
	"A.INVADERS;;",
	"-;",
	"H0O1,Aspect Ratio,Original,Wide;", 
	"H1H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",  
	"-;",
	"DIP;",
	"-;",
	"O9A,Colours,Original,colour1,colour2,colour3;",
	"-;",
	"R0,Reset;",
	"J1,Fire 1,Fire 2,Fire 3,Fire 4,Start 1P,Start 2P,Coin;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_48, clk_sys, clk_6, clk_12, clk_10;



pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_48),
	.outclk_1(clk_sys),// 24MHz
	.outclk_2(clk_12),
	.outclk_3(clk_10),
	.outclk_4(clk_6)
);

reg ce_12, ce_6, ce_3, ce_1p5;
always @(posedge clk_sys) begin
	reg [3:0] div;
	
	div <= div + 1'd1;
	ce_12  <= !div[0:0];
	ce_6   <= !div[1:0];
	ce_3   <= !div[2:0];
	ce_1p5 <= !div[3:0];
end

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_index;

reg	[7:0] machine_info;



wire [10:0] ps2_key;

wire [15:0] joy1, joy2;
wire [15:0] joya;

wire [21:0] gamma_bus;



hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

   .buttons(buttons),
   .status(status),
   .status_menumask({landscape,direct_video}),
   .forced_scandoubler(forced_scandoubler),
   .gamma_bus(gamma_bus),
   .direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),
	
	.joystick_0(joy1),
	.joystick_1(joy2),
	.joystick_analog_0(joya),
	.ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'h75: btn_up            <= pressed; // up
			'h72: btn_down          <= pressed; // down
			'h6B: btn_left          <= pressed; // left
			'h74: btn_right         <= pressed; // right
			'h76: btn_coin1         <= pressed; // ESC
			'h05: btn_start1        <= pressed; // F1
			'h06: btn_start2        <= pressed; // F2
			'h14: btn_fireA         <= pressed; // lctrl
			'h11: btn_fireB         <= pressed; // lalt
			'h29: btn_fireC         <= pressed; // Space
			'h12: btn_fireD         <= pressed; // l-shift

			// JPAC/IPAC/MAME Style Codes
			'h16: btn_start1        <= pressed; // 1
			'h1E: btn_start2        <= pressed; // 2
			'h2E: btn_coin1         <= pressed; // 5
			'h36: btn_coin2         <= pressed; // 6
			'h2D: btn_up2           <= pressed; // R
			'h2B: btn_down2         <= pressed; // F
			'h23: btn_left2         <= pressed; // D
			'h34: btn_right2        <= pressed; // G
			'h1C: btn_fire2A        <= pressed; // A
			'h1B: btn_fire2B        <= pressed; // S
			'h21: btn_fire2C        <= pressed; // Q
			'h1D: btn_fire2D        <= pressed; // W
		endcase
	end
end

always @(posedge clk_sys) begin
	case(status[10:9])
		2'b00: begin
					ms_col	<= 3'b100;
					bs_col	<= 3'b010;
					sh_col	<= 3'b010;
					sc1_col	<= 3'b111;
					sc2_col	<= 3'b111;
					mn_col	<= 3'b111;
				 end
		2'b01: begin
					ms_col	<= 3'b100;
					bs_col	<= 3'b010;
					sh_col	<= 3'b110;
					sc1_col	<= 3'b011;
					sc2_col	<= 3'b101;
					mn_col	<= 3'b111;
				 end
		2'b10: begin
					ms_col	<= 3'b110;
					bs_col	<= 3'b001;
					sh_col	<= 3'b101;
					sc1_col	<= 3'b100;
					sc2_col	<= 3'b100;
					mn_col	<= 3'b111;
				 end
		2'b11: begin
					ms_col	<= 3'b101;
					bs_col	<= 3'b011;
					sh_col	<= 3'b001;
					sc1_col	<= 3'b110;
					sc2_col	<= 3'b100;
					mn_col	<= 3'b010;
				 end
	endcase
end


reg btn_left   = 0;
reg btn_right  = 0;
reg btn_down   = 0;
reg btn_up     = 0;
reg btn_fireA  = 0;
reg btn_fireB  = 0;
reg btn_fireC  = 0;
reg btn_fireD  = 0;
reg btn_coin1  = 0;
reg btn_coin2  = 0;
reg btn_start1 = 0;
reg btn_start2 = 0;
reg btn_up2    = 0;
reg btn_down2  = 0;
reg btn_left2  = 0;
reg btn_right2 = 0;
reg btn_fire2A = 0;
reg btn_fire2B = 0;
reg btn_fire2C = 0;
reg btn_fire2D = 0;

wire m_start1  = btn_start1 | joy[8];
wire m_start2  = btn_start2 | joy[9];
wire m_coin1   = btn_coin1  | btn_coin2 | joy[10];

wire m_right1  = btn_right  | joy1[0];
wire m_left1   = btn_left   | joy1[1];
wire m_down1   = btn_down   | joy1[2];
wire m_up1     = btn_up     | joy1[3];
wire m_fire1a  = btn_fireA  | joy1[4];
wire m_fire1b  = btn_fireB  | joy1[5];
wire m_fire1c  = btn_fireC  | joy1[6];
wire m_fire1d  = btn_fireD  | joy1[7];

wire m_right2  = btn_right2 | joy2[0];
wire m_left2   = btn_left2  | joy2[1];
wire m_down2   = btn_down2  | joy2[2];
wire m_up2     = btn_up2    | joy2[3];
wire m_fire2a  = btn_fire2A | joy2[4];
wire m_fire2b  = btn_fire2B | joy2[5];
wire m_fire2c  = btn_fire2C | joy2[6];
wire m_fire2d  = btn_fire2D | joy2[7];

wire m_right   = m_right1 | m_right2;
wire m_left    = m_left1  | m_left2; 
wire m_down    = m_down1  | m_down2; 
wire m_up      = m_up1    | m_up2;   
wire m_fire_a  = m_fire1a | m_fire2a;
wire m_fire_b  = m_fire1b | m_fire2b;
wire m_fire_c  = m_fire1c | m_fire2c;
wire m_fire_d  = m_fire1d | m_fire2d;

wire [2:0] ms_col;
wire [2:0] bs_col;
wire [2:0] sh_col;
wire [2:0] sc1_col;
wire [2:0] sc2_col;
wire [2:0] mn_col;

wire [15:0] joy = joy1 | joy2;


///////////////////////////////////////////////////////////////////


wire hblank, vblank;
wire hs, vs;
wire [3:0] r,g,b;
wire no_rotate = status[2] | direct_video | landscape;

arcade_video #(260,224,12) arcade_video
(
	.*,

	.clk_video(clk_48),
	.ce_pix(ce_6),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.rotate_ccw(ccw),
   .fx(status[5:3])

);


wire [7:0] audio;
assign AUDIO_L = {audio, audio};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;
wire reset;
assign reset = (RESET | status[0] | buttons[1] | ioctl_download);

wire [7:0] GDB0;
wire [7:0] GDB1;
wire [7:0] GDB2;


localparam mod_spaceinvaders = 0;
localparam mod_shuffleboard  = 1;
localparam mod_vortex        = 2;
localparam mod_280zap        = 3;
localparam mod_blueshark     = 4;
localparam mod_boothill      = 5;
localparam mod_lunarrescue   = 6;
localparam mod_ozmawars      = 7;
localparam mod_spacelaser    = 8;
localparam mod_spacewalk     = 9;
reg [7:0] mod = 0;
always @(posedge clk_sys) if (ioctl_wr & (ioctl_index==1)) mod <= ioctl_dout;




reg [7:0] sw[8];
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;

reg landscape;
reg ccw;
always @(*) begin

        landscape <= 1;
		  ccw<=0;
        GDB0 <= 8'hFF;
        GDB1 <= 8'hFF;
        GDB2 <= 8'hFF;

        case (mod) 
		  mod_spaceinvaders:
		  begin
			 landscape<=0;
          ccw<=1;
          GDB0 <= sw[0] | { 1'b0, m_right,m_left,m_fire_a,1'b1,1'b0, 1'b0,1'b0};
          GDB1 <= sw[1] | { 1'b1, m_right,m_left,m_fire_a,1'b1,m_start1, m_start2, m_coin1 };
          GDB2 <= sw[2] | { 1'b1, m_right,m_left,m_fire_a,1'b0,1'b0, 1'b0, 1'b0 };
        end
        mod_shuffleboard:
		  begin
 			 landscape<=0;
          ccw<=0;
          GDB0 <= sw[0] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b0,1'b0, 1'b0,1'b0};
          GDB1 <= sw[1] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b0,m_start1, m_start2, m_coin1 };
          GDB2 <= sw[2] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b1,1'b1, 1'b0, 1'b0 };
        end
		  mod_vortex:
		  begin
			//GDB0 -- all FF
			 GDB1 <= sw[1] | ~{ 1'b0, m_right1,m_left1,m_fire1a,1'b0,m_start1, m_start2, m_coin1 };
          GDB2 <= sw[2] | ~{ 1'b1, m_right2,m_left2,m_fire2a,1'b1,1'b1, 1'b1, 1'b1 };
	
		  end
		  mod_280zap:
		  begin
 			 landscape<=1;
         // ccw<=1;
		     GDB0 <= sw[0] | ~{ m_start1, m_coin1,1'b0,m_fire_a,1'b0,1'b1, 1'b1,1'b1};
           GDB1 <= sw[1] | ~{ 1'b0, 1'b1,1'b1,1'b1,1'b1,1'b1, 1'b1, 1'b1 };
           GDB2 <= sw[2] | ~{ 1'b1, 1'b1,1'b0,1'b0,1'b0,1'b0, 1'b1, 1'b1 };

		  end
		  mod_blueshark:
		  begin
		     GDB0 <= sw[0] | ~{ 1'b0, 1'b0,1'b0,1'b0,1'b0,1'b0, 1'b0,1'b0};
		     GDB1 <= sw[1] | ~{ 1'b1, 1'b0,1'b0,1'b0,1'b0,1'b0, 1'b0,1'b0};
		     GDB2 <= sw[2] | ~{ 1'b0, 1'b0,1'b0,1'b0,1'b0,1'b0,m_coin1 ,m_fire_a};
		  end
		  mod_boothill:
		  begin
          GDB0 <= sw[0] | ~{ m_fire1a, 1'b1,1'b0,1'b1,m_right1,m_left1,m_down1,m_up1};
          GDB1 <= sw[1] | ~{ m_fire2a, 1'b1,1'b0,1'b1,m_right2,m_left2,m_down2,m_up2};
          GDB2 <= sw[2] | ~{ m_start1, m_coin1,m_start1,1'b1,1'b0,1'b0, 1'b1, 1'b0 };
		  end
		  mod_lunarrescue:
		  begin
		  	 landscape<=0;
          ccw<=1;
          GDB0 <= sw[0] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b0,1'b1, 1'b1,1'b1};
          GDB1 <= sw[1] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b0,m_start1, m_start2, m_coin1 };
          GDB2 <= sw[2] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b1,1'b1, 1'b0, 1'b0 };
		  end
        mod_ozmawars:
		  begin
 		  	 landscape<=0;
          ccw<=1;
         // GDB0 <= sw[0] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b0,1'b1, 1'b1,1'b1};
          GDB1 <= sw[1] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b0,m_start1, m_start2, ~m_coin1 };
          GDB2 <= sw[2] | ~{ m_start1, m_coin1,m_start2,1'b0,1'b0,1'b0, 1'b0, 1'b0 };

		  end
		  mod_spacelaser:
		  begin
  		  	 landscape<=0;
          ccw<=1;
        // GDB0 <= sw[0] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b0,1'b1, 1'b1,1'b1};
          GDB1 <= sw[1] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b0,m_start1, m_start2, m_coin1 };
          GDB2 <= sw[2] | ~{ 1'b0, m_right,m_left,m_fire_a,1'b1,1'b1, 1'b1, 1'b1 };
		  end
		  mod_spacewalk:
		  begin
			GDB0 <= 8'b0;
         GDB1 <= sw[1] | ~{ 1'b0, 1'b0,1'b0,1'b0,m_start1, m_start2, m_coin1 , 1'b0};
			GDB2 <= 8'b0;
		  end
		  endcase
end

invaders_top invaders_top
(

	.Clk(clk_10),
	.Clk_mem(clk_sys),
	.clk_vid(clk_6),

	.I_RESET(reset),

	.GDB0(GDB0),
	.GDB1(GDB1),
	.GDB2(GDB2),
	

	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr&(ioctl_index==0)),

	.r(r),
	.g(g),
	.b(b),
	.hblnk(hblank),
	.vblnk(vblank),
	.hs(hs),
	.vs(vs),
	
	.audio_out(audio),
	.ms_col(ms_col),
	.bs_col(bs_col),
	.sh_col(sh_col),
	.sc1_col(sc1_col),
	.sc2_col(sc2_col),
	.mn_col(mn_col)
	

);

endmodule
