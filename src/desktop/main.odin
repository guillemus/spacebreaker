// Native build used as a smoke-test harness: scripted play + screenshots.
// usage: starbreaker [-play] [-wave=N] [-fire] [-missiles] [-shots=f1,f2,..] [-frames=N]
package main_desktop

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import game "../game"
import rl "vendor:raylib"

parse :: proc(s: string) -> int {
	v, ok := strconv.parse_int(s)
	if !ok {
		fmt.eprintln("bad number:", s)
		os.exit(1)
	}
	return v
}

main :: proc() {
	play := false
	fire := false
	missiles := false
	wave := 1
	yaw: f32 = 0
	frames := -1
	shots: [dynamic]int
	for arg in os.args[1:] {
		if arg == "-play" {
			play = true
		} else if arg == "-fire" {
			fire = true
		} else if arg == "-missiles" {
			missiles = true
		} else if strings.has_prefix(arg, "-wave=") {
			wave = parse(arg[6:])
		} else if strings.has_prefix(arg, "-yaw=") {
			yaw = f32(parse(arg[5:])) * 0.0174533
		} else if strings.has_prefix(arg, "-frames=") {
			frames = parse(arg[8:])
		} else if strings.has_prefix(arg, "-shots=") {
			for part in strings.split(arg[7:], ",") {
				append(&shots, parse(part))
			}
		}
	}

	game.init(1280, 720)
	game.g.yaw = yaw
	scripted := play || fire || missiles || len(shots) > 0
	if scripted {
		game.debug_mouse = game.Vec2{640, 330}
	}
	if play {
		game.g.start_level = max(wave, 1)
		game.start_game()
	}
	frame := 0
	for !rl.WindowShouldClose() {
		if play && fire && frame > 200 && frame % 5 == 0 && game.g.phase == .Playing && !game.g.overheated {
			game.fire_bullet()
		}
		if play && missiles && frame > 240 && frame % 45 == 0 && game.g.phase == .Playing {
			game.fire_missile()
		}
		for s in shots {
			if s == frame {
				game.debug_shot = fmt.ctprintf("shot_%04d.png", frame)
			}
		}
		game.frame()
		frame += 1
		if frames > 0 && frame >= frames {
			break
		}
	}
	rl.CloseWindow()
}
