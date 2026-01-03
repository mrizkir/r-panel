#!/bin/bash

case "$1" in
    start)
        echo "Starting R-Panel development environment..."
        docker-compose up -d
        echo ""
        echo "R-Panel running on http://localhost:8081"
        echo "MySQL running on localhost:3306"
        echo ""
        echo "View logs: docker-compose logs -f"
        echo "Or use: ./scripts/dev.sh logs"
        ;;
    stop)
        echo "Stopping R-Panel development environment..."
        docker-compose down
        ;;
    restart)
        echo "Restarting R-Panel..."
        docker-compose restart r-panel
        ;;
    logs)
        docker-compose logs -f r-panel
        ;;
    build)
        echo "Building R-Panel development image..."
        docker-compose build
        ;;
    shell)
        docker-compose exec r-panel sh
        ;;
    rebuild)
        echo "Rebuilding R-Panel..."
        docker-compose build --no-cache r-panel
        docker-compose up -d
        ;;
    mysql)
        echo "Connecting to MySQL..."
        docker-compose exec mysql mysql -urpanel -prpanel rpanel
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|build|shell|rebuild|mysql}"
        echo ""
        echo "Commands:"
        echo "  start    - Start development environment"
        echo "  stop     - Stop development environment"
        echo "  restart  - Restart R-Panel container"
        echo "  logs     - View R-Panel logs"
        echo "  build    - Build Docker image"
        echo "  shell    - Open shell in container"
        echo "  rebuild  - Rebuild image and restart"
        echo "  mysql    - Connect to MySQL database"
        exit 1
        ;;
esac

