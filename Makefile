.PHONY: dev-start dev-stop dev-logs dev-build dev-shell dev-rebuild dev-mysql frontend-build dev clean

# Development commands
dev-start:
	@./scripts/dev.sh start

dev-stop:
	@./scripts/dev.sh stop

dev-logs:
	@./scripts/dev.sh logs

dev-build:
	@./scripts/dev.sh build

dev-shell:
	@./scripts/dev.sh shell

dev-rebuild:
	@./scripts/dev.sh rebuild

dev-mysql:
	@./scripts/dev.sh mysql

# Build frontend (run once, atau saat frontend berubah)
frontend-build:
	@echo "Building frontend..."
	@cd frontend && yarn install && yarn build
	@echo "Frontend built to backend/web/dist"

# Quick start - build frontend + start docker
dev: frontend-build dev-start
	@echo ""
	@echo "=========================================="
	@echo "Development environment ready!"
	@echo "=========================================="
	@echo "R-Panel: http://localhost:8081"
	@echo "MySQL:   localhost:3306"
	@echo ""
	@echo "View logs: make dev-logs"
	@echo "Stop:     make dev-stop"

# Clean up Docker resources
clean:
	@echo "Cleaning up Docker resources..."
	@docker-compose down -v
	@echo "Done!"

