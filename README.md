# BNMB Provisioning Broker — ActiveMQ Artemis

## Setup and Deployment Guide

### 1. Clone the Repository

Clone the repository and navigate to the project directory:

```bash
git clone <repository-url>
cd <project-directory>
```

### 2. Configure the TLS Certificate

* Copy the client-provided `.p12` certificate into the `certs/` folder.
* Ensure that the certificate password is available.
* The certificate must be valid and approved for the intended environment.

In the `config/` folder, open `broker.xml` and verify the TLS acceptor configuration:

```xml
<acceptor name="artemis-ssl">tcp://0.0.0.0:61617?sslEnabled=true;keyStorePath=${artemis.instance}/etc/broker.p12;keyStorePassword=ENC(-35da6099f7543734b442d3b2e1759aeddd05b6572705eea3);keyStoreType=PKCS12;enabledProtocols=TLSv1.3,TLSv1.2;protocols=CORE;tcpSendBufferSize=1048576;tcpReceiveBufferSize=1048576;useEpoll=true</acceptor>
```

This configuration enables TLS-secured connections on port `61617`.

### 3. Create the `.env` File

Create a `.env` file in the project directory and configure the following properties:

```properties
BROKER_TLS_PASSWORD=<keystore-password>
ARTEMIS_USER=<username>
ARTEMIS_PASSWORD=<password>
```

### 4. Build and Run the Container

The Docker image configuration is available in the `Dockerfile`.

Run the following commands:

```bash
docker compose up -d --build
docker compose logs -f
```

The broker will be available at:

```text
tcp://192.168.100.142:61617
```

The Artemis Web Console can be accessed at:

```text
http://localhost:8161/console
```

### 5. Consumer Configuration

Any service connecting to the broker must configure the following properties:

```properties
ARTEMIS_URL=tcp://<broker-host>:61617?sslEnabled=true;trustStorePath=/path/to/client-truststore.p12;trustStorePassword=<password>;trustStoreType=PKCS12
ARTEMIS_USER=<user>
ARTEMIS_PASSWORD=<password>
```

### 6. View Queue Statistics

Queue statistics can be viewed through the Web Console or by running the following command inside the container:

```bash
docker exec bnmb-artemis bash -c 'bin/artemis queue stat \
    --url "tcp://<broker-host>:61617?sslEnabled=true;trustStorePath=/var/lib/artemis-instance/etc/broker.p12;trustStorePassword=<TLS_PASSWORD>;trustStoreType=PKCS12" \
    --user admin \
    --password <ARTEMIS_PASSWORD>'
```

Replace the placeholders with the appropriate broker host, TLS password, and Artemis credentials.
