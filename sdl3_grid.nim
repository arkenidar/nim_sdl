# sdl3_grid.nim
# Minimal SDL3 app using raw Nim FFI (no bindings package):
# opens a window, draws a white/gray checkerboard grid, and closes on the
# Escape key or the window close (X) button.
#
# Build:  ~/.nimble/bin/nim c sdl3_grid.nim

const
  SDL_INIT_VIDEO              = 0x00000020'u32
  SDL_EVENT_QUIT              = 0x00000100'u32
  SDL_EVENT_WINDOW_CLOSE_REQUESTED = 0x00000210'u32
  SDL_EVENT_KEY_DOWN          = 0x00000300'u32
  SDLK_ESCAPE                 = 0x0000001b'u32

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
proc SDL_DestroyRenderer(renderer: ptr SDL_Renderer) {.importc, cdecl.}
proc SDL_DestroyWindow(window: ptr SDL_Window) {.importc, cdecl.}
proc SDL_Quit() {.importc, cdecl.}
proc SDL_GetError(): cstring {.importc, cdecl.}

when defined(windows):
  {.passL: "-Wl,-Bstatic -lSDL3 -Wl,-Bdynamic -lkernel32 -luser32 -lgdi32 -lwinmm -limm32 -lole32 -loleaut32 -lversion -luuid -ladvapi32 -lsetupapi -lshell32 -ldinput8".}
else:
  {.passL: "-L/usr/local/lib -Wl,-rpath,/usr/local/lib -lSDL3".}

const
  WinW  = 800
  WinH  = 600
  Cell  = 50
  Cols  = WinW div Cell
  Rows  = WinH div Cell

proc main() =
  if not SDL_Init(SDL_INIT_VIDEO):
    echo "SDL_Init failed: ", SDL_GetError()
    quit(1)

  let window = SDL_CreateWindow("SDL3 checkerboard", cint(WinW), cint(WinH), 0'u64)
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

  var running = true
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
        discard

    # Background
    discard SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255)
    discard SDL_RenderClear(renderer)

    # Checkerboard squares
    for row in 0 ..< Rows:
      for col in 0 ..< Cols:
        if (row + col) mod 2 == 0:
          discard SDL_SetRenderDrawColor(renderer, 240, 240, 240, 255)  # white
        else:
          discard SDL_SetRenderDrawColor(renderer, 110, 110, 110, 255)  # gray
        var rect = SDL_FRect(
          x: cfloat(col * Cell),
          y: cfloat(row * Cell),
          w: cfloat(Cell),
          h: cfloat(Cell))
        discard SDL_RenderFillRect(renderer, addr rect)

    discard SDL_RenderPresent(renderer)

  SDL_DestroyRenderer(renderer)
  SDL_DestroyWindow(window)
  SDL_Quit()

main()
