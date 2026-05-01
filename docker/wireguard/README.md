# WireGuard gateway

The `wg` service in `docker-compose.yml` is a WireGuard VPN gateway that
provides the only ingress path to the Prime Service stack.

## How it works

* On first `docker compose up`, the container generates server keys and
  `WG_PEERS` peer configs under `./wireguard/config/peer1/peer1.conf`,
  `peer2/peer2.conf`, etc., each accompanied by a QR code PNG.
* Peers connect over UDP/51820 (the only port published to the host).
* The peer's tunnel is routed to `172.28.0.0/24` (the Compose internal
  bridge network), so peers can reach `http://172.28.0.20:8080` — the
  FastAPI service.
* The PostgreSQL container at `172.28.0.10` is reachable from the API
  container, but firewalled at the docker network level from peers via
  the `ALLOWEDIPS` list (peers are only routed to the api IP if you
  tighten the AllowedIPs in their generated config; see below).

## Distribute peer configs

```bash
# Show the QR for peer1 (for a phone client)
docker exec prime_wg /app/show-peer 1

# Or hand off the file
cat ./wireguard/config/peer1/peer1.conf
```

## Hardening checklist

1. Restrict `AllowedIPs` on each peer config to only the IPs they
   need (e.g., `172.28.0.20/32` to permit API access only).
2. Rotate peer keys periodically.
3. Replace `WG_SERVER_URL=auto` with a stable DNS name in production.
4. Consider running this gateway behind a hostname guarded by Cloudflare
   /AWS WAF rate-limiting at the UDP edge if exposed publicly.

## Production note

For the cloud deployment (Task 3) the local WireGuard gateway is
**replaced by AWS Client VPN**, which is mutual-TLS based and integrates
with AWS IAM via SAML. See `terraform/modules/client_vpn/`.
