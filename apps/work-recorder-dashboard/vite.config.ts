import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";

export default defineConfig({
  plugins: [react()],
  base: "./",
  build: {
    assetsDir: "assets",
    sourcemap: false,
    rollupOptions: {
      input: {
        dashboard: path.resolve(__dirname, "index.html"),
        sitePreview: path.resolve(__dirname, "site-preview.html")
      }
    }
  }
});
