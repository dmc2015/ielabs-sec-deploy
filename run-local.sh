#!/usr/bin/env bash
docker run --rm --add-host=host.docker.internal:host-gateway -e SECRET_KEY_BASE=$(openssl rand -hex 64) -e DATABASE_URL="postgres://postgres:postgres@host.docker.internal:5432/ielabs_development" -e REDIS_URL="redis://host.docker.internal:6379/0" -e SEED_USER_PASSWORD="dev_password" -p 3000:3000 ielabs:test
