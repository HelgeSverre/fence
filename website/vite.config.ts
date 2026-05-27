import { defineConfig } from 'vite';
import analog from '@analogjs/platform';

export default defineConfig({
  publicDir: 'src/public',
  build: {
    target: ['es2020'],
  },
  plugins: [
    analog({
      static: true,
      prerender: {
        routes: ['/', '/features', '/download', '/docs', '/about', '/changelog'],
      },
    }),
  ],
});
