// SkyPilot playable Vulkos buttons: 1 LEFT, 2 RIGHT, 7 RESTART, 8 FIRE
// Includes crash detection with red game-over screen.
// 640x480 VGA timing. Feed clk with approximately 25 MHz.
// At 25 MHz: horizontal 31.25 kHz and vertical ~59.52 Hz.
`default_nettype none
module vga_timing (
    input wire clk,
    input wire rst_n,
    input wire ena,
    output reg [9:0] x,
    output reg [9:0] y,
    output wire visible,
    output wire hsync,
    output wire vsync,
    output wire frame_tick
);
    localparam [9:0] H_TOTAL = 10'd800;
    localparam [9:0] V_TOTAL = 10'd525;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 10'd0;
            y <= 10'd0;
        end else if (ena) begin
            if (x == H_TOTAL - 10'd1) begin
                x <= 10'd0;
                if (y == V_TOTAL - 10'd1)
                    y <= 10'd0;
                else
                    y <= y + 10'd1;
            end else begin
                x <= x + 10'd1;
            end
        end
    end

    assign visible = (x < 10'd640) && (y < 10'd480);
    assign hsync = ~((x >= 10'd656) && (x < 10'd752));
    assign vsync = ~((y >= 10'd490) && (y < 10'd492));
    assign frame_tick = (x == 10'd799) && (y == 10'd524);
endmodule
`default_nettype wire
// SkyPilot game: moving player, scoring, best-in-session, and hit effects.
`default_nettype none
module sky_game (
    input wire clk, rst_n, ena, frame_tick,
    input wire [7:0] steering,
    input wire button_mode, fire, restart,
    output reg [9:0] plane_x,
    output reg [9:0] bullet_x, bullet_y,
    output reg bullet_active,
    output reg [9:0] enemy_x, enemy_y,
    output reg [7:0] score,
    output reg [7:0] best_score,
    output reg game_over,
    output reg [9:0] explosion_x, explosion_y,
    output reg [3:0] explosion_timer,
    output reg [1:0] muzzle_timer,
    output reg [7:0] frame_number
);
    reg [7:0] steering_meta, steering_sync;
    reg mode_meta, mode_sync;
    reg fire_meta, fire_sync, fire_prev;
    reg restart_meta, restart_sync;
    reg fire_pending, enemy_right;

    wire signed [7:0] tilt = $signed(steering_sync);
    wire left_cmd = mode_sync ? steering_sync[0] : (tilt < -8'sd12);
    wire right_cmd = mode_sync ? steering_sync[1] : (tilt > 8'sd12);
    wire [9:0] step_size = mode_sync ? 10'd4 :
        ((tilt > 8'sd65) || (tilt < -8'sd65) ? 10'd5 : 10'd2);

    wire bullet_hit = bullet_active &&
        (bullet_x + 10'd3 >= enemy_x - 10'd14) &&
        (bullet_x <= enemy_x + 10'd14) &&
        (bullet_y <= enemy_y + 10'd11) &&
        (bullet_y + 10'd11 >= enemy_y - 10'd11);

    wire crash_body =
        (enemy_y + 10'd12 >= 10'd408) && (enemy_y <= 10'd451) &&
        (enemy_x + 10'd14 >= plane_x - 10'd4) &&
        (enemy_x <= plane_x + 10'd4);
    wire crash_wings =
        (enemy_y + 10'd12 >= 10'd429) && (enemy_y <= 10'd435) &&
        (enemy_x + 10'd14 >= plane_x - 10'd17) &&
        (enemy_x <= plane_x + 10'd17);
    wire plane_hit = crash_body || crash_wings;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            steering_meta <= 0;
            steering_sync <= 0;
            mode_meta <= 0;
            mode_sync <= 0;
            fire_meta <= 0;
            fire_sync <= 0;
            fire_prev <= 0;
            restart_meta <= 0;
            restart_sync <= 0;
            fire_pending <= 0;
            plane_x <= 10'd320;
            bullet_x <= 10'd320;
            bullet_y <= 10'd410;
            bullet_active <= 0;
            enemy_x <= 10'd180;
            enemy_y <= 10'd60;
            enemy_right <= 1;
            score <= 0;
            best_score <= 0;
            game_over <= 0;
            explosion_x <= 0;
            explosion_y <= 0;
            explosion_timer <= 0;
            muzzle_timer <= 0;
            frame_number <= 0;
        end else begin
            steering_meta <= steering;
            steering_sync <= steering_meta;
            mode_meta <= button_mode;
            mode_sync <= mode_meta;
            fire_meta <= fire;
            fire_sync <= fire_meta;
            fire_prev <= fire_sync;
            restart_meta <= restart;
            restart_sync <= restart_meta;
            if (frame_tick)
                fire_pending <= 1'b0;
            if (fire_sync && !fire_prev)
                fire_pending <= 1'b1;

            if (ena && frame_tick) begin
                frame_number <= frame_number + 8'd1;
                if (explosion_timer != 0)
                    explosion_timer <= explosion_timer - 4'd1;
                if (muzzle_timer != 0)
                    muzzle_timer <= muzzle_timer - 2'd1;

                if (restart_sync) begin
                    plane_x <= 10'd320;
                    bullet_active <= 0;
                    enemy_x <= 10'd180;
                    enemy_y <= 10'd60;
                    enemy_right <= 1;
                    score <= 0;
                    // best_score intentionally survives a GAME restart.
                    game_over <= 0;
                    explosion_timer <= 0;
                    muzzle_timer <= 0;
                    fire_pending <= 0;
                end else if (game_over) begin
                    bullet_active <= 0;
                end else if (plane_hit) begin
                    game_over <= 1;
                    bullet_active <= 0;
                    explosion_x <= plane_x;
                    explosion_y <= 10'd430;
                    explosion_timer <= 4'd12;
                end else begin
                    if (left_cmd && !right_cmd) begin
                        if (plane_x > 10'd20 + step_size)
                            plane_x <= plane_x - step_size;
                        else
                            plane_x <= 10'd20;
                    end else if (right_cmd && !left_cmd) begin
                        if (plane_x < 10'd620 - step_size)
                            plane_x <= plane_x + step_size;
                        else
                            plane_x <= 10'd620;
                    end

                    if (enemy_right) begin
                        if (enemy_x >= 10'd598)
                            enemy_right <= 0;
                        else
                            enemy_x <= enemy_x + 10'd2;
                    end else begin
                        if (enemy_x <= 10'd42)
                            enemy_right <= 1;
                        else
                            enemy_x <= enemy_x - 10'd2;
                    end

                    if (bullet_hit) begin
                        if (score != 8'hff) begin
                            score <= score + 8'd1;
                            if (score + 8'd1 > best_score)
                                best_score <= score + 8'd1;
                        end
                        bullet_active <= 0;
                        explosion_x <= enemy_x;
                        explosion_y <= enemy_y;
                        explosion_timer <= 4'd12;
                        enemy_y <= 10'd60;
                    end else begin
                        if (enemy_y >= 10'd470)
                            enemy_y <= 10'd60;
                        else
                            enemy_y <= enemy_y + 10'd2;

                        if (bullet_active) begin
                            if (bullet_y < 10'd12)
                                bullet_active <= 0;
                            else
                                bullet_y <= bullet_y - 10'd10;
                        end else if (fire_pending || (fire_sync && !fire_prev)) begin
                            bullet_active <= 1;
                            bullet_x <= plane_x;
                            bullet_y <= 10'd407;
                            muzzle_timer <= 2'd2;
                        end
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
// Tiny raster renderer. No RAM framebuffer or DSP needed.
`default_nettype none
module sky_renderer (
    input wire [9:0] x, y,
    input wire visible,
    input wire [9:0] plane_x,
    input wire [9:0] bullet_x, bullet_y,
    input wire bullet_active,
    input wire [9:0] enemy_x, enemy_y,
    input wire [7:0] score, best_score,
    input wire game_over,
    input wire [9:0] explosion_x, explosion_y,
    input wire [3:0] explosion_timer,
    input wire [1:0] muzzle_timer,
    input wire [7:0] frame_number,
    output reg [1:0] red, green, blue
);
    wire player_body = (x >= plane_x - 10'd4) &&
                       (x <= plane_x + 10'd4) &&
                       (y >= 10'd408) && (y <= 10'd451);
    wire player_wings = (x >= plane_x - 10'd17) &&
                        (x <= plane_x + 10'd17) &&
                        (y >= 10'd429) && (y <= 10'd435);
    wire player_tail = (x >= plane_x - 10'd10) &&
                       (x <= plane_x + 10'd10) &&
                       (y >= 10'd445) && (y <= 10'd449);
    wire plane_pixel = player_body || player_wings || player_tail;
    wire windshield = (x >= plane_x - 10'd2) &&
                      (x <= plane_x + 10'd2) &&
                      (y >= 10'd421) && (y <= 10'd430);
    wire enemy_body = (x >= enemy_x - 10'd5) &&
                      (x <= enemy_x + 10'd5) &&
                      (y >= enemy_y - 10'd12) &&
                      (y <= enemy_y + 10'd12);
    wire enemy_wings = (x >= enemy_x - 10'd14) &&
                       (x <= enemy_x + 10'd14) &&
                       (y >= enemy_y - 10'd4) &&
                       (y <= enemy_y + 10'd4);
    wire enemy_pixel = enemy_body || enemy_wings;
    wire bullet_pixel = bullet_active &&
                        (x >= bullet_x - 10'd2) &&
                        (x <= bullet_x + 10'd2) &&
                        (y >= bullet_y) && (y <= bullet_y + 10'd10);
    wire muzzle_pixel = (muzzle_timer != 0) &&
                        (x >= plane_x - 10'd4) &&
                        (x <= plane_x + 10'd4) &&
                        (y >= 10'd397) && (y <= 10'd410);

    // 12-frame expanding explosion ring plus four directional sparks.
    wire [9:0] dx = (x >= explosion_x) ? x - explosion_x : explosion_x - x;
    wire [9:0] dy = (y >= explosion_y) ? y - explosion_y : explosion_y - y;
    wire [5:0] radius = 6'd4 + ((6'd12 - {2'b0, explosion_timer}) << 1);
    wire [9:0] major = (dx > dy) ? dx : dy;
    wire explosion_pixel = (explosion_timer != 0) &&
        (((major >= radius - 6'd3) && (major <= radius + 6'd1) &&
          ((dx < 10'd5) || (dy < 10'd5) ||
           ((dx > dy-10'd4) && (dx < dy+10'd4)))) ||
         ((dx < 10'd5) && (dy < 10'd5)));

    // Scrolling cloud formations and a speckled sky.
    wire [9:0] cx1 = 10'd68 + {2'b00, frame_number};
    wire [9:0] cx2 = 10'd440 - {3'b000,frame_number[7:1]};
    wire cloud1 = (x >= cx1 - 10'd38 && x <= cx1 + 10'd38 && y >= 10'd115 && y <= 10'd121) ||
                  (x >= cx1 - 10'd20 && x <= cx1 + 10'd20 && y >= 10'd109 && y <= 10'd127);
    wire cloud2 = (x >= cx2 - 10'd50 && x <= cx2 + 10'd50 && y >= 10'd230 && y <= 10'd237) ||
                  (x >= cx2 - 10'd27 && x <= cx2 + 10'd27 && y >= 10'd221 && y <= 10'd242);
    wire tiny_sparkles = (x[6:0] == {frame_number[4:0], 2'b01}) &&
                          (y[5:0] == {x[3:0],2'b11}) && (y > 10'd46);

    // Convert an 8-bit score (0..255) to three BCD digits.
    // Double-dabble conversion uses only shifts and add-3, no divider.
    function [11:0] bcd3;
        input [7:0] val;
        reg [11:0] d;
        integer i;
        begin
            d = 12'd0;
            for (i=7; i>=0; i=i-1) begin
                if (d[3:0] >= 4'd5) d[3:0] = d[3:0] + 4'd3;
                if (d[7:4] >= 4'd5) d[7:4] = d[7:4] + 4'd3;
                if (d[11:8] >= 4'd5) d[11:8] = d[11:8] + 4'd3;
                d = {d[10:0], val[i]};
            end
            bcd3 = d;
        end
    endfunction
    wire [11:0] score_bcd = bcd3(score);
    wire [11:0] best_bcd = bcd3(best_score);
    // Seven-segment glyph order: top, upper-right, lower-right,
    // bottom, lower-left, upper-left, center.
    function [6:0] seg7;
        input [3:0] val;
        begin
            case (val)
                4'd0: seg7 = 7'b1111110;
                4'd1: seg7 = 7'b0110000;
                4'd2: seg7 = 7'b1101101;
                4'd3: seg7 = 7'b1111001;
                4'd4: seg7 = 7'b0110011;
                4'd5: seg7 = 7'b1011011;
                4'd6: seg7 = 7'b1011111;
                4'd7: seg7 = 7'b1110000;
                4'd8: seg7 = 7'b1111111;
                4'd9: seg7 = 7'b1111011;
                default: seg7 = 7'd0;
            endcase
        end
    endfunction
    reg digit_select;
    reg [9:0] digit_x;
    reg [3:0] digit_value;
    reg best_digit;
    always @* begin
        digit_select = 1'b1;
        digit_x = 10'd0;
        digit_value = 4'd0;
        best_digit = 1'b0;
        if (x >= 10'd24 && x < 10'd40) begin
            digit_x = 10'd24; digit_value = score_bcd[11:8];
        end else if (x >= 10'd46 && x < 10'd62) begin
            digit_x = 10'd46; digit_value = score_bcd[7:4];
        end else if (x >= 10'd68 && x < 10'd84) begin
            digit_x = 10'd68; digit_value = score_bcd[3:0];
        end else if (x >= 10'd500 && x < 10'd516) begin
            digit_x = 10'd500; digit_value = best_bcd[11:8]; best_digit = 1'b1;
        end else if (x >= 10'd522 && x < 10'd538) begin
            digit_x = 10'd522; digit_value = best_bcd[7:4]; best_digit = 1'b1;
        end else if (x >= 10'd544 && x < 10'd560) begin
            digit_x = 10'd544; digit_value = best_bcd[3:0]; best_digit = 1'b1;
        end else begin
            digit_select = 1'b0;
        end
    end
    wire [4:0] sx = x - digit_x;
    wire [4:0] sy = y - 10'd22;
    wire [6:0] segments = seg7(digit_value);
    wire digit_pixel = digit_select && (y >= 10'd22 && y <= 10'd48) &&
        ((segments[6] && (sy <= 5'd2)  && sx >= 5'd3 && sx <= 5'd12) ||
         (segments[5] && (sy >= 5'd3 && sy <= 5'd12) && sx >= 5'd13) ||
         (segments[4] && (sy >= 5'd14 && sy <= 5'd23) && sx >= 5'd13) ||
         (segments[3] && (sy >= 5'd24) && sx >= 5'd3 && sx <= 5'd12) ||
         (segments[2] && (sy >= 5'd14 && sy <= 5'd23) && sx <= 5'd2) ||
         (segments[1] && (sy >= 5'd3 && sy <= 5'd12) && sx <= 5'd2) ||
         (segments[0] && (sy >= 5'd12 && sy <= 5'd14) && sx >= 5'd3 && sx <= 5'd12));
    wire hud_back = (x >= 10'd10 && x <= 10'd96 && y >= 10'd8 && y <= 10'd55) ||
                    (x >= 10'd487 && x <= 10'd573 && y >= 10'd8 && y <= 10'd55);
    wire hud_bar = (y >= 10'd8 && y <= 10'd12) &&
                   ((x >= 10'd10 && x <= 10'd96) || (x >= 10'd487 && x <= 10'd573));

    always @* begin
        red   = game_over ? 2'b11 : 2'b01;
        green = game_over ? 2'b00 : (y < 10'd200 ? 2'b10 : 2'b11);
        blue  = game_over ? 2'b00 : 2'b11;
        if (!visible) begin
            red=0; green=0; blue=0;
        end else if (explosion_pixel) begin
            red=2'b11; green=explosion_timer[0] ? 2'b11 : 2'b01; blue=2'b00;
        end else if (bullet_pixel || muzzle_pixel) begin
            red=2'b11; green=2'b11; blue=2'b00;
        end else if (windshield) begin
            red=2'b11; green=2'b11; blue=2'b11;
        end else if (plane_pixel) begin
            red=2'b00; green=2'b01; blue=2'b11;
        end else if (enemy_pixel) begin
            red=2'b11; green=2'b00; blue=2'b01;
        end else if (digit_pixel) begin
            if (best_digit) begin
                red=2'b11; green=2'b11; blue=2'b00;
            end else begin
                red=2'b00; green=2'b11; blue=2'b11;
            end
        end else if (hud_bar) begin
            red=2'b11; green=2'b11; blue=2'b11;
        end else if (hud_back) begin
            red=0; green=0; blue=2'b01;
        end else if (!game_over && (cloud1 || cloud2 || tiny_sparkles)) begin
            red=2'b11; green=2'b11; blue=2'b11;
        end
    end
endmodule
`default_nettype wire
// Music from 25 MHz pixel clock: 8-note loop on passive piezo (uio[7]).
// Pure digital square wave; no music file, DAC, or VGA audio channel.
`default_nettype none
module sky_audio (
    input wire clk, rst_n, ena, frame_tick,
    input wire game_over,
    input wire [3:0] explosion_timer,
    output reg audio_out
);
    reg [3:0] beat;
    reg [2:0] note;
    reg [15:0] half_count;
    reg [15:0] half_period;
    always @* begin
        case (note)
            3'd0: half_period=16'd23901;  // C5 523 Hz
            3'd1: half_period=16'd18968;  // E5 659 Hz
            3'd2: half_period=16'd15944;  // G5 784 Hz
            3'd3: half_period=16'd18968;
            3'd4: half_period=16'd21259;  // D5 588 Hz
            3'd5: half_period=16'd16892;  // F#5 740 Hz
            3'd6: half_period=16'd15944;
            default: half_period=16'd0;  // rest
        endcase
        if (explosion_timer != 0)
            half_period=explosion_timer[3] ? 16'd7000 : 16'd11000;
        if (game_over && explosion_timer == 0)
            half_period=0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat <= 0;
            note <= 0;
            half_count <= 0;
            audio_out <= 0;
        end else if (!ena) begin
            half_count <= 0;
            audio_out <= 0;
        end else begin
            if (frame_tick) begin
                if (beat == 4'd11) begin
                    beat <= 0;
                    note <= note + 3'd1;
                end else begin
                    beat <= beat + 4'd1;
                end
            end
            if (half_period == 0) begin
                half_count <= 0;
                audio_out <= 0;
            end else if (half_count >= half_period - 16'd1) begin
                half_count <= 0;
                audio_out <= ~audio_out;
            end else begin
                half_count <= half_count + 16'd1;
            end
        end
    end
endmodule
`default_nettype wire
// PlaneShooter - Tiny Tapeout 640x480 VGA and one-channel audio.
`default_nettype none
module tt_um_z10565_spaceshooter (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire ena, clk, rst_n
);
    wire [9:0] x, y;
    wire visible, hsync, vsync, frame_tick;
    wire [9:0] plane_x, bullet_x, bullet_y, enemy_x, enemy_y;
    wire bullet_active, game_over;
    wire [7:0] score, best_score;
    wire [9:0] explosion_x, explosion_y;
    wire [3:0] explosion_timer;
    wire [1:0] muzzle_timer;
    wire [7:0] frame_number;
    wire [1:0] red, green, blue;
    wire sound_pin;

    // Keep 1 for VGA Playground and your physical button wiring.
    // With 0: ui_in is signed phone tilt and uio[0:2] are control inputs.
    localparam VULKOS_BUTTON_MODE = 1'b1;
    wire mode_ctrl = VULKOS_BUTTON_MODE ? 1'b1 : uio_in[2];
    wire fire_ctrl = VULKOS_BUTTON_MODE ? ui_in[7] : uio_in[0];
    wire restart_ctrl = VULKOS_BUTTON_MODE ? ui_in[6] : uio_in[1];

    vga_timing video (
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .x(x), .y(y), .visible(visible),
        .hsync(hsync), .vsync(vsync), .frame_tick(frame_tick)
    );
    sky_game game (
        .clk(clk), .rst_n(rst_n), .ena(ena), .frame_tick(frame_tick),
        .steering(ui_in), .button_mode(mode_ctrl),
        .fire(fire_ctrl), .restart(restart_ctrl),
        .plane_x(plane_x), .bullet_x(bullet_x), .bullet_y(bullet_y),
        .bullet_active(bullet_active), .enemy_x(enemy_x), .enemy_y(enemy_y),
        .score(score), .best_score(best_score), .game_over(game_over),
        .explosion_x(explosion_x), .explosion_y(explosion_y),
        .explosion_timer(explosion_timer), .muzzle_timer(muzzle_timer),
        .frame_number(frame_number)
    );
    sky_renderer render (
        .x(x), .y(y), .visible(visible), .plane_x(plane_x),
        .bullet_x(bullet_x), .bullet_y(bullet_y),
        .bullet_active(bullet_active), .enemy_x(enemy_x), .enemy_y(enemy_y),
        .score(score), .best_score(best_score), .game_over(game_over),
        .explosion_x(explosion_x), .explosion_y(explosion_y),
        .explosion_timer(explosion_timer), .muzzle_timer(muzzle_timer),
        .frame_number(frame_number), .red(red), .green(green), .blue(blue)
    );
    sky_audio soundtrack (
        .clk(clk), .rst_n(rst_n), .ena(ena), .frame_tick(frame_tick),
        .game_over(game_over), .explosion_timer(explosion_timer),
        .audio_out(sound_pin)
    );
    // Standard Tiny VGA Pmod digital outputs.
    assign uo_out = {hsync, blue[0], green[0], red[0],
                     vsync, blue[1], green[1], red[1]};
    // uio[7] sends digital audio to a passive piezo through a current-
    // limiting resistor / buffer; no analog speaker directly on the pin.
    assign uio_out = {sound_pin, 7'b0000000};
    assign uio_oe  = 8'b10000000;
    wire _unused = &{uio_in[7:3], 1'b0};
endmodule
`default_nettype wire
