# Fresh Pantry API

Cloudflare Worker for Fresh Pantry health checks and household invite links.

Routes:

- `GET /health`
- `GET /invite/:token`

Validation:

```bash
npm test
```

Deployment:

```bash
npx wrangler deploy
```

Production route: `api.freshpantry.sunpebblelabs.com`.
