
`timescale 1ns/10ps

module  CONV(
            input		  clk,
            input		  reset,
            output		  busy,
            input		  ready,

            output [11:0] iaddr,
            input  [19:0] idata,

            output	 	  cwr,
            output [11:0] caddr_wr,
            output [19:0] cdata_wr,

            output	 	  crd,
            output [11:0] caddr_rd,
            input  [19:0] cdata_rd,

            output [ 2:0] csel
        );
//---------------------------------------
//  Bool Define
//---------------------------------------
localparam TRUE = 1'b1;
localparam FALSE = 1'b0;
//---------------------------------------
//  Image Paramter Define
//---------------------------------------
localparam IMG_NO_PADDING_BIT = 6;
localparam IMG_PADDING_BIT = IMG_NO_PADDING_BIT + 1;
//---------------------------------------
//  Image reg/wire
//---------------------------------------
reg [IMG_NO_PADDING_BIT-1:0] img_x, img_y;  //0~63
reg signed [IMG_PADDING_BIT-1:0] img_padding_x, img_padding_y; //-1~64
reg  [11:0] img_addr;
wire [19:0] img_data = idata;
assign iaddr = img_addr;
//---------------------------------------
//  Busy reg/wire
//---------------------------------------
reg busy_o;
assign busy = busy_o;
//---------------------------------------
//  Memory reg/wire
//---------------------------------------
// Memory Write
reg mem_valid_w;
reg [11:0] mem_addr_w;
reg [19:0] mem_data_w;
assign cwr = mem_valid_w;
assign caddr_wr = mem_addr_w;
assign cdata_wr = mem_data_w;
// Memory Read
reg mem_valid_r;
reg [11:0] mem_addr_r;
wire [19:0] mem_data_r;
assign crd = mem_valid_r;
assign caddr_rd = mem_addr_r;
assign mem_data_r = cdata_rd;
// Memory Select
reg [ 2:0] mem_sel;
assign csel = mem_sel;
//---------------------------------------
//  Timer reg/wire
//---------------------------------------
localparam TIMER_MAX = 9;   //0~8
localparam TIMER_BIT = $clog2(TIMER_MAX);
reg [TIMER_BIT-1 : 0] timer;
//---------------------------------------
//  Memory Paramter Define
//---------------------------------------
localparam MEM_NONE = 3'b000,   //no select
           MEM_LAYER0 = 3'b001, //layer 0 memory
           MEM_LAYER1 = 3'b011; //layer 1 memory
//---------------------------------------
//  Adder reg/wire
//---------------------------------------
reg [39:0] add_a, add_b, add_o;
//---------------------------------------
//  Multiplier reg/wire
//---------------------------------------
reg [19:0] mul_a, mul_b;
reg [39:0] mul_o;
//---------------------------------------
//  Kernel/Bias Define
//---------------------------------------
wire [19:0] kernel[0:8];
assign kernel[0] = 20'h0A89E;
assign kernel[1] = 20'h092D5;
assign kernel[2] = 20'h06D43;
assign kernel[3] = 20'h01004;
assign kernel[4] = 20'hF8F71;
assign kernel[5] = 20'hF6E54;
assign kernel[6] = 20'hFA6D7;
assign kernel[7] = 20'hFC834;
assign kernel[8] = 20'hFAC19;
wire [19:0] bias = 20'h01310;
//---------------------------------------
//  Conv flag
//---------------------------------------
reg first_state_flg;
wire next_conv_pixel_flg = (timer==10);
wire next_maxp_pixel_flg = (timer==4);
reg next_conv_pixel_flg_buf;
wire edge_flg = (img_padding_x[6] || img_padding_y[6]);
reg edge_flg_buf;
//---------------------------------------
//  FSM Paramter Define
//---------------------------------------
localparam FSM_STATE_NUM = 4,
           FSM_STATE_BIT = $clog2(FSM_STATE_NUM);
localparam FSM_IDLE     = {{FSM_STATE_BIT-2{1'b0}}, 2'd0},
           FSM_CONV     = {{FSM_STATE_BIT-2{1'b0}}, 2'd1},
           FSM_MAXP     = {{FSM_STATE_BIT-2{1'b0}}, 2'd2};
//---------------------------------------
//  FSM reg/wire
//---------------------------------------
// FSM State
reg [FSM_STATE_BIT-1 : 0] cur_state, nxt_state;
// FSM Flag
wire fsm_start_flg = (ready);
wire fsm_conv_finish_flg = (mem_addr_w=={6'd63, 6'd63} && mem_valid_w);
wire fsm_maxp_finish_flg = (mem_addr_w=={12'd1023} && mem_valid_w);
//---------------------------------------
//  FSM First State
//---------------------------------------
always @(*) begin
    case(cur_state)
        FSM_IDLE     : begin
            if(fsm_start_flg) begin
                first_state_flg = TRUE;
            end
            else begin
                first_state_flg = FALSE;
            end
        end
        FSM_CONV     : begin
            if(fsm_conv_finish_flg) begin
                first_state_flg = TRUE;
            end
            else begin
                first_state_flg = FALSE;
            end
        end
        FSM_MAXP     : begin
            if(fsm_maxp_finish_flg) begin
                first_state_flg = TRUE;
            end
            else begin
                first_state_flg = FALSE;
            end
        end
        default      : begin
            first_state_flg = FALSE;
        end
    endcase
end
//---------------------------------------
//  FSM Design
//---------------------------------------
always @(posedge clk or posedge reset) begin
    if(reset) begin
        cur_state <= FSM_IDLE;
    end
    else begin
        cur_state <= nxt_state;
    end
end
always @(*) begin
    case(cur_state)
        FSM_IDLE     : begin
            if(fsm_start_flg) begin
                nxt_state = FSM_CONV;
            end
            else begin
                nxt_state = FSM_IDLE;
            end
        end
        FSM_CONV     : begin
            if(fsm_conv_finish_flg) begin
                nxt_state = FSM_MAXP;
            end
            else begin
                nxt_state = FSM_CONV;
            end
        end
        FSM_MAXP     : begin
            if(fsm_maxp_finish_flg) begin
                nxt_state = FSM_IDLE;
            end
            else begin
                nxt_state = FSM_MAXP;
            end
        end
        default      : begin
            nxt_state = FSM_IDLE;
        end
    endcase
end
//---------------------------------------
//  busy Design
//---------------------------------------
always @(posedge clk or posedge reset) begin
    if(reset) begin
        busy_o <= FALSE;
    end
    else begin
        case(cur_state)
            FSM_IDLE     : begin
                if(fsm_start_flg) begin
                    busy_o <= TRUE;
                end
            end
            FSM_MAXP     : begin
                if(fsm_maxp_finish_flg) begin
                    busy_o <= FALSE;
                end
            end
            default      : begin
                busy_o <= busy_o;
            end
        endcase
    end
end
//---------------------------------------
//  Conv flag
//---------------------------------------
always @(posedge clk or posedge reset) begin
    if(reset) begin
        edge_flg_buf <= FALSE;
    end
    else begin
        edge_flg_buf <= edge_flg;
    end
end
//---------------------------------------
//  Image Design
//---------------------------------------
always @(*) begin
    case(cur_state)
        FSM_CONV     : begin
            if(fsm_conv_finish_flg) begin
                img_x = 0;
                img_y = 0;
            end
            else begin
                if(next_conv_pixel_flg_buf) begin
                    if(mem_addr_w[5:0]==6'd63) begin
                        img_x = 0;
                        img_y = mem_addr_w[11:6] + 6'd1;
                    end
                    else begin
                        img_x = mem_addr_w[5:0]  + 6'd1;
                        img_y = mem_addr_w[11:6];
                    end
                end
                else begin
                    img_x = mem_addr_w[5:0];
                    img_y = mem_addr_w[11:6];
                end
            end
        end
        FSM_MAXP     : begin
            img_x = img_addr[5:0];
            img_y = img_addr[11:6];
        end
        default      : begin
            img_x = 0;
            img_y = 0;
        end
    endcase

    case(cur_state)
        FSM_MAXP: begin
            img_padding_x = $signed({1'b0,img_x});
            img_padding_y = $signed({1'b0,img_y});
        end
        default: begin
            case(timer)
                0: begin
                    if(first_state_flg) begin
                        img_padding_x = $signed({1'b0,img_x}) - $signed(7'd1);
                        img_padding_y = $signed({1'b0,img_y}) - $signed(7'd1);
                    end
                    else begin
                        img_padding_x = $signed({1'b0,img_x});
                        img_padding_y = $signed({1'b0,img_y}) - $signed(7'd1);
                    end
                end
                1: begin
                    img_padding_x = $signed({1'b0,img_x}) + $signed(7'd1);
                    img_padding_y = $signed({1'b0,img_y}) - $signed(7'd1);
                end
                2: begin
                    img_padding_x = $signed({1'b0,img_x}) - $signed(7'd1);
                    img_padding_y = $signed({1'b0,img_y});
                end
                3: begin
                    img_padding_x = $signed({1'b0,img_x});
                    img_padding_y = $signed({1'b0,img_y});
                end
                4: begin
                    img_padding_x = $signed({1'b0,img_x}) + $signed(7'd1);
                    img_padding_y = $signed({1'b0,img_y});
                end
                5: begin
                    img_padding_x = $signed({1'b0,img_x}) - $signed(7'd1);
                    img_padding_y = $signed({1'b0,img_y}) + $signed(7'd1);
                end
                6: begin
                    img_padding_x = $signed({1'b0,img_x});
                    img_padding_y = $signed({1'b0,img_y}) + $signed(7'd1);
                end
                7: begin
                    img_padding_x = $signed({1'b0,img_x}) + $signed(7'd1);
                    img_padding_y = $signed({1'b0,img_y}) + $signed(7'd1);
                end
                default : begin
                    img_padding_x = $signed({1'b0,img_x}) - $signed(7'd1);
                    img_padding_y = $signed({1'b0,img_y}) - $signed(7'd1);
                end
            endcase
        end
    endcase
end
always @(posedge clk or posedge reset) begin
    if(reset) begin
        img_addr <= 12'd0;
    end
    else begin
        case(cur_state)
            FSM_IDLE     : begin
                img_addr <= {img_padding_y[5:0], img_padding_x[5:0]};
            end
            FSM_CONV : begin
                if(fsm_conv_finish_flg)
                    img_addr <= 12'd0;
                else
                    img_addr <= {img_padding_y[5:0], img_padding_x[5:0]};
            end
            FSM_MAXP : begin
                if(timer[0]==1'b1) begin
                    if(img_x==6'd63) begin
                        img_addr[11:6] <= img_y + 6'd2;
                    end
                    else begin
                        img_addr[11:6] <= img_y;
                    end

                    img_addr[5:0] <= img_x + 6'd1;
                end
            end
            default      : begin
                img_addr <= 12'd0;
            end
        endcase
    end
end
//---------------------------------------
//  Memory Design
//---------------------------------------
// Memory Write
always @(posedge clk or posedge reset) begin
    if(reset) begin
        mem_valid_w <= FALSE;
        mem_addr_w <= 12'd0;
        mem_data_w <= 20'd0;
    end
    else begin
        case(cur_state)
            FSM_CONV     : begin
                if(fsm_conv_finish_flg) begin
                    mem_valid_w <= FALSE;
                    mem_addr_w <= 12'hfff;

                    mem_data_w <= 20'd0;
                end
                else begin
                    if(next_conv_pixel_flg) begin
                        mem_valid_w <= TRUE;
                        mem_addr_w <= mem_addr_w;
                    end
                    else begin
                        mem_valid_w <= FALSE;
                        mem_addr_w <= {img_y, img_x};
                    end

                    if(add_o[39]==1'b0) begin   // RELU:add_o>0
                        mem_data_w <= add_o[40-4-1 -: 20] + add_o[15];
                    end
                    else begin
                        mem_data_w <= 20'd0;
                    end
                end
            end
            FSM_MAXP     : begin
                if(next_maxp_pixel_flg)
                    mem_valid_w <= TRUE;
                else
                    mem_valid_w <= FALSE;

                if(next_maxp_pixel_flg)
                    mem_addr_w <= mem_addr_w + 12'd1;

                case(timer)
                    1: begin
                        mem_data_w <= mem_data_r;
                    end
                    2,3,4: begin
                        if(mem_data_w < mem_data_r)
                            mem_data_w <= mem_data_r;
                    end
                    default:
                        mem_data_w <= mem_data_w;
                endcase
            end
            default      : begin
                mem_valid_w <= FALSE;
                mem_addr_w <= 12'd0;
                mem_data_w <= 20'd0;
            end
        endcase
    end
end
// Memory Read
always @(posedge clk or posedge reset) begin
    if(reset) begin
        mem_valid_r <= FALSE;
        mem_addr_r <= 12'd0;
    end
    else begin
        case(cur_state)
            FSM_CONV     : begin
                if(fsm_conv_finish_flg)
                    mem_valid_r <= TRUE;
                else
                    mem_valid_r <= FALSE;
                mem_addr_r <= 12'd0;
            end
            FSM_MAXP     : begin
                if(next_maxp_pixel_flg)
                    mem_valid_r <= FALSE;
                else
                    mem_valid_r <= TRUE;

                case(timer)
                    0, 2: begin
                        mem_addr_r <= {img_padding_y[5:0], img_padding_x[5:0]};
                    end
                    1, 3: begin
                        mem_addr_r <= {img_padding_y[5:0]+$signed(7'd1), img_padding_x[5:0]};
                    end
                    default : begin
                        mem_addr_r <= {img_padding_y[5:0], img_padding_x[5:0]};
                    end
                endcase

            end
            default      : begin
                mem_valid_r <= FALSE;
                mem_addr_r <= 12'd0;
            end
        endcase
    end
end
// Memory Select
always @(posedge clk or posedge reset) begin
    if(reset) begin
        mem_sel <= MEM_NONE;
    end
    else begin
        case(cur_state)
            FSM_CONV     : begin
                mem_sel <= MEM_LAYER0;
            end
            FSM_MAXP     : begin
                if(next_maxp_pixel_flg) begin
                    mem_sel <= MEM_LAYER1;
                end
                else begin
                    mem_sel <= MEM_LAYER0;
                end
            end
            default      : begin
                mem_sel <= MEM_NONE;
            end
        endcase
    end
end
//---------------------------------------
//  Timer Design
//---------------------------------------
always @(posedge clk or posedge reset) begin
    if(reset) begin
        timer <= {{TIMER_BIT-1{1'b0}},1'b0};
    end
    else begin
        case(cur_state)
            FSM_CONV     : begin
                if(first_state_flg) begin
                    timer <= {{TIMER_BIT-1{1'b0}},1'b0};
                end
                else if(fsm_conv_finish_flg) begin
                    timer <= {{TIMER_BIT-1{1'b0}},1'd0};
                end
                else begin
                    if(next_conv_pixel_flg_buf)
                        timer <= {{TIMER_BIT-1{1'b0}},1'b0};
                    else
                        timer <= timer + {{TIMER_BIT-1{1'b0}},1'b1};
                end
            end
            FSM_MAXP     : begin
                if(first_state_flg) begin
                    timer <= {{TIMER_BIT-3{1'b0}},3'd0};
                end
                else begin
                    if(next_maxp_pixel_flg)
                        timer <= {{TIMER_BIT-1{1'b0}},1'b0};
                    else
                        timer <= timer + {{TIMER_BIT-1{1'b0}},1'b1};
                end
            end
            default      : begin
                timer <= {{TIMER_BIT-1{1'b0}},1'b0};
            end
        endcase
    end
end
//---------------------------------------
//  Adder Design
//---------------------------------------
always @(*) begin
    add_o = $signed(add_a) + $signed(add_b);
end
always @(posedge clk or posedge reset) begin
    if(reset) begin
        add_a <= 40'd0;
        add_b <= 40'd0;
    end
    else begin
        case(cur_state)
            FSM_IDLE     : begin
                if(fsm_start_flg) begin
                    add_a <= {4'd0,bias, 16'd0};
                    add_b <= 40'd0;
                end
                else begin
                    add_a <= 40'd0;
                    add_b <= 40'd0;
                end
            end
            FSM_CONV     : begin
                if(next_conv_pixel_flg) begin
                    add_a <= {4'd0,bias, 16'd0};
                    add_b <= 40'd0;
                end
                else begin
                    add_a <= add_o;
                    add_b <= mul_o;
                end
            end
            default      : begin
                add_a <= 40'd0;
                add_b <= 40'd0;
            end
        endcase
    end
end
//---------------------------------------
//  Multiplier Design
//---------------------------------------
always @(*) begin
    mul_o = $signed(mul_a) * $signed(mul_b);
end
always @(posedge clk or posedge reset) begin
    if(reset) begin
        mul_a <= 20'd0;
        mul_b <= 20'd0;
    end
    else begin
        case(cur_state)
            FSM_CONV     : begin
                if(edge_flg_buf)
                    mul_a <= 20'd0;
                else
                    mul_a <= img_data;
                if(timer<9)
                    mul_b <= kernel[timer];
                else
                    mul_b <= 20'd0;
            end
            default      : begin
                mul_a <= 20'd0;
                mul_b <= 20'd0;
            end
        endcase
    end
end
//---------------------------------------
//  Conv flag Design
//---------------------------------------
always @(posedge clk or posedge reset) begin
    if(reset) begin
        next_conv_pixel_flg_buf <= FALSE;
    end
    else begin
        next_conv_pixel_flg_buf <= next_conv_pixel_flg;
    end
end

endmodule
