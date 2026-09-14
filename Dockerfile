FROM apache/activemq-artemis:2.44.0

COPY --chown=artemis:artemis certs/broker.p12 /var/lib/artemis-instance/etc-override/broker.p12
COPY --chown=artemis:artemis config/broker.xml /var/lib/artemis-instance/etc-override/broker.xml
COPY --chown=artemis:artemis .keep /var/lib/artemis-instance/data/.keep

# 61617 = CORE over TLS (the only messaging port), 8161 = web console.
EXPOSE 61617 8161
