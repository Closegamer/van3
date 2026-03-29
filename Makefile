# На сервере с Docker (Linux): make up-down / logs
COMPOSE ?= docker compose --env-file .env.docker

.PHONY: up down logs psql status

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f postgres

status:
	$(COMPOSE) ps

psql:
	$(COMPOSE) exec postgres psql -U vanuser -d vandb
