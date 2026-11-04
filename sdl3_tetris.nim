# sdl3_tetris.nim
# Minimal SDL3 Tetris game using raw Nim FFI (no bindings package):
# opens a window, runs classic Tetris on a grid, and closes on the Escape key
# or the window close (X) button.
#
# Controls:
#   Left / Right  move the piece
#   Down          soft drop
#   Up / X        rotate clockwise
#   Z             rotate counter-clockwise
#   Space         hard drop (or restart when game over)
#   R / Enter     restart on game over
#   Escape        quit
#
# Build:  ~/.nimble/bin/nim c sdl3_tetris.nim

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
  SDLK_X                      = 0x00000078'u32
  SDLK_Z                      = 0x0000007a'u32
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
proc SDL_RenderClear(renderer: ptr SDL_Renderer): bool {.importc, cdecl.}
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
else:
  {.passL: "-L/usr/local/lib -Wl,-rpath,/usr/local/lib -lSDL3".}

const
  WinW       = 800
  WinH       = 600
  Cell       = 30
  BoardCols  = 10
  BoardRows  = 20
  BoardX     = (WinW - BoardCols * Cell) div 2   # 250, board centered
  BoardY     = 0
  LineScores = [0, 40, 100, 300, 1200]

type
  Shape   = enum sI, sO, sT, sS, sZ, sJ, sL
  CellPos = tuple[col, row: int]

# Rotation bounding-box size per piece, matching SRS: I uses a 4x4 box, O a
# 2x2 box, and J/L/S/T/Z use a 3x3 box.
const BoxSize: array[Shape, int] = [
  sI: 4, sO: 2, sT: 3, sS: 3, sZ: 3, sJ: 3, sL: 3,
]

# Base orientation of every piece as four cells in its bounding box
# (rotation state 0 = spawn orientation).
const ShapeCells: array[Shape, array[4, CellPos]] = [
  sI: [(0, 1), (1, 1), (2, 1), (3, 1)],
  sO: [(0, 0), (1, 0), (0, 1), (1, 1)],
  sT: [(1, 0), (0, 1), (1, 1), (2, 1)],
  sS: [(1, 0), (2, 0), (0, 1), (1, 1)],
  sZ: [(0, 0), (1, 0), (1, 1), (2, 1)],
  sJ: [(0, 0), (0, 1), (1, 1), (2, 1)],
  sL: [(2, 0), (0, 1), (1, 1), (2, 1)],
]

type Kicks = array[5, CellPos]

