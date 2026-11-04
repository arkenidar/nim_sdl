# Snake (SDL3)

## Overview

`sdl3_snake.nim` is a classic Snake game written in Nim using raw SDL3 FFI — no
Nim SDL bindings package. It is a sibling to `sdl3_grid.nim` in the same
directory and follows the same minimal raw-FFI pattern: declare the handful of
SDL3 C functions directly with `importc`, link against SDL3, open a window, and
run a render loop.

The game runs on a fixed grid: the player steers a snake with the arrow keys,
eats red food to grow and score, and dies only by colliding with its own body.
The snake **wraps around** all four edges of the window — there is no wall death.

## Build & Run

```sh
# Unix (Linux/macOS) — dynamically links SDL3
~/.nimble/bin/nim c sdl3_snake.nim
./sdl3_snake

# Windows (MSYS2 MINGW64) — statically links SDL3 into a self-contained .exe
nim c -d:release \
  --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc \
  sdl3_snake.nim
```

- Nim 2.4.0 (any recent 2.x should work).
- Output binary is `sdl3_snake` (Unix) / `sdl3_snake.exe` (Windows), listed in
  `.gitignore`.
- Release build (Unix): `~/.nimble/bin/nim c -d:release sdl3_snake.nim`.

## Dependencies

- SDL3, linked via Nim's `passL` pragma, which selects the flags per platform:

```nim
when defined(windows):
  {.passL: "-Wl,-Bstatic -lSDL3 -Wl,-Bdynamic -lkernel32 -luser32 -lgdi32 -lwinmm -limm32 -lole32 -loleaut32 -lversion -luuid -ladvapi32 -lsetupapi -lshell32 -ldinput8".}
else:
  {.passL: "-L/usr/local/lib -Wl,-rpath,/usr/local/lib -lSDL3".}
```

- **Windows**: SDL3 is linked **statically**, so the `.exe` is self-contained
  (no `SDL3.dll` beside it; only Windows system DLLs are required). SDL3 must be
  installed in the MinGW prefix (`mingw64/include/SDL3`, `mingw64/lib`).
- **Unix (Linux/macOS)**: SDL3 is linked dynamically from `/usr/local/lib`
  (headers at `/usr/local/include/SDL3`), with an rpath so the binary finds
  `libSDL3.so` at runtime.
- Only stdlib module used: `import std/random` (for food placement). No SDL
  bindings package of any kind.

## Geometry / Grid

| Constant   | Value | Meaning                |
| ---------- | ----- | ---------------------- |
| `WinW`     | 800   | window width (px)      |
| `WinH`     | 600   | window height (px)     |
| `Cell`     | 20    | grid cell size (px)    |
| `Cols`     | 40    | `WinW div Cell`        |
| `Rows`     | 30    | `WinH div Cell`        |
| `StartLen` | 3     | initial snake length   |

The play field is a `40 x 30` grid of 20px cells, exactly filling the 800x600
window.

## Data Model

```nim
type Pos = tuple[col, row: int]
```

- A grid position `(col, row)`; a direction is also a `Pos` holding `(dx, dy)`.
- The snake is `seq[Pos]`, **head first** (`snake[0]`).
- Direction vectors: left `(-1, 0)`, right `(1, 0)`, up `(0, -1)`, down `(0, 1)`.

Helpers:

- `addPos(a, b)` — component-wise addition of two positions/directions.
- `opposite(a, b)` — true when `a + b == (0, 0)`; used to reject 180-degree
  turns.

## Game Mechanics

### Movement & timing

Movement is a fixed-tick step driven by `SDL_GetTicks()` rather than a per-frame
move, so it stays at a steady pace regardless of frame rate:

```nim
let interval = max(60, 140 - score * 4)
let now = int(SDL_GetTicks())
if not gameOver and now - lastTick >= interval:
  lastTick = now
  dir = pending
  step(...)
```

- Base interval **140 ms**, reduced by 4 ms per food eaten, clamped to a
  **60 ms** minimum — the snake speeds up as the score grows.

### Step logic

Each tick, the new head is the old head plus the direction, then wrapped:

```nim
var newHead = addPos(head, dir)
newHead.col = ((newHead.col mod Cols) + Cols) mod Cols
newHead.row = ((newHead.row mod Rows) + Rows) mod Rows
```

- **Wrap-around** on all four edges — no wall death.
- **Self-collision** against any segment **except the tail** causes game over
  (the tail cell moves away on the same tick, so entering it is legal unless
  the snake is also growing).
- If the new head lands on the food: increment the score, grow (do not pop the
  tail), and respawn the food.
- Otherwise: pop the tail (the snake moves without growing).

### Food

- Spawned by `spawnFood`, which picks a random cell and rejects any position
  already occupied by the snake.
- Food is always placed on an empty cell, so it can never coincide with the
  head or body.

### Win / lose

