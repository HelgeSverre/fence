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
  },
});
