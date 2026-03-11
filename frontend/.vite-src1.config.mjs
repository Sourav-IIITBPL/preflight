import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    {
      name: 'use-src1-entry',
      transformIndexHtml(html) {
        return html.replace('/src/main.jsx', '/src1/main.jsx');
      },
    },
  ],
});
