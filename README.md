# pingd

 pingd is a small, self-hosted push notification service. It lets you send notifications to your phone or desktop from any script, app, or service you run, with user accounts, fine-grained permissions, and automatic retries on transient delivery failures. Free software, runs in one Docker container.

```bash
curl -s https://pingd.example.com/topics/deploy.prod/messages \
  -H "Content-Type: application/json" \
  -d '{ "payload": { "body": "Deploy finished" } }'
```

That's it.

## What's good about it

- **NATS-style permissions**: `ro`, `wo`, `rw`, `deny` on topic-name patterns, per user or globally. Wildcards work.
- **Per-topic webhook templates**: rewrite incoming JSON with `{{path.to.field}}` before it becomes a push. No glue script in between.
- **Per-delivery tracking**: every push to every device is its own row with status, retry count, and timestamps. When something doesn't arrive you can find out why.
- **Share tokens for topics**: hand out scoped read/write/rw access to one topic without creating a user. Rotate or revoke on its own.
- **Per-device controls**: list devices, mute one, see exactly which device got which message.
- **Free, self-hostable, boring on purpose**: one Docker container, one SQLite file, your data.

## Quick start

```bash
docker run -d \
  --name pingd \
  -p 7685:7685 \
  -e ADMIN_USERNAME=admin \
  -e ADMIN_PASSWORD=change-me \
  -e PINGD_DATA_DIR=/data \
  -v "$PWD/pingd-data:/data" \
  ghcr.io/saeid/pingd:latest
```

Open `http://localhost:7685`, log in, create a topic, publish a message, watch it arrive.

## Docs

Full guides, API reference, and the FAQ live at [pingd.dev/docs](https://pingd.dev/docs).

## What's next

I'm actively working on pingd and have a list of things I want to add (an iOS App Store release, an Android client, a managed instance at pingd.dev). Ideas, bug reports, and PRs are all very welcome, this is the kind of project that gets better the more people poke at it.

## Contributing

Bug reports, feature ideas, PRs all welcome. For anything beyond a small fix, open an issue first so we can talk through the shape.

Build and test (needs Swift 6.0+, runs on macOS 13+ and Linux):

```bash
swift build
swift test
```

The codebase is hand-written and that's part of why working on it is fun. AI-assisted PRs are absolutely welcome, just mention it in the description so reviewers have the context.

## License

Apache 2.0. See [LICENSE](LICENSE).
