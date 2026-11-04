# sdl3_snake.nim
# Minimal SDL3 Snake game using raw Nim FFI (no bindings package):
# opens a window, runs a classic snake on a grid, and closes on the Escape key
# or the window close (X) button.
#
# Controls: Arrow keys steer the snake. Eat the red food to grow and score.
#           On game over, press Space / Enter / R to restart, Escape to quit.
#
# Build:  ~/.nimble/bin/nim c sdl3_snake.nim

import std/random

const
  SDL_INIT_VIDEO              = 0x00000020'u32
  SDL_EVENT_QUIT              = 0x00000100'u32
  SDL_EVENT_WINDOW_CLOSE_REQUESTED = 0x00000210'u32
  SDL_EVENT_KEY_DOWN          = 0x00000300'u32

  SDLK_ESCAPE                 = 0x0000001b'u32
  SDLK_RETURN                 = 0x0000000d'u32
  SDLK_SPACE                  = 0x00000020'u32
  SDLK_R                      = 0x00000072'u32
  SDLK_LEFT                   = 0x40000050'u32
  SDLK_RIGHT                  = 0x4000004f'u32
  SDLK_DOWN                   = 0x40000051'u32
  SDLK_UP                     = 0x40000052'u32

type
  SDL_Window   = object
  SDL_Renderer = object

  SDL_FRect {.bycopy.} = object
    x, y, w, h: cfloat

  SDL_KeyboardEvent {.bycopy.} = object
    typeVal:   uint32
    reserved:  uint32
    timestamp: uint64
    windowID:  uint32
    which:     uint32
    scancode:  int32
    key:       uint32   # SDL_Keycode
    modVal:    uint16   # SDL_Keymod
    raw:       uint16
    down:      bool
    repeat:    bool

  # SDL_Event is a C union: first member is the type, padded to 128 bytes.
  SDL_Event {.union, bycopy.} = object
    typeVal: uint32
    key:     SDL_KeyboardEvent
    padding: array[128, uint8]

proc SDL_Init(flags: uint32): bool {.importc, cdecl.}
proc SDL_CreateWindow(title: cstring, w, h: cint, flags: uint64): ptr SDL_Window {.importc, cdecl.}
proc SDL_CreateRenderer(window: ptr SDL_Window, name: cstring): ptr SDL_Renderer {.importc, cdecl.}
proc SDL_SetRenderDrawColor(renderer: ptr SDL_Renderer, r, g, b, a: uint8): bool {.importc, cdecl.}
proc SDL_RenderFillRect(renderer: ptr SDL_Renderer, rect: ptr SDL_FRect): bool {.importc, cdecl.}
proc SDL_RenderPresent(renderer: ptr SDL_Renderer): bool {.importc, cdecl.}
proc SDL_PollEvent(event: ptr SDL_Event): bool {.importc, cdecl.}
proc SDL_SetWindowTitle(window: ptr SDL_Window, title: cstring): bool {.importc, cdecl.}
proc SDL_GetTicks(): uint64 {.importc, cdecl.}
proc SDL_DestroyRenderer(renderer: ptr SDL_Renderer) {.importc, cdecl.}
proc SDL_DestroyWindow(window: ptr SDL_Window) {.importc, cdecl.}
proc SDL_Quit() {.importc, cdecl.}
proc SDL_GetError(): cstring {.importc, cdecl.}

when defined(windows):
  {.passL: "-Wl,-Bstatic -lSDL3 -Wl,-Bdynamic -lkernel32 -luser32 -lgdi32 -lwinmm -limm32 -lole32 -loleaut32 -lversion -luuid -ladvapi32 -lsetupapi -lshell32 -ldinput8".}
elif defined(linux):
  {.passL: "-L/usr/local/lib -Wl,-Bstatic -lSDL3 -Wl,-Bdynamic -pthread -lm".}
else:
  {.passL: "-L/usr/local/lib -Wl,-rpath,/usr/local/lib -lSDL3".}

const
  WinW  = 800
  WinH  = 600
  Cell  = 20
  Cols  = WinW div Cell
  Rows  = WinH div Cell
  StartLen = 3

# A grid position is (col, row) and a direction is (dx, dy).
type Pos = tuple[col, row: int]

proc addPos(a, b: Pos): Pos = (a.col + b.col, a.row + b.row)

proc opposite(a, b: Pos): bool =
  (a.col + b.col == 0) and (a.row + b.row == 0)

proc spawnFood(snake: seq[Pos]): Pos =
  var pos: Pos
  var free = false
  while not free:
    pos = (rand(Cols - 1), rand(Rows - 1))
    free = true
    for seg in snake:
      if seg == pos:
        free = false
        break
  result = pos

proc resetGame(snake: var seq[Pos], dir: var Pos, pending: var Pos,
               food: var Pos, score: var int, gameOver: var bool) =
  snake.setLen(0)
  let startCol = Cols div 2
  let startRow = Rows div 2
  for i in 0 ..< StartLen:
    snake.add((startCol - i, startRow))
  dir = (1, 0)
  pending = dir
  score = 0
  gameOver = false
  food = spawnFood(snake)

