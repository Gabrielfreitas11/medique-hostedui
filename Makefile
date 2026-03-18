# medique-hostedui — Atalhos para comandos comuns
# Uso: make <comando>
#
# Exemplos:
#   make dev          → sobe em desenvolvimento (localhost:3000)
#   make prod         → sobe em produção (Nginx + PostgreSQL)
#   make down         → para todos os containers
#   make logs         → mostra logs do Open WebUI
#   make restart      → reinicia todos os containers (prod)
#   make backup       → executa backup
#   make status       → mostra status dos containers

PROD = -f docker-compose.yml -f docker-compose.prod.yml

# --- Desenvolvimento ---

dev: ## Sobe em desenvolvimento (localhost:3000)
	docker compose up -d

dev-logs: ## Logs do Open WebUI (dev)
	docker compose logs -f open-webui

# --- Produção ---

prod: ## Sobe em produção (Nginx + PostgreSQL + Open WebUI)
	docker compose $(PROD) up -d

restart: ## Reinicia todos os containers (prod)
	docker compose $(PROD) restart

restart-nginx: ## Reinicia só o Nginx
	docker compose $(PROD) restart nginx

restart-webui: ## Reinicia só o Open WebUI
	docker compose $(PROD) restart open-webui

# --- Comum (dev e prod) ---

down: ## Para todos os containers
	docker compose $(PROD) down

status: ## Mostra status dos containers
	docker compose $(PROD) ps

logs: ## Logs do Open WebUI (prod)
	docker compose $(PROD) logs -f open-webui --tail 50

logs-nginx: ## Logs do Nginx
	docker compose $(PROD) logs -f nginx --tail 50

logs-all: ## Logs de todos os containers
	docker compose $(PROD) logs -f --tail 50

health: ## Verifica se o Open WebUI está respondendo
	docker exec medique-nginx curl -s http://open-webui:8080/health

# --- Operações ---

backup: ## Executa backup
	./scripts/backup.sh

setup: ## Setup inicial (valida .env e sobe dev)
	./scripts/setup.sh

secrets: ## Verifica status dos secrets
	./scripts/rotate-secrets.sh check

# --- Ajuda ---

help: ## Mostra esta ajuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: dev dev-logs prod restart restart-nginx restart-webui down status logs logs-nginx logs-all health backup setup secrets help
.DEFAULT_GOAL := help
