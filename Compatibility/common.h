/* Shared constants for the shim DLL and the injector EXE.
 *
 * Both files must agree on these names: the injector finds the game by
 * window class and loads the DLL by file name, and the shim subclasses that
 * same window. A rename must touch exactly this file.
 */
#ifndef COMPATIBILITY_COMMON_H
#define COMPATIBILITY_COMMON_H

#define GAME_WINDOW_CLASS    "GxWindowClassD3d"  /* the client's top-level window class */
#define COMPAT_DLL_NAME      "compatibility.dll" /* file name the injector loads */

#endif /* COMPATIBILITY_COMMON_H */
