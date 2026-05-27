import { defineConfig } from "vite";
import elm from "vite-plugin-elm";
import electron from "vite-plugin-electron/simple";

export default defineConfig({
  base: "./",
  plugins: [
    elm({ debug: false }),
    electron({
      main: {
        entry: "electron/main.js",
        vite: {
          build: {
            outDir: "dist-electron",
            commonjsOptions: {
              include: [/node_modules/, /electron\//],
            },
            rollupOptions: {
              external: ["electron", "electron-updater", "chokidar"],
            },
          },
        },
      },
      preload: {
        input: "electron/preload.js",
        vite: {
          build: {
            outDir: "dist-electron",
            rollupOptions: {
              external: ["electron"],
            },
          },
        },
      },
    }),
  ],
  server: {
    port: 5173,
  },
  build: {
    outDir: "dist",
    minify: "esbuild",
    esbuild: {
      pure: ["F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9"],
    },
  },
});
