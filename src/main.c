/* Platform/input scaffold. Optional host-generated MUL preview; no simulation. */
#include <SDL.h>
#include <stdio.h>
#include <string.h>
#ifdef ULTIMAXB_XBOX
#include <hal/video.h>
#endif

static void diamond(SDL_Renderer *renderer, int x, int y, int alternate)
{
    SDL_SetRenderDrawColor(renderer, alternate ? 67 : 55,
                         alternate ? 96 : 82, alternate ? 65 : 54, 255);
    for (int row = 0; row < 22; ++row) {
        int half = row < 11 ? row * 2 : (21 - row) * 2;
        SDL_RenderDrawLine(renderer, x - half, y + row, x + half, y + row);
    }
    SDL_SetRenderDrawColor(renderer, 38, 55, 42, 255);
    SDL_RenderDrawLine(renderer, x, y, x + 22, y + 11);
    SDL_RenderDrawLine(renderer, x + 22, y + 11, x, y + 22);
}

static float axis(Sint16 value)
{
    if (value > -8000 && value < 8000) return 0.0f;
    return value / 32768.0f;
}

int main(int argc, char **argv)
{
    int smoke = 0;
    const char *preview_path = NULL;
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--smoke") == 0) smoke = 1;
        else if (strcmp(argv[i], "--preview") == 0 && i + 1 < argc)
            preview_path = argv[++i];
        else {
            fprintf(stderr, "Usage: %s [--smoke] [--preview image.bmp]\n", argv[0]);
            return 2;
        }
    }
#ifdef ULTIMAXB_XBOX
    XVideoSetMode(640, 480, 32, REFRESH_DEFAULT);
#endif
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_TIMER) < 0) {
        fprintf(stderr, "SDL initialization: %s\n", SDL_GetError());
        return 1;
    }
    SDL_Window *window = SDL_CreateWindow(preview_path ?
        "UltimaXB | offline MUL preview | arrows / left stick" :
        "UltimaXB | procedural prototype | arrows / left stick",
        SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 640, 480, 0);
    SDL_Renderer *renderer = window ? SDL_CreateRenderer(window, -1, 0) : NULL;
    if (!renderer) {
        fprintf(stderr, "SDL renderer: %s\n", SDL_GetError());
        if (window) SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }
    SDL_RenderSetLogicalSize(renderer, 640, 480);
    SDL_Texture *preview = NULL;
    int preview_w = 0, preview_h = 0;
    if (preview_path) {
        SDL_Surface *surface = SDL_LoadBMP(preview_path);
        if (surface) {
            preview_w = surface->w;
            preview_h = surface->h;
            preview = SDL_CreateTextureFromSurface(renderer, surface);
            SDL_FreeSurface(surface);
        }
        if (!preview) {
            fprintf(stderr, "Preview load: %s\n", SDL_GetError());
            SDL_DestroyRenderer(renderer);
            SDL_DestroyWindow(window);
            SDL_Quit();
            return 1;
        }
    }
    SDL_GameController *pad = NULL;
    for (int i = 0; i < SDL_NumJoysticks() && !pad; ++i)
        if (SDL_IsGameController(i)) pad = SDL_GameControllerOpen(i);
    int running = 1, frames = 0;
    float camera_x = 0, camera_y = 0;
    Uint32 previous = SDL_GetTicks();
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT ||
                (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE))
                running = 0;
            if (event.type == SDL_CONTROLLERDEVICEADDED && !pad)
                pad = SDL_GameControllerOpen(event.cdevice.which);
            if (event.type == SDL_CONTROLLERDEVICEREMOVED && pad &&
                SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(pad)) == event.cdevice.which) {
                SDL_GameControllerClose(pad);
                pad = NULL;
            }
        }
        Uint32 now = SDL_GetTicks();
        float dt = (now - previous) / 1000.0f;
        previous = now;
        if (dt > 0.1f) dt = 0.1f;
        const Uint8 *keys = SDL_GetKeyboardState(NULL);
        float dx = keys[SDL_SCANCODE_RIGHT] - keys[SDL_SCANCODE_LEFT];
        float dy = keys[SDL_SCANCODE_DOWN] - keys[SDL_SCANCODE_UP];
        if (pad) {
            dx += axis(SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTX));
            dy += axis(SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTY));
        }
        camera_x += dx * dt * 150;
        camera_y += dy * dt * 150;
        if (camera_x < -300) camera_x = -300;
        if (camera_x > 300) camera_x = 300;
        if (camera_y < -200) camera_y = -200;
        if (camera_y > 200) camera_y = 200;
        SDL_SetRenderDrawColor(renderer, 16, 22, 27, 255);
        SDL_RenderClear(renderer);
        if (preview) {
            SDL_Rect destination = {(640 - preview_w) / 2 - (int)camera_x,
                (480 - preview_h) / 2 - (int)camera_y, preview_w, preview_h};
            SDL_RenderCopy(renderer, preview, NULL, &destination);
        } else for (int sum = 0; sum <= 30; ++sum) {
            for (int x = 0; x < 16; ++x) {
                int y = sum - x;
                if (y < 0 || y >= 16) continue;
                diamond(renderer, 320 + (x - y) * 22 - (int)camera_x,
                        60 + (x + y) * 11 - (int)camera_y, (x + y) & 1);
            }
        }
        SDL_SetRenderDrawColor(renderer, 220, 195, 125, 255);
        SDL_RenderDrawLine(renderer, 313, 240, 327, 240);
        SDL_RenderDrawLine(renderer, 320, 233, 320, 247);
        SDL_RenderPresent(renderer);
        if (smoke && ++frames == 3) running = 0;
        SDL_Delay(16);
    }
    if (pad) SDL_GameControllerClose(pad);
    if (preview) SDL_DestroyTexture(preview);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    if (smoke) puts(preview_path ? "Rendered three offline preview frames successfully." :
        "Rendered three procedural frames successfully (no UO assets loaded).");
    return 0;
}
