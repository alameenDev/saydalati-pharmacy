const { createServer } = require('node:http');
const next = require('next');
const port = Number(process.env.PORT || 3000);
const hostname = '0.0.0.0';
const app = next({ dev: false, hostname, port });
const handle = app.getRequestHandler();
app.prepare().then(() => {
  const server = createServer((req, res) => handle(req, res));
  server.listen(port, hostname, () => console.log(`Saydalati ready on port ${port}`));
  process.on('SIGTERM', () => server.close(() => process.exit(0)));
}).catch((err) => { console.error('Failed to start Saydalati:', err.message); process.exit(1); });
