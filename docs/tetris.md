# Tetris (SDL3)

## Overview

`sdl3_tetris.nim` is a classic Tetris game written in Nim using raw SDL3 FFI —
no Nim SDL bindings package. It is a sibling to `sdl3_grid.nim` and
`sdl3_snake.nim` in the same directory and follows the same minimal raw-FFI
pattern: declare the handful of SDL3 C functions directly with `importc`, link
against SDL3, open a window, and run a render loop.

The player steers and rotates falling tetrominoes into a 10x20 well. Completed
rows disappear and award score; the game ends when a new piece cannot spawn.

## Build & Run

```sh
~/.nimble/bin/nim c sdl3_tetris.nim
./sdl3_tetris
```

- Nim 2.4.0 (any recent 2.x should work).
- Output binary is `sdl3_tetris`, listed in `.gitignore`.
- Release build: `~/.nimble/bin/nim c -d:release sdl3_tetris.nim`.

## Dependencies

- SDL3, installed at `/usr/local/lib` (headers at `/usr/local/include/SDL3`).
- Linker flags, passed via Nim's `passL` pragma:

```nim
{.passL: "-L/usr/local/lib -Wl,-rpath,/usr/local/lib -lSDL3".}
```

- Only stdlib module used: `import std/random` (for piece selection). No SDL
  bindings package of any kind.

## Geometry / Grid

| Constant   | Value | Meaning                         |
| ---------- | ----- | ------------------------------- |
| `WinW`     | 800   | window width (px)               |
| `WinH`     | 600   | window height (px)              |
| `Cell`     | 30    | grid cell size (px)             |
| `BoardCols`| 10    | play field width (cells)        |
| `BoardRows`| 20    | play field height (cells)       |
| `BoardX`   | 250   | `(WinW - BoardCols*Cell) div 2` |
| `BoardY`   | 0     | top-aligned                     |

The well is a 10x20 grid of 30px cells (300x600), centered horizontally. The
side panels are cleared to a dark background each frame; the **next piece**
preview is drawn in the right panel.

## Data Model

```nim
type
  Shape   = enum sI, sO, sT, sS, sZ, sJ, sL
  CellPos = tuple[col, row: int]
```

- Each shape is defined once as **four cells in its bounding box** (rotation 0),
  in the `ShapeCells` const array. The box size per shape is `BoxSize`: `I` uses
  a 4x4 box, `O` a 2x2 box, and `J`/`L`/`S`/`T`/`Z` a 3x3 box (matching SRS).
- Rotation is a 90-degree clockwise transform inside that box:
  `(col, row) → (size - 1 - row, col)`.
- The board is `array[BoardRows, array[BoardCols, int]]`; `0` is empty,
  otherwise the value is `ord(shape) + 1` (the shape's color index).
- The current piece is `(curKind, curCol, curRow, curRot)` — the top-left of its
  bounding box on the board plus a rotation index (`0..3`).

## Game Mechanics

### Pieces & rotation

The seven standard tetrominoes (I, O, T, S, Z, J, L) with the standard colors
(I cyan, O yellow, T purple, S green, Z red, J blue, L orange). `rotateCell`
rotates a single cell clockwise; `cellsOf` applies it `rot` times and offsets
each cell by the piece position.

Rotation uses the **Super Rotation System (SRS)**. When a rotation collides,
`tryRotate` walks the five SRS wall-kick offsets for that transition (in order)
until one fits, otherwise the rotation is cancelled. The `KickJlstz` and `KickI`
tables hold the kick data in board coordinates; the `O` piece never kicks. The
published SRS tables use "+row = up", so their y values are negated here
("+row = down").

### Randomizer

Pieces are dealt with a **7-bag randomizer** (`drawFromBag`): all seven pieces
are shuffled into a bag and dealt one at a time, and the bag is only refilled
when empty. Every run of seven pieces therefore contains each piece exactly
once — no long droughts or floods of any single piece.

### Gravity & locking

Gravity is a fixed-tick step driven by `SDL_GetTicks()` (not per-frame), so it
stays steady regardless of frame rate:

```nim
let interval = max(80, 700 - level * 60)
```

- Base interval **700 ms**, reduced by 60 ms per level, clamped to **80 ms**.
- When a piece can no longer move down, `lockPiece` stamps it into the board,
  clears full rows, and spawns the next piece.
- **Soft drop** (Down) moves one cell per key event; **hard drop** (Space)
  instantly drops to the ghost position and locks.

### Line clear & scoring

`clearLines` scans from the bottom, and for each full row shifts everything
above it down. Scoring follows the classic table, scaled by level:

| Lines | Points            |
| ----- | ----------------- |
| 1     | `40 * (level+1)`  |
| 2     | `100 * (level+1)` |
| 3     | `300 * (level+1)` |
| 4     | `1200 * (level+1)`|

The level is `lines div 10`, so every 10 cleared lines raises the level and
speeds up gravity.

### Game over & restart

A new piece spawns at the top-center. If it immediately collides with the stack,
`gameOver` is set and the gravity loop stops. `R` / `Enter` / `Space` restart;
`Esc` quits.

## Controls

| Key          | Action                        |
| ------------ | ----------------------------- |
| Left / Right | move piece                    |
| Down         | soft drop                     |
| Up / X       | rotate clockwise              |
| Z            | rotate counter-clockwise      |
| Space        | hard drop (restart when over) |
| R / Enter    | restart on game over          |
| Escape       | quit                          |

## Rendering

- The whole window is cleared dark each frame (`SDL_RenderClear`), then the
  board area is drawn as a faint checkerboard with a gray outline.
- Stacked cells are filled in their shape color; the current piece is drawn in
  full color with a dimmed **ghost piece** at the hard-drop position.
- The **next piece** preview is drawn in the right side panel.
- Score / lines / level are shown in the **window title** (no text/font
  rendering), keeping the game dependency-free.

## Summary & Verification

### Files changed

- **`sdl3_tetris.nim`** (new) — the Tetris game.
- **`.gitignore`** — added `/sdl3_tetris` (the compiled binary).

### What it does

- Same SDL3 window/renderer/event boilerplate as the sibling games, adding
  `SDL_RenderClear` to clear the side panels.
- 800x600 window; a centered 10x20 well of 30px cells with a next-piece preview
  in the right panel.
- All seven tetrominoes with SRS rotation/wall kicks and a 7-bag randomizer,
  ghost piece, soft/hard drop, line clearing, scoring, and level-based speed-up.
- Score / lines / level in the window title; `R`/`Enter`/`Space` restart on game
  over, `Esc` quits.

### Verification

- `~/.nimble/bin/nim c sdl3_tetris.nim` compiles cleanly (no warnings).
- Smoke-tested the binary: it launched and ran the loop until `timeout` killed
  it (exit code 124), with no init errors.

Run it with:

```sh
~/.nimble/bin/nim c sdl3_tetris.nim && ./sdl3_tetris
```

