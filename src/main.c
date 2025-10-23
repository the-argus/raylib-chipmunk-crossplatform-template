#include <box2d/box2d.h>
#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#endif
#include <raylib.h>
#include <stdio.h>
#include <math.h>

void update();
void init();
void deinit();

#define SCREEN_WIDTH 600
#define SCREEN_HEIGHT 600

#ifdef __EMSCRIPTEN__
int emsc_main()
#else
int main()
#endif
{
	printf("Hello, World\n");
	init();
#ifdef __EMSCRIPTEN__
	emscripten_set_main_loop(update, 0, 1);
#else
	while (!WindowShouldClose()) {
		update();
	}
#endif
}

void init()
{
	SetConfigFlags(FLAG_MSAA_4X_HINT);
	InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Raylib/Chipmunk Example Project");
	SetTargetFPS(60);
    cpSpace* space = cpSpaceNew();
    cpSpaceInit(space);
}

void update()
{
	BeginDrawing();
	ClearBackground(BLACK);
	DrawRectanglePro((Rectangle){.width = 100,
								 .height = 100,
								 .x = (int)(GetTime() * 200) % SCREEN_WIDTH,
								 .y = SCREEN_HEIGHT / 2.0},
					 (Vector2){0, 0}, sin(GetTime()) * RAD2DEG, RED);
	EndDrawing();
}

void deinit() { CloseWindow(); }

#ifdef __EMSCRIPTEN__
void emsc_set_window_size(int width, int height)
{
	SetWindowSize(width, height);
}
#endif
