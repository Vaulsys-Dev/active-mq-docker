# BNMB provisioning broker (ActiveMQ Artemis)

The broker that carries provisioning events (`USER_CREATED`, `USER_DEACTIVATED`, `SMS`,
`EMAIL`) from backoffice into this gateway. Everything the broker needs is in this
directory, so it can be rebuilt identically on any machine instead of being hand-patched
inside a running container.

```
docker/
  Dockerfile           image = stock Artemis + our config + TLS keystore
  docker-compose.yml   how to run it
  config/broker.xml    acceptors, queues, address-settings
  certs/broker.p12     TLS keystore - NOT in git, you place it (see below)
```

## Before the first build: place the keystore

`docker/certs/broker.p12` is gitignored, because it holds the broker's private key.
Copy the one that was generated for this environment:

```bash
cp /d/abdul_khaliq/projects/BNMB/certs/broker.p12 docker/certs/broker.p12
```

If you need a new one (expiry, new host, different SAN):

```bash
keytool -genkeypair -alias broker -keyalg RSA -keysize 2048 -validity 825 \
  -storetype PKCS12 -keystore broker.p12 \
  -dname "CN=bnmb-artemis, OU=IT, O=BNMB, L=Khartoum, C=SD" \
  -ext "SAN=IP:192.168.100.142,IP:127.0.0.1,DNS:localhost,DNS:artemis" \
  -storepass '<password>'

# clients need the certificate, not the key
keytool -exportcert -rfc -alias broker -keystore broker.p12 -storepass '<password>' -file artemis.crt
keytool -importcert -noprompt -alias broker -file artemis.crt \
  -keystore client-truststore.p12 -storetype PKCS12 -storepass '<password>'
```

The SAN list matters: a client verifying the hostname rejects the certificate if the
address it dialled is not in there.

## Run it

Secrets come from `.env`, which Compose loads automatically from this directory:

```properties
BROKER_TLS_PASSWORD=<keystore password>   # used by the healthcheck
ARTEMIS_USER=admin
ARTEMIS_PASSWORD=admin
```

`.env` is gitignored. Without `BROKER_TLS_PASSWORD` set, Compose substitutes a blank
string and the healthcheck fails (the broker itself still starts - it just never reports
healthy).

```bash
docker compose up -d --build
docker compose logs -f
```

Healthy startup ends with:

```
AMQ221020: Started EPOLL Acceptor at 0.0.0.0:61617 for protocols [CORE]
AMQ221007: Server is now active
```

| Port | What |
|------|------|
| 61617 | CORE over TLS - the only messaging port |
| 8161  | web console, `http://localhost:8161/console` |

## Connecting the gateway

```properties
ARTEMIS_URL=tcp://<broker-host>:61617?sslEnabled=true;trustStorePath=/path/to/client-truststore.p12;trustStorePassword=<password>;trustStoreType=PKCS12
ARTEMIS_USER=admin
ARTEMIS_PASSWORD=<password>
```

The client needs `client-truststore.p12`, never `broker.p12` — that one contains the
private key and must not leave the broker host.

## Design notes

Three things here are easy to get wrong, and all three have bitten this setup already.

**Config goes in `etc-override/`, not `etc/`.** The image entrypoint is:

```bash
if ! [ -f ./etc/broker.xml ]; then
    artemis create ...                 # also generates ./bin/artemis
    cp ./etc-override/* ./etc
fi
exec ./bin/artemis run
```

Writing `broker.xml` directly into `etc/` makes it skip instance creation, so `bin/artemis`
is never generated and the container exits immediately. `etc-override/` is the supported
hook: the instance is created first, then our files are copied over the generated ones.

**Mount `data/`, never the instance root.** `/var/lib/artemis-instance` is a declared
`VOLUME` in the base image, so a volume mounted there shadows everything baked into the
image at that path — `broker.xml` and `broker.p12` would silently revert to stock and the
broker would come up on plaintext 61616 with no queues. Mounting only
`/var/lib/artemis-instance/data` keeps the split honest: **config is code** (change it here
and rebuild), **data is state** (messages and journal survive in the volume).

The Dockerfile also seeds `data/.keep` owned by `artemis`. Without it Docker creates that
mount point root-owned, the broker cannot write `data/server.lock`, and it dies with
`java.io.IOException: No such file or directory ... setUpServerLockFile`.

**Ubuntu base, not Alpine.** `broker.xml` sets `<journal-type>ASYNCIO</journal-type>`,
which needs `libaio` — a glibc library. On musl Artemis silently falls back to the NIO
journal, which is slower for exactly the write-heavy workload a broker has.

## Secrets

The keystore password in `broker.xml` is masked, not plaintext:

```
keyStorePassword=ENC(-35da6099f7543734b442d3b2e1759aeddd05b6572705eea3)
```

Regenerate after a password change:

```bash
docker compose exec artemis ./bin/artemis mask '<new password>'
```

This is obfuscation, not encryption — it keeps the password out of plain sight in a file
that ships inside an image anyone who can pull it can extract. It is not a substitute for
controlling who can pull the image.

Broker credentials come from the environment (`ARTEMIS_USER` / `ARTEMIS_PASSWORD`) and are
written into `etc/artemis-users.properties` when the instance is created. The `admin/admin`
default in `docker-compose.yml` is a laptop convenience — override it anywhere else.

## Queue topology

Defined in `config/broker.xml`:

| Address | Purpose |
|---------|---------|
| `BNMB.GATEWAY.PROVISIONING` | provisioning events, ANYCAST (competing consumers) |
| `DLQ.BNMB.GATEWAY.PROVISIONING` | its dead-letter queue |
| `DLQ`, `ExpiryQueue` | broker defaults |

`max-delivery-attempts` is 3 — deliberately low. A redelivery can re-send a real, billable
SMS, so a poison message should dead-letter quickly rather than loop. `address-full-policy`
is `PAGE`, so a backlog spills to disk instead of blocking producers or exhausting broker
memory.

To add a second queue (splitting notifications off provisioning, say), add the address and
its `address-setting` here and rebuild. Both the gateway and the producer already read
their destination from config, so no code change is needed.