# SRS wall-kick tables. Each row is one rotation transition holding the five
# (col, row) offsets to test in order (relative to basic rotation). Published
# tables use "+row = up"; here they are stored in board coordinates
# (+row = down), i.e. the published y values are negated.
const KickJlstz: array[8, Kicks] = [
  # 0 -> R
  [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
  # R -> 0
  [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
  # R -> 2
  [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
  # 2 -> R
  [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
  # 2 -> L
  [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
  # L -> 2
  [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
  # L -> 0
  [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
  # 0 -> L
  [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
]

const KickI: array[8, Kicks] = [
  # 0 -> R
  [(0, 0), (-2, 0), (1, 0), (-2, 1), (1, -2)],
  # R -> 0
  [(0, 0), (2, 0), (-1, 0), (2, -1), (-1, 2)],
  # R -> 2
  [(0, 0), (-1, 0), (2, 0), (-1, -2), (2, 1)],
  # 2 -> R
  [(0, 0), (1, 0), (-2, 0), (1, 2), (-2, -1)],
  # 2 -> L
  [(0, 0), (2, 0), (-1, 0), (2, -1), (-1, 2)],
  # L -> 2
  [(0, 0), (-2, 0), (1, 0), (-2, 1), (1, -2)],
  # L -> 0
  [(0, 0), (1, 0), (-2, 0), (1, 2), (-2, -1)],
  # 0 -> L
  [(0, 0), (-1, 0), (2, 0), (-1, -2), (2, 1)],
]

var
  board: array[BoardRows, array[BoardCols, int]]
  curKind, nextKind: Shape
  curCol, curRow, curRot: int
  score, lines, level: int
  gameOver: bool
  bag: seq[Shape]

proc shapeColor(s: Shape): tuple[r, g, b: uint8] =
  case s
  of sI: (0, 240, 240)      # cyan
  of sO: (240, 240, 0)      # yellow
  of sT: (160, 0, 240)      # purple
  of sS: (0, 240, 0)        # green
  of sZ: (240, 0, 0)        # red
  of sJ: (0, 0, 240)        # blue
  of sL: (240, 160, 0)      # orange

# Rotate one cell 90 degrees clockwise inside an NxN box.
proc rotateCell(c: CellPos, size: int): CellPos =
  (size - 1 - c.row, c.col)

proc cellsOf(kind: Shape, col, row, rot: int): seq[CellPos] =
  result = @[]
  let size = BoxSize[kind]
  for i in 0 ..< 4:
    var c = ShapeCells[kind][i]
    for r in 0 ..< rot:
      c = rotateCell(c, size)
    result.add((col + c.col, row + c.row))

proc collides(kind: Shape, col, row, rot: int): bool =
  for c in cellsOf(kind, col, row, rot):
    if c.col < 0 or c.col >= BoardCols or c.row >= BoardRows:
      return true
    if c.row >= 0 and board[c.row][c.col] != 0:
      return true
  result = false

proc stamp(kind: Shape, col, row, rot: int) =
  for c in cellsOf(kind, col, row, rot):
    if c.row >= 0 and c.row < BoardRows and c.col >= 0 and c.col < BoardCols:
      board[c.row][c.col] = ord(kind) + 1

proc clearLines(): int =
  var cleared = 0
  var y = BoardRows - 1
  while y >= 0:
    var full = true
    for x in 0 ..< BoardCols:
      if board[y][x] == 0:
        full = false
        break
    if full:
      var yy = y
      while yy > 0:
        board[yy] = board[yy - 1]
        dec yy
      for x in 0 ..< BoardCols:
        board[0][x] = 0
      inc cleared
    else:
      dec y
  result = cleared

# 7-bag randomizer: deal all seven pieces in a shuffled order, refilling the
# bag only when it is empty, so no piece can repeat before all seven appear.
proc drawFromBag(): Shape =
  if bag.len == 0:
    for s in Shape:
      bag.add(s)
    shuffle(bag)
  result = bag[^1]
  bag.setLen(bag.len - 1)

# Maps a (from, to) rotation-state pair to a row in the kick tables.
proc kickIndex(fromRot, toRot: int): int =
  case fromRot
  of 0:
    if toRot == 1: 0 else: 7   # 0->R / 0->L
  of 1:
    if toRot == 0: 1 else: 2   # R->0 / R->2
  of 2:
    if toRot == 1: 3 else: 4   # 2->R / 2->L
  else:
    if toRot == 2: 5 else: 6   # L->2 / L->0

proc kicksFor(kind: Shape, fromRot, toRot: int): Kicks =
  if kind == sO:
    return [(0, 0), (0, 0), (0, 0), (0, 0), (0, 0)]
  let tbl = if kind == sI: KickI else: KickJlstz
  result = tbl[kickIndex(fromRot, toRot)]

proc spawnNew() =
  curKind = nextKind
  nextKind = drawFromBag()
  curCol = (BoardCols - BoxSize[curKind]) div 2
  curRow = -1
  curRot = 0
  if collides(curKind, curCol, curRow, curRot):
    gameOver = true

proc resetGame() =
  for row in 0 ..< BoardRows:
    for col in 0 ..< BoardCols:
      board[row][col] = 0
  score = 0
  lines = 0
  level = 0
  gameOver = false
  bag.setLen(0)
  nextKind = drawFromBag()
  spawnNew()

proc lockPiece() =
  stamp(curKind, curCol, curRow, curRot)
  let cleared = clearLines()
  if cleared > 0:
    lines += cleared
    score += LineScores[cleared] * (level + 1)
    level = lines div 10
  spawnNew()

proc stepDown(): bool =
  if not collides(curKind, curCol, curRow + 1, curRot):
    inc curRow
    result = false
  else:
    lockPiece()
    result = true

proc tryMove(dc, dr: int): bool =
  if not collides(curKind, curCol + dc, curRow + dr, curRot):
    curCol += dc
    curRow += dr
    result = true

proc tryRotate(dir: int): bool =
  let fromRot = curRot
  let toRot = (curRot + dir + 4) mod 4
  # Try the SRS wall-kick offsets for this transition, in order.
  for kick in kicksFor(curKind, fromRot, toRot):
    if not collides(curKind, curCol + kick.col, curRow + kick.row, toRot):
      curCol += kick.col
      curRow += kick.row
      curRot = toRot
      return true
  result = false

proc hardDrop() =
  while not collides(curKind, curCol, curRow + 1, curRot):
    inc curRow
  lockPiece()

proc ghostRow(): int =
  var row = curRow
  while not collides(curKind, curCol, row + 1, curRot):
    inc row
  result = row

proc titleString(): string =
  if gameOver:
    "SDL3 Tetris - Score: " & $score & " - Game Over (R to restart)"
  else:
    "SDL3 Tetris - Score: " & $score & " - Lines: " & $lines &
      " - Level: " & $level

proc updateTitle(window: ptr SDL_Window) =
  discard SDL_SetWindowTitle(window, titleString().cstring)

proc handleKey(key: uint32, window: ptr SDL_Window) =
  case key
  of SDLK_LEFT:
    if not gameOver: discard tryMove(-1, 0)
  of SDLK_RIGHT:
    if not gameOver: discard tryMove(1, 0)
  of SDLK_DOWN:
    if not gameOver: discard tryMove(0, 1)
  of SDLK_UP, SDLK_X:
    if not gameOver: discard tryRotate(1)
  of SDLK_Z:
    if not gameOver: discard tryRotate(-1)
  of SDLK_SPACE:
    if gameOver:
      resetGame()
      updateTitle(window)
    else:
      hardDrop()
      updateTitle(window)
  of SDLK_RETURN, SDLK_R:
    if gameOver:
      resetGame()
      updateTitle(window)
  else:
    discard

proc fillRect(renderer: ptr SDL_Renderer, px, py: int, r, g, b: uint8, inset: int) =
  var rect = SDL_FRect(
    x: cfloat(px + inset),
    y: cfloat(py + inset),
    w: cfloat(Cell - 2 * inset),
    h: cfloat(Cell - 2 * inset))
  discard SDL_SetRenderDrawColor(renderer, r, g, b, 255)
  discard SDL_RenderFillRect(renderer, addr rect)

proc drawCells(renderer: ptr SDL_Renderer, kind: Shape, col, row, rot: int,
               r, g, b: uint8, inset: int) =
  for c in cellsOf(kind, col, row, rot):
    if c.row >= 0:
      fillRect(renderer, BoardX + c.col * Cell, BoardY + c.row * Cell,
               r, g, b, inset)

proc drawNext(renderer: ptr SDL_Renderer) =
  let pv = Cell div 2   # preview cell size
  var minCol = 3
  var maxCol = 0
  var minRow = 3
  for c in ShapeCells[nextKind]:
    if c.col < minCol: minCol = c.col
    if c.col > maxCol: maxCol = c.col
    if c.row < minRow: minRow = c.row
  let w = (maxCol - minCol + 1) * pv
  let px = BoardX + BoardCols * Cell + (WinW - BoardX - BoardCols * Cell - w) div 2
  let py = 80
  let (r, g, b) = shapeColor(nextKind)
  for c in ShapeCells[nextKind]:
    var rect = SDL_FRect(
      x: cfloat(px + (c.col - minCol) * pv),
      y: cfloat(py + (c.row - minRow) * pv),
      w: cfloat(pv - 2),
      h: cfloat(pv - 2))
    discard SDL_SetRenderDrawColor(renderer, r, g, b, 255)
    discard SDL_RenderFillRect(renderer, addr rect)

proc draw(renderer: ptr SDL_Renderer) =
  # Clear the whole window (the board only fills the central column).
  discard SDL_SetRenderDrawColor(renderer, 16, 16, 16, 255)
  discard SDL_RenderClear(renderer)

  # Board background: faint checkerboard.
  for row in 0 ..< BoardRows:
    for col in 0 ..< BoardCols:
      if (row + col) mod 2 == 0:
        discard SDL_SetRenderDrawColor(renderer, 22, 22, 22, 255)
      else:
        discard SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255)
      var rect = SDL_FRect(
        x: cfloat(BoardX + col * Cell),
        y: cfloat(BoardY + row * Cell),
        w: cfloat(Cell),
        h: cfloat(Cell))
      discard SDL_RenderFillRect(renderer, addr rect)

  # Board outline.
  let bw = BoardCols * Cell
  let bh = BoardRows * Cell
  discard SDL_SetRenderDrawColor(renderer, 90, 90, 90, 255)
  var rTop = SDL_FRect(x: cfloat(BoardX - 2), y: cfloat(BoardY - 2),
                       w: cfloat(bw + 4), h: 2)
  discard SDL_RenderFillRect(renderer, addr rTop)
  var rBot = SDL_FRect(x: cfloat(BoardX - 2), y: cfloat(BoardY + bh),
                       w: cfloat(bw + 4), h: 2)
  discard SDL_RenderFillRect(renderer, addr rBot)
  var rLef = SDL_FRect(x: cfloat(BoardX - 2), y: cfloat(BoardY - 2),
                       w: 2, h: cfloat(bh + 4))
  discard SDL_RenderFillRect(renderer, addr rLef)
  var rRig = SDL_FRect(x: cfloat(BoardX + bw), y: cfloat(BoardY - 2),
                       w: 2, h: cfloat(bh + 4))
  discard SDL_RenderFillRect(renderer, addr rRig)

  # Stacked cells.
  for row in 0 ..< BoardRows:
    for col in 0 ..< BoardCols:
      if board[row][col] != 0:
        let s = Shape(board[row][col] - 1)
        let (r, g, b) = shapeColor(s)
        fillRect(renderer, BoardX + col * Cell, BoardY + row * Cell, r, g, b, 1)

  if not gameOver:
    # Ghost piece at the hard-drop position.
    let gr = ghostRow()
    let (r, g, b) = shapeColor(curKind)
    drawCells(renderer, curKind, curCol, gr, curRot,
              uint8(r div 2), uint8(g div 2), uint8(b div 2), 4)

    # Current piece.
    drawCells(renderer, curKind, curCol, curRow, curRot, r, g, b, 1)

  # Next piece preview.
  drawNext(renderer)

proc main() =
  if not SDL_Init(SDL_INIT_VIDEO):
    echo "SDL_Init failed: ", SDL_GetError()
    quit(1)

  let window = SDL_CreateWindow("SDL3 Tetris", cint(WinW), cint(WinH), 0'u64)
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
  resetGame()
  updateTitle(window)

  var running = true
  var lastTick = int(SDL_GetTicks())
  while running:
    var event: SDL_Event
    while SDL_PollEvent(addr event):
      case event.typeVal
      of SDL_EVENT_QUIT, SDL_EVENT_WINDOW_CLOSE_REQUESTED:
        running = false
      of SDL_EVENT_KEY_DOWN:
        if event.key.key == SDLK_ESCAPE:
          running = false
        else:
          handleKey(event.key.key, window)
      else:
        discard

    # Fixed-tick gravity; interval shortens as the level grows.
    if not gameOver:
      let interval = max(80, 700 - level * 60)
      let now = int(SDL_GetTicks())
      if now - lastTick >= interval:
        lastTick = now
        discard stepDown()
        updateTitle(window)

    draw(renderer)
    discard SDL_RenderPresent(renderer)

  SDL_DestroyRenderer(renderer)
  SDL_DestroyWindow(window)
  SDL_Quit()

main()



