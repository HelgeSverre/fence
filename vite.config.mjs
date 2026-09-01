import { defineConfig } from "vite";
import elm from "vite-plugin-elm";
import electron from "vite-plugin-electron/simple";

export default defineConfig({
  base: "./",
  plugins: [
    elm({ debug: false }),
    {
      // vite-plugin-elm's HMR wrapper uses eval(); allow it in dev only so
      // the production CSP in index.html stays strict.
      name: "dev-csp-unsafe-eval",
      apply: "serve",
      transformIndexHtml: (html) => html.replace("script-src 'self';", "script-src 'self' 'unsafe-eval';"),
    },
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