- **Game over** only on self-collision.
- There is no win condition; play continues until a self-collision.

## Controls

| Key                 | Action                    |
| ------------------- | ------------------------- |
| Arrow keys          | Steer the snake           |
| `Esc`               | Quit                      |
| `Space` / `Enter` / `R` | Restart (after game over) |
| Window close (`X`)  | Quit                      |

### Direction handling

Two direction variables are kept:

- `dir` — the direction **committed** at the last tick.
- `pending` — the direction **queued** for the next tick.

An arrow key sets `pending` only if it is not opposite to the committed `dir`:

```nim
of SDLK_LEFT:
  if not opposite((-1, 0), dir): pending = (-1, 0)
```

At the start of a tick, `dir = pending`. Comparing against the *committed* `dir`
(rather than the just-queued value) prevents a rapid two-key sequence (e.g.
Right, then Down, then Left within a single tick) from reversing the snake into
its own body.

## SDL3 FFI Surface

All SDL3 symbols are declared manually with `importc` — no bindings package.

### Constants

| Constant                          | Value (hex)   | Meaning            |
| --------------------------------- | ------------- | ------------------ |
| `SDL_INIT_VIDEO`                  | `0x00000020`  | init flag          |
| `SDL_EVENT_QUIT`                  | `0x00000100`  | quit event         |
| `SDL_EVENT_WINDOW_CLOSE_REQUESTED`| `0x00000210`  | X button           |
| `SDL_EVENT_KEY_DOWN`              | `0x00000300`  | key press          |
| `SDLK_ESCAPE`                     | `0x0000001b`  | Esc                |
| `SDLK_RETURN`                     | `0x0000000d`  | Enter              |
| `SDLK_SPACE`                      | `0x00000020`  | Space              |
| `SDLK_R`                          | `0x00000072`  | R                  |
| `SDLK_LEFT`                       | `0x40000050`  | Left arrow         |
| `SDLK_RIGHT`                      | `0x4000004f`  | Right arrow        |
| `SDLK_DOWN`                       | `0x40000051`  | Down arrow         |
| `SDLK_UP`                         | `0x40000052`  | Up arrow           |

### Types

- `SDL_Window`, `SDL_Renderer` — opaque C objects, declared as empty Nim
  objects.
- `SDL_FRect {.bycopy.}` — `x, y, w, h: cfloat`.
- `SDL_KeyboardEvent {.bycopy.}` — mirrors the C struct (`typeVal`, `timestamp`,
  `windowID`, `scancode`, `key`, `modVal`, `down`, `repeat`, ...).
- `SDL_Event {.union, bycopy.}` — SDL3's `SDL_Event` is a 128-byte C union,
  modeled as a Nim union with `typeVal`, an embedded `key` event, and a
  `padding: array[128, uint8]` to match the size.

### Imported functions

```nim
SDL_Init, SDL_CreateWindow, SDL_CreateRenderer,
SDL_SetRenderDrawColor, SDL_RenderFillRect, SDL_RenderPresent,
SDL_PollEvent, SDL_SetWindowTitle, SDL_GetTicks,
SDL_DestroyRenderer, SDL_DestroyWindow, SDL_Quit, SDL_GetError
```

## Rendering

Drawn every frame with `SDL_RenderFillRect` (rectangle fills); no textures or
fonts:

1. **Background** — faint checkerboard (`rgb(24,24,24)` / `rgb(30,30,30)`) for
   grid reference.
2. **Food** — red `rgb(220,60,60)`, 2px inset.
3. **Snake** — body green `rgb(40,160,40)` at 1px inset, head brighter green
   `rgb(90,220,90)`.

The score is displayed in the **window title** (via `SDL_SetWindowTitle`), e.g.
`SDL3 Snake - Score: 5`, and `... - Game Over (R to restart)` on death. This
avoids any text/font dependency.

## Main Loop

1. Poll all pending events; handle quit, window close, and key input.
2. If enough time has passed since the last tick, commit `pending` into `dir`
   and run one `step`.
3. Redraw (`draw`) and present (`SDL_RenderPresent`).
4. On exit, destroy renderer/window and call `SDL_Quit`.

## Implementation Notes / Gotchas

- **Nim `mod` is C-style** (sign follows the dividend): `-1 mod 40 == -1`, not
  `39`. The wrap-around therefore uses the double-mod normalization
  `((x mod N) + N) mod N` to always land in `[0, N)`.
- **Tail-cell exclusion** in self-collision: the loop checks `0 ..< snake.len - 1`
  because the tail will move out of its cell on the same tick.
- **Reversal prevention** uses a committed vs. pending direction to block
  multi-key double-turns within a single tick.
- **No `SDL_RenderClear`**: the checkerboard fills the entire window every
  frame, so an explicit clear is unnecessary.

## Development Plan

The following is the original implementation plan, recorded for reference. Where
the final code diverges from it, a reconciliation note follows.

### Context gathered

