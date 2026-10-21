// Tiny static server for previewing the built window in a browser (node windows/scripts-preview.cjs).
const http = require('http'), fs = require('fs'), path = require('path')
const root = path.join(__dirname, 'out', 'renderer')
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff', '.png': 'image/png', '.svg': 'image/svg+xml' }
http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname))
  const file = fs.existsSync(p) && fs.statSync(p).isFile() ? p : path.join(root, 'index.html')
  res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' })
  fs.createReadStream(file).pipe(res)
}).listen(Number(process.env.PORT) || 5193, '127.0.0.1', () => console.log('preview ready'))
