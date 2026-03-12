import { defineConfig } from "vite";
import elm from "vite-plugin-elm";

export default defineConfig({
  base: "./",
  plugins: [elm({ debug: false })],
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