- The project is a raw-Nim-FFI SDL3 demo (no `sdl3` bindings package), built
  from a single-file checkerboard demo `sdl3_grid.nim`.
- Key patterns reused: `importc` FFI declarations,
  `{.passL: "-L/usr/local/lib -Wl,-rpath,/usr/local/lib -lSDL3".}`, the
  `SDL_Event` union + `SDL_KeyboardEvent` struct, and the window/renderer/event
  loop lifecycle.
- Confirmed SDL3 constants/APIs from the installed headers:
  - Arrow keys: `SDLK_LEFT = 0x40000050`, `SDLK_RIGHT = 0x4000004f`,
    `SDLK_DOWN = 0x40000051`, `SDLK_UP = 0x40000052`.
  - Timing: `SDL_GetTicks(): uint64`, `SDL_Delay(ms: uint32)`.
- Nim 2.4.0 available at `~/.nimble/bin/nim`.

### Planned steps

1. New file `sdl3_snake.nim` (same directory, same conventions), plus a
   `.gitignore` entry for `/sdl3_snake`.
2. Reuse the FFI boilerplate from `sdl3_grid.nim`: same init/event constants
   plus the 4 arrow keycodes; same `SDL_Window` / `SDL_Renderer` / `SDL_FRect` /
   `SDL_KeyboardEvent` / `SDL_Event` types; same `importc` declarations, adding
   `SDL_GetTicks` and `SDL_Delay`; same `{.passL: ...}` linker line.
3. Grid/geometry: window `800x600`, `Cell = 20` → `40x30` play grid.
4. Game model (`std/random` + `std/sequtils`): snake as `seq[(int, int)]` of
   (col, row), head first, start centered with length 3; direction as `(dx, dy)`
   ints, default right; arrow keys set a pending direction; reject 180°
   reversals; food at a random unoccupied cell; fixed tick (~140 ms) driven by
   `SDL_GetTicks`, with a speed-up as the snake grows.
5. Game logic per tick: compute new head; wall or self collision → game over;
   moving into food grows + scores + respawns food; otherwise pop the tail.
6. Rendering each frame: dark background clear; snake body green (head
   brighter), food red, optional faint grid; score/length in the window title
   (no font/text library needed).
7. States & input: Esc / window close → quit; arrow keys → steering; game over
   → Space / Enter / R restarts, with a "Press R to restart" hint in the title.
8. Verify: compile with `~/.nimble/bin/nim c sdl3_snake.nim` and confirm a clean
   build.

### Tradeoffs / assumptions

- Classic rules (death on wall, no wrapping) — easy to switch to wrapping.
- Score displayed in the window title (no text rendering) to stay
  dependency-free, matching the raw-FFI approach.
- Game tick uses `SDL_GetTicks` polling rather than `SDL_Delay`, so input stays
  responsive.

### Reconciliation with the final code

- **Wall death → wrap-around**: the final `step` wraps on all four edges rather
  than ending the game on a wall hit (changed at the user's request).
- **`std/sequtils` not needed**: only `std/random` is imported.
- **`SDL_Delay` not used**: timing relies solely on `SDL_GetTicks` polling.
- **"Dark background clear" → faint checkerboard**: the background is a subtle
  checkerboard rather than a flat clear.

## Summary & Verification

### Smoke test

The binary launched successfully and ran the game loop until `timeout` killed it
(exit code 124), with no crash or error output.

### Files changed

- **`sdl3_snake.nim`** (new) — the snake game.
- **`.gitignore`** — added `/sdl3_snake` (the compiled binary).

### What it does

- Same SDL3 window/renderer/event boilerplate as `sdl3_grid.nim`, with a couple
  of extra FFI declarations (`SDL_GetTicks`, `SDL_SetWindowTitle`).
- 800x600 window, 40x30 grid (20px cells), faint checkerboard background for
  grid reference.
- Classic snake: arrow-key steering, red food that grows the snake and increases
  score, wall/self collision → game over.
- Rejects 180° turns (committed direction vs. pending direction, so rapid
  multi-key turns can't reverse into the body).
- Fixed-tick movement (~140 ms, speeding up slightly with score) via
  `SDL_GetTicks`, so input stays responsive.
- Score shown in the window title (no font/text dependency); game over shows a
  "Press R to restart" hint — Space/Enter/R restarts, Esc quits.

### Verification

- `~/.nimble/bin/nim c sdl3_snake.nim` compiles cleanly (no warnings).
- Smoke-tested the binary: it opened and ran the loop until `timeout` killed it
  (no init errors).

Run it with:

```sh
~/.nimble/bin/nim c sdl3_snake.nim && ./sdl3_snake
```

> **Note:** the "wall/self collision → game over" wording above reflects the
> original summary. In the final build, wall collision was replaced by
> **wrap-around**, so game over occurs only on self-collision (see
> [Game Mechanics](#game-mechanics)).




