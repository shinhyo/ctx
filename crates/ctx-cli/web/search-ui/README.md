# ctx search web UI

Static React UI for `ctx search --web`.

The CLI serves the production `dist/` directory from a loopback-only, token-gated
Rust server. Rebuild the embedded assets after changing this package:

```bash
pnpm build
cargo build -p ctx
```

The UI uses shadcn/ui components, TanStack Table, Tailwind, and Vite. Keep
assets local; do not add CDN-hosted fonts, scripts, styles, or telemetry.
