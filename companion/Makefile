FLUTTER ?= fvm flutter
DART ?= fvm dart

.PHONY: help get format lint test check apk run

help: ## Lista os comandos
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "%-10s %s\n", $$1, $$2}'

get: ## Baixa as dependências
	$(FLUTTER) pub get

format: ## Formata o código (linhas de 80 colunas)
	$(DART) format --line-length 80 lib test

lint: ## Roda o analisador
	$(FLUTTER) analyze

test: ## Roda os testes
	$(FLUTTER) test

check: format lint test ## Formata, analisa e testa

apk: ## Gera o APK de release (Android)
	$(FLUTTER) build apk --release

run: ## Roda no aparelho conectado
	$(FLUTTER) run
