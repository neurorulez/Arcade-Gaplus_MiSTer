//============================================================================
//  Arcade: Gaplus
//
//  Original implimentation and port to MiSTer by MiSTer-X 2019
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

assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd4 : 8'd3;
assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd3 : 8'd4;

`include "build_id.v" 
localparam CONF_STR = {
	"A.GAPLUS;;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"O8A,Difficulty,Standard,1-Easiest,2,3,4,5,6,7-Hardest;",
	"OBC,Life,3,2,4,5;",
	"ODF,Bonus Life,M0,M1,M2,M3,M4,M5,M6,M7;",
	"OG,Round Advance,Off,On;",
	"OH,Demo Sound,On,Off;",
	//"OJ,Cabinet,Upright,Cocktail;",
	"-;",
	"OI,Service Mode,Off,On;",
	"-;",
	"R0,Reset;",
	"J1,Fire,Start 1P,Start 2P,Coin;",
	"V,v",`BUILD_DATE
};


////////////////////   CLOCKS   ///////////////////

wire clk_48M;
wire clk_hdmi = clk_48M;
wire clk_sys = clk_48M;

pll pll
(
	.rst(0),
	.refclk(CLK_50M),
	.outclk_0(clk_48M)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joystk1 = joy1a | joy2a;
wire [15:0] joystk2 = joy1a | joy2a;
wire [15:0] joy1a;
wire [15:0] joy2a;
wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask({direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joy1a),
	.joystick_1(joy2a),
	.ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_trig1       <= pressed; // space
			'h014: btn_trig1       <= pressed; // ctrl
			'h005: btn_one_player  <= pressed; // F1
			'h006: btn_two_players <= pressed; // F2

			// JPAC/IPAC/MAME Style Codes
			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			'h01C: btn_trig1_2     <= pressed; // A
			'h01B: btn_trig1_2     <= pressed; // S
		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_trig1 = 0;
reg btn_one_player  = 0;
reg btn_two_players = 0;

reg btn_start_1 = 0;
reg btn_start_2 = 0;
reg btn_coin_1  = 0;
reg btn_coin_2  = 0;
reg btn_up_2    = 0;
reg btn_down_2  = 0;
reg btn_left_2  = 0;
reg btn_right_2 = 0;
reg btn_trig1_2  = 0;


//wire bCabinet  = status[19];
wire bCabinet  = 1'b0;	// (upright only)

wire m_up2     = btn_up_2    | joystk2[3];
wire m_down2   = btn_down_2  | joystk2[2];
wire m_left2   = btn_left_2  | joystk2[1];
wire m_right2  = btn_right_2 | joystk2[0];
wire m_trig21  = btn_trig1_2 | joystk2[4];

wire m_start1  = btn_one_player  | joystk1[5] | joystk2[5] | btn_start_1;
wire m_start2  = btn_two_players | joystk1[6] | joystk2[6] | btn_start_2;

wire m_up1     = btn_up      | joystk1[3] | (bCabinet ? 1'b0 : m_up2);
wire m_down1   = btn_down    | joystk1[2] | (bCabinet ? 1'b0 : m_down2);
wire m_left1   = btn_left    | joystk1[1] | (bCabinet ? 1'b0 : m_left2);
wire m_right1  = btn_right   | joystk1[0] | (bCabinet ? 1'b0 : m_right2);
wire m_trig11  = btn_trig1   | joystk1[4] | (bCabinet ? 1'b0 : m_trig21);

wire m_coin1   = btn_one_player | btn_coin_1 | joystk1[7];
wire m_coin2   = btn_two_players| btn_coin_2 | joystk2[7];

wire no_rotate = status[2] & ~direct_video;

///////////////////////////////////////////////////

wire hblank, vblank;
wire ce_vid;
wire hs, vs;
wire [3:0] r,g,b;

reg ce_pix;
always @(posedge clk_hdmi) begin
	reg old_clk;
	old_clk <= ce_vid;
	ce_pix  <= old_clk & ~ce_vid;
end

arcade_rotate_fx #(288,224,12) arcade_video
(
	.*,

	.clk_video(clk_hdmi),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(~hs),
	.VSync(~vs),

	.rotate_ccw(0),
	.fx(status[5:3])
);

wire			PCLK;
wire  [8:0] HPOS,VPOS;
wire [11:0] POUT;
HVGEN hvgen
(
	.HPOS(HPOS),.VPOS(VPOS),.PCLK(PCLK),.iRGB(POUT),
	.oRGB({b,g,r}),.HBLK(hblank),.VBLK(vblank),.HSYN(hs),.VSYN(vs)
);
assign ce_vid = PCLK;


wire [15:0] AOUT;
assign AUDIO_L = AOUT;
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0; // unsigned PCM


///////////////////////////////////////////////////

wire iRST = RESET | status[0] | buttons[1] | ioctl_download;

wire  [1:0] COIA = 2'b00;				// 1coin/1credit
wire  [1:0] COIB = 2'b00;				// 1coin/1credit

wire	[2:0]	DIFF = status[10:8];
wire  [1:0] LIFE = status[12:11];
wire  [2:0] EXTD = status[15:13]; 
wire			ADVN = status[16];
wire			DEMO = status[17];
wire        SERV = status[18];		// Service-SW
wire			CABI = bCabinet;

wire  [7:0] DSW0 = {LIFE,COIA,DEMO,1'b0,COIB};
wire  [7:0] DSW1 = {SERV,DIFF,ADVN,EXTD};
wire	[7:0] DSW2 = {6'h0,~SERV,~CABI};

wire  [4:0]	INP0 = { m_trig11, m_left1, m_down1, m_right1, m_up1 };
wire  [4:0]	INP1 = { m_trig21, m_left2, m_down2, m_right2, m_up2 };
wire  [2:0] INP2 = { (m_coin1|m_coin2), m_start2, m_start1 };


wire  [7:0] oSND;

FPGA_GAPLUS GameCore ( 
	.RESET(iRST),.MCLK(clk_48M),
	.PH(HPOS),.PV(VPOS),.PCLK(PCLK),.POUT(POUT),
	.SOUT(oSND),

	.INP0(INP0),.INP1(INP1),.INP2(INP2),
	.DSW0(DSW0),.DSW1(DSW1),.DSW2(DSW2),
	
	.ROMCL(clk_sys),.ROMAD(ioctl_addr),.ROMDT(ioctl_dout),.ROMEN(ioctl_wr)
);

assign AOUT = {oSND,8'h0};

endmodule


module HVGEN
(
	output  [8:0]		HPOS,
	output  [8:0]		VPOS,
	input 				PCLK,
	input	 [11:0]		iRGB,

	output reg [11:0]	oRGB,
	output reg			HBLK = 1,
	output reg			VBLK = 1,
	output reg			HSYN = 1,
	output reg			VSYN = 1
);

reg [8:0] hcnt = 0;
reg [8:0] vcnt = 0;

assign HPOS = hcnt;
assign VPOS = vcnt;

always @(posedge PCLK) begin
	case (hcnt)
		  0: begin HBLK <= 0; hcnt <= hcnt+1; end
		289: begin HBLK <= 1; hcnt <= hcnt+1; end
		311: begin HSYN <= 0; hcnt <= hcnt+1; end
		342: begin HSYN <= 1; hcnt <= 471;    end
		511: begin hcnt <= 0;
			case (vcnt)
				223: begin VBLK <= 1; vcnt <= vcnt+1; end
				235: begin VSYN <= 0; vcnt <= vcnt+1; end
				242: begin VSYN <= 1; vcnt <= 492;	  end
				511: begin VBLK <= 0; vcnt <= 0;		  end
				default: vcnt <= vcnt+1;
			endcase
		end
		default: hcnt <= hcnt+1;
	endcase
	oRGB <= (HBLK|VBLK) ? 12'h0 : iRGB;
end

endmodule

