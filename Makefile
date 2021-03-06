.PHONY: all clean server

HUGO := ./hugo
HUGO_RELEASE := https://github.com/joaohf/hugo/releases/download/0.61.0-diminish/hugo

# Below are PHONY targets
all: server

fetch:
	wget -qN $(HUGO_RELEASE) && chmod 755 ./hugo

clean:
	-rm -rf public

server: clean
	$(HUGO) server -D -F
