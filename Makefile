NAME        = inception
LOGIN       = moham
COMPOSE     = srcs/docker-compose.yml
DATA_PATH   = /home/$(LOGIN)/data

all: setup up

# Create the host directories that will back the named volumes.
# (Docker will also create them itself, but doing it here lets us
# fix ownership/permissions ahead of time if needed.)
setup:
	@mkdir -p $(DATA_PATH)/wordpress
	@mkdir -p $(DATA_PATH)/mariadb
	@echo "Data directories ready at $(DATA_PATH)"

build:
	@docker compose -f $(COMPOSE) build

up: setup
	@docker compose -f $(COMPOSE) up -d --build

down:
	@docker compose -f $(COMPOSE) down

start:
	@docker compose -f $(COMPOSE) start

stop:
	@docker compose -f $(COMPOSE) stop

restart: down up

logs:
	@docker compose -f $(COMPOSE) logs -f

ps:
	@docker compose -f $(COMPOSE) ps

# Remove containers/images/network but keep the data volumes.
clean: down
	@docker system prune -af

# Full wipe: containers, images, network AND the persisted data on the host.
# Use with caution.
fclean: clean
	@sudo rm -rf $(DATA_PATH)
	@docker volume rm srcs_wordpress_data srcs_mariadb_data 2>/dev/null || true

re: fclean all

.PHONY: all setup build up down start stop restart logs ps clean fclean re