proc step(snake: var seq[Pos], dir: Pos, food: var Pos, score: var int,
          gameOver: var bool) =
  let head = snake[0]
  var newHead = addPos(head, dir)

  # Wrap around the edges.
  newHead.col = ((newHead.col mod Cols) + Cols) mod Cols
  newHead.row = ((newHead.row mod Rows) + Rows) mod Rows

  # Self collision (the tail cell may move away this tick, so exclude it).
  for i in 0 ..< snake.len - 1:
    if snake[i] == newHead:
      gameOver = true
      return

  snake.insert(newHead, 0)
  if newHead == food:
    inc score
    food = spawnFood(snake)
  else:
    discard snake.pop()

proc fillCell(renderer: ptr SDL_Renderer, pos: Pos, inset: int,
              r, g, b: uint8) =
  var rect = SDL_FRect(
    x: cfloat(pos.col * Cell + inset),
    y: cfloat(pos.row * Cell + inset),
    w: cfloat(Cell - 2 * inset),
    h: cfloat(Cell - 2 * inset))
  discard SDL_SetRenderDrawColor(renderer, r, g, b, 255)
  discard SDL_RenderFillRect(renderer, addr rect)

proc draw(renderer: ptr SDL_Renderer, snake: seq[Pos], food: Pos) =
  # Background: faint checkerboard for grid reference.
  for row in 0 ..< Rows:
    for col in 0 ..< Cols:
      if (row + col) mod 2 == 0:
        discard SDL_SetRenderDrawColor(renderer, 24, 24, 24, 255)
      else:
        discard SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255)
      var rect = SDL_FRect(
        x: cfloat(col * Cell),
        y: cfloat(row * Cell),
        w: cfloat(Cell),
        h: cfloat(Cell))
      discard SDL_RenderFillRect(renderer, addr rect)

  # Food.
  fillCell(renderer, food, 2, 220, 60, 60)

  # Snake: body then brighter head.
  for i in 1 ..< snake.len:
    fillCell(renderer, snake[i], 1, 40, 160, 40)
  fillCell(renderer, snake[0], 1, 90, 220, 90)

proc main() =
  if not SDL_Init(SDL_INIT_VIDEO):
    echo "SDL_Init failed: ", SDL_GetError()
    quit(1)

  let window = SDL_CreateWindow("SDL3 Snake", cint(WinW), cint(WinH), 0'u64)
  if window.isNil:
    echo "SDL_CreateWindow failed: ", SDL_GetError()
    SDL_Quit()
    quit(1)

  let renderer = SDL_CreateRenderer(window, nil)
  if renderer.isNil:
    echo "SDL_CreateRenderer failed: ", SDL_GetError()
    SDL_DestroyWindow(window)
    SDL_Quit()
    quit(1)

  randomize()

  var snake: seq[Pos] = @[]
  var dir: Pos = (1, 0)
  var pending: Pos = dir
  var food: Pos = (0, 0)
  var score = 0
  var gameOver = false
  resetGame(snake, dir, pending, food, score, gameOver)

  var running = true
  var lastTick = int(SDL_GetTicks())
  while running:
    var event: SDL_Event
    while SDL_PollEvent(addr event):
      case event.typeVal
      of SDL_EVENT_QUIT, SDL_EVENT_WINDOW_CLOSE_REQUESTED:
        running = false
      of SDL_EVENT_KEY_DOWN:
        case event.key.key
        of SDLK_ESCAPE:
          running = false
        of SDLK_LEFT:
          if not opposite((-1, 0), dir): pending = (-1, 0)
        of SDLK_RIGHT:
          if not opposite((1, 0), dir):  pending = (1, 0)
        of SDLK_UP:
          if not opposite((0, -1), dir): pending = (0, -1)
        of SDLK_DOWN:
          if not opposite((0, 1), dir):  pending = (0, 1)
        of SDLK_SPACE, SDLK_RETURN, SDLK_R:
          if gameOver:
            resetGame(snake, dir, pending, food, score, gameOver)
            discard SDL_SetWindowTitle(window, "SDL3 Snake - Score: 0".cstring)
        else:
          discard
      else:
        discard

    # Fixed-tick update; interval shortens slightly as the score grows.
    let interval = max(60, 140 - score * 4)
    let now = int(SDL_GetTicks())
    if not gameOver and now - lastTick >= interval:
      lastTick = now
      dir = pending
      step(snake, dir, food, score, gameOver)
      if gameOver:
        discard SDL_SetWindowTitle(
          window, ("SDL3 Snake - Score: " & $score & " - Game Over (R to restart)").cstring)
      else:
        discard SDL_SetWindowTitle(window, ("SDL3 Snake - Score: " & $score).cstring)

    draw(renderer, snake, food)
    discard SDL_RenderPresent(renderer)

  SDL_DestroyRenderer(renderer)
  SDL_DestroyWindow(window)
  SDL_Quit()

main()
