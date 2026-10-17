# Run your own sync server

The sync server is small and open source: [aikatsu-sync](https://github.com/KidiXDev/aikatsu-sync). Run it on a home server, a NAS, or a VPS, and your history never leaves machines you control. All you need is Docker.

## Start it

Pick SQLite unless you already run Postgres. SQLite keeps everything in one file and needs nothing else.

### With SQLite

```sh
mkdir aikatsu-sync && cd aikatsu-sync
curl -O https://raw.githubusercontent.com/KidiXDev/aikatsu-sync/main/compose.yaml
docker compose up -d
```

### With Postgres

```sh
mkdir aikatsu-sync && cd aikatsu-sync
curl -O https://raw.githubusercontent.com/KidiXDev/aikatsu-sync/main/compose.postgres.yaml
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)" > .env
docker compose -f compose.postgres.yaml up -d
```

For the Postgres setup, add `-f compose.postgres.yaml` to every `docker compose` command on this page.

Either way, the server listens on port 3000. Check it with `curl http://localhost:3000/health`.

## Connect the app

In Aikatsu, open **Settings > Sync** (**Settings > Account** on desktop), choose **Change** next to the server, and enter your server's address, such as `http://192.168.1.20:3000`. Then choose **Create account** and pick a username and password.

On your other devices, set the same server, then choose **Sign in** with the same username and password.

If you're already signed in to Aikatsu's server, sign out first. You can only change the server while signed out.

If the server is just for you, close sign-ups once your account exists:

1. Set `ALLOW_REGISTRATION: "false"` in the compose file.
2. Run `docker compose up -d`.

## Reach it from outside your home

Put the server behind a reverse proxy with HTTPS, so your password never travels unencrypted. With [Caddy](https://caddyserver.com) on the same machine, this is the whole Caddyfile:

```
sync.example.com {
    reverse_proxy localhost:3000
}
```

Then change the compose file:

1. Set `TRUST_PROXY: "true"`. Without it, the server sees every visitor as the proxy, so one person's wrong passwords could lock everyone out.
2. Change the port line to `"127.0.0.1:3000:3000"`, so plain HTTP isn't exposed directly.

In the app, use `https://sync.example.com` as the server.

## Settings

Set these under `environment:` in the compose file, then run `docker compose up -d`.

| Variable | Default | What it does |
| --- | --- | --- |
| `ALLOW_REGISTRATION` | `true` | Whether anyone can create an account |
| `TRUST_PROXY` | `false` | Set `true` behind a reverse proxy |
| `MAX_RECORDS_PER_USER` | `100000` | Caps each account. One watched episode or one setting is one record |
| `DATABASE_URL` | SQLite in the `data` volume | `sqlite://<path>` or `postgres://user:pass@host:5432/db` |
| `PORT` | `3000` | The port inside the container |

## Look after it

**Reset a forgotten password.** This prints a new password and signs that account out everywhere:

```sh
docker compose exec sync bun src/cli.ts reset-password <username>
```

**Update:**

```sh
docker compose pull && docker compose up -d
```

**Back up:**
- **SQLite:** run `docker compose stop`, copy the `data` volume, then run `docker compose start`.
- **Postgres:** use `pg_dump`.

Your devices also keep their own copy of your history, so a lost server can be rebuilt. Start a new one and sign in again, and the history uploads from your devices.

## What the server stores

For each account, the server keeps:
- the username;
- a hashed password;
- one entry per signed-in device;
- the history and [settings that sync](./sync.md#what-syncs).

It doesn't log requests.

Sign-ups, wrong passwords, and request rates are rate-limited.
